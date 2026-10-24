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

/// Count Tendencies as a grid of SQUARES: one row per pitch type (plus an ALL
/// row), one column per count that actually has pitches.
///
/// Each square is split into three strips, always in this order:
///  1. Usage % with N - that pitch type's share of ALL pitches thrown at the
///     count, and N = how many of those pitches there were (pitches, not
///     at-bats, batters or games). Usage is not graded.
///  2. Strike % with strikes/N - SKOUTAR's strike rule (called, swinging, foul
///     or in play), graded on the First-Pitch Strike % cutoffs.
///  3. BAA with hits/AB - hits ÷ official at-bats that ENDED on that pitch at
///     that count; a dash when none did (never .000).
/// Pitch types never thrown at a count show an empty square, and counts with
/// no pitches get no column. Graded strips use the app's scale style: bright
/// border, duller fill. If the grid is wider than the screen it scrolls
/// sideways inside itself.
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
      const labelW = 58.0;
      // Whole pixels, so the row can never be a fraction of a pixel wider than
      // the space it is given. Below the minimum the grid scrolls sideways.
      final fit = ((constraints.maxWidth - labelW) / shown.length).floorToDouble();
      final cell = fit.clamp(84.0, 108.0).toDouble();
      final valueFont = (cell * 0.16).clamp(13.0, 17.0).toDouble();
      final subFont = (cell * 0.115).clamp(9.5, 12.0).toDouble();
      final tableW = labelW + cell * shown.length;

      Widget strip({
        required String value,
        required String? sub,
        required Color? tier,
        required String title,
        required String what,
        String? guide,
      }) {
        final graded = tier != null && value != kUnavailable;
        return StatHoldInfo(
          title: title,
          showOnHover: true,
          description: composeHoldInfo(what: what, colorGuide: guide),
          child: Container(
            margin: const EdgeInsets.all(1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: graded ? ScaleStyle.fillAny(tier) : (value == kUnavailable ? AppColors.surfaceAlt : Colors.white),
              border: Border.all(color: graded ? tier : AppColors.colBorder, width: graded ? 1.8 : 1.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: valueFont,
                          fontWeight: FontWeight.w900,
                          color: value == kUnavailable ? AppColors.colMuted : AppColors.colText)),
                  if (sub != null) ...[
                    const SizedBox(width: 3),
                    Text(sub, style: TextStyle(fontSize: subFont, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
                  ],
                ]),
              ),
            ),
          ),
        );
      }

      Widget square({
        required String count,
        required String who,
        required bool isAll,
        required int n,
        required int totalAtCount,
        required double? usage,
        required int strikes,
        required double? strikePct,
        required double? baa,
        required int ab,
        required int hits,
      }) {
        final where = '$who at $count';
        return SizedBox(
          width: cell,
          height: cell,
          child: Column(children: [
            Expanded(
              child: strip(
                value: usage == null ? kUnavailable : _pct1(usage),
                sub: 'N=$n',
                tier: null,
                title: 'Usage % · $where',
                what: isAll
                    ? 'All $totalAtCount pitches thrown at $count (every pitch type together), so this is 100%. N is the number of pitches.'
                    : '$n of the $totalAtCount pitches thrown at $count were $who: $n ÷ $totalAtCount × 100. '
                        'N=$n is the number of recorded pitches, not at-bats, batters or games. '
                        'Usage is not graded: using a pitch more or less often is not good or bad by itself.',
              ),
            ),
            Expanded(
              child: strip(
                value: strikePct == null ? kUnavailable : _pct1(strikePct),
                sub: n == 0 ? null : '$strikes/$n',
                tier: strikePct == null ? null : perfHex('f_strike', strikePct),
                title: 'Strike % · $where',
                what: 'Of the $n pitch${n == 1 ? '' : 'es'} counted here, $strikes were strikes '
                    '(called, swinging, foul or put in play): $strikes ÷ $n. Higher is better.',
                guide: statColorGuide('f_strike', note: 'Strike % uses the same cutoffs as First-Pitch Strike % (F-Strike%).'),
              ),
            ),
            Expanded(
              child: strip(
                value: baa == null ? kUnavailable : _avg(baa),
                sub: ab > 0 ? '$hits/$ab' : null,
                tier: baa == null ? null : perfHex('AVG', baa),
                title: 'BAA · $where',
                what: 'Batting average against: hits ÷ official at-bats that ENDED on ${isAll ? 'a pitch' : 'this pitch'} '
                    'thrown at $count (each at-bat is credited only to the pitch that ended it; walks and hit-by-pitch are not at-bats). '
                    '${ab > 0 ? '$hits hit${hits == 1 ? '' : 's'} in $ab at-bat${ab == 1 ? '' : 's'}. Lower is better.' : 'No at-bat has ended on it here yet, so BAA is unavailable (a dash), not .000.'}',
                guide: statColorGuide('AVG'),
              ),
            ),
          ]),
        );
      }

      // The margin goes INSIDE the fixed-size box: a Container with both a
      // width and a margin is wider than its width, which pushed rows with an
      // empty square past the edge (the 3-2 overflow).
      Widget emptySquare() => SizedBox(
            width: cell,
            height: cell,
            child: Container(
              margin: const EdgeInsets.all(1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border.all(color: AppColors.colBorder, width: 1.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('—', style: TextStyle(color: AppColors.colMuted, fontSize: valueFont)),
            ),
          );

      Widget label(Widget child) => SizedBox(
            width: labelW,
            height: cell,
            child: Center(child: child),
          );

      Widget pitchChip(String pt) => StatHoldInfo(
            title: pt.toUpperCase(),
            description: composeHoldInfo(
              what: 'One row per pitch type: for each count, how often it is used, how often it is a strike, '
                  'and the batting average against when an at-bat ended on it.',
              colorGuide: pitchTypeColorGuide([pt]),
            ),
            child: Container(
              width: 50,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              decoration: BoxDecoration(color: AppColors.pitchColor(pt), borderRadius: BorderRadius.circular(14)),
              child: Text(pt.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          );

      Widget countHeader(String count) {
        final total = countTotals[count] ?? 0;
        return StatHoldInfo(
          title: 'Count $count',
          description: composeHoldInfo(
            what: 'Balls-strikes before the pitch. $total recorded pitch${total == 1 ? '' : 'es'} were thrown at $count '
                'in this selection; every usage % in this column is out of that $total.'
                '${total < 10 ? '\nSmall sample: fewer than 10 pitches at this count.' : ''}',
          ),
          child: SizedBox(
            width: cell,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text('$total pitch${total == 1 ? '' : 'es'}${total < 10 ? ' · small' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: total < 10 ? AppColors.brandOrangeDeep : AppColors.colMuted)),
            ]),
          ),
        );
      }

      final grid = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(width: labelW),
          for (final c in shown) countHeader(c),
        ]),
        const SizedBox(height: 2),
        for (final pt in pitchTypes)
          Row(children: [
            label(pitchChip(pt)),
            for (final c in shown)
              if (cells['$c|$pt'] == null)
                emptySquare()
              else
                square(
                  count: c,
                  who: pt.toUpperCase(),
                  isAll: false,
                  n: cells['$c|$pt']!['n'] as int,
                  totalAtCount: countTotals[c] ?? 0,
                  usage: cells['$c|$pt']!['usagePct1'] as double?,
                  strikes: (cells['$c|$pt']!['strikes'] as int?) ?? 0,
                  strikePct: cells['$c|$pt']!['strikePct1'] as double?,
                  baa: cells['$c|$pt']!['baa'] as double?,
                  ab: (cells['$c|$pt']!['ab'] as int?) ?? 0,
                  hits: (cells['$c|$pt']!['hits'] as int?) ?? 0,
                ),
          ]),
        Row(children: [
          label(Container(
            width: 50,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
            child: const Text('ALL',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          )),
          for (final c in shown)
            square(
              count: c,
              who: 'All pitches',
              isAll: true,
              n: countTotals[c] ?? 0,
              totalAtCount: countTotals[c] ?? 0,
              usage: (countTotals[c] ?? 0) > 0 ? 100.0 : null,
              strikes: countStrikes[c] ?? 0,
              strikePct: (countTotals[c] ?? 0) > 0 ? ((countStrikes[c] ?? 0) / countTotals[c]! * 100) : null,
              baa: countBaa[c]?['baa'] as double?,
              ab: (countBaa[c]?['ab'] as int?) ?? 0,
              hits: (countBaa[c]?['hits'] as int?) ?? 0,
            ),
        ]),
      ]);

      // Key to the three strips inside every square, top to bottom.
      final key = Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(spacing: 14, runSpacing: 2, children: const [
          Text('Each square, top to bottom:', style: TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
          Text('USAGE % (N)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
          Text('STRIKE %', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
          Text('BAA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
        ]),
      );

      final sized = SizedBox(width: tableW, child: grid);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        key,
        if (tableW <= constraints.maxWidth)
          sized
        else
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: sized),
      ]);
    });
  }
}
