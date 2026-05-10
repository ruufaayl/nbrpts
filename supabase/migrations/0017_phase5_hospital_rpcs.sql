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
