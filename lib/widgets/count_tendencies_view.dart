import 'package:flutter/material.dart';

import '../services/color_guides.dart';
import '../services/stats_service.dart' show perfHex;
import '../theme/app_theme.dart';
import 'stat_box.dart';
import 'stat_hold_info.dart';

String _avg(double v) {
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : s;
}

String _pct1(double v) => '${v.toStringAsFixed(1)}%';

/// Count Tendencies, one card per count that actually has pitches.
///
/// Inside a card every pitch type thrown at that count is a row with, in this
/// order: Usage % (with N), Strike %, BAA.
///  * Usage % = pitches of that type at this count ÷ ALL pitches at this count.
///    N is the number of those pitches (not at-bats, batters or games). Usage
///    is not graded: it carries no good/bad color.
///  * Strike % = strikes ÷ N for that pitch type at this count (SKOUTAR's
///    strike rule: called, swinging, foul or in play), graded on the same
///    cutoffs as First-Pitch Strike %.
///  * BAA = hits ÷ official at-bats that ENDED on that pitch at that count;
///    a dash when none did (never .000).
/// Pitch types never thrown at a count, and counts with no pitches, are not
/// shown. The layout is cards rather than a 12-column grid so it stays
/// readable on a phone.
class CountTendenciesView extends StatelessWidget {
  final Map<String, dynamic> heatmap;
  const CountTendenciesView({super.key, required this.heatmap});

  @override
  Widget build(BuildContext context) {
    final counts = heatmap['counts'] as List<String>;
    final pitchTypes = heatmap['pitchTypes'] as List<String>;
    final cells = heatmap['cells'] as Map<String, Map<String, dynamic>>;
    final countTotals = heatmap['countTotals'] as Map<String, int>;
    final countStrikes = (heatmap['countStrikes'] as Map<String, int>?) ?? const <String, int>{};
    final countBaa = (heatmap['countBaa'] as Map<String, Map<String, dynamic>>?) ?? const {};

    final shown = [
      for (final c in counts)
        if ((countTotals[c] ?? 0) > 0) c,
    ];
    if (pitchTypes.isEmpty || shown.isEmpty) {
      return const Text('No pitch data yet.', style: TextStyle(color: Colors.grey));
    }

    return LayoutBuilder(builder: (context, constraints) {
      const gap = 8.0;
      final cols = constraints.maxWidth >= 900 ? 2 : 1;
      final cardWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final count in shown)
            SizedBox(
              width: cardWidth,
              child: _CountCard(
                count: count,
                total: countTotals[count] ?? 0,
                strikesAtCount: countStrikes[count] ?? 0,
                baaAtCount: countBaa[count],
                rows: [
                  for (final pt in pitchTypes)
                    if (cells['$count|$pt'] != null) cells['$count|$pt']!,
                ]..sort((a, b) {
                    final c = (b['n'] as int).compareTo(a['n'] as int);
                    return c != 0 ? c : (a['pitchType'] as String).compareTo(b['pitchType'] as String);
                  }),
              ),
            ),
        ],
      );
    });
  }
}

class _CountCard extends StatelessWidget {
  final String count;
  final int total;
  final int strikesAtCount;
  final Map<String, dynamic>? baaAtCount;
  final List<Map<String, dynamic>> rows;

  const _CountCard({
    required this.count,
    required this.total,
    required this.strikesAtCount,
    required this.baaAtCount,
    required this.rows,
  });

  static const double _labelWidth = 58;

  Widget _pitchChip(String pt) => StatHoldInfo(
        title: pt.toUpperCase(),
        description: composeHoldInfo(
          what: 'One row per pitch type thrown at $count: how often it is used here, how often it is a strike, '
              'and the batting average against when an at-bat ended on it.',
          colorGuide: pitchTypeColorGuide([pt]),
        ),
        child: Container(
          width: _labelWidth,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(color: AppColors.pitchColor(pt), borderRadius: BorderRadius.circular(14)),
          child: Text(pt.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _headerLabel(String text, int flex) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(text,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.4, color: AppColors.colMuted)),
        ),
      );

  Widget _line({
    required Widget label,
    required String who,
    required int n,
    required int totalAtCount,
    required double? usage,
    required int strikes,
    required double? strikePct,
    required double? baa,
    required int ab,
    required int hits,
    bool isAll = false,
  }) {
    final where = '$who at $count';
    final usageBox = StatBox(
      label: '',
      value: usage == null ? kUnavailable : _pct1(usage),
      sub: 'N=$n',
      emphasis: true,
      valueSize: 17,
      width: double.infinity,
      title: 'Usage % · $where',
      description: isAll
          ? 'All $totalAtCount pitches thrown at $count (every pitch type together), so this is 100%. '
              'N is the number of pitches.'
          : '$n of the $totalAtCount pitches thrown at $count were $who: $n ÷ $totalAtCount × 100. '
              'N=$n is the number of recorded pitches, not at-bats, batters or games. '
              'The usage of every pitch type at this count adds up to about 100%. '
              'Usage is not graded: using a pitch more or less often is not good or bad by itself.',
      showOnHover: true,
    );
    final strikeBox = StatBox(
      label: '',
      value: strikePct == null ? kUnavailable : _pct1(strikePct),
      sub: n == 0 ? null : '$strikes/$n',
      tier: strikePct == null ? null : perfHex('f_strike', strikePct),
      width: double.infinity,
      title: 'Strike % · $where',
      description: 'Of the $n pitch${n == 1 ? '' : 'es'} counted here, $strikes were strikes '
          '(called, swinging, foul or put in play): $strikes ÷ $n. Higher is better.',
      colorGuide: statColorGuide('f_strike', note: 'Strike % uses the same cutoffs as First-Pitch Strike % (F-Strike%).'),
      showOnHover: true,
    );
    final baaBox = StatBox(
      label: '',
      value: baa == null ? kUnavailable : _avg(baa),
      sub: ab > 0 ? '$hits/$ab AB' : 'no AB yet',
      tier: baa == null ? null : perfHex('AVG', baa),
      width: double.infinity,
      title: 'BAA · $where',
      description: 'Batting average against: hits ÷ official at-bats that ENDED on ${isAll ? 'a pitch' : 'this pitch'} '
          'thrown at $count (each at-bat is credited only to the pitch that ended it; walks and hit-by-pitch are not at-bats). '
          '${ab > 0 ? '$hits hit${hits == 1 ? '' : 's'} in $ab at-bat${ab == 1 ? '' : 's'}. Lower is better.' : 'No at-bat has ended on it here yet, so BAA is unavailable (a dash), not .000.'}',
      colorGuide: statColorGuide('AVG'),
      showOnHover: true,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: _labelWidth, child: label),
        const SizedBox(width: 4),
        Expanded(flex: 12, child: usageBox),
        const SizedBox(width: 4),
        Expanded(flex: 10, child: strikeBox),
        const SizedBox(width: 4),
        Expanded(flex: 10, child: baaBox),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bAb = (baaAtCount?['ab'] as int?) ?? 0;
    final bHits = (baaAtCount?['hits'] as int?) ?? 0;
    final bBaa = baaAtCount?['baa'] as double?;
    final allStrikePct = total > 0 ? (strikesAtCount / total * 100) : null;
    final smallCount = total < 10;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.colBorder, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StatHoldInfo(
          title: 'Count $count',
          description: composeHoldInfo(
            what: 'Balls-strikes before the pitch. $total recorded pitch${total == 1 ? '' : 'es'} were thrown at $count '
                'in this selection; every usage % below is out of that $total.',
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(count, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$total pitch${total == 1 ? '' : 'es'} thrown',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
            ),
            if (smallCount)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.brandOrangeDeep),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('small sample',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.brandOrangeDeep)),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          const SizedBox(width: _labelWidth + 4),
          _headerLabel('USAGE % (N)', 12),
          const SizedBox(width: 4),
          _headerLabel('STRIKE %', 10),
          const SizedBox(width: 4),
          _headerLabel('BAA', 10),
        ]),
        const Divider(height: 8, thickness: 1.2, color: AppColors.colBorder),
        for (final c in rows)
          _line(
            label: _pitchChip(c['pitchType'] as String),
            who: (c['pitchType'] as String).toUpperCase(),
            n: c['n'] as int,
            totalAtCount: total,
            usage: c['usagePct1'] as double?,
            strikes: (c['strikes'] as int?) ?? 0,
            strikePct: c['strikePct1'] as double?,
            baa: c['baa'] as double?,
            ab: (c['ab'] as int?) ?? 0,
            hits: (c['hits'] as int?) ?? 0,
          ),
        const Divider(height: 8, thickness: 1.2, color: AppColors.colBorder),
        _line(
          isAll: true,
          label: Container(
            width: _labelWidth,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
            child: const Text('ALL',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          who: 'All pitches',
          n: total,
          totalAtCount: total,
          usage: total > 0 ? 100.0 : null,
          strikes: strikesAtCount,
          strikePct: allStrikePct,
          baa: bBaa,
          ab: bAb,
          hits: bHits,
        ),
      ]),
    );
  }
}
