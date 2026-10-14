import 'package:flutter/material.dart';

/// The one place the SKOUTAR logo is drawn. Every screen uses this widget so
/// size, aspect ratio and treatment stay identical everywhere.
///
/// [height] is the height of the logo artwork itself (aspect ratio is always
/// preserved). With [framed] (default) the logo sits on a dark badge with a
/// soft orange glow, like the original neon artwork. The badge is drawn by
/// Flutter (not baked into the PNG), so it stays sharp at every size and
/// density. Set `framed: false` for the bare transparent logo.
class SkoutarLogo extends StatelessWidget {
  final double height;
  final bool framed;

  const SkoutarLogo({super.key, required this.height, this.framed = true});

  static const String asset = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (!framed) return image;
    final pad = height * 0.14;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height * 0.16 + 4),
        gradient: const RadialGradient(
          radius: 0.85,
          colors: [Color(0xFF3B1B0B), Color(0xFF140B07)],
        ),
        border: Border.all(color: const Color(0x59ED652A), width: 1),
        boxShadow: [
          BoxShadow(color: const Color(0x40ED652A), blurRadius: height * 0.22),
        ],
      ),
      child: image,
    );
  }
}
