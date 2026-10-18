// Shared building blocks for the Bullpen and Pitching Analysis screens.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'bullpen_models.dart';

/// Canvas size ratio so 1 unit of x is as wide as 17in and 1 unit of y is
/// as tall as 24in (the visible window is 2.0 x 1.8 zone units).
const double zoneCanvasAspect =
    ((ZoneGeo.maxX - ZoneGeo.minX) * ZoneGeo.plateWidthIn) / ((ZoneGeo.maxY - ZoneGeo.minY) * ZoneGeo.zoneHeightIn);

class ZoneMarker {
  final double x, y;
  final Color color;
  final double radius;
  final bool ring; // outlined instead of filled
  const ZoneMarker(this.x, this.y, this.color, {this.radius = 6, this.ring = false});
}

class ZoneRect {
  final ZoneTarget target;
  final Color color;
  const ZoneRect(this.target, this.color);
}

class StrikeZonePainter extends CustomPainter {
  final List<ZoneRect> rects;
  final List<ZoneMarker> markers;
  const StrikeZonePainter({this.rects = const [], this.markers = const []});

  Offset _px(Size s, double x, double y) => Offset(
        (x - ZoneGeo.minX) / (ZoneGeo.maxX - ZoneGeo.minX) * s.width,
        (1 - (y - ZoneGeo.minY) / (ZoneGeo.maxY - ZoneGeo.minY)) * s.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(bg, Paint()..color = AppColors.tint);
    canvas.save();
    canvas.clipRRect(bg);

    final tl = _px(size, 0, 1), br = _px(size, 1, 0);
    final zone = Rect.fromPoints(tl, br);
    canvas.drawRect(zone, Paint()..color = Colors.white);

    // 3x3 grid inside the zone.
    final grid = Paint()
      ..color = AppColors.colBorder
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = zone.left + zone.width * i / 3;
      final y = zone.top + zone.height * i / 3;
      canvas.drawLine(Offset(x, zone.top), Offset(x, zone.bottom), grid);
      canvas.drawLine(Offset(zone.left, y), Offset(zone.right, y), grid);
    }
    canvas.drawRect(
      zone,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.ink
        ..strokeWidth = 2,
    );

    // Home plate under the zone.
    final pTop = _px(size, 0, -0.10), pBot = _px(size, 1, -0.10);
    final plate = Path()
      ..moveTo(pTop.dx, pTop.dy)
      ..lineTo(pBot.dx, pBot.dy)
      ..lineTo(pBot.dx, pBot.dy + zone.height * 0.07)
      ..lineTo((pTop.dx + pBot.dx) / 2, pBot.dy + zone.height * 0.14)
      ..lineTo(pTop.dx, pTop.dy + zone.height * 0.07)
      ..close();
    canvas.drawPath(plate, Paint()..color = Colors.white);
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.colMuted
        ..strokeWidth = 1.2,
    );

    for (final r in rects) {
      final a = _px(size, r.target.left, r.target.top);
      final b = _px(size, r.target.right, r.target.bottom);
      final rect = Rect.fromPoints(a, b);
      canvas.drawRect(rect, Paint()..color = r.color.withOpacity(0.22));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = r.color
          ..strokeWidth = 2,
      );
    }
    for (final m in markers) {
      final c = _px(size, m.x, m.y);
      if (m.ring) {
        canvas.drawCircle(
          c,
          m.radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = m.color
            ..strokeWidth = 2.5,
        );
      } else {
        canvas.drawCircle(c, m.radius, Paint()..color = m.color);
        canvas.drawCircle(
          c,
          m.radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white
            ..strokeWidth = 1.5,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StrikeZonePainter old) => true;
}

/// The strike-zone graphic. Pass [onPick] to make it tappable/draggable; the
/// callback receives zone coordinates (0..1 = inside the zone).
class StrikeZone extends StatelessWidget {
  final List<ZoneRect> rects;
  final List<ZoneMarker> markers;
  final void Function(double x, double y)? onPick;
  final double maxWidth;
  final String semanticsLabel;

  const StrikeZone({
    super.key,
    this.rects = const [],
    this.markers = const [],
    this.onPick,
    this.maxWidth = 340,
    this.semanticsLabel = 'Strike zone',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AspectRatio(
          aspectRatio: zoneCanvasAspect,
          child: LayoutBuilder(builder: (context, c) {
            final size = c.biggest;
            void pick(Offset p) {
              if (onPick == null) return;
              final x = ZoneGeo.minX + p.dx / size.width * (ZoneGeo.maxX - ZoneGeo.minX);
              final y = ZoneGeo.minY + (1 - p.dy / size.height) * (ZoneGeo.maxY - ZoneGeo.minY);
              onPick!(ZoneGeo.clampX(x), ZoneGeo.clampY(y));
            }

            return Semantics(
              label: semanticsLabel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: onPick == null ? null : (d) => pick(d.localPosition),
                onPanUpdate: onPick == null ? null : (d) => pick(d.localPosition),
                child: MouseRegion(
                  cursor: onPick == null ? MouseCursor.defer : SystemMouseCursors.precise,
                  child: CustomPaint(
                    size: size,
                    painter: StrikeZonePainter(rects: rects, markers: markers),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Width and height sliders (independent) plus quick size presets.
class TargetSizeControls extends StatelessWidget {
  final double width, height; // zone units
  final void Function(double w, double h) onChanged;
  const TargetSizeControls({super.key, required this.width, required this.height, required this.onChanged});

  static const double minSize = 0.10, maxSize = 1.0;
  static const presets = <String, double>{
    'Precise': 0.15,
    'Small': 0.25,
    'Medium': 0.40,
    'Large': 0.60,
    'Full zone': 1.0,
  };

  Widget _slider(String label, double value, String inches, ValueChanged<double> onC) {
    return Row(children: [
      SizedBox(
        width: 64,
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(minSize, maxSize).toDouble(),
          min: minSize,
          max: maxSize,
          divisions: 90,
          activeColor: AppColors.brandOrangeDeep,
          label: inches,
          semanticFormatterCallback: (_) => '$label $inches',
          onChanged: onC,
        ),
      ),
      SizedBox(
        width: 58,
        child: Text(inches,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final e in presets.entries)
          ChoiceChip(
            label: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            selected: (width - e.value).abs() < 0.001 && (height - e.value).abs() < 0.001,
            selectedColor: AppColors.brandOrangeDeep,
            labelStyle: TextStyle(
                color: (width - e.value).abs() < 0.001 && (height - e.value).abs() < 0.001 ? Colors.white : AppColors.ink),
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onChanged(e.value, e.value),
          ),
      ]),
      _slider('Width', width, '${(width * ZoneGeo.plateWidthIn).toStringAsFixed(1)} in',
          (v) => onChanged(v, height)),
      _slider('Height', height, '${(height * ZoneGeo.zoneHeightIn).toStringAsFixed(1)} in',
          (v) => onChanged(width, v)),
    ]);
  }
}

/// Small stat tile used on both screens: label, big value, optional note.
class BigStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  const BigStatCard({super.key, required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.colBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppColors.colMuted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: value == '—' ? AppColors.colMuted : AppColors.ink)),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(note!, style: const TextStyle(fontSize: 11, color: AppColors.colMuted)),
          ),
      ]),
    );
  }
}

/// A row of 2-3 stat cards that wraps nicely on phones.
class StatCardGrid extends StatelessWidget {
  final List<Widget> children;
  const StatCardGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final perRow = c.maxWidth < 420 ? 2 : (c.maxWidth < 700 ? 3 : 5);
      final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final ch in children) SizedBox(width: w, child: ch),
      ]);
    });
  }
}

/// Generic compact segmented control (same look as the Pitch Profiles tabs).
class SegmentedTabs<T> extends StatelessWidget {
  final List<T> values;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  const SegmentedTabs({
    super.key,
    required this.values,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.colBorder),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(children: [
        for (final v in values)
          Expanded(
            child: Semantics(
              button: true,
              selected: v == value,
              label: labelOf(v),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? AppColors.brandOrangeDeep : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(labelOf(v),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: v == value ? Colors.white : AppColors.ink)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Plots where misses landed RELATIVE to their target (center = on target).
/// Right = arm side, up = high, so it reads the same for lefties and righties.
class MissPlot extends StatelessWidget {
  /// (armSideInches, highInches) per pitch that had a target + landing.
  final List<Offset> offsets;
  final List<Color> colors;
  final Offset? mean;
  const MissPlot({super.key, required this.offsets, required this.colors, this.mean});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _MissPlotPainter(offsets, colors, mean)),
        ),
      ),
    );
  }
}

class _MissPlotPainter extends CustomPainter {
  final List<Offset> offsets;
  final List<Color> colors;
  final Offset? mean;
  _MissPlotPainter(this.offsets, this.colors, this.mean);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(bg, Paint()..color = AppColors.tint);
    var maxAbs = 12.0;
    for (final o in offsets) {
      if (o.dx.abs() > maxAbs) maxAbs = o.dx.abs();
      if (o.dy.abs() > maxAbs) maxAbs = o.dy.abs();
    }
    maxAbs = (maxAbs / 6).ceil() * 6.0;
    final c = size.center(Offset.zero);
    final scale = (size.width / 2 - 22) / maxAbs;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.colBorder
      ..strokeWidth = 1;
    for (var r = 6.0; r <= maxAbs; r += 6) {
      canvas.drawCircle(c, r * scale, ring);
    }
    final axis = Paint()
      ..color = AppColors.colMuted
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(c.dx, 14), Offset(c.dx, size.height - 14), axis);
    canvas.drawLine(Offset(14, c.dy), Offset(size.width - 14, c.dy), axis);

    void label(String t, Offset at) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label('HIGH', Offset(c.dx, 8));
    label('LOW', Offset(c.dx, size.height - 8));
    label('GLOVE', Offset(20, c.dy - 10));
    label('ARM', Offset(size.width - 16, c.dy - 10));
    label('${maxAbs.toStringAsFixed(0)} in', Offset(size.width - 26, size.height - 8));

    for (var i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      final p = Offset(c.dx + o.dx * scale, c.dy - o.dy * scale);
      canvas.drawCircle(p, 4.5, Paint()..color = colors[i].withOpacity(0.85));
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 1,
      );
    }
    // Target center.
    canvas.drawCircle(
      c,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.ink
        ..strokeWidth = 2,
    );
    if (mean != null) {
      final m = Offset(c.dx + mean!.dx * scale, c.dy - mean!.dy * scale);
      final x = Paint()
        ..color = AppColors.brandOrangeDeep
        ..strokeWidth = 3;
      canvas.drawLine(m + const Offset(-7, -7), m + const Offset(7, 7), x);
      canvas.drawLine(m + const Offset(-7, 7), m + const Offset(7, -7), x);
    }
  }

  @override
  bool shouldRepaint(_MissPlotPainter old) => true;
}

String fmtPct(double? v, {int digits = 0}) => v == null ? '—' : '${v.toStringAsFixed(digits)}%';
String fmtIn(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} in';
