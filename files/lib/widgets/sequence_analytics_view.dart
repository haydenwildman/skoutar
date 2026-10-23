import 'package:flutter/material.dart';

import '../services/color_guides.dart';
import '../services/sequence_analytics.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/stat_hold_info.dart';

String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)}%';
String _frac(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(0)}%';
String _mixText(List<(String, double)> shares, {int top = 5}) =>
    shares.take(top).map((e) => '${e.$1.toUpperCase()} ${(e.$2 * 100).toStringAsFixed(0)}%').join(' · ');

String _avg(double? v) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(3);
  return s.startsWith('0.') ? s.substring(1) : s;
}

/// One labelled value. Wraps in a [Wrap] so nothing ever needs horizontal scroll.
class _M extends StatelessWidget {
  final String label, value;
  const _M(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 52),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.colMuted, fontWeight: FontWeight.w700)),
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

class _Row extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<_M> metrics;
  final bool small;
  final String smallText;
  const _Row({
    required this.title,
    required this.metrics,
    this.subtitle,
    this.small = false,
    this.smallText = 'small sample',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.colBorder, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          if (small) ...[const SizedBox(width: 6), _SmallFlag(smallText)],
        ]),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.colMuted)),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 16, runSpacing: 6, children: metrics),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title, what, blurb;
  final List<Widget> children;
  const _Section({required this.title, required this.what, required this.blurb, required this.children});

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
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

  @override
  Widget build(BuildContext context) {
    final a = widget.analytics;
    final d = a.diagnostics;

    // Default to the 2-pitch view when there are no 3-pitch openers at all.
    final openLen = (_openLen == 3 && !a.hasOpeningThree && a.hasOpeningTwo) ? 2 : _openLen;
    final openRows = openLen == 3 ? a.openingThree : a.openingTwo;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Section(
        title: 'Data used',
        what: 'How many logged rows feed the sequencing analysis. Plate appearances are rebuilt from the stored '
            'game, batter sequence number and pitch number, so the order rows were saved in does not matter. '
            'Each metric below needs different data: counts and transitions work on any at-bat, '
            'opening sequences need FINISHED at-bats with at least that many pitches.',
        blurb: 'Everything below uses only pitch type, call, count and at-bat result.',
        children: [
          Wrap(spacing: 16, runSpacing: 6, children: [
            _M('Pitches', '${d.pitchRows}'),
            _M('Plate appearances', '${d.plateAppearances}'),
            _M('Finished', '${d.finishedPas}'),
            _M('Finished, 2+ pitches', '${d.pasWith2Plus}'),
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
        what: 'DESCRIPTIVE (plain ratios of logged at-bats): n, Out%, K%, BB%, BAA (hits ÷ official at-bats) and Strike% of the opening pitches.\n'
            'MODELED (one number): "Out% floor" is the lower end of the 95% Wilson confidence interval for the out rate. '
            'It has no hand-picked weights; it only asks "how low could the true out rate plausibly be given this many at-bats?" '
            'and the list is ranked by it, so a sequence seen 3 times ranks below one with the same Out% seen 30 times. '
            'It is a ranking aid, not a prediction or a claim that the sequence caused the result.\n'
            'Out = batter retired (strikeouts, outs in play, fielder\'s choice); reaching base = hit, walk, HBP or error.',
        blurb: 'Opening pitch types of finished at-bats, ranked by the Out% floor (95% Wilson). n = at-bats.',
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 3, label: Text('First 3 pitches')),
              ButtonSegment(value: 2, label: Text('First 2 pitches')),
            ],
            selected: {openLen},
            onSelectionChanged: (s) => setState(() => _openLen = s.first),
          ),
          const SizedBox(height: 8),
          if (openRows.isEmpty)
            Text(
              openLen == 3
                  ? 'No finished at-bats with 3+ pitches in this selection (${d.pasWith3Plus} found, ${d.finishedPas} finished at-bats in total).'
                  : 'No finished at-bats with 2+ pitches in this selection (${d.pasWith2Plus} found).',
              style: const TextStyle(color: Colors.grey),
            )
          else
            for (final r in openRows.take(12))
              _Row(
                title: r.label,
                small: r.small,
                smallText: 'n < ${SeqSampleSize.smallPas}',
                metrics: [
                  _M('n', '${r.n}'),
                  _M('Out%', _pct(r.pa.outPct)),
                  _M('Out% floor', _frac(r.outLower)),
                  _M('K%', _pct(r.pa.kPct)),
                  _M('BB%', _pct(r.pa.bbPct)),
                  _M('BAA', r.pa.ab == 0 ? '—' : '${_avg(r.pa.baa)} (${r.pa.hits}/${r.pa.ab})'),
                  _M('Strike%', _pct(r.strikePct)),
                ],
              ),
          if (openRows.length > 12)
            Text('Showing the top 12 of ${openRows.length} sequences.',
                style: const TextStyle(fontSize: 11, color: AppColors.colMuted)),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Results after each pitch type',
        what: 'For every pitch that was followed by another pitch in the same at-bat: what happened on that NEXT pitch. '
            'Strike% = called + swinging + foul + in play ÷ pitches. Whiff% = swinging strikes ÷ swings (swinging + foul + in play). '
            'Ball% = balls ÷ pitches. n = next pitches observed.',
        blurb: 'Grouped by the pitch thrown before. n = next pitches.',
        children: [
          if (a.afterPitch.isEmpty)
            Text('No at-bat has two or more pitches in this selection (${d.transitions} pitch-to-pitch pairs).',
                style: const TextStyle(color: Colors.grey))
          else
            for (final r in a.afterPitch)
              _Row(
                title: 'After ${r.prevType.toUpperCase()}',
                subtitle: 'Next pitch type: ${(r.nextTypes.entries.toList()..sort((x, y) => y.value.compareTo(x.value))).take(4).map((e) => '${e.key.toUpperCase()} ${e.value}').join(' · ')}',
                small: r.next.small,
                smallText: 'n < ${SeqSampleSize.smallPitches}',
                metrics: [
                  _M('n', '${r.next.n}'),
                  _M('Strike%', _pct(r.next.strikePct)),
                  _M('Whiff%', r.next.swings == 0 ? '—' : '${_pct(r.next.whiffPct)} (${r.next.swinging}/${r.next.swings})'),
                  _M('Ball%', _pct(r.next.ballPct)),
                  _M('In play', '${r.next.inPlay}'),
                ],
              ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Pitch-to-pitch transitions',
        what: 'Each row is one pitch type followed directly by another in the same at-bat (A → B). The numbers describe the B pitch: '
            'Strike%, Whiff% (swinging strikes ÷ swings) and how many at-bats ended on B (with K and hits/AB for those). '
            'n = times that transition happened.',
        blurb: 'A → B, most frequent first. n = times thrown in that order.',
        children: [
          if (!a.hasTransitions)
            const Text('No at-bat has two or more pitches in this selection.', style: TextStyle(color: Colors.grey))
          else
            for (final r in a.transitions.take(15))
              _Row(
                title: '${r.from.toUpperCase()} → ${r.to.toUpperCase()}',
                small: r.n < SeqSampleSize.smallPitches,
                smallText: 'n < ${SeqSampleSize.smallPitches}',
                metrics: [
                  _M('n', '${r.n}'),
                  _M('Strike%', _pct(r.results.strikePct)),
                  _M('Whiff%', r.results.swings == 0 ? '—' : '${_pct(r.results.whiffPct)} (${r.results.swinging}/${r.results.swings})'),
                  _M('Ended AB', '${r.paEnd.pas}'),
                  _M('K', '${r.paEnd.k}'),
                  _M('Hits/AB', r.paEnd.ab == 0 ? '—' : '${r.paEnd.hits}/${r.paEnd.ab}'),
                ],
              ),
          if (a.transitions.length > 15)
            Text('Showing the 15 most frequent of ${a.transitions.length} transitions.',
                style: const TextStyle(fontSize: 11, color: AppColors.colMuted)),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Performance by count',
        what: 'Every pitch is credited to the count it was thrown in (balls-strikes before the pitch). '
            'Strike%, Whiff% and Ball% describe those pitches. K / BB / BAA are for at-bats whose FINAL pitch was thrown at that count '
            '(BAA = hits ÷ official at-bats; walks and HBP are not at-bats).',
        blurb: 'All pitch types combined. n = pitches thrown at the count.',
        children: [
          if (!a.hasCounts)
            const Text('No pitches logged in this selection.', style: TextStyle(color: Colors.grey))
          else
            for (final r in a.counts)
              _Row(
                title: r.label,
                subtitle: 'Pitches thrown: ${_mixText([
                      for (final e in (r.mix.entries.toList()
                        ..sort((x, y) => y.value.compareTo(x.value))))
                        (e.key, e.value / r.pitches.n),
                    ])}',
                small: r.pitches.small,
                smallText: 'n < ${SeqSampleSize.smallPitches}',
                metrics: [
                  _M('n', '${r.pitches.n}'),
                  _M('Strike%', _pct(r.pitches.strikePct)),
                  _M('Whiff%', r.pitches.swings == 0 ? '—' : _pct(r.pitches.whiffPct)),
                  _M('Ball%', _pct(r.pitches.ballPct)),
                  _M('AB ended', '${r.paEnd.pas}'),
                  _M('K', '${r.paEnd.k}'),
                  _M('BB', '${r.paEnd.bb}'),
                  _M('BAA', r.paEnd.ab == 0 ? '—' : '${_avg(r.paEnd.baa)} (${r.paEnd.hits}/${r.paEnd.ab})'),
                ],
              ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'Pitch selection by count situation',
        what: 'How your pitch mix changes as the at-bat moves from early to late counts. '
            'Ahead = more strikes than balls, Behind = more balls than strikes, Even = same number (after 0-0). '
            'Two strikes overlaps with Ahead/Even/Behind because a 2-2 or 1-2 count is both. '
            'The percentages are each pitch type\'s share of the pitches thrown in that situation; '
            'Strike%, Whiff% and Ball% describe those same pitches.',
        blurb: 'Each pitch is counted in the count it was thrown in. n = pitches.',
        children: [
          if (!a.hasSituations)
            const Text('No pitches logged in this selection.', style: TextStyle(color: Colors.grey))
          else
            for (final r in a.situations)
              _Row(
                title: r.label,
                subtitle: _mixText(r.shares),
                small: r.small,
                smallText: 'n < ${SeqSampleSize.smallPitches}',
                metrics: [
                  _M('n', '${r.n}'),
                  _M('Strike%', _pct(r.pitches.strikePct)),
                  _M('Whiff%', r.pitches.swings == 0 ? '—' : _pct(r.pitches.whiffPct)),
                  _M('Ball%', _pct(r.pitches.ballPct)),
                  _M('AB ended', '${r.paEnd.pas}'),
                  _M('K', '${r.paEnd.k}'),
                ],
              ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: 'By batter handedness',
        what: 'The same pitch mix and results split by the batter hand stored on each pitch (L or R). '
            'The app stores R when no hand was chosen, so treat a split with very few left-handed pitches as thin data, not as proof of how you pitch to lefties.',
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
            for (final r in a.byHand)
              _Row(
                title: r.label,
                subtitle: _mixText(r.shares),
                small: r.small,
                smallText: 'n < ${SeqSampleSize.smallPitches}',
                metrics: [
                  _M('n', '${r.n}'),
                  _M('Strike%', _pct(r.pitches.strikePct)),
                  _M('Whiff%', r.pitches.swings == 0 ? '—' : _pct(r.pitches.whiffPct)),
                  _M('Ball%', _pct(r.pitches.ballPct)),
                  _M('PA ended', '${r.paEnd.pas}'),
                  _M('K%', _pct(r.paEnd.kPct)),
                  _M('BAA', r.paEnd.ab == 0 ? '—' : '${_avg(r.paEnd.baa)} (${r.paEnd.hits}/${r.paEnd.ab})'),
                ],
              ),
        ],
      ),
    ]);
  }
}
