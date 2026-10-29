import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/subscription_plan.dart';
import '../models/user.dart';
import '../services/app_session.dart';
import '../services/legal_config.dart';
import '../services/plan_service.dart';
import '../services/supabase_config.dart';
import '../subscriptions/revenuecat_config.dart';
import '../subscriptions/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/orange_glow_button.dart';

/// Real subscription purchase screen (RevenueCat).
///
/// Shows Individual / Family / Team with a Monthly / Yearly switch, the store's
/// localized price for each, and buys the chosen product. Success is only
/// reported once RevenueCat confirms the `skoutar_pro` entitlement; the account
/// itself is marked paid by the verified server webhook, never by this screen.
///
/// [asGate]: shown right after login when nothing is paid yet; "Not now"
/// continues into the app.
class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key, this.asGate = false});
  final bool asGate;

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  List<SubscriptionPlan> _plans = SubscriptionPlan.fallback;
  late String _planId;
  late BillingInterval _interval;

  bool _busy = false;
  bool _rcConfirmed = false; // RevenueCat confirmed skoutar_pro in this visit
  String? _message;
  bool _messageOk = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppSession>().currentUser;
    _planId = user?.planId ?? 'individual';
    final meta = sb.auth.currentUser?.userMetadata;
    _interval = BillingIntervalX.fromString(
        (meta?['billing_interval'] as String?) ?? user?.billingInterval);
    _loadPlans();
    SubscriptionService.instance.refresh();
  }

  Future<void> _loadPlans() async {
    final r = await PlanService().fetchPlans();
    if (!mounted) return;
    setState(() {
      _plans = r.plans;
      if (!_plans.any((p) => p.id == _planId) && _plans.isNotEmpty) {
        _planId = _plans.first.id;
      }
    });
  }

  SubscriptionPlan get _plan =>
      _plans.firstWhere((p) => p.id == _planId, orElse: () => _plans.first);

  void _setMessage(String? m, {bool ok = false}) =>
      setState(() {
        _message = m;
        _messageOk = ok;
      });

  Future<void> _buy() async {
    final svc = SubscriptionService.instance;
    final session = context.read<AppSession>();
    final pkg = svc.packageFor(_planId, _interval);
    if (pkg == null) {
      return _setMessage(
          'This plan is not available to buy right now. Please try again later.');
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final out = await svc.purchase(pkg);
    if (!mounted) return;
    switch (out.status) {
      case PurchaseStatus.success:
        _rcConfirmed = true;
        _setMessage('Purchase confirmed by RevenueCat. Syncing your account…', ok: true);
        await _syncAccount(session);
      case PurchaseStatus.cancelled:
        _setMessage(null);
      case PurchaseStatus.alreadySubscribed:
        _rcConfirmed = true;
        _setMessage(out.message, ok: true);
        await _syncAccount(session);
      default:
        _setMessage(out.message ?? 'The purchase did not complete.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _syncAccount(AppSession session) async {
    final paid = await session.refreshEntitlement(waitForPaid: true);
    if (!mounted) return;
    _setMessage(
      paid
          ? 'You are subscribed to ${_plan.name} (${_interval.label.toLowerCase()}). Thank you!'
          : 'Your purchase is confirmed by RevenueCat, but your SKOUTAR account is '
              'still syncing. This can take a minute. You can continue; your plan '
              'updates automatically.',
      ok: true,
    );
  }

  Future<void> _restore() async {
    final svc = SubscriptionService.instance;
    final session = context.read<AppSession>();
    setState(() {
      _busy = true;
      _message = null;
    });
    final out = await svc.restore();
    if (!mounted) return;
    if (out.isSuccess) {
      _rcConfirmed = true;
      _setMessage('Purchases restored. Syncing your account…', ok: true);
      await _syncAccount(session);
    } else {
      _setMessage(out.message ?? 'Nothing to restore.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _manage() async {
    final svc = SubscriptionService.instance;
    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (_) {
      final url = svc.managementUrl;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _setMessage('Open your App Store / Google Play subscriptions to manage this plan.');
      }
    } finally {
      await svc.refresh();
      if (mounted) await context.read<AppSession>().refreshEntitlement();
    }
  }

  Future<void> _openLink(String url, String name) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The $name link has not been published yet.')),
      );
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _continue() {
    if (widget.asGate) {
      context.read<AppSession>().dismissSubscribePrompt();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ── pieces ──────────────────────────────────────────────────

  String _dateText(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _statusCard(AppUser? u, SubscriptionService svc) {
    String title;
    String detail;
    final subscribed = svc.hasPaidEntitlement || (u?.paid ?? false);
    if (subscribed) {
      final prod = svc.activeProduct;
      final plan = prod?.planId ?? u?.planId;
      final name = _plans.where((p) => p.id == plan).map((p) => p.name).firstOrNull ??
          u?.planName ??
          'SKOUTAR';
      final interval = prod?.interval.label ??
          (u?.billingInterval == null
              ? ''
              : BillingIntervalX.fromString(u!.billingInterval).label);
      title = 'Subscribed · $name${interval.isEmpty ? '' : ' · $interval'}';
      final end = svc.entitlementExpires ?? u?.periodEnd;
      final willRenew = svc.hasPaidEntitlement ? svc.entitlementWillRenew : !(u?.cancelAtPeriodEnd ?? false);
      detail = end == null
          ? 'Active'
          : willRenew
              ? 'Renews ${_dateText(end)}'
              : 'Ends ${_dateText(end)}';
      if (svc.hasPaidEntitlement && !(u?.paid ?? false)) {
        detail += ' · syncing with your account';
      }
    } else if (u?.subscriptionStatus == 'trialing' &&
        u?.trialEnd != null &&
        u!.trialEnd!.isAfter(DateTime.now())) {
      title = 'Free trial';
      detail = 'Trial ends ${_dateText(u.trialEnd!)}. Subscribe any time to keep access.';
    } else {
      title = 'No active subscription';
      detail = 'Choose a plan below.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.colBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 2),
          Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
        ],
      ),
    );
  }

  Widget _intervalToggle() {
    Widget seg(BillingInterval i) {
      final sel = _interval == i;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _busy ? null : () => setState(() => _interval = i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: sel ? AppColors.brandOrangeDeep : AppColors.colBorder, width: 2),
              color: sel ? AppColors.tint : Colors.white,
            ),
            child: Text(i.label,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: sel ? AppColors.brandOrangeDeep : AppColors.ink)),
          ),
        ),
      );
    }

    return Row(children: [
      seg(BillingInterval.monthly),
      const SizedBox(width: 8),
      seg(BillingInterval.yearly),
    ]);
  }

  /// "7-day free trial" etc. when the STORE product has a free intro offer.
  String? _storeTrialText(Package? pkg) {
    final intro = pkg?.storeProduct.introductoryPrice;
    if (intro == null || intro.price != 0) return null;
    final n = intro.periodNumberOfUnits;
    switch (intro.periodUnit) {
      case PeriodUnit.day:
        return '$n-day free trial';
      case PeriodUnit.week:
        return '${n * 7}-day free trial';
      case PeriodUnit.month:
        return '$n-month free trial';
      default:
        return 'Free trial included';
    }
  }

  Widget _planCard(SubscriptionPlan p, SubscriptionService svc, int pitcherCount) {
    final selected = _planId == p.id;
    final pkg = svc.packageFor(p.id, _interval);
    final live = svc.priceLabelFor(p.id, _interval); // localized, from RevenueCat
    final price = live ??
        (_interval == BillingInterval.monthly
            ? p.priceLabel
            : 'Price shown at checkout');
    final trial = _storeTrialText(pkg);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _busy ? null : () => setState(() => _planId = p.id),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? AppColors.brandOrangeDeep : AppColors.colBorder, width: 2),
          borderRadius: BorderRadius.circular(10),
          color: selected ? AppColors.tint : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20,
                  color: selected ? AppColors.brandOrangeDeep : AppColors.colMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink)),
              ),
              Text(price,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.brandOrangeDeep)),
            ]),
            const SizedBox(height: 4),
            Text(
              p.pitcherLimit == 1
                  ? '1 pitcher profile'
                  : 'Up to ${p.pitcherLimit} pitcher profiles',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            if (trial != null)
              Text(trial,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.perfExcellent)),
            if (pitcherCount > p.pitcherLimit)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'You have $pitcherCount pitcher profiles; this plan covers ${p.pitcherLimit}.',
                  style: const TextStyle(fontSize: 12, color: AppColors.colError),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final user = session.currentUser;
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: widget.asGate
          ? null
          : AppBar(title: const Text('Subscription')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListenableBuilder(
                listenable: SubscriptionService.instance,
                builder: (context, _) => _body(session, user),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppSession session, AppUser? user) {
    final svc = SubscriptionService.instance;
    final pkg = svc.packageFor(_planId, _interval);
    final canBuy = svc.isConfigured && pkg != null && !_busy && !svc.purchaseInFlight;
    final subscribed = svc.hasPaidEntitlement || (user?.paid ?? false);
    final buyLabel = pkg == null
        ? 'Subscribe'
        : 'Subscribe · ${pkg.storeProduct.priceString} / ${_interval.unit}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.asGate)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Start your SKOUTAR subscription',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink)),
          ),
        _statusCard(user, svc),
        if (!svc.isSupported)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Subscriptions are purchased in the SKOUTAR iOS or Android app. '
              'Your plan and status sync to your account.',
              style: TextStyle(fontSize: 12, color: AppColors.colMuted),
            ),
          )
        else if (!svc.isConfigured)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Purchases are not set up in this build yet.',
                style: TextStyle(fontSize: 12, color: AppColors.colError)),
          ),
        const Text('Choose your plan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        _intervalToggle(),
        const SizedBox(height: 10),
        if (svc.isConfigured && svc.isLoading && !svc.hasOfferings)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final p in _plans) _planCard(p, svc, session.pitchers.length),
        if (_message != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _messageOk ? const Color(0xFFEAF7EE) : const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _messageOk ? AppColors.colSuccess : AppColors.colError),
            ),
            child: Text(_message!, style: const TextStyle(fontSize: 13)),
          ),
        if (!subscribed || !_rcConfirmed)
          OrangeGlowButton(
            onPressed: canBuy && !subscribed ? _buy : null,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.brandOrangeDeep))
                : Text(subscribed ? 'You are subscribed' : buyLabel),
          ),
        if (_rcConfirmed || subscribed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OrangeGlowButton(
              onPressed: _continue,
              child: Text(widget.asGate ? 'Continue to SKOUTAR →' : 'Done'),
            ),
          ),
        const SizedBox(height: 8),
        if (svc.isConfigured)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: _busy ? null : _restore,
                child: const Text('Restore purchases'),
              ),
              if (subscribed)
                TextButton(
                  onPressed: _busy ? null : _manage,
                  child: const Text('Manage subscription'),
                ),
            ],
          ),
        if (widget.asGate && !_rcConfirmed)
          Center(
            child: TextButton(
              onPressed: _busy ? null : _continue,
              child: const Text('Not now'),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Payment is charged to your Apple ID or Google Play account when you '
          'confirm. Subscriptions renew automatically at the price shown unless '
          'cancelled in your store account settings at least 24 hours before the '
          'period ends.',
          style: TextStyle(fontSize: 11, color: AppColors.colMuted),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => _openLink(LegalConfig.termsUrl, 'Terms of Service'),
              child: const Text('Terms of Service'),
            ),
            TextButton(
              onPressed: () => _openLink(LegalConfig.privacyUrl, 'Privacy Policy'),
              child: const Text('Privacy Policy'),
            ),
          ],
        ),
      ],
    );
  }
}
