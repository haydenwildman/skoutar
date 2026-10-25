import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../theme/app_theme.dart' show ScaleStyle;
import 'scouting_game_plan.dart' show GpConfig;
import 'scouting_report_data.dart';
import 'scouting_report_sheet.dart';

/// PDF brand colors — same hex values as [AppColors] in app_theme.dart,
/// re-expressed as PdfColor (the `pdf` package can't take Flutter's `Color`).
class _C {
  static final ink = PdfColor.fromInt(0xFF26201C);
  static final accent = PdfColor.fromInt(0xFFC94F1B);
  static final tint = PdfColor.fromInt(0xFFFDF1E4);
  static final surfaceAlt = PdfColor.fromInt(0xFFFBF7F0);
  static final text = PdfColor.fromInt(0xFF1C1917);
  static final muted = PdfColor.fromInt(0xFF78716C);
  static final border = PdfColor.fromInt(0xFFE7DCCF);
  static final perfExcellent = PdfColor.fromInt(0xFF15803D);
  static final perfAverage = PdfColor.fromInt(0xFFFACC15);
  static final perfPoor = PdfColor.fromInt(0xFFDC2626);

  /// Heat-map fill: exactly the app's own wash of the tier color
  /// ([ScaleStyle.fillAny]); the number inside is always dark text.
  static PdfColor wash(Color tier) => PdfColor.fromInt(ScaleStyle.fillAny(tier).value);
  static PdfColor solid(Color tier) => PdfColor.fromInt(tier.value);
}

/// How page 2 was laid out; the on-screen report reads this to tell the user
/// exactly what the PDF contains.
class ScoutingPdfFit {
  final int totalHitters;
  final int fullCards;
  final int rosterRows;
  final int cols;
  final double cardHeight; // tallest printed card
  final List<int> fullIdx; // indexes into ScoutingSheet.cards, report order
  const ScoutingPdfFit(this.totalHitters, this.fullCards, this.rosterRows, this.cols, this.cardHeight, this.fullIdx);
  bool get allFit => rosterRows == 0;
}

/// Builds the two-page US Letter Scouting Report PDF.
///
/// Page 1 = team overview, page 2 = hitter scouting cards. Both pages are
/// fixed `pw.Page`s (never a MultiPage), so the document can only ever be two
/// pages. Every row has a fixed height so the layout is deterministic, and
/// anything that cannot fit legibly is stated on the page instead of being
/// shrunk or dropped silently.
class ScoutingPdfService {
  // ── page geometry (points; 72 pt = 1 in) ───────────────────────────
  static const double _mL = 24, _mT = 20;
  static const double _w = 612 - 2 * _mL; // 564
  static const double _contentH = 792 - 2 * _mT; // 752
  static const double _headerH = 30;
  static const double _footerH = 22;
  static const double _gap = 6;

  // ── type scale (Teko, the app font; line height = 1.433 x size) ────
  static const double _fBody = 8; // page-1 tables
  static const double _fCard = 7; // hitter-card tables and notes
  static const double _fHead = 6.5; // table headers
  static const double _rowP1 = 12, _headP1 = 10.5;
  static const double _rowCard = 10.5, _headCard = 10;
  static const double _secH = 12; // section heading
  static const double _teko = 0.40; // average glyph width / font size (regular)
  static const double _tekoB = 0.50; // same, bold/uppercase (conservative)

  static const int _maxPitchRows = 7;

  // ───────────────────────── entry point ─────────────────────────
  static Future<Uint8List> generate(ScoutingReportData r) async {
    // SKOUTAR typeface: Teko (bundled), regular + bold. Falls back to the PDF
    // default font only if the assets cannot be read, so export never fails.
    pw.ThemeData? theme;
    try {
      final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/Teko-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Teko-Bold.ttf'));
      theme = pw.ThemeData.withFont(base: reg, bold: bold, italic: reg, boldItalic: bold);
    } catch (_) {
      theme = null;
    }
    pw.MemoryImage? logo;
    try {
      ByteData bytes;
      try {
        bytes = await rootBundle.load('assets/images/2.0x/logo.png');
      } catch (_) {
        bytes = await rootBundle.load('assets/images/logo.png');
      }
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }

    final sheet = ScoutingSheet.build(r);
    final fit = fitFor(sheet.cards);
    final doc = pw.Document(theme: theme);
    final margin = const pw.EdgeInsets.fromLTRB(_mL, _mT, _mL, _mT);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: margin,
      build: (ctx) => _pageShell(logo, sheet, 1, _page1(sheet)),
    ));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: margin,
      build: (ctx) => _pageShell(logo, sheet, 2, _page2(sheet, fit)),
    ));
    return doc.save();
  }

  // ───────────────────────── shared pieces ─────────────────────────

  static pw.Widget _t(String s, double size,
      {bool bold = false, PdfColor? color, pw.TextAlign? align}) {
    return pw.Text(s,
        textAlign: align,
        style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? _C.text));
  }

  /// Shortens [s] with an ellipsis so it fits [widthPt] on one line.
  static String _fit(String s, double widthPt, double size, {bool bold = false}) {
    final per = size * (bold ? _tekoB : _teko);
    final maxChars = (widthPt / per).floor();
    if (maxChars <= 1 || s.length <= maxChars) return s;
    return '${s.substring(0, maxChars - 1).trimRight()}…';
  }

  static int _lines(String s, double widthPt, double size) {
    final perLine = (widthPt / (size * _teko)).floor();
    if (perLine <= 0) return 1;
    final n = (s.length / perLine).ceil();
    return n < 1 ? 1 : n;
  }

  static pw.Widget _pageShell(pw.MemoryImage? logo, ScoutingSheet sh, int page, pw.Widget body) {
    final r = sh.r;
    final threat = r.threatLevel == 'high'
        ? _C.perfPoor
        : (r.threatLevel == 'medium' ? _C.perfAverage : _C.perfExcellent);
    final threatText = r.threatLevel == 'medium' ? _C.text : PdfColors.white;
    final title = page == 1 ? 'SCOUTING REPORT: ${r.team.toUpperCase()}' : 'HITTER SCOUTING CARDS: ${r.team.toUpperCase()}';
    final today = DateTime.now().toString().split(' ').first;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.SizedBox(
        height: _headerH,
        child: pw.Column(children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            if (logo != null) ...[
              pw.Image(logo, width: 34, height: 26, fit: pw.BoxFit.contain),
              pw.SizedBox(width: 6),
            ],
            pw.Expanded(child: _t(title, 15, bold: true, color: _C.ink)),
            _t('${r.gamesFaced} game${r.gamesFaced == 1 ? '' : 's'} · $today · Page $page of 2', 7.5, color: _C.muted),
            pw.SizedBox(width: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: pw.BoxDecoration(color: threat, borderRadius: pw.BorderRadius.circular(8)),
              child: _t('${r.threatLevel.toUpperCase()} THREAT', 7.5, bold: true, color: threatText),
            ),
          ]),
          pw.SizedBox(height: 2),
          pw.Container(height: 1.2, color: _C.accent),
        ]),
      ),
      pw.SizedBox(height: _contentH - _headerH - _footerH, child: pw.ClipRect(child: body)),
      pw.SizedBox(
        height: _footerH,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(height: 0.5, color: _C.border),
          pw.SizedBox(height: 2),
          _t(
              'Heat map = the SKOUTAR scale (same cutoffs as Overview and Pitch Breakdown), graded from the pitcher\'s view. '
              'Gray/cream = no data or sample below the minimum (under ${GpConfig.minAb} AB, ${GpConfig.minSwings} swings or ${GpConfig.minPitches} pitches); the number and its sample are always printed. '
              'Results are credited to the pitch that ended the plate appearance. * Two-strike row overlaps the rows above it and is never added to a total.',
              6, color: _C.muted),
        ]),
      ),
    ]);
  }

  static pw.Widget _heading(String title, {String? note, double? width}) {
    return pw.SizedBox(
      height: _secH,
      width: width,
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Container(width: 3, height: 10, color: _C.accent),
        pw.SizedBox(width: 3),
        _t(title.toUpperCase(), 8.5, bold: true, color: _C.ink),
        if (note != null) ...[
          pw.SizedBox(width: 5),
          pw.Expanded(child: _t(_fit(note, (width ?? _w) - 80, 6.5), 6.5, color: _C.muted)),
        ],
      ]),
    );
  }

  // ───────────────────────── tables ─────────────────────────

  static pw.Widget _table(SheetTable t, double width,
      {double font = _fBody, double rowH = _rowP1, double headH = _headP1, int minRows = 0, String empty = 'No data recorded'}) {
    final total = t.flex.fold<double>(0, (a, b) => a + b);
    final widths = [for (final f in t.flex) width * f / total];

    pw.Widget cell(String text, double w, double h,
        {PdfColor? bg, PdfColor? color, bool bold = false, bool left = false, double size = 0}) {
      return pw.Container(
        width: w,
        height: h,
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 1.5),
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
        child: pw.Text(_fit(text, w - 3, size == 0 ? font : size, bold: bold),
            style: pw.TextStyle(
                fontSize: size == 0 ? font : size,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? _C.text)),
      );
    }

    final rows = <pw.Widget>[
      pw.Row(children: [
        for (var i = 0; i < t.headers.length; i++)
          cell(t.headers[i], widths[i], headH,
              bg: _C.ink, color: PdfColors.white, bold: true, left: i == 0, size: _fHead),
      ]),
    ];
    for (var ri = 0; ri < t.rows.length; ri++) {
      final row = t.rows[ri];
      final zebra = ri.isOdd ? _C.surfaceAlt : null;
      rows.add(pw.Row(children: [
        for (var i = 0; i < row.length; i++)
          cell(row[i].text, widths[i], rowH,
              bg: row[i].tier != null ? _C.wash(row[i].tier!) : zebra,
              color: row[i].muted ? _C.muted : _C.text,
              bold: row[i].bold,
              left: row[i].left),
      ]));
    }
    if (t.rows.isEmpty) {
      rows.add(pw.Container(
        width: width,
        height: rowH,
        alignment: pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.only(left: 3),
        child: _t(empty, font, color: _C.muted),
      ));
    }
    final shown = t.rows.isEmpty ? 1 : t.rows.length;
    for (var i = shown; i < minRows; i++) {
      rows.add(pw.SizedBox(height: rowH, width: width));
    }
    return pw.Container(
      width: width,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _C.border, width: 0.5)),
      child: pw.Column(children: rows),
    );
  }

  static double _tableH(int rows, double rowH, double headH) => headH + (rows < 1 ? 1 : rows) * rowH + 1;

  // ───────────────────────── page 1 ─────────────────────────

  static pw.Widget _page1(ScoutingSheet s) {
    final half = (_w - _gap) / 2;
    final nGames = s.games.rows.length;
    final nPitch = s.pitches.rows.length;

    // Fixed band heights, so the Game Plan area gets exactly what is left.
    const summaryH = _secH + 42.0;
    final pitchH = _secH + _tableH(nPitch, _rowP1, _headP1) + 10;
    final bandAH = _secH + _tableH(nGames > 5 ? nGames : 5, _rowP1, _headP1) + 10;
    final bandBH = _secH + _tableH(5, _rowP1, _headP1) + 10;
    final planH = (_contentH - _headerH - _footerH) - (summaryH + pitchH + bandAH + bandBH + 5 * _gap);

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.SizedBox(height: _gap),
      // A. Team performance summary
      pw.SizedBox(height: summaryH, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _heading('Team performance vs this pitcher',
            note: 'Whole-opponent totals. ERA/WHIP use innings pitched; K%, BB% and XBH use plate appearances.'),
        _metricRow(s.summary),
      ])),
      pw.SizedBox(height: _gap),
      // C. Team-wide pitch effectiveness
      pw.SizedBox(height: pitchH, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _heading('Pitch effectiveness vs this team',
            note: 'Use = share of all pitches. Strike/Swing/Whiff are pitch-level rates; H-AB, AVG, XBH, K, BB count only at-bats that ENDED on that pitch.'),
        _table(s.pitches, _w, empty: 'No pitch data recorded'),
        pw.SizedBox(height: 1),
        _t('Pit = pitches thrown · Sw = swings (Whiff % = misses ÷ swings). Different measures: usage, strike rate and whiff rate are not interchangeable with AVG against.',
            6, color: _C.muted),
      ])),
      pw.SizedBox(height: _gap),
      // B (left) + D (right)
      pw.SizedBox(height: bandAH, child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: half, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _heading('Previous games', width: half, note: 'AVG, K%, BB% per game'),
          _table(s.games, half, empty: 'No games recorded'),
          pw.SizedBox(height: 1),
          _t(s.gamesHidden > 0
                  ? '${s.gamesHidden} earlier game(s) not listed; they are included in the team totals above.'
                  : 'ER = earned runs charged in that game.',
              6, color: _C.muted),
        ])),
        pw.SizedBox(width: _gap),
        pw.SizedBox(width: half, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _heading('Most dangerous hitters', width: half, note: 'ranked by OBP, min. 2 PA, top 5'),
          _table(s.dangerous, half, empty: 'Need 2+ PA from a hitter'),
          pw.SizedBox(height: 1),
          _t('Small samples: a high OBP over 2–4 PA is a note, not proof. Full cards on page 2.', 6, color: _C.muted),
        ])),
      ])),
      pw.SizedBox(height: _gap),
      // team counts (left) + struggled (right)
      pw.SizedBox(height: bandBH, child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: half, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _heading('Team results by count', width: half, note: 'Ahead/Even/Behind are exclusive'),
          _table(s.teamCounts, half, empty: 'No count data recorded'),
          pw.SizedBox(height: 1),
          _t('Pit/Sw/Whiff count every pitch thrown in that count; PA, H-AB, K, BB count at-bats that ENDED there. * overlaps rows above.',
              6, color: _C.muted),
        ])),
        pw.SizedBox(width: _gap),
        pw.SizedBox(width: half, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _heading('Hitters who have struggled', width: half, note: 'hitless, min. 2 PA'),
          _table(s.struggled, half, empty: 'No hitless hitter with 2+ PA'),
          pw.SizedBox(height: 1),
          _t('Recorded matchups only; not proof a hitter is weak. Details on each hitter\'s card.', 6, color: _C.muted),
        ])),
      ])),
      pw.SizedBox(height: _gap),
      // F. Game plan
      pw.SizedBox(height: planH, child: _gamePlan(s, planH)),
    ]);
  }

  static pw.Widget _metricRow(List<SheetMetric> ms) {
    const g = 3.0;
    final w = (_w - g * (ms.length - 1)) / ms.length;
    return pw.Row(children: [
      for (var i = 0; i < ms.length; i++) ...[
        if (i > 0) pw.SizedBox(width: g),
        _metricBox(ms[i], w, 42),
      ],
    ]);
  }

  static pw.Widget _metricBox(SheetMetric m, double w, double h) {
    final tier = m.tier;
    return pw.Container(
      width: w,
      height: h,
      decoration: pw.BoxDecoration(
        color: tier != null ? _C.wash(tier) : _C.tint,
        border: pw.Border.all(color: tier != null ? _C.solid(tier) : _C.border, width: tier != null ? 1.2 : 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        _t(m.label.toUpperCase(), 6.5, bold: true, color: _C.muted),
        _t(m.value, 15, bold: true, color: _C.ink),
        _t(m.sub, 6, color: _C.muted),
      ]),
    );
  }

  // ── F. Game plan: four columns, facts apart from suggestions ───────

  static pw.Widget _gamePlan(ScoutingSheet s, double height) {
    const g = 6.0;
    final colW = (_w - 3 * g) / 4;
    final bodyH = height - _secH - 2;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _heading('Game plan & key takeaways',
          note: 'Each line carries its confidence and sample. Observed = counted from recorded events; Suggested = an idea, not a guarantee.'),
      pw.SizedBox(height: 2),
      pw.SizedBox(
        height: bodyH,
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _planCol('Strengths to exploit', _C.perfExcellent, s.strengths, colW, bodyH),
          pw.SizedBox(width: g),
          _planCol('Potential weaknesses', _C.perfPoor, s.weaknesses, colW, bodyH),
          pw.SizedBox(width: g),
          _planCol('Suggested approaches', _C.accent, s.approaches, colW, bodyH),
          pw.SizedBox(width: g),
          _planCol('Cautions', _C.ink, s.cautions, colW, bodyH),
        ]),
      ),
    ]);
  }

  static pw.Widget _planCol(String title, PdfColor accent, List<SheetFinding> items, double w, double h) {
    const font = 7.5;
    const lineH = font * 1.433;
    const metaH = 6.5 * 1.433;
    const itemGap = 3.0;
    final inner = w - 7;
    var used = 13.0; // column title bar
    final widgets = <pw.Widget>[];
    var shown = 0;
    for (final f in items) {
      final rawLines = _lines(f.body, inner, font);
      final bodyLines = rawLines > 4 ? 4 : rawLines;
      final itemH = lineH + bodyLines * lineH + metaH + itemGap + 2;
      if (used + itemH + 9 > h) break; // keep room for the "+N more" line
      used += itemH;
      shown++;
      final body = _clip(f.body, (inner / (font * _teko)).floor() * 4 - 4);
      final meta = [f.tag, '${f.conf} conf.', if (f.sample.isNotEmpty) f.sample].where((e) => e != 'n/a conf.').join(' · ');
      widgets.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: itemGap),
        padding: const pw.EdgeInsets.only(left: 3),
        decoration: pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: accent, width: 1.5))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _t(_fit(f.headline, inner, font, bold: true), font, bold: true, color: _C.ink),
          _t(body, font),
          _t(_fit(meta, inner, 6.5), 6.5, color: _C.muted),
        ]),
      ));
    }
    final hidden = items.length - shown;
    return pw.SizedBox(
      width: w,
      height: h,
      child: pw.ClipRect(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
            width: w,
            height: 11,
            color: accent,
            padding: const pw.EdgeInsets.only(left: 3),
            alignment: pw.Alignment.centerLeft,
            child: _t(title.toUpperCase(), 7, bold: true, color: PdfColors.white),
          ),
          pw.SizedBox(height: 2),
          if (items.isEmpty)
            _t('None supported by the recorded data.', font, color: _C.muted),
          ...widgets,
          if (hidden > 0)
            _t('+$hidden more finding(s) not printed (no room); see the on-screen report.', 6.5, color: _C.muted),
        ]),
      ),
    );
  }

  static String _clip(String s, int maxChars) {
    if (maxChars < 8 || s.length <= maxChars) return s;
    return '${s.substring(0, maxChars - 1).trimRight()}…';
  }

  // ───────────────────────── page 2 ─────────────────────────

  /// Decides which hitters get a full card; the rest are listed in a compact
  /// roster table (jersey, hand, PA, H-AB, AVG/OBP/SLG) so no hitter vanishes
  /// from the printout. Hitters with the most plate appearances get the cards.
  static ScoutingPdfFit fitFor(List<HitterCard> cards) {
    final n = cards.length;
    if (n == 0) return const ScoutingPdfFit(0, 0, 0, 2, 0, []);
    final order = [for (var i = 0; i < n; i++) i]
      ..sort((a, b) {
        final c = cards[b].pa.compareTo(cards[a].pa);
        return c != 0 ? c : a.compareTo(b);
      });
    final avail = _contentH - _headerH - _footerH - _secH - 18 - _gap;
    var tallest = 0.0;
    for (final c in cards) {
      final h = _cardHeightOf(c);
      if (h > tallest) tallest = h;
    }
    for (var k = n; k >= 0; k--) {
      final idx = order.take(k).toList()..sort();
      final cardsH = _rowsHeight(cards, idx);
      final stubs = n - k;
      final stubH = stubs == 0 ? 0.0 : _gap + _secH + _tableH(stubs, _rowCard, _headCard) + 12;
      if (cardsH + stubH <= avail) return ScoutingPdfFit(n, k, stubs, 2, tallest, idx);
    }
    return ScoutingPdfFit(n, 0, n, 2, tallest, const []);
  }

  /// Total height of the card rows (two cards per row, row height = taller
  /// of the pair) for the hitters at [idx], including the gaps between rows.
  static double _rowsHeight(List<HitterCard> cards, List<int> idx) {
    var total = 0.0;
    for (var i = 0; i < idx.length; i += 2) {
      var m = _cardHeightOf(cards[idx[i]]);
      if (i + 1 < idx.length) {
        final b = _cardHeightOf(cards[idx[i + 1]]);
        if (b > m) m = b;
      }
      total += m;
      if (i + 2 < idx.length) total += 4;
    }
    return total;
  }

  /// Height one card needs for ITS content: 5 count rows always, one pitch row
  /// per recorded pitch type (capped), and its own note lines.
  static double _cardHeightOf(HitterCard c) {
    var pitchRows = c.pitchTable.rows.length;
    if (pitchRows < 1) pitchRows = 1;
    if (pitchRows > _maxPitchRows) pitchRows = _maxPitchRows;
    const cw = (_w - _gap) / 2;
    var notesH = 0.0;
    for (final n in c.notes) {
      notesH += _noteLines(n, cw - 8) * (_fCard * 1.433);
    }
    return 16 + 2 + 17 + 2 + _tableH(pitchRows, _rowCard, _headCard) + 2 + _tableH(5, _rowCard, _headCard) + 2 + notesH + 8;
  }

  static int _noteLines(SheetNote n, double width) {
    final perLine = (width / (_fCard * _teko)).floor();
    final prefix = '${n.label} · ${n.tag} · ${n.conf}: ';
    final est = prefix.length * (_tekoB / _teko) + _clipNote(n, width).length;
    return est <= perLine ? 1 : 2;
  }

  /// Note text shortened (with an ellipsis) so prefix + text fit in two lines.
  static String _clipNote(SheetNote n, double width) {
    final perLine = (width / (_fCard * _teko)).floor();
    final prefix = '${n.label} · ${n.tag} · ${n.conf}: ';
    final cap = perLine * 2 - (prefix.length * (_tekoB / _teko)).ceil() - 4;
    return _clip(n.text, cap);
  }

  static pw.Widget _page2(ScoutingSheet s, ScoutingPdfFit fit) {
    final cards = s.cards;
    if (cards.isEmpty) {
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(height: _gap),
        _heading('Hitter scouting cards'),
        pw.SizedBox(height: 4),
        _t('No hitter has a recorded jersey number, so no hitter cards can be built. Add jersey numbers in Game Input.', 9, color: _C.muted),
      ]);
    }
    final fullSet = fit.fullIdx.toSet();
    final full = [for (final i in fit.fullIdx) cards[i]];
    final stubs = [for (var i = 0; i < cards.length; i++) if (!fullSet.contains(i)) cards[i]];

    const cw = (_w - _gap) / 2;
    final rows = <pw.Widget>[];
    for (var i = 0; i < full.length; i += 2) {
      var rowH = _cardHeightOf(full[i]);
      if (i + 1 < full.length) {
        final b = _cardHeightOf(full[i + 1]);
        if (b > rowH) rowH = b;
      }
      rows.add(pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _card(full[i], cw, rowH),
        pw.SizedBox(width: _gap),
        i + 1 < full.length ? _card(full[i + 1], cw, rowH) : pw.SizedBox(width: cw),
      ]));
      if (i + 2 < full.length) rows.add(pw.SizedBox(height: 4));
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.SizedBox(height: _gap),
      _heading('Individual hitter scouting cards',
          note: 'AVG/OBP/SLG are the hitter\'s numbers against this pitcher; heat is from the pitcher\'s view.'),
      pw.SizedBox(
        height: 18,
        child: _t(
            'Pitch rows: Pit = pitches, Use = share of that hitter\'s pitches, H-AB/AVG = at-bats ended on that pitch, Wh/Sw = misses over swings. '
            'Count rows: Pit/Sw/Whiff = every pitch in that count; PA, H-AB, K, BB, AVG = at-bats that ended there.',
            6, color: _C.muted),
      ),
      ...rows,
      if (stubs.isNotEmpty) ...[
        pw.SizedBox(height: _gap),
        _heading('Remaining hitters (no room for a full card)',
            note: '${stubs.length} of ${cards.length} hitters; full card on screen'),
        _table(_stubTable(stubs), _w),
        pw.SizedBox(height: 2),
        _t('Pitch-type and count detail for these hitters is in the on-screen report; their batting lines are not omitted.',
            6, color: _C.muted),
      ],
    ]);
  }

  static SheetTable _stubTable(List<HitterCard> hs) {
    return SheetTable(
      ['#', 'Hand', 'PA', 'AB', 'H-AB', 'AVG', 'OBP', 'SLG', 'Conf'],
      [
        for (final h in hs)
          [
            SheetCell('#${h.jersey}', bold: true, left: true),
            SheetCell(h.hand),
            SheetCell('${h.pa}'),
            SheetCell('${h.ab}'),
            SheetCell(h.hAb),
            SheetCell(h.avg.value, tier: h.avg.tier),
            SheetCell(h.obp.value, tier: h.obp.tier),
            SheetCell(h.slg.value, tier: h.slg.tier),
            SheetCell(h.conf, muted: true),
          ],
      ],
      [1.2, 1.3, 0.8, 0.8, 1.1, 1, 1, 1, 1.3],
    );
  }

  // ── one hitter card ────────────────────────────────────────────────

  static pw.Widget _card(HitterCard c, double w, double h) {
    final inner = w - 6;
    // Cap the pitch table so every card keeps the same height.
    var pt = c.pitchTable;
    if (pt.rows.length > _maxPitchRows) {
      final extra = pt.rows.length - (_maxPitchRows - 1);
      final cut = pt.rows.take(_maxPitchRows - 1).toList()
        ..add([
          SheetCell('+$extra types', muted: true, left: true),
          ...List.generate(pt.headers.length - 1, (_) => const SheetCell('')),
        ]);
      pt = SheetTable(pt.headers, cut, pt.flex);
    }
    final metricW = (inner - 8) / 3;

    return pw.SizedBox(
      width: w,
      height: h,
      child: pw.ClipRect(
        child: pw.Container(
          width: w,
          height: h,
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _C.border, width: 0.8),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            // identification
            pw.SizedBox(
              height: 16,
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                  decoration: pw.BoxDecoration(color: _C.ink, borderRadius: pw.BorderRadius.circular(2)),
                  child: _t('#${c.jersey}', 10, bold: true, color: PdfColors.white),
                ),
                pw.SizedBox(width: 4),
                _t(c.hand, 10, bold: true, color: _C.accent),
                pw.Spacer(),
                _t('${c.pa} PA · ${c.ab} AB · ${c.games} G · ${c.conf} conf.', 6.5, color: _C.muted),
              ]),
            ),
            pw.SizedBox(height: 2),
            // AVG / OBP / SLG
            pw.SizedBox(
              height: 17,
              child: pw.Row(children: [
                _batBox(c.avg, metricW),
                pw.SizedBox(width: 4),
                _batBox(c.obp, metricW),
                pw.SizedBox(width: 4),
                _batBox(c.slg, metricW),
              ]),
            ),
            pw.SizedBox(height: 2),
            _table(pt, inner,
                font: _fCard, rowH: _rowCard, headH: _headCard, empty: 'No pitches recorded'),
            pw.SizedBox(height: 2),
            _table(c.countTable, inner, font: _fCard, rowH: _rowCard, headH: _headCard),
            pw.SizedBox(height: 2),
            for (final n in c.notes) _note(n, inner),
          ]),
        ),
      ),
    );
  }

  static pw.Widget _batBox(SheetMetric m, double w) {
    final tier = m.tier;
    return pw.Container(
      width: w,
      height: 17,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3),
      decoration: pw.BoxDecoration(
        color: tier != null ? _C.wash(tier) : _C.tint,
        border: pw.Border.all(color: tier != null ? _C.solid(tier) : _C.border, width: tier != null ? 1 : 0.5),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        _t(m.label, 6.5, bold: true, color: _C.muted),
        pw.Spacer(),
        if (m.sub.isNotEmpty) ...[
          _t(m.sub, 6, color: _C.muted),
          pw.SizedBox(width: 3),
        ],
        _t(m.value, 11, bold: true, color: _C.ink),
      ]),
    );
  }

  static pw.Widget _note(SheetNote n, double width) {
    final prefix = '${n.label} · ${n.tag} · ${n.conf}: ';
    final lines = _noteLines(n, width);
    return pw.Container(
      height: lines * (_fCard * 1.433) + 0.5,
      width: width,
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(fontSize: _fCard, color: _C.text),
          children: [
            pw.TextSpan(
                text: prefix,
                style: pw.TextStyle(fontSize: _fCard, fontWeight: pw.FontWeight.bold, color: _noteColor(n.label))),
            pw.TextSpan(text: _clipNote(n, width)),
          ],
        ),
      ),
    );
  }

  static PdfColor _noteColor(String label) {
    if (label == 'Potential weakness') return _C.perfExcellent; // hitter weak spot = good for the pitcher
    if (label == 'Caution') return _C.perfPoor;
    return _C.accent;
  }
}
