// The Pitching Analysis tab: turns bullpen, Game Mode and game data into
// findings, a development plan, and progress tracking.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glow.dart';
import '../widgets/stat_vbox.dart' show StatHeaderRow;
import '../widgets/value_bar.dart';
import 'analytics.dart';
import 'bullpen_models.dart';
import 'bullpen_screen.dart' show LoadErrorCard, SyncBanner;
import 'challenges.dart';
import 'entry_widgets.dart';
import 'plan_models.dart';
import 'recommendations.dart';
import 'session_summary.dart';
import 'store.dart';
import 'widgets.dart';

enum _Range { all, days30, days90 }

class PitchingAnalysisScreen extends StatefulWidget {
  const PitchingAnalysisScreen({super.key});

  @override
  State<PitchingAnalysisScreen> createState() => _PitchingAnalysisScreenState();
}

class _PitchingAnalysisScreenState extends State<PitchingAnalysisScreen> {
  _Range _range = _Range.all;
  String? _pitch; // null = all pitches
  BullpenType? _type; // null = all bullpen types
  PlanFocus _focus = PlanFocus.command;
  BullpenPlan? _plan;
  bool _planLoaded = false;
  int _planVersion = 0; // changes when the plan is replaced so text fields reset

  DateTime? get _since => switch (_range) {
        _Range.all => null,
        _Range.days30 => DateTime.now().subtract(const Duration(days: 30)),
        _Range.days90 => DateTime.now().subtract(const Duration(days: 90)),
      };

  bool get _filtered => _range != _Range.all || _pitch != null || _type != null;

  Widget _card(String title, Widget child, {String? subtitle}) => GlowCard(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
              ),
            const SizedBox(height: 6),
            child,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BullpenStore>();
    final app = context.watch<AppSession>();
    if (!store.loaded) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (store.loadError != null) return LoadErrorCard(store: store);
    if (!_planLoaded) {
      _plan = store.plan;
      _planLoaded = true;
    }

    // Everything is computed from the player's real rows. `ranged` ignores the
    // pitch filter (recommendations and plans always look at all pitches);
    // `shown` applies every filter for the charts.
    final ranged = BullpenAnalytics.analyze(
        sessions: store.sessions, pitches: store.pitches, since: _since, sessionType: _type);
    final shown = BullpenAnalytics.analyze(
        sessions: store.sessions, pitches: store.pitches, pitchType: _pitch, since: _since, sessionType: _type);
    final comparison = BullpenAnalytics.compare(bullpen: ranged, gamePitches: app.pitches);
    final lastPlan = store.finishedSessions.where((s) => s.plan != null).toList();
    final lastPlanResults = lastPlan.isEmpty ? <PlanSetResult>[] : BullpenAnalytics.planResults(lastPlan.first, store.pitches);
    final recs = Recommender.findings(
      analysis: ranged,
      comparison: comparison,
      attempts: store.attempts,
      lastPlanResults: lastPlanResults,
      label: app.pitchTypeLabel,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (store.syncError != null) SyncBanner(store: store),
      _filters(ranged, app),
      if (!ranged.hasData && store.attempts.isEmpty)
        _emptyState(store)
      else ...[
        if (ranged.hasData) ...[
          _overview(shown),
          // Side by side on wide screens; stacked on narrow ones.
          ResponsiveRow(breakpoint: 900, crossAxisAlignment: CrossAxisAlignment.start, stackedGap: 0, children: [
            Expanded(child: _byPitch(shown, app)),
            const SizedBox(width: 8),
            Expanded(child: _misses(shown, app, store)),
          ]),
          _progress(shown, app),
        ] else
          _card('Bullpen analysis', const Text('No finished bullpens in this filter yet.', style: TextStyle(color: AppColors.colMuted))),
        ResponsiveRow(breakpoint: 900, crossAxisAlignment: CrossAxisAlignment.start, stackedGap: 0, children: [
          Expanded(child: _compare(comparison, app)),
          const SizedBox(width: 8),
          Expanded(child: _workOnNext(recs, app)),
        ]),
        _planCard(ranged, app, store, lastPlanResults),
        _gameModeResults(store, app),
      ],
    ]);
  }

  // ── filters ───────────────────────────────────────────────────

  Widget _filters(BullpenAnalysis ranged, AppSession app) {
    final types = {...ranged.byType.keys}.toList()..sort();
    Widget rangeField() => DropdownButtonFormField<_Range>(
          isExpanded: true,
          isDense: true,
          value: _range,
          decoration: const InputDecoration(labelText: 'Time range'),
          items: const [
            DropdownMenuItem(value: _Range.all, child: Text('All time')),
            DropdownMenuItem(value: _Range.days30, child: Text('Last 30 days')),
            DropdownMenuItem(value: _Range.days90, child: Text('Last 90 days')),
          ],
          onChanged: (v) => setState(() => _range = v!),
        );
    Widget pitchField() => DropdownButtonFormField<String?>(
          isExpanded: true,
          isDense: true,
          value: types.contains(_pitch) ? _pitch : null,
          decoration: const InputDecoration(labelText: 'Pitch'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All pitches')),
            for (final t in types) DropdownMenuItem<String?>(value: t, child: Text(app.pitchTypeLabel(t))),
          ],
          onChanged: (v) => setState(() => _pitch = v),
        );
    Widget typeField() => DropdownButtonFormField<BullpenType?>(
          isExpanded: true,
          isDense: true,
          value: _type,
          decoration: const InputDecoration(labelText: 'Bullpen type'),
          items: [
            const DropdownMenuItem<BullpenType?>(value: null, child: Text('All types')),
            for (final t in BullpenType.values) DropdownMenuItem<BullpenType?>(value: t, child: Text(t.label)),
          ],
          onChanged: (v) => setState(() => _type = v),
        );

    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Filter', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${ranged.sessionCount} finished bullpen${ranged.sessionCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
            ),
            if (_filtered)
              TextButton.icon(
                onPressed: () => setState(() {
                  _range = _Range.all;
                  _pitch = null;
                  _type = null;
                }),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: const Text('Clear Filters'),
                style: TextButton.styleFrom(foregroundColor: AppColors.brandOrangeDeep, visualDensity: VisualDensity.compact),
              ),
          ]),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 640) {
              return Row(children: [
                Expanded(child: rangeField()),
                const SizedBox(width: 10),
                Expanded(child: pitchField()),
                const SizedBox(width: 10),
                Expanded(child: typeField()),
              ]);
            }
            final half = (c.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 8, children: [
              SizedBox(width: half, child: rangeField()),
              SizedBox(width: half, child: pitchField()),
              SizedBox(width: c.maxWidth, child: typeField()),
            ]);
          }),
        ]),
      ),
    );
  }

  Widget _emptyState(BullpenStore store) => _card(
        'Nothing to analyze yet',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Finish a bullpen (set a target, mark where each pitch lands) or play a Game Mode challenge. '
              'This page then shows accuracy, misses, game comparisons and a plan built from your own numbers.',
              style: TextStyle(color: AppColors.colMuted)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
            onPressed: () => store.requestNavigate('Bullpen'),
            icon: const Icon(Icons.sports_baseball_outlined, size: 18),
            label: const Text('Go to Bullpen'),
          ),
        ]),
      );

  // ── bullpen analysis ──────────────────────────────────────────

  Widget _overview(BullpenAnalysis a) {
    final o = a.overall;
    return _card(
      'Bullpen overview',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StatCardGrid(children: [
          BigStatCard(label: 'Bullpens completed', value: '${a.sessionCount}'),
          BigStatCard(label: 'Pitches thrown', value: '${o.pitches}'),
          BigStatCard(
              label: 'Target accuracy',
              value: fmtPct(o.targetAccuracy),
              note: o.targetPitches == 0 ? 'no targets set' : '${o.targetHits} of ${o.targetPitches}'),
          BigStatCard(
              label: 'Strike %',
              value: fmtPct(o.zonePct),
              note: o.landed == 0 ? null : '${o.strikes} of ${o.landed} in zone'),
          BigStatCard(label: 'Avg miss', value: fmtIn(o.avgDistanceIn), note: 'from target center'),
        ]),
        const SizedBox(height: 8),
        const Text(
            'Target accuracy = landed inside the target you set (bigger targets are easier). '
            'Strike % = landed inside the strike zone, whatever the target. They measure different things.',
            style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
      ]),
    );
  }

  Widget _byPitch(BullpenAnalysis a, AppSession app) {
    final entries = a.byType.entries.toList()..sort((x, y) => y.value.pitches.compareTo(x.value.pitches));
    return _card(
      'Accuracy by pitch type',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                PitchPill(type: e.key, label: app.pitchTypeLabel(e.key)),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(fmtPct(e.value.targetAccuracy),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.ink)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              ValueBar(
                fraction: ((e.value.targetAccuracy ?? 0) / 100).clamp(0.0, 1.0),
                color: AppColors.pitchColor(e.key),
                text: '',
                height: 12,
                radius: 6,
              ),
              const SizedBox(height: 4),
              Text(
                'target accuracy · ${e.value.pitches} pitches · strike ${fmtPct(e.value.zonePct)} · avg miss ${fmtIn(e.value.avgDistanceIn)}'
                '${e.value.avgTargetWidthIn == null ? '' : ' · avg target ${e.value.avgTargetWidthIn!.toStringAsFixed(1)} × ${e.value.avgTargetHeightIn!.toStringAsFixed(1)} in'}'
                '${e.value.targetPitches < BullpenThresholds.minPitchTypeSample ? ' · small sample' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.colMuted),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _misses(BullpenAnalysis a, AppSession app, BullpenStore store) {
    final handBySession = {for (final s in store.sessions) s.id: s.throwsHand};
    final offsets = <Offset>[];
    final colors = <Color>[];
    double armSum = 0, upSum = 0;
    for (final p in a.pitches) {
      if (!p.hasTarget || !p.hasActual) continue;
      final hand = handBySession[p.sessionId] ?? 'R';
      final dx = (p.actualX! - p.target!.x) * ZoneGeo.plateWidthIn;
      final arm = hand == 'R' ? -dx : dx;
      final up = (p.actualY! - p.target!.y) * ZoneGeo.zoneHeightIn;
      offsets.add(Offset(arm, up));
      colors.add(AppColors.pitchColor(p.pitchType));
      armSum += arm;
      upSum += up;
    }
    final m = a.misses;
    final landed = a.pitches.where((p) => p.hasActual).toList();
    final recent = landed.length > 400 ? landed.sublist(landed.length - 400) : landed;

    Widget dirRow(String label, int count) {
      final share = m.share(count);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StatHeaderRow(label: label, value: fmtPct(share)),
          const SizedBox(height: 4),
          ValueBar(fraction: ((share ?? 0) / 100).clamp(0.0, 1.0), color: AppColors.brandOrangeDeep, text: '', height: 10, radius: 5),
        ]),
      );
    }

    final dominant = m.dominant;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Where pitches landed', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      StrikeZone(
        maxWidth: 280,
        semanticsLabel: 'Landing locations',
        markers: [for (final p in recent) ZoneMarker(p.actualX!, p.actualY!, AppColors.pitchColor(p.pitchType), radius: 4.5)],
      ),
      const SizedBox(height: 4),
      const Text('Catcher\'s view. Colors match the pitch type.', style: TextStyle(fontSize: 11, color: AppColors.colMuted)),
    ]);
    final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('How misses compare to the target', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      MissPlot(
        offsets: offsets,
        colors: colors,
        mean: offsets.isEmpty ? null : Offset(armSum / offsets.length, upSum / offsets.length),
      ),
      const SizedBox(height: 4),
      const Text('Center = your target. Right = arm side, up = high. The X is your average.',
          style: TextStyle(fontSize: 11, color: AppColors.colMuted)),
    ]);

    return _card(
      'Common misses',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ResponsiveRow(breakpoint: 640, crossAxisAlignment: CrossAxisAlignment.start, stackedGap: 14, children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ]),
        const SizedBox(height: 12),
        if (m.misses == 0)
          const Text('No misses recorded: every targeted pitch landed inside its target.',
              style: TextStyle(color: AppColors.colMuted))
        else ...[
          Text('${m.misses} pitches missed their target (share of misses; a miss can be both high and arm-side):',
              style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
          ResponsiveRow(breakpoint: 560, stackedGap: 0, children: [
            Expanded(child: Column(children: [dirRow('High', m.high), dirRow('Low', m.low)])),
            const SizedBox(width: 16),
            Expanded(child: Column(children: [dirRow('Arm-side', m.armSide), dirRow('Glove-side', m.gloveSide)])),
          ]),
          const SizedBox(height: 6),
          Text(
            dominant != null
                ? 'Most misses lean $dominant (at least ${(BullpenThresholds.dominantShare * 100).round()}% of ${m.misses}).'
                : (m.misses < BullpenThresholds.minMisses
                    ? 'Only ${m.misses} misses so far; a direction needs at least ${BullpenThresholds.minMisses} to count as a pattern.'
                    : 'No single direction accounts for most misses.'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ]),
    );
  }

  Widget _progress(BullpenAnalysis a, AppSession app) {
    final ss = a.perSession;
    final accSpots = <FlSpot>[], zoneSpots = <FlSpot>[];
    for (var i = 0; i < ss.length; i++) {
      final s = ss[i].stats;
      if (s.targetAccuracy != null) accSpots.add(FlSpot(i + 1.0, s.targetAccuracy!));
      if (s.zonePct != null) zoneSpots.add(FlSpot(i + 1.0, s.zonePct!));
    }
    LineChartBarData line(List<FlSpot> spots, Color c) => LineChartBarData(
          spots: spots,
          isCurved: false,
          color: c,
          barWidth: 3,
          dotData: const FlDotData(show: true),
        );

    return _card(
      'Progress across bullpens',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ss.length < 2)
          const Text('Complete at least two bullpens to see a trend.', style: TextStyle(color: AppColors.colMuted))
        else ...[
          Row(children: const [
            Icon(Icons.circle, size: 10, color: AppColors.brandOrangeDeep),
            SizedBox(width: 4),
            Text('Target accuracy', style: TextStyle(fontSize: 12)),
            SizedBox(width: 12),
            Icon(Icons.circle, size: 10, color: AppColors.ink),
            SizedBox(width: 4),
            Text('Strike %', style: TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: LineChart(LineChartData(
              minY: 0,
              maxY: 100,
              minX: 1,
              maxX: ss.length.toDouble(),
              lineBarsData: [
                if (accSpots.isNotEmpty) line(accSpots, AppColors.brandOrangeDeep),
                if (zoneSpots.isNotEmpty) line(zoneSpots, AppColors.ink),
              ],
              gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 25),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: 25,
                    getTitlesWidget: (v, meta) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 10)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: ss.length > 8 ? (ss.length / 6).ceilToDouble() : 1,
                    getTitlesWidget: (v, meta) => Text('#${v.toInt()}', style: const TextStyle(fontSize: 10)),
                  ),
                ),
              ),
            )),
          ),
        ],
        const SizedBox(height: 10),
        const Text('BULLPEN BY BULLPEN',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
        const SizedBox(height: 4),
        for (var i = 0; i < ss.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '#${i + 1} · ${ss[i].session.startedAt.month}/${ss[i].session.startedAt.day} · ${ss[i].session.title} · '
              '${ss[i].stats.pitches} pitches · target ${fmtPct(ss[i].stats.targetAccuracy)} · strike ${fmtPct(ss[i].stats.zonePct)} · '
              'avg target ${ss[i].stats.avgTargetWidthIn == null ? '—' : '${ss[i].stats.avgTargetWidthIn!.toStringAsFixed(1)} × ${ss[i].stats.avgTargetHeightIn!.toStringAsFixed(1)} in'}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 10),
        const Text('ACCURACY BY TARGET SIZE (compare bullpens fairly)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
        const SizedBox(height: 4),
        for (final b in SizeBucket.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              a.bySize[b] == null
                  ? '${b.label} (${b.detail}): no pitches yet'
                  : '${b.label} (${b.detail}): ${fmtPct(a.bySize[b]!.targetAccuracy)} on ${a.bySize[b]!.targetPitches} pitches',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 4),
        const Text('A higher accuracy at a bigger target is not the same as improving; check the size rows.',
            style: TextStyle(fontSize: 11, color: AppColors.colMuted)),
      ]),
    );
  }

  // ── bullpen vs. game ──────────────────────────────────────────

  Widget _compare(BullpenGameComparison c, AppSession app) {
    final min = BullpenThresholds.minPitchTypeSample;
    final gamePitchCount = c.rows.fold<int>(0, (n, r) => n + r.gamePitches);
    return _card(
      'Compare bullpens with games',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Bullpen strike % (landed in the zone) and game strike % (called/swung/fouled/in play) are defined differently, '
            'so they are never subtracted from each other. Each pitch is compared with your OWN average in that setting. '
            'Games here have no pitch locations, so there is no game target accuracy.',
            style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
        const SizedBox(height: 8),
        if (c.rows.isEmpty)
          const Text('No pitch data to compare yet.', style: TextStyle(color: AppColors.colMuted))
        else
          for (final r in c.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  PitchPill(type: r.pitchType, label: app.pitchTypeLabel(r.pitchType)),
                  const SizedBox(width: 8),
                  if (r.weakInBoth) _badge('Weak in both', AppColors.perfPoor)
                  else if (r.weakInBullpen == true) _badge('Weak in bullpen only', AppColors.perfBelowAvg)
                  else if (r.weakInGame == true) _badge('Weak in games only', AppColors.perfBelowAvg)
                  else if (r.bullpenEnough && r.gameEnough) _badge('Fine in both', AppColors.perfExcellent)
                  else _badge('Not enough data to compare', AppColors.colMuted),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Bullpen: ${r.bullpen == null ? 'no pitches' : '${r.bullpen!.pitches} pitches · strike ${fmtPct(r.bullpen!.zonePct)} · target ${fmtPct(r.bullpen!.targetAccuracy)}'}'
                  '${r.bullpen != null && !r.bullpenEnough ? ' (needs $min with landings)' : ''}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  'Games: ${r.gamePitches == 0 ? 'no pitches' : '${r.gamePitches} pitches · strike ${fmtPct(r.gameStrikePct)}'}'
                  '${r.gamePitches > 0 && !r.gameEnough ? ' (needs $min)' : ''}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ]),
            ),
        if (c.overallGameStrike != null || c.overallBullpenZone != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Your averages: bullpen strike ${fmtPct(c.overallBullpenZone)}, bullpen target ${fmtPct(c.overallBullpenAccuracy)}, '
                'game strike ${fmtPct(c.overallGameStrike)} ($gamePitchCount game pitches). '
                'A pitch counts as weak when it is ${BullpenThresholds.gapPoints.toStringAsFixed(0)}+ points below your own average with at least $min pitches.',
                style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
          ),
        const SizedBox(height: 10),
        const Text('ARE BULLPEN CHANGES SHOWING UP IN GAMES?',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
        const SizedBox(height: 4),
        if (c.checks.isEmpty)
          Text('Needs at least ${min * 2} bullpen pitches with landings for a pitch, across two or more bullpens.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.colMuted))
        else
          for (final k in c.checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${app.pitchTypeLabel(k.pitchType)}: bullpen '
                '${k.zoneDelta != null ? 'strike ${fmtPct(k.earlyZone)} → ${fmtPct(k.lateZone)}' : 'strike n/a'}'
                '${k.accuracyDelta != null ? ', target ${fmtPct(k.earlyAccuracy)} → ${fmtPct(k.lateAccuracy)}' : ''}. '
                '${k.gameDelta != null ? 'Games strike ${fmtPct(k.gameBeforeStrike)} (${k.gameBeforeN}) → ${fmtPct(k.gameAfterStrike)} (${k.gameAfterN}).' : 'Games: not enough pitches before/after (${k.gameBeforeN} / ${k.gameAfterN}).'}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
      ]),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.tint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
      );

  // ── what to work on next ──────────────────────────────────────

  Widget _workOnNext(RecommendationSet recs, AppSession app) {
    Widget part(String label, String text, {bool italic = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.brandOrangeDeep)),
            Text(text, style: TextStyle(fontSize: 13.5, fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
          ]),
        );

    return _card(
      'What to Work On Next',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (recs.insufficientData != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.colBorder)),
            child: Text(recs.insufficientData!, style: const TextStyle(fontSize: 13)),
          ),
        if (recs.findings.isEmpty && recs.insufficientData == null)
          const Text('Nothing stands out. No pitch is clearly behind your others, no miss direction dominates, and no setting disagrees with the other.',
              style: TextStyle(color: AppColors.colMuted)),
        for (final f in recs.findings)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.colBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              part('What happened', f.whatHappened),
              part('What it means', f.whatItMeans),
              if (f.possibleExplanation != null) part('Possible explanation (not measured)', f.possibleExplanation!, italic: true),
              part('What to do next', f.whatToDo),
              part('How to measure progress', f.howToMeasure),
            ]),
          ),
      ]),
    );
  }

  // ── recommended plan ──────────────────────────────────────────

  Widget _planCard(BullpenAnalysis ranged, AppSession app, BullpenStore store, List<PlanSetResult> lastResults) {
    final types = availablePitchTypes(app);
    final plan = _plan;

    void setPlan(BullpenPlan p) => setState(() => _plan = p);

    Future<void> editTarget(int i) async {
      final current = plan;
      if (current == null) return;
      final t = await showDialog<ZoneTarget>(
        context: context,
        builder: (ctx) => _TargetDialog(
          initial: current.sets[i].target,
          color: AppColors.pitchColor(current.sets[i].pitchType),
        ),
      );
      if (t != null) {
        final sets = [...current.sets];
        sets[i] = sets[i].copyWith(target: t);
        setPlan(current.copyWith(sets: sets));
      }
    }

    return _card(
      'Recommended Bullpen Plan',
      subtitle: 'Built from your bullpens, Game Mode attempts and game usage. Edit anything, then send it to the Bullpen tab.',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Focus', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in PlanFocus.values)
            ChoiceChip(
              label: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              selected: _focus == f,
              selectedColor: AppColors.brandOrangeDeep,
              labelStyle: TextStyle(color: _focus == f ? Colors.white : AppColors.ink),
              onSelected: (_) => setState(() => _focus = f),
            ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
            onPressed: () {
              final usage = [
                for (final r in StatsService.pitchBreakdown(app.pitches)) (r['pitchType'] as String).toLowerCase(),
              ];
              setState(() {
                _plan = PlanGenerator.generate(
                  focus: _focus,
                  analysis: ranged,
                  attempts: store.attempts,
                  availableTypes: types,
                  label: app.pitchTypeLabel,
                  gameUsageOrder: usage,
                );
                _planVersion++;
              });
            },
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text(plan == null ? 'Generate Plan' : 'Regenerate Plan'),
          ),
        ),
        if (plan != null) ...[
          const SizedBox(height: 10),
          Text('${plan.focus.label} plan · ${plan.sets.length} sets · ${plan.totalReps} pitches',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          for (final r in plan.rationale)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('• $r', style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < plan.sets.length; i++)
            Container(
              key: ValueKey('set-$i-$_planVersion'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.colBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('Set ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      isDense: true,
                      value: {...types, plan.sets[i].pitchType}.contains(plan.sets[i].pitchType) ? plan.sets[i].pitchType : types.first,
                      items: [
                        for (final t in {...types, plan.sets[i].pitchType})
                          DropdownMenuItem(value: t, child: Text(app.pitchTypeLabel(t))),
                      ],
                      onChanged: (v) {
                        final sets = [...plan.sets];
                        sets[i] = sets[i].copyWith(pitchType: v);
                        setPlan(plan.copyWith(sets: sets));
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fewer reps',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: plan.sets[i].reps <= 1
                        ? null
                        : () {
                            final sets = [...plan.sets];
                            sets[i] = sets[i].copyWith(reps: sets[i].reps - 1);
                            setPlan(plan.copyWith(sets: sets));
                          },
                  ),
                  Text('${plan.sets[i].reps}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  IconButton(
                    tooltip: 'More reps',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      final sets = [...plan.sets];
                      sets[i] = sets[i].copyWith(reps: sets[i].reps + 1);
                      setPlan(plan.copyWith(sets: sets));
                    },
                  ),
                ]),
                Row(children: [
                  Expanded(
                    child: Text(
                      'Aim: ${_aimName(plan.sets[i].target)} · target ${plan.sets[i].target.widthIn.toStringAsFixed(1)} × ${plan.sets[i].target.heightIn.toStringAsFixed(1)} in',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(onPressed: () => editTarget(i), child: const Text('Edit target')),
                ]),
                TextFormField(
                  initialValue: plan.sets[i].purpose,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(labelText: 'What this set improves', isDense: true),
                  onChanged: (v) {
                    final sets = [...plan.sets];
                    sets[i] = sets[i].copyWith(purpose: v);
                    _plan = plan.copyWith(sets: sets); // no rebuild: keeps the cursor in place
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Remove set'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.colError),
                    onPressed: plan.sets.length <= 1
                        ? null
                        : () {
                            final sets = [...plan.sets]..removeAt(i);
                            setState(() {
                              _plan = plan.copyWith(sets: sets);
                              _planVersion++;
                            });
                          },
                  ),
                ),
              ]),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add set'),
              onPressed: () {
                final p = _plan!;
                setState(() {
                  _plan = p.copyWith(sets: [
                    ...p.sets,
                    PlanSet(
                      pitchType: types.first,
                      reps: 10,
                      target: const ZoneTarget(0.5, 0.5, PlanGenerator.defaultSize, PlanGenerator.defaultSize),
                      purpose: 'Added by you.',
                    ),
                  ]);
                  _planVersion++;
                });
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save plan'),
              onPressed: () async {
                await store.savePlan(_plan);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan saved.')));
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Send to Bullpen'),
              onPressed: () async {
                final p = _plan!;
                store.sendPlanToBullpen(p);
                await store.savePlan(p);
              },
            ),
          ]),
        ],
        if (lastResults.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('YOUR LAST PLANNED BULLPEN: PLAN vs. RESULTS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
          const SizedBox(height: 4),
          for (final r in lastResults)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Set ${r.index + 1} ${app.pitchTypeLabel(r.planned.pitchType)}: ${r.thrown}/${r.planned.reps} reps · '
                'target ${fmtPct(r.stats.targetAccuracy)} · strike ${fmtPct(r.stats.zonePct)} · avg miss ${fmtIn(r.stats.avgDistanceIn)}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          const Text('Regenerating the plan uses these results: sets you hit well get smaller targets, sets you missed get larger ones.',
              style: TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
        ],
      ]),
    );
  }

  String _aimName(ZoneTarget t) {
    final col = t.x < 1 / 3 ? 0 : (t.x < 2 / 3 ? 1 : 2);
    final row = t.y > 2 / 3 ? 0 : (t.y > 1 / 3 ? 1 : 2);
    final inside = t.x >= 0 && t.x <= 1 && t.y >= 0 && t.y <= 1;
    return inside ? ChallengeRules.cellNames[row * 3 + col] : 'Outside the zone';
  }

  // ── game mode results ─────────────────────────────────────────

  Widget _gameModeResults(BullpenStore store, AppSession app) {
    final all = store.attempts;
    final summaries = summarizeChallenges(all);
    final streakBest = all.where((a) => a.mode == ChallengeMode.streak).fold<int>(0, (m, a) => a.score > m ? a.score : m);
    final accAttempts = all.where((a) => a.mode == ChallengeMode.accuracy).toList();
    final accThrown = accAttempts.fold<int>(0, (n, a) => n + a.pitchesThrown);
    final accHits = accAttempts.fold<int>(0, (n, a) => n + a.score);
    final failedCount = all.where((a) => !a.success).length;

    return _card(
      'Game Mode results',
      subtitle: 'Kept separate from bullpen sessions and game stats.',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (all.isEmpty)
          const Text('Play a challenge on the Bullpen tab to see results here.', style: TextStyle(color: AppColors.colMuted))
        else ...[
          StatCardGrid(children: [
            BigStatCard(label: 'Attempts', value: '${all.length}'),
            BigStatCard(label: 'Best streak', value: streakBest == 0 ? '—' : '$streakBest'),
            BigStatCard(
                label: 'Target hit %',
                value: accThrown == 0 ? '—' : fmtPct(accHits / accThrown * 100),
                note: accThrown == 0 ? null : '$accHits of $accThrown pitches'),
            BigStatCard(label: 'Failed attempts', value: '$failedCount'),
          ]),
          const SizedBox(height: 10),
          const Text('PROGRESS AT THE SAME DIFFICULTY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
          const SizedBox(height: 4),
          for (final s in summaries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.mode.label} · ${s.difficulty.label}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                Text(
                  '${s.attempts} attempts · ${s.passed} passed · ${s.failed} failed · best ${s.bestScore} (goal ${s.goal})'
                  '${s.recentPassRate == null ? '' : ' · last ${s.recent.length < 5 ? s.recent.length : 5}: ${fmtPct(s.recentPassRate)} passed'}'
                  '${s.priorPassRate == null ? '' : ' (before that: ${fmtPct(s.priorPassRate)})'}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _TargetDialog extends StatefulWidget {
  final ZoneTarget initial;
  final Color color;
  const _TargetDialog({required this.initial, required this.color});

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late ZoneTarget _t = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.dialogWidth(context, 460)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Edit target', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 6),
            const Text('Tap the zone to move the target. Use the sliders to change its width and height.',
                style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
            const SizedBox(height: 8),
            StrikeZone(
              semanticsLabel: 'Place target',
              rects: [ZoneRect(_t, AppColors.brandOrangeDeep)],
              onPick: (x, y) => setState(() => _t = ZoneTarget(x, y, _t.w, _t.h)),
            ),
            const SizedBox(height: 8),
            TargetSizeControls(width: _t.w, height: _t.h, onChanged: (w, h) => setState(() => _t = ZoneTarget(_t.x, _t.y, w, h))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context, _t),
                  child: const Text('Use target'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
