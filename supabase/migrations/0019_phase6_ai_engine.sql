-- Phase 6: AI Engine.
--
-- A deterministic rules-based verification engine that scores PENDING records
-- and transitions them through the state machine.
--
-- Verdict logic:
--   * REJECT (auto): hard fail — birth_weight outside [0.5, 6.5], birth_datetime > now+1d, mother age <14
--   * FLAG   (queue): soft signal — mother <18, weight <2.0 or >5.0, missing CNIC, no father with no temp_reg_id, age delta unusual, AI < 0.6
--   * PASS   (auto-verify): all checks clean, confidence ≥ 0.85
--
-- Each call inserts an ai_review_log row, then updates birth_record.status which
-- fires the existing state-machine + post-verification cascade triggers.
-- The AI engine acts as the system officer (EMP-999999).

-- ---------------------------------------------------------------------------
-- ai_score_record — pure scoring, no side effects. Returns verdict + flags.
-- ---------------------------------------------------------------------------
create or replace function public.ai_score_record(p_brn text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_br      public.birth_record;
  v_mother  public.parent_guardian;
  v_father  public.parent_guardian;
  v_flags   jsonb := '[]'::jsonb;
  v_score   numeric := 1.0;
  v_verdict text;
  v_reasons text[] := array[]::text[];
  v_mother_age int;
  v_birth_year int;
begin
  select * into v_br from public.birth_record where brn = p_brn;
  if not found then
    raise exception 'Birth record % not found', p_brn using errcode = 'P0002';
  end if;

  select * into v_mother from public.parent_guardian where guardian_id = v_br.mother_id;
  if v_br.father_id is not null then
    select * into v_father from public.parent_guardian where guardian_id = v_br.father_id;
  end if;

  v_mother_age := extract(year from age(v_br.birth_datetime, v_mother.date_of_birth));
  v_birth_year := extract(year from v_br.birth_datetime);

  -- HARD REJECTS -----------------------------------------------------------
  if v_br.birth_weight_kg < 0.5 or v_br.birth_weight_kg > 6.5 then
    v_flags := v_flags || jsonb_build_object('code', 'WEIGHT_IMPLAUSIBLE',
                          'severity', 'reject',
                          'detail', format('birth_weight_kg = %s outside [0.5, 6.5]', v_br.birth_weight_kg));
    v_reasons := array_append(v_reasons, 'implausible birth weight');
    v_score := 0.05;
  end if;

  if v_br.birth_datetime > now() + interval '1 day' then
    v_flags := v_flags || jsonb_build_object('code', 'BIRTH_IN_FUTURE',
                          'severity', 'reject',
                          'detail', format('birth_datetime = %s', v_br.birth_datetime));
    v_reasons := array_append(v_reasons, 'birth date in future');
    v_score := 0.02;
  end if;

  if v_mother_age < 14 then
    v_flags := v_flags || jsonb_build_object('code', 'MOTHER_TOO_YOUNG',
                          'severity', 'reject',
                          'detail', format('mother age = %s', v_mother_age));
    v_reasons := array_append(v_reasons, 'mother under 14');
    v_score := 0.05;
  end if;

  -- SOFT FLAGS -------------------------------------------------------------
  if v_mother_age between 14 and 17 then
    v_flags := v_flags || jsonb_build_object('code', 'MOTHER_MINOR',
                          'severity', 'flag',
                          'detail', format('mother age = %s', v_mother_age));
    v_reasons := array_append(v_reasons, 'mother under 18');
    v_score := least(v_score, 0.55);
  end if;

  if v_br.birth_weight_kg between 0.5 and 1.99 then
    v_flags := v_flags || jsonb_build_object('code', 'WEIGHT_LOW',
                          'severity', 'flag',
                          'detail', format('birth_weight_kg = %s — premature?', v_br.birth_weight_kg));
    v_reasons := array_append(v_reasons, 'low birth weight');
    v_score := least(v_score, 0.65);
  end if;

  if v_br.birth_weight_kg between 5.01 and 6.5 then
    v_flags := v_flags || jsonb_build_object('code', 'WEIGHT_HIGH',
                          'severity', 'flag',
                          'detail', format('birth_weight_kg = %s — macrosomia?', v_br.birth_weight_kg));
    v_reasons := array_append(v_reasons, 'high birth weight');
    v_score := least(v_score, 0.7);
  end if;

  if v_mother.cnic is null then
    v_flags := v_flags || jsonb_build_object('code', 'MOTHER_NO_CNIC',
                          'severity', 'flag',
                          'detail', 'mother has only a temp_reg_id');
    v_reasons := array_append(v_reasons, 'mother lacks CNIC');
    v_score := least(v_score, 0.55);
  end if;

  if v_br.father_id is null then
    v_flags := v_flags || jsonb_build_object('code', 'NO_FATHER_RECORD',
                          'severity', 'flag',
                          'detail', 'father not provided');
    v_reasons := array_append(v_reasons, 'father missing');
    v_score := least(v_score, 0.7);
  end if;

  if v_br.father_id is not null and v_father.cnic is null then
    v_flags := v_flags || jsonb_build_object('code', 'FATHER_NO_CNIC',
                          'severity', 'flag',
                          'detail', 'father has only a temp_reg_id');
    v_score := least(v_score, 0.65);
  end if;

  if v_br.birth_outcome <> 'LIVE_BIRTH' then
    v_flags := v_flags || jsonb_build_object('code', 'NON_LIVE_OUTCOME',
                          'severity', 'flag',
                          'detail', format('outcome = %s', v_br.birth_outcome));
    v_reasons := array_append(v_reasons, 'non-live birth');
    v_score := least(v_score, 0.55);
  end if;

  -- DUPLICATE DETECTION: any other record with the same mother + same DOB +/- 12h?
  if exists (
    select 1 from public.birth_record br2
    where br2.birth_record_id <> v_br.birth_record_id
      and br2.mother_id = v_br.mother_id
      and br2.status not in ('REJECTED')
      and abs(extract(epoch from (br2.birth_datetime - v_br.birth_datetime))) < 43200
  ) then
    v_flags := v_flags || jsonb_build_object('code', 'POSSIBLE_DUPLICATE',
                          'severity', 'reject',
                          'detail', 'mother has another active record within 12h');
    v_reasons := array_append(v_reasons, 'possible duplicate');
    v_score := least(v_score, 0.1);
  end if;

  -- VERDICT ----------------------------------------------------------------
  if exists (
    select 1 from jsonb_array_elements(v_flags) f
    where f->>'severity' = 'reject'
  ) then
    v_verdict := 'REJECT';
  elsif v_score < 0.7 or jsonb_array_length(v_flags) > 0 then
    v_verdict := 'FLAG';
  else
    v_verdict := 'PASS';
    v_score := greatest(v_score, 0.92);  -- clean records get high confidence
  end if;

  return jsonb_build_object(
    'brn',              v_br.brn,
    'birth_record_id',  v_br.birth_record_id,
    'verdict',          v_verdict,
    'confidence_score', round(v_score, 3),
    'flags_raised',     v_flags,
    'reasons',          coalesce(to_jsonb(v_reasons), '[]'::jsonb),
    'mother_age',       v_mother_age
  );
end$$;

grant execute on function public.ai_score_record(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- ai_process_record — score + log + transition. The full AI Engine action.
-- ---------------------------------------------------------------------------
create or replace function public.ai_process_record(p_brn text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_score      jsonb;
  v_br         public.birth_record;
  v_ai_officer uuid;
  v_review_id  uuid;
  v_action     text;
  v_start      timestamptz := clock_timestamp();
begin
  select * into v_br from public.birth_record where brn = p_brn;
  if not found then
    raise exception 'Birth record % not found', p_brn using errcode = 'P0002';
  end if;

  if v_br.status not in ('PENDING', 'FLAGGED', 'AMENDED') then
    return jsonb_build_object(
      'ok', false, 'brn', p_brn,
      'reason', format('status %s is not processable', v_br.status)
    );
  end if;

  v_score := public.ai_score_record(p_brn);

  -- AI engine system officer (EMP-999999)
  select officer_id into v_ai_officer
    from public.nadra_officer where employee_no = 'EMP-999999';

  -- Insert ai_review_log first so the verdict is recorded even if state change fails
  insert into public.ai_review_log
    (birth_record_id, verdict, flags_raised, confidence_score, reviewed_at,
     human_override, raw_response)
  values
    (v_br.birth_record_id,
     (v_score->>'verdict')::ai_verdict_t,
     v_score->'flags_raised',
     (v_score->>'confidence_score')::numeric,
     now(), false,
     v_score)
  returning review_id into v_review_id;

  -- Make the AI engine the actor for downstream triggers.
  perform set_config('app.actor_type',         'AI_ENGINE',         true);
  perform set_config('app.actor_id',           v_ai_officer::text,  true);
  perform set_config('app.current_officer_id', v_ai_officer::text,  true);

  -- Transition the record. The state-machine validator + post-verification
  -- cascade triggers will handle child + B-Form + notifications.
  case v_score->>'verdict'
    when 'PASS' then
      if (v_score->>'confidence_score')::numeric >= 0.85 then
        update public.birth_record
           set status = 'VERIFIED',
               ai_review_result = v_score,
               remarks = coalesce(remarks, '') ||
                         case when remarks is null or remarks = '' then ''
                              else E'\n' end ||
                         format('AI auto-approved (confidence %s)',
                                v_score->>'confidence_score')
         where birth_record_id = v_br.birth_record_id;
        v_action := 'AUTO_VERIFIED';
      else
        update public.birth_record
           set status = 'FLAGGED',
               ai_review_result = v_score
         where birth_record_id = v_br.birth_record_id;
        v_action := 'FLAGGED_LOW_CONFIDENCE';
      end if;
    when 'FLAG' then
      update public.birth_record
         set status = 'FLAGGED',
             ai_review_result = v_score,
             remarks = coalesce(remarks, '') ||
                       case when remarks is null or remarks = '' then ''
                            else E'\n' end ||
                       format('AI flagged: %s', v_score->'reasons')
       where birth_record_id = v_br.birth_record_id;
      v_action := 'FLAGGED';
    when 'REJECT' then
      update public.birth_record
         set status = 'REJECTED',
             ai_review_result = v_score,
             remarks = format('AI auto-rejected: %s', v_score->'reasons')
       where birth_record_id = v_br.birth_record_id;
      v_action := 'AUTO_REJECTED';
  end case;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('ai_process_record',
          'score(brn) -> insert ai_review_log -> update birth_record.status',
          jsonb_build_object('brn', p_brn,
                             'verdict', v_score->>'verdict',
                             'action',  v_action),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return jsonb_build_object(
    'ok',           true,
    'brn',          p_brn,
    'review_id',    v_review_id,
    'verdict',      v_score->>'verdict',
    'confidence',   v_score->>'confidence_score',
    'action',       v_action,
    'flags',        v_score->'flags_raised',
    'reasons',      v_score->'reasons',
    'duration_ms',  extract(epoch from (clock_timestamp() - v_start)) * 1000
  );
end$$;

grant execute on function public.ai_process_record(text) to anon, authenticated;

comment on function public.ai_process_record(text) is
  'AI Engine: score a PENDING/FLAGGED/AMENDED record, insert ai_review_log, transition status via state machine.';

-- ---------------------------------------------------------------------------
-- ai_process_all_pending — batch processor
-- ---------------------------------------------------------------------------
create or replace function public.ai_process_all_pending(p_limit int default 50)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_brn       text;
  v_results   jsonb := '[]'::jsonb;
  v_one       jsonb;
  v_processed int := 0;
  v_passed    int := 0;
  v_flagged   int := 0;
  v_rejected  int := 0;
  v_errors    int := 0;
  v_start     timestamptz := clock_timestamp();
begin
  for v_brn in
    select brn from public.birth_record
    where status = 'PENDING'
    order by submitted_at asc
    limit p_limit
  loop
    begin
      v_one := public.ai_process_record(v_brn);
      v_results := v_results || v_one;
      v_processed := v_processed + 1;
      case v_one->>'verdict'
        when 'PASS'   then v_passed   := v_passed + 1;
        when 'FLAG'   then v_flagged  := v_flagged + 1;
        when 'REJECT' then v_rejected := v_rejected + 1;
        else null;
      end case;
    exception when others then
      v_errors := v_errors + 1;
      v_results := v_results || jsonb_build_object('brn', v_brn, 'ok', false, 'error', SQLERRM);
    end;
  end loop;

  return jsonb_build_object(
    'processed',   v_processed,
    'passed',      v_passed,
    'flagged',     v_flagged,
    'rejected',    v_rejected,
    'errors',      v_errors,
    'duration_ms', round(extract(epoch from (clock_timestamp() - v_start)) * 1000),
    'results',     v_results
  );
end$$;

grant execute on function public.ai_process_all_pending(int) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- get_ai_engine_data — dashboard data for /ai-engine
-- ---------------------------------------------------------------------------
create or replace function public.get_ai_engine_data()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'counts', jsonb_build_object(
      'pending_to_process', (select count(*) from public.birth_record where status = 'PENDING'),
      'flagged_records',    (select count(*) from public.birth_record where status = 'FLAGGED'),
      'reviews_today',      (select count(*) from public.ai_review_log where reviewed_at::date = current_date),
      'reviews_total',      (select count(*) from public.ai_review_log),
      'overrides',          (select count(*) from public.ai_review_log where human_override)
    ),
    'verdict_breakdown', (
      select coalesce(jsonb_object_agg(verdict, n), '{}'::jsonb)
      from (
        select verdict::text, count(*) as n
        from public.ai_review_log
        group by verdict
      ) x
    ),
    'avg_confidence', (
      select coalesce(jsonb_object_agg(verdict, avg_score), '{}'::jsonb)
      from (
        select verdict::text, round(avg(confidence_score)::numeric, 3) as avg_score
        from public.ai_review_log
        where confidence_score is not null
        group by verdict
      ) x
    ),
    'recent_reviews', (
      select coalesce(jsonb_agg(row_to_json(x) order by reviewed_at desc), '[]'::jsonb) from (
        select ar.review_id, ar.verdict, ar.confidence_score, ar.flags_raised,
               ar.reviewed_at, ar.human_override,
               br.brn, br.status as record_status,
               h.hospital_name, h.district,
               m.full_name as mother_name
        from public.ai_review_log ar
        join public.birth_record br on br.birth_record_id = ar.birth_record_id
        join public.hospital     h  on h.hospital_id     = br.hospital_id
        join public.parent_guardian m on m.guardian_id = br.mother_id
        order by ar.reviewed_at desc
        limit 25
      ) x
    ),
    'next_pending', (
      select coalesce(jsonb_agg(row_to_json(x) order by submitted_at asc), '[]'::jsonb) from (
        select br.birth_record_id, br.brn, br.submitted_at,
               br.attending_doctor, br.birth_weight_kg, br.delivery_type,
               h.hospital_name, h.district,
               m.full_name as mother_name, m.cnic as mother_cnic
        from public.birth_record br
        join public.hospital     h on h.hospital_id  = br.hospital_id
        join public.parent_guardian m on m.guardian_id = br.mother_id
        where br.status = 'PENDING'
        order by br.submitted_at asc
        limit 10
      ) x
    ),
    'generated_at', now()
  ) into v_result;

  return v_result;
end$$;

grant execute on function public.get_ai_engine_data() to anon, authenticated;
