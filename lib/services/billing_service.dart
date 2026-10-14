import '../models/user.dart';

/// ══════════════════════════════════════════════════════════════
/// BILLING — INTEGRATION POINT
///
/// This app has NO real payment processing wired in yet, on purpose:
/// charging real money requires a backend you control (to verify
/// payments via webhooks) plus a registered Stripe account and/or
/// Apple/Google developer accounts. None of that can be fabricated
/// client-side, and a client can never be trusted to self-report
/// "I paid" — that must be verified server-side.
///
/// This file is the single place to plug in real billing later:
///   - Web / Windows  -> Stripe Checkout + a backend webhook endpoint
///   - iOS / Android  -> RevenueCat (wraps Apple/Google In-App Purchase)
///
/// Recommended architecture:
///   1. User taps "Upgrade" in the app.
///   2. App calls startCheckout() below.
///   3. That opens a Stripe Checkout URL (web/desktop) or triggers a
///      RevenueCat purchase flow (iOS/Android).
///   4. Stripe/RevenueCat notifies YOUR backend via webhook when the
///      payment succeeds, renews, or is canceled.
///   5. Your backend — not this app — updates the user's `tier` and
///      `status` in the real database (see AuthService.adminUpdateUser
///      for the equivalent local-storage version of that same update).
///   6. The app polls or listens for that updated status and unlocks
///      Plus features (see AppSession.isPlus).
///
/// Until that's wired up, AuthService.signUp() marks new accounts as
/// SubStatus.active immediately so the rest of the app (and this demo)
/// works end-to-end. Flip that once real billing is live — see the
/// comment in auth_service.dart's signUp() method.
/// ══════════════════════════════════════════════════════════════

/// Centralized pricing — change these two numbers and every screen
/// that displays a price (signup, etc.) should
/// read from here instead of hardcoding strings.
class PricingConfig {
  static const double basicMonthlyPriceUsd = 4.99;
  static const double plusMonthlyPriceUsd = 9.99;

  static String priceLabel(UserTier tier) {
    switch (tier) {
      case UserTier.basic:
        return '\$${basicMonthlyPriceUsd.toStringAsFixed(2)} / month';
      case UserTier.plus:
        return '\$${plusMonthlyPriceUsd.toStringAsFixed(2)} / month';
      case UserTier.admin:
        return 'N/A';
    }
  }
}

/// Stub — replace the TODOs with real Stripe/RevenueCat calls.
class BillingService {
  /// Kick off a checkout flow for [tier]. On web/desktop this should
  /// open a Stripe Checkout session URL (created by your backend, which
  /// holds your secret API key — never put a Stripe secret key in the
  /// client). On iOS/Android, this should trigger a RevenueCat purchase.
  Future<void> startCheckout({
    required String userId,
    required UserTier tier,
  }) async {
    // TODO(web/desktop): call your backend to create a Stripe Checkout
    // Session for PricingConfig.priceLabel(tier), then launch the
    // returned session URL, e.g. with url_launcher:
    //   final url = await myBackend.createCheckoutSession(userId, tier);
    //   await launchUrl(Uri.parse(url));
    //
    // TODO(iOS/Android): call Purchases.purchasePackage(...) via the
    // `purchases_flutter` (RevenueCat) package, using an entitlement
    // that matches `tier`.
    throw UnimplementedError(
      'Wire this up to Stripe (web/desktop) or RevenueCat (iOS/Android) '
      'before calling startCheckout() in production.',
    );
  }

  /// Re-sync entitlement state after app restart / device switch.
  /// With RevenueCat this is `Purchases.restorePurchases()`; with Stripe
  /// this is typically "ask your backend for this user's current
  /// subscription status."
  Future<void> restorePurchases(String userId) async {
    // TODO: query your backend / RevenueCat, then call
    // AuthService.adminUpdateUser(userId, tier: ..., status: ...)
    // (or an equivalent non-admin "sync my own status" method) to
    // reflect the real subscription state locally.
    throw UnimplementedError('Wire this up before calling in production.');
  }
}
