// Bullpen & Game Mode data models.
//
// Everything here is stored in its OWN tables (bullpen_sessions,
// bullpen_pitches, challenge_attempts) and never touches pitch_events, so
// official game statistics can not be affected by practice data.
//
// Zone coordinates: (0,0) is the bottom-left corner of the strike zone and
// (1,1) the top-right, as seen from the catcher's side. Values outside 0..1
// are misses outside the zone. x grows toward the catcher's right.

import 'dart:math' as math;

class ZoneGeo {
  ZoneGeo._();

  /// Real-world size used only to turn zone units into inches. The zone is
  /// treated as the 17-inch plate wide and 24 inches tall - an approximation
  /// (a real zone changes with each batter), so distances are "about" values.
  static const double plateWidthIn = 17.0;
  static const double zoneHeightIn = 24.0;

  /// Visible window drawn around the zone.
  static const double minX = -0.5, maxX = 1.5;
  static const double minY = -0.4, maxY = 1.4;

  static bool inZone(double x, double y) => x >= 0 && x <= 1 && y >= 0 && y <= 1;

  static double distanceIn(double ax, double ay, double bx, double by) {
    final dx = (ax - bx) * plateWidthIn;
    final dy = (ay - by) * zoneHeightIn;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double clampX(double x) => x.clamp(minX, maxX).toDouble();
  static double clampY(double y) => y.clamp(minY, maxY).toDouble();
}

/// A rectangular target on the zone: center + independent width/height.
class ZoneTarget {
  final double x, y, w, h;
  const ZoneTarget(this.x, this.y, this.w, this.h);

  double get left => x - w / 2;
  double get right => x + w / 2;
  double get bottom => y - h / 2;
  double get top => y + h / 2;
  double get widthIn => w * ZoneGeo.plateWidthIn;
  double get heightIn => h * ZoneGeo.zoneHeightIn;

  bool contains(double px, double py) => px >= left && px <= right && py >= bottom && py <= top;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
  factory ZoneTarget.fromJson(Map<String, dynamic> j) => ZoneTarget(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['w'] as num).toDouble(),
        (j['h'] as num).toDouble(),
      );
}

enum BullpenType { command, pitchDevelopment, sequencing, simulatedHitters, general, custom }

extension BullpenTypeX on BullpenType {
  String get key => switch (this) {
        BullpenType.command => 'command',
        BullpenType.pitchDevelopment => 'pitch_development',
        BullpenType.sequencing => 'sequencing',
        BullpenType.simulatedHitters => 'simulated_hitters',
        BullpenType.general => 'general',
        BullpenType.custom => 'custom',
      };

  String get label => switch (this) {
        BullpenType.command => 'Command',
        BullpenType.pitchDevelopment => 'Pitch Development',
        BullpenType.sequencing => 'Sequencing',
        BullpenType.simulatedHitters => 'Simulated Hitters',
        BullpenType.general => 'General',
        BullpenType.custom => 'Custom',
      };

  static BullpenType fromKey(String? k) =>
      BullpenType.values.firstWhere((t) => t.key == k, orElse: () => BullpenType.general);
}

enum SessionStatus { active, paused, finished }

class BullpenSession {
  final String id;
  final String userId;
  final BullpenType type;
  final String? customName;

  /// 'R' or 'L' - needed to turn left/right misses into arm-side/glove-side.
  final String throwsHand;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SessionStatus status;

  /// Total time spent paused so far, in milliseconds.
  final int pausedMs;
  final DateTime? pausedAt;
  final String? notes;

  /// Snapshot (JSON) of the plan this bullpen was started from, if any.
  final Map<String, dynamic>? plan;

  const BullpenSession({
    required this.id,
    required this.userId,
    required this.type,
    this.customName,
    this.throwsHand = 'R',
    required this.startedAt,
    this.endedAt,
    this.status = SessionStatus.active,
    this.pausedMs = 0,
    this.pausedAt,
    this.notes,
    this.plan,
  });

  String get title => type == BullpenType.custom && (customName?.trim().isNotEmpty ?? false)
      ? customName!.trim()
      : type.label;

  bool get isOpen => status != SessionStatus.finished;

  /// Active time (excludes paused time).
  Duration elapsed([DateTime? now]) {
    final end = endedAt ?? (status == SessionStatus.paused ? pausedAt : null) ?? (now ?? DateTime.now());
    final ms = end.difference(startedAt).inMilliseconds - pausedMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  BullpenSession copyWith({
    BullpenType? type,
    String? customName,
    String? throwsHand,
    DateTime? endedAt,
    SessionStatus? status,
    int? pausedMs,
    DateTime? pausedAt,
    bool clearPausedAt = false,
    String? notes,
    Map<String, dynamic>? plan,
  }) =>
      BullpenSession(
        id: id,
        userId: userId,
        type: type ?? this.type,
        customName: customName ?? this.customName,
        throwsHand: throwsHand ?? this.throwsHand,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        status: status ?? this.status,
        pausedMs: pausedMs ?? this.pausedMs,
        pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
        notes: notes ?? this.notes,
        plan: plan ?? this.plan,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'user_id': userId,
        'pitcher_id': userId,
        'bullpen_type': type.key,
        'custom_name': customName,
        'throws_hand': throwsHand,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'status': status.name,
        'paused_ms': pausedMs,
        'paused_at': pausedAt?.toUtc().toIso8601String(),
        'notes': notes,
        'plan': plan,
      };

  factory BullpenSession.fromRow(Map<String, dynamic> r) => BullpenSession(
        id: r['id'] as String,
        userId: (r['pitcher_id'] ?? r['user_id']) as String,
        type: BullpenTypeX.fromKey(r['bullpen_type'] as String?),
        customName: r['custom_name'] as String?,
        throwsHand: (r['throws_hand'] as String?) ?? 'R',
        startedAt: DateTime.parse(r['started_at'] as String).toLocal(),
        endedAt: r['ended_at'] == null ? null : DateTime.parse(r['ended_at'] as String).toLocal(),
        status: SessionStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => SessionStatus.finished),
        pausedMs: (r['paused_ms'] as num?)?.toInt() ?? 0,
        pausedAt: r['paused_at'] == null ? null : DateTime.parse(r['paused_at'] as String).toLocal(),
        notes: r['notes'] as String?,
        plan: (r['plan'] as Map?)?.cast<String, dynamic>(),
      );
}

/// Optional "what happened" tags, same vocabulary as the game call buttons.
const Map<String, String> bullpenResultLabels = {
  'ball': 'Ball',
  'called_strike': 'Called Strike',
  'swinging_strike': 'Swing & Miss',
  'foul': 'Foul',
  'in_play': 'In Play',
};

class BullpenPitch {
  final String id;
  final String sessionId;
  final String userId;
  final int seq; // 1-based order inside the session
  final String pitchType;

  /// Intended target; null when the pitcher chose "no target" for this pitch.
  final ZoneTarget? target;
  final double? actualX, actualY;
  final double? velocity; // optional
  final String? result; // optional, a key of [bullpenResultLabels]
  final String? notes; // optional
  final DateTime timestamp;

  /// Which set of the plan this pitch belonged to (plan-guided bullpens).
  final int? planSetIndex;

  const BullpenPitch({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.seq,
    required this.pitchType,
    this.target,
    this.actualX,
    this.actualY,
    this.velocity,
    this.result,
    this.notes,
    required this.timestamp,
    this.planSetIndex,
  });

  bool get hasActual => actualX != null && actualY != null;
  bool get hasTarget => target != null;
  bool get inZone => hasActual && ZoneGeo.inZone(actualX!, actualY!);
  bool get hitTarget => hasActual && hasTarget && target!.contains(actualX!, actualY!);

  /// Distance in inches from the CENTER of the target to where it landed.
  double? get distanceIn => (hasActual && hasTarget)
      ? ZoneGeo.distanceIn(actualX!, actualY!, target!.x, target!.y)
      : null;

  BullpenPitch copyWith({
    int? seq,
    String? pitchType,
    ZoneTarget? target,
    bool clearTarget = false,
    double? actualX,
    double? actualY,
    double? velocity,
    bool clearVelocity = false,
    String? result,
    bool clearResult = false,
    String? notes,
    bool clearNotes = false,
  }) =>
      BullpenPitch(
        id: id,
        sessionId: sessionId,
        userId: userId,
        seq: seq ?? this.seq,
        pitchType: pitchType ?? this.pitchType,
        target: clearTarget ? null : (target ?? this.target),
        actualX: actualX ?? this.actualX,
        actualY: actualY ?? this.actualY,
        velocity: clearVelocity ? null : (velocity ?? this.velocity),
        result: clearResult ? null : (result ?? this.result),
        notes: clearNotes ? null : (notes ?? this.notes),
        timestamp: timestamp,
        planSetIndex: planSetIndex,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'session_id': sessionId,
        'user_id': userId,
        'pitcher_id': userId,
        'seq': seq,
        'pitch_type': pitchType,
        'target_x': target?.x,
        'target_y': target?.y,
        'target_w': target?.w,
        'target_h': target?.h,
        'actual_x': actualX,
        'actual_y': actualY,
        'velocity': velocity,
        'result': result,
        'notes': notes,
        'plan_set_index': planSetIndex,
        'ts': timestamp.toUtc().toIso8601String(),
      };

  factory BullpenPitch.fromRow(Map<String, dynamic> r) {
    final tx = (r['target_x'] as num?)?.toDouble();
    final ty = (r['target_y'] as num?)?.toDouble();
    final tw = (r['target_w'] as num?)?.toDouble();
    final th = (r['target_h'] as num?)?.toDouble();
    return BullpenPitch(
      id: r['id'] as String,
      sessionId: r['session_id'] as String,
      userId: (r['pitcher_id'] ?? r['user_id']) as String,
      seq: (r['seq'] as num).toInt(),
      pitchType: r['pitch_type'] as String,
      target: (tx != null && ty != null && tw != null && th != null) ? ZoneTarget(tx, ty, tw, th) : null,
      actualX: (r['actual_x'] as num?)?.toDouble(),
      actualY: (r['actual_y'] as num?)?.toDouble(),
      velocity: (r['velocity'] as num?)?.toDouble(),
      result: r['result'] as String?,
      notes: r['notes'] as String?,
      planSetIndex: (r['plan_set_index'] as num?)?.toInt(),
      timestamp: DateTime.parse(r['ts'] as String).toLocal(),
    );
  }
}

enum ChallengeMode { streak, accuracy, sequence }

extension ChallengeModeX on ChallengeMode {
  String get label => switch (this) {
        ChallengeMode.streak => 'Strike Streak',
        ChallengeMode.accuracy => 'Target Accuracy',
        ChallengeMode.sequence => 'Pitch Sequencing',
      };
}

enum Difficulty { beginner, intermediate, advanced, elite }

extension DifficultyX on Difficulty {
  String get label => switch (this) {
        Difficulty.beginner => 'Beginner',
        Difficulty.intermediate => 'Intermediate',
        Difficulty.advanced => 'Advanced',
        Difficulty.elite => 'Elite',
      };
}

/// One finished (passed OR failed) Game Mode attempt.
class ChallengeAttempt {
  final String id;
  final String userId;
  final ChallengeMode mode;
  final Difficulty difficulty;

  /// Pitch type for streak/accuracy; the joined sequence ("fb-cv-fb") for sequencing.
  final String pitchKey;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool success;

  /// Streak reached / hits made / sequence steps completed.
  final int score;
  final int goal;
  final int pitchesThrown;

  /// Per-pitch log: pitchType, target (x,y,w,h), actual (x,y), hit.
  final List<Map<String, dynamic>> detail;

  /// Why it ended: goal, miss, out_of_pitches, ended.
  final String endReason;

  const ChallengeAttempt({
    required this.id,
    required this.userId,
    required this.mode,
    required this.difficulty,
    required this.pitchKey,
    required this.startedAt,
    required this.endedAt,
    required this.success,
    required this.score,
    required this.goal,
    required this.pitchesThrown,
    required this.detail,
    required this.endReason,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'user_id': userId,
        'pitcher_id': userId,
        'mode': mode.name,
        'difficulty': difficulty.name,
        'pitch_key': pitchKey,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'success': success,
        'score': score,
        'goal': goal,
        'pitches_thrown': pitchesThrown,
        'detail': detail,
        'end_reason': endReason,
      };

  factory ChallengeAttempt.fromRow(Map<String, dynamic> r) => ChallengeAttempt(
        id: r['id'] as String,
        userId: (r['pitcher_id'] ?? r['user_id']) as String,
        mode: ChallengeMode.values.firstWhere((m) => m.name == r['mode'], orElse: () => ChallengeMode.streak),
        difficulty: Difficulty.values.firstWhere((d) => d.name == r['difficulty'], orElse: () => Difficulty.beginner),
        pitchKey: (r['pitch_key'] as String?) ?? '',
        startedAt: DateTime.parse(r['started_at'] as String).toLocal(),
        endedAt: DateTime.parse(r['ended_at'] as String).toLocal(),
        success: r['success'] as bool? ?? false,
        score: (r['score'] as num?)?.toInt() ?? 0,
        goal: (r['goal'] as num?)?.toInt() ?? 0,
        pitchesThrown: (r['pitches_thrown'] as num?)?.toInt() ?? 0,
        detail: ((r['detail'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
        endReason: (r['end_reason'] as String?) ?? '',
      );
}
