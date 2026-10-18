# SKOUTAR audit report (2026-10-16)

**Scope and limits.** This is a static review of the project files: the Flutter code, the SQL migrations, the
`admin-users` Edge Function, config, assets and `.gitignore`. I could **not**: connect to your Supabase project,
run `flutter analyze/test/build`, run Lighthouse (needs a deployed URL), scan Git history (the zip has no `.git`),
check dependency CVEs (pub.dev is not reachable from my sandbox), or test backups. Anything that needs those is
listed under "You must do". Nothing here is a guarantee of security or legal compliance.

## Findings and what I did

### Critical
| # | Finding | Status |
|---|---|---|
| C1 | **The app pointed at the wrong Supabase project.** `supabase_config.dart` had URL and anon key for `xuqrmsjiftjwlhoqekpi`; every migration was run in `xmzdwoqvnnwhbnntziuk`. The key's embedded project id confirmed it. This is why signup said "email already in use" for an email that is not in your project, and why new tables/functions looked missing. | **Fixed (URL).** The key is now supplied at run time (see below) because I do not have the key for your project and must not guess it. |

### High
| # | Finding | Status |
|---|---|---|
| H1 | **Game pitch data silently truncated at 1000 rows.** `loadPitchesForUser` and the save-time id lookup had no paging; Supabase returns at most 1000 rows per request, so a pitcher with more pitches lost the rest from every stat. | **Fixed** in `storage_service.dart` (pages of 1000, stable order). |
| H2 | **Plans are not tied to payment.** `complete_signup()` takes `plan_id` from user-editable sign-up metadata, and `pitcher_limit_for()` / `get_my_entitlement()` ignore payment status, so anyone can pick Team (20 pitchers) free, and every account gets every feature. | **Not changed.** It matches "no payments active", but must be fixed before you charge: gate limits and tier on `status in ('trialing','active')` and set the plan from a verified payment webhook. |
| H3 | **Weak `admin-users` Edge Function** (wildcard CORS, no input validation, raw error text returned, could delete itself, unpaged user list). Nothing in the app calls it. | **Hardened** (origin allow-list, validation, 12+ char passwords, no self-delete, generic errors, size limit, paging, no admin creation). **Recommended: delete it** if unused: `supabase functions delete admin-users`. |
| H4 | **RLS on `profiles` and `pitch_events` cannot be confirmed.** The original `supabase_schema.sql` is not in the project. The migrations that exist are sound (users cannot change tier/status/terms, pitcher ownership is enforced by trigger, subscription tables are read-only to clients, functions are `SECURITY DEFINER` with a fixed `search_path` and restricted `EXECUTE`). | **Needs your run:** `supabase_security_audit.sql` (read-only) and `supabase_pitchers_tests.sql`. |

### Medium
| # | Finding | Status |
|---|---|---|
| M1 | Terms/Privacy URLs in `legal_config.dart` are empty, so the sign-up links go nowhere. No Refund or Cookie policy existed. | **Drafts added** in `web/legal/` (privacy, terms, refunds, cookies), marked DRAFT with `[BRACKETED]` blanks. They need your details and a lawyer's review, then fill `termsUrl` / `privacyUrl`. |
| M2 | Password rules were client-side only (8 chars). | Client minimum raised to **10** with a letter and a number. Real enforcement must be set in the Supabase dashboard (below). |
| M3 | `supabase_pitchers_tests.sql` was stale (old column names, limits 1/3/20, functions that no longer exist). | **Rewritten** to match the real migration, plus cross-account, escalation and anon tests. |
| M4 | Dead file `admin_panel_screen.dart` called admin methods that no longer exist in `auth_service.dart` (would fail `flutter analyze`). | **Removed** (unreferenced; your old copy is still in `SKOUTAR_old`). |
| M5 | No security headers on the web build (cannot be set from Flutter). | Added `Referrer-Policy` meta. Headers must be set at your host (below). |
| M6 | Removed ("archived") pitchers keep their data forever; youth data. | Documented in the draft privacy policy; **needs your decision** and legal review (see Children). |
| M7 | `.gitignore` did not exclude env/secret/keystore files. | **Fixed.** |

### Low / notes
- `is_username_available()` is callable signed-out, so usernames can be enumerated (low risk, needed for sign-up).
- `invite_member_by_username()` is a leftover from the old family model; the pitchers migration dropped the unique username index it relies on. Consider removing the invite functions.
- `savePitchesForUser` upserts the whole pitch list on each save: correct but O(n) writes; fine now, worth batching later.
- Fonts: Teko ships with `OFL.txt` (license on file). **`logo.png`, `logo_watermark.png`, `field_bg.png`: I cannot verify you own these.**
- Accessibility: only ~8 `Semantics` labels in the app; icon buttons and charts need labels and a contrast check. Not changed.
- Children: pitchers may be minors. If under-13s could use the app directly, COPPA-style parental consent applies; the draft assumes an adult account owner. **Needs qualified legal review.**
- I found no service-role or secret keys in the app code. `.gitignore` aside, I could not check Git history.

## What changed (files)
`lib/services/supabase_config.dart` · `lib/services/storage_service.dart` · `lib/services/legal_config.dart` ·
`.gitignore` · `web/index.html` · `web/legal/*.html` (new) · `supabase/functions/admin-users/index.ts` ·
`supabase_pitchers_tests.sql` · `supabase_security_audit.sql` (new) · `lib/screens/admin_panel_screen.dart` (removed).

## You must do
1. **Run with your key** (project `xmzdwoqvnnwhbnntziuk`, Dashboard → Project Settings → API → anon/publishable key):
   `flutter run -d windows --dart-define=SUPABASE_ANON_KEY=PASTE_KEY_HERE`
   Same flag on `flutter build web`. Without it the app stops at startup with a clear message. **Never use the secret/service_role key.**
2. **Run `supabase_security_audit.sql`** in the SQL Editor and send me the results. Then run the tests in `supabase_pitchers_tests.sql` (fill in two user ids).
3. **Dashboard settings:** Authentication → Providers → Email: *Confirm email* on, minimum password length 10+, enable leaked-password protection if your plan has it; enable **MFA** on your admin account and on Supabase/GitHub/hosting accounts; Authentication → URL Configuration: set Site URL and only your real redirect URLs; Rate Limits: keep defaults or tighter; use custom SMTP (the built-in sender is rate limited, which caused your "email rate limit" error); consider CAPTCHA on sign-up.
4. **Edge function:** delete `admin-users` if unused. If kept, set `ALLOWED_ORIGINS` and enable MFA for admins.
5. **Web headers** at your host (test after enabling; Flutter web needs `wasm-unsafe-eval` and Google's CanvasKit host): `Strict-Transport-Security: max-age=31536000`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` (or `frame-ancestors 'none'`), `Referrer-Policy: strict-origin-when-cross-origin`, plus a Content-Security-Policy that allows `https://xmzdwoqvnnwhbnntziuk.supabase.co` for `connect-src`.
6. **Git:** `git ls-files | findstr /i "\.env key pem"` to confirm no secrets are tracked, and `git log --all --oneline -S"service_role"` to check history. If a real secret was ever committed, rotate it in Supabase; the anon key is public by design and does not need rotation.
7. **Dependencies:** run `flutter pub outdated`, then `flutter pub upgrade` (and test); there is no built-in CVE scanner for pub, so also watch advisories for `supabase_flutter`, `pdf`, `printing`, `url_launcher`.
8. **Backups:** Dashboard → Database → Backups (paid plans have daily backups). On any plan: `pg_dump "postgresql://postgres:<DB_PASSWORD>@db.xmzdwoqvnnwhbnntziuk.supabase.co:5432/postgres" -Fc -f skoutar.dump`, then restore into a scratch project with `pg_restore` to prove it works.
9. **Verify:** `flutter analyze`, `flutter test`, `flutter build web --dart-define=SUPABASE_ANON_KEY=...`, then Lighthouse on the deployed URL.
10. **Legal:** fill in and publish `web/legal/*`, set the two URLs in `legal_config.dart`, decide the minors/age rule and retention, and get legal review.
