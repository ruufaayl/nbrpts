-- Phase 4: SELECT policies on every domain table.
--
-- Coarse-grained policies:
--   * anon              → no domain rows visible (the observatory RPCs are
--                         SECURITY DEFINER and continue to work)
--   * hospital_staff    → only their hospital's data
--   * nadra_officer     → all rows (read-only at the table level; writes go
--                         through SECURITY DEFINER RPCs)
--   * admin             → ALL on everything
--
-- Phase 4.5 (deferred) will tighten officer scope to "officers see records
-- for hospitals in their office's jurisdiction_districts."

-- ---------------------------------------------------------------------------
-- Helper macro idea: every table follows the same pattern. We re-use the
-- following four policies per table:
--   <table>_admin_all          ALL using/check (is_admin())
--   <table>_officer_select     SELECT using (current_app_role() = 'nadra_officer')
--   <table>_hospital_self      SELECT using (hospital scope check)  ← varies
-- ---------------------------------------------------------------------------

-- =============== hospital ==================================================
drop policy if exists hospital_admin_all     on public.hospital;
drop policy if exists hospital_officer_read  on public.hospital;
drop policy if exists hospital_staff_self    on public.hospital;
create policy hospital_admin_all     on public.hospital for all
  using (public.is_admin()) with check (public.is_admin());
create policy hospital_officer_read  on public.hospital for select
  using (public.current_app_role() = 'nadra_officer');
create policy hospital_staff_self    on public.hospital for select
  using (public.current_app_role() = 'hospital_staff'
         and hospital_id = public.current_hospital_id());

-- =============== nadra_office ==============================================
drop policy if exists nadra_office_admin_all    on public.nadra_office;
drop policy if exists nadra_office_officer_read on public.nadra_office;
create policy nadra_office_admin_all    on public.nadra_office for all
  using (public.is_admin()) with check (public.is_admin());
create policy nadra_office_officer_read on public.nadra_office for select
  using (public.current_app_role() = 'nadra_officer');

-- =============== nadra_officer =============================================
drop policy if exists nadra_officer_admin_all    on public.nadra_officer;
drop policy if exists nadra_officer_self_read    on public.nadra_officer;
drop policy if exists nadra_officer_peer_read    on public.nadra_officer;
create policy nadra_officer_admin_all on public.nadra_officer for all
  using (public.is_admin()) with check (public.is_admin());
create policy nadra_officer_self_read on public.nadra_officer for select
  using (officer_id = public.current_officer_id());
-- Officers can see other officers in the same office (for assignment lists).
create policy nadra_officer_peer_read on public.nadra_officer for select
  using (
    public.current_app_role() = 'nadra_officer'
    and office_id = (
      select o.office_id from public.nadra_officer o
      where o.officer_id = public.current_officer_id()
    )
  );

-- =============== parent_guardian ===========================================
drop policy if exists parent_guardian_admin_all      on public.parent_guardian;
drop policy if exists parent_guardian_officer_read   on public.parent_guardian;
drop policy if exists parent_guardian_hospital_read  on public.parent_guardian;
create policy parent_guardian_admin_all on public.parent_guardian for all
  using (public.is_admin()) with check (public.is_admin());
create policy parent_guardian_officer_read on public.parent_guardian for select
  using (public.current_app_role() = 'nadra_officer');
-- Hospital staff see parents linked to any of their hospital's birth_records.
create policy parent_guardian_hospital_read on public.parent_guardian for select
  using (
    public.current_app_role() = 'hospital_staff'
    and exists (
      select 1 from public.birth_record br
      where br.hospital_id = public.current_hospital_id()
        and (br.mother_id = parent_guardian.guardian_id
             or br.father_id = parent_guardian.guardian_id)
    )
  );

-- =============== birth_record ==============================================
drop policy if exists birth_record_admin_all     on public.birth_record;
drop policy if exists birth_record_officer_read  on public.birth_record;
drop policy if exists birth_record_hospital_read on public.birth_record;
create policy birth_record_admin_all on public.birth_record for all
  using (public.is_admin()) with check (public.is_admin());
create policy birth_record_officer_read on public.birth_record for select
  using (public.current_app_role() = 'nadra_officer');
create policy birth_record_hospital_read on public.birth_record for select
  using (public.current_app_role() = 'hospital_staff'
         and hospital_id = public.current_hospital_id());

-- =============== child =====================================================
drop policy if exists child_admin_all     on public.child;
drop policy if exists child_officer_read  on public.child;
drop policy if exists child_hospital_read on public.child;
create policy child_admin_all on public.child for all
  using (public.is_admin()) with check (public.is_admin());
create policy child_officer_read on public.child for select
  using (public.current_app_role() = 'nadra_officer');
create policy child_hospital_read on public.child for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1 from public.birth_record br
           where br.birth_record_id = child.birth_record_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== child_guardian ============================================
drop policy if exists child_guardian_admin_all     on public.child_guardian;
drop policy if exists child_guardian_officer_read  on public.child_guardian;
drop policy if exists child_guardian_hospital_read on public.child_guardian;
create policy child_guardian_admin_all on public.child_guardian for all
  using (public.is_admin()) with check (public.is_admin());
create policy child_guardian_officer_read on public.child_guardian for select
  using (public.current_app_role() = 'nadra_officer');
create policy child_guardian_hospital_read on public.child_guardian for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1
           from public.child c
           join public.birth_record br on br.birth_record_id = c.birth_record_id
           where c.child_id = child_guardian.child_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== bform =====================================================
drop policy if exists bform_admin_all     on public.bform;
drop policy if exists bform_officer_read  on public.bform;
drop policy if exists bform_hospital_read on public.bform;
create policy bform_admin_all on public.bform for all
  using (public.is_admin()) with check (public.is_admin());
create policy bform_officer_read on public.bform for select
  using (public.current_app_role() = 'nadra_officer');
create policy bform_hospital_read on public.bform for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1
           from public.child c
           join public.birth_record br on br.birth_record_id = c.birth_record_id
           where c.child_id = bform.child_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== verification_log ==========================================
drop policy if exists verification_log_admin_all     on public.verification_log;
drop policy if exists verification_log_officer_read  on public.verification_log;
drop policy if exists verification_log_hospital_read on public.verification_log;
create policy verification_log_admin_all on public.verification_log for all
  using (public.is_admin()) with check (public.is_admin());
create policy verification_log_officer_read on public.verification_log for select
  using (public.current_app_role() = 'nadra_officer');
create policy verification_log_hospital_read on public.verification_log for select
  using (public.current_app_role() = 'hospital_staff'
         and exists (
           select 1 from public.birth_record br
           where br.birth_record_id = verification_log.birth_record_id
             and br.hospital_id = public.current_hospital_id()
         ));

-- =============== ai_review_log =============================================
drop policy if exists ai_review_log_admin_all    on public.ai_review_log;
drop policy if exists ai_review_log_officer_read on public.ai_review_log;
create policy ai_review_log_admin_all on public.ai_review_log for all
  using (public.is_admin()) with check (public.is_admin());
create policy ai_review_log_officer_read on public.ai_review_log for select
  using (public.current_app_role() = 'nadra_officer');

-- =============== audit_trail ===============================================
drop policy if exists audit_trail_admin_all    on public.audit_trail;
drop policy if exists audit_trail_officer_read on public.audit_trail;
create policy audit_trail_admin_all on public.audit_trail for all
  using (public.is_admin()) with check (public.is_admin());
create policy audit_trail_officer_read on public.audit_trail for select
  using (public.current_app_role() = 'nadra_officer');

-- =============== offline_queue =============================================
drop policy if exists offline_queue_admin_all     on public.offline_queue;
drop policy if exists offline_queue_officer_read  on public.offline_queue;
drop policy if exists offline_queue_hospital_read on public.offline_queue;
create policy offline_queue_admin_all on public.offline_queue for all
  using (public.is_admin()) with check (public.is_admin());
create policy offline_queue_officer_read on public.offline_queue for select
  using (public.current_app_role() = 'nadra_officer');
create policy offline_queue_hospital_read on public.offline_queue for select
  using (public.current_app_role() = 'hospital_staff'
         and hospital_id = public.current_hospital_id());

-- =============== notifications =============================================
drop policy if exists notifications_admin_all    on public.notifications;
drop policy if exists notifications_officer_read on public.notifications;
create policy notifications_admin_all on public.notifications for all
  using (public.is_admin()) with check (public.is_admin());
create policy notifications_officer_read on public.notifications for select
  using (public.current_app_role() = 'nadra_officer');

-- ---------------------------------------------------------------------------
-- query_log: keep public so /dev observatory works for anon viewers.
-- This was set up in 0000_init_query_log.sql; this is just a comment marker.
-- ---------------------------------------------------------------------------
-- (no change)
