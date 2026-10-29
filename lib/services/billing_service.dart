import '../subscriptions/revenuecat_config.dart';
import '../subscriptions/subscription_service.dart';

/// ══════════════════════════════════════════════════════════════
/// BILLING (RevenueCat)
///
/// Real purchases are made through [SubscriptionService] (RevenueCat, entitlement
/// `skoutar_pro`). Nothing the app does can mark an account as paid: the
/// RevenueCat webhook (supabase/functions/revenuecat-webhook, signature-checked,
/// service-role only on the server) writes `user_subscriptions`, and the app
/// reads the result from the server function `get_my_entitlement()`.
///
/// This class is kept as a small facade so older call sites keep compiling.
/// ══════════════════════════════════════════════════════════════
class BillingService {
  final SubscriptionService _svc = SubscriptionService.instance;

  /// Buys [planId] ('individual' | 'family' | 'team') at [interval].
  Future<PurchaseOutcome> startCheckout({
    required String planId,
    BillingInterval interval = BillingInterval.monthly,
  }) async {
    final pkg = _svc.packageFor(planId, interval);
    if (pkg == null) {
      return const PurchaseOutcome(
          PurchaseStatus.unsupported, 'That plan is not available to buy right now.');
    }
    return _svc.purchase(pkg);
  }

  Future<PurchaseOutcome> restorePurchases() => _svc.restore();
}
