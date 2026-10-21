// Game Input: Undo, pitch count, Edit/Delete sync and persistence.
//
// Uses an in-memory stand-in for the database, so no Supabase connection is
// needed. "Reopening the app" is simulated by building a brand-new AppSession
// that loads what the first session saved.
//
// Run with:  flutter test test/game_undo_persistence_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/models/pitcher.dart';
import 'package:pitching_analytics/models/user.dart';
import 'package:pitching_analytics/services/app_session.dart';
import 'package:pitching_analytics/services/auth_service.dart';
import 'package:pitching_analytics/services/stats_service.dart';
import 'package:pitching_analytics/services/storage_service.dart';

/// In-memory database. Also records whether two saves ever overlapped.
class FakeStorage extends StorageService {
  final Map<String, List<PitchEvent>> pitches = {};
  final Map<String, Map<String, dynamic>> live = {};
  int inFlight = 0;
  int maxInFlight = 0;
  bool failSaves = false;

  @override
  Future<List<PitchEvent>> loadPitchesForUser(String userId) async =>
      List<PitchEvent>.from(pitches[userId] ?? const []);

  @override
  Future<void> savePitchesForUser(String userId, List<PitchEvent> list) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    inFlight--;
    if (failSaves) throw Exception('offline');
    pitches[userId] = List<PitchEvent>.from(list);
  }

  @override
  Future<Map<String, dynamic>?> loadLiveState(String userId) async => live[userId];

  @override
  Future<void> saveLiveState(String userId, Map<String, dynamic> state) async {
    if (failSaves) throw Exception('offline');
    live[userId] = Map<String, dynamic>.from(state);
  }

  @override
  Future<List<String>> loadCustomPitchTypes(String userId) async => [];
  @override
  Future<List<String>> loadHiddenBuiltInPitchTypes(String userId) async => [];
  @override
  Future<Map<int, String>> loadBatterNames(String userId) async => {};
  @override
  Future<Map<String, String>> loadCustomPitchTypeNames(String userId) async => {};
  @override
  Future<Map<String, int>> loadCustomPitchTypeColors(String userId) async => {};
}

const _pitcher = Pitcher(id: 'p1', ownerId: 'u1', displayName: 'Pitcher', username: 'pitcher1');

AppSession _newSession(FakeStorage st) {
  final s = AppSession(auth: AuthService(), storage: st);
  s.currentUser = AppUser(id: 'u1', username: 'user', email: 'user@example.com');
  s.activePitcher = _pitcher;
  return s;
}

/// "Close and reopen the app": a fresh session that loads the saved data.
Future<AppSession> _reopen(FakeStorage st) async {
  final s = AppSession(auth: AuthService(), storage: st);
  s.currentUser = AppUser(id: 'u1', username: 'user', email: 'user@example.com');
  s.activePitcher = const Pitcher(id: 'other', ownerId: 'u1', displayName: 'x', username: 'xother');
  await s.switchPitcher(_pitcher);
  return s;
}

Future<void> _pitch(AppSession s, String call, {String? outcome}) =>
    s.addPitch(pitchType: 'fb', call: call, bipOutcome: outcome);

void main() {
  late FakeStorage st;
  late AppSession s;

  setUp(() {
    st = FakeStorage();
    s = _newSession(st);
    s.setGame('Eagles', 1, 2026);
    s.setBatter(7, 1);
  });

  test('A: enter three pitches, undo once -> two pitches and correct counts', () async {
    await _pitch(s, 'b');
    await _pitch(s, 'sl');
    await _pitch(s, 'f');
    await s.undoLastPitch();
    expect(s.pitches.length, 2);
    expect((s.balls, s.strikes), (1, 1));
    expect(s.pitchNumInAB, 3);
    expect(s.currentGamePitchCount, 2);
  });

  test('B: undo the pitch that ended an at-bat -> previous batter and 2-1 count', () async {
    await _pitch(s, 'b');
    await _pitch(s, 'b');
    await _pitch(s, 'sl'); // 2-1
    await _pitch(s, 'ip', outcome: 'go'); // ground out: at-bat over, next batter
    expect(s.battingOrderSlot, 2);
    expect(s.outs, 1);
    expect(s.completedPAs, 1);

    await s.undoLastPitch();

    expect(s.battingOrderSlot, 1);
    expect(s.committedJersey, 7);
    expect((s.balls, s.strikes), (2, 1));
    expect(s.outs, 0);
    expect(s.completedPAs, 0);
    expect(s.pitchNumInAB, 4);
    expect(s.pitches.length, 3);
    expect(s.currentGamePitchCount, 3);
  });

  test('C: undo the first pitch of a new batter -> state before that pitch', () async {
    await _pitch(s, 'ip', outcome: 'fo'); // batter 1 out on the first pitch
    s.setBatter(8, 2);
    await _pitch(s, 'b'); // first pitch to the new batter
    expect(s.balls, 1);

    await s.undoLastPitch();

    expect(s.committedJersey, 8);
    expect(s.battingOrderSlot, 2);
    expect((s.balls, s.strikes), (0, 0));
    expect(s.pitchNumInAB, 1);
    expect(s.completedPAs, 1);
    expect(s.outs, 1);
    expect(s.currentGamePitchCount, 1);
  });

  test('undo one step at a time returns the exact state before each action', () async {
    final states = <List<Object?>>[];
    List<Object?> snap() =>
        [s.balls, s.strikes, s.outs, s.pitchNumInAB, s.battingOrderSlot, s.completedPAs, s.pitches.length];
    states.add(snap());
    await _pitch(s, 'b');
    states.add(snap());
    await _pitch(s, 'ss');
    states.add(snap());
    await _pitch(s, 'sl');
    states.add(snap());
    for (var i = states.length - 2; i >= 0; i--) {
      await s.undoLastPitch();
      expect(snap(), states[i]);
    }
  });

  test('pickoff is not a pitch and can be undone', () async {
    await _pitch(s, 'b');
    await s.addPickoff();
    expect(s.pitches.length, 2);
    expect(s.currentGamePitchCount, 1); // the pickoff is not a pitch
    expect(s.outs, 1);
    await s.undoLastPitch();
    expect(s.pitches.length, 1);
    expect(s.outs, 0);
    expect(s.currentGamePitchCount, 1);
  });

  test('D: each game shows its own pitch count', () async {
    await _pitch(s, 'b');
    await _pitch(s, 'sl');
    s.setGame('Hawks', 1, 2026);
    s.setBatter(3, 1);
    await _pitch(s, 'b');
    await _pitch(s, 'b');
    await _pitch(s, 'ss');
    expect(s.currentGamePitchCount, 3);
    s.setGame('Eagles', 1, 2026);
    expect(s.currentGamePitchCount, 2);
    s.setGame('Hawks', 1, 2026);
    expect(s.currentGamePitchCount, 3);
  });

  test('undo cannot reach into another game', () async {
    await _pitch(s, 'b');
    s.setGame('Hawks', 1, 2026);
    s.setBatter(3, 1);
    await s.undoLastPitch(); // nothing to undo in this game
    s.setGame('Eagles', 1, 2026);
    expect(s.pitches.length, 1);
    expect(s.currentGamePitchCount, 1);
  });

  test('E: a pitch deleted in Edit At-Bats stays deleted after reopening', () async {
    await _pitch(s, 'b');
    await _pitch(s, 'sl');
    await _pitch(s, 'f');
    await s.deletePitchAt(1);
    expect(s.pitches.length, 2);
    expect(s.currentGamePitchCount, 2);
    expect((s.balls, s.strikes), (1, 1)); // rebuilt from the remaining pitches

    final s2 = await _reopen(st);
    expect(s2.pitches.length, 2);
    expect(s2.currentGamePitchCount, 2);
    expect(st.pitches['p1']!.length, 2);
  });

  test('F: an undone pitch does not come back after reopening', () async {
    await _pitch(s, 'b');
    await _pitch(s, 'sl');
    await s.undoLastPitch();
    final s2 = await _reopen(st);
    expect(s2.pitches.length, 1);
    expect((s2.balls, s2.strikes), (1, 0));
    expect(s2.committedJersey, 7);
    expect(s2.currentOpponent, 'Eagles');
    expect(s2.currentGamePitchCount, 1);
  });

  test('G: autosave restores batter, count, outs, inning and pitch count', () async {
    await _pitch(s, 'ip', outcome: 'go'); // 1 out, next batter
    s.setBatter(8, 2);
    await _pitch(s, 'b');
    await _pitch(s, 'b');
    await _pitch(s, 'sl'); // 2-1 to batter #8
    final s2 = await _reopen(st);
    expect(s2.currentOpponent, 'Eagles');
    expect(s2.committedJersey, 8);
    expect(s2.battingOrderSlot, 2);
    expect((s2.balls, s2.strikes), (2, 1));
    expect(s2.outs, 1);
    expect(s2.completedPAs, 1);
    expect(s2.currentGamePitchCount, 4);
    // Undo still works after reopening, and restores the exact earlier state.
    await s2.undoLastPitch();
    expect((s2.balls, s2.strikes), (2, 0));
    expect(s2.currentGamePitchCount, 3);
  });

  test('state is rebuilt from the saved pitches when no live state was saved', () async {
    await _pitch(s, 'b');
    await _pitch(s, 'ss');
    await s.flushPendingWrites();
    st.live.clear(); // simulate data saved by an older version of the app
    final s2 = await _reopen(st);
    expect((s2.balls, s2.strikes), (1, 1));
    expect(s2.pitchNumInAB, 3);
    await s2.undoLastPitch(); // falls back to rebuilding from the log
    expect(s2.pitches.length, 1);
    expect((s2.balls, s2.strikes), (1, 0));
  });

  test('a quick Undo right after a pitch is safe and saves are never concurrent', () async {
    final first = _pitch(s, 'b');
    final second = _pitch(s, 'sl');
    final third = _pitch(s, 'ss');
    final undo = s.undoLastPitch();
    await Future.wait([first, second, third, undo]);
    await s.flushPendingWrites();
    expect(s.pitches.length, 2);
    expect(st.pitches['p1']!.length, 2);
    expect(st.maxInFlight, 1);
    expect((s.balls, s.strikes), (1, 1));
  });

  test('a failed save is reported, not hidden, and succeeds on retry', () async {
    st.failSaves = true;
    await _pitch(s, 'b');
    expect(s.saveError, isNotNull);
    st.failSaves = false;
    await s.retrySave();
    expect(s.saveError, isNull);
    expect(st.pitches['p1']!.length, 1);
  });

  test('editing a game name keeps the pitch count with the renamed game', () async {
    await _pitch(s, 'b');
    await s.editCurrentGameInfo('Eagles Blue', 1, 2026);
    expect(s.currentGamePitchCount, 1);
    await s.flushPendingWrites();
    expect(st.pitches['p1']!.single.game, 'Eagles Blue');
  });

  group('Drop Third Strike', () {
    int strikeouts(AppSession x) =>
        StatsService.finalPAs(x.pitches).fold<int>(0, (a, r) => a + r.k);

    /// 0-2 count to batter #7.
    Future<void> twoStrikes() async {
      await _pitch(s, 'ss');
      await _pitch(s, 'sl');
    }

    test('records one pitch and one strikeout, and never an out', () async {
      await twoStrikes();
      final before = s.currentGamePitchCount;
      final msg = await s.addDroppedThirdStrike(pitchType: 'curve');
      expect(msg, isNull);
      expect(s.pitches.last.outcome, 'dk3');
      expect(s.pitches.last.pitchType, 'curve'); // the pitch that was thrown
      expect(s.currentGamePitchCount, before + 1); // one pitch, counted once
      expect(strikeouts(s), 1); // credited exactly once
      expect(s.outs, 0); // NOT an out
      expect(StatsService.outsFromPitches(s.pitches), 0);
      expect(StatsService.pickoffRows(s.pitches), isEmpty);
      expect(s.droppedThirdPending, isTrue);
      expect(s.battingOrderSlot, 1); // the batter does not advance by itself
      expect(s.committedJersey, 7);
      expect((s.balls, s.strikes), (0, 2));
    });

    test('needs two strikes and records nothing otherwise', () async {
      await _pitch(s, 'b');
      final msg = await s.addDroppedThirdStrike(pitchType: 'curve');
      expect(msg, isNotNull);
      expect(s.pitches.length, 1);
      expect(s.droppedThirdPending, isFalse);
    });

    test('cannot be pressed twice for the same play', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      final again = await s.addDroppedThirdStrike(pitchType: 'curve');
      expect(again, isNotNull);
      expect(strikeouts(s), 1);
      expect(s.currentGamePitchCount, 3);
    });

    test('batter reached: next batter up, still no out, still one strikeout', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      await s.resolveDroppedThirdStrike(batterOut: false);
      expect(s.droppedThirdPending, isFalse);
      expect(s.outs, 0);
      expect(s.battingOrderSlot, 2);
      expect((s.balls, s.strikes), (0, 0));
      expect(s.completedPAs, 1);
      expect(s.pitches.length, 3); // no extra row, no extra pitch
      expect(strikeouts(s), 1);
    });

    test('batter thrown out: records exactly one out, separately and on request', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      expect(s.outs, 0);
      await s.resolveDroppedThirdStrike(batterOut: true);
      expect(s.outs, 1);
      expect(StatsService.pickoffRows(s.pitches).length, 1);
      expect(s.currentGamePitchCount, 3); // the throw-out is not a pitch
      expect(strikeouts(s), 1);
      expect(s.battingOrderSlot, 2);
    });

    test('Undo of the dropped third strike restores the whole previous state', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      await s.undoLastPitch();
      expect(s.pitches.length, 2);
      expect(s.droppedThirdPending, isFalse);
      expect((s.balls, s.strikes), (0, 2));
      expect(s.outs, 0);
      expect(s.completedPAs, 0);
      expect(s.battingOrderSlot, 1);
      expect(s.committedJersey, 7);
      expect(s.currentGamePitchCount, 2);
      expect(strikeouts(s), 0);
    });

    test('Undo of "batter reached", then of the strikeout, goes back one step at a time', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      await s.resolveDroppedThirdStrike(batterOut: false);
      await s.undoLastPitch();
      expect(s.droppedThirdPending, isTrue);
      expect(s.battingOrderSlot, 1);
      expect(s.pitches.length, 3);
      await s.undoLastPitch();
      expect(s.droppedThirdPending, isFalse);
      expect(s.pitches.length, 2);
    });

    test('Undo of a throw-out removes the out and keeps the play waiting', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      await s.resolveDroppedThirdStrike(batterOut: true);
      await s.undoLastPitch();
      expect(s.outs, 0);
      expect(s.droppedThirdPending, isTrue);
      expect(StatsService.pickoffRows(s.pitches), isEmpty);
      expect(s.pitches.length, 3);
    });

    test('survives closing and reopening the app, and does not duplicate', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      var s2 = await _reopen(st);
      expect(s2.pitches.where((p) => p.outcome == 'dk3').length, 1);
      expect(s2.droppedThirdPending, isTrue);
      expect(s2.outs, 0);
      expect(s2.committedJersey, 7);
      expect(s2.currentGamePitchCount, 3);
      expect(strikeouts(s2), 1);
      await s2.resolveDroppedThirdStrike(batterOut: false);
      s2 = await _reopen(st);
      expect(s2.droppedThirdPending, isFalse);
      expect(s2.battingOrderSlot, 2);
      expect(s2.pitches.where((p) => p.outcome == 'dk3').length, 1);
    });

    test('still waiting for the play after reopening with no saved live state', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      await s.flushPendingWrites();
      st.live.clear(); // data saved by an older version of the app
      final s2 = await _reopen(st);
      expect(s2.droppedThirdPending, isTrue);
      expect(s2.battingOrderSlot, 1);
      expect(s2.outs, 0);
    });

    test('deleting the dropped third strike in Edit At-Bats leaves a consistent game', () async {
      await twoStrikes();
      await s.addDroppedThirdStrike(pitchType: 'curve');
      await s.deletePitchAt(2);
      expect(s.pitches.length, 2);
      expect(s.droppedThirdPending, isFalse);
      expect((s.balls, s.strikes), (0, 2));
      expect(s.outs, 0);
      expect(s.currentGamePitchCount, 2);
      expect(strikeouts(s), 0);
    });

    test('an ordinary strikeout still records its out and moves to the next batter', () async {
      await _pitch(s, 'ss');
      await _pitch(s, 'ss');
      await _pitch(s, 'ss');
      expect(s.outs, 1);
      expect(s.battingOrderSlot, 2);
      expect(strikeouts(s), 1);
      expect(StatsService.outsFromPitches(s.pitches), 1);
    });
  });

  group('Automatic game numbering', () {
    Future<void> game(AppSession x, String team, int number, {int season = 2026}) async {
      x.setGame(team, number, season);
      x.setBatter(1, 1);
      await _pitch(x, 'b');
    }

    test('two saved games against Eureka -> Game 3, however it is typed', () async {
      await game(s, 'Eureka', 1);
      await game(s, 'EUREKA', 2);
      expect(s.nextGameNumberVs('Eureka', season: 2026), 3);
      expect(s.nextGameNumberVs('  eureka  ', season: 2026), 3);
      expect(s.nextGameNumberVs('Eu  reka', season: 2026), 1); // a different team
    });

    test('a team never played starts at Game 1', () async {
      await game(s, 'Eureka', 1);
      expect(s.nextGameNumberVs('Hawks', season: 2026), 1);
      expect(s.nextGameNumberVs('', season: 2026), 1);
    });

    test('three saved games -> Game 4', () async {
      await game(s, 'Hawks', 1);
      await game(s, 'Hawks', 2);
      await game(s, 'Hawks', 3);
      expect(s.nextGameNumberVs('Hawks', season: 2026), 4);
    });

    test('never reuses a number that is still taken after a game is deleted', () async {
      await game(s, 'Hawks', 1);
      await game(s, 'Hawks', 2);
      await game(s, 'Hawks', 3);
      // Delete every saved row of Game 2.
      while (true) {
        final i = s.pitches.indexWhere((p) => p.game == 'Hawks' && p.gameNumber == 2);
        if (i < 0) break;
        await s.deletePitchAt(i);
      }
      expect(s.savedGamesVs('Hawks', season: 2026).map((g) => g.gameNumber), [1, 3]);
      expect(s.nextGameNumberVs('Hawks', season: 2026), 4);
    });

    test('a New Game that was started but never used is not counted', () async {
      await game(s, 'Hawks', 1);
      s.setGame('Hawks', 2, 2026); // picked, nothing recorded
      expect(s.nextGameNumberVs('Hawks', season: 2026), 2);
    });

    test('seasons are numbered separately', () async {
      await game(s, 'Hawks', 1, season: 2025);
      await game(s, 'Hawks', 2, season: 2025);
      expect(s.nextGameNumberVs('Hawks', season: 2025), 3);
      expect(s.nextGameNumberVs('Hawks', season: 2026), 1);
    });

    test('previous teams are listed once each, and typed names reuse the saved spelling', () async {
      await game(s, 'Eureka', 1);
      await game(s, 'EUREKA ', 2);
      await game(s, 'Hawks', 1);
      expect(s.previousTeamsPlayed.length, 2);
      expect(s.canonicalTeamName('  eUrEkA '), 'EUREKA');
      expect(s.canonicalTeamName('Brand New'), 'Brand New');
    });

    test('the saved game number is still there after reopening the app', () async {
      await game(s, 'Eureka', 1);
      await game(s, 'Eureka', 2);
      final s2 = await _reopen(st);
      expect(s2.nextGameNumberVs('Eureka', season: 2026), 3);
      expect(s2.currentGameNumber, 2);
      expect(s2.currentOpponent, 'Eureka');
    });
  });
}
