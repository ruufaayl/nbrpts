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
