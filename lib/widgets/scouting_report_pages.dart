import 'package:flutter/material.dart';
import '../services/scouting_pdf_service.dart' show ScoutingPdfFit;
import '../utils/responsive.dart';
import '../services/scouting_report_sheet.dart';
import '../theme/app_theme.dart';
import 'baseball_field_painter.dart' show SprayFieldSurface;
import 'glow.dart';

/// The Scouting Report: a team-overview page followed by ONE individual
/// scouting card (its own page) for every eligible hitter, all content visible
/// (no dropdowns, accordions or hidden panels). Draws the same
/// [ScoutingSheet] the PDF export uses, in the app's own typography and
/// heat-map styling ([ScaleStyle], the perf palette).
///
/// Responsive: on desktop the pages are letter-proportioned (max 816 wide). On
/// phones everything stacks into one column that fits the screen width; tables
/// scale their text down instead of scrolling sideways.
class ScoutingReportPages extends StatelessWidget {
  final ScoutingSheet sheet;
  final ScoutingPdfFit fit;
  const ScoutingReportPages({super.key, required this.sheet, required this.fit});

  static const double _paperW = 816; // 8.5 in at 96 dpi

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth.clamp(0.0, _paperW).toDouble() : _paperW;
      final phone = w < Breakpoints.phone;
      final total = 1 + sheet.cards.length;
      final pages = SizedBox(
        width: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Paper(phone: phone, child: _Page1(sheet, phone: phone, pages: total)),
          if (sheet.cards.isEmpty) ...[
            const SizedBox(height: 14),
            _Paper(
              phone: phone,
              child: const Text(
                  'No hitter has a recorded jersey number, so no hitter cards can be built. Add jersey numbers in Game Input.',
                  style: _muted),
            ),
          ],
          // One card per hitter, each on its own page.
          for (var i = 0; i < sheet.cards.length; i++) ...[
            const SizedBox(height: 14),
            _Paper(
              phone: phone,
              child: _HitterPage(sheet, sheet.cards[i], page: i + 2, pages: total, phone: phone),
            ),
          ],
        ]),
      );
      return Center(child: pages);
    });
  }
}

class _Paper extends StatelessWidget {
  final Widget child;
  final bool phone;
  const _Paper({required this.child, this.phone = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(phone ? 10 : 18),
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

Widget _pageHeader(ScoutingSheet s, String title, int page, int pages, {bool phone = false}) {
  final r = s.r;
  final threat = r.threatLevel == 'high'
      ? AppColors.perfPoor
      : (r.threatLevel == 'medium' ? AppColors.perfAverage : AppColors.perfExcellent);
  final threatText = r.threatLevel == 'medium' ? AppColors.colText : Colors.white;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: phone ? 18 : 22, color: AppColors.ink)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${r.gamesFaced} game${r.gamesFaced == 1 ? '' : 's'} · Page $page of $pages', style: _muted),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: threat, borderRadius: BorderRadius.circular(12)),
            child: Text('${r.threatLevel.toUpperCase()} THREAT',
                style: TextStyle(color: threatText, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ]),
      ],
    ),
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
Widget _table(SheetTable t,
    {double font = 12, String empty = 'No data recorded', bool phone = false, bool heat = true}) {
  if (phone && font > 10.5) font = 10.5;
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
      color: header ? AppColors.ink : ((heat && tier != null) ? ScaleStyle.fill(tier) : null),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      alignment: c.left ? Alignment.centerLeft : Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: c.left ? Alignment.centerLeft : Alignment.center,
        child: Text(
        c.text,
        maxLines: 1,
        softWrap: false,
        textAlign: c.left ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          fontSize: header ? font - 1 : font,
          fontWeight: (header || c.bold) ? FontWeight.w800 : FontWeight.w500,
          color: header ? Colors.white : (c.muted ? AppColors.colMuted : AppColors.colText),
        ),
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

/// Every summary box has the same fixed height, so long labels or a missing
/// sub-line never change its size.
Widget _metricBox(SheetMetric m, {double valueSize = 24}) {
  final tier = m.tier;
  return Container(
    height: 78,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    decoration: BoxDecoration(
      color: tier != null ? ScaleStyle.fill(tier) : AppColors.tint,
      border: Border.all(color: tier ?? AppColors.colBorder, width: tier != null ? 2 : 1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(m.label.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
        Text(m.value,
            maxLines: 1,
            style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.05)),
        if (m.sub.isNotEmpty)
          Text(m.sub, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 10, color: AppColors.colMuted)),
      ]),
    ),
  );
}

// ───────────────────────── page 1 ─────────────────────────

class _Page1 extends StatelessWidget {
  final ScoutingSheet s;
  final bool phone;
  final int pages;
  const _Page1(this.s, {this.phone = false, this.pages = 2});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader(s, 'SCOUTING REPORT: ${s.r.team.toUpperCase()}', 1, pages, phone: phone),
      _section('Team performance vs this pitcher',
          note: 'Whole-opponent totals. ERA/WHIP use innings pitched; K%, BB% and XBH use plate appearances.'),
      LayoutBuilder(builder: (context, c) {
        // Equal-width boxes: one row on wide screens, 3 or 2 per row on phones.
        final perRow = phone ? (c.maxWidth >= 420 ? 3 : 2) : s.summary.length;
        const gap = 5.0;
        final w = ((c.maxWidth - gap * (perRow - 1)) / perRow).floorToDouble();
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final m in s.summary) SizedBox(width: w, child: _metricBox(m, valueSize: phone ? 20 : 24)),
        ]);
      }),
      _gapBox(),
      _section('Pitch effectiveness vs this team',
          note: 'Strike/Swing/Whiff are pitch-level rates; H-AB, AVG, XBH, K, BB count only at-bats that ENDED on that pitch.'),
      _table(s.pitches, empty: 'No pitch data recorded', phone: phone),
      _foot('P = pitches · Use = share of all pitches · Sw = swings (Whiff % = misses ÷ swings). '
          'Usage, strike rate and whiff rate are different measures from AVG against.'),
      _gapBox(),
      _twoUp(
        _titled('Previous games', 'AVG, K%, BB% per game', _table(s.games, empty: 'No games recorded', phone: phone),
            foot: s.gamesHidden > 0
                ? '${s.gamesHidden} earlier game(s) not listed here; they are in the team totals above.'
                : 'ER = earned runs charged in that game.'),
        _titled('Most dangerous hitters', 'ranked by OBP, min. 2 PA, top 5',
            _table(s.dangerous, empty: 'Need 2+ PA from a hitter', phone: phone),
            foot: 'A high OBP over 2–4 PA is a note, not proof. Each hitter has their own card on the pages that follow.'),
      ),
      _gapBox(),
      _twoUp(
        _titled('Team results by count', 'Ahead / Even / Behind are exclusive', _table(s.teamCounts, phone: phone),
            foot: 'P/Sw/Whiff count every pitch in that count; PA, H-AB, K, BB count at-bats that ENDED there. '
                '* overlaps the rows above.'),
        _titled('Hitters who have struggled', 'hitless, min. 2 PA', _table(s.struggled, empty: 'No hitless hitter with 2+ PA', phone: phone),
            foot: 'Recorded matchups only; not proof a hitter is weak.'),
      ),
      _gapBox(),
      _section('Game plan & key takeaways',
          note: 'Observed = counted from recorded events; Suggested = an idea, not a guarantee.'),
      LayoutBuilder(builder: (context, c) {
        // 4 columns on desktop, 1 column on phones; equal widths either way.
        final cols = phone ? 1 : 4;
        const gap = 6.0;
        final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(spacing: gap, runSpacing: 10, children: [
          SizedBox(width: w, child: _findingCol('Strengths to exploit', AppColors.perfExcellent, s.strengths)),
          SizedBox(width: w, child: _findingCol('Potential weaknesses', AppColors.perfPoor, s.weaknesses)),
          SizedBox(width: w, child: _findingCol('Suggested approaches', AppColors.brandOrangeDeep, s.approaches)),
          SizedBox(width: w, child: _findingCol('Cautions', AppColors.ink, s.cautions)),
        ]);
      }),
      _gapBox(8),
      const _HeatLegend(),
    ]);
  }

  Widget _twoUp(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
        if (phone) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 10), b]);
        }
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

// ───────────────────── one hitter per page ─────────────────────

class _HitterPage extends StatelessWidget {
  final ScoutingSheet s;
  final HitterCard c;
  final int page;
  final int pages;
  final bool phone;
  const _HitterPage(this.s, this.c, {required this.page, required this.pages, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader(s, 'HITTER SCOUTING CARD: ${s.r.team.toUpperCase()}', page, pages, phone: phone),
      _HitterCardView(c, phone: phone),
      _gapBox(8),
      const Text(
          'AVG/OBP/SLG are the hitter\'s numbers against this pitcher; heat is from the pitcher\'s view. '
          'Pitch rows: P = pitches, Use = share of that hitter\'s pitches, H-AB/AVG = at-bats ended on that pitch, Wh/Sw = misses over swings. '
          'Count rows: P/Sw/Whiff = every pitch in that count; PA, H-AB, K, BB, AVG = at-bats that ended there. '
          'Ahead / Even / Behind are exclusive; * two strikes overlaps them. '
          'Pitch sequencing: each finished at-bat with its pitches in the order they were thrown.',
          style: _muted),
      _gapBox(4),
      const Text(
          'Only AVG, OBP and SLG are colored (the SKOUTAR scale, graded from the pitcher\'s view; cream = no data). '
          'Every other number is plain, with its sample always printed. Results are credited to the pitch that ended the plate appearance.',
          style: _muted),
    ]);
  }
}

class _HitterCardView extends StatelessWidget {
  final HitterCard c;
  final bool phone;
  const _HitterCardView(this.c, {this.phone = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.colBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(3)),
            child: Text('#${c.jersey}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          ),
          Text('Bats: ${c.hand}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.brandOrangeDeep)),
          Text('Plate Appearances: ${c.pa} · At-Bats: ${c.ab} · Games: ${c.games} · ${c.conf} confidence', style: _muted),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, k) {
          // AVG / OBP / SLG: three equal boxes on every screen size.
          const gap = 6.0;
          final w = ((k.maxWidth - gap * 2) / 3).floorToDouble();
          return Row(children: [
            SizedBox(width: w, child: _batBox(c.avg)),
            const SizedBox(width: gap),
            SizedBox(width: w, child: _batBox(c.obp)),
            const SizedBox(width: gap),
            SizedBox(width: w, child: _batBox(c.slg)),
          ]);
        }),
        const SizedBox(height: 10),
        _section('By pitch type'),
        _table(c.pitchTable, font: 12, empty: 'No pitches recorded', phone: phone, heat: false),
        const SizedBox(height: 10),
        _section('By count'),
        _table(c.countTable, font: 12, phone: phone, heat: false),
        const SizedBox(height: 10),
        _section('Pitch sequencing', note: 'this hitter only'),
        Text(c.sequenceNote, style: _muted),
        const SizedBox(height: 4),
        _table(c.paTable, font: 12, empty: 'No finished plate appearances recorded', phone: phone, heat: false),
        const SizedBox(height: 10),
        _section('Spray chart', note: 'balls in play with a recorded location'),
        _HitterSpray(c, phone: phone),
        const SizedBox(height: 10),
        for (final n in c.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${n.label} · ${n.tag} · ${n.conf}: ',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: n.label == 'Potential weakness'
                          ? AppColors.perfExcellent
                          : (n.label == 'Caution' ? AppColors.perfPoor : AppColors.brandOrangeDeep))),
              TextSpan(text: n.text),
            ]), style: const TextStyle(fontSize: 13)),
          ),
      ]),
    );
  }

  /// Fixed-height, equal-width AVG / OBP / SLG box.
  Widget _batBox(SheetMetric m) {
    final tier = m.tier;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tier != null ? ScaleStyle.fill(tier) : AppColors.tint,
        border: Border.all(color: tier ?? AppColors.colBorder, width: tier != null ? 1.5 : 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Text(m.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
        const Spacer(),
        if (m.sub.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(m.sub, style: const TextStyle(fontSize: 10, color: AppColors.colMuted))),
        Text(m.value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink)),
      ]),
    );
  }
}


/// One hitter's spray chart, drawn with the same field surface and coordinate
/// system as the Spray Chart tab. Same size for every hitter; a hitter with no
/// located ball in play gets a clear empty message instead of a blank field.
class _HitterSpray extends StatelessWidget {
  final HitterCard c;
  final bool phone;
  const _HitterSpray(this.c, {this.phone = false});

  @override
  Widget build(BuildContext context) {
    const side = 240.0;
    final pts = c.sprayPoints;
    final missing = c.sprayMissing;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: SizedBox(
          width: phone ? double.infinity : side,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: side),
            child: AspectRatio(
              aspectRatio: 1,
              child: pts.isEmpty
                  ? Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.tint,
                        border: Border.all(color: AppColors.colBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'No ball in play with a recorded location for this hitter yet.',
                        textAlign: TextAlign.center,
                        style: _muted,
                      ),
                    )
                  : SprayFieldSurface(sprayPoints: pts),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        pts.isEmpty
            ? (missing > 0 ? '$missing ball${missing == 1 ? '' : 's'} in play had no location recorded.' : '')
            : 'Balls in play plotted: ${pts.length}.'
                '${missing > 0 ? ' $missing more had no location recorded and are not drawn.' : ''}'
                ' Dot fill = result, ring = pitch hit; dotted line = ground ball, straight = line drive, arc = fly ball.',
        textAlign: TextAlign.center,
        style: _muted,
      ),
    ]);
  }
}
