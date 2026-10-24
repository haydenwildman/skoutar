import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/stat_box.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import '../widgets/year_filter_dropdown.dart';

class GameLogsScreen extends StatefulWidget {
  const GameLogsScreen({super.key});

  @override
  State<GameLogsScreen> createState() => _GameLogsScreenState();
}

class _GameLogsScreenState extends State<GameLogsScreen> {
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
    final log = StatsService.gameLog(data);
    final teams = ['All', ...session.knownTeams];
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == 'All' || p.game == _team)
          .map((p) => p.gameNumber.toString())
          .toSet()
    ];

    final filterRow = GlowCard(
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
    );

    if (log.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterRow,
          const GlowCard(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No games logged yet.', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      );
    }

    List<FlSpot> spotsFor(String key) {
      final spots = <FlSpot>[];
      for (int i = 0; i < log.length; i++) {
        final v = log[i][key];
        if (v != null) spots.add(FlSpot(i.toDouble(), (v as num).toDouble()));
      }
      return spots;
    }

    Widget lineCard(String title, String key, Color lineColor, String perfStat) {
      final spots = spotsFor(key);
      // Fixed axis bounds so every tick maps to exactly one game index —
      // without this, fl_chart can pick a fractional label interval (e.g.
      // every 0.5 units) and the same opponent name gets drawn twice along
      // the line instead of once, right at its dot.
      final maxIndex = (log.length - 1).toDouble();
      const xPad = 1.0; // game-slots of room left/right of the first/last dot
      // Pad the Y range so a dot sitting exactly at the data's min/max
      // isn't drawn right on the clip boundary (which was cutting the
      // circle markers in half at the top/bottom of the chart).
      double? minY, maxY;
      if (spots.isNotEmpty) {
        final ys = spots.map((s) => s.y).toList();
        final loY = ys.reduce((a, b) => a < b ? a : b);
        final hiY = ys.reduce((a, b) => a > b ? a : b);
        final range = hiY - loY;
        final pad = range > 0 ? range * 0.18 : (hiY == 0 ? 1.0 : hiY.abs() * 0.18);
        minY = loY - pad;
        maxY = hiY + pad;
        if (minY > 0 && loY >= 0 && minY < pad) minY = 0; // don't go negative for %/count stats needlessly
      }
      return GlowCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
          child: StatHoldInfo(
            title: title,
            description: composeHoldInfo(
              what: 'One dot per game, in game order (left to right). The height of a dot is that game\'s value, '
                  'and the label under it is the opponent. Use it to see whether the stat is trending the right way over the season.',
              colorGuide: 'The line is a fixed color that just identifies this chart; it is not graded.\n'
                  'Each DOT is colored by that game\'s value, using the same cutoffs as the Full Game Log:\n'
                  '${statColorGuide(perfStat)}',
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 4),
              SizedBox(
                height: 240,
                child: spots.isEmpty
                    ? const Center(child: Text('—', style: TextStyle(color: Colors.grey)))
                    // The chart always fills exactly the width its card has:
                    // the old code reserved a fixed 76px per game and put the
                    // chart in a horizontal scroll view, so every added game
                    // widened it. Now the games share the available width, and
                    // only the opponent LABELS are thinned (every Nth, always
                    // including the latest game) when they would collide.
                    // Every game keeps its dot; tap/hover shows any game.
                    : LayoutBuilder(builder: (context, constraints) {
                        const leftAxis = 34.0; // matches leftTitles reservedSize
                        const minLabelGap = 24.0; // px between rotated labels
                        final slots = (maxIndex < 0 ? 0 : maxIndex) + 2 * xPad;
                        final slotPx = ((constraints.maxWidth - leftAxis) / slots).clamp(1.0, 1000.0);
                        final labelStep = (minLabelGap / slotPx).ceil().clamp(1, 1000);
                        final dotRadius = slotPx >= 16 ? 5.0 : (slotPx >= 10 ? 3.5 : 2.5);
                        final dotStroke = slotPx >= 10 ? 2.0 : 1.0;
                        return SizedBox(
                            width: constraints.maxWidth,
                            height: 240,
                            child: LineChart(
                              LineChartData(
                          // One whole game-slot of empty room on each side. With
                          // minX = 0 / maxX = lastIndex the first and last dots sat
                          // exactly ON the clip boundary (clipData below), so
                          // half of each circle was cut off. Whole-number padding
                          // keeps the ticks on integer game indexes (labels stay
                          // pinned to their dots) and the dot size is unchanged.
                          minX: -xPad,
                          maxX: (maxIndex < 0 ? 0 : maxIndex) + xPad,
                          minY: minY,
                          maxY: maxY,
                          // Clip anything (dots, stroke, touch overlay) to the
                          // chart's own bounds so it can never bleed into the
                          // title above or the card below it.
                          clipData: const FlClipData.all(),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              color: lineColor,
                              barWidth: 3,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, bar, index) {
                                  final color = perfHex(perfStat, spot.y);
                                  return FlDotCirclePainter(
                                    radius: dotRadius,
                                    color: color,
                                    strokeWidth: dotStroke,
                                    strokeColor: Colors.white,
                                  );
                                },
                              ),
                            ),
                          ],
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => AppColors.ink,
                              tooltipRoundedRadius: 8,
                              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                                final i = s.x.toInt();
                                final label = (i >= 0 && i < log.length)
                                    ? '${log[i]['opponent']} #${log[i]['gameNumber']}\n'
                                    : '';
                                return LineTooltipItem(
                                  '$label${s.y.toStringAsFixed(2)}',
                                  const TextStyle(
                                    fontFamily: AppFonts.family,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: true, reservedSize: 34),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 60,
                                // Force exactly one tick per game index — the
                                // single fix that stops opponent labels from
                                // repeating along the connecting line.
                                interval: 1,
                                getTitlesWidget: (v, meta) {
                                  final i = v.round();
                                  // Only draw a label if v lands (near) exactly
                                  // on a real data-point index — this is what
                                  // keeps labels pinned to the dots only.
                                  if ((v - i).abs() > 0.01 || i < 0 || i >= log.length) {
                                    return const SizedBox();
                                  }
                                  // Thin labels from the newest game backwards.
                                  if ((log.length - 1 - i) % labelStep != 0) {
                                    return const SizedBox();
                                  }
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    child: Transform.rotate(
                                      angle: -0.5,
                                      child: SizedBox(
                                        width: 60,
                                        child: Text(
                                          '${log[i]['opponent']} #${log[i]['gameNumber']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: true),
                          borderData: FlBorderData(show: false),
                        ),
                              ),
                          );
                        }),
              ),
            ],
          ),
          ),
        ),
      );
    }

    // On narrow (mobile) widths, 3 charts squeezed into one row left almost
    // no room per chart — dots were tiny and crowded. Below the breakpoint,
    // stack them full-width instead so each chart (and its dot markers) has
    // real room to breathe; on wide screens keep the 3-across row.
    Widget chartsSection = LayoutBuilder(builder: (context, constraints) {
      final charts = [
        lineCard('ERA by Game', 'era', AppColors.dataBlue, 'ERA'),
        lineCard('WHIP by Game', 'whip', AppColors.perfAverage, 'WHIP'),
        lineCard('K% by Game', 'kPct', AppColors.perfExcellent, 'K_pct'),
      ];
      // 3 across only when each chart gets >= ~300px; 2 across on mid-size
      // screens (last chart spans the full row); 1 across on phones.
      final w = constraints.maxWidth;
      final cols = w >= 960 ? 3 : (w >= 640 ? 2 : 1);
      const gap = 8.0;
      final colW = (w - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: 0,
        children: [
          for (var i = 0; i < charts.length; i++)
            SizedBox(
              width: (cols == 2 && i == charts.length - 1 && charts.length.isOdd) ? w : colW,
              child: charts[i],
            ),
        ],
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterRow,
        const SizedBox(height: 8),
        chartsSection,
        const SizedBox(height: 14),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Full Game Log', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text(
                  'Each card is one game. Press and hold any stat for what it means and, when it is colored, what the color means.',
                  style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 8),
                for (final row in log) _GameLogCard(row: row),
                const SizedBox(height: 2),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: const ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text('What do these abbreviations mean?',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    children: [_GameLogColumnLegend()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ColumnLabel {
  final String short;
  final String full;
  const _ColumnLabel(this.short, this.full);
}

/// Full-name definitions for every abbreviated column in the Full Game Log
/// table, used both for header tooltips and the legend beneath the title.
const List<_ColumnLabel> _gameLogColumns = [
  _ColumnLabel('IP', 'Innings Pitched'),
  _ColumnLabel('PIT', 'Pitches thrown'),
  _ColumnLabel('PA', 'Plate Appearances faced'),
  _ColumnLabel('AB', 'At-Bats against'),
  _ColumnLabel('H', 'Hits allowed'),
  _ColumnLabel('2B / 3B / HR', 'Doubles, triples and home runs allowed'),
  _ColumnLabel('BB', 'Walks (Bases on Balls) allowed'),
  _ColumnLabel('HBP', 'Batters hit by a pitch'),
  _ColumnLabel('K', 'Strikeouts'),
  _ColumnLabel('ER', 'Earned Runs allowed'),
  _ColumnLabel('PO', 'Pickoff / caught-stealing / throw-out outs'),
  _ColumnLabel('ERA', 'Earned Run Average (ER × 9 / IP)'),
  _ColumnLabel('WHIP', 'Walks + Hits per Inning Pitched'),
  _ColumnLabel('AVG', 'Batting average against (H / AB)'),
  _ColumnLabel('OBP', 'On-base percentage against ((H + BB + HBP) / PA)'),
  _ColumnLabel('SLG', 'Slugging percentage against (total bases / AB)'),
  _ColumnLabel('K%', 'Strikeout Percentage — K ÷ PA'),
  _ColumnLabel('BB%', 'Walk Percentage — BB ÷ PA'),
  _ColumnLabel('K-BB%', 'Strikeout % minus Walk %'),
  _ColumnLabel('P/PA', 'Pitches per Plate Appearance'),
  _ColumnLabel('F-Str%', 'First-Pitch Strike Percentage'),
  _ColumnLabel('Str%', 'Strike % — strikes ÷ all pitches'),
  _ColumnLabel('Ball%', 'Ball % — balls ÷ all pitches'),
  _ColumnLabel('Whiff%', 'Swinging misses ÷ swings'),
  _ColumnLabel('Swing%', 'Swings ÷ all pitches'),
  _ColumnLabel('Foul%', 'Foul balls ÷ swings'),
  _ColumnLabel('InPlay%', 'Balls put in play ÷ all pitches'),
  _ColumnLabel('CStr%', 'Called-strike % — called strikes ÷ all pitches'),
  _ColumnLabel('Cont%', 'Contact % — (fouls + balls in play) ÷ swings'),
  _ColumnLabel('GB% / FB% / LD%', 'Share of balls in play that were ground balls / fly balls / line drives'),
];

/// A compact, always-visible key for what each Full Game Log column means —
/// spelled out so the abbreviations don't require hovering/long-pressing
/// every header to decode.
class _GameLogColumnLegend extends StatelessWidget {
  const _GameLogColumnLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: _gameLogColumns
            .where((c) => c.short != 'Opponent' && c.short != 'Game')
            .map((c) => RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11, color: AppColors.colText),
                    children: [
                      TextSpan(
                          text: '${c.short}: ',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: c.full),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// One game in the Full Game Log, laid out like a baseball box score:
///  1. a distinct heading band (opponent and game number),
///  2. the traditional pitching line,
///  3. the pitching summary (ERA / WHIP / AVG / OBP / SLG),
///  4. the advanced analytics in labeled groups.
/// Every table uses the same fixed column width, so a column lines up from one
/// game to the next, and a table wider than the screen scrolls sideways inside
/// itself instead of wrapping or overlapping. Graded values get a subtle tint
/// from the same cutoffs as before; a value with no data shows a dash.
class _GameLogCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _GameLogCard({required this.row});

  static String _f(Object? v, int d) => v == null ? kUnavailable : (v as num).toStringAsFixed(d);
  static String _p(Object? v) => v == null ? kUnavailable : '$v%';

  /// Average-style stats read ".245" like a box score.
  static String _avg3(Object? v) {
    if (v == null) return kUnavailable;
    final t = (v as num).toStringAsFixed(3);
    return t.startsWith('0.') ? t.substring(1) : t;
  }

  @override
  Widget build(BuildContext context) {
    double? n(String k) => (row[k] as num?)?.toDouble();

    // Count / ungraded column.
    BoxScoreCol plain(String label, Object? v, String what) =>
        BoxScoreCol(label: label, value: v == null ? kUnavailable : '$v', title: label, what: what);

    // Column graded with a perfHex ladder.
    BoxScoreCol graded(String label, double? v, String text, String key, String what, {String? note}) =>
        BoxScoreCol(
          label: label,
          value: v == null ? kUnavailable : text,
          tier: v == null ? null : perfHex(key, v),
          title: label,
          what: what,
          colorGuide: statColorGuide(key, note: note),
        );

    // Column colored by a relationship rule (Swing %, Foul %, In Play %).
    BoxScoreCol related(String label, double? v, Color bg, String guide, String what) => BoxScoreCol(
          label: label,
          value: v == null ? kUnavailable : '$v%',
          tier: v == null ? null : bg,
          title: label,
          what: what,
          colorGuide: guide,
        );

    final swing = n('swingPct');
    final foul = n('foulPct');
    final inPlay = n('inPlayPct');

    // The runs-allowed column is intentionally absent: SKOUTAR stores earned
    // runs per pitch (ER) but not total runs, so there is no real value to show.
    final pitchingLine = <BoxScoreCol>[
      plain('IP', row['ip'], 'Innings pitched in this game.'),
      plain('H', row['h'], 'Hits allowed.'),
      plain('ER', row['er'], 'Earned runs allowed.'),
      plain('BB', row['bb'], 'Walks allowed.'),
      plain('K', row['k'], 'Strikeouts.'),
      plain('PIT', row['pitches'], 'Pitches thrown in this game.'),
      plain('PA', row['pa'], 'Plate appearances faced.'),
      plain('AB', row['ab'], 'At-bats against (plate appearances minus walks and hit-by-pitches).'),
      plain('2B', row['doubles'], 'Doubles allowed.'),
      plain('3B', row['triples'], 'Triples allowed.'),
      plain('HR', row['hr'], 'Home runs allowed.'),
      plain('HBP', row['hbp'], 'Batters hit by a pitch.'),
      plain('PO', row['po'], 'Outs on pickoffs, caught stealing and throw-outs.'),
    ];

    final summary = <BoxScoreCol>[
      graded('ERA', n('era'), _f(row['era'], 2), 'ERA', 'Earned Run Average for this game: earned runs × 9 ÷ innings pitched.'),
      graded('WHIP', n('whip'), _f(row['whip'], 3), 'WHIP', 'Walks + hits per inning pitched in this game.'),
      graded('AVG', n('avg'), _avg3(row['avg']), 'AVG', 'Batting average against: hits ÷ at-bats.'),
      graded('OBP', n('obp'), _avg3(row['obp']), 'OBP_allowed',
          'On-base percentage against: (hits + walks + hit-by-pitches) ÷ plate appearances.'),
      graded('SLG', n('slg'), _avg3(row['slg']), 'SLG', 'Slugging percentage against: total bases ÷ at-bats.'),
    ];

    final command = <BoxScoreCol>[
      graded('Str%', n('strikePct'), _p(row['strikePct']), 'f_strike',
          'Strike percentage: strikes (called, swinging, foul, in play) ÷ all pitches.',
          note: 'Strike % uses the same cutoffs as First-Pitch Strike % (F-Strike%).'),
      graded('F-Str%', n('fStrikePct'), _p(row['fStrikePct']), 'f_strike',
          'First-pitch strike percentage: plate appearances that started with a strike ÷ all plate appearances.'),
      graded('Ball%', n('ballPct'), _p(row['ballPct']), 'ball_pct', 'Ball percentage: balls ÷ all pitches.'),
      graded('BB%', n('bbPct'), _p(row['bbPct']), 'BB_pct', 'Walk percentage: walks ÷ plate appearances.'),
      graded('P/PA', n('ppa'), _f(row['ppa'], 2), 'PPA', 'Pitches thrown per plate appearance.'),
    ];

    final swingMiss = <BoxScoreCol>[
      graded('Whiff%', n('whiffPct'), _p(row['whiffPct']), 'whiff_pct', 'Whiff percentage: swinging misses ÷ swings.'),
      related('Swing%', swing, swingPctColor(swing, n('whiffPct')), swingPctColorGuide(),
          'Swing percentage: swings ÷ all pitches.'),
      related('Foul%', foul, foulPctColor(foul), foulPctColorGuide(), 'Foul percentage: foul balls ÷ swings.'),
      plain('CStr%', row['calledStrikePct'] == null ? null : '${row['calledStrikePct']}%',
          'Called-strike percentage: pitches taken for a strike ÷ all pitches.'),
      plain('Cont%', row['contactPct'] == null ? null : '${row['contactPct']}%',
          'Contact percentage: (foul balls + balls in play) ÷ swings.'),
      graded('K%', n('kPct'), _p(row['kPct']), 'K_pct', 'Strikeout percentage: strikeouts ÷ plate appearances.'),
      graded('K-BB%', n('kbb'), _p(row['kbb']), 'kbb_pct', 'Strikeout percentage minus walk percentage.'),
    ];

    final battedBall = <BoxScoreCol>[
      related('InPlay%', inPlay, inPlayPctColor(inPlay, n('bipOutPct')), inPlayPctColorGuide(),
          'In-play percentage: balls put in play ÷ all pitches.'),
      graded('GB%', n('groundBallPct'), _p(row['groundBallPct']), 'gb_pct',
          'Ground-ball percentage: ground balls ÷ balls in play with a known type.'),
      graded('FB%', n('flyBallPct'), _p(row['flyBallPct']), 'fb_pct',
          'Fly-ball percentage: fly balls ÷ balls in play with a known type.'),
      graded('LD%', n('lineDrivePct'), _p(row['lineDrivePct']), 'ld_pct',
          'Line-drive percentage: line drives ÷ balls in play with a known type.'),
    ];

    Widget group(String title, List<BoxScoreCol> cols) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(title.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: AppColors.brandOrangeDeep)),
            ),
            BoxScoreTable(cols: cols),
          ]),
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.colBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Heading band: clearly separate from the numbers below.
          Container(
            color: AppColors.tint,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Text('vs ${row['opponent']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              Text('Game ${row['gameNumber']}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.colMuted)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BoxScoreTable(cols: pitchingLine),
              const SizedBox(height: 8),
              BoxScoreTable(cols: summary),
              group('Command and control', command),
              group('Swing and miss', swingMiss),
              group('Batted-ball results', battedBall),
            ]),
          ),
        ],
      ),
    );
  }
}
