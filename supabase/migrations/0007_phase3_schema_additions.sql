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
