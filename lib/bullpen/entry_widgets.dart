// Pitch entry widgets shared by the live bullpen and the edit-pitch dialog.

import 'package:flutter/material.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import 'bullpen_models.dart';
import 'widgets.dart';

/// Pitch types the player can currently choose: only the ones they created
/// themselves on Game Input. There are no preset pitches.
List<String> availablePitchTypes(AppSession s) => [...s.customPitchTypes];

class PitchTypeChips extends StatelessWidget {
  final List<String> types;
  final String selected;
  final String Function(String) labelOf;
  final ValueChanged<String> onSelected;
  const PitchTypeChips({
    super.key,
    required this.types,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final t in types)
        ChoiceChip(
          label: Text(labelOf(t), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          selected: t == selected,
          selectedColor: AppColors.pitchColor(t),
          labelStyle: TextStyle(color: t == selected ? Colors.white : AppColors.ink),
          avatar: t == selected ? null : CircleAvatar(radius: 6, backgroundColor: AppColors.pitchColor(t)),
          onSelected: (_) => onSelected(t),
        ),
    ]);
  }
}

/// Zone + "Target / Landing" toggle + size sliders. Tapping the zone sets the
/// target center in Target mode and the landing spot in Landing mode.
class TargetLandingPicker extends StatelessWidget {
  final ZoneTarget target;
  final bool noTarget;
  final bool landingMode;
  final double? actualX, actualY;
  final List<ZoneMarker> trail;
  final Color pitchColor;
  final bool enabled;
  final ValueChanged<bool> onLandingMode;
  final ValueChanged<bool> onNoTarget;
  final ValueChanged<ZoneTarget> onTarget;
  final void Function(double x, double y) onLanding;

  const TargetLandingPicker({
    super.key,
    required this.target,
    required this.noTarget,
    required this.landingMode,
    required this.actualX,
    required this.actualY,
    this.trail = const [],
    required this.pitchColor,
    this.enabled = true,
    required this.onLandingMode,
    required this.onNoTarget,
    required this.onTarget,
    required this.onLanding,
  });

  @override
  Widget build(BuildContext ctx) {
    final marksLanding = landingMode || noTarget;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!noTarget)
        SegmentedTabs<bool>(
          values: const [false, true],
          value: landingMode,
          labelOf: (v) => v ? '2  Mark where it landed' : '1  Set your target',
          onChanged: enabled ? onLandingMode : (_) {},
        ),
      const SizedBox(height: 6),
      Text(
        noTarget
            ? 'No target for this pitch: tap where it landed.'
            : (landingMode
                ? 'Tap the spot where the pitch actually landed.'
                : 'Tap the zone to place your target. Drag to fine-tune.'),
        style: const TextStyle(fontSize: 12, color: AppColors.colMuted),
      ),
      const SizedBox(height: 6),
      StrikeZone(
        semanticsLabel: marksLanding ? 'Mark landing spot' : 'Place target',
        rects: [if (!noTarget) ZoneRect(target, AppColors.brandOrangeDeep)],
        markers: [
          ...trail,
          if (actualX != null && actualY != null) ZoneMarker(actualX!, actualY!, pitchColor, radius: 8),
        ],
        onPick: !enabled
            ? null
            : (x, y) {
                if (marksLanding) {
                  onLanding(x, y);
                } else {
                  onTarget(ZoneTarget(x, y, target.w, target.h));
                }
              },
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('No target for this pitch', style: TextStyle(fontSize: 13)),
        value: noTarget,
        activeColor: AppColors.brandOrangeDeep,
        onChanged: enabled ? onNoTarget : null,
      ),
      if (!noTarget)
        TargetSizeControls(
          width: target.w,
          height: target.h,
          onChanged: (w, h) {
            if (enabled) onTarget(ZoneTarget(target.x, target.y, w, h));
          },
        ),
    ]);
  }
}
