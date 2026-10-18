/// ══════════════════════════════════════════════════════════════
/// BILLING — INTEGRATION POINT (no payments are active)
///
/// Nothing in this app charges money or marks anyone as having paid.
/// Choosing a plan at sign-up only records WHICH plan was picked
/// (`user_subscriptions`, status 'trialing' if the plan has a trial_days value,
/// otherwise 'pending'). What a person can access is decided on the server by
/// `get_my_entitlement()`; the client can never self-report "I paid".
///
/// Prices, trial length and member limits live in `subscription_plans`
/// (editable in Supabase), not in app code.
///
/// To add real billing later, keep the same shape:
///   1. App asks YOUR backend to start checkout for a plan id.
///   2. Web/desktop -> Stripe Checkout; iOS -> Apple In-App Purchase;
///      Android -> Google Play Billing (often via RevenueCat). Apple and Google
///      require their own billing for digital subscriptions sold in their apps —
///      a web checkout does NOT automatically satisfy store rules.
///   3. The provider calls a WEBHOOK (Supabase Edge Function). It must verify
///      the provider's signature, then use the service-role key (server-side
///      only) to update `user_subscriptions` (status, current_period_end,
///      billing_provider / billing_customer_id / billing_subscription_id).
///   4. The app just re-reads get_my_entitlement().
///
/// The service-role key and any payment-provider secret key must never be put
/// in Flutter code, GitHub, or the public website.
/// ══════════════════════════════════════════════════════════════
class BillingService {
  /// Kick off checkout for [planId]. Not implemented on purpose.
  Future<void> startCheckout({required String planId}) async {
    throw UnimplementedError(
      'Billing is not active. Wire this to a backend-created Stripe Checkout '
      'session (web/desktop) or store billing (iOS/Android) first.',
    );
  }

  /// Re-sync entitlement after a restart / device switch. With real billing
  /// this asks the backend (or RevenueCat) for the current subscription state.
  Future<void> restorePurchases() async {
    throw UnimplementedError('Billing is not active.');
  }
}
