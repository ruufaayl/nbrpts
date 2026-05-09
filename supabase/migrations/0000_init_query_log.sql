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
