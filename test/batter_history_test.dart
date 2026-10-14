// Batter recognition within a game.
// Run with:  flutter test test/batter_history_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/batter_history_service.dart';

int _n = 0;
PitchEvent _p(int jersey, int seq, String call,
        {String? outcome, int game = 1, String team = 'Tigers', int season = 2026}) =>
    PitchEvent(
      id: '${_n++}',
      userId: 'u',
      game: team,
      gameNumber: game,
      batter: seq,
      batterNumber: jersey,
      battingOrder: 1,
      hand: 'R',
      eventType: 'pitch',
      pitchNum: 1,
      pitchType: 'fb',
      call: call,
      outcome: outcome,
      ab: 0,
      outs: 0,
      er: 0,
      xCoord: null,
      yCoord: null,
      battedType: null,
      inning: 1,
      paId: 1, // the app really does reuse one paId for the whole game
      season: season,
    );

BatterHistory _build(List<PitchEvent> ps, int jersey, {int game = 1}) =>
    BatterHistoryService.build(
        allPitches: ps, team: 'Tigers', jersey: jersey, gameNumber: game, season: 2026);

void main() {
  test('first PA of the game: not faced yet', () {
    final h = _build([_p(7, 0, 'b')], 7);
    expect(h.timesFaced, 0);
    expect(h.hasData, isFalse);
    expect(h.currentAtBat, isNotNull);
  });

  test('second PA: first one is the Last At-Bat, current one is not counted', () {
    final ps = [
      _p(7, 0, 'ss'), _p(7, 0, 'ip', outcome: 'go'), // PA 1 (done)
      _p(9, 1, 'ip', outcome: 'fo'), // someone else
      _p(7, 2, 'b'), // PA 2 in progress
    ];
    final h = _build(ps, 7);
    expect(h.timesFaced, 1);
    expect(h.currentPlateAppearance, 2);
    expect(h.lastAtBat!.finalOutcome, 'go');
    expect(h.previousSequences, isEmpty);
    expect(h.currentAtBat!.pitches.length, 1);
  });

  test('before the first pitch of the 2nd PA the prior PA is already found', () {
    final ps = [_p(7, 0, 'ip', outcome: 'go'), _p(9, 1, 'ip', outcome: 'fo')];
    expect(_build(ps, 7).hasData, isTrue);
  });

  test('third PA: Last = 2nd, Previous = only the 1st', () {
    final ps = [
      _p(7, 0, 'ip', outcome: 'go'),
      _p(7, 5, 'ss', outcome: 'k'),
      _p(7, 9, 'b'),
    ];
    final h = _build(ps, 7);
    expect(h.lastAtBat!.finalOutcome, 'k');
    expect(h.previousSequences.map((a) => a.finalOutcome), ['go']);
  });

  test('same jersey in a different game is never matched', () {
    final ps = [_p(7, 0, 'ip', outcome: 'go', game: 1), _p(7, 0, 'b', game: 2)];
    expect(_build(ps, 7, game: 2).timesFaced, 0);
  });

  test('jersey corrected mid at-bat does not split the PA', () {
    final ps = [_p(17, 0, 'b'), _p(7, 0, 'ip', outcome: 'go'), _p(7, 1, 'b')];
    final h = _build(ps, 7);
    expect(h.timesFaced, 1);
    expect(h.lastAtBat!.pitches.length, 2);
  });
}
