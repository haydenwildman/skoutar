import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/pitch_event.dart';
import 'scouting_report_data.dart';

/// PDF brand colors — same hex values as [AppColors] in app_theme.dart,
/// just re-expressed as PdfColor since the `pdf` package can't consume
/// Flutter's `Color` directly.
class _PdfColors {
  static final ink = PdfColor.fromInt(0xFF26201C);
  static final accent = PdfColor.fromInt(0xFFC94F1B);
  static final tint = PdfColor.fromInt(0xFFFDF1E4);
  static final colText = PdfColor.fromInt(0xFF1C1917);
  static final colMuted = PdfColor.fromInt(0xFF78716C);
  static final colBorder = PdfColor.fromInt(0xFFE7DCCF);
  static final colSuccess = PdfColor.fromInt(0xFF22C55E);
  static final colError = PdfColor.fromInt(0xFFEF4444);

  static final perfExcellent = PdfColor.fromInt(0xFF15803D);
  static final perfGood = PdfColor.fromInt(0xFF4ADE80);
  static final perfAverage = PdfColor.fromInt(0xFFFACC15);
  static final perfBelowAvg = PdfColor.fromInt(0xFFFB923C);
  static final perfPoor = PdfColor.fromInt(0xFFDC2626);

  static final goodFill = PdfColor.fromInt(0xFFF0FDF4);
  static final badFill = PdfColor.fromInt(0xFFFEF2F2);

  static PdfColor onColor(PdfColor bg) =>
      (bg == perfExcellent || bg == perfPoor || bg == perfBelowAvg) ? PdfColors.white : colText;
}

/// Builds a professional, multi-page PDF export of a Scouting Report.
/// Every section shown on screen (summary, strengths/weaknesses, approach,
/// attack plan, key hitters, spray chart, adjustment notes) is included so
/// the PDF is a complete standalone copy of the report.
class ScoutingPdfService {
  static String _fmtAvg(double v) {
    final s = v.toStringAsFixed(3);
    return s.startsWith('0.') ? s.substring(1) : s;
  }

  static PdfColor _perfHex(String stat, double? value) {
    if (value == null) return _PdfColors.tint;
    // Mirrors StatsService.perfHex()'s tiering closely enough for the PDF's
    // purposes — pulls the same thresholds used across the app for the
    // stats that appear on the scouting report.
    double v = value;
    // Normalize a 0-1 scale roughly using known good/bad bounds per stat.
    double frac;
    switch (stat) {
      case 'AVG':
        frac = 1 - (v / 0.350).clamp(0.0, 1.0);
        break;
      case 'K_pct':
        frac = (v / 35).clamp(0.0, 1.0);
        break;
      case 'BB_pct':
      case 'OBP_allowed':
        frac = 1 - (v / 0.450).clamp(0.0, 1.0);
        break;
      case 'whiff_pct':
        frac = (v / 40).clamp(0.0, 1.0);
        break;
      case 'f_strike':
        frac = (v / 75).clamp(0.0, 1.0);
        break;
      default:
        frac = 0.5;
    }
    if (frac >= 0.8) return _PdfColors.perfExcellent;
    if (frac >= 0.6) return _PdfColors.perfGood;
    if (frac >= 0.4) return _PdfColors.perfAverage;
    if (frac >= 0.2) return _PdfColors.perfBelowAvg;
    return _PdfColors.perfPoor;
  }

  static Future<Uint8List> generate(ScoutingReportData r) async {
    // SKOUTAR typeface: Teko (bundled), regular + bold. Falls back to the
    // PDF default font if the assets can't be read, so export never fails.
    pw.ThemeData? pdfTheme;
    try {
      final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/Teko-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Teko-Bold.ttf'));
      pdfTheme = pw.ThemeData.withFont(base: reg, bold: bold, italic: reg, boldItalic: bold);
    } catch (_) {
      pdfTheme = null;
    }
    final doc = pw.Document(theme: pdfTheme);
    pw.MemoryImage? logo;
    try {
      // Use the 2x variant so the PDF logo stays sharp; fall back to the base file.
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

    final threatColor = r.threatLevel == 'high'
        ? _PdfColors.perfPoor
        : (r.threatLevel == 'medium' ? _PdfColors.perfAverage : _PdfColors.perfExcellent);
    final threatTextColor = r.threatLevel == 'medium' ? _PdfColors.colText : PdfColors.white;

    final withAvgRows = r.breakdown.where((b) => b['avgAgainst'] != null).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
        header: (context) => _header(logo, r, threatColor, threatTextColor),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _PdfColors.colMuted),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 8),
          _summaryStatsRow(r),
          pw.SizedBox(height: 12),
          _threePillets(r),
          pw.SizedBox(height: 14),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: _whatWorksCard(r)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _whatGetsHitCard(r)),
          ]),
          pw.SizedBox(height: 10),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: _theirApproachCard(r, withAvgRows)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _attackPlanCard(r)),
          ]),
          pw.SizedBox(height: 10),
          _keyHittersCard(r),
          pw.SizedBox(height: 10),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(flex: 5, child: _sprayChartCard(r)),
            pw.SizedBox(width: 10),
            pw.Expanded(flex: 6, child: _adjustmentNotesCard(r)),
          ]),
        ],
      ),
    );

    return doc.save();
  }

  // ── Header ───────────────────────────────────────────────────────
  static pw.Widget _header(
      pw.MemoryImage? logo, ScoutingReportData r, PdfColor threatColor, PdfColor threatTextColor) {
    return pw.Column(children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logo != null) ...[
          pw.Image(logo, width: 48, height: 38, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Scouting Report: ${r.team.toUpperCase()}',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _PdfColors.ink)),
            pw.Text('${r.gamesFaced} game(s) faced  •  Generated ${DateTime.now().toString().split('.').first}',
                style: pw.TextStyle(fontSize: 9, color: _PdfColors.colMuted)),
          ]),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: pw.BoxDecoration(color: threatColor, borderRadius: pw.BorderRadius.circular(14)),
          child: pw.Text('${r.threatLevel.toUpperCase()} THREAT',
              style: pw.TextStyle(color: threatTextColor, fontWeight: pw.FontWeight.bold, fontSize: 10)),
        ),
      ]),
      pw.SizedBox(height: 6),
      pw.Divider(color: _PdfColors.colBorder, thickness: 1),
    ]);
  }

  // ── Summary stat row ─────────────────────────────────────────────
  static pw.Widget _summaryStatsRow(ScoutingReportData r) {
    final s = r.stats;
    pw.Widget statChip(String label, String value, PdfColor bg) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 2),
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(children: [
              pw.Text(label.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold, color: _PdfColors.onColor(bg))),
              pw.SizedBox(height: 2),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold, color: _PdfColors.onColor(bg))),
            ]),
          ),
        );
    return pw.Row(children: [
      statChip('PA', '${r.pa}', _PdfColors.tint),
      statChip('AVG', s.avg?.toStringAsFixed(3) ?? 'N/A', _perfHex('AVG', s.avg)),
      statChip('K%', s.kPct != null ? '${s.kPct}%' : 'N/A', _perfHex('K_pct', s.kPct)),
      statChip('BB%', s.bbPct != null ? '${s.bbPct}%' : 'N/A', _perfHex('BB_pct', s.bbPct)),
      statChip('Whiff%', s.whiffPct != null ? '${s.whiffPct}%' : 'N/A', _perfHex('whiff_pct', s.whiffPct)),
      statChip('XBH', '${r.xbh}', _PdfColors.badFill),
    ]);
  }

  static pw.Widget _pilletBox(String title, String body, PdfColor bg, PdfColor titleColor) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: bg,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: titleColor, width: 0.75),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(title, style: pw.TextStyle(color: titleColor, fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.SizedBox(height: 3),
            pw.Text(body, style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
      );

  static pw.Widget _threePillets(ScoutingReportData r) {
    final s = r.stats;
    final strength = r.bestPitch != null
        ? 'Best pitch: ${(r.bestPitch!['pitchType'] as String).toUpperCase()} (${r.bestPitch!['whiffPct']}% whiff)'
        : (s.kPct != null && s.kPct! >= 20 ? "Getting K's — K%: ${s.kPct}%" : "Build on what's working");
    final weakness = s.bbPct != null && s.bbPct! > 12
        ? 'Walk rate high — ${s.bbPct}% BB'
        : (r.worstPitch != null
            ? 'Most hittable: ${(r.worstPitch!['pitchType'] as String).toUpperCase()} (${_fmtAvg(r.worstPitch!['avgAgainst'] as double)} AVG)'
            : 'Hold the line — no major leaks');
    final plan = r.threatLevel == 'high'
        ? 'Attack the zone. Win pitch 1. Use your best whiff pitch in 2-strike counts.'
        : (r.threatLevel == 'medium'
            ? 'Limit XBH. Mix speeds. Trust your sequencing.'
            : 'Cruise mode. Throw strikes. Finish ABs efficiently.');
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _pilletBox('STRENGTH', strength, _PdfColors.goodFill, _PdfColors.perfExcellent),
      _pilletBox('WEAKNESS', weakness, _PdfColors.badFill, _PdfColors.colError),
      _pilletBox('QUICK PLAN', plan, _PdfColors.tint, _PdfColors.ink),
    ]);
  }

  static pw.Widget _sectionCard(String title, List<pw.Widget> children) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _PdfColors.colBorder, width: 0.75),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 6),
          ...children,
        ]),
      );

  static pw.Widget _tinyCard(String head, String sub, bool good) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 5),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: good ? _PdfColors.goodFill : _PdfColors.badFill,
          border: pw.Border.all(color: good ? _PdfColors.colSuccess : _PdfColors.colError, width: 1),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(head,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9.5,
                  color: good ? _PdfColors.perfExcellent : _PdfColors.colError)),
          pw.Text(sub, style: pw.TextStyle(fontSize: 8.5, color: _PdfColors.colMuted)),
        ]),
      );

  static pw.Widget _whatWorksCard(ScoutingReportData r) {
    final items = <pw.Widget>[];
    if (r.bestPitch != null) {
      items.add(_tinyCard(
        '${(r.bestPitch!['pitchType'] as String).toUpperCase()} — highest whiff rate',
        'Whiff%: ${r.bestPitch!['whiffPct']}% against this team',
        true,
      ));
    }
    for (final s in r.bestSeqs.take(3)) {
      items.add(_tinyCard(
          s['seq'] as String, 'Score ${s['score']}  |  Out%: ${s['outPct']}%  K%: ${s['kPct']}%  n=${s['count']}', true));
    }
    if (r.cd['fpsPct'] != null && (r.cd['fpsPct'] as double) >= 60) {
      items.add(_tinyCard('F-Strike% — ${r.cd['fpsPct']}%',
          'After a first-pitch strike, OBP: ${r.cd['fpsOBP'] != null ? (r.cd['fpsOBP'] as double).toStringAsFixed(3) : 'N/A'}',
          true));
    }
    if (r.cd['aheadOBP'] != null && (r.cd['aheadOBP'] as double) < 0.300) {
      items.add(_tinyCard('Ahead in count → low damage',
          'OBP when pitcher ahead: ${(r.cd['aheadOBP'] as double).toStringAsFixed(3)}', true));
    }
    if (items.isEmpty) {
      items.add(pw.Text('Not enough data yet for this opponent.', style: pw.TextStyle(fontSize: 9, color: _PdfColors.colMuted)));
    }
    return _sectionCard('What Works vs This Team', items);
  }

  static pw.Widget _whatGetsHitCard(ScoutingReportData r) {
    final items = <pw.Widget>[];
    if (r.worstPitch != null) {
      items.add(_tinyCard(
        '${(r.worstPitch!['pitchType'] as String).toUpperCase()} — most hittable',
        'AVG: ${_fmtAvg(r.worstPitch!['avgAgainst'] as double)} — reduce usage in hitter counts',
        false,
      ));
    }
    for (final s in r.avoidSeqs.take(2)) {
      if ((s['outPct'] as double) < 60) {
        items.add(_tinyCard(s['seq'] as String, 'Score ${s['score']}  |  Out%: ${s['outPct']}%  n=${s['count']}', false));
      }
    }
    if (r.topDamage != null) {
      items.add(_tinyCard('Count ${r.topDamage!['count']} — most damage',
          'OBP: ${(r.topDamage!['obp'] as double).toStringAsFixed(3)} in ${r.topDamage!['n']} PA', false));
    }
    if (r.cd['behindOBP'] != null && (r.cd['behindOBP'] as double) > 0.400) {
      items.add(_tinyCard('Behind in count → big trouble',
          'OBP when pitcher behind: ${(r.cd['behindOBP'] as double).toStringAsFixed(3)}', false));
    }
    if (r.xbh >= 3) {
      items.add(_tinyCard('Extra-base power threat', '${r.xbh} XBH including ${r.hr} HR — keep the ball down', false));
    }
    if (items.isEmpty) {
      items.add(pw.Text('No major damage patterns found yet.', style: pw.TextStyle(fontSize: 9, color: _PdfColors.colMuted)));
    }
    return _sectionCard('What Gets Hit', items);
  }

  static pw.Widget _approachRow(String label, bool? val, bool yesIsBad) {
    String text;
    PdfColor color;
    if (val == null) {
      text = 'N/A';
      color = _PdfColors.colMuted;
    } else if (val) {
      text = 'YES';
      color = yesIsBad ? _PdfColors.colError : _PdfColors.perfExcellent;
    } else {
      text = 'NO';
      color = yesIsBad ? _PdfColors.perfExcellent : _PdfColors.colMuted;
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 9))),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Text(text, style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ),
      ]),
    );
  }

  static pw.Widget _theirApproachCard(ScoutingReportData r, List<Map<String, dynamic>> withAvgRows) {
    final rows = <pw.Widget>[
      _approachRow('Aggressive early (swings pitch 1)?', r.approach['aggressiveEarly'] as bool?, true),
      _approachRow('Chase off-speed (high whiff on CV/CH/SL)?', r.approach['chaseOffspeed'] as bool?, false),
      _approachRow('Sit on fastball in hitter counts?', r.approach['sitFastball'] as bool?, true),
      pw.SizedBox(height: 6),
      pw.Text('AVG by Pitch Type vs You',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _PdfColors.colMuted)),
      pw.SizedBox(height: 3),
    ];
    for (final row in withAvgRows) {
      final bg = _perfHex('AVG', row['avgAgainst'] as double?);
      rows.add(pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: pw.BoxDecoration(color: _PdfColors.accent, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Text((row['pitchType'] as String).toUpperCase(),
                style: pw.TextStyle(color: PdfColors.white, fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: bg,
            child: pw.Text(_fmtAvg(row['avgAgainst'] as double),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _PdfColors.onColor(bg))),
          ),
        ]),
      ));
    }
    return _sectionCard('Their Approach', rows);
  }

  static pw.Widget _stepRow(int n, String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
            width: 16,
            height: 16,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: _PdfColors.ink, shape: pw.BoxShape.circle),
            child: pw.Text('$n', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8)),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 9))),
        ]),
      );

  static pw.Widget _attackPlanCard(ScoutingReportData r) {
    final steps = <pw.Widget>[
      _stepRow(1, r.cd['fpsPct'] != null && (r.cd['fpsPct'] as double) >= 60
          ? 'Continue leading with strikes — your first-pitch strike rate is working.'
          : 'Prioritize a fastball strike on pitch 1 — F-Strike% needs improvement.'),
      _stepRow(2, r.worstPitch != null
          ? 'Minimize ${(r.worstPitch!['pitchType'] as String).toUpperCase()} in hitter counts (AVG: ${_fmtAvg(r.worstPitch!['avgAgainst'] as double)}).'
          : 'No single pitch stands out as a problem — maintain your mix.'),
      _stepRow(3, r.bestPitch != null
          ? 'In 0-2 / 1-2 counts, go to ${(r.bestPitch!['pitchType'] as String).toUpperCase()} — ${r.bestPitch!['whiffPct']}% whiff rate.'
          : 'Use your highest-whiff pitch in two-strike counts.'),
      _stepRow(4, r.stats.bbPct != null && r.stats.bbPct! > 12
          ? 'Walk rate is ${r.stats.bbPct}% — this lineup works counts. Challenge them early.'
          : 'Walk rate under control. Maintain zone aggression.'),
      _stepRow(5, r.approach['chaseOffspeed'] == true
          ? 'This lineup chases off-speed. Use it as a put-away weapon.'
          : (r.approach['chaseOffspeed'] == false
              ? 'This lineup lays off off-speed. Win with fastball strikes.'
              : 'Off-speed chase tendency unclear — test it early.')),
    ];
    if (r.topDamage != null) {
      steps.add(_stepRow(6,
          'Be careful at the ${r.topDamage!['count']} count (OBP: ${(r.topDamage!['obp'] as double).toStringAsFixed(3)}). Avoid predictable patterns here.'));
    }
    return _sectionCard('Attack Plan', steps);
  }

  static pw.Widget _keyHittersCard(ScoutingReportData r) {
    if (r.keyHitters.isEmpty) {
      return _sectionCard('Key Hitters', [
        pw.Text('Need more PA data.', style: pw.TextStyle(fontSize: 9, color: _PdfColors.colMuted)),
      ]);
    }
    final rows = <pw.TableRow>[
      pw.TableRow(decoration: pw.BoxDecoration(color: _PdfColors.ink), children: [
        _hCell('#'), _hCell('PA'), _hCell('AVG'), _hCell('OBP'), _hCell('BB'), _hCell('K'), _hCell('XBH'),
      ]),
    ];
    for (final h in r.keyHitters) {
      final avg = h['avg'] as double?;
      final obp = h['obp'] as double?;
      rows.add(pw.TableRow(children: [
        _cell('#${h['jersey']}'),
        _cell('${h['pa']}'),
        _coloredCell(avg != null ? _fmtAvg(avg) : '—', _perfHex('AVG', avg)),
        _coloredCell(obp != null ? obp.toStringAsFixed(3) : '—', _perfHex('OBP_allowed', obp)),
        _cell('${h['bb']}'),
        _cell('${h['k']}'),
        _cell('${h['xbh']}'),
      ]));
    }
    return _sectionCard('Key Hitters (ranked by OBP against, min. 2 PA)', [
      pw.Table(border: pw.TableBorder.all(color: _PdfColors.colBorder, width: 0.5), children: rows),
    ]);
  }

  static pw.Widget _hCell(String t) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(t, style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );
  static pw.Widget _cell(String t) =>
      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t, style: const pw.TextStyle(fontSize: 8.5)));
  static pw.Widget _coloredCell(String t, PdfColor bg) => pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _PdfColors.onColor(bg))),
      );

  // ── Spray chart (simplified vector recreation) ──────────────────
  static pw.Widget _sprayChartCard(ScoutingReportData r) {
    final points = r.data.where((p) => p.xCoord != null && p.yCoord != null).toList();
    return _sectionCard('Spray Chart vs This Team', [
      pw.Container(
        height: 190,
        decoration: pw.BoxDecoration(color: _PdfColors.tint, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.CustomPaint(
          size: const PdfPoint(240, 190),
          painter: (canvas, size) => _paintSprayField(canvas, size, points),
        ),
      ),
    ]);
  }

  static void _paintSprayField(PdfGraphics canvas, PdfPoint size, List<PitchEvent> points) {
    const fieldMinX = -400.0, fieldMaxX = 400.0;
    const fieldMinY = -80.0, fieldMaxY = 400.0;
    PdfPoint toCanvas(double fx, double fy) {
      final nx = (fx - fieldMinX) / (fieldMaxX - fieldMinX);
      final ny = (fy - fieldMinY) / (fieldMaxY - fieldMinY);
      return PdfPoint(nx * size.x, ny * size.y);
    }

    final home = toCanvas(0, 0);

    // Foul lines (fan shape from home plate to the outfield corners).
    final leftCorner = toCanvas(-283, 283);
    final rightCorner = toCanvas(283, 283);
    canvas
      ..setColor(PdfColors.white)
      ..setLineWidth(1.2)
      ..drawLine(home.x, home.y, leftCorner.x, leftCorner.y)
      ..strokePath()
      ..drawLine(home.x, home.y, rightCorner.x, rightCorner.y)
      ..strokePath();

    // Outfield arc, approximated with line segments.
    canvas.setColor(PdfColors.white);
    const steps = 24;
    PdfPoint? prev;
    for (int i = 0; i <= steps; i++) {
      final t = -45 + (90 * i / steps);
      final rad = t * 3.14159265 / 180;
      final x = 330 * _sin(rad);
      final y = 330 * _cos(rad);
      final p = toCanvas(x, y);
      if (prev != null) {
        canvas
          ..drawLine(prev.x, prev.y, p.x, p.y)
          ..strokePath();
      }
      prev = p;
    }

    // Spray points, colored by outcome (same palette as the on-screen chart).
    for (final p in points) {
      final pos = toCanvas(p.xCoord!, p.yCoord!);
      final fill = _sprayColor(p.outcome);
      canvas
        ..setColor(fill)
        ..drawEllipse(pos.x, pos.y, 4, 4)
        ..fillPath();
    }
  }

  static double _sin(double rad) {
    // Minimal Taylor-series sine to avoid importing dart:math into a PDF
    // painter that only needs a rough field outline.
    double x = rad;
    double term = x;
    double sum = x;
    for (int n = 1; n <= 6; n++) {
      term *= -x * x / ((2 * n) * (2 * n + 1));
      sum += term;
    }
    return sum;
  }

  static double _cos(double rad) => _sin(rad + 1.5707963267948966);

  static PdfColor _sprayColor(String? outcome) {
    const map = <String, PdfColor>{
      '1b': PdfColor.fromInt(0xFF22C55E),
      '2b': PdfColor.fromInt(0xFF2563EB),
      '3b': PdfColor.fromInt(0xFF7C3AED),
      'hr': PdfColor.fromInt(0xFFF97316),
      'go': PdfColor.fromInt(0xFFDC2626),
      'fo': PdfColor.fromInt(0xFFDC2626),
      'lo': PdfColor.fromInt(0xFFDC2626),
      'dp': PdfColor.fromInt(0xFFDC2626),
      'e': PdfColor.fromInt(0xFFFACC15),
      'fc': PdfColor.fromInt(0xFF6B7280),
    };
    if (outcome == null) return PdfColor.fromInt(0xFFDC2626);
    return map[outcome.toLowerCase().trim()] ?? PdfColor.fromInt(0xFFDC2626);
  }

  // ── Adjustment notes ─────────────────────────────────────────────
  static pw.Widget _adjustmentNotesCard(ScoutingReportData r) {
    final children = <pw.Widget>[];
    if (r.gameTrend.length < 2) {
      children.add(_tinyCard('First encounter', 'No prior history to adjust from. Use the general plan above.', true));
      children.add(pw.SizedBox(height: 4));
      children.add(pw.Text(
        '• Establish fastball strikes early\n'
        '• Test off-speed in 0-1 and 1-1 counts\n'
        '• Watch swing tendencies and adjust by the 3rd PA\n'
        '• Check the spray chart mid-game for pull/oppo tendencies',
        style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 2),
      ));
    } else {
      final avgs = r.gameTrend.map((g) => g['avg'] as double?).toList();
      final kpcts = r.gameTrend.map((g) => g['kPct'] as double?).toList();
      double? avgTrend;
      double? kTrend;
      if (avgs.every((v) => v != null) && avgs.length >= 2) avgTrend = avgs.last! - avgs.first!;
      if (kpcts.every((v) => v != null) && kpcts.length >= 2) kTrend = kpcts.last! - kpcts.first!;

      if (avgTrend != null) {
        if (avgTrend > 0.040) {
          children.add(_tinyCard('AVG trending UP (+${avgTrend.toStringAsFixed(3)})',
              'This team is hitting you better each game. Mix looks predictable.', false));
        } else if (avgTrend < -0.040) {
          children.add(_tinyCard('AVG trending DOWN (${avgTrend.toStringAsFixed(3)})',
              'Your approach is working better over time. Stay the course.', true));
        }
      }
      if (kTrend != null) {
        if (kTrend > 5) {
          children.add(_tinyCard(
              'K% trending UP (+${kTrend.toStringAsFixed(1)}%)', 'You are generating more swing-and-miss each game.', true));
        } else if (kTrend < -5) {
          children.add(_tinyCard('K% trending DOWN (${kTrend.toStringAsFixed(1)}%)',
              'This lineup is making more contact — vary your put-away pitch.', false));
        }
      }
      if (children.isEmpty) {
        children.add(pw.Text('No significant trends detected yet.', style: pw.TextStyle(fontSize: 9, color: _PdfColors.colMuted)));
      }
      children.add(pw.SizedBox(height: 6));
      children.add(pw.Text('Game-by-game performance',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _PdfColors.colMuted)));
      children.add(pw.SizedBox(height: 3));
      final rows = <pw.TableRow>[
        pw.TableRow(decoration: pw.BoxDecoration(color: _PdfColors.ink), children: [
          _hCell('Game'), _hCell('AVG'), _hCell('K%'), _hCell('BB%'),
        ]),
      ];
      for (final g in r.gameTrend) {
        rows.add(pw.TableRow(children: [
          _cell('G${g['game']}'),
          _coloredCell(g['avg'] != null ? _fmtAvg(g['avg'] as double) : '—', _perfHex('AVG', g['avg'] as double?)),
          _coloredCell(g['kPct'] != null ? '${g['kPct']}%' : '—', _perfHex('K_pct', g['kPct'] as double?)),
          _coloredCell(g['bbPct'] != null ? '${g['bbPct']}%' : '—', _perfHex('BB_pct', g['bbPct'] as double?)),
        ]));
      }
      children.add(pw.Table(border: pw.TableBorder.all(color: _PdfColors.colBorder, width: 0.5), children: rows));
    }
    return _sectionCard('Adjustment Notes', children);
  }
}
