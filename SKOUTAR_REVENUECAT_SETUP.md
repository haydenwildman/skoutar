# SKOUTAR: RevenueCat purchases (v3.1)

Not compiled or run by whoever wrote it. Run `flutter pub get` and `flutter analyze` first and fix anything it reports.
The SQL and the webhook were exercised only against a throwaway local Postgres (PGlite) built from your real accounts and pitchers migrations, never against your Supabase project or RevenueCat.

## How the six products connect
`lib/subscriptions/revenuecat_config.dart` is the only place in the app that knows the RevenueCat ids. They are unchanged.

| Plan / interval     | Offering             | Product (RevenueCat Product ID) | Pitchers |
|---------------------|----------------------|----------------------------------|----------|
| Individual monthly  | `individual_monthly` | `monthly`                        | 1        |
| Individual yearly   | `individual_yearly`  | `yearly`                         | 1        |
| Family monthly      | `family_monthly`     | `family_monthly`                 | 4        |
| Family yearly       | `family_yearly`      | `family_yearly`                  | 4        |
| Team monthly        | `team_monthly`       | `team_monthly`                   | 20       |
| Team yearly         | `team_yearly`        | `team_yearly`                    | 20       |

All six share the entitlement `skoutar_pro`. **Prices are whatever you configured in RevenueCat / the stores.** Nothing in the SQL or the webhook stores or checks a price; the app shows RevenueCat's localized price, and `subscription_plans.monthly_price_cents` is only a display fallback (the migration does not touch it).

`SubscriptionService.packageFor(plan, interval)` opens the plan's offering and picks the package whose store product matches (Google Play `id:base-plan` suffixes are ignored); if that offering lacks it, any offering that has it is used.

## Access model (unchanged)
- **Everyone gets Plus.** `get_my_entitlement()` always returns `tier: plus`. A refund, expiry or no purchase never locks a feature.
- **The subscription decides the plan, and the plan decides the pitcher limit** (`subscription_plans.max_pitchers`: Individual 1, Family 4, Team 20). The migration *checks* these values and the all-Plus setting before it changes anything, and stops with a message if they differ. It does not overwrite them.
- Consequence to be aware of: the pitcher limit follows `user_subscriptions.plan_id`, not payment status. After a refund or expiry the account keeps its plan's limit (exactly as an unpaid `pending` account already keeps the plan chosen at sign-up). Only `paid` / `subscription_status` change. If you later want the limit to drop when payment stops, that is a separate change to `pitcher_limit_for()`.
- Dropping to a smaller plan never deletes pitchers; it only blocks adding more.

## Purchase flow
Plan -> Account -> Pitcher -> More pitchers -> Review is unchanged. Creating the account charges nothing. Payment happens right after the first login, in `SubscribeScreen`, also reachable from Account dialog -> Subscription. The screen reports success only when RevenueCat says `skoutar_pro` is active, then re-reads the server and says plainly if the account is still syncing.

## Who decides what is paid
- Client: `SubscriptionService` shows what RevenueCat/the store say. It never writes subscription data.
- Server: RevenueCat webhook -> Edge Function `revenuecat-webhook` (shared-secret check) -> `apply_revenuecat_event()` (service_role only) -> `user_subscriptions`. The plan comes from the purchased PRODUCT id via `revenuecat_product_plans`.
- App reads `get_my_entitlement()`: `paid` = status `active`/`past_due` and the period has not ended. A cancelled subscription whose period is still running is `paid: true` with `cancel_at_period_end: true`.

## How each RevenueCat event is handled
Field names and meanings are from RevenueCat's webhook docs (body is `{ "api_version": ..., "event": { ... } }`; `cancel_reason` appears on CANCELLATION, `expiration_reason` on EXPIRATION).

| Event (reason) | Status | Access / period fields |
|---|---|---|
| INITIAL_PURCHASE, RENEWAL | `active` (`trialing` if `period_type` = TRIAL) | `plan_id` from product; `current_period_end` = `expiration_at_ms`; `cancel_at_period_end` = false |
| UNCANCELLATION | `active` | as above; flag cleared |
| SUBSCRIPTION_EXTENDED | `active` | new `current_period_end`; auto-renew flag left alone |
| PRODUCT_CHANGE | `active` | upgrade or same size: new plan now. **Downgrade while paid: kept on the current plan until the RENEWAL that carries the new product** (RevenueCat: the new product "isn't necessarily in effect immediately") |
| CANCELLATION (UNSUBSCRIBE, DEVELOPER_INITIATED, PRICE_INCREASE, UNKNOWN) | **unchanged** | `cancel_at_period_end` = true. **Period end kept. Access continues** until EXPIRATION |
| CANCELLATION (CUSTOMER_SUPPORT = refund) | `canceled` | `current_period_end` = now (access ends now); end reason `refund` |
| CANCELLATION (BILLING_ERROR) | `past_due` | not an expiry; period end moves to the grace-period end if RevenueCat sends one |
| BILLING_ISSUE | `past_due` | same; recovers on the next RENEWAL |
| EXPIRATION (UNSUBSCRIBE, BILLING_ERROR, PRICE_INCREASE, SUBSCRIPTION_PAUSED, UNKNOWN) | `expired` | `current_period_end` = min(expiration, now) |
| EXPIRATION (CUSTOMER_SUPPORT = refund, DEVELOPER_INITIATED = revoked) | `canceled` | access ends now; end reason `refund` / `revoked` |
| REFUND_REVERSED (App Store) | `active` | access restored to the event's `expiration_at_ms`; auto-renew flag left as recorded |
| SUBSCRIPTION_PAUSED | no change | RevenueCat: "Don't revoke access on this event"; the EXPIRATION that follows ends access |
| TEMPORARY_ENTITLEMENT_GRANT | no change | <=24h stop-gap with partial data; an INITIAL_PURCHASE or EXPIRATION follows |
| TRANSFER, NON_RENEWING_PURCHASE, INVOICE_ISSUANCE, TEST, anything new | no change | logged in `revenuecat_events` only |

Guards: events for a product the account has since moved off are ignored; an event older than one already applied (`event_timestamp_ms`) is `stale`; a purchase with an unknown product, no expiration date, or an expiration already in the past is logged and ignored (a missing date would otherwise mean "forever"). Anonymous RevenueCat ids and ids that are not a SKOUTAR account are ignored.

## Retry and duplicate handling
- Every event is written to `revenuecat_events` first (audit trail, never deleted). New columns: `processed_at`, `attempts`, `last_attempt_at`, `last_error`.
- An event is **done** only when `processed_at` is set. Results beginning `retry` (`retry_no_subscription_row`, or `retry_error` for an unexpected database error, whose partial changes are rolled back) leave it pending.
- The Edge Function answers those with HTTP 500, so RevenueCat redelivers the same event id (5 retries, about 80 minutes). A redelivery of a pending event is processed, not discarded as a duplicate. Done events return `duplicate` and change nothing.
- If the account's `user_subscriptions` row appears after RevenueCat has stopped retrying, a trigger on that table replays the account's pending events oldest-first, so a purchase made during sign-up is not lost. Anything else can be replayed by hand: `select public.replay_pending_revenuecat_events();`
- Upgrading from the earlier v3.0 file: its `retry_no_subscription_row` events were wrongly marked as seen. The migration leaves exactly those pending, and the replay applies them.

## Known limits
- TRANSFER events are logged but not applied: the body names the app user ids but carries no product or period. SKOUTAR purchases require a signed-in account, so this should be rare. Check the RevenueCat dashboard for the customer if one happens.
- The webhook trusts RevenueCat's event order only through `event_timestamp_ms`; there is no call back to RevenueCat's REST API to cross-check state.
- A downgrade deferral relies on RevenueCat sending RENEWAL with the new product at the boundary (it does).
- Auto-renew state after a refund or reversal is carried forward, not re-read from the store.

## Next steps (do in this order)
1. Apply the patch / copy the files, `flutter pub get`, `flutter analyze` (no app code changed in this round).
2. **Back up first:** Supabase dashboard -> Database -> Backups (or `pg_dump`).
3. Supabase SQL Editor: run `supabase_revenuecat_migration.sql` once. It runs as one transaction. If it stops with a message (missing earlier migration, plan limits changed), nothing was changed. Then run the checks at the bottom of the file: six products; plan limits 1 / 4 / 20.
4. Webhook secret + deploy:
   `supabase secrets set REVENUECAT_WEBHOOK_AUTH="<long random string>"`
   `supabase functions deploy revenuecat-webhook --no-verify-jwt`
5. RevenueCat dashboard -> Integrations -> Webhooks: URL `https://xmzdwoqvnnwhbnntziuk.supabase.co/functions/v1/revenuecat-webhook`, Authorization header = the same string.
6. In RevenueCat use "Send test event". Expected: HTTP 200, and a `revenuecat_events` row with `result = 'test'`.
7. Keys (public SDK keys only, never `sk_`): debug uses the built-in Test Store key; release needs `--dart-define=REVENUECAT_API_KEY_IOS=appl_...` and `--dart-define=REVENUECAT_API_KEY_ANDROID=goog_...`.
8. Enable Customer Center in RevenueCat (used by "Manage subscription").
9. Sandbox pass on a device, watching `select event_type, result, attempts, processed_at, last_error from revenuecat_events order by received_at desc;`: purchase -> `applied`; cancel in the store -> `applied_cancel_at_period_end` and the account stays paid; (Test Store/sandbox) refund -> `applied_refund`; confirm Family shows 4 pitchers.

## Testing in Test Store
Run on an Android or iOS device/emulator: `flutter run -d <device> --dart-define=SUPABASE_ANON_KEY=...`. Purchases do not run on Windows or Web (the screen says so).
