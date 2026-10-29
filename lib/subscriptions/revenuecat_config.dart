import 'package:flutter/foundation.dart';

/// Billing interval of a SKOUTAR subscription.
enum BillingInterval { monthly, yearly }

extension BillingIntervalX on BillingInterval {
  String get label => this == BillingInterval.monthly ? 'Monthly' : 'Yearly';
  String get unit => this == BillingInterval.monthly ? 'month' : 'year';
  static BillingInterval fromString(String? s) =>
      s == 'yearly' ? BillingInterval.yearly : BillingInterval.monthly;
}

/// One purchasable SKOUTAR product and where it lives in RevenueCat.
class PlanProduct {
  const PlanProduct(this.planId, this.interval, this.offeringId, this.productId);

  /// SKOUTAR plan id in `subscription_plans`: individual | family | team.
  final String planId;
  final BillingInterval interval;

  /// RevenueCat offering that holds this product (as configured in the dashboard).
  final String offeringId;

  /// Store product identifier (RevenueCat Product ID).
  final String productId;
}

/// RevenueCat identifiers. They mirror the dashboard exactly; nothing here
/// creates or renames anything in RevenueCat.
class RevenueCatConfig {
  RevenueCatConfig._();

  /// Shared by all six products. Access = this entitlement is active.
  static const String entitlementId = 'skoutar_pro';

  /// Six plan x interval products, each in its own offering. (The `default`
  /// offering also holds the Individual monthly/yearly packages; the lookup in
  /// SubscriptionService.packageFor() falls back to any offering that contains
  /// the product.)
  static const List<PlanProduct> products = [
    PlanProduct('individual', BillingInterval.monthly, 'individual_monthly', 'monthly'),
    PlanProduct('individual', BillingInterval.yearly, 'individual_yearly', 'yearly'),
    PlanProduct('family', BillingInterval.monthly, 'family_monthly', 'family_monthly'),
    PlanProduct('family', BillingInterval.yearly, 'family_yearly', 'family_yearly'),
    PlanProduct('team', BillingInterval.monthly, 'team_monthly', 'team_monthly'),
    PlanProduct('team', BillingInterval.yearly, 'team_yearly', 'team_yearly'),
  ];

  static PlanProduct? lookup(String planId, BillingInterval interval) {
    for (final p in products) {
      if (p.planId == planId && p.interval == interval) return p;
    }
    return null;
  }

  /// Google Play ids can look like `family_monthly:base-plan`; compare the part
  /// before the colon.
  static String normalizeProductId(String id) => id.split(':').first;

  static PlanProduct? byProductId(String? id) {
    if (id == null) return null;
    final n = normalizeProductId(id);
    for (final p in products) {
      if (p.productId == n) return p;
    }
    return null;
  }

  // ── SDK keys ────────────────────────────────────────────────────────────
  // PUBLIC SDK keys only (never a RevenueCat secret `sk_` key). Supply at build
  // time, like SUPABASE_ANON_KEY:
  //   flutter run --dart-define=REVENUECAT_API_KEY=<key>            (one key for all platforms, e.g. Test Store)
  //   flutter build apk --dart-define=REVENUECAT_API_KEY_ANDROID=goog_...
  //   flutter build ios --dart-define=REVENUECAT_API_KEY_IOS=appl_...
  static const String _anyKey = String.fromEnvironment('REVENUECAT_API_KEY');
  static const String _iosKey = String.fromEnvironment('REVENUECAT_API_KEY_IOS');
  static const String _androidKey = String.fromEnvironment('REVENUECAT_API_KEY_ANDROID');

  /// Debug builds only: the project's RevenueCat Test Store public key, so
  /// `flutter run` works without a --dart-define. Release builds ignore this and
  /// need a real key (RevenueCat refuses Test Store keys in release builds).
  static const String _debugTestStoreKey = 'test_xZFMHRlvelkLGYpiqVZDzkFeGrn';

  /// Purchases run on iOS and Android only.
  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// The key for this platform, or null when none is configured (the app then
  /// simply shows "purchases unavailable" instead of failing).
  static String? get apiKey {
    if (!isPlatformSupported) return null;
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? _iosKey : _androidKey;
    if (platform.isNotEmpty) return platform;
    if (_anyKey.isNotEmpty) return _anyKey;
    if (kDebugMode) return _debugTestStoreKey;
    return null;
  }
}
