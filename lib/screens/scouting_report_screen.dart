import '../widgets/orange_glow_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../models/pitch_event.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../services/scouting_report_data.dart';
import '../services/scouting_pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/scouting_plan_sections.dart';
import '../utils/responsive.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import '../widgets/baseball_field_painter.dart';
import '../widgets/year_filter_dropdown.dart';

class ScoutingReportScreen extends StatefulWidget {
  const ScoutingReportScreen({super.key});

  @override
  State<ScoutingReportScreen> createState() => _ScoutingReportScreenState();
}

const Map<String, String> _scoutingInfo = {
  'AVG': 'Calculation: Hits Allowed ÷ At-Bats\n\n'
      "This opponent's batting average against you. Lower is better.",
  'K%': 'Calculation: (Strikeouts ÷ Plate Appearances) × 100\n\n'
      'How often you struck this opponent out. Higher is better.',
  'BB%': 'Calculation: (Walks ÷ Plate Appearances) × 100\n\n'
      'How often you walked this opponent. Lower is better.',
  'Whiff%': 'Calculation: (Swinging Misses ÷ Total Swings) × 100\n\n'
      'How often this opponent swung and missed against you. Higher is better.',
};

String _fmtAvg(double v) {
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : '$s';
}

Color _textColorFor(Color bg) => (bg == AppColors.perfExcellent ||
        bg == AppColors.perfPoor ||
        bg == AppColors.perfBelowAvg)
    ? Colors.white
    : AppColors.colText;

class _ScoutingReportScreenState extends State<ScoutingReportScreen> {
  String? _team;
  String _gameNum = 'All';
  bool _generated = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final teams = session.knownTeams;
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == null || p.game == _team)
          .map((p) => p.gameNumber.toString())
          .toSet()
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _team,
                      decoration: const InputDecoration(labelText: 'Opponent'),
                      items: teams
                          .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _team = v;
                        _gameNum = 'All';
                        _generated = false;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _gameNum,
                      decoration: const InputDecoration(labelText: 'Game #'),
                      items: gameNums.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() {
                        _gameNum = v!;
                        _generated = false;
                      }),
                    ),
                  ),
                  const YearFilterDropdown(),
                  OrangeGlowButton(
                    onPressed: _team == null ? null : () => setState(() => _generated = true),
                    child: const Text('Generate Report'),
                  ),
                ]),
                const SizedBox(height: 10),
                const PerfTierLegend(),
              ],
            ),
          ),
        ),
        if (_generated && _team != null)
          Builder(builder: (context) => _ScoutingReportBody(
                team: _team!,
                history: session.filteredPitches,
                data: () {
                  var data = session.filteredPitches.where((p) => p.game == _team).toList();
                  if (_gameNum != 'All') {
                    final gn = int.tryParse(_gameNum);
                    data = data.where((p) => p.gameNumber == gn).toList();
                  }
                  return data;
                }(),
              ))
        else
          const GlowCard(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Select an opponent and generate a report.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
      ],
    );
  }
}

class _ScoutingReportBody extends StatefulWidget {
  final String team;
  final List<PitchEvent> data;
  final List<PitchEvent> history;
  const _ScoutingReportBody({required this.team, required this.data, required this.history});

  @override
  State<_ScoutingReportBody> createState() => _ScoutingReportBodyState();
}

class _ScoutingReportBodyState extends State<_ScoutingReportBody> {
  bool _exporting = false;

  Future<void> _downloadPdf(ScoutingReportData r) async {
    setState(() => _exporting = true);
    try {
      final bytes = await ScoutingPdfService.generate(r);
      final safeTeam = r.team.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      await Printing.sharePdf(bytes: bytes, filename: 'scouting_report_$safeTeam.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ScoutingReportData.compute(widget.team, widget.data, history: widget.history);
    final stats = r.stats;
    final gameTrend = r.gameTrend;
    final cd = r.cd;
    final xbh = r.xbh;
    final hr = r.hr;
    final pa = r.pa;
    final gamesFaced = r.gamesFaced;
    final bestPitch = r.bestPitch;
    final worstPitch = r.worstPitch;
    final threatLevel = r.threatLevel;
    final threatColor = threatLevel == 'high'
        ? AppColors.perfPoor
        : (threatLevel == 'medium' ? AppColors.perfAverage : AppColors.perfExcellent);
    final threatTc = threatLevel == 'medium' ? AppColors.colText : Colors.white;
    final bestSeqs = r.bestSeqs;
    final avoidSeqs = r.avoidSeqs;
    final breakdown = r.breakdown;
    final approach = r.approach;
    final topDamage = r.topDamage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Summary card ──────────────────────────────────────────
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResponsiveRow(stackedGap: 8, stackedCrossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text('Scouting: ${r.team.toUpperCase()}  •  $gamesFaced game(s) faced',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : () => _downloadPdf(r),
                    icon: _exporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                          )
                        : const Icon(Icons.picture_as_pdf, size: 16),
                    label: Text(_exporting ? 'Generating…' : 'Download PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.ink, width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatHoldInfo(
                    title: 'Threat Level',
                    description: composeHoldInfo(
                      what: 'A quick read on how dangerous this lineup is, built from a point score:\n'
                          '• AVG over .250: +1 (over .300: +3 in total)\n'
                          '• BB% over 8%: +1 (over 12%: +3 in total)\n'
                          '• K% under 15%: +1\n'
                          '• 3 or more extra-base hits: +1\n'
                          'This team: ${r.threatScore} point(s) → ${threatLevel.toUpperCase()}.',
                      colorGuide: [
                        swatchLine(AppColors.perfPoor, 'Red - HIGH threat: 5 or more points'),
                        swatchLine(AppColors.perfAverage, 'Yellow - MEDIUM threat: 3 to 4 points'),
                        swatchLine(AppColors.perfExcellent, 'Dark green - LOW threat: 0 to 2 points'),
                      ].join('\n'),
                    ),
                    child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(color: threatColor, borderRadius: BorderRadius.circular(20)),
                    child: Text('${threatLevel.toUpperCase()} THREAT',
                        style: TextStyle(color: threatTc, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // Headline numbers: ERA / WHIP / AVG Against / SLG Against.
                ResponsiveRow(stackedColumns: 2, stackedGap: 8, children: [
                  Expanded(
                      child: StatSummaryCard(
                          label: 'ERA',
                          value: stats.era?.toStringAsFixed(2) ?? 'N/A',
                          statKey: 'ERA',
                          rawValue: stats.era,
                          description: 'Calculation: (Earned Runs ÷ Innings Pitched) × 9\n\nRuns the pitcher allows per nine innings against this opponent. Lower is better.')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: StatSummaryCard(
                          label: 'WHIP',
                          value: stats.whip?.toStringAsFixed(2) ?? 'N/A',
                          statKey: 'WHIP',
                          rawValue: stats.whip,
                          description: 'Calculation: (Walks + Hits) ÷ Innings Pitched\n\nBaserunners allowed per inning against this opponent. Lower is better.')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: StatSummaryCard(
                          label: 'AVG Against',
                          value: stats.avg != null ? _fmtAvg(stats.avg!) : 'N/A',
                          statKey: 'AVG',
                          rawValue: stats.avg,
                          description: _scoutingInfo['AVG'])),
                  const SizedBox(width: 8),
                  Expanded(
                      child: StatSummaryCard(
                          label: 'SLG Against',
                          value: stats.slg != null ? _fmtAvg(stats.slg!) : 'N/A',
                          statKey: 'SLG',
                          rawValue: stats.slg,
                          description: 'Calculation: Total Bases ÷ At-Bats\n\nPower this opponent shows against you; extra-base hits count for more. Lower is better.')),
                ]),
                const SizedBox(height: 10),
                ResponsiveRow(stackedColumns: 3, children: [
                  Expanded(
                      child: StatVBox(
                          label: 'PA',
                          value: '$pa',
                          background: AppColors.tint,
                          description: 'Plate appearances this team has had against you.',
                          colorGuide: swatchLine(AppColors.tint, 'Cream: a plain count, not a good/bad grade, so there are no cutoffs.'))),
                  const SizedBox(width: 6),
                  Expanded(
                      child: StatVBox(
                          label: 'AVG',
                          value: stats.avg?.toStringAsFixed(3) ?? 'N/A',
                          background: perfHex('AVG', stats.avg),
                          textColor: _textColorFor(perfHex('AVG', stats.avg)),
                          description: _scoutingInfo['AVG'], statKey: 'AVG')),
                  const SizedBox(width: 6),
                  Expanded(
                      child: StatVBox(
                          label: 'K%',
                          value: stats.kPct != null ? '${stats.kPct}%' : 'N/A',
                          background: perfHex('K_pct', stats.kPct),
                          textColor: _textColorFor(perfHex('K_pct', stats.kPct)),
                          description: _scoutingInfo['K%'], statKey: 'K_pct')),
                  const SizedBox(width: 6),
                  Expanded(
                      child: StatVBox(
                          label: 'BB%',
                          value: stats.bbPct != null ? '${stats.bbPct}%' : 'N/A',
                          background: perfHex('BB_pct', stats.bbPct),
                          textColor: _textColorFor(perfHex('BB_pct', stats.bbPct)),
                          description: _scoutingInfo['BB%'], statKey: 'BB_pct')),
                  const SizedBox(width: 6),
                  Expanded(
                      child: StatVBox(
                          label: 'Whiff%',
                          value: stats.whiffPct != null ? '${stats.whiffPct}%' : 'N/A',
                          background: perfHex('whiff_pct', stats.whiffPct),
                          textColor: _textColorFor(perfHex('whiff_pct', stats.whiffPct)),
                          description: _scoutingInfo['Whiff%'], statKey: 'whiff_pct')),
                  const SizedBox(width: 6),
                  Expanded(
                      child: StatVBox(
                          label: 'XBH',
                          value: '$xbh',
                          background: const Color(0xFFFEF2F2),
                          textColor: AppColors.colError,
                          description: 'Extra-base hits (doubles, triples and home runs) this team has hit against you.',
                          colorGuide: swatchLine(const Color(0xFFFEF2F2),
                              'Pink box, red text: a fixed highlight color for damage. It never changes with the value, so there are no cutoffs. (3 or more XBH adds a point to the Threat Level.)'))),
                ]),
                const SizedBox(height: 10),
                ResponsiveRow(stackedGap: 8, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _pillet(
                      'Strength',
                      bestPitch != null
                          ? 'Best pitch: ${(bestPitch['pitchType'] as String).toUpperCase()} (${bestPitch['whiffPct']}% whiff)'
                          : (stats.kPct != null && stats.kPct! >= 20 ? 'Getting K\'s — K%: ${stats.kPct}%' : 'Build on what\'s working'),
                      const Color(0xFFF0FDF4),
                      AppColors.perfExcellent,
                      info: composeHoldInfo(
                        what: 'The pitcher\'s best asset against this team: the pitch with the highest Whiff % (at least 5 pitches thrown); if there isn\'t one, a K% note when K% is 20% or higher.',
                        colorGuide: swatchLine(AppColors.perfExcellent, 'Green box: always marks a strength. It is a fixed label color, not a graded cutoff.'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _pillet(
                      'Weakness',
                      stats.bbPct != null && stats.bbPct! > 12
                          ? 'Walk rate high — ${stats.bbPct}% BB'
                          : (worstPitch != null
                              ? 'Most hittable: ${(worstPitch['pitchType'] as String).toUpperCase()} (${_fmtAvg(worstPitch['avgAgainst'] as double)} AVG)'
                              : 'Hold the line — no major leaks'),
                      const Color(0xFFFEF2F2),
                      AppColors.colError,
                      info: composeHoldInfo(
                        what: 'The biggest leak against this team: a walk-rate warning when BB% is over 12%; otherwise the pitch with the highest batting average against.',
                        colorGuide: swatchLine(AppColors.colError, 'Red box: always marks a weakness. It is a fixed label color, not a graded cutoff.'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _pillet(
                      'Quick Plan',
                      threatLevel == 'high'
                          ? 'Attack the zone. Win pitch 1. Use your best whiff pitch in 2-strike counts.'
                          : (threatLevel == 'medium'
                              ? 'Limit XBH. Mix speeds. Trust your sequencing.'
                              : 'Cruise mode. Throw strikes. Finish ABs efficiently.'),
                      AppColors.tint,
                      AppColors.ink,
                      info: composeHoldInfo(
                        what: 'A one-line plan chosen by the Threat Level (high, medium or low).',
                        colorGuide: swatchLine(AppColors.tint, 'Cream box: neutral. The plan changes with the Threat Level, the color does not.'),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        // ── Game Overview + Key Takeaways (added) ─────────────────
        PlanOverviewCard(r),
        KeyTakeawaysCard(r.plan),
        // ── What Works / What Gets Hit ────────────────────────────
        ResponsiveRow(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: GlowCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('What Works vs This Team', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (bestPitch != null)
                      _tinySeqCard(
                        '${(bestPitch['pitchType'] as String).toUpperCase()} — highest whiff rate',
                        'Whiff%: ${bestPitch['whiffPct']}% against this team',
                        true,
                        rule: 'the pitch with the highest Whiff % against this team (among pitches thrown at least 5 times).',
                      ),
                    for (final s in bestSeqs.take(3))
                      _tinySeqCard(s['seq'] as String,
                          'Score ${s['score']}  |  Out%: ${s['outPct']}%  K%: ${s['kPct']}%  n=${s['count']}', true,
                          rule: 'one of the 3 highest-scoring sequences against this team (see Pitch Sequencing for how Score is built).'),
                    if (cd['fpsPct'] != null && (cd['fpsPct'] as double) >= 60)
                      _tinySeqCard('F-Strike% — ${cd['fpsPct']}%',
                          'After a first-pitch strike, OBP: ${cd['fpsOBP'] != null ? (cd['fpsOBP'] as double).toStringAsFixed(3) : 'N/A'}', true,
                          rule: 'only shown when F-Strike% is 60% or higher.'),
                    if (cd['aheadOBP'] != null && (cd['aheadOBP'] as double) < 0.300)
                      _tinySeqCard('Ahead in count → low damage',
                          'OBP when pitcher ahead: ${(cd['aheadOBP'] as double).toStringAsFixed(3)}', true,
                          rule: 'only shown when OBP allowed while ahead in the count is under .300.'),
                    if (bestPitch == null && bestSeqs.isEmpty)
                      const Text('Not enough data yet for this opponent.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GlowCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('What Gets Hit', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (worstPitch != null)
                      _tinySeqCard(
                        '${(worstPitch['pitchType'] as String).toUpperCase()} — most hittable',
                        'AVG: ${_fmtAvg(worstPitch['avgAgainst'] as double)} — reduce usage in hitter counts',
                        false,
                        rule: 'the pitch with the highest batting average against.',
                      ),
                    for (final s in avoidSeqs.take(2))
                      if ((s['outPct'] as double) < 60)
                        _tinySeqCard(s['seq'] as String,
                            'Score ${s['score']}  |  Out%: ${s['outPct']}%  n=${s['count']}', false,
                            rule: 'one of the 2 lowest-scoring sequences seen at least 2 times, shown only when its Out% is under 60%.'),
                    if (topDamage != null)
                      _tinySeqCard('Count ${topDamage['count']} — most damage',
                          'OBP: ${(topDamage['obp'] as double).toStringAsFixed(3)} in ${topDamage['n']} PA', false,
                          rule: 'the count where hitters have reached base the most against you.'),
                    if (cd['behindOBP'] != null && (cd['behindOBP'] as double) > 0.400)
                      _tinySeqCard('Behind in count → big trouble',
                          'OBP when pitcher behind: ${(cd['behindOBP'] as double).toStringAsFixed(3)}', false,
                          rule: 'only shown when OBP allowed while behind in the count is over .400.'),
                    if (xbh >= 3)
                      _tinySeqCard('Extra-base power threat',
                          '$xbh XBH including $hr HR — keep the ball down', false,
                          rule: 'only shown when this team has 3 or more extra-base hits.'),
                    if (worstPitch == null && topDamage == null && xbh < 3)
                      const Text('No major damage patterns found yet.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ]),
        // ── Their Approach / Attack Plan ──────────────────────────
        ResponsiveRow(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: GlowCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Their Approach', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _approachRow('Aggressive early (swings pitch 1)?', approach['aggressiveEarly'] as bool?, true),
                    _approachRow('Chase off-speed (high whiff on CV/CH/SL)?', approach['chaseOffspeed'] as bool?, false),
                    _approachRow('Sit on fastball in hitter counts?', approach['sitFastball'] as bool?, true),
                    const SizedBox(height: 10),
                    const Text('AVG by Pitch Type vs You', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
                    const SizedBox(height: 4),
                    for (final row in breakdown.where((b) => b['avgAgainst'] != null))
                      PerfStatBar(
                        label: (row['pitchType'] as String).toUpperCase(),
                        value: _fmtAvg(row['avgAgainst'] as double),
                        color: perfHex('AVG', row['avgAgainst'] as double?),
                        description: 'Batting average this team has against your ${(row['pitchType'] as String).toUpperCase()}: hits ÷ at-bats.',
                        scaleHint: statScaleHint('AVG'),
                        statKey: 'AVG',
                        rawValue: row['avgAgainst'] as double?,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GlowCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Attack Plan', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _step(1, cd['fpsPct'] != null && (cd['fpsPct'] as double) >= 60
                        ? 'Continue leading with strikes — your first-pitch strike rate is working.'
                        : 'Prioritize a fastball strike on pitch 1 — F-Strike% needs improvement.'),
                    _step(2, worstPitch != null
                        ? 'Minimize ${(worstPitch['pitchType'] as String).toUpperCase()} in hitter counts (AVG: ${_fmtAvg(worstPitch['avgAgainst'] as double)}).'
                        : 'No single pitch stands out as a problem — maintain your mix.'),
                    _step(3, bestPitch != null
                        ? 'In 0-2 / 1-2 counts, go to ${(bestPitch['pitchType'] as String).toUpperCase()} — ${bestPitch['whiffPct']}% whiff rate.'
                        : 'Use your highest-whiff pitch in two-strike counts.'),
                    _step(4, stats.bbPct != null && stats.bbPct! > 12
                        ? 'Walk rate is ${stats.bbPct}% — this lineup works counts. Challenge them early.'
                        : 'Walk rate under control. Maintain zone aggression.'),
                    _step(5, approach['chaseOffspeed'] == true
                        ? 'This lineup chases off-speed. Use it as a put-away weapon.'
                        : (approach['chaseOffspeed'] == false
                            ? 'This lineup lays off off-speed. Win with fastball strikes.'
                            : 'Off-speed chase tendency unclear — test it early.')),
                    if (topDamage != null)
                      _step(6, 'Be careful at the ${topDamage['count']} count (OBP: ${(topDamage['obp'] as double).toStringAsFixed(3)}). Avoid predictable patterns here.'),
                  ],
                ),
              ),
            ),
          ),
        ]),
        // ── Team Tendencies + Pitch Selection Strategy (added) ────
        TeamTendenciesCard(r.plan),
        PitchStrategyCard(r),
        // ── Best Hitters ───────────────────────────────────────────
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Key Hitters', style: TextStyle(fontWeight: FontWeight.w800)),
                const Text('Ranked by OBP against you. Focus on hitters with 2+ PA.',
                    style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                if (r.keyHitters.isEmpty)
                  const Text('Need more PA data.', style: TextStyle(color: Colors.grey))
                else
                  for (final h in r.keyHitters) _hitterCard(h),
              ],
            ),
          ),
        ),
        // ── Lineup, hitter reports, situations (added) ────────────
        LineupBreakdownCard(r.plan),
        HitterReportsCard(r.plan),
        SituationalPlanCard(r.plan),
        // ── Spray chart + Adjustment Notes ────────────────────────
        ResponsiveRow(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: GlowCard(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('Spray Chart vs This Team', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    AspectRatio(
                      aspectRatio: 1,
                      child: SprayFieldSurface(
                        sprayPoints: widget.data.where((p) => p.xCoord != null).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GlowCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Adjustment Notes', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (gameTrend.length < 2) ...[
                      _tinySeqCard('First encounter', 'No prior history to adjust from. Use the general plan above.', true,
                          rule: 'shown when there are fewer than 2 games to compare, so no trend is being graded.'),
                      const SizedBox(height: 6),
                      const Text(
                        '• Establish fastball strikes early\n'
                        '• Test off-speed in 0-1 and 1-1 counts\n'
                        '• Watch swing tendencies and adjust by the 3rd PA\n'
                        '• Check the spray chart mid-game for pull/oppo tendencies',
                        style: TextStyle(fontSize: 12, height: 1.6),
                      ),
                    ] else ...[
                      Builder(builder: (context) {
                        final avgs = gameTrend.map((g) => g['avg'] as double?).toList();
                        final kpcts = gameTrend.map((g) => g['kPct'] as double?).toList();
                        double? avgTrend;
                        double? kTrend;
                        if (avgs.every((v) => v != null) && avgs.length >= 2) {
                          avgTrend = avgs.last! - avgs.first!;
                        }
                        if (kpcts.every((v) => v != null) && kpcts.length >= 2) {
                          kTrend = kpcts.last! - kpcts.first!;
                        }
                        final items = <Widget>[];
                        if (avgTrend != null) {
                          if (avgTrend > 0.040) {
                            items.add(_tinySeqCard('AVG trending UP (${avgTrend > 0 ? '+' : ''}${avgTrend.toStringAsFixed(3)})',
                                'This team is hitting you better each game. Mix looks predictable.', false,
                                rule: 'the team\'s AVG rose by more than .040 from the first game to the latest.'));
                          } else if (avgTrend < -0.040) {
                            items.add(_tinySeqCard('AVG trending DOWN (${avgTrend.toStringAsFixed(3)})',
                                'Your approach is working better over time. Stay the course.', true,
                                rule: 'the team\'s AVG fell by more than .040 from the first game to the latest.'));
                          }
                        }
                        if (kTrend != null) {
                          if (kTrend > 5) {
                            items.add(_tinySeqCard('K% trending UP (+${kTrend.toStringAsFixed(1)}%)',
                                'You are generating more swing-and-miss each game.', true,
                                rule: 'the team\'s K% rose by more than 5 points from the first game to the latest.'));
                          } else if (kTrend < -5) {
                            items.add(_tinySeqCard('K% trending DOWN (${kTrend.toStringAsFixed(1)}%)',
                                'This lineup is making more contact — vary your put-away pitch.', false,
                                rule: 'the team\'s K% fell by more than 5 points from the first game to the latest.'));
                          }
                        }
                        if (items.isEmpty) {
                          items.add(const Text('No significant trends detected yet.', style: TextStyle(color: Colors.grey, fontSize: 12)));
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
                      }),
                      const SizedBox(height: 8),
                      const Text('Game-by-game performance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
                      const SizedBox(height: 4),
                      Table(
                        border: TableBorder.all(color: AppColors.colBorder),
                        children: [
                          TableRow(decoration: const BoxDecoration(color: AppColors.ink), children: [
                            _hc('Game'), _hc('AVG'), _hc('K%'), _hc('BB%'),
                          ]),
                          for (final g in gameTrend)
                            TableRow(children: [
                              _cell('G${g['game']}'),
                              _cellColored(g['avg'] != null ? _fmtAvg(g['avg'] as double) : '—', perfHex('AVG', g['avg'] as double?), statKey: 'AVG', statName: 'AVG'),
                              _cellColored(g['kPct'] != null ? '${g['kPct']}%' : '—', perfHex('K_pct', g['kPct'] as double?), statKey: 'K_pct', statName: 'K%'),
                              _cellColored(g['bbPct'] != null ? '${g['bbPct']}%' : '—', perfHex('BB_pct', g['bbPct'] as double?), statKey: 'BB_pct', statName: 'BB%'),
                            ]),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ]),
        // ── Previous Matchup Review (added) ───────────────────────
        MatchupReviewCard(r),
      ],
    );
  }
}

Widget _pillet(String title, String body, Color bg, Color titleColor, {String? info}) {
  final box = _pilletBox(title, body, bg, titleColor);
  if (info == null) return box;
  return StatHoldInfo(title: title, description: info, child: box);
}

Widget _pilletBox(String title, String body, Color bg, Color titleColor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: titleColor.withOpacity(0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 3),
        Text(body, style: const TextStyle(fontSize: 12.5)),
      ]),
    );

Widget _tinySeqCard(String head, String sub, bool good, {String? rule}) {
  final box = _tinySeqBox(head, sub, good);
  return StatHoldInfo(
    title: head,
    description: composeHoldInfo(
      what: '$head\n$sub',
      colorGuide: swatchLine(
        good ? AppColors.colSuccess : AppColors.colError,
        '${good ? 'Green' : 'Red'} card: ${rule ?? (good ? 'a point in the pitcher\'s favor.' : 'a problem area to fix.')} '
            'The card color shows which side it falls on; it is not a numeric grade.',
      ),
    ),
    child: box,
  );
}

Widget _tinySeqBox(String head, String sub, bool good) => Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: good ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        border: Border.all(color: good ? AppColors.colSuccess : AppColors.colError, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(head, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: good ? AppColors.perfExcellent : AppColors.colError)),
        Text(sub, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
      ]),
    );

Widget _approachRow(String label, bool? val, bool yesIsBad) {
  Widget badge;
  final badgeGuide = [
    swatchLine(yesIsBad ? AppColors.colError : AppColors.perfExcellent,
        '${yesIsBad ? 'Red' : 'Dark green'} YES: this tendency is present, and it ${yesIsBad ? 'works against you' : 'works in your favor'}.'),
    swatchLine(yesIsBad ? AppColors.perfExcellent : AppColors.colMuted,
        '${yesIsBad ? 'Dark green' : 'Gray'} NO: this tendency is not present${yesIsBad ? ', which is good for you' : ''}.'),
    swatchLine(AppColors.colMuted, 'Gray N/A: not enough data to tell.'),
  ].join('\n');
  if (val == null) {
    badge = const _Badge(text: 'N/A', color: AppColors.colMuted);
  } else if (val) {
    badge = _Badge(text: 'YES', color: yesIsBad ? AppColors.colError : AppColors.perfExcellent);
  } else {
    badge = _Badge(text: 'NO', color: yesIsBad ? AppColors.perfExcellent : AppColors.colMuted);
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
      StatHoldInfo(
        title: label,
        description: composeHoldInfo(
          what: 'A yes/no read on this team\'s approach, from their swing and pitch-result data.',
          colorGuide: badgeGuide,
        ),
        child: badge,
      ),
    ]),
  );
}

Widget _step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
          child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4))),
      ]),
    );

Widget _hitterCard(Map<String, dynamic> h) {
  final avg = h['avg'] as double?;
  final obp = h['obp'] as double?;
  final avgBg = perfHex('AVG', avg);
  final obpBg = perfHex('OBP_allowed', obp);
  final pa = h['pa'] as int;
  final k = h['k'] as int;
  final bb = h['bb'] as int;
  final xbh = h['xbh'] as int;
  final weakness = (avg != null && avg < 0.200)
      ? 'Weak hitter — attack the zone'
      : (pa > 0 && k / pa >= 0.30)
          ? 'High K rate — use your put-away pitch'
          : (avg != null && avg > 0.320)
              ? 'Dangerous bat — vary pitch selection'
              : 'Standard approach';
  final strength = bb >= 2
      ? 'Patient — $bb BB (${pa > 0 ? (bb / pa * 100).round() : 0}% BB)'
      : (xbh >= 2 ? 'Power — $xbh XBH' : (obp != null && obp > 0.400 ? 'Gets on base' : 'No standout strength'));
  final plan = (avg != null && avg < 0.200)
      ? 'Challenge — throw strikes'
      : (bb >= 2 ? 'Limit walks — throw strikes early' : (xbh >= 2 ? 'Keep the ball down' : 'Standard sequencing'));

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(border: Border.all(color: AppColors.tint, width: 2), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: CircleAvatar(
            backgroundColor: AppColors.ink,
            child: Text('#${h['jersey']}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ),
        _miniStat('OBP', obp != null ? obp.toStringAsFixed(3) : '—', obpBg,
            statKey: 'OBP_allowed', note: 'OBP is graded on the OBP-allowed scale, where lower is better for the pitcher.'),
        _miniStat('AVG', avg != null ? avg.toStringAsFixed(3) : '—', avgBg, statKey: 'AVG'),
        _miniStat('PA', '$pa', AppColors.tint),
        _miniStat('XBH', '$xbh', const Color(0xFFFEF2F2)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        _tagBox('Strength', strength, const Color(0xFFFEF2F2), AppColors.colError),
        _tagBox('Exploit', weakness, const Color(0xFFF0FDF4), AppColors.perfExcellent),
        _tagBox('Plan', plan, AppColors.tint, AppColors.ink),
      ]),
    ]),
  );
}

Widget _miniStat(String label, String value, Color bg, {String? statKey, String? note}) {
  final box = _miniStatBox(label, value, bg);
  String? guide;
  if (statKey != null) {
    guide = statColorGuide(statKey, note: note);
  } else if (label == 'XBH') {
    guide = swatchLine(bg, 'Pink: a fixed highlight color for extra-base hits; it does not change with the value, so there are no cutoffs.');
  } else {
    guide = swatchLine(bg, 'Cream: a plain count, not a good/bad grade, so there are no cutoffs.');
  }
  final what = label == 'OBP'
      ? 'On-base percentage this hitter has against you (hits + walks + hit-by-pitches ÷ plate appearances).'
      : label == 'AVG'
          ? 'Batting average this hitter has against you: hits ÷ at-bats.'
          : label == 'PA'
              ? 'Plate appearances this hitter has had against you.'
              : 'Extra-base hits (doubles, triples, home runs) this hitter has against you.';
  return StatHoldInfo(
    title: label,
    description: composeHoldInfo(what: what, colorGuide: guide),
    child: box,
  );
}

Widget _miniStatBox(String label, String value, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      constraints: const BoxConstraints(minWidth: 46),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _textColorFor(bg).withOpacity(0.75))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _textColorFor(bg))),
      ]),
    );

Widget _tagBox(String label, String text, Color bg, Color labelColor) {
  final info = label == 'Strength'
      ? 'What this hitter does well against you: patient (2 or more walks), power (2 or more XBH), or gets on base (OBP over .400).\nRed box: marks a hitter strength, a danger for the pitcher. Fixed label color, not a graded cutoff.'
      : label == 'Exploit'
          ? 'Where the pitcher can attack: weak hitter (AVG under .200), high K rate (30% or more), or dangerous bat (AVG over .320).\nGreen box: marks an opportunity for the pitcher. Fixed label color, not a graded cutoff.'
          : 'The suggested plan for this hitter.\nCream box: neutral. The color does not change.';
  return StatHoldInfo(
    title: label,
    description: info,
    child: _tagBoxBox(label, text, bg, labelColor),
  );
}

Widget _tagBoxBox(String label, String text, Color bg, Color labelColor) => Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11.5, color: AppColors.colText),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(color: labelColor, fontWeight: FontWeight.w800)),
            TextSpan(text: text),
          ],
        ),
      ),
    );

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

Widget _hc(String text) => Padding(
      padding: const EdgeInsets.all(6),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
    );

Widget _cell(String text) => Padding(
      padding: const EdgeInsets.all(6),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );

Widget _cellColored(String text, Color color, {String? statKey, String? statName}) {
  final box = _cellColoredBox(text, color);
  if (statKey == null) return box;
  return StatHoldInfo(
    title: statName ?? statKey,
    description: composeHoldInfo(
      what: 'This team\'s ${statName ?? statKey} in this game.\n\nThis game: $text → ${colorNameOf(color)}.',
      colorGuide: statColorGuide(statKey),
    ),
    child: box,
  );
}

Widget _cellColoredBox(String text, Color color) => Container(
      color: color,
      padding: const EdgeInsets.all(6),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: (color == AppColors.perfExcellent || color == AppColors.perfPoor || color == AppColors.perfBelowAvg)
                  ? Colors.white
                  : AppColors.colText)),
    );
