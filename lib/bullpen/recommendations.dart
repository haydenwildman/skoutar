// "What to Work On Next" findings and the Recommended Bullpen Plan.
//
// Every sentence is assembled from the pitcher's own numbers; nothing is
// canned. When there is not enough data a rule stays silent and the screen
// says so instead of guessing. Measured results are kept apart from
// "possible explanations", which are labeled as unmeasured.

import 'dart:math' as math;
import 'analytics.dart';
import 'bullpen_models.dart';
import 'challenges.dart';
import 'plan_models.dart';

String _pct(double v) => '${v.toStringAsFixed(0)}%';
String _in(double v) => v.toStringAsFixed(1);

class Finding {
  final String id;
  final String title;
  final String whatHappened;
  final String whatItMeans;
  final String whatToDo;
  final String howToMeasure;

  /// Unmeasured ideas, shown under a "Possible explanation (not measured)" label.
  final String? possibleExplanation;
  final int priority; // lower = shown first
  final String? pitchType;

  const Finding({
    required this.id,
    required this.title,
    required this.whatHappened,
    required this.whatItMeans,
    required this.whatToDo,
    required this.howToMeasure,
    this.possibleExplanation,
    required this.priority,
    this.pitchType,
  });
}

class RecommendationSet {
  final List<Finding> findings;

  /// Set when there isn't enough data for the bullpen-based rules.
  final String? insufficientData;
  const RecommendationSet(this.findings, this.insufficientData);
}

/// Index (0-8, row-major from top-left) of the zone cell where this pitch
/// type's TARGETS were hit least often, or null if no cell has enough tries.
int? weakestCell(List<BullpenPitch> pitches, String type, {int minPerCell = 5}) {
  final tries = List<int>.filled(9, 0);
  final hits = List<int>.filled(9, 0);
  for (final p in pitches) {
    if (p.pitchType != type || !p.hasTarget || !p.hasActual) continue;
    final t = p.target!;
    final col = t.x < 1 / 3 ? 0 : (t.x < 2 / 3 ? 1 : 2);
    final row = t.y > 2 / 3 ? 0 : (t.y > 1 / 3 ? 1 : 2);
    final i = row * 3 + col;
    tries[i]++;
    if (p.hitTarget) hits[i]++;
  }
  int? best;
  double bestAcc = 2;
  for (var i = 0; i < 9; i++) {
    if (tries[i] < minPerCell) continue;
    final acc = hits[i] / tries[i];
    if (acc < bestAcc) {
      bestAcc = acc;
      best = i;
    }
  }
  return best;
}

class Recommender {
  Recommender._();

  static RecommendationSet findings({
    required BullpenAnalysis analysis,
    required BullpenGameComparison? comparison,
    required List<ChallengeAttempt> attempts,
    required List<PlanSetResult> lastPlanResults,
    required String Function(String) label,
  }) {
    final min = BullpenThresholds.minPitchTypeSample;
    final out = <Finding>[];
    String? insufficient;

    final totalTargets = analysis.overall.targetPitches;
    if (totalTargets < BullpenThresholds.minTotalTargetPitches) {
      insufficient = 'Not enough bullpen data yet: $totalTargets pitches with a target across '
          '${analysis.sessionCount} finished bullpen${analysis.sessionCount == 1 ? '' : 's'}. '
          'Bullpen-based recommendations start once there are ${BullpenThresholds.minTotalTargetPitches} '
          'targeted pitches. Keep setting a target and marking where each pitch lands.';
    } else {
      final overallAcc = analysis.overall.targetAccuracy!;
      final overallZone = analysis.overall.zonePct;

      // 1. Lowest target accuracy.
      final accCands = analysis.byType.entries
          .where((e) => e.value.targetPitches >= min && e.value.targetAccuracy != null)
          .toList()
        ..sort((a, b) => a.value.targetAccuracy!.compareTo(b.value.targetAccuracy!));
      if (accCands.isNotEmpty) {
        final e = accCands.first;
        final s = e.value;
        final acc = s.targetAccuracy!;
        final gap = overallAcc - acc;
        final relative = accCands.length >= 2 && gap >= BullpenThresholds.gapPoints;
        if (relative || (accCands.length == 1 && acc < 50)) {
          final cell = weakestCell(analysis.pitches, e.key);
          final goal = math.min(100, acc + 10);
          out.add(Finding(
            id: 'low-accuracy-${e.key}',
            title: '${label(e.key)} target accuracy',
            whatHappened: '${label(e.key)}: ${_pct(acc)} target accuracy on ${s.targetPitches} targeted pitches '
                '(average target ${_in(s.avgTargetWidthIn!)} x ${_in(s.avgTargetHeightIn!)} in)'
                '${relative ? '; your overall is ${_pct(overallAcc)}.' : '.'}',
            whatItMeans: relative
                ? 'It is the lowest of ${accCands.length} pitch types with enough data, ${gap.toStringAsFixed(0)} points '
                    'below your overall accuracy, so it has the most room to improve.'
                : 'Fewer than half of your targeted ${label(e.key)} landed inside the target you set.',
            whatToDo: 'Throw 20 ${label(e.key)}: 10 at a ${_in(s.avgTargetWidthIn!)} x ${_in(s.avgTargetHeightIn!)} in target'
                '${cell != null ? ', then 10 at the ${ChallengeRules.cellNames[cell].toLowerCase()} area, where you hit your target least' : ''}. '
                'Goal: ${_pct(goal.toDouble())} target accuracy.',
            howToMeasure: 'Target accuracy for ${label(e.key)} at about the same target size next bullpen (now ${_pct(acc)} on ${s.targetPitches}).',
            priority: 10,
            pitchType: e.key,
          ));
        }
      }

      // 2. Misses that lean one way.
      String? leanType;
      int leanMisses = 0;
      for (final e in analysis.missesByType.entries) {
        if (e.value.dominant != null && e.value.misses > leanMisses) {
          leanType = e.key;
          leanMisses = e.value.misses;
        }
      }
      if (leanType != null) {
        final m = analysis.missesByType[leanType]!;
        final dir = m.dominant!;
        final count = switch (dir) {
          'high' => m.high,
          'low' => m.low,
          'arm-side' => m.armSide,
          _ => m.gloveSide,
        };
        final vertical = dir == 'high' || dir == 'low';
        final avg = vertical ? m.avgHighIn! : m.avgArmSideIn!;
        final axis = vertical ? 'vertical' : 'horizontal';
        out.add(Finding(
          id: 'miss-lean-$leanType',
          title: '${label(leanType)} misses lean $dir',
          whatHappened: '$count of ${m.misses} ${label(leanType)} misses (${_pct(count / m.misses * 100)}) '
              'were $dir. On average a miss was ${_in(avg.abs())} in ${vertical ? (avg >= 0 ? 'high' : 'low') : (avg >= 0 ? 'arm-side' : 'glove-side')} of the target.',
          whatItMeans: 'Misses that go the same way are a pattern, not random scatter, so they can be corrected on purpose.',
          whatToDo: 'Throw 15 ${label(leanType)} at one fixed target and watch only the $axis miss. '
              'Goal: average $axis miss within 2 in of the target.',
          howToMeasure: 'Share of ${label(leanType)} misses that are $dir next bullpen (now ${_pct(count / m.misses * 100)}) and the average $axis miss (now ${_in(avg.abs())} in).',
          priority: 20,
          pitchType: leanType,
        ));
      }

      // 3. Fewer strikes than the pitcher's other pitches.
      if (overallZone != null) {
        final zoneCands = analysis.byType.entries
            .where((e) => e.value.landed >= min && e.value.zonePct != null)
            .toList()
          ..sort((a, b) => a.value.zonePct!.compareTo(b.value.zonePct!));
        if (zoneCands.length >= 2) {
          final e = zoneCands.first;
          final z = e.value.zonePct!;
          if (overallZone - z >= BullpenThresholds.gapPoints) {
            out.add(Finding(
              id: 'low-zone-${e.key}',
              title: '${label(e.key)} strikes',
              whatHappened: '${label(e.key)} landed in the strike zone ${_pct(z)} of the time (${e.value.landed} pitches) vs ${_pct(overallZone)} for all your bullpen pitches.',
              whatItMeans: 'Strike % is separate from target accuracy: this pitch is leaving the zone more often than your others, even before looking at where you aimed.',
              whatToDo: 'Throw 20 ${label(e.key)} at a full-zone target. Goal: at least ${_pct(overallZone)} in the zone.',
              howToMeasure: 'Strike % for ${label(e.key)} next bullpen (now ${_pct(z)}).',
              priority: 30,
              pitchType: e.key,
            ));
          }
        }
      }

      // 4 / 5. Bullpen vs. game.
      if (comparison != null) {
        for (final r in comparison.rows) {
          if (r.weakInBoth) {
            out.add(Finding(
              id: 'both-${r.pitchType}',
              title: '${label(r.pitchType)} is a weakness in both settings',
              whatHappened: '${label(r.pitchType)} is below your own average in bullpens (${r.bullpen!.zonePct != null ? 'strike ${_pct(r.bullpen!.zonePct!)}' : ''}'
                  '${r.bullpen!.targetAccuracy != null ? ', target ${_pct(r.bullpen!.targetAccuracy!)}' : ''}) '
                  'and in games (strike ${_pct(r.gameStrikePct!)} vs ${_pct(comparison.overallGameStrike!)} overall, ${r.gamePitches} pitches).',
              whatItMeans: 'It shows up in two different settings, so it is less likely to be a one-day issue.',
              whatToDo: 'Make ${label(r.pitchType)} the first block of your next bullpen: 25 reps, alternating a large and a medium target.',
              howToMeasure: 'Bullpen strike %/target accuracy for ${label(r.pitchType)} next bullpen, and its strike % in your next game.',
              priority: 5,
              pitchType: r.pitchType,
            ));
          } else if (r.strongBullpenWeakGame) {
            out.add(Finding(
              id: 'gap-${r.pitchType}',
              title: '${label(r.pitchType)}: bullpen vs. game',
              whatHappened: '${label(r.pitchType)} is not below your bullpen average, but in games its strike % is ${_pct(r.gameStrikePct!)} vs ${_pct(comparison.overallGameStrike!)} overall (${r.gamePitches} pitches).',
              whatItMeans: 'Bullpen strikes and game strikes are defined differently, so each is judged against your own average rather than against each other. '
                  'This pitch looks weaker in games than its bullpen results suggest.',
              possibleExplanation: 'Game conditions (hitters, count, situation) or how often it is thrown in hard counts. Neither is measured here.',
              whatToDo: 'Use a Simulated Hitters bullpen: 15 ${label(r.pitchType)} with a different target before every pitch.',
              howToMeasure: 'Game strike % for ${label(r.pitchType)} in your next outing (now ${_pct(r.gameStrikePct!)}).',
              priority: 15,
              pitchType: r.pitchType,
            ));
          }
        }
        // 7. Is bullpen improvement showing in games?
        for (final c in comparison.checks) {
          final bpDelta = c.zoneDelta ?? c.accuracyDelta;
          if (bpDelta == null || bpDelta < BullpenThresholds.gapPoints) continue;
          final what = c.zoneDelta != null ? 'strike %' : 'target accuracy';
          final from = c.zoneDelta != null ? c.earlyZone! : c.earlyAccuracy!;
          final to = c.zoneDelta != null ? c.lateZone! : c.lateAccuracy!;
          final gd = c.gameDelta;
          out.add(Finding(
            id: 'carry-${c.pitchType}',
            title: '${label(c.pitchType)} bullpen gains',
            whatHappened: 'Bullpen $what for ${label(c.pitchType)} moved from ${_pct(from)} to ${_pct(to)}. '
                '${gd == null ? 'There are not enough game pitches before/after (${c.gameBeforeN} / ${c.gameAfterN}) to compare.' : 'In games its strike % went from ${_pct(c.gameBeforeStrike!)} (${c.gameBeforeN} pitches) to ${_pct(c.gameAfterStrike!)} (${c.gameAfterN}).'}',
            whatItMeans: gd == null
                ? 'The practice gain is measured; whether it carries into games cannot be checked yet.'
                : (gd >= 2 ? 'The practice gain and the game numbers moved the same way.' : 'The practice gain is not visible in game strike % yet.'),
            whatToDo: 'Keep the same ${label(c.pitchType)} work and add a Simulated Hitters set.',
            howToMeasure: 'Game strike % for ${label(c.pitchType)} over your next ${BullpenThresholds.minPitchTypeSample} or more game pitches.',
            priority: 40,
            pitchType: c.pitchType,
          ));
        }
      }

      // 8. Swings from bullpen to bullpen.
      final sessionAcc = [
        for (final s in analysis.perSession)
          if (s.stats.targetPitches >= 10) s.stats.targetAccuracy!,
      ];
      if (sessionAcc.length >= 3) {
        final hi = sessionAcc.reduce(math.max), lo = sessionAcc.reduce(math.min);
        if (hi - lo >= 20) {
          out.add(Finding(
            id: 'consistency',
            title: 'Bullpen-to-bullpen consistency',
            whatHappened: 'Target accuracy ranged from ${_pct(lo)} to ${_pct(hi)} across ${sessionAcc.length} bullpens.',
            whatItMeans: 'A ${(hi - lo).toStringAsFixed(0)}-point swing means results depend a lot on the day. Target size also changes accuracy, so check sizes before comparing.',
            whatToDo: 'Run the same plan (same pitches, targets and sizes) in two bullpens in a row.',
            howToMeasure: 'The gap between those two bullpens\' target accuracy; smaller is more consistent.',
            priority: 50,
          ));
        }
      }
    }

    // 6. Sequencing challenge: where do failed attempts break? (independent of bullpen data)
    final seqFails = attempts.where((a) => a.mode == ChallengeMode.sequence).toList();
    final failed = seqFails.where((a) => !a.success && a.endReason == 'miss' && a.detail.isNotEmpty).toList();
    if (seqFails.length >= 3 && failed.length >= 2) {
      final byPitch = <String, int>{};
      for (final a in failed) {
        final t = a.detail.last['pitchType'] as String;
        byPitch[t] = (byPitch[t] ?? 0) + 1;
      }
      final top = byPitch.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (top.value >= 2 && top.value / failed.length >= 0.4) {
        out.add(Finding(
          id: 'sequence-break',
          title: 'Where your sequences break',
          whatHappened: '${top.value} of ${failed.length} failed Pitch Sequencing attempts ended on a ${label(top.key)}.',
          whatItMeans: 'That pitch is where your sequences most often stop, so it is the weak link in the chain.',
          whatToDo: 'Do 15 ${label(top.key)} at a target the size of your sequence challenge, then replay the sequence.',
          howToMeasure: 'Share of failed sequence attempts that end on ${label(top.key)}, and your sequence pass rate at the same difficulty.',
          priority: 25,
          pitchType: top.key,
        ));
      }
    }

    // 9. How the last planned bullpen went.
    if (lastPlanResults.isNotEmpty) {
      final done = lastPlanResults.where((r) => r.completed).length;
      final parts = <String>[];
      for (final r in lastPlanResults) {
        final acc = r.stats.targetAccuracy;
        parts.add('${label(r.planned.pitchType)} ${r.thrown}/${r.planned.reps} reps'
            '${acc != null ? ', ${_pct(acc)} on target' : ''}');
      }
      out.add(Finding(
        id: 'last-plan',
        title: 'Your last planned bullpen',
        whatHappened: 'You completed $done of ${lastPlanResults.length} sets: ${parts.join('; ')}.',
        whatItMeans: 'The next plan reads these results: sets you hit well get smaller targets, sets you missed get larger ones.',
        whatToDo: 'Generate a new plan below; it already uses this bullpen.',
        howToMeasure: 'Compare each set\'s target accuracy with the numbers above at the new target size.',
        priority: 60,
      ));
    }

    out.sort((a, b) => a.priority.compareTo(b.priority));
    return RecommendationSet(out.take(6).toList(), insufficient);
  }
}

class PlanGenerator {
  PlanGenerator._();

  static const double defaultSize = 0.35;

  /// Target size for a pitch: from its most recent bullpen if there is one
  /// with enough targets (so each bullpen reshapes the next plan), else from
  /// all its history, else a medium default.
  static double sizeFor(BullpenAnalysis a, String type, {double scale = 1.0}) {
    BullpenStats? basis;
    final mine = a.pitches.where((p) => p.pitchType == type && p.hasTarget && p.hasActual).toList();
    if (mine.isNotEmpty) {
      final lastSession = mine.last.sessionId;
      final recent = BullpenStats();
      for (final p in mine.where((p) => p.sessionId == lastSession)) {
        recent.add(p);
      }
      if (recent.targetPitches >= 8) basis = recent;
    }
    basis ??= (a.byType[type]?.targetPitches ?? 0) >= 10 ? a.byType[type] : null;
    var size = defaultSize;
    if (basis != null && basis.avgTargetSize != null && basis.targetAccuracy != null) {
      size = basis.avgTargetSize!;
      if (basis.targetAccuracy! >= 65) size *= 0.85;
      if (basis.targetAccuracy! <= 35) size *= 1.15;
    }
    return (size * scale).clamp(0.12, 0.9).toDouble();
  }

  static ZoneTarget _aim(BullpenAnalysis a, String type, double size) {
    final cell = weakestCell(a.pitches, type);
    final c = ChallengeRules.cells[cell ?? 4];
    return ZoneTarget(c[0], c[1], size, size);
  }

  static List<String> _byWeakness(BullpenAnalysis a, List<String> available) {
    final withData = a.byType.entries
        .where((e) => e.value.targetPitches >= 10 && e.value.targetAccuracy != null && available.contains(e.key))
        .toList()
      ..sort((x, y) => x.value.targetAccuracy!.compareTo(y.value.targetAccuracy!));
    final order = withData.map((e) => e.key).toList();
    for (final t in available) {
      if (!order.contains(t)) order.add(t);
    }
    return order;
  }

  static BullpenPlan generate({
    required PlanFocus focus,
    required BullpenAnalysis analysis,
    required List<ChallengeAttempt> attempts,
    required List<String> availableTypes,
    required String Function(String) label,
    List<String> gameUsageOrder = const [],
    DateTime? now,
  }) {
    final types = availableTypes.isEmpty ? <String>['fb'] : availableTypes;
    final sets = <PlanSet>[];
    final why = <String>[];

    String accNote(String t) {
      final s = analysis.byType[t];
      if (s == null || s.targetPitches < 10 || s.targetAccuracy == null) return 'no target history yet, so this sets a baseline';
      return 'currently ${_pct(s.targetAccuracy!)} on ${s.targetPitches} targeted pitches';
    }

    switch (focus) {
      case PlanFocus.command:
        {
        final order = _byWeakness(analysis, types).take(3).toList();
        for (var i = 0; i < order.length; i++) {
          final t = order[i];
          final size = sizeFor(analysis, t);
          sets.add(PlanSet(
            pitchType: t,
            reps: i == 0 ? 20 : 15,
            target: _aim(analysis, t, size),
            purpose: 'Raise target accuracy on ${label(t)} (${accNote(t)}).',
          ));
        }
        why.add('Pitches are ordered from lowest to highest target accuracy; pitches without history come last.');
        why.add('Target size follows your last bullpen: smaller where you hit 65%+, larger where you hit 35% or less.');
        why.add('Aim is the zone area where you hit that pitch\'s targets least (needs 5 tries per area), else the middle.');
        break;
        }

      case PlanFocus.pitchDevelopment:
        {
        final counts = {for (final t in types) t: analysis.byType[t]?.pitches ?? 0};
        final order = types.toList()..sort((a, b) => counts[a]!.compareTo(counts[b]!));
        for (final t in order.take(2)) {
          final size = sizeFor(analysis, t, scale: 1.25);
          sets.add(PlanSet(
            pitchType: t,
            reps: 20,
            target: ZoneTarget(0.5, 0.5, size, size),
            purpose: '${label(t)} has ${counts[t]} bullpen pitch${counts[t] == 1 ? '' : 'es'} logged; build repetitions with a roomier target.',
          ));
        }
        why.add('Pitches with the fewest logged bullpen reps come first; targets are 25% larger so the focus is feel, not precision.');
        break;
        }

      case PlanFocus.sequencing:
        {
        final usage = [
          ...gameUsageOrder.where(types.contains),
          ...types.where((t) => !gameUsageOrder.contains(t)),
        ];
        final base = usage.first;
        final b = usage.length > 1 ? usage[1] : base;
        final c = usage.length > 2 ? usage[2] : b;
        final pattern = [base, b, base, c, base];
        // Slot that sequence challenges break on, if there is history.
        String? breakType;
        final fails = attempts.where((a) => a.mode == ChallengeMode.sequence && !a.success && a.detail.isNotEmpty);
        final counts = <String, int>{};
        for (final a in fails) {
          final t = a.detail.last['pitchType'] as String;
          counts[t] = (counts[t] ?? 0) + 1;
        }
        if (counts.isNotEmpty) breakType = counts.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
        for (var i = 0; i < pattern.length; i++) {
          final t = pattern[i];
          final size = sizeFor(analysis, t);
          final cell = ChallengeRules.cells[ChallengeRules.sequenceCellOrder[i % ChallengeRules.sequenceCellOrder.length]];
          sets.add(PlanSet(
            pitchType: t,
            reps: t == breakType ? 8 : 5,
            target: ZoneTarget(cell[0], cell[1], size, size),
            purpose: 'Step ${i + 1} of the ${pattern.map(label).join(' - ')} sequence${t == breakType ? ' (your sequences break most often on ${label(t)})' : ''}.',
          ));
        }
        why.add('Sequence is built from your most-used pitches (${pattern.map(label).join(', ')}); each set is one step, repeated.');
        break;
        }

      case PlanFocus.consistency:
        {
        final stats = {
          for (final e in analysis.byType.entries)
            if (e.value.targetPitches >= 10 && e.value.avgDistanceIn != null && types.contains(e.key)) e.key: e.value.avgDistanceIn!,
        };
        final order = stats.keys.toList()..sort((a, b) => stats[b]!.compareTo(stats[a]!));
        for (final t in [...order, ...types.where((t) => !order.contains(t))].take(2)) {
          final size = sizeFor(analysis, t);
          sets.add(PlanSet(
            pitchType: t,
            reps: 20,
            target: ZoneTarget(0.5, 0.5, size, size),
            purpose: stats.containsKey(t)
                ? 'Repeat one fixed target to tighten spread (average miss ${_in(stats[t]!)} in).'
                : 'Repeat one fixed target to set a baseline for ${label(t)}.',
          ));
        }
        why.add('Pitches with the largest average miss distance come first; every rep uses the same target so spread is easy to compare.');
        break;
        }

      case PlanFocus.general:
        {
        final order = _byWeakness(analysis, types).take(4).toList();
        for (final t in order) {
          final size = sizeFor(analysis, t);
          sets.add(PlanSet(
            pitchType: t,
            reps: 12,
            target: _aim(analysis, t, size),
            purpose: 'Keep ${label(t)} sharp (${accNote(t)}).',
          ));
        }
        why.add('A balanced mix of up to four pitches, weakest first.');
        break;
        }
    }

    if (analysis.overall.targetPitches < BullpenThresholds.minTotalTargetPitches) {
      why.add('There are only ${analysis.overall.targetPitches} targeted bullpen pitches so far, so this plan uses defaults where history is missing. Edit it freely.');
    }
    return BullpenPlan(focus: focus, sets: sets, rationale: why, createdAt: now ?? DateTime.now());
  }
}
