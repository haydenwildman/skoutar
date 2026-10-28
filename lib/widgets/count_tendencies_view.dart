import 'package:flutter/material.dart';

import '../services/color_guides.dart';
import '../services/stats_service.dart' show perfHex;
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'stat_box.dart';
import 'stat_hold_info.dart';

String _avg(double v) {
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : s;
}

String _pct1(double v) => '${v.toStringAsFixed(1)}%';

/// Count Tendencies as a grid of SQUARES.
///
/// DESKTOP / WIDE: one row per pitch type (plus an ALL row), one column per
/// count that actually has pitches.
/// PHONE (content narrower than [Breakpoints.phone]): see the pitch selector
/// below; the desktop grid is not used.
///
/// Each square is split into three strips, always in this order:
///  1. Usage % with P - that pitch type's share of ALL pitches thrown at the
///     count, and P = how many of those pitches there were (pitches, not
///     at-bats, batters or games). Usage is not graded.
///  2. Strike % with strikes/N - SKOUTAR's strike rule (called, swinging, foul
///     or in play), graded on the First-Pitch Strike % cutoffs.
///  3. BAA with hits/AB - hits ÷ official at-bats that ENDED on that pitch at
///     that count; a dash when none did (never .000).
/// Pitch types never thrown at a count show an empty square, and counts with
/// no pitches get no column. Graded strips use the app's scale style: bright
/// border, duller fill. If the grid is wider than the screen it scrolls
/// sideways inside itself.
///
/// PHONE ONLY: a pitch selector (ALL + every pitch type in the data) sits at
/// the top and the grid below shows ONLY the selected pitch, laid out as balls
/// (down) by strikes (across) - 4 rows by 3 columns, no sideways scrolling.
/// The selection is kept for as long as this view stays on screen, and falls
/// back to ALL if that pitch type is no longer in the data. Desktop and tablet
/// keep the full grid above unchanged.
class CountTendenciesView extends StatefulWidget {
  final Map<String, dynamic> heatmap;
  const CountTendenciesView({super.key, required this.heatmap});

  @override
  State<CountTendenciesView> createState() => _CountTendenciesViewState();
}

class _CountTendenciesViewState extends State<CountTendenciesView> {
  /// Phone selector: 'ALL' or a pitch-type key.
  String _selected = 'ALL';

  @override
  Widget build(BuildContext context) {
    final heatmap = widget.heatmap;
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
      final phone = constraints.maxWidth < Breakpoints.phone;
      // Phone: narrow row labels (balls) and always 3 columns (strikes 0-2).
      final labelW = phone ? 46.0 : 64.0;
      // Number of columns the grid has in the current orientation.
      final cols = phone ? 3 : shown.length;
      // Whole pixels, so the row can never be a fraction of a pixel wider than
      // the space it is given. Below the minimum the grid scrolls sideways.
      final fit = ((constraints.maxWidth - labelW) / cols).floorToDouble();
      final cell = phone ? fit.clamp(60.0, 130.0).toDouble() : fit.clamp(84.0, 108.0).toDouble();
      final cellH = phone ? 96.0 : (cell < 100.0 ? 100.0 : cell);
      final valueFont = phone ? (cell * 0.15).clamp(12.0, 15.0).toDouble() : (cell * 0.15).clamp(13.0, 16.0).toDouble();
      final subFont = phone ? 9.5 : (cell * 0.105).clamp(9.5, 11.0).toDouble();
      final labelFont = phone ? 8.0 : 8.5;
      final tableW = labelW + cell * cols;

      // Usage / strike / BAA cells share one look on both layouts.
      Widget strip({
        required String label,
        required String value,
        required String? sub,
        required Color? tier,
        required String title,
        required String what,
        String? guide,
      }) {
        final graded = tier != null && value != kUnavailable;
        final valueText = Text(value,
            style: TextStyle(
                fontSize: valueFont,
                fontWeight: FontWeight.w900,
                color: value == kUnavailable ? AppColors.colMuted : AppColors.colText));
        final subText = sub == null
            ? null
            : Text(sub, style: TextStyle(fontSize: subFont, fontWeight: FontWeight.w700, color: AppColors.colMuted));
        return StatHoldInfo(
          title: title,
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
                // Every strip says what it is: a small label on top, then the
                // value, then its sample (P, strikes/pitches, hits/at-bats).
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                          fontSize: labelFont, fontWeight: FontWeight.w900, color: AppColors.colMuted, letterSpacing: 0.3)),
                  if (phone)
                    Column(mainAxisSize: MainAxisSize.min, children: [valueText, if (subText != null) subText])
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        valueText,
                        if (subText != null) ...[const SizedBox(width: 3), subText],
                      ],
                    ),
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
        String usageText(double v) => phone ? '${v.toStringAsFixed(0)}%' : _pct1(v);
        return SizedBox(
          width: cell,
          height: cellH,
          child: Column(children: [
            Expanded(
              child: strip(
                label: 'USAGE %',
                value: usage == null ? kUnavailable : usageText(usage),
                sub: 'P: $n',
                tier: null,
                title: 'Usage % · $where',
                what: isAll
                    ? 'All $totalAtCount pitches thrown at $count (every pitch type together), so this is 100%. P is the number of pitches.'
                    : '$n of the $totalAtCount pitches thrown at $count were $who: $n ÷ $totalAtCount × 100. '
                        'P: $n is the number of recorded pitches, not at-bats, batters or games. '
                        'Usage is not graded: using a pitch more or less often is not good or bad by itself.',
              ),
            ),
            Expanded(
              child: strip(
                label: 'STRIKE %',
                value: strikePct == null ? kUnavailable : (phone ? '${strikePct.toStringAsFixed(0)}%' : _pct1(strikePct)),
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
                label: 'BAA',
                value: baa == null ? kUnavailable : _avg(baa),
                sub: ab > 0 ? '$hits/$ab' : null,
                tier: baa == null ? null : perfHex('AVG', baa),
                title: 'BAA · $where',
                what: 'Batting average against = hits ÷ official at-bats (H ÷ AB), counting only at-bats that ENDED on '
                    '${isAll ? 'a pitch (any type)' : 'a $who'} thrown when the count was $count.\n\n'
                    'Which count: the count is balls-strikes BEFORE the pitch is thrown. Only the pitch that ends a plate appearance '
                    'can add to BAA, and it is credited to the count that pitch was thrown at (for example, a single on a 1-2 pitch '
                    'belongs to 1-2, not to the 0-0 pitch that started the at-bat). Earlier pitches of the same at-bat add nothing here. '
                    'This is not every plate appearance that ever passed through $count: only those that finished on a pitch thrown at $count. '
                    '${isAll ? '' : 'In this box it is also limited to $who as the finishing pitch. '}'
                    'An at-bat still in progress has no result yet and is not counted.\n\n'
                    'Hits (numerator): single, double, triple, home run.\n'
                    'At-bats (denominator): every finished plate appearance except a walk or hit-by-pitch. '
                    'That includes hits, strikeouts (swinging, looking, dropped third strike), ground/fly/line outs, double plays, '
                    "fielder's choices and errors (an error is an at-bat, not a hit).\n"
                    'Not at-bats: walks and hit-by-pitches (they do not lower BAA). SKOUTAR has no separate sacrifice-fly result, '
                    'so a fly out is logged and counted as a normal at-bat.\n\n'
                    '${ab > 0 ? 'Here: $hits hit${hits == 1 ? '' : 's'} in $ab at-bat${ab == 1 ? '' : 's'}. Lower is better.' : 'No at-bat has ended here yet, so BAA is a dash, not .000.'}',
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
            height: cellH,
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

      // A pitch-type tag that scales its text down instead of cutting it off.
      Widget tag(String text, Color color, double width) => Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          );

      Widget pitchChip(String pt, double width) => StatHoldInfo(
            title: pt.toUpperCase(),
            description: composeHoldInfo(
              what: phone
                  ? 'One column per pitch type: for each count, how often it is used, how often it is a strike, '
                      'and the batting average against when an at-bat ended on it.'
                  : 'One row per pitch type: for each count, how often it is used, how often it is a strike, '
                      'and the batting average against when an at-bat ended on it.',
              colorGuide: pitchTypeColorGuide([pt]),
            ),
            child: tag(pt.toUpperCase(), AppColors.pitchColor(pt), width),
          );

      Widget allChip(double width) => StatHoldInfo(
            title: 'ALL pitches',
            description: 'Every pitch type combined at each count.',
            child: tag('ALL', AppColors.ink, width),
          );

      // Count label: "balls-strikes" plus its pitch total (P).
      Widget countLabel(String count, {required double width, double? height}) {
        final total = countTotals[count] ?? 0;
        final small = total < 10;
        return StatHoldInfo(
          title: 'Count $count',
          description: composeHoldInfo(
            what: 'Balls-strikes before the pitch. $total recorded pitch${total == 1 ? '' : 'es'} were thrown at $count '
                'in this selection; every usage % for this count is out of that $total (P: $total).'
                '${small ? '\nSmall sample: fewer than 10 pitches at this count.' : ''}',
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('P: $total',
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: small ? AppColors.brandOrangeDeep : AppColors.colMuted)),
              ),
            ]),
          ),
        );
      }

      // Top-left corner: names the two axes so nobody has to guess.
      Widget corner({required String across, required String down, double? height}) => SizedBox(
            width: labelW,
            height: height,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('$across across',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
                  Text('$down down',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
                ]),
              ),
            ),
          );

      Widget cellFor(String c, String pt) {
        final cell0 = cells['$c|$pt'];
        if (cell0 == null) return emptySquare();
        return square(
          count: c,
          who: pt.toUpperCase(),
          isAll: false,
          n: cell0['n'] as int,
          totalAtCount: countTotals[c] ?? 0,
          usage: cell0['usagePct1'] as double?,
          strikes: (cell0['strikes'] as int?) ?? 0,
          strikePct: cell0['strikePct1'] as double?,
          baa: cell0['baa'] as double?,
          ab: (cell0['ab'] as int?) ?? 0,
          hits: (cell0['hits'] as int?) ?? 0,
        );
      }

      Widget allCellFor(String c) => square(
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
          );

      final Widget grid;
      if (!phone) {
        // WIDE: pitch types down the side, counts across the top.
        grid = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            corner(across: 'Count', down: 'Pitch', height: 46),
            for (final c in shown) countLabel(c, width: cell, height: 46),
          ]),
          const SizedBox(height: 2),
          for (final pt in pitchTypes)
            Row(children: [
              SizedBox(width: labelW, height: cellH, child: Center(child: pitchChip(pt, labelW - 8))),
              for (final c in shown) cellFor(c, pt),
            ]),
          Row(children: [
            SizedBox(width: labelW, height: cellH, child: Center(child: allChip(labelW - 8))),
            for (final c in shown) allCellFor(c),
          ]),
        ]);
      } else {
        // PHONE: one pitch at a time. Balls (0-3) down the side, strikes
        // (0-2) across the top; each square is that pitch at that count.
        final sel = (_selected == 'ALL' || pitchTypes.contains(_selected)) ? _selected : 'ALL';
        Widget head(String t) => SizedBox(
              width: cell,
              height: 22,
              child: Center(
                child: Text(t,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
              ),
            );
        Widget rowHead(int balls) => SizedBox(
              width: labelW,
              height: cellH,
              child: Center(
                child: Text('$balls ${balls == 1 ? 'ball' : 'balls'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
              ),
            );
        Widget selChip(String pt) {
          final on = sel == pt;
          final color = pt == 'ALL' ? AppColors.ink : AppColors.pitchColor(pt);
          return GestureDetector(
            onTap: () => setState(() => _selected = pt),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? color : Colors.white,
                border: Border.all(color: color, width: 1.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(pt.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: on ? Colors.white : AppColors.colText)),
            ),
          );
        }

        grid = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [selChip('ALL'), for (final pt in pitchTypes) selChip(pt)],
            ),
          ),
          Center(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SizedBox(width: labelW, height: 22),
                for (var st = 0; st < 3; st++) head('$st ${st == 1 ? 'strike' : 'strikes'}'),
              ]),
              for (var b = 0; b < 4; b++)
                Row(children: [
                  rowHead(b),
                  for (var st = 0; st < 3; st++)
                    () {
                      final c = '$b-$st';
                      return sel == 'ALL'
                          ? ((countTotals[c] ?? 0) > 0 ? allCellFor(c) : emptySquare())
                          : cellFor(c, sel);
                    }(),
                ]),
            ]),
          ),
        ]);
      }

      // Key to the three strips inside every square, top to bottom.
      final key = Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(spacing: 14, runSpacing: 2, children: [
          const Text('Each square, top to bottom:', style: TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
          const Text('USAGE % (P = pitches)',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
          const Text('STRIKE %',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
          const Text('BAA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.colMuted)),
          Text(
            phone
                ? 'Pick a pitch above. Rows: balls · Columns: strikes (the count before the pitch). A dash = no pitch there.'
                : 'Rows: pitch types · Columns: counts (balls-strikes). Orange P = under 10 pitches.',
            style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted),
          ),
        ]),
      );

      final sized = SizedBox(width: phone ? constraints.maxWidth : tableW, child: grid);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        key,
        if (phone || tableW <= constraints.maxWidth)
          sized
        else
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: sized),
      ]);
    });
  }
}
