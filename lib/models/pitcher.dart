/// One pitcher profile under an account (row of `public.pitchers`).
/// Each pitcher's games, pitches, bullpens and settings are keyed by [id].
class Pitcher {
  final String id;
  final String ownerId;
  final String displayName;
  final String username;
  final List<String> sports; // subset of ['baseball', 'softball']
  final String? throwsHand; // 'R' | 'L'

  const Pitcher({
    required this.id,
    required this.ownerId,
    required this.displayName,
    required this.username,
    this.sports = const [],
    this.throwsHand,
  });

  /// Throwing hand and sport are what the Bullpen needs; if either is missing
  /// the person is asked to complete the profile.
  bool get isComplete => throwsHand != null && sports.isNotEmpty;

  String get handLabel => switch (throwsHand) {
        'R' => 'Right-handed',
        'L' => 'Left-handed',
        _ => '—',
      };

  String get sportLabel => sports.isEmpty
      ? '—'
      : sports.map((s) => s == 'baseball' ? 'Baseball' : 'Softball').join(' & ');

  factory Pitcher.fromMap(Map<String, dynamic> m) => Pitcher(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        displayName: m['display_name'] as String? ?? 'Pitcher',
        username: m['username'] as String? ?? '',
        sports: ((m['sports'] as List?) ?? const []).map((e) => e.toString()).toList(),
        throwsHand: m['throws_hand'] as String?,
      );
}

/// Editable pitcher details used by the sign-up flow and the add/edit dialogs.
class PitcherDraft {
  String name;
  String username;
  final Set<String> sports;
  String? hand;

  PitcherDraft({
    this.name = '',
    this.username = '',
    Set<String>? sports,
    this.hand,
  }) : sports = sports ?? <String>{};

  factory PitcherDraft.from(Pitcher p) => PitcherDraft(
        name: p.displayName,
        username: p.username,
        sports: p.sports.toSet(),
        hand: p.throwsHand,
      );

  /// Error message, or null when everything required is filled in.
  String? validate() {
    final n = name.trim();
    if (n.isEmpty) return 'Enter the pitcher\'s name.';
    if (n.length > 60) return 'Name is too long (60 characters max).';
    final u = username.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(u)) {
      return 'Username: 3-20 letters, numbers or underscores.';
    }
    if (sports.isEmpty) return 'Choose baseball, softball, or both.';
    if (hand == null) return 'Choose right- or left-handed.';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'display_name': name.trim(),
        'username': username.trim(),
        'sports': (sports.toList()..sort()),
        'throws_hand': hand,
      };

  PitcherDraft copy() =>
      PitcherDraft(name: name, username: username, sports: {...sports}, hand: hand);
}
