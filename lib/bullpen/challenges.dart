// Game Mode rules. Pure Dart (no Flutter) so every rule is unit-testable.
//
// Difficulty only ever makes a challenge harder through smaller targets,
// longer sequences, longer required streaks or more required hits. The
// numbers live in ONE place below so standardized challenges stay identical
// from attempt to attempt and results can be compared over time.

import 'bullpen_models.dart';

class StreakSpec {
  final int goal;

  /// The "strike" region is the zone shrunk to this fraction around its center.
  final double zoneScale;
  const StreakSpec(this.goal, this.zoneScale);
}

class AccuracySpec {
  final double size; // target width = height, in zone units
  final int pitches; // pitches allowed per attempt
  final int required; // hits needed to pass
  const AccuracySpec(this.size, this.pitches, this.required);
}

class SequenceSpec {
  final int length;
  final double size;
  const SequenceSpec(this.length, this.size);
}

class ChallengeRules {
  ChallengeRules._();

  static const Map<Difficulty, StreakSpec> streak = {
    Difficulty.beginner: StreakSpec(5, 1.0),
    Difficulty.intermediate: StreakSpec(8, 0.85),
    Difficulty.advanced: StreakSpec(10, 0.70),
    Difficulty.elite: StreakSpec(12, 0.55),
  };

  static const Map<Difficulty, AccuracySpec> accuracy = {
    Difficulty.beginner: AccuracySpec(0.50, 10, 4),
    Difficulty.intermediate: AccuracySpec(0.40, 10, 5),
    Difficulty.advanced: AccuracySpec(0.30, 10, 6),
    Difficulty.elite: AccuracySpec(0.22, 10, 7),
  };

  static const Map<Difficulty, SequenceSpec> sequence = {
    Difficulty.beginner: SequenceSpec(3, 0.50),
    Difficulty.intermediate: SequenceSpec(4, 0.40),
    Difficulty.advanced: SequenceSpec(5, 0.32),
    Difficulty.elite: SequenceSpec(6, 0.25),
  };

  /// The nine zone cells (3x3) as target centers, row-major from the top-left.
  static const List<List<double>> cells = [
    [1 / 6, 5 / 6], [0.5, 5 / 6], [5 / 6, 5 / 6],
    [1 / 6, 0.5], [0.5, 0.5], [5 / 6, 0.5],
    [1 / 6, 1 / 6], [0.5, 1 / 6], [5 / 6, 1 / 6],
  ];

  static const List<String> cellNames = [
    'Up & Left', 'Up', 'Up & Right',
    'Left', 'Middle', 'Right',
    'Down & Left', 'Down', 'Down & Right',
  ];

  /// Fixed order the sequencing targets walk through (indexes into [cells]),
  /// so the same difficulty always asks for the same locations.
  static const List<int> sequenceCellOrder = [6, 2, 4, 0, 8, 5];

  /// Default pitch order offered for a sequence; the player can change any slot.
  static const List<String> sequenceTemplate = ['fb', 'cv', 'fb', 'ch', 'fb', 'sl'];

  /// Template mapped onto the pitch types the player actually has.
  static List<String> defaultSequence(Difficulty d, List<String> available) {
    final len = sequence[d]!.length;
    if (available.isEmpty) return List.filled(len, 'fb');
    return [
      for (var i = 0; i < len; i++)
        available.contains(sequenceTemplate[i]) ? sequenceTemplate[i] : available[i % available.length],
    ];
  }

  static ZoneTarget cellTarget(int cell, double size) =>
      ZoneTarget(cells[cell][0], cells[cell][1], size, size);
}

enum EndReason { goal, miss, outOfPitches, ended }

extension EndReasonX on EndReason {
  String get key => switch (this) {
        EndReason.goal => 'goal',
        EndReason.miss => 'miss',
        EndReason.outOfPitches => 'out_of_pitches',
        EndReason.ended => 'ended',
      };
}

/// One in-progress attempt. Call [submit] with where each pitch landed.
abstract class ChallengeEngine {
  ChallengeMode get mode;
  Difficulty get difficulty;
  String get pitchKey;
  int get goal;

  /// Streak so far / hits so far / steps completed.
  int get score;
  int get pitchesThrown;
  bool get finished;
  bool get success;
  EndReason? get endReason;

  /// What the player should aim at right now (null once finished).
  ZoneTarget? get currentTarget;

  /// Pitch type for the next pitch.
  String get currentPitchType;

  List<Map<String, dynamic>> get log;

  /// Records a pitch landing at (x, y). Returns whether it counted as a hit.
  bool submit(double x, double y);

  /// Gives up on this attempt; it is recorded as failed.
  void endEarly();
}

abstract class _BaseEngine implements ChallengeEngine {
  @override
  final Difficulty difficulty;
  int _score = 0;
  int _thrown = 0;
  bool _finished = false;
  bool _success = false;
  EndReason? _reason;
  final List<Map<String, dynamic>> _log = [];

  _BaseEngine(this.difficulty);

  @override
  int get score => _score;
  @override
  int get pitchesThrown => _thrown;
  @override
  bool get finished => _finished;
  @override
  bool get success => _success;
  @override
  EndReason? get endReason => _reason;
  @override
  List<Map<String, dynamic>> get log => List.unmodifiable(_log);

  void _record(String pitchType, ZoneTarget t, double x, double y, bool hit) {
    _thrown++;
    _log.add({
      'pitchType': pitchType,
      'tx': t.x, 'ty': t.y, 'tw': t.w, 'th': t.h,
      'ax': x, 'ay': y,
      'hit': hit,
    });
  }

  void _finish(bool ok, EndReason r) {
    _finished = true;
    _success = ok;
    _reason = r;
  }

  @override
  void endEarly() {
    if (_finished) return;
    _finish(false, EndReason.ended);
  }
}

/// Strike Streak: consecutive strikes with one pitch type. The first ball
/// ends (fails) the attempt; reaching the goal passes it.
class StreakEngine extends _BaseEngine {
  final String pitchType;
  final StreakSpec spec;

  StreakEngine(Difficulty d, this.pitchType)
      : spec = ChallengeRules.streak[d]!,
        super(d);

  @override
  ChallengeMode get mode => ChallengeMode.streak;
  @override
  String get pitchKey => pitchType;
  @override
  int get goal => spec.goal;
  @override
  String get currentPitchType => pitchType;

  @override
  ZoneTarget? get currentTarget =>
      _finished ? null : ZoneTarget(0.5, 0.5, spec.zoneScale, spec.zoneScale);

  @override
  bool submit(double x, double y) {
    if (_finished) return false;
    final t = currentTarget!;
    final hit = t.contains(x, y);
    _record(pitchType, t, x, y, hit);
    if (hit) {
      _score++;
      if (_score >= spec.goal) _finish(true, EndReason.goal);
    } else {
      _finish(false, EndReason.miss);
    }
    return hit;
  }
}

/// Target Accuracy: a fixed number of pitches at one target; pass with enough hits.
class AccuracyEngine extends _BaseEngine {
  final String pitchType;
  final int cell;
  final AccuracySpec spec;

  AccuracyEngine(Difficulty d, this.pitchType, this.cell)
      : spec = ChallengeRules.accuracy[d]!,
        super(d);

  @override
  ChallengeMode get mode => ChallengeMode.accuracy;
  @override
  String get pitchKey => pitchType;
  @override
  int get goal => spec.required;
  @override
  String get currentPitchType => pitchType;

  int get pitchesLeft => spec.pitches - _thrown;

  @override
  ZoneTarget? get currentTarget => _finished ? null : ChallengeRules.cellTarget(cell, spec.size);

  @override
  bool submit(double x, double y) {
    if (_finished) return false;
    final t = currentTarget!;
    final hit = t.contains(x, y);
    _record(pitchType, t, x, y, hit);
    if (hit) _score++;
    final left = spec.pitches - _thrown;
    if (left == 0) {
      final ok = _score >= spec.required;
      _finish(ok, ok ? EndReason.goal : EndReason.outOfPitches);
    } else if (_score + left < spec.required) {
      // Can no longer reach the goal - end it now instead of making them finish.
      _finish(false, EndReason.outOfPitches);
    }
    return hit;
  }
}

/// Pitch Sequencing: hit each pitch's target in order; any miss fails the attempt.
class SequenceEngine extends _BaseEngine {
  final List<String> pitches;
  final SequenceSpec spec;

  SequenceEngine(Difficulty d, List<String> pitches)
      : spec = ChallengeRules.sequence[d]!,
        pitches = List.of(pitches),
        super(d) {
    assert(pitches.length == spec.length);
  }

  @override
  ChallengeMode get mode => ChallengeMode.sequence;
  @override
  String get pitchKey => pitches.join('-');
  @override
  int get goal => spec.length;

  /// 0-based index of the step being thrown.
  int get step => _score;

  @override
  String get currentPitchType => pitches[_finished && _score >= pitches.length ? pitches.length - 1 : _score];

  ZoneTarget targetForStep(int i) =>
      ChallengeRules.cellTarget(ChallengeRules.sequenceCellOrder[i % ChallengeRules.sequenceCellOrder.length], spec.size);

  @override
  ZoneTarget? get currentTarget => _finished ? null : targetForStep(_score);

  @override
  bool submit(double x, double y) {
    if (_finished) return false;
    final t = currentTarget!;
    final type = pitches[_score];
    final hit = t.contains(x, y);
    _record(type, t, x, y, hit);
    if (hit) {
      _score++;
      if (_score >= spec.length) _finish(true, EndReason.goal);
    } else {
      _finish(false, EndReason.miss);
    }
    return hit;
  }
}

/// Builds the record that gets saved for a finished attempt.
ChallengeAttempt attemptFromEngine({
  required String id,
  required String userId,
  required ChallengeEngine engine,
  required DateTime startedAt,
  DateTime? endedAt,
}) {
  assert(engine.finished);
  return ChallengeAttempt(
    id: id,
    userId: userId,
    mode: engine.mode,
    difficulty: engine.difficulty,
    pitchKey: engine.pitchKey,
    startedAt: startedAt,
    endedAt: endedAt ?? DateTime.now(),
    success: engine.success,
    score: engine.score,
    goal: engine.goal,
    pitchesThrown: engine.pitchesThrown,
    detail: engine.log,
    endReason: engine.endReason!.key,
  );
}
