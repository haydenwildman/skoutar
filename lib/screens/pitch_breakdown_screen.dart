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
import '../utils/responsive.dart';

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

/// The three selectable column groups of the Pitch Profiles table.
enum _ProfileView { results, approach, contact }

class PitchBreakdownScreen extends StatefulWidget {
  const PitchBreakdownScreen({super.key});

  @override
  State<PitchBreakdownScreen> createState() => _PitchBreakdownScreenState();
}

class _PitchBreakdownScreenState extends State<PitchBreakdownScreen> {
  String _team = 'All';
  String _gameNum = 'All';
  _ProfileView _view = _ProfileView.results;

  /// Pitch type whose row is highlighted in Pitch Profiles (null = none).
  /// Survives switching between Results / Approach / Contact.
  String? _selectedPitch;

  void _togglePitch(String pitch) =>
      setState(() => _selectedPitch = _selectedPitch == pitch ? null : pitch);

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

          // Which columns each view shows. Together the three views cover every
          // stat the table already had (Ball % rides with the Results view).
          const viewOrder = <_ProfileView, List<String>>{
            _ProfileView.results: ['BAA', 'Strike %', 'K%', 'BB%', 'Ball %'],
            _ProfileView.approach: ['Take %', 'Swing %', 'Whiff %', 'Foul %'],
            _ProfileView.contact: ['In Play %', 'Ground Ball %', 'Fly Ball %', 'Line Drive %'],
          };
          final byLabel = {for (final m in metrics) m.label: m};
          final shown = [for (final l in viewOrder[_view]!) byLabel[l]!];

          final presentPitches = {for (final r in breakdown) r['pitchType'] as String};
          final selected = presentPitches.contains(_selectedPitch) ? _selectedPitch : null;
          final narrow = Responsive.isPhone(context);
          final valueSize = narrow ? 13.5 : 15.0;

          // Very light wash toward white: same hue and same cutoffs, just less
          // saturated so the numbers - not the color blocks - lead.

          const countNoun = <String, String>{
            'n': 'pitches',
            'abN': 'official at-bats',
            'paN': 'plate appearances',
            'swingsN': 'swings',
            'battedBallsN': 'balls in play',
          };

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
            double? usagePct,
            required Color color,
            required String what,
            required String colorGuide,
          }) {
            return StatHoldInfo(
              title: name,
              description: composeHoldInfo(
                what: '$what\n\nPitch count: $pitches pitch${pitches == 1 ? '' : 'es'} thrown '
                    '(every recorded pitch of this type; at-bats, strikes and balls are not mixed into this number).'
                    '${usagePct == null ? '' : '\n\n${_pitchMetricInfo['Usage %']}\n\nUsage: $usagePct%'}',
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
                  // Usage % sits right beside the pitch name (pitches of this
                  // type / all pitches in the current filter).
                  if (usagePct != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('$usagePct%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
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
            final tc = ScaleStyle.isTier(bg) ? ScaleStyle.textOn(bg) : textColorForCell(bg);
            final valueText = value == null
                ? 'N/A'
                : (m.isAvg ? value.toStringAsFixed(3) : '${value}%');
            final what = '${_pitchMetricInfo[m.label] ?? m.label}\n\n${whyLine(row, m, bg, valueText)}'
                '${n == null ? '' : '\n\nSample size: the small number under the value ($n) is how many ${countNoun[m.nKey] ?? 'events'} this stat is based on. Fewer than a handful means the percentage can swing a lot, so weigh it accordingly.'}';
            return StatHoldInfo(
              title: '${m.label} · $rowName',
              description: composeHoldInfo(what: what, colorGuide: guides[m.label]),
              child: Container(
                decoration: ScaleStyle.box(bg),
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(valueText,
                        maxLines: 1,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: valueSize, color: tc)),
                  ),
                  if (n != null)
                    Text('$n',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: tc.withOpacity(0.7))),
                ]),
              ),
            );
          }

          // Click / tap / Enter on a pitch row highlights it (border) and dims
          // the others a little; the same pitch again clears it. Only taps are
          // handled here - press-and-hold explanations still work untouched.
          Widget selectable(String pitch, Widget cell, {bool first = false, bool last = false}) {
            final isSel = selected == pitch;
            Widget w = cell;
            if (isSel) {
              const side = BorderSide(color: AppColors.ink, width: 2.5);
              w = DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(
                    top: side,
                    bottom: side,
                    left: first ? side : BorderSide.none,
                    right: last ? side : BorderSide.none,
                  ),
                ),
                child: w,
              );
            } else if (selected != null) {
              w = Opacity(opacity: 0.55, child: w);
            }
            w = GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _togglePitch(pitch), child: w);
            if (first) {
              w = Semantics(
                button: true,
                selected: isSel,
                label: '${pitch.toUpperCase()} row. Activate to ${isSel ? 'clear' : 'highlight'}.',
                child: FocusableActionDetector(
                  mouseCursor: SystemMouseCursors.click,
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                      _togglePitch(pitch);
                      return null;
                    }),
                  },
                  child: w,
                ),
              );
            }
            return w;
          }

          return GlowCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pitch Profiles', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  // Quick overview first: one compact card per pitch thrown.
                  _PitchSummaryCards(
                    breakdown: breakdown,
                    selected: selected,
                    onTap: _togglePitch,
                    usageInfo: _pitchMetricInfo['Usage %']!,
                    whiffInfo: _pitchMetricInfo['Whiff %']!,
                  ),
                  const SizedBox(height: 12),
                  _ProfileViewTabs(value: _view, onChanged: (v) => setState(() => _view = v)),
                  const SizedBox(height: 6),
                  const Text(
                      'Pick Results, Approach or Contact to choose the stats shown. Each stat box: value on top, the sample it is based on below. Tap a pitch row to highlight it; tap it again to clear. Press and hold any box or pitch for what it means and its color cutoffs.',
                      style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 8),
                  Table(
                    border: TableBorder.all(color: AppColors.colBorder, width: 1),
                    defaultVerticalAlignment: TableCellVerticalAlignment.fill,
                    defaultColumnWidth: const FlexColumnWidth(1),
                    columnWidths: {0: narrow ? const FixedColumnWidth(62) : const FlexColumnWidth(0.9)},
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: AppColors.ink),
                        children: [
                          // The first cell sets the row height; the rest fill it.
                          const TableCell(
                            verticalAlignment: TableCellVerticalAlignment.top,
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              child: Text('Pitch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                            ),
                          ),
                          for (final m in shown)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
                              child: StatHoldInfo(
                                title: m.label,
                                description: _pitchMetricInfo[m.label],
                                child: Text(m.label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: narrow ? 10.5 : 11.5)),
                              ),
                            ),
                        ],
                      ),
                      if (overall != null)
                        TableRow(children: [
                          TableCell(
                            verticalAlignment: TableCellVerticalAlignment.top,
                            child: pitchLabelCell(
                            name: 'OVERALL',
                            pitches: overall['n'] as int,
                            color: AppColors.brandOrangeDeep,
                            what: 'Every pitch of every type combined. Each box to the right is the all-pitches value for that stat.',
                            colorGuide: swatchLine(AppColors.brandOrangeDeep,
                                'Orange label: marks the combined row. It is a fixed label color, not a grade, so it has no cutoffs.'),
                          ),
                          ),
                          for (final m in shown) statBox(overall, m, 'Overall'),
                        ]),
                      for (final row in breakdown)
                        TableRow(children: [
                          TableCell(
                            verticalAlignment: TableCellVerticalAlignment.top,
                            child: selectable(
                              row['pitchType'] as String,
                              pitchLabelCell(
                                name: (row['pitchType'] as String).toUpperCase(),
                                pitches: row['n'] as int,
                                usagePct: row['usagePct'] as double?,
                                color: AppColors.pitchColor(row['pitchType'] as String),
                                what: 'This row shows every stat for this one pitch type. Tap the row to highlight it.',
                                colorGuide: pitchTypeColorGuide([row['pitchType'] as String]),
                              ),
                              first: true,
                            ),
                          ),
                          for (var i = 0; i < shown.length; i++)
                            selectable(
                              row['pitchType'] as String,
                              statBox(row, shown[i], (row['pitchType'] as String).toUpperCase()),
                              last: i == shown.length - 1,
                            ),
                        ]),
                    ],
                  ),
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
  final longestValue = bars.map((b) => b.displayValue.length).reduce((a, b) => a > b ? a : b);
  final valueW = (longestValue * 12.5 + 6).clamp(48.0, 92.0).toDouble();

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
                  text: '',
                  height: 16,
                  radius: 8,
                ),
              ),
              const SizedBox(width: 8),
              // The real value, large and bold, at the right end of the row.
              SizedBox(
                width: valueW,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    b.displayValue,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Compact segmented control for the Pitch Profiles column groups.
class _ProfileViewTabs extends StatelessWidget {
  final _ProfileView value;
  final ValueChanged<_ProfileView> onChanged;
  const _ProfileViewTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      _ProfileView.results: 'Results',
      _ProfileView.approach: 'Approach',
      _ProfileView.contact: 'Contact',
    };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.colBorder),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(children: [
        for (final v in _ProfileView.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: v == value,
              label: '${labels[v]} stats',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? AppColors.brandOrangeDeep : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    labels[v]!,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: v == value ? Colors.white : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// One compact card per pitch type thrown: name + total pitches, Usage %, Whiff %.
/// Values come straight from the same [StatsService.pitchBreakdown] rows the
/// table uses (n, usagePct, whiffPct), so they always agree with it.
class _PitchSummaryCards extends StatelessWidget {
  final List<Map<String, dynamic>> breakdown;
  final String? selected;
  final ValueChanged<String> onTap;
  final String usageInfo;
  final String whiffInfo;
  const _PitchSummaryCards({
    required this.breakdown,
    required this.selected,
    required this.onTap,
    required this.usageInfo,
    required this.whiffInfo,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 8.0;
      final w = constraints.maxWidth;
      final perRow = w < 420 ? 2 : (w < 640 ? 3 : 5);
      var cardW = (w - gap * (perRow - 1)) / perRow;
      if (perRow > 2 && cardW > 180) cardW = 180;
      return Wrap(
          spacing: gap,
          runSpacing: gap,
          // Phones: an odd last card is centered instead of left-packed.
          alignment: Responsive.isPhone(context) ? WrapAlignment.center : WrapAlignment.start,
          children: [
        for (final row in breakdown) SizedBox(width: cardW, child: _card(context, row)),
      ]);
    });
  }

  Widget _card(BuildContext context, Map<String, dynamic> row) {
    final type = row['pitchType'] as String;
    final name = type.toUpperCase();
    final color = AppColors.pitchColor(type);
    final n = row['n'] as int;
    final usage = row['usagePct'] as double?;
    final whiff = row['whiffPct'] as double?;
    final isSel = selected == type;
    final dim = selected != null && !isSel;
    // Phones: center the card's contents; desktop/tablet keep them left-aligned.
    final phone = Responsive.isPhone(context);

    Widget stat(String value, String label) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: phone ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: phone ? Alignment.center : Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.colMuted)),
          ],
        );

    Widget card = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSel ? AppColors.ink : AppColors.colBorder, width: isSel ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: phone ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: phone ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 70),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text('$n pitch${n == 1 ? '' : 'es'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
            ),
          ]),
          const SizedBox(height: 6),
          stat(usage == null ? 'N/A' : '$usage%', 'Usage'),
          stat(whiff == null ? 'N/A' : '$whiff%', 'Whiff'),
        ],
      ),
    );
    if (dim) card = Opacity(opacity: 0.6, child: card);

    return StatHoldInfo(
      title: name,
      description: composeHoldInfo(
        what: '$n pitch${n == 1 ? '' : 'es'} thrown.\n\n$usageInfo\n\n$whiffInfo\n\nTap the card to highlight this pitch in the table below.',
        colorGuide: pitchTypeColorGuide([type]),
      ),
      child: Semantics(
        button: true,
        selected: isSel,
        label: '$name summary card',
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onTap(type), child: card),
      ),
    );
  }
}
