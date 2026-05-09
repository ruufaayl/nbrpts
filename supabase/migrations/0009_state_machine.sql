-- Phase 3: birth_record status state machine + verification log + cascade.
--
-- Three triggers fire on UPDATE OF status:
--   1. BEFORE — fn_validate_birth_record_status validates legality
--   2. AFTER  — fn_log_status_change writes a verification_log row
--   3. AFTER  — fn_post_verification_cascade creates child + bform + notification
--               when status transitions into VERIFIED
--
-- Officer for the verification_log row is read from session var
-- app.current_officer_id. AI-driven changes can leave it unset; the trigger
-- falls back to the EMP-999999 sentinel officer.

-- ---------------------------------------------------------------------------
-- 1. State-machine validator
-- ---------------------------------------------------------------------------
create or replace function public.fn_validate_birth_record_status()
returns trigger
language plpgsql
as $$
declare
  v_legal boolean;
begin
  if NEW.status is not distinct from OLD.status then
    return NEW;
  end if;

  v_legal := exists (
    select 1
    from (values
      ('PENDING'::record_status_t,  'VERIFIED'::record_status_t),
      ('PENDING',                   'FLAGGED'),
      ('PENDING',                   'REJECTED'),
      ('FLAGGED',                   'VERIFIED'),
      ('FLAGGED',                   'REJECTED'),
      ('REJECTED',                  'PENDING'),
      ('VERIFIED',                  'AMENDED'),
      ('AMENDED',                   'AMENDED')
    ) as legal(prev, next)
    where legal.prev = OLD.status and legal.next = NEW.status
  );

  if not v_legal then
    raise exception
      'Illegal status transition on birth_record %: % -> %',
      NEW.birth_record_id, OLD.status, NEW.status
      using errcode = 'check_violation';
  end if;

  return NEW;
end$$;

comment on function public.fn_validate_birth_record_status() is
  'BEFORE UPDATE trigger on birth_record. Rejects illegal status transitions per the proposal''s state machine (§4.1).';

drop trigger if exists trg_birth_record_state_machine on public.birth_record;
create trigger trg_birth_record_state_machine
  before update of status on public.birth_record
  for each row
  execute function public.fn_validate_birth_record_status();

-- ---------------------------------------------------------------------------
-- 2. Status-change logger
-- ---------------------------------------------------------------------------
create or replace function public.fn_log_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_officer_id uuid;
begin
  if NEW.status is not distinct from OLD.status then
    return NEW;
  end if;

  begin
    v_officer_id := nullif(current_setting('app.current_officer_id', true), '')::uuid;
  exception when others then
    v_officer_id := null;
  end;

  if v_officer_id is null then
    select officer_id into v_officer_id
    from public.nadra_officer
    where employee_no = 'EMP-999999';
  end if;

  if v_officer_id is null then
    raise exception 'Cannot log status change: no officer in session and no AI system officer configured';
  end if;

  insert into public.verification_log
    (birth_record_id, officer_id, action, previous_status, new_status, remarks)
  values
    (NEW.birth_record_id, v_officer_id,
     coalesce(TG_ARGV[0], 'STATUS_CHANGE'),
     OLD.status, NEW.status,
     NEW.remarks);

  return NEW;
end$$;

comment on function public.fn_log_status_change() is
  'AFTER UPDATE trigger on birth_record. Writes a verification_log row for every status change.';

drop trigger if exists trg_birth_record_log_status on public.birth_record;
create trigger trg_birth_record_log_status
  after update of status on public.birth_record
  for each row
  execute function public.fn_log_status_change('STATUS_CHANGE');

-- ---------------------------------------------------------------------------
-- 3. Post-verification cascade
-- ---------------------------------------------------------------------------
create or replace function public.fn_post_verification_cascade()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_child_id     uuid;
  v_cnin         text;
  v_bform_number text;
  v_officer_id   uuid;
  v_district     text;
  v_mother_phone text;
begin
  -- Only fire on transitions into VERIFIED from PENDING or FLAGGED.
  if not (NEW.status = 'VERIFIED' and OLD.status in ('PENDING', 'FLAGGED')) then
    return NEW;
  end if;

  -- Idempotency: if a child already exists for this birth, do nothing.
  if exists (select 1 from public.child where birth_record_id = NEW.birth_record_id) then
    return NEW;
  end if;

  begin
    v_officer_id := nullif(current_setting('app.current_officer_id', true), '')::uuid;
  exception when others then
    v_officer_id := null;
  end;
  if v_officer_id is null then
    select officer_id into v_officer_id
    from public.nadra_officer where employee_no = 'EMP-999999';
  end if;

  -- Mint a CNIN and create the CHILD row. Place of birth = hospital district.
  v_cnin := 'CNIN-' || lpad(nextval('public.cnin_seq')::text, 10, '0');

  select h.district into v_district
    from public.hospital h
   where h.hospital_id = NEW.hospital_id;

  insert into public.child
    (cnin, birth_record_id, full_name, gender, date_of_birth, place_of_birth)
  values
    (v_cnin, NEW.birth_record_id,
     coalesce(NEW.child_full_name, 'Pending'),
     NEW.child_gender,
     NEW.birth_datetime::date,
     coalesce(v_district, 'Unknown'))
  returning child_id into v_child_id;

  -- Link mother (always primary).
  insert into public.child_guardian
    (child_id, guardian_id, relationship_type, is_primary)
  values
    (v_child_id, NEW.mother_id, 'MOTHER', true);

  if NEW.father_id is not null then
    insert into public.child_guardian
      (child_id, guardian_id, relationship_type, is_primary)
    values
      (v_child_id, NEW.father_id, 'FATHER', false);
  end if;

  -- Mint a B-Form number and create the BFORM row, NOT YET authorized.
  v_bform_number := 'BF-' || to_char(now(), 'YYYY') || '-' ||
                    lpad(nextval('public.bform_seq')::text, 8, '0');

  insert into public.bform
    (bform_number, child_id, issued_by, version, is_current, authorized_at)
  values
    (v_bform_number, v_child_id, v_officer_id, 1, true, null);

  -- Queue an SMS notification (held until officer authorizes).
  select contact_number into v_mother_phone
    from public.parent_guardian where guardian_id = NEW.mother_id;

  insert into public.notifications
    (recipient_type, recipient_contact, channel, subject, body,
     status, related_table, related_id)
  values
    ('PARENT', v_mother_phone, 'SMS', null,
     'Mubarak ho! Your child''s B-Form ' || v_bform_number ||
     ' has been generated. You will receive another message when it is authorized for collection.',
     'QUEUED', 'bform', v_bform_number);

  return NEW;
end$$;

comment on function public.fn_post_verification_cascade() is
  'AFTER UPDATE trigger on birth_record. On transition into VERIFIED: creates child (with CNIN), links guardians, generates B-Form, queues SMS.';

drop trigger if exists trg_birth_record_post_verification on public.birth_record;
create trigger trg_birth_record_post_verification
  after update of status on public.birth_record
  for each row
  when (NEW.status = 'VERIFIED' and OLD.status <> 'VERIFIED')
  execute function public.fn_post_verification_cascade();
