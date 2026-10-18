import 'package:flutter/material.dart';
import '../services/sequence_scoring.dart';
import '../theme/app_theme.dart';
import 'stat_vbox.dart' show statValueFontSize;

/// "Why this score" panels for Pitch Sequencing. Everything shown here comes
/// from the engine's recorded calculations (components, samples, notes);
/// nothing is templated text that could contradict the numbers.

String _pts(double v) => v.toStringAsFixed(1);

class _CompRow extends StatelessWidget {
  final String label;
  final double nominal;
  final double? earned;
  final double? max;
  final bool limited;
  final String? note; // shown under the bar (skip reason / evaluated PAs)

  const _CompRow({
    required this.label,
    required this.nominal,
    required this.earned,
    required this.max,
    required this.limited,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final evaluated = earned != null && max != null && max! > 0;
    final frac = evaluated ? (earned! / max!).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('$label  (${nominal.round()} pts)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.colMuted)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  evaluated ? '${_pts(earned!)} / ${_pts(max!)}' : 'not evaluated',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: evaluated ? statValueFontSize(context) - 6 : 13,
                      height: 1.1,
                      color: evaluated ? AppColors.ink : AppColors.colMuted),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: AppColors.tint,
              valueColor: AlwaysStoppedAnimation(
                  evaluated ? AppColors.brandOrangeDeep : AppColors.colBorder),
            ),
          ),
          if (limited && evaluated)
            const Text('Limited confidence: small sample',
                style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
          if (note != null)
            Text(note!,
                style: const TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

Widget _noteLine(SeqPolarity p, String text, {int? count, int? of}) {
  final (prefix, color) = switch (p) {
    SeqPolarity.positive => ('Positive: ', AppColors.perfExcellent),
    SeqPolarity.review => ('Review: ', AppColors.perfPoor),
    SeqPolarity.limited => ('Limited confidence: ', AppColors.colMuted),
    SeqPolarity.neutral => ('Note: ', AppColors.colMuted),
  };
  final suffix = (count != null && of != null && of > 1) ? '  ($count of $of at-bats)' : '';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text.rich(TextSpan(children: [
      TextSpan(text: prefix, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      TextSpan(text: '$text$suffix', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.colText)),
    ]), style: const TextStyle(fontSize: 12.5, height: 1.25)),
  );
}

Widget _formulaFoot(String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text,
          style: const TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
    );

/// Breakdown for one plate appearance.
class PaBreakdown extends StatelessWidget {
  final PaScore pa;
  const PaBreakdown(this.pa, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!pa.hasScore) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(pa.unscoredReason ?? 'Not scored.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final k in SeqWeights.keys)
        _CompRow(
          label: pa.components[k]!.label,
          nominal: pa.components[k]!.nominalWeight,
          earned: pa.components[k]!.earned,
          max: pa.components[k]!.maxPoints,
          limited: pa.components[k]!.limitedConfidence,
          note: pa.components[k]!.skipReason,
        ),
      const SizedBox(height: 4),
      for (final n in pa.notes) _noteLine(n.polarity, n.text),
      _formulaFoot(
          'Points = 100 × weight × value ÷ evaluated weight (${pa.coverage.round()} of 100). '
          'Confidence: ${pa.confidence}.'
          '${pa.coverage < SeqWeights.total ? ' Missing components were dropped and the rest re-weighted, not counted as bad.' : ''}'),
    ]);
  }
}

/// Breakdown averaged over every plate appearance that opened with a sequence.
class SequenceBreakdown extends StatelessWidget {
  final Map<String, dynamic> seq;
  const SequenceBreakdown(this.seq, {super.key});

  @override
  Widget build(BuildContext context) {
    final n = seq['count'] as int;
    final comps = seq['components'] as Map<String, Map<String, dynamic>>;
    final reasons = (seq['reasons'] as List).cast<Map<String, dynamic>>();
    final reduced = seq['reducedConfidencePAs'] as int;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final k in SeqWeights.keys)
        _CompRow(
          label: comps[k]!['label'] as String,
          nominal: comps[k]!['nominal'] as double,
          earned: comps[k]!['avgEarned'] as double,
          max: comps[k]!['avgMax'] as double,
          limited: comps[k]!['limited'] as bool,
          note: (comps[k]!['evaluatedPAs'] as int) < n
              ? 'Evaluated in ${comps[k]!['evaluatedPAs']} of $n at-bats'
              : null,
        ),
      const SizedBox(height: 4),
      if (reasons.isEmpty)
        const Text('No specific flags or highlights for this sequence.',
            style: TextStyle(fontSize: 12.5, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
      for (final r in reasons.take(8))
        _noteLine(r['polarity'] as SeqPolarity, r['text'] as String, count: r['count'] as int, of: n),
      _formulaFoot(
          'Score = average of the $n at-bat score${n == 1 ? '' : 's'}; bars show average points earned / available. '
          '${reduced > 0 ? '$reduced of $n had reduced confidence (missing data or small samples).' : 'All at-bats had full component coverage.'}'),
    ]);
  }
}
