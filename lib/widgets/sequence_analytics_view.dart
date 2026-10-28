import 'package:flutter/material.dart';

import '../services/color_guides.dart';
import '../services/sequence_analytics.dart';
import '../services/stats_service.dart' show perfHex;
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glow.dart';
import '../widgets/stat_box.dart';
import '../widgets/stat_hold_info.dart';

// ── formatting ─────────────────────────────────────────────────────────────
String _pct(double? v) => v == null ? kUnavailable : '${v.toStringAsFixed(0)}%';
String _avg(double? v) {
  if (v == null) return kUnavailable;
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : s;
}

// ── shared statistic boxes (one look for every sequencing section) ─────────
// Graded boxes take their color from SKOUTAR's existing tier cutoffs
// (perfHex / statColorGuide); counts and pitch usage are never graded, so a
// low or high usage share is never colored good or bad.

const String _whatStrike = 'Share of pitches that were strikes (called, swinging, foul or put in play). Higher is better.';
const String _whatWhiff = 'Swinging strikes ÷ swings (swinging + foul + in play). Higher is better.';
const String _whatBall = 'Share of pitches that were balls. Lower is better.';
const String _whatBaa =
    'Batting average against: hits ÷ official at-bats (walks and hit-by-pitch are not at-bats). Lower is better. '
    'A dash means no official at-bat yet.';
const String _whatBb = 'Walk percentage: share of finished at-bats that ended in a walk. Lower is better.';
const String _whatK =
    'Strikeout percentage: share of finished at-bats that ended in a strikeout (including a dropped third strike). Higher is better.';
/// A graded box. [raw] null = no eligible data: dash and neutral styling.
StatBox _graded({
  required String label,
  required double? raw,
  required String text,
  required String statKey,
  required String title,
  required String what,
  String? sub,
}) =>
    StatBox(
      label: label,
      value: raw == null ? kUnavailable : text,
      sub: raw == null ? null : sub,
      tier: raw == null ? null : perfHex(statKey, raw),
      title: title,
      description: what,
      colorGuide: statColorGuide(statKey),
    );

/// An ungraded box (a count or sample size).
StatBox _count(String label, String value, String title, String what, {String? sub}) => StatBox(
      label: label,
      value: value,
      sub: sub,
      title: title,
      description: what,
    );

/// Pitches / Strike% / Whiff% / Ball% for a set of pitches.
List<Widget> _pitchBoxes(PitchResults r, String ctx, {String nWhat = 'Pitches in this group.'}) => [
      _count('Pitches', '${r.n}', 'Pitches · $ctx', '$nWhat Not graded: it is the sample size.'),
      _graded(
          label: 'Strike%',
          raw: r.strikePct,
          text: _pct(r.strikePct),
          statKey: 'f_strike',
          title: 'Strike % · $ctx',
          what: _whatStrike),
      _graded(
          label: 'Whiff%',
          raw: r.whiffPct,
          text: _pct(r.whiffPct),
          statKey: 'whiff_pct',
          title: 'Whiff % · $ctx',
          what: _whatWhiff,
          sub: r.swings == 0 ? null : '${r.swinging}/${r.swings}'),
      _graded(
          label: 'Ball%',
          raw: r.ballPct,
          text: _pct(r.ballPct),
          statKey: 'ball_pct',
          title: 'Ball % · $ctx',
          what: _whatBall),
    ];

StatBox _baaBox(PaResults pa, String ctx) => _graded(
      label: 'BAA',
      raw: pa.baa,
      text: _avg(pa.baa),
      statKey: 'AVG',
      title: 'BAA · $ctx',
      what: _whatBaa,
      sub: pa.ab == 0 ? null : '${pa.hits}/${pa.ab}',
    );

/// Pitch-type usage as neutral boxes (share of the group, with the raw count).
/// The most-used pitch gets the brand outline; nothing is colored good or bad.
List<Widget> _mixBoxList(Map<String, int> counts, String ctx) {
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return const <Widget>[];
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [
    for (var i = 0; i < entries.length; i++)
      StatBox(
        label: entries[i].key.toUpperCase(),
        value: '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
        sub: '${entries[i].value} of $total',
        accent: AppColors.pitchColor(entries[i].key),
        highlighted: i == 0 && entries.length > 1,
        title: '${entries[i].key.toUpperCase()} usage · $ctx',
        description: 'Share of the pitches in this group that were ${entries[i].key.toUpperCase()} '
            '(${entries[i].value} of $total). Usage is not graded: throwing a pitch more or less often is not good or bad '
            'by itself. The outlined box is the most used.',
        ),
  ];
}

/// Boxes sit centered in their card on phones (so a short last line is not
/// jammed against the left edge); desktop and tablet keep the start alignment.
WrapAlignment _boxAlign(BuildContext context) =>
    Responsive.isPhone(context) ? WrapAlignment.center : WrapAlignment.start;

Widget _mixBoxes(Map<String, int> counts, String ctx) => Builder(
    builder: (context) =>
        Wrap(spacing: 6, runSpacing: 6, alignment: _boxAlign(context), children: _mixBoxList(counts, ctx)));

Widget _boxes(List<Widget> children) => Builder(
    builder: (context) => Wrap(spacing: 6, runSpacing: 6, alignment: _boxAlign(context), children: children));

/// One labelled value (used by the plain "Data used" card).
class _M extends StatelessWidget {
  final String label, value;
  const _M(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final phone = Responsive.isPhone(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 52),
      child: Column(
          crossAxisAlignment: phone ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                textAlign: phone ? TextAlign.center : TextAlign.start,
                style: const TextStyle(fontSize: 10, color: AppColors.colMuted, fontWeight: FontWeight.w700)),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
    );
  }
}

class _SmallFlag extends StatelessWidget {
  final String text;
  const _SmallFlag(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.brandOrangeDeep),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.brandOrangeDeep)),
      );
}

/// One row card: a title (a sequence, a count, a pitch type ...), then its
/// boxes. [selected] draws the brand outline; [onTap] makes the row tappable.
class _Row extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool small;
  final String smallText;
  final bool selected;
  final VoidCallback? onTap;
  const _Row({
    required this.title,
    required this.children,
    this.small = false,
    this.smallText = 'small sample',
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(
          color: selected ? AppColors.brandOrangeDeep : AppColors.colBorder,
          width: selected ? 2.5 : 1.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          if (small) ...[const SizedBox(width: 6), _SmallFlag(smallText)],
        ]),
        for (final c in children) ...[const SizedBox(height: 6), c],
      ]),
    );
    final padded = Padding(padding: const EdgeInsets.only(bottom: 6), child: card);
    if (onTap == null) return padded;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: padded),
    );
  }
}

/// Puts two cards side by side when there is room (easy left/right
/// comparison), otherwise stacks them.
Widget _sideBySide(List<Widget> items) => LayoutBuilder(builder: (context, constraints) {
      if (items.length == 2 && constraints.maxWidth >= 760) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: items[0]),
          const SizedBox(width: 8),
          Expanded(child: items[1]),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
    });

class _Section extends StatelessWidget {
  final String title, what, blurb;
  final List<Widget> children;
  const _Section({required this.title, required this.what, required this.blurb, required this.children});

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StatHoldInfo(
            title: title,
            description: composeHoldInfo(what: what),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(blurb,
                style: const TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
          ),
          ...children,
        ]),
      ),
    );
  }
}

/// All the descriptive sequencing sections. Each section renders on its own
/// when it has data; a section without data explains exactly what is missing
/// instead of hiding the whole screen.
class SequenceAnalyticsView extends StatefulWidget {
  final SequenceAnalytics analytics;
  const SequenceAnalyticsView({super.key, required this.analytics});

  @override
  State<SequenceAnalyticsView> createState() => _SequenceAnalyticsViewState();
}

class _SequenceAnalyticsViewState extends State<SequenceAnalyticsView> {
  int _openLen = 3;
  bool _showAll = false;
  bool _showAllTransitions = false;

  /// Rows in two columns (rank order runs left to right, then down) with a
  /// subtle vertical divider between them. Narrow widths stack them in one
  /// column. [minWidth] is the content width needed for two columns.
  ///
  /// LAYOUT NOTE: this widget lives inside the app shell's vertical
  /// SingleChildScrollView, so its height is UNBOUNDED. A Row with
  /// CrossAxisAlignment.stretch tries to force every child to the Row's
  /// (infinite) height and cannot lay out, which left the heading visible but
  /// everything under it missing. The Row therefore uses start alignment, and
  /// the divider is the left column's own right border, so it takes that
  /// column's real height instead of needing the Row to impose one.
  Widget _twoColumnRows(List<Widget> rows, {double minWidth = 820}) => LayoutBuilder(builder: (context, c) {
        if (rows.length < 2 || c.maxWidth < minWidth) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: AppColors.colBorder, width: 1.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < rows.length; i += 2) rows[i],
                ]),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 1; i < rows.length; i += 2) rows[i],
                ]),
              ),
            ),
          ],
        );
      });

  /// "Next pitch" usage boxes for one "After X" row, under their own small
  /// caption. (They used to share the results Wrap behind a thin divider
  /// widget; when that Wrap broke lines the divider could sit alone in a
  /// 44px-high run, which showed up as an empty box under the results.)
  Widget _nextPitchMix(Map<String, int> counts, String ctx) =>
      Column(
          crossAxisAlignment: Responsive.isPhone(context) ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
        const Text('Next pitch thrown',
            style: TextStyle(fontSize: 10, color: AppColors.colMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        _mixBoxes(counts, ctx),
      ]);

  /// One "After X" row: how the NEXT pitch went, then which pitch came next.
  Widget _afterPitchRow(AfterPitchRow r) {
    final prev = r.prevType.toUpperCase();
    return _Row(
      title: 'After $prev',
      small: r.next.small,
      smallText: 'Under ${SeqSampleSize.smallPitches} pitches',
      children: [
        _boxes([
          ..._pitchBoxes(r.next, 'after $prev', nWhat: 'Next pitches thrown right after a $prev.'),
          _count('In play', '${r.next.inPlay}', 'In play · after $prev',
              'Next pitches that were put in play. A count, not graded.'),
        ]),
        if (r.nextTypes.isNotEmpty) _nextPitchMix(r.nextTypes, 'next pitch after $prev'),
      ],
    );
  }

  /// One A → B transition row.
  Widget _transitionRow(TransitionRow r) {
    final t = '${r.from.toUpperCase()} → ${r.to.toUpperCase()}';
    return _Row(
      title: t,
      small: r.n < SeqSampleSize.smallPitches,
      smallText: 'Under ${SeqSampleSize.smallPitches} times',
      children: [
        _boxes([
          _count('Times Thrown', '${r.n}', 'Times thrown · $t',
              'Times this pitch followed the other in the same at-bat. Not graded: it is the sample size.'),
          _graded(
              label: 'Strike%',
              raw: r.results.strikePct,
              text: _pct(r.results.strikePct),
              statKey: 'f_strike',
              title: 'Strike % · $t',
              what: _whatStrike),
          _graded(
              label: 'Whiff%',
              raw: r.results.whiffPct,
              text: _pct(r.results.whiffPct),
              statKey: 'whiff_pct',
              title: 'Whiff % · $t',
              what: _whatWhiff,
              sub: r.results.swings == 0 ? null : '${r.results.swinging}/${r.results.swings}'),
          _count('At-Bats Ended', '${r.paEnd.pas}', 'At-bats ended · $t',
              'At-bats that ended on the second pitch of this transition. A count, not graded.'),
          _count('Strikeouts', '${r.paEnd.k}', 'Strikeouts · $t',
              'Strikeouts among the at-bats that ended on this transition. A count, not graded.'),
          _baaBox(r.paEnd, t),
        ]),
      ],
    );
  }

  Widget _sequenceRow(SequenceRow r) {
    final t = r.label;
    return _Row(
      title: r.label,
      small: r.small,
      smallText: 'Under ${SeqSampleSize.smallPas} plate appearances',
      children: [
        _boxes([
          _count('Plate Appearances', '${r.n}', 'Plate appearances · $t',
              'Finished at-bats that opened with exactly this pitch order. Not graded: it is the sample size. '
                  'Under ${SeqSampleSize.smallPas} is a small sample, so read the colors cautiously.'),
          _graded(
              label: 'Strike%',
              raw: r.strikePct,
              text: _pct(r.strikePct),
              statKey: 'f_strike',
              title: 'Strike % · $t',
              what: 'Share of the pitches in this sequence that were strikes (called, swinging, foul or put in play). Higher is better.'),
          _baaBox(r.pa, t),
          _graded(
              label: 'BB%',
              raw: r.pa.bbPct,
              text: _pct(r.pa.bbPct),
              statKey: 'BB_pct',
              title: 'Walk % · $t',
              what: _whatBb),
          _graded(
              label: 'K%',
              raw: r.pa.kPct,
              text: _pct(r.pa.kPct),
              statKey: 'K_pct',
              title: 'Strikeout % · $t',
              what: _whatK),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analytics;
    final d = a.diagnostics;

    // Only lengths that have real data are offered. If the remembered choice
    // is not available in this selection (e.g. a shorter game), fall back to
    // the shortest available length instead of showing an empty result.
    final lengths = a.sequenceLengths;
    final int? openLen = lengths.isEmpty ? null : (lengths.contains(_openLen) ? _openLen : lengths.first);
    final openRows = openLen == null ? const <SequenceRow>[] : a.openingByLength[openLen]!;
    final visibleRows = _showAll ? openRows : openRows.take(12).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Section(
        title: 'Data used',
        what: 'How many logged rows feed the sequencing analysis. Plate appearances are rebuilt from the stored '
            'game, batter sequence number and pitch number, so the order rows were saved in does not matter. '
            'Each metric below needs different data: counts and transitions work on any at-bat, '
            'opening sequences need FINISHED at-bats with at least that many pitches.',
        blurb: 'Everything below uses only pitch type, call, count and at-bat result.',
        children: [
          Wrap(
              spacing: 16,
              runSpacing: 6,
              alignment: Responsive.isPhone(context) ? WrapAlignment.spaceEvenly : WrapAlignment.start,
              children: [
            _M('Pitches', '${d.pitchRows}'),
            _M('Plate appearances', '${d.plateAppearances}'),
            _M('Finished', '${d.finishedPas}'),
            _M('Longest finished at-bat', '${d.longestFinishedPa}'),
            _M('Finished, 3+ pitches', '${d.pasWith3Plus}'),
            _M('Pitch-to-pitch pairs', '${d.transitions}'),
          ]),
          if (d.pitchesMissingType > 0 || d.pitchesMissingCall > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${d.pitchesMissingType > 0 ? '${d.pitchesMissingType} pitch(es) have no pitch type (grouped as OTHER). ' : ''}'
                '${d.pitchesMissingCall > 0 ? '${d.pitchesMissingCall} pitch(es) have no call and count as neither a strike nor a ball.' : ''}',
                style: const TextStyle(fontSize: 11, color: AppColors.brandOrangeDeep),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Sequence effectiveness',
        what: 'The first pitches of FINISHED at-bats, grouped by exact pitch-type order. Pick a length (3 pitches and up); '
            'only lengths that a recorded at-bat actually reached are offered, and only sequences that really happened are listed. '
            'Each at-bat counts once per sequence and the result is how that at-bat ended.\n'
            'The list is ranked by a conservative estimate of how often the at-bat ended in an out (a 95% Wilson floor), '
            'so a sequence seen 3 times ranks below one with the same results seen 30 times. '
            'It is a ranking aid, not a prediction or proof the sequence caused the result.',
        blurb: 'Opening pitches of finished at-bats, by sequence length. Boxes tint green (favorable) to red (unfavorable); '
            'plain boxes are counts and are not graded. Press and hold a box for what it means.',
        children: [
          if (openLen == null)
            Text(
              d.finishedPas == 0
                  ? 'No finished at-bats in this selection yet.'
                  : 'No finished at-bat with 3 or more pitches in this selection '
                      '(${d.finishedPas} finished, longest ${d.longestFinishedPa} pitch${d.longestFinishedPa == 1 ? '' : 'es'}). '
                      'Sequences appear here as soon as one does.',
              style: const TextStyle(color: Colors.grey),
            )
          else ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final len in lengths)
                ChoiceChip(
                  label: Text('$len pitches'),
                  selected: len == openLen,
                  onSelected: (_) => setState(() {
                    _openLen = len;
                    _showAll = false;
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            _twoColumnRows([for (final r in visibleRows) _sequenceRow(r)]),
            if (openRows.length > 12)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll
                      ? 'Show top 12 only'
                      : 'Show all ${openRows.length} sequences (top 12 shown)'),
                ),
              ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Results after each pitch type',
        what: 'For every pitch that was followed by another pitch in the same at-bat: what happened on that NEXT pitch. '
            'Strike% = called + swinging + foul + in play ÷ pitches. Whiff% = swinging strikes ÷ swings (swinging + foul + in play). '
            'Ball% = balls ÷ pitches. Pitches = next pitches observed. The pitch-type boxes show which pitch came next (usage, not graded).',
        blurb: 'Grouped by the pitch thrown before. Pitches = next pitches observed.',
        children: [
          if (a.afterPitch.isEmpty)
            Text('No at-bat has two or more pitches in this selection (${d.transitions} pitch-to-pitch pairs).',
                style: const TextStyle(color: Colors.grey))
          else
            // Two columns when wide enough for each row's boxes to stay on one
            // line (most-used previous pitch first, left to right, then down).
            _twoColumnRows([for (final r in a.afterPitch) _afterPitchRow(r)], minWidth: 980),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Pitch-to-pitch transitions',
        what: 'Each row is one pitch type followed directly by another in the same at-bat (A → B). The boxes describe the B pitch: '
            'Strike% and Whiff% (swinging strikes ÷ swings), plus how many at-bats ended on B (with strikeouts and BAA for those). '
            'Times Thrown = times that transition happened.',
        blurb: 'A → B, most frequent first. Times Thrown = times thrown in that order.',
        children: [
          if (!a.hasTransitions)
            const Text('No at-bat has two or more pitches in this selection.', style: TextStyle(color: Colors.grey))
          else
            _twoColumnRows([
              for (final r in (_showAllTransitions ? a.transitions : a.transitions.take(15).toList()))
                _transitionRow(r),
            ], minWidth: 980),
          if (a.transitions.length > 15)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showAllTransitions = !_showAllTransitions),
                child: Text(_showAllTransitions
                    ? 'Show the 15 most frequent only'
                    : 'Show all ${a.transitions.length} transitions (15 most frequent shown)'),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Pitch selection by batter handedness',
        what: 'The same pitch mix and results split by the BATTER hand stored on each pitch (L or R), not the pitcher\'s throwing hand. '
            'The app stores R when no hand was chosen, so treat a split with very few left-handed pitches as thin data, not as proof of how you pitch to lefties. '
            'Usage boxes are not graded.',
        blurb: 'Shown only when both hands have logged pitches.',
        children: [
          if (!a.hasHandSplit)
            Text(
              a.byHand.isEmpty
                  ? 'No pitches with a batter hand in this selection.'
                  : 'Only ${a.byHand.first.label.toLowerCase()} have logged pitches in this selection, so there is nothing to compare yet.',
              style: const TextStyle(color: Colors.grey),
            )
          else
            _sideBySide([
              for (final r in a.byHand)
                _Row(
                  title: r.label,
                  small: r.small,
                  smallText: 'Under ${SeqSampleSize.smallPitches} pitches',
                  children: [
                    _boxes([
                      ..._pitchBoxes(r.pitches, r.label, nWhat: 'Pitches thrown to this group of batters.'),
                      _count('At-Bats Ended', '${r.paEnd.pas}', 'At-bats ended · ${r.label}',
                          'At-bats whose final pitch was thrown to this group of batters. A count, not graded.'),
                      _graded(
                          label: 'K%',
                          raw: r.paEnd.kPct,
                          text: _pct(r.paEnd.kPct),
                          statKey: 'K_pct',
                          title: 'Strikeout % · ${r.label}',
                          what: _whatK),
                      _baaBox(r.paEnd, r.label),
                    ]),
                    _mixBoxes(r.mix, r.label),
                  ],
                ),
            ]),
        ],
      ),
    ]);
  }
}
