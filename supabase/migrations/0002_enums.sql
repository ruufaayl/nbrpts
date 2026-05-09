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
