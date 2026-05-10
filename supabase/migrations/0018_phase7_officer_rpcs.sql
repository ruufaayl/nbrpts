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
