-- Phase 2 hardening: clamp pg_class.reltuples at 0.
--
-- After bulk INSERTs without an explicit ANALYZE, reltuples can be -1
-- (Postgres uses negative values to mean "stats are stale, planner should
-- re-estimate"). The /dev/schema observatory was rendering "Seed rows -14".
-- greatest(..., 0) gives a sane lower bound for the UI.
--
-- This is a function replacement only; structure of the JSONB return is
-- unchanged.

create or replace function public.get_schema()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start    timestamptz := clock_timestamp();
  v_tables   jsonb;
  v_fks      jsonb;
  v_result   jsonb;
  v_duration numeric;
  v_rows     integer;
begin
  with cols as (
    select c.table_schema, c.table_name, c.column_name, c.ordinal_position,
           c.data_type, c.is_nullable = 'YES' as nullable, c.column_default
    from information_schema.columns c
    where c.table_schema = 'public'
  ),
  pks as (
    select kcu.table_schema, kcu.table_name, kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
      and tc.table_name      = kcu.table_name
    where tc.constraint_type = 'PRIMARY KEY' and tc.table_schema = 'public'
  ),
  uqs as (
    select kcu.table_schema, kcu.table_name, kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name
      and tc.table_schema    = kcu.table_schema
      and tc.table_name      = kcu.table_name
    where tc.constraint_type = 'UNIQUE' and tc.table_schema = 'public'
  ),
  fks_per_col as (
    select kcu.table_schema as from_schema, kcu.table_name as from_table,
           kcu.column_name as from_column, ccu.table_schema as to_schema,
           ccu.table_name  as to_table,    ccu.column_name as to_column
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on  tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on  ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema
    where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
  ),
  table_meta as (
    select t.table_name,
           coalesce(obj_description(format('public.%I', t.table_name)::regclass, 'pg_class'), '') as table_comment,
           c.relrowsecurity as rls_enabled,
           greatest(c.reltuples::bigint, 0) as row_count_estimate
    from information_schema.tables t
    join pg_class    c on c.relname = t.table_name
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
  ),
  table_columns as (
    select cols.table_name,
      jsonb_agg(
        jsonb_build_object(
          'name',           cols.column_name,
          'type',           cols.data_type,
          'nullable',       cols.nullable,
          'default',        cols.column_default,
          'is_primary_key', exists (select 1 from pks p where p.table_name = cols.table_name and p.column_name = cols.column_name),
          'is_unique',      exists (select 1 from uqs u where u.table_name = cols.table_name and u.column_name = cols.column_name),
          'is_foreign_key', exists (select 1 from fks_per_col f where f.from_table = cols.table_name and f.from_column = cols.column_name),
          'references',     (select jsonb_build_object('table', f.to_table, 'column', f.to_column)
                             from fks_per_col f
                             where f.from_table = cols.table_name and f.from_column = cols.column_name limit 1)
        ) order by cols.ordinal_position
      ) as columns
    from cols group by cols.table_name
  )
  select jsonb_agg(
    jsonb_build_object(
      'name', tm.table_name,
      'comment', tm.table_comment,
      'rls_enabled', tm.rls_enabled,
      'row_count', tm.row_count_estimate,
      'columns', coalesce(tc.columns, '[]'::jsonb)
    ) order by tm.table_name
  )
  into v_tables
  from table_meta tm
  left join table_columns tc on tc.table_name = tm.table_name;

  select jsonb_agg(
    jsonb_build_object('from_table', from_table, 'from_column', from_column,
                       'to_table', to_table, 'to_column', to_column)
  )
  into v_fks
  from (
    select distinct kcu.table_name as from_table, kcu.column_name as from_column,
                    ccu.table_name as to_table,   ccu.column_name as to_column
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema
    where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
  ) distinct_fks;

  v_result := jsonb_build_object(
    'tables',       coalesce(v_tables, '[]'::jsonb),
    'foreign_keys', coalesce(v_fks,    '[]'::jsonb),
    'generated_at', now()
  );

  v_rows := jsonb_array_length(coalesce(v_tables, '[]'::jsonb));
  v_duration := extract(epoch from (clock_timestamp() - v_start)) * 1000;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned, plan)
  values ('get_schema', 'select table & fk metadata from information_schema',
          null, v_duration, v_rows, null);

  return v_result;
end
$$;
