import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/scouting_game_plan.dart';

int _id = 0;
int _seq = 0;

/// One plate appearance. [outsBefore]/[inning] feed the situational logic;
/// the final pitch carries outs AFTER the event, like the real data.
List<PitchEvent> pa(
  List<(String, String, String?)> pitches, {
  int? jersey = 7,
  int order = 3,
  int inning = 1,
  int outsBefore = 0,
  int game = 1,
  String hand = 'R',
}) {
  _seq++;
  var n = 0;
  return [
    for (final p in pitches)
      PitchEvent(
        id: '${_id++}',
        userId: 'u',
        game: 'Opp',
        gameNumber: game,
        batter: _seq,
        batterNumber: jersey,
        battingOrder: order,
        hand: hand,
        eventType: 'pitch',
        pitchNum: ++n,
        pitchType: p.$1,
        call: p.$2,
        outcome: p.$3,
        ab: (p.$3 != null && p.$3 != 'bb' && p.$3 != 'hbp') ? 1 : 0,
        outs: (p.$3 != null && const {'go', 'fo', 'lo', 'k', 'kl'}.contains(p.$3)) ? outsBefore + 1 : outsBefore,
        er: 0,
        xCoord: null,
        yCoord: null,
        battedType: null,
        inning: inning,
        paId: _seq,
      ),
  ];
}

ScoutingGamePlan build(List<PitchEvent> d) => ScoutingGamePlanBuilder.build('Opp', d);
HitterReport hitter(ScoutingGamePlan p, int j) => p.hitters.firstWhere((h) => h.jersey == j);

void main() {
  final pa1 = [('fb', 'b', null), ('fb', 'sl', null), ('cv', 'ip', '1b')];
  final pa2 = [('fb', 'ss', null), ('fb', 'f', null), ('cv', 'ss', 'k')];

  test('hitter totals and credit only the pitch that ENDED the at-bat', () {
    final p = build([...pa(pa1), ...pa(pa2)]);
    final h = hitter(p, 7);
    expect([h.pa, h.ab, h.hits, h.ks], [2, 2, 1, 1]);
    final fb = h.byType.firstWhere((t) => t.type == 'fb');
    final cv = h.byType.firstWhere((t) => t.type == 'cv');
    expect([fb.pitches, fb.ab, fb.hits, fb.ks], [4, 0, 0, 0]); // earlier pitches get no result
    expect([cv.pitches, cv.ab, cv.hits, cv.ks], [2, 2, 1, 1]);
    expect([cv.swings, cv.whiffs], [2, 1]);
  });

  test('incomplete and unknown-jersey plate appearances are handled, not invented', () {
    final p = build([
      ...pa(pa1),
      ...pa([('fb', 'b', null), ('fb', 'b', null)]), // unfinished
      ...pa([('fb', 'sl', null), ('fb', 'ss', null), ('cv', 'ss', 'k')], jersey: null),
    ]);
    expect(p.incompletePa, 1);
    expect(p.unknownJerseyPa, 1);
    expect(p.hitters.map((h) => h.jersey), [7]);
    expect(hitter(p, 7).pa, 1);
  });

  test('base runners are reported as unavailable; leadoff and two-out come from recorded data', () {
    final d = [
      ...pa([('fb', 'ip', 'go')], inning: 1, outsBefore: 0), // leadoff, ends with 1 out
      ...pa([('fb', 'ip', 'go')], inning: 1, outsBefore: 1, jersey: 8), // 2 outs now
      ...pa([('fb', 'ip', 'go')], inning: 1, outsBefore: 2, jersey: 9), // came up with two outs
      ...pa([('fb', 'ip', '1b')], inning: 2, outsBefore: 0, jersey: 1), // new inning -> leadoff
    ];
    final p = build(d);
    SituationLine s(String l) => p.situations.firstWhere((x) => x.label.startsWith(l));
    expect(s('Runners on base').available, isFalse);
    expect(s('Runners in scoring').available, isFalse);
    expect(s('Leadoff').pa, 2);
    expect(s('Two outs').pa, 1);
    expect(s('Zero or one out').pa, 3);
  });

  test('a tiny sample is never called a weakness; larger samples are labelled correctly', () {
    // 2 swings, 2 whiffs on the curveball: too small
    final small = build(pa([('cv', 'ss', null), ('cv', 'ss', null), ('cv', 'ss', 'k')]));
    expect(hitter(small, 7).notes.any((n) => n.label == 'Potential weakness'), isFalse);

    // 6 swings, 4 whiffs: observed fact with low confidence, not a tendency
    final mid = <PitchEvent>[];
    for (var i = 0; i < 2; i++) {
      mid.addAll(pa([('cv', 'ss', null), ('cv', 'ss', null), ('cv', 'f', null), ('cv', 'ip', 'go')]));
    }
    final w = hitter(build(mid), 7).notes.firstWhere((n) => n.label == 'Potential weakness');
    expect(w.tag, 'Observed fact');
    expect(w.conf, Conf.low);

    // 12 swings, 8 whiffs: supported tendency
    final big = <PitchEvent>[];
    for (var i = 0; i < 4; i++) {
      big.addAll(pa([('cv', 'ss', null), ('cv', 'ss', null), ('cv', 'f', null), ('cv', 'ip', 'go')]));
    }
    final w2 = hitter(build(big), 7).notes.firstWhere((n) => n.label == 'Potential weakness');
    expect(w2.tag, 'Supported tendency');
  });

  test('0-for-2 against a pitch is reported as a small-sample fact, not a weakness', () {
    final d = [
      ...pa([('fb', 'sl', null), ('cv', 'ip', 'go')]),
      ...pa([('fb', 'sl', null), ('cv', 'ip', 'fo')]),
    ];
    final h = hitter(build(d), 7);
    expect(h.notes.any((n) => n.label == 'Potential weakness'), isFalse);
    expect(h.notes.any((n) => n.text.contains('Too small to call a weakness')), isTrue);
  });

  test('no takeaways are invented from a tiny data set', () {
    expect(build(pa(pa1)).takeaways, isEmpty);
  });

  test('a hitter who went 3-for-6 produces a concern with the evidence, as a fact', () {
    final d = <PitchEvent>[];
    for (final r in ['1b', '1b', '2b', 'go', 'fo', 'lo']) {
      d.addAll(pa([('fb', 'sl', null), ('fb', 'ip', r)]));
    }
    final p = build(d);
    final t = p.takeaways.firstWhere((x) => x.kind == 'concern');
    expect(t.fact, contains('3-for-6'));
    expect(t.tendency, isNull); // 6 AB is below the "good sample" size
    expect(t.conf, Conf.low);
  });

  test('lineup groups only appear when batting order is recorded', () {
    final withOrder = build([...pa(pa1, order: 1), ...pa(pa2, jersey: 9, order: 5)]);
    expect(withOrder.lineupOrderKnown, isTrue);
    expect(withOrder.lineupGroups.length, 3);
    final noOrder = build([...pa(pa1, order: 0)]);
    expect(noOrder.lineupOrderKnown, isFalse);
    expect(noOrder.lineupGroups, isEmpty);
  });

  test('at-bats are chronological with per-pitch counts kept separate from the result', () {
    final p = build([...pa(pa1), ...pa(pa2)]);
    expect(p.atBats.length, 2);
    expect(p.atBats.first.outcome, '1b');
    expect(p.atBats.first.pitches.map((x) => x.count).toList(), ['0-0', '1-0', '1-1']);
    expect(p.atBats.first.pitches.map((x) => x.call).toList(), ['b', 'sl', 'ip']);
    expect(p.atBats[1].outcome, 'k');
  });
}
