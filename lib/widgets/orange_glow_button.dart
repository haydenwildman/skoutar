import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Look shared by every orange button: an orange border/edge, a soft faded
/// center that deepens toward the edge, and a faint orange glow for depth —
/// the same family as the pitch-type buttons (tinted card + colored border),
/// just in the brand orange. The text on it is dark so it stays readable.
BoxDecoration orangeGlowDecoration({double radius = 12, bool enabled = true}) {
  const c = AppColors.brandOrangeDeep;
  final a = enabled ? 1.0 : 0.45;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: c.withOpacity(a), width: 2),
    gradient: RadialGradient(
      center: Alignment.center,
      radius: 1.1,
      colors: [c.withOpacity(0.04 * a), c.withOpacity(0.20 * a)],
    ),
    boxShadow: [
      BoxShadow(
        color: c.withOpacity(0.16 * a),
        blurRadius: 10,
        spreadRadius: -2,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

/// Drop-in replacement for the theme's solid-orange [ElevatedButton]
/// (same `onPressed` / `child`, plus an optional leading [icon]). A null
/// [onPressed] shows the same faded, disabled look as before.
class OrangeGlowButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final EdgeInsetsGeometry padding;

  const OrangeGlowButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final textColor = enabled ? AppColors.colText : AppColors.colMuted;
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: orangeGlowDecoration(radius: 10, enabled: enabled),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: padding,
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: DefaultTextStyle.merge(
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textColor),
                  child: IconTheme.merge(
                    data: IconThemeData(color: AppColors.brandOrangeDeep, size: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[icon!, const SizedBox(width: 8)],
                        Flexible(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
