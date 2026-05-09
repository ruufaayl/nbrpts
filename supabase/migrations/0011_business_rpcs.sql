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
