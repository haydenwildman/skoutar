import '../models/pitch_event.dart';
import 'sequence_scoring.dart';

/// Opponent game-plan analysis for the Scouting Report. Everything here is
/// computed from the pitch rows SKOUTAR already stores for ONE opponent
/// (no velocity, movement or location, and no base-runner data — SKOUTAR does
/// not record runners, so runner-based situations are reported as unavailable
/// rather than guessed).
///
/// Every statement carries one of three labels, never blended:
///   * OBSERVED FACT   - counted directly from recorded events.
///   * SUPPORTED TENDENCY - a pattern with a sample at/above the "good" size.
///   * SUGGESTED APPROACH - an idea derived from the above, never a promise.
/// A result is only attributed to a pitch type when that pitch ENDED the
/// plate appearance (the final pitch); earlier pitches in an at-bat are never
/// credited with the result.

// ─────────────────────────── confidence ───────────────────────────

enum Conf { insufficient, low, moderate, good }

String confLabel(Conf c) => switch (c) {
      Conf.insufficient => 'Insufficient data',
      Conf.low => 'Low confidence',
      Conf.moderate => 'Moderate confidence',
      Conf.good => 'Good sample',
    };

/// Minimum / "good" sample sizes per kind of statistic. Below `min` nothing
/// is claimed; between `min` and `good` only a labelled, low-confidence fact.
class GpConfig {
  static const int minAb = 3, goodAb = 8;
  static const int minSwings = 4, goodSwings = 10;
  static const int minPitches = 5, goodPitches = 12;
  static const int minPa = 4, goodPa = 12; // team-level rates
  static const int minSeq = 2;

  static const double hitterHotAvg = 0.350;
  static const double typeHighBaa = 0.350;
  static const double whiffHigh = 0.35; // fraction of swings
  static const double calledHigh = 0.30; // fraction of pitches
  static const double walkHigh = 12; // BB% (team)
  static const double kHigh = 25; // K% (team)
  static const double sitMostly = 0.60; // share of a hitter's pitches

  // Count buckets (same count-value idea as the sequencing score).
  static const double aheadMin = 0.64; // 0-1, 0-2, 1-2
  static const double behindMax = 0.30; // 2-0, 3-0, 3-1
  static const int timesThroughMin = 8; // PAs per group to compare
}

Conf confFor(int n, int min, int good) {
  if (n < min) return Conf.insufficient;
  if (n < good) return Conf.low;
  if (n < good * 2) return Conf.moderate;
  return Conf.good;
}

double _confFactor(Conf c) => switch (c) {
      Conf.good => 1.0,
      Conf.moderate => 0.85,
      Conf.low => 0.6,
      Conf.insufficient => 0.0,
    };

// ─────────────────────────── data classes ───────────────────────────

/// One pitch type's results for a hitter (or for the whole team).
class PitchTypeLine {
  final String type;
  int pitches = 0, swings = 0, whiffs = 0, called = 0, fouls = 0, strikes = 0;
  int bip = 0, bipHits = 0, bipOuts = 0; // balls in play (pitch-level)
  // Plate appearances that this pitch type ENDED (final pitch of the PA):
  int ab = 0, hits = 0, xbh = 0, ks = 0, bb = 0;

  PitchTypeLine(this.type);

  double? get swingPct => pitches > 0 ? swings / pitches : null;
  double? get whiffPct => swings > 0 ? whiffs / swings : null;
  double? get calledPct => pitches > 0 ? called / pitches : null;
  double? get strikePct => pitches > 0 ? strikes / pitches : null;
  double? get baa => ab > 0 ? hits / ab : null;
}

/// Swing/take behaviour and results in one kind of count.
class CountBucketLine {
  final String key; // first | ahead | even | behind | two
  final String label;
  final String detail;
  int pitches = 0, swings = 0, whiffs = 0, called = 0;
  int paEnded = 0, ab = 0, hits = 0, ks = 0, bb = 0; // PAs that ENDED here

  CountBucketLine(this.key, this.label, this.detail);

  double? get swingPct => pitches > 0 ? swings / pitches : null;
  double? get whiffPct => swings > 0 ? whiffs / swings : null;
  double? get calledPct => pitches > 0 ? called / pitches : null;
  double? get baa => ab > 0 ? hits / ab : null;
}

class GpPitchLine {
  final String count; // e.g. "1-2" (count BEFORE the pitch)
  final String type;
  final String call; // b ss sl f ip hbp
  const GpPitchLine(this.count, this.type, this.call);
}

/// One plate appearance in chronological order.
class AtBatLine {
  final int gameNumber;
  final int season;
  final int? inning;
  final int? jersey;
  final int outsBefore;
  final bool leadoff;
  final List<GpPitchLine> pitches;
  final String? outcome; // final plate-appearance result (null = unfinished)
  final double? seqScore; // Pitch Sequencing score, if scoreable
  final int order; // chronological index in this report's data
  const AtBatLine({
    required this.gameNumber,
    required this.season,
    required this.inning,
    required this.jersey,
    required this.outsBefore,
    required this.leadoff,
    required this.pitches,
    required this.outcome,
    required this.seqScore,
    required this.order,
  });
}

/// A labelled statement: [tag] says whether it is a fact, a tendency or a
/// suggestion; [label] is the card heading (Strength, Potential weakness...).
class GpNote {
  final String label; // Strength | Potential weakness | Suggested approach | Watch for | Observed
  final String tag; // Observed fact | Supported tendency | Suggested approach
  final String text;
  final Conf conf;
  const GpNote(this.label, this.tag, this.text, this.conf);
}

class HitterReport {
  final int jersey;
  final String? hand; // 'L' | 'R' | 'Both recorded'
  final int? battingOrder;
  int pa = 0, ab = 0, hits = 0, bb = 0, hbp = 0, ks = 0, xbh = 0, hr = 0, tb = 0;
  int games = 0;
  final List<PitchTypeLine> byType = [];
  final List<CountBucketLine> byCount = [];
  final List<AtBatLine> atBats = []; // chronological
  final List<GpNote> notes = [];

  HitterReport(this.jersey, this.hand, this.battingOrder);

  double? get avg => ab > 0 ? hits / ab : null;
  double? get obp {
    final d = ab + bb + hbp;
    return d > 0 ? (hits + bb + hbp) / d : null;
  }

  double? get slg => ab > 0 ? tb / ab : null;
  int get totalPitches => byType.fold(0, (a, b) => a + b.pitches);
}

class SituationLine {
  final String label;
  final String? note; // why unavailable / extra caveat
  final bool available;
  int pa = 0, ab = 0, hits = 0, bb = 0, hbp = 0, ks = 0, xbh = 0;
  SituationLine(this.label, {this.note, this.available = true});

  double? get avg => ab > 0 ? hits / ab : null;
  double? get obp {
    final d = ab + bb + hbp;
    return d > 0 ? (hits + bb + hbp) / d : null;
  }

  double? get kPct => pa > 0 ? ks / pa * 100 : null;
}

class LineupGroup {
  final String label; // Top / Middle / Bottom
  final String slots; // "1-3"
  final List<HitterReport> hitters;
  final int pa, ab, hits, bb, hbp, ks;
  final String summary;
  final Conf conf;
  const LineupGroup(this.label, this.slots, this.hitters, this.pa, this.ab, this.hits, this.bb, this.hbp,
      this.ks, this.summary, this.conf);
  double? get avg => ab > 0 ? hits / ab : null;
  double? get obp {
    final d = ab + bb + hbp;
    return d > 0 ? (hits + bb + hbp) / d : null;
  }
}

class Takeaway {
  final String kind; // concern | strength | pattern
  final String headline;
  final String fact; // observed fact
  final String? tendency; // supported tendency (only when sample is good)
  final String suggestion;
  final Conf conf;
  final String sample;
  final double priority;
  const Takeaway({
    required this.kind,
    required this.headline,
    required this.fact,
    required this.tendency,
    required this.suggestion,
    required this.conf,
    required this.sample,
    required this.priority,
  });
}

class GameLine {
  final int gameNumber;
  final int season;
  final int pa, ab, hits, bb, ks;
  final double er;
  const GameLine(this.gameNumber, this.season, this.pa, this.ab, this.hits, this.bb, this.ks, this.er);
}

class ScoutingGamePlan {
  final String team;
  final List<GameLine> games;
  final int unknownJerseyPa; // completed PAs with no jersey recorded
  final int incompletePa;
  final List<PitchTypeLine> teamTypes;
  final List<CountBucketLine> teamCounts;
  final List<HitterReport> hitters; // lineup order when known, else by PA
  final bool lineupOrderKnown;
  final List<LineupGroup> lineupGroups;
  final List<SituationLine> situations;
  final List<SituationLine> timesThrough;
  final List<AtBatLine> atBats; // chronological
  final List<Takeaway> takeaways;
  final List<Map<String, dynamic>> struggled; // hitters the pitcher handled
  final List<Map<String, dynamic>> dangerous;
  final List<Map<String, dynamic>> patterns; // repeated ineffective patterns
  final List<Map<String, dynamic>> hitterCountLeaders; // who hurts you when behind
  final List<Map<String, dynamic>> recoveryPitches; // strike-getters when behind
  final int totalPa;

  const ScoutingGamePlan({
    required this.team,
    required this.games,
    required this.unknownJerseyPa,
    required this.incompletePa,
    required this.teamTypes,
    required this.teamCounts,
    required this.hitters,
    required this.lineupOrderKnown,
    required this.lineupGroups,
    required this.situations,
    required this.timesThrough,
    required this.atBats,
    required this.takeaways,
    required this.struggled,
    required this.dangerous,
    required this.patterns,
    required this.hitterCountLeaders,
    required this.recoveryPitches,
    required this.totalPa,
  });
}

// ─────────────────────────── helpers ───────────────────────────

String fmtAvg3(double? v) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : s;
}

String pctText(double? v) => v == null ? '—' : '${(v * 100).round()}%';

String upperType(String t) => t.toUpperCase();

String outcomeName(String? o) => switch (o) {
      '1b' => 'Single',
      '2b' => 'Double',
      '3b' => 'Triple',
      'hr' => 'Home run',
      'go' => 'Groundout',
      'fo' => 'Flyout',
      'lo' => 'Lineout',
      'dp' => 'Double play',
      'fc' => "Fielder's choice",
      'e' => 'Reached on error',
      'bb' => 'Walk',
      'hbp' => 'Hit by pitch',
      'k' => 'Strikeout (swinging)',
      'kl' => 'Strikeout (looking)',
      'dk3' => 'Strikeout (dropped third strike)',
      null => 'In progress',
      _ => o.toUpperCase(),
    };

String callName(String c) => switch (c) {
      'b' => 'Ball',
      'ss' => 'Swinging strike',
      'sl' => 'Called strike',
      'f' => 'Foul',
      'ip' => 'In play',
      'hbp' => 'Hit by pitch',
      _ => c,
    };

String _typeKey(PitchEvent e) {
  final t = (e.pitchType ?? '').toLowerCase().trim();
  return t.isEmpty ? 'other' : t;
}

bool _isSwing(String? c) => c == 'ss' || c == 'f' || c == 'ip';
bool _isStrike(String? c) => c == 'ss' || c == 'sl' || c == 'f' || c == 'ip';

PitchTypeLine _line(Map<String, PitchTypeLine> m, String t) => m.putIfAbsent(t, () => PitchTypeLine(t));

List<CountBucketLine> _newBuckets() => [
      CountBucketLine('first', 'First pitch (0-0)', '0-0'),
      CountBucketLine('ahead', 'Pitcher ahead', '0-1, 0-2, 1-2'),
      CountBucketLine('even', 'Even counts', '1-0, 1-1, 2-1, 2-2, 3-2'),
      CountBucketLine('behind', "Hitter's counts", '2-0, 3-0, 3-1'),
      CountBucketLine('two', 'Two strikes', '0-2, 1-2, 2-2, 3-2 (overlaps the rows above)'),
    ];

/// Which exclusive bucket a count belongs to ('first' is its own bucket).
String _bucketKeyFor(int b, int s) {
  if (b == 0 && s == 0) return 'first';
  final v = SequenceScoring.countValue(b, s);
  if (v >= GpConfig.aheadMin) return 'ahead';
  if (v <= GpConfig.behindMax) return 'behind';
  return 'even';
}

CountBucketLine _bucket(List<CountBucketLine> l, String k) => l.firstWhere((x) => x.key == k);

// ─────────────────────────── builder ───────────────────────────

class ScoutingGamePlanBuilder {
  ScoutingGamePlanBuilder._();

  /// [data]: this opponent's rows (already season/team/game filtered).
  /// [history]: the full (season-filtered) pitch list, used only so the
  /// Pitch Sequencing scores see earlier games; defaults to [data].
  /// [bestSeqs]/[avoidSeqs]: opening-sequence lists already computed by the
  /// report (reused, not recomputed).
  static ScoutingGamePlan build(
    String team,
    List<PitchEvent> data, {
    List<PitchEvent>? history,
    List<Map<String, dynamic>> bestSeqs = const [],
    List<Map<String, dynamic>> avoidSeqs = const [],
  }) {
    final shownIds = {for (final e in data) e.id};
    final scored = SequenceScoring.scoreAll(history ?? data)
        .where((s) => shownIds.contains(s.pitches.first.id))
        .toList();
    final scoreByKey = {for (final s in scored) s.key: s};

    // Position of every event within its game (for outs-before / leadoff).
    final perGame = <String, List<PitchEvent>>{};
    for (final e in data) {
      perGame.putIfAbsent('${e.game}|${e.gameNumber}|${e.season}', () => []).add(e);
    }
    final posInGame = <String, int>{};
    perGame.forEach((_, list) {
      for (var i = 0; i < list.length; i++) {
        posInGame[list[i].id] = i;
      }
    });

    final pas = SequenceScoring.splitPlateAppearances(data);
    final atBats = <AtBatLine>[];
    final seenInnings = <String>{};
    final gameAgg = <String, List<int>>{}; // 'g|season' -> [pa, ab, h, bb, k]
    final gameEr = <String, double>{};
    var incomplete = 0, unknownJersey = 0;

    // per-hitter accumulators
    final hit = <int, HitterReport>{};
    final hitTypes = <int, Map<String, PitchTypeLine>>{};
    final hitCounts = <int, List<CountBucketLine>>{};
    final hitGames = <int, Set<String>>{};
    final teamTypes = <String, PitchTypeLine>{};
    final teamCounts = _newBuckets();

    // lookups for hand / order modes
    final handVotes = <int, Set<String>>{};
    final orderVotes = <int, Map<int, int>>{};
    for (final e in data) {
      final j = e.batterNumber;
      if (j == null || e.eventType != 'pitch') continue;
      if (e.hand.isNotEmpty) handVotes.putIfAbsent(j, () => {}).add(e.hand);
      if (e.battingOrder > 0) {
        final m = orderVotes.putIfAbsent(j, () => {});
        m[e.battingOrder] = (m[e.battingOrder] ?? 0) + 1;
      }
    }
    String? handFor(int j) {
      final v = handVotes[j];
      if (v == null || v.isEmpty) return null;
      return v.length == 1 ? v.first : 'Both recorded';
    }

    int? orderFor(int j) {
      final m = orderVotes[j];
      if (m == null || m.isEmpty) return null;
      var best = -1, bestN = -1;
      m.forEach((k, n) {
        if (n > bestN || (n == bestN && k < best)) {
          best = k;
          bestN = n;
        }
      });
      return best;
    }

    // situations
    final sitLeadoff = SituationLine('Leadoff batters (bases empty)',
        note: 'First batter of an inning: bases are guaranteed empty.');
    final sitTwoOuts = SituationLine('Two outs');
    final sitFewerOuts = SituationLine('Zero or one out');
    final sitRunners = SituationLine('Runners on base',
        available: false, note: 'SKOUTAR does not record base runners, so this cannot be measured.');
    final sitRisp = SituationLine('Runners in scoring position',
        available: false, note: 'SKOUTAR does not record base runners, so this cannot be measured.');
    final sitBasesEmpty = SituationLine('Bases empty (all PAs)',
        available: false,
        note: 'Only leadoff batters are known to have come up with bases empty; see the leadoff row.');

    // times through the order (team-level)
    final first = SituationLine('First time facing a hitter in a game');
    final later = SituationLine('Second time or later');
    final seenBatter = <String, int>{};

    void addSit(SituationLine s, PitchEvent last) {
      s.pa++;
      s.ab += last.ab;
      final o = last.outcome;
      if (PitchEvent.hitOutcomes.contains(o)) s.hits++;
      if (o == 'bb') s.bb++;
      if (o == 'hbp') s.hbp++;
      if (PitchEvent.kOutcomes.contains(o)) s.ks++;
      if (o == '2b' || o == '3b' || o == 'hr') s.xbh++;
    }

    var order = 0;
    for (final pa in pas) {
      final firstEv = pa.first;
      final last = pa.last;
      final completed = (last.outcome ?? '').isNotEmpty;
      final jersey = pa.reversed.map((e) => e.batterNumber).firstWhere((j) => j != null, orElse: () => null);
      final gk = '${firstEv.game}|${firstEv.gameNumber}|${firstEv.season}';
      final cts = SequenceScoring.countsBefore(pa);

      // outs before this PA & leadoff detection
      var outsBefore = 0;
      final list = perGame[gk]!;
      final pos = posInGame[firstEv.id] ?? 0;
      if (pos > 0) {
        final prev = list[pos - 1];
        final sameInning = prev.inning == null || firstEv.inning == null || prev.inning == firstEv.inning;
        outsBefore = (sameInning && prev.outs < 3) ? prev.outs : 0;
      }
      var leadoff = false;
      if (firstEv.inning != null) {
        leadoff = seenInnings.add('$gk|${firstEv.inning}');
      }

      // pitch lines for this PA
      final pitchLines = <GpPitchLine>[
        for (var i = 0; i < pa.length; i++)
          GpPitchLine('${cts[i].$1}-${cts[i].$2}', _typeKey(pa[i]), pa[i].call ?? ''),
      ];
      final paKey = '${firstEv.game}|${firstEv.gameNumber}|${firstEv.season}|${firstEv.id}';
      atBats.add(AtBatLine(
        gameNumber: firstEv.gameNumber,
        season: firstEv.season,
        inning: firstEv.inning,
        jersey: jersey,
        outsBefore: outsBefore,
        leadoff: leadoff,
        pitches: pitchLines,
        outcome: completed ? last.outcome : null,
        seqScore: scoreByKey[paKey]?.score,
        order: order++,
      ));

      // pitch-level tallies (hitter, team, count buckets)
      HitterReport? hr;
      Map<String, PitchTypeLine>? ht;
      List<CountBucketLine>? hc;
      if (jersey != null) {
        hr = hit.putIfAbsent(jersey, () => HitterReport(jersey, handFor(jersey), orderFor(jersey)));
        ht = hitTypes.putIfAbsent(jersey, () => {});
        hc = hitCounts.putIfAbsent(jersey, _newBuckets);
        hitGames.putIfAbsent(jersey, () => {}).add(gk);
      }
      for (var i = 0; i < pa.length; i++) {
        final p = pa[i];
        final t = _typeKey(p);
        final (b, s) = cts[i];
        final tl = _line(teamTypes, t);
        final lines = <PitchTypeLine>[tl, if (ht != null) _line(ht, t)];
        final buckets = <CountBucketLine>[
          _bucket(teamCounts, _bucketKeyFor(b, s)),
          if (s == 2) _bucket(teamCounts, 'two'),
          if (hc != null) _bucket(hc, _bucketKeyFor(b, s)),
          if (hc != null && s == 2) _bucket(hc, 'two'),
        ];
        for (final l in lines) {
          l.pitches++;
          if (_isSwing(p.call)) l.swings++;
          if (p.call == 'ss') l.whiffs++;
          if (p.call == 'sl') l.called++;
          if (p.call == 'f') l.fouls++;
          if (_isStrike(p.call)) l.strikes++;
          if (p.call == 'ip') {
            l.bip++;
            if (PitchEvent.hitOutcomes.contains(p.outcome)) l.bipHits++;
            if (PitchEvent.ballInPlayOutOutcomes.contains(p.outcome)) l.bipOuts++;
          }
        }
        for (final bk in buckets) {
          bk.pitches++;
          if (_isSwing(p.call)) bk.swings++;
          if (p.call == 'ss') bk.whiffs++;
          if (p.call == 'sl') bk.called++;
        }
      }

      if (!completed) {
        incomplete++;
        continue;
      }

      // plate-appearance-level (completed only)
      final o = last.outcome;
      final lastType = _typeKey(last);
      final (lb, ls) = cts.last;
      final isHit = PitchEvent.hitOutcomes.contains(o);
      final isK = PitchEvent.kOutcomes.contains(o);
      final isXbh = o == '2b' || o == '3b' || o == 'hr';
      final endLines = <PitchTypeLine>[_line(teamTypes, lastType), if (ht != null) _line(ht, lastType)];
      for (final l in endLines) {
        l.ab += last.ab;
        if (isHit) l.hits++;
        if (isXbh) l.xbh++;
        if (isK) l.ks++;
        if (o == 'bb') l.bb++;
      }
      final endBuckets = <CountBucketLine>[
        _bucket(teamCounts, _bucketKeyFor(lb, ls)),
        if (ls == 2) _bucket(teamCounts, 'two'),
        if (hc != null) _bucket(hc, _bucketKeyFor(lb, ls)),
        if (hc != null && ls == 2) _bucket(hc, 'two'),
      ];
      for (final bk in endBuckets) {
        bk.paEnded++;
        bk.ab += last.ab;
        if (isHit) bk.hits++;
        if (isK) bk.ks++;
        if (o == 'bb') bk.bb++;
      }

      final ga = gameAgg.putIfAbsent('${firstEv.gameNumber}|${firstEv.season}', () => [0, 0, 0, 0, 0]);
      ga[0]++;
      ga[1] += last.ab;
      if (isHit) ga[2]++;
      if (o == 'bb') ga[3]++;
      if (isK) ga[4]++;

      if (hr == null) {
        unknownJersey++;
      } else {
        hr.pa++;
        hr.ab += last.ab;
        if (isHit) hr.hits++;
        if (o == 'bb') hr.bb++;
        if (o == 'hbp') hr.hbp++;
        if (isK) hr.ks++;
        if (isXbh) hr.xbh++;
        if (o == 'hr') hr.hr++;
        hr.tb += last.totalBases;
        hr.atBats.add(atBats.last);
      }

      if (leadoff) addSit(sitLeadoff, last);
      if (outsBefore == 2) {
        addSit(sitTwoOuts, last);
      } else {
        addSit(sitFewerOuts, last);
      }
      if (jersey != null) {
        final bk = '$gk|$jersey';
        final n = seenBatter[bk] ?? 0;
        addSit(n == 0 ? first : later, last);
        seenBatter[bk] = n + 1;
      }
    }

    // earned runs per game (event-level)
    for (final e in data) {
      gameEr['${e.gameNumber}|${e.season}'] = (gameEr['${e.gameNumber}|${e.season}'] ?? 0) + e.er;
    }
    final games = <GameLine>[
      for (final k in gameAgg.keys.toList()..sort((a, b) {
            final pa = a.split('|'), pb = b.split('|');
            final c = int.parse(pa[1]).compareTo(int.parse(pb[1]));
            return c != 0 ? c : int.parse(pa[0]).compareTo(int.parse(pb[0]));
          }))
        GameLine(int.parse(k.split('|')[0]), int.parse(k.split('|')[1]), gameAgg[k]![0], gameAgg[k]![1],
            gameAgg[k]![2], gameAgg[k]![3], gameAgg[k]![4], gameEr[k] ?? 0),
    ];

    // finish hitters
    final hitters = <HitterReport>[];
    hit.forEach((j, h) {
      final tl = hitTypes[j]!.values.toList()..sort((a, b) => b.pitches.compareTo(a.pitches));
      h.byType.addAll(tl);
      h.byCount.addAll(hitCounts[j]!);
      h.games = hitGames[j]!.length;
      _hitterNotes(h);
      hitters.add(h);
    });
    final orderKnown = hitters.isNotEmpty && hitters.every((h) => h.battingOrder != null);
    hitters.sort((a, b) {
      if (orderKnown) {
        final c = a.battingOrder!.compareTo(b.battingOrder!);
        if (c != 0) return c;
      }
      final c = b.pa.compareTo(a.pa);
      return c != 0 ? c : a.jersey.compareTo(b.jersey);
    });

    final teamTypeList = teamTypes.values.toList()..sort((a, b) => b.pitches.compareTo(a.pitches));
    final totalPa = games.fold<int>(0, (a, g) => a + g.pa) + 0;

    final groups = orderKnown ? _lineupGroups(hitters) : <LineupGroup>[];

    // who the pitcher handled / who hurt
    final withPa = hitters.where((h) => h.pa >= 2).toList();
    final dangerous = (List<HitterReport>.from(withPa)
          ..sort((a, b) => (b.obp ?? -1).compareTo(a.obp ?? -1)))
        .where((h) => (h.obp ?? 0) > 0 && (h.hits + h.bb + h.hbp) >= 1)
        .take(3)
        .map((h) => {'h': h})
        .toList();
    final struggled = (List<HitterReport>.from(withPa)
          ..sort((a, b) => (a.obp ?? 2).compareTo(b.obp ?? 2)))
        .where((h) => h.hits == 0 && (h.ks + (h.pa - h.ab - h.bb - h.hbp)) >= 1)
        .take(3)
        .map((h) => {'h': h})
        .toList();

    // repeated ineffective patterns (from sequencing notes, ≥2 PAs)
    final patternCounts = <String, Map<String, dynamic>>{};
    for (final s in scored) {
      final seen = <String>{};
      for (final n in s.notes) {
        if (n.polarity != SeqPolarity.review) continue;
        if (!const {
          'streak_ineffective',
          'usage_ineffective',
          'pattern_all',
          'pattern_batter',
          'repeat_after_misses',
          'same_after_fouls',
          'ball_run'
        }.contains(n.code)) {
          continue;
        }
        final m = patternCounts.putIfAbsent(n.code, () => {'text': n.text, 'n': 0, 'code': n.code});
        if (seen.add(n.code)) m['n'] = (m['n'] as int) + 1;
      }
    }
    final patterns = patternCounts.values.where((m) => (m['n'] as int) >= 2).toList()
      ..sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));

    // who hurts you in hitter's counts / what gets strikes when behind
    final hcl = <Map<String, dynamic>>[];
    for (final h in hitters) {
      final b = _bucket(h.byCount, 'behind');
      if (b.paEnded >= 2 && (b.hits + b.bb) >= 1) {
        hcl.add({'h': h, 'ended': b.paEnded, 'hits': b.hits, 'bb': b.bb});
      }
    }
    hcl.sort((a, b) => ((b['hits'] as int) + (b['bb'] as int)).compareTo((a['hits'] as int) + (a['bb'] as int)));

    // pitch types thrown in hitter's counts and how often they were strikes
    final recovery = <Map<String, dynamic>>[];
    final recMap = <String, List<int>>{}; // type -> [n, strikes]
    for (final ab in atBats) {
      for (final p in ab.pitches) {
        final parts = p.count.split('-');
        final b = int.parse(parts[0]), s = int.parse(parts[1]);
        if (_bucketKeyFor(b, s) != 'behind') continue;
        final r = recMap.putIfAbsent(p.type, () => [0, 0]);
        r[0]++;
        if (_isStrike(p.call)) r[1]++;
      }
    }
    recMap.forEach((t, r) {
      if (r[0] >= GpConfig.minPitches) {
        recovery.add({'type': t, 'n': r[0], 'strikes': r[1], 'pct': r[1] / r[0], 'conf': confFor(r[0], GpConfig.minPitches, GpConfig.goodPitches)});
      }
    });
    recovery.sort((a, b) => (b['pct'] as double).compareTo(a['pct'] as double));

    final takeaways = _takeaways(hitters, teamTypeList, games, totalPa, bestSeqs, avoidSeqs, patterns);

    return ScoutingGamePlan(
      team: team,
      games: games,
      unknownJerseyPa: unknownJersey,
      incompletePa: incomplete,
      teamTypes: teamTypeList,
      teamCounts: teamCounts,
      hitters: hitters,
      lineupOrderKnown: orderKnown,
      lineupGroups: groups,
      situations: [sitLeadoff, sitTwoOuts, sitFewerOuts, sitRunners, sitRisp, sitBasesEmpty],
      timesThrough: [first, later],
      atBats: atBats,
      takeaways: takeaways,
      struggled: struggled,
      dangerous: dangerous,
      patterns: patterns,
      hitterCountLeaders: hcl,
      recoveryPitches: recovery,
      totalPa: totalPa,
    );
  }

  // ───────────────────── hitter recommendations ─────────────────────

  static void _hitterNotes(HitterReport h) {
    final j = '#${h.jersey}';
    final totalPitches = h.totalPitches;

    // Observed overall line.
    if (h.pa > 0) {
      h.notes.add(GpNote(
        'Observed',
        'Observed fact',
        '${h.hits}-for-${h.ab}'
            '${h.xbh > 0 ? ' (${h.xbh} extra-base hit${h.xbh == 1 ? '' : 's'})' : ''}, '
            '${h.bb} BB, ${h.ks} K in ${h.pa} PA over ${h.games} game${h.games == 1 ? '' : 's'}.',
        confFor(h.pa, 2, 6),
      ));
    }

    PitchTypeLine? bestWhiff, worstBaa;
    for (final t in h.byType) {
      if (t.swings >= GpConfig.minSwings && (t.whiffPct ?? 0) >= GpConfig.whiffHigh) {
        if (bestWhiff == null || (t.whiffPct ?? 0) > (bestWhiff.whiffPct ?? 0)) bestWhiff = t;
      }
      if (t.ab >= GpConfig.minAb && t.hits >= 2 && (t.baa ?? 0) >= GpConfig.typeHighBaa) {
        if (worstBaa == null || (t.baa ?? 0) > (worstBaa.baa ?? 0)) worstBaa = t;
      }
    }

    if (worstBaa != null) {
      final c = confFor(worstBaa.ab, GpConfig.minAb, GpConfig.goodAb);
      final good = worstBaa.ab >= GpConfig.goodAb;
      h.notes.add(GpNote(
        'Strength',
        good ? 'Supported tendency' : 'Observed fact',
        '$j has ${worstBaa.hits} hit${worstBaa.hits == 1 ? '' : 's'} in ${worstBaa.ab} at-bats that ended on a '
            '${upperType(worstBaa.type)} (${fmtAvg3(worstBaa.baa)}). '
            '${good ? '' : 'Small sample - this is a fact about these at-bats, not yet a tendency. '}'
            'Credited only to the pitch that ended each at-bat.',
        c,
      ));
    }
    if (bestWhiff != null) {
      final c = confFor(bestWhiff.swings, GpConfig.minSwings, GpConfig.goodSwings);
      final good = bestWhiff.swings >= GpConfig.goodSwings;
      final whiffTwoStrike = _whiffsAtTwoStrikes(h, bestWhiff.type);
      h.notes.add(GpNote(
        'Potential weakness',
        good ? 'Supported tendency' : 'Observed fact',
        '$j swung and missed at ${bestWhiff.whiffs} of ${bestWhiff.swings} swings vs ${upperType(bestWhiff.type)} '
            '(${pctText(bestWhiff.whiffPct)}).'
            '${good ? '' : ' Small sample.'}',
        c,
      ));
      h.notes.add(GpNote(
        'Suggested approach',
        'Suggested approach',
        'Consider mixing in the ${upperType(bestWhiff.type)} in appropriate counts'
            '${whiffTwoStrike != null ? whiffTwoStrike : ''}'
            ' rather than relying only on other pitches. Not a guarantee - hitters adjust.',
        c,
      ));
    }

    // Called strikes (useful where a strike is needed).
    for (final t in h.byType) {
      if (t.pitches >= GpConfig.goodPitches && (t.calledPct ?? 0) >= GpConfig.calledHigh) {
        h.notes.add(GpNote(
          'Potential weakness',
          'Supported tendency',
          '$j took the ${upperType(t.type)} for a called strike ${t.called} of ${t.pitches} times '
              '(${pctText(t.calledPct)}). May be useful when a strike is needed.',
          confFor(t.pitches, GpConfig.minPitches, GpConfig.goodPitches),
        ));
        break;
      }
    }

    // 0-for-N: a fact, never a weakness by itself.
    for (final t in h.byType) {
      if (t.ab >= 2 && t.hits == 0 && t.type != (worstBaa?.type)) {
        final good = t.ab >= GpConfig.goodAb;
        h.notes.add(GpNote(
          'Observed',
          'Observed fact',
          '0-for-${t.ab} in at-bats that ended on a ${upperType(t.type)}.'
              '${good ? '' : ' Too small to call a weakness.'}',
          confFor(t.ab, GpConfig.minAb, GpConfig.goodAb),
        ));
        break;
      }
    }

    // Watch for: concentration of one pitch type.
    if (totalPitches >= 10 && h.byType.isNotEmpty) {
      final top = h.byType.first;
      final share = top.pitches / totalPitches;
      if (share >= GpConfig.sitMostly) {
        h.notes.add(GpNote(
          'Watch for',
          'Suggested approach',
          '$j has mostly seen the ${upperType(top.type)} (${top.pitches} of $totalPitches pitches). '
              'A hitter who sees one pitch repeatedly may adjust; consider a change of pace.',
          Conf.low,
        ));
      }
    }

    if (h.notes.length <= 1) {
      h.notes.add(GpNote(
        'Observed',
        'Observed fact',
        'Not enough history yet to identify strengths or weaknesses for $j - use the team plan.',
        Conf.insufficient,
      ));
    }
  }

  static String? _whiffsAtTwoStrikes(HitterReport h, String type) {
    var two = 0, all = 0;
    for (final ab in h.atBats) {
      for (final p in ab.pitches) {
        if (p.type != type || p.call != 'ss') continue;
        all++;
        if (p.count.endsWith('-2')) two++;
      }
    }
    if (all >= 2 && two * 2 >= all) return ' (especially with two strikes - $two of $all whiffs came there)';
    return null;
  }

  // ───────────────────── lineup groups ─────────────────────

  static List<LineupGroup> _lineupGroups(List<HitterReport> hitters) {
    LineupGroup mk(String label, String slots, int lo, int hi) {
      final hs = hitters.where((h) => h.battingOrder! >= lo && h.battingOrder! <= hi).toList();
      final pa = hs.fold<int>(0, (a, h) => a + h.pa);
      final ab = hs.fold<int>(0, (a, h) => a + h.ab);
      final hits = hs.fold<int>(0, (a, h) => a + h.hits);
      final bb = hs.fold<int>(0, (a, h) => a + h.bb);
      final hbp = hs.fold<int>(0, (a, h) => a + h.hbp);
      final ks = hs.fold<int>(0, (a, h) => a + h.ks);
      final c = confFor(pa, GpConfig.minPa, GpConfig.goodPa);
      String summary;
      if (hs.isEmpty) {
        summary = 'No hitters recorded in these lineup spots.';
      } else if (c == Conf.insufficient) {
        summary = 'Only $pa plate appearance${pa == 1 ? '' : 's'} so far - not enough to describe this part of the lineup.';
      } else {
        final names = (List<HitterReport>.from(hs)..sort((a, b) => (b.obp ?? -1).compareTo(a.obp ?? -1)))
            .where((h) => h.pa >= 2 && (h.obp ?? 0) > 0)
            .take(2)
            .map((h) => '#${h.jersey}')
            .toList();
        summary = '${hits}-for-$ab, $bb BB, $ks K in $pa PA'
            '${names.isNotEmpty ? '. Most on base: ${names.join(', ')}' : ''}.';
      }
      return LineupGroup(label, slots, hs, pa, ab, hits, bb, hbp, ks, summary, c);
    }

    return [mk('Top of the order', '1-3', 1, 3), mk('Middle of the order', '4-6', 4, 6), mk('Bottom of the order', '7-9', 7, 9)];
  }

  // ───────────────────── key takeaways ─────────────────────

  static List<Takeaway> _takeaways(
    List<HitterReport> hitters,
    List<PitchTypeLine> teamTypes,
    List<GameLine> games,
    int totalPa,
    List<Map<String, dynamic>> bestSeqs,
    List<Map<String, dynamic>> avoidSeqs,
    List<Map<String, dynamic>> patterns,
  ) {
    final out = <Takeaway>[];

    for (final h in hitters) {
      final j = '#${h.jersey}';
      if (h.ab >= GpConfig.minAb && h.hits >= 2 && (h.avg ?? 0) >= GpConfig.hitterHotAvg) {
        final c = confFor(h.ab, GpConfig.minAb, GpConfig.goodAb);
        // attribution: hits whose ending pitch was a given type
        PitchTypeLine? top;
        for (final t in h.byType) {
          if (t.hits >= 2 && (top == null || t.hits > top.hits)) top = t;
        }
        out.add(Takeaway(
          kind: 'concern',
          headline: '$j has hit you',
          fact: '$j went ${h.hits}-for-${h.ab}${h.xbh > 0 ? ' with ${h.xbh} extra-base hit${h.xbh == 1 ? '' : 's'}' : ''} '
              'over ${h.pa} PA.'
              '${top != null ? ' ${top.hits} of those hits came in at-bats that ended on a ${upperType(top.type)} (the ending pitch only).' : ''}',
          tendency: h.ab >= GpConfig.goodAb ? '$j has produced contact against you across a meaningful sample.' : null,
          suggestion: top != null
              ? 'Review $j\'s full pitch history and consider a more varied approach rather than leaning on the ${upperType(top.type)}.'
              : 'Review $j\'s full pitch history before settling on one approach.',
          conf: c,
          sample: 'At-Bats: ${h.ab}',
          priority: (60 + h.hits * 5 + h.xbh * 5) * _confFactor(c),
        ));
      }
      for (final t in h.byType) {
        if (t.swings >= GpConfig.minSwings && (t.whiffPct ?? 0) >= 0.40) {
          final c = confFor(t.swings, GpConfig.minSwings, GpConfig.goodSwings);
          out.add(Takeaway(
            kind: 'strength',
            headline: '$j swings through the ${upperType(t.type)}',
            fact: '$j swung and missed at ${t.whiffs} of ${t.swings} ${upperType(t.type)}s (${pctText(t.whiffPct)}).',
            tendency: t.swings >= GpConfig.goodSwings
                ? 'Repeated misses across ${t.swings} swings point to a real tendency.'
                : null,
            suggestion: 'Consider the ${upperType(t.type)} in appropriate counts, especially to finish at-bats.',
            conf: c,
            sample: 'Swings: ${t.swings}',
            priority: (45 + (t.whiffPct ?? 0) * 30) * _confFactor(c),
          ));
        }
        if (t.pitches >= GpConfig.goodPitches && (t.calledPct ?? 0) >= 0.35) {
          out.add(Takeaway(
            kind: 'strength',
            headline: '$j takes the ${upperType(t.type)} for strikes',
            fact: '$j let ${t.called} of ${t.pitches} ${upperType(t.type)}s go for a called strike (${pctText(t.calledPct)}).',
            tendency: 'A repeated take across ${t.pitches} pitches.',
            suggestion: 'May be a useful pitch to steal a strike when you need one.',
            conf: confFor(t.pitches, GpConfig.minPitches, GpConfig.goodPitches),
            sample: 'Pitches: ${t.pitches}',
            priority: 38 * _confFactor(confFor(t.pitches, GpConfig.minPitches, GpConfig.goodPitches)),
          ));
        }
      }
    }

    for (final t in teamTypes) {
      if (t.swings >= 10 && (t.whiffPct ?? 0) >= GpConfig.whiffHigh) {
        final c = confFor(t.swings, 10, 25);
        out.add(Takeaway(
          kind: 'strength',
          headline: 'This team struggles to make contact with the ${upperType(t.type)}',
          fact: 'The lineup swung and missed at ${t.whiffs} of ${t.swings} ${upperType(t.type)} swings (${pctText(t.whiffPct)}).',
          tendency: t.swings >= 25 ? 'Whiff rate has held up over a large number of swings.' : null,
          suggestion: 'The ${upperType(t.type)} has been a reliable swing-and-miss pitch against this team.',
          conf: c,
          sample: 'Swings: ${t.swings}',
          priority: (50 + (t.whiffPct ?? 0) * 30) * _confFactor(c),
        ));
      }
      if (t.ab >= 5 && (t.baa ?? 0) >= GpConfig.typeHighBaa) {
        final c = confFor(t.ab, 5, 12);
        out.add(Takeaway(
          kind: 'concern',
          headline: 'The ${upperType(t.type)} has been hit',
          fact: '${t.hits} hit${t.hits == 1 ? '' : 's'} in ${t.ab} at-bats that ended on a ${upperType(t.type)} (${fmtAvg3(t.baa)}).',
          tendency: t.ab >= 12 ? 'The pattern has held across a large sample.' : null,
          suggestion: 'Not a reason to abandon the pitch by itself - check counts and sequences, and vary how it is used.',
          conf: c,
          sample: 'At-Bats: ${t.ab}',
          priority: (48 + (t.baa ?? 0) * 25) * _confFactor(c),
        ));
      }
    }

    final totalPaTeam = games.fold<int>(0, (a, g) => a + g.pa);
    final totalBb = games.fold<int>(0, (a, g) => a + g.bb);
    final totalK = games.fold<int>(0, (a, g) => a + g.ks);
    if (totalPaTeam >= 10) {
      final c = confFor(totalPaTeam, GpConfig.minPa, 25);
      final bbPct = totalBb / totalPaTeam * 100;
      final kPct = totalK / totalPaTeam * 100;
      if (bbPct >= GpConfig.walkHigh) {
        out.add(Takeaway(
          kind: 'concern',
          headline: 'Walks have been an issue',
          fact: '$totalBb walks in $totalPaTeam PA (${bbPct.toStringAsFixed(0)}%).',
          tendency: totalPaTeam >= 25 ? 'The walk rate holds across a large number of plate appearances.' : null,
          suggestion: 'Prioritise first-pitch strikes and getting ahead.',
          conf: c,
          sample: 'Plate Appearances: $totalPaTeam',
          priority: 55 * _confFactor(c),
        ));
      }
      if (kPct >= GpConfig.kHigh) {
        out.add(Takeaway(
          kind: 'strength',
          headline: 'You have been striking this lineup out',
          fact: '$totalK strikeouts in $totalPaTeam PA (${kPct.toStringAsFixed(0)}%).',
          tendency: totalPaTeam >= 25 ? 'The strikeout rate holds across a meaningful sample.' : null,
          suggestion: 'Look at which pitches ended those strikeouts and lean on what has been working.',
          conf: c,
          sample: 'Plate Appearances: $totalPaTeam',
          priority: 44 * _confFactor(c),
        ));
      }
    }

    for (final s in bestSeqs) {
      final n = s['count'] as int;
      if (n >= GpConfig.minSeq && (s['score'] as double) >= 65) {
        final c = confFor(n, GpConfig.minSeq, 5);
        out.add(Takeaway(
          kind: 'pattern',
          headline: 'A sequence worth revisiting: ${_seqText(s['seq'])}',
          fact: 'The opening sequence ${_seqText(s['seq'])} appeared in $n at-bats with a Pitch Sequencing score of ${s['score']}.',
          tendency: n >= 5 ? 'It has scored well across several at-bats.' : null,
          suggestion: 'Consider it again where the situation fits - hitters may adjust if it is repeated every time.',
          conf: c,
          sample: 'At-Bats: $n',
          priority: 40 * _confFactor(c),
        ));
        break;
      }
    }
    for (final s in avoidSeqs) {
      final n = s['count'] as int;
      if (n >= GpConfig.minSeq && (s['score'] as double) <= 40) {
        final c = confFor(n, GpConfig.minSeq, 5);
        out.add(Takeaway(
          kind: 'pattern',
          headline: 'A sequence to reconsider: ${_seqText(s['seq'])}',
          fact: 'The opening sequence ${_seqText(s['seq'])} appeared in $n at-bats with a Pitch Sequencing score of ${s['score']}.',
          tendency: n >= 5 ? 'It has scored poorly across several at-bats.' : null,
          suggestion: 'Review those at-bats before using it again. A low score reflects count, matchup and setup, not just the result.',
          conf: c,
          sample: 'At-Bats: $n',
          priority: 42 * _confFactor(c),
        ));
        break;
      }
    }
    if (patterns.isNotEmpty) {
      final p = patterns.first;
      out.add(Takeaway(
        kind: 'pattern',
        headline: 'A repeated pattern has been working against you',
        fact: '${p['text']} (seen in ${p['n']} at-bats).',
        tendency: null,
        suggestion: 'Flagged for review - location and intended pitch are not tracked, so check whether it was a decision or an execution issue.',
        conf: Conf.low,
        sample: 'At-Bats: ${p['n']}',
        priority: 36 * _confFactor(Conf.low),
      ));
    }

    out.sort((a, b) => b.priority.compareTo(a.priority));
    // Avoid five takeaways about the same hitter or the same pitch.
    final picked = <Takeaway>[];
    final seenHeads = <String>{};
    final perSubject = <String, int>{};
    for (final t in out) {
      if (!seenHeads.add(t.headline)) continue;
      final subj = t.headline.split(' ').first;
      if ((perSubject[subj] ?? 0) >= 2) continue;
      perSubject[subj] = (perSubject[subj] ?? 0) + 1;
      picked.add(t);
      if (picked.length == 5) break;
    }
    return picked;
  }
}

/// Teko has no arrow glyph and an unbroken FB→CH→SL cannot wrap, so sequences
/// are shown with spaces around ">" (wraps between pitches, never mid-word).
String _seqText(Object? seq) => '$seq'.replaceAll('→', ' > ');
