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
