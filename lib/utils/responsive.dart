import 'package:flutter/material.dart';

/// Layout breakpoints used across the app.
///
/// The app already switched from a persistent sidebar to a drawer below
/// 900px (see HomeShell), so that value is kept as [drawer] rather than
/// being replaced by a different number.
class Breakpoints {
  /// Below this width the layout is treated as a phone (iPhone / Android).
  static const double phone = 600;

  /// Below this width the persistent sidebar becomes a slide-out drawer.
  static const double drawer = 900;

  /// Default CONTENT width (not screen width) below which a side-by-side
  /// pair of cards is stacked vertically. Measured against the space the
  /// widget is actually given, so it behaves correctly whether or not a
  /// sidebar is taking up room.
  static const double splitContent = 640;
}

class Responsive {
  const Responsive._();

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isPhone(BuildContext context) => width(context) < Breakpoints.phone;

  static bool useDrawer(BuildContext context) => width(context) < Breakpoints.drawer;

  /// Outer padding around every screen's content.
  static double pagePadding(BuildContext context) => isPhone(context) ? 8 : 12;

  /// Width for a dialog's content: [desired] on large screens, but never
  /// wider than what actually fits on a small one (allowing for the
  /// dialog's own inset + content padding).
  static double dialogWidth(BuildContext context, double desired) {
    final max = width(context) - 96;
    if (max >= desired) return desired;
    return max < 200 ? 200 : max;
  }
}

/// Drop-in replacement for a `Row` of `Expanded` cards / boxes.
///
/// When the space it is given is at least [breakpoint] wide it builds the
/// original `Row` untouched, so desktop output is identical. When narrower,
/// it unwraps the `Expanded`/`Flexible` children, drops the horizontal
/// spacer `SizedBox`es and rearranges them:
///
///  * [stackedColumns] == 1 (default): one full-width item per row.
///  * [stackedColumns] > 1: a grid with that many equal columns (for small
///    stat boxes that should wrap 3-across instead of stacking).
///
/// The breakpoint is measured against the width the widget is actually
/// given (LayoutBuilder), not the screen, so it behaves the same whether or
/// not a sidebar is taking up room.
class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final double stackedGap;
  final int stackedColumns;
  final CrossAxisAlignment crossAxisAlignment;

  /// Cross-axis alignment used when the items are stacked vertically.
  final CrossAxisAlignment stackedCrossAxisAlignment;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.breakpoint = Breakpoints.splitContent,
    this.stackedGap = 0,
    this.stackedColumns = 1,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.stackedCrossAxisAlignment = CrossAxisAlignment.stretch,
  });

  List<Widget> _items() => [
        for (final c in children)
          if (c is Flexible)
            c.child
          else if (c is SizedBox && c.child == null)
            ...const <Widget>[] // horizontal spacer: not needed when stacked
          else
            c,
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= breakpoint) {
        return Row(crossAxisAlignment: crossAxisAlignment, children: children);
      }

      final items = _items();

      if (stackedColumns <= 1) {
        return Column(
          crossAxisAlignment: stackedCrossAxisAlignment,
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0 && stackedGap > 0) SizedBox(height: stackedGap),
              items[i],
            ],
          ],
        );
      }

      const colGap = 6.0;
      final rows = <Widget>[];
      for (int start = 0; start < items.length; start += stackedColumns) {
        if (rows.isNotEmpty) rows.add(SizedBox(height: stackedGap > 0 ? stackedGap : colGap));
        rows.add(Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            for (int j = 0; j < stackedColumns; j++) ...[
              if (j > 0) const SizedBox(width: colGap),
              Expanded(
                child: start + j < items.length ? items[start + j] : const SizedBox.shrink(),
              ),
            ],
          ],
        ));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}
