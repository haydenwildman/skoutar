import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../utils/responsive.dart';
import '../widgets/stat_vbox.dart';
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import '../widgets/year_filter_dropdown.dart';
import '../widgets/sequence_breakdown.dart';
import '../services/sequence_scoring.dart';

const String _seqScoreWhat =
    'Score (0-100) rates the pitch-calling DECISIONS in the at-bats that opened this way (average of each at-bat\'s score), using only logged data - no velocity or location.\n'
    'Count management 30 + Batter matchup 25 + Setup & response 20 + Predictability 10 + Result 15. '
    'Missing data is dropped and the other weights re-scaled, never counted as bad. Small samples are pulled toward neutral. '
    'A hit or walk does not by itself make a sequence bad, and repeating a pitch is only penalized when the data shows it was not working.';

String _seqCardGuide() => [
      swatchLine(AppColors.colSuccess,
          'Green card: listed under Best Sequences - the 5 sequences with the highest Score.'),
      swatchLine(AppColors.colError,
          'Red card: listed under Sequences to Avoid - the lowest Scores among sequences seen at least 3 times.'),
      'The card color shows which list the sequence is in, not a fixed cutoff; the Score pill has its own cutoffs (press and hold it).',
    ].join('\n');

class PitchSequencingScreen extends StatefulWidget {
  const PitchSequencingScreen({super.key});

  @override
  State<PitchSequencingScreen> createState() => _PitchSequencingScreenState();
}

class _PitchSequencingScreenState extends State<PitchSequencingScreen> {
  String _team = 'All';
  String _gameNum = 'All';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    var data = session.filteredPitches;
    if (_team != 'All') data = data.where((p) => p.game == _team).toList();
    if (_gameNum != 'All') {
      final gn = int.tryParse(_gameNum);
      data = data.where((p) => p.gameNumber == gn).toList();
    }
    final seqs = StatsService.pitchSequencing(data, history: session.filteredPitches);
    final atBats = StatsService.sequencingByAtBat(data, history: session.filteredPitches);
    final putAway = StatsService.putAwayPitch(data);
    final firstPitchStrike = StatsService.firstPitchStrikeByType(data);
    final teams = ['All', ...session.knownTeams];
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == 'All' || p.game == _team)
          .map((p) => p.gameNumber.toString())
          .toSet()
    ];
    final pitchTypesUsed = {
      for (final p in data) if (p.pitchType != null) p.pitchType!
    }.toList()
      ..sort();

    final filterRow = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filter', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _team,
                    decoration: const InputDecoration(labelText: 'Team'),
                    items: teams.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() {
                      _team = v!;
                      _gameNum = 'All';
                    }),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _gameNum,
                    decoration: const InputDecoration(labelText: 'Game #'),
                    items: gameNums.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _gameNum = v!),
                  ),
                ),
                const YearFilterDropdown(),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 6, children: [
              StatHoldInfo(
                title: 'Favorable sequence',
                description: composeHoldInfo(
                  what: 'Green marks sequences in the Best Sequences list: the 5 highest Sequence Scores, scored on count management, batter matchup, setup and response, predictability and result.',
                  colorGuide: _seqCardGuide(),
                ),
                child: const LegendChip(label: 'Best sequences (highest Score)', color: AppColors.colSuccess),
              ),
              StatHoldInfo(
                title: 'Sequence to avoid',
                description: composeHoldInfo(
                  what: 'Red marks sequences in the Sequences to Avoid list: the lowest Sequence Scores among sequences seen at least 3 times.',
                  colorGuide: _seqCardGuide(),
                ),
                child: const LegendChip(label: 'Sequence to avoid', color: AppColors.colError),
              ),
              if (pitchTypesUsed.isNotEmpty) ...[
                const SizedBox(width: 4),
                const Text('Pitch colors:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                for (final pt in pitchTypesUsed)
                  StatHoldInfo(
                    title: pt.toUpperCase(),
                    description: composeHoldInfo(
                      what: 'Pitch colors are used by the Put-Away and First-Pitch Strike bars and the Count Tendencies labels below.',
                      colorGuide: pitchTypeColorGuide(pitchTypesUsed),
                    ),
                    child: LegendChip(label: pt.toUpperCase(), color: AppColors.pitchColor(pt)),
                  ),
              ],
            ]),
          ],
        ),
      ),
    );

    if (seqs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterRow,
          const GlowCard(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Not enough data yet (need 3-pitch sequences).',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      );
    }

    final best = List<Map<String, dynamic>>.from(seqs)
      ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final worst = seqs.where((s) => (s['count'] as int) >= 3).toList()
      ..sort((a, b) => (a['score'] as double).compareTo(b['score'] as double));
    final heatmap = StatsService.countHeatmap(data);

    Widget seqCard(Map<String, dynamic> s, bool good) => StatHoldInfo(
        title: 'Sequence ${s['seq']}',
        description: composeHoldInfo(
          what: 'The first three pitch types of a finished plate appearance, in the order thrown.\n'
              'Out% = share of those plate appearances that ended in an out. K% = share that ended in a strikeout. '
              'Strike% = share of the 3 pitches that were strikes. n = plate appearances it is based on (under 3 is a small sample). Weak contact = share of balls in play that were ground balls.\n'
              'Score: ${s['score']}. $_seqScoreWhat',
          colorGuide: _seqCardGuide(),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: good ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
            border: Border.all(color: good ? AppColors.colSuccess : AppColors.colError, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(s['seq'] as String,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: good ? AppColors.perfExcellent : AppColors.colError)),
                ),
                const SizedBox(width: 8),
                StatHoldInfo(
                  title: 'Sequence Score',
                  description: composeHoldInfo(
                    what: '$_seqScoreWhat\n\nThis sequence: Score ${s['score']} → ${colorNameOf(perfHex('seq_score', s['score'] as double?))}.',
                    colorGuide: statColorGuide('seq_score'),
                  ),
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: perfHex('seq_score', s['score'] as double?),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Score ${s['score']}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Text('Out%: ${s['outPct']}%  |  K%: ${s['kPct']}%  |  Strike%: ${s['strikePct']}%  |  n=${s['count']} PA'
                  '${s['lowSample'] == true ? ' (small sample)' : ''}'
                  '${s['weakContactPct'] != null ? '  |  Weak contact: ${s['weakContactPct']}%' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 6),
                  dense: true,
                  title: const Text('Why this score',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.brandOrangeDeep)),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [SequenceBreakdown(s)],
                ),
              ),
            ],
          ),
        ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterRow,
        const SizedBox(height: 8),
        ResponsiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GlowCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Best Sequences (Top 5)', style: TextStyle(fontWeight: FontWeight.w800)),
                      const Text('Ranked by Sequence Score - decision quality, not just results. Tap "Why this score" on a card.',
                          style: TextStyle(fontSize: 10.5, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 8),
                      for (final s in best.take(5)) seqCard(s, true),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GlowCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sequences to Avoid', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (worst.isEmpty)
                        const Text('Need more data.', style: TextStyle(color: Colors.grey))
                      else
                        for (final s in worst.take(4)) seqCard(s, false),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        _AtBatReviewCard(atBats: atBats),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Put-Away Pitch (Final Pitch of K)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (putAway.isEmpty)
                  const Text('No strikeouts logged yet.', style: TextStyle(color: Colors.grey))
                else
                  for (final p in putAway)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _PitchBarRow(
                        pitchType: p['pitchType'] as String,
                        pct: p['pct'] as double,
                        detail: '${p['count']}/${p['ofTotal']} K',
                        title: 'Put-Away Pitch',
                        what: 'Of all strikeouts, the share that ended on this pitch type (strikeouts finished with it ÷ total strikeouts). The bar fills from 0% to 100%.',
                      ),
                    ),
              ],
            ),
          ),
        ),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('First-Pitch Strike% by Pitch Type', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (firstPitchStrike.isEmpty)
                  const Text('No first pitches logged yet.', style: TextStyle(color: Colors.grey))
                else
                  for (final p in firstPitchStrike)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _PitchBarRow(
                        pitchType: p['pitchType'] as String,
                        pct: p['pct'] as double,
                        detail: '${p['count']}/${p['ofTotal']} 1st pitches',
                        title: 'First-Pitch Strike %',
                        what: 'How often this pitch type was a strike when thrown as the first pitch of a plate appearance (first-pitch strikes ÷ first pitches of that type). The bar fills from 0% to 100%.',
                        statKey: 'f_strike',
                      ),
                    ),
              ],
            ),
          ),
        ),
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatHoldInfo(
                  title: 'Count Tendencies',
                  description: composeHoldInfo(
                    what: 'Rows are pitch types; columns are counts (balls-strikes, with n = pitches thrown at that count). '
                        'Each cell has three stacked blocks: STR% (top, how often the pitch was a strike), USE% (middle, how often it was chosen at that count) and BAA (bottom, batting average against).\n'
                        'Read across a row to see where a pitch is used; read down a column to compare pitches at one count. A "—" cell has no pitches.\n'
                        'The last row (ALL) is the BAA at each count with every pitch type combined: hits ÷ official at-bats whose final pitch was thrown at that count (walks and hit-by-pitches are not at-bats, and unfinished at-bats are left out).',
                    colorGuide: 'Each block is colored on its own, from dark green (best) to red (worst), using that stat\'s own cutoffs.\n'
                        'Press and hold any colored block to see its exact cutoffs and why it has that color.\n'
                        '${swatchLine(noDataGray, 'Gray block: not enough data for that stat')}',
                  ),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Count Tendencies', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                      'Each cell: Strike% (left) · Usage% (center) · BAA (right). Colors are scored independently on a 5-tier scale.',
                      style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                _PitchUsageHeatmap(heatmap: heatmap),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Formats a batting-average-style value the traditional way (".287"
/// rather than "0.287"), without breaking for the rare 1.000 case.
String _fmtAvg(double v) {
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : s;
}

/// One "pitch tag + progress bar + detail" row. The tag is width-bounded (so
/// long custom pitch names ellipsize instead of overflowing) and the detail
/// text sits under the bar so it can wrap instead of squeezing the bar.
class _PitchBarRow extends StatelessWidget {
  final String pitchType;
  final double pct;
  final String detail;
  final String title;
  final String what;

  /// When set, the pct's quality scale is appended to the hold info (the bar
  /// itself stays pitch-colored).
  final String? statKey;
  const _PitchBarRow({
    required this.pitchType,
    required this.pct,
    required this.detail,
    required this.title,
    required this.what,
    this.statKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.pitchColor(pitchType);
    final guide = '${pitchTypeColorGuide([pitchType])}'
        '${statKey == null ? '' : '\nThe bar color does not grade the number. To judge how good the percentage is, this stat uses these cutoffs (same scale as First-Pitch Strike % elsewhere in the app):\n${statTierLines(statKey!).join('\n')}'}';
    return StatHoldInfo(
      title: '$title · ${pitchType.toUpperCase()}',
      description: composeHoldInfo(what: what, colorGuide: guide),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row: pitch tag on the left, the actual % large on the right.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 56, maxWidth: 104),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      pitchType.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$pct%',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: statValueFontSize(context),
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 14,
                backgroundColor: AppColors.colBorder,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniTag({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      );
}

/// Larger, three-part-per-cell heat map: Strike% / Usage% / BAA, each
/// colored independently on the shared 5-tier perf scale (item 11).
class _PitchUsageHeatmap extends StatelessWidget {
  final Map<String, dynamic> heatmap;
  const _PitchUsageHeatmap({required this.heatmap});

  @override
  Widget build(BuildContext context) {
    final counts = heatmap['counts'] as List<String>;
    final pitchTypes = heatmap['pitchTypes'] as List<String>;
    final cells = heatmap['cells'] as Map<String, Map<String, dynamic>>;
    final countTotals = heatmap['countTotals'] as Map<String, int>;
    final countBaa = (heatmap['countBaa'] as Map<String, Map<String, dynamic>>?) ?? const {};

    if (pitchTypes.isEmpty) {
      return const Text('No pitch data yet.', style: TextStyle(color: Colors.grey));
    }

    Widget totalBaaCell(String count) {
      final c = countBaa[count];
      final ab = (c?['ab'] as int?) ?? 0;
      final hits = (c?['hits'] as int?) ?? 0;
      final baa = c?['baa'] as double?;
      if (baa == null) {
        return Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.surfaceAlt, border: Border.all(color: AppColors.colBorder, width: 2)),
          child: const Text('—', style: TextStyle(color: Colors.grey, fontSize: 11)),
        );
      }
      final bg = perfHex('AVG', baa);
      final fg = (bg == AppColors.perfExcellent || bg == AppColors.perfPoor || bg == AppColors.perfBelowAvg)
          ? Colors.white
          : AppColors.colText;
      return StatHoldInfo(
        title: 'BAA at $count (all pitches)',
        description: composeHoldInfo(
          what: 'Batting average against for at-bats whose final pitch was thrown at $count, every pitch type combined.\n'
              '$hits hit(s) ÷ $ab official at-bat(s) = ${_fmtAvg(baa)}.\n'
              'Walks and hit-by-pitches are not at-bats, and each at-bat is credited only to the count of its final pitch.',
          colorGuide: statColorGuide('AVG'),
        ),
        child: Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('BAA', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: fg.withOpacity(0.75))),
            Text(_fmtAvg(baa), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: fg)),
            Text('$hits/$ab', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: fg.withOpacity(0.75))),
          ]),
        ),
      );
    }

    Widget cellWidget(String count, String pt) {
      final key = '$count|$pt';
      final c = cells[key];
      if (c == null) {
        return Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.surfaceAlt, border: Border.all(color: AppColors.colBorder, width: 2)),
          child: const Text('—', style: TextStyle(color: Colors.grey, fontSize: 11)),
        );
      }
      final strikePct = c['strikePct'] as double?;
      final usagePct = c['usagePct'] as double?;
      final baa = c['baa'] as double?;
      final strikeBg = perfHex('f_strike', strikePct);
      final usageBg = perfHex('usage_predictability', usagePct);
      final baaBg = perfHex('AVG', baa);
      Color tc(Color bg) => (bg == AppColors.perfExcellent || bg == AppColors.perfPoor || bg == AppColors.perfBelowAvg)
          ? Colors.white
          : AppColors.colText;
      Widget third(Color bg, String label, String value, String statKey, String what, String? note) {
        final shown = '${label == 'STR%' ? 'Strike %' : label == 'USE%' ? 'Usage %' : 'BAA'} at $count · ${pt.toUpperCase()}';
        return StatHoldInfo(
          title: shown,
          description: composeHoldInfo(
            what: '$what\n\nThis block: $value → ${colorNameOf(bg)}.',
            colorGuide: statColorGuide(statKey, note: note),
          ),
          child: Container(
            width: double.infinity,
            color: bg,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: tc(bg).withOpacity(0.75))),
              Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tc(bg))),
            ]),
          ),
        );
      }
      return Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.colBorder, width: 2)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          third(strikeBg, 'STR%', strikePct != null ? '${strikePct.toStringAsFixed(0)}' : '—',
              'f_strike',
              'Strike %: of this pitch type thrown at this count, the share that were strikes (called, swinging or foul).',
              'Strike % here uses the same cutoffs as First-Pitch Strike % (F-Strike%).'),
          third(usageBg, 'USE%', usagePct != null ? '${usagePct.toStringAsFixed(0)}' : '—',
              'usage_predictability',
              'Usage %: of all pitches thrown at this count, the share that were this pitch type.',
              'Graded on the usage-predictability scale: leaning heavily on one pitch at a count is more predictable, so high usage trends toward orange/red.'),
          third(baaBg, 'BAA', baa != null ? _fmtAvg(baa) : '—',
              'AVG',
              'BAA (batting average against) for ONLY the pitches of this type thrown at this count: '
                  'each at-bat is credited to the single pitch that ended it (a hit or an out on that pitch), '
                  'not to the earlier pitches of the at-bat.\n'
                  '${(c['ab'] as int? ?? 0) > 0 ? 'Here: ${c['hits']} hit(s) in ${c['ab']} at-bat(s) that ended on this pitch at this count.' : 'No at-bat has ended on this pitch at this count yet, so BAA is left blank (—), not 0.'}',
              null),
        ]),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      // Size every column to fit the available card width exactly (instead
      // of fixed pixel widths inside a horizontally-scrolling container) so
      // the whole heat map is visible without scrolling right.
      // Label column grows with the longest (custom) pitch name, within bounds.
      final longestPitch = pitchTypes.fold<int>(0, (a, p) => p.length > a ? p.length : a);
      final labelColWidth = (longestPitch * 6.5 + 12).clamp(46.0, 88.0).toDouble();
      // Each cell holds three stacked values (".287", "STR%", ...), so a column
      // needs a minimum width to stay legible. On narrow screens the table keeps
      // that width and scrolls sideways instead of crushing 12 columns to ~20px.
      const minColWidth = 54.0;
      final neededWidth = labelColWidth + counts.length * minColWidth;
      final tableWidth = constraints.maxWidth >= neededWidth ? constraints.maxWidth : neededWidth;
      final available = (tableWidth - labelColWidth).clamp(0.0, double.infinity);
      final colWidth = counts.isEmpty ? available : available / counts.length;

      final table = Table(
        defaultColumnWidth: FixedColumnWidth(colWidth),
        columnWidths: {0: FixedColumnWidth(labelColWidth)},
        border: TableBorder.all(color: AppColors.colBorder, width: 2),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.ink),
            children: [
              const Padding(
                padding: EdgeInsets.all(4),
                child: Text('Pitch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9)),
              ),
              for (final count in counts)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(count, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                    Text('n=${countTotals[count] ?? 0}',
                        style: const TextStyle(fontSize: 7.5, color: Colors.white70)),
                  ]),
                ),
            ],
          ),
          for (final pt in pitchTypes)
            TableRow(children: [
              StatHoldInfo(
                title: pt.toUpperCase(),
                description: composeHoldInfo(
                  what: 'This row shows how this pitch type is used and how it performs at each count.',
                  colorGuide: pitchTypeColorGuide([pt]),
                ),
                child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                color: AppColors.surfaceAlt,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.pitchColor(pt), shape: BoxShape.circle)),
                  const SizedBox(height: 2),
                  Text(pt.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 9),
                      textAlign: TextAlign.center),
                ]),
                ),
              ),
              for (final count in counts) cellWidget(count, pt),
            ]),
          TableRow(children: [
            StatHoldInfo(
              title: 'ALL pitches',
              description: composeHoldInfo(
                what: 'Batting average against at each count with every pitch type combined.\n'
                    'BAA = hits ÷ official at-bats. An at-bat is credited to the count of its FINAL pitch only; '
                    'walks, hit-by-pitches and unfinished at-bats are not counted.',
                colorGuide: swatchLine(AppColors.surfaceAlt, 'Row label: not graded, so it has no cutoffs.'),
              ),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                color: AppColors.surfaceAlt,
                child: const Text('ALL',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 9), textAlign: TextAlign.center),
              ),
            ),
            for (final count in counts) totalBaaCell(count),
          ]),
        ],
      );
      if (constraints.maxWidth >= neededWidth) return table;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: tableWidth, child: table),
      );
    });
  }
}


/// Recent at-bats, each with its own explainable Sequencing Score — covers
/// every at-bat length (including ones too short for the opening-sequence
/// lists) and at-bats still in progress.
class _AtBatReviewCard extends StatelessWidget {
  final List<PaScore> atBats; // newest first
  const _AtBatReviewCard({required this.atBats});

  String _seqText(PaScore pa) {
    final out = <String>[];
    for (var i = 0; i < pa.pitches.length; i++) {
      final p = pa.pitches[i];
      final (b, st) = pa.countsBefore[i];
      final t = (p.pitchType ?? '?').toUpperCase();
      out.add('$b-$st $t ${p.call ?? ''}');
    }
    return out.join('  \u2192  ');
  }

  @override
  Widget build(BuildContext context) {
    final shown = atBats.take(15).toList();
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('At-Bat Review', style: TextStyle(fontWeight: FontWeight.w800)),
            const Text(
                'Newest first. Each pitch shows the count it was thrown in. Tap an at-bat for the full score breakdown.',
                style: TextStyle(fontSize: 10.5, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
            const SizedBox(height: 6),
            if (shown.isEmpty)
              const Text('No at-bats logged yet.', style: TextStyle(color: Colors.grey))
            else
              for (final pa in shown)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: Text(
                      '${pa.team} #${pa.gameNumber}'
                      '${pa.jersey != null ? '  |  Batter #${pa.jersey}' : ''}'
                      '${pa.completed ? '  |  ${(pa.finalOutcome ?? '').toUpperCase()}' : '  |  in progress'}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    subtitle: Text(_seqText(pa),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: pa.hasScore ? perfHex('seq_score', pa.score) : AppColors.colBorder,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(pa.hasScore ? pa.score!.toStringAsFixed(0) : 'n/a',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    children: [PaBreakdown(pa)],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
