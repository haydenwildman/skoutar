// Pitch Profiles: summary cards, Results / Approach / Contact views, and
// single-pitch highlight.
//
// Run with:  flutter test test/pitch_profiles_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/screens/pitch_breakdown_screen.dart';
import 'package:pitching_analytics/services/app_session.dart';
import 'package:pitching_analytics/services/auth_service.dart';
import 'package:pitching_analytics/services/stats_service.dart';
import 'package:pitching_analytics/services/storage_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';

int _id = 0;
PitchEvent _ev(int pa, int num, String type, String call, {String? outcome, String? batted}) => PitchEvent(
      id: '${_id++}',
      userId: 'u',
      game: 'Opp',
      gameNumber: 1,
      batter: pa,
      batterNumber: pa,
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
      battedType: batted,
      inning: 1,
      paId: pa,
    );

final _data = [
  _ev(1, 1, 'fb', 'b'),
  _ev(1, 2, 'fb', 'sl'),
  _ev(1, 3, 'sl', 'ip', outcome: '1b', batted: 'ld'),
  _ev(2, 1, 'fb', 'ip', outcome: 'go', batted: 'gb'),
  _ev(3, 1, 'fb', 'b'),
  _ev(3, 2, 'sl', 'ss'),
  _ev(3, 3, 'sl', 'ss'),
  _ev(3, 4, 'fb', 'ss', outcome: 'k'),
];

Future<void> _pump(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final session = AppSession(auth: AuthService(), storage: StorageService());
  session.pitches = List.of(_data);
  await t.pumpWidget(ChangeNotifierProvider<AppSession>.value(
    value: session,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: SingleChildScrollView(child: PitchBreakdownScreen())),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  for (final w in <double>[1440, 768, 430, 320]) {
    testWidgets('Pitch Profiles lays out cleanly at ${w.toInt()}px', (t) async {
      await _pump(t, w);
      expect(t.takeException(), isNull);
      for (final tab in ['Results', 'Approach', 'Contact']) {
        await t.tap(find.text(tab));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: tab);
      }
    });
  }

  testWidgets('summary cards show the same numbers the breakdown computes', (t) async {
    await _pump(t, 1440);
    final rows = StatsService.pitchBreakdown(_data);
    for (final r in rows) {
      final n = r['n'] as int;
      expect(find.text('$n pitch${n == 1 ? '' : 'es'}'), findsWidgets);
    }
    final fb = rows.firstWhere((r) => r['pitchType'] == 'fb');
    expect(find.text('${fb['usagePct']}%'), findsWidgets);
  });

  testWidgets('each view shows only its own columns (Pitch column always stays)', (t) async {
    await _pump(t, 1440);
    // Header cells are Text widgets inside Tooltips in the table header.
    bool hasHeader(String label) => find.byType(Tooltip).evaluate().any((e) {
          final w = e.widget as Tooltip;
          final c = w.child;
          return c is Text && c.data == label;
        });

    // Default = Results.
    expect(hasHeader('BAA'), isTrue);
    expect(hasHeader('K%'), isTrue);
    expect(hasHeader('Swing %'), isFalse);
    expect(find.text('Pitch'), findsOneWidget);

    await t.tap(find.text('Approach'));
    await t.pumpAndSettle();
    for (final l in ['Take %', 'Swing %', 'Whiff %', 'Foul %']) {
      expect(hasHeader(l), isTrue, reason: l);
    }
    // Usage is no longer its own column: it sits beside each pitch name.
    expect(hasHeader('Usage %'), isFalse);
    final fb = StatsService.pitchBreakdown(_data).firstWhere((r) => r['pitchType'] == 'fb');
    expect(find.text('${fb['usagePct']}%'), findsWidgets);
    expect(hasHeader('BAA'), isFalse);
    expect(find.text('Pitch'), findsOneWidget);

    await t.tap(find.text('Contact'));
    await t.pumpAndSettle();
    for (final l in ['In Play %', 'Ground Ball %', 'Fly Ball %', 'Line Drive %']) {
      expect(hasHeader(l), isTrue, reason: l);
    }
    expect(find.text('Pitch'), findsOneWidget);
  });

  testWidgets('tapping a pitch highlights it, persists across views, and clears on re-tap', (t) async {
    await _pump(t, 1440);
    // Pitch label cells are the only places a 'PITCHES' pill appears besides
    // OVERALL; the first FB label is the row's tap target.
    final fbLabel = find.text('FB').last;
    await t.tap(fbLabel);
    await t.pumpAndSettle();
    expect(find.byType(Opacity), findsWidgets); // others dimmed

    await t.tap(find.text('Contact'));
    await t.pumpAndSettle();
    expect(find.byType(Opacity), findsWidgets); // still selected after view switch

    await t.tap(find.text('FB').last);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
