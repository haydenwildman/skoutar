import '../widgets/orange_glow_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../models/pitch_event.dart';
import '../services/app_session.dart';
import '../services/scouting_report_data.dart';
import '../services/scouting_report_sheet.dart';
import '../services/scouting_pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/scouting_report_pages.dart';
import '../utils/responsive.dart';
import '../widgets/stat_vbox.dart' show PerfTierLegend;
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import '../widgets/year_filter_dropdown.dart';

class ScoutingReportScreen extends StatefulWidget {
  const ScoutingReportScreen({super.key});

  @override
  State<ScoutingReportScreen> createState() => _ScoutingReportScreenState();
}

class _ScoutingReportScreenState extends State<ScoutingReportScreen> {
  String? _team;
  String _gameNum = 'All';
  bool _generated = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final teams = session.knownTeams;
    final gameNums = [
      'All',
      ...session.filteredPitches
          .where((p) => _team == null || p.game == _team)
          .map((p) => p.gameNumber.toString())
          .toSet()
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _team,
                      decoration: const InputDecoration(labelText: 'Opponent'),
                      items: teams
                          .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _team = v;
                        _gameNum = 'All';
                        _generated = false;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _gameNum,
                      decoration: const InputDecoration(labelText: 'Game #'),
                      items: gameNums.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() {
                        _gameNum = v!;
                        _generated = false;
                      }),
                    ),
                  ),
                  const YearFilterDropdown(),
                  OrangeGlowButton(
                    onPressed: _team == null ? null : () => setState(() => _generated = true),
                    child: const Text('Generate Report'),
                  ),
                ]),
                const SizedBox(height: 10),
                const PerfTierLegend(),
              ],
            ),
          ),
        ),
        if (_generated && _team != null)
          Builder(builder: (context) => _ScoutingReportBody(
                team: _team!,
                history: session.filteredPitches,
                data: () {
                  var data = session.filteredPitches.where((p) => p.game == _team).toList();
                  if (_gameNum != 'All') {
                    final gn = int.tryParse(_gameNum);
                    data = data.where((p) => p.gameNumber == gn).toList();
                  }
                  return data;
                }(),
              ))
        else
          const GlowCard(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Select an opponent and generate a report.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
      ],
    );
  }
}

class _ScoutingReportBody extends StatefulWidget {
  final String team;
  final List<PitchEvent> data;
  final List<PitchEvent> history;
  const _ScoutingReportBody({required this.team, required this.data, required this.history});

  @override
  State<_ScoutingReportBody> createState() => _ScoutingReportBodyState();
}

class _ScoutingReportBodyState extends State<_ScoutingReportBody> {
  bool _exporting = false;

  Future<void> _downloadPdf(ScoutingReportData r) async {
    setState(() => _exporting = true);
    try {
      final bytes = await ScoutingPdfService.generate(r);
      final safeTeam = r.team.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      await Printing.sharePdf(bytes: bytes, filename: 'scouting_report_$safeTeam.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ScoutingReportData.compute(widget.team, widget.data, history: widget.history);
    final sheet = ScoutingSheet.build(r);
    final fit = ScoutingPdfService.fitFor(sheet.cards);
    final threatLevel = r.threatLevel;
    final threatColor = threatLevel == 'high'
        ? AppColors.perfPoor
        : (threatLevel == 'medium' ? AppColors.perfAverage : AppColors.perfExcellent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ResponsiveRow(stackedGap: 8, stackedCrossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text('Scouting: ${r.team.toUpperCase()}  •  ${r.gamesFaced} game(s) faced',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _downloadPdf(r),
                icon: _exporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                      )
                    : const Icon(Icons.picture_as_pdf, size: 16),
                label: Text(_exporting ? 'Generating…' : 'Download PDF (2 pages)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.ink, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              StatHoldInfo(
                title: 'Threat Level',
                description: composeHoldInfo(
                  what: 'A quick read on how dangerous this lineup is, built from a point score:\n'
                      '• AVG over .250: +1 (over .300: +3 in total)\n'
                      '• BB% over 8%: +1 (over 12%: +3 in total)\n'
                      '• K% under 15%: +1\n'
                      '• 3 or more extra-base hits: +1\n'
                      'This team: ${r.threatScore} point(s) → ${threatLevel.toUpperCase()}.',
                  colorGuide: [
                    swatchLine(AppColors.perfPoor, 'Red - HIGH threat: 5 or more points'),
                    swatchLine(AppColors.perfAverage, 'Yellow - MEDIUM threat: 3 to 4 points'),
                    swatchLine(AppColors.perfExcellent, 'Dark green - LOW threat: 0 to 2 points'),
                  ].join('\n'),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(color: threatColor, borderRadius: BorderRadius.circular(20)),
                  child: Text('${threatLevel.toUpperCase()} THREAT',
                      style: TextStyle(
                          color: threatLevel == 'medium' ? AppColors.colText : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12)),
                ),
              ),
            ]),
          ),
        ),
        ScoutingReportPages(sheet: sheet, fit: fit),
      ],
    );
  }
}
