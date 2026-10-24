// Game Logs box score + Pitch Sequencing statistic boxes.
//
// Run with:  flutter test test/box_score_and_stat_boxes_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/screens/game_logs_screen.dart';
import 'package:pitching_analytics/services/app_session.dart';
import 'package:pitching_analytics/services/auth_service.dart';
import 'package:pitching_analytics/services/sequence_analytics.dart';
import 'package:pitching_analytics/services/storage_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';
import 'package:pitching_analytics/widgets/sequence_analytics_view.dart';
import 'package:pitching_analytics/widgets/stat_box.dart';
import 'package:pitching_analytics/widgets/tier_scale_bar.dart';

int _id = 0;
int _seq = 0;

List<PitchEvent> _pa(List<(String, String, String?)> pitches, {String hand = 'R'}) {
  _seq++;
  var n = 0;
  return [
    for (final p in pitches)
      PitchEvent(
        id: '${_id++}',
        userId: 'u',
        game: 'Opp',
        gameNumber: 1,
        batter: _seq,
        batterNumber: 7,
        battingOrder: 1,
        hand: hand,
        eventType: 'pitch',
        pitchNum: ++n,
        pitchType: p.$1,
        call: p.$2,
        outcome: p.$3,
        ab: 0,
        outs: 0,
        er: 0,
        xCoord: null,
        yCoord: null,
        battedType: null,
        inning: 1,
        paId: _seq,
        season: 2026,
        timestamp: DateTime(2026, 4, 1, 12).add(Duration(seconds: _seq * 100 + n)),
      ),
  ];
}

List<PitchEvent> _rows() => [
      ..._pa([('fb', 'sl', null), ('cv', 'ss', null), ('ch', 'ip', 'go')]),
      ..._pa([('fb', 'b', null), ('fb', 'b', null), ('cv', 'f', null), ('cv', 'f', null), ('ch', 'ss', 'k')]),
      ..._pa([('fb', 'ss', null), ('cv', 'sl', null), ('ch', 'ip', '1b')], hand: 'L'),
    ];

Future<void> _pumpGameLogs(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final session = AppSession(auth: AuthService(), storage: StorageService());
  session.pitches = _rows();
  await t.pumpWidget(ChangeNotifierProvider<AppSession>.value(
    value: session,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: SingleChildScrollView(child: GameLogsScreen())),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _pumpSequences(WidgetTester t, double width, List<PitchEvent> rows) async {
  t.view.physicalSize = Size(width, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(child: SequenceAnalyticsView(analytics: SequenceAnalytics.build(rows))),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('subtle tint is lighter than the tier color; ungraded colors are not tinted', () {
    expect(isGradedTier(AppColors.perfPoor), isTrue);
    expect(isGradedTier(AppColors.tint), isFalse);
    expect(isGradedTier(null), isFalse);
    expect(subtleFill(AppColors.perfPoor).computeLuminance(), greaterThan(AppColors.perfPoor.computeLuminance()));
  });

  testWidgets('a StatBox with no data shows a dash, not a zero', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatBox(label: 'BAA', value: kUnavailable, tier: AppColors.perfPoor)),
    ));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  for (final w in <double>[1440, 768, 430, 320]) {
    testWidgets('Game Logs box score lays out at ${w.toInt()}px', (t) async {
      await _pumpGameLogs(t, w);
      expect(t.takeException(), isNull);
      // Traditional line, summary and the three advanced groups are present.
      for (final l in ['IP', 'H', 'ER', 'BB', 'K', 'PIT', 'ERA', 'WHIP', 'AVG', 'OBP', 'SLG']) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      for (final g in ['COMMAND AND CONTROL', 'SWING AND MISS', 'BATTED-BALL RESULTS']) {
        expect(find.text(g), findsOneWidget, reason: g);
      }
      // Runs allowed are not stored, so there must be no invented R column.
      expect(find.text('R'), findsNothing);
      // Old tile-wall labels still exist as table columns.
      for (final l in ['Str%', 'F-Str%', 'Ball%', 'Whiff%', 'Swing%', 'Foul%', 'CStr%', 'InPlay%', 'GB%', 'FB%', 'LD%']) {
        expect(find.text(l), findsWidgets, reason: l);
      }
    });
  }

  for (final w in <double>[1440, 768, 430, 320]) {
    testWidgets('Remaining sequencing sections use stat boxes and no progress bars at ${w.toInt()}px', (t) async {
      await _pumpSequences(t, w, _rows());
      expect(t.takeException(), isNull);
      expect(find.byType(StatBox), findsWidgets);
      expect(find.byType(TierScaleBar), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      for (final s in [
        'Sequence effectiveness',
        'Results after each pitch type',
        'Pitch-to-pitch transitions',
        'Pitch selection by batter handedness',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      // These two sections were removed from Pitch Sequencing.
      expect(find.text('Performance by count'), findsNothing);
      expect(find.text('Pitch selection by count'), findsNothing);
    });
  }

  testWidgets('sequence length chips come from the data and start at 3', (t) async {
    await _pumpSequences(t, 1000, _rows());
    expect(find.text('3 pitches'), findsOneWidget);
    expect(find.text('4 pitches'), findsOneWidget);
    expect(find.text('5 pitches'), findsOneWidget);
    expect(find.text('6 pitches'), findsNothing);
    expect(find.text('2 pitches'), findsNothing);
    await t.tap(find.text('5 pitches'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('FB→FB→CV→CV→CH'), findsOneWidget);
  });

  testWidgets('with only 2-pitch at-bats there are no sequence chips and an empty state', (t) async {
    await _pumpSequences(t, 1000, _pa([('fb', 'ss', null), ('ch', 'ip', 'go')]));
    expect(find.text('3 pitches'), findsNothing);
    expect(find.textContaining('No finished at-bat with 3 or more pitches'), findsOneWidget);
  });
}
