import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/sequence_scoring.dart';

int _id = 0;
int _pa = 0;

/// One plate appearance from (type, call[, outcome]) tuples, batter #[jersey].
List<PitchEvent> pa(List<(String, String, String?)> pitches, {int jersey = 7}) {
  _pa++;
  var n = 0;
  return [
    for (final p in pitches)
      PitchEvent(
        id: '${_id++}',
        userId: 'u',
        game: 'Opp',
        gameNumber: 1,
        batter: _pa,
        batterNumber: jersey,
        battingOrder: 1,
        hand: 'R',
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
        paId: _pa,
      ),
  ];
}

PaScore one(List<(String, String, String?)> pitches) => SequenceScoring.scoreAll(pa(pitches)).single;
bool has(PaScore s, String code) => s.notes.any((n) => n.code == code);

void main() {
  test('weights sum to 100', () => expect(SeqWeights.total, 100));

  test('good sequence: FB take, CV whiff, CV whiff K scores high and repeat is NOT penalized', () {
    final s = one([('fb', 'sl', null), ('cv', 'ss', null), ('cv', 'ss', 'k')]);
    expect(s.score, closeTo(79.2, 0.2));
    expect(has(s, 'repeat_after_whiff'), isTrue);
    expect(has(s, 'change_after_take'), isTrue);
    expect(has(s, 'streak_ineffective'), isFalse);
    expect(s.components['matchup']!.evaluated, isFalse); // no history -> dropped, not zero
    expect(s.reducedConfidence, isTrue);
  });

  test('concerning sequence is flagged without claiming intent', () {
    final s = one([('fb', 'b', null), ('cv', 'b', null), ('cv', 'b', null)]);
    expect(s.completed, isFalse);
    expect(s.score, closeTo(50.0, 0.2));
    expect(has(s, 'ball_run'), isTrue);
    final txt = s.notes.firstWhere((n) => n.code == 'ball_run').text;
    expect(txt, contains("aren't tracked"));
    expect(s.components['result']!.evaluated, isFalse);
  });

  test('walk is low but result is only 15 of 100 nominal points', () {
    final s = one([('fb', 'b', null), ('cv', 'b', null), ('cv', 'b', null), ('cv', 'b', 'bb')]);
    expect(s.score, closeTo(33.9, 0.2));
    expect(s.components['result']!.value, 0.0);
  });

  test('a hit after sound decisions is not automatically bad; a lucky out does not rescue poor ones', () {
    final hit = one([('fb', 'sl', null), ('cv', 'ss', null), ('ch', 'ip', '1b')]);
    final lucky = one([
      ('fb', 'b', null), ('fb', 'b', null), ('fb', 'b', null), ('fb', 'b', null), ('fb', 'ip', 'go'),
    ]);
    expect(hit.score, closeTo(63.1, 0.2));
    expect(lucky.score, closeTo(44.1, 0.2));
    expect(hit.score! > lucky.score!, isTrue);
  });

  test('one-pitch at-bat is not scored (insufficient information)', () {
    final s = one([('fb', 'ip', 'go')]);
    expect(s.score, isNull);
    expect(s.unscoredReason, isNotNull);
  });

  test('component points sum to the score; same data -> same score', () {
    final data = pa([('fb', 'sl', null), ('cv', 'ss', null), ('cv', 'ss', 'k')]);
    final a = SequenceScoring.scoreAll(data).single;
    final b = SequenceScoring.scoreAll(data).single;
    expect(a.score, b.score);
    final sum = a.components.values.where((c) => c.evaluated).fold<double>(0, (x, c) => x + c.earned!);
    expect(sum, closeTo(a.score!, 1e-9));
  });

  test('two-strike ball is neutral for count management', () {
    final s = one([('fb', 'ss', null), ('cv', 'sl', null), ('cv', 'b', null), ('cv', 'ss', 'k')]);
    expect(s.components['count']!.value, isNotNull);
    expect(has(s, 'count_down'), isFalse);
  });

  test('a 1-for-2 history against a pitch is NOT treated as a weakness', () {
    final hist = [
      ...pa([('cv', 'ip', '1b')], jersey: 10),
      ...pa([('cv', 'ip', 'go')], jersey: 10),
    ];
    final target = pa([('cv', 'sl', null), ('cv', 'sl', null), ('cv', 'ip', 'go')], jersey: 10);
    final s = SequenceScoring.scoreAll([...hist, ...target]).last;
    expect(s.components['matchup']!.evaluated, isFalse);
    expect(has(s, 'limited_matchup'), isTrue);
    expect(has(s, 'baa_high'), isFalse);
  });

  test('history never includes the at-bat being scored or later ones', () {
    final first = pa([('cv', 'ss', null), ('cv', 'ss', null), ('cv', 'ss', 'k')], jersey: 9);
    final all = SequenceScoring.scoreAll(first);
    expect(all.single.components['matchup']!.evaluated, isFalse);
  });

  test('dead-ball rows are not pitches', () {
    final data = pa([('fb', 'b', null), ('fb', 'dk', 'dk')]);
    expect(SequenceScoring.scoreAll(data), isEmpty);
  });
}
