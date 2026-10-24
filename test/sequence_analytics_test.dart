import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/sequence_analytics.dart';
import 'package:pitching_analytics/services/sequence_scoring.dart';
import 'package:pitching_analytics/services/stats_service.dart';
import 'package:pitching_analytics/theme/app_theme.dart';

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
    expect(a.openingByLength[3]!.single.label, 'FB→CV→CV');
  });

  test('dropped third strike counts as a strikeout but not as an out by itself', () {
    final rows = pa([('fb', 'sl', null), ('cv', 'ss', null), ('cv', 'ss', 'dk3')]);
    final a = SequenceAnalytics.build(rows);
    final r = a.openingByLength[3]!.single;
    expect(r.pa.k, 1);
    expect(r.pa.outs, 0);
    expect(SequenceScoring.scoreAll(rows).single.score, isNotNull);
  });

  test('2-pitch at-bats offer no sequence length, but counts and transitions still work', () {
    final rows = [
      ...pa([('fb', 'ss', null), ('ch', 'ip', 'go')]),
      ...pa([('fb', 'b', null), ('ch', 'ip', '1b')]),
      ...pa([('fb', 'sl', null), ('sl', 'ss', null)]), // unfinished
    ];
    final a = SequenceAnalytics.build(rows);
    expect(a.diagnostics.pasWith3Plus, 0);
    expect(a.diagnostics.longestFinishedPa, 2);
    expect(a.sequenceLengths, isEmpty);
    expect(a.hasOpeningSequences, isFalse);
    expect(a.hasTransitions, isTrue);
    expect(a.hasCounts, isTrue);
  });

  test('sequence lengths come from the data: 3 up to the longest finished at-bat, never beyond', () {
    final threeOnly = SequenceAnalytics.build([
      ...pa([('fb', 'sl', null), ('cv', 'ss', null), ('ch', 'ip', 'go')]),
    ]);
    expect(threeOnly.sequenceLengths, [3]);

    final five = SequenceAnalytics.build([
      ...pa([('fb', 'sl', null), ('cv', 'ss', null), ('ch', 'ip', 'go')]),
      ...pa([('fb', 'b', null), ('fb', 'b', null), ('cv', 'f', null), ('cv', 'f', null), ('ch', 'ss', 'k')]),
    ]);
    expect(five.sequenceLengths, [3, 4, 5]);
    expect(five.openingByLength.containsKey(6), isFalse);
    // Only the 5-pitch at-bat can make 4- and 5-pitch sequences.
    expect(five.openingByLength[4]!.single.label, 'FB→FB→CV→CV');
    expect(five.openingByLength[4]!.single.n, 1);
    expect(five.openingByLength[5]!.single.label, 'FB→FB→CV→CV→CH');
    // Two different 3-pitch openers occurred; nothing else is listed.
    expect(five.openingByLength[3]!.map((r) => r.label).toSet(), {'FB→CV→CH', 'FB→FB→CV'});
  });

  test('a longer at-bat in one game does not create a length for a game without one', () {
    final long = pa([('fb', 'b', null), ('fb', 'b', null), ('cv', 'f', null), ('cv', 'f', null), ('ch', 'ss', 'k')]);
    final short = pa([('fb', 'sl', null), ('cv', 'ss', null), ('ch', 'ip', 'go')], game: 2);
    expect(SequenceAnalytics.build([...long, ...short]).sequenceLengths, [3, 4, 5]);
    final onlyGame2 = [...long, ...short].where((p) => p.gameNumber == 2).toList();
    expect(SequenceAnalytics.build(onlyGame2).sequenceLengths, [3]);
  });

  test('identical sequences are grouped; at-bats never run into each other; unfinished at-bats are ignored', () {
    final rows = [
      ...pa([('fb', 'sl', null), ('cv', 'ss', null), ('ch', 'ip', 'go')]),
      ...pa([('fb', 'sl', null), ('cv', 'b', null), ('ch', 'ip', '1b')]),
      ...pa([('fb', 'b', null), ('cv', 'b', null)]), // unfinished, 2 pitches
    ];
    final a = SequenceAnalytics.build(rows);
    final r = a.openingByLength[3]!.single; // both finished at-bats share FB→CV→CH
    expect(r.label, 'FB→CV→CH');
    expect(r.n, 2);
    expect(r.pa.outs, 1);
    expect(r.pa.hits, 1);
    expect(r.pa.ab, 2);
    expect(r.pa.baa, closeTo(0.5, 1e-9));
    // strikes among the 6 opening pitches: sl, ss, ip, sl, (b), ip = 5
    expect(r.strikePct, closeTo(5 / 6 * 100, 1e-9));
    // The 2-pitch unfinished at-bat plus the next at-bat's pitches never join into a 3-pitch sequence.
    expect(a.openingByLength.length, 1);
  });

  test('walk and no-official-at-bat results use correct denominators and never show 0 for missing', () {
    final rows = pa([('fb', 'b', null), ('cv', 'b', null), ('ch', 'b', null), ('fb', 'b', 'bb')]);
    final r = SequenceAnalytics.build(rows).openingByLength[3]!.single;
    expect(r.pa.pas, 1);
    expect(r.pa.ab, 0);
    expect(r.pa.baa, isNull); // no official at-bat: not 0.000
    expect(r.pa.bbPct, closeTo(100, 1e-9));
    expect(r.pa.outPct, closeTo(0, 1e-9));
  });

  test('out_pct scale: higher is better, with a gray no-data color', () {
    expect(statLowerIsBetter('out_pct'), isFalse);
    expect(perfHex('out_pct', 80), AppColors.perfExcellent);
    expect(perfHex('out_pct', 70), AppColors.perfGood);
    expect(perfHex('out_pct', 65), AppColors.perfAverage);
    expect(perfHex('out_pct', 60), AppColors.perfBelowAvg);
    expect(perfHex('out_pct', 40), AppColors.perfPoor);
    expect(perfHex('out_pct', null), const Color(0xFFE5E7EB));
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
    expect(a.hasTransitions || a.hasCounts || a.hasOpeningSequences, isFalse);
  });
}
