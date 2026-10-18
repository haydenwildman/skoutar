# SKOUTAR pitcher-profiles update

## Apply (in order)
1. Copy these files over your project (same folders). Do not touch `supabase_config.dart`.
2. Supabase SQL Editor: run `supabase_pitchers_migration.sql` (after the earlier accounts migration). Safe to run twice; deletes nothing.
3. `flutter pub get`, fully restart the app.
4. Optional: run `supabase_pitchers_tests.sql` blocks (each rolls back) and `flutter test test/pitcher_form_test.dart`.

## What now works (written, NOT yet run - no Flutter or database in my sandbox)
- Every plan unlocks every feature. Lock icons and `requiresPlus`/`isPlus` gating are gone from the sidebar and shell; `AppUser.isPlus` is always true so any other screen that still asks gets "yes".
- Plans: Individual = 1 pitcher, Family = 3, Team = 20 (database trigger enforces it). Prices untouched.
- Create Account: Plan -> Account (owner email + password) -> Pitchers. Individual shows one form; Family/Team show an Add Pitcher button until the limit. Each pitcher saved as its own row. Pitcher 1 is the account's own profile.
- Account dialog (click the name in the sidebar): lists pitchers, "2 of 3" counter, Add Pitcher, Remove (frees a slot; data kept).
- Existing accounts: each gets one pitcher with the same id as the user, so existing data stays attached.

## Not done yet - needs files I don't have
- Sidebar profile switcher that reloads games / pitches / stats / scouting / bullpen per pitcher.
- Bullpen tab: removing its own hand selector and reading the active pitcher's profile.
- Re-keying game / pitch / bullpen tables to `pitcher_id` and their RLS.
Until those are done, ALL saved game and bullpen data is still keyed to the account owner, so adding pitchers does not yet separate their data.
- Pitchers with their own logins (schema is ready: `pitchers.auth_user_id`); needs an Edge Function for invites.
- Payments (none exist).

## Files
New: supabase_pitchers_migration.sql, supabase_pitchers_tests.sql, test/pitcher_form_test.dart, lib/models/pitcher_profile.dart, lib/services/pitcher_service.dart, lib/widgets/pitcher_form.dart
Changed: lib/models/subscription_plan.dart, lib/models/user.dart, lib/services/auth_service.dart (signUp), lib/screens/signup_screen.dart, lib/screens/account_dialog.dart, lib/screens/home_shell.dart, lib/widgets/sidebar_nav.dart
Database: new table `pitchers`; changed `subscription_plans` rows; replaced functions complete_signup, is_username_available; new functions add_pitcher, update_pitcher, remove_pitcher, username_taken, assert_valid_pitcher.
