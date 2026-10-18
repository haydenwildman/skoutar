// Bullpen analytics: pure functions over sessions, pitches and game data.
//
// Definitions (kept deliberately separate):
//   * Target accuracy = share of pitches (that had a target) landing INSIDE the
//     target rectangle the pitcher set. Depends on target size.
//   * Strike % (zone %)  = share of pitches (that were marked) landing inside
//     the strike zone. Does not depend on the target.
//   * Distance = inches from the target's center to the landing point. Uses a
//     fixed 17" x 24" zone, so it is an approximation.

import 'dart:math' as math;
import '../models/pitch_event.dart';
import '../services/stats_service.dart';
import 'bullpen_models.dart';
import 'plan_models.dart';

class BullpenThresholds {
  BullpenThresholds._();

  /// Fewest pitches of one type (per setting) before a number about it is called a finding.
  static const int minPitchTypeSample = 15;

  /// Fewest misses before a miss DIRECTION is called a pattern.
  static const int minMisses = 8;

  /// Share of misses on one side that counts as "leaning" that way.
  static const double dominantShare = 0.6;

  /// Percentage-point gap from a pitcher's own average that counts as "different".
  static const double gapPoints = 5.0;

  /// Fewest target pitches in the data before any recommendation is made.
  static const int minTotalTargetPitches = 30;
}

class BullpenStats {
  int pitches = 0;
  int targetPitches = 0;
  int targetHits = 0;
  int landed = 0;
  int strikes = 0;
  double _distSum = 0;
  int _distN = 0;
  double _wSum = 0;
  double _hSum = 0;

  void add(BullpenPitch p) {
    pitches++;
    if (p.hasActual) {
      landed++;
      if (p.inZone) strikes++;
    }
    if (p.hasTarget && p.hasActual) {
      targetPitches++;
      if (p.hitTarget) targetHits++;
      _distSum += p.distanceIn!;
      _distN++;
      _wSum += p.target!.widthIn;
      _hSum += p.target!.heightIn;
    }
  }

  double? get targetAccuracy => targetPitches == 0 ? null : targetHits / targetPitches * 100;
  double? get zonePct => landed == 0 ? null : strikes / landed * 100;
  double? get avgDistanceIn => _distN == 0 ? null : _distSum / _distN;
  double? get avgTargetWidthIn => _distN == 0 ? null : _wSum / _distN;
  double? get avgTargetHeightIn => _distN == 0 ? null : _hSum / _distN;

  /// Typical target size in zone units (geometric mean of width and height).
  double? get avgTargetSize {
    if (_distN == 0) return null;
    final w = avgTargetWidthIn! / ZoneGeo.plateWidthIn;
    final h = avgTargetHeightIn! / ZoneGeo.zoneHeightIn;
    return math.sqrt(w * h);
  }
}

enum SizeBucket { small, medium, large }

extension SizeBucketX on SizeBucket {
  String get label => switch (this) {
        SizeBucket.small => 'Small targets',
        SizeBucket.medium => 'Medium targets',
        SizeBucket.large => 'Large targets',
      };
  String get detail => switch (this) {
        SizeBucket.small => 'under 25% of the zone',
        SizeBucket.medium => '25-45% of the zone',
        SizeBucket.large => '45%+ of the zone',
      };
}

SizeBucket sizeBucketOf(ZoneTarget t) {
  final s = math.sqrt(t.w * t.h);
  if (s < 0.25) return SizeBucket.small;
  if (s < 0.45) return SizeBucket.medium;
  return SizeBucket.large;
}

/// Where the pitches that MISSED their target ended up, relative to the target.
class MissCounts {
  int misses = 0;
  int high = 0, low = 0, armSide = 0, gloveSide = 0;
  double _armSum = 0; // inches; + = arm side
  double _upSum = 0; // inches; + = high

  void add(BullpenPitch p, String hand) {
    if (!p.hasTarget || !p.hasActual || p.hitTarget) return;
    final t = p.target!;
    misses++;
    if (p.actualY! > t.top) high++;
    if (p.actualY! < t.bottom) low++;
    // Catcher's view: a right-hander's arm side is the catcher's LEFT.
    final leftOfTarget = p.actualX! < t.left;
    final rightOfTarget = p.actualX! > t.right;
    if (leftOfTarget) hand == 'R' ? armSide++ : gloveSide++;
    if (rightOfTarget) hand == 'R' ? gloveSide++ : armSide++;
    final dx = (p.actualX! - t.x) * ZoneGeo.plateWidthIn;
    _armSum += hand == 'R' ? -dx : dx;
    _upSum += (p.actualY! - t.y) * ZoneGeo.zoneHeightIn;
  }

  double? share(int c) => misses == 0 ? null : c / misses * 100;
  double? get avgArmSideIn => misses == 0 ? null : _armSum / misses;
  double? get avgHighIn => misses == 0 ? null : _upSum / misses;

  /// The one direction most misses lean toward, or null when no clear lean
  /// (or too few misses to call it a pattern).
  String? get dominant {
    if (misses < BullpenThresholds.minMisses) return null;
    final shares = <String, double>{
      'high': high / misses,
      'low': low / misses,
      'arm-side': armSide / misses,
      'glove-side': gloveSide / misses,
    };
    final best = shares.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value >= BullpenThresholds.dominantShare ? best.key : null;
  }
}

class SessionStat {
  final BullpenSession session;
  final BullpenStats stats;
  const SessionStat(this.session, this.stats);
}

class BullpenAnalysis {
  final int sessionCount;
  final BullpenStats overall;
  final Map<String, BullpenStats> byType;
  final MissCounts misses;
  final Map<String, MissCounts> missesByType;
  final List<SessionStat> perSession; // oldest first
  final Map<SizeBucket, BullpenStats> bySize;
  final List<BullpenPitch> pitches; // chronological, the filtered set

  const BullpenAnalysis({
    required this.sessionCount,
    required this.overall,
    required this.byType,
    required this.misses,
    required this.missesByType,
    required this.perSession,
    required this.bySize,
    required this.pitches,
  });

  bool get hasData => overall.pitches > 0;
}

class BullpenAnalytics {
  BullpenAnalytics._();

  /// Analyses FINISHED bullpens (open ones are still being thrown).
  static BullpenAnalysis analyze({
    required List<BullpenSession> sessions,
    required List<BullpenPitch> pitches,
    String? pitchType,
    DateTime? since,
    BullpenType? sessionType,
  }) {
    final chosen = <String, BullpenSession>{
      for (final s in sessions)
        if (s.status == SessionStatus.finished &&
            (since == null || !s.startedAt.isBefore(since)) &&
            (sessionType == null || s.type == sessionType))
          s.id: s,
    };
    final rows = pitches
        .where((p) => chosen.containsKey(p.sessionId) && (pitchType == null || p.pitchType == pitchType))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final overall = BullpenStats();
    final byType = <String, BullpenStats>{};
    final misses = MissCounts();
    final missesByType = <String, MissCounts>{};
    final bySize = <SizeBucket, BullpenStats>{};
    final perSession = <String, BullpenStats>{};

    for (final p in rows) {
      final hand = chosen[p.sessionId]!.throwsHand;
      overall.add(p);
      byType.putIfAbsent(p.pitchType, BullpenStats.new).add(p);
      perSession.putIfAbsent(p.sessionId, BullpenStats.new).add(p);
      misses.add(p, hand);
      missesByType.putIfAbsent(p.pitchType, MissCounts.new).add(p, hand);
      if (p.hasTarget) bySize.putIfAbsent(sizeBucketOf(p.target!), BullpenStats.new).add(p);
    }

    final sessionStats = [
      for (final e in perSession.entries) SessionStat(chosen[e.key]!, e.value),
    ]..sort((a, b) => a.session.startedAt.compareTo(b.session.startedAt));

    return BullpenAnalysis(
      sessionCount: chosen.values.where((s) => perSession.containsKey(s.id) || pitchType == null).length,
      overall: overall,
      byType: byType,
      misses: misses,
      missesByType: missesByType,
      perSession: sessionStats,
      bySize: bySize,
      pitches: rows,
    );
  }

  // ── Plan vs results ────────────────────────────────────────────────

  static List<PlanSetResult> planResults(BullpenSession session, List<BullpenPitch> pitches) {
    final planJson = session.plan;
    if (planJson == null) return const [];
    final plan = BullpenPlan.fromJson(planJson);
    final mine = pitches.where((p) => p.sessionId == session.id).toList();
    return [
      for (var i = 0; i < plan.sets.length; i++)
        () {
          final stats = BullpenStats();
          for (final p in mine.where((p) => p.planSetIndex == i)) {
            stats.add(p);
          }
          return PlanSetResult(i, plan.sets[i], stats);
        }(),
    ];
  }

  // ── Bullpen vs. game ───────────────────────────────────────────────

  /// Compares ONLY like-for-like things:
  ///  * each setting's pitch types are judged against that setting's OWN average
  ///    (so "zone %" in the bullpen and "strike %" in games are never subtracted
  ///    from each other - they are defined differently);
  ///  * improvement is checked as bullpen change vs. game change over the same
  ///    time split.
  static BullpenGameComparison compare({
    required BullpenAnalysis bullpen,
    required List<PitchEvent> gamePitches,
  }) {
    final min = BullpenThresholds.minPitchTypeSample;
    final gameRows = {
      for (final r in StatsService.pitchBreakdown(gamePitches)) (r['pitchType'] as String).toLowerCase(): r,
    };
    final overallGame = StatsService.pitchBreakdownOverall(gamePitches);
    final gameOverallStrike = (overallGame?['strikePct'] as num?)?.toDouble();
    final bpOverallZone = bullpen.overall.zonePct;
    final bpOverallAcc = bullpen.overall.targetAccuracy;

    final types = {...bullpen.byType.keys, ...gameRows.keys}.toList()..sort();
    final rows = <PitchComparison>[];
    for (final t in types) {
      final b = bullpen.byType[t];
      final g = gameRows[t];
      final gameN = (g?['n'] as int?) ?? 0;
      final gameStrike = (g?['strikePct'] as num?)?.toDouble();
      final bullpenEnough = b != null && b.landed >= min;
      final gameEnough = gameN >= min && gameStrike != null;
      bool? weakBp;
      if (b != null && bullpenEnough) {
        final zoneLow = b.zonePct != null && bpOverallZone != null && b.zonePct! < bpOverallZone - BullpenThresholds.gapPoints;
        final accLow = b.targetPitches >= min &&
            b.targetAccuracy != null &&
            bpOverallAcc != null &&
            b.targetAccuracy! < bpOverallAcc - BullpenThresholds.gapPoints;
        weakBp = zoneLow || accLow;
      }
      bool? weakGame;
      if (gameEnough && gameStrike != null && gameOverallStrike != null) {
        weakGame = gameStrike < gameOverallStrike - BullpenThresholds.gapPoints;
      }
      rows.add(PitchComparison(
        pitchType: t,
        bullpen: b,
        gamePitches: gameN,
        gameStrikePct: gameStrike,
        bullpenEnough: bullpenEnough,
        gameEnough: gameEnough,
        weakInBullpen: weakBp,
        weakInGame: weakGame,
      ));
    }

    // Did bullpen change carry into games? Split each pitch type's bullpen
    // history in half by time and look at games before/after that moment.
    final checks = <ImprovementCheck>[];
    for (final t in bullpen.byType.keys) {
      final list = bullpen.pitches.where((p) => p.pitchType == t && p.hasActual).toList();
      final sessionsTouched = list.map((p) => p.sessionId).toSet().length;
      if (list.length < min * 2 || sessionsTouched < 2) continue;
      final half = list.length ~/ 2;
      final early = BullpenStats(), late = BullpenStats();
      for (var i = 0; i < list.length; i++) {
        (i < half ? early : late).add(list[i]);
      }
      final splitAt = list[half].timestamp;
      final before = gamePitches.where((p) => p.timestamp.isBefore(splitAt)).toList();
      final after = gamePitches.where((p) => !p.timestamp.isBefore(splitAt)).toList();
      Map<String, dynamic>? rowFor(List<PitchEvent> d) {
        for (final r in StatsService.pitchBreakdown(d)) {
          if ((r['pitchType'] as String).toLowerCase() == t) return r;
        }
        return null;
      }

      final gb = rowFor(before), ga = rowFor(after);
      final nb = (gb?['n'] as int?) ?? 0, na = (ga?['n'] as int?) ?? 0;
      checks.add(ImprovementCheck(
        pitchType: t,
        splitAt: splitAt,
        earlyZone: early.zonePct,
        lateZone: late.zonePct,
        earlyAccuracy: early.targetPitches >= min ~/ 2 ? early.targetAccuracy : null,
        lateAccuracy: late.targetPitches >= min ~/ 2 ? late.targetAccuracy : null,
        gameBeforeStrike: (gb?['strikePct'] as num?)?.toDouble(),
        gameAfterStrike: (ga?['strikePct'] as num?)?.toDouble(),
        gameBeforeN: nb,
        gameAfterN: na,
        gameEnough: nb >= min && na >= min,
      ));
    }

    return BullpenGameComparison(
      rows: rows,
      overallBullpenZone: bpOverallZone,
      overallBullpenAccuracy: bpOverallAcc,
      overallGameStrike: gameOverallStrike,
      checks: checks,
    );
  }
}

class PlanSetResult {
  final int index;
  final PlanSet planned;
  final BullpenStats stats;
  const PlanSetResult(this.index, this.planned, this.stats);
  int get thrown => stats.pitches;
  bool get completed => thrown >= planned.reps;
}

class PitchComparison {
  final String pitchType;
  final BullpenStats? bullpen;
  final int gamePitches;
  final double? gameStrikePct;
  final bool bullpenEnough, gameEnough;
  final bool? weakInBullpen, weakInGame;
  const PitchComparison({
    required this.pitchType,
    required this.bullpen,
    required this.gamePitches,
    required this.gameStrikePct,
    required this.bullpenEnough,
    required this.gameEnough,
    required this.weakInBullpen,
    required this.weakInGame,
  });

  bool get weakInBoth => weakInBullpen == true && weakInGame == true;
  bool get strongBullpenWeakGame => weakInBullpen == false && weakInGame == true;
}

class ImprovementCheck {
  final String pitchType;
  final DateTime splitAt;
  final double? earlyZone, lateZone, earlyAccuracy, lateAccuracy;
  final double? gameBeforeStrike, gameAfterStrike;
  final int gameBeforeN, gameAfterN;
  final bool gameEnough;
  const ImprovementCheck({
    required this.pitchType,
    required this.splitAt,
    required this.earlyZone,
    required this.lateZone,
    required this.earlyAccuracy,
    required this.lateAccuracy,
    required this.gameBeforeStrike,
    required this.gameAfterStrike,
    required this.gameBeforeN,
    required this.gameAfterN,
    required this.gameEnough,
  });

  double? get zoneDelta => (earlyZone != null && lateZone != null) ? lateZone! - earlyZone! : null;
  double? get accuracyDelta => (earlyAccuracy != null && lateAccuracy != null) ? lateAccuracy! - earlyAccuracy! : null;
  double? get gameDelta =>
      (gameEnough && gameBeforeStrike != null && gameAfterStrike != null) ? gameAfterStrike! - gameBeforeStrike! : null;
}

class BullpenGameComparison {
  final List<PitchComparison> rows;
  final double? overallBullpenZone, overallBullpenAccuracy, overallGameStrike;
  final List<ImprovementCheck> checks;
  const BullpenGameComparison({
    required this.rows,
    required this.overallBullpenZone,
    required this.overallBullpenAccuracy,
    required this.overallGameStrike,
    required this.checks,
  });
}

/// Aggregates for Game Mode history (shown separately from bullpens).
class ChallengeSummary {
  final ChallengeMode mode;
  final Difficulty difficulty;
  final int attempts;
  final int passed;
  final int failed;
  final int bestScore;
  final int goal;
  final List<ChallengeAttempt> recent; // newest first
  const ChallengeSummary(this.mode, this.difficulty, this.attempts, this.passed, this.failed, this.bestScore, this.goal, this.recent);

  double get passRate => attempts == 0 ? 0 : passed / attempts * 100;

  /// Pass rate of the last 5 vs the 5 before them - progress at the SAME difficulty.
  double? get recentPassRate => _rate(recent.take(5).toList());
  double? get priorPassRate => recent.length > 5 ? _rate(recent.skip(5).take(5).toList()) : null;

  static double? _rate(List<ChallengeAttempt> l) =>
      l.isEmpty ? null : l.where((a) => a.success).length / l.length * 100;
}

List<ChallengeSummary> summarizeChallenges(List<ChallengeAttempt> attempts) {
  final out = <ChallengeSummary>[];
  for (final m in ChallengeMode.values) {
    for (final d in Difficulty.values) {
      final list = attempts.where((a) => a.mode == m && a.difficulty == d).toList()
        ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
      if (list.isEmpty) continue;
      final passed = list.where((a) => a.success).length;
      final best = list.map((a) => a.score).reduce(math.max);
      out.add(ChallengeSummary(m, d, list.length, passed, list.length - passed, best, list.first.goal, list));
    }
  }
  return out;
}
