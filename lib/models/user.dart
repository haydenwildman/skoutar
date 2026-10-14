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

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.tier = UserTier.basic,
    this.status = SubStatus.active,
    String? pitcherDisplayName,
    DateTime? createdAt,
  })  : pitcherDisplayName = pitcherDisplayName ?? username,
        createdAt = createdAt ?? DateTime.now();

  bool get isPlus => tier == UserTier.plus || tier == UserTier.admin;
  bool get isActive => status == SubStatus.active;

  /// Built from a joined `auth.users` (email) + `public.profiles`
  /// (username/tier/status/...) row — see AuthService.
  factory AppUser.fromSupabase({
    required String id,
    required String email,
    required Map<String, dynamic> profile,
  }) =>
      AppUser(
        id: id,
        username: profile['username'] as String? ?? email.split('@').first,
        email: email,
        tier: UserTierX.fromString(profile['tier'] as String? ?? 'basic'),
        status: SubStatusX.fromString(profile['status'] as String? ?? 'active'),
        pitcherDisplayName:
            profile['pitcher_display_name'] as String? ?? profile['username'] as String? ?? email,
        createdAt: DateTime.tryParse(profile['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
