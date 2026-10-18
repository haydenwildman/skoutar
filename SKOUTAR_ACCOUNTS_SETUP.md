# SKOUTAR accounts, plans & pitcher profiles — setup and review notes

## 1. Apply it (in this order)

1. Back up first if you can (Supabase -> Database -> Backups, or just export `pitch_events`).
2. Unzip over your project root. **It does not contain `lib/services/supabase_config.dart`** — your URL and key stay.
3. Delete the old lock screen (no longer used):
   `Remove-Item lib\screens\plus_lock_card.dart`
4. Supabase SQL Editor (project `xmzdwoqvnnwhbnntziuk`): `supabase_accounts_migration.sql` is already run.
   Now run **`supabase_pitchers_migration.sql`** (safe to re-run). Run it BEFORE starting the new app build.
5. `flutter pub get`, then fully restart `flutter run -d windows`.
6. Replace the deployed web build with this new one. An older web build keeps working for the account's
   first pitcher (the database fills in `pitcher_id`), but it can't switch pitchers and its per-pitcher settings
   won't match.

## 2. How it works

- **One login per account** (the owner). **Pitcher profiles** hang off it: name, username, sport(s), throwing hand.
- **Plans** (all features in every plan; only the pitcher limit differs): Individual 1, Family 4, Team 20.
  Limits live in `subscription_plans.max_pitchers` and are enforced by a database trigger, not just the UI.
- **Data separation:** every game/pitch/bullpen/challenge row has `pitcher_id`; `user_id` stays the owner
  (so existing RLS still works). A trigger rejects a row whose pitcher doesn't belong to the signed-in account,
  and blocks moving a row to another pitcher. The app loads only the active pitcher's rows and saves only to them.
- **Per-pitcher settings** (custom pitch types, batter names, colors, bullpen plan) moved from `profiles.settings`
  to `pitchers.settings` (copied for existing accounts).
- **Existing accounts:** each got one pitcher with the same id as the account, so all current data is attached
  automatically. They are recorded as the Individual plan. Nothing was deleted. `profiles.tier` is left alone
  but no longer limits any feature.
- **Switching:** click the name in the sidebar -> pick a pitcher. Add Pitcher appears while there's room.
  "Remove" archives the pitcher (hidden, data kept, stops counting toward the limit).
- **Bullpen** no longer asks for left/right. It uses the active pitcher's throwing hand and prompts to complete
  the profile if it's missing.
- **Free trial:** still blank until you set it, e.g. `update public.subscription_plans set trial_days = 14;`.

## 3. Manual Supabase settings

- Auth -> Providers -> Email: minimum password length 8+, leaked-password protection if available, decide on
  "Confirm email" (recommended).
- Auth -> URL Configuration: Site URL = your deployed web app URL (password-reset links land there).
- Auth -> Rate Limits: review sign-up / sign-in / email limits.
- Confirm RLS is on for every `public` table.

## 4. Tests to run (not run here — no Flutter or database access)

Flutter: `flutter test test/pitcher_test.dart test/bullpen_screens_test.dart`.

By hand:
1. Log in to an existing account: data is all there under one pitcher; Bullpen asks to complete the profile only if
   hand is missing.
2. Create a Family account with 4 pitchers; the 5th must be refused (button disabled, and the server rejects it).
3. Log pitches as pitcher A, switch to B: B sees none of A's. Log as B, switch back: A unchanged.
4. Start a bullpen as A and as B; confirm each appears only under its own pitcher.
5. Switch while a game is in progress: the live game clears (it belonged to the previous pitcher).

SQL attack tests (replace `<UID>`, `<OTHER_PITCHER>`; each should FAIL; roll back):
```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','<UID>','role','authenticated')::text, true);
insert into public.pitchers (owner_id, display_name, username) values ('<UID>','x','xxx');   -- permission denied
update public.pitchers set owner_id = '<UID>' where id = '<OTHER_PITCHER>';                  -- permission denied
update public.profiles set tier = 'admin' where id = '<UID>';                                -- permission denied
insert into public.pitch_events (id, user_id, pitcher_id, game, game_number, batter, season, ts)
  values ('t1','<UID>','<OTHER_PITCHER>','g',1,1,2026,now());                                -- not this account's pitcher
rollback;
```

## 5. Known gaps / decisions

- Pitchers have no separate logins yet. The table has a reserved `auth_user_id` so invited logins can be added later
  without another migration (needs invite + RLS work).
- Plan limits count active pitchers only; archiving frees a slot. Archiving does not delete data.
- If the original `profiles` table already has its own unique constraint on `username`, two accounts whose FIRST pitcher
  uses the same username will fail to sign up. Dropping that constraint fixes it; I couldn't see your live schema.
- No real billing. Everyone has every feature until billing exists. Needs Stripe (web/desktop), Apple IAP and Google
  Play Billing for mobile, and a webhook function that verifies signatures.
- Terms/Privacy URLs are empty (`lib/services/legal_config.dart`); get real documents before launch.
- The older `account_members` table and invite functions from the first migration are unused now (kept for a future
  pitcher-invite feature).
- Not tested on iOS/Android; no web-only APIs are used.
