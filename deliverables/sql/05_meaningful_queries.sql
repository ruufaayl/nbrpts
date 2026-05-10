-- =============================================================================
-- NBRPTS — Meaningful SQL Query Catalogue
-- =============================================================================
-- This file demonstrates the SQL operations required by the CS2013 rubric:
--   * INNER / LEFT joins across multiple tables
--   * Aggregate functions (COUNT, AVG, SUM, MAX, MIN)
--   * GROUP BY with HAVING
--   * Subqueries and CTEs
--   * Window functions
--   * Transaction management (BEGIN, SAVEPOINT, COMMIT, ROLLBACK)
--
-- Every query reflects a real reporting requirement of the system.
-- Run any single query interactively in the Supabase SQL editor.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1.  Per-hospital submission scoreboard (JOIN + GROUP BY + ORDER BY)
--      Reporting need: NADRA HQ wants to see which hospitals are most active.
-- -----------------------------------------------------------------------------
select
  h.hospital_name,
  h.province,
  count(b.birth_record_id)                                       as total_records,
  count(*) filter (where b.status = 'VERIFIED')                  as verified,
  count(*) filter (where b.status = 'FLAGGED')                   as flagged,
  count(*) filter (where b.status = 'PENDING')                   as pending,
  round(
    100.0 * count(*) filter (where b.status = 'VERIFIED')
    / nullif(count(*), 0),
    1
  )                                                              as verified_pct
from   public.hospital      h
left   join public.birth_record b on b.hospital_id = h.hospital_id
group  by h.hospital_id, h.hospital_name, h.province
order  by total_records desc;


-- -----------------------------------------------------------------------------
-- Q2.  Hospitals with > 5 flagged records this year (GROUP BY + HAVING)
--      Reporting need: compliance team flags facilities for audit.
-- -----------------------------------------------------------------------------
select
  h.hospital_name,
  count(*) as flagged_this_year
from   public.hospital      h
join   public.birth_record  b  on b.hospital_id = h.hospital_id
where  b.status = 'FLAGGED'
  and  b.submitted_at >= date_trunc('year', current_date)
group  by h.hospital_id, h.hospital_name
having count(*) > 5
order  by flagged_this_year desc;


-- -----------------------------------------------------------------------------
-- Q3.  Detailed verified-births report (multi-way INNER JOIN)
--      Joins birth_record × child × parent_guardian (mother) × hospital.
-- -----------------------------------------------------------------------------
select
  c.cnin,
  c.full_name           as child_name,
  c.gender              as child_gender,
  c.date_of_birth,
  m.full_name           as mother_name,
  m.cnic                as mother_cnic,
  h.hospital_name,
  h.district,
  b.attending_doctor,
  b.delivery_type,
  b.birth_weight_kg
from   public.child            c
join   public.birth_record     b on b.birth_record_id = c.birth_record_id
join   public.parent_guardian  m on m.guardian_id = b.mother_id
join   public.hospital         h on h.hospital_id = b.hospital_id
where  b.status = 'VERIFIED'
order  by c.created_at desc
limit  50;


-- -----------------------------------------------------------------------------
-- Q4.  Births by province and gender (GROUP BY ROLLUP for sub-totals)
--      Reporting need: demographic breakdown by region and sex.
-- -----------------------------------------------------------------------------
select
  coalesce(h.province::text, 'TOTAL')          as province,
  coalesce(c.gender::text,   'ALL')            as gender,
  count(*)                                     as births
from   public.child           c
join   public.birth_record    b on b.birth_record_id = c.birth_record_id
join   public.hospital        h on h.hospital_id    = b.hospital_id
group  by rollup (h.province, c.gender)
order  by h.province nulls last, c.gender;


-- -----------------------------------------------------------------------------
-- Q5.  AI engine performance dashboard (JOIN + multiple aggregates)
-- -----------------------------------------------------------------------------
select
  ar.verdict,
  count(*)                              as total_reviews,
  round(avg(ar.confidence_score)::numeric, 3) as avg_confidence,
  count(*) filter (where ar.human_override) as overridden,
  round(
    100.0 * count(*) filter (where ar.human_override) / count(*),
    1
  ) as override_pct
from   public.ai_review_log ar
group  by ar.verdict
order  by total_reviews desc;


-- -----------------------------------------------------------------------------
-- Q6.  Average officer caseload (subquery + aggregate)
--      Reporting need: workload balancing across NADRA offices.
-- -----------------------------------------------------------------------------
select
  o.office_name,
  o.city,
  count(distinct vl.officer_id)                          as officers_active,
  count(vl.log_id)                                       as actions_taken,
  round(
    count(vl.log_id)::numeric
    / nullif(count(distinct vl.officer_id), 0),
    1
  )                                                      as avg_actions_per_officer
from   public.nadra_office          o
join   public.nadra_officer         off on off.office_id = o.office_id
left   join public.verification_log vl  on vl.officer_id = off.officer_id
group  by o.office_id, o.office_name, o.city
order  by actions_taken desc;


-- -----------------------------------------------------------------------------
-- Q7.  Pending-record ageing (date arithmetic + CASE buckets)
-- -----------------------------------------------------------------------------
select
  case
    when now() - submitted_at <  interval '1 hour'  then '< 1h'
    when now() - submitted_at <  interval '24 hours' then '1-24h'
    when now() - submitted_at <  interval '7 days'   then '1-7d'
    else                                                  '> 7d'
  end                                          as age_bucket,
  count(*)                                     as pending_records
from   public.birth_record
where  status = 'PENDING'
group  by 1
order  by min(now() - submitted_at);


-- -----------------------------------------------------------------------------
-- Q8.  Top 5 hospitals by birth weight (window function)
-- -----------------------------------------------------------------------------
with ranked as (
  select
    h.hospital_name,
    avg(b.birth_weight_kg) as avg_weight,
    count(*)               as births,
    rank() over (order by avg(b.birth_weight_kg) desc) as rk
  from   public.hospital      h
  join   public.birth_record  b on b.hospital_id = h.hospital_id
  where  b.status = 'VERIFIED'
  group  by h.hospital_id, h.hospital_name
  having count(*) >= 3
)
select hospital_name, avg_weight, births, rk
from   ranked
where  rk <= 5;


-- -----------------------------------------------------------------------------
-- Q9.  B-Form reissuance history (LEFT JOIN + grouping)
-- -----------------------------------------------------------------------------
select
  c.full_name              as child_name,
  c.cnin,
  count(bf.bform_id)       as total_bforms_issued,
  max(bf.version)          as latest_version,
  string_agg(
    bf.reissue_reason, '; ' order by bf.version
  ) filter (where bf.reissue_reason is not null) as reissue_history
from   public.child  c
left   join public.bform bf on bf.child_id = c.child_id
group  by c.child_id, c.full_name, c.cnin
having count(bf.bform_id) > 1
order  by total_bforms_issued desc;


-- =============================================================================
-- TRANSACTION MANAGEMENT
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TX1.  Successful officer verification — atomic group of writes.
--       If any single statement fails the entire transaction rolls back so
--       the database is never left in a half-verified state.
-- -----------------------------------------------------------------------------
begin;

  -- 1. Claim the record (state-machine trigger validates the transition)
  update public.birth_record
     set status = 'VERIFIED'
   where brn = 'BRN-2025-00001000'
     and status in ('PENDING', 'FLAGGED');

  -- 2. The post-verification trigger has already inserted the child + B-Form,
  --    fired audit triggers, and queued notifications. We only need to
  --    record the officer's note here.
  insert into public.verification_log (birth_record_id, officer_id, action,
                                       previous_status, new_status, remarks)
  select b.birth_record_id,
         (select officer_id from public.nadra_officer where employee_no = 'EMP-100201'),
         'VERIFY_RECORD',
         'PENDING',
         'VERIFIED',
         'Documents reviewed; CNIC matches.'
    from public.birth_record b
   where b.brn = 'BRN-2025-00001000';

commit;


-- -----------------------------------------------------------------------------
-- TX2.  Failed verification — savepoint + rollback to savepoint.
--       Demonstrates partial rollback while keeping the rest of the txn alive.
-- -----------------------------------------------------------------------------
begin;

  -- Stage 1: provisional flag (kept)
  update public.birth_record
     set status = 'FLAGGED'
   where brn = 'BRN-2025-00001001'
     and status = 'PENDING';

  savepoint after_flag;

  -- Stage 2: attempt an illegal transition (FLAGGED → PENDING is not allowed
  -- by the state-machine trigger). This will raise an exception.
  begin
    update public.birth_record
       set status = 'PENDING'
     where brn = 'BRN-2025-00001001';
  exception when others then
    -- Roll back only the bad statement; the FLAGGED state survives.
    rollback to savepoint after_flag;
  end;

  -- Stage 3: do the legal action instead
  insert into public.verification_log (birth_record_id, officer_id, action,
                                       previous_status, new_status, remarks)
  select b.birth_record_id,
         (select officer_id from public.nadra_officer where employee_no = 'EMP-100201'),
         'FLAG_FOR_REVIEW',
         'PENDING',
         'FLAGGED',
         'AI confidence below 0.6 — manual review queued.'
    from public.birth_record b
   where b.brn = 'BRN-2025-00001001';

commit;


-- -----------------------------------------------------------------------------
-- TX3.  Full rollback — never reaches the database.
--       Useful when the application detects an inconsistency mid-transaction.
-- -----------------------------------------------------------------------------
begin;

  insert into public.parent_guardian
    (cnic, full_name, gender, date_of_birth, contact_number, address,
     province, district, nationality)
  values
    ('99999-9999999-9', 'Test Parent', 'FEMALE', '1990-01-01',
     '+92 300 0000000', '— test —', 'PUNJAB', 'Lahore', 'Pakistani');

  -- Application-side check failed: undo everything.
rollback;
