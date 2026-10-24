import 'package:flutter/material.dart';
import '../services/scouting_game_plan.dart';
import '../services/scouting_report_data.dart';
import '../theme/app_theme.dart';
import 'glow.dart';

/// New sections of the (existing) Scouting Report: overview, key takeaways,
/// team tendencies, pitch selection strategy, lineup breakdown, individual
/// hitter reports, situational plan and previous matchup review.
///
/// Every statement is tagged as an OBSERVED FACT, a SUPPORTED TENDENCY or a
/// SUGGESTED APPROACH, with sample sizes and a confidence label.

const _muted = TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic);

// ───────────────────────── shared pieces ─────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;
  const _Section({required this.title, this.subtitle, required this.children, this.initiallyExpanded = true});

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          subtitle: subtitle == null ? null : Text(subtitle!, style: _muted),
          children: children,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String tag;
  const _Tag(this.tag);
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tag) {
      'Observed fact' => (AppColors.tint, AppColors.ink),
      'Supported tendency' => (const Color(0xFFF0FDF4), AppColors.perfExcellent),
      _ => (const Color(0xFFFFF4EC), AppColors.brandOrangeDeep),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: fg.withOpacity(0.5))),
      child: Text(tag, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class _ConfChip extends StatelessWidget {
  final Conf conf;
  final String? sample;
  const _ConfChip(this.conf, {this.sample});
  @override
  Widget build(BuildContext context) {
    final color = switch (conf) {
      Conf.good => AppColors.perfExcellent,
      Conf.moderate => AppColors.colText,
      Conf.low => AppColors.perfPoor,
      Conf.insufficient => AppColors.colMuted,
    };
    return Text('${confLabel(conf)}${sample != null ? '  •  $sample' : ''}',
        style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: color));
  }
}

Widget _labeled(String tag, String text, {Conf? conf}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_Tag(tag), if (conf != null) ...[const SizedBox(width: 6), _ConfChip(conf)]]),
        const SizedBox(height: 2),
        Text(text, style: const TextStyle(fontSize: 12.5, height: 1.25)),
      ]),
    );

Widget _h(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
    );

Widget _cell(String t, {bool bold = false, bool muted = false, TextAlign align = TextAlign.center}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Text(t,
          textAlign: align,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: muted ? AppColors.colMuted : AppColors.colText,
              fontStyle: muted ? FontStyle.italic : FontStyle.normal)),
    );

Widget _table(List<String> headers, List<List<Widget>> rows, {List<double>? flex}) {
  final f = flex ?? List.filled(headers.length, 1.0);
  return Table(
    border: TableBorder.all(color: AppColors.colBorder),
    columnWidths: {for (var i = 0; i < f.length; i++) i: FlexColumnWidth(f[i])},
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
          decoration: const BoxDecoration(color: AppColors.ink),
          children: [
            for (var i = 0; i < headers.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                child: Text(headers[i],
                    textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ]),
      for (final r in rows) TableRow(children: r),
    ],
  );
}

/// Cards in two columns (1 and 2 on the first row, 3 and 4 under them, ...) when
/// the section is at least [minWidth] wide, otherwise stacked in one column.
///
/// Each card sizes to its own content: the columns use start alignment (never
/// stretch), because this sits inside the app shell's vertical scroll view
/// whose height is unbounded, and cards should not be stretched taller than
/// their text anyway. The gap between columns equals the gap between cards.
Widget _twoUp(List<Widget> cards, {double minWidth = 720}) => LayoutBuilder(builder: (context, c) {
      if (cards.length < 2 || c.maxWidth < minWidth) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < cards.length; i += 2) cards[i],
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 1; i < cards.length; i += 2) cards[i],
            ]),
          ),
        ],
      );
    });

/// "37%" plus the sample in brackets; greyed out when below the minimum.
Widget _rate(double? v, int n, int min) {
  if (v == null || n == 0) return _cell('—', muted: true);
  return _cell('${(v * 100).round()}% ($n)', muted: n < min);
}

String _line(int h, int ab) => '$h-for-$ab';
String _typeName(String t) => t.toUpperCase();

// ───────────────────────── 1. Game overview extras ─────────────────────────

class PlanOverviewCard extends StatelessWidget {
  final ScoutingReportData r;
  const PlanOverviewCard(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final plan = r.plan;
    final dang = plan.dangerous.map((m) => m['h'] as HitterReport).toList();
    final strug = plan.struggled.map((m) => m['h'] as HitterReport).toList();
    return _Section(
      title: 'Game Overview',
      subtitle: '${plan.team}  •  ${plan.games.length} previous matchup${plan.games.length == 1 ? '' : 's'}',
      children: [
        _h('Previous games'),
        if (plan.games.isEmpty)
          const Text('No completed plate appearances recorded.', style: _muted)
        else
          _table(
            ['Game', 'PA', 'H-AB', 'BB', 'K', 'ER'],
            [
              for (final g in plan.games)
                [
                  _cell('G${g.gameNumber} (${g.season})', align: TextAlign.left),
                  _cell('${g.pa}'),
                  _cell('${g.hits}-${g.ab}'),
                  _cell('${g.bb}'),
                  _cell('${g.ks}'),
                  _cell(g.er == g.er.roundToDouble() ? '${g.er.round()}' : g.er.toStringAsFixed(1)),
                ],
            ],
            flex: const [2.2, 1, 1.4, 1, 1, 1],
          ),
        _h('Most dangerous hitters (by OBP, 2+ PA)'),
        if (dang.isEmpty)
          const Text('Not enough plate appearances to rank hitters yet.', style: _muted)
        else
          for (final h in dang)
            _labeled('Observed fact',
                '#${h.jersey}: ${_line(h.hits, h.ab)}, ${h.bb} BB, ${h.ks} K in ${h.pa} PA (OBP ${fmtAvg3(h.obp)}).',
                conf: confFor(h.pa, 2, 6)),
        _h('Hitters who have struggled against you (hitless, 2+ PA)'),
        if (strug.isEmpty)
          const Text('No hitless hitters with 2+ plate appearances.', style: _muted)
        else
          for (final h in strug)
            _labeled('Observed fact', '#${h.jersey}: ${_line(h.hits, h.ab)}, ${h.bb} BB, ${h.ks} K in ${h.pa} PA.',
                conf: confFor(h.pa, 2, 6)),
        _h('Your best and worst pitch types vs this team'),
        ..._bestWorst(plan),
        if (plan.unknownJerseyPa > 0 || plan.incompletePa > 0) ...[
          _h('Data notes'),
          if (plan.unknownJerseyPa > 0)
            Text('${plan.unknownJerseyPa} plate appearance${plan.unknownJerseyPa == 1 ? '' : 's'} have no batter jersey # '
                'and count in team totals but not in individual hitter cards.',
                style: _muted),
          if (plan.incompletePa > 0)
            Text('${plan.incompletePa} unfinished at-bat${plan.incompletePa == 1 ? '' : 's'} are excluded from results.',
                style: _muted),
        ],
      ],
    );
  }

  List<Widget> _bestWorst(ScoutingGamePlan plan) {
    final byWhiff = plan.teamTypes.where((t) => t.swings >= GpConfig.minSwings).toList()
      ..sort((a, b) => (b.whiffPct ?? 0).compareTo(a.whiffPct ?? 0));
    final byBaa = plan.teamTypes.where((t) => t.ab >= GpConfig.minAb).toList()
      ..sort((a, b) => (b.baa ?? 0).compareTo(a.baa ?? 0));
    final out = <Widget>[];
    if (byWhiff.isNotEmpty) {
      final t = byWhiff.first;
      out.add(_labeled('Observed fact',
          'Most swings and misses: ${_typeName(t.type)} (${t.whiffs} of ${t.swings} swings, ${pctText(t.whiffPct)}).',
          conf: confFor(t.swings, GpConfig.minSwings, GpConfig.goodSwings)));
    }
    if (byBaa.isNotEmpty) {
      final best = byBaa.last, worst = byBaa.first;
      out.add(_labeled('Observed fact',
          'Most hit: ${_typeName(worst.type)} (${_line(worst.hits, worst.ab)} in at-bats it ended, ${fmtAvg3(worst.baa)}). '
          'Least hit: ${_typeName(best.type)} (${_line(best.hits, best.ab)}, ${fmtAvg3(best.baa)}).',
          conf: confFor(worst.ab < best.ab ? worst.ab : best.ab, GpConfig.minAb, GpConfig.goodAb)));
    }
    if (out.isEmpty) out.add(const Text('Not enough recorded pitches to rank pitch types.', style: _muted));
    return out;
  }
}

// ───────────────────────── 2. Key takeaways ─────────────────────────

class KeyTakeawaysCard extends StatelessWidget {
  final ScoutingGamePlan plan;
  const KeyTakeawaysCard(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    final ts = plan.takeaways;
    return _Section(
      title: 'Key Takeaways',
      subtitle: 'Only shown when the recorded data supports them',
      children: [
        if (ts.isEmpty)
          const Text('Not enough data yet to generate takeaways for this opponent.', style: _muted)
        else ...[
          // Two columns on wide screens (numbered 1, 2 across, then down),
          // one stacked column on narrow ones. Nothing is dropped or reordered.
          _twoUp([for (var i = 0; i < ts.length; i++) _takeaway(i + 1, ts[i])]),
          if (ts.length < 3)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Fewer than three takeaways are supported by the data so far - more games will unlock more.', style: _muted),
            ),
        ],
      ],
    );
  }

  Widget _takeaway(int n, Takeaway t) {
    final color = switch (t.kind) {
      'concern' => AppColors.perfPoor,
      'strength' => AppColors.perfExcellent,
      _ => AppColors.brandOrangeDeep,
    };
    final label = switch (t.kind) {
      'concern' => 'Potential concern',
      'strength' => 'Strength',
      _ => 'Pattern',
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n.  $label: ${t.headline}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: color)),
        const SizedBox(height: 2),
        _ConfChip(t.conf, sample: t.sample),
        _labeled('Observed fact', t.fact),
        if (t.tendency != null) _labeled('Supported tendency', t.tendency!),
        _labeled('Suggested approach', t.suggestion),
      ]),
    );
  }
}

// ───────────────────────── 3. Team tendencies ─────────────────────────

class TeamTendenciesCard extends StatelessWidget {
  final ScoutingGamePlan plan;
  const TeamTendenciesCard(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    final types = plan.teamTypes;
    return _Section(
      title: 'Team Tendencies',
      subtitle: 'Counts in brackets are sample sizes; grey = too small to read much into',
      children: [
        _h('By pitch type'),
        if (types.isEmpty)
          const Text('No pitches recorded.', style: _muted)
        else
          _table(
            ['Pitch', 'Seen', 'Swing', 'Whiff', 'Called K', 'BAA (AB)'],
            [
              for (final t in types)
                [
                  _cell(_typeName(t.type), bold: true, align: TextAlign.left),
                  _cell('${t.pitches}', muted: t.pitches < GpConfig.minPitches),
                  _rate(t.swingPct, t.pitches, GpConfig.minPitches),
                  _rate(t.whiffPct, t.swings, GpConfig.minSwings),
                  _rate(t.calledPct, t.pitches, GpConfig.minPitches),
                  _cell(t.ab == 0 ? '—' : '${fmtAvg3(t.baa)} (${t.ab})', muted: t.ab < GpConfig.minAb),
                ],
            ],
            flex: const [1.2, 0.9, 1.5, 1.5, 1.5, 1.6],
          ),
        const Text('BAA counts only at-bats that the pitch type ENDED; earlier pitches are not credited.', style: _muted),
        _h('By count'),
        _table(
          ['Count type', 'Pitches', 'Swing', 'Whiff', 'PAs ended: H-AB / K / BB'],
          [
            for (final b in plan.teamCounts)
              [
                _cell(b.label, bold: true, align: TextAlign.left),
                _cell('${b.pitches}', muted: b.pitches < GpConfig.minPitches),
                _rate(b.swingPct, b.pitches, GpConfig.minPitches),
                _rate(b.whiffPct, b.swings, GpConfig.minSwings),
                _cell('${b.hits}-${b.ab} / ${b.ks} / ${b.bb}  (${b.paEnded})', muted: b.paEnded < GpConfig.minAb),
              ],
          ],
          flex: const [1.6, 1, 1.4, 1.4, 2.4],
        ),
        Text(
            plan.teamCounts.map((b) => '${b.label}: ${b.detail}').join('   |   '),
            style: _muted),
        _h('Takeaways from these tables'),
        ..._notes(plan),
      ],
    );
  }

  List<Widget> _notes(ScoutingGamePlan plan) {
    final out = <Widget>[];
    final first = plan.teamCounts.firstWhere((b) => b.key == 'first');
    if (first.pitches >= GpConfig.minPitches) {
      final c = confFor(first.pitches, GpConfig.minPitches, GpConfig.goodPitches);
      out.add(_labeled('Observed fact',
          'On the first pitch this lineup swung at ${first.swings} of ${first.pitches} (${pctText(first.swingPct)}) '
          'and took ${first.called} for a called strike.',
          conf: c));
    }
    final two = plan.teamCounts.firstWhere((b) => b.key == 'two');
    if (two.pitches >= GpConfig.minPitches) {
      final c = confFor(two.pitches, GpConfig.minPitches, GpConfig.goodPitches);
      out.add(_labeled(c == Conf.good || c == Conf.moderate ? 'Supported tendency' : 'Observed fact',
          'With two strikes: ${two.whiffs} misses in ${two.swings} swings (${pctText(two.whiffPct)}); '
          'PAs ended there went ${two.hits}-for-${two.ab} with ${two.ks} K and ${two.bb} BB.',
          conf: c));
    }
    if (out.isEmpty) out.add(const Text('Not enough pitches in these counts to describe tendencies.', style: _muted));
    return out;
  }
}

// ───────────────────────── 4. Pitch selection strategy ─────────────────────────

class PitchStrategyCard extends StatelessWidget {
  final ScoutingReportData r;
  const PitchStrategyCard(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final plan = r.plan;
    final total = plan.teamTypes.fold<int>(0, (a, t) => a + t.pitches);
    final kEnders = plan.teamTypes.where((t) => t.ks > 0).toList()..sort((a, b) => b.ks.compareTo(a.ks));
    final dmg = plan.teamTypes.where((t) => t.xbh > 0).toList()..sort((a, b) => b.xbh.compareTo(a.xbh));
    return _Section(
      title: 'Pitch Selection Strategy',
      subtitle: 'Pitch type, count and recorded outcome only - no velocity, movement or location',
      initiallyExpanded: false,
      children: [
        _h('Usage and effectiveness'),
        if (plan.teamTypes.isEmpty)
          const Text('No pitches recorded.', style: _muted)
        else
          _table(
            ['Pitch', 'Usage', 'Whiff', 'Strike%', 'H-AB', 'K'],
            [
              for (final t in plan.teamTypes)
                [
                  _cell(_typeName(t.type), bold: true, align: TextAlign.left),
                  _cell('${total > 0 ? (t.pitches / total * 100).round() : 0}% (${t.pitches})'),
                  _rate(t.whiffPct, t.swings, GpConfig.minSwings),
                  _rate(t.strikePct, t.pitches, GpConfig.minPitches),
                  _cell(t.ab == 0 ? '—' : '${t.hits}-${t.ab}', muted: t.ab < GpConfig.minAb),
                  _cell('${t.ks}'),
                ],
            ],
            flex: const [1.2, 1.5, 1.5, 1.5, 1, 0.8],
          ),
        const Text('H-AB and K count only at-bats the pitch type ENDED.', style: _muted),
        _h('What has finished at-bats'),
        if (kEnders.isEmpty)
          const Text('No strikeouts recorded yet.', style: _muted)
        else
          _labeled('Observed fact',
              'Strikeouts ended on: ${kEnders.map((t) => '${_typeName(t.type)} (${t.ks})').join(', ')}.'),
        _h('Damaging contact'),
        if (dmg.isEmpty)
          const Text('No extra-base hits recorded.', style: _muted)
        else
          _labeled('Observed fact',
              'Extra-base hits came on at-bats ended by: ${dmg.map((t) => '${_typeName(t.type)} (${t.xbh})').join(', ')}. '
              'One hit does not make a pitch bad - check the count and the sequence before changing the plan.'),
        _h('Getting back into the count'),
        if (plan.recoveryPitches.isEmpty)
          const Text('Not enough pitches thrown in hitter\'s counts (2-0, 3-0, 3-1) to compare.', style: _muted)
        else
          for (final m in plan.recoveryPitches.take(3))
            _labeled(
                (m['n'] as int) >= GpConfig.goodPitches ? 'Supported tendency' : 'Observed fact',
                '${_typeName(m['type'] as String)} was a strike ${m['strikes']} of ${m['n']} times in hitter\'s counts '
                '(${((m['pct'] as double) * 100).round()}%).',
                conf: m['conf'] as Conf),
        _h('Pitch types in pitcher-ahead counts'),
        ..._aheadTypes(plan),
        _h('Sequences that have worked'),
        if (r.bestSeqs.where((s) => (s['count'] as int) >= GpConfig.minSeq && (s['score'] as double) >= 60).isEmpty)
          const Text('No opening sequence has been repeated enough yet to call it reliable.', style: _muted)
        else
          for (final s in r.bestSeqs.where((s) => (s['count'] as int) >= GpConfig.minSeq && (s['score'] as double) >= 60).take(3))
            _labeled('Observed fact',
                '${s['seq']}: Pitch Sequencing score ${s['score']} across ${s['count']} at-bats.',
                conf: confFor(s['count'] as int, GpConfig.minSeq, 5)),
        _h('Patterns flagged for review'),
        if (plan.patterns.isEmpty)
          const Text('No repeated ineffective or predictable pattern was found (needs the same flag in 2+ at-bats).', style: _muted)
        else
          for (final p in plan.patterns.take(4)) _labeled('Observed fact', '${p['text']}  (in ${p['n']} at-bats)', conf: Conf.low),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              'Flagged patterns are for review only: without location or intended-pitch data SKOUTAR cannot tell a poor decision from a missed spot.',
              style: _muted),
        ),
      ],
    );
  }

  List<Widget> _aheadTypes(ScoutingGamePlan plan) {
    final m = <String, List<int>>{}; // type -> [pitches, swings, whiffs]
    for (final ab in plan.atBats) {
      for (final p in ab.pitches) {
        final parts = p.count.split('-');
        final b = int.parse(parts[0]), s = int.parse(parts[1]);
        if (s == 0 && b == 0) continue;
        // pitcher-ahead counts: 0-1, 0-2, 1-2
        if (!((b == 0 && s >= 1) || (b == 1 && s == 2))) continue;
        final l = m.putIfAbsent(p.type, () => [0, 0, 0]);
        l[0]++;
        if (p.call == 'ss' || p.call == 'f' || p.call == 'ip') l[1]++;
        if (p.call == 'ss') l[2]++;
      }
    }
    final rows = m.entries.where((e) => e.value[0] >= GpConfig.minPitches).toList()
      ..sort((a, b) => b.value[2].compareTo(a.value[2]));
    if (rows.isEmpty) return [const Text('Not enough pitches in these counts to compare pitch types.', style: _muted)];
    return [
      for (final e in rows.take(3))
        _labeled(e.value[0] >= GpConfig.goodPitches ? 'Supported tendency' : 'Observed fact',
            '${_typeName(e.key)}: ${e.value[2]} swinging strikes in ${e.value[1]} swings out of ${e.value[0]} pitches when you were ahead.',
            conf: confFor(e.value[0], GpConfig.minPitches, GpConfig.goodPitches)),
    ];
  }
}

// ───────────────────────── 5. Lineup breakdown ─────────────────────────

class LineupBreakdownCard extends StatelessWidget {
  final ScoutingGamePlan plan;
  const LineupBreakdownCard(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Lineup Breakdown',
      subtitle: plan.lineupOrderKnown ? 'In batting order, from the logged lineup spots' : 'Batting order not recorded - sorted by plate appearances',
      initiallyExpanded: false,
      children: [
        if (plan.hitters.isEmpty)
          const Text('No hitters with a recorded jersey #.', style: _muted),
        if (plan.lineupOrderKnown)
          for (final g in plan.lineupGroups) ...[
            _h('${g.label} (${g.slots})'),
            _labeled('Observed fact', g.summary, conf: g.conf),
          ],
        _h('Hitter by hitter'),
        for (final h in plan.hitters) _row(context, h),
      ],
    );
  }

  Widget _row(BuildContext context, HitterReport h) {
    final conf = confFor(h.pa, 2, 6);
    final approach = h.notes.firstWhere(
      (n) => n.label == 'Suggested approach' || n.label == 'Watch for',
      orElse: () => h.notes.firstWhere((n) => n.label == 'Strength',
          orElse: () => h.notes.firstWhere((n) => n.label == 'Potential weakness', orElse: () => h.notes.first)),
    );
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                HitterReportBody(h),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close'))),
              ]),
            ),
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.colBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(10)),
              child: Text('${h.battingOrder != null ? '${h.battingOrder}.  ' : ''}#${h.jersey}',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${_line(h.hits, h.ab)}  •  ${h.bb} BB  •  ${h.ks} K  •  ${h.pa} PA',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
            const Icon(Icons.open_in_new, size: 14, color: AppColors.colMuted),
          ]),
          const SizedBox(height: 3),
          Text(approach.text, style: const TextStyle(fontSize: 12, height: 1.2)),
          const SizedBox(height: 2),
          Row(children: [_Tag(approach.tag), const SizedBox(width: 6), _ConfChip(conf == Conf.insufficient ? Conf.insufficient : approach.conf)]),
        ]),
      ),
    );
  }
}

// ───────────────────────── 6. Individual hitter reports ─────────────────────────

class HitterReportsCard extends StatelessWidget {
  final ScoutingGamePlan plan;
  const HitterReportsCard(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Individual Hitter Reports',
      subtitle: '${plan.hitters.length} hitter${plan.hitters.length == 1 ? '' : 's'} - tap one to expand',
      initiallyExpanded: false,
      children: [
        if (plan.hitters.isEmpty) const Text('No hitters with a recorded jersey #.', style: _muted),
        for (final h in plan.hitters)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 10),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(
                  '${h.battingOrder != null ? '${h.battingOrder}.  ' : ''}#${h.jersey}'
                  '${h.hand != null ? '  (${h.hand})' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              subtitle: Text(
                  '${_line(h.hits, h.ab)}, ${h.bb} BB, ${h.ks} K  •  ${h.pa} PA  •  AVG ${fmtAvg3(h.avg)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.colMuted)),
              children: [HitterReportBody(h)],
            ),
          ),
      ],
    );
  }
}

/// The full scouting card for one hitter (used inline and in the dialog).
class HitterReportBody extends StatelessWidget {
  final HitterReport h;
  const HitterReportBody(this.h, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          'Batter #${h.jersey}'
          '${h.hand != null ? '  •  Bats: ${h.hand}' : '  •  Batting side not recorded'}'
          '${h.battingOrder != null ? '  •  Lineup spot ${h.battingOrder}' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      const SizedBox(height: 2),
      Text(
          '${h.pa} PA over ${h.games} game${h.games == 1 ? '' : 's'}: ${_line(h.hits, h.ab)}, ${h.bb} BB, ${h.hbp} HBP, ${h.ks} K'
          '${h.xbh > 0 ? ', ${h.xbh} XBH' : ''}  •  AVG ${fmtAvg3(h.avg)}  •  OBP ${fmtAvg3(h.obp)}',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      _h('Scouting summary'),
      for (final n in h.notes) _noteRow(n),
      _h('By pitch type (sample size in brackets)'),
      if (h.byType.isEmpty)
        const Text('No pitches recorded.', style: _muted)
      else
        _table(
          ['Pitch', 'Seen', 'Swing', 'Whiff', 'Called K', 'BAA (AB)', 'In play'],
          [
            for (final t in h.byType)
              [
                _cell(_typeName(t.type), bold: true, align: TextAlign.left),
                _cell('${t.pitches}', muted: t.pitches < GpConfig.minPitches),
                _rate(t.swingPct, t.pitches, GpConfig.minPitches),
                _rate(t.whiffPct, t.swings, GpConfig.minSwings),
                _rate(t.calledPct, t.pitches, GpConfig.minPitches),
                _cell(t.ab == 0 ? '—' : '${fmtAvg3(t.baa)} (${t.ab})', muted: t.ab < GpConfig.minAb),
                _cell(t.bip == 0 ? '—' : '${t.bipHits}H ${t.bipOuts}O/${t.bip}', muted: t.bip < 2),
              ],
          ],
          flex: const [1.1, 0.8, 1.4, 1.4, 1.5, 1.5, 1.4],
        ),
      const Text('Grey = fewer than the minimum sample, so no tendency is drawn. BAA counts only at-bats the pitch ENDED.', style: _muted),
      _h('By count'),
      _table(
        ['Count type', 'Pitches', 'Swing', 'Whiff', 'PAs ended: H-AB / K / BB'],
        [
          for (final b in h.byCount)
            [
              _cell(b.label, bold: true, align: TextAlign.left),
              _cell('${b.pitches}', muted: b.pitches < GpConfig.minPitches),
              _rate(b.swingPct, b.pitches, GpConfig.minPitches),
              _rate(b.whiffPct, b.swings, GpConfig.minSwings),
              _cell(b.paEnded == 0 ? '—' : '${b.hits}-${b.ab} / ${b.ks} / ${b.bb}  (${b.paEnded})', muted: b.paEnded < GpConfig.minAb),
            ],
        ],
        flex: const [1.6, 1, 1.4, 1.4, 2.4],
      ),
      _h('Previous at-bats (${h.atBats.length})'),
      if (h.atBats.isEmpty)
        const Text('None recorded.', style: _muted)
      else
        for (final ab in h.atBats) AtBatTile(ab, showBatter: false),
    ]);
  }

  Widget _noteRow(GpNote n) {
    final color = switch (n.label) {
      'Strength' => AppColors.perfPoor, // a hitter strength is a pitcher concern
      'Potential weakness' => AppColors.perfExcellent,
      'Suggested approach' => AppColors.brandOrangeDeep,
      _ => AppColors.colText,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${n.label}:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: color)),
          const SizedBox(width: 6),
          _Tag(n.tag),
          const SizedBox(width: 6),
          Flexible(child: _ConfChip(n.conf)),
        ]),
        const SizedBox(height: 1),
        Text(n.text, style: const TextStyle(fontSize: 12.5, height: 1.25)),
      ]),
    );
  }
}

// ───────────────────────── 7. Situational plan ─────────────────────────

class SituationalPlanCard extends StatelessWidget {
  final ScoutingGamePlan plan;
  const SituationalPlanCard(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    final ahead = plan.teamCounts.firstWhere((b) => b.key == 'ahead');
    final behind = plan.teamCounts.firstWhere((b) => b.key == 'behind');
    return _Section(
      title: 'Situational Game Plan',
      subtitle: 'Unknown means SKOUTAR does not have the data - nothing is guessed',
      initiallyExpanded: false,
      children: [
        _h('By situation'),
        _table(
          ['Situation', 'PA', 'H-AB', 'BB', 'K', 'OBP'],
          [
            for (final s in plan.situations)
              [
                _cell(s.label, bold: true, align: TextAlign.left),
                if (!s.available) ...[
                  _cell('Unknown', muted: true),
                  _cell('—', muted: true),
                  _cell('—', muted: true),
                  _cell('—', muted: true),
                  _cell('—', muted: true),
                ] else ...[
                  _cell('${s.pa}', muted: s.pa < GpConfig.minPa),
                  _cell('${s.hits}-${s.ab}', muted: s.pa < GpConfig.minPa),
                  _cell('${s.bb}', muted: s.pa < GpConfig.minPa),
                  _cell('${s.ks}', muted: s.pa < GpConfig.minPa),
                  _cell(fmtAvg3(s.obp), muted: s.pa < GpConfig.minPa),
                ],
              ],
          ],
          flex: const [2.6, 1.1, 1, 0.8, 0.8, 1],
        ),
        for (final s in plan.situations)
          if (s.note != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text('${s.label}: ${s.note}', style: _muted)),
        _h('Two outs'),
        ..._twoOuts(plan),
        _h('Pitcher ahead in the count'),
        if (ahead.pitches < GpConfig.minPitches)
          const Text('Unknown: not enough pitches thrown when you were ahead.', style: _muted)
        else
          _labeled(ahead.pitches >= GpConfig.goodPitches ? 'Supported tendency' : 'Observed fact',
              'Hitters swung at ${pctText(ahead.swingPct)} of pitches when behind in the count (${ahead.pitches} pitches), '
              'missing on ${pctText(ahead.whiffPct)} of swings. At-bats that ended there went ${ahead.hits}-for-${ahead.ab} '
              'with ${ahead.ks} K and ${ahead.bb} BB.',
              conf: confFor(ahead.pitches, GpConfig.minPitches, GpConfig.goodPitches)),
        _h('Pitcher behind in the count'),
        if (behind.pitches < GpConfig.minPitches)
          const Text('Unknown: you have rarely been behind to this lineup.', style: _muted)
        else ...[
          _labeled(behind.pitches >= GpConfig.goodPitches ? 'Supported tendency' : 'Observed fact',
              'In hitter\'s counts hitters swung at ${pctText(behind.swingPct)} of ${behind.pitches} pitches. '
              'At-bats that ended there went ${behind.hits}-for-${behind.ab} with ${behind.bb} BB.',
              conf: confFor(behind.pitches, GpConfig.minPitches, GpConfig.goodPitches)),
          if (plan.hitterCountLeaders.isNotEmpty)
            for (final m in plan.hitterCountLeaders.take(3))
              _labeled('Observed fact',
                  '#${(m['h'] as HitterReport).jersey} reached or got a hit ${((m['hits'] as int) + (m['bb'] as int))} time(s) '
                  'in ${m['ended']} at-bats that ended in hitter\'s counts (${m['hits']} H, ${m['bb']} BB).',
                  conf: confFor(m['ended'] as int, 2, 5)),
          const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Suggested approach: prioritise a strike-throwing pitch you trust here (see "Getting back into the count" under Pitch Selection Strategy).', style: _muted)),
        ],
      ],
    );
  }

  List<Widget> _twoOuts(ScoutingGamePlan plan) {
    final two = plan.situations.firstWhere((s) => s.label == 'Two outs');
    if (two.pa < GpConfig.minPa) {
      return [const Text('Unknown: too few plate appearances with two outs.', style: _muted)];
    }
    final c = confFor(two.pa, GpConfig.minPa, GpConfig.goodPa);
    return [
      _labeled('Observed fact',
          'With two outs this lineup went ${two.hits}-for-${two.ab} with ${two.bb} BB and ${two.ks} K in ${two.pa} PA '
          '(${two.kPct == null ? '—' : '${two.kPct!.round()}%'} strikeout rate).',
          conf: c),
      if (c == Conf.good || c == Conf.moderate)
        _labeled('Suggested approach', 'Finishing the inning quickly matters; compare these numbers with the zero/one-out row above before changing your plan.'),
    ];
  }
}

// ───────────────────────── 8. Previous matchup review ─────────────────────────

class MatchupReviewCard extends StatelessWidget {
  final ScoutingReportData r;
  const MatchupReviewCard(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final plan = r.plan;
    final byGame = <String, List<AtBatLine>>{};
    for (final ab in plan.atBats) {
      byGame.putIfAbsent('${ab.season}|${ab.gameNumber}', () => []).add(ab);
    }
    final first = plan.timesThrough[0], later = plan.timesThrough[1];
    final comparable = first.pa >= GpConfig.timesThroughMin && later.pa >= GpConfig.timesThroughMin;
    final worked = plan.teamTypes.where((t) => t.swings >= GpConfig.minSwings).toList()
      ..sort((a, b) => (b.whiffPct ?? 0).compareTo(a.whiffPct ?? 0));
    final hurt = plan.teamTypes.where((t) => t.xbh > 0).toList()..sort((a, b) => b.xbh.compareTo(a.xbh));
    return _Section(
      title: 'Previous Matchup Review',
      subtitle: 'What happened, in order. Pitch results and at-bat results are shown separately',
      initiallyExpanded: false,
      children: [
        _h('What worked'),
        if (worked.isEmpty)
          const Text('Not enough swings recorded to say.', style: _muted)
        else
          _labeled('Observed fact',
              '${_typeName(worked.first.type)} drew the most swing-and-miss (${worked.first.whiffs} of ${worked.first.swings} swings).',
              conf: confFor(worked.first.swings, GpConfig.minSwings, GpConfig.goodSwings)),
        if (plan.struggled.isNotEmpty)
          _labeled('Observed fact',
              'Hitters you handled: ${plan.struggled.map((m) => '#${(m['h'] as HitterReport).jersey}').join(', ')} (hitless, 2+ PA).'),
        _h('What did not work'),
        if (hurt.isEmpty && plan.dangerous.isEmpty)
          const Text('No damaging contact recorded.', style: _muted)
        else ...[
          if (hurt.isNotEmpty)
            _labeled('Observed fact',
                'Extra-base hits came in at-bats ended by ${hurt.map((t) => '${_typeName(t.type)} (${t.xbh})').join(', ')}.'),
          if (plan.dangerous.isNotEmpty)
            _labeled('Observed fact',
                'Hitters who gave you the most trouble: ${plan.dangerous.map((m) => '#${(m['h'] as HitterReport).jersey}').join(', ')}.'),
        ],
        _h('Did hitters respond differently as the game went on?'),
        if (!comparable)
          const Text('Unknown: needs at least 8 plate appearances in both the first look and the second-or-later look.', style: _muted)
        else
          _labeled('Observed fact',
              'First time facing a hitter: ${first.hits}-for-${first.ab}, ${first.bb} BB, ${first.ks} K in ${first.pa} PA (OBP ${fmtAvg3(first.obp)}). '
              'Second time or later: ${later.hits}-for-${later.ab}, ${later.bb} BB, ${later.ks} K in ${later.pa} PA (OBP ${fmtAvg3(later.obp)}).',
              conf: confFor(first.pa < later.pa ? first.pa : later.pa, GpConfig.timesThroughMin, 20)),
        _h('Patterns that repeated'),
        if (plan.patterns.isEmpty)
          const Text('No pattern was flagged in 2 or more at-bats.', style: _muted)
        else
          for (final p in plan.patterns.take(3)) _labeled('Observed fact', '${p['text']}  (in ${p['n']} at-bats)', conf: Conf.low),
        _h('At-bats in order'),
        for (final e in byGame.entries)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text('Game ${e.value.first.gameNumber} (${e.value.first.season})  •  ${e.value.length} at-bat${e.value.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              children: [for (final ab in e.value) AtBatTile(ab, showBatter: true)],
            ),
          ),
        if (plan.atBats.isEmpty) const Text('No at-bats recorded.', style: _muted),
      ],
    );
  }
}

/// One plate appearance: the pitch sequence (with the count each pitch was
/// thrown in) and, separately, the plate-appearance result.
class AtBatTile extends StatelessWidget {
  final AtBatLine ab;
  final bool showBatter;
  const AtBatTile(this.ab, {super.key, required this.showBatter});

  @override
  Widget build(BuildContext context) {
    final head = [
      if (ab.inning != null) 'Inn ${ab.inning}',
      if (showBatter && ab.jersey != null) '#${ab.jersey}',
      if (showBatter && ab.jersey == null) 'Batter unknown',
      '${ab.outsBefore} out${ab.outsBefore == 1 ? '' : 's'}',
      if (ab.leadoff) 'leadoff',
      if (!showBatter) 'G${ab.gameNumber}',
    ].join('  •  ');
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.colBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(head, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
        const SizedBox(height: 3),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final p in ab.pitches)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.colBorder)),
              child: Text('${p.count}  ${_typeName(p.type)}  ${callName(p.call)}', style: const TextStyle(fontSize: 11.5)),
            ),
        ]),
        const SizedBox(height: 3),
        Row(children: [
          const Text('Result: ', style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
          Text(outcomeName(ab.outcome), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
          if (ab.seqScore != null) ...[
            const SizedBox(width: 8),
            Text('Sequencing score ${ab.seqScore!.round()}', style: _muted),
          ],
        ]),
      ]),
    );
  }
}
