import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/opponent_plan_service.dart';

int _n = 0;
PitchEvent ev({
  required int seq,
  required int jersey,
  required int num,
  required String type,
  required String call,
  String? outcome,
  int outs = 0,
  int gameNumber = 1,
  int season = 2026,
  int order = 1,
  String eventType = 'pitch',
}) =>
    PitchEvent(
      id: 'e${_n++}',
      userId: 'u',
      game: 'Opp',
      gameNumber: gameNumber,
      batter: seq,
      batterNumber: jersey,
      battingOrder: order,
      hand: 'R',
      eventType: eventType,
      pitchNum: num,
      pitchType: type,
      call: call,
      outcome: outcome,
      ab: 0,
      outs: outs,
      er: 0,
      xCoord: null,
      yCoord: null,
      battedType: null,
      inning: 1,
      paId: seq,
      season: season,
    );

void main() {
  test('an at-bat result is credited to its final pitch only', () {
    final data = [
      ev(seq: 1, jersey: 7, num: 1, type: 'fb', call: 'b'),
      ev(seq: 1, jersey: 7, num: 2, type: 'fb', call: 'f'),
      ev(seq: 1, jersey: 7, num: 3, type: 'cv', call: 'ss', outcome: 'k'),
    ];
    final plan = OpponentPlan.compute(data);
    final fb = plan.teamPitchLines.firstWhere((l) => l.type == 'fb');
    final cv = plan.teamPitchLines.firstWhere((l) => l.type == 'cv');
    expect(cv.kEnded, 1);
    expect(fb.kEnded, 0);
    expect(fb.abEnded, 0);
    expect(plan.teamLine.pa, 1);
  });

  test('pitch counts are tracked per pitch (0-0, 1-0, 1-1)', () {
    final data = [
      ev(seq: 1, jersey: 7, num: 1, type: 'fb', call: 'b'),
      ev(seq: 1, jersey: 7, num: 2, type: 'fb', call: 'sl'),
      ev(seq: 1, jersey: 7, num: 3, type: 'fb', call: 'ip', outcome: 'go'),
    ];
    final steps = OpponentPlan.buildPas(data).single.steps;
    expect(steps.map((s) => s.count).toList(), ['0-0', '1-0', '1-1']);
  });

  test('two seasons that reuse a game number are not merged', () {
    final data = [
      ev(seq: 1, jersey: 7, num: 1, type: 'fb', call: 'ip', outcome: '1b', season: 2025),
      ev(seq: 1, jersey: 7, num: 1, type: 'fb', call: 'ip', outcome: 'go', season: 2026),
    ];
    expect(OpponentPlan.buildPas(data).length, 2);
  });

  test('one at-bat gives no takeaway and no confident tendency', () {
    final data = [ev(seq: 1, jersey: 7, num: 1, type: 'fb', call: 'ip', outcome: '1b')];
    final plan = OpponentPlan.compute(data);
    expect(plan.takeaways, isEmpty);
    final h = plan.hitters.single;
    expect(h.hasSupportedTendency, isFalse);
    expect(h.line.pa, 1);
    expect(h.line.confidence, Confidence.insufficient);
  });

  test('a repeated swing-and-miss pattern produces a labeled takeaway', () {
    final data = <PitchEvent>[];
    for (var i = 1; i <= 5; i++) {
      data.add(ev(seq: i, jersey: 7, num: 1, type: 'cv', call: 'ss'));
      data.add(ev(seq: i, jersey: 7, num: 2, type: 'fb', call: 'ip', outcome: 'go'));
    }
    final plan = OpponentPlan.compute(data);
    final t = plan.takeaways.firstWhere((t) => t.title.contains('#7'));
    expect(t.concern, isFalse);
    expect(t.confidence, Confidence.low); // 5 swings is a small sample
  });

  test('out count before a plate appearance is read from the previous PA', () {
    final data = [
      ev(seq: 1, jersey: 1, num: 1, type: 'fb', call: 'ss', outcome: 'k', outs: 1),
      ev(seq: 2, jersey: 2, num: 1, type: 'fb', call: 'ss', outcome: 'k', outs: 2),
      ev(seq: 3, jersey: 3, num: 1, type: 'fb', call: 'ip', outcome: '1b', outs: 2),
    ];
    final pas = OpponentPlan.buildPas(data);
    expect(pas.map((p) => p.outsBefore).toList(), [0, 1, 2]);
    final plan = OpponentPlan.compute(data);
    expect(plan.situational.twoOuts.pa, 1);
  });

  test('a game with no out data leaves the out count unknown', () {
    final data = [
      ev(seq: 1, jersey: 1, num: 1, type: 'fb', call: 'ip', outcome: '1b'),
      ev(seq: 2, jersey: 2, num: 1, type: 'fb', call: 'ip', outcome: 'go'),
    ];
    final pas = OpponentPlan.buildPas(data);
    expect(pas.every((p) => p.outsBefore == -1), isTrue);
    expect(OpponentPlan.compute(data).situational.twoOutsKnownPas, 0);
  });

  test('base-runner situations are reported as not tracked', () {
    final data = [ev(seq: 1, jersey: 7, num: 1, type: 'fb', call: 'ip', outcome: '1b')];
    expect(OpponentPlan.compute(data).situational.basesTracked, isFalse);
  });

  test('lineup segments only appear when the batting order is recorded', () {
    final unknown = [
      ev(seq: 1, jersey: 1, num: 1, type: 'fb', call: 'ip', outcome: '1b'),
      ev(seq: 2, jersey: 2, num: 1, type: 'fb', call: 'ip', outcome: 'go'),
    ];
    expect(OpponentPlan.compute(unknown).orderKnown, isFalse);
    final known = [
      ev(seq: 1, jersey: 1, num: 1, type: 'fb', call: 'ip', outcome: '1b', order: 1),
      ev(seq: 2, jersey: 2, num: 1, type: 'fb', call: 'ip', outcome: 'go', order: 5),
    ];
    final plan = OpponentPlan.compute(known);
    expect(plan.orderKnown, isTrue);
    expect(plan.segments.length, 2);
  });

  test('an unfinished at-bat is shown but not counted as a plate appearance', () {
    final data = [
      ev(seq: 1, jersey: 7, num: 1, type: 'fb', call: 'b'),
      ev(seq: 1, jersey: 7, num: 2, type: 'fb', call: 'sl'),
    ];
    final plan = OpponentPlan.compute(data);
    expect(plan.pas.length, 1);
    expect(plan.incompletePas, 1);
    expect(plan.teamLine.pa, 0);
  });
}
