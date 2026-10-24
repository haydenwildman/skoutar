import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glow.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/year_filter_dropdown.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  String _team = 'All';
  String _gameNum = 'All';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    var data = session.filteredPitches;
    if (_team != 'All') data = data.where((p) => p.game == _team).toList();
    if (_gameNum != 'All') {
      final gn = int.tryParse(_gameNum);
      data = data.where((p) => p.gameNumber == gn).toList();
    }
    final stats = StatsService.overview(data);
    final teams = ['All', ...session.knownTeams];
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == 'All' || p.game == _team)
          .map((p) => p.gameNumber.toString())
          .toSet()
    ];

    const descriptions = <String, String>{
      'IP': 'Calculation: Outs Recorded ÷ 3\n\n'
          'Innings Pitched — total outs recorded divided by 3. Includes strikeouts, '
          'batted-ball outs, double plays, and pickoffs/throwouts.',
      'ERA': 'Calculation: (Earned Runs × 9) ÷ Innings Pitched\n\n'
          'Earned Run Average — earned runs allowed per 9 innings. Lower is better; '
          'the classic measure of run prevention.',
      'WHIP': 'Calculation: (Walks + Hits) ÷ Innings Pitched\n\n'
          'Walks + Hits per Inning Pitched. Measures how many baserunners you allow '
          'per inning. Lower is better.',
      'AVG Against': 'Calculation: Hits Allowed ÷ At-Bats\n\n'
          'Opponent Batting Average — how often batters get a hit against you. '
          'Lower is better.',
      'SLG Against': 'Calculation: Total Bases Allowed ÷ At-Bats\n\n'
          'Opponent Slugging % — measures the power (not just frequency) of contact '
          'allowed. Lower is better.',
      'P/PA': 'Calculation: Total Pitches ÷ Plate Appearances\n\n'
          "Pitches per Plate Appearance — a measure of efficiency; lower means you're "
          'working batters faster.',
      'K%': 'Calculation: (Strikeouts ÷ Plate Appearances) × 100\n\n'
          'Strikeout Percentage — how often you strike batters out. Higher is better.',
      'BB%': 'Calculation: (Walks ÷ Plate Appearances) × 100\n\n'
          'Walk Percentage — how often you walk batters. Lower is better.',
      'K-BB%': 'Calculation: K% − BB%\n\n'
          'Strikeout-minus-Walk Percentage — a single number combining strikeout and '
          'command ability; considered one of the best predictors of pitching '
          'success. Higher is better.',
      'Whiff%': 'Calculation: (Swinging Misses ÷ Total Swings) × 100\n\n'
          'Swinging Strike Percentage — how often a swing results in a miss. Higher '
          'is better.',
      'F-Strike%': 'Calculation: First-Pitch Strikes ÷ Total Plate Appearances × 100\n\n'
          'First-Pitch Strike Percentage — pitches of a plate appearance that were '
          'strikes (called, swinging, foul, or in play), out of total plate '
          'appearances. Getting ahead in the count early. Higher is better.',
    };

    // `prominent` makes the number the focal point of each bar (larger value,
    // slightly larger benchmark text) while the label stays the supporting
    // text. Only the Overview opts in; other screens keep the standard look.
    Widget bar(String label, String value, Color bg, [String? statKey, double? rawValue]) => PerfStatBar(
          label: label,
          value: value,
          color: bg,
          description: descriptions[label],
          scaleHint: statKey != null ? statScaleHint(statKey) : null,
          statKey: statKey,
          rawValue: rawValue,
          prominent: true,
        );

    final keyStatsCard = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Key Stats', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar('IP', stats.ipDisplay, AppColors.tint),
                bar('ERA', stats.era?.toStringAsFixed(2) ?? 'N/A', perfHex('ERA', stats.era), 'ERA', stats.era),
                bar('WHIP', stats.whip?.toStringAsFixed(3) ?? 'N/A', perfHex('WHIP', stats.whip), 'WHIP', stats.whip),
                bar('AVG Against', stats.avg?.toStringAsFixed(3) ?? 'N/A', perfHex('AVG', stats.avg), 'AVG', stats.avg),
                bar('SLG Against', stats.slg?.toStringAsFixed(3) ?? 'N/A', perfHex('SLG', stats.slg), 'SLG', stats.slg),
                bar('P/PA', stats.ppa?.toStringAsFixed(2) ?? 'N/A', perfHex('PPA', stats.ppa), 'PPA', stats.ppa),
              ],
            ),
          ],
        ),
      ),
    );

    final rateStatsCard = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rate Stats', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar('K%', stats.kPct != null ? '${stats.kPct}%' : 'N/A', perfHex('K_pct', stats.kPct), 'K_pct', stats.kPct),
                bar('BB%', stats.bbPct != null ? '${stats.bbPct}%' : 'N/A', perfHex('BB_pct', stats.bbPct), 'BB_pct', stats.bbPct),
                bar('K-BB%', stats.kbb != null ? '${stats.kbb}%' : 'N/A', perfHex('kbb_pct', stats.kbb), 'kbb_pct', stats.kbb),
                bar('Whiff%', stats.whiffPct != null ? '${stats.whiffPct}%' : 'N/A', perfHex('whiff_pct', stats.whiffPct), 'whiff_pct', stats.whiffPct),
                bar('F-Strike%', stats.fStrikePct != null ? '${stats.fStrikePct}%' : 'N/A', perfHex('f_strike', stats.fStrikePct), 'f_strike', stats.fStrikePct),
              ],
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _team,
                        decoration: const InputDecoration(labelText: 'Team'),
                        items: teams
                            .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _team = v!;
                          _gameNum = 'All';
                        }),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _gameNum,
                        decoration: const InputDecoration(labelText: 'Game #'),
                        items: gameNums
                            .map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _gameNum = v!),
                      ),
                    ),
                    const YearFilterDropdown(),
                  ],
                ),
                const SizedBox(height: 10),
                const PerfTierLegend(),
              ],
            ),
          ),
        ),
        // Side by side when there is room (each card then fits its own bars
        // instead of one bar stretching across the whole window); stacked on
        // narrow screens. Start alignment: the cards size to their content.
        ResponsiveRow(
          breakpoint: 720,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: keyStatsCard),
            const SizedBox(width: 8),
            Expanded(child: rateStatsCard),
          ],
        ),
      ],
    );
  }
}
