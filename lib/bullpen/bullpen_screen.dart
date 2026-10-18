// The Bullpen tab: Standard Bullpen sessions and Game Mode challenges.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/pitcher_switcher_dialog.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glow.dart';
import 'analytics.dart';
import 'bullpen_models.dart';
import 'challenges.dart';
import 'entry_widgets.dart';
import 'game_mode_view.dart';
import 'plan_models.dart';
import 'session_summary.dart';
import 'store.dart';
import 'widgets.dart';

enum _BpMode { standard, game }

class BullpenScreen extends StatefulWidget {
  const BullpenScreen({super.key});

  @override
  State<BullpenScreen> createState() => _BullpenScreenState();
}

class _BullpenScreenState extends State<BullpenScreen> {
  _BpMode _mode = _BpMode.standard;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BullpenStore>();
    if (!store.loaded) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (store.loadError != null) return LoadErrorCard(store: store);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (store.syncError != null) SyncBanner(store: store),
      SegmentedTabs<_BpMode>(
        values: _BpMode.values,
        value: _mode,
        labelOf: (m) => m == _BpMode.standard ? 'Standard Bullpen' : 'Game Mode',
        onChanged: (m) => setState(() => _mode = m),
      ),
      const SizedBox(height: 10),
      if (_mode == _BpMode.standard) _StandardView(store: store) else const GameModeView(),
    ]);
  }
}

class LoadErrorCard extends StatelessWidget {
  final BullpenStore store;
  const LoadErrorCard({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bullpen data could not be loaded', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          const SizedBox(height: 4),
          SelectableText(store.loadError ?? '', style: const TextStyle(fontSize: 13, color: AppColors.colText)),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
            onPressed: store.load,
            child: const Text('Retry'),
          ),
        ]),
      ),
    );
  }
}

class SyncBanner extends StatelessWidget {
  final BullpenStore store;
  const SyncBanner({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.colError),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.colError),
        const SizedBox(width: 8),
        Expanded(child: Text(store.syncError!, style: const TextStyle(fontSize: 12.5))),
        TextButton(onPressed: store.retrySync, child: const Text('Retry')),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// STANDARD BULLPEN
// ════════════════════════════════════════════════════════════════

class _StandardView extends StatelessWidget {
  final BullpenStore store;
  const _StandardView({required this.store});

  @override
  Widget build(BuildContext context) {
    final active = store.activeSession;
    if (active != null) return _ActiveSessionView(key: ValueKey(active.id), store: store, session: active);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SetupCard(store: store),
      const SizedBox(height: 8),
      _HistoryCard(store: store),
    ]);
  }
}

class _SetupCard extends StatefulWidget {
  final BullpenStore store;
  const _SetupCard({required this.store});

  @override
  State<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<_SetupCard> {
  BullpenType _type = BullpenType.command;
  final _name = TextEditingController();
  bool _usePlan = true;

  @override
  void initState() {
    super.initState();
    final p = widget.store.pendingPlan;
    if (p != null) _type = p.focus.bullpenType;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final store = widget.store;
    // Throwing hand comes from the active pitcher's profile - never asked here.
    final hand = context.read<AppSession>().activePitcher?.throwsHand;
    if (hand == null) return;
    final plan = _usePlan ? store.pendingPlan : null;
    await store.startSession(
      type: plan != null ? plan.focus.bullpenType : _type,
      customName: (plan == null && _type == BullpenType.custom) ? _name.text.trim() : null,
      hand: hand,
      usePlan: plan,
    );
    if (plan != null) store.takePendingPlan();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppSession>();
    final pitcher = context.watch<AppSession>().activePitcher;
    final plan = widget.store.pendingPlan;
    final planned = plan != null && _usePlan;
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Start a Bullpen', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Bullpen pitches are saved separately and never change your game stats.',
              style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
          if (plan != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.tint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.brandOrangeDeep, width: 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Plan ready: ${plan.focus.label} · ${plan.sets.length} sets · ${plan.totalReps} pitches',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                for (var i = 0; i < plan.sets.length; i++)
                  Text('${i + 1}. ${plan.sets[i].reps} × ${app.pitchTypeLabel(plan.sets[i].pitchType)} - ${plan.sets[i].purpose}',
                      style: const TextStyle(fontSize: 12)),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start with this plan', style: TextStyle(fontSize: 13)),
                  value: _usePlan,
                  activeColor: AppColors.brandOrangeDeep,
                  onChanged: (v) => setState(() => _usePlan = v),
                ),
              ]),
            ),
          ],
          if (!planned) ...[
            const SizedBox(height: 12),
            const Text('Bullpen type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in BullpenType.values)
                ChoiceChip(
                  label: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  selected: _type == t,
                  selectedColor: AppColors.brandOrangeDeep,
                  labelStyle: TextStyle(color: _type == t ? Colors.white : AppColors.ink),
                  onSelected: (_) => setState(() => _type = t),
                ),
            ]),
            if (_type == BullpenType.custom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Custom bullpen name', isDense: true),
              ),
            ],
          ],
          const SizedBox(height: 10),
          if (pitcher != null && pitcher.throwsHand != null) ...[
            Row(children: [
              const Icon(Icons.sports_baseball_outlined, size: 16, color: AppColors.colMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${pitcher.displayName} · ${pitcher.handLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Throwing hand comes from the pitcher profile and is used to tell arm-side misses from glove-side misses.',
                style: TextStyle(fontSize: 11, color: AppColors.colMuted)),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: AppColors.brandOrangeDeep),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  pitcher == null
                      ? 'No pitcher profile is loaded yet.'
                      : "${pitcher.displayName}'s profile is missing a throwing hand. "
                          'Complete the profile once and the Bullpen will use it every time.',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (pitcher != null)
                  TextButton(
                    onPressed: () => showEditPitcher(context, pitcher),
                    child: const Text('Complete profile'),
                  ),
              ]),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandOrangeDeep,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: (pitcher?.throwsHand == null) ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Bullpen'),
          ),
        ]),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final BullpenStore store;
  const _HistoryCard({required this.store});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppSession>();
    final sessions = store.finishedSessions;
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Past Bullpens (${sessions.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          if (sessions.isEmpty)
            const Text('Finished bullpens will show up here.', style: TextStyle(color: AppColors.colMuted)),
          for (final s in sessions.take(15))
            Builder(builder: (context) {
              final pitches = store.pitchesFor(s.id);
              final stats = BullpenStats();
              for (final p in pitches) {
                stats.add(p);
              }
              final d = s.startedAt;
              return ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 10),
                title: Text('${d.month}/${d.day}/${d.year} · ${s.title}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${stats.pitches} pitches · target ${fmtPct(stats.targetAccuracy)} · strike ${fmtPct(stats.zonePct)}',
                    style: const TextStyle(fontSize: 12)),
                children: [
                  SessionSummaryView(session: s, pitches: pitches, labelOf: app.pitchTypeLabel),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete bullpen'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.colError),
                      onPressed: () async {
                        final ok = await _confirm(context, 'Delete this bullpen?',
                            'Its ${pitches.length} pitches will be removed. Game data is not affected.');
                        if (ok) await store.deleteSession(s.id);
                      },
                    ),
                  ),
                ],
              );
            }),
        ]),
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body, {String yes = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
  return r ?? false;
}

/// mm:ss of active time; ticks once a second while the bullpen is running.
class _ElapsedText extends StatefulWidget {
  final BullpenSession session;
  const _ElapsedText(this.session);

  @override
  State<_ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<_ElapsedText> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.session.status == SessionStatus.active) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(fmtDuration(widget.session.elapsed()),
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18));
}

class _ActiveSessionView extends StatefulWidget {
  final BullpenStore store;
  final BullpenSession session;
  const _ActiveSessionView({super.key, required this.store, required this.session});

  @override
  State<_ActiveSessionView> createState() => _ActiveSessionViewState();
}

class _ActiveSessionViewState extends State<_ActiveSessionView> {
  String? _pitchType;
  ZoneTarget _target = const ZoneTarget(0.5, 0.5, 0.35, 0.35);
  bool _noTarget = false;
  bool _landingMode = false;
  double? _ax, _ay;
  final _vel = TextEditingController();
  final _notes = TextEditingController();
  String? _result;
  String? _velError;
  bool _saving = false;
  int? _planIdx;

  BullpenPlan? get _plan => widget.session.plan == null ? null : BullpenPlan.fromJson(widget.session.plan!);

  @override
  void initState() {
    super.initState();
    _applyPlan();
    if (_plan != null) _landingMode = true;
  }

  @override
  void dispose() {
    _vel.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Plan-guided bullpens: first set that still has reps left sets the pitch and target.
  void _applyPlan() {
    final plan = _plan;
    if (plan == null) return;
    final thrown = widget.store.pitchesFor(widget.session.id);
    for (var i = 0; i < plan.sets.length; i++) {
      final done = thrown.where((p) => p.planSetIndex == i).length;
      if (done < plan.sets[i].reps) {
        _planIdx = i;
        _pitchType = plan.sets[i].pitchType;
        _target = plan.sets[i].target;
        _noTarget = false;
        return;
      }
    }
    _planIdx = null; // plan finished: free throwing
  }

  Future<void> _save(String type) async {
    if (_ax == null || _ay == null) return;
    if (type.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a pitch type on Game Input first (Add New Pitch).')));
      return;
    }
    double? vel;
    if (_vel.text.trim().isNotEmpty) {
      vel = double.tryParse(_vel.text.trim());
      if (vel == null || vel <= 0 || vel > 130) {
        setState(() => _velError = 'Enter a speed like 87.5');
        return;
      }
    }
    setState(() => _saving = true);
    await widget.store.addPitch(
      pitchType: type,
      target: _noTarget ? null : _target,
      actualX: _ax!,
      actualY: _ay!,
      velocity: vel,
      result: _result,
      notes: _notes.text,
      planSetIndex: _planIdx,
    );
    if (!mounted) return;
    setState(() {
      _ax = null;
      _ay = null;
      _vel.clear();
      _notes.clear();
      _result = null;
      _velError = null;
      _saving = false;
      if (!_noTarget) _landingMode = true; // next pitch: same target, mark the landing
      _applyPlan();
    });
  }

  Future<void> _finish() async {
    final app = context.read<AppSession>();
    final store = widget.store;
    final id = widget.session.id;
    final count = store.pitchesFor(id).length;
    final ok = await _confirm(
      context,
      'Finish this bullpen?',
      count == 0 ? 'No pitches were logged, so this bullpen will be discarded.' : 'It is saved already; finishing closes it and shows the summary.',
      yes: 'Finish',
    );
    if (!ok || !mounted) return;
    final done = await store.finish();
    if (!mounted) return;
    if (done == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Empty bullpen discarded.')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.dialogWidth(ctx, 640)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${done.title} summary', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 10),
              SessionSummaryView(session: done, pitches: store.pitchesFor(done.id), labelOf: app.pitchTypeLabel),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BullpenPitch p) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditPitchDialog(store: widget.store, pitch: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppSession>();
    final store = context.watch<BullpenStore>();
    // Re-read the session from the store so pause/resume shows immediately.
    final session = store.sessions.firstWhere((s) => s.id == widget.session.id, orElse: () => widget.session);
    final types = availablePitchTypes(app);
    final type = (_pitchType != null && types.contains(_pitchType)) ? _pitchType! : (types.isNotEmpty ? types.first : '');
    final paused = session.status == SessionStatus.paused;
    final pitches = store.pitchesFor(session.id);
    final stats = BullpenStats();
    for (final p in pitches) {
      stats.add(p);
    }
    final plan = _plan;
    final prev = pitches.reversed.take(10).where((p) => p.hasActual).toList();

    final header = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(session.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: paused ? AppColors.perfAverage : AppColors.perfGood,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(paused ? 'PAUSED' : 'LIVE',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.ink)),
            ),
            const SizedBox(width: 10),
            _ElapsedText(session),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: paused ? store.resume : store.pause,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
              label: Text(paused ? 'Resume' : 'Pause'),
            ),
            OutlinedButton.icon(
              onPressed: pitches.isEmpty ? null : store.undoLast,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Undo Last Pitch'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
              onPressed: _finish,
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Finish'),
            ),
          ]),
          const SizedBox(height: 10),
          StatCardGrid(children: [
            BigStatCard(label: 'Pitches', value: '${stats.pitches}'),
            BigStatCard(label: 'Target accuracy', value: fmtPct(stats.targetAccuracy), note: stats.targetPitches == 0 ? null : '${stats.targetHits} of ${stats.targetPitches}'),
            BigStatCard(label: 'Strike %', value: fmtPct(stats.zonePct)),
            BigStatCard(label: 'Avg miss', value: fmtIn(stats.avgDistanceIn)),
          ]),
        ]),
      ),
    );

    Widget? planCard;
    if (plan != null) {
      planCard = GlowCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Plan: ${plan.focus.label}', style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            if (_planIdx == null)
              const Text('Plan complete. Keep throwing freely or finish the bullpen to see plan vs. results.',
                  style: TextStyle(fontSize: 13))
            else ...[
              Text(
                  'Set ${_planIdx! + 1} of ${plan.sets.length}: ${app.pitchTypeLabel(plan.sets[_planIdx!].pitchType)} - '
                  '${pitches.where((p) => p.planSetIndex == _planIdx).length}/${plan.sets[_planIdx!].reps} reps',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(plan.sets[_planIdx!].purpose, style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
            ],
          ]),
        ),
      );
    }

    final zoneCard = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TargetLandingPicker(
          target: _target,
          noTarget: _noTarget,
          landingMode: _landingMode,
          actualX: _ax,
          actualY: _ay,
          pitchColor: AppColors.pitchColor(type),
          enabled: !paused,
          trail: [
            for (final p in prev) ZoneMarker(p.actualX!, p.actualY!, AppColors.colMuted.withOpacity(0.45), radius: 4),
          ],
          onLandingMode: (v) => setState(() => _landingMode = v),
          onNoTarget: (v) => setState(() {
            _noTarget = v;
            if (v) _landingMode = true;
          }),
          onTarget: (t) => setState(() => _target = t),
          onLanding: (x, y) => setState(() {
            _ax = x;
            _ay = y;
          }),
        ),
      ),
    );

    final controlsCard = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Pitch', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          PitchTypeChips(
            types: types,
            selected: type,
            labelOf: app.pitchTypeLabel,
            onSelected: (t) => setState(() => _pitchType = t),
          ),
          const SizedBox(height: 10),
          Text(
            _noTarget
                ? 'Target: none'
                : 'Target: ${(_target.w * ZoneGeo.plateWidthIn).toStringAsFixed(1)} × ${(_target.h * ZoneGeo.zoneHeightIn).toStringAsFixed(1)} in',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          Text(
            _ax == null ? 'Landing: not marked yet' : 'Landing: ${(_ax! >= 0 && _ax! <= 1 && _ay! >= 0 && _ay! <= 1) ? 'in the zone' : 'outside the zone'}'
                '${(!_noTarget && _target.contains(_ax!, _ay!)) ? ' · on target' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Velocity, result, notes (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            children: [
              TextField(
                controller: _vel,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Velocity (mph)', isDense: true, errorText: _velError),
                onChanged: (_) => setState(() => _velError = null),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final e in bullpenResultLabels.entries)
                  ChoiceChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 12)),
                    selected: _result == e.key,
                    selectedColor: AppColors.brandPeach,
                    onSelected: (v) => setState(() => _result = v ? e.key : null),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes', isDense: true),
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandOrangeDeep,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: (paused || _saving || _ax == null) ? null : () => _save(type),
            icon: const Icon(Icons.add),
            label: const Text('Save Pitch & Add Another'),
          ),
          if (paused)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Paused. Resume to log pitches.', style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
            ),
        ]),
      ),
    );

    final log = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Pitches this bullpen (${pitches.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (pitches.isEmpty) const Text('Nothing logged yet.', style: TextStyle(color: AppColors.colMuted)),
          for (final p in pitches.reversed.take(30))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 30, child: Text('#${p.seq}', style: const TextStyle(fontWeight: FontWeight.w800))),
                PitchPill(type: p.pitchType, label: app.pitchTypeLabel(p.pitchType)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      p.hasTarget ? (p.hitTarget ? 'on target' : 'missed ${p.distanceIn!.toStringAsFixed(1)} in') : 'no target',
                      p.inZone ? 'strike' : 'ball',
                      if (p.velocity != null) '${p.velocity!.toStringAsFixed(1)} mph',
                      if (p.result != null) bullpenResultLabels[p.result] ?? p.result!,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit pitch #${p.seq}',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _edit(p),
                ),
                IconButton(
                  tooltip: 'Delete pitch #${p.seq}',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.colError),
                  onPressed: () async {
                    if (await _confirm(context, 'Delete pitch #${p.seq}?', 'This removes it from the bullpen.')) {
                      await store.deletePitch(p.id);
                    }
                  },
                ),
              ]),
            ),
          if (pitches.length > 30)
            Text('Showing the latest 30 of ${pitches.length}.', style: const TextStyle(fontSize: 11, color: AppColors.colMuted)),
        ]),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      if (planCard != null) planCard,
      ResponsiveRow(
        breakpoint: 760,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: zoneCard),
          Expanded(flex: 5, child: controlsCard),
        ],
      ),
      log,
    ]);
  }
}

class _EditPitchDialog extends StatefulWidget {
  final BullpenStore store;
  final BullpenPitch pitch;
  const _EditPitchDialog({required this.store, required this.pitch});

  @override
  State<_EditPitchDialog> createState() => _EditPitchDialogState();
}

class _EditPitchDialogState extends State<_EditPitchDialog> {
  late String _type = widget.pitch.pitchType;
  late ZoneTarget _target = widget.pitch.target ?? const ZoneTarget(0.5, 0.5, 0.35, 0.35);
  late bool _noTarget = widget.pitch.target == null;
  bool _landingMode = false;
  late double? _ax = widget.pitch.actualX;
  late double? _ay = widget.pitch.actualY;
  late final _vel = TextEditingController(text: widget.pitch.velocity?.toString() ?? '');
  late final _notes = TextEditingController(text: widget.pitch.notes ?? '');
  late String? _result = widget.pitch.result;
  String? _velError;

  @override
  void dispose() {
    _vel.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    double? vel;
    if (_vel.text.trim().isNotEmpty) {
      vel = double.tryParse(_vel.text.trim());
      if (vel == null || vel <= 0 || vel > 130) {
        setState(() => _velError = 'Enter a speed like 87.5');
        return;
      }
    }
    final updated = widget.pitch.copyWith(
      pitchType: _type,
      target: _noTarget ? null : _target,
      clearTarget: _noTarget,
      actualX: _ax,
      actualY: _ay,
      velocity: vel,
      clearVelocity: vel == null,
      result: _result,
      clearResult: _result == null,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      clearNotes: _notes.text.trim().isEmpty,
    );
    await widget.store.updatePitch(updated);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppSession>();
    final types = {...availablePitchTypes(app), widget.pitch.pitchType}.toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.dialogWidth(context, 520)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Edit pitch #${widget.pitch.seq}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 10),
            PitchTypeChips(types: types, selected: _type, labelOf: app.pitchTypeLabel, onSelected: (t) => setState(() => _type = t)),
            const SizedBox(height: 10),
            TargetLandingPicker(
              target: _target,
              noTarget: _noTarget,
              landingMode: _landingMode,
              actualX: _ax,
              actualY: _ay,
              pitchColor: AppColors.pitchColor(_type),
              onLandingMode: (v) => setState(() => _landingMode = v),
              onNoTarget: (v) => setState(() {
                _noTarget = v;
                if (v) _landingMode = true;
              }),
              onTarget: (t) => setState(() => _target = t),
              onLanding: (x, y) => setState(() {
                _ax = x;
                _ay = y;
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _vel,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Velocity (mph, optional)', isDense: true, errorText: _velError),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final e in bullpenResultLabels.entries)
                ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 12)),
                  selected: _result == e.key,
                  selectedColor: AppColors.brandPeach,
                  onSelected: (v) => setState(() => _result = v ? e.key : null),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', isDense: true)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
                  onPressed: (_ax == null || _ay == null) ? null : _save,
                  child: const Text('Save Changes'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
