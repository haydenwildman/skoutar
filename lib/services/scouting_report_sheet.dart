import 'dart:ui' show Color;
import '../theme/app_theme.dart' show ScaleStyle;
import 'scouting_game_plan.dart';
import 'scouting_report_data.dart';
import 'sequence_scoring.dart' show SequenceScoring;
import 'stats_service.dart' show perfHex, swingPctColor;

/// Layout-agnostic content of the Scouting Report (team page plus one card per hitter), built ONCE from
/// [ScoutingReportData] (and its [ScoutingGamePlan]) and drawn by both the
/// on-screen report and the PDF export, so the two can never drift apart.
///
/// Nothing here recalculates a statistic: every number comes from the
/// existing calculators (StatsService / ScoutingGamePlanBuilder). This file
/// only arranges those numbers into rows, picks the heat-map tier with the
/// app's own [perfHex] / [swingPctColor], and shortens the existing notes.
///
/// Heat-map colors are stored as the raw tier color (or null = neutral).
/// A color is only attached when the sample reaches the same minimums the
/// game-plan analysis already uses ([GpConfig]); below that the cell stays
/// neutral and shows its sample size instead.

// ───────────────────────── small value types ─────────────────────────

/// One table cell. [tier] is a perf-palette color or null (neutral).
class SheetCell {
  final String text;
  final Color? tier;
  final bool bold;
  final bool muted;
  final bool left;
  const SheetCell(this.text, {this.tier, this.bold = false, this.muted = false, this.left = false});
}

class SheetTable {
  final List<String> headers;
  final List<List<SheetCell>> rows;
  final List<double> flex;
  const SheetTable(this.headers, this.rows, this.flex);
  bool get isEmpty => rows.isEmpty;
}

/// A metric box (label, big value, small denominator line, heat tier).
class SheetMetric {
  final String label;
  final String value;
  final String sub;
  final Color? tier;
  const SheetMetric(this.label, this.value, this.sub, this.tier);
}

/// One finding in the Game Plan area. [tag] keeps facts and suggestions apart.
class SheetFinding {
  final String headline;
  final String body;
  final String tag; // 'Observed' | 'Tendency' | 'Suggested' | 'Caution'
  final String conf; // short confidence label
  final String sample; // e.g. "Plate Appearances: 5"
  const SheetFinding(this.headline, this.body, this.tag, this.conf, this.sample);
}

class SheetNote {
  final String label; // Potential weakness | Potential approach | Caution
  final String tag; // Observed | Tendency | Suggested | Sample
  final String text;
  final String conf;
  const SheetNote(this.label, this.tag, this.text, this.conf);
}

class HitterCard {
  final int jersey;
  final String hand; // RHB | LHB | Hand n/a
  final int pa, ab, games;
  final String hAb; // "3-for-8" style H-AB
  final SheetMetric avg, obp, slg;
  final SheetTable pitchTable;
  final SheetTable countTable;
  final List<SheetNote> notes;
  final String conf;
  const HitterCard({
    required this.jersey,
    required this.hand,
    required this.pa,
    required this.ab,
    required this.games,
    required this.hAb,
    required this.avg,
    required this.obp,
    required this.slg,
    required this.pitchTable,
    required this.countTable,
    required this.notes,
    required this.conf,
  });
}

// ───────────────────────── the sheet ─────────────────────────

class ScoutingSheet {
  final ScoutingReportData r;
  final List<SheetMetric> summary;
  final SheetTable games;
  final int gamesHidden; // earliest games not listed (totals still in summary)
  final SheetTable pitches;
  final SheetTable teamCounts;
  final SheetTable dangerous;
  final SheetTable struggled;
  final List<SheetFinding> strengths;
  final List<SheetFinding> weaknesses;
  final List<SheetFinding> approaches;
  final List<SheetFinding> cautions;
  final List<HitterCard> cards; // every hitter with a jersey, report order

  const ScoutingSheet({
    required this.r,
    required this.summary,
    required this.games,
    required this.gamesHidden,
    required this.pitches,
    required this.teamCounts,
    required this.dangerous,
    required this.struggled,
    required this.strengths,
    required this.weaknesses,
    required this.approaches,
    required this.cautions,
    required this.cards,
  });

  /// Games listed in the history table before older ones are summarized.
  static const int maxGameRows = 8;

  factory ScoutingSheet.build(ScoutingReportData r) {
    final plan = r.plan;
    final s = r.stats;

    // ── A. Team performance summary ─────────────────────────────────
    final summary = <SheetMetric>[
      SheetMetric('ERA', s.era?.toStringAsFixed(2) ?? 'N/A', 'IP ${s.ipDisplay}', _tier('ERA', s.era)),
      SheetMetric('WHIP', s.whip?.toStringAsFixed(2) ?? 'N/A', 'IP ${s.ipDisplay}', _tier('WHIP', s.whip)),
      SheetMetric('AVG vs', s.avg != null ? fmtAvg3(s.avg) : 'N/A', 'team', _tier('AVG', s.avg)),
      SheetMetric('SLG vs', s.slg != null ? fmtAvg3(s.slg) : 'N/A', 'team', _tier('SLG', s.slg)),
      SheetMetric('PA', '${r.pa}', '${r.gamesFaced} game${r.gamesFaced == 1 ? '' : 's'}', null),
      SheetMetric('K%', s.kPct != null ? '${s.kPct}%' : 'N/A', 'of ${r.pa} PA', _tier('K_pct', s.kPct)),
      SheetMetric('BB%', s.bbPct != null ? '${s.bbPct}%' : 'N/A', 'of ${r.pa} PA', _tier('BB_pct', s.bbPct)),
      SheetMetric('Whiff%', s.whiffPct != null ? '${s.whiffPct}%' : 'N/A', 'of swings', _tier('whiff_pct', s.whiffPct)),
      SheetMetric('XBH', '${r.xbh}', '${r.hr} HR', null),
    ];

    // ── B. Previous-game history (existing per-game lines) ──────────
    final allGames = plan.games;
    final shownGames = allGames.length > maxGameRows ? allGames.sublist(allGames.length - maxGameRows) : allGames;
    final gameRows = <List<SheetCell>>[];
    for (final g in shownGames) {
      final avg = g.ab > 0 ? g.hits / g.ab : null;
      final kPct = g.pa > 0 ? g.ks / g.pa * 100 : null;
      final bbPct = g.pa > 0 ? g.bb / g.pa * 100 : null;
      final okAb = g.ab >= GpConfig.minAb;
      final okPa = g.pa >= GpConfig.minPa;
      gameRows.add([
        SheetCell('G${g.gameNumber}', bold: true, left: true),
        SheetCell('${g.pa}'),
        SheetCell('${g.hits}-${g.ab}'),
        SheetCell(avg == null ? '—' : fmtAvg3(avg), tier: _tier('AVG', avg, ok: okAb)),
        SheetCell('${g.bb}'),
        SheetCell('${g.ks}'),
        SheetCell(kPct == null ? '—' : '${kPct.round()}%', tier: _tier('K_pct', kPct, ok: okPa)),
        SheetCell(bbPct == null ? '—' : '${bbPct.round()}%', tier: _tier('BB_pct', bbPct, ok: okPa)),
        SheetCell(_er(g.er)),
      ]);
    }
    final games = SheetTable(
      ['Game', 'PA', 'H-AB', 'AVG', 'BB', 'K', 'K%', 'BB%', 'ER'],
      gameRows,
      [1.3, 1, 1.2, 1.3, 1, 1, 1.2, 1.2, 1],
    );

    // ── C. Team-wide pitch effectiveness ────────────────────────────
    final totalPitches = plan.teamTypes.fold<int>(0, (a, t) => a + t.pitches);
    final pitchRows = <List<SheetCell>>[];
    for (final t in plan.teamTypes) {
      final strikePct = t.strikePct == null ? null : t.strikePct! * 100;
      final whiffPct = t.whiffPct == null ? null : t.whiffPct! * 100;
      final swingPct = t.swingPct == null ? null : t.swingPct! * 100;
      final okP = t.pitches >= GpConfig.minPitches;
      final okSw = t.swings >= GpConfig.minSwings;
      final okAb = t.ab >= GpConfig.minAb;
      pitchRows.add([
        SheetCell(upperType(t.type), bold: true, left: true),
        SheetCell('${t.pitches}'),
        SheetCell(totalPitches > 0 ? '${(t.pitches / totalPitches * 100).round()}%' : '—'),
        SheetCell(strikePct == null ? '—' : '${strikePct.round()}%', tier: _tier('f_strike', strikePct, ok: okP)),
        SheetCell(swingPct == null ? '—' : '${swingPct.round()}%',
            tier: okSw && swingPct != null && whiffPct != null ? _asTier(swingPctColor(swingPct, whiffPct)) : null),
        SheetCell('${t.swings}'),
        SheetCell(whiffPct == null ? '—' : '${whiffPct.round()}%', tier: _tier('whiff_pct', whiffPct, ok: okSw)),
        SheetCell('${t.hits}-${t.ab}'),
        SheetCell(t.baa == null ? '—' : fmtAvg3(t.baa), tier: _tier('AVG', t.baa, ok: okAb)),
        SheetCell('${t.xbh}'),
        SheetCell('${t.ks}'),
        SheetCell('${t.bb}'),
      ]);
    }
    final pitches = SheetTable(
      ['Pitch', 'P', 'Use', 'Strike', 'Swing', 'Sw', 'Whiff', 'H-AB', 'AVG', 'XBH', 'K', 'BB'],
      pitchRows,
      [1.5, 1, 1, 1.3, 1.3, 1, 1.4, 1.3, 1.4, 1, 0.9, 0.9],
    );

    // Team count tendencies (same exclusive buckets as the hitter cards).
    final teamCounts = SheetTable(_countHeaders, _countRows(plan.teamCounts, null), _countFlex);

    // ── D. Most dangerous hitters (existing OBP rank, min 2 PA) ─────
    final handByJersey = {for (final h in plan.hitters) h.jersey: h};
    final dRows = <List<SheetCell>>[];
    for (final h in r.keyHitters) {
      final j = h['jersey'] as int;
      final pa = h['pa'] as int;
      final ab = (h['ab'] ?? 0) as int;
      final hits = (h['h'] ?? 0) as int;
      final hr = handByJersey[j];
      final avg = h['avg'] as double?;
      final obp = h['obp'] as double?;
      final slg = hr?.slg;
      final okAb = ab >= GpConfig.minAb;
      dRows.add([
        SheetCell('#$j', bold: true, left: true),
        SheetCell(_hand(hr?.hand, short: true)),
        SheetCell('$pa'),
        SheetCell('$hits-$ab'),
        SheetCell(avg == null ? '—' : fmtAvg3(avg), tier: _tier('batter_AVG', avg, ok: okAb)),
        SheetCell(obp == null ? '—' : fmtAvg3(obp), tier: _tier('batter_OBP', obp, ok: okAb)),
        SheetCell(slg == null ? '—' : fmtAvg3(slg), tier: _tier('batter_SLG', slg, ok: okAb)),
        SheetCell('${h['bb']}'),
        SheetCell('${h['k']}'),
      ]);
    }
    final dangerous = SheetTable(
      ['#', 'Hand', 'PA', 'H-AB', 'AVG', 'OBP', 'SLG', 'BB', 'K'],
      dRows,
      [1.2, 1, 1, 1.2, 1.3, 1.3, 1.3, 0.9, 0.9],
    );

    // ── E. Hitters who have struggled (existing hitless rule) ───────
    final sRows = <List<SheetCell>>[];
    for (final m in plan.struggled) {
      final h = m['h'] as HitterReport;
      sRows.add([
        SheetCell('#${h.jersey}', bold: true, left: true),
        SheetCell(_hand(h.hand, short: true)),
        SheetCell('${h.pa}'),
        SheetCell('${h.hits}-${h.ab}'),
        SheetCell(h.obp == null ? '—' : fmtAvg3(h.obp),
            tier: _tier('batter_OBP', h.obp, ok: h.ab >= GpConfig.minAb)),
        SheetCell('${h.bb}'),
        SheetCell('${h.ks}'),
        SheetCell('See p.2', muted: true),
      ]);
    }
    final struggled = SheetTable(
      ['#', 'Hand', 'PA', 'H-AB', 'OBP', 'BB', 'K', 'Card'],
      sRows,
      [1.2, 1, 1, 1.2, 1.3, 0.9, 0.9, 1.5],
    );

    // ── F. Game plan: facts and suggestions kept apart ──────────────
    final strengths = <SheetFinding>[];
    final weaknesses = <SheetFinding>[];
    final approaches = <SheetFinding>[];
    final cautions = <SheetFinding>[];
    for (final t in plan.takeaways) {
      final fact = SheetFinding(t.headline, t.fact, t.tendency != null ? 'Tendency' : 'Observed',
          _confShort(t.conf), t.sample);
      switch (t.kind) {
        case 'strength':
          strengths.add(fact);
        case 'concern':
          weaknesses.add(fact);
        default:
          cautions.add(SheetFinding(t.headline, t.fact, 'Caution', _confShort(t.conf), t.sample));
      }
      approaches.add(SheetFinding(t.headline, t.suggestion, 'Suggested', _confShort(t.conf), t.sample));
    }
    // Data-quality cautions that are always true of the recorded data.
    if (plan.incompletePa > 0) {
      cautions.add(SheetFinding('Unfinished at-bats', '${plan.incompletePa} plate appearance(s) have no recorded result and are excluded from AVG/OBP/SLG.',
          'Caution', 'n/a', 'Plate Appearances: ${plan.incompletePa}'));
    }
    if (plan.unknownJerseyPa > 0) {
      cautions.add(SheetFinding('No jersey recorded', '${plan.unknownJerseyPa} completed PA(s) have no jersey number, so they are in team totals but on no hitter card.',
          'Caution', 'n/a', 'Plate Appearances: ${plan.unknownJerseyPa}'));
    }
    cautions.add(const SheetFinding('Not recorded',
        'Base runners, pitch location and velocity are not tracked, so no runner or location advice is given.',
        'Caution', 'n/a', ''));

    // ── Hitter cards (every hitter with a jersey) ───────────────────
    final cards = [for (final h in plan.hitters) _card(h)];

    return ScoutingSheet(
      r: r,
      summary: summary,
      games: games,
      gamesHidden: allGames.length - shownGames.length,
      pitches: pitches,
      teamCounts: teamCounts,
      dangerous: dangerous,
      struggled: struggled,
      strengths: strengths,
      weaknesses: weaknesses,
      approaches: approaches,
      cautions: cautions,
      cards: cards,
    );
  }

  // ───────────────────────── hitter card ─────────────────────────

  static HitterCard _card(HitterReport h) {
    final okAb = h.ab >= GpConfig.minAb;
    SheetMetric box(String label, String stat, double? v) => SheetMetric(
        label, v == null ? '—' : fmtAvg3(v), okAb ? '' : 'Under ${GpConfig.minAb} At-Bats', _tier(stat, v, ok: okAb));

    final total = h.totalPitches;
    final tRows = <List<SheetCell>>[];
    for (final t in h.byType) {
      final whiffPct = t.whiffPct == null ? null : t.whiffPct! * 100;
      tRows.add([
        SheetCell(upperType(t.type), bold: true, left: true),
        SheetCell('${t.pitches}'),
        SheetCell(total > 0 ? '${(t.pitches / total * 100).round()}%' : '—'),
        SheetCell('${t.hits}-${t.ab}'),
        SheetCell(t.baa == null ? '—' : fmtAvg3(t.baa),
            tier: _tier('batter_AVG', t.baa, ok: t.ab >= GpConfig.minAb)),
        SheetCell('${t.whiffs}/${t.swings}'),
        SheetCell(whiffPct == null ? '—' : '${whiffPct.round()}%',
            tier: _tier('whiff_pct', whiffPct, ok: t.swings >= GpConfig.minSwings)),
      ]);
    }

    return HitterCard(
      jersey: h.jersey,
      hand: _hand(h.hand),
      pa: h.pa,
      ab: h.ab,
      games: h.games,
      hAb: '${h.hits}-${h.ab}',
      avg: box('AVG', 'batter_AVG', h.avg),
      obp: box('OBP', 'batter_OBP', h.obp),
      slg: box('SLG', 'batter_SLG', h.slg),
      pitchTable: SheetTable(['Pitch', 'P', 'Use', 'H-AB', 'AVG', 'Wh/Sw', 'Whiff'], tRows,
          [1.5, 1, 1, 1.2, 1.3, 1.3, 1.2]),
      countTable: SheetTable(_countHeaders, _countRows(h.byCount, h), _countFlex),
      notes: _notes(h),
      conf: _confShort(confFor(h.pa, 2, 6)),
    );
  }

  /// Weakness / approach / caution, taken from the notes the game-plan
  /// builder already wrote for this hitter (shortened to the first sentence),
  /// with a plain sample warning when the data cannot support a conclusion.
  static List<SheetNote> _notes(HitterReport h) {
    GpNote? pick(bool Function(GpNote n) f) {
      for (final n in h.notes) {
        if (f(n)) return n;
      }
      return null;
    }

    final weak = pick((n) => n.label == 'Potential weakness');
    final appr = pick((n) => n.label == 'Suggested approach') ?? pick((n) => n.label == 'Watch for');
    final strong = pick((n) => n.label == 'Strength');

    SheetNote from(String label, GpNote? n, String none) {
      if (n == null) return SheetNote(label, 'Sample', none, 'n/a');
      return SheetNote(label, _tagShort(n.tag), _firstSentence(n.text), _confShort(n.conf));
    }

    final smallSample = h.pa < 6;
    SheetNote caution;
    if (strong != null) {
      caution = SheetNote('Caution', _tagShort(strong.tag), _firstSentence(strong.text), _confShort(strong.conf));
    } else if (smallSample) {
      caution = SheetNote('Caution', 'Sample',
          'Small sample (${h.pa} PA, ${h.ab} AB). Treat every number here as a note, not a tendency.',
          _confShort(confFor(h.pa, 2, 6)));
    } else {
      caution = const SheetNote('Caution', 'Sample', 'No hitting strength stands out in the recorded data.', 'n/a');
    }

    return [
      from('Potential weakness', weak, 'Insufficient data to name one.'),
      from('Potential approach', appr, 'Insufficient data for a suggestion.'),
      caution,
    ];
  }

  // ───────────────────────── count tables ─────────────────────────

  static const List<String> _countHeaders = ['Count', 'P', 'Sw', 'Whiff', 'PA', 'H-AB', 'K', 'BB', 'AVG', 'Pitches used'];
  static const List<double> _countFlex = [1.9, 0.8, 0.8, 1.4, 0.8, 1.15, 0.7, 0.7, 1.2, 3.8];

  /// Rows for the exclusive buckets (0-0, pitcher ahead, even, hitter ahead)
  /// then the two-strike row, which is drawn as an overlapping subset of the
  /// rows above it and so is never added into any total.
  static List<List<SheetCell>> _countRows(List<CountBucketLine> buckets, HitterReport? h) {
    final byType = h == null ? null : _pitchesByBucket(h);
    final rows = <List<SheetCell>>[];
    for (final b in buckets) {
      final whiffPct = b.whiffPct == null ? null : b.whiffPct! * 100;
      final isTwo = b.key == 'two';
      rows.add([
        SheetCell(_countLabel(b), bold: true, left: true),
        SheetCell('${b.pitches}'),
        SheetCell('${b.swings}'),
        SheetCell(whiffPct == null ? '—' : '${whiffPct.round()}%',
            tier: _tier('whiff_pct', whiffPct, ok: b.swings >= GpConfig.minSwings)),
        SheetCell('${b.paEnded}'),
        SheetCell('${b.hits}-${b.ab}'),
        SheetCell('${b.ks}'),
        SheetCell('${b.bb}'),
        SheetCell(b.baa == null ? '—' : fmtAvg3(b.baa),
            tier: _tier(h == null ? 'AVG' : 'batter_AVG', b.baa, ok: b.ab >= GpConfig.minAb)),
        SheetCell(byType == null ? _teamUsed(b) : _usedText(byType[b.key]),
            left: true, muted: b.pitches == 0 || isTwo && b.pitches < GpConfig.minPitches),
      ]);
    }
    return rows;
  }

  static String _countLabel(CountBucketLine b) => switch (b.key) {
        'first' => '0-0',
        'ahead' => ('Ahead'),
        'even' => 'Even',
        'behind' => 'Behind',
        _ => '2 strikes*',
      };

  /// Team rows have no per-bucket pitch-type breakdown in the plan, so they
  /// state the sample instead of inventing one.
  static String _teamUsed(CountBucketLine b) => b.pitches == 0 ? '—' : '${b.pitches} pitches';

  /// bucket key -> pitch type -> [pitches, swings, whiffs], derived from the
  /// hitter's recorded at-bats with the same bucket rule the plan builder uses.
  static Map<String, Map<String, List<int>>> _pitchesByBucket(HitterReport h) {
    final out = <String, Map<String, List<int>>>{};
    for (final ab in h.atBats) {
      for (final p in ab.pitches) {
        final parts = p.count.split('-');
        if (parts.length != 2) continue;
        final b = int.tryParse(parts[0]), s = int.tryParse(parts[1]);
        if (b == null || s == null) continue;
        final keys = <String>[_bucketKey(b, s), if (s == 2) 'two'];
        final swing = p.call == 'ss' || p.call == 'f' || p.call == 'ip';
        for (final k in keys) {
          final m = out.putIfAbsent(k, () => {}).putIfAbsent(p.type, () => [0, 0, 0]);
          m[0]++;
          if (swing) m[1]++;
          if (p.call == 'ss') m[2]++;
        }
      }
    }
    return out;
  }

  /// Same classification as the plan's private `_bucketKeyFor` (kept in step
  /// by reading the shared thresholds in [GpConfig]).
  static String _bucketKey(int b, int s) {
    if (b == 0 && s == 0) return 'first';
    final v = SequenceScoring.countValue(b, s);
    if (v >= GpConfig.aheadMin) return 'ahead';
    if (v <= GpConfig.behindMax) return 'behind';
    return 'even';
  }

  /// "FB 6 · SL 3(2/4)": pitch type and count; whiffs/swings in brackets only
  /// when that type has enough swings in this count to mean something.
  static String _usedText(Map<String, List<int>>? m) {
    if (m == null || m.isEmpty) return '—';
    final entries = m.entries.toList()..sort((a, b) => b.value[0].compareTo(a.value[0]));
    final parts = <String>[];
    for (final e in entries.take(3)) {
      final v = e.value;
      final res = v[1] >= GpConfig.minSwings ? ' (${v[2]}/${v[1]} wh)' : '';
      parts.add('${upperType(e.key)} ${v[0]}$res');
    }
    final more = entries.length - 3;
    return parts.join(' · ') + (more > 0 ? ' +$more' : '');
  }

  // ───────────────────────── helpers ─────────────────────────

  static Color? _tier(String stat, double? v, {bool ok = true}) {
    if (!ok || v == null) return null;
    return _asTier(perfHex(stat, v));
  }

  static Color? _asTier(Color c) => ScaleStyle.isTier(c) ? c : null;

  static String _er(double er) => er == er.roundToDouble() ? er.toStringAsFixed(0) : er.toStringAsFixed(1);

  static String _hand(String? hand, {bool short = false}) {
    switch (hand) {
      case 'R':
        return short ? 'R' : 'RHB';
      case 'L':
        return short ? 'L' : 'LHB';
      case 'Both recorded':
        return short ? 'L/R' : 'Both recorded';
      default:
        return short ? '—' : 'Hand n/a';
    }
  }

  static String _confShort(Conf c) => switch (c) {
        Conf.insufficient => 'Insufficient',
        Conf.low => 'Low',
        Conf.moderate => 'Moderate',
        Conf.good => 'Good',
      };

  static String _tagShort(String tag) => switch (tag) {
        'Observed fact' => 'Observed',
        'Supported tendency' => 'Tendency',
        'Suggested approach' => 'Suggested',
        _ => tag,
      };

  static String _firstSentence(String t) {
    final i = t.indexOf('. ');
    final s = i > 0 ? t.substring(0, i + 1) : t;
    return s.trim();
  }
}
