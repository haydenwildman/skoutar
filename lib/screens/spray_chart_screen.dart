import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pitch_event.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/baseball_field_painter.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import '../widgets/year_filter_dropdown.dart';

class SprayChartScreen extends StatefulWidget {
  const SprayChartScreen({super.key});

  @override
  State<SprayChartScreen> createState() => _SprayChartScreenState();
}

class _SprayChartScreenState extends State<SprayChartScreen> {
  String _team = 'All';
  String _outcome = 'All';
  String _pitch = 'All';
  String _hand = 'All';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    var data = session.filteredPitches
        .where((p) => p.xCoord != null && p.yCoord != null)
        .toList();
    if (_team != 'All') data = data.where((p) => p.game == _team).toList();
    if (_outcome != 'All') {
      if (_outcome == 'out') {
        data = data
            .where((p) => {'go', 'fo', 'lo', 'dp', 'fc'}.contains(p.outcome))
            .toList();
      } else {
        data = data.where((p) => p.outcome == _outcome).toList();
      }
    }
    if (_hand != 'All') data = data.where((p) => p.hand == _hand).toList();

    // Pitch key / Pitch filter: built from the pitch types that actually
    // appear in the spray data being shown (before the Pitch filter itself, so
    // picking one pitch doesn't empty the key). Add a pitch type and it shows
    // up; once no ball in play uses a type, it drops out. Nothing hard-coded.
    String keyOf(PitchEvent p) {
      final t = (p.pitchType ?? '').toLowerCase().trim();
      return t.isEmpty ? 'other' : t;
    }
    const preferredOrder = ['fb', 'sl', 'cv', 'ch'];
    final present = {for (final p in data) keyOf(p)};
    final pitchKeys = [
      ...preferredOrder.where(present.contains),
      ...(present.difference(preferredOrder.toSet()).toList()..sort()),
    ];
    // A pitch filter whose type has since disappeared falls back to All.
    final activePitch = pitchKeys.contains(_pitch) ? _pitch : 'All';
    if (activePitch != 'All') data = data.where((p) => keyOf(p) == activePitch).toList();

    final teams = ['All', ...session.knownTeams];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _team,
                    decoration: const InputDecoration(labelText: 'Team'),
                    items: teams.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _team = v!),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _outcome,
                    decoration: const InputDecoration(labelText: 'Outcome'),
                    items: ['All', 'out', '1b', '2b', '3b', 'hr', 'e', 'dp', 'fc']
                        .map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _outcome = v!),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: activePitch,
                    decoration: const InputDecoration(labelText: 'Pitch'),
                    items: ['All', ...pitchKeys]
                        .map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _pitch = v!),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _hand,
                    decoration: const InputDecoration(labelText: 'Hand'),
                    items: ['All', 'R', 'L']
                        .map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _hand = v!),
                  ),
                ),
                const YearFilterDropdown(),
              ],
            ),
          ),
        ),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              const Text('Fill = Result:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              for (final k in ['1b', '2b', '3b', 'hr', 'e', 'fc', 'out'])
                StatHoldInfo(
                  title: 'Fill = Result',
                  description: composeHoldInfo(
                    what: 'The inside color of each dot is what happened on the ball in play.',
                    colorGuide: sprayFillColorGuide(),
                  ),
                  child: LegendChip(label: k.toUpperCase(), color: AppColors.sprayColor(k)),
                ),
              const SizedBox(width: 16),
              const Text('Ring = Pitch:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              for (final k in pitchKeys)
                StatHoldInfo(
                  title: 'Ring = Pitch',
                  description: composeHoldInfo(
                    what: 'The outline color around each dot is the pitch type that was hit.',
                    colorGuide: sprayRingColorGuide(pitchKeys),
                  ),
                  child: LegendChip(label: k.toUpperCase(), color: AppColors.pitchColor(k)),
                ),
              const SizedBox(width: 16),
              const Text('Trajectory:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const _TrajectoryLegendItem(label: 'Ground Ball — dotted', style: _TrajStyle.dotted),
              const _TrajectoryLegendItem(label: 'Line Drive — straight', style: _TrajStyle.straight),
              const _TrajectoryLegendItem(label: 'Fly Ball — arc', style: _TrajStyle.arc),
            ]),
          ),
        ),
        GlowCard(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Spray Chart', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 6),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: data.isEmpty
                          ? const Center(
                              child: Text('No spray data yet.', style: TextStyle(color: Colors.grey)))
                          : StatHoldInfo(
                              title: 'Spray Chart',
                              description: composeHoldInfo(
                                what: 'Every ball in play is a dot placed where it landed on the field, seen from behind home plate. '
                                    'Dot fill = what happened, the ring around it = which pitch was hit, and the line from home plate shows the batted-ball type '
                                    '(dotted = ground ball, straight = line drive, arc = fly ball). Clusters show where hitters put the ball.',
                                colorGuide: 'Fill (result):\n${sprayFillColorGuide()}\n\nRing (pitch):\n${sprayRingColorGuide(pitchKeys)}\n\n'
                                    'These are labels, not good/bad grades, so there are no numeric cutoffs.',
                              ),
                              child: SprayFieldSurface(sprayPoints: data),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _TrajStyle { dotted, straight, arc }

class _TrajectoryLegendItem extends StatelessWidget {
  final String label;
  final _TrajStyle style;
  const _TrajectoryLegendItem({required this.label, required this.style});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 28,
        height: 12,
        child: CustomPaint(painter: _TrajSwatchPainter(style)),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
    ]);
  }
}

class _TrajSwatchPainter extends CustomPainter {
  final _TrajStyle style;
  _TrajSwatchPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.colMuted
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final start = Offset(0, size.height / 2);
    final end = Offset(size.width, size.height / 2);
    switch (style) {
      case _TrajStyle.dotted:
        double x = 0;
        while (x < size.width) {
          canvas.drawLine(Offset(x, size.height / 2),
              Offset((x + 3).clamp(0, size.width).toDouble(), size.height / 2), paint);
          x += 5.5;
        }
        break;
      case _TrajStyle.straight:
        canvas.drawLine(start, end, paint);
        break;
      case _TrajStyle.arc:
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(size.width / 2, -4, end.dx, end.dy);
        canvas.drawPath(path, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TrajSwatchPainter oldDelegate) => false;
}
