import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
                              // Press and hold a dot for that pitch's details. The
                              // gate only lets a press through when it lands on
                              // (or right next to) a dot, so pressing the empty
                              // field still shows the chart explanation above.
                              child: _DotGate(
                                points: data,
                                child: Builder(
                                  builder: (ctx) => GestureDetector(
                                    onLongPressStart: (d) {
                                      final box = ctx.findRenderObject();
                                      if (box is! RenderBox) return;
                                      final hit = _nearestDot(data, box.size, d.localPosition, _dotHitRadius);
                                      if (hit != null) _showDotInfo(ctx, hit);
                                    },
                                    child: SprayFieldSurface(sprayPoints: data),
                                  ),
                                ),
                              ),
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

/// How close (in logical pixels) a press has to be to a dot's center to count
/// as pressing that dot. Larger than the drawn dot (radius ~9) so a finger
/// does not have to hit a tiny target exactly.
const double _dotHitRadius = 22;

/// The same field-to-canvas mapping [BaseballFieldPainter] uses to place a dot.
Offset _dotCenter(PitchEvent p, Size size) {
  final nx = (p.xCoord! - BaseballFieldPainter.fieldMinX) /
      (BaseballFieldPainter.fieldMaxX - BaseballFieldPainter.fieldMinX);
  final ny = (p.yCoord! - BaseballFieldPainter.fieldMinY) /
      (BaseballFieldPainter.fieldMaxY - BaseballFieldPainter.fieldMinY);
  return Offset(nx * size.width, size.height - ny * size.height);
}

/// The plotted pitch whose dot is closest to [pos] (within [radius]), or null.
/// Each dot is looked up from its own PitchEvent, so the details shown are
/// always those of the dot that was pressed.
PitchEvent? _nearestDot(List<PitchEvent> points, Size size, Offset pos, double radius) {
  PitchEvent? best;
  var bestD = radius;
  for (final p in points) {
    if (p.xCoord == null || p.yCoord == null) continue;
    final d = (_dotCenter(p, size) - pos).distance;
    if (d <= bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
}

/// Lets pointers reach its child only when they land on a dot; everywhere
/// else the press falls through to the widgets behind it.
class _DotGate extends SingleChildRenderObjectWidget {
  final List<PitchEvent> points;
  const _DotGate({required this.points, required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDotGate(points);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderDotGate renderObject) {
    renderObject.points = points;
  }
}

class _RenderDotGate extends RenderProxyBox {
  _RenderDotGate(this.points);
  List<PitchEvent> points;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (_nearestDot(points, size, position, _dotHitRadius) == null) return false;
    return super.hitTest(result, position: position);
  }
}

const Map<String, String> _outcomeNames = {
  '1b': 'Single', '2b': 'Double', '3b': 'Triple', 'hr': 'Home Run',
  'go': 'Ground Out', 'fo': 'Fly Out', 'lo': 'Line Out',
  'fc': "Fielder's Choice", 'dp': 'Double Play', 'e': 'Error',
};

/// Bottom sheet with what is known about one plotted pitch. A field that is
/// missing from the data is left out (no blanks or placeholders).
void _showDotInfo(BuildContext context, PitchEvent p) {
  final session = context.read<AppSession>();
  HapticFeedback.selectionClick();
  final jersey = p.batterNumber;
  final name = jersey == null ? null : session.batterNames[jersey]?.trim();
  final outcome = (p.outcome == null || p.outcome!.isEmpty)
      ? null
      : (_outcomeNames[p.outcome] ?? p.outcome!.toUpperCase());
  final hand = switch (p.hand) {
    'R' => 'Right-handed',
    'L' => 'Left-handed',
    'S' => 'Switch hitter',
    _ => null,
  };
  final pitchKey = (p.pitchType ?? '').trim();
  final rows = <(String, String)>[
    if (pitchKey.isNotEmpty) ('Pitch', session.pitchTypeLabel(pitchKey)),
    if (outcome != null) ('Outcome', outcome),
    if (hand != null) ('Hand', hand),
    if (p.game.trim().isNotEmpty) ('Team', p.game),
    ('Game', 'Game ${p.gameNumber} · ${p.season}'),
    if (jersey != null) ('Jersey Number', '#$jersey'),
    if (name != null && name.isNotEmpty) ('Name', name),
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.sprayColor(p.outcome),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.pitchColor(p.pitchType), width: 2.5),
                ),
              ),
              const SizedBox(width: 8),
              const Text('PITCH DETAILS',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1, color: AppColors.ink)),
            ]),
            const SizedBox(height: 10),
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.colBorder))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 120,
                    child: Text(r.$1,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
                  ),
                  Expanded(
                    child: Text(r.$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  ),
                ]),
              ),
          ],
        ),
      ),
    ),
  );
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
