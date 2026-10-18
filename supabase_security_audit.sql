-- ════════════════════════════════════════════════════════════════════
-- SKOUTAR security audit (READ-ONLY). Run in the SQL Editor of project
-- xmzdwoqvnnwhbnntziuk. It changes nothing; it only reports what is actually
-- configured, because a policy that exists is not proof that access is safe.
-- Send me the results of any block that returns rows marked PROBLEM.
-- ════════════════════════════════════════════════════════════════════

-- 1. Tables in public WITHOUT row level security. Expect: no rows.
select c.relname as table_without_rls
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

-- 2. Every policy. Read these: each user-data table should compare
--    auth.uid() to user_id (or owner_id), never "true".
select tablename, policyname, cmd, roles, qual as using_clause, with_check
  from pg_policies where schemaname = 'public' order by tablename, cmd, policyname;

-- 3. PROBLEM if any policy is wide open ("true") for anon or authenticated.
select tablename, policyname, cmd, roles
  from pg_policies
 where schemaname = 'public'
   and (coalesce(qual, '') in ('true', '(true)') or coalesce(with_check, '') in ('true', '(true)'))
   and tablename not in ('subscription_plans');          -- plans are meant to be public to read

-- 4. What the signed-out (anon) role can touch. Expect: only subscription_plans SELECT.
select table_name, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public' and grantee = 'anon'
 order by table_name, privilege_type;

-- 5. What signed-in users can write directly. profiles should allow UPDATE only on
--    a few harmless columns; tier/status/terms must NOT be updatable.
select table_name, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public' and grantee = 'authenticated'
   and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
 order by table_name, privilege_type;
select table_name, column_name, privilege_type
  from information_schema.column_privileges
 where table_schema = 'public' and grantee = 'authenticated' and privilege_type = 'UPDATE'
   and table_name in ('profiles', 'pitchers')
 order by table_name, column_name;

-- 6. SECURITY DEFINER functions that anon / PUBLIC can execute. Only
--    is_username_available is meant to be callable while signed out.
select p.proname as function_name,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_run,
       has_function_privilege('authenticated', p.oid, 'execute') as signed_in_can_run
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef
 order by 2 desc, 1;

-- 7. Storage buckets. PROBLEM if public = true for private data. (No buckets is fine.)
select id, name, public, file_size_limit, allowed_mime_types from storage.buckets;

-- 8. Admin accounts (should be only you).
select p.id, u.email, p.tier, p.status
  from public.profiles p join auth.users u on u.id = p.id
 where p.tier = 'admin';

-- 9. Data integrity after the pitcher migration. Expect 0 in every column.
select
  (select count(*) from public.pitch_events       where pitcher_id is null) as pitch_events_no_pitcher,
  (select count(*) from public.bullpen_sessions   where pitcher_id is null) as sessions_no_pitcher,
  (select count(*) from public.bullpen_pitches    where pitcher_id is null) as bullpen_pitches_no_pitcher,
  (select count(*) from public.challenge_attempts where pitcher_id is null) as attempts_no_pitcher,
  (select count(*) from public.profiles p where not exists
      (select 1 from public.pitchers x where x.owner_id = p.id)) as accounts_without_pitcher;

-- 10. Rows whose pitcher belongs to a DIFFERENT account than user_id. Expect 0.
select 'pitch_events' as tbl, count(*) from public.pitch_events t
  join public.pitchers p on p.id = t.pitcher_id where p.owner_id <> t.user_id
union all
select 'bullpen_sessions', count(*) from public.bullpen_sessions t
  join public.pitchers p on p.id = t.pitcher_id where p.owner_id <> t.user_id;

-- 11. Indexes for the columns the app filters on.
select tablename, indexname from pg_indexes
 where schemaname = 'public' and indexdef ilike '%pitcher_id%' order by tablename;
