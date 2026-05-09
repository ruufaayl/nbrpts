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
