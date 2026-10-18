import '../models/pitch_event.dart';
import 'stats_service.dart';

/// One completed (or in-progress) plate appearance's full pitch sequence,
/// against a specific Team + Jersey #. Built by [BatterHistoryService] —
/// never constructed by hand.
class AtBatSequence {
  final String opponent;
  final int gameNumber;
  final int season;
  final DateTime date; // timestamp of the last pitch in this at-bat
  final List<PitchEvent> pitches; // chronological, one per pitch thrown
  final List<(String, String)> counts; // (before, after) per pitch, aligned to `pitches`
  final String? finalOutcome; // e.g. 'k', 'bb', 'go' — null if still in progress
  final bool ballInPlay;

  const AtBatSequence({
    required this.opponent,
    required this.gameNumber,
    required this.season,
    required this.date,
    required this.pitches,
    required this.counts,
    required this.finalOutcome,
    required this.ballInPlay,
  });

  /// The single pitch that was put in play, if any — used to render this
  /// at-bat's spray-chart location.
  PitchEvent? get ballInPlayPitch {
    for (final p in pitches) {
      if (p.call == 'ip' && p.xCoord != null && p.yCoord != null) return p;
    }
    return null;
  }
}

/// One pitch type's results against ONE specific batter (Team + Jersey #).
/// Computed with the same [StatsService.pitchBreakdown] math the Pitch
/// Breakdown tab uses, but fed only this batter's pitches — never the
/// pitcher's overall or all-batters numbers. A rate with an empty
/// denominator is null so the UI shows "N/A" instead of a misleading 0%.
class BatterPitchTypeStats {
  final String pitchType;
  final int pitches;
  final double? usagePct;
  final double? whiffPct; // swinging misses / swings
  final double? baa; // hits / official at-bats ended on this pitch type
  final double? strikePct; // strikes / pitches

  const BatterPitchTypeStats({
    required this.pitchType,
    required this.pitches,
    required this.usagePct,
    required this.whiffPct,
    required this.baa,
    required this.strikePct,
  });
}

/// Aggregate tendencies against this specific Team + Jersey #, computed
/// only from this batter's pitches — never used to suggest what to
/// throw, purely informational (per the redesign spec).
class BatterTendencies {
  final int totalAtBats;
  final int totalPitches;
  final Map<String, int> pitchUsageCounts; // pitchType key -> count
  final String? mostFrequentPitch;
  final int strikeouts;
  final int walks;
  final int foulBalls;
  final int ballsInPlay;

  /// Per-pitch-type Whiff % / BAA / Strike % for this batter, most-used first.
  final List<BatterPitchTypeStats> byPitchType;

  const BatterTendencies({
    required this.totalAtBats,
    required this.totalPitches,
    required this.pitchUsageCounts,
    required this.mostFrequentPitch,
    required this.strikeouts,
    required this.walks,
    required this.foulBalls,
    required this.ballsInPlay,
    required this.byPitchType,
  });

  bool get hasData => totalAtBats > 0;

  /// Usage % for a given pitch type key, or null if there's no data for it.
  double? usagePct(String key) {
    if (totalPitches == 0) return null;
    final n = pitchUsageCounts[key];
    if (n == null || n == 0) return null;
    return n / totalPitches * 100;
  }
}

/// The batter's own recorded offensive line against this pitcher, built
/// only from the same completed plate appearances already grouped in
/// [BatterHistory.atBats] — the exact same at-bat-ending outcomes the rest
/// of the app already uses (see [PAResult] in stats_service.dart), just
/// totaled for one batter instead of every batter faced. Any rate with an
/// empty denominator is left null so the UI can show "N/A" instead of a
/// misleading 0%.
class BatterOffenseStats {
  final int pa;
  final int ab;
  final int hits;
  final int walks;
  final int hitByPitch;
  final int strikeouts;
  final int homeRuns;
  final int totalBases;
  final int ballsInPlay;

  const BatterOffenseStats({
    required this.pa,
    required this.ab,
    required this.hits,
    required this.walks,
    required this.hitByPitch,
    required this.strikeouts,
    required this.homeRuns,
    required this.totalBases,
    required this.ballsInPlay,
  });

  double? get avg => ab > 0 ? hits / ab : null;
  double? get obp {
    final denom = ab + walks + hitByPitch;
    return denom > 0 ? (hits + walks + hitByPitch) / denom : null;
  }

  double? get slg => ab > 0 ? totalBases / ab : null;
  double? get ops {
    final o = obp, s = slg;
    return (o != null && s != null) ? o + s : null;
  }

  double? get bbPct => pa > 0 ? walks / pa * 100 : null;
  double? get kPct => pa > 0 ? strikeouts / pa * 100 : null;
  double? get babip {
    final denom = ab - strikeouts - homeRuns;
    return denom > 0 ? (hits - homeRuns) / denom : null;
  }
}

/// Everything known about previous encounters with one specific
/// Team + Jersey # (never jersey # alone — see [BatterHistoryService.build]),
/// across every game ever logged, oldest games included.
class BatterHistory {
  final String opponent;
  final int jersey;
  final List<AtBatSequence> atBats; // newest first
  final List<PitchEvent> sprayPoints; // every ball in play, across all at-bats
  final BatterTendencies tendencies;
  final BatterOffenseStats offense;

  const BatterHistory({
    required this.opponent,
    required this.jersey,
    required this.atBats,
    required this.sprayPoints,
    required this.tendencies,
    required this.offense,
  });

  /// Every at-bat that has an outcome, newest first. An at-bat with no
  /// outcome yet is the one being thrown right now ([currentAtBat]) and
  /// never belongs in a history list.
  List<AtBatSequence> get completedAtBats =>
      [for (final ab in atBats) if (ab.finalOutcome != null) ab];

  /// The at-bat currently in progress against this batter, if any.
  AtBatSequence? get currentAtBat {
    for (final ab in atBats) {
      if (ab.finalOutcome == null) return ab;
    }
    return null;
  }

  bool get hasData => completedAtBats.isNotEmpty;

  /// Times this batter has been fully faced so far this game.
  int get timesFaced => completedAtBats.length;

  /// Which plate appearance of the game this is for him (1 = first).
  int get currentPlateAppearance => timesFaced + 1;

  /// Last Sequence: the most recently COMPLETED at-bat against this batter
  /// (never the current, in-progress one).
  AtBatSequence? get lastAtBat {
    final done = completedAtBats;
    return done.isEmpty ? null : done.first;
  }

  /// Previous Sequences: completed at-bats strictly older than
  /// [lastAtBat] — so nothing shown as Last Sequence (or as the current
  /// at-bat) is ever repeated here.
  List<AtBatSequence> get previousSequences {
    final done = completedAtBats;
    return done.length <= 1 ? const [] : done.sublist(1);
  }
}

class BatterHistoryService {
  /// Builds the history of ONE batter within ONE game: every plate
  /// appearance (PA) he has had so far, finished or in progress.
  ///
  /// Identity: a batter is the jersey # within the current game — the same
  /// [team] + [gameNumber] + [season] the live Game Input screen is logging
  /// to. Rows from any other game are never considered, so a batter's first
  /// PA of THIS game always starts with no history, and a different game
  /// against the same team can never leak in.
  ///
  /// How PAs are found (deliberately NOT via `paId`, which only advances
  /// once per lineup and so is the same on every PA after the first): the
  /// game's pitch rows are walked in logged order. A PA is a run of pitches
  /// that ends at the first pitch carrying an outcome (strikeout, walk,
  /// hit-by-pitch, ball in play ...); the next pitch starts a new PA. A
  /// change in the stored PA sequence number (`batter`) also starts a new
  /// PA, as a safety net. Each PA is then credited to the jersey # on its
  /// LAST pitch, so correcting a mistyped jersey # mid-at-bat doesn't split
  /// one PA across two batters.
  static BatterHistory build({
    required List<PitchEvent> allPitches,
    required String team,
    required int jersey,
    required int gameNumber,
    required int season,
  }) {
    // Only real pitches (not pickoffs/balks/etc.) count toward an at-bat
    // sequence. `allPitches` is already in chronological (append) order.
    final gamePitches = allPitches.where((p) =>
        p.eventType == 'pitch' &&
        p.game == team &&
        p.gameNumber == gameNumber &&
        p.season == season);

    // 1. Split the whole game into plate appearances (every batter).
    final allPAs = <List<PitchEvent>>[];
    List<PitchEvent>? open;
    int? openSeq;
    for (final p in gamePitches) {
      if (open == null || openSeq != p.batter) {
        open = <PitchEvent>[];
        allPAs.add(open);
        openSeq = p.batter;
      }
      open.add(p);
      if (p.isFinalPitchOfPA) {
        open = null; // PA finished — the next pitch is a new PA
        openSeq = null;
      }
    }

    // 2. Keep this batter's PAs (jersey on the PA's last tagged pitch).
    int? jerseyOf(List<PitchEvent> pa) {
      for (final p in pa.reversed) {
        if (p.batterNumber != null) return p.batterNumber;
      }
      return null;
    }

    final mine = [
      for (final pa in allPAs)
        if (jerseyOf(pa) == jersey) pa,
    ];
    final relevant = [for (final pa in mine) ...pa];

    final atBats = <AtBatSequence>[];
    for (final pitchesInPA in mine) {
      final counts = <(String, String)>[];
      int b = 0, s = 0;
      for (final p in pitchesInPA) {
        final before = '$b-$s';
        switch (p.call) {
          case 'b':
            b++;
            break;
          case 'ss':
          case 'sl':
            s++;
            break;
          case 'f':
            if (s < 2) s++;
            break;
        }
        counts.add((before, '$b-$s'));
      }
      final last = pitchesInPA.last;
      atBats.add(AtBatSequence(
        opponent: last.game,
        gameNumber: last.gameNumber,
        season: last.season,
        date: last.timestamp,
        pitches: pitchesInPA,
        counts: counts,
        finalOutcome: last.isFinalPitchOfPA ? last.outcome : null,
        ballInPlay: pitchesInPA.any((p) => p.call == 'ip'),
      ));
    }

    // Newest first = reverse logged order (more reliable than timestamps,
    // which can tie or be edited).
    final newestFirst = atBats.reversed.toList();

    final sprayPoints = <PitchEvent>[
      for (final ab in newestFirst)
        if (ab.ballInPlayPitch != null) ab.ballInPlayPitch!,
    ];

    final tendencies = _computeTendencies(newestFirst, relevant);
    final offense = _computeOffense(newestFirst);

    return BatterHistory(
      opponent: team,
      jersey: jersey,
      atBats: newestFirst,
      sprayPoints: sprayPoints,
      tendencies: tendencies,
      offense: offense,
    );
  }

  /// Totals the batter's own offensive line from the same completed
  /// at-bats (`finalOutcome != null`) already grouped by [build] — same
  /// outcome-to-stat mapping the rest of the app uses (bb/hbp don't count
  /// as an AB; 1b/2b/3b/hr count as hits; k/kl count as a strikeout).
  static BatterOffenseStats _computeOffense(List<AtBatSequence> atBats) {
    int pa = 0, ab = 0, hits = 0, walks = 0, hbp = 0, k = 0, hr = 0, tb = 0, bip = 0;
    for (final at in atBats) {
      final outcome = at.finalOutcome;
      if (outcome == null) continue; // still in progress — not a final PA yet
      pa++;
      if (outcome == 'bb') {
        walks++;
      } else if (outcome == 'hbp') {
        hbp++;
      } else {
        ab++;
        if (PitchEvent.hitOutcomes.contains(outcome)) hits++;
        if (outcome == 'hr') hr++;
        if (PitchEvent.kOutcomes.contains(outcome)) k++;
      }
      if (at.ballInPlay) bip++;
      final finalPitch = at.pitches.isNotEmpty ? at.pitches.last : null;
      if (finalPitch != null) tb += finalPitch.totalBases;
    }
    return BatterOffenseStats(
      pa: pa,
      ab: ab,
      hits: hits,
      walks: walks,
      hitByPitch: hbp,
      strikeouts: k,
      homeRuns: hr,
      totalBases: tb,
      ballsInPlay: bip,
    );
  }

  static BatterTendencies _computeTendencies(
      List<AtBatSequence> atBats, List<PitchEvent> relevant) {
    final usage = <String, int>{};
    int strikeouts = 0, walks = 0, fouls = 0, bip = 0;

    for (final p in relevant) {
      final pt = p.pitchType;
      if (pt != null) usage[pt] = (usage[pt] ?? 0) + 1;
      if (p.call == 'f') fouls++;
      if (p.call == 'ip') bip++;
    }

    for (final ab in atBats) {
      if (PitchEvent.kOutcomes.contains(ab.finalOutcome)) strikeouts++;
      if (ab.finalOutcome == 'bb') walks++;
    }

    String? mostFrequent(Map<String, int> m) {
      if (m.isEmpty) return null;
      var bestKey = m.keys.first;
      var bestVal = m[bestKey]!;
      for (final e in m.entries) {
        if (e.value > bestVal) {
          bestKey = e.key;
          bestVal = e.value;
        }
      }
      return bestKey;
    }

    // Per-pitch-type Whiff % / BAA / Strike %. `relevant` is already
    // filtered to this Team + Jersey # only, so these are this batter's
    // numbers — and they come from the exact same calc the Pitch Breakdown
    // tab uses (StatsService.pitchBreakdown), just on that smaller set.
    final byPitchType = <BatterPitchTypeStats>[
      for (final row in StatsService.pitchBreakdown(relevant))
        BatterPitchTypeStats(
          pitchType: row['pitchType'] as String,
          pitches: row['n'] as int,
          usagePct: row['usagePct'] as double?,
          whiffPct: row['whiffPct'] as double?,
          baa: row['avgAgainst'] as double?,
          strikePct: row['strikePct'] as double?,
        ),
    ];

    return BatterTendencies(
      totalAtBats: atBats.where((a) => a.finalOutcome != null).length,
      totalPitches: relevant.length,
      pitchUsageCounts: usage,
      mostFrequentPitch: mostFrequent(usage),
      strikeouts: strikeouts,
      walks: walks,
      foulBalls: fouls,
      ballsInPlay: bip,
      byPitchType: byPitchType,
    );
  }
}
