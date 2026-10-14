import 'dart:math' as math;
import 'package:collection/collection.dart';
import '../models/pitch_event.dart';
import 'stats_service.dart';

/// ══════════════════════════════════════════════════════════════
/// OPPONENT GAME PLAN
///
/// Extra analytics for the Scouting Report: per-hitter reports, lineup
/// grouping, team tendencies by count, pitch-selection strategy,
/// situational splits, a chronological matchup review and auto-generated
/// takeaways.
///
/// Nothing here changes an existing calculation. Plate-appearance results
/// reuse [PAResult] and pitch-level flags use the same call codes as
/// [StatsService] (swing = ss/f/ip, whiff = ss, called strike = sl).
/// Everything is computed from the events passed in (already filtered to
/// one opponent by the screen) and nothing is invented: a value that
/// cannot be computed is null / "unknown".
/// ══════════════════════════════════════════════════════════════

// ─── Confidence ───────────────────────────────────────────────

enum Confidence { insufficient, low, moderate, solid }

extension ConfidenceLabel on Confidence {
  String get label => switch (this) {
        Confidence.insufficient => 'Insufficient data',
        Confidence.low => 'Low confidence',
        Confidence.moderate => 'Moderate confidence',
        Confidence.solid => 'Solid sample',
      };
}

/// Sample-size grade for pitch-level counts (pitches or swings).
Confidence pitchConfidence(int n) => n < 3
    ? Confidence.insufficient
    : (n < 8 ? Confidence.low : (n < 20 ? Confidence.moderate : Confidence.solid));

/// Sample-size grade for plate appearances / at-bats.
Confidence paConfidence(int n) => n < 2
    ? Confidence.insufficient
    : (n < 5 ? Confidence.low : (n < 12 ? Confidence.moderate : Confidence.solid));

double? _pct(int a, int b) => b > 0 ? (a / b * 1000).round() / 10 : null;
double? _rate3(int a, int b) => b > 0 ? (a / b * 1000).round() / 1000 : null;

String fmtRate3(double v) {
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : s;
}

// ─── Counts / buckets ─────────────────────────────────────────

/// Exclusive count buckets (two strikes wins over everything else).
String countBucket(int balls, int strikes) {
  if (strikes >= 2) return 'two';
  if (balls == 0 && strikes == 0) return 'first';
  if (strikes > balls) return 'ahead';
  if (balls > strikes) return 'behind';
  return 'even';
}

const List<String> bucketOrder = ['first', 'ahead', 'even', 'behind', 'two'];

const Map<String, String> bucketLabels = {
  'first': 'First pitch (0-0)',
  'ahead': 'Pitcher ahead (0-1)',
  'even': 'Even (1-1)',
  'behind': "Hitter's counts (1-0, 2-0, 2-1, 3-0, 3-1)",
  'two': 'Two strikes',
};

String outcomeLabel(String? o) => switch (o) {
      '1b' => 'Single',
      '2b' => 'Double',
      '3b' => 'Triple',
      'hr' => 'Home run',
      'go' => 'Groundout',
      'fo' => 'Flyout',
      'lo' => 'Lineout',
      'dp' => 'Double play',
      'e' => 'Error',
      'fc' => "Fielder's choice",
      'bb' => 'Walk',
      'hbp' => 'Hit by pitch',
      'k' => 'Strikeout (swinging)',
      'kl' => 'Strikeout (looking)',
      'dk' => 'Dead ball',
      null => 'No result recorded',
      _ => (o ?? '').toUpperCase(),
    };

String callLabel(String? c) => switch (c) {
      'b' => 'Ball',
      'ss' => 'Swinging strike',
      'sl' => 'Called strike',
      'f' => 'Foul',
      'ip' => 'In play',
      'hbp' => 'Hit by pitch',
      null => '—',
      _ => (c ?? '').toUpperCase(),
    };

// ─── Plate appearances ────────────────────────────────────────

/// One pitch with the count it was thrown in.
class PitchStep {
  final PitchEvent e;
  final int balls;
  final int strikes;
  const PitchStep(this.e, this.balls, this.strikes);

  String get count => '$balls-$strikes';
  String get bucket => countBucket(balls, strikes);
  String get type {
    final t = (e.pitchType ?? '').toLowerCase().trim();
    return t.isEmpty ? 'other' : t;
  }

  bool get isSwing => e.call == 'ss' || e.call == 'f' || e.call == 'ip';
  bool get isWhiff => e.call == 'ss';
  bool get isFoul => e.call == 'f';
  bool get isCalledStrike => e.call == 'sl';
  bool get isBall => e.call == 'b';
  bool get isStrike => isSwing || isCalledStrike;
}

/// One plate appearance: its pitches (in order, with counts) and, when it
/// finished, its result. The result belongs to the PA, never to every pitch.
class PaRecord {
  final int season;
  final int gameNumber;
  final int seq; // PitchEvent.batter — PA order within the game
  final int? jersey;
  final int order;
  final String hand;
  final int? inning;
  final List<PitchStep> steps;
  final PAResult? result;
  int outsBefore = -1; // -1 = not known
  int timesThrough = 1;

  PaRecord({
    required this.season,
    required this.gameNumber,
    required this.seq,
    required this.jersey,
    required this.order,
    required this.hand,
    required this.inning,
    required this.steps,
    required this.result,
  });

  bool get complete => result != null;
  String? get outcome => result?.event.outcome;
  bool get onBase => result != null && (result!.hit == 1 || result!.bb == 1 || result!.hbp == 1);
  bool get reachedTwoStrikes => steps.any((s) => s.strikes >= 2);

  /// Final pitch type (null if the PA has no result or ended on a dead ball).
  String? get finalType {
    final r = result;
    if (r == null || r.event.outcome == 'dk') return null;
    final t = (r.event.pitchType ?? '').toLowerCase().trim();
    return t.isEmpty ? 'other' : t;
  }

  /// 'ahead' / 'behind' / 'even' — same definition as
  /// [StatsService.countApproach]: ahead = reached 2 strikes before 2 balls,
  /// behind = reached 2 balls before 2 strikes (last one reached wins).
  String get category {
    int balls = 0, strikes = 0;
    String cat = 'even';
    for (final s in steps) {
      final c = s.e.call;
      if (c == 'b') {
        balls++;
      } else if ((c == 'ss' || c == 'sl' || c == 'f') && strikes < 2) {
        strikes++;
      }
      if (strikes >= 2 && balls < 2) cat = 'ahead';
      if (balls >= 2 && strikes < 2) cat = 'behind';
    }
    return cat;
  }
}

// ─── Aggregates ───────────────────────────────────────────────

/// Totals for a set of plate appearances (only PAs with a result count).
class SituationLine {
  final String label;
  final int pa, ab, h, bb, hbp, k, xbh;
  const SituationLine(this.label, this.pa, this.ab, this.h, this.bb, this.hbp, this.k, this.xbh);

  double? get avg => _rate3(h, ab);
  double? get obp => _rate3(h + bb + hbp, ab + bb + hbp);
  double? get kPct => _pct(k, pa);
  double? get bbPct => _pct(bb, pa);
  Confidence get confidence => paConfidence(pa);
}

SituationLine situationOf(String label, Iterable<PaRecord> pas) {
  int pa = 0, ab = 0, h = 0, bb = 0, hbp = 0, k = 0, xbh = 0;
  for (final p in pas) {
    final r = p.result;
    if (r == null) continue;
    pa++;
    ab += r.ab;
    h += r.hit;
    bb += r.bb;
    hbp += r.hbp;
    k += r.k;
    if (const {'2b', '3b', 'hr'}.contains(r.event.outcome)) xbh++;
  }
  return SituationLine(label, pa, ab, h, bb, hbp, k, xbh);
}

/// Pitch-level totals for one pitch type in some slice of pitches. The
/// at-bat columns (abEnded…) only count plate appearances whose FINAL pitch
/// was this type — earlier pitches in the same at-bat are never credited.
class PitchLine {
  final String type;
  final int n, swings, whiffs, called, strikes, balls, fouls;
  final int abEnded, hitsEnded, kEnded, xbhEnded, bipOuts, bipHits;
  const PitchLine({
    required this.type,
    required this.n,
    required this.swings,
    required this.whiffs,
    required this.called,
    required this.strikes,
    required this.balls,
    required this.fouls,
    required this.abEnded,
    required this.hitsEnded,
    required this.kEnded,
    required this.xbhEnded,
    required this.bipOuts,
    required this.bipHits,
  });

  double? get swingPct => _pct(swings, n);
  double? get whiffPct => _pct(whiffs, swings);
  double? get foulPct => _pct(fouls, swings);
  double? get calledPct => _pct(called, n);
  double? get strikePct => _pct(strikes, n);
  double? get avg => _rate3(hitsEnded, abEnded);
  Confidence get pitchConf => pitchConfidence(n);
  Confidence get swingConf => pitchConfidence(swings);
  Confidence get abConf => paConfidence(abEnded);
}

/// Lines for each pitch type in [steps]. [finalById] maps the event id of a
/// finished PA's last pitch to its result.
List<PitchLine> pitchLinesFor(List<PitchStep> steps, Map<String, PAResult> finalById) {
  final byType = groupBy(steps, (PitchStep s) => s.type);
  final lines = byType.entries.map((entry) {
    final list = entry.value;
    int abEnded = 0, hitsEnded = 0, kEnded = 0, xbhEnded = 0, bipOuts = 0, bipHits = 0;
    for (final s in list) {
      final r = finalById[s.e.id];
      if (r == null) continue;
      abEnded += r.ab;
      hitsEnded += r.hit;
      kEnded += r.k;
      if (const {'2b', '3b', 'hr'}.contains(r.event.outcome)) xbhEnded++;
      if (s.e.call == 'ip') {
        if (r.hit == 1) bipHits++;
        if (PitchEvent.ballInPlayOutOutcomes.contains(r.event.outcome)) bipOuts++;
      }
    }
    return PitchLine(
      type: entry.key,
      n: list.length,
      swings: list.where((s) => s.isSwing).length,
      whiffs: list.where((s) => s.isWhiff).length,
      called: list.where((s) => s.isCalledStrike).length,
      strikes: list.where((s) => s.isStrike).length,
      balls: list.where((s) => s.isBall).length,
      fouls: list.where((s) => s.isFoul).length,
      abEnded: abEnded,
      hitsEnded: hitsEnded,
      kEnded: kEnded,
      xbhEnded: xbhEnded,
      bipOuts: bipOuts,
      bipHits: bipHits,
    );
  }).toList()
    ..sort((a, b) => b.n.compareTo(a.n));
  return lines;
}

/// Pitch-level totals for one count bucket (all pitch types together).
class BucketLine {
  final String bucket;
  final int n, swings, whiffs, called, balls;
  const BucketLine(this.bucket, this.n, this.swings, this.whiffs, this.called, this.balls);

  String get label => bucketLabels[bucket] ?? bucket;
  double? get swingPct => _pct(swings, n);
  double? get whiffPct => _pct(whiffs, swings);
  int get takes => n - swings;
  Confidence get confidence => pitchConfidence(n);
}

List<BucketLine> bucketLinesFor(List<PitchStep> steps) => [
      for (final b in bucketOrder)
        () {
          final list = steps.where((s) => s.bucket == b).toList();
          return BucketLine(
            b,
            list.length,
            list.where((s) => s.isSwing).length,
            list.where((s) => s.isWhiff).length,
            list.where((s) => s.isCalledStrike).length,
            list.where((s) => s.isBall).length,
          );
        }()
    ];

// ─── Insights / takeaways ─────────────────────────────────────

enum InsightKind { fact, tendency, suggestion }

class Insight {
  final InsightKind kind;
  final String text;
  final Confidence? confidence;
  const Insight(this.kind, this.text, [this.confidence]);
}

/// A report-level takeaway with the evidence behind it.
class Takeaway {
  final bool concern; // true = potential concern, false = opportunity
  final String title;
  final String fact;
  final String tendency;
  final Confidence confidence;
  final String suggestion;
  final double score;
  final int? jersey;
  const Takeaway({
    required this.concern,
    required this.title,
    required this.fact,
    required this.tendency,
    required this.confidence,
    required this.suggestion,
    required this.score,
    this.jersey,
  });
}

// ─── Hitter report ────────────────────────────────────────────

class HitterReport {
  final int jersey;
  final String? hand; // null when not recorded or mixed
  final int? order; // null when the lineup spot is not recorded
  final List<PaRecord> pas;
  final int games;
  final SituationLine line; // completed PAs only
  final int incompletePas;
  final int pitches;
  final List<PitchLine> pitchLines;
  final List<BucketLine> bucketLines;
  final SituationLine reachedTwoStrikes; // PAs that reached two strikes
  final SituationLine reachedHitterCount; // PAs that reached a hitter's count
  final List<Insight> insights;
  final List<Takeaway> takeaways;

  HitterReport({
    required this.jersey,
    required this.hand,
    required this.order,
    required this.pas,
    required this.games,
    required this.line,
    required this.incompletePas,
    required this.pitches,
    required this.pitchLines,
    required this.bucketLines,
    required this.reachedTwoStrikes,
    required this.reachedHitterCount,
    required this.insights,
    required this.takeaways,
  });

  /// Same report with the lineup spot cleared (used when the batting order is
  /// not actually recorded, so a default spot is never shown as real data).
  HitterReport withoutOrder() => HitterReport(
        jersey: jersey,
        hand: hand,
        order: null,
        pas: pas,
        games: games,
        line: line,
        incompletePas: incompletePas,
        pitches: pitches,
        pitchLines: pitchLines,
        bucketLines: bucketLines,
        reachedTwoStrikes: reachedTwoStrikes,
        reachedHitterCount: reachedHitterCount,
        insights: insights,
        takeaways: takeaways,
      );

  /// Short approach line for the lineup list: the first suggestion, if any.
  String get approach {
    final s = insights.firstWhereOrNull((i) => i.kind == InsightKind.suggestion);
    return s?.text ?? 'Not enough data for a hitter-specific approach.';
  }

  bool get hasSupportedTendency => insights.any((i) =>
      i.kind == InsightKind.tendency && i.confidence != null && i.confidence != Confidence.insufficient);
}

class LineupSegment {
  final String label;
  final List<HitterReport> hitters;
  final SituationLine line;
  final String summary;
  const LineupSegment(this.label, this.hitters, this.line, this.summary);
}

class GameReview {
  final int season;
  final int gameNumber;
  final List<PaRecord> pas;
  final SituationLine line;
  const GameReview(this.season, this.gameNumber, this.pas, this.line);
}

class MatchupReview {
  final List<GameReview> games;
  final List<String> worked;
  final List<String> didNotWork;
  final List<SituationLine> timesThrough;
  final String timesThroughNote;
  const MatchupReview(this.games, this.worked, this.didNotWork, this.timesThrough, this.timesThroughNote);
}

class SituationalPlan {
  /// The app does not record base runners, so bases-empty / runners-on /
  /// RISP splits cannot be computed.
  final bool basesTracked;
  final SituationLine twoOuts;
  final int twoOutsKnownPas; // PAs whose out count could be determined
  final SituationLine pitcherAhead;
  final SituationLine even;
  final SituationLine pitcherBehind;
  final List<BucketLine> teamBuckets;
  final List<PitchLine> twoStrikeTypes; // pitch lines at two strikes
  final List<PitchLine> hitterCountTypes; // pitch lines in hitter's counts
  final List<HitterReport> hitterCountDamage; // hitters who got on base after reaching a hitter's count
  const SituationalPlan({
    required this.basesTracked,
    required this.twoOuts,
    required this.twoOutsKnownPas,
    required this.pitcherAhead,
    required this.even,
    required this.pitcherBehind,
    required this.teamBuckets,
    required this.twoStrikeTypes,
    required this.hitterCountTypes,
    required this.hitterCountDamage,
  });
}

// ─── The whole plan ───────────────────────────────────────────

class OpponentPlan {
  final List<PaRecord> pas;
  final List<HitterReport> hitters; // lineup order when known, else by PA
  final bool orderKnown;
  final List<LineupSegment> segments; // empty when the order is not known
  final int unknownHitterPas;
  final int incompletePas;
  final List<({int season, int gameNumber})> games;
  final SituationLine teamLine;
  final List<PitchLine> teamPitchLines;
  final List<BucketLine> teamBuckets;
  final PitchLine? teamOverall;
  final List<PitchLine> firstPitchTypes;
  final Map<String, List<PitchLine>> pitchLinesByBucket;
  final SituationalPlan situational;
  final MatchupReview review;
  final List<Takeaway> takeaways;

  OpponentPlan._({
    required this.pas,
    required this.hitters,
    required this.orderKnown,
    required this.segments,
    required this.unknownHitterPas,
    required this.incompletePas,
    required this.games,
    required this.teamLine,
    required this.teamPitchLines,
    required this.teamBuckets,
    required this.teamOverall,
    required this.firstPitchTypes,
    required this.pitchLinesByBucket,
    required this.situational,
    required this.review,
    required this.takeaways,
  });

  Set<int> get seasons => {for (final p in pas) p.season};

  /// Builds every plate appearance with counts, outs-before and
  /// times-through-the-order. Groups on season + game + game# + batter# + paId
  /// so two seasons that reuse a game number can never merge.
  static List<PaRecord> buildPas(List<PitchEvent> data) {
    final pitchRows = data.where((e) => e.eventType == 'pitch').toList();
    final groups = groupBy(
      pitchRows,
      (PitchEvent e) => '${e.season}|${e.game}|${e.gameNumber}|${e.batter}|${e.batterNumber}|${e.paId}',
    );

    // Out count by game: highest `outs` seen for each PA number.
    final byGame = groupBy(data, (PitchEvent e) => '${e.season}|${e.game}|${e.gameNumber}');
    final outsBySeq = <String, Map<int, int>>{};
    final outsKnown = <String, bool>{};
    byGame.forEach((gk, events) {
      final m = <int, int>{};
      for (final e in events) {
        m[e.batter] = math.max(m[e.batter] ?? 0, e.outs);
      }
      outsBySeq[gk] = m;
      // Unknown when the game has no out data at all, or values beyond 3.
      outsKnown[gk] = events.any((e) => e.outs > 0) && !events.any((e) => e.outs > 3);
    });

    final pas = <PaRecord>[];
    groups.forEach((key, rows) {
      rows.sort((a, b) => (a.pitchNum ?? 0).compareTo(b.pitchNum ?? 0));
      final live = rows.where((e) => e.call != 'dk').toList();
      final finals = rows.where((e) => e.isFinalPitchOfPA).toList();
      final result = finals.isEmpty ? null : PAResult(finals.last);
      if (live.isEmpty && result == null) return;

      final steps = <PitchStep>[];
      int balls = 0, strikes = 0;
      for (final e in live) {
        steps.add(PitchStep(e, balls, strikes));
        if (e.call == 'b') {
          balls++;
        } else if ((e.call == 'ss' || e.call == 'sl' || e.call == 'f') && strikes < 2) {
          strikes++;
        }
      }

      final first = rows.first;
      final gk = '${first.season}|${first.game}|${first.gameNumber}';
      int outsBefore = -1;
      if (outsKnown[gk] == true) {
        final m = outsBySeq[gk]!;
        int? prior;
        for (final s in m.keys) {
          if (s < first.batter && (prior == null || s > prior)) prior = s;
        }
        if (prior == null) {
          outsBefore = 0;
        } else {
          final o = m[prior]!;
          outsBefore = o >= 3 ? 0 : o;
        }
      }

      final pa = PaRecord(
        season: first.season,
        gameNumber: first.gameNumber,
        seq: first.batter,
        jersey: first.batterNumber,
        order: first.battingOrder,
        hand: first.hand,
        inning: first.inning,
        steps: steps,
        result: result,
      );
      pa.outsBefore = outsBefore;
      pas.add(pa);
    });

    pas.sort((a, b) {
      final s = a.season.compareTo(b.season);
      if (s != 0) return s;
      final g = a.gameNumber.compareTo(b.gameNumber);
      return g != 0 ? g : a.seq.compareTo(b.seq);
    });

    // Times through the order, per hitter per game.
    final perHitterGame = groupBy(
      pas.where((p) => p.jersey != null),
      (PaRecord p) => '${p.season}|${p.gameNumber}|${p.jersey}',
    );
    for (final list in perHitterGame.values) {
      list.sort((a, b) => a.seq.compareTo(b.seq));
      for (var i = 0; i < list.length; i++) {
        list[i].timesThrough = i + 1;
      }
    }
    return pas;
  }

  static Map<String, PAResult> _finalMap(Iterable<PaRecord> pas) => {
        for (final p in pas)
          if (p.result != null && p.result!.event.outcome != 'dk') p.result!.event.id: p.result!,
      };

  static List<PitchStep> _stepsOf(Iterable<PaRecord> pas) => [for (final p in pas) ...p.steps];

  /// [seqs] is the existing `StatsService.pitchSequencing` output; it is used
  /// only for the sequence takeaways.
  static OpponentPlan compute(List<PitchEvent> data, {List<Map<String, dynamic>> seqs = const []}) {
    final pas = buildPas(data);
    final finalById = _finalMap(pas);
    final allSteps = _stepsOf(pas);

    final games = <({int season, int gameNumber})>[];
    for (final p in pas) {
      if (!games.any((g) => g.season == p.season && g.gameNumber == p.gameNumber)) {
        games.add((season: p.season, gameNumber: p.gameNumber));
      }
    }

    // Hitters (keyed by jersey; the screen already filtered to one team).
    final byJersey = groupBy(pas.where((p) => p.jersey != null), (PaRecord p) => p.jersey!);
    var hitters = byJersey.entries.map((e) => _buildHitter(e.key, e.value)).toList();

    final distinctOrders = {for (final h in hitters) if (h.order != null) h.order!};
    final orderKnown = distinctOrders.length >= 2;
    if (orderKnown) {
      hitters.sort((a, b) {
        final o = (a.order ?? 99).compareTo(b.order ?? 99);
        return o != 0 ? o : b.line.pa.compareTo(a.line.pa);
      });
    } else {
      hitters = hitters.map((h) => h.withoutOrder()).toList()
        ..sort((a, b) => b.pas.length.compareTo(a.pas.length));
    }

    final segments = <LineupSegment>[];
    if (orderKnown) {
      for (final seg in const [
        ('Top of the order (1-3)', 1, 3),
        ('Middle of the order (4-6)', 4, 6),
        ('Bottom of the order (7-9)', 7, 9),
      ]) {
        final hs = hitters.where((h) => h.order != null && h.order! >= seg.$2 && h.order! <= seg.$3).toList();
        if (hs.isEmpty) continue;
        final line = situationOf(seg.$1, hs.expand((h) => h.pas));
        segments.add(LineupSegment(seg.$1, hs, line, _segmentSummary(line, hs)));
      }
    }

    final teamPitchLines = pitchLinesFor(allSteps, finalById);
    final byBucket = <String, List<PitchLine>>{
      for (final b in bucketOrder) b: pitchLinesFor(allSteps.where((s) => s.bucket == b).toList(), finalById),
    };
    final teamOverall = allSteps.isEmpty ? null : _mergeLines('all', teamPitchLines);

    final teamLine = situationOf('Team', pas);
    final situational = _buildSituational(pas, hitters, allSteps, finalById);
    final review = _buildReview(pas, hitters, teamPitchLines, teamLine);

    final takeaways = _buildTakeaways(hitters, teamPitchLines, pas, seqs);

    return OpponentPlan._(
      pas: pas,
      hitters: hitters,
      orderKnown: orderKnown,
      segments: segments,
      unknownHitterPas: pas.where((p) => p.jersey == null).length,
      incompletePas: pas.where((p) => !p.complete).length,
      games: games,
      teamLine: teamLine,
      teamPitchLines: teamPitchLines,
      teamBuckets: bucketLinesFor(allSteps),
      teamOverall: teamOverall,
      firstPitchTypes: byBucket['first'] ?? const [],
      pitchLinesByBucket: byBucket,
      situational: situational,
      review: review,
      takeaways: takeaways,
    );
  }

  static PitchLine _mergeLines(String type, List<PitchLine> lines) {
    int sum(int Function(PitchLine) f) => lines.fold<int>(0, (a, l) => a + f(l));
    return PitchLine(
      type: type,
      n: sum((l) => l.n),
      swings: sum((l) => l.swings),
      whiffs: sum((l) => l.whiffs),
      called: sum((l) => l.called),
      strikes: sum((l) => l.strikes),
      balls: sum((l) => l.balls),
      fouls: sum((l) => l.fouls),
      abEnded: sum((l) => l.abEnded),
      hitsEnded: sum((l) => l.hitsEnded),
      kEnded: sum((l) => l.kEnded),
      xbhEnded: sum((l) => l.xbhEnded),
      bipOuts: sum((l) => l.bipOuts),
      bipHits: sum((l) => l.bipHits),
    );
  }

  static String _segmentSummary(SituationLine line, List<HitterReport> hs) {
    if (line.pa == 0) return 'No completed plate appearances from these spots yet.';
    final top = hs.where((h) => h.line.pa >= 2 && h.line.obp != null).toList()
      ..sort((a, b) => b.line.obp!.compareTo(a.line.obp!));
    final b = StringBuffer(
        '${line.h}-for-${line.ab}, ${line.k} K, ${line.bb} BB in ${line.pa} PA across ${hs.length} hitter(s).');
    if (top.isNotEmpty && top.first.line.obp! > 0) {
      b.write(' Most on-base: #${top.first.jersey} (${fmtRate3(top.first.line.obp!)} OBP, ${top.first.line.pa} PA).');
    }
    return b.toString();
  }

  // ─── Hitter ────────────────────────────────────────────────

  static HitterReport _buildHitter(int jersey, List<PaRecord> pas) {
    pas.sort((a, b) {
      final g = a.gameNumber.compareTo(b.gameNumber);
      return g != 0 ? g : a.seq.compareTo(b.seq);
    });
    final finalById = _finalMap(pas);
    final steps = _stepsOf(pas);
    final line = situationOf('Hitter', pas);
    final incomplete = pas.where((p) => !p.complete).length;
    final games = {for (final p in pas) '${p.season}|${p.gameNumber}'}.length;

    final hands = pas.map((p) => p.hand).where((h) => h == 'L' || h == 'R').toSet();
    final hand = hands.length == 1 ? hands.first : null;
    final orderMode = pas.isEmpty
        ? null
        : (groupBy(pas, (PaRecord p) => p.order).entries.toList()
              ..sort((a, b) => b.value.length.compareTo(a.value.length)))
            .first
            .key;

    final pitchLines = pitchLinesFor(steps, finalById);
    final bucketLines = bucketLinesFor(steps);
    final two = situationOf('Reached two strikes', pas.where((p) => p.reachedTwoStrikes));
    final hitterCount = situationOf(
        "Reached a hitter's count", pas.where((p) => p.steps.any((s) => s.bucket == 'behind')));

    final insights = <Insight>[];
    final takeaways = <Takeaway>[];

    // Observed facts
    final fact = StringBuffer('${line.h}-for-${line.ab}, ${line.k} K, ${line.bb} BB');
    if (line.hbp > 0) fact.write(', ${line.hbp} HBP');
    if (line.xbh > 0) fact.write(', ${line.xbh} XBH');
    fact.write(' in ${line.pa} PA over $games game(s).');
    insights.add(Insight(InsightKind.fact, fact.toString(), paConfidence(line.pa)));
    if (incomplete > 0) {
      insights.add(Insight(InsightKind.fact,
          '$incomplete plate appearance(s) have no recorded result and are left out of AVG/OBP.'));
    }

    // Supported tendencies (each needs a minimum sample and a clear gap)
    bool anyTendency = false;
    for (final l in pitchLines) {
      final t = l.type.toUpperCase();
      if (l.swings >= 5 && (l.whiffPct ?? 0) >= 40) {
        anyTendency = true;
        final c = pitchConfidence(l.swings);
        insights.add(Insight(InsightKind.tendency,
            'Swung and missed on ${l.whiffs} of ${l.swings} swings against $t.', c));
        insights.add(Insight(InsightKind.suggestion,
            'Consider $t when you want a swing-and-miss, and vary how it is set up so it does not become predictable.', c));
        takeaways.add(Takeaway(
          concern: false,
          title: '#$jersey swings through $t',
          fact: '${l.whiffs} swinging strikes on ${l.swings} swings against $t (${l.whiffPct}% whiff).',
          tendency: c == Confidence.low
              ? 'Small sample — an early signal, not an established weakness.'
              : 'Repeated across a meaningful number of swings.',
          confidence: c,
          suggestion: 'Consider $t in counts where you want a miss, and keep mixing it.',
          score: l.swings * 1.5 + (l.whiffPct ?? 0) / 10,
          jersey: jersey,
        ));
      }
      if (l.abEnded >= 3 && l.hitsEnded >= 2 && (l.avg ?? 0) >= 0.400) {
        anyTendency = true;
        final c = paConfidence(l.abEnded);
        insights.add(Insight(InsightKind.tendency,
            'At-bats that ended on $t produced ${l.hitsEnded} hits in ${l.abEnded} at-bats (final pitch only; earlier pitches are not credited).',
            c));
        insights.add(Insight(InsightKind.suggestion,
            'Consider a different finishing pitch, or a different way of using $t, and review the pitch history below first.', c));
      }
    }
    for (final b in bucketLines) {
      if (b.n >= 6 && b.swingPct != null) {
        if (b.swingPct! >= 75) {
          anyTendency = true;
          final c = pitchConfidence(b.n);
          insights.add(Insight(InsightKind.tendency,
              'Swung at ${b.swings} of ${b.n} pitches in ${b.label.toLowerCase()}.', c));
          insights.add(Insight(InsightKind.suggestion,
              'He has been aggressive in this count; consider using it to attack with a pitch you trust.', c));
        } else if (b.swingPct! <= 25) {
          anyTendency = true;
          final c = pitchConfidence(b.n);
          insights.add(Insight(InsightKind.tendency,
              'Took ${b.takes} of ${b.n} pitches in ${b.label.toLowerCase()}.', c));
          insights.add(Insight(InsightKind.suggestion,
              'He has been patient in this count; consider it as a chance to get a strike without a swing.', c));
        }
      }
    }
    if (two.pa >= 3 && two.k >= 2 && two.k / two.pa >= 0.5) {
      anyTendency = true;
      final c = paConfidence(two.pa);
      insights.add(Insight(InsightKind.tendency,
          'Struck out in ${two.k} of ${two.pa} plate appearances that reached two strikes.', c));
      insights.add(Insight(InsightKind.suggestion,
          'Consider going to your preferred put-away pitch once you are ahead.', c));
    }
    final twoOb = pas.where((p) => p.reachedTwoStrikes && p.onBase).length;
    if (two.pa >= 3 && twoOb >= 2 && twoOb / two.pa >= 0.5) {
      anyTendency = true;
      final c = paConfidence(two.pa);
      insights.add(Insight(InsightKind.tendency,
          'Reached base in $twoOb of ${two.pa} plate appearances that reached two strikes.', c));
      insights.add(Insight(InsightKind.suggestion,
          'Be careful finishing this hitter; avoid repeating the same put-away pattern.', c));
    }
    if (!anyTendency) {
      insights.add(const Insight(InsightKind.tendency,
          'No supported tendency yet — samples are too small.', Confidence.insufficient));
      insights.add(const Insight(InsightKind.suggestion,
          'Use the general game plan and revisit as more at-bats are logged.', Confidence.insufficient));
    }

    // Damage takeaway
    if (line.ab >= 3 && ((line.h >= 2 && (line.avg ?? 0) >= 0.400) || line.xbh >= 2)) {
      final c = paConfidence(line.ab);
      takeaways.add(Takeaway(
        concern: true,
        title: '#$jersey has hit you',
        fact: '${line.h}-for-${line.ab} with ${line.xbh} extra-base hit(s) in ${line.pa} PA.',
        tendency: c == Confidence.low
            ? 'Small sample — treat as an early signal.'
            : 'Repeated across a meaningful sample.',
        confidence: c,
        suggestion: 'Review his full pitch history below and consider a more varied approach.',
        score: 2.0 * line.ab + 3 * line.h + 2 * line.xbh,
        jersey: jersey,
      ));
    }

    return HitterReport(
      jersey: jersey,
      hand: hand,
      order: orderMode,
      pas: pas,
      games: games,
      line: line,
      incompletePas: incomplete,
      pitches: steps.length,
      pitchLines: pitchLines,
      bucketLines: bucketLines,
      reachedTwoStrikes: two,
      reachedHitterCount: hitterCount,
      insights: insights,
      takeaways: takeaways,
    );
  }

  // ─── Situational ───────────────────────────────────────────

  static SituationalPlan _buildSituational(
    List<PaRecord> pas,
    List<HitterReport> hitters,
    List<PitchStep> steps,
    Map<String, PAResult> finalById,
  ) {
    final known = pas.where((p) => p.outsBefore >= 0).toList();
    final two = situationOf('Two outs', known.where((p) => p.outsBefore == 2));
    final damage = hitters
        .where((h) => h.reachedHitterCount.pa >= 2)
        .where((h) => h.pas.where((p) => p.steps.any((s) => s.bucket == 'behind') && p.onBase).length >= 2)
        .toList();
    return SituationalPlan(
      basesTracked: false,
      twoOuts: two,
      twoOutsKnownPas: known.where((p) => p.complete).length,
      pitcherAhead: situationOf('Pitcher ahead', pas.where((p) => p.category == 'ahead')),
      even: situationOf('Even', pas.where((p) => p.category == 'even')),
      pitcherBehind: situationOf('Pitcher behind', pas.where((p) => p.category == 'behind')),
      teamBuckets: bucketLinesFor(steps),
      twoStrikeTypes: pitchLinesFor(steps.where((s) => s.bucket == 'two').toList(), finalById),
      hitterCountTypes: pitchLinesFor(steps.where((s) => s.bucket == 'behind').toList(), finalById),
      hitterCountDamage: damage,
    );
  }

  // ─── Matchup review ────────────────────────────────────────

  static MatchupReview _buildReview(
    List<PaRecord> pas,
    List<HitterReport> hitters,
    List<PitchLine> teamLines,
    SituationLine team,
  ) {
    final byGame = groupBy(pas, (PaRecord p) => '${p.season}|${p.gameNumber}');
    final games = byGame.values.map((list) {
      list.sort((a, b) => a.seq.compareTo(b.seq));
      return GameReview(list.first.season, list.first.gameNumber, list, situationOf('Game', list));
    }).toList()
      ..sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.gameNumber.compareTo(b.gameNumber);
      });

    final worked = <String>[];
    final didNot = <String>[];

    final whiffTypes = teamLines.where((l) => l.swings >= 8 && l.whiffPct != null).toList()
      ..sort((a, b) => b.whiffPct!.compareTo(a.whiffPct!));
    if (whiffTypes.isNotEmpty && whiffTypes.first.whiffPct! >= 25) {
      final l = whiffTypes.first;
      worked.add('${l.type.toUpperCase()}: ${l.whiffs} swings-and-misses on ${l.swings} swings (${l.whiffPct}%).');
    }
    final teamAvg = team.avg;
    final byAvg = teamLines.where((l) => l.abEnded >= 5 && l.avg != null).toList()
      ..sort((a, b) => a.avg!.compareTo(b.avg!));
    if (byAvg.isNotEmpty && teamAvg != null && byAvg.first.avg! < teamAvg) {
      final l = byAvg.first;
      worked.add(
          '${l.type.toUpperCase()}: ${l.hitsEnded}-for-${l.abEnded} on the at-bats it ended (team: ${fmtRate3(teamAvg)}).');
    }
    if (byAvg.length >= 2 && teamAvg != null && byAvg.last.avg! > teamAvg) {
      final l = byAvg.last;
      didNot.add(
          '${l.type.toUpperCase()}: ${l.hitsEnded}-for-${l.abEnded} on the at-bats it ended (team: ${fmtRate3(teamAvg)}).');
    }
    for (final l in teamLines.where((l) => l.xbhEnded >= 1)) {
      didNot.add(
          '${l.type.toUpperCase()} ended ${l.xbhEnded} extra-base hit(s) in ${l.abEnded} at-bats it ended.');
    }
    for (final h in hitters.where((h) => h.line.pa >= 2)) {
      if (h.line.hbp + h.line.bb + h.line.h == 0) {
        worked.add('#${h.jersey}: no hits, walks or hit-by-pitches in ${h.line.pa} PA (${h.line.k} K).');
      } else if ((h.line.obp ?? 0) >= 0.500) {
        didNot.add(
            '#${h.jersey}: reached base ${h.line.h + h.line.bb + h.line.hbp} times in ${h.line.pa} PA.');
      }
    }
    if (team.pa >= 8 && (team.bbPct ?? 0) >= 12) {
      didNot.add('${team.bb} walks in ${team.pa} PA (${team.bbPct}% BB).');
    }

    // Did hitters respond differently as the game went on?
    final tto = <SituationLine>[
      situationOf('1st PA of the game', pas.where((p) => p.jersey != null && p.timesThrough == 1)),
      situationOf('2nd PA', pas.where((p) => p.jersey != null && p.timesThrough == 2)),
      situationOf('3rd+ PA', pas.where((p) => p.jersey != null && p.timesThrough >= 3)),
    ];
    final later = situationOf('2nd+ PA', pas.where((p) => p.jersey != null && p.timesThrough >= 2));
    String note;
    if (tto[0].pa >= 8 && later.pa >= 8 && tto[0].obp != null && later.obp != null) {
      final diff = later.obp! - tto[0].obp!;
      if (diff.abs() >= 0.100) {
        note =
            'On-base rate was ${diff > 0 ? 'higher' : 'lower'} the 2nd+ time through (${fmtRate3(later.obp!)} vs ${fmtRate3(tto[0].obp!)}); ${later.pa} PA vs ${tto[0].pa} PA, so treat it as a suggestion only.';
      } else {
        note = 'No clear change between the 1st and later plate appearances.';
      }
    } else {
      note = 'Not enough plate appearances to say whether hitters adjusted as the game went on.';
    }

    return MatchupReview(games, worked, didNot, tto, note);
  }

  // ─── Takeaways ─────────────────────────────────────────────

  static List<Takeaway> _buildTakeaways(
    List<HitterReport> hitters,
    List<PitchLine> teamLines,
    List<PaRecord> pas,
    List<Map<String, dynamic>> seqs,
  ) {
    final cands = <Takeaway>[for (final h in hitters) ...h.takeaways];

    for (final l in teamLines) {
      final t = l.type.toUpperCase();
      if (l.swings >= 10 && (l.whiffPct ?? 0) >= 35) {
        cands.add(Takeaway(
          concern: false,
          title: 'The lineup swings through $t',
          fact: '${l.whiffs} swinging strikes on ${l.swings} swings (${l.whiffPct}% whiff) across the lineup.',
          tendency: 'Supported by ${l.swings} swings (${pitchConfidence(l.swings).label.toLowerCase()}).',
          confidence: pitchConfidence(l.swings),
          suggestion: 'Consider $t as a swing-and-miss option, mixed with your other pitches.',
          score: l.swings * 1.2,
        ));
      }
      if (l.abEnded >= 8 && (l.avg ?? 0) >= 0.300) {
        cands.add(Takeaway(
          concern: true,
          title: 'At-bats ended on $t have been hit',
          fact: '${l.hitsEnded}-for-${l.abEnded} on at-bats whose final pitch was $t (${l.xbhEnded} XBH).',
          tendency: 'Based on ${l.abEnded} at-bats (${paConfidence(l.abEnded).label.toLowerCase()}); final pitch only.',
          confidence: paConfidence(l.abEnded),
          suggestion: 'Review where in counts $t was thrown before leaning on it.',
          score: l.abEnded * 1.2 + l.hitsEnded,
        ));
      }
    }

    final two = situationOf('two', pas.where((p) => p.reachedTwoStrikes));
    if (two.pa >= 8 && two.k / two.pa >= 0.5) {
      cands.add(Takeaway(
        concern: false,
        title: 'Two-strike counts have finished at-bats',
        fact: '${two.k} strikeouts in ${two.pa} plate appearances that reached two strikes.',
        tendency: 'Supported by ${two.pa} plate appearances.',
        confidence: paConfidence(two.pa),
        suggestion: 'Consider protecting the lead in two-strike counts rather than changing the plan.',
        score: two.pa * 1.0,
      ));
    }

    for (final s in seqs) {
      final count = s['count'] as int? ?? 0;
      final outPct = (s['outPct'] as num?)?.toDouble();
      final seq = s['seq'] as String? ?? '';
      if (count < 3 || outPct == null || seq.isEmpty) continue;
      if (outPct >= 66) {
        cands.add(Takeaway(
          concern: false,
          title: 'A sequence worth considering again',
          fact: '$seq was used $count times and produced an out in ${outPct.round()}% of them.',
          tendency: 'Based on $count uses (${pitchConfidence(count).label.toLowerCase()}).',
          confidence: pitchConfidence(count),
          suggestion: 'Consider it again, but hitters may adjust if it is repeated.',
          score: count * 1.5,
        ));
      } else if (outPct <= 34) {
        cands.add(Takeaway(
          concern: true,
          title: 'A repeated sequence that has not worked',
          fact: '$seq was used $count times and produced an out in ${outPct.round()}% of them.',
          tendency: 'Based on $count uses (${pitchConfidence(count).label.toLowerCase()}).',
          confidence: pitchConfidence(count),
          suggestion: 'Consider a different sequence in that spot.',
          score: count * 1.5,
        ));
      }
    }

    cands.sort((a, b) => b.score.compareTo(a.score));
    final out = <Takeaway>[];
    final perJersey = <int, int>{};
    for (final c in cands) {
      if (out.length >= 5) break;
      if (c.jersey != null) {
        if ((perJersey[c.jersey!] ?? 0) >= 1) continue;
        perJersey[c.jersey!] = 1;
      }
      out.add(c);
    }
    return out;
  }
}
