import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'analytics.dart';
import 'bullpen_models.dart';
import 'widgets.dart';

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Small colored pitch-name pill (same look as the rest of the app).
class PitchPill extends StatelessWidget {
  final String type;
  final String label;
  const PitchPill({super.key, required this.type, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: AppColors.pitchColor(type), borderRadius: BorderRadius.circular(12)),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
      );
}

/// Summary of one bullpen: shown when finishing and when opening past bullpens.
class SessionSummaryView extends StatelessWidget {
  final BullpenSession session;
  final List<BullpenPitch> pitches;
  final String Function(String) labelOf;
  const SessionSummaryView({super.key, required this.session, required this.pitches, required this.labelOf});

  @override
  Widget build(BuildContext context) {
    final overall = BullpenStats();
    final byType = <String, BullpenStats>{};
    final misses = MissCounts();
    for (final p in pitches) {
      overall.add(p);
      byType.putIfAbsent(p.pitchType, BullpenStats.new).add(p);
      misses.add(p, session.throwsHand);
    }
    final plan = BullpenAnalytics.planResults(session, pitches);
    final landed = pitches.where((p) => p.hasActual).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StatCardGrid(children: [
        BigStatCard(label: 'Pitches', value: '${overall.pitches}'),
        BigStatCard(label: 'Time', value: fmtDuration(session.elapsed())),
        BigStatCard(
            label: 'Target accuracy',
            value: fmtPct(overall.targetAccuracy),
            note: overall.targetPitches == 0 ? 'no targets set' : '${overall.targetHits} of ${overall.targetPitches}'),
        BigStatCard(
            label: 'Strike %',
            value: fmtPct(overall.zonePct),
            note: overall.landed == 0 ? null : '${overall.strikes} of ${overall.landed} in zone'),
        BigStatCard(label: 'Avg miss', value: fmtIn(overall.avgDistanceIn), note: 'from target center'),
      ]),
      const SizedBox(height: 12),
      if (byType.isNotEmpty) ...[
        const Text('BY PITCH',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
        const SizedBox(height: 6),
        for (final e in byType.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Flexible(flex: 3, child: Align(alignment: Alignment.centerLeft, child: PitchPill(type: e.key, label: labelOf(e.key)))),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text(
                  '${e.value.pitches} thrown · target ${fmtPct(e.value.targetAccuracy)} · strike ${fmtPct(e.value.zonePct)} · miss ${fmtIn(e.value.avgDistanceIn)}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.colText),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 6),
      ],
      if (misses.misses > 0) ...[
        const Text('MISSES (pitches outside the target)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
        const SizedBox(height: 4),
        Text(
          '${misses.misses} misses · high ${fmtPct(misses.share(misses.high))} · low ${fmtPct(misses.share(misses.low))} · '
          'arm-side ${fmtPct(misses.share(misses.armSide))} · glove-side ${fmtPct(misses.share(misses.gloveSide))}',
          style: const TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 10),
      ],
      if (landed.isNotEmpty) ...[
        const Text('WHERE THEY LANDED (catcher\'s view)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
        const SizedBox(height: 6),
        StrikeZone(
          maxWidth: 260,
          semanticsLabel: 'Landing locations',
          markers: [
            for (final p in landed)
              ZoneMarker(p.actualX!, p.actualY!, AppColors.pitchColor(p.pitchType), radius: 5),
          ],
        ),
        const SizedBox(height: 10),
      ],
      if (plan.isNotEmpty) ...[
        const Text('PLAN vs. WHAT YOU THREW',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
        const SizedBox(height: 6),
        for (final r in plan)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(r.completed ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                  size: 18, color: r.completed ? AppColors.perfExcellent : AppColors.colMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Set ${r.index + 1}: ${labelOf(r.planned.pitchType)} - ${r.thrown}/${r.planned.reps} reps, '
                  'target ${fmtPct(r.stats.targetAccuracy)}, strike ${fmtPct(r.stats.zonePct)}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          ),
      ],
      if ((session.notes ?? '').trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('Notes: ${session.notes}', style: const TextStyle(fontSize: 12.5, color: AppColors.colMuted)),
      ],
    ]);
  }
}
