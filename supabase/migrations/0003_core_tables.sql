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
