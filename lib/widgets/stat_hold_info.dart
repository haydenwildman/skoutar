import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'glow.dart';

/// Wraps a stat so that PRESSING AND HOLDING it shows the stat's
/// explanation, and releasing dismisses it. Replaces the old "i" buttons.
///
/// * Uses Flutter's built-in long-press recognizer, which handles both a
///   held mouse button (desktop / web) and a held touch (iPhone / Android).
/// * Only long-press callbacks are registered, so normal taps still reach
///   whatever the child (or an ancestor) does with them, and vertical /
///   horizontal drags still scroll. Moving past the touch slop before the
///   hold completes cancels the gesture, so scrolling is never blocked.
/// * The popup is drawn in the app [Overlay] inside an [IgnorePointer], and
///   is clamped to the visible area (safe-area aware) so it can never run
///   off the edge of a phone or create horizontal overflow. It opens above
///   the stat when there is room, otherwise below.
///
/// When [description] is null the child is returned untouched.
class StatHoldInfo extends StatefulWidget {
  final String title;
  final String? description;
  final Widget child;

  /// Also show the explanation while a mouse pointer hovers over the stat
  /// (desktop / web). Press-and-hold keeps working everywhere, including
  /// touch screens, where there is no hover.
  final bool showOnHover;

  const StatHoldInfo({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.showOnHover = false,
  });

  @override
  State<StatHoldInfo> createState() => _StatHoldInfoState();
}

class _StatHoldInfoState extends State<StatHoldInfo> {
  OverlayEntry? _entry;

  void _show() {
    if (_entry != null || widget.description == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Target rectangle in the overlay's (global) coordinate space.
    final topLeft = box.localToGlobal(Offset.zero);
    final target = topLeft & box.size;
    final media = MediaQuery.of(context);
    final title = widget.title;
    final description = widget.description!;

    HapticFeedback.selectionClick();
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: SizedBox.expand(
          child: _StatInfoPopup(
            target: target,
            media: media,
            title: title,
            description: description,
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.description == null) return widget.child;
    return MouseRegion(
      // Subtle desktop hint that the stat can be held for an explanation.
      cursor: SystemMouseCursors.help,
      onEnter: widget.showOnHover ? (_) => _show() : null,
      onExit: widget.showOnHover ? (_) => _hide() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (_) => _show(),
        onLongPressEnd: (_) => _hide(),
        onLongPressCancel: _hide,
        child: widget.child,
      ),
    );
  }
}

class _StatInfoPopup extends StatelessWidget {
  final Rect target;
  final MediaQueryData media;
  final String title;
  final String description;

  const _StatInfoPopup({
    required this.target,
    required this.media,
    required this.title,
    required this.description,
  });

  static final RegExp _swatch = RegExp(r'^\{c:([0-9A-Fa-f]{8})\}\s?(.*)$');
  // Explanatory/supporting copy: Teko italic (the popup sits in an Overlay,
  // so the family is set explicitly rather than relying on inheritance).
  static const TextStyle _bodyStyle = TextStyle(
    fontFamily: AppFonts.family,
    fontStyle: FontStyle.italic,
    fontSize: 13,
    height: 1.35,
    color: AppColors.colText,
  );

  /// Renders the description line by line: `## Heading`, `{c:AARRGGBB} text`
  /// (color swatch + text) and plain text. A description with none of these
  /// markers renders exactly as plain text, as before.
  static List<Widget> _body(String description) {
    final out = <Widget>[];
    for (final line in description.split('\n')) {
      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 5));
        continue;
      }
      final m = _swatch.firstMatch(line);
      if (m != null) {
        final color = Color(int.parse(m.group(1)!, radix: 16));
        out.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.black26, width: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(child: Text(m.group(2)!, style: _bodyStyle)),
            ],
          ),
        ));
      } else if (line.startsWith('## ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            line.substring(3),
            style: const TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.brandOrangeDeep,
            ),
          ),
        ));
      } else {
        out.add(Text(line, style: _bodyStyle));
      }
    }
    return out;
  }

  static const double _margin = 12;
  static const double _gap = 8;
  static const double _maxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final safe = media.padding;
    final availW = media.size.width - safe.left - safe.right - _margin * 2;
    final width = availW < _maxWidth ? availW : _maxWidth;

    return CustomSingleChildLayout(
        delegate: _PopupLayout(
          target: target,
          safe: safe,
          size: media.size,
          margin: _margin,
          gap: _gap,
        ),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: (media.size.height - safe.top - safe.bottom) * 0.85,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandOrangeDeep.withOpacity(0.5)),
                boxShadow: AppGlow.shadows,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._body(description),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}

/// Centers the popup on the stat horizontally, then clamps it inside the
/// visible (safe) area. Prefers sitting above the stat; flips below when
/// there isn't room, and as a last resort is pinned inside the screen.
class _PopupLayout extends SingleChildLayoutDelegate {
  final Rect target;
  final EdgeInsets safe;
  final Size size;
  final double margin;
  final double gap;

  _PopupLayout({
    required this.target,
    required this.safe,
    required this.size,
    required this.margin,
    required this.gap,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(size);

  @override
  Offset getPositionForChild(Size _, Size child) {
    final minX = safe.left + margin;
    final maxX = size.width - safe.right - margin - child.width;
    var x = target.center.dx - child.width / 2;
    x = maxX < minX ? minX : x.clamp(minX, maxX).toDouble();

    final minY = safe.top + margin;
    final maxY = size.height - safe.bottom - margin - child.height;

    final above = target.top - gap - child.height;
    final below = target.bottom + gap;
    double y;
    if (above >= minY) {
      y = above;
    } else if (below <= maxY) {
      y = below;
    } else {
      // Neither fits cleanly (very tall stat / small window): keep it on
      // screen, on whichever side has more room.
      final roomAbove = target.top - minY;
      final roomBelow = maxY + child.height - target.bottom;
      y = roomBelow > roomAbove ? maxY : minY;
    }
    y = maxY < minY ? minY : y.clamp(minY, maxY).toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopupLayout old) =>
      old.target != target || old.safe != safe || old.size != size;
}
