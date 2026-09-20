-- ============================================================
--  SUPABASE SECURITY AUDIT  ·  single-file, read-only
--  Paste into the Supabase SQL Editor and hit Run.
--
--  It only SELECTs from system catalogs. It reads no table data,
--  writes nothing, and sends nothing anywhere. Read it yourself
--  before running it — that is the point of shipping one file.
--
--  Findings are ordered worst-first.
--  https://nightfix-dev.netlify.app
-- ============================================================

with

-- anon/authenticated only exist on Supabase; degrade gracefully elsewhere
exposed_roles as (
  select rolname, oid from pg_roles where rolname in ('anon','authenticated')
),

-- 1. Tables in an API-exposed schema with RLS switched off.
rls_off as (
  select
    1 as sev, 'CRITICAL' as severity, 'RLS disabled' as check_name,
    n.nspname||'.'||c.relname as object,
    'Reachable through PostgREST with RLS off. Anyone holding the anon key can read '||
    'every row, and the anon key ships in your frontend bundle.' as detail,
    'alter table '||quote_ident(n.nspname)||'.'||quote_ident(c.relname)||' enable row level security;' as fix
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'r'
    and n.nspname = 'public'
    and not c.relrowsecurity
    and exists (
      select 1 from information_schema.role_table_grants g
      join exposed_roles r on r.rolname = g.grantee
      where g.table_schema = n.nspname and g.table_name = c.relname
    )
),

-- 2. RLS on, but not one policy: the table answers with zero rows, forever.
rls_no_policy as (
  select
    2 as sev, 'HIGH' as severity, 'RLS on, zero policies' as check_name,
    n.nspname||'.'||c.relname as object,
    'RLS is enabled but no policy exists, so every client query returns an empty set. '||
    'This is the usual cause of "my query works in the SQL editor but returns nothing in the app".' as detail,
    'Add a policy, or confirm this table is meant to be service-role only.' as fix
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'r' and n.nspname = 'public' and c.relrowsecurity
    and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
),

-- 3. A policy that lets anon read everything.
policy_open as (
  select
    1 as sev, 'CRITICAL' as severity, 'Policy open to anon' as check_name,
    p.schemaname||'.'||p.tablename||' · '||p.policyname as object,
    'Grants '||p.cmd||' to '||array_to_string(p.roles,', ')||' with an always-true condition. '||
    'If that is not deliberately public data, it is a leak.' as detail,
    'Replace the USING clause with a real predicate, e.g. (select auth.uid()) = user_id.' as fix
  from pg_policies p
  where p.schemaname = 'public'
    and (p.roles && array['anon','public']::name[])
    and coalesce(btrim(p.qual), 'true') = 'true'
),

-- 4. SECURITY DEFINER functions that PUBLIC can execute.
--    Postgres grants EXECUTE to PUBLIC by default: these are born open.
definer_public as (
  select
    1 as sev, 'CRITICAL' as severity, 'SECURITY DEFINER open to PUBLIC' as check_name,
    n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as object,
    'Runs with the owner''s privileges and EXECUTE was never revoked from PUBLIC, so the '||
    'anon key can call it. New functions are open by default — the REVOKE has to be in the '||
    'same migration that creates them.' as detail,
    'revoke execute on function '||n.nspname||'.'||p.proname||'('||
      pg_get_function_identity_arguments(p.oid)||') from public;' as fix
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef
    and n.nspname not in ('pg_catalog','information_schema','extensions','graphql','vault')
    and exists (
      select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE'
    )
),

-- 5. SECURITY DEFINER without a pinned search_path: privilege-escalation vector.
definer_searchpath as (
  select
    2 as sev, 'HIGH' as severity, 'SECURITY DEFINER without search_path' as check_name,
    n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as object,
    'Runs as its owner with a mutable search_path. A caller who can create objects in an '||
    'earlier schema can shadow a function this one calls and have it run as the owner.' as detail,
    'alter function '||n.nspname||'.'||p.proname||'('||
      pg_get_function_identity_arguments(p.oid)||') set search_path = '''';' as fix
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef
    and n.nspname not in ('pg_catalog','information_schema','extensions','graphql','vault')
    and not exists (
      select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg
      where cfg like 'search_path=%'
    )
),

-- 6. Views that run as their owner. Often fine — flagged for a decision, not as a bug.
views_definer as (
  select
    3 as sev, 'REVIEW' as severity, 'View runs as owner' as check_name,
    n.nspname||'.'||c.relname as object,
    'Without security_invoker the view executes with its owner''s rights, so RLS on the '||
    'underlying tables is not applied to the caller. This is CORRECT when the view itself '||
    'filters by auth.uid(); it is a leak when it does not. Check the definition before changing it.' as detail,
    'If the view does not filter by itself: alter view '||quote_ident(n.nspname)||'.'||
      quote_ident(c.relname)||' set (security_invoker = true);' as fix
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'v' and n.nspname = 'public'
    and not coalesce((
      select lower(option_value) in ('true','on')
      from pg_options_to_table(c.reloptions) where option_name = 'security_invoker'
    ), false)
    and exists (
      select 1 from information_schema.role_table_grants g
      join exposed_roles r on r.rolname = g.grantee
      where g.table_schema = n.nspname and g.table_name = c.relname
    )
),

-- 7. Secret-shaped columns on tables the API can reach.
secret_columns as (
  select
    2 as sev, 'HIGH' as severity, 'Secret-shaped column exposed' as check_name,
    col.table_schema||'.'||col.table_name||'.'||col.column_name as object,
    'A column whose name suggests a credential sits on a table reachable through the API. '||
    'Even behind RLS, a leaked row hands over a live secret.' as detail,
    'Move it to a separate table that only the service role can reach, or store a hash.' as fix
  from information_schema.columns col
  where col.table_schema = 'public'
    and col.column_name ~* '(password|passwd|secret|api_?key|private_key|access_token|refresh_token)'
    and exists (
      select 1 from information_schema.role_table_grants g
      join exposed_roles r on r.rolname = g.grantee
      where g.table_schema = col.table_schema and g.table_name = col.table_name
    )
),

-- 8. auth.uid() called per row instead of once. The single biggest RLS slowdown.
policy_initplan as (
  select
    3 as sev, 'PERFORMANCE' as severity, 'auth.uid() re-evaluated per row' as check_name,
    p.schemaname||'.'||p.tablename||' · '||p.policyname as object,
    'auth.uid() is called unwrapped, so Postgres evaluates it once per row instead of once '||
    'per query. On a large table this is the difference between 20 ms and 20 s.' as detail,
    'Wrap it: (select auth.uid()) instead of auth.uid().' as fix
  from pg_policies p
  where p.schemaname = 'public'
    and (coalesce(p.qual,'')||' '||coalesce(p.with_check,'')) ~ 'auth\.(uid|jwt|role)\(\)'
    and (coalesce(p.qual,'')||' '||coalesce(p.with_check,'')) !~* 'select\s+auth\.(uid|jwt|role)\(\)'
),

-- 9. A policy on a table that queries the same table: classic infinite recursion.
policy_recursion as (
  select
    2 as sev, 'HIGH' as severity, 'Possible policy recursion' as check_name,
    p.schemaname||'.'||p.tablename||' · '||p.policyname as object,
    'The policy expression references its own table. Postgres answers this with '||
    '"infinite recursion detected in policy for relation". Heuristic: confirm by reading the policy.' as detail,
    'Move the lookup into a SECURITY DEFINER function that bypasses RLS, and call that from the policy.' as fix
  from pg_policies p
  where p.schemaname = 'public'
    and (coalesce(p.qual,'')||' '||coalesce(p.with_check,'')) ~ ('\m'||p.tablename||'\M')
),

-- 10. Foreign keys with no supporting index. Heuristic: leading column only.
fk_no_index as (
  select
    3 as sev, 'PERFORMANCE' as severity, 'Foreign key without index' as check_name,
    con.conrelid::regclass::text||' · '||con.conname as object,
    'No index starts with this foreign key column, so every join and every cascading delete '||
    'scans the whole table.' as detail,
    'create index on '||con.conrelid::regclass::text||' ('||
      (select string_agg(quote_ident(a.attname), ', ')
         from unnest(con.conkey) k join pg_attribute a
           on a.attrelid = con.conrelid and a.attnum = k)||');' as fix
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where con.contype = 'f' and n.nspname = 'public'
    and not exists (
      select 1 from pg_index i
      where i.indrelid = con.conrelid and i.indkey[0] = con.conkey[1]
    )
),

-- 11. Extensions living in public: they crowd the namespace the API exposes.
ext_in_public as (
  select
    3 as sev, 'REVIEW' as severity, 'Extension installed in public' as check_name,
    e.extname as object,
    'Its functions and types land in the schema PostgREST exposes, widening the API surface.' as detail,
    'create schema if not exists extensions; alter extension '||e.extname||' set schema extensions;' as fix
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where n.nspname = 'public' and e.extname not in ('plpgsql')
),

all_findings as (
  select * from rls_off
  union all select * from rls_no_policy
  union all select * from policy_open
  union all select * from definer_public
  union all select * from definer_searchpath
  union all select * from views_definer
  union all select * from secret_columns
  union all select * from policy_initplan
  union all select * from policy_recursion
  union all select * from fk_no_index
  union all select * from ext_in_public
)

select severity, check_name as check, object, detail, fix
from all_findings
order by sev, check_name, object;

-- ============================================================
--  Nothing came back? Then the eleven failure modes that cause
--  most Supabase production incidents are not present. Good.
--
--  Something came back and you want it fixed rather than
--  explained? That is what I do:  https://nightfix-dev.netlify.app
--  Flat $100, and you pay after it works.
-- ============================================================
