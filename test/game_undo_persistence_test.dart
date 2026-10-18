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
}
