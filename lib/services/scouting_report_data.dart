import '../models/pitch_event.dart';
import 'stats_service.dart';
import 'scouting_game_plan.dart';

/// All derived numbers/heuristics shown on a Scouting Report, computed once
/// and shared by both the on-screen widget (`ScoutingReportScreen`) and the
/// PDF export (`ScoutingPdfService`) — so the PDF can never drift out of
/// sync with what's on screen.
class ScoutingReportData {
  final String team;
  final List<PitchEvent> data;
  final int gamesFaced;

  final OverviewStats stats;
  final List<Map<String, dynamic>> hitters;
  final List<Map<String, dynamic>> breakdown;
  final Map<String, dynamic> approach;
  final List<Map<String, dynamic>> seqs;
  final Map<String, dynamic>? topDamage;
  final Map<String, dynamic> cd;
  final List<Map<String, dynamic>> gameTrend;

  final int pa;
  final int xbh;
  final int hr;

  final Map<String, dynamic>? bestPitch;
  final Map<String, dynamic>? worstPitch;

  final int threatScore;
  final String threatLevel; // 'high' | 'medium' | 'low'

  final List<Map<String, dynamic>> bestSeqs;
  final List<Map<String, dynamic>> avoidSeqs;

  /// Top 5 hitters by OBP against, min 2 PA — same list shown in the
  /// "Key Hitters" card.
  final List<Map<String, dynamic>> keyHitters;

  /// Game-plan analysis (takeaways, hitter cards, situations, at-bat review).
  final ScoutingGamePlan plan;

  ScoutingReportData._({
    required this.team,
    required this.data,
    required this.gamesFaced,
    required this.stats,
    required this.hitters,
    required this.breakdown,
    required this.approach,
    required this.seqs,
    required this.topDamage,
    required this.cd,
    required this.gameTrend,
    required this.pa,
    required this.xbh,
    required this.hr,
    required this.bestPitch,
    required this.worstPitch,
    required this.threatScore,
    required this.threatLevel,
    required this.bestSeqs,
    required this.avoidSeqs,
    required this.keyHitters,
    required this.plan,
  });

  /// [history]: the full season-filtered pitch list, so batter matchup history
  /// and sequencing scores can see games outside this report's filter.
  factory ScoutingReportData.compute(String team, List<PitchEvent> data, {List<PitchEvent>? history}) {
    final stats = StatsService.overview(data);
    final hitters = StatsService.batterStats(data);
    final breakdown = StatsService.pitchBreakdown(data);
    final approach = StatsService.scoutingApproach(data);
    final seqs = StatsService.pitchSequencing(data, history: history);
    final topDamage = StatsService.topDamageCount(data);
    final cd = StatsService.countApproach(data);
    final gameTrend = StatsService.opponentGameTrend(data);
    final finals = StatsService.finalPAs(data);
    final xbh = finals.where((r) => {'2b', '3b', 'hr'}.contains(r.event.outcome)).length;
    final hr = finals.where((r) => r.event.outcome == 'hr').length;
    final pa = finals.length;
    final gamesFaced = {for (final p in data) p.gameNumber}.length;

    // Best/worst pitch (same logic as R's best_pitch_row / worst_pitch_row)
    final withWhiff = breakdown.where((r) => r['whiffPct'] != null && (r['n'] as int) >= 5).toList()
      ..sort((a, b) => (b['whiffPct'] as double).compareTo(a['whiffPct'] as double));
    final bestPitch = withWhiff.isNotEmpty ? withWhiff.first : null;
    final withAvg = breakdown.where((r) => r['avgAgainst'] != null).toList()
      ..sort((a, b) => (b['avgAgainst'] as double).compareTo(a['avgAgainst'] as double));
    final worstPitch = withAvg.isNotEmpty ? withAvg.first : null;

    // Threat level (same weighted heuristic as R's scout_metrics)
    int threatScore = 0;
    if (stats.avg != null && stats.avg! > 0.300) threatScore += 2;
    if (stats.avg != null && stats.avg! > 0.250) threatScore += 1;
    if (stats.bbPct != null && stats.bbPct! > 12) threatScore += 2;
    if (stats.bbPct != null && stats.bbPct! > 8) threatScore += 1;
    if (stats.kPct != null && stats.kPct! < 15) threatScore += 1;
    if (xbh >= 3) threatScore += 1;
    final threatLevel = threatScore >= 5 ? 'high' : (threatScore >= 3 ? 'medium' : 'low');

    final bestSeqs = List<Map<String, dynamic>>.from(seqs)
      ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final avoidSeqs = seqs.where((s) => (s['count'] as int) >= 2).toList()
      ..sort((a, b) => (a['score'] as double).compareTo(b['score'] as double));

    final keyHitters = hitters.where((h) => (h['pa'] as int) >= 2).toList()
      ..sort((a, b) {
        final ao = a['obp'] as double?;
        final bo = b['obp'] as double?;
        if (ao == null && bo == null) return 0;
        if (ao == null) return 1;
        if (bo == null) return -1;
        return bo.compareTo(ao);
      });

    final plan = ScoutingGamePlanBuilder.build(team, data,
        history: history, bestSeqs: bestSeqs, avoidSeqs: avoidSeqs);

    return ScoutingReportData._(
      team: team,
      data: data,
      gamesFaced: gamesFaced,
      stats: stats,
      hitters: hitters,
      breakdown: breakdown,
      approach: approach,
      seqs: seqs,
      topDamage: topDamage,
      cd: cd,
      gameTrend: gameTrend,
      pa: pa,
      xbh: xbh,
      hr: hr,
      bestPitch: bestPitch,
      worstPitch: worstPitch,
      threatScore: threatScore,
      threatLevel: threatLevel,
      bestSeqs: bestSeqs,
      avoidSeqs: avoidSeqs,
      keyHitters: keyHitters.take(5).toList(),
      plan: plan,
    );
  }
}
