import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'revenuecat_config.dart';

enum PurchaseStatus {
  /// RevenueCat confirmed `skoutar_pro` is active.
  success,
  cancelled,
  pending,
  alreadySubscribed,

  /// Already subscribed to a DIFFERENT product: change it from Manage subscription.
  useManage,
  unsupported,
  failed,
}

class PurchaseOutcome {
  const PurchaseOutcome(this.status, [this.message]);
  final PurchaseStatus status;
  final String? message;
  bool get isSuccess => status == PurchaseStatus.success;
}

/// All RevenueCat access for SKOUTAR. A ChangeNotifier singleton (same style as
/// AppSession). It never decides what the account may do: that is the server's
/// get_my_entitlement(). This service only runs purchases and reports what the
/// store/RevenueCat say.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  bool _configured = false;
  bool _loading = false;
  bool _purchaseInFlight = false;
  String? _appUserId; // Supabase user id currently linked to RevenueCat
  CustomerInfo? _customerInfo;
  Offerings? _offerings;
  String? _error;

  bool get isSupported => RevenueCatConfig.isPlatformSupported;
  bool get isConfigured => _configured;
  bool get isLoading => _loading;
  bool get purchaseInFlight => _purchaseInFlight;
  String? get lastError => _error;
  CustomerInfo? get customerInfo => _customerInfo;
  Offerings? get offerings => _offerings;
  bool get hasOfferings => (_offerings?.all.isNotEmpty ?? false);

  // ── entitlement (client view; the server's copy is what grants access) ───
  EntitlementInfo? get entitlement =>
      _customerInfo?.entitlements.all[RevenueCatConfig.entitlementId];

  bool get hasPaidEntitlement => entitlement?.isActive ?? false;

  /// Which SKOUTAR product the active entitlement came from.
  PlanProduct? get activeProduct => hasPaidEntitlement
      ? RevenueCatConfig.byProductId(entitlement?.productIdentifier)
      : null;

  DateTime? get entitlementExpires {
    final raw = entitlement?.expirationDate;
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  bool get entitlementWillRenew => entitlement?.willRenew ?? false;

  String? get managementUrl => _customerInfo?.managementURL;

  // ── setup ────────────────────────────────────────────────────────────────

  /// Call once at startup. Never throws; with no key / unsupported platform it
  /// is a no-op and the app keeps working without purchases.
  Future<void> init() async {
    if (_configured || !isSupported) return;
    final key = RevenueCatConfig.apiKey;
    if (key == null || key.isEmpty) {
      _error = 'Purchases are not configured in this build.';
      return;
    }
    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      await refresh();
    } catch (e, st) {
      _error = 'Purchases could not start.';
      debugPrint('RevenueCat init failed: $e\n$st');
      notifyListeners();
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    _customerInfo = info;
    notifyListeners();
  }

  /// Link RevenueCat to the signed-in Supabase user (their auth uuid). The
  /// server webhook relies on this id to find the right account.
  Future<void> identify(String supabaseUserId) async {
    if (!_configured) return;
    try {
      final result = await Purchases.logIn(supabaseUserId);
      _customerInfo = result.customerInfo;
      _appUserId = supabaseUserId;
      _error = null;
    } catch (e) {
      _error = _friendly(e);
    }
    notifyListeners();
    await _loadOfferings();
  }

  /// Sign-out: detach RevenueCat from this account.
  Future<void> reset() async {
    _appUserId = null;
    if (!_configured) return;
    try {
      if (!await Purchases.isAnonymous) {
        _customerInfo = await Purchases.logOut();
      }
    } catch (e) {
      debugPrint('RevenueCat logOut: $e');
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!_configured) return;
    _loading = true;
    notifyListeners();
    try {
      _customerInfo = await Purchases.getCustomerInfo();
      _error = null;
    } catch (e) {
      _error = _friendly(e);
    }
    await _loadOfferings(notify: false);
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadOfferings({bool notify = true}) async {
    try {
      _offerings = await Purchases.getOfferings();
    } catch (e) {
      _error = _friendly(e);
    }
    if (notify) notifyListeners();
  }

  // ── products ─────────────────────────────────────────────────────────────

  /// The package for a plan + billing interval. Looks in that product's own
  /// offering first, then in any offering that contains the product (so the
  /// Individual products also resolve through the `default` offering).
  Package? packageFor(String planId, BillingInterval interval) {
    final ref = RevenueCatConfig.lookup(planId, interval);
    final all = _offerings?.all;
    if (ref == null || all == null) return null;

    Package? pick(Offering? o) {
      if (o == null) return null;
      for (final p in o.availablePackages) {
        if (RevenueCatConfig.normalizeProductId(p.storeProduct.identifier) ==
            ref.productId) {
          return p;
        }
      }
      return null;
    }

    final direct = pick(all[ref.offeringId]);
    if (direct != null) return direct;
    for (final o in all.values) {
      final p = pick(o);
      if (p != null) return p;
    }
    return null;
  }

  /// Localized price from the store, e.g. "$14.99 / month". Null if unavailable.
  String? priceLabelFor(String planId, BillingInterval interval) {
    final p = packageFor(planId, interval);
    return p == null
        ? null
        : '${p.storeProduct.priceString} / ${interval.unit}';
  }

  // ── purchase / restore ───────────────────────────────────────────────────

  Future<PurchaseOutcome> purchase(Package package) async {
    if (!_configured) {
      return const PurchaseOutcome(PurchaseStatus.unsupported,
          'Purchases are not available in this build or on this device.');
    }
    if (_purchaseInFlight) {
      return const PurchaseOutcome(
          PurchaseStatus.pending, 'A purchase is already in progress.');
    }
    // A purchase must belong to a signed-in SKOUTAR account, or the server
    // could never match it to anyone.
    try {
      if (_appUserId == null || await Purchases.isAnonymous) {
        return const PurchaseOutcome(
            PurchaseStatus.failed, 'Please sign in before subscribing.');
      }
    } catch (_) {
      return const PurchaseOutcome(
          PurchaseStatus.failed, 'Could not verify your account. Try again.');
    }

    // Retry / double-tap safety: never buy what is already active.
    await refresh();
    if (hasPaidEntitlement) {
      final wanted =
          RevenueCatConfig.normalizeProductId(package.storeProduct.identifier);
      return activeProduct?.productId == wanted
          ? const PurchaseOutcome(PurchaseStatus.alreadySubscribed,
              'You are already subscribed to this plan.')
          : const PurchaseOutcome(PurchaseStatus.useManage,
              'You already have an active SKOUTAR subscription. To switch plans, use Manage subscription.');
    }

    _purchaseInFlight = true;
    notifyListeners();
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _customerInfo = result.customerInfo;
      _error = null;
      // Only report success when RevenueCat itself says skoutar_pro is active.
      if (hasPaidEntitlement) {
        return const PurchaseOutcome(PurchaseStatus.success);
      }
      return const PurchaseOutcome(PurchaseStatus.failed,
          'The store finished, but RevenueCat has not activated SKOUTAR Pro. Try Restore purchases in a moment.');
    } on PlatformException catch (e) {
      switch (PurchasesErrorHelper.getErrorCode(e)) {
        case PurchasesErrorCode.purchaseCancelledError:
          return const PurchaseOutcome(PurchaseStatus.cancelled);
        case PurchasesErrorCode.paymentPendingError:
          return const PurchaseOutcome(PurchaseStatus.pending,
              'Your payment is pending approval. Access starts when it clears.');
        case PurchasesErrorCode.productAlreadyPurchasedError:
          await refresh();
          return hasPaidEntitlement
              ? const PurchaseOutcome(PurchaseStatus.alreadySubscribed,
                  'You are already subscribed.')
              : PurchaseOutcome(PurchaseStatus.failed, _friendly(e));
        default:
          _error = _friendly(e);
          return PurchaseOutcome(PurchaseStatus.failed, _error);
      }
    } catch (e) {
      _error = _friendly(e);
      return PurchaseOutcome(PurchaseStatus.failed, _error);
    } finally {
      _purchaseInFlight = false;
      notifyListeners();
    }
  }

  Future<PurchaseOutcome> restore() async {
    if (!_configured) {
      return const PurchaseOutcome(
          PurchaseStatus.unsupported, 'Purchases are not available here.');
    }
    try {
      _customerInfo = await Purchases.restorePurchases();
      _error = null;
      notifyListeners();
      return hasPaidEntitlement
          ? const PurchaseOutcome(PurchaseStatus.success)
          : const PurchaseOutcome(PurchaseStatus.failed,
              'No active SKOUTAR subscription was found for this store account.');
    } catch (e) {
      _error = _friendly(e);
      notifyListeners();
      return PurchaseOutcome(PurchaseStatus.failed, _error);
    }
  }

  String _friendly(Object e) {
    if (e is PlatformException) {
      switch (PurchasesErrorHelper.getErrorCode(e)) {
        case PurchasesErrorCode.networkError:
          return 'Network problem. Check your connection and try again.';
        case PurchasesErrorCode.purchaseNotAllowedError:
          return 'Purchases are not allowed on this device.';
        case PurchasesErrorCode.storeProblemError:
          return 'The app store had a problem. Please try again shortly.';
        case PurchasesErrorCode.receiptAlreadyInUseError:
          return 'That store purchase is already linked to another SKOUTAR account.';
        case PurchasesErrorCode.configurationError:
          return 'Subscription setup is incomplete. Please contact support.';
        default:
          return e.message ?? 'Something went wrong with your subscription.';
      }
    }
    return 'Something went wrong with your subscription.';
  }

  @override
  void dispose() {
    if (_configured) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    super.dispose();
  }
}
