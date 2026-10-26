import 'package:flutter/material.dart';

import '../services/color_guides.dart';
import '../theme/app_theme.dart';
import 'stat_hold_info.dart';

/// Shared "subtle performance" look used by Game Logs and Pitch Sequencing.
///
/// A graded statistic is tinted with a washed-out version of the SKOUTAR
/// performance color (dark green / green / yellow / orange / red) that
/// `perfHex` (or one of the relationship color helpers) returned for it. The
/// number itself always stays dark and readable; the tint only helps you read
/// it. A statistic with no tier (a count, a usage share) or no data gets the
/// plain neutral look, never a performance color.

/// True when [c] is a real performance tier color (not the no-data gray or the
/// neutral tint that some helpers return for "ungraded").
bool isGradedTier(Color? c) => c != null && c != noDataGray && c != AppColors.tint;

/// Duller interior of the tier's own color (the border is the bright color).
Color subtleFill(Color tier) => ScaleStyle.fillAny(tier);

/// Bright border: the tier color itself.
Color subtleBorder(Color tier) => tier;

/// Value shown when a statistic has no eligible data. Never a zero.
const String kUnavailable = '—';

/// A small rounded box: label on top, value in the middle, optional detail
/// line under it (a sample size or a fraction such as "3/8").
///
/// * [tier] - performance color from the stat's own scale, or null for a
///   neutral box (counts, usage shares).
/// * [accent] - thin colored strip on the left edge, used to identify a pitch
///   type. It carries no performance meaning.
/// * [highlighted] - brand-colored border (e.g. the selected or most-used item).
/// * [description] - when set, press-and-hold shows it, followed by the color guide for [colorGuide].
class StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? tier;
  final Color? accent;
  final bool highlighted;

  /// Warm brand-tinted fill for the one statistic that should lead a group
  /// (e.g. Usage %). Not a performance color.
  final bool emphasis;
  final double valueSize;
  final double width;

  /// Every box in a grid has the same fixed size, so a long label or a missing
  /// sub-line never makes one box taller or wider than its neighbours.
  final double height;
  final String? title;
  final String? description;
  final String? colorGuide;

  const StatBox({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.tier,
    this.accent,
    this.highlighted = false,
    this.emphasis = false,
    this.valueSize = 14,
    this.width = 88,
    this.height = 66,
    this.title,
    this.description,
    this.colorGuide,
  });

  bool get _unavailable => value == kUnavailable;

  @override
  Widget build(BuildContext context) {
    final graded = !_unavailable && isGradedTier(tier);
    final fill = graded
        ? subtleFill(tier!)
        : (emphasis ? AppColors.tint : (_unavailable ? AppColors.surfaceAlt : Colors.white));
    final border = graded
        ? subtleBorder(tier!)
        : (emphasis ? AppColors.brandOrange.withOpacity(0.55) : AppColors.colBorder);

    Widget box = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: EdgeInsets.fromLTRB(accent == null ? 6 : 9, 4, 6, 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? AppColors.brandOrangeDeep : border,
          width: highlighted ? 2 : (graded ? 2 : 1.2),
        ),
      ),
      // The whole stack scales down if a font ever runs taller than the box,
      // so a fixed-size box can never overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (label.isNotEmpty)
            // Scales down instead of wrapping or cutting the label off.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 10, color: AppColors.colMuted, fontWeight: FontWeight.w700)),
            ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w800,
                  color: _unavailable ? AppColors.colMuted : AppColors.colText,
                )),
          ),
          if (sub != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(sub!,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.colMuted, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      ),
    );

    if (accent != null) {
      box = Stack(children: [
        box,
        Positioned(
          left: 3,
          top: 6,
          bottom: 6,
          width: 3,
          child: DecoratedBox(
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      ]);
    }

    if (description == null) return box;
    return StatHoldInfo(
      title: title ?? label,
      description: composeHoldInfo(what: description, colorGuide: colorGuide),
      child: box,
    );
  }
}

/// One column of a [BoxScoreTable].
class BoxScoreCol {
  final String label;
  final String value; // [kUnavailable] when there is no data
  final Color? tier; // null = plain (ungraded) cell
  final String title;
  final String what;
  final String? colorGuide;

  const BoxScoreCol({
    required this.label,
    required this.value,
    required this.title,
    required this.what,
    this.tier,
    this.colorGuide,
  });
}

/// A compact, aligned box-score table: a header row of short labels over one
/// row of values. Every cell has the same fixed [cellWidth], so the same
/// column lines up from one game to the next. Cells never wrap or overlap.
///
/// When the space it is given is narrower than the whole table (phones), the
/// columns are folded onto as few evenly filled lines as needed, each line a
/// header row over a value row, so the table fits the screen width with no
/// sideways scrolling and every column keeps its header and value.
class BoxScoreTable extends StatelessWidget {
  final List<BoxScoreCol> cols;
  final double cellWidth;

  const BoxScoreTable({super.key, required this.cols, this.cellWidth = 54});

  /// Narrowest a folded cell may get; below this a value would be cramped.
  static const double _minFoldedCell = 40;

  Widget _cell(BoxScoreCol c, double width) {
    final unavailable = c.value == kUnavailable;
    final graded = !unavailable && isGradedTier(c.tier);
    final cell = SizedBox(
      width: width,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.colBorder, width: 1.5)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(c.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
          ),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(2, 4, 2, 0),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: graded ? subtleFill(c.tier!) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: graded ? Border.all(color: subtleBorder(c.tier!), width: 2) : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(c.value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: unavailable ? AppColors.colMuted : AppColors.colText,
                )),
          ),
        ),
      ]),
    );
    return StatHoldInfo(
      title: c.title,
      description: composeHoldInfo(what: c.what, colorGuide: c.colorGuide),
      child: cell,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final needed = cols.length * cellWidth;
      if (needed <= constraints.maxWidth) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [for (final c in cols) _cell(c, cellWidth)],
          ),
        );
      }
      // Fold onto evenly filled lines that fit the width.
      final maxPerLine = (constraints.maxWidth / _minFoldedCell).floor().clamp(1, cols.length);
      final lines = (cols.length / maxPerLine).ceil();
      final perLine = (cols.length / lines).ceil();
      final width = (constraints.maxWidth / perLine).floorToDouble().clamp(_minFoldedCell, cellWidth).toDouble();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cols.length; i += perLine) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in cols.skip(i).take(perLine)) _cell(c, width),
              ],
            ),
          ],
        ],
      );
    });
  }
}
