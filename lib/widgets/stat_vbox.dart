import '../services/color_guides.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'tier_scale_bar.dart';
import 'value_bar.dart';
import '../services/stats_service.dart' show statHasScale, perfHex;
import 'stat_hold_info.dart';
import '../utils/responsive.dart' show Breakpoints;

/// Port of the R app's `.stat-vbox` / `mk_vb()` helper: a colored box
/// with a small uppercase label and a large bold value. If [description]
/// is provided, pressing and holding the box shows an explanation of what
/// the stat means (released = dismissed); see [StatHoldInfo].
class StatVBox extends StatelessWidget {
  final String label;
  final String value;
  final Color background;
  final Color textColor;
  final String? description;

  /// When true, renders with tighter padding and smaller type — used on
  /// screens like Pitch Breakdown where many boxes are shown at once and
  /// the default sizing leaves a lot of empty color around each value.
  final bool compact;

  /// [perfHex] stat key this box's [background] was graded with; when set, the
  /// hold popup lists that stat's exact color cutoffs.
  final String? statKey;

  /// Pre-built "Color Guide" text for boxes whose color isn't a plain
  /// [statKey] ladder (relationship colors, fixed highlight colors).
  final String? colorGuide;

  /// One extra clarifying line added to the generated [statKey] guide.
  final String? colorNote;

  const StatVBox({
    super.key,
    required this.label,
    required this.value,
    this.background = AppColors.tint,
    this.textColor = AppColors.colText,
    this.description,
    this.compact = false,
    this.statKey,
    this.colorGuide,
    this.colorNote,
  });

  String? get _holdText {
    String? guide = colorGuide;
    if (guide == null && statKey != null) {
      final g = statColorGuide(statKey!, note: colorNote);
      if (g.isNotEmpty) guide = g;
    }
    if (guide == null) return description;
    return composeHoldInfo(what: description, colorGuide: guide);
  }

  @override
  Widget build(BuildContext context) {
    final vPad = compact ? 5.0 : 8.0;
    final hPad = compact ? 5.0 : 6.0;
    final labelSize = compact ? 8.5 : 10.0;
    final valueSize = compact ? 14.0 : 18.0;
    final gap = compact ? 1.0 : 3.0;
    final textColor = ScaleStyle.isTier(background) ? ScaleStyle.textOn(background) : this.textColor;

    return StatHoldInfo(
      title: label,
      description: _holdText,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
        decoration: ScaleStyle.box(background, radius: compact ? 7 : 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: labelSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: textColor.withOpacity(0.85),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: gap),
            Text(
              value,
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal progress bar for one stat.
///
/// Graded stats (pass [statKey] + [rawValue], the same key used for
/// [perfHex]) render a [TierScaleBar]: a marker at the value's true position
/// on the stat's scale (0-100 for percentages) over the five tier colors,
/// ordered so the GOOD end is green - on the LEFT for lower-is-better stats
/// (ERA, WHIP, BB%, ...) and on the RIGHT for higher-is-better ones (K%,
/// Whiff%, ...). Plain counts (PA, IP, ...) keep a neutral full bar.
class PerfStatBar extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? description;

  /// Raw numeric value behind [value] (e.g. 3.62 for an ERA shown as
  /// "3.62"), used together with [statKey] to place the bar continuously
  /// within its color tier instead of snapping to a fixed tier length.
  final double? rawValue;

  /// The [perfHex] stat key (e.g. 'ERA', 'K_pct') that [color] and
  /// [rawValue] were computed from. Leave null for plain counts that
  /// aren't performance-graded.
  final String? statKey;

  /// Short benchmark text (e.g. "Elite 30%+ · Poor ≤10%") shown under the
  /// bar so the value can be judged against a typical scale, not just
  /// read in isolation. Pass `StatsService.statScaleHint(statKey)`, or
  /// leave null for plain counts (PA, IP, etc.) that have no benchmark.
  final String? scaleHint;

  /// One extra clarifying line added to the generated color guide (e.g. when
  /// the bar borrows another stat's scale).
  final String? colorNote;

  const PerfStatBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.description,
    this.rawValue,
    this.statKey,
    this.scaleHint,
    this.colorNote,
  });

  String? _holdText(bool graded) {
    if (graded) {
      final t = composeHoldInfo(
        what: description,
        colorGuide: statColorGuide(statKey!, bar: true, note: colorNote),
      );
      return t.isEmpty ? null : t;
    }
    if (description == null) return null;
    if (color == AppColors.tint) {
      return composeHoldInfo(
        what: description,
        colorGuide: swatchLine(AppColors.brandOrangeDeep,
            'Orange bar: a plain count. The bar is always full and the color is not a good/bad grade, so there are no cutoffs.'),
      );
    }
    return description;
  }

  @override
  Widget build(BuildContext context) {
    final graded = statHasScale(statKey);
    // Plain/unrated counts use the neutral tint fill - render the bar itself
    // in the stronger brand orange so it's visible against the track.
    final barColor = color == AppColors.tint ? AppColors.brandOrangeDeep : color;

    return StatHoldInfo(
      title: label,
      description: _holdText(graded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: small stat name on the left, the ACTUAL value large
            // and bold on the right.
            StatHeaderRow(label: label, value: value),
            const SizedBox(height: 6),
            // Graded stat: tier-colored scale with a marker at the real value.
            // Plain counts: neutral full bar (no text inside - the number
            // lives in the header row).
            if (graded)
              TierScaleBar(statKey: statKey!, rawValue: rawValue, valueText: value)
            else
              ValueBar(
                fraction: 1.0,
                color: barColor,
                text: '',
                height: 12,
                radius: 6,
              ),
            if (scaleHint != null) ...[
              const SizedBox(height: 4),
              Text(
                scaleHint!,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.colMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Primary-number font size shared by every progress bar: 28px on desktop,
/// stepping down on tablets and phones so the number stays prominent without
/// overflowing. [compact] is for dense grids (e.g. the Game Input mini cells).
double statValueFontSize(BuildContext context, {bool compact = false}) {
  final w = MediaQuery.sizeOf(context).width;
  if (compact) return w < Breakpoints.phone ? 16 : 18;
  if (w < Breakpoints.phone) return 22;
  if (w < Breakpoints.drawer) return 26;
  return 28;
}

/// The standard header row above a progress bar:
///
///   STAT NAME                                   ACTUAL VALUE
///
/// The name is small and muted; the real statistic is large, bold, and
/// high-contrast. The value scales down (never wraps or clips) if the row is
/// narrow, and a long name ellipsizes instead of colliding with the value.
class StatHeaderRow extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  const StatHeaderRow({super.key, required this.label, required this.value, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final hasValue = value != 'N/A' && value.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12.5 : 15.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              height: 1.15,
              color: AppColors.ink,
              decoration: TextDecoration.underline,
              decorationThickness: 1.6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: statValueFontSize(context, compact: compact),
                fontWeight: FontWeight.w900,
                height: 1.1,
                color: hasValue ? AppColors.ink : AppColors.colMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact summary card: small stat label, a large bold value, and a subtle
/// performance strip along the bottom in the stat's existing tier color
/// (graded with the same [perfHex] key as everywhere else). Press and hold
/// shows the same "What This Means" + "Color Guide" as the other stats.
class StatSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String statKey;
  final double? rawValue;
  final String? description;

  const StatSummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.statKey,
    required this.rawValue,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = rawValue != null && value != 'N/A';
    final tier = perfHex(statKey, rawValue);
    final guide = statColorGuide(statKey);
    return StatHoldInfo(
      title: label,
      description: guide.isEmpty ? description : composeHoldInfo(what: description, colorGuide: guide),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.tint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.colBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: AppColors.colMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: statValueFontSize(context),
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        color: hasValue ? AppColors.ink : AppColors.colMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 5, color: hasValue ? tier : AppColors.colBorder),
          ],
        ),
      ),
    );
  }
}

/// Reusable "what do the colors mean" key for any screen that uses the
/// 5-tier perf_hex color coding (green → yellow → orange → red).
/// Drop `const PerfTierLegend()` into a Filter card on any stats screen.
class PerfTierLegend extends StatelessWidget {
  const PerfTierLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget chip(int tier, String label, Color color, String name, {Color textColor = Colors.white}) {
      final k = statTierLines('K_pct');
      final era = statTierLines('ERA');
      final idx = 4 - tier;
      return StatHoldInfo(
        title: '$label tier',
        description: composeHoldInfo(
          what: 'Every graded stat in the app is sorted into one of these 5 tiers and colored to match. '
              'The cutoffs are different for each stat, so press and hold the colored stat itself for its exact numbers.',
          colorGuide: 'This color means "$name".\n'
              'Example - K% (higher is better):\n${idx < k.length ? k[idx] : ''}\n'
              'Example - ERA (lower is better):\n${idx < era.length ? era[idx] : ''}',
        ),
        child: LegendChip(label: label, color: color, textColor: textColor),
      );
    }

    return Wrap(spacing: 6, runSpacing: 6, children: [
      chip(4, '5 – Excellent', AppColors.perfExcellent, 'Excellent'),
      chip(3, '4 – Good', AppColors.perfGood, 'Good'),
      chip(2, '3 – Avg', AppColors.perfAverage, 'Average', textColor: AppColors.colText),
      chip(1, '2 – Below', AppColors.perfBelowAvg, 'Below average'),
      chip(0, '1 – Poor', AppColors.perfPoor, 'Poor'),
    ]);
  }
}

/// Small colored legend chip, e.g. "5 – Excellent" swatches.
class LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  const LegendChip({
    super.key,
    required this.label,
    required this.color,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}
