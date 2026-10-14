import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/year_filter_dropdown.dart';
import 'plus_lock_card.dart';

const Map<String, String> _countInfo = {
  'Plate Appearances': 'Calculation: Count of completed plate appearances in the '
      'selected filter.\n\nThe total number of batters faced whose at-bat has ended '
      '(via hit, walk, strikeout, or ball in play).',
  'F-Strike%': 'Calculation: First-Pitch Strikes ÷ Total Plate Appearances × 100\n\n'
      'How often the very first pitch of a plate appearance was a strike (called, '
      'swinging, foul, or in play). Getting ahead in the count early. Higher is better.',
  'OBP after F-Strike': 'Calculation: On-base results ÷ Plate Appearances where the '
      'first pitch was a strike\n\n'
      'Shows how much throwing a first-pitch strike actually helps you — the lower '
      'this is, the more that early strike is turning into outs instead of '
      'baserunners.',
  'PA': 'Calculation: Count of plate appearances that fell into this '
      'count-approach bucket (Ahead / Behind / Even / Two-Strike / Hitter\'s Count).\n\n'
      'A PA is "Ahead" if you reached 2 strikes before 2 balls, "Behind" if you '
      'reached 2 balls before 2 strikes, and "Even" otherwise.',
  'Two-Strike Count %': 'Calculation: (PAs that reached 0-2 or 1-2 ÷ Total PA) × 100\n\n'
      'How often you get a hitter to a put-away count (0-2 or 1-2). Higher is '
      'better — these counts are where you should be finishing hitters off.',
  'Hitter\'s Count %': 'Calculation: (PAs that reached 2-0 or 2-1 ÷ Total PA) × 100\n\n'
      'How often the count tilts in the hitter\'s favor (2-0 or 2-1). Lower is '
      'better — these are the counts hitters do the most damage in.',
  'OBP Allowed': 'Calculation: On-base results ÷ Plate Appearances in this bucket\n\n'
      'On-Base Percentage allowed while pitching from this count situation. Lower is '
      'better — it shows how well you close out at-bats once you reach this bucket.',
};

class CountApproachScreen extends StatefulWidget {
  const CountApproachScreen({super.key});

  @override
  State<CountApproachScreen> createState() => _CountApproachScreenState();
}

class _CountApproachScreenState extends State<CountApproachScreen> {
  String _team = 'All';
  String _gameNum = 'All';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    if (!session.isPlus) {
      return const PlusLockCard(feature: 'Count & Approach analytics');
    }
    var data = session.filteredPitches;
    if (_team != 'All') data = data.where((p) => p.game == _team).toList();
    if (_gameNum != 'All') {
      final gn = int.tryParse(_gameNum);
      data = data.where((p) => p.gameNumber == gn).toList();
    }
    final cd = StatsService.countApproach(data);
    final gcs = StatsService.groupedCountStats(data);
    final teams = ['All', ...session.knownTeams];
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == 'All' || p.game == _team)
          .map((p) => p.gameNumber.toString())
          .toSet()
    ];

    Widget bucketCard(String title, int pa, double? obp) {
      final bg = perfHex('OBP_allowed', obp);
      return GlowCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              PerfStatBar(
                label: 'PA',
                value: '$pa',
                color: AppColors.tint,
                description: _countInfo['PA'],
              ),
              PerfStatBar(
                label: 'OBP Allowed',
                value: obp != null ? obp.toStringAsFixed(3) : 'N/A',
                color: bg,
                description: _countInfo['OBP Allowed'],
                scaleHint: statScaleHint('OBP_allowed'),
                statKey: 'OBP_allowed',
                rawValue: obp,
              ),
            ],
          ),
        ),
      );
    }

    Widget groupedCountCard(String title, int pa, double? pct, double? obp, String pctLabel) {
      final pctBg = perfHex(pctLabel == "Two-Strike Count %" ? 'f_strike' : 'BB_pct', pct);
      final obpBg = perfHex('OBP_allowed', obp);
      return GlowCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              PerfStatBar(
                label: 'PA',
                value: '$pa',
                color: AppColors.tint,
                description: _countInfo['PA'],
              ),
              PerfStatBar(
                label: pctLabel,
                value: pct != null ? '$pct%' : 'N/A',
                color: pctBg,
                description: _countInfo[pctLabel],
                scaleHint: statScaleHint(pctLabel == "Two-Strike Count %" ? 'f_strike' : 'BB_pct'),
                statKey: pctLabel == "Two-Strike Count %" ? 'f_strike' : 'BB_pct',
                colorNote: pctLabel == "Two-Strike Count %"
                    ? 'This bar is graded on the same cutoffs as First-Pitch Strike % (F-Strike%).'
                    : 'This bar is graded on the same cutoffs as Walk % (BB%), so a larger hitter\'s-count share trends toward orange/red.',
                rawValue: pct,
              ),
              PerfStatBar(
                label: 'OBP Allowed',
                value: obp != null ? obp.toStringAsFixed(3) : 'N/A',
                color: obpBg,
                description: _countInfo['OBP Allowed'],
                scaleHint: statScaleHint('OBP_allowed'),
                statKey: 'OBP_allowed',
                rawValue: obp,
              ),
            ],
          ),
        ),
      );
    }

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
                        items: teams.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
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
                        items: gameNums.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
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
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PerfStatBar(
                  label: 'Plate Appearances',
                  value: '${cd['totalPA']}',
                  color: AppColors.tint,
                  description: _countInfo['Plate Appearances'],
                ),
                PerfStatBar(
                  label: 'F-Strike%',
                  value: cd['fpsPct'] != null ? '${cd['fpsPct']}%' : 'N/A',
                  color: perfHex('f_strike', cd['fpsPct'] as double?),
                  description: _countInfo['F-Strike%'],
                  scaleHint: statScaleHint('f_strike'),
                  statKey: 'f_strike',
                  rawValue: cd['fpsPct'] as double?,
                ),
                PerfStatBar(
                  label: 'OBP after F-Strike',
                  value: cd['fpsOBP'] != null ? (cd['fpsOBP'] as double).toStringAsFixed(3) : 'N/A',
                  color: perfHex('OBP_allowed', cd['fpsOBP'] as double?),
                  description: _countInfo['OBP after F-Strike'],
                  scaleHint: statScaleHint('OBP_allowed'),
                  statKey: 'OBP_allowed',
                  rawValue: cd['fpsOBP'] as double?,
                ),
              ],
            ),
          ),
        ),
        bucketCard('Pitcher Ahead in Count', cd['aheadPA'] as int, cd['aheadOBP'] as double?),
        bucketCard('Pitcher Behind in Count', cd['behindPA'] as int, cd['behindOBP'] as double?),
        bucketCard('Even Count', cd['evenPA'] as int, cd['evenOBP'] as double?),
        groupedCountCard('Two-Strike Counts (0-2 / 1-2)', gcs['twoStrikePA'] as int,
            gcs['twoStrikePct'] as double?, gcs['twoStrikeOBP'] as double?, 'Two-Strike Count %'),
        groupedCountCard('Hitter\'s Counts (2-0 / 2-1)', gcs['hittersCountPA'] as int,
            gcs['hittersCountPct'] as double?, gcs['hittersCountOBP'] as double?, 'Hitter\'s Count %'),
      ],
    );
  }
}
