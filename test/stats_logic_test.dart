import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/stats_service.dart';

int _id = 0;
PitchEvent ev(int pa, int num, String type, String call, {String? outcome, String? batted, String eventType = 'pitch'}) =>
    PitchEvent(
      id: '${_id++}',
      userId: 'u',
      game: 'Opp',
      gameNumber: 1,
      batter: pa,
      batterNumber: pa,
      battingOrder: 1,
      hand: 'R',
      eventType: eventType,
      pitchNum: num,
      pitchType: type,
      call: call,
      outcome: outcome,
      ab: 0,
      outs: 0,
      er: 0,
      xCoord: null,
      yCoord: null,
      battedType: batted,
      inning: 1,
      paId: pa,
    );

void main() {
  // PA 1: fb ball, fb called strike, sl put in play for a single (1-1 count).
  // PA 2: fb put in play for a ground out at 0-0.
  // PA 3: fb ball, sl swinging, sl swinging, fb swinging -> strikeout on a fb.
  final data = [
    ev(1, 1, 'fb', 'b'),
    ev(1, 2, 'fb', 'sl'),
    ev(1, 3, 'sl', 'ip', outcome: '1b', batted: 'ld'),
    ev(2, 1, 'fb', 'ip', outcome: 'go', batted: 'gb'),
    ev(3, 1, 'fb', 'b'),
    ev(3, 2, 'sl', 'ss'),
    ev(3, 3, 'sl', 'ss'),
    ev(3, 4, 'fb', 'ss', outcome: 'k'),
  ];

  test('heat map BAA credits only the pitch that ended the at-bat', () {
    final cells = StatsService.countHeatmap(data)['cells'] as Map<String, Map<String, dynamic>>;
    // The single came on the slider at 1-1 — not on the earlier 0-0 / 1-0 fastballs.
    expect(cells['1-1|sl']!['baa'], 1.0);
    expect(cells['1-1|sl']!['hits'], 1);
    expect(cells['0-0|fb']!['hits'], 0);
    expect(cells['0-0|fb']!['ab'], 1); // the ground out at 0-0
    expect(cells['0-0|fb']!['baa'], 0.0);
    // Strikeout on a fastball at 2-2: an at-bat with no hit.
    expect(cells['1-2|fb']!['ab'], 1);
    // A cell where no at-bat ended is blank, not 0.
    expect(cells['1-0|fb']!['baa'], isNull);
  });

  test('pitch breakdown puts each pitch and result in its own bucket', () {
    final rows = StatsService.pitchBreakdown(data);
    final fb = rows.firstWhere((r) => r['pitchType'] == 'fb');
    final sl = rows.firstWhere((r) => r['pitchType'] == 'sl');
    expect(fb['n'], 5);
    expect(sl['n'], 3);
    // BAA: the single belongs to the slider, the out and the K to fastballs.
    expect(sl['avgAgainst'], 1.0);
    expect(fb['avgAgainst'], 0.0);
    expect(fb['kPct'], 50.0); // 1 K out of the 2 PAs that ended on a fastball
    expect(sl['kPct'], 0.0);
    expect(sl['whiffPct'], closeTo(66.7, 0.1)); // 2 whiffs of 3 swings
  });

  test('sequencing ignores unfinished plate appearances', () {
    final withOpen = [
      ...data,
      ev(4, 1, 'fb', 'b'),
      ev(4, 2, 'fb', 'b'),
      ev(4, 3, 'fb', 'b'), // still in progress: no outcome yet
    ];
    final seqs = StatsService.pitchSequencing(withOpen);
    expect(seqs.any((s) => s['seq'] == 'FB→FB→FB'), isFalse);
    final s = seqs.firstWhere((s) => s['seq'] == 'FB→FB→SL');
    expect(s['count'], 1);
    expect(s['outPct'], 0.0); // a single is not an out
    expect(s['lowSample'], true);
  });

  test('progress bar red end: lower-is-better stats are red on the right', () {
    expect(statLowerIsBetter('ERA'), isTrue);
    expect(statLowerIsBetter('K_pct'), isFalse);
  });
}
