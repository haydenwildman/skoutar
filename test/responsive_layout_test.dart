// Responsive layout checks.
//
// Pumps the main screens at desktop, laptop, tablet and phone widths and
// fails on any framework exception (RenderFlex overflow, unbounded
// constraints, etc.). No Supabase connection is needed: the screens are
// shown with an empty, logged-out AppSession.
//
// Run with:  flutter test test/responsive_layout_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pitching_analytics/screens/game_input_screen.dart';
import 'package:pitching_analytics/screens/home_shell.dart';
import 'package:pitching_analytics/screens/login_screen.dart';
import 'package:pitching_analytics/screens/signup_screen.dart';
import 'package:pitching_analytics/services/app_session.dart';
import 'package:pitching_analytics/services/auth_service.dart';
import 'package:pitching_analytics/services/storage_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';
import 'package:pitching_analytics/utils/responsive.dart';
import 'package:pitching_analytics/widgets/sidebar_nav.dart';

const _widths = <double>[1440, 1280, 768, 430, 375];

AppSession _session() => AppSession(auth: AuthService(), storage: StorageService());

Future<void> _pump(WidgetTester tester, double width, Widget home, {AppSession? session}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppSession>.value(
      value: session ?? _session(),
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Login / Signup', () {
    for (final w in _widths) {
      testWidgets('LoginScreen has no layout errors at ${w.toInt()}px', (tester) async {
        await _pump(tester, w, const LoginScreen());
        expect(tester.takeException(), isNull);
        expect(find.text('Sign in to your account'), findsOneWidget);
      });

      testWidgets('SignupScreen has no layout errors at ${w.toInt()}px', (tester) async {
        await _pump(tester, w, const SignupScreen());
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ResponsiveRow', () {
    Widget row() => const ResponsiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SizedBox(key: ValueKey('a'), height: 40)),
            SizedBox(width: 8),
            Expanded(child: SizedBox(key: ValueKey('b'), height: 40)),
          ],
        );

    testWidgets('stays side by side when there is room', (tester) async {
      await _pump(tester, 1000, Scaffold(body: row()));
      final a = tester.getTopLeft(find.byKey(const ValueKey('a')));
      final b = tester.getTopLeft(find.byKey(const ValueKey('b')));
      expect(a.dy, b.dy);
      expect(b.dx, greaterThan(a.dx));
    });

    testWidgets('stacks vertically on a phone', (tester) async {
      await _pump(tester, 375, Scaffold(body: row()));
      final a = tester.getTopLeft(find.byKey(const ValueKey('a')));
      final b = tester.getTopLeft(find.byKey(const ValueKey('b')));
      expect(a.dx, b.dx);
      expect(b.dy, greaterThan(a.dy));
    });
  });

  group('Home shell', () {
    for (final w in _widths) {
      testWidgets('HomeShell has no layout errors at ${w.toInt()}px', (tester) async {
        await _pump(tester, w, const HomeShell());
        expect(tester.takeException(), isNull);

        if (w < Breakpoints.drawer) {
          // Mobile: no permanent sidebar, a menu button instead.
          expect(find.byType(SidebarNav), findsNothing);
          expect(find.byIcon(Icons.menu), findsOneWidget);
        } else {
          expect(find.byType(SidebarNav), findsOneWidget);
          expect(find.byIcon(Icons.menu), findsNothing);
        }
      });
    }

    testWidgets('menu button opens the drawer; choosing a page closes it', (tester) async {
      await _pump(tester, 375, const HomeShell());

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(SidebarNav), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(SidebarNav),
        matching: find.text('Overview'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SidebarNav), findsNothing); // drawer closed
      expect(find.text('Overview'), findsWidgets); // app bar title
      expect(tester.takeException(), isNull);
    });

    // Walks every screen that does not need a paid tier or the network.
    const screens = [
      'Game Input',
      'Overview',
      'Pitch Breakdown',
      'Spray Chart',
      'Game Logs',
      'Edit Raw Data',
      'Edit At-Bats',
    ];
    for (final w in _widths) {
      testWidgets('every free screen renders without errors at ${w.toInt()}px', (tester) async {
        await _pump(tester, w, const HomeShell());
        for (final label in screens) {
          if (w < Breakpoints.drawer) {
            await tester.tap(find.byIcon(Icons.menu));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.descendant(
            of: find.byType(SidebarNav),
            matching: find.text(label),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$label @ ${w.toInt()}px');
        }
      });
    }
  });

  group('Game Input on a phone', () {
    for (final w in <double>[430, 375]) {
      testWidgets('game header, batter bar and pitch buttons fit at ${w.toInt()}px',
          (tester) async {
        final session = _session()..setGame('Lincoln', 1, 2026);
        await _pump(
          tester,
          w,
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: GameInputScreen(),
            ),
          ),
          session: session,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Add New Pitch'), findsOneWidget);
      });

      testWidgets('Add New Pitch dialog fits the screen at ${w.toInt()}px', (tester) async {
        final session = _session()..setGame('Lincoln', 1, 2026);
        await _pump(
          tester,
          w,
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: GameInputScreen(),
            ),
          ),
          session: session,
        );

        await tester.ensureVisible(find.text('Add New Pitch'));
        await tester.tap(find.text('Add New Pitch'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(AlertDialog)).width, lessThanOrEqualTo(w));
      });
    }
  });

  // Regression: selecting a game used to turn the Game Input screen gray on
  // desktop/tablet (>= 600px) because the confirmed-game header put a
  // `Spacer` (an Expanded) directly inside a `Wrap`, which throws a
  // ParentDataWidget error. Phones never built the Spacer, so they worked.
  group('Game Input after a game is selected (tablet / desktop)', () {
    for (final w in <double>[1440, 1280, 1024, 900, 768, 600, 430, 375]) {
      testWidgets('game header and pitch logging render and respond at ${w.toInt()}px',
          (tester) async {
        final session = _session()..setGame('Lincoln', 1, 2026);
        await _pump(
          tester,
          w,
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: GameInputScreen(),
            ),
          ),
          session: session,
        );
        expect(tester.takeException(), isNull);

        // Header chips + buttons are actually on screen (not an ErrorWidget).
        expect(find.text('vs Lincoln'), findsOneWidget);
        expect(find.text('Game 1'), findsOneWidget);
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('New Game'), findsOneWidget);

        // ...and the pitch-logging UI is interactive.
        expect(find.text('Add New Pitch'), findsOneWidget);
        await tester.ensureVisible(find.text('Add New Pitch'));
        await tester.tap(find.text('Add New Pitch'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    }

    testWidgets('selecting a game through the Confirm button works at 1280px', (tester) async {
      await _pump(
        tester,
        1280,
        const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: GameInputScreen(),
          ),
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Team Name'), 'Lincoln');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('vs Lincoln'), findsOneWidget);
    });
  });
}
