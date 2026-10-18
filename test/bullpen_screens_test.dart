// Bullpen + Pitching Analysis screens: layout at several widths and the main
// workflows (start, throw, undo, pause, Game Mode pass/fail, plan hand-off).
//
// The live bullpen shows a ticking clock, so these tests advance time with
// pump() instead of pumpAndSettle().
//
// Run with:  flutter test test/bullpen_screens_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pitching_analytics/bullpen/analysis_screen.dart';
import 'package:pitching_analytics/bullpen/bullpen_models.dart';
import 'package:pitching_analytics/bullpen/bullpen_screen.dart';
import 'package:pitching_analytics/bullpen/repository.dart';
import 'package:pitching_analytics/bullpen/store.dart';
import 'package:pitching_analytics/bullpen/widgets.dart';
import 'package:pitching_analytics/models/pitcher.dart';
import 'package:pitching_analytics/screens/home_shell.dart';
import 'package:pitching_analytics/services/app_session.dart';
import 'package:pitching_analytics/services/auth_service.dart';
import 'package:pitching_analytics/services/storage_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';

const _widths = <double>[1440, 768, 430, 320];

/// The Bullpen takes throwing hand from the active pitcher's profile.
const _testPitcher = Pitcher(
  id: 'u',
  ownerId: 'u',
  displayName: 'Test Pitcher',
  username: 'test_pitcher',
  sports: ['baseball'],
  throwsHand: 'R',
);

Future<void> _tick(WidgetTester t) => t.pump(const Duration(milliseconds: 350));

Future<BullpenStore> _pump(
  WidgetTester t,
  double width,
  Widget home, {
  InMemoryBullpenRepository? repo,
}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final store = BullpenStore(repo: repo ?? InMemoryBullpenRepository(), userId: 'u');
  await store.load();
  final session = AppSession(auth: AuthService(), storage: StorageService())
    ..activePitcher = _testPitcher;
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSession>.value(value: session),
      ChangeNotifierProvider<BullpenStore>.value(value: store),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: home))),
  ));
  await _tick(t);
  return store;
}

Future<void> _tapText(WidgetTester t, String text) async {
  final f = find.text(text).first;
  await t.ensureVisible(f);
  await _tick(t);
  await t.tap(f);
  await _tick(t);
}

/// Taps the LAST match: used for dialog buttons that share a label with a
/// button on the page underneath.
Future<void> _tapLast(WidgetTester t, String text) async {
  await t.tap(find.text(text).last);
  await _tick(t);
}

Future<void> _tapTextContaining(WidgetTester t, String text) async {
  final f = find.textContaining(text).first;
  await t.ensureVisible(f);
  await _tick(t);
  await t.tap(f);
  await _tick(t);
}

Future<void> _tapZone(WidgetTester t, {Offset? atFraction}) async {
  final zone = find.descendant(of: find.byType(StrikeZone).first, matching: find.byType(CustomPaint)).first;
  await t.ensureVisible(zone);
  await _tick(t);
  final r = t.getRect(zone);
  final f = atFraction ?? const Offset(0.5, 0.5);
  await t.tapAt(Offset(r.left + r.width * f.dx, r.top + r.height * f.dy));
  await _tick(t);
}

/// Three finished command bullpens (60+ targeted pitches) for the analysis tab.
InMemoryBullpenRepository _seeded() {
  final repo = InMemoryBullpenRepository();
  var n = 0;
  for (var s = 0; s < 3; s++) {
    final start = DateTime(2026, 3, 1 + s * 3, 10);
    final id = 'sess$s';
    repo.sessions[id] = BullpenSession(
      id: id,
      userId: 'u',
      type: BullpenType.command,
      throwsHand: 'R',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 30)),
      status: SessionStatus.finished,
    );
    for (var i = 0; i < 24; i++) {
      final type = i.isEven ? 'fb' : 'cv';
      final hit = type == 'fb' ? i % 6 != 0 : i % 4 == 1; // fb mostly hits, cv rarely
      repo.pitches['p${n++}'] = BullpenPitch(
        id: 'p$n',
        sessionId: id,
        userId: 'u',
        seq: i + 1,
        pitchType: type,
        target: const ZoneTarget(0.5, 0.5, 0.4, 0.4),
        actualX: hit ? 0.5 : 0.5,
        actualY: hit ? 0.5 : 1.15,
        timestamp: start.add(Duration(minutes: i)),
      );
    }
  }
  return repo;
}

void main() {
  group('Strike zone widget', () {
    testWidgets('tapping reports zone coordinates (center = middle of the zone)', (t) async {
      double? x, y;
      await _pump(t, 800, StrikeZone(onPick: (a, b) {
        x = a;
        y = b;
      }));
      await _tapZone(t);
      expect(x, closeTo(0.5, 0.03));
      expect(y, closeTo(0.5, 0.03));
      await _tapZone(t, atFraction: const Offset(0.02, 0.02));
      expect(x!, lessThan(0)); // outside the zone, left
      expect(y!, greaterThan(1)); // outside the zone, high
    });

    testWidgets('target width and height change independently', (t) async {
      double w = 0.4, h = 0.4;
      await _pump(
        t,
        800,
        StatefulBuilder(builder: (c, set) => TargetSizeControls(width: w, height: h, onChanged: (a, b) => set(() {
              w = a;
              h = b;
            }))),
      );
      await t.drag(find.byType(Slider).first, const Offset(60, 0));
      await _tick(t);
      expect(w, isNot(0.4));
      expect(h, 0.4); // height untouched
      await _tapText(t, 'Precise');
      expect(w, 0.15);
      expect(h, 0.15);
    });
  });

  group('Bullpen tab', () {
    for (final w in _widths) {
      testWidgets('lays out without errors at ${w.toInt()}px (setup, live bullpen, Game Mode)', (t) async {
        await _pump(t, w, const BullpenScreen());
        expect(t.takeException(), isNull);
        expect(find.text('Start a Bullpen'), findsOneWidget);

        await _tapText(t, 'Start Bullpen');
        expect(find.text('Save Pitch & Add Another'), findsOneWidget);
        expect(t.takeException(), isNull);

        await _tapText(t, 'Game Mode');
        expect(find.text('Pitching Challenges'), findsOneWidget);
        for (final m in ['Target Accuracy', 'Pitch Sequencing', 'Strike Streak']) {
          await _tapText(t, m);
          expect(t.takeException(), isNull, reason: m);
        }
      });
    }

    testWidgets('throw, save, undo, pause, resume and finish', (t) async {
      final store = await _pump(t, 1200, const BullpenScreen());
      await _tapText(t, 'Start Bullpen');
      expect(store.activeSession, isNotNull);

      // Target mode: place target; Landing mode: mark landing; save.
      await _tapZone(t);
      await _tapTextContaining(t, 'Mark where it landed');
      await _tapZone(t, atFraction: const Offset(0.55, 0.45));
      await _tapText(t, 'Save Pitch & Add Another');
      var pitches = store.pitchesFor(store.activeSession!.id);
      expect(pitches.length, 1);
      expect(pitches.first.hasTarget, isTrue);
      expect(pitches.first.hasActual, isTrue);
      expect(pitches.first.velocity, isNull); // optional fields left empty

      // Save button needs a new landing before it can be used again.
      final save = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save Pitch & Add Another'));
      expect(save.onPressed, isNull);

      // Second pitch keeps the same target.
      await _tapZone(t, atFraction: const Offset(0.9, 0.2));
      await _tapText(t, 'Save Pitch & Add Another');
      expect(store.pitchesFor(store.activeSession!.id).length, 2);

      await _tapText(t, 'Undo Last Pitch');
      expect(store.pitchesFor(store.activeSession!.id).length, 1);

      await _tapText(t, 'Pause');
      expect(find.text('PAUSED'), findsOneWidget);
      expect(store.activeSession!.status, SessionStatus.paused);
      await _tapText(t, 'Resume');
      expect(store.activeSession!.status, SessionStatus.active);

      await _tapText(t, 'Finish'); // opens the confirm dialog
      await _tapLast(t, 'Finish'); // confirm
      await _tick(t);
      await _tick(t);
      expect(store.activeSession, isNull);
      expect(store.finishedSessions.length, 1);
      expect(find.textContaining('summary'), findsWidgets);
    });

    testWidgets('an empty bullpen is discarded on finish', (t) async {
      final store = await _pump(t, 1200, const BullpenScreen());
      await _tapText(t, 'Start Bullpen');
      await _tapText(t, 'Finish');
      await _tapLast(t, 'Finish');
      await _tick(t);
      expect(store.sessions, isEmpty);
    });

    testWidgets('Strike Streak: pass saves a passed attempt', (t) async {
      final store = await _pump(t, 1200, const BullpenScreen());
      await _tapText(t, 'Game Mode');
      await _tapText(t, 'Start Challenge');
      for (var i = 0; i < 5; i++) {
        await _tapZone(t);
        await _tapText(t, 'Submit Pitch');
      }
      expect(find.text('Challenge passed'), findsOneWidget);
      expect(store.attempts.length, 1);
      expect(store.attempts.single.success, isTrue);
      expect(store.attempts.single.score, 5);
    });

    testWidgets('Strike Streak: a ball fails, is saved, and Try Again starts fresh', (t) async {
      final store = await _pump(t, 1200, const BullpenScreen());
      await _tapText(t, 'Game Mode');
      await _tapText(t, 'Start Challenge');
      await _tapZone(t);
      await _tapText(t, 'Submit Pitch');
      await _tapZone(t, atFraction: const Offset(0.02, 0.02)); // far outside the zone
      await _tapText(t, 'Submit Pitch');
      expect(find.text('Attempt failed'), findsOneWidget);
      expect(store.attempts.single.success, isFalse);
      expect(store.attempts.single.score, 1);

      await _tapText(t, 'Try Again');
      expect(find.text('Attempt failed'), findsNothing);
      expect(find.text('Submit Pitch'), findsOneWidget);
    });

    testWidgets('ending an attempt before any pitch saves nothing', (t) async {
      final store = await _pump(t, 1200, const BullpenScreen());
      await _tapText(t, 'Game Mode');
      await _tapText(t, 'Start Challenge');
      await _tapText(t, 'End Attempt');
      expect(store.attempts, isEmpty);
      expect(find.text('Pitching Challenges'), findsOneWidget);
    });
  });

  group('Pitching Analysis tab', () {
    for (final w in _widths) {
      testWidgets('empty state at ${w.toInt()}px', (t) async {
        await _pump(t, w, const PitchingAnalysisScreen());
        expect(t.takeException(), isNull);
        expect(find.text('Nothing to analyze yet'), findsOneWidget);
      });

      testWidgets('full analysis lays out without errors at ${w.toInt()}px', (t) async {
        await _pump(t, w, const PitchingAnalysisScreen(), repo: _seeded());
        expect(t.takeException(), isNull);
        for (final s in [
          'Bullpen overview',
          'Accuracy by pitch type',
          'Common misses',
          'Progress across bullpens',
          'Compare bullpens with games',
          'What to Work On Next',
          'Recommended Bullpen Plan',
          'Game Mode results',
        ]) {
          expect(find.text(s), findsOneWidget, reason: s);
        }
      });
    }

    testWidgets('numbers come from the saved bullpens', (t) async {
      await _pump(t, 1200, const PitchingAnalysisScreen(), repo: _seeded());
      expect(find.text('72'), findsWidgets); // 3 bullpens x 24 pitches
      expect(find.text('3'), findsWidgets); // bullpens completed
    });

    testWidgets('filters narrow the data and Clear Filters resets', (t) async {
      await _pump(t, 1200, const PitchingAnalysisScreen(), repo: _seeded());
      expect(find.text('Clear Filters'), findsNothing);
      await t.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'All pitches'));
      await _tick(t);
      await t.tap(find.text('Curveball').last);
      await _tick(t);
      expect(find.text('Clear Filters'), findsOneWidget);
      await _tapText(t, 'Clear Filters');
      expect(find.text('Clear Filters'), findsNothing);
    });

    testWidgets('recommendations quote real numbers and never invent game accuracy', (t) async {
      await _pump(t, 1200, const PitchingAnalysisScreen(), repo: _seeded());
      expect(find.text('WHAT HAPPENED'), findsWidgets);
      expect(find.text('WHAT IT MEANS'), findsWidgets);
      expect(find.text('WHAT TO DO NEXT'), findsWidgets);
      expect(find.text('HOW TO MEASURE PROGRESS'), findsWidgets);
      expect(find.textContaining('no game target accuracy'), findsOneWidget);
    });

    testWidgets('plan: generate, edit, and send to the Bullpen tab', (t) async {
      final store = await _pump(t, 1200, const PitchingAnalysisScreen(), repo: _seeded());
      await _tapText(t, 'Generate Plan');
      expect(find.textContaining('Command plan'), findsOneWidget);

      // Edit reps on the first set.
      final before = find.textContaining('pitches').evaluate().length; // plan header exists
      expect(before, greaterThan(0));
      await t.ensureVisible(find.byTooltip('More reps').first);
      await _tick(t);
      await t.tap(find.byTooltip('More reps').first);
      await _tick(t);

      await _tapText(t, 'Send to Bullpen');
      expect(store.pendingPlan, isNotNull);
      expect(store.pendingPlan!.sets.first.reps, 21); // 20 generated + 1 edit
      expect(store.navigateRequest, 'Bullpen');
      expect(store.plan, isNotNull); // also saved
    });

    testWidgets('Send to Bullpen makes the Bullpen tab start with the plan', (t) async {
      final repo = _seeded();
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final session = AppSession(auth: AuthService(), storage: StorageService())
        ..activePitcher = _testPitcher;
      await t.pumpWidget(ChangeNotifierProvider<AppSession>.value(
        value: session,
        child: MaterialApp(theme: buildAppTheme(), home: HomeShell(bullpenRepository: repo)),
      ));
      await _tick(t);

      // Open Pitching Analysis from the sidebar, build and send a plan.
      await t.tap(find.text('Pitching Analysis').first);
      await _tick(t);
      await _tapText(t, 'Generate Plan');
      await _tapText(t, 'Send to Bullpen');
      await _tick(t);
      await _tick(t);

      // The shell switched tabs and the setup card offers the plan.
      expect(find.text('Start a Bullpen'), findsOneWidget);
      expect(find.textContaining('Plan ready'), findsOneWidget);
      await _tapText(t, 'Start Bullpen');
      expect(find.textContaining('Set 1 of'), findsOneWidget);
    });
  });
}
