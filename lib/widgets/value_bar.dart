import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A horizontal bar whose filled portion is EXACTLY [fraction] of the track
/// (so 25% fills a quarter and 100% fills it all) and which shows [text].
///
/// When the fill is wide enough the label sits inside it. When it is too
/// narrow to hold the label (a small value on a short track) the fill keeps
/// its true length and the label is drawn just past the end of the fill, on
/// the track — the label never spills out of the bar and the bar length is
/// never distorted to make room for it.
class ValueBar extends StatelessWidget {
  /// 0..1 share of the track to fill.
  final double fraction;
  final Color color;
  final String text;
  final Color textColor;
  final double height;
  final double fontSize;
  final double radius;

  /// Optional overlay drawn on top of the track (e.g. tier key dots). Receives
  /// the track width.
  final Widget Function(double trackWidth)? overlay;

  const ValueBar({
    super.key,
    required this.fraction,
    required this.color,
    required this.text,
    this.textColor = Colors.white,
    this.height = 26,
    this.fontSize = 13,
    this.radius = 8,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: LayoutBuilder(builder: (context, constraints) {
        final track = constraints.maxWidth;
        final frac = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
        // Rough label width: bold digits/letters ~0.62em, plus side padding.
        final need = text.isEmpty ? 0.0 : text.length * fontSize * 0.62 + 20;
        final fill = (track * frac).clamp(0.0, track).toDouble();
        final labelInside = fill >= need;
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.colBorder,
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            if (fill > 0)
              SizedBox(
                width: fill < 3 ? 3 : fill,
                height: height,
                child: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: (labelInside && text.isNotEmpty)
                      ? Text(
                          text,
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: textColor),
                        )
                      : null,
                ),
              ),
            if (!labelInside && text.isNotEmpty)
              Positioned(
                left: fill + 6,
                right: 4,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: AppColors.colText),
                  ),
                ),
              ),
            if (overlay != null) overlay!(track),
          ],
        );
      }),
    );
  }
}
