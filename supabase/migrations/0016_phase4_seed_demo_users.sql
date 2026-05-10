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
