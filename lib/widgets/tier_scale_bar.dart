import 'package:flutter/material.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';

/// Progress bar for a graded (tiered) stat. It shows where the value falls
/// on the stat's natural scale AND which way is good:
///
///  * LOWER is better (ERA, WHIP, BB%, AVG against ...): the 5 tier colors run
///    green -> red from LEFT to RIGHT, so the marker moving right is bad.
///  * HIGHER is better (K%, Whiff%, F-Strike% ...): red -> green from LEFT to
///    RIGHT, so the marker moving right is good.
///
/// Direction and tier cut-offs come from the same table [perfHex] uses
/// ([statLowerIsBetter] / [statTierCutoffFractions]); the marker's position is
/// the real value on a 0..max scale ([statValueFraction]; 0-100 for every
/// percentage). The solid fill always STARTS AT THE RED (poor) END and runs to
/// the marker, with the rest faded: for higher-is-better stats red is on the
/// left so it fills from the left; for lower-is-better stats red is on the
/// right so it fills from the right. The marker never moves.
class TierScaleBar extends StatelessWidget {
  final String statKey;
  final double? rawValue;
  final String valueText;

  /// Compact mode: a thin band + marker with no value chip (for small stat
  /// cells that already print the value themselves).
  final bool compact;

  const TierScaleBar({
    super.key,
    required this.statKey,
    required this.rawValue,
    required this.valueText,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final frac = statValueFraction(statKey, rawValue);
    final colors = statTierColorsLeftToRight(statKey);
    final cuts = statTierCutoffFractions(statKey);
    final tierColor = perfHex(statKey, rawValue);

    final bandH = compact ? 6.0 : 12.0;
    final chipH = compact ? 0.0 : 20.0;
    final dotD = compact ? 10.0 : 16.0;
    final totalH = compact ? dotD : chipH + 4 + dotD;

    return SizedBox(
      width: double.infinity,
      height: totalH,
      child: LayoutBuilder(builder: (context, constraints) {
        final track = constraints.maxWidth;
        final x = frac == null ? null : track * frac;
        final bandTop = totalH - dotD / 2 - bandH / 2;

        // Value chip: centered over the marker, kept fully inside the track.
        Widget? chip;
        if (!compact) {
          final wanted = valueText.length * 7.4 + 16;
          final chipW = (wanted < 30 ? 30.0 : wanted) > track ? track : (wanted < 30 ? 30.0 : wanted);
          final cx = x ?? 0;
          final left = (x == null ? 0.0 : cx - chipW / 2).clamp(0.0, (track - chipW).clamp(0.0, track)).toDouble();
          final textColor = _onTier(tierColor);
          chip = Positioned(
            left: left,
            top: 0,
            width: chipW,
            height: chipH,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: x == null ? AppColors.colBorder : tierColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                valueText,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: x == null ? AppColors.colMuted : textColor,
                ),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: bandTop,
              height: bandH,
              child: CustomPaint(
                painter: _BandPainter(
                  colors: colors,
                  cuts: cuts,
                  markerX: x,
                  radius: bandH / 2,
                  fromRight: statLowerIsBetter(statKey),
                ),
              ),
            ),
            if (x != null)
              Positioned(
                left: (x - dotD / 2).clamp(0.0, (track - dotD).clamp(0.0, track)).toDouble(),
                top: totalH - dotD,
                width: dotD,
                height: dotD,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tierColor,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                ),
              ),
            if (chip != null) chip,
          ],
        );
      }),
    );
  }

  static Color _onTier(Color bg) {
    if (bg == AppColors.perfExcellent ||
        bg == AppColors.perfPoor ||
        bg == AppColors.perfBelowAvg) {
      return Colors.white;
    }
    return AppColors.colText;
  }
}

/// Paints the five tier bands (left->right) between the stat's cut-offs:
/// solid between the red end and [markerX], faded on the other side. With
/// [fromRight] the red end is the right edge (lower-is-better stats).
class _BandPainter extends CustomPainter {
  final List<Color> colors; // 5, left -> right
  final List<double> cuts; // 4 ascending 0..1 boundaries
  final double? markerX;
  final double radius;
  final bool fromRight;

  _BandPainter({
    required this.colors,
    required this.cuts,
    required this.markerX,
    required this.radius,
    this.fromRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final edges = <double>[0, for (final c in cuts) c * w, w];
    for (var i = 0; i < 5; i++) {
      final l = edges[i];
      final r = edges[i + 1];
      if (r <= l) continue;
      final base = colors[i];
      final mx = markerX;
      if (mx == null) {
        canvas.drawRect(Rect.fromLTRB(l, 0, r, size.height), Paint()..color = base.withOpacity(0.3));
        continue;
      }
      // The part of this band between the marker and the red end is solid;
      // the part on the far side of the marker is faded.
      final leftPart = l < mx ? Rect.fromLTRB(l, 0, r < mx ? r : mx, size.height) : null;
      final rightPart = r > mx ? Rect.fromLTRB(l > mx ? l : mx, 0, r, size.height) : null;
      final solid = fromRight ? rightPart : leftPart;
      final faded = fromRight ? leftPart : rightPart;
      if (solid != null) canvas.drawRect(solid, Paint()..color = base);
      if (faded != null) canvas.drawRect(faded, Paint()..color = base.withOpacity(0.28));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.markerX != markerX ||
      old.colors != colors ||
      old.cuts != cuts ||
      old.radius != radius ||
      old.fromRight != fromRight;
}
