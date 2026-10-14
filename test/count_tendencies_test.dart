import 'package:flutter_test/flutter_test.dart';
import 'package:pitching_analytics/models/pitch_event.dart';
import 'package:pitching_analytics/services/stats_service.dart';

int _n = 0;
PitchEvent ev(int pa, int num, String type, String call, {String? outcome, String game = 'Opp'}) => PitchEvent(
      id: '${_n++}',
      userId: 'u',
      game: game,
      gameNumber: 1,
      batter: pa,
      batterNumber: pa,
      battingOrder: 1,
      hand: 'R',
      eventType: 'pitch',
      pitchNum: num,
      pitchType: type,
      call: call,
      outcome: outcome,
      ab: 0,
      outs: 0,
      er: 0,
      xCoord: null,
      yCoord: null,
      battedType: null,
      inning: 1,
      paId: pa,
    );

/// Four-pitch at-bat whose final pitch is thrown at 1-2: ball, called strike,
/// foul (count 1-2), then the deciding pitch.
List<PitchEvent> abAt12(int pa, String call, String outcome) => [
      ev(pa, 1, 'fb', 'b'),
      ev(pa, 2, 'fb', 'sl'),
      ev(pa, 3, 'fb', 'f'),
      ev(pa, 4, 'sl', call, outcome: outcome),
    ];

void main() {
  test('five at-bats ending at 1-2 with one hit give .200 for that count', () {
    final data = [
      ...abAt12(1, 'ip', '1b'),
      ...abAt12(2, 'ip', 'go'),
      ...abAt12(3, 'ip', 'fo'),
      ...abAt12(4, 'ip', 'lo'),
      ...abAt12(5, 'ss', 'k'),
    ];
    final h = StatsService.countHeatmap(data);
    final c = (h['countBaa'] as Map<String, Map<String, dynamic>>)['1-2']!;
    expect(c['ab'], 5);
    expect(c['hits'], 1);
    expect(c['baa'], 0.2);
    // The earlier pitches of those at-bats (0-0, 1-0, 1-1) got no result.
    final earlier = (h['countBaa'] as Map<String, Map<String, dynamic>>)['0-0']!;
    expect(earlier['ab'], 0);
    expect(earlier['baa'], isNull);
  });

  test('walks, hit-by-pitches and unfinished at-bats are not official at-bats', () {
    final data = [
      // Walk on a 3-0 count (final pitch thrown at 3-0).
      ev(1, 1, 'fb', 'b'), ev(1, 2, 'fb', 'b'), ev(1, 3, 'fb', 'b'), ev(1, 4, 'fb', 'b', outcome: 'bb'),
      // HBP at 0-0.
      ev(2, 1, 'fb', 'hbp', outcome: 'hbp'),
      // Unfinished at-bat: two pitches, no result yet.
      ev(3, 1, 'fb', 'b'), ev(3, 2, 'fb', 'sl'),
      // One real at-bat: a double at 0-0.
      ev(4, 1, 'fb', 'ip', outcome: '2b'),
    ];
    final cb = StatsService.countHeatmap(data)['countBaa'] as Map<String, Map<String, dynamic>>;
    expect(cb['3-0']!['ab'], 0);
    expect(cb['3-0']!['baa'], isNull); // blank, not 0
    expect(cb['0-0']!['ab'], 1); // only the double; the HBP and the open AB add nothing
    expect(cb['0-0']!['hits'], 1);
    expect(cb['0-0']!['baa'], 1.0);
    expect(cb['0-1']!['ab'], 0);
  });

  test('an at-bat is never counted twice, even with a stray extra result row', () {
    final data = [
      ev(1, 1, 'fb', 'ip', outcome: '1b'),
      ev(1, 2, 'fb', 'ip', outcome: 'go'), // bad data: second result in same PA
    ];
    final cb = StatsService.countHeatmap(data)['countBaa'] as Map<String, Map<String, dynamic>>;
    expect(cb['0-0']!['ab'], 1);
  });

  test('pitch counter = every pitch of that type, independent of at-bats', () {
    final data = [
      ...List.generate(25, (i) => ev(i + 1, 1, 'fb', 'b')), // 25 unfinished fastballs
      ev(100, 1, 'sl', 'ss'),
      ev(100, 2, 'sl', 'ip', outcome: 'go'),
    ];
    final rows = StatsService.pitchBreakdown(data);
    final fb = rows.firstWhere((r) => r['pitchType'] == 'fb');
    final sl = rows.firstWhere((r) => r['pitchType'] == 'sl');
    expect(fb['n'], 25);
    expect(fb['abN'], 0); // pitches, not at-bats
    expect(sl['n'], 2);
    expect(sl['abN'], 1);
    final overall = StatsService.pitchBreakdownOverall(data)!;
    expect(overall['n'], 27);
  });
}
