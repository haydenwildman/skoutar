import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/sequence_analytics.dart';
import 'package:pitching_analytics/services/sequence_scoring.dart';

int _id = 0;
int _seq = 0;
final _t0 = DateTime(2026, 4, 1, 12);

/// One plate appearance from (type, call[, outcome]) tuples. [tsOffset] lets a
/// test give rows timestamps that do NOT match the order they were thrown.
List<PitchEvent> pa(
  List<(String, String, String?)> pitches, {
  int game = 1,
  String hand = 'R',
  List<int>? tsOffset,
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
        batterNumber: 7,
        battingOrder: 1,
        hand: hand,
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
        paId: _seq,
        season: 2026,
        timestamp: _t0.add(Duration(seconds: _seq * 100 + (tsOffset?[n - 1] ?? n))),
      ),
  ];
}

void main() {
  test('Wilson lower bound: same out rate, bigger sample ranks higher; n=0 is null', () {
    final small = wilsonLower(3, 4)!; // 75% of 4
    final big = wilsonLower(30, 40)!; // 75% of 40
    expect(big, greaterThan(small));
    expect(wilsonLower(0, 0), isNull);
    expect(wilsonLower(10, 10)!, lessThan(1.0));
    expect(wilsonUpper(0, 10)!, greaterThan(0.0));
  });

  test('plate appearances are rebuilt even when rows are shuffled', () {
    final a = pa([('fb', 'sl', null), ('cv', 'ss', null), ('cv', 'ss', 'k')]);
    final b = pa([('fb', 'b', null), ('ch', 'ss', null), ('fb', 'ip', 'go')]);
    final shuffled = [a[2], b[1], a[0], b[2], a[1], b[0]]; // interleaved, out of order
    final pas = SequenceScoring.splitPlateAppearances(shuffled);
    expect(pas.length, 2);
    expect(pas.map((p) => p.length).toList(), [3, 3]);
    expect(pas[0].map((p) => p.pitchNum).toList(), [1, 2, 3]);
  });

  test('a row inserted later (newer timestamp) still lands in its own at-bat in pitch order', () {
    // Pitch 2 of the at-bat was added afterwards with Insert Row, so it reloads
    // with the newest timestamp and comes back AFTER the final pitch.
    final rows = pa(
      [('fb', 'sl', null), ('cv', 'ss', null), ('cv', 'ss', 'k')],
      tsOffset: [1, 900, 3],
    );
    final loaded = [...rows]..sort((x, y) => x.timestamp.compareTo(y.timestamp));
    expect(loaded.map((p) => p.pitchNum).toList(), [1, 3, 2]); // reload order is wrong
    final pas = SequenceScoring.splitPlateAppearances(loaded);
    expect(pas.length, 1);
    expect(pas.single.map((p) => p.pitchNum).toList(), [1, 2, 3]);
    final a = SequenceAnalytics.build(loaded);
    expect(a.diagnostics.pasWith3Plus, 1);
    expect(a.openingThree.single.label, 'FB→CV→CV');
  });

  test('dropped third strike counts as a strikeout but not as an out by itself', () {
    final rows = pa([('fb', 'sl', null), ('cv', 'ss', null), ('cv', 'ss', 'dk3')]);
    final a = SequenceAnalytics.build(rows);
    final r = a.openingThree.single;
    expect(r.pa.k, 1);
    expect(r.pa.outs, 0);
    expect(SequenceScoring.scoreAll(rows).single.score, isNotNull);
  });

  test('2-pitch metrics are available when there are no 3-pitch at-bats', () {
    final rows = [
      ...pa([('fb', 'ss', null), ('ch', 'ip', 'go')]),
      ...pa([('fb', 'b', null), ('ch', 'ip', '1b')]),
      ...pa([('fb', 'sl', null), ('sl', 'ss', null)]), // unfinished
    ];
    final a = SequenceAnalytics.build(rows);
    expect(a.diagnostics.pasWith3Plus, 0);
    expect(a.hasOpeningThree, isFalse);
    expect(a.hasOpeningTwo, isTrue);
    expect(a.openingTwo.single.label, 'FB→CH');
    expect(a.openingTwo.single.n, 2);
    expect(a.openingTwo.single.pa.hits, 1);
    expect(a.openingTwo.single.pa.outs, 1);
    expect(a.hasTransitions, isTrue);
    expect(a.hasCounts, isTrue);
  });

  test('transition and after-pitch statistics are plain ratios with sample sizes', () {
    final rows = [
      ...pa([('fb', 'sl', null), ('ch', 'ss', null), ('ch', 'f', null), ('fb', 'ip', 'fo')]),
      ...pa([('fb', 'sl', null), ('ch', 'b', null), ('fb', 'ss', null), ('ch', 'ss', 'k')]),
    ];
    final a = SequenceAnalytics.build(rows);
    final fbCh = a.transitions.firstWhere((t) => t.from == 'fb' && t.to == 'ch');
    expect(fbCh.n, 3);
    expect(fbCh.results.swinging, 2);
    expect(fbCh.results.balls, 1);
    expect(fbCh.results.strikePct, closeTo(200 / 3, 0.001));
    final afterFb = a.afterPitch.firstWhere((r) => r.prevType == 'fb');
    expect(afterFb.next.n, 3); // three fb→ch pairs
    expect(afterFb.nextTypes['ch'], 3);
    expect(afterFb.next.whiffPct, closeTo(100, 0.001)); // 2 swings, both swinging strikes
  });

  test('count table credits each pitch to the count it was thrown in', () {
    final rows = pa([('fb', 'b', null), ('fb', 'ss', null), ('ch', 'f', null), ('ch', 'ip', 'go')]);
    final a = SequenceAnalytics.build(rows);
    final labels = a.counts.map((c) => c.label).toList();
    expect(labels, ['0-0', '1-0', '1-1', '1-2']);
    final last = a.counts.last;
    expect(last.pitches.n, 1);
    expect(last.paEnd.pas, 1);
    expect(last.paEnd.outs, 1);
  });

  test('pitch mix is grouped by count situation, each pitch in the count it was thrown in', () {
    // counts before each pitch: 0-0, 1-0, 1-1, 1-2
    final rows = pa([('fb', 'b', null), ('fb', 'ss', null), ('ch', 'f', null), ('ch', 'ip', 'go')]);
    final a = SequenceAnalytics.build(rows);
    final labels = a.situations.map((r) => r.label).toList();
    expect(labels.first, 'First pitch (0-0)');
    MixRow g(String start) => a.situations.firstWhere((r) => r.label.startsWith(start));
    expect(g('First pitch').mix, {'fb': 1});
    expect(g('Behind').mix, {'fb': 1}); // 1-0
    expect(g('Even').mix, {'ch': 1}); // 1-1
    expect(g('Ahead').mix, {'ch': 1}); // 1-2
    expect(g('Two strikes').mix, {'ch': 1}); // 1-2 is also a two-strike count
    expect(g('Two strikes').paEnd.outs, 1); // the at-bat ended on that pitch
    expect(a.counts.last.mix, {'ch': 1});
    expect(g('Ahead').shares.single.$2, closeTo(1.0, 1e-9));
  });

  test('batter hand split only appears when both hands have pitches', () {
    final rOnly = SequenceAnalytics.build(pa([('fb', 'ss', null), ('ch', 'ip', 'go')]));
    expect(rOnly.byHand.length, 1);
    expect(rOnly.hasHandSplit, isFalse);

    final both = SequenceAnalytics.build([
      ...pa([('fb', 'ss', null), ('ch', 'ip', 'go')]),
      ...pa([('fb', 'b', null), ('cv', 'ss', 'k')], hand: 'L'),
    ]);
    expect(both.hasHandSplit, isTrue);
    expect(both.byHand.map((r) => r.label).toList(),
        ['Right-handed batters', 'Left-handed batters']);
    expect(both.byHand.last.n, 2);
    expect(both.byHand.last.paEnd.k, 1);
    expect(both.byHand.first.paEnd.outs, 1);
  });

  test('rows that share one timestamp (bulk add/import) still rebuild whole at-bats', () {
    final rows = pa(
      [('fb', 'sl', null), ('cv', 'ss', null), ('ch', 'sl', null), ('cv', 'ss', 'k')],
      tsOffset: [5, 5, 5, 5],
    );
    // Same timestamp: a database ordering by id can return them in any order.
    final loaded = [rows[2], rows[0], rows[3], rows[1]];
    final pas = SequenceScoring.splitPlateAppearances(loaded);
    expect(pas.length, 1);
    expect(pas.single.map((p) => p.pitchNum).toList(), [1, 2, 3, 4]);
    expect(SequenceAnalytics.build(loaded).diagnostics.pasWith3Plus, 1);
  });

  test('empty input gives empty sections, not an exception', () {
    final a = SequenceAnalytics.build(const []);
    expect(a.diagnostics.pitchRows, 0);
    expect(a.hasTransitions || a.hasCounts || a.hasOpeningTwo || a.hasOpeningThree, isFalse);
  });
}
