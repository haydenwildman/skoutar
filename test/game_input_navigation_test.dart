// Game Input: History navigation, the Pitch Count display and button order.
//
// Run with:  flutter test test/game_input_navigation_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/models/pitcher.dart';
import 'package:pitching_analytics/models/user.dart';
import 'package:pitching_analytics/screens/game_input_screen.dart';
import 'package:pitching_analytics/services/app_session.dart';
import 'package:pitching_analytics/services/auth_service.dart';
import 'package:pitching_analytics/services/storage_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';

/// Storage that saves nothing, so the screen can run without a database.
class _QuietStorage extends StorageService {
  @override
  Future<void> savePitchesForUser(String userId, List<PitchEvent> pitches) async {}
  @override
  Future<void> saveLiveState(String userId, Map<String, dynamic> state) async {}
}

AppSession _session() {
  // A logged-in session with a game and batter already set.
  final s = AppSession(auth: AuthService(), storage: _QuietStorage());
  s.currentUser = AppUser(id: 'u1', username: 'user', email: 'user@example.com');
  s.activePitcher = const Pitcher(id: 'p1', ownerId: 'u1', displayName: 'Pitcher', username: 'pitcher1');
  s.customPitchTypes = ['sinker'];
  s.setGame('Eagles', 1, 2026);
  s.setBatter(7, 1);
  return s;
}

Future<void> _pump(WidgetTester tester, double width, AppSession session) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppSession>.value(
      value: session,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SingleChildScrollView(child: GameInputScreen())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final w in <double>[1280, 390]) {
    group('at ${w.toInt()}px', () {
      testWidgets('H: History opens and the back arrow returns, game unchanged', (tester) async {
        final s = _session();
        await _pump(tester, w, s);
        expect(find.textContaining('HISTORY'), findsNothing);

        await tester.tap(find.byTooltip('History'));
        await tester.pumpAndSettle();
        expect(find.textContaining('HISTORY'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await tester.pumpAndSettle();
        expect(find.textContaining('HISTORY'), findsNothing);
        expect(s.currentOpponent, 'Eagles');
        expect(s.committedJersey, 7);
        expect(tester.takeException(), isNull);
      });

      testWidgets('History button pressed twice still returns (no stuck screen)', (tester) async {
        final s = _session();
        await _pump(tester, w, s);
        await tester.tap(find.byTooltip('History'));
        await tester.pumpAndSettle();
        // The same button now closes History instead of re-opening it.
        await tester.tap(find.byTooltip('Back to game input'));
        await tester.pumpAndSettle();
        expect(find.textContaining('HISTORY'), findsNothing);
      });

      testWidgets('Drop Third Strike opens a pitch selector, records the pitch, never an out',
          (tester) async {
        final s = _session();
        s.strikes = 2; // two strikes on the batter
        await _pump(tester, w, s);

        final tile = find.text('Drop Third Strike');
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();

        // The selector lists the pitcher's own pitch types.
        expect(find.text('Dropped third strike'), findsOneWidget);
        final pitchInSheet =
            find.descendant(of: find.byType(BottomSheet), matching: find.text('Sinker'));
        expect(pitchInSheet, findsOneWidget);

        await tester.tap(pitchInSheet);
        await tester.pumpAndSettle();

        expect(s.pitches.length, 1);
        expect(s.pitches.single.pitchType, 'sinker');
        expect(s.pitches.single.outcome, 'dk3');
        expect(s.outs, 0); // not an out
        expect(s.currentGamePitchCount, 1);
        // The screen now waits for what happened on the play.
        expect(find.text('DROPPED THIRD STRIKE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Pitch Count is shown and starts at 0', (tester) async {
        final s = _session();
        await _pump(tester, w, s);
        expect(find.text('PITCH COUNT'), findsOneWidget);
        expect(s.currentGamePitchCount, 0);
        expect(tester.takeException(), isNull);
      });
    });
  }

  test('I: Ball In Play is the last button, right after Hit By Pitch', () {
    final names = gameInputCallButtons.map((b) => b[0]).toList();
    expect(names.last, 'Ball In Play');
    expect(names[names.length - 2], 'Hit By Pitch');
    expect(names.where((n) => n == 'Ball In Play').length, 1);
  });
}
