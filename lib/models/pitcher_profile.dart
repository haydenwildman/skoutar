/// One row of `public.pitchers`: a pitcher profile under a subscription.
/// Each pitcher has a unique [id]; all of that pitcher's data is keyed by it.
class PitcherProfile {
  final String id;
  final String displayName;
  final String username;
  final List<String> sports; // subset of ['baseball', 'softball']
  final String? throwsHand; // 'R' | 'L'
  final String? position;
  final bool hasOwnLogin;

  const PitcherProfile({
    required this.id,
    required this.displayName,
    required this.username,
    this.sports = const [],
    this.throwsHand,
    this.position,
    this.hasOwnLogin = false,
  });

  /// Required profile info is present. Used to prompt people to complete a
  /// profile instead of asking for the same details again and again.
  bool get isComplete => sports.isNotEmpty && throwsHand != null;

  String get sportsLabel => sports.isEmpty
      ? '—'
      : sports.map((s) => s == 'baseball' ? 'Baseball' : 'Softball').join(' & ');

  String get handLabel => switch (throwsHand) {
        'R' => 'Right-handed',
        'L' => 'Left-handed',
        _ => '—',
      };

  factory PitcherProfile.fromMap(Map<String, dynamic> m) => PitcherProfile(
        id: m['id'] as String,
        displayName: (m['display_name'] as String?) ?? (m['username'] as String? ?? ''),
        username: m['username'] as String? ?? '',
        sports: ((m['sports'] as List?) ?? const []).map((e) => e.toString()).toList(),
        throwsHand: m['throws_hand'] as String?,
        position: m['player_position'] as String?,
        hasOwnLogin: m['auth_user_id'] != null,
      );
}
