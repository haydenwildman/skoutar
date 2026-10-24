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

/// Very light fill derived from a tier color.
Color subtleFill(Color tier) => Color.lerp(tier, Colors.white, 0.80)!;

/// Slightly stronger border derived from a tier color.
Color subtleBorder(Color tier) => Color.lerp(tier, Colors.white, 0.35)!;

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
/// * [description] - when set, hover (if [showOnHover]) or press-and-hold shows
///   it, followed by the color guide for [colorGuide].
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
  final String? title;
  final String? description;
  final String? colorGuide;
  final bool showOnHover;

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
    this.width = 68,
    this.title,
    this.description,
    this.colorGuide,
    this.showOnHover = false,
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
      padding: EdgeInsets.fromLTRB(accent == null ? 6 : 9, 5, 6, 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? AppColors.brandOrangeDeep : border,
          width: highlighted ? 2 : 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (label.isNotEmpty)
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: AppColors.colMuted, fontWeight: FontWeight.w700)),
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
      showOnHover: showOnHover,
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
/// column lines up from one game to the next. Cells never wrap or overlap; if
/// the table is wider than the space it is given (phones) it scrolls
/// sideways inside itself.
class BoxScoreTable extends StatelessWidget {
  final List<BoxScoreCol> cols;
  final double cellWidth;

  const BoxScoreTable({super.key, required this.cols, this.cellWidth = 54});

  Widget _cell(BoxScoreCol c) {
    final unavailable = c.value == kUnavailable;
    final graded = !unavailable && isGradedTier(c.tier);
    final cell = SizedBox(
      width: cellWidth,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.colBorder, width: 1.5)),
          ),
          child: Text(c.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(2, 4, 2, 0),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: graded ? subtleFill(c.tier!) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: graded ? Border.all(color: subtleBorder(c.tier!), width: 1) : null,
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
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [for (final c in cols) _cell(c)],
    );
    return LayoutBuilder(builder: (context, constraints) {
      final needed = cols.length * cellWidth;
      if (needed <= constraints.maxWidth) {
        return Align(alignment: Alignment.centerLeft, child: row);
      }
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
    });
  }
}
