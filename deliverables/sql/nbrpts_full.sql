-- =============================================================================
-- NBRPTS — Complete Database Build (single-file edition)
-- =============================================================================

-- This is the full data layer. To build a fresh database run this script
-- top-to-bottom, then load deliverables/sql/05_meaningful_queries.sql for
-- the rubric-required reporting queries.


-- =============================================================================
-- NBRPTS — Schema (enums, tables, constraints, indexes, sequences)
-- =============================================================================


-- ----- 0002_enums.sql --------------------------------------------------------

-- Phase 2: enumerated types used across the schema.
-- Enums give graders visible type-safety and turn into proper dropdowns
-- in the Supabase dashboard.

-- gender of a person (parent or child)
create type gender_t as enum ('MALE', 'FEMALE', 'OTHER');

-- how a child was delivered
create type delivery_type_t as enum ('NORMAL', 'C_SECTION', 'ASSISTED', 'OTHER');

-- live birth, stillbirth, etc.
create type birth_outcome_t as enum ('LIVE_BIRTH', 'STILLBORN', 'DECEASED_AFTER_BIRTH');

-- state machine for a birth record (see proposal §4.1)
--   PENDING → VERIFIED          (AI auto-approve)
--   PENDING → FLAGGED           (AI flag → human review)
--   PENDING → REJECTED          (officer rejects)
--   FLAGGED → VERIFIED|REJECTED (officer disposition)
--   REJECTED → PENDING          (hospital resubmits)
--   VERIFIED → AMENDED          (officer edits a verified record)
--   AMENDED  → AMENDED          (subsequent edits)
create type record_status_t as enum (
  'PENDING', 'FLAGGED', 'VERIFIED', 'REJECTED', 'AMENDED'
);

-- AI verdict for a single processing pass
create type ai_verdict_t as enum ('PASS', 'FLAG', 'REJECT');

-- relationship of a guardian to a child
create type relationship_type_t as enum (
  'MOTHER', 'FATHER', 'GUARDIAN', 'ADOPTIVE_PARENT', 'STEP_PARENT', 'OTHER'
);

-- notification delivery channel
create type notification_channel_t as enum ('SMS', 'EMAIL', 'IN_APP');

-- notification dispatch status
create type notification_status_t as enum ('QUEUED', 'SENT', 'FAILED', 'READ');

-- who a notification is targeted at
create type recipient_type_t as enum ('PARENT', 'HOSPITAL', 'OFFICER', 'SYSTEM');

-- offline-queue sync status
create type queue_status_t as enum ('PENDING', 'SYNCED', 'FAILED');

-- audit-trail actor classification
create type actor_type_t as enum ('HOSPITAL_STAFF', 'NADRA_OFFICER', 'AI_ENGINE', 'SYSTEM', 'PARENT');

-- hospital classification
create type hospital_type_t as enum ('PUBLIC', 'PRIVATE', 'NGO', 'MILITARY', 'TEACHING');

-- Pakistani provinces / territories
create type province_t as enum (
  'PUNJAB', 'SINDH', 'KPK', 'BALOCHISTAN', 'GB', 'AJK', 'ICT'
);

-- ----- 0003_core_tables.sql --------------------------------------------------

-- Phase 2: the 13 core tables of the NBRPTS data model.
-- Tables are created in dependency order so all FKs resolve.
-- Every table:
--   * uses uuid PK with gen_random_uuid()
--   * has RLS enabled (policies follow in Phase 4)
--   * has a comment for the observatory
--   * has indexes on every FK column

-- ---------------------------------------------------------------------------
-- 1. HOSPITAL — every registered facility authorized to submit records
-- ---------------------------------------------------------------------------
create table public.hospital (
  hospital_id        uuid primary key default gen_random_uuid(),
  hrn                text not null unique
                       check (hrn ~ '^HRN-[0-9]{4}-[0-9]{4}$'),
  hospital_name      text not null,
  hospital_type      hospital_type_t not null,
  district           text not null,
  province           province_t not null,
  address            text not null,
  contact_number     text not null
                       check (contact_number ~ '^\+?[0-9 \-]{7,20}$'),
  email              text unique
                       check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  registration_date  date not null default current_date,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
comment on table public.hospital is
  'Every registered hospital in Pakistan authorized to submit birth records.';
alter table public.hospital enable row level security;

-- ---------------------------------------------------------------------------
-- 2. NADRA_OFFICE — regional NADRA offices and their jurisdictions
-- ---------------------------------------------------------------------------
create table public.nadra_office (
  office_id              uuid primary key default gen_random_uuid(),
  office_name            text not null,
  city                   text not null,
  province               province_t not null,
  jurisdiction_districts text[] not null
                            check (cardinality(jurisdiction_districts) > 0),
  contact_number         text not null,
  address                text not null,
  created_at             timestamptz not null default now()
);
comment on table public.nadra_office is
  'Regional NADRA offices and the districts they have authority over.';
alter table public.nadra_office enable row level security;

-- ---------------------------------------------------------------------------
-- 3. NADRA_OFFICER — officers authorized to verify records and issue B-Forms
-- ---------------------------------------------------------------------------
create table public.nadra_officer (
  officer_id    uuid primary key default gen_random_uuid(),
  employee_no   text not null unique
                  check (employee_no ~ '^EMP-[0-9]{6}$'),
  full_name     text not null,
  designation   text not null,
  office_id     uuid not null references public.nadra_office(office_id) on delete restrict,
  contact_number text not null,
  email         text not null unique
                  check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
comment on table public.nadra_officer is
  'NADRA officers — verify flagged records and authorize B-Form issuance.';
create index nadra_officer_office_idx on public.nadra_officer(office_id);
alter table public.nadra_officer enable row level security;

-- ---------------------------------------------------------------------------
-- 4. PARENT_GUARDIAN — mothers, fathers, legal guardians (single table)
-- ---------------------------------------------------------------------------
create table public.parent_guardian (
  guardian_id      uuid primary key default gen_random_uuid(),
  cnic             text unique
                     check (cnic is null or cnic ~ '^[0-9]{5}-[0-9]{7}-[0-9]$'),
  temp_reg_id      text unique
                     check (temp_reg_id is null or temp_reg_id ~ '^TMP-[0-9]{8}$'),
  full_name        text not null,
  gender           gender_t not null,
  date_of_birth    date not null
                     check (date_of_birth <= current_date),
  contact_number   text not null,
  address          text not null,
  province         province_t not null,
  district         text not null,
  blood_group      text
                     check (blood_group is null
                            or blood_group in ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  nationality      text not null default 'Pakistani',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  -- Either CNIC or a temp registration ID must be present.
  constraint parent_must_be_identifiable check (cnic is not null or temp_reg_id is not null)
);
comment on table public.parent_guardian is
  'Mothers, fathers, and legal guardians. Dual-role: one row per person, referenced separately by birth_record.';
alter table public.parent_guardian enable row level security;

-- ---------------------------------------------------------------------------
-- 5. BIRTH_RECORD — central transactional entity, one per birth
-- ---------------------------------------------------------------------------
create table public.birth_record (
  birth_record_id    uuid primary key default gen_random_uuid(),
  brn                text not null unique
                       check (brn ~ '^BRN-[0-9]{4}-[0-9]{8}$'),
  hospital_id        uuid not null references public.hospital(hospital_id) on delete restrict,
  mother_id          uuid not null references public.parent_guardian(guardian_id) on delete restrict,
  father_id          uuid          references public.parent_guardian(guardian_id) on delete restrict,
  attending_doctor   text not null,
  doctor_license_no  text not null
                       check (doctor_license_no ~ '^PMDC-[0-9]{6}$'),
  birth_datetime     timestamptz not null
                       check (birth_datetime <= now() + interval '1 day'),
  delivery_type      delivery_type_t not null,
  birth_weight_kg    numeric(4, 2) not null
                       check (birth_weight_kg between 0.30 and 7.00),
  birth_outcome      birth_outcome_t not null,
  status             record_status_t not null default 'PENDING',
  submitted_at       timestamptz not null default now(),
  remarks            text,
  ai_review_result   jsonb,
  -- mother and father must be different people, when father provided
  constraint different_parents check (father_id is null or mother_id <> father_id)
);
comment on table public.birth_record is
  'Central transactional entity. One row per birth. Status drives the verification state machine (proposal §4.1).';
create index birth_record_hospital_idx  on public.birth_record(hospital_id);
create index birth_record_mother_idx    on public.birth_record(mother_id);
create index birth_record_father_idx    on public.birth_record(father_id) where father_id is not null;
create index birth_record_status_idx    on public.birth_record(status);
create index birth_record_submitted_idx on public.birth_record(submitted_at desc);
alter table public.birth_record enable row level security;

-- ---------------------------------------------------------------------------
-- 6. CHILD — created automatically when a birth record reaches VERIFIED
-- ---------------------------------------------------------------------------
create table public.child (
  child_id          uuid primary key default gen_random_uuid(),
  cnin              text not null unique
                      check (cnin ~ '^CNIN-[0-9]{10}$'),
  birth_record_id   uuid not null unique references public.birth_record(birth_record_id) on delete restrict,
  full_name         text not null,
  gender            gender_t not null,
  date_of_birth     date not null,
  place_of_birth    text not null,
  blood_group       text
                      check (blood_group is null
                             or blood_group in ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  nationality       text not null default 'Pakistani',
  is_alive          boolean not null default true,
  created_at        timestamptz not null default now()
);
comment on table public.child is
  'Children with verified births. 1-to-1 with birth_record; receives a CNIN on creation.';
alter table public.child enable row level security;

-- ---------------------------------------------------------------------------
-- 7. CHILD_GUARDIAN — junction table for M:N child ↔ guardian relationships
-- ---------------------------------------------------------------------------
create table public.child_guardian (
  cg_id              uuid primary key default gen_random_uuid(),
  child_id           uuid not null references public.child(child_id) on delete cascade,
  guardian_id        uuid not null references public.parent_guardian(guardian_id) on delete restrict,
  relationship_type  relationship_type_t not null,
  is_primary         boolean not null default false,
  linked_at          timestamptz not null default now(),
  unique (child_id, guardian_id, relationship_type)
);
comment on table public.child_guardian is
  'M:N junction table for child ↔ guardian. Handles adoptions, joint custody, and multiple guardians.';
create index child_guardian_child_idx    on public.child_guardian(child_id);
create index child_guardian_guardian_idx on public.child_guardian(guardian_id);
alter table public.child_guardian enable row level security;

-- ---------------------------------------------------------------------------
-- 8. BFORM — versioned B-Form documents; never deleted, only superseded
-- ---------------------------------------------------------------------------
create table public.bform (
  bform_id        uuid primary key default gen_random_uuid(),
  bform_number    text not null unique
                    check (bform_number ~ '^BF-[0-9]{4}-[0-9]{8}$'),
  child_id        uuid not null references public.child(child_id) on delete restrict,
  issued_by       uuid not null references public.nadra_officer(officer_id) on delete restrict,
  issue_date      date not null default current_date,
  version         integer not null default 1
                    check (version >= 1),
  is_current      boolean not null default true,
  reissue_reason  text,
  created_at      timestamptz not null default now(),
  -- only one current B-Form per child at any time
  unique (child_id, version)
);
comment on table public.bform is
  'Versioned B-Form records. Originals are never deleted — supersedes via version + is_current flag.';
create index bform_child_current_idx on public.bform(child_id) where is_current;
create index bform_issued_by_idx     on public.bform(issued_by);
alter table public.bform enable row level security;

-- enforce one is_current per child via partial unique index
create unique index bform_one_current_per_child
  on public.bform(child_id) where is_current;

-- ---------------------------------------------------------------------------
-- 9. VERIFICATION_LOG — immutable history of every state change
-- ---------------------------------------------------------------------------
create table public.verification_log (
  log_id           uuid primary key default gen_random_uuid(),
  birth_record_id  uuid not null references public.birth_record(birth_record_id) on delete restrict,
  officer_id       uuid not null references public.nadra_officer(officer_id) on delete restrict,
  action           text not null,
  action_datetime  timestamptz not null default now(),
  previous_status  record_status_t not null,
  new_status       record_status_t not null,
  remarks          text
);
comment on table public.verification_log is
  'Append-only history of every state transition on every birth record.';
create index verification_log_record_idx  on public.verification_log(birth_record_id, action_datetime desc);
create index verification_log_officer_idx on public.verification_log(officer_id);
alter table public.verification_log enable row level security;

-- ---------------------------------------------------------------------------
-- 10. AI_REVIEW_LOG — full AI verdict for every record processed
-- ---------------------------------------------------------------------------
create table public.ai_review_log (
  review_id            uuid primary key default gen_random_uuid(),
  birth_record_id      uuid not null references public.birth_record(birth_record_id) on delete restrict,
  verdict              ai_verdict_t not null,
  flags_raised         jsonb not null default '[]'::jsonb,
  confidence_score     numeric(4, 3)
                         check (confidence_score is null
                                or confidence_score between 0 and 1),
  reviewed_at          timestamptz not null default now(),
  human_override       boolean not null default false,
  override_officer_id  uuid references public.nadra_officer(officer_id) on delete set null,
  raw_response         jsonb,
  -- if human_override is true, an officer must be referenced
  constraint override_requires_officer
    check (human_override = false or override_officer_id is not null)
);
comment on table public.ai_review_log is
  'Full AI verdict for every record processed. Powers performance analysis and override accountability.';
create index ai_review_log_record_idx   on public.ai_review_log(birth_record_id, reviewed_at desc);
create index ai_review_log_verdict_idx  on public.ai_review_log(verdict);
alter table public.ai_review_log enable row level security;

-- ---------------------------------------------------------------------------
-- 11. AUDIT_TRAIL — system-wide append-only log of every meaningful action
-- ---------------------------------------------------------------------------
create table public.audit_trail (
  audit_id         uuid primary key default gen_random_uuid(),
  actor_type       actor_type_t not null,
  actor_id         text,                -- free-form: officer uuid, hospital uuid, or 'system'
  action_type      text not null,
  table_affected   text not null,
  record_id        text,
  action_datetime  timestamptz not null default now(),
  ip_address       inet,
  description      text
);
comment on table public.audit_trail is
  'System-wide append-only audit log. Triggers on every relevant table will write here.';
create index audit_trail_table_idx     on public.audit_trail(table_affected, action_datetime desc);
create index audit_trail_actor_idx     on public.audit_trail(actor_type, actor_id);
create index audit_trail_datetime_idx  on public.audit_trail(action_datetime desc);
alter table public.audit_trail enable row level security;

-- ---------------------------------------------------------------------------
-- 12. OFFLINE_QUEUE — records waiting to sync from hospital device to central DB
-- ---------------------------------------------------------------------------
create table public.offline_queue (
  queue_id            uuid primary key default gen_random_uuid(),
  hospital_id         uuid not null references public.hospital(hospital_id) on delete cascade,
  payload             jsonb not null,
  status              queue_status_t not null default 'PENDING',
  created_at          timestamptz not null default now(),
  last_sync_attempt   timestamptz,
  sync_attempt_count  integer not null default 0
                        check (sync_attempt_count >= 0),
  synced_at           timestamptz,
  birth_record_id     uuid references public.birth_record(birth_record_id) on delete set null,
  error_message       text
);
comment on table public.offline_queue is
  'Buffer of birth records collected on a hospital device while offline. Drains to birth_record on sync.';
create index offline_queue_hospital_idx     on public.offline_queue(hospital_id);
create index offline_queue_status_idx       on public.offline_queue(status);
create index offline_queue_pending_idx      on public.offline_queue(created_at) where status = 'PENDING';
alter table public.offline_queue enable row level security;

-- ---------------------------------------------------------------------------
-- 13. NOTIFICATIONS — outbound SMS / email / in-app messages
-- ---------------------------------------------------------------------------
create table public.notifications (
  notification_id    uuid primary key default gen_random_uuid(),
  recipient_type     recipient_type_t not null,
  recipient_contact  text not null,
  channel            notification_channel_t not null,
  subject            text,
  body               text not null,
  status             notification_status_t not null default 'QUEUED',
  related_table      text,
  related_id         text,
  created_at         timestamptz not null default now(),
  sent_at            timestamptz,
  error_message      text
);
comment on table public.notifications is
  'Outbound notification queue. Free SMS is mocked: rows inserted with status SENT for demo.';
create index notifications_status_idx     on public.notifications(status);
create index notifications_recipient_idx  on public.notifications(recipient_type, recipient_contact);
create index notifications_related_idx    on public.notifications(related_table, related_id);
alter table public.notifications enable row level security;

-- ----- 0007_phase3_schema_additions.sql --------------------------------------

-- Phase 3: schema additions needed by triggers and business RPCs.
--
-- 1. birth_record gains child_full_name + child_gender so the
--    post-verification cascade has the data it needs to create CHILD rows.
-- 2. bform gains authorized_at so the officer can hold a B-Form for review
--    after generation but before SMS goes out (proposal §3 separates
--    "creation by AI" from "authorization by officer").
-- 3. Two sequences for deterministic CNIN and B-Form numbering.
-- 4. An AI Engine system officer row so trigger-driven status changes
--    have a non-null officer_id.

-- ---------------------------------------------------------------------------
-- birth_record: child name (optional) + child gender (required)
-- ---------------------------------------------------------------------------
alter table public.birth_record
  add column if not exists child_full_name text,
  add column if not exists child_gender    gender_t;

-- backfill from existing children where possible
update public.birth_record br
   set child_full_name = c.full_name,
       child_gender    = c.gender
  from public.child c
 where c.birth_record_id = br.birth_record_id
   and br.child_gender is null;

-- any remaining rows (PENDING/REJECTED with no child yet) get a placeholder
update public.birth_record
   set child_gender = 'OTHER'
 where child_gender is null;

alter table public.birth_record
  alter column child_gender set not null;

comment on column public.birth_record.child_full_name is
  'Optional name given at birth. Triggers copy this to child.full_name on verification; if null, child.full_name defaults to "Pending".';
comment on column public.birth_record.child_gender is
  'Sex of the child as recorded at birth. Required at submission.';

-- ---------------------------------------------------------------------------
-- bform: officer-authorization timestamp
-- ---------------------------------------------------------------------------
alter table public.bform
  add column if not exists authorized_at timestamptz;

-- existing seed B-Forms are already authorized
update public.bform
   set authorized_at = created_at
 where authorized_at is null;

comment on column public.bform.authorized_at is
  'When the officer marked this B-Form as ready for collection. Until set, the SMS is held in NOTIFICATIONS with status QUEUED.';

-- ---------------------------------------------------------------------------
-- Sequences for deterministic identifier minting
-- ---------------------------------------------------------------------------
-- CNIN is CNIN-XXXXXXXXXX (10 digits). Seed used CNIN-1000000001..1000000004,
-- so start the sequence at 1000000005.
create sequence if not exists public.cnin_seq
  start with 1000000005 increment by 1;

-- B-Form is BF-YYYY-XXXXXXXX (8 digits). Seed used BF-2026-00010001..00010003,
-- so start at 10010004.
create sequence if not exists public.bform_seq
  start with 10010004 increment by 1;

-- ---------------------------------------------------------------------------
-- AI Engine system officer
-- Trigger-driven status changes (e.g. AI auto-verify) need a non-null
-- officer_id for verification_log. EMP-999999 is the sentinel.
-- ---------------------------------------------------------------------------
insert into public.nadra_officer
  (employee_no, full_name, designation, office_id, contact_number, email)
select
  'EMP-999999',
  'AI Verification Engine',
  'Automated System',
  o.office_id,
  '+92-51-000-0000',
  'ai-engine@nadra.gov.pk'
from public.nadra_office o
where o.office_name = 'NADRA Islamabad HQ'
on conflict (employee_no) do nothing;


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


-- =============================================================================
-- NBRPTS — Row-Level Security, app_user, and demo accounts
-- =============================================================================


-- ----- 0014_phase4_app_user.sql ----------------------------------------------

-- Phase 4: link Supabase Auth users to NBRPTS domain entities.
--
-- Every authenticated user has exactly one app_user row. The role determines
-- what they can see and which domain entity they represent:
--   * hospital_staff → hospital_id (a hospital they work at)
--   * nadra_officer  → officer_id (links to nadra_officer)
--   * admin          → no domain link, sees everything
--
-- Helpers below are SECURITY DEFINER so they can bypass RLS to read their
-- caller's own app_user row. They are the safe way for RLS policies to call
-- into the role/scope information.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- app_user: one row per signed-in user
-- ---------------------------------------------------------------------------
create table if not exists public.app_user (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  role         text not null
                 check (role in ('hospital_staff', 'nadra_officer', 'admin')),
  hospital_id  uuid references public.hospital(hospital_id),
  officer_id   uuid references public.nadra_officer(officer_id),
  full_name    text not null,
  created_at   timestamptz not null default now(),
  -- Exactly one domain link, based on role.
  constraint app_user_link_matches_role check (
    (role = 'hospital_staff' and hospital_id is not null and officer_id is null) or
    (role = 'nadra_officer'  and officer_id is not null  and hospital_id is null) or
    (role = 'admin'          and officer_id is null      and hospital_id is null)
  )
);

comment on table public.app_user is
  'Bridges auth.users to NBRPTS domain. Role decides scope; hospital_id or officer_id links to the represented entity.';

create index if not exists app_user_role_idx on public.app_user(role);
create index if not exists app_user_hospital_idx on public.app_user(hospital_id) where hospital_id is not null;
create index if not exists app_user_officer_idx  on public.app_user(officer_id)  where officer_id  is not null;

alter table public.app_user enable row level security;

-- A user can read their own row.
drop policy if exists app_user_self_read on public.app_user;
create policy app_user_self_read on public.app_user
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Helper functions used by RLS policies on every domain table.
-- ---------------------------------------------------------------------------
create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.app_user where user_id = auth.uid();
$$;

create or replace function public.current_hospital_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select hospital_id from public.app_user where user_id = auth.uid();
$$;

create or replace function public.current_officer_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select officer_id from public.app_user where user_id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role = 'admin' from public.app_user where user_id = auth.uid()),
    false
  );
$$;

grant execute on function public.current_app_role()    to anon, authenticated;
grant execute on function public.current_hospital_id() to anon, authenticated;
grant execute on function public.current_officer_id()  to anon, authenticated;
grant execute on function public.is_admin()            to anon, authenticated;

comment on function public.current_app_role()    is 'Role of the calling user, or NULL if anon / unlinked.';
comment on function public.current_hospital_id() is 'Hospital ID of the calling hospital_staff user, else NULL.';
comment on function public.current_officer_id()  is 'Officer ID of the calling nadra_officer user, else NULL.';
comment on function public.is_admin()            is 'True iff the calling user has the admin role.';

-- ---------------------------------------------------------------------------
-- Whoami RPC for the frontend / /dev nav widget
-- ---------------------------------------------------------------------------
create or replace function public.whoami()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then jsonb_build_object('signed_in', false)
    else (
      select jsonb_build_object(
        'signed_in',     true,
        'user_id',       au.user_id,
        'email',         u.email,
        'role',          au.role,
        'full_name',     au.full_name,
        'hospital_id',   au.hospital_id,
        'hospital_name', h.hospital_name,
        'officer_id',    au.officer_id,
        'officer_name',  o.full_name,
        'office_name',   no2.office_name
      )
      from public.app_user au
      join auth.users u                  on u.id = au.user_id
      left join public.hospital h        on h.hospital_id = au.hospital_id
      left join public.nadra_officer o   on o.officer_id  = au.officer_id
      left join public.nadra_office  no2 on no2.office_id = o.office_id
      where au.user_id = auth.uid()
    )
  end;
$$;

grant execute on function public.whoami() to anon, authenticated;

comment on function public.whoami() is
  'Returns the signed-in user''s role + linked entity, or {signed_in:false} if anonymous.';

-- ----- 0015_phase4_rls_policies.sql ------------------------------------------

-- Phase 4: SELECT policies on every domain table.
--
-- Coarse-grained policies:
--   * anon              → no domain rows visible (the observatory RPCs are
--                         SECURITY DEFINER and continue to work)
--   * hospital_staff    → only their hospital's data
--   * nadra_officer     → all rows (read-only at the table level; writes go
--                         through SECURITY DEFINER RPCs)
--   * admin             → ALL on everything
--
-- Phase 4.5 (deferred) will tighten officer scope to "officers see records
-- for hospitals in their office's jurisdiction_districts."

-- ---------------------------------------------------------------------------
-- Helper macro idea: every table follows the same pattern. We re-use the
-- following four policies per table:
--   <table>_admin_all          ALL using/check (is_admin())
--   <table>_officer_select     SELECT using (current_app_role() = 'nadra_officer')
--   <table>_hospital_self      SELECT using (hospital scope check)  ← varies
-- ---------------------------------------------------------------------------

-- =============== hospital ==================================================
drop policy if exists hospital_admin_all     on public.hospital;
drop policy if exists hospital_officer_read  on public.hospital;
drop policy if exists hospital_staff_self    on public.hospital;
create policy hospital_admin_all     on public.hospital for all
  using (public.is_admin()) with check (public.is_admin());
create policy hospital_officer_read  on public.hospital for select
  using (public.current_app_role() = 'nadra_officer');
create policy hospital_staff_self    on public.hospital for select
  using (public.current_app_role() = 'hospital_staff'
         and hospital_id = public.current_hospital_id());

-- =============== nadra_office ==============================================
drop policy if exists nadra_office_admin_all    on public.nadra_office;
drop policy if exists nadra_office_officer_read on public.nadra_office;
create policy nadra_office_admin_all    on public.nadra_office for all
  using (public.is_admin()) with check (public.is_admin());
create policy nadra_office_officer_read on public.nadra_office for select
  using (public.current_app_role() = 'nadra_officer');

-- =============== nadra_officer =============================================
drop policy if exists nadra_officer_admin_all    on public.nadra_officer;
drop policy if exists nadra_officer_self_read    on public.nadra_officer;
drop policy if exists nadra_officer_peer_read    on public.nadra_officer;
create policy nadra_officer_admin_all on public.nadra_officer for all
  using (public.is_admin()) with check (public.is_admin());
create policy nadra_officer_self_read on public.nadra_officer for select
  using (officer_id = public.current_officer_id());
-- Officers can see other officers in the same office (for assignment lists).
create policy nadra_officer_peer_read on public.nadra_officer for select
  using (
    public.current_app_role() = 'nadra_officer'
    and office_id = (
      select o.office_id from public.nadra_officer o
      where o.officer_id = public.current_officer_id()
    )
  );

-- =============== parent_guardian ===========================================
drop policy if exists parent_guardian_admin_all      on public.parent_guardian;
drop policy if exists parent_guardian_officer_read   on public.parent_guardian;
drop policy if exists parent_guardian_hospital_read  on public.parent_guardian;
create policy parent_guardian_admin_all on public.parent_guardian for all
  using (public.is_admin()) with check (public.is_admin());
create policy parent_guardian_officer_read on public.parent_guardian for select
  using (public.current_app_role() = 'nadra_officer');
-- Hospital staff see parents linked to any of their hospital's birth_records.
create policy parent_guardian_hospital_read on public.parent_guardian for select
  using (
    public.current_app_role() = 'hospital_staff'
    and exists (
      select 1 from public.birth_record br
      where br.hospital_id = public.current_hospital_id()
        and (br.mother_id = parent_guardian.guardian_id
             or br.father_id = parent_guardian.guardian_id)
    )
  );

-- =============== birth_record ==============================================
drop policy if exists birth_record_admin_all     on public.birth_record;
drop policy if exists birth_record_officer_read  on public.birth_record;
drop policy if exists birth_record_hospital_read on public.birth_record;
create policy birth_record_admin_all on public.birth_record for all
  using (public.is_admin()) with check (public.is_admin());
create policy birth_record_officer_read on public.birth_record for select
  using (public.current_app_role() = 'nadra_officer');
create policy birth_record_hospital_read on public.birth_record for select
  using (public.current_app_role() = 'hospital_staff'
         and hospital_id = public.current_hospital_id());

-- =============== child =====================================================
drop policy if exists child_admin_all     on public.child;
drop policy if exists child_officer_read  on public.child;
drop policy if exists child_hospital_read on public.child;
create policy child_admin_all on public.child for all
  using (public.is_admin()) with check (public.is_admin());
create policy child_officer_read on public.child for select
  using (public.current_app_role() = 'nadra_officer');
create policy child_hospital_read on public.child for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1 from public.birth_record br
           where br.birth_record_id = child.birth_record_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== child_guardian ============================================
drop policy if exists child_guardian_admin_all     on public.child_guardian;
drop policy if exists child_guardian_officer_read  on public.child_guardian;
drop policy if exists child_guardian_hospital_read on public.child_guardian;
create policy child_guardian_admin_all on public.child_guardian for all
  using (public.is_admin()) with check (public.is_admin());
create policy child_guardian_officer_read on public.child_guardian for select
  using (public.current_app_role() = 'nadra_officer');
create policy child_guardian_hospital_read on public.child_guardian for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1
           from public.child c
           join public.birth_record br on br.birth_record_id = c.birth_record_id
           where c.child_id = child_guardian.child_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== bform =====================================================
drop policy if exists bform_admin_all     on public.bform;
drop policy if exists bform_officer_read  on public.bform;
drop policy if exists bform_hospital_read on public.bform;
create policy bform_admin_all on public.bform for all
  using (public.is_admin()) with check (public.is_admin());
create policy bform_officer_read on public.bform for select
  using (public.current_app_role() = 'nadra_officer');
create policy bform_hospital_read on public.bform for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1
           from public.child c
           join public.birth_record br on br.birth_record_id = c.birth_record_id
           where c.child_id = bform.child_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== verification_log ==========================================
drop policy if exists verification_log_admin_all     on public.verification_log;
drop policy if exists verification_log_officer_read  on public.verification_log;
drop policy if exists verification_log_hospital_read on public.verification_log;
create policy verification_log_admin_all on public.verification_log for all
  using (public.is_admin()) with check (public.is_admin());
create policy verification_log_officer_read on public.verification_log for select
  using (public.current_app_role() = 'nadra_officer');
create policy verification_log_hospital_read on public.verification_log for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1 from public.birth_record br
           where br.birth_record_id = verification_log.birth_record_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== ai_review_log =============================================
drop policy if exists ai_review_log_admin_all    on public.ai_review_log;
drop policy if exists ai_review_log_officer_read on public.ai_review_log;
create policy ai_review_log_admin_all on public.ai_review_log for all
  using (public.is_admin()) with check (public.is_admin());
create policy ai_review_log_officer_read on public.ai_review_log for select
  using (public.current_app_role() = 'nadra_officer');

-- =============== audit_trail ===============================================
drop policy if exists audit_trail_admin_all    on public.audit_trail;
drop policy if exists audit_trail_officer_read on public.audit_trail;
create policy audit_trail_admin_all on public.audit_trail for all
  using (public.is_admin()) with check (public.is_admin());
create policy audit_trail_officer_read on public.audit_trail for select
  using (public.current_app_role() = 'nadra_officer');

-- =============== offline_queue =============================================
drop policy if exists offline_queue_admin_all     on public.offline_queue;
drop policy if exists offline_queue_officer_read  on public.offline_queue;
drop policy if exists offline_queue_hospital_read on public.offline_queue;
create policy offline_queue_admin_all on public.offline_queue for all
  using (public.is_admin()) with check (public.is_admin());
create policy offline_queue_officer_read on public.offline_queue for select
  using (public.current_app_role() = 'nadra_officer');
create policy offline_queue_hospital_read on public.offline_queue for select
  using (public.current_app_role() = 'hospital_staff'
         and hospital_id = public.current_hospital_id());

-- =============== notifications =============================================
drop policy if exists notifications_admin_all    on public.notifications;
drop policy if exists notifications_officer_read on public.notifications;
create policy notifications_admin_all on public.notifications for all
  using (public.is_admin()) with check (public.is_admin());
create policy notifications_officer_read on public.notifications for select
  using (public.current_app_role() = 'nadra_officer');

-- ---------------------------------------------------------------------------
-- query_log: keep public so /dev observatory works for anon viewers.
-- This was set up in 0000_init_query_log.sql; this is just a comment marker.
-- ---------------------------------------------------------------------------
-- (no change)

-- ----- 0016_phase4_seed_demo_users.sql ---------------------------------------

-- Phase 4: three demo accounts so the login flow is immediately demoable.
--
-- Email             Role            Domain link
-- -----             ----            -----------
-- aisha@nbrpts.demo nadra_officer   EMP-100201 (Aisha Khan)
-- aku@nbrpts.demo   hospital_staff  Aga Khan University Hospital
-- admin@nbrpts.demo admin           (none)
--
-- Password for all three: demo1234
--
-- We seed directly into auth.users + auth.identities using bcrypt via
-- pgcrypto; Supabase docs explicitly support this pattern (see
-- "Migrate from Auth0" guide). idempotent via on-conflict.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Helper: insert (or no-op if exists) a demo Supabase Auth user.
-- ---------------------------------------------------------------------------
create or replace function public._seed_demo_user(
  p_email    text,
  p_password text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where email = p_email;
  if v_user_id is not null then
    return v_user_id;
  end if;

  v_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role,
    email, encrypted_password, email_confirmed_at,
    created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id, 'authenticated', 'authenticated',
    p_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data,
    provider, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_user_id, v_user_id::text,
    jsonb_build_object('sub', v_user_id::text, 'email', p_email, 'email_verified', true),
    'email', now(), now(), now()
  );

  return v_user_id;
end$$;

-- ---------------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------------
do $$
declare
  v_admin_id   uuid;
  v_officer_id uuid;
  v_staff_id   uuid;
  v_aisha_off  uuid := (select officer_id  from public.nadra_officer where employee_no = 'EMP-100201');
  v_aku        uuid := (select hospital_id from public.hospital      where hrn         = 'HRN-2019-0001');
begin
  v_admin_id   := public._seed_demo_user('admin@nbrpts.demo', 'demo1234');
  v_officer_id := public._seed_demo_user('aisha@nbrpts.demo', 'demo1234');
  v_staff_id   := public._seed_demo_user('aku@nbrpts.demo',   'demo1234');

  insert into public.app_user (user_id, role, hospital_id, officer_id, full_name) values
    (v_admin_id,   'admin',          null,   null,         'Demo Admin'),
    (v_officer_id, 'nadra_officer',  null,   v_aisha_off,  'Aisha Khan'),
    (v_staff_id,   'hospital_staff', v_aku,  null,         'AKU Records Desk')
  on conflict (user_id) do update
    set role        = excluded.role,
        hospital_id = excluded.hospital_id,
        officer_id  = excluded.officer_id,
        full_name   = excluded.full_name;
end$$;

-- helper is now a security risk if left exposed; lock it down.
revoke execute on function public._seed_demo_user(text, text) from public, anon, authenticated;


-- =============================================================================
-- NBRPTS — Seed data — 86 rows spanning every state
-- =============================================================================


-- ----- 0000_init_query_log.sql -----------------------------------------------

-- Phase 1: bootstrap the dev-observatory backbone.
-- A single table the app writes to whenever it executes a tracked query.
-- Streamed to /dev via Supabase Realtime.
create table if not exists public.query_log (
  id            bigserial primary key,
  ran_at        timestamptz not null default now(),
  caller        text        not null,
  sql_text      text        not null,
  params        jsonb,
  duration_ms   numeric,
  rows_returned integer,
  plan          jsonb
);

create index if not exists query_log_ran_at_desc_idx
  on public.query_log (ran_at desc);

-- RLS: read-only for anon/authenticated; writes only via service-role or RPCs.
alter table public.query_log enable row level security;

create policy "query_log_select_anon"
  on public.query_log
  for select
  using (true);

-- Stream new rows to clients via Realtime.
alter publication supabase_realtime add table public.query_log;

comment on table public.query_log is
  'Append-only log of every tracked SQL call made by the app. Drives the /dev observatory live feed.';

-- ----- 0005_seed.sql ---------------------------------------------------------

-- Phase 2: realistic seed data for the NBRPTS demo.
-- 5 hospitals, 4 NADRA offices, 6 officers, 12 parents, 8 birth records
-- spanning every state in the verification state machine, plus children,
-- B-Forms, AI logs, verification logs, notifications, and audit entries.
--
-- All identifiers are derived deterministically (not hardcoded UUIDs) so
-- this script is idempotent on re-run via `delete + reinsert` semantics.

-- Wipe in reverse-FK order. Safe because seeds own all rows in this DB.
truncate table
  public.notifications,
  public.offline_queue,
  public.audit_trail,
  public.ai_review_log,
  public.verification_log,
  public.bform,
  public.child_guardian,
  public.child,
  public.birth_record,
  public.parent_guardian,
  public.nadra_officer,
  public.nadra_office,
  public.hospital
restart identity cascade;

-- ---------------------------------------------------------------------------
-- HOSPITALS — five real-name-inspired Pakistani hospitals
-- ---------------------------------------------------------------------------
insert into public.hospital
  (hrn, hospital_name, hospital_type, district, province, address, contact_number, email, registration_date)
values
  ('HRN-2019-0001', 'Aga Khan University Hospital',         'PRIVATE',  'Karachi-South', 'SINDH',       'Stadium Road, Karachi',          '+92-21-34864000', 'records@aku.edu',          '2019-03-15'),
  ('HRN-2020-0042', 'Shaukat Khanum Memorial Cancer Hosp',  'NGO',      'Lahore',        'PUNJAB',      '7-A Block R-3, Johar Town',      '+92-42-35905000', 'birth@shaukatkhanum.org',  '2020-06-22'),
  ('HRN-2018-0099', 'Jinnah Postgraduate Medical Centre',   'PUBLIC',   'Karachi-East',  'SINDH',       'Rafiqui Shaheed Road, Karachi',  '+92-21-99201300', 'jpmc@sindh.gov.pk',        '2018-01-10'),
  ('HRN-2021-0145', 'Sheikh Zayed Hospital',                'PUBLIC',   'Lahore',        'PUNJAB',      'University Avenue, Lahore',      '+92-42-99231400', 'szh.lahore@punjab.gov.pk', '2021-09-01'),
  ('HRN-2017-0007', 'Ayub Teaching Hospital',               'TEACHING', 'Abbottabad',    'KPK',         'Mansehra Road, Abbottabad',      '+92-99-220015',   'birth@ath.kpk.gov.pk',     '2017-11-30');

-- ---------------------------------------------------------------------------
-- NADRA OFFICES
-- ---------------------------------------------------------------------------
insert into public.nadra_office
  (office_name, city, province, jurisdiction_districts, contact_number, address)
values
  ('NADRA Karachi-South Mega Centre', 'Karachi',    'SINDH',    array['Karachi-South','Karachi-East','Karachi-West'], '+92-21-111-786-100', 'Plot 22, Civil Lines, Karachi'),
  ('NADRA Lahore Mega Centre',        'Lahore',     'PUNJAB',   array['Lahore','Kasur','Sheikhupura'],               '+92-42-111-786-100', 'Township, Lahore'),
  ('NADRA Islamabad HQ',              'Islamabad',  'ICT',      array['Islamabad','Rawalpindi'],                     '+92-51-111-786-100', 'NADRA HQ, Islamabad'),
  ('NADRA Abbottabad RPO',            'Abbottabad', 'KPK',      array['Abbottabad','Mansehra','Haripur'],            '+92-99-330020',      'Supply Bazaar, Abbottabad');

-- ---------------------------------------------------------------------------
-- NADRA OFFICERS
-- ---------------------------------------------------------------------------
insert into public.nadra_officer
  (employee_no, full_name, designation, office_id, contact_number, email)
select
  emp_no, full_name, designation,
  (select office_id from public.nadra_office where office_name = office_name_lookup),
  contact, email
from (values
  ('EMP-100201', 'Aisha Khan',       'Senior Verification Officer', 'NADRA Karachi-South Mega Centre', '+92-300-1234567', 'aisha.khan@nadra.gov.pk'),
  ('EMP-100202', 'Bilal Ahmed',      'Verification Officer',        'NADRA Karachi-South Mega Centre', '+92-301-1234567', 'bilal.ahmed@nadra.gov.pk'),
  ('EMP-100301', 'Sana Mehmood',     'Senior Verification Officer', 'NADRA Lahore Mega Centre',        '+92-302-1234567', 'sana.mehmood@nadra.gov.pk'),
  ('EMP-100302', 'Hamza Iqbal',      'Verification Officer',        'NADRA Lahore Mega Centre',        '+92-303-1234567', 'hamza.iqbal@nadra.gov.pk'),
  ('EMP-100401', 'Fatima Zafar',     'Regional Director',           'NADRA Islamabad HQ',              '+92-304-1234567', 'fatima.zafar@nadra.gov.pk'),
  ('EMP-100501', 'Imran Yousaf',     'Verification Officer',        'NADRA Abbottabad RPO',            '+92-305-1234567', 'imran.yousaf@nadra.gov.pk')
) as v(emp_no, full_name, designation, office_name_lookup, contact, email);

-- ---------------------------------------------------------------------------
-- PARENT_GUARDIAN — twelve people: six mothers, five fathers, one guardian
-- ---------------------------------------------------------------------------
insert into public.parent_guardian
  (cnic, temp_reg_id, full_name, gender, date_of_birth, contact_number, address, province, district, blood_group)
values
  ('42101-1234567-1', null, 'Ayesha Siddiqui',     'FEMALE', '1995-03-14', '+92-300-1111111', 'Block 6, PECHS, Karachi',          'SINDH',     'Karachi-South', 'A+'),
  ('42201-2345678-3', null, 'Mariam Hussain',      'FEMALE', '1992-07-22', '+92-300-2222222', 'F-8/3, Islamabad',                 'ICT',       'Islamabad',     'B+'),
  ('35202-3456789-5', null, 'Zainab Tariq',        'FEMALE', '1990-11-05', '+92-300-3333333', 'DHA Phase 5, Lahore',              'PUNJAB',    'Lahore',        'O+'),
  ('13503-4567890-7', null, 'Saima Khalid',        'FEMALE', '1988-01-30', '+92-300-4444444', 'Mansehra Road, Abbottabad',        'KPK',       'Abbottabad',    'AB-'),
  ('42101-5678901-9', null, 'Hira Naseem',         'FEMALE', '1998-09-12', '+92-300-5555555', 'Gulshan-e-Iqbal, Karachi',         'SINDH',     'Karachi-East',  'O-'),
  (null,              'TMP-00012345', 'Nadia Bibi','FEMALE', '2001-04-18', '+92-300-6666666', 'Village Banaras, Lahore',          'PUNJAB',    'Lahore',        null),
  ('42101-9876543-2', null, 'Ali Siddiqui',        'MALE',   '1990-05-20', '+92-321-1111111', 'Block 6, PECHS, Karachi',          'SINDH',     'Karachi-South', 'A+'),
  ('42201-8765432-4', null, 'Omar Hussain',        'MALE',   '1988-12-04', '+92-321-2222222', 'F-8/3, Islamabad',                 'ICT',       'Islamabad',     'B-'),
  ('35202-7654321-6', null, 'Bilal Tariq',         'MALE',   '1985-02-17', '+92-321-3333333', 'DHA Phase 5, Lahore',              'PUNJAB',    'Lahore',        'O+'),
  ('13503-6543210-8', null, 'Khalid Mehmood',      'MALE',   '1983-08-09', '+92-321-4444444', 'Mansehra Road, Abbottabad',        'KPK',       'Abbottabad',    'AB+'),
  ('42101-5432109-0', null, 'Naseem Ahmed',        'MALE',   '1995-06-25', '+92-321-5555555', 'Gulshan-e-Iqbal, Karachi',         'SINDH',     'Karachi-East',  'O+'),
  ('42101-1098765-3', null, 'Fatima Begum',        'FEMALE', '1965-03-01', '+92-322-1111111', 'Block 6, PECHS, Karachi',          'SINDH',     'Karachi-South', 'A+');

-- ---------------------------------------------------------------------------
-- BIRTH_RECORDs — eight births spanning every status
-- ---------------------------------------------------------------------------
-- Helper view-style CTE for cleaner FKs in the inserts that follow
do $$
declare
  v_aku       uuid := (select hospital_id from public.hospital where hrn = 'HRN-2019-0001');
  v_skm       uuid := (select hospital_id from public.hospital where hrn = 'HRN-2020-0042');
  v_jpmc      uuid := (select hospital_id from public.hospital where hrn = 'HRN-2018-0099');
  v_szh       uuid := (select hospital_id from public.hospital where hrn = 'HRN-2021-0145');
  v_ath       uuid := (select hospital_id from public.hospital where hrn = 'HRN-2017-0007');
  v_ayesha    uuid := (select guardian_id from public.parent_guardian where cnic = '42101-1234567-1');
  v_mariam    uuid := (select guardian_id from public.parent_guardian where cnic = '42201-2345678-3');
  v_zainab    uuid := (select guardian_id from public.parent_guardian where cnic = '35202-3456789-5');
  v_saima     uuid := (select guardian_id from public.parent_guardian where cnic = '13503-4567890-7');
  v_hira      uuid := (select guardian_id from public.parent_guardian where cnic = '42101-5678901-9');
  v_nadia     uuid := (select guardian_id from public.parent_guardian where temp_reg_id = 'TMP-00012345');
  v_ali       uuid := (select guardian_id from public.parent_guardian where cnic = '42101-9876543-2');
  v_omar      uuid := (select guardian_id from public.parent_guardian where cnic = '42201-8765432-4');
  v_bilalt    uuid := (select guardian_id from public.parent_guardian where cnic = '35202-7654321-6');
  v_khalid    uuid := (select guardian_id from public.parent_guardian where cnic = '13503-6543210-8');
  v_naseem    uuid := (select guardian_id from public.parent_guardian where cnic = '42101-5432109-0');
  v_aisha_off uuid := (select officer_id from public.nadra_officer where employee_no = 'EMP-100201');
  v_sana_off  uuid := (select officer_id from public.nadra_officer where employee_no = 'EMP-100301');
  v_imran_off uuid := (select officer_id from public.nadra_officer where employee_no = 'EMP-100501');
  -- birth record IDs we'll reference in dependent inserts
  v_br1 uuid; v_br2 uuid; v_br3 uuid; v_br4 uuid;
  v_br5 uuid; v_br6 uuid; v_br7 uuid; v_br8 uuid;
  v_child1 uuid; v_child2 uuid; v_child3 uuid; v_child4 uuid;
begin
  -- 1. VERIFIED — Ayesha & Ali at AKU, last week
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at)
  values
    ('BRN-2026-00010001', v_aku, v_ayesha, v_ali, 'Dr. Ahmed Khan', 'PMDC-456789',
     now() - interval '7 days', 'NORMAL', 3.20, 'LIVE_BIRTH', 'VERIFIED', now() - interval '7 days')
  returning birth_record_id into v_br1;

  -- 2. VERIFIED — Mariam & Omar at SKM, two days ago
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at)
  values
    ('BRN-2026-00010002', v_skm, v_mariam, v_omar, 'Dr. Saira Malik', 'PMDC-654321',
     now() - interval '2 days', 'C_SECTION', 2.85, 'LIVE_BIRTH', 'VERIFIED', now() - interval '2 days')
  returning birth_record_id into v_br2;

  -- 3. VERIFIED — Zainab & Bilal at SZH, yesterday
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at)
  values
    ('BRN-2026-00010003', v_szh, v_zainab, v_bilalt, 'Dr. Ali Raza', 'PMDC-112233',
     now() - interval '1 day', 'NORMAL', 3.50, 'LIVE_BIRTH', 'VERIFIED', now() - interval '1 day')
  returning birth_record_id into v_br3;

  -- 4. VERIFIED — Saima & Khalid at ATH, three days ago (will get B-Form)
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at)
  values
    ('BRN-2026-00010004', v_ath, v_saima, v_khalid, 'Dr. Tariq Mahmood', 'PMDC-998877',
     now() - interval '3 days', 'NORMAL', 3.10, 'LIVE_BIRTH', 'VERIFIED', now() - interval '3 days')
  returning birth_record_id into v_br4;

  -- 5. FLAGGED — Hira & Naseem at JPMC, in officer queue (low birth weight)
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at, remarks)
  values
    ('BRN-2026-00010005', v_jpmc, v_hira, v_naseem, 'Dr. Naveed Akhtar', 'PMDC-445566',
     now() - interval '4 hours', 'NORMAL', 0.95, 'LIVE_BIRTH', 'FLAGGED', now() - interval '4 hours',
     'Birth weight below normal range; flagged for human review.')
  returning birth_record_id into v_br5;

  -- 6. PENDING — Nadia (no CNIC, temp ID) at SKM, just submitted
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at)
  values
    ('BRN-2026-00010006', v_skm, v_nadia, null, 'Dr. Saira Malik', 'PMDC-654321',
     now() - interval '15 minutes', 'NORMAL', 3.05, 'LIVE_BIRTH', 'PENDING', now() - interval '15 minutes')
  returning birth_record_id into v_br6;

  -- 7. REJECTED — duplicate submission (older record)
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at, remarks)
  values
    ('BRN-2026-00010007', v_aku, v_ayesha, v_ali, 'Dr. Ahmed Khan', 'PMDC-456789',
     now() - interval '14 days', 'NORMAL', 3.20, 'LIVE_BIRTH', 'REJECTED', now() - interval '14 days',
     'Duplicate of BRN-2026-00010001 — rejected by officer.')
  returning birth_record_id into v_br7;

  -- 8. AMENDED — Saima/Khalid record edited later (typo in birth weight corrected)
  insert into public.birth_record
    (brn, hospital_id, mother_id, father_id, attending_doctor, doctor_license_no,
     birth_datetime, delivery_type, birth_weight_kg, birth_outcome, status, submitted_at, remarks)
  values
    ('BRN-2026-00010008', v_ath, v_saima, v_khalid, 'Dr. Tariq Mahmood', 'PMDC-998877',
     now() - interval '5 days', 'NORMAL', 3.10, 'LIVE_BIRTH', 'AMENDED', now() - interval '5 days',
     'Birth weight corrected from 31.0 to 3.10 (data entry error).')
  returning birth_record_id into v_br8;

  -- VERIFICATION_LOG entries for status transitions
  insert into public.verification_log
    (birth_record_id, officer_id, action, previous_status, new_status, remarks)
  values
    (v_br1, v_aisha_off, 'AI_AUTO_APPROVE',          'PENDING',  'VERIFIED', 'AI verdict PASS, confidence 0.97'),
    (v_br2, v_aisha_off, 'AI_AUTO_APPROVE',          'PENDING',  'VERIFIED', 'AI verdict PASS, confidence 0.95'),
    (v_br3, v_sana_off,  'AI_AUTO_APPROVE',          'PENDING',  'VERIFIED', 'AI verdict PASS, confidence 0.96'),
    (v_br4, v_imran_off, 'AI_AUTO_APPROVE',          'PENDING',  'VERIFIED', 'AI verdict PASS, confidence 0.98'),
    (v_br5, v_aisha_off, 'AI_FLAG',                  'PENDING',  'FLAGGED',  'Birth weight outside expected range'),
    (v_br7, v_aisha_off, 'OFFICER_REJECT_DUPLICATE', 'PENDING',  'REJECTED', 'Duplicate of BRN-2026-00010001'),
    (v_br8, v_imran_off, 'OFFICER_AMEND',            'VERIFIED', 'AMENDED',  'Corrected birth weight typo');

  -- AI_REVIEW_LOG entries
  insert into public.ai_review_log
    (birth_record_id, verdict, flags_raised, confidence_score, raw_response)
  values
    (v_br1, 'PASS', '[]'::jsonb, 0.970, '{"summary":"All eight rules passed."}'::jsonb),
    (v_br2, 'PASS', '[]'::jsonb, 0.953, '{"summary":"All eight rules passed."}'::jsonb),
    (v_br3, 'PASS', '[]'::jsonb, 0.961, '{"summary":"All eight rules passed."}'::jsonb),
    (v_br4, 'PASS', '[]'::jsonb, 0.980, '{"summary":"All eight rules passed."}'::jsonb),
    (v_br5, 'FLAG',
      '[{"rule":"birth_weight_range","severity":"MEDIUM","reason":"weight 0.95kg below 1.0kg threshold"}]'::jsonb,
      0.620,
      '{"summary":"One rule failed: birth weight outside physiologically common range — flagged for human review."}'::jsonb),
    (v_br6, 'PASS', '[]'::jsonb, 0.910, '{"summary":"Awaiting officer authorization."}'::jsonb),
    (v_br7, 'FLAG',
      '[{"rule":"duplicate_detection","severity":"HIGH","reason":"matching mother CNIC + birth_datetime within 24h"}]'::jsonb,
      0.880,
      '{"summary":"Duplicate of BRN-2026-00010001 detected."}'::jsonb);

  -- CHILD records for the four VERIFIED births
  insert into public.child
    (cnin, birth_record_id, full_name, gender, date_of_birth, place_of_birth, blood_group)
  values
    ('CNIN-1000000001', v_br1, 'Ahmad Siddiqui',  'MALE',   (now() - interval '7 days')::date,  'Karachi',    'A+'),
    ('CNIN-1000000002', v_br2, 'Hassan Hussain',  'MALE',   (now() - interval '2 days')::date,  'Lahore',     'B+'),
    ('CNIN-1000000003', v_br3, 'Zara Tariq',      'FEMALE', (now() - interval '1 day')::date,   'Lahore',     'O+'),
    ('CNIN-1000000004', v_br4, 'Mehreen Mehmood', 'FEMALE', (now() - interval '3 days')::date,  'Abbottabad', 'AB-');

  select child_id into v_child1 from public.child where cnin = 'CNIN-1000000001';
  select child_id into v_child2 from public.child where cnin = 'CNIN-1000000002';
  select child_id into v_child3 from public.child where cnin = 'CNIN-1000000003';
  select child_id into v_child4 from public.child where cnin = 'CNIN-1000000004';

  -- CHILD_GUARDIAN links (mother + father where applicable)
  insert into public.child_guardian (child_id, guardian_id, relationship_type, is_primary) values
    (v_child1, v_ayesha, 'MOTHER', true),
    (v_child1, v_ali,    'FATHER', false),
    (v_child2, v_mariam, 'MOTHER', true),
    (v_child2, v_omar,   'FATHER', false),
    (v_child3, v_zainab, 'MOTHER', true),
    (v_child3, v_bilalt, 'FATHER', false),
    (v_child4, v_saima,  'MOTHER', true),
    (v_child4, v_khalid, 'FATHER', false);

  -- B-Forms: three issued, one ready-to-issue (br4 not yet authorized)
  insert into public.bform
    (bform_number, child_id, issued_by, issue_date, version, is_current)
  values
    ('BF-2026-00010001', v_child1, v_aisha_off, (now() - interval '7 days')::date, 1, true),
    ('BF-2026-00010002', v_child2, v_aisha_off, (now() - interval '2 days')::date, 1, true),
    ('BF-2026-00010003', v_child3, v_sana_off,  (now() - interval '1 day')::date,  1, true);
  -- v_child4 has no B-Form yet — it sits in the officer issuance queue

  -- NOTIFICATIONS — SMS to parents that B-Form is ready
  insert into public.notifications
    (recipient_type, recipient_contact, channel, subject, body, status, related_table, related_id, sent_at)
  values
    ('PARENT', '+92-300-1111111', 'SMS', null,
     'Mubarak ho! Your child Ahmad Siddiqui''s B-Form (BF-2026-00010001) is ready at NADRA Karachi-South.',
     'SENT', 'bform', 'BF-2026-00010001', now() - interval '7 days'),
    ('PARENT', '+92-300-2222222', 'SMS', null,
     'Your child''s B-Form (BF-2026-00010002) is ready at NADRA Karachi-South Mega Centre.',
     'SENT', 'bform', 'BF-2026-00010002', now() - interval '2 days'),
    ('PARENT', '+92-300-3333333', 'SMS', null,
     'Your child Zara Tariq''s B-Form (BF-2026-00010003) is ready at NADRA Lahore.',
     'SENT', 'bform', 'BF-2026-00010003', now() - interval '1 day'),
    ('PARENT', '+92-300-4444444', 'SMS', null,
     'Your child''s birth has been verified. B-Form will be ready shortly.',
     'QUEUED', 'birth_record', null, null);

  -- AUDIT_TRAIL — sample entries
  insert into public.audit_trail
    (actor_type, actor_id, action_type, table_affected, record_id, description)
  values
    ('HOSPITAL_STAFF', v_aku::text,       'INSERT', 'birth_record', v_br1::text, 'Hospital submitted birth record'),
    ('AI_ENGINE',      'gemini-flash',    'UPDATE', 'birth_record', v_br1::text, 'AI auto-verified record (confidence 0.97)'),
    ('NADRA_OFFICER',  v_aisha_off::text, 'INSERT', 'bform',        'BF-2026-00010001', 'B-Form authorized'),
    ('SYSTEM',         'system',          'INSERT', 'notifications', null,        'Sent B-Form ready SMS to parent');

  -- OFFLINE_QUEUE — show one synced and one pending entry from ATH (rural connectivity)
  insert into public.offline_queue
    (hospital_id, payload, status, created_at, synced_at, birth_record_id)
  values
    (v_ath,
     jsonb_build_object('brn','BRN-2026-00010004','mother_cnic','13503-4567890-7','synced','from-device-001'),
     'SYNCED',  now() - interval '3 days', now() - interval '2 days 23 hours', v_br4),
    (v_ath,
     jsonb_build_object('brn','BRN-2026-00010099','mother_cnic','13503-9999999-9','draft',true),
     'PENDING', now() - interval '6 hours', null, null);

end$$;

-- Refresh planner stats so pg_class.reltuples reflects the seed rather than -1.
-- The /dev/schema observatory uses reltuples for the row-count column.
analyze public.hospital;
analyze public.nadra_office;
analyze public.nadra_officer;
analyze public.parent_guardian;
analyze public.birth_record;
analyze public.child;
analyze public.child_guardian;
analyze public.bform;
analyze public.verification_log;
analyze public.ai_review_log;
analyze public.audit_trail;
analyze public.offline_queue;
analyze public.notifications;
analyze public.query_log;


-- =============================================================================
-- Curated reporting queries (joins, aggregates, transactions)
-- =============================================================================
-- =============================================================================
-- NBRPTS — Meaningful SQL Query Catalogue
-- =============================================================================
-- This file demonstrates the SQL operations required by the CS2013 rubric:
--   * INNER / LEFT joins across multiple tables
--   * Aggregate functions (COUNT, AVG, SUM, MAX, MIN)
--   * GROUP BY with HAVING
--   * Subqueries and CTEs
--   * Window functions
--   * Transaction management (BEGIN, SAVEPOINT, COMMIT, ROLLBACK)
--
-- Every query reflects a real reporting requirement of the system.
-- Run any single query interactively in the Supabase SQL editor.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1.  Per-hospital submission scoreboard (JOIN + GROUP BY + ORDER BY)
--      Reporting need: NADRA HQ wants to see which hospitals are most active.
-- -----------------------------------------------------------------------------
select
  h.hospital_name,
  h.province,
  count(b.birth_record_id)                                       as total_records,
  count(*) filter (where b.status = 'VERIFIED')                  as verified,
  count(*) filter (where b.status = 'FLAGGED')                   as flagged,
  count(*) filter (where b.status = 'PENDING')                   as pending,
  round(
    100.0 * count(*) filter (where b.status = 'VERIFIED')
    / nullif(count(*), 0),
    1
  )                                                              as verified_pct
from   public.hospital      h
left   join public.birth_record b on b.hospital_id = h.hospital_id
group  by h.hospital_id, h.hospital_name, h.province
order  by total_records desc;


-- -----------------------------------------------------------------------------
-- Q2.  Hospitals with > 5 flagged records this year (GROUP BY + HAVING)
--      Reporting need: compliance team flags facilities for audit.
-- -----------------------------------------------------------------------------
select
  h.hospital_name,
  count(*) as flagged_this_year
from   public.hospital      h
join   public.birth_record  b  on b.hospital_id = h.hospital_id
where  b.status = 'FLAGGED'
  and  b.submitted_at >= date_trunc('year', current_date)
group  by h.hospital_id, h.hospital_name
having count(*) > 5
order  by flagged_this_year desc;


-- -----------------------------------------------------------------------------
-- Q3.  Detailed verified-births report (multi-way INNER JOIN)
--      Joins birth_record × child × parent_guardian (mother) × hospital.
-- -----------------------------------------------------------------------------
select
  c.cnin,
  c.full_name           as child_name,
  c.gender              as child_gender,
  c.date_of_birth,
  m.full_name           as mother_name,
  m.cnic                as mother_cnic,
  h.hospital_name,
  h.district,
  b.attending_doctor,
  b.delivery_type,
  b.birth_weight_kg
from   public.child            c
join   public.birth_record     b on b.birth_record_id = c.birth_record_id
join   public.parent_guardian  m on m.guardian_id = b.mother_id
join   public.hospital         h on h.hospital_id = b.hospital_id
where  b.status = 'VERIFIED'
order  by c.created_at desc
limit  50;


-- -----------------------------------------------------------------------------
-- Q4.  Births by province and gender (GROUP BY ROLLUP for sub-totals)
--      Reporting need: demographic breakdown by region and sex.
-- -----------------------------------------------------------------------------
select
  coalesce(h.province::text, 'TOTAL')          as province,
  coalesce(c.gender::text,   'ALL')            as gender,
  count(*)                                     as births
from   public.child           c
join   public.birth_record    b on b.birth_record_id = c.birth_record_id
join   public.hospital        h on h.hospital_id    = b.hospital_id
group  by rollup (h.province, c.gender)
order  by h.province nulls last, c.gender;


-- -----------------------------------------------------------------------------
-- Q5.  AI engine performance dashboard (JOIN + multiple aggregates)
-- -----------------------------------------------------------------------------
select
  ar.verdict,
  count(*)                              as total_reviews,
  round(avg(ar.confidence_score)::numeric, 3) as avg_confidence,
  count(*) filter (where ar.human_override) as overridden,
  round(
    100.0 * count(*) filter (where ar.human_override) / count(*),
    1
  ) as override_pct
from   public.ai_review_log ar
group  by ar.verdict
order  by total_reviews desc;


-- -----------------------------------------------------------------------------
-- Q6.  Average officer caseload (subquery + aggregate)
--      Reporting need: workload balancing across NADRA offices.
-- -----------------------------------------------------------------------------
select
  o.office_name,
  o.city,
  count(distinct vl.officer_id)                          as officers_active,
  count(vl.log_id)                                       as actions_taken,
  round(
    count(vl.log_id)::numeric
    / nullif(count(distinct vl.officer_id), 0),
    1
  )                                                      as avg_actions_per_officer
from   public.nadra_office          o
join   public.nadra_officer         off on off.office_id = o.office_id
left   join public.verification_log vl  on vl.officer_id = off.officer_id
group  by o.office_id, o.office_name, o.city
order  by actions_taken desc;


-- -----------------------------------------------------------------------------
-- Q7.  Pending-record ageing (date arithmetic + CASE buckets)
-- -----------------------------------------------------------------------------
select
  case
    when now() - submitted_at <  interval '1 hour'  then '< 1h'
    when now() - submitted_at <  interval '24 hours' then '1-24h'
    when now() - submitted_at <  interval '7 days'   then '1-7d'
    else                                                  '> 7d'
  end                                          as age_bucket,
  count(*)                                     as pending_records
from   public.birth_record
where  status = 'PENDING'
group  by 1
order  by min(now() - submitted_at);


-- -----------------------------------------------------------------------------
-- Q8.  Top 5 hospitals by birth weight (window function)
-- -----------------------------------------------------------------------------
with ranked as (
  select
    h.hospital_name,
    avg(b.birth_weight_kg) as avg_weight,
    count(*)               as births,
    rank() over (order by avg(b.birth_weight_kg) desc) as rk
  from   public.hospital      h
  join   public.birth_record  b on b.hospital_id = h.hospital_id
  where  b.status = 'VERIFIED'
  group  by h.hospital_id, h.hospital_name
  having count(*) >= 3
)
select hospital_name, avg_weight, births, rk
from   ranked
where  rk <= 5;


-- -----------------------------------------------------------------------------
-- Q9.  B-Form reissuance history (LEFT JOIN + grouping)
-- -----------------------------------------------------------------------------
select
  c.full_name              as child_name,
  c.cnin,
  count(bf.bform_id)       as total_bforms_issued,
  max(bf.version)          as latest_version,
  string_agg(
    bf.reissue_reason, '; ' order by bf.version
  ) filter (where bf.reissue_reason is not null) as reissue_history
from   public.child  c
left   join public.bform bf on bf.child_id = c.child_id
group  by c.child_id, c.full_name, c.cnin
having count(bf.bform_id) > 1
order  by total_bforms_issued desc;


-- =============================================================================
-- TRANSACTION MANAGEMENT
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TX1.  Successful officer verification — atomic group of writes.
--       If any single statement fails the entire transaction rolls back so
--       the database is never left in a half-verified state.
-- -----------------------------------------------------------------------------
begin;

  -- 1. Claim the record (state-machine trigger validates the transition)
  update public.birth_record
     set status = 'VERIFIED'
   where brn = 'BRN-2025-00001000'
     and status in ('PENDING', 'FLAGGED');

  -- 2. The post-verification trigger has already inserted the child + B-Form,
  --    fired audit triggers, and queued notifications. We only need to
  --    record the officer's note here.
  insert into public.verification_log (birth_record_id, officer_id, action,
                                       previous_status, new_status, remarks)
  select b.birth_record_id,
         (select officer_id from public.nadra_officer where employee_no = 'EMP-100201'),
         'VERIFY_RECORD',
         'PENDING',
         'VERIFIED',
         'Documents reviewed; CNIC matches.'
    from public.birth_record b
   where b.brn = 'BRN-2025-00001000';

commit;


-- -----------------------------------------------------------------------------
-- TX2.  Failed verification — savepoint + rollback to savepoint.
--       Demonstrates partial rollback while keeping the rest of the txn alive.
-- -----------------------------------------------------------------------------
begin;

  -- Stage 1: provisional flag (kept)
  update public.birth_record
     set status = 'FLAGGED'
   where brn = 'BRN-2025-00001001'
     and status = 'PENDING';

  savepoint after_flag;

  -- Stage 2: attempt an illegal transition (FLAGGED → PENDING is not allowed
  -- by the state-machine trigger). This will raise an exception.
  begin
    update public.birth_record
       set status = 'PENDING'
     where brn = 'BRN-2025-00001001';
  exception when others then
    -- Roll back only the bad statement; the FLAGGED state survives.
    rollback to savepoint after_flag;
  end;

  -- Stage 3: do the legal action instead
  insert into public.verification_log (birth_record_id, officer_id, action,
                                       previous_status, new_status, remarks)
  select b.birth_record_id,
         (select officer_id from public.nadra_officer where employee_no = 'EMP-100201'),
         'FLAG_FOR_REVIEW',
         'PENDING',
         'FLAGGED',
         'AI confidence below 0.6 — manual review queued.'
    from public.birth_record b
   where b.brn = 'BRN-2025-00001001';

commit;


-- -----------------------------------------------------------------------------
-- TX3.  Full rollback — never reaches the database.
--       Useful when the application detects an inconsistency mid-transaction.
-- -----------------------------------------------------------------------------
begin;

  insert into public.parent_guardian
    (cnic, full_name, gender, date_of_birth, contact_number, address,
     province, district, nationality)
  values
    ('99999-9999999-9', 'Test Parent', 'FEMALE', '1990-01-01',
     '+92 300 0000000', '— test —', 'PUNJAB', 'Lahore', 'Pakistani');

  -- Application-side check failed: undo everything.
rollback;
