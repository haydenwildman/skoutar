import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/pitch_event.dart';

/// Recreates the R app's `draw_field()` ggplot: a green outfield/infield
/// wedge with foul lines, a home-plate arc, bases, and a mound — plus the
/// FILL/RING legend text. Field coordinates use the same coordinate system
/// as the R version: home plate at (0,0), foul lines at 45°/135°, outfield
/// wall radius ~330.
class BaseballFieldPainter extends CustomPainter {
  final List<PitchEvent> sprayPoints;
  final double? highlightX;
  final double? highlightY;

  BaseballFieldPainter({
    required this.sprayPoints,
    this.highlightX,
    this.highlightY,
  });

  // Field-space bounds matching R: xlim(-400,400), ylim(-80,400)
  static const double fieldMinX = -400, fieldMaxX = 400;
  static const double fieldMinY = -80, fieldMaxY = 400;

  // Home plate's actual position within assets/images/field_bg.png, as a
  // fraction of the image's width/height. Measured directly from the image
  // (it isn't exactly at field-space (0,0) — the plate sits low in the
  // frame, near fieldMinY) so trajectory lines start precisely on the
  // plate instead of a few dozen units above it.
  static const double _homePlateFracX = 0.4992;
  static const double _homePlateFracY = 0.9522;

  Offset _homePlate(Size size) =>
      Offset(_homePlateFracX * size.width, _homePlateFracY * size.height);

  Offset _toCanvas(double fx, double fy, Size size) {
    final nx = (fx - fieldMinX) / (fieldMaxX - fieldMinX);
    final ny = (fy - fieldMinY) / (fieldMaxY - fieldMinY);
    return Offset(nx * size.width, size.height - ny * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The field itself (grass, dirt, foul lines, bases, mound, branded
    // watermark) is now supplied by the branded field-photo background —
    // see SprayFieldSurface below, which paints assets/images/field_bg.png
    // behind this CustomPaint. This painter only draws what's plotted on
    // top of it: trajectories and spray points.

    // Ball trajectories, drawn before the points themselves so the dots sit
    // on top. Ground balls get a dotted line (skips along the dirt), line
    // drives get a straight solid line (the flattest, fastest path), and
    // fly balls get a looping arc (the highest, slowest path) — matching
    // the R app's geom_segment(dashed)/geom_segment(solid)/geom_curve.
    final home = _homePlate(size);
    for (final p in sprayPoints) {
      if (p.xCoord == null || p.yCoord == null || p.battedType == null) continue;
      final end = _toCanvas(p.xCoord!, p.yCoord!, size);
      final trajPaint = Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      switch (p.battedType) {
        case 'gb':
          _drawDottedLine(canvas, home, end, trajPaint);
          break;
        case 'ld':
          canvas.drawLine(home, end, trajPaint);
          break;
        case 'fb':
          _drawArc(canvas, home, end, trajPaint);
          break;
      }
    }

    // Spray points
    for (final p in sprayPoints) {
      if (p.xCoord == null || p.yCoord == null) continue;
      final pos = _toCanvas(p.xCoord!, p.yCoord!, size);
      final ringColor = AppColors.pitchColor(p.pitchType);
      final ringPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      // Fill color comes straight from sprayColor(), which already maps
      // every out outcome (go/fo/lo/dp) to the same consistent red — so
      // outs are immediately recognizable at a glance, no letter needed.
      final fillColor = AppColors.sprayColor(p.outcome);
      final fillPaint = Paint()..color = fillColor.withOpacity(0.9);
      canvas.drawCircle(pos, 7, fillPaint);
      canvas.drawCircle(pos, 7, ringPaint);
    }

    // Highlighted/marking dot (used by the game-input spray modal)
    if (highlightX != null && highlightY != null) {
      final pos = _toCanvas(highlightX!, highlightY!, size);
      final glowPaint = Paint()..color = const Color(0xFFF1C40F);
      canvas.drawCircle(pos, 9, glowPaint);
      canvas.drawCircle(
        pos,
        9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _drawDottedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 5.0, gapLength = 4.0;
    final total = (end - start).distance;
    if (total == 0) return;
    final direction = (end - start) / total;
    double covered = 0;
    while (covered < total) {
      final segStart = start + direction * covered;
      final segEndDist = (covered + dashLength) > total ? total : (covered + dashLength);
      final segEnd = start + direction * segEndDist;
      canvas.drawLine(segStart, segEnd, paint);
      covered += dashLength + gapLength;
    }
  }

  void _drawArc(Canvas canvas, Offset start, Offset end, Paint paint) {
    // A gentle looping arc from home plate out to the landing spot —
    // approximates a fly ball's high, slow flight path (vs. a line
    // drive's flat straight shot or a ground ball's skipping path).
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final dx = end.dx - start.dx, dy = end.dy - start.dy;
    // Perpendicular offset, scaled to the shot distance, to bow the arc.
    final perp = Offset(-dy, dx);
    final perpLen = perp.distance;
    final bow = perpLen == 0 ? Offset.zero : (perp / perpLen) * ((end - start).distance * 0.18);
    final control = mid + bow;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BaseballFieldPainter oldDelegate) {
    return oldDelegate.sprayPoints != sprayPoints ||
        oldDelegate.highlightX != highlightX ||
        oldDelegate.highlightY != highlightY;
  }
}

/// The branded field background (assets/images/field_bg.png — an aerial
/// diamond shot with the SKOUTAR logo watermarked into the
/// outfield grass) plus the [BaseballFieldPainter] on top of it. This is
/// the one shared "spray chart surface" used everywhere hits/pitches get
/// plotted onto a field, so every screen looks and behaves the same way.
///
/// [onTapDown] is forwarded from a [GestureDetector] wrapping the whole
/// surface, for screens (Game Input, Edit At-Bats) that let the user tap
/// the field to place a hit.
class SprayFieldSurface extends StatelessWidget {
  final List<PitchEvent> sprayPoints;
  final double? highlightX;
  final double? highlightY;
  final void Function(TapDownDetails)? onTapDown;

  const SprayFieldSurface({
    super.key,
    required this.sprayPoints,
    this.highlightX,
    this.highlightY,
    this.onTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final field = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/field_bg.png', fit: BoxFit.cover),
          CustomPaint(
            painter: BaseballFieldPainter(
              sprayPoints: sprayPoints,
              highlightX: highlightX,
              highlightY: highlightY,
            ),
            child: Container(),
          ),
        ],
      ),
    );
    if (onTapDown == null) return field;
    return GestureDetector(onTapDown: onTapDown, child: field);
  }
}

/// Converts a tap position inside the field widget back into field-space
/// coordinates — the inverse of `BaseballFieldPainter._toCanvas`.
class FieldCoordConverter {
  static Offset canvasToField(Offset local, Size size) {
    final nx = local.dx / size.width;
    final ny = 1 - (local.dy / size.height);
    final fx = BaseballFieldPainter.fieldMinX +
        nx * (BaseballFieldPainter.fieldMaxX - BaseballFieldPainter.fieldMinX);
    final fy = BaseballFieldPainter.fieldMinY +
        ny * (BaseballFieldPainter.fieldMaxY - BaseballFieldPainter.fieldMinY);
    return Offset(fx, fy);
  }
}
