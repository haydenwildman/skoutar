import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/services/color_guides.dart';
import 'package:pitching_analytics/services/stats_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';
import 'package:pitching_analytics/widgets/stat_vbox.dart';

void main() {
  group('tier guides are read from perfHex', () {
    test('lower-is-better ladder (ERA)', () {
      final t = statTierLines('ERA').join('\n');
      expect(t, contains('Dark green (Excellent): below 2.00'));
      expect(t, contains('Light green (Good): 2.00 to just under 3.50'));
      expect(t, contains('Red (Poor): 6.50 or higher'));
    });

    test('higher-is-better ladder with exclusive edges (K%)', () {
      final t = statTierLines('K_pct').join('\n');
      expect(t, contains('Dark green (Excellent): above 30%'));
      expect(t, contains('Light green (Good): over 22% up to 30%'));
      expect(t, contains('Red (Poor): 10% or lower'));
    });

    test('inclusive ladders (usage predictability, batter AVG)', () {
      expect(statTierLines('usage_predictability').join('\n'), contains('Red (Poor): 70% or higher'));
      expect(statTierLines('batter_AVG').join('\n'), contains('Red (Poor): .350 or higher'));
      expect(statTierLines('batter_AVG').join('\n'), contains('Dark green (Excellent): below .200'));
    });

    test('every graded stat yields five tier lines whose colors match perfHex', () {
      const stats = [
        'ERA', 'WHIP', 'K_pct', 'BB_pct', 'whiff_pct', 'f_strike', 'kbb_pct', 'AVG', 'OBP_allowed',
        'SLG', 'PPA', 'usage_predictability', 'seq_score', 'ball_pct', 'gb_pct', 'fb_pct', 'ld_pct',
        'batter_AVG', 'batter_OBP', 'batter_SLG', 'batter_OPS', 'batter_BB_pct', 'batter_K_pct', 'batter_BABIP',
      ];
      for (final s in stats) {
        final lines = statTierLines(s);
        expect(lines.length, 5, reason: s);
        expect(statColorGuide(s), contains('Gray: no data'), reason: s);
        // Each tier's midpoint value really gets that tier's color.
        final b = statTierBounds(s)!;
        final cuts = [b[1], b[2], b[3], b[4]]..sort();
        final reps = [cuts[0] - 1, (cuts[0] + cuts[1]) / 2, (cuts[1] + cuts[2]) / 2, (cuts[2] + cuts[3]) / 2, cuts[3] + 1];
        expect({for (final v in reps) perfHex(s, v)}.length, 5, reason: s);
      }
    });
  });

  group('relationship colors read the same constants as the colors', () {
    test('swing %', () {
      expect(swingPctColor(50, 40), AppColors.perfExcellent);
      expect(swingPctColor(50, 5), AppColors.perfPoor);
      expect(swingPctColor(20, 40), AppColors.perfAverage);
      final g = swingPctColorGuide();
      expect(g, contains('25%'));
      expect(g, contains('50%'));
      expect(g, contains('Whiff %'));
    });

    test('take, foul and in-play', () {
      expect(takePctColor(60, 60), AppColors.perfExcellent);
      expect(takePctColorGuide(), contains('55% or higher'));
      expect(foulPctColor(35), AppColors.perfPoor);
      expect(foulPctColorGuide(), contains('35% or higher'));
      expect(foulPctColorGuide(), contains('below 20%'));
      expect(inPlayPctColor(22, 75), AppColors.perfExcellent);
      expect(inPlayPctColorGuide(), contains('75% or higher'));
    });
  });

  test('composeHoldInfo adds the standard headings only when there is a guide', () {
    expect(composeHoldInfo(what: 'x'), 'x');
    final t = composeHoldInfo(what: 'x', colorGuide: 'y');
    expect(t, contains('## What This Means'));
    expect(t, contains('## Color Guide'));
  });

  testWidgets('holding a graded stat box shows the color guide', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(375, 667)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: 110,
              child: StatVBox(label: 'K%', value: '31%', description: 'Strikeout Percentage.', statKey: 'K_pct'),
            ),
          ),
        ),
      ),
    ));
    final g = await tester.startGesture(tester.getCenter(find.byType(StatVBox)));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('What This Means'), findsOneWidget);
    expect(find.text('Color Guide'), findsOneWidget);
    expect(find.textContaining('Dark green (Excellent): above 30%'), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(find.text('Color Guide'), findsNothing);
  });
}
