import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/value_bar.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import '../widgets/year_filter_dropdown.dart';

/// Info-button reference text for every metric on this tab. Copied from the
/// team's pitch-metric glossary so every stat here explains itself exactly
/// the way the Overview tab's stat boxes do.
const Map<String, String> _pitchMetricInfo = {
  'Usage %': 'Calculation: (Pitch Type Thrown ÷ Total Pitches) × 100\n\n'
      "Shows how often a specific pitch is thrown compared to all pitches. Pitch usage "
      "helps identify your pitching tendencies and overall pitch mix. A balanced pitch "
      "mix can make you less predictable, while heavy reliance on one pitch may allow "
      "hitters to anticipate what's coming.",
  'Strike %': 'Calculation: (Strikes Thrown ÷ Total Pitches) × 100\n\n'
      'The percentage of pitches that resulted in a strike, including called strikes, '
      'swinging strikes, all foul balls, and balls put into '
      'play. Higher strike percentages generally indicate better command and force '
      'hitters into more defensive counts.',
  'Ball %': 'Calculation: (Balls Thrown ÷ Total Pitches) × 100\n\n'
      'The percentage of pitches called balls. A lower ball percentage usually reflects '
      'better control and command. Consistently limiting balls helps reduce walks and '
      'keeps pitchers ahead in the count.',
  'Swing %': 'Calculation: (Swings ÷ Total Pitches) × 100\n\n'
      'Measures how often hitters offered at a particular pitch. High swing percentages '
      'often indicate aggressive hitters or pitches that appear attractive, while lower '
      'percentages may suggest hitters recognize the pitch as a ball.',
  'Take %': 'Calculation: (Takes ÷ Total Pitches) × 100\n\n'
      "The percentage of pitches hitters chose not to swing at. Comparing Swing % and "
      "Take % helps evaluate how hitters react to your pitches and whether you're "
      "consistently throwing competitive strikes.",
  'Whiff %': 'Calculation: (Swinging Misses ÷ Swings) × 100\n\n'
      "Measures how often hitters swing and completely miss. This is one of the best "
      "indicators of a pitch's effectiveness. A high Whiff % usually reflects excellent "
      "movement, deception, velocity separation, or pitch location.",
  'Foul %': 'Calculation: (Foul Balls ÷ Swings) × 100\n\n'
      'Measures how often hitters foul off a pitch after swinging. High foul '
      'percentages often indicate hitters are making late or imperfect contact. While '
      'not as valuable as a whiff, foul balls still move at-bats toward two strikes.',
  'In Play %': 'Calculation: (Balls Put Into Play ÷ Total Pitches) × 100\n\n'
      'Shows how often a pitch results in a ball being hit into fair territory. Lower '
      'values generally indicate more swings and misses or called strikes, while higher '
      'values suggest hitters are putting the ball in play more frequently.',
  'Contact %': 'Calculation: (Swings That Make Contact ÷ Swings) × 100\n\n'
      'Measures how often hitters make any contact when they swing, including fair '
      'balls and foul balls. Lower Contact % generally means your pitches are more '
      'difficult to hit, while higher percentages indicate hitters are consistently '
      'finding the baseball.',
  'Ground Ball %': 'Calculation: (Ground Balls ÷ Balls In Play) × 100\n\n'
      'Measures the percentage of batted balls hit on the ground. Ground balls rarely '
      'become extra-base hits and cannot become home runs, making this an important '
      'metric for inducing weak contact.',
  'Fly Ball %': 'Calculation: (Fly Balls ÷ Balls In Play) × 100\n\n'
      'Measures the percentage of balls hit into the air. Fly balls can become outs, '
      'but they also carry a greater risk of extra-base hits and home runs. Monitoring '
      'this percentage helps evaluate contact quality.',
  'Line Drive %': 'Calculation: (Line Drives ÷ Balls In Play) × 100\n\n'
      'Measures how often hitters produce line drives. Line drives generally have the '
      'highest batting average of any batted-ball type, so limiting them is a strong '
      'indicator of effective pitching.',
  'BAA': 'Calculation: Hits Allowed ÷ Official At-Bats Against\n'
      '(Walks, Hit By Pitch, and Sacrifice Bunts are not counted as at-bats.)\n\n'
      "Shows the opponent's batting average against a specific pitch. Lower values "
      "indicate hitters have difficulty producing hits. BAA is one of the simplest ways "
      "to compare the effectiveness of different pitch types.",
  'K%': 'Calculation: (Strikeouts ÷ Batters Faced) × 100\n\n'
      "Measures the percentage of hitters that end their plate appearance with a "
      "strikeout on this pitch. K% is one of the best overall indicators of a pitch's "
      "ability to miss bats and finish hitters.",
  'BB%': 'Calculation: (Walks ÷ Batters Faced) × 100\n\n'
      'Measures the percentage of hitters who reach base via a walk on this pitch. '
      'Lower BB% reflects better control and command, allowing pitchers to limit free '
      'baserunners and work more efficiently.',
};

class PitchBreakdownScreen extends StatefulWidget {
  const PitchBreakdownScreen({super.key});

  @override
  State<PitchBreakdownScreen> createState() => _PitchBreakdownScreenState();
}

class _PitchBreakdownScreenState extends State<PitchBreakdownScreen> {
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
    final breakdown = StatsService.pitchBreakdown(data);
    final teams = ['All', ...session.knownTeams];
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == 'All' || p.game == _team)
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
        if (breakdown.isEmpty)
          const GlowCard(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No pitches logged yet.', style: TextStyle(color: Colors.grey)),
            ),
          )
        else ...[
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: StatHoldInfo(
              title: 'Pitch colors',
              description: composeHoldInfo(
                what: 'The key for the pitch colors used in the charts and the Pitch Profiles table below.',
                colorGuide: pitchTypeColorGuide([for (final r in breakdown) r['pitchType'] as String]),
              ),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
              const Text('Pitch colors:', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final row in breakdown)
                Chip(
                  label: Text((row['pitchType'] as String).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                  backgroundColor: AppColors.pitchColor(row['pitchType'] as String),
                ),
            ]),
            ),
          ),
        ),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: StatHoldInfo(
              title: 'Usage %',
              description: composeHoldInfo(
                what: 'How often each pitch type is thrown: pitches of that type ÷ all pitches × 100.\n'
                    'Each row is one pitch type; the bar fills from 0% to 100% (a 25% pitch fills a quarter of the bar) and the number inside is the exact percentage.',
                colorGuide: pitchTypeColorGuide([for (final r in breakdown) r['pitchType'] as String]),
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Usage %', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _horizontalBarChart(
                  [
                    for (final row in breakdown)
                      _HBar(
                        (row['pitchType'] as String).toUpperCase(),
                        row['usagePct'] as double,
                        AppColors.pitchColor(row['pitchType'] as String),
                        '${row['usagePct']}%',
                      ),
                  ],
                  maxValue: 100,
                ),
              ],
            ),
            ),
          ),
        ),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: StatHoldInfo(
              title: 'Whiff % by Pitch',
              description: composeHoldInfo(
                what: 'Swinging misses ÷ swings × 100 for each pitch type, sorted from most to fewest whiffs.\n'
                    'Each row is one pitch type; the bar fills from 0% to 100% and the number inside is the exact percentage. A longer bar means the pitch misses more bats.',
                colorGuide: pitchTypeColorGuide([for (final r in breakdown) r['pitchType'] as String]) +
                    '\nTo see how good a Whiff % is, press and hold a Whiff % box in the Pitch Profiles table: it lists the exact color cutoffs.',
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Whiff % by Pitch', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final withWhiff = breakdown.where((r) => r['whiffPct'] != null).toList()
                    ..sort((a, b) => (b['whiffPct'] as double).compareTo(a['whiffPct'] as double));
                  if (withWhiff.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No swing data yet.', style: TextStyle(color: Colors.grey))),
                    );
                  }
                  // Whiff % is a true percentage: the whole bar is 100%, exactly
                  // like Usage % (25% fills a quarter - never scaled to the
                  // best pitch's whiff rate).
                  return _horizontalBarChart([
                    for (final row in withWhiff)
                      _HBar(
                        (row['pitchType'] as String).toUpperCase(),
                        row['whiffPct'] as double,
                        AppColors.pitchColor(row['pitchType'] as String),
                        '${row['whiffPct']}%',
                      ),
                  ], maxValue: 100);
                }),
              ],
            ),
            ),
          ),
        ),
        Builder(builder: (context) {
          // One single grid instead of a separate box per pitch type:
          // rows are stats, columns are pitch types, and every cell shows
          // both the stat value and the number of pitches it's based on.
          final metrics = <_MetricRow>[
            _MetricRow('BAA', 'avgAgainst', 'abN', tier: 'AVG', isAvg: true),
            _MetricRow('Usage %', 'usagePct', 'n', tier: 'usage_predictability'),
            _MetricRow('Strike %', 'strikePct', 'n', tier: 'f_strike'),
            _MetricRow('K%', 'kPct', 'paN', tier: 'K_pct'),
            _MetricRow('Ball %', 'ballPct', 'n', tier: 'ball_pct'),
            _MetricRow('BB%', 'bbPct', 'paN', tier: 'BB_pct'),
            // Take / Swing / Foul / In Play are colored by how they pair
            // with a second stat (see the helpers in stats_service.dart).
            _MetricRow('Take %', 'takePct', 'n',
                colorFn: (r) => takePctColor(r['takePct'] as double?, r['takeStrikePct'] as double?)),
            _MetricRow('Swing %', 'swingPct', 'n',
                colorFn: (r) => swingPctColor(r['swingPct'] as double?, r['whiffPct'] as double?)),
            _MetricRow('Whiff %', 'whiffPct', 'swingsN', tier: 'whiff_pct'),
            _MetricRow('Foul %', 'foulPct', 'swingsN', colorFn: (r) => foulPctColor(r['foulPct'] as double?)),
            _MetricRow('In Play %', 'inPlayPct', 'n',
                colorFn: (r) => inPlayPctColor(r['inPlayPct'] as double?, r['bipOutPct'] as double?)),
            _MetricRow('Ground Ball %', 'groundBallPct', 'battedBallsN', tier: 'gb_pct'),
            _MetricRow('Fly Ball %', 'flyBallPct', 'battedBallsN', tier: 'fb_pct'),
            _MetricRow('Line Drive %', 'lineDrivePct', 'battedBallsN', tier: 'ld_pct'),
          ];

          final overall = StatsService.pitchBreakdownOverall(data);

          Color textColorForCell(Color bg) => (bg == AppColors.perfExcellent ||
                  bg == AppColors.perfPoor ||
                  bg == AppColors.perfBelowAvg)
              ? Colors.white
              : AppColors.colText;

          // Color Guide text per metric (built once; cutoffs come from the
          // same code that colors the boxes).
          String? guideFor(_MetricRow m) {
            if (m.label == 'Take %') return takePctColorGuide();
            if (m.label == 'Swing %') return swingPctColorGuide();
            if (m.label == 'Foul %') return foulPctColorGuide();
            if (m.label == 'In Play %') return inPlayPctColorGuide();
            if (m.tier == null) return null;
            String? note;
            if (m.label == 'Usage %') {
              note = 'Usage % is graded on the usage-predictability scale: leaning heavily on one pitch is more predictable, so high usage trends toward orange/red.';
            } else if (m.label == 'Strike %') {
              note = 'Strike % here uses the same cutoffs as First-Pitch Strike % (F-Strike%).';
            }
            return statColorGuide(m.tier!, note: note);
          }

          final guides = <String, String?>{for (final m in metrics) m.label: guideFor(m)};

          String pctText(double? v) => v == null ? 'N/A' : '$v%';

          // "Why is THIS box this color" line, using the row's own numbers.
          String whyLine(Map<String, dynamic> row, _MetricRow m, Color bg, String valueText) {
            final name = colorNameOf(bg);
            switch (m.label) {
              case 'Swing %':
                return 'This box: Swing % $valueText with Whiff % ${pctText(row['whiffPct'] as double?)} → $name.';
              case 'Take %':
                return 'This box: Take % $valueText with ${pctText(row['takeStrikePct'] as double?)} of takes called strikes → $name.';
              case 'In Play %':
                return 'This box: In Play % $valueText with an out rate of ${pctText(row['bipOutPct'] as double?)} on balls in play → $name.';
              default:
                return 'This box: $valueText → $name.';
            }
          }

          // Pitch label cell: the pitch name plus the TOTAL pitches thrown of
          // that type (row['n'] = every recorded pitch of that type), shown as
          // its own pill so it can't be confused with the smaller per-stat
          // counts (at-bats, swings, batted balls) in the boxes beside it.
          Widget pitchLabelCell({
            required String name,
            required int pitches,
            required Color color,
            required String what,
            required String colorGuide,
          }) {
            return StatHoldInfo(
              title: name,
              description: composeHoldInfo(
                what: '$what\n\nPitch count: $pitches pitch${pitches == 1 ? '' : 'es'} thrown '
                    '(every recorded pitch of this type; at-bats, strikes and balls are not mixed into this number).',
                colorGuide: colorGuide,
              ),
              child: Container(
                color: color,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$pitches',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      const Text('PITCHES',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 7, letterSpacing: 0.4)),
                    ]),
                  ),
                ]),
              ),
            );
          }

          Widget statBox(Map<String, dynamic> row, _MetricRow m, String rowName) {
            final value = row[m.valueKey] as double?;
            final n = row[m.nKey] as int?;
            final bg = m.colorFn != null
                ? m.colorFn!(row)
                : (m.tier != null ? perfHex(m.tier!, value) : AppColors.tint);
            final tc = textColorForCell(bg);
            final valueText = value == null
                ? 'N/A'
                : (m.isAvg ? value.toStringAsFixed(3) : '${value}%');
            final what = '${_pitchMetricInfo[m.label] ?? m.label}\n\n${whyLine(row, m, bg, valueText)}';
            return StatHoldInfo(
              title: '${m.label} · $rowName',
              description: composeHoldInfo(what: what, colorGuide: guides[m.label]),
              child: Container(
                color: bg,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(valueText,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: tc)),
                  if (n != null)
                    Text('$n',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: tc.withOpacity(0.8))),
                ]),
              ),
            );
          }

          return GlowCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pitch Profiles', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const Text('Each pitch label shows the total pitches thrown of that type. Each stat box: value on top, the count it is based on below. Rows = pitch, columns = stat — read across a row to see one pitch\'s full profile, or down a column to compare pitches on one stat. Hover a column name for what it means. Swing %, Take %, Foul % and In Play % are colored by how they pair with Whiff %, called strikes, and outs on balls in play.',
                      style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 8),
                  // 15 columns can't be read at phone width, so below a
                  // minimum table width the table scrolls sideways
                  // instead of squeezing every column to ~20px.
                  LayoutBuilder(builder: (context, constraints) {
                    const minTableWidth = 760.0;
                    final tableWidth =
                        constraints.maxWidth < minTableWidth ? minTableWidth : constraints.maxWidth;
                    final table = Table(
                    border: TableBorder.all(color: AppColors.colBorder, width: 2),
                    defaultColumnWidth: const FlexColumnWidth(1),
                    columnWidths: const {0: FlexColumnWidth(0.9)},
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: AppColors.ink),
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Pitch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                          ),
                          for (final m in metrics)
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Tooltip(
                                message: _pitchMetricInfo[m.label] ?? '',
                                child: Text(m.label,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                              ),
                            ),
                        ],
                      ),
                      if (overall != null)
                        TableRow(children: [
                          pitchLabelCell(
                            name: 'OVERALL',
                            pitches: overall['n'] as int,
                            color: AppColors.brandOrangeDeep,
                            what: 'Every pitch of every type combined. Each box to the right is the all-pitches value for that stat.',
                            colorGuide: swatchLine(AppColors.brandOrangeDeep,
                                'Orange label: marks the combined row. It is a fixed label color, not a grade, so it has no cutoffs.'),
                          ),
                          for (final m in metrics) statBox(overall, m, 'Overall'),
                        ]),
                      for (final row in breakdown)
                        TableRow(children: [
                          pitchLabelCell(
                            name: (row['pitchType'] as String).toUpperCase(),
                            pitches: row['n'] as int,
                            color: AppColors.pitchColor(row['pitchType'] as String),
                            what: 'This row shows every stat for this one pitch type.',
                            colorGuide: pitchTypeColorGuide([row['pitchType'] as String]),
                          ),
                          for (final m in metrics) statBox(row, m, (row['pitchType'] as String).toUpperCase()),
                        ]),
                    ],
                  );
                    if (constraints.maxWidth >= minTableWidth) return table;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: tableWidth, child: table),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
        ],
      ],
    );
  }
}

class _MetricRow {
  final String label;
  final String valueKey;
  final String nKey;
  final String? tier;
  final bool isAvg;

  /// Optional row-aware color (used where a stat's color depends on a second
  /// stat, e.g. Swing % vs Whiff %). Takes precedence over [tier].
  final Color Function(Map<String, dynamic> row)? colorFn;
  const _MetricRow(this.label, this.valueKey, this.nKey, {this.tier, this.isAvg = false, this.colorFn});
}

/// One row of a horizontal bar chart: a label, the raw value (used to size
/// the bar), a fill color, and the text shown inside the bar.
class _HBar {
  final String label;
  final double value;
  final Color color;
  final String displayValue;
  _HBar(this.label, this.value, this.color, this.displayValue);
}

/// Horizontal bar chart — bars extend left to right, proportional to value.
/// Used instead of fl_chart's vertical BarChart so the "Usage %" and
/// "Whiff % by Pitch" cards read left-to-right and make full use of the
/// available card width instead of bottom-to-top with wasted horizontal space.
Widget _horizontalBarChart(List<_HBar> bars, {double? maxValue}) {
  if (bars.isEmpty) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text('No data yet.', style: TextStyle(color: Colors.grey))),
    );
  }
  final maxVal = maxValue ?? bars.map((b) => b.value).reduce((a, b) => a > b ? a : b);
  final safeMax = maxVal <= 0 ? 1.0 : maxVal;
  // One shared label column width (sized to the longest label, within sane
  // bounds) so every bar starts at the same x and long custom pitch names
  // are ellipsized instead of overflowing.
  final longest = bars.map((b) => b.label.length).reduce((a, b) => a > b ? a : b);
  final labelW = (longest * 7.5 + 12).clamp(48.0, 100.0).toDouble();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final b in bars)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelW,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.colMuted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ValueBar(
                  fraction: (b.value / safeMax).clamp(0.0, 1.0),
                  color: b.color,
                  text: b.displayValue,
                  fontSize: 11,
                  radius: 7,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
