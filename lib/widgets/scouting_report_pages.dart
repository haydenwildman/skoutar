import 'package:flutter/material.dart';
import '../services/scouting_pdf_service.dart' show ScoutingPdfFit;
import '../services/scouting_report_sheet.dart';
import '../theme/app_theme.dart';
import 'glow.dart';

/// The Scouting Report as two letter-proportioned pages, all content visible
/// (no dropdowns, accordions or hidden panels). Draws the same
/// [ScoutingSheet] the PDF export uses, in the app's own typography (the text
/// inherits the theme's Teko; no font is set here) and heat-map styling
/// ([ScaleStyle], the perf palette).
///
/// On screen nothing is clipped or capped: if a page has more content than a
/// printed sheet can hold legibly, the page simply grows, and a note says how
/// the PDF handles it ([fit]).
class ScoutingReportPages extends StatelessWidget {
  final ScoutingSheet sheet;
  final ScoutingPdfFit fit;
  const ScoutingReportPages({super.key, required this.sheet, required this.fit});

  static const double _paperW = 816; // 8.5 in at 96 dpi
  static const double _minW = 720; // narrower screens scroll sideways

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth.clamp(_minW, _paperW).toDouble() : _paperW;
      final pages = SizedBox(
        width: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Paper(child: _Page1(sheet)),
          const SizedBox(height: 14),
          _Paper(child: _Page2(sheet, fit)),
        ]),
      );
      if (c.maxWidth >= _minW) {
        return Center(child: pages);
      }
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: pages);
    });
  }
}

class _Paper extends StatelessWidget {
  final Widget child;
  const _Paper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.colBorder),
        borderRadius: BorderRadius.circular(6),
        boxShadow: AppGlow.shadows,
      ),
      child: child,
    );
  }
}

// ───────────────────────── shared bits ─────────────────────────

const TextStyle _muted = TextStyle(fontSize: 11, color: AppColors.colMuted);

Widget _pageHeader(ScoutingSheet s, String title, int page) {
  final r = s.r;
  final threat = r.threatLevel == 'high'
      ? AppColors.perfPoor
      : (r.threatLevel == 'medium' ? AppColors.perfAverage : AppColors.perfExcellent);
  final threatText = r.threatLevel == 'medium' ? AppColors.colText : Colors.white;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [
      Expanded(
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.ink)),
      ),
      Text('${r.gamesFaced} game${r.gamesFaced == 1 ? '' : 's'} · Page $page of 2', style: _muted),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: threat, borderRadius: BorderRadius.circular(12)),
        child: Text('${r.threatLevel.toUpperCase()} THREAT',
            style: TextStyle(color: threatText, fontWeight: FontWeight.w900, fontSize: 12)),
      ),
    ]),
    const SizedBox(height: 4),
    Container(height: 2, color: AppColors.brandOrangeDeep),
    const SizedBox(height: 10),
  ]);
}

Widget _section(String title, {String? note}) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 4, height: 15, color: AppColors.brandOrangeDeep),
        const SizedBox(width: 6),
        Text(title.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.ink)),
        if (note != null) ...[
          const SizedBox(width: 8),
          Expanded(child: Text(note, style: _muted, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ]),
    );

Widget _foot(String text) => Padding(padding: const EdgeInsets.only(top: 3), child: Text(text, style: _muted));

Widget _gapBox([double h = 10]) => SizedBox(height: h);

/// One heat-map-aware table. A tier color becomes the app's own washed fill
/// ([ScaleStyle.fill]); the number is always dark text on top of it.
Widget _table(SheetTable t, {double font = 12, String empty = 'No data recorded'}) {
  if (t.rows.isEmpty) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(border: Border.all(color: AppColors.colBorder)),
      child: Text(empty, style: _muted),
    );
  }
  Widget cell(SheetCell c, {bool header = false}) {
    final tier = c.tier;
    return Container(
      color: header ? AppColors.ink : (tier != null ? ScaleStyle.fill(tier) : null),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      alignment: c.left ? Alignment.centerLeft : Alignment.center,
      child: Text(
        c.text,
        textAlign: c.left ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          fontSize: header ? font - 1 : font,
          fontWeight: (header || c.bold) ? FontWeight.w800 : FontWeight.w500,
          color: header ? Colors.white : (c.muted ? AppColors.colMuted : AppColors.colText),
        ),
      ),
    );
  }

  return Table(
    border: TableBorder.all(color: AppColors.colBorder, width: 0.6),
    columnWidths: {for (var i = 0; i < t.flex.length; i++) i: FlexColumnWidth(t.flex[i])},
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(children: [
        for (var i = 0; i < t.headers.length; i++) cell(SheetCell(t.headers[i], left: i == 0), header: true),
      ]),
      for (var ri = 0; ri < t.rows.length; ri++)
        TableRow(
          decoration: BoxDecoration(color: ri.isOdd ? AppColors.surfaceAlt : null),
          children: [for (final c in t.rows[ri]) cell(c)],
        ),
    ],
  );
}

Widget _metricBox(SheetMetric m, {double valueSize = 24}) {
  final tier = m.tier;
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    decoration: BoxDecoration(
      color: tier != null ? ScaleStyle.fill(tier) : AppColors.tint,
      border: Border.all(color: tier ?? AppColors.colBorder, width: tier != null ? 2 : 1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(m.label.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
      Text(m.value,
          style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.05)),
      if (m.sub.isNotEmpty) Text(m.sub, style: const TextStyle(fontSize: 10, color: AppColors.colMuted)),
    ]),
  );
}

// ───────────────────────── page 1 ─────────────────────────

class _Page1 extends StatelessWidget {
  final ScoutingSheet s;
  const _Page1(this.s);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader(s, 'SCOUTING REPORT: ${s.r.team.toUpperCase()}', 1),
      _section('Team performance vs this pitcher',
          note: 'Whole-opponent totals. ERA/WHIP use innings pitched; K%, BB% and XBH use plate appearances.'),
      Row(children: [
        for (var i = 0; i < s.summary.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: _metricBox(s.summary[i])),
        ],
      ]),
      _gapBox(),
      _section('Pitch effectiveness vs this team',
          note: 'Strike/Swing/Whiff are pitch-level rates; H-AB, AVG, XBH, K, BB count only at-bats that ENDED on that pitch.'),
      _table(s.pitches, empty: 'No pitch data recorded'),
      _foot('Pit = pitches · Use = share of all pitches · Sw = swings (Whiff % = misses ÷ swings). '
          'Usage, strike rate and whiff rate are different measures from AVG against.'),
      _gapBox(),
      _twoUp(
        _titled('Previous games', 'AVG, K%, BB% per game', _table(s.games, empty: 'No games recorded'),
            foot: s.gamesHidden > 0
                ? '${s.gamesHidden} earlier game(s) not listed here; they are in the team totals above.'
                : 'ER = earned runs charged in that game.'),
        _titled('Most dangerous hitters', 'ranked by OBP, min. 2 PA, top 5',
            _table(s.dangerous, empty: 'Need 2+ PA from a hitter'),
            foot: 'A high OBP over 2–4 PA is a note, not proof. Full cards on page 2.'),
      ),
      _gapBox(),
      _twoUp(
        _titled('Team results by count', 'Ahead / Even / Behind are exclusive', _table(s.teamCounts),
            foot: 'Pit/Sw/Whiff count every pitch in that count; PA, H-AB, K, BB count at-bats that ENDED there. '
                '* overlaps the rows above.'),
        _titled('Hitters who have struggled', 'hitless, min. 2 PA', _table(s.struggled, empty: 'No hitless hitter with 2+ PA'),
            foot: 'Recorded matchups only; not proof a hitter is weak.'),
      ),
      _gapBox(),
      _section('Game plan & key takeaways',
          note: 'Observed = counted from recorded events; Suggested = an idea, not a guarantee.'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _findingCol('Strengths to exploit', AppColors.perfExcellent, s.strengths)),
        const SizedBox(width: 6),
        Expanded(child: _findingCol('Potential weaknesses', AppColors.perfPoor, s.weaknesses)),
        const SizedBox(width: 6),
        Expanded(child: _findingCol('Suggested approaches', AppColors.brandOrangeDeep, s.approaches)),
        const SizedBox(width: 6),
        Expanded(child: _findingCol('Cautions', AppColors.ink, s.cautions)),
      ]),
      _gapBox(8),
      const _HeatLegend(),
    ]);
  }

  Widget _twoUp(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: 10),
          Expanded(child: b),
        ]);
      });

  Widget _titled(String title, String note, Widget table, {String? foot}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section(title, note: note),
        table,
        if (foot != null) _foot(foot),
      ]);

  Widget _findingCol(String title, Color accent, List<SheetFinding> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: accent,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(title.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
      ),
      const SizedBox(height: 4),
      if (items.isEmpty) const Text('None supported by the recorded data.', style: _muted),
      for (final f in items)
        Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.only(left: 5),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.headline, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
            Text(f.body, style: const TextStyle(fontSize: 12)),
            Text(
              [f.tag, if (f.conf != 'n/a') '${f.conf} conf.', if (f.sample.isNotEmpty) f.sample].join(' · '),
              style: const TextStyle(fontSize: 10.5, color: AppColors.colMuted),
            ),
          ]),
        ),
    ]);
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend();
  @override
  Widget build(BuildContext context) => const Text(
        'Heat map = the SKOUTAR scale (same cutoffs as Overview and Pitch Breakdown), graded from the pitcher\'s view. '
        'Cream or gray = no data or a sample below the minimum; the number and its sample are always printed. '
        'Results are credited to the pitch that ended the plate appearance.',
        style: _muted,
      );
}

// ───────────────────────── page 2 ─────────────────────────

class _Page2 extends StatelessWidget {
  final ScoutingSheet s;
  final ScoutingPdfFit fit;
  const _Page2(this.s, this.fit);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader(s, 'HITTER SCOUTING CARDS: ${s.r.team.toUpperCase()}', 2),
      _section('Individual hitter scouting cards',
          note: 'AVG/OBP/SLG are the hitter\'s numbers against this pitcher; heat is from the pitcher\'s view.'),
      Text(
          'Pitch rows: Pit = pitches, Use = share of that hitter\'s pitches, H-AB/AVG = at-bats ended on that pitch, Wh/Sw = misses over swings. '
          'Count rows: Pit/Sw/Whiff = every pitch in that count; PA, H-AB, K, BB, AVG = at-bats that ended there. '
          'Ahead / Even / Behind are exclusive; * two strikes overlaps them.',
          style: _muted),
      if (!fit.allFit && fit.totalHitters > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'PDF note: ${fit.fullCards} of ${fit.totalHitters} hitters fit as full cards on the printed page; '
              'the other ${fit.rosterRows} are printed as a roster table with their batting lines. Everything is shown here.',
              style: const TextStyle(fontSize: 11, color: AppColors.brandOrangeDeep, fontWeight: FontWeight.w700)),
        ),
      _gapBox(8),
      if (s.cards.isEmpty)
        const Text('No hitter has a recorded jersey number, so no hitter cards can be built. Add jersey numbers in Game Input.',
            style: _muted)
      else
        LayoutBuilder(builder: (context, c) {
          const gap = 8.0;
          final w = (c.maxWidth - gap) / 2;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final h in s.cards) SizedBox(width: w, child: _HitterCardView(h)),
          ]);
        }),
      _gapBox(8),
      const _HeatLegend(),
    ]);
  }
}

class _HitterCardView extends StatelessWidget {
  final HitterCard c;
  const _HitterCardView(this.c);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.colBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(3)),
            child: Text('#${c.jersey}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          ),
          const SizedBox(width: 6),
          Text(c.hand,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.brandOrangeDeep)),
          const Spacer(),
          Text('${c.pa} PA · ${c.ab} AB · ${c.games} G · ${c.conf} conf.', style: _muted),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: _batBox(c.avg)),
          const SizedBox(width: 4),
          Expanded(child: _batBox(c.obp)),
          const SizedBox(width: 4),
          Expanded(child: _batBox(c.slg)),
        ]),
        const SizedBox(height: 4),
        _table(c.pitchTable, font: 11, empty: 'No pitches recorded'),
        const SizedBox(height: 4),
        _table(c.countTable, font: 11),
        const SizedBox(height: 4),
        for (final n in c.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${n.label} · ${n.tag} · ${n.conf}: ',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: n.label == 'Potential weakness'
                          ? AppColors.perfExcellent
                          : (n.label == 'Caution' ? AppColors.perfPoor : AppColors.brandOrangeDeep))),
              TextSpan(text: n.text),
            ]), style: const TextStyle(fontSize: 11.5)),
          ),
      ]),
    );
  }

  Widget _batBox(SheetMetric m) {
    final tier = m.tier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tier != null ? ScaleStyle.fill(tier) : AppColors.tint,
        border: Border.all(color: tier ?? AppColors.colBorder, width: tier != null ? 1.5 : 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Text(m.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
        const Spacer(),
        if (m.sub.isNotEmpty)
          Padding(padding: const EdgeInsets.only(right: 4), child: Text(m.sub, style: const TextStyle(fontSize: 10, color: AppColors.colMuted))),
        Text(m.value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
      ]),
    );
  }
}
