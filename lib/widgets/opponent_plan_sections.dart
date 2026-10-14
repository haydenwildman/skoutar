import 'package:flutter/material.dart';
import '../services/color_guides.dart';
import '../services/opponent_plan_service.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'glow.dart';
import 'stat_hold_info.dart';

/// Extra Scouting Report sections (takeaways, team tendencies, pitch
/// selection, lineup, hitter reports, situational plan, matchup review).
/// They are placed inside the existing Scouting Report screen — there is no
/// new tab — and reuse its cards, fonts, colors and press-and-hold info.

Color _textOn(Color bg) => (bg == AppColors.perfExcellent ||
        bg == AppColors.perfPoor ||
        bg == AppColors.perfBelowAvg)
    ? Colors.white
    : AppColors.colText;

String _p(double? v) => v == null ? '—' : '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%';
String _a(double? v) => v == null ? '—' : fmtRate3(v);
double? _share(int a, int b) => b > 0 ? (a / b * 1000).round() / 10 : null;

// ─── Small building blocks ────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _SectionCard({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) => GlowCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!,
                      style: const TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
                ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );
}

Widget _divider() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, color: AppColors.colBorder),
    );

Widget _muted(String text) =>
    Text(text, style: const TextStyle(fontSize: 12, color: AppColors.colMuted));

/// "n=6 · Low confidence" label. Press and hold explains the grading.
class _Conf extends StatelessWidget {
  final int n;
  final Confidence c;
  final String unit;
  const _Conf(this.n, this.c, {this.unit = ''});

  @override
  Widget build(BuildContext context) {
    final strong = c == Confidence.moderate || c == Confidence.solid;
    final color = c == Confidence.insufficient
        ? AppColors.colMuted
        : (strong ? AppColors.perfExcellent : AppColors.brandOrangeDeep);
    return StatHoldInfo(
      title: 'Sample size',
      description: composeHoldInfo(
        what: 'How much data sits behind this number. Small samples can look dramatic by chance, '
            'so each stat shows its sample (n) and a grade.\n\n'
            'Pitch counts (pitches or swings): under 3 = insufficient, 3-7 = low, 8-19 = moderate, 20+ = solid.\n'
            'Plate appearances / at-bats: under 2 = insufficient, 2-4 = low, 5-11 = moderate, 12+ = solid.',
        colorGuide: [
          swatchLine(AppColors.colMuted, 'Gray: insufficient data — no tendency is claimed.'),
          swatchLine(AppColors.brandOrangeDeep, 'Orange: low confidence — an early signal only.'),
          swatchLine(AppColors.perfExcellent, 'Green: moderate or solid sample.'),
        ].join('\n'),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('n=$n$unit · ${c.label}',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }
}

/// FACT / TENDENCY / SUGGESTION tag.
class _KindTag extends StatelessWidget {
  final InsightKind kind;
  const _KindTag(this.kind);

  @override
  Widget build(BuildContext context) {
    final (label, color, what) = switch (kind) {
      InsightKind.fact => ('FACT', AppColors.ink, 'Observed fact: something directly recorded in the data.'),
      InsightKind.tendency => (
          'TENDENCY',
          AppColors.brandOrangeDeep,
          'Supported tendency: a pattern that met the minimum sample size. Its confidence is shown beside it.'
        ),
      InsightKind.suggestion => (
          'SUGGESTION',
          AppColors.perfExcellent,
          'Suggested approach: an idea informed by the facts and tendencies. It is not a guaranteed outcome.'
        ),
    };
    return StatHoldInfo(
      title: label,
      description: composeHoldInfo(
        what: what,
        colorGuide: swatchLine(color, 'A fixed label color for this kind of statement; it is not a graded cutoff.'),
      ),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final Insight insight;
  const _InsightRow(this.insight);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _KindTag(insight.kind),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(insight.text, style: const TextStyle(fontSize: 12.5, height: 1.35)),
              if (insight.confidence != null && insight.kind != InsightKind.suggestion)
                Text('(${insight.confidence!.label.toLowerCase()})',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.colMuted)),
            ]),
          ),
        ]),
      );
}

/// A graded stat chip (AVG / OBP / K% …) that reuses the app's existing
/// color scale and its press-and-hold color guide.
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final String? statKey;
  final String what;
  const _StatChip(this.label, this.value, this.bg, {this.statKey, required this.what});

  @override
  Widget build(BuildContext context) {
    final guide = statKey != null
        ? statColorGuide(statKey!)
        : swatchLine(bg, 'Cream: a plain count, not a good/bad grade, so there are no cutoffs.');
    return StatHoldInfo(
      title: label,
      description: composeHoldInfo(what: what, colorGuide: guide),
      child: Container(
        constraints: const BoxConstraints(minWidth: 50),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _textOn(bg).withOpacity(0.75))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _textOn(bg))),
        ]),
      ),
    );
  }
}

Widget _lineChips(SituationLine l) => Wrap(spacing: 6, runSpacing: 6, children: [
      _StatChip('PA', '${l.pa}', AppColors.tint, what: 'Completed plate appearances in this group.'),
      _StatChip('AVG', _a(l.avg), perfHex('AVG', l.avg),
          statKey: 'AVG', what: 'Hits ÷ at-bats against you (${l.h}-for-${l.ab}).'),
      _StatChip('OBP', _a(l.obp), perfHex('OBP_allowed', l.obp),
          statKey: 'OBP_allowed', what: 'Hits + walks + hit-by-pitches ÷ plate appearances that count.'),
      _StatChip('K%', l.kPct == null ? '—' : '${l.kPct}%', perfHex('K_pct', l.kPct),
          statKey: 'K_pct', what: 'Strikeouts ÷ plate appearances (${l.k} K).'),
      _StatChip('BB%', l.bbPct == null ? '—' : '${l.bbPct}%', perfHex('BB_pct', l.bbPct),
          statKey: 'BB_pct', what: 'Walks ÷ plate appearances (${l.bb} BB).'),
    ]);

/// Pitch-type table row: type, sample, rates. Everything shows its n.
Widget _pitchRow(PitchLine l, {bool showAb = true}) {
  final type = l.type.toUpperCase();
  const color = AppColors.brandOrangeMid;
  Widget cell(String top, String bottom) => Expanded(
        child: Column(children: [
          Text(top, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          Text(bottom, style: const TextStyle(fontSize: 9.5, color: AppColors.colMuted)),
        ]),
      );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(
        width: 54,
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Flexible(child: Text(type, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5))),
        ]),
      ),
      cell('${l.n}', 'pitches'),
      cell(_p(l.strikePct), 'strike'),
      cell(_p(l.whiffPct), 'whiff (${l.swings} sw)'),
      if (showAb) cell(l.abEnded > 0 ? _a(l.avg) : '—', 'AVG (${l.hitsEnded}/${l.abEnded})'),
    ]),
  );
}

// ─── 2. Key Takeaways ─────────────────────────────────────────

class OpponentTakeaways extends StatelessWidget {
  final OpponentPlan plan;
  const OpponentTakeaways({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final seasons = plan.seasons.toList()..sort();
    final gameText = plan.games.map((g) => 'G${g.gameNumber}${seasons.length > 1 ? " (${g.season})" : ""}').join(', ');
    return _SectionCard(
      title: 'Key Takeaways',
      subtitle:
          'Based on ${plan.games.length} previous game(s) [$gameText], ${plan.teamLine.pa} completed PA'
          '${plan.incompletePas > 0 ? ", ${plan.incompletePas} incomplete PA not counted" : ""}. '
          'Only patterns that meet a minimum sample are listed.',
      children: [
        if (plan.takeaways.isEmpty)
          _muted('No takeaway met the minimum-sample rules yet. Log more at-bats against this opponent.')
        else
          for (var i = 0; i < plan.takeaways.length; i++) ...[
            if (i > 0) _divider(),
            _TakeawayTile(plan.takeaways[i], i + 1),
          ],
        if (plan.takeaways.isNotEmpty && plan.takeaways.length < 3) ...[
          const SizedBox(height: 8),
          _muted('Only ${plan.takeaways.length} takeaway(s) had enough data.'),
        ],
      ],
    );
  }
}

class _TakeawayTile extends StatelessWidget {
  final Takeaway t;
  final int n;
  const _TakeawayTile(this.t, this.n);

  @override
  Widget build(BuildContext context) {
    final color = t.concern ? AppColors.colError : AppColors.perfExcellent;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        StatHoldInfo(
          title: t.concern ? 'Potential concern' : 'Opportunity',
          description: composeHoldInfo(
            what: t.concern
                ? 'Something that has gone against the pitcher in the recorded data.'
                : 'Something that has gone in the pitcher\'s favor in the recorded data.',
            colorGuide: swatchLine(color, '${t.concern ? 'Red' : 'Green'}: a fixed label for this kind of takeaway; not a graded cutoff.'),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Text(t.concern ? 'CONCERN' : 'OPPORTUNITY',
                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('$n. ${t.title}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
      ]),
      const SizedBox(height: 6),
      _InsightRow(Insight(InsightKind.fact, t.fact)),
      _InsightRow(Insight(InsightKind.tendency, t.tendency, t.confidence)),
      _InsightRow(Insight(InsightKind.suggestion, t.suggestion)),
    ]);
  }
}

// ─── 3. Team Tendencies (swing / take / count splits) ─────────

class OpponentTeamTendencies extends StatelessWidget {
  final OpponentPlan plan;
  const OpponentTeamTendencies({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final o = plan.teamOverall;
    if (o == null || o.n == 0) {
      return _SectionCard(title: 'Team Tendencies', children: [_muted('No pitch data for this opponent yet.')]);
    }
    return _SectionCard(
      title: 'Team Tendencies',
      subtitle: 'How the lineup has handled your pitches, overall and by count. Rates show their sample.',
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          _StatChip('Swing%', _p(o.swingPct), AppColors.tint,
              what: 'Swings ÷ pitches (${o.swings} of ${o.n}).'),
          _StatChip('Whiff%', _p(o.whiffPct), perfHex('whiff_pct', o.whiffPct),
              statKey: 'whiff_pct', what: 'Swinging misses ÷ swings (${o.whiffs} of ${o.swings}).'),
          _StatChip('Foul%', _p(o.foulPct), AppColors.tint,
              what: 'Fouls ÷ swings (${o.fouls} of ${o.swings}).'),
          _StatChip('Called K%', _p(o.calledPct), AppColors.tint,
              what: 'Pitches taken for a called strike ÷ all pitches (${o.called} of ${o.n}).'),
          _StatChip('Pitches', '${o.n}', AppColors.tint, what: 'Pitches thrown to this lineup.'),
        ]),
        _divider(),
        const Text('By count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
        const SizedBox(height: 4),
        for (final b in plan.teamBuckets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: b.n == 0
                ? Text('${b.label}: no pitches recorded.', style: const TextStyle(fontSize: 12, color: AppColors.colMuted))
                : Wrap(spacing: 8, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(b.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    Text('swing ${_p(b.swingPct)} · whiff ${_p(b.whiffPct)} (${b.swings} sw) · took ${b.takes}',
                        style: const TextStyle(fontSize: 12)),
                    _Conf(b.n, b.confidence, unit: ' pitches'),
                  ]),
          ),
      ],
    );
  }
}

// ─── 4. Pitch Selection Strategy ──────────────────────────────

class OpponentPitchStrategy extends StatelessWidget {
  final OpponentPlan plan;
  const OpponentPitchStrategy({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final lines = plan.teamPitchLines;
    final total = lines.fold<int>(0, (a, l) => a + l.n);
    if (lines.isEmpty) {
      return _SectionCard(title: 'Pitch Selection Strategy', children: [_muted('No pitch data for this opponent yet.')]);
    }
    return _SectionCard(
      title: 'Pitch Selection Strategy',
      subtitle: 'Results are credited only to the pitch that ended the at-bat. No velocity, movement or location is used.',
      children: [
        for (final l in lines) ...[
          _pitchRow(l),
          Padding(
            padding: const EdgeInsets.only(left: 54, bottom: 2),
            child: Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('usage ${_p(_share(l.n, total))} · K ${l.kEnded} · XBH ${l.xbhEnded} · '
                  'in-play outs ${l.bipOuts}, hits ${l.bipHits}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.colMuted)),
              _Conf(l.n, l.pitchConf, unit: ' pitches'),
            ]),
          ),
        ],
        _divider(),
        const Text('What each pitch has done by count',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
        const SizedBox(height: 4),
        for (final b in bucketOrder) _bucketBlock(b),
        _divider(),
        _muted('Sequences that worked or were hit hard are listed under "What Works vs This Team" and '
            '"What Gets Hit" above. A pitch is not graded bad for one hit or good for one out; the '
            'sample is shown so you can judge.'),
      ],
    );
  }

  Widget _bucketBlock(String b) {
    final lines = (plan.pitchLinesByBucket[b] ?? const <PitchLine>[]).where((l) => l.n >= 3).toList();
    final metricIsWhiff = b == 'two';
    lines.sort((x, y) {
      final xv = (metricIsWhiff ? x.whiffPct : x.strikePct) ?? -1;
      final yv = (metricIsWhiff ? y.whiffPct : y.strikePct) ?? -1;
      return yv.compareTo(xv);
    });
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(bucketLabels[b]!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        if (lines.isEmpty)
          _muted('Not enough pitches of any one type here (need 3+).')
        else
          Wrap(spacing: 10, runSpacing: 4, children: [
            for (final l in lines)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    '${l.type.toUpperCase()} ${metricIsWhiff ? 'whiff ${_p(l.whiffPct)} (${l.swings} sw)' : 'strike ${_p(l.strikePct)}'} · ${l.n}',
                    style: const TextStyle(fontSize: 11.5)),
                const SizedBox(width: 4),
                Text('(${l.pitchConf.label.toLowerCase()})',
                    style: const TextStyle(fontSize: 10, color: AppColors.colMuted)),
              ]),
          ]),
      ]),
    );
  }
}

// ─── 5. Lineup Breakdown ──────────────────────────────────────

class OpponentLineupBreakdown extends StatelessWidget {
  final OpponentPlan plan;
  const OpponentLineupBreakdown({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Lineup Breakdown',
      subtitle: plan.orderKnown
          ? 'In batting order. Tap a hitter to open the full scouting card.'
          : 'Batting order is not recorded for this opponent, so hitters are listed by plate appearances. Tap a hitter to open the full card.',
      children: [
        if (plan.hitters.isEmpty)
          _muted('No hitters with a jersey number recorded yet.')
        else if (plan.orderKnown)
          for (final seg in plan.segments) ...[
            Text(seg.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 2),
            Text(seg.summary, style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
            const SizedBox(height: 4),
            for (final h in seg.hitters) _lineupRow(context, h),
            _divider(),
          ]
        else
          for (final h in plan.hitters) _lineupRow(context, h),
        if (plan.unknownHitterPas > 0)
          _muted('${plan.unknownHitterPas} plate appearance(s) have no jersey number and are not tied to a hitter.'),
      ],
    );
  }

  Widget _lineupRow(BuildContext context, HitterReport h) {
    final l = h.line;
    return InkWell(
      onTap: () => showHitterSheet(context, h),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.ink,
            child: Text('#${h.jersey}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${plan.orderKnown && h.order != null ? "Spot ${h.order} · " : ""}${h.hand == null ? "bats ?" : "bats ${h.hand}"} · '
                '${l.h}-for-${l.ab}, ${l.k} K, ${l.bb} BB in ${l.pa} PA',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(h.approach, style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
              const SizedBox(height: 3),
              _Conf(l.pa, l.confidence, unit: ' PA'),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.colMuted),
        ]),
      ),
    );
  }
}

void showHitterSheet(BuildContext context, HitterReport h) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.pageBg,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(12),
        children: [HitterCard(report: h, startExpanded: true)],
      ),
    ),
  );
}

// ─── 6. Individual Hitter Reports ─────────────────────────────

class OpponentHitterReports extends StatelessWidget {
  final OpponentPlan plan;
  const OpponentHitterReports({super.key, required this.plan});

  @override
  Widget build(BuildContext context) => _SectionCard(
        title: 'Individual Hitter Reports',
        subtitle: 'Every hitter on file. Expand a hitter for pitch-by-pitch-type and count detail.',
        children: [
          if (plan.hitters.isEmpty)
            _muted('No hitters with a jersey number recorded yet.')
          else
            for (final h in plan.hitters) HitterCard(report: h),
        ],
      );
}

class HitterCard extends StatelessWidget {
  final HitterReport report;
  final bool startExpanded;
  const HitterCard({super.key, required this.report, this.startExpanded = false});

  @override
  Widget build(BuildContext context) {
    final h = report;
    final l = h.line;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.tint, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: startExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Row(children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.ink,
              child: Text('#${h.jersey}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${h.hand == null ? "Bats not recorded" : (h.hand == "L" ? "Bats L" : "Bats R")}'
                '${h.order != null && h.order! > 0 ? " · spot ${h.order}" : ""}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 8, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${l.h}-for-${l.ab}, ${l.k} K, ${l.bb} BB · ${l.pa} PA',
                  style: const TextStyle(fontSize: 11.5)),
              _Conf(l.pa, l.confidence, unit: ' PA'),
            ]),
          ),
          children: [
            _lineChips(l),
            _divider(),
            const Text('Summary', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
            const SizedBox(height: 4),
            for (final i in h.insights) _InsightRow(i),
            _divider(),
            const Text('By pitch type', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
            const SizedBox(height: 2),
            if (h.pitchLines.isEmpty)
              _muted('No pitches recorded.')
            else
              for (final p in h.pitchLines) ...[
                _pitchRow(p),
                Padding(
                  padding: const EdgeInsets.only(left: 54, bottom: 2),
                  child: Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('called strikes ${p.called} · swing ${_p(p.swingPct)} · in-play outs ${p.bipOuts}, hits ${p.bipHits}',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.colMuted)),
                    _Conf(p.n, p.pitchConf, unit: ' pitches'),
                  ]),
                ),
              ],
            _divider(),
            const Text('By count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
            const SizedBox(height: 2),
            for (final b in h.bucketLines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: b.n == 0
                    ? Text('${b.label}: no pitches.', style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted))
                    : Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(b.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        Text('swing ${_p(b.swingPct)} (${b.swings}/${b.n}) · whiff ${_p(b.whiffPct)}',
                            style: const TextStyle(fontSize: 11.5)),
                        _Conf(b.n, b.confidence, unit: ' pitches'),
                      ]),
              ),
            const SizedBox(height: 4),
            Text(
              'Reached two strikes in ${h.reachedTwoStrikes.pa} PA (${h.reachedTwoStrikes.k} K) · '
              "reached a hitter's count in ${h.reachedHitterCount.pa} PA "
              '(${h.reachedHitterCount.h + h.reachedHitterCount.bb + h.reachedHitterCount.hbp} on base).',
              style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted),
            ),
            _divider(),
            const Text('Plate appearances', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
            const SizedBox(height: 4),
            for (final pa in h.pas) PaSequenceTile(pa: pa, showHitter: false),
          ],
        ),
      ),
    );
  }
}

// ─── 7. Situational Game Plan ─────────────────────────────────

class OpponentSituational extends StatelessWidget {
  final OpponentPlan plan;
  const OpponentSituational({super.key, required this.plan});

  Widget _sit(SituationLine l, {String? note}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (l.pa == 0)
            _muted('Unknown — no completed plate appearances in this situation.')
          else ...[
            _lineChips(l),
            const SizedBox(height: 4),
            _Conf(l.pa, l.confidence, unit: ' PA'),
          ],
          if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: _muted(note)),
        ]),
      );

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final s = plan.situational;
    const notTracked =
        'Unknown — SKOUTAR does not record base runners, so this split cannot be calculated. Nothing is estimated.';
    return _SectionCard(
      title: 'Situational Game Plan',
      subtitle: 'Only situations the recorded data can support. Anything else says "unknown".',
      children: [
        _head('Bases empty / runners on / runners in scoring position'),
        _muted(notTracked),
        _divider(),
        _head('Two outs'),
        if (s.twoOutsKnownPas == 0)
          _muted('Unknown — the out count before each plate appearance could not be determined from the logged games.')
        else
          _sit(s.twoOuts,
              note: 'Out counts were readable for ${s.twoOutsKnownPas} completed PA. Plate appearances from games without out data are left out.'),
        _divider(),
        _head('Pitcher ahead in the count'),
        _sit(s.pitcherAhead,
            note: 'Plate appearances where you reached two strikes before two balls (same definition as Count & Approach).'),
        if (s.twoStrikeTypes.where((l) => l.n >= 3).isNotEmpty) ...[
          const Text('Pitches at two strikes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
          for (final l in s.twoStrikeTypes.where((l) => l.n >= 3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${l.type.toUpperCase()}: whiff ${_p(l.whiffPct)} (${l.swings} sw) · K ${l.kEnded} · hits allowed ${l.hitsEnded}',
                    style: const TextStyle(fontSize: 12)),
                _Conf(l.n, l.pitchConf, unit: ' pitches'),
              ]),
            ),
        ],
        _divider(),
        _head('Pitcher behind in the count'),
        _sit(s.pitcherBehind,
            note: 'Plate appearances where the count reached two balls before two strikes.'),
        if (s.hitterCountTypes.where((l) => l.n >= 3).isNotEmpty) ...[
          const Text("Pitches thrown in hitter's counts (strikes to get back in the count)",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
          for (final l in s.hitterCountTypes.where((l) => l.n >= 3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${l.type.toUpperCase()}: strike ${_p(l.strikePct)} · hits allowed ${l.hitsEnded}',
                    style: const TextStyle(fontSize: 12)),
                _Conf(l.n, l.pitchConf, unit: ' pitches'),
              ]),
            ),
        ],
        if (s.hitterCountDamage.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Hitters who reached base after getting to a hitter\'s count (2+ times)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
          for (final h in s.hitterCountDamage)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: InkWell(
                onTap: () => showHitterSheet(context, h),
                child: Text('#${h.jersey}: ${h.reachedHitterCount.h + h.reachedHitterCount.bb + h.reachedHitterCount.hbp} on base in ${h.reachedHitterCount.pa} PA that reached a hitter\'s count',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ],
    );
  }
}

// ─── 8. Previous Matchup Review ───────────────────────────────

class OpponentMatchupReview extends StatelessWidget {
  final OpponentPlan plan;
  const OpponentMatchupReview({super.key, required this.plan});

  Widget _bullets(String title, List<String> items, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
          const SizedBox(height: 2),
          if (items.isEmpty)
            _muted('Nothing met the minimum sample yet.')
          else
            for (final t in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $t', style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final r = plan.review;
    return _SectionCard(
      title: 'Previous Matchup Review',
      subtitle: 'What happened, in order. Pitch results and at-bat results are kept separate.',
      children: [
        ResponsiveRow(crossAxisAlignment: CrossAxisAlignment.start, stackedGap: 10, children: [
          Expanded(child: _bullets('What worked', r.worked, AppColors.perfExcellent)),
          const SizedBox(width: 12),
          Expanded(child: _bullets("What didn't", r.didNotWork, AppColors.colError)),
        ]),
        _divider(),
        const Text('Did hitters respond differently as the game went on?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 4),
        for (final l in r.timesThrough)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${l.label}: ${l.pa == 0 ? "no data" : "${l.h}-for-${l.ab}, OBP ${_a(l.obp)}, ${l.k} K"}',
                  style: const TextStyle(fontSize: 12)),
              _Conf(l.pa, l.confidence, unit: ' PA'),
            ]),
          ),
        const SizedBox(height: 2),
        _muted(r.timesThroughNote),
        _divider(),
        const Text('Game by game', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 4),
        for (final g in r.games) _GameTile(g),
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  final GameReview g;
  const _GameTile(this.g);

  @override
  Widget build(BuildContext context) {
    final l = g.line;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.colBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text('Game ${g.gameNumber} (${g.season})',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          subtitle: Text('${l.h}-for-${l.ab}, ${l.k} K, ${l.bb} BB in ${l.pa} PA · ${g.pas.length - l.pa} incomplete',
              style: const TextStyle(fontSize: 11.5)),
          children: [for (final pa in g.pas) PaSequenceTile(pa: pa, showHitter: true)],
        ),
      ),
    );
  }
}

/// One plate appearance: each pitch with its count and call, then the
/// at-bat result shown once, separately.
class PaSequenceTile extends StatelessWidget {
  final PaRecord pa;
  final bool showHitter;
  const PaSequenceTile({super.key, required this.pa, required this.showHitter});

  @override
  Widget build(BuildContext context) {
    final res = pa.result;
    final head = StringBuffer();
    if (showHitter) head.write('#${pa.jersey ?? "?"} · ');
    if (!showHitter) head.write('G${pa.gameNumber} · ');
    if (pa.inning != null) head.write('Inn ${pa.inning} · ');
    head.write(res == null ? 'No result recorded' : outcomeLabel(res.event.outcome));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(head.toString(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        if (pa.steps.isEmpty)
          _muted('No pitches recorded.')
        else
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final s in pa.steps)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.tint,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.brandOrangeSoft, width: 1.4),
                ),
                child: Text('${s.count}  ${s.type.toUpperCase()} · ${callLabel(s.e.call)}',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
              ),
          ]),
      ]),
    );
  }
}
