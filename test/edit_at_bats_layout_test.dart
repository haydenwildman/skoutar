// At-Bat Management: layout at several widths, empty state, selection, and
// Clear Filters.
//
// Run with:  flutter test test/edit_at_bats_layout_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/screens/edit_at_bats_screen.dart';
import 'package:pitching_analytics/services/app_session.dart';
import 'package:pitching_analytics/services/auth_service.dart';
import 'package:pitching_analytics/services/storage_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';

PitchEvent _bip(String id, String team, int game, int jersey, String outcome, {double? x, double? y}) =>
    PitchEvent(
      id: id,
      userId: 'u',
      game: team,
      gameNumber: game,
      batter: 1,
      batterNumber: jersey,
      battingOrder: 3,
      hand: 'R',
      eventType: 'pitch',
      pitchNum: 2,
      pitchType: 'fb',
      call: 'ip',
      outcome: outcome,
      ab: 1,
      outs: 0,
      er: 0,
      xCoord: x,
      yCoord: y,
      battedType: 'gb',
      inning: 2,
      paId: 1,
    );

Future<AppSession> _pump(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final session = AppSession(auth: AuthService(), storage: StorageService());
  session.pitches = [
    _bip('a', 'Tigers', 1, 12, '1b', x: 10, y: 20),
    _bip('b', 'Tigers', 2, 7, 'go'),
    _bip('c', 'Lions', 1, 12, 'fo'),
  ];
  await t.pumpWidget(ChangeNotifierProvider<AppSession>.value(
    value: session,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: SingleChildScrollView(child: EditAtBatsScreen())),
    ),
  ));
  await t.pumpAndSettle();
  return session;
}

void main() {
  for (final w in <double>[1440, 900, 430, 320]) {
    testWidgets('lays out without errors at ${w.toInt()}px, before and after selecting', (t) async {
      await _pump(t, w);
      expect(t.takeException(), isNull);
      expect(find.text('Select an at-bat'), findsOneWidget);
      expect(find.text('3 of 3 at-bats'), findsOneWidget);

      await t.tap(find.textContaining('Tigers G1').first);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Select an at-bat'), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.text('Batter'.toUpperCase()), findsOneWidget);
    });
  }

  testWidgets('outcome shows as a secondary label and Clear Filters resets the list', (t) async {
    await _pump(t, 1440);
    expect(find.text('Single'), findsOneWidget);
    expect(find.text('Clear Filters'), findsNothing);

    await t.tap(find.byType(DropdownButtonFormField<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Lions').last);
    await t.pumpAndSettle();
    expect(find.text('1 of 3 at-bats'), findsOneWidget);
    expect(find.text('Clear Filters'), findsOneWidget);

    await t.tap(find.text('Clear Filters'));
    await t.pumpAndSettle();
    expect(find.text('3 of 3 at-bats'), findsOneWidget);
  });
}
