import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../utils/responsive.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import '../widgets/year_filter_dropdown.dart';
import '../services/sequence_analytics.dart';
import '../widgets/sequence_analytics_view.dart';
import '../widgets/count_tendencies_view.dart';

class PitchSequencingScreen extends StatefulWidget {
  const PitchSequencingScreen({super.key});

  @override
  State<PitchSequencingScreen> createState() => _PitchSequencingScreenState();
}

class _PitchSequencingScreenState extends State<PitchSequencingScreen> {
  String _team = 'All';
  String _gameNum = 'All';

  /// Hitter hand filter: 'All', 'L' or 'R'. It filters the pitch rows by the
  /// batter hand already stored on every pitch, before any sequencing
  /// analytic is computed, so it combines with Team, Game # and Year.
  String _hand = 'All';

  static const Map<String, String> _handLabels = {
    'All': 'All Hitters',
    'L': 'Left-Handed Hitters',
    'R': 'Right-Handed Hitters',
  };

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    var data = session.filteredPitches;
    if (_team != 'All') data = data.where((p) => p.game == _team).toList();
    if (_gameNum != 'All') {
      final gn = int.tryParse(_gameNum);
      data = data.where((p) => p.gameNumber == gn).toList();
    }
    // Switch hitters are stored as their own hand value ('S'); the data does
    // not say which side they batted from, so they are never counted as L or R.
    final switchPitches = data.where((p) => p.hand.toUpperCase() == 'S').length;
    if (_hand != 'All') data = data.where((p) => p.hand.toUpperCase() == _hand).toList();
    final analytics = SequenceAnalytics.build(data);
    final putAway = StatsService.putAwayPitch(data);
    final firstPitchStrike = StatsService.firstPitchStrikeByType(data);
    final teams = ['All', ...session.knownTeams];
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == 'All' || p.game == _team)
          .map((p) => p.gameNumber.toString())
          .toSet()
    ];
    final pitchTypesUsed = {
      for (final p in data) if (p.pitchType != null) p.pitchType!
    }.toList()
      ..sort();

    final filterRow = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(10),
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
                SizedBox(
                  width: 200,
                  child: StatHoldInfo(
                    title: 'Hitter Hand',
                    description: 'Limits every sequencing section on this page to pitches thrown to left-handed or right-handed hitters, '
                        'using the batter hand stored on each pitch. It works together with Team, Game # and Year.\n'
                        'Switch hitters are stored as their own hand, so they are included under All Hitters only.',
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _hand,
                      decoration: const InputDecoration(labelText: 'Hitter Hand'),
                      items: _handLabels.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _hand = v ?? 'All'),
                    ),
                  ),
                ),
                const YearFilterDropdown(),
              ],
            ),
            if (_hand != 'All' && switchPitches > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$switchPitches pitch${switchPitches == 1 ? '' : 'es'} to switch hitters ${switchPitches == 1 ? 'is' : 'are'} not included: '
                  'the data does not record which side they batted from. Choose All Hitters to include them.',
                  style: const TextStyle(fontSize: 11, color: AppColors.brandOrangeDeep, fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 6, children: [
              if (pitchTypesUsed.isNotEmpty) ...[
                const SizedBox(width: 4),
                const Text('Pitch colors:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                for (final pt in pitchTypesUsed)
                  StatHoldInfo(
                    title: pt.toUpperCase(),
                    description: composeHoldInfo(
                      what: 'Pitch colors are used by the Put-Away and First-Pitch Strike bars and the Count Tendencies labels below.',
                      colorGuide: pitchTypeColorGuide(pitchTypesUsed),
                    ),
                    child: LegendChip(label: pt.toUpperCase(), color: AppColors.pitchColor(pt)),
                  ),
              ],
            ]),
          ],
        ),
      ),
    );

    final heatmap = StatsService.countHeatmap(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterRow,
        const SizedBox(height: 8),
        SequenceAnalyticsView(analytics: analytics),
        const SizedBox(height: 8),
        ResponsiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child:
            GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Put-Away Pitch (Final Pitch of K)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (putAway.isEmpty)
                  const Text('No strikeouts logged yet.', style: TextStyle(color: Colors.grey))
                else
                  for (final p in putAway)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _PitchBarRow(
                        pitchType: p['pitchType'] as String,
                        pct: p['pct'] as double,
                        detail: '${p['count']}/${p['ofTotal']} K',
                        title: 'Put-Away Pitch',
                        what: 'Of all strikeouts, the share that ended on this pitch type (strikeouts finished with it ÷ total strikeouts). The bar fills from 0% to 100%.',
                      ),
                    ),
              ],
            ),
          ),
        ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child:
            GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('First-Pitch Strike% by Pitch Type', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (firstPitchStrike.isEmpty)
                  const Text('No first pitches logged yet.', style: TextStyle(color: Colors.grey))
                else
                  for (final p in firstPitchStrike)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _PitchBarRow(
                        pitchType: p['pitchType'] as String,
                        pct: p['pct'] as double,
                        detail: '${p['count']}/${p['ofTotal']} 1st pitches',
                        title: 'First-Pitch Strike %',
                        what: 'How often this pitch type was a strike when thrown as the first pitch of a plate appearance (first-pitch strikes ÷ first pitches of that type). The bar fills from 0% to 100%.',
                        statKey: 'f_strike',
                      ),
                    ),
              ],
            ),
          ),
        ),
            ),
          ],
        ),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatHoldInfo(
                  title: 'Count Tendencies',
                  description: composeHoldInfo(
                    what: 'A grid of squares: one column per count (balls-strikes) that has recorded pitches, one row per pitch type, plus an ALL row. '
                        'Each square has three strips, top to bottom: USAGE % with the number of pitches (that pitch type\'s share of ALL pitches thrown at the count, and how many pitches that is), '
                        'STRIKE % (how often that pitch was a strike, with strikes/pitches) and BAA (batting average against, with hits/at-bats).\n'
                        'BAA credits an at-bat only to the pitch that ended it, counts official at-bats only (no walks or hit-by-pitches) and is a dash when none ended there. '
                        'The ALL row combines every pitch type at the count. A dash square means that pitch was never thrown at that count.',
                    colorGuide: 'Usage is not graded: using a pitch more or less often is not good or bad by itself, so its strip has no performance color. '
                        'Strike % and BAA use a bright border with a duller fill of the same color, green (favorable) to red (unfavorable), each with its own cutoffs. Press and hold a strip for its exact numbers.\n'
                        '${swatchLine(noDataGray, 'Dash: not enough data for that stat')}',
                  ),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Count Tendencies', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                      'For each count and pitch: Usage % and pitches (P), then Strike % and BAA, in one square. Strike % and BAA are tinted; usage is not.',
                      style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                CountTendenciesView(heatmap: heatmap),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One "pitch tag + progress bar + detail" row. The tag is width-bounded (so
/// long custom pitch names ellipsize instead of overflowing) and the detail
/// text sits under the bar so it can wrap instead of squeezing the bar.
class _PitchBarRow extends StatelessWidget {
  final String pitchType;
  final double pct;
  final String detail;
  final String title;
  final String what;

  /// When set, the pct's quality scale is appended to the hold info (the bar
  /// itself stays pitch-colored).
  final String? statKey;
  const _PitchBarRow({
    required this.pitchType,
    required this.pct,
    required this.detail,
    required this.title,
    required this.what,
    this.statKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.pitchColor(pitchType);
    final guide = '${pitchTypeColorGuide([pitchType])}'
        '${statKey == null ? '' : '\nThe bar color does not grade the number. To judge how good the percentage is, this stat uses these cutoffs (same scale as First-Pitch Strike % elsewhere in the app):\n${statTierLines(statKey!).join('\n')}'}';
    return StatHoldInfo(
      title: '$title · ${pitchType.toUpperCase()}',
      description: composeHoldInfo(what: what, colorGuide: guide),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row: pitch tag on the left, the actual % large on the right.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 56, maxWidth: 104),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      pitchType.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$pct%',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: statValueFontSize(context),
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 14,
                backgroundColor: AppColors.colBorder,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniTag({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      );
}
