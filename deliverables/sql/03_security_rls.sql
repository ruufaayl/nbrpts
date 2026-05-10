-- =============================================================================
-- NBRPTS — Row-Level Security, app_user, and demo accounts
-- =============================================================================


-- ----- 0014_phase4_app_user.sql ----------------------------------------------

-- Phase 4: link Supabase Auth users to NBRPTS domain entities.
--
-- Every authenticated user has exactly one app_user row. The role determines
-- what they can see and which domain entity they represent:
--   * hospital_staff → hospital_id (a hospital they work at)
--   * nadra_officer  → officer_id (links to nadra_officer)
--   * admin          → no domain link, sees everything
--
-- Helpers below are SECURITY DEFINER so they can bypass RLS to read their
-- caller's own app_user row. They are the safe way for RLS policies to call
-- into the role/scope information.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- app_user: one row per signed-in user
-- ---------------------------------------------------------------------------
create table if not exists public.app_user (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  role         text not null
                 check (role in ('hospital_staff', 'nadra_officer', 'admin')),
  hospital_id  uuid references public.hospital(hospital_id),
  officer_id   uuid references public.nadra_officer(officer_id),
  full_name    text not null,
  created_at   timestamptz not null default now(),
  -- Exactly one domain link, based on role.
  constraint app_user_link_matches_role check (
    (role = 'hospital_staff' and hospital_id is not null and officer_id is null) or
    (role = 'nadra_officer'  and officer_id is not null  and hospital_id is null) or
    (role = 'admin'          and officer_id is null      and hospital_id is null)
  )
);

comment on table public.app_user is
  'Bridges auth.users to NBRPTS domain. Role decides scope; hospital_id or officer_id links to the represented entity.';

create index if not exists app_user_role_idx on public.app_user(role);
create index if not exists app_user_hospital_idx on public.app_user(hospital_id) where hospital_id is not null;
create index if not exists app_user_officer_idx  on public.app_user(officer_id)  where officer_id  is not null;

alter table public.app_user enable row level security;

-- A user can read their own row.
drop policy if exists app_user_self_read on public.app_user;
create policy app_user_self_read on public.app_user
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Helper functions used by RLS policies on every domain table.
-- ---------------------------------------------------------------------------
create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.app_user where user_id = auth.uid();
$$;

create or replace function public.current_hospital_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select hospital_id from public.app_user where user_id = auth.uid();
$$;

create or replace function public.current_officer_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select officer_id from public.app_user where user_id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role = 'admin' from public.app_user where user_id = auth.uid()),
    false
  );
$$;

grant execute on function public.current_app_role()    to anon, authenticated;
grant execute on function public.current_hospital_id() to anon, authenticated;
grant execute on function public.current_officer_id()  to anon, authenticated;
grant execute on function public.is_admin()            to anon, authenticated;

comment on function public.current_app_role()    is 'Role of the calling user, or NULL if anon / unlinked.';
comment on function public.current_hospital_id() is 'Hospital ID of the calling hospital_staff user, else NULL.';
comment on function public.current_officer_id()  is 'Officer ID of the calling nadra_officer user, else NULL.';
comment on function public.is_admin()            is 'True iff the calling user has the admin role.';

-- ---------------------------------------------------------------------------
-- Whoami RPC for the frontend / /dev nav widget
-- ---------------------------------------------------------------------------
create or replace function public.whoami()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then jsonb_build_object('signed_in', false)
    else (
      select jsonb_build_object(
        'signed_in',     true,
        'user_id',       au.user_id,
        'email',         u.email,
        'role',          au.role,
        'full_name',     au.full_name,
        'hospital_id',   au.hospital_id,
        'hospital_name', h.hospital_name,
        'officer_id',    au.officer_id,
        'officer_name',  o.full_name,
        'office_name',   no2.office_name
      )
      from public.app_user au
      join auth.users u                  on u.id = au.user_id
      left join public.hospital h        on h.hospital_id = au.hospital_id
      left join public.nadra_officer o   on o.officer_id  = au.officer_id
      left join public.nadra_office  no2 on no2.office_id = o.office_id
      where au.user_id = auth.uid()
    )
  end;
$$;

grant execute on function public.whoami() to anon, authenticated;

comment on function public.whoami() is
  'Returns the signed-in user''s role + linked entity, or {signed_in:false} if anonymous.';

-- ----- 0015_phase4_rls_policies.sql ------------------------------------------

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

-- ----- 0016_phase4_seed_demo_users.sql ---------------------------------------

-- Phase 4: three demo accounts so the login flow is immediately demoable.
--
-- Email             Role            Domain link
-- -----             ----            -----------
-- aisha@nbrpts.demo nadra_officer   EMP-100201 (Aisha Khan)
-- aku@nbrpts.demo   hospital_staff  Aga Khan University Hospital
-- admin@nbrpts.demo admin           (none)
--
-- Password for all three: demo1234
--
-- We seed directly into auth.users + auth.identities using bcrypt via
-- pgcrypto; Supabase docs explicitly support this pattern (see
-- "Migrate from Auth0" guide). idempotent via on-conflict.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Helper: insert (or no-op if exists) a demo Supabase Auth user.
-- ---------------------------------------------------------------------------
create or replace function public._seed_demo_user(
  p_email    text,
  p_password text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where email = p_email;
  if v_user_id is not null then
    return v_user_id;
  end if;

  v_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role,
    email, encrypted_password, email_confirmed_at,
    created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id, 'authenticated', 'authenticated',
    p_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data,
    provider, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_user_id, v_user_id::text,
    jsonb_build_object('sub', v_user_id::text, 'email', p_email, 'email_verified', true),
    'email', now(), now(), now()
  );

  return v_user_id;
end$$;

-- ---------------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------------
do $$
declare
  v_admin_id   uuid;
  v_officer_id uuid;
  v_staff_id   uuid;
  v_aisha_off  uuid := (select officer_id  from public.nadra_officer where employee_no = 'EMP-100201');
  v_aku        uuid := (select hospital_id from public.hospital      where hrn         = 'HRN-2019-0001');
begin
  v_admin_id   := public._seed_demo_user('admin@nbrpts.demo', 'demo1234');
  v_officer_id := public._seed_demo_user('aisha@nbrpts.demo', 'demo1234');
  v_staff_id   := public._seed_demo_user('aku@nbrpts.demo',   'demo1234');

  insert into public.app_user (user_id, role, hospital_id, officer_id, full_name) values
    (v_admin_id,   'admin',          null,   null,         'Demo Admin'),
    (v_officer_id, 'nadra_officer',  null,   v_aisha_off,  'Aisha Khan'),
    (v_staff_id,   'hospital_staff', v_aku,  null,         'AKU Records Desk')
  on conflict (user_id) do update
    set role        = excluded.role,
        hospital_id = excluded.hospital_id,
        officer_id  = excluded.officer_id,
        full_name   = excluded.full_name;
end$$;

-- helper is now a security risk if left exposed; lock it down.
revoke execute on function public._seed_demo_user(text, text) from public, anon, authenticated;
