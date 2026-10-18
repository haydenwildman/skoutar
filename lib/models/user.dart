/// Subscription / permission tier — mirrors the R app's `tier` column
/// ("basic", "plus"); "admin" is kept so existing admin accounts still parse
/// and keep Plus access.
enum UserTier { basic, plus, admin }

extension UserTierX on UserTier {
  String get label => switch (this) {
        UserTier.basic => 'basic',
        UserTier.plus => 'plus',
        UserTier.admin => 'admin',
      };

  static UserTier fromString(String s) {
    switch (s.toLowerCase().trim()) {
      case 'plus':
        return UserTier.plus;
      case 'admin':
        return UserTier.admin;
      default:
        return UserTier.basic;
    }
  }
}

/// Subscription status — mirrors R's `subscription_status` column.
enum SubStatus { active, inactive, pendingPayment, canceled }

extension SubStatusX on SubStatus {
  String get label => switch (this) {
        SubStatus.active => 'active',
        SubStatus.inactive => 'inactive',
        SubStatus.pendingPayment => 'pending_payment',
        SubStatus.canceled => 'canceled',
      };

  static SubStatus fromString(String s) {
    switch (s.toLowerCase().trim()) {
      case 'inactive':
        return SubStatus.inactive;
      case 'pending_payment':
        return SubStatus.pendingPayment;
      case 'canceled':
        return SubStatus.canceled;
      default:
        return SubStatus.active;
    }
  }
}

class AppUser {
  final String id; // uuid — matches auth.users.id in Supabase
  String username;
  String email;
  UserTier tier;
  SubStatus status;
  String pitcherDisplayName;
  DateTime createdAt;

  // Profile + subscription info (filled from `profiles` and the server-side
  // get_my_entitlement() function; display only — the server decides access).
  List<String> sports; // subset of ['baseball', 'softball']
  String? throwsHand; // 'R' | 'L'
  String? planId; // 'individual' | 'family' | 'team'
  String? planName;
  String? subscriptionStatus; // pending | trialing | active | ...
  DateTime? trialEnd;
  int maxPitchers; // how many pitcher profiles the plan allows

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.tier = UserTier.basic,
    this.status = SubStatus.active,
    String? pitcherDisplayName,
    DateTime? createdAt,
    this.sports = const [],
    this.throwsHand,
    this.planId,
    this.planName,
    this.subscriptionStatus,
    this.trialEnd,
    this.maxPitchers = 1,
  })  : pitcherDisplayName = pitcherDisplayName ?? username,
        createdAt = createdAt ?? DateTime.now();

  /// Every plan includes every feature (plans differ only by how many pitcher
  /// profiles they allow), so nothing in the app is locked any more. Kept as a
  /// getter so older call sites keep compiling.
  bool get isPlus => true;
  bool get isActive => status == SubStatus.active;

  /// Built from a joined `auth.users` (email) + `public.profiles`
  /// (username/tier/status/...) row — see AuthService.
  factory AppUser.fromSupabase({
    required String id,
    required String email,
    required Map<String, dynamic> profile,
    Map<String, dynamic>? entitlement,
  }) {
    // `tier` only matters for spotting admins now; features are not tiered.
    final tier = UserTierX.fromString(profile['tier'] as String? ?? 'basic');
    return AppUser(
      id: id,
      username: profile['username'] as String? ?? email.split('@').first,
      email: email,
      tier: tier,
      status: SubStatusX.fromString(profile['status'] as String? ?? 'active'),
      pitcherDisplayName:
          profile['pitcher_display_name'] as String? ?? profile['username'] as String? ?? email,
      createdAt: DateTime.tryParse(profile['created_at'] as String? ?? '') ?? DateTime.now(),
      sports: ((profile['sports'] as List?) ?? const []).map((e) => e.toString()).toList(),
      throwsHand: profile['throws_hand'] as String?,
      planId: entitlement?['plan_id'] as String?,
      planName: entitlement?['plan_name'] as String?,
      subscriptionStatus: entitlement?['subscription_status'] as String?,
      trialEnd: DateTime.tryParse(entitlement?['trial_end'] as String? ?? '')?.toLocal(),
      maxPitchers: (entitlement?['max_pitchers'] as num?)?.toInt() ?? 1,
    );
  }
}
