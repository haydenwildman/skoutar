-- ════════════════════════════════════════════════════════════════════
-- SKOUTAR pitcher + account security tests. Run in the Supabase SQL Editor
-- AFTER supabase_pitchers_migration.sql. Every block ends in ROLLBACK, so
-- nothing is saved.
--
-- Replace <OWNER_UID> with an account's id from auth.users, and <OTHER_UID>
-- with a DIFFERENT account's id. Each block says what is expected. A block
-- that "expects an error" must show an error; if it succeeds, that is a bug.
-- ════════════════════════════════════════════════════════════════════

-- TEST 1: plan limits are 1 / 4 / 20 and every plan unlocks everything.
select id, max_pitchers, grants_tier, active from public.subscription_plans order by sort_order;
-- expect: individual 1 plus / family 4 plus / team 20 plus

-- TEST 2: the Family limit is enforced by the database (owner already has 1).
begin;
update public.user_subscriptions set plan_id = 'family' where owner_id = '<OWNER_UID>';
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<OWNER_UID>','role','authenticated')::text, true);
select public.add_pitcher('Test Two',   'test_two_x',   array['baseball'], 'R');   -- ok
select public.add_pitcher('Test Three', 'test_three_x', array['softball'], 'L');   -- ok
select public.add_pitcher('Test Four',  'test_four_x',  array['baseball'], 'R');   -- ok (4 of 4)
select public.add_pitcher('Test Five',  'test_five_x',  array['baseball'], 'R');   -- expect error: Your plan allows up to 4 pitchers.
rollback;

-- TEST 3: clients cannot write pitchers directly (must use the functions).
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<OWNER_UID>','role','authenticated')::text, true);
insert into public.pitchers (owner_id, display_name, username) values ('<OWNER_UID>', 'Sneaky', 'sneaky_one');  -- expect: permission denied
rollback;
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<OWNER_UID>','role','authenticated')::text, true);
update public.pitchers set owner_id = '<OTHER_UID>' where owner_id = '<OWNER_UID>';                           -- expect: permission denied
rollback;

-- TEST 4: another account cannot see these pitchers.
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<OTHER_UID>','role','authenticated')::text, true);
select count(*) from public.pitchers where owner_id = '<OWNER_UID>';                                          -- expect: 0
rollback;

-- TEST 5: another account cannot archive, rename, or read the settings of someone else's pitcher.
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<OTHER_UID>','role','authenticated')::text, true);
select public.archive_pitcher('<OWNER_UID>');                                                                 -- expect error: Pitcher not found.
select public.update_pitcher('<OWNER_UID>', 'Hacked', 'hacked_x', array['baseball'], 'R');                    -- expect error: Pitcher not found.
rollback;

-- TEST 6: nobody can attach data to a pitcher that is not theirs, or read another account's data.
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<OTHER_UID>','role','authenticated')::text, true);
insert into public.bullpen_sessions (id, user_id, pitcher_id, bullpen_type, started_at)
  values ('rls-test-1', '<OTHER_UID>', '<OWNER_UID>', 'test', now());   -- expect error: That pitcher does not belong to this account
insert into public.bullpen_sessions (id, user_id, pitcher_id, bullpen_type, started_at)
  values ('rls-test-2', '<OWNER_UID>', '<OWNER_UID>', 'test', now());   -- expect error: row-level security policy
select count(*) from public.pitch_events where user_id = '<OWNER_UID>';                                      -- expect: 0
select count(*) from public.bullpen_pitches where user_id = '<OWNER_UID>';                                   -- expect: 0
rollback;

-- TEST 7: users cannot upgrade themselves or change billing/terms fields.
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<OWNER_UID>','role','authenticated')::text, true);
update public.profiles set tier = 'admin' where id = '<OWNER_UID>';                                           -- expect: permission denied
update public.user_subscriptions set plan_id = 'team', status = 'active' where owner_id = '<OWNER_UID>';     -- expect: permission denied
update public.subscription_plans set monthly_price_cents = 0;                                                 -- expect: permission denied
rollback;

-- TEST 8: signed-out requests get nothing.
begin;
set local role anon;
select count(*) from public.pitch_events;                                                                     -- expect error: permission denied
rollback;

-- TEST 9: existing accounts were backfilled with exactly one pitcher whose id = the account id.
select count(*) as accounts_without_pitcher
  from public.profiles p
 where not exists (select 1 from public.pitchers x where x.id = p.id);                                        -- expect: 0

-- TEST 10: pitcher usernames are unique within an account (case-insensitive).
select owner_id, lower(username), count(*) from public.pitchers where archived_at is null
 group by 1, 2 having count(*) > 1;                                                                           -- expect: no rows
