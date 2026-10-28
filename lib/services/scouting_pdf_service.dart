import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/pitch_event.dart';
import '../theme/app_theme.dart' show AppColors, ScaleStyle;
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
  static final perfExcellent = PdfColor.fromInt(0xFF0F6B32);
  static final perfAverage = PdfColor.fromInt(0xFFFACC15);
  static final perfPoor = PdfColor.fromInt(0xFFDC2626);

  /// Heat-map fill: exactly the app's own wash of the tier color
  /// ([ScaleStyle.fillAny]); the number inside is always dark text.
  static PdfColor wash(Color tier) => PdfColor.fromInt(ScaleStyle.fillAny(tier).value);
  static PdfColor solid(Color tier) => PdfColor.fromInt(tier.value);
}

/// How the hitter cards were laid out. Every hitter now gets their own card
/// (one per page in the PDF), so [fullCards] always equals [totalHitters] and
/// there is never a roster-only remainder.
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

/// Builds the US Letter Scouting Report PDF.
///
/// Page 1 = team overview. Then ONE page per hitter, each a full individual
/// scouting card with the same design, so the page count is 1 + the number of
/// eligible hitters (never hard-coded) and each card starts on its own page.
/// Every row has a fixed height so the layout is deterministic.
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

    // The same branded field photo the in-app spray chart uses (dots are
    // placed with the same field coordinate system). If it cannot be read the
    // chart falls back to a plain green field so export never fails.
    pw.MemoryImage? field;
    try {
      final bytes = await rootBundle.load('assets/images/field_bg.png');
      field = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      field = null;
    }

    final sheet = ScoutingSheet.build(r);
    final fit = fitFor(sheet.cards);
    final doc = pw.Document(theme: theme);
    final margin = const pw.EdgeInsets.fromLTRB(_mL, _mT, _mL, _mT);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: margin,
      build: (ctx) => _pageShell(logo, sheet, 1, 1 + (sheet.cards.isEmpty ? 1 : sheet.cards.length), _page1(sheet)),
    ));
    final pageCount = 1 + sheet.cards.length;
    if (sheet.cards.isEmpty) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: margin,
        build: (ctx) => _pageShell(logo, sheet, 2, 2, _noCards()),
      ));
    }
    for (var i = 0; i < sheet.cards.length; i++) {
      final card = sheet.cards[i];
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: margin,
        build: (ctx) => _pageShell(logo, sheet, i + 2, pageCount, _hitterPage(card, field)),
      ));
    }
    return doc.save();
  }

  // ───────────────────────── shared pieces ─────────────────────────

  static pw.Widget _t(String s, double size,
      {bool bold = false, PdfColor? color, pw.TextAlign? align}) {
    // The Teko font has no arrow glyph; use plain ">" so nothing prints blank.
    return pw.Text(s.replaceAll('→', '>'),
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

  static pw.Widget _pageShell(pw.MemoryImage? logo, ScoutingSheet sh, int page, int pages, pw.Widget body) {
    final r = sh.r;
    final threat = r.threatLevel == 'high'
        ? _C.perfPoor
        : (r.threatLevel == 'medium' ? _C.perfAverage : _C.perfExcellent);
    final threatText = r.threatLevel == 'medium' ? _C.text : PdfColors.white;
    final title = page == 1 ? 'SCOUTING REPORT: ${r.team.toUpperCase()}' : 'HITTER SCOUTING CARD: ${r.team.toUpperCase()}';
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
            _t('${r.gamesFaced} game${r.gamesFaced == 1 ? '' : 's'} · $today · Page $page of $pages', 7.5, color: _C.muted),
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
      {double font = _fBody, double rowH = _rowP1, double headH = _headP1, int minRows = 0, String empty = 'No data recorded', bool heat = true}) {
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
              bg: (heat && row[i].tier != null) ? _C.wash(row[i].tier!) : zebra,
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
        _t('P = pitches thrown · Sw = swings (Whiff % = misses ÷ swings). Different measures: usage, strike rate and whiff rate are not interchangeable with AVG against.',
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
          _t('Small samples: a high OBP over 2–4 PA is a note, not proof. Each hitter has their own card on the pages that follow.', 6, color: _C.muted),
        ])),
      ])),
      pw.SizedBox(height: _gap),
      // team counts (left) + struggled (right)
      pw.SizedBox(height: bandBH, child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: half, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _heading('Team results by count', width: half, note: 'Ahead/Even/Behind are exclusive'),
          _table(s.teamCounts, half, empty: 'No count data recorded'),
          pw.SizedBox(height: 1),
          _t('P/Sw/Whiff count every pitch thrown in that count; PA, H-AB, K, BB count at-bats that ENDED there. * overlaps rows above.',
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

  // ───────────────────── hitter pages (one per hitter) ─────────────────────

  /// Decides which hitters get a full card; the rest are listed in a compact
  /// roster table (jersey, hand, PA, H-AB, AVG/OBP/SLG) so no hitter vanishes
  /// from the printout. Hitters with the most plate appearances get the cards.
  static ScoutingPdfFit fitFor(List<HitterCard> cards) {
    final n = cards.length;
    return ScoutingPdfFit(n, n, 0, 1, 0, [for (var i = 0; i < n; i++) i]);
  }

  static pw.Widget _noCards() {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(height: _gap),
      _heading('Hitter scouting cards'),
      pw.SizedBox(height: 4),
      _t('No hitter has a recorded jersey number, so no hitter cards can be built. Add jersey numbers in Game Input.', 9, color: _C.muted),
    ]);
  }

  // ── one hitter per page ────────────────────────────────────────────

  static const double _fFull = 9, _rowFull = 15, _headFull = 13;

  /// A full-page individual card. Nothing is capped or clipped: every pitch
  /// type, every count row and every note for THIS hitter is printed.
  static pw.Widget _hitterPage(HitterCard c, pw.MemoryImage? field) {
    final inner = _w - 12;
    final metricW = (inner - 12) / 3;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.SizedBox(height: _gap),
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: _C.border, width: 0.8),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(
            height: 28,
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: pw.BoxDecoration(color: _C.ink, borderRadius: pw.BorderRadius.circular(3)),
                child: _t('#${c.jersey}', 20, bold: true, color: PdfColors.white),
              ),
              pw.SizedBox(width: 8),
              _t('Bats: ${c.hand}', 16, bold: true, color: _C.accent),
              pw.Spacer(),
              _t('Plate Appearances: ${c.pa} · At-Bats: ${c.ab} · Games: ${c.games} · ${c.conf} confidence', 9, color: _C.muted),
            ]),
          ),
          pw.SizedBox(height: 6),
          pw.SizedBox(
            height: 30,
            child: pw.Row(children: [
              _batBox(c.avg, metricW, 30),
              pw.SizedBox(width: 6),
              _batBox(c.obp, metricW, 30),
              pw.SizedBox(width: 6),
              _batBox(c.slg, metricW, 30),
            ]),
          ),
          pw.SizedBox(height: 4),
          _t('AVG/OBP/SLG are this hitter\'s numbers against this pitcher; heat is from the pitcher\'s view. Only these three boxes are colored.', 7, color: _C.muted),
          pw.SizedBox(height: 6),
          _heading('By pitch type',
              note: 'P = pitches, Use = share of his pitches, H-AB/AVG = at-bats ended on that pitch, Wh/Sw = misses over swings'),
          pw.SizedBox(height: 2),
          _table(c.pitchTable, inner, font: _fFull, rowH: _rowFull, headH: _headFull, empty: 'No pitches recorded', heat: false),
          pw.SizedBox(height: 8),
          _heading('By count',
              note: 'P/Sw/Whiff = every pitch in that count; PA, H-AB, K, BB, AVG = at-bats that ended there'),
          pw.SizedBox(height: 2),
          _table(c.countTable, inner, font: _fFull, rowH: _rowFull, headH: _headFull, heat: false),
          pw.SizedBox(height: 8),
          _sequencingAndSpray(c, inner, field),
          pw.SizedBox(height: 8),
          for (final n in c.notes) ...[
            _fullNote(n, inner),
            pw.SizedBox(height: 3),
          ],
        ]),
      ),
    ]);
  }

  // ── Pitch Sequencing + Spray Chart (this hitter only) ───────────────
  static const double _sprayW = 176;
  static const double _seqFont = 7.5, _seqRow = 10.5, _seqHead = 10;

  static pw.Widget _sequencingAndSpray(HitterCard c, double inner, pw.MemoryImage? field) {
    const gap = 8.0;
    final leftW = inner - _sprayW - gap;
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(
        width: leftW,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _heading('Pitch sequencing', width: leftW, note: 'this hitter only'),
          pw.SizedBox(height: 2),
          _t(c.sequenceNote, 6.5, color: _C.muted),
          pw.SizedBox(height: 3),
          _table(c.paTable, leftW,
              font: _seqFont,
              rowH: _seqRow,
              headH: _seqHead,
              empty: 'No finished plate appearances recorded',
              heat: false),
        ]),
      ),
      pw.SizedBox(width: gap),
      pw.SizedBox(
        width: _sprayW,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _heading('Spray chart', width: _sprayW, note: 'recorded locations'),
          pw.SizedBox(height: 3),
          _sprayChart(c.sprayPoints, _sprayW, field),
          pw.SizedBox(height: 2),
          _t(
              c.sprayPoints.isEmpty
                  ? (c.sprayMissing > 0
                      ? '${c.sprayMissing} ball${c.sprayMissing == 1 ? '' : 's'} in play had no location recorded.'
                      : 'No ball in play with a recorded location yet.')
                  : 'Balls in play plotted: ${c.sprayPoints.length}.'
                      '${c.sprayMissing > 0 ? ' ${c.sprayMissing} more had no location and are not drawn.' : ''}'
                      ' Fill = result, ring = pitch hit. Dotted = ground ball, straight = line drive, arc = fly ball.',
              6,
              color: _C.muted),
        ]),
      ),
    ]);
  }

  // Same constants and mapping as BaseballFieldPainter (field x -400..400,
  // y -80..400; home plate sits at 49.92% / 95.22% of the picture).
  static const double _fMinX = -400, _fMaxX = 400, _fMinY = -80, _fMaxY = 400;
  static const double _homeFx = 0.4992, _homeFy = 0.9522;

  static pw.Widget _sprayChart(List<PitchEvent> pts, double side, pw.MemoryImage? field) {
    PdfColor col(Color c) => PdfColor.fromInt(c.value);
    // (x, y) in points, origin top-left of the square.
    (double, double) toBox(double fx, double fy) {
      final nx = (fx - _fMinX) / (_fMaxX - _fMinX);
      final ny = (fy - _fMinY) / (_fMaxY - _fMinY);
      return (nx * side, side - ny * side);
    }

    final located = [
      for (final p in pts)
        if (p.xCoord != null && p.yCoord != null) p,
    ];
    final homeX = _homeFx * side, homeY = _homeFy * side;

    final lines = pw.CustomPaint(
      size: PdfPoint(side, side),
      painter: (PdfGraphics g, PdfPoint size) {
        g.setStrokeColor(PdfColors.white);
        g.setLineWidth(0.9);
        for (final p in located) {
          if (p.battedType == null) continue;
          final e = toBox(p.xCoord!, p.yCoord!);
          // PDF y runs upward; flip our top-left origin.
          final x0 = homeX, y0 = side - homeY, x1 = e.$1, y1 = side - e.$2;
          switch (p.battedType) {
            case 'gb':
              g.setLineDashPattern([3, 2.5]);
              g.moveTo(x0, y0);
              g.lineTo(x1, y1);
              g.strokePath();
              g.setLineDashPattern();
              break;
            case 'ld':
              g.moveTo(x0, y0);
              g.lineTo(x1, y1);
              g.strokePath();
              break;
            case 'fb':
              final mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
              final dx = x1 - x0, dy = y1 - y0;
              final len = (dx * dx + dy * dy) == 0 ? 0.0 : _sqrt(dx * dx + dy * dy);
              if (len == 0) break;
              // bow the arc like the app does (18% of the shot length)
              final cx = mx + (-dy / len) * len * 0.18, cy = my + (dx / len) * len * 0.18;
              g.moveTo(x0, y0);
              g.curveTo(x0 + 2 / 3 * (cx - x0), y0 + 2 / 3 * (cy - y0), x1 + 2 / 3 * (cx - x1),
                  y1 + 2 / 3 * (cy - y1), x1, y1);
              g.strokePath();
              break;
          }
        }
      },
    );

    final dots = <pw.Widget>[
      for (final p in located)
        () {
          final pos = toBox(p.xCoord!, p.yCoord!);
          const r = 3.6;
          return pw.Positioned(
            left: pos.$1 - r,
            top: pos.$2 - r,
            child: pw.Container(
              width: r * 2,
              height: r * 2,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: col(AppColors.sprayColor(p.outcome)),
                border: pw.Border.all(color: col(AppColors.pitchColor(p.pitchType)), width: 1.1),
              ),
            ),
          );
        }(),
    ];

    return pw.Container(
      width: side,
      height: side,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF4F8A3C),
        border: pw.Border.all(color: _C.border, width: 0.5),
      ),
      child: pw.ClipRect(
        child: pw.Stack(fit: pw.StackFit.expand, children: [
          if (field != null) pw.Positioned.fill(child: pw.Image(field, fit: pw.BoxFit.cover)),
          pw.Positioned.fill(child: lines),
          ...dots,
          if (located.isEmpty)
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: PdfColors.white,
                child: _t('No recorded locations', 8, color: _C.muted),
              ),
            ),
        ]),
      ),
    );
  }

  static double _sqrt(double v) => v <= 0 ? 0 : math.sqrt(v);

  static pw.Widget _fullNote(SheetNote n, double width) {
    final prefix = '${n.label} · ${n.tag} · ${n.conf}: ';
    return pw.SizedBox(
      width: width,
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(fontSize: 10, color: _C.text),
          children: [
            pw.TextSpan(text: prefix, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _noteColor(n.label))),
            pw.TextSpan(text: n.text),
          ],
        ),
      ),
    );
  }

  static pw.Widget _batBox(SheetMetric m, double w, double h) {
    final tier = m.tier;
    return pw.Container(
      width: w,
      height: h,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3),
      decoration: pw.BoxDecoration(
        color: tier != null ? _C.wash(tier) : _C.tint,
        border: pw.Border.all(color: tier != null ? _C.solid(tier) : _C.border, width: tier != null ? 1 : 0.5),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        _t(m.label, 10, bold: true, color: _C.muted),
        pw.Spacer(),
        if (m.sub.isNotEmpty) ...[
          _t(m.sub, 8, color: _C.muted),
          pw.SizedBox(width: 4),
        ],
        _t(m.value, 18, bold: true, color: _C.ink),
      ]),
    );
  }

  static PdfColor _noteColor(String label) {
    if (label == 'Potential weakness') return _C.perfExcellent; // hitter weak spot = good for the pitcher
    if (label == 'Caution') return _C.perfPoor;
    return _C.accent;
  }
}
