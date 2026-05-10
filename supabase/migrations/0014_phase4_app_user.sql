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
