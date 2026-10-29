# SKOUTAR: RevenueCat purchases

Not compiled or run by whoever wrote it. Run `flutter pub get` and `flutter analyze` first and fix anything it reports.

## How the six products connect
`lib/subscriptions/revenuecat_config.dart` is the only place that knows the RevenueCat ids.

| Plan / interval     | Offering             | Product (RevenueCat Product ID) |
|---------------------|----------------------|----------------------------------|
| Individual monthly  | `individual_monthly` | `monthly`                        |
| Individual yearly   | `individual_yearly`  | `yearly`                         |
| Family monthly      | `family_monthly`     | `family_monthly`                 |
| Family yearly       | `family_yearly`      | `family_yearly`                  |
| Team monthly        | `team_monthly`       | `team_monthly`                   |
| Team yearly         | `team_yearly`        | `team_yearly`                    |

`SubscriptionService.packageFor(plan, interval)` fetches offerings, opens the plan's offering, and picks the package whose store product matches (Google Play `id:base-plan` suffixes are ignored). If that offering doesn't contain it, any offering that does is used (this is how the Individual products also resolve through `default`). All six share the entitlement `skoutar_pro`.

## Purchase flow
Plan -> Account -> Pitcher -> More pitchers -> Review is unchanged. The plan step now has a Monthly/Yearly switch and shows RevenueCat's localized price when loaded (iOS/Android), else the database reference price. Creating the account charges nothing.
Payment happens right after the first login (sign-up signs you out, and email confirmation may be on), in `SubscribeScreen`:
- shown automatically after login when nothing is paid and there is no real trial left, or the account is under 24 hours old; "Not now" continues into the app
- always reachable: Account dialog -> Subscription
- the screen only reports success when RevenueCat says `skoutar_pro` is active; it then re-reads the server and says plainly if the account is still syncing

## Who decides what is paid
- Client: `SubscriptionService` shows what RevenueCat/the store say. It never writes subscription data.
- Server: RevenueCat webhook -> Edge Function `revenuecat-webhook` (shared-secret check) -> `apply_revenuecat_event()` (service_role only) -> `user_subscriptions`. The plan comes from the purchased PRODUCT id via `revenuecat_product_plans`, so a Family purchase can't become Individual, and the client cannot name its own plan or price.
- App reads `get_my_entitlement()` (now also returns `paid`, `current_period_end`, `cancel_at_period_end`, `billing_interval`).
- Pitcher limits keep coming from `subscription_plans.max_pitchers` for the plan on the account.

## Setup you must do
1. Apply the patch, `flutter pub get`.
2. Supabase SQL Editor: run `supabase_revenuecat_migration.sql`.
3. Webhook secret + deploy:
   `supabase secrets set REVENUECAT_WEBHOOK_AUTH="<long random string>"`
   `supabase functions deploy revenuecat-webhook --no-verify-jwt`
4. RevenueCat dashboard -> Integrations -> Webhooks: URL `https://xmzdwoqvnnwhbnntziuk.supabase.co/functions/v1/revenuecat-webhook`, Authorization header = the same string.
5. Keys (public SDK keys only, never `sk_`):
   - Debug: the Test Store key is built in for `flutter run`.
   - Release: `--dart-define=REVENUECAT_API_KEY_IOS=appl_...` and `--dart-define=REVENUECAT_API_KEY_ANDROID=goog_...` (a Test Store key does not work in release).
6. Customer Center: enable it in RevenueCat (used by "Manage subscription").

## Testing in Test Store
Run on an Android or iOS device/emulator: `flutter run -d <device> --dart-define=SUPABASE_ANON_KEY=...`. Purchases do not run on Windows or Web (the screen says so).
