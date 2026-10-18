/// One row of `public.subscription_plans`. Prices, trial length and member
/// limits all come from the database, so changing them never needs an app
/// release.
class SubscriptionPlan {
  final String id; // 'individual' | 'family' | 'team'
  final String name;
  final int monthlyPriceCents;
  final int? trialDays; // null / 0 = trial length not decided yet
  final int? maxPitchers; // pitcher profiles allowed; null = no limit
  final String description;
  final List<String> features;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.monthlyPriceCents,
    this.trialDays,
    this.maxPitchers,
    this.description = '',
    this.features = const [],
  });

  String get priceLabel =>
      '\$${(monthlyPriceCents / 100).toStringAsFixed(2)} / month';

  /// Pitcher profiles this plan allows (no limit if unset).
  int get pitcherLimit => maxPitchers ?? 1000;

  bool get hasTrialLength => (trialDays ?? 0) > 0;

  /// Short trial text for the plan card.
  String get trialLabel =>
      hasTrialLength ? '$trialDays-day free trial' : 'Free trial included';

  factory SubscriptionPlan.fromMap(Map<String, dynamic> m) => SubscriptionPlan(
        id: m['id'] as String,
        name: m['name'] as String,
        monthlyPriceCents: (m['monthly_price_cents'] as num).toInt(),
        trialDays: (m['trial_days'] as num?)?.toInt(),
        maxPitchers: (m['max_pitchers'] as num?)?.toInt() ?? (m['max_members'] as num?)?.toInt(),
        description: m['description'] as String? ?? '',
        features: ((m['features'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  /// Shown only if the database can't be reached / the migration hasn't been
  /// run yet. Display-only: the server still validates the plan on sign-up.
  static const List<SubscriptionPlan> fallback = [
    SubscriptionPlan(
      id: 'individual',
      name: 'Individual',
      monthlyPriceCents: 499,
      maxPitchers: 1,
      description: 'One pitcher profile with every SKOUTAR feature.',
      features: ['One pitcher profile', 'Every SKOUTAR feature'],
    ),
    SubscriptionPlan(
      id: 'family',
      name: 'Family',
      monthlyPriceCents: 1499,
      maxPitchers: 4,
      description: 'One shared login for up to 4 pitchers, every feature.',
      features: [
        'Up to 4 pitcher profiles',
        'One shared login, switch between pitchers',
        'Every SKOUTAR feature',
        "Each pitcher's stats stay separate",
      ],
    ),
    SubscriptionPlan(
      id: 'team',
      name: 'Team',
      monthlyPriceCents: 1999,
      maxPitchers: 20,
      description: 'One subscription for up to 20 pitchers, every feature.',
      features: [
        'Up to 20 pitcher profiles',
        'Switch between pitchers in one account',
        'Every SKOUTAR feature',
        "Each pitcher's stats stay separate",
      ],
    ),
  ];
}
