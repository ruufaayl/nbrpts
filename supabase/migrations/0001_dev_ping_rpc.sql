-- Phase 1: a self-contained tracked query the /dev observatory can fire.
-- Runs `select now()`, captures wall-clock duration, captures the EXPLAIN
-- (FORMAT JSON) plan, and writes a query_log row that streams to clients
-- via Realtime.

create or replace function public.dev_ping()
returns public.query_log
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start    timestamptz := clock_timestamp();
  v_now      timestamptz;
  v_duration numeric;
  v_plan_txt text;
  v_plan     jsonb;
  v_row      public.query_log;
begin
  -- the tracked query itself
  select now() into v_now;

  v_duration := extract(epoch from (clock_timestamp() - v_start)) * 1000;

  -- capture the EXPLAIN plan for the same query
  begin
    execute 'EXPLAIN (FORMAT JSON) SELECT now()' into v_plan_txt;
    v_plan := v_plan_txt::jsonb;
  exception when others then
    v_plan := jsonb_build_object('error', SQLERRM);
  end;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned, plan)
  values ('dev_ping', 'select now()', null, v_duration, 1, v_plan)
  returning * into v_row;

  return v_row;
end
$$;

grant execute on function public.dev_ping() to anon, authenticated;

comment on function public.dev_ping() is
  'Demo RPC for /dev observatory: runs `select now()`, captures duration + EXPLAIN plan, appends to query_log.';
