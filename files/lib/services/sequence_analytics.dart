import 'dart:math' as math;

import '../models/pitch_event.dart';
import 'sequence_scoring.dart';

/// Descriptive pitch-sequencing statistics built ONLY from what SKOUTAR
/// records: pitch type, call, count and plate-appearance outcome. Nothing here
/// needs velocity, movement or location, and nothing here uses a hand-picked
/// weight.
///
/// DESCRIPTIVE statistics (counts, strike %, whiff %, BAA, K %, out %) are
/// plain ratios of logged events, always shown with their sample size.
///
/// The ONE modeled number is the Wilson 95% lower bound on out rate used to
/// RANK opening sequences (see [wilsonLower]). It has no tunable weights: it is
/// the standard statistical confidence bound, so a sequence seen 3 times is
/// ranked below one with the same out rate seen 30 times. It is a ranking aid,
/// not a prediction.
class SeqSampleSize {
  /// Below this many pitches a pitch-level cell is flagged "small sample".
  /// Display flag only; it never changes a number.
  static const int smallPitches = 10;

  /// Below this many plate appearances an opening-sequence row is flagged.
  static const int smallPas = 5;
}

/// How a pitch ended its own pitch-level event.
class PitchResults {
  int n = 0, balls = 0, called = 0, swinging = 0, fouls = 0, inPlay = 0, hbp = 0;

  void add(PitchEvent p) {
    n++;
    switch (p.call) {
      case 'b':
        balls++;
        break;
      case 'sl':
        called++;
        break;
      case 'ss':
        swinging++;
        break;
      case 'f':
        fouls++;
        break;
      case 'ip':
        inPlay++;
        break;
      case 'hbp':
        hbp++;
        break;
    }
  }

  int get strikes => called + swinging + fouls + inPlay;
  int get swings => swinging + fouls + inPlay;
  double? get strikePct => n == 0 ? null : strikes / n * 100;
  double? get whiffPct => swings == 0 ? null : swinging / swings * 100;
  double? get ballPct => n == 0 ? null : balls / n * 100;
  bool get small => n < SeqSampleSize.smallPitches;
}

/// Plate-appearance-level results (used per count, per transition, per sequence).
class PaResults {
  int pas = 0, k = 0, bb = 0, hbp = 0, hits = 0, ab = 0, outs = 0;

  // 'dk3' (dropped third strike) is a strikeout for the pitcher but the batter
  // may reach, so it is not counted as a batter retired.
  static const _reach = {'1b', '2b', '3b', 'hr', 'bb', 'hbp', 'e', 'dk3'};

  /// Adds one FINISHED plate appearance's outcome.
  void addOutcome(String? o) {
    if (o == null || o.isEmpty) return;
    pas++;
    if (PitchEvent.kOutcomes.contains(o)) k++;
    if (o == 'bb') bb++;
    if (o == 'hbp') hbp++;
    if (o != 'bb' && o != 'hbp') ab++;
    if (PitchEvent.hitOutcomes.contains(o)) hits++;
    // Anything that is not a hit/walk/HBP/error/dropped third strike is a
    // batter retired (a fielder's choice counts as an out).
    if (!_reach.contains(o)) outs++;
  }

  double? get baa => ab == 0 ? null : hits / ab;
  double? get kPct => pas == 0 ? null : k / pas * 100;
  double? get bbPct => pas == 0 ? null : bb / pas * 100;
  double? get outPct => pas == 0 ? null : outs / pas * 100;
}

/// Wilson score interval LOWER bound (z = 1.96 → 95%) for [successes]/[n].
/// Returns a proportion in 0..1, or null when n == 0.
double? wilsonLower(int successes, int n, {double z = 1.96}) {
  if (n <= 0) return null;
  final p = successes / n;
  final z2 = z * z;
  final denom = 1 + z2 / n;
  final centre = p + z2 / (2 * n);
  final margin = z * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n));
  return ((centre - margin) / denom).clamp(0.0, 1.0).toDouble();
}

/// Wilson score interval UPPER bound.
double? wilsonUpper(int successes, int n, {double z = 1.96}) {
  if (n <= 0) return null;
  final p = successes / n;
  final z2 = z * z;
  final denom = 1 + z2 / n;
  final centre = p + z2 / (2 * n);
  final margin = z * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n));
  return ((centre + margin) / denom).clamp(0.0, 1.0).toDouble();
}

/// Results of the NEXT pitch after a given previous pitch type.
class AfterPitchRow {
  final String prevType;
  final PitchResults next = PitchResults();
  final Map<String, int> nextTypes = {};
  AfterPitchRow(this.prevType);
}

/// One A → B pitch-type transition (B thrown right after A in the same PA).
class TransitionRow {
  final String from, to;
  final PitchResults results = PitchResults(); // outcome of the B pitch
  final PaResults paEnd = PaResults(); // only when B ended the plate appearance
  TransitionRow(this.from, this.to);
  int get n => results.n;
}

/// One ball-strike count (balls before the pitch, strikes before the pitch).
class CountRow {
  final int balls, strikes;
  final PitchResults pitches = PitchResults();
  final PaResults paEnd = PaResults(); // PAs whose FINAL pitch was thrown here
  final Map<String, int> mix = {}; // pitch type -> pitches thrown at this count
  CountRow(this.balls, this.strikes);
  String get label => '$balls-$strikes';
}

/// Pitch-type usage inside one group of pitches (a count situation or a batter
/// hand). Counts are plain tallies of logged pitches.
class MixRow {
  final String label;
  final PitchResults pitches = PitchResults();
  final PaResults paEnd = PaResults(); // PAs whose FINAL pitch is in this group
  final Map<String, int> mix = {};
  MixRow(this.label);
  int get n => pitches.n;

  /// (pitch type, share 0..1) pairs, most used first.
  List<(String, double)> get shares {
    final entries = mix.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in entries) (e.key, e.value / n)];
  }

  bool get small => n < SeqSampleSize.smallPitches;
}

/// An opening sequence (first [length] pitch types) over finished PAs.
class SequenceRow {
  final String label; // e.g. FB→CH→CV
  final int length;
  final PaResults pa = PaResults();
  int strikePitches = 0; // of the length x pas opening pitches
  SequenceRow(this.label, this.length);

  int get n => pa.pas;
  double? get strikePct => n == 0 ? null : strikePitches / (n * length) * 100;
  double? get outLower => wilsonLower(pa.outs, n);
  double? get outUpper => wilsonUpper(pa.outs, n);
  bool get small => n < SeqSampleSize.smallPas;
}

/// Counts that explain WHY a metric is or is not available.
class SequenceDiagnostics {
  final int pitchRows; // eventType == 'pitch' rows received
  final int plateAppearances; // reconstructed PAs (finished or not)
  final int finishedPas;
  final int pasWith2Plus;
  final int pasWith3Plus; // finished AND 3+ pitches
  final int transitions; // consecutive pitch pairs inside a PA
  final int pitchesMissingType;
  final int pitchesMissingCall;
  const SequenceDiagnostics({
    required this.pitchRows,
    required this.plateAppearances,
    required this.finishedPas,
    required this.pasWith2Plus,
    required this.pasWith3Plus,
    required this.transitions,
    required this.pitchesMissingType,
    required this.pitchesMissingCall,
  });
}

class SequenceAnalytics {
  final SequenceDiagnostics diagnostics;
  final List<AfterPitchRow> afterPitch; // by previous pitch type, n desc
  final List<TransitionRow> transitions; // A→B, n desc
  final List<CountRow> counts; // 12 counts in standard order (with data only)
  final List<SequenceRow> openingTwo; // first two pitches, finished PAs
  final List<SequenceRow> openingThree; // first three pitches, finished PAs
  final List<MixRow> situations; // pitch usage by count situation (with data only)
  final List<MixRow> byHand; // pitch usage / results by batter hand (with data only)

  const SequenceAnalytics({
    required this.diagnostics,
    required this.afterPitch,
    required this.transitions,
    required this.counts,
    required this.openingTwo,
    required this.openingThree,
    required this.situations,
    required this.byHand,
  });

  bool get hasTransitions => transitions.isNotEmpty;
  bool get hasCounts => counts.isNotEmpty;
  bool get hasOpeningTwo => openingTwo.isNotEmpty;
  bool get hasOpeningThree => openingThree.isNotEmpty;
  bool get hasSituations => situations.isNotEmpty;
  bool get hasHandSplit => byHand.length >= 2;

  static String typeKey(PitchEvent p) {
    final t = (p.pitchType ?? '').toLowerCase().trim();
    return t.isEmpty ? 'other' : t;
  }

  /// [data] = pitch rows to analyse (already filtered by team/game/year).
  /// Row order is irrelevant: plate appearances are rebuilt with
  /// [SequenceScoring.splitPlateAppearances].
  static SequenceAnalytics build(List<PitchEvent> data) {
    final pitchRows = data.where((p) => p.eventType == 'pitch' && p.call != 'dk').toList();
    final pas = SequenceScoring.splitPlateAppearances(data);

    final after = <String, AfterPitchRow>{};
    final trans = <String, TransitionRow>{};
    final countMap = <String, CountRow>{};
    final two = <String, SequenceRow>{};
    final three = <String, SequenceRow>{};
    final situ = <String, MixRow>{};
    final hands = <String, MixRow>{};
    var finished = 0, with2 = 0, with3 = 0, transitionCount = 0;

    const strikeCalls = {'ss', 'sl', 'f', 'ip'};

    for (final pa in pas) {
      final done = pa.last.isFinalPitchOfPA;
      if (done) finished++;
      final cts = SequenceScoring.countsBefore(pa);

      // By count: every pitch is credited to the count it was thrown in.
      for (var i = 0; i < pa.length; i++) {
        final (b, s) = cts[i];
        final row = countMap.putIfAbsent('$b-$s', () => CountRow(b, s));
        row.pitches.add(pa[i]);
        final t = typeKey(pa[i]);
        row.mix[t] = (row.mix[t] ?? 0) + 1;
        final isLast = done && i == pa.length - 1;
        if (isLast) row.paEnd.addOutcome(pa[i].outcome);

        // Count situations use plain balls/strikes comparisons (no weights).
        // A pitch can belong to more than one group (e.g. 0-2 is both
        // "Ahead" and "Two strikes").
        final groups = <String>[
          if (b == 0 && s == 0) 'First pitch (0-0)',
          if (s > b) 'Ahead (more strikes than balls)',
          if (s == b && !(b == 0 && s == 0)) 'Even (same balls and strikes, after 0-0)',
          if (b > s) 'Behind (more balls than strikes)',
          if (s == 2) 'Two strikes',
        ];
        for (final g in groups) {
          final m = situ.putIfAbsent(g, () => MixRow(g));
          m.pitches.add(pa[i]);
          m.mix[t] = (m.mix[t] ?? 0) + 1;
          if (isLast) m.paEnd.addOutcome(pa[i].outcome);
        }

        // Batter hand is whatever was stored on the row (the app stores R when
        // none was chosen, so an all-R split is not evidence of no lefties).
        final h = (pa[i].hand).toUpperCase();
        if (h == 'L' || h == 'R') {
          final hm = hands.putIfAbsent(h, () => MixRow(h == 'L' ? 'Left-handed batters' : 'Right-handed batters'));
          hm.pitches.add(pa[i]);
          hm.mix[t] = (hm.mix[t] ?? 0) + 1;
          if (isLast) hm.paEnd.addOutcome(pa[i].outcome);
        }
      }

      // Pitch-to-pitch transitions inside the PA.
      for (var i = 1; i < pa.length; i++) {
        transitionCount++;
        final a = typeKey(pa[i - 1]), bT = typeKey(pa[i]);
        final ar = after.putIfAbsent(a, () => AfterPitchRow(a));
        ar.next.add(pa[i]);
        ar.nextTypes[bT] = (ar.nextTypes[bT] ?? 0) + 1;
        final tr = trans.putIfAbsent('$a>$bT', () => TransitionRow(a, bT));
        tr.results.add(pa[i]);
        if (done && i == pa.length - 1) tr.paEnd.addOutcome(pa[i].outcome);
      }

      // Opening sequences need a finished PA so every row has a known result.
      if (done) {
        if (pa.length >= 2) {
          with2++;
          final label = pa.take(2).map((p) => typeKey(p).toUpperCase()).join('→');
          final r = two.putIfAbsent(label, () => SequenceRow(label, 2));
          r.pa.addOutcome(pa.last.outcome);
          r.strikePitches += pa.take(2).where((p) => strikeCalls.contains(p.call)).length;
        }
        if (pa.length >= 3) {
          with3++;
          final label = pa.take(3).map((p) => typeKey(p).toUpperCase()).join('→');
          final r = three.putIfAbsent(label, () => SequenceRow(label, 3));
          r.pa.addOutcome(pa.last.outcome);
          r.strikePitches += pa.take(3).where((p) => strikeCalls.contains(p.call)).length;
        }
      }
    }

    const order = [
      '0-0', '0-1', '0-2', '1-0', '1-1', '1-2', '2-0', '2-1', '2-2', '3-0', '3-1', '3-2'
    ];
    final counts = [
      for (final k in order)
        if (countMap[k] != null) countMap[k]!,
    ];

    const situOrder = [
      'First pitch (0-0)',
      'Ahead (more strikes than balls)',
      'Even (same balls and strikes, after 0-0)',
      'Behind (more balls than strikes)',
      'Two strikes',
    ];
    final situations = [
      for (final k in situOrder)
        if (situ[k] != null) situ[k]!,
    ];
    final byHand = [
      for (final k in const ['R', 'L'])
        if (hands[k] != null) hands[k]!,
    ];

    // Ranking: Wilson lower bound on out rate (higher = more reliably effective),
    // then sample size, then label for a stable order.
    int rank(SequenceRow a, SequenceRow b) {
      final c = (b.outLower ?? -1).compareTo(a.outLower ?? -1);
      if (c != 0) return c;
      final n = b.n.compareTo(a.n);
      return n != 0 ? n : a.label.compareTo(b.label);
    }

    return SequenceAnalytics(
      diagnostics: SequenceDiagnostics(
        pitchRows: pitchRows.length,
        plateAppearances: pas.length,
        finishedPas: finished,
        pasWith2Plus: with2,
        pasWith3Plus: with3,
        transitions: transitionCount,
        pitchesMissingType: pitchRows.where((p) => (p.pitchType ?? '').trim().isEmpty).length,
        pitchesMissingCall: pitchRows.where((p) => (p.call ?? '').trim().isEmpty).length,
      ),
      afterPitch: after.values.toList()..sort((a, b) => b.next.n.compareTo(a.next.n)),
      transitions: trans.values.toList()
        ..sort((a, b) {
          final c = b.n.compareTo(a.n);
          return c != 0 ? c : '${a.from}>${a.to}'.compareTo('${b.from}>${b.to}');
        }),
      counts: counts,
      openingTwo: two.values.toList()..sort(rank),
      openingThree: three.values.toList()..sort(rank),
      situations: situations,
      byHand: byHand,
    );
  }
}
