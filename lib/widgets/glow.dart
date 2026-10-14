import 'package:flutter/material.dart';

/// SKOUTAR's soft orange glow, shared so every panel uses the identical
/// treatment. Apply it to panels/cards only — not to buttons, inputs, chips,
/// chart cells or data colours.
class AppGlow {
  AppGlow._();

  /// Two soft layers: a tighter halo plus a wide, faint bloom.
  static const List<BoxShadow> shadows = [
    BoxShadow(color: Color(0x2EED652A), blurRadius: 14),
    BoxShadow(color: Color(0x14ED652A), blurRadius: 30),
  ];

  /// Same glow, slightly stronger — for overlays/dialogs that float above
  /// the page and sit on a dark scrim.
  static const List<BoxShadow> shadowsRaised = [
    BoxShadow(color: Color(0x47ED652A), blurRadius: 18),
    BoxShadow(color: Color(0x24ED652A), blurRadius: 40),
  ];
}

/// Drop-in replacement for [Card] that adds [AppGlow.shadows]. Same
/// parameters as the Card it replaces; the card's own shape, border,
/// margin and elevation still come from the theme.
class GlowCard extends StatelessWidget {
  final Widget? child;
  final Color? color;
  final double? elevation;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? margin;
  final Clip? clipBehavior;

  const GlowCard({
    super.key,
    this.child,
    this.color,
    this.elevation,
    this.shape,
    this.margin,
    this.clipBehavior,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).cardTheme;
    final ShapeBorder? s = shape ?? theme.shape;
    var radius = BorderRadius.circular(12);
    if (s is RoundedRectangleBorder && s.borderRadius is BorderRadius) {
      radius = s.borderRadius as BorderRadius;
    }
    // The glow wrapper takes over the card's margin so the halo hugs the
    // card itself, not the empty margin around it.
    final outer = margin ?? theme.margin ?? const EdgeInsets.all(4);
    return Padding(
      padding: outer,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: AppGlow.shadows),
        child: Card(
          margin: EdgeInsets.zero,
          color: color,
          elevation: elevation,
          shape: shape,
          clipBehavior: clipBehavior,
          child: child,
        ),
      ),
    );
  }
}
