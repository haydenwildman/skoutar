// Bullpen / Game Mode logic: geometry, analytics, challenge rules, storage
// workflow, plan generation and recommendations. No UI and no network.
//
// Run with:  flutter test test/bullpen_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/bullpen/analytics.dart';
import 'package:pitching_analytics/bullpen/bullpen_models.dart';
import 'package:pitching_analytics/bullpen/challenges.dart';
import 'package:pitching_analytics/bullpen/plan_models.dart';
import 'package:pitching_analytics/bullpen/recommendations.dart';
import 'package:pitching_analytics/bullpen/repository.dart';
import 'package:pitching_analytics/bullpen/store.dart';
import 'package:pitching_analytics/models/pitch_event.dart';

final _t0 = DateTime(2026, 3, 1, 12);

BullpenPitch _p(
  String id,
  String type, {
  ZoneTarget? target,
  double? ax,
  double? ay,
  String session = 's1',
  int seq = 1,
  DateTime? ts,
  int? setIdx,
}) =>
    BullpenPitch(
      id: id,
      sessionId: session,
      userId: 'u',
      seq: seq,
      pitchType: type,
      target: target,
      actualX: ax,
      actualY: ay,
      timestamp: ts ?? _t0,
      planSetIndex: setIdx,
    );

BullpenSession _session(String id, {String hand = 'R', DateTime? at, SessionStatus status = SessionStatus.finished, Map<String, dynamic>? plan}) =>
    BullpenSession(
      id: id,
      userId: 'u',
      type: BullpenType.command,
      throwsHand: hand,
      startedAt: at ?? _t0,
      endedAt: (at ?? _t0).add(const Duration(minutes: 20)),
      status: status,
      plan: plan,
    );

/// Builds [n] targeted pitches of [type] in one finished session, [hits] of
/// them landing inside a 0.4 x 0.4 target at the center, the rest far outside.
({List<BullpenSession> sessions, List<BullpenPitch> pitches}) _data(
  Map<String, List<int>> spec, {
  String hand = 'R',
  double missX = 1.3,
  double missY = 0.5,
}) {
  final pitches = <BullpenPitch>[];
  var n = 0;
  spec.forEach((type, v) {
    final total = v[0], hits = v[1];
    for (var i = 0; i < total; i++) {
      final hit = i < hits;
      pitches.add(_p(
        'p${n++}',
        type,
        target: const ZoneTarget(0.5, 0.5, 0.4, 0.4),
        ax: hit ? 0.5 : missX,
        ay: hit ? 0.5 : missY,
        seq: n,
        ts: _t0.add(Duration(minutes: n)),
      ));
    }
  });
  return (sessions: [_session('s1', hand: hand)], pitches: pitches);
}

void main() {
  group('Zone geometry', () {
    test('target rectangle contains its edges and nothing beyond', () {
      const t = ZoneTarget(0.5, 0.5, 0.4, 0.2);
      expect(t.contains(0.3, 0.4), isTrue);
      expect(t.contains(0.7, 0.6), isTrue);
      expect(t.contains(0.71, 0.5), isFalse);
      expect(t.contains(0.5, 0.39), isFalse);
    });

    test('width and height are independent and convert to inches', () {
      const t = ZoneTarget(0.5, 0.5, 0.2, 0.5);
      expect(t.widthIn, closeTo(3.4, 1e-9));
      expect(t.heightIn, closeTo(12.0, 1e-9));
    });

    test('distance is measured in inches (17 in wide, 24 in tall)', () {
      expect(ZoneGeo.distanceIn(0.5, 0.5, 0.5, 1.0), closeTo(12.0, 1e-9));
      expect(ZoneGeo.distanceIn(0.0, 0.5, 1.0, 0.5), closeTo(17.0, 1e-9));
    });

    test('strike = inside the zone', () {
      expect(ZoneGeo.inZone(0.0, 1.0), isTrue);
      expect(ZoneGeo.inZone(1.01, 0.5), isFalse);
      expect(ZoneGeo.inZone(0.5, -0.01), isFalse);
    });
  });

  group('Analytics', () {
    test('target accuracy and strike % are separate measures', () {
      final s = BullpenStats();
      // On target.
      s.add(_p('a', 'fb', target: const ZoneTarget(0.5, 0.5, 0.2, 0.2), ax: 0.5, ay: 0.5));
      // Missed the target but still a strike.
      s.add(_p('b', 'fb', target: const ZoneTarget(0.2, 0.2, 0.1, 0.1), ax: 0.8, ay: 0.8));
      // Ball outside the zone, missed target.
      s.add(_p('c', 'fb', target: const ZoneTarget(0.5, 0.5, 0.2, 0.2), ax: 1.2, ay: 0.5));
      // No target, strike: counts for strike % only.
      s.add(_p('d', 'fb', ax: 0.4, ay: 0.4));
      expect(s.pitches, 4);
      expect(s.targetPitches, 3);
      expect(s.targetHits, 1);
      expect(s.targetAccuracy, closeTo(33.333, 0.01));
      expect(s.landed, 4);
      expect(s.strikes, 3);
      expect(s.zonePct, closeTo(75.0, 1e-9));
    });

    test('average distance only counts pitches that had a target', () {
      final s = BullpenStats();
      s.add(_p('a', 'fb', target: const ZoneTarget(0.5, 0.5, 0.2, 0.2), ax: 0.5, ay: 1.0)); // 12 in
      s.add(_p('b', 'fb', target: const ZoneTarget(0.5, 0.5, 0.2, 0.2), ax: 0.5, ay: 0.5)); // 0 in
      s.add(_p('c', 'fb', ax: 0.0, ay: 0.0)); // no target
      expect(s.avgDistanceIn, closeTo(6.0, 1e-9));
    });

    test('arm-side vs glove-side flips with throwing hand (catcher view)', () {
      const t = ZoneTarget(0.5, 0.5, 0.2, 0.2);
      final left = _p('a', 'fb', target: t, ax: 0.1, ay: 0.5); // catcher's left
      final r = MissCounts()..add(left, 'R');
      final l = MissCounts()..add(left, 'L');
      expect(r.armSide, 1);
      expect(r.gloveSide, 0);
      expect(l.gloveSide, 1);
      expect(l.armSide, 0);
    });

    test('high / low use the target edges, and a pitch can be two directions', () {
      const t = ZoneTarget(0.5, 0.5, 0.2, 0.2);
      final m = MissCounts()
        ..add(_p('a', 'fb', target: t, ax: 0.5, ay: 0.9), 'R') // high
        ..add(_p('b', 'fb', target: t, ax: 0.5, ay: 0.1), 'R') // low
        ..add(_p('c', 'fb', target: t, ax: 0.9, ay: 0.9), 'R') // high + glove
        ..add(_p('d', 'fb', target: t, ax: 0.5, ay: 0.5), 'R'); // hit: not a miss
      expect(m.misses, 3);
      expect(m.high, 2);
      expect(m.low, 1);
      expect(m.gloveSide, 1);
    });

    test('a miss direction needs enough misses AND a clear lean', () {
      const t = ZoneTarget(0.5, 0.5, 0.2, 0.2);
      final few = MissCounts();
      for (var i = 0; i < 5; i++) {
        few.add(_p('a$i', 'fb', target: t, ax: 0.5, ay: 0.9), 'R');
      }
      expect(few.dominant, isNull); // only 5 misses

      final many = MissCounts();
      for (var i = 0; i < 10; i++) {
        many.add(_p('b$i', 'fb', target: t, ax: 0.5, ay: 0.9), 'R');
      }
      expect(many.dominant, 'high');

      final mixed = MissCounts();
      for (var i = 0; i < 5; i++) {
        mixed.add(_p('c$i', 'fb', target: t, ax: 0.5, ay: 0.9), 'R'); // high
        mixed.add(_p('d$i', 'fb', target: t, ax: 0.5, ay: 0.1), 'R'); // low
      }
      expect(mixed.dominant, isNull);
    });

    test('analysis ignores unfinished bullpens and applies filters', () {
      final d = _data({'fb': [10, 5], 'cv': [10, 8]});
      final open = _session('open', status: SessionStatus.active);
      final extra = _p('x', 'fb', session: 'open', target: const ZoneTarget(0.5, 0.5, 0.4, 0.4), ax: 0.5, ay: 0.5);
      final all = BullpenAnalytics.analyze(sessions: [...d.sessions, open], pitches: [...d.pitches, extra]);
      expect(all.overall.pitches, 20);
      expect(all.sessionCount, 1);
      final cv = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches, pitchType: 'cv');
      expect(cv.overall.pitches, 10);
      expect(cv.overall.targetAccuracy, 80);
      final future = BullpenAnalytics.analyze(
          sessions: d.sessions, pitches: d.pitches, since: _t0.add(const Duration(days: 1)));
      expect(future.hasData, isFalse);
    });

    test('target size buckets let sessions be compared fairly', () {
      expect(sizeBucketOf(const ZoneTarget(0.5, 0.5, 0.2, 0.2)), SizeBucket.small);
      expect(sizeBucketOf(const ZoneTarget(0.5, 0.5, 0.4, 0.4)), SizeBucket.medium);
      expect(sizeBucketOf(const ZoneTarget(0.5, 0.5, 0.9, 0.9)), SizeBucket.large);
    });

    test('plan results count reps per plan set', () {
      final plan = BullpenPlan(
        focus: PlanFocus.command,
        createdAt: _t0,
        sets: const [
          PlanSet(pitchType: 'fb', reps: 3, target: ZoneTarget(0.5, 0.5, 0.4, 0.4), purpose: 'x'),
          PlanSet(pitchType: 'cv', reps: 2, target: ZoneTarget(0.5, 0.5, 0.4, 0.4), purpose: 'y'),
        ],
      );
      final s = _session('s1', plan: plan.toJson());
      final ps = [
        _p('a', 'fb', target: const ZoneTarget(0.5, 0.5, 0.4, 0.4), ax: 0.5, ay: 0.5, setIdx: 0),
        _p('b', 'fb', target: const ZoneTarget(0.5, 0.5, 0.4, 0.4), ax: 1.2, ay: 0.5, setIdx: 0),
        _p('c', 'cv', target: const ZoneTarget(0.5, 0.5, 0.4, 0.4), ax: 0.5, ay: 0.5, setIdx: 1),
        _p('d', 'cv', target: const ZoneTarget(0.5, 0.5, 0.4, 0.4), ax: 0.5, ay: 0.5, setIdx: 1),
      ];
      final r = BullpenAnalytics.planResults(s, ps);
      expect(r[0].thrown, 2);
      expect(r[0].completed, isFalse);
      expect(r[0].stats.targetAccuracy, 50);
      expect(r[1].completed, isTrue);
    });
  });

  group('Game Mode rules', () {
    test('difficulty only makes challenges harder', () {
      final s = ChallengeRules.streak.values.toList();
      for (var i = 1; i < s.length; i++) {
        expect(s[i].goal, greaterThanOrEqualTo(s[i - 1].goal));
        expect(s[i].zoneScale, lessThan(s[i - 1].zoneScale));
      }
      final a = ChallengeRules.accuracy.values.toList();
      for (var i = 1; i < a.length; i++) {
        expect(a[i].size, lessThan(a[i - 1].size));
        expect(a[i].required, greaterThan(a[i - 1].required));
      }
      final q = ChallengeRules.sequence.values.toList();
      for (var i = 1; i < q.length; i++) {
        expect(q[i].length, greaterThan(q[i - 1].length));
        expect(q[i].size, lessThan(q[i - 1].size));
      }
    });

    test('Strike Streak: reaching the goal passes', () {
      final e = StreakEngine(Difficulty.beginner, 'fb');
      for (var i = 0; i < 4; i++) {
        expect(e.submit(0.5, 0.5), isTrue);
        expect(e.finished, isFalse);
      }
      e.submit(0.4, 0.6);
      expect(e.finished, isTrue);
      expect(e.success, isTrue);
      expect(e.score, 5);
    });

    test('Strike Streak: the first ball fails the attempt and keeps the streak reached', () {
      final e = StreakEngine(Difficulty.beginner, 'fb');
      e.submit(0.5, 0.5);
      e.submit(0.5, 0.5);
      e.submit(0.5, 1.2); // ball
      expect(e.finished, isTrue);
      expect(e.success, isFalse);
      expect(e.score, 2);
      expect(e.endReason, EndReason.miss);
      expect(e.submit(0.5, 0.5), isFalse); // nothing counts after it ends
      expect(e.pitchesThrown, 3);
    });

    test('Strike Streak: harder levels shrink the strike area', () {
      // 0.1 is inside the normal zone but outside the Elite 55% area.
      expect(StreakEngine(Difficulty.beginner, 'fb').submit(0.1, 0.5), isTrue);
      expect(StreakEngine(Difficulty.elite, 'fb').submit(0.1, 0.5), isFalse);
    });

    test('Target Accuracy: passes with enough hits after all pitches', () {
      final e = AccuracyEngine(Difficulty.intermediate, 'fb', 4); // 5 of 10, middle
      final t = e.currentTarget!;
      for (var i = 0; i < 5; i++) {
        e.submit(t.x, t.y);
      }
      expect(e.finished, isFalse); // keeps going until all 10 are thrown
      for (var i = 0; i < 5; i++) {
        e.submit(1.4, 1.3);
      }
      expect(e.finished, isTrue);
      expect(e.success, isTrue);
      expect(e.score, 5);
    });

    test('Target Accuracy: ends early once the goal is out of reach', () {
      final e = AccuracyEngine(Difficulty.intermediate, 'fb', 4);
      for (var i = 0; i < 5; i++) {
        e.submit(1.4, 1.3);
      }
      expect(e.finished, isFalse); // 5 left, still possible
      e.submit(1.4, 1.3);
      expect(e.finished, isTrue); // 4 left, need 5
      expect(e.success, isFalse);
      expect(e.endReason, EndReason.outOfPitches);
    });

    test('Pitch Sequencing: every target in order passes; a miss fails', () {
      final seq = ['fb', 'cv', 'fb', 'ch', 'fb'];
      final ok = SequenceEngine(Difficulty.advanced, seq);
      for (var i = 0; i < 5; i++) {
        expect(ok.currentPitchType, seq[i]);
        final t = ok.currentTarget!;
        ok.submit(t.x, t.y);
      }
      expect(ok.success, isTrue);
      expect(ok.score, 5);

      final bad = SequenceEngine(Difficulty.advanced, seq);
      var t = bad.currentTarget!;
      bad.submit(t.x, t.y);
      t = bad.currentTarget!;
      bad.submit(t.x, t.y);
      bad.submit(1.4, -0.3);
      expect(bad.finished, isTrue);
      expect(bad.success, isFalse);
      expect(bad.score, 2);
      expect(bad.log.last['pitchType'], 'fb');
    });

    test('the same difficulty always asks for the same targets', () {
      final a = SequenceEngine(Difficulty.intermediate, ['fb', 'cv', 'fb', 'ch']);
      final b = SequenceEngine(Difficulty.intermediate, ['sl', 'sl', 'sl', 'sl']);
      for (var i = 0; i < 4; i++) {
        expect(a.targetForStep(i).x, b.targetForStep(i).x);
        expect(a.targetForStep(i).y, b.targetForStep(i).y);
        expect(a.targetForStep(i).w, b.targetForStep(i).w);
      }
    });

    test('default sequence only uses pitch types the player has', () {
      final seq = ChallengeRules.defaultSequence(Difficulty.elite, ['fb', 'sl']);
      expect(seq.length, 6);
      expect(seq.every(['fb', 'sl'].contains), isTrue);
    });

    test('a finished attempt becomes a saved record, failed or not', () {
      final e = StreakEngine(Difficulty.advanced, 'cv')..submit(0.5, 0.5)..submit(5, 5);
      final a = attemptFromEngine(id: 'a1', userId: 'u', engine: e, startedAt: _t0, endedAt: _t0);
      expect(a.success, isFalse);
      expect(a.score, 1);
      expect(a.goal, 10);
      expect(a.pitchesThrown, 2);
      expect(a.detail.length, 2);
      final back = ChallengeAttempt.fromRow(a.toRow());
      expect(back.mode, ChallengeMode.streak);
      expect(back.difficulty, Difficulty.advanced);
      expect(back.endReason, 'miss');
    });

    test('history groups by challenge and difficulty', () {
      ChallengeAttempt at(String id, bool ok, int score, int day) => ChallengeAttempt(
            id: id, userId: 'u', mode: ChallengeMode.streak, difficulty: Difficulty.beginner, pitchKey: 'fb',
            startedAt: _t0, endedAt: _t0.add(Duration(days: day)), success: ok, score: score, goal: 5,
            pitchesThrown: score + 1, detail: const [], endReason: ok ? 'goal' : 'miss');
      final sums = summarizeChallenges([at('1', false, 2, 1), at('2', true, 5, 2), at('3', false, 4, 3)]);
      expect(sums.length, 1);
      expect(sums.first.attempts, 3);
      expect(sums.first.passed, 1);
      expect(sums.first.failed, 2);
      expect(sums.first.bestScore, 5);
      expect(sums.first.recent.first.id, '3'); // newest first
    });
  });

  group('Bullpen workflow + saving', () {
    late InMemoryBullpenRepository repo;
    late BullpenStore store;
    var now = _t0;
    var n = 0;

    BullpenStore make() => BullpenStore(repo: repo, userId: 'u', clock: () => now, idGenerator: () => 'id${n++}');

    setUp(() {
      repo = InMemoryBullpenRepository();
      now = _t0;
      n = 0;
      store = make();
    });

    Future<void> addN(int count, {double ax = 0.5}) async {
      for (var i = 0; i < count; i++) {
        await store.addPitch(
            pitchType: 'fb', target: const ZoneTarget(0.5, 0.5, 0.4, 0.4), actualX: ax, actualY: 0.5);
      }
    }

    test('everything is saved as it happens, and reloads', () async {
      await store.load();
      await store.startSession(type: BullpenType.command, hand: 'L');
      await addN(3);
      expect(repo.sessions.length, 1);
      expect(repo.pitches.length, 3);
      await store.finish();

      final again = make();
      await again.load();
      expect(again.sessions.single.status, SessionStatus.finished);
      expect(again.sessions.single.throwsHand, 'L');
      expect(again.pitchesFor(again.sessions.single.id).length, 3);
      expect(again.lastHand, 'L');
    });

    test('an open bullpen is still there after a reload (resume)', () async {
      await store.load();
      await store.startSession(type: BullpenType.general, hand: 'R');
      await addN(2);
      final again = make();
      await again.load();
      expect(again.activeSession, isNotNull);
      expect(again.pitchesFor(again.activeSession!.id).length, 2);
    });

    test('undo removes the last pitch; delete renumbers; edit updates', () async {
      await store.load();
      await store.startSession(type: BullpenType.command, hand: 'R');
      await addN(3);
      await store.undoLast();
      expect(store.pitchesFor(store.activeSession!.id).map((p) => p.seq), [1, 2]);

      final first = store.pitchesFor(store.activeSession!.id).first;
      await store.deletePitch(first.id);
      final left = store.pitchesFor(store.activeSession!.id);
      expect(left.map((p) => p.seq), [1]);
      expect(repo.pitches.values.map((p) => p.seq), [1]);

      await store.updatePitch(left.first.copyWith(pitchType: 'cv', actualX: 1.4, velocity: 81.5, result: 'ball'));
      final saved = repo.pitches[left.first.id]!;
      expect(saved.pitchType, 'cv');
      expect(saved.actualX, 1.4);
      expect(saved.velocity, 81.5);
      expect(saved.result, 'ball');
    });

    test('velocity, result and notes are optional', () async {
      await store.load();
      await store.startSession(type: BullpenType.command, hand: 'R');
      final p = await store.addPitch(pitchType: 'fb', actualX: 0.5, actualY: 0.5);
      expect(p, isNotNull);
      expect(p!.velocity, isNull);
      expect(p.result, isNull);
      expect(p.notes, isNull);
      expect(p.target, isNull); // "no target" pitches are allowed
    });

    test('pause blocks new pitches and does not count toward time', () async {
      await store.load();
      await store.startSession(type: BullpenType.command, hand: 'R');
      now = _t0.add(const Duration(minutes: 5));
      await store.pause();
      expect(store.activeSession!.status, SessionStatus.paused);
      expect(await store.addPitch(pitchType: 'fb', actualX: 0.5, actualY: 0.5), isNull);

      now = _t0.add(const Duration(minutes: 15)); // 10 minutes paused
      await store.resume();
      expect(store.activeSession!.status, SessionStatus.active);
      expect(store.activeSession!.pausedMs, const Duration(minutes: 10).inMilliseconds);
      await store.addPitch(pitchType: 'fb', actualX: 0.5, actualY: 0.5);

      now = _t0.add(const Duration(minutes: 25));
      final done = await store.finish();
      expect(done!.elapsed(), const Duration(minutes: 15)); // 25 total - 10 paused
    });

    test('finishing a bullpen with no pitches discards it', () async {
      await store.load();
      await store.startSession(type: BullpenType.command, hand: 'R');
      expect(await store.finish(), isNull);
      expect(store.sessions, isEmpty);
      expect(repo.sessions, isEmpty);
    });

    test('bullpen data lives in its own tables (no game data touched)', () async {
      await store.load();
      await store.startSession(type: BullpenType.command, hand: 'R');
      await addN(1);
      // The repository only knows bullpen sessions, pitches and attempts.
      expect(repo.sessions.length, 1);
      expect(repo.pitches.length, 1);
      expect(repo.attempts, isEmpty);
    });

    test('a failed save keeps the data, reports it, and can be retried', () async {
      await store.load();
      await store.startSession(type: BullpenType.command, hand: 'R');
      repo.failWrites = true;
      await addN(1);
      expect(store.pitchesFor(store.activeSession!.id).length, 1);
      expect(store.syncError, isNotNull);
      expect(repo.pitches, isEmpty);

      repo.failWrites = false;
      await store.retrySync();
      expect(store.syncError, isNull);
      expect(repo.pitches.length, 1);
    });

    test('failed Game Mode attempts are saved to history', () async {
      await store.load();
      final e = StreakEngine(Difficulty.beginner, 'fb')..submit(0.5, 0.5)..submit(1.4, 0.5);
      await store.recordAttempt(attemptFromEngine(id: 'a', userId: 'u', engine: e, startedAt: _t0));
      expect(repo.attempts.values.single.success, isFalse);
      expect(repo.attempts.values.single.score, 1);
    });

    test('a load failure is reported instead of crashing', () async {
      final broken = _BrokenRepo();
      final s = BullpenStore(repo: broken, userId: 'u');
      await s.load();
      expect(s.loaded, isTrue);
      expect(s.loadError, isNotNull);
    });

    test('sending a plan to Bullpen stores it and requests the tab', () {
      final plan = BullpenPlan(focus: PlanFocus.command, createdAt: _t0, sets: const []);
      store.sendPlanToBullpen(plan);
      expect(store.pendingPlan, same(plan));
      expect(store.navigateRequest, 'Bullpen');
      expect(store.takePendingPlan(), same(plan));
      expect(store.pendingPlan, isNull);
    });
  });

  group('Plans and recommendations', () {
    String label(String t) => t.toUpperCase();

    test('command plan puts the least accurate pitch first and sizes targets from results', () {
      // FB 18/20 = 90% (strong), CV 4/20 = 20% (weak).
      final d = _data({'fb': [20, 18], 'cv': [20, 4]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final plan = PlanGenerator.generate(
        focus: PlanFocus.command,
        analysis: a,
        attempts: const [],
        availableTypes: const ['fb', 'cv', 'ch'],
        label: label,
      );
      expect(plan.sets.first.pitchType, 'cv');
      expect(plan.sets.first.reps, 20);
      final fb = plan.sets.firstWhere((s) => s.pitchType == 'fb');
      final cv = plan.sets.firstWhere((s) => s.pitchType == 'cv');
      expect(fb.target.w, lessThan(0.4)); // 90% accuracy: smaller target
      expect(cv.target.w, greaterThan(0.4)); // 20% accuracy: bigger target
      // CH has no history: default medium size, listed after pitches with data.
      final ch = plan.sets.firstWhere((s) => s.pitchType == 'ch');
      expect(ch.target.w, PlanGenerator.defaultSize);
      expect(plan.sets.last.pitchType, 'ch');
    });

    test('with no history the plan uses defaults and says so', () {
      final a = BullpenAnalytics.analyze(sessions: const [], pitches: const []);
      final plan = PlanGenerator.generate(
        focus: PlanFocus.general,
        analysis: a,
        attempts: const [],
        availableTypes: const ['fb', 'cv'],
        label: label,
      );
      expect(plan.sets, isNotEmpty);
      expect(plan.rationale.join(' '), contains('only 0 targeted bullpen pitches'));
    });

    test('every focus produces a usable plan with positive reps', () {
      final d = _data({'fb': [20, 10], 'cv': [20, 5], 'ch': [20, 15]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      for (final f in PlanFocus.values) {
        final plan = PlanGenerator.generate(
          focus: f,
          analysis: a,
          attempts: const [],
          availableTypes: const ['fb', 'cv', 'ch', 'sl'],
          label: label,
          gameUsageOrder: const ['fb', 'ch', 'cv'],
        );
        expect(plan.sets, isNotEmpty, reason: f.name);
        expect(plan.sets.every((s) => s.reps > 0 && s.target.w > 0 && s.target.h > 0), isTrue, reason: f.name);
        expect(plan.focus, f);
      }
    });

    test('plans survive being saved and loaded', () {
      final d = _data({'fb': [20, 10]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final plan = PlanGenerator.generate(
          focus: PlanFocus.command, analysis: a, attempts: const [], availableTypes: const ['fb'], label: label);
      final back = BullpenPlan.fromJson(plan.toJson());
      expect(back.sets.length, plan.sets.length);
      expect(back.sets.first.target.w, plan.sets.first.target.w);
      expect(back.totalReps, plan.totalReps);
    });

    test('weakest zone area is found from where targets were missed', () {
      final ps = <BullpenPitch>[];
      // 6 tries each in the middle (all hit) and bottom-left (all miss).
      for (var i = 0; i < 6; i++) {
        ps.add(_p('m$i', 'fb', target: const ZoneTarget(0.5, 0.5, 0.2, 0.2), ax: 0.5, ay: 0.5));
        ps.add(_p('l$i', 'fb', target: const ZoneTarget(0.17, 0.17, 0.2, 0.2), ax: 0.9, ay: 0.9));
      }
      expect(weakestCell(ps, 'fb'), 6); // bottom-left
      expect(weakestCell(ps, 'fb', minPerCell: 7), isNull); // not enough tries
    });

    test('too little data: no bullpen advice, and it says why', () {
      final d = _data({'fb': [10, 5]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final r = Recommender.findings(
          analysis: a, comparison: null, attempts: const [], lastPlanResults: const [], label: label);
      expect(r.insufficientData, contains('10 pitches with a target'));
      expect(r.findings, isEmpty);
    });

    test('findings quote the pitcher\'s own numbers and have all four parts', () {
      final d = _data({'fb': [20, 18], 'cv': [20, 4]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final r = Recommender.findings(
          analysis: a, comparison: null, attempts: const [], lastPlanResults: const [], label: label);
      expect(r.insufficientData, isNull);
      final f = r.findings.firstWhere((f) => f.id == 'low-accuracy-cv');
      expect(f.whatHappened, contains('20%'));
      expect(f.whatHappened, contains('20 targeted pitches'));
      expect(f.whatItMeans, isNotEmpty);
      expect(f.whatToDo, isNotEmpty);
      expect(f.howToMeasure, contains('20%'));
    });

    test('misses that lean one way become a finding (and name the direction)', () {
      // Every miss is high.
      final d = _data({'fb': [30, 10]}, missX: 0.5, missY: 1.3);
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final r = Recommender.findings(
          analysis: a, comparison: null, attempts: const [], lastPlanResults: const [], label: label);
      final f = r.findings.firstWhere((f) => f.id == 'miss-lean-fb');
      expect(f.whatHappened, contains('20 of 20'));
      expect(f.whatHappened, contains('high'));
    });

    test('sequencing failures point at the pitch where sequences break', () {
      ChallengeAttempt fail(String id, String brokeOn) => ChallengeAttempt(
            id: id, userId: 'u', mode: ChallengeMode.sequence, difficulty: Difficulty.beginner,
            pitchKey: 'fb-cv-fb', startedAt: _t0, endedAt: _t0, success: false, score: 1, goal: 3, pitchesThrown: 2,
            detail: [{'pitchType': brokeOn, 'hit': false}], endReason: 'miss');
      final a = BullpenAnalytics.analyze(sessions: const [], pitches: const []);
      final r = Recommender.findings(
        analysis: a,
        comparison: null,
        attempts: [fail('1', 'cv'), fail('2', 'cv'), fail('3', 'fb')],
        lastPlanResults: const [],
        label: label,
      );
      final f = r.findings.firstWhere((f) => f.id == 'sequence-break');
      expect(f.whatHappened, contains('2 of 3'));
      expect(f.whatHappened, contains('CV'));
    });
  });

  group('Bullpen vs. games', () {
    int id = 0;
    PitchEvent game(String type, String call, DateTime ts) => PitchEvent(
          id: '${id++}', userId: 'u', game: 'Opp', gameNumber: 1, batter: 1, batterNumber: 1, battingOrder: 1,
          hand: 'R', eventType: 'pitch', pitchNum: 1, pitchType: type, call: call, outcome: null, ab: 0, outs: 0,
          er: 0, xCoord: null, yCoord: null, battedType: null, inning: 1, paId: id, timestamp: ts);

    test('small game samples are never compared', () {
      final d = _data({'fb': [20, 10]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final games = [for (var i = 0; i < 5; i++) game('fb', 'b', _t0)];
      final c = BullpenAnalytics.compare(bullpen: a, gamePitches: games);
      final fb = c.rows.firstWhere((r) => r.pitchType == 'fb');
      expect(fb.gameEnough, isFalse);
      expect(fb.weakInGame, isNull);
      expect(fb.weakInBoth, isFalse);
    });

    test('a pitch below the pitcher\'s own average in both settings is flagged', () {
      // Bullpen: FB 18/20 on target, CV 2/20.   Games: FB mostly strikes, CV mostly balls.
      final d = _data({'fb': [20, 18], 'cv': [20, 2]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final games = <PitchEvent>[
        for (var i = 0; i < 20; i++) game('fb', i < 16 ? 'ss' : 'b', _t0),
        for (var i = 0; i < 20; i++) game('cv', i < 4 ? 'ss' : 'b', _t0),
      ];
      final c = BullpenAnalytics.compare(bullpen: a, gamePitches: games);
      final cv = c.rows.firstWhere((r) => r.pitchType == 'cv');
      final fb = c.rows.firstWhere((r) => r.pitchType == 'fb');
      expect(cv.weakInBoth, isTrue);
      expect(fb.weakInBoth, isFalse);
      expect(c.overallGameStrike, isNotNull);
    });

    test('no game target accuracy exists: only bullpen rows carry it', () {
      final d = _data({'fb': [20, 10]});
      final a = BullpenAnalytics.analyze(sessions: d.sessions, pitches: d.pitches);
      final c = BullpenAnalytics.compare(bullpen: a, gamePitches: const []);
      expect(c.rows.single.bullpen!.targetAccuracy, 50);
      expect(c.rows.single.gamePitches, 0);
      expect(c.rows.single.gameStrikePct, isNull);
    });
  });
}

class _BrokenRepo extends InMemoryBullpenRepository {
  @override
  Future<List<BullpenSession>> loadSessions(String userId) async => throw Exception('no table');
}
