-- =============================================================================
-- NBRPTS — Triggers, business RPCs, and observatory helpers
-- =============================================================================


-- ----- 0001_dev_ping_rpc.sql -------------------------------------------------

-- Phase 1: a self-contained tracked query the /dev observatory can fire.
-- Runs `select now()`, captures wall-clock duration, captures the EXPLAIN
-- (FORMAT JSON) plan, and writes a query_log row that streams to clients
-- via Realtime.

create or replace function public.dev_ping()
returns public.query_log
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start    timestamptz := clock_timestamp();
  v_now      timestamptz;
  v_duration numeric;
  v_plan_txt text;
  v_plan     jsonb;
  v_row      public.query_log;
begin
  -- the tracked query itself
  select now() into v_now;

  v_duration := extract(epoch from (clock_timestamp() - v_start)) * 1000;

  -- capture the EXPLAIN plan for the same query
  begin
    execute 'EXPLAIN (FORMAT JSON) SELECT now()' into v_plan_txt;
    v_plan := v_plan_txt::jsonb;
  exception when others then
    v_plan := jsonb_build_object('error', SQLERRM);
  end;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned, plan)
  values ('dev_ping', 'select now()', null, v_duration, 1, v_plan)
  returning * into v_row;

  return v_row;
end
$$;

grant execute on function public.dev_ping() to anon, authenticated;

comment on function public.dev_ping() is
  'Demo RPC for /dev observatory: runs `select now()`, captures duration + EXPLAIN plan, appends to query_log.';

-- ----- 0004_get_schema_rpc.sql -----------------------------------------------

-- Phase 2: schema-introspection RPC for the /dev/schema observatory.
-- Returns a single JSONB payload describing every table in the public schema:
--   * tables[] — name, comment, rls_enabled, row_count, column[]
--   * foreign_keys[] — from/to table+column pairs (used to render edges)
-- Tracked: writes a row to query_log.

create or replace function public.get_schema()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start    timestamptz := clock_timestamp();
  v_tables   jsonb;
  v_fks      jsonb;
  v_result   jsonb;
  v_duration numeric;
  v_rows     integer;
begin
  -- per-table summary including column metadata, primary key flags,
  -- unique constraints, comment, and rls status. row_count is read from
  -- pg_class.reltuples (planner estimate — fast, "good enough" for a UI).
  with cols as (
    select
      c.table_schema,
      c.table_name,
      c.column_name,
      c.ordinal_position,
      c.data_type,
      c.is_nullable = 'YES' as nullable,
      c.column_default
    from information_schema.columns c
    where c.table_schema = 'public'
  ),
  pks as (
    select kcu.table_schema, kcu.table_name, kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
      and tc.table_name      = kcu.table_name
    where tc.constraint_type = 'PRIMARY KEY'
      and tc.table_schema    = 'public'
  ),
  uqs as (
    select kcu.table_schema, kcu.table_name, kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
      and tc.table_name      = kcu.table_name
    where tc.constraint_type = 'UNIQUE'
      and tc.table_schema    = 'public'
  ),
  fks_per_col as (
    select
      kcu.table_schema   as from_schema,
      kcu.table_name     as from_table,
      kcu.column_name    as from_column,
      ccu.table_schema   as to_schema,
      ccu.table_name     as to_table,
      ccu.column_name    as to_column
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on  ccu.constraint_name = tc.constraint_name
      and ccu.table_schema    = tc.table_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema    = 'public'
  ),
  table_meta as (
    select
      t.table_name,
      coalesce(obj_description(format('public.%I', t.table_name)::regclass, 'pg_class'), '') as table_comment,
      c.relrowsecurity as rls_enabled,
      c.reltuples::bigint as row_count_estimate
    from information_schema.tables t
    join pg_class   c  on c.relname = t.table_name
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where t.table_schema = 'public'
      and t.table_type   = 'BASE TABLE'
  ),
  table_columns as (
    select
      cols.table_name,
      jsonb_agg(
        jsonb_build_object(
          'name',           cols.column_name,
          'type',           cols.data_type,
          'nullable',       cols.nullable,
          'default',        cols.column_default,
          'is_primary_key', exists (select 1 from pks p
                                     where p.table_name = cols.table_name
                                       and p.column_name = cols.column_name),
          'is_unique',      exists (select 1 from uqs u
                                     where u.table_name = cols.table_name
                                       and u.column_name = cols.column_name),
          'is_foreign_key', exists (select 1 from fks_per_col f
                                     where f.from_table = cols.table_name
                                       and f.from_column = cols.column_name),
          'references',     (
            select jsonb_build_object('table', f.to_table, 'column', f.to_column)
            from fks_per_col f
            where f.from_table = cols.table_name
              and f.from_column = cols.column_name
            limit 1
          )
        )
        order by cols.ordinal_position
      ) as columns
    from cols
    group by cols.table_name
  )
  select jsonb_agg(
    jsonb_build_object(
      'name',         tm.table_name,
      'comment',      tm.table_comment,
      'rls_enabled',  tm.rls_enabled,
      'row_count',    tm.row_count_estimate,
      'columns',      coalesce(tc.columns, '[]'::jsonb)
    )
    order by tm.table_name
  )
  into v_tables
  from table_meta tm
  left join table_columns tc on tc.table_name = tm.table_name;

  -- distinct foreign-key pairs for the ER-diagram edges
  select jsonb_agg(
    jsonb_build_object(
      'from_table',  from_table,
      'from_column', from_column,
      'to_table',    to_table,
      'to_column',   to_column
    )
  )
  into v_fks
  from (
    select distinct from_table, from_column, to_table, to_column
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on  ccu.constraint_name = tc.constraint_name
      and ccu.table_schema    = tc.table_schema
    cross join lateral (values
      (kcu.table_name, kcu.column_name, ccu.table_name, ccu.column_name)
    ) as v(from_table, from_column, to_table, to_column)
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema    = 'public'
  ) distinct_fks;

  v_result := jsonb_build_object(
    'tables',       coalesce(v_tables, '[]'::jsonb),
    'foreign_keys', coalesce(v_fks,    '[]'::jsonb),
    'generated_at', now()
  );

  v_rows := jsonb_array_length(coalesce(v_tables, '[]'::jsonb));
  v_duration := extract(epoch from (clock_timestamp() - v_start)) * 1000;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned, plan)
  values (
    'get_schema',
    'select table & fk metadata from information_schema',
    null,
    v_duration,
    v_rows,
    null
  );

  return v_result;
end
$$;

grant execute on function public.get_schema() to anon, authenticated;

comment on function public.get_schema() is
  'Returns the full public-schema metadata as JSONB. Powers the /dev/schema observatory.';

-- ----- 0006_harden_get_schema_row_count.sql ----------------------------------

-- Phase 2 hardening: clamp pg_class.reltuples at 0.
--
-- After bulk INSERTs without an explicit ANALYZE, reltuples can be -1
-- (Postgres uses negative values to mean "stats are stale, planner should
-- re-estimate"). The /dev/schema observatory was rendering "Seed rows -14".
-- greatest(..., 0) gives a sane lower bound for the UI.
--
-- This is a function replacement only; structure of the JSONB return is
-- unchanged.

create or replace function public.get_schema()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start    timestamptz := clock_timestamp();
  v_tables   jsonb;
  v_fks      jsonb;
  v_result   jsonb;
  v_duration numeric;
  v_rows     integer;
begin
  with cols as (
    select c.table_schema, c.table_name, c.column_name, c.ordinal_position,
           c.data_type, c.is_nullable = 'YES' as nullable, c.column_default
    from information_schema.columns c
    where c.table_schema = 'public'
  ),
  pks as (
    select kcu.table_schema, kcu.table_name, kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
      and tc.table_name      = kcu.table_name
    where tc.constraint_type = 'PRIMARY KEY' and tc.table_schema = 'public'
  ),
  uqs as (
    select kcu.table_schema, kcu.table_name, kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
      and tc.table_name      = kcu.table_name
    where tc.constraint_type = 'UNIQUE' and tc.table_schema = 'public'
  ),
  fks_per_col as (
    select kcu.table_schema as from_schema, kcu.table_name as from_table,
           kcu.column_name as from_column, ccu.table_schema as to_schema,
           ccu.table_name  as to_table,    ccu.column_name as to_column
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on  ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema
    where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
  ),
  table_meta as (
    select t.table_name,
           coalesce(obj_description(format('public.%I', t.table_name)::regclass, 'pg_class'), '') as table_comment,
           c.relrowsecurity as rls_enabled,
           greatest(c.reltuples::bigint, 0) as row_count_estimate
    from information_schema.tables t
    join pg_class    c on c.relname = t.table_name
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
  ),
  table_columns as (
    select cols.table_name,
      jsonb_agg(
        jsonb_build_object(
          'name',           cols.column_name,
          'type',           cols.data_type,
          'nullable',       cols.nullable,
          'default',        cols.column_default,
          'is_primary_key', exists (select 1 from pks p where p.table_name = cols.table_name and p.column_name = cols.column_name),
          'is_unique',      exists (select 1 from uqs u where u.table_name = cols.table_name and u.column_name = cols.column_name),
          'is_foreign_key', exists (select 1 from fks_per_col f where f.from_table = cols.table_name and f.from_column = cols.column_name),
          'references',     (select jsonb_build_object('table', f.to_table, 'column', f.to_column)
                             from fks_per_col f
                             where f.from_table = cols.table_name and f.from_column = cols.column_name limit 1)
        ) order by cols.ordinal_position
      ) as columns
    from cols group by cols.table_name
  )
  select jsonb_agg(
    jsonb_build_object(
      'name', tm.table_name,
      'comment', tm.table_comment,
      'rls_enabled', tm.rls_enabled,
      'row_count', tm.row_count_estimate,
      'columns', coalesce(tc.columns, '[]'::jsonb)
    ) order by tm.table_name
  )
  into v_tables
  from table_meta tm
  left join table_columns tc on tc.table_name = tm.table_name;

  select jsonb_agg(
    jsonb_build_object('from_table', from_table, 'from_column', from_column,
                       'to_table', to_table, 'to_column', to_column)
  )
  into v_fks
  from (
    select distinct kcu.table_name as from_table, kcu.column_name as from_column,
                    ccu.table_name as to_table,   ccu.column_name as to_column
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema
    where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
  ) distinct_fks;

  v_result := jsonb_build_object(
    'tables',       coalesce(v_tables, '[]'::jsonb),
    'foreign_keys', coalesce(v_fks,    '[]'::jsonb),
    'generated_at', now()
  );

  v_rows := jsonb_array_length(coalesce(v_tables, '[]'::jsonb));
  v_duration := extract(epoch from (clock_timestamp() - v_start)) * 1000;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned, plan)
  values ('get_schema', 'select table & fk metadata from information_schema',
          null, v_duration, v_rows, null);

  return v_result;
end
$$;

-- ----- 0008_audit_trigger.sql ------------------------------------------------

-- Phase 3: generic audit trigger.
--
-- Every meaningful table (12 of them) gets an AFTER INSERT/UPDATE/DELETE
-- trigger that writes a single row to public.audit_trail. The actor is
-- pulled from session-local config that the RPC layer sets:
--     perform set_config('app.actor_type', 'NADRA_OFFICER', true);
--     perform set_config('app.actor_id',   officer_id::text, true);
-- If unset (e.g. seed scripts), the trigger records SYSTEM/system.
--
-- Tables that are themselves logs (audit_trail, query_log) are intentionally
-- not audited to avoid recursion and noise.

create or replace function public.fn_audit_trail()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_type   actor_type_t;
  v_actor_id     text;
  v_pk_col       text;
  v_record_id    text;
  v_payload      jsonb;
  v_description  text;
begin
  -- Resolve actor from session vars set by the RPC layer.
  begin
    v_actor_type := nullif(current_setting('app.actor_type', true), '')::actor_type_t;
  exception when others then
    v_actor_type := null;
  end;
  v_actor_type := coalesce(v_actor_type, 'SYSTEM');
  v_actor_id   := coalesce(nullif(current_setting('app.actor_id', true), ''), 'system');

  -- Pick the right primary-key column for this table.
  v_pk_col := case TG_TABLE_NAME
    when 'child_guardian' then 'cg_id'
    else TG_TABLE_NAME || '_id'
  end;

  v_payload := case TG_OP when 'DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;
  v_record_id := v_payload->>v_pk_col;

  v_description := case TG_OP
    when 'INSERT' then format('Inserted into %s', TG_TABLE_NAME)
    when 'UPDATE' then format('Updated %s', TG_TABLE_NAME)
    when 'DELETE' then format('Deleted from %s', TG_TABLE_NAME)
  end;

  insert into public.audit_trail
    (actor_type, actor_id, action_type, table_affected, record_id, description)
  values
    (v_actor_type, v_actor_id, TG_OP, TG_TABLE_NAME, v_record_id, v_description);

  return coalesce(NEW, OLD);
end$$;

comment on function public.fn_audit_trail() is
  'Generic audit trigger. Reads actor from app.actor_type / app.actor_id session vars. Attached to every domain table.';

-- Attach to all relevant tables. audit_trail itself and query_log are excluded.
do $$
declare
  t text;
  audited_tables text[] := array[
    'hospital', 'nadra_office', 'nadra_officer', 'parent_guardian',
    'birth_record', 'child', 'child_guardian', 'bform',
    'verification_log', 'ai_review_log', 'offline_queue', 'notifications'
  ];
begin
  foreach t in array audited_tables loop
    execute format(
      'drop trigger if exists trg_audit_%I on public.%I', t, t
    );
    execute format(
      'create trigger trg_audit_%I
         after insert or update or delete on public.%I
         for each row execute function public.fn_audit_trail()',
      t, t
    );
  end loop;
end$$;

-- ----- 0009_state_machine.sql ------------------------------------------------

-- Phase 3: birth_record status state machine + verification log + cascade.
--
-- Three triggers fire on UPDATE OF status:
--   1. BEFORE — fn_validate_birth_record_status validates legality
--   2. AFTER  — fn_log_status_change writes a verification_log row
--   3. AFTER  — fn_post_verification_cascade creates child + bform + notification
--               when status transitions into VERIFIED
--
-- Officer for the verification_log row is read from session var
-- app.current_officer_id. AI-driven changes can leave it unset; the trigger
-- falls back to the EMP-999999 sentinel officer.

-- ---------------------------------------------------------------------------
-- 1. State-machine validator
-- ---------------------------------------------------------------------------
create or replace function public.fn_validate_birth_record_status()
returns trigger
language plpgsql
as $$
declare
  v_legal boolean;
begin
  if NEW.status is not distinct from OLD.status then
    return NEW;
  end if;

  v_legal := exists (
    select 1
    from (values
      ('PENDING'::record_status_t,  'VERIFIED'::record_status_t),
      ('PENDING',                   'FLAGGED'),
      ('PENDING',                   'REJECTED'),
      ('FLAGGED',                   'VERIFIED'),
      ('FLAGGED',                   'REJECTED'),
      ('REJECTED',                  'PENDING'),
      ('VERIFIED',                  'AMENDED'),
      ('AMENDED',                   'AMENDED')
    ) as legal(prev, next)
    where legal.prev = OLD.status and legal.next = NEW.status
  );

  if not v_legal then
    raise exception
      'Illegal status transition on birth_record %: % -> %',
      NEW.birth_record_id, OLD.status, NEW.status
      using errcode = 'check_violation';
  end if;

  return NEW;
end$$;

comment on function public.fn_validate_birth_record_status() is
  'BEFORE UPDATE trigger on birth_record. Rejects illegal status transitions per the proposal''s state machine (§4.1).';

drop trigger if exists trg_birth_record_state_machine on public.birth_record;
create trigger trg_birth_record_state_machine
  before update of status on public.birth_record
  for each row
  execute function public.fn_validate_birth_record_status();

-- ---------------------------------------------------------------------------
-- 2. Status-change logger
-- ---------------------------------------------------------------------------
create or replace function public.fn_log_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_officer_id uuid;
begin
  if NEW.status is not distinct from OLD.status then
    return NEW;
  end if;

  begin
    v_officer_id := nullif(current_setting('app.current_officer_id', true), '')::uuid;
  exception when others then
    v_officer_id := null;
  end;

  if v_officer_id is null then
    select officer_id into v_officer_id
    from public.nadra_officer
    where employee_no = 'EMP-999999';
  end if;

  if v_officer_id is null then
    raise exception 'Cannot log status change: no officer in session and no AI system officer configured';
  end if;

  insert into public.verification_log
    (birth_record_id, officer_id, action, previous_status, new_status, remarks)
  values
    (NEW.birth_record_id, v_officer_id,
     coalesce(TG_ARGV[0], 'STATUS_CHANGE'),
     OLD.status, NEW.status,
     NEW.remarks);

  return NEW;
end$$;

comment on function public.fn_log_status_change() is
  'AFTER UPDATE trigger on birth_record. Writes a verification_log row for every status change.';

drop trigger if exists trg_birth_record_log_status on public.birth_record;
create trigger trg_birth_record_log_status
  after update of status on public.birth_record
  for each row
  execute function public.fn_log_status_change('STATUS_CHANGE');

-- ---------------------------------------------------------------------------
-- 3. Post-verification cascade
-- ---------------------------------------------------------------------------
create or replace function public.fn_post_verification_cascade()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_child_id     uuid;
  v_cnin         text;
  v_bform_number text;
  v_officer_id   uuid;
  v_district     text;
  v_mother_phone text;
begin
  -- Only fire on transitions into VERIFIED from PENDING or FLAGGED.
  if not (NEW.status = 'VERIFIED' and OLD.status in ('PENDING', 'FLAGGED')) then
    return NEW;
  end if;

  -- Idempotency: if a child already exists for this birth, do nothing.
  if exists (select 1 from public.child where birth_record_id = NEW.birth_record_id) then
    return NEW;
  end if;

  begin
    v_officer_id := nullif(current_setting('app.current_officer_id', true), '')::uuid;
  exception when others then
    v_officer_id := null;
  end;
  if v_officer_id is null then
    select officer_id into v_officer_id
    from public.nadra_officer where employee_no = 'EMP-999999';
  end if;

  -- Mint a CNIN and create the CHILD row. Place of birth = hospital district.
  v_cnin := 'CNIN-' || lpad(nextval('public.cnin_seq')::text, 10, '0');

  select h.district into v_district
    from public.hospital h
   where h.hospital_id = NEW.hospital_id;

  insert into public.child
    (cnin, birth_record_id, full_name, gender, date_of_birth, place_of_birth)
  values
    (v_cnin, NEW.birth_record_id,
     coalesce(NEW.child_full_name, 'Pending'),
     NEW.child_gender,
     NEW.birth_datetime::date,
     coalesce(v_district, 'Unknown'))
  returning child_id into v_child_id;

  -- Link mother (always primary).
  insert into public.child_guardian
    (child_id, guardian_id, relationship_type, is_primary)
  values
    (v_child_id, NEW.mother_id, 'MOTHER', true);

  if NEW.father_id is not null then
    insert into public.child_guardian
      (child_id, guardian_id, relationship_type, is_primary)
    values
      (v_child_id, NEW.father_id, 'FATHER', false);
  end if;

  -- Mint a B-Form number and create the BFORM row, NOT YET authorized.
  v_bform_number := 'BF-' || to_char(now(), 'YYYY') || '-' ||
                    lpad(nextval('public.bform_seq')::text, 8, '0');

  insert into public.bform
    (bform_number, child_id, issued_by, version, is_current, authorized_at)
  values
    (v_bform_number, v_child_id, v_officer_id, 1, true, null);

  -- Queue an SMS notification (held until officer authorizes).
  select contact_number into v_mother_phone
    from public.parent_guardian where guardian_id = NEW.mother_id;

  insert into public.notifications
    (recipient_type, recipient_contact, channel, subject, body,
     status, related_table, related_id)
  values
    ('PARENT', v_mother_phone, 'SMS', null,
     'Mubarak ho! Your child''s B-Form ' || v_bform_number ||
     ' has been generated. You will receive another message when it is authorized for collection.',
     'QUEUED', 'bform', v_bform_number);

  return NEW;
end$$;

comment on function public.fn_post_verification_cascade() is
  'AFTER UPDATE trigger on birth_record. On transition into VERIFIED: creates child (with CNIN), links guardians, generates B-Form, queues SMS.';

drop trigger if exists trg_birth_record_post_verification on public.birth_record;
create trigger trg_birth_record_post_verification
  after update of status on public.birth_record
  for each row
  when (NEW.status = 'VERIFIED' and OLD.status <> 'VERIFIED')
  execute function public.fn_post_verification_cascade();

-- ----- 0010_bform_functions.sql ----------------------------------------------

-- Phase 3: B-Form lifecycle functions.
--
-- authorize_bform — officer marks an existing B-Form as authorized,
--                   moves notification from QUEUED to SENT.
-- reissue_bform   — generates a new version, marks the prior current
--                   version as is_current = false, queues a new SMS.

-- ---------------------------------------------------------------------------
-- authorize_bform
-- ---------------------------------------------------------------------------
create or replace function public.authorize_bform(
  p_bform_id   uuid,
  p_officer_id uuid
)
returns public.bform
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bform     public.bform;
  v_start     timestamptz := clock_timestamp();
begin
  -- Set actor for the audit trigger.
  perform set_config('app.actor_type', 'NADRA_OFFICER', true);
  perform set_config('app.actor_id',   p_officer_id::text, true);

  update public.bform
     set authorized_at = now()
   where bform_id = p_bform_id
     and authorized_at is null
   returning * into v_bform;

  if v_bform is null then
    raise exception 'B-Form % not found or already authorized', p_bform_id;
  end if;

  -- Promote the matching queued SMS to SENT (mocked).
  update public.notifications
     set status = 'SENT', sent_at = now(),
         body = replace(body, 'You will receive another message when it is authorized for collection.',
                              'It is now ready for collection at your nearest NADRA office.')
   where related_table = 'bform'
     and related_id    = v_bform.bform_number
     and status        = 'QUEUED';

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('authorize_bform',
          'update bform set authorized_at = now() where bform_id = $1',
          jsonb_build_object('bform_id', p_bform_id, 'officer_id', p_officer_id),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_bform;
end$$;

grant execute on function public.authorize_bform(uuid, uuid) to anon, authenticated;

comment on function public.authorize_bform(uuid, uuid) is
  'Officer authorizes a B-Form for collection. Sets authorized_at and promotes the queued SMS to SENT.';

-- ---------------------------------------------------------------------------
-- reissue_bform
-- ---------------------------------------------------------------------------
create or replace function public.reissue_bform(
  p_child_id      uuid,
  p_officer_id    uuid,
  p_reason        text
)
returns public.bform
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev_version  integer;
  v_new_number    text;
  v_new_bform     public.bform;
  v_mother_phone  text;
  v_start         timestamptz := clock_timestamp();
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Reissue reason is required';
  end if;

  perform set_config('app.actor_type', 'NADRA_OFFICER', true);
  perform set_config('app.actor_id',   p_officer_id::text, true);

  -- Lock the prior current row.
  select version into v_prev_version
    from public.bform
   where child_id = p_child_id and is_current = true
   for update;

  if v_prev_version is null then
    raise exception 'No current B-Form found for child %', p_child_id;
  end if;

  -- Mark prior version as not current.
  update public.bform
     set is_current = false
   where child_id = p_child_id and is_current = true;

  -- Mint new number and insert new version.
  v_new_number := 'BF-' || to_char(now(), 'YYYY') || '-' ||
                  lpad(nextval('public.bform_seq')::text, 8, '0');

  insert into public.bform
    (bform_number, child_id, issued_by, version, is_current,
     reissue_reason, authorized_at)
  values
    (v_new_number, p_child_id, p_officer_id,
     v_prev_version + 1, true, p_reason, now())
  returning * into v_new_bform;

  -- Queue an SMS to the primary mother.
  select pg.contact_number
    into v_mother_phone
    from public.child_guardian cg
    join public.parent_guardian pg on pg.guardian_id = cg.guardian_id
   where cg.child_id = p_child_id
     and cg.relationship_type = 'MOTHER'
   limit 1;

  if v_mother_phone is not null then
    insert into public.notifications
      (recipient_type, recipient_contact, channel, body,
       status, related_table, related_id, sent_at)
    values
      ('PARENT', v_mother_phone, 'SMS',
       'Your child''s B-Form has been reissued as ' || v_new_number ||
       ' (reason: ' || p_reason || '). Ready for collection at your nearest NADRA office.',
       'SENT', 'bform', v_new_number, now());
  end if;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('reissue_bform',
          'update bform set is_current=false, insert new version, queue notification',
          jsonb_build_object('child_id', p_child_id, 'officer_id', p_officer_id, 'reason', p_reason),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_new_bform;
end$$;

grant execute on function public.reissue_bform(uuid, uuid, text) to anon, authenticated;

comment on function public.reissue_bform(uuid, uuid, text) is
  'Versioned B-Form reissuance. Marks prior version not current, inserts new version, queues SMS.';

-- ----- 0011_business_rpcs.sql ------------------------------------------------

-- Phase 3: business RPCs the frontend will call.
--
-- All RPCs are SECURITY DEFINER and grant EXECUTE to anon/authenticated.
-- Phase 4 will add real RLS-aware authentication; for now they accept the
-- caller's identity as a parameter (officer_id, hospital_id).

-- ---------------------------------------------------------------------------
-- submit_birth_record — hospital staff submits a new birth
-- ---------------------------------------------------------------------------
create or replace function public.submit_birth_record(
  p_hospital_id        uuid,
  p_mother_id          uuid,
  p_father_id          uuid,
  p_attending_doctor   text,
  p_doctor_license_no  text,
  p_birth_datetime     timestamptz,
  p_delivery_type      delivery_type_t,
  p_birth_weight_kg    numeric,
  p_birth_outcome      birth_outcome_t,
  p_child_gender       gender_t,
  p_child_full_name    text default null,
  p_remarks            text default null
)
returns public.birth_record
language plpgsql
security definer
set search_path = public
as $$
declare
  v_brn   text;
  v_row   public.birth_record;
  v_start timestamptz := clock_timestamp();
begin
  perform set_config('app.actor_type', 'HOSPITAL_STAFF', true);
  perform set_config('app.actor_id',   p_hospital_id::text, true);

  v_brn := 'BRN-' || to_char(now(), 'YYYY') || '-' ||
           lpad((floor(random() * 99999999) + 1)::int::text, 8, '0');

  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome,
     child_gender, child_full_name, remarks, status)
  values
    (v_brn, p_hospital_id, p_mother_id, p_father_id, p_attending_doctor, p_doctor_license_no,
     p_birth_datetime, p_delivery_type, p_birth_weight_kg, p_birth_outcome,
     p_child_gender, p_child_full_name, p_remarks, 'PENDING')
  returning * into v_row;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('submit_birth_record',
          'insert into birth_record (...) values (...) returning *',
          jsonb_build_object('brn', v_brn, 'hospital_id', p_hospital_id),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_row;
end$$;

grant execute on function public.submit_birth_record(
  uuid, uuid, uuid, text, text, timestamptz, delivery_type_t, numeric,
  birth_outcome_t, gender_t, text, text
) to anon, authenticated;

comment on function public.submit_birth_record(
  uuid, uuid, uuid, text, text, timestamptz, delivery_type_t, numeric,
  birth_outcome_t, gender_t, text, text
) is 'Hospital portal: submit a new birth record. Status defaults to PENDING; AI engine picks it up next.';

-- ---------------------------------------------------------------------------
-- verify_birth_record — officer or AI approves a record
-- ---------------------------------------------------------------------------
create or replace function public.verify_birth_record(
  p_birth_record_id uuid,
  p_officer_id      uuid,
  p_remarks         text default null
)
returns public.birth_record
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   public.birth_record;
  v_start timestamptz := clock_timestamp();
begin
  perform set_config('app.actor_type',         'NADRA_OFFICER', true);
  perform set_config('app.actor_id',           p_officer_id::text, true);
  perform set_config('app.current_officer_id', p_officer_id::text, true);

  update public.birth_record
     set status  = 'VERIFIED',
         remarks = coalesce(p_remarks, remarks)
   where birth_record_id = p_birth_record_id
   returning * into v_row;

  if v_row is null then
    raise exception 'Birth record % not found', p_birth_record_id;
  end if;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('verify_birth_record',
          'update birth_record set status = VERIFIED where birth_record_id = $1',
          jsonb_build_object('birth_record_id', p_birth_record_id, 'officer_id', p_officer_id),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_row;
end$$;

grant execute on function public.verify_birth_record(uuid, uuid, text) to anon, authenticated;

comment on function public.verify_birth_record(uuid, uuid, text) is
  'Officer (or AI Engine via EMP-999999) verifies a record. Triggers fire: state machine, verification_log, post-verification cascade.';

-- ---------------------------------------------------------------------------
-- flag_birth_record — AI engine or officer flags for review
-- ---------------------------------------------------------------------------
create or replace function public.flag_birth_record(
  p_birth_record_id uuid,
  p_officer_id      uuid,
  p_remarks         text
)
returns public.birth_record
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   public.birth_record;
  v_start timestamptz := clock_timestamp();
begin
  perform set_config('app.actor_type',         'AI_ENGINE', true);
  perform set_config('app.actor_id',           p_officer_id::text, true);
  perform set_config('app.current_officer_id', p_officer_id::text, true);

  update public.birth_record
     set status  = 'FLAGGED',
         remarks = coalesce(p_remarks, remarks)
   where birth_record_id = p_birth_record_id
   returning * into v_row;

  if v_row is null then
    raise exception 'Birth record % not found', p_birth_record_id;
  end if;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('flag_birth_record',
          'update birth_record set status = FLAGGED where birth_record_id = $1',
          jsonb_build_object('birth_record_id', p_birth_record_id),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_row;
end$$;

grant execute on function public.flag_birth_record(uuid, uuid, text) to anon, authenticated;

comment on function public.flag_birth_record(uuid, uuid, text) is
  'Move a record to FLAGGED for human review.';

-- ---------------------------------------------------------------------------
-- reject_birth_record — officer rejects after review
-- ---------------------------------------------------------------------------
create or replace function public.reject_birth_record(
  p_birth_record_id uuid,
  p_officer_id      uuid,
  p_remarks         text
)
returns public.birth_record
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   public.birth_record;
  v_start timestamptz := clock_timestamp();
begin
  if p_remarks is null or length(trim(p_remarks)) = 0 then
    raise exception 'Rejection requires a reason';
  end if;

  perform set_config('app.actor_type',         'NADRA_OFFICER', true);
  perform set_config('app.actor_id',           p_officer_id::text, true);
  perform set_config('app.current_officer_id', p_officer_id::text, true);

  update public.birth_record
     set status  = 'REJECTED',
         remarks = p_remarks
   where birth_record_id = p_birth_record_id
   returning * into v_row;

  if v_row is null then
    raise exception 'Birth record % not found', p_birth_record_id;
  end if;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('reject_birth_record',
          'update birth_record set status = REJECTED where birth_record_id = $1',
          jsonb_build_object('birth_record_id', p_birth_record_id, 'officer_id', p_officer_id),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_row;
end$$;

grant execute on function public.reject_birth_record(uuid, uuid, text) to anon, authenticated;

comment on function public.reject_birth_record(uuid, uuid, text) is
  'Officer rejects a record. Reason is required; the hospital sees the reason and can resubmit (REJECTED -> PENDING).';

-- ---------------------------------------------------------------------------
-- resubmit_birth_record — hospital resubmits a rejected record
-- ---------------------------------------------------------------------------
create or replace function public.resubmit_birth_record(
  p_birth_record_id uuid,
  p_hospital_id     uuid,
  p_remarks         text default null
)
returns public.birth_record
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   public.birth_record;
  v_start timestamptz := clock_timestamp();
begin
  perform set_config('app.actor_type',         'HOSPITAL_STAFF', true);
  perform set_config('app.actor_id',           p_hospital_id::text, true);
  perform set_config('app.current_officer_id', '', true);

  update public.birth_record
     set status  = 'PENDING',
         remarks = coalesce(p_remarks, remarks)
   where birth_record_id = p_birth_record_id
     and hospital_id     = p_hospital_id
   returning * into v_row;

  if v_row is null then
    raise exception 'Birth record % not found for hospital %', p_birth_record_id, p_hospital_id;
  end if;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('resubmit_birth_record',
          'update birth_record set status = PENDING where birth_record_id = $1 and hospital_id = $2',
          jsonb_build_object('birth_record_id', p_birth_record_id, 'hospital_id', p_hospital_id),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_row;
end$$;

grant execute on function public.resubmit_birth_record(uuid, uuid, text) to anon, authenticated;

comment on function public.resubmit_birth_record(uuid, uuid, text) is
  'Hospital resubmits a REJECTED record after correcting the issue.';

-- ---------------------------------------------------------------------------
-- get_pipeline_summary — quick stats for the /dev/triggers demo
-- ---------------------------------------------------------------------------
create or replace function public.get_pipeline_summary()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'records_by_status', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
      from (select status::text, count(*) as n from public.birth_record group by status) s
    ),
    'children',         (select count(*) from public.child),
    'bforms_total',     (select count(*) from public.bform),
    'bforms_authorized',(select count(*) from public.bform where authorized_at is not null),
    'bforms_pending',   (select count(*) from public.bform where authorized_at is null),
    'notifications_queued', (select count(*) from public.notifications where status = 'QUEUED'),
    'notifications_sent',   (select count(*) from public.notifications where status = 'SENT'),
    'audit_entries',    (select count(*) from public.audit_trail),
    'verification_logs',(select count(*) from public.verification_log),
    'generated_at',     now()
  );
$$;

grant execute on function public.get_pipeline_summary() to anon, authenticated;

-- ----- 0012_harden_function_security.sql -------------------------------------

-- Phase 3 hardening: lock down trigger-only functions.
--
-- The Supabase advisors correctly flagged that fn_audit_trail,
-- fn_log_status_change, and fn_post_verification_cascade can be invoked
-- directly via /rest/v1/rpc/<name> by anon and authenticated roles.
-- They are meant to fire only as triggers, never as user RPCs.
-- Revoking EXECUTE removes them from the REST surface; triggers still work
-- because PostgreSQL invokes trigger functions internally regardless of
-- granted privileges (and they are SECURITY DEFINER as well, so they keep
-- running with the table owner's permissions).
--
-- Also pin search_path on fn_validate_birth_record_status, which is a
-- SECURITY INVOKER function but should still have a stable search_path.

revoke execute on function public.fn_audit_trail()                from anon, authenticated, public;
revoke execute on function public.fn_log_status_change()           from anon, authenticated, public;
revoke execute on function public.fn_post_verification_cascade()   from anon, authenticated, public;

alter function public.fn_validate_birth_record_status()
  set search_path = public;

-- ----- 0013_get_trigger_lab_data_rpc.sql -------------------------------------

-- Phase 3: a single RPC that returns everything the /dev/triggers lab needs.
--
-- The page can't read tables directly: RLS is enabled but no SELECT policies
-- exist (Phase 4 adds them), so anon table reads return 0 rows. This RPC is
-- SECURITY DEFINER, so it runs as the table owner and sees every row.

create or replace function public.get_trigger_lab_data()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'pending_records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'birth_record_id', br.birth_record_id,
        'brn',             br.brn,
        'status',          br.status,
        'submitted_at',    br.submitted_at,
        'mother_name',     m.full_name,
        'hospital_name',   h.hospital_name
      ) order by br.submitted_at desc)
      from (
        select * from public.birth_record
        where status in ('PENDING','FLAGGED')
        order by submitted_at desc
        limit 20
      ) br
      join public.parent_guardian m on m.guardian_id = br.mother_id
      join public.hospital h        on h.hospital_id = br.hospital_id
    ), '[]'::jsonb),

    'pending_bforms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'bform_id',      b.bform_id,
        'bform_number',  b.bform_number,
        'child_id',      c.child_id,
        'child_name',    c.full_name,
        'authorized_at', b.authorized_at
      ) order by b.created_at desc)
      from (
        select * from public.bform
        where authorized_at is null and is_current = true
        order by created_at desc
        limit 20
      ) b
      join public.child c on c.child_id = b.child_id
    ), '[]'::jsonb),

    'current_bforms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'child_id',     c.child_id,
        'child_name',   c.full_name,
        'bform_number', b.bform_number,
        'version',      b.version
      ) order by b.created_at desc)
      from (
        select * from public.bform
        where is_current = true and authorized_at is not null
        order by created_at desc
        limit 20
      ) b
      join public.child c on c.child_id = b.child_id
    ), '[]'::jsonb),

    'recent_audit', coalesce((
      select jsonb_agg(jsonb_build_object(
        'audit_id',        audit_id,
        'actor_type',      actor_type::text,
        'actor_id',        actor_id,
        'action_type',     action_type,
        'table_affected',  table_affected,
        'record_id',       record_id,
        'action_datetime', action_datetime,
        'description',     description
      ) order by action_datetime desc)
      from (
        select * from public.audit_trail
        order by action_datetime desc
        limit 20
      ) a
    ), '[]'::jsonb),

    'officers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'officer_id',  officer_id,
        'full_name',   full_name,
        'employee_no', employee_no
      ) order by full_name)
      from public.nadra_officer
      where employee_no <> 'EMP-999999' and is_active = true
    ), '[]'::jsonb),

    'generated_at', now()
  );
$$;

grant execute on function public.get_trigger_lab_data() to anon, authenticated;

comment on function public.get_trigger_lab_data() is
  'Single RPC returning every list the /dev/triggers lab needs: pending records, pending B-Forms, current B-Forms, recent audit, active officers.';

-- ----- 0017_phase5_hospital_rpcs.sql -----------------------------------------

-- Phase 5: hospital-portal RPCs.
--
-- submit_birth_record_v2 — what the multi-step form actually calls.
--   Looks up mother (and optional father) by CNIC. If a guardian exists,
--   reuses it. Otherwise creates a parent_guardian row. Then inserts the
--   birth_record (PENDING) for the caller's hospital.
--   The caller's hospital_id is read from auth.uid() via current_hospital_id().
--
-- get_hospital_dashboard_data — the dashboard's single fetch:
--   counts by status, recent submissions, latest notifications.

create or replace function public.submit_birth_record_v2(
  p_mother_cnic         text,
  p_mother_full_name    text,
  p_mother_dob          date,
  p_mother_contact      text,
  p_mother_address      text,
  p_mother_province     province_t,
  p_mother_district     text,
  p_mother_blood_group  text default null,
  p_father_cnic         text default null,
  p_father_full_name    text default null,
  p_father_dob          date default null,
  p_father_contact      text default null,
  p_attending_doctor    text default null,
  p_doctor_license_no   text default null,
  p_birth_datetime      timestamptz default null,
  p_delivery_type       delivery_type_t default null,
  p_birth_weight_kg     numeric default null,
  p_birth_outcome       birth_outcome_t default null,
  p_child_gender        gender_t default null,
  p_child_full_name     text default null,
  p_remarks             text default null
)
returns public.birth_record
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hospital_id uuid := public.current_hospital_id();
  v_mother_id   uuid;
  v_father_id   uuid;
  v_brn         text;
  v_row         public.birth_record;
  v_start       timestamptz := clock_timestamp();
begin
  if v_hospital_id is null then
    raise exception 'submit_birth_record_v2 must be called by a hospital_staff user (current_hospital_id is null)';
  end if;

  if p_attending_doctor is null or p_doctor_license_no is null
     or p_birth_datetime is null or p_delivery_type is null
     or p_birth_weight_kg is null or p_birth_outcome is null
     or p_child_gender is null then
    raise exception 'Missing required birth-record field';
  end if;

  perform set_config('app.actor_type', 'HOSPITAL_STAFF', true);
  perform set_config('app.actor_id',   v_hospital_id::text, true);

  -- mother: lookup by cnic, else create
  if p_mother_cnic is not null then
    select guardian_id into v_mother_id
      from public.parent_guardian
     where cnic = p_mother_cnic
     limit 1;
  end if;

  if v_mother_id is null then
    insert into public.parent_guardian
      (cnic, full_name, gender, date_of_birth,
       contact_number, address, province, district, blood_group)
    values
      (p_mother_cnic, p_mother_full_name, 'FEMALE', p_mother_dob,
       p_mother_contact, p_mother_address, p_mother_province, p_mother_district,
       p_mother_blood_group)
    returning guardian_id into v_mother_id;
  end if;

  -- father: optional
  if p_father_cnic is not null then
    select guardian_id into v_father_id
      from public.parent_guardian
     where cnic = p_father_cnic
     limit 1;

    if v_father_id is null then
      if p_father_full_name is null or p_father_dob is null
         or p_father_contact is null then
        raise exception 'Father CNIC provided but other fields missing';
      end if;

      insert into public.parent_guardian
        (cnic, full_name, gender, date_of_birth,
         contact_number, address, province, district)
      values
        (p_father_cnic, p_father_full_name, 'MALE', p_father_dob,
         p_father_contact, p_mother_address, p_mother_province, p_mother_district)
      returning guardian_id into v_father_id;
    end if;
  end if;

  -- mint a fresh BRN
  v_brn := 'BRN-' || to_char(now(), 'YYYY') || '-' ||
           lpad((floor(random() * 99999999) + 1)::int::text, 8, '0');

  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id,
     attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome,
     child_gender, child_full_name, remarks, status)
  values
    (v_brn, v_hospital_id, v_mother_id, v_father_id,
     p_attending_doctor, p_doctor_license_no,
     p_birth_datetime, p_delivery_type, p_birth_weight_kg, p_birth_outcome,
     p_child_gender, p_child_full_name, p_remarks, 'PENDING')
  returning * into v_row;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('submit_birth_record_v2',
          'upsert mother+father by cnic, insert birth_record (PENDING)',
          jsonb_build_object(
            'brn', v_brn,
            'hospital_id', v_hospital_id,
            'mother_cnic', p_mother_cnic,
            'father_cnic', p_father_cnic
          ),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_row;
end$$;

grant execute on function public.submit_birth_record_v2(
  text, text, date, text, text, province_t, text, text,
  text, text, date, text,
  text, text, timestamptz, delivery_type_t, numeric,
  birth_outcome_t, gender_t, text, text
) to authenticated;

comment on function public.submit_birth_record_v2(
  text, text, date, text, text, province_t, text, text,
  text, text, date, text,
  text, text, timestamptz, delivery_type_t, numeric,
  birth_outcome_t, gender_t, text, text
) is 'Hospital portal: smart submit. Looks up mother/father by CNIC or creates them, then inserts a PENDING birth_record for the caller''s hospital.';

-- ---------------------------------------------------------------------------
-- get_hospital_dashboard_data — single payload for /hospital
-- ---------------------------------------------------------------------------
create or replace function public.get_hospital_dashboard_data()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case
    when public.current_hospital_id() is null then
      jsonb_build_object('error', 'Caller is not hospital staff')
    else jsonb_build_object(
      'hospital', (
        select jsonb_build_object(
          'hospital_id', h.hospital_id,
          'hospital_name', h.hospital_name,
          'district', h.district,
          'province', h.province,
          'hrn', h.hrn
        )
        from public.hospital h
        where h.hospital_id = public.current_hospital_id()
      ),
      'records_by_status', coalesce((
        select jsonb_object_agg(status, n)
        from (
          select status::text, count(*) as n
          from public.birth_record
          where hospital_id = public.current_hospital_id()
          group by status
        ) s
      ), '{}'::jsonb),
      'recent_submissions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'birth_record_id', br.birth_record_id,
          'brn', br.brn,
          'status', br.status,
          'submitted_at', br.submitted_at,
          'mother_name', m.full_name,
          'child_name', br.child_full_name,
          'remarks', br.remarks
        ) order by br.submitted_at desc)
        from (
          select * from public.birth_record
          where hospital_id = public.current_hospital_id()
          order by submitted_at desc
          limit 10
        ) br
        join public.parent_guardian m on m.guardian_id = br.mother_id
      ), '[]'::jsonb),
      'children_registered', (
        select count(*)
        from public.child c
        join public.birth_record br on br.birth_record_id = c.birth_record_id
        where br.hospital_id = public.current_hospital_id()
      ),
      'bforms_ready', (
        select count(*)
        from public.bform b
        join public.child c on c.child_id = b.child_id
        join public.birth_record br on br.birth_record_id = c.birth_record_id
        where br.hospital_id = public.current_hospital_id()
          and b.is_current = true
          and b.authorized_at is not null
      ),
      'pending_offline', (
        select count(*) from public.offline_queue
        where hospital_id = public.current_hospital_id()
          and status = 'PENDING'
      ),
      'generated_at', now()
    )
  end;
$$;

grant execute on function public.get_hospital_dashboard_data() to authenticated;

comment on function public.get_hospital_dashboard_data() is
  'Hospital portal dashboard: hospital info, status counts, recent submissions, children, B-Forms, offline queue depth.';

-- ---------------------------------------------------------------------------
-- get_hospital_submissions — paginated list for /hospital/submissions
-- ---------------------------------------------------------------------------
create or replace function public.get_hospital_submissions(
  p_limit  integer default 100
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case
    when public.current_hospital_id() is null then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'birth_record_id', br.birth_record_id,
        'brn', br.brn,
        'status', br.status,
        'submitted_at', br.submitted_at,
        'birth_datetime', br.birth_datetime,
        'child_full_name', br.child_full_name,
        'child_gender', br.child_gender,
        'birth_weight_kg', br.birth_weight_kg,
        'mother_name', m.full_name,
        'mother_cnic', m.cnic,
        'attending_doctor', br.attending_doctor,
        'remarks', br.remarks,
        'has_child', exists (select 1 from public.child c where c.birth_record_id = br.birth_record_id),
        'cnin', (select cnin from public.child c where c.birth_record_id = br.birth_record_id)
      ) order by br.submitted_at desc)
      from (
        select * from public.birth_record
        where hospital_id = public.current_hospital_id()
        order by submitted_at desc
        limit p_limit
      ) br
      join public.parent_guardian m on m.guardian_id = br.mother_id
    ), '[]'::jsonb)
  end;
$$;

grant execute on function public.get_hospital_submissions(integer) to authenticated;

-- ----- 0018_phase7_officer_rpcs.sql ------------------------------------------

-- Phase 7: NADRA Officer Portal RPCs.
--
-- Auth-aware versions of the verify/reject/flag/authorize/reissue functions
-- (no officer_id parameter — pulled from current_officer_id() / auth.uid()).
-- Plus dashboard, queue, record-detail, search, B-Form, and stats RPCs.
--
-- All read RPCs are SECURITY DEFINER so they bypass RLS — the entry-point
-- checks current_app_role() and rejects non-officers explicitly.

-- ---------------------------------------------------------------------------
-- Helper: must be officer (or admin) — raise if not.
-- ---------------------------------------------------------------------------
create or replace function public.assert_officer()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  v_role := public.current_app_role();
  if v_role not in ('nadra_officer', 'admin') then
    raise exception 'insufficient_privilege: requires nadra_officer or admin role'
      using errcode = '42501';
  end if;
end$$;

grant execute on function public.assert_officer() to authenticated;

-- ---------------------------------------------------------------------------
-- get_officer_dashboard_data — stat tiles + queue previews
-- ---------------------------------------------------------------------------
create or replace function public.get_officer_dashboard_data()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_officer_id uuid;
  v_result     jsonb;
begin
  perform public.assert_officer();
  v_officer_id := public.current_officer_id();

  select jsonb_build_object(
    'officer', (
      select jsonb_build_object(
        'officer_id',  o.officer_id,
        'employee_no', o.employee_no,
        'full_name',   o.full_name,
        'designation', o.designation,
        'office_name', no2.office_name,
        'city',        no2.city,
        'province',    no2.province
      )
      from public.nadra_officer o
      left join public.nadra_office no2 on no2.office_id = o.office_id
      where o.officer_id = v_officer_id
    ),
    'counts', jsonb_build_object(
      'pending',         (select count(*) from public.birth_record where status = 'PENDING'),
      'flagged',         (select count(*) from public.birth_record where status = 'FLAGGED'),
      'verified_today',  (select count(*) from public.birth_record where status = 'VERIFIED'
                                              and submitted_at::date = current_date),
      'rejected_today',  (select count(*) from public.birth_record where status = 'REJECTED'
                                              and submitted_at::date = current_date),
      'my_actions_today', (select count(*) from public.verification_log
                                              where officer_id = v_officer_id
                                                and action_datetime::date = current_date),
      'bforms_to_authorize', (select count(*) from public.bform where authorized_at is null and is_current),
      'children_total',  (select count(*) from public.child),
      'records_total',   (select count(*) from public.birth_record)
    ),
    'recent_actions', (
      select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
        select vl.log_id,
               vl.action,
               vl.previous_status,
               vl.new_status,
               vl.action_datetime,
               vl.remarks,
               br.brn,
               h.hospital_name
        from public.verification_log vl
        join public.birth_record br on br.birth_record_id = vl.birth_record_id
        join public.hospital     h  on h.hospital_id     = br.hospital_id
        where vl.officer_id = v_officer_id
        order by vl.action_datetime desc
        limit 10
      ) x
    ),
    'oldest_pending', (
      select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
        select br.birth_record_id, br.brn, br.status, br.submitted_at,
               br.attending_doctor, br.birth_weight_kg,
               h.hospital_name, h.district,
               m.full_name as mother_name,
               extract(epoch from (now() - br.submitted_at))::bigint as age_seconds
        from public.birth_record br
        join public.hospital     h on h.hospital_id  = br.hospital_id
        join public.parent_guardian m on m.guardian_id = br.mother_id
        where br.status in ('PENDING', 'FLAGGED')
        order by br.submitted_at asc
        limit 8
      ) x
    ),
    'generated_at', now()
  ) into v_result;

  insert into public.query_log (caller, sql_text, duration_ms, rows_returned)
  values ('get_officer_dashboard_data', '12 aggregates over birth_record, verification_log, bform, child', 0, 1);

  return v_result;
end$$;

grant execute on function public.get_officer_dashboard_data() to authenticated;

-- ---------------------------------------------------------------------------
-- get_officer_queue — paged list of records awaiting officer action
-- ---------------------------------------------------------------------------
create or replace function public.get_officer_queue(
  p_status text default 'all',     -- 'pending' | 'flagged' | 'all'
  p_limit  int  default 100,
  p_offset int  default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_filter record_status_t[];
  v_rows   jsonb;
  v_total  int;
begin
  perform public.assert_officer();

  v_filter := case p_status
    when 'pending' then array['PENDING']::record_status_t[]
    when 'flagged' then array['FLAGGED']::record_status_t[]
    else array['PENDING','FLAGGED']::record_status_t[]
  end;

  select count(*) into v_total
    from public.birth_record br
   where br.status = any(v_filter);

  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into v_rows from (
    select br.birth_record_id,
           br.brn,
           br.status,
           br.submitted_at,
           br.birth_datetime,
           br.attending_doctor,
           br.doctor_license_no,
           br.delivery_type,
           br.birth_weight_kg,
           br.birth_outcome,
           br.child_full_name,
           br.child_gender,
           br.remarks,
           h.hospital_id,
           h.hospital_name,
           h.district,
           h.province,
           m.full_name as mother_name,
           m.cnic      as mother_cnic,
           f.full_name as father_name,
           f.cnic      as father_cnic,
           (
             select jsonb_build_object(
               'verdict',          ar.verdict,
               'confidence_score', ar.confidence_score,
               'flags_raised',     ar.flags_raised,
               'reviewed_at',      ar.reviewed_at
             )
             from public.ai_review_log ar
             where ar.birth_record_id = br.birth_record_id
             order by ar.reviewed_at desc
             limit 1
           ) as latest_ai_review,
           extract(epoch from (now() - br.submitted_at))::bigint as age_seconds
    from public.birth_record br
    join public.hospital     h on h.hospital_id   = br.hospital_id
    join public.parent_guardian m on m.guardian_id = br.mother_id
    left join public.parent_guardian f on f.guardian_id = br.father_id
    where br.status = any(v_filter)
    order by
      case when br.status = 'FLAGGED' then 0 else 1 end,
      br.submitted_at asc
    limit p_limit offset p_offset
  ) x;

  return jsonb_build_object(
    'rows',       v_rows,
    'total',      v_total,
    'returned',   coalesce(jsonb_array_length(v_rows), 0),
    'status',     p_status,
    'generated_at', now()
  );
end$$;

grant execute on function public.get_officer_queue(text, int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- get_officer_record_detail — full view of a single record
-- ---------------------------------------------------------------------------
create or replace function public.get_officer_record_detail(p_brn text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_record jsonb;
begin
  perform public.assert_officer();

  select jsonb_build_object(
    'record', jsonb_build_object(
      'birth_record_id', br.birth_record_id,
      'brn',             br.brn,
      'status',          br.status,
      'submitted_at',    br.submitted_at,
      'birth_datetime',  br.birth_datetime,
      'attending_doctor', br.attending_doctor,
      'doctor_license_no', br.doctor_license_no,
      'delivery_type',   br.delivery_type,
      'birth_weight_kg', br.birth_weight_kg,
      'birth_outcome',   br.birth_outcome,
      'child_full_name', br.child_full_name,
      'child_gender',    br.child_gender,
      'remarks',         br.remarks,
      'ai_review_result', br.ai_review_result
    ),
    'hospital', jsonb_build_object(
      'hospital_id',   h.hospital_id,
      'hrn',           h.hrn,
      'hospital_name', h.hospital_name,
      'hospital_type', h.hospital_type,
      'district',      h.district,
      'province',      h.province,
      'contact_number', h.contact_number
    ),
    'mother', jsonb_build_object(
      'guardian_id', m.guardian_id,
      'cnic',        m.cnic,
      'full_name',   m.full_name,
      'date_of_birth', m.date_of_birth,
      'contact_number', m.contact_number,
      'address',     m.address,
      'province',    m.province,
      'district',    m.district,
      'blood_group', m.blood_group
    ),
    'father', case when f.guardian_id is null then null else jsonb_build_object(
      'guardian_id', f.guardian_id,
      'cnic',        f.cnic,
      'full_name',   f.full_name,
      'date_of_birth', f.date_of_birth,
      'contact_number', f.contact_number
    ) end,
    'child', (
      select jsonb_build_object(
        'child_id',   c.child_id,
        'cnin',       c.cnin,
        'full_name',  c.full_name,
        'gender',     c.gender,
        'date_of_birth', c.date_of_birth,
        'created_at', c.created_at
      )
      from public.child c
      where c.birth_record_id = br.birth_record_id
    ),
    'bform', (
      select jsonb_build_object(
        'bform_id',      bf.bform_id,
        'bform_number',  bf.bform_number,
        'version',       bf.version,
        'is_current',    bf.is_current,
        'authorized_at', bf.authorized_at,
        'reissue_reason', bf.reissue_reason,
        'issue_date',    bf.issue_date,
        'issued_by_name', o.full_name
      )
      from public.bform bf
      join public.child c on c.child_id = bf.child_id
      left join public.nadra_officer o on o.officer_id = bf.issued_by
      where c.birth_record_id = br.birth_record_id and bf.is_current
      limit 1
    ),
    'ai_history', (
      select coalesce(jsonb_agg(row_to_json(x) order by reviewed_at desc), '[]'::jsonb) from (
        select review_id, verdict, confidence_score, flags_raised,
               reviewed_at, human_override
        from public.ai_review_log ar
        where ar.birth_record_id = br.birth_record_id
        order by reviewed_at desc
        limit 20
      ) x
    ),
    'verification_log', (
      select coalesce(jsonb_agg(row_to_json(x) order by action_datetime desc), '[]'::jsonb) from (
        select vl.log_id, vl.action, vl.previous_status, vl.new_status,
               vl.action_datetime, vl.remarks, o.full_name as officer_name,
               o.employee_no
        from public.verification_log vl
        left join public.nadra_officer o on o.officer_id = vl.officer_id
        where vl.birth_record_id = br.birth_record_id
        order by action_datetime desc
        limit 50
      ) x
    ),
    'generated_at', now()
  )
  into v_record
  from   public.birth_record br
  join   public.hospital      h on h.hospital_id   = br.hospital_id
  join   public.parent_guardian m on m.guardian_id = br.mother_id
  left   join public.parent_guardian f on f.guardian_id = br.father_id
  where  br.brn = p_brn;

  if v_record is null then
    raise exception 'Birth record % not found', p_brn using errcode = 'P0002';
  end if;

  return v_record;
end$$;

grant execute on function public.get_officer_record_detail(text) to authenticated;

-- ---------------------------------------------------------------------------
-- search_records — search by CNIN, BRN, CNIC, mother name, child name
-- ---------------------------------------------------------------------------
create or replace function public.search_records(
  p_query text,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q text;
begin
  perform public.assert_officer();

  v_q := trim(p_query);
  if v_q is null or length(v_q) < 2 then
    return jsonb_build_object('rows', '[]'::jsonb, 'query', v_q);
  end if;

  return jsonb_build_object(
    'query', v_q,
    'rows', (
      select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
        select br.birth_record_id, br.brn, br.status, br.submitted_at,
               br.child_full_name, br.child_gender,
               c.cnin,
               m.full_name as mother_name, m.cnic as mother_cnic,
               h.hospital_name, h.district,
               case
                 when c.cnin                       ilike '%' || v_q || '%' then 'cnin'
                 when br.brn                       ilike '%' || v_q || '%' then 'brn'
                 when m.cnic                       ilike '%' || v_q || '%' then 'mother_cnic'
                 when m.full_name                  ilike '%' || v_q || '%' then 'mother_name'
                 when coalesce(br.child_full_name, c.full_name) ilike '%' || v_q || '%' then 'child_name'
                 else 'other'
               end as match_field
        from public.birth_record br
        join public.hospital h on h.hospital_id = br.hospital_id
        join public.parent_guardian m on m.guardian_id = br.mother_id
        left join public.child c on c.birth_record_id = br.birth_record_id
        where br.brn               ilike '%' || v_q || '%'
           or m.cnic               ilike '%' || v_q || '%'
           or m.full_name          ilike '%' || v_q || '%'
           or coalesce(br.child_full_name, c.full_name) ilike '%' || v_q || '%'
           or c.cnin               ilike '%' || v_q || '%'
        order by br.submitted_at desc
        limit p_limit
      ) x
    )
  );
end$$;

grant execute on function public.search_records(text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- get_population_stats — district + province breakdown
-- ---------------------------------------------------------------------------
create or replace function public.get_population_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_officer();

  return jsonb_build_object(
    'by_province', (
      select coalesce(jsonb_agg(row_to_json(x) order by total_births desc), '[]'::jsonb)
      from (
        select h.province::text as province,
               count(*) as total_births,
               count(*) filter (where br.status = 'VERIFIED') as verified,
               count(*) filter (where br.status = 'FLAGGED')  as flagged,
               count(*) filter (where br.status = 'PENDING')  as pending
        from public.birth_record br
        join public.hospital h on h.hospital_id = br.hospital_id
        group by h.province
      ) x
    ),
    'by_district', (
      select coalesce(jsonb_agg(row_to_json(x) order by total_births desc), '[]'::jsonb)
      from (
        select h.district,
               h.province::text as province,
               count(*) as total_births,
               count(distinct br.hospital_id) as hospitals,
               count(*) filter (where br.status = 'VERIFIED') as verified
        from public.birth_record br
        join public.hospital h on h.hospital_id = br.hospital_id
        group by h.district, h.province
      ) x
    ),
    'by_gender', (
      select coalesce(jsonb_object_agg(coalesce(child_gender::text, 'unknown'), n), '{}'::jsonb)
      from (
        select child_gender, count(*) as n
        from public.birth_record
        group by child_gender
      ) x
    ),
    'by_delivery_type', (
      select coalesce(jsonb_object_agg(delivery_type::text, n), '{}'::jsonb)
      from (
        select delivery_type, count(*) as n
        from public.birth_record
        group by delivery_type
      ) x
    ),
    'top_hospitals', (
      select coalesce(jsonb_agg(row_to_json(x) order by total_births desc), '[]'::jsonb)
      from (
        select h.hospital_name, h.district, h.province::text as province, count(*) as total_births,
               round(100.0 * count(*) filter (where br.status = 'VERIFIED') / count(*), 1) as verified_pct
        from public.birth_record br
        join public.hospital h on h.hospital_id = br.hospital_id
        group by h.hospital_id, h.hospital_name, h.district, h.province
        order by total_births desc
        limit 10
      ) x
    ),
    'totals', jsonb_build_object(
      'records',      (select count(*) from public.birth_record),
      'children',     (select count(*) from public.child),
      'hospitals',    (select count(*) from public.hospital),
      'parents',      (select count(*) from public.parent_guardian),
      'bforms_authorized', (select count(*) from public.bform where authorized_at is not null)
    ),
    'generated_at', now()
  );
end$$;

grant execute on function public.get_population_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- get_bforms_workload — to-authorize + recent issuances
-- ---------------------------------------------------------------------------
create or replace function public.get_bforms_workload(p_limit int default 25)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_officer();

  return jsonb_build_object(
    'to_authorize', (
      select coalesce(jsonb_agg(row_to_json(x) order by created_at asc), '[]'::jsonb) from (
        select bf.bform_id,
               bf.bform_number,
               bf.version,
               bf.created_at,
               bf.reissue_reason,
               c.child_id,
               c.cnin,
               c.full_name as child_name,
               c.date_of_birth,
               br.brn,
               h.hospital_name, h.district,
               m.full_name as mother_name, m.contact_number as mother_contact
        from public.bform bf
        join public.child c on c.child_id = bf.child_id
        join public.birth_record br on br.birth_record_id = c.birth_record_id
        join public.hospital h on h.hospital_id = br.hospital_id
        join public.parent_guardian m on m.guardian_id = br.mother_id
        where bf.authorized_at is null and bf.is_current
        order by bf.created_at asc
        limit p_limit
      ) x
    ),
    'recent_authorized', (
      select coalesce(jsonb_agg(row_to_json(x) order by authorized_at desc), '[]'::jsonb) from (
        select bf.bform_id,
               bf.bform_number,
               bf.version,
               bf.authorized_at,
               bf.reissue_reason,
               c.child_id,
               c.cnin,
               c.full_name as child_name,
               m.full_name as mother_name,
               h.hospital_name,
               o.full_name as authorized_by
        from public.bform bf
        join public.child c on c.child_id = bf.child_id
        join public.birth_record br on br.birth_record_id = c.birth_record_id
        join public.hospital h on h.hospital_id = br.hospital_id
        join public.parent_guardian m on m.guardian_id = br.mother_id
        left join public.nadra_officer o on o.officer_id = bf.issued_by
        where bf.authorized_at is not null
        order by bf.authorized_at desc
        limit p_limit
      ) x
    ),
    'generated_at', now()
  );
end$$;

grant execute on function public.get_bforms_workload(int) to authenticated;

-- ---------------------------------------------------------------------------
-- verify_birth_record_v2 — auth-aware (no officer_id parameter)
-- ---------------------------------------------------------------------------
create or replace function public.verify_birth_record_v2(
  p_brn     text,
  p_remarks text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record_id  uuid;
  v_officer_id uuid;
  v_row        public.birth_record;
begin
  perform public.assert_officer();
  v_officer_id := public.current_officer_id();

  if v_officer_id is null then
    -- admin acting? fall back to AI engine officer
    select officer_id into v_officer_id from public.nadra_officer where employee_no = 'EMP-999999';
  end if;

  select birth_record_id into v_record_id
    from public.birth_record where brn = p_brn;
  if v_record_id is null then
    raise exception 'Birth record % not found', p_brn using errcode = 'P0002';
  end if;

  perform set_config('app.actor_type',         'NADRA_OFFICER',     true);
  perform set_config('app.actor_id',           v_officer_id::text,  true);
  perform set_config('app.current_officer_id', v_officer_id::text,  true);

  update public.birth_record
     set status  = 'VERIFIED',
         remarks = coalesce(p_remarks, remarks)
   where birth_record_id = v_record_id
   returning * into v_row;

  return jsonb_build_object('ok', true, 'brn', v_row.brn, 'status', v_row.status);
end$$;

grant execute on function public.verify_birth_record_v2(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- reject_birth_record_v2 — auth-aware
-- ---------------------------------------------------------------------------
create or replace function public.reject_birth_record_v2(
  p_brn     text,
  p_remarks text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record_id  uuid;
  v_officer_id uuid;
  v_row        public.birth_record;
begin
  perform public.assert_officer();

  if p_remarks is null or length(trim(p_remarks)) = 0 then
    raise exception 'Rejection requires a reason' using errcode = '22023';
  end if;

  v_officer_id := public.current_officer_id();
  if v_officer_id is null then
    select officer_id into v_officer_id from public.nadra_officer where employee_no = 'EMP-999999';
  end if;

  select birth_record_id into v_record_id from public.birth_record where brn = p_brn;
  if v_record_id is null then
    raise exception 'Birth record % not found', p_brn using errcode = 'P0002';
  end if;

  perform set_config('app.actor_type',         'NADRA_OFFICER',     true);
  perform set_config('app.actor_id',           v_officer_id::text,  true);
  perform set_config('app.current_officer_id', v_officer_id::text,  true);

  update public.birth_record
     set status  = 'REJECTED',
         remarks = p_remarks
   where birth_record_id = v_record_id
   returning * into v_row;

  return jsonb_build_object('ok', true, 'brn', v_row.brn, 'status', v_row.status);
end$$;

grant execute on function public.reject_birth_record_v2(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- flag_birth_record_v2 — auth-aware
-- ---------------------------------------------------------------------------
create or replace function public.flag_birth_record_v2(
  p_brn     text,
  p_remarks text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record_id  uuid;
  v_officer_id uuid;
  v_row        public.birth_record;
begin
  perform public.assert_officer();

  v_officer_id := public.current_officer_id();
  if v_officer_id is null then
    select officer_id into v_officer_id from public.nadra_officer where employee_no = 'EMP-999999';
  end if;

  select birth_record_id into v_record_id from public.birth_record where brn = p_brn;
  if v_record_id is null then
    raise exception 'Birth record % not found', p_brn using errcode = 'P0002';
  end if;

  perform set_config('app.actor_type',         'NADRA_OFFICER',     true);
  perform set_config('app.actor_id',           v_officer_id::text,  true);
  perform set_config('app.current_officer_id', v_officer_id::text,  true);

  update public.birth_record
     set status  = 'FLAGGED',
         remarks = coalesce(p_remarks, remarks)
   where birth_record_id = v_record_id
   returning * into v_row;

  return jsonb_build_object('ok', true, 'brn', v_row.brn, 'status', v_row.status);
end$$;

grant execute on function public.flag_birth_record_v2(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- authorize_bform_v2 — auth-aware
-- ---------------------------------------------------------------------------
create or replace function public.authorize_bform_v2(p_bform_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_officer_id uuid;
  v_bform      public.bform;
begin
  perform public.assert_officer();
  v_officer_id := public.current_officer_id();
  if v_officer_id is null then
    select officer_id into v_officer_id from public.nadra_officer where employee_no = 'EMP-999999';
  end if;

  perform set_config('app.actor_type', 'NADRA_OFFICER', true);
  perform set_config('app.actor_id',   v_officer_id::text, true);

  update public.bform
     set authorized_at = now()
   where bform_id = p_bform_id and authorized_at is null
   returning * into v_bform;

  if v_bform is null then
    raise exception 'B-Form % not found or already authorized', p_bform_id using errcode = 'P0002';
  end if;

  update public.notifications
     set status = 'SENT', sent_at = now(),
         body = replace(body, 'You will receive another message when it is authorized for collection.',
                              'It is now ready for collection at your nearest NADRA office.')
   where related_table = 'bform'
     and related_id    = v_bform.bform_number
     and status        = 'QUEUED';

  return jsonb_build_object(
    'ok', true,
    'bform_id', v_bform.bform_id,
    'bform_number', v_bform.bform_number,
    'authorized_at', v_bform.authorized_at
  );
end$$;

grant execute on function public.authorize_bform_v2(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- reissue_bform_v2 — auth-aware
-- ---------------------------------------------------------------------------
create or replace function public.reissue_bform_v2(
  p_child_id uuid,
  p_reason   text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_officer_id   uuid;
  v_prev_version int;
  v_new_number   text;
  v_new_bform    public.bform;
  v_mother_phone text;
begin
  perform public.assert_officer();

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Reissue reason is required' using errcode = '22023';
  end if;

  v_officer_id := public.current_officer_id();
  if v_officer_id is null then
    select officer_id into v_officer_id from public.nadra_officer where employee_no = 'EMP-999999';
  end if;

  perform set_config('app.actor_type', 'NADRA_OFFICER', true);
  perform set_config('app.actor_id',   v_officer_id::text, true);

  select version into v_prev_version
    from public.bform where child_id = p_child_id and is_current = true
    for update;
  if v_prev_version is null then
    raise exception 'No current B-Form found for child %', p_child_id using errcode = 'P0002';
  end if;

  update public.bform set is_current = false
   where child_id = p_child_id and is_current = true;

  v_new_number := 'BF-' || to_char(now(), 'YYYY') || '-' ||
                  lpad(nextval('public.bform_seq')::text, 8, '0');

  insert into public.bform
    (bform_number, child_id, issued_by, version, is_current, reissue_reason, authorized_at)
  values
    (v_new_number, p_child_id, v_officer_id, v_prev_version + 1, true, p_reason, now())
  returning * into v_new_bform;

  select pg.contact_number into v_mother_phone
    from public.child_guardian cg
    join public.parent_guardian pg on pg.guardian_id = cg.guardian_id
   where cg.child_id = p_child_id and cg.relationship_type = 'MOTHER'
   limit 1;

  if v_mother_phone is not null then
    insert into public.notifications
      (recipient_type, recipient_contact, channel, body,
       status, related_table, related_id, sent_at)
    values
      ('PARENT', v_mother_phone, 'SMS',
       'Your child''s B-Form has been reissued as ' || v_new_number ||
       ' (reason: ' || p_reason || '). Ready for collection at your nearest NADRA office.',
       'SENT', 'bform', v_new_number, now());
  end if;

  return jsonb_build_object(
    'ok', true,
    'bform_id', v_new_bform.bform_id,
    'bform_number', v_new_bform.bform_number,
    'version', v_new_bform.version
  );
end$$;

grant execute on function public.reissue_bform_v2(uuid, text) to authenticated;
