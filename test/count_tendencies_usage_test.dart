// Count Tendencies: Usage % (with N) first, then Strike %, then BAA.
//
// Run with:  flutter test test/count_tendencies_usage_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/stats_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';
import 'package:pitching_analytics/widgets/count_tendencies_view.dart';

int _id = 0;
PitchEvent _p(int batter, int num, String type, String call, {String? outcome}) => PitchEvent(
      id: '${_id++}',
      userId: 'u',
      game: 'Opp',
      gameNumber: 1,
      batter: batter,
      batterNumber: batter,
      battingOrder: 1,
      hand: 'R',
      eventType: 'pitch',
      pitchNum: num,
      pitchType: type,
      call: call,
      outcome: outcome,
      ab: 0,
      outs: 0,
      er: 0,
      xCoord: null,
      yCoord: null,
      battedType: null,
      inning: 1,
      paId: batter,
      season: 2026,
    );

// 0-0: fb, fb, cv   |  1-0: cv, cv  |  1-1: ch (single)  |  3-0: fb (walk)
final _rows = [
  _p(1, 1, 'fb', 'sl'), // 0-0 strike
  _p(1, 2, 'fb', 'ss'), // 0-1
  _p(1, 3, 'cv', 'ip', outcome: 'go'), // 0-2, ends the at-bat (out)
  _p(2, 1, 'fb', 'b'), // 0-0 ball
  _p(2, 2, 'cv', 'ss'), // 1-0
  _p(2, 3, 'ch', 'ip', outcome: '1b'), // 1-1, ends the at-bat (hit)
  _p(3, 1, 'cv', 'b'), // 0-0 ball
  _p(3, 2, 'cv', 'b'), // 1-0
  _p(3, 3, 'fb', 'b'), // 2-0
  _p(3, 4, 'fb', 'b', outcome: 'bb'), // 3-0, walk (not an at-bat)
];

void main() {
  test('usage is out of ALL pitches at that count, with N, and sums to ~100', () {
    final h = StatsService.countHeatmap(_rows);
    final cells = h['cells'] as Map<String, Map<String, dynamic>>;
    final totals = h['countTotals'] as Map<String, int>;
    expect(totals['0-0'], 3);
    expect(cells['0-0|fb']!['n'], 2);
    expect(cells['0-0|fb']!['usagePct1'], 66.7);
    expect(cells['0-0|cv']!['n'], 1);
    expect(cells['0-0|cv']!['usagePct1'], 33.3);
    final sum = ['fb', 'cv'].fold<double>(0, (a, pt) => a + (cells['0-0|$pt']!['usagePct1'] as double));
    expect(sum, closeTo(100, 0.2));
    // 1-0 only saw curveballs: 100% of the 2 pitches thrown at 1-0, not of the game.
    expect(cells['1-0|cv']!['usagePct1'], 100.0);
    expect(cells['1-0|cv']!['n'], 2);
    // A pitch never thrown at a count has no cell (no fabricated 0%).
    expect(cells.containsKey('0-0|ch'), isFalse);
  });

  test('strike % and BAA use their own denominators; BAA is null (not .000) when unavailable', () {
    final h = StatsService.countHeatmap(_rows);
    final cells = h['cells'] as Map<String, Map<String, dynamic>>;
    // 0-0 fastballs: one strike (called) and one ball -> 1 of 2.
    expect(cells['0-0|fb']!['strikes'], 1);
    expect(cells['0-0|fb']!['strikePct1'], 50.0);
    expect(cells['0-0|cv']!['strikePct1'], 0.0); // thrown, none were strikes: a real 0
    // No at-bat ended on a first pitch: BAA unavailable.
    expect(cells['0-0|fb']!['baa'], isNull);
    // The single at 1-1 is 1 hit in 1 official at-bat.
    expect(cells['1-1|ch']!['baa'], 1.0);
    // A walk is not an official at-bat: no BAA.
    expect(cells['3-0|fb']!['ab'], 0);
    expect(cells['3-0|fb']!['baa'], isNull);
    final cs = h['countStrikes'] as Map<String, int>;
    expect(cs['0-0'], 1);
  });

  for (final w in <double>[1200, 700, 320]) {
    testWidgets('Count Tendencies cards lay out at ${w.toInt()}px', (t) async {
      t.view.physicalSize = Size(w, 4000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: CountTendenciesView(heatmap: StatsService.countHeatmap(_rows))),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // Usage % and N are shown, usage first in the header.
      expect(find.text('66.7%'), findsWidgets);
      expect(find.text('N=2'), findsWidgets);
      expect(find.text('N=3'), findsOneWidget); // ALL row at 0-0
      expect(find.text('USAGE % (N)'), findsWidgets);
      expect(find.text('STRIKE %'), findsWidgets);
      expect(find.text('BAA'), findsWidgets);
      // Unavailable BAA is a dash, never .000.
      expect(find.text('—'), findsWidgets);
      expect(find.text('.000'), findsNothing);
      // Counts with no pitches are not shown.
      expect(find.text('3-2'), findsNothing);
      expect(find.text('0-0'), findsOneWidget);
    });
  }

  testWidgets('no pitches shows an empty state, not zeros', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: CountTendenciesView(heatmap: StatsService.countHeatmap(const []))),
    ));
    expect(find.text('No pitch data yet.'), findsOneWidget);
    expect(find.text('0.0%'), findsNothing);
  });
}
