import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../utils/responsive.dart';
import '../widgets/baseball_field_painter.dart';
import '../widgets/stat_hold_info.dart';
import '../widgets/year_filter_dropdown.dart';
import '../services/color_guides.dart';

/// Port of the R app's "Edit At-Bats" tab: pick a ball-in-play row from a
/// list, then tap the field to set/adjust its spray-chart landing spot.
class EditAtBatsScreen extends StatefulWidget {
  const EditAtBatsScreen({super.key});

  @override
  State<EditAtBatsScreen> createState() => _EditAtBatsScreenState();
}

class _EditAtBatsScreenState extends State<EditAtBatsScreen> {
  int? _selectedIndex;
  double? _pendingX;
  double? _pendingY;
  String _battedType = 'gb';

  // Filters (same Team / Game # / Year set the Overview tab uses, plus Jersey #).
  // They only change which at-bats are LISTED; no record is touched.
  String _team = 'All';
  String _gameNum = 'All';
  String _jersey = 'All';

  static const bipOutcomes = {
    '1b', '2b', '3b', 'hr', 'go', 'fo', 'lo', 'dp', 'e', 'fc'
  };

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    // Every ball-in-play row (as an index into session.pitches, so saving an
    // edit still targets the right record), narrowed step by step so each
    // filter's choices come from the rows left by the filters before it.
    final year = session.selectedYear;
    final all = <int>[];
    for (int i = 0; i < session.pitches.length; i++) {
      final p = session.pitches[i];
      if (bipOutcomes.contains(p.outcome) && (year == null || p.season == year)) all.add(i);
    }
    final teams = ['All', ...{for (final i in all) session.pitches[i].game}];
    final activeTeam = teams.contains(_team) ? _team : 'All';
    final byTeam = all.where((i) => activeTeam == 'All' || session.pitches[i].game == activeTeam).toList();
    final gameNums = ['All', ...{for (final i in byTeam) session.pitches[i].gameNumber.toString()}];
    final activeGame = gameNums.contains(_gameNum) ? _gameNum : 'All';
    final byGame = byTeam
        .where((i) => activeGame == 'All' || session.pitches[i].gameNumber.toString() == activeGame)
        .toList();
    final jerseyNums = {
      for (final i in byGame)
        if (session.pitches[i].batterNumber != null) session.pitches[i].batterNumber!
    }.toList()
      ..sort();
    final jerseys = ['All', ...jerseyNums.map((j) => '$j')];
    final activeJersey = jerseys.contains(_jersey) ? _jersey : 'All';
    final candidates = byGame
        .where((i) => activeJersey == 'All' || '${session.pitches[i].batterNumber}' == activeJersey)
        .toList();

    final anyFilter = activeTeam != 'All' || activeGame != 'All' || activeJersey != 'All' || year != null;

    Widget teamField() => DropdownButtonFormField<String>(
          isExpanded: true,
          isDense: true,
          value: activeTeam,
          decoration: const InputDecoration(labelText: 'Team'),
          items: teams
              .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() {
            _team = v!;
            _gameNum = 'All';
            _jersey = 'All';
          }),
        );
    Widget gameField() => DropdownButtonFormField<String>(
          isExpanded: true,
          isDense: true,
          value: activeGame,
          decoration: const InputDecoration(labelText: 'Game #'),
          items: gameNums
              .map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() {
            _gameNum = v!;
            _jersey = 'All';
          }),
        );
    Widget jerseyField() => DropdownButtonFormField<String>(
          isExpanded: true,
          isDense: true,
          value: activeJersey,
          decoration: const InputDecoration(labelText: 'Jersey #'),
          items: jerseys
              .map((j) => DropdownMenuItem(
                  value: j, child: Text(j == 'All' ? 'All' : '#$j', overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _jersey = v!),
        );
    final clearButton = TextButton.icon(
      onPressed: () {
        setState(() {
          _team = 'All';
          _gameNum = 'All';
          _jersey = 'All';
        });
        if (session.selectedYear != null) session.setSelectedYear(null);
      },
      icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
      label: const Text('Clear Filters'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandOrangeDeep,
        visualDensity: VisualDensity.compact,
      ),
    );

    final filterCard = GlowCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Filter', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${candidates.length} of ${all.length} at-bats',
                    style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
              ),
              if (anyFilter) clearButton,
            ]),
            const SizedBox(height: 4),
            LayoutBuilder(builder: (context, c) {
              // Desktop / tablet: one aligned row. Phones: two per line.
              if (c.maxWidth >= 640) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: teamField()),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: gameField()),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: jerseyField()),
                  const SizedBox(width: 10),
                  const YearFilterDropdown(),
                ]);
              }
              final half = (c.maxWidth - 10) / 2;
              return Wrap(spacing: 10, runSpacing: 8, children: [
                SizedBox(width: half, child: teamField()),
                SizedBox(width: half, child: gameField()),
                SizedBox(width: half, child: jerseyField()),
                SizedBox(width: half, child: const YearFilterDropdown()),
              ]);
            }),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterCard,
        _body(context, session, candidates),
      ],
    );
  }

  static const _outcomeNames = <String, String>{
    '1b': 'Single', '2b': 'Double', '3b': 'Triple', 'hr': 'Home Run',
    'go': 'Ground Out', 'fo': 'Fly Out', 'lo': 'Line Out',
    'fc': "Fielder's Choice", 'dp': 'Double Play', 'e': 'Error',
  };
  static const _battedNames = <String, String>{'gb': 'Ground Ball', 'ld': 'Line Drive', 'fb': 'Fly Ball'};

  Widget _body(BuildContext context, AppSession session, List<int> candidates) {
    final panelH = (MediaQuery.sizeOf(context).height * (Responsive.isPhone(context) ? 0.4 : 0.6))
        .clamp(260.0, 560.0)
        .toDouble();
    return ResponsiveRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: _listCard(context, session, candidates, panelH)),
        const SizedBox(width: 8),
        Expanded(flex: 6, child: _editorCard(context, session, candidates, panelH)),
      ],
    );
  }

  Widget _listCard(BuildContext context, AppSession session, List<int> candidates, double panelH) {
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select At-Bat', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              height: panelH,
              child: candidates.isEmpty
                  ? const Center(
                      child: Text('No balls-in-play match these filters.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, idx) => _atBatCard(session, candidates[idx], idx),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _atBatCard(AppSession session, int ri, int idx) {
    final row = session.pitches[ri];
    final selected = _selectedIndex == ri;
    final hasSpray = row.xCoord != null && row.yCoord != null;
    final outcomeLabel = _outcomeNames[row.outcome] ?? row.outcome;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _selectedIndex = ri;
            _pendingX = row.xCoord;
            _pendingY = row.yCoord;
            _battedType = row.battedType ?? 'gb';
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.tint : Colors.white,
              border: Border.all(
                color: selected ? AppColors.brandOrangeDeep : AppColors.colBorder,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brandOrangeDeep : AppColors.tint,
                    shape: BoxShape.circle,
                  ),
                  child: Text('${idx + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: selected ? Colors.white : AppColors.colText)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${row.game} G${row.gameNumber} | #${row.batterNumber}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.colText)),
                      const SizedBox(height: 2),
                      Text('${row.pitchType} / ${row.outcome}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Secondary label: the recorded outcome, spelled out.
                if (outcomeLabel != null)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.tint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(outcomeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandOrangeDeep)),
                    ),
                  ),
                const SizedBox(width: 8),
                // Same status as before (spray location saved or not), now
                // with a word next to the icon so the meaning is visible.
                StatHoldInfo(
                  title: 'Spray location',
                  description: composeHoldInfo(
                    what: 'Shows whether a spray chart location was recorded for this at-bat.',
                    colorGuide: [
                      swatchLine(AppColors.perfExcellent, 'Green check: a spray location is saved.'),
                      swatchLine(AppColors.colMuted, 'Gray minus: no spray location saved.'),
                      'A status marker, not a graded stat, so there are no cutoffs.',
                    ].join('\n'),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      hasSpray ? Icons.check_circle_outline : Icons.remove_circle_outline,
                      size: 18,
                      color: hasSpray ? AppColors.perfExcellent : AppColors.colMuted,
                    ),
                    Text(hasSpray ? 'Spray' : 'No spray',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: hasSpray ? AppColors.perfExcellent : AppColors.colMuted)),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.colMuted)),
      );

  Widget _fact(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.colText)),
          ),
        ]),
      );

  Widget _group(String title, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(color: AppColors.colBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sectionLabel(title), ...children]),
      );

  Widget _editorCard(BuildContext context, AppSession session, List<int> candidates, double panelH) {
    // The selection only counts while that at-bat is still in the filtered list.
    final sel = (_selectedIndex != null && candidates.contains(_selectedIndex)) ? _selectedIndex : null;
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Selected At-Bat', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (sel == null)
              SizedBox(
                height: panelH,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.touch_app_outlined, size: 34, color: AppColors.brandOrangeDeep.withOpacity(0.6)),
                    const SizedBox(height: 8),
                    const Text('Select an at-bat',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.colText)),
                    const SizedBox(height: 2),
                    const Text('Choose one from the list to review it and set its landing spot.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
                  ]),
                ),
              )
            else
              _editorBody(context, session, sel),
          ],
        ),
      ),
    );
  }

  Widget _editorBody(BuildContext context, AppSession session, int selIndex) {
    final row = session.pitches[selIndex];
    final outcomeLabel = _outcomeNames[row.outcome] ?? row.outcome ?? '—';
    final pitchLabel = row.pitchType == null ? '—' : session.pitchTypeLabel(row.pitchType);

    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _group('Batter', [
        _fact('Jersey #', row.batterNumber == null ? '—' : '#${row.batterNumber}'),
        _fact('Lineup spot', '${row.battingOrder}'),
        _fact('Batter hand', row.hand == 'L' ? 'Left' : (row.hand == 'R' ? 'Right' : row.hand)),
      ]),
      _group('Game', [
        _fact('Opponent', row.game),
        _fact('Game #', '${row.gameNumber}'),
        _fact('Season', '${row.season}'),
        if (row.inning != null) _fact('Inning', '${row.inning}'),
      ]),
      _group('At-bat result', [
        _fact('Pitch', pitchLabel),
        _fact('Outcome', outcomeLabel),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          isExpanded: true,
          isDense: true,
          value: _battedType,
          decoration: const InputDecoration(labelText: 'Batted Type'),
          items: [
            for (final e in _battedNames.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _battedType = v!),
        ),
      ]),
    ]);

    final spray = _group('Spray location', [
      const Text('Click the field to mark the landing spot.', style: TextStyle(color: AppColors.colMuted, fontSize: 12)),
      const SizedBox(height: 6),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (layoutCtx, constraints) {
                final size = constraints.biggest;
                return SprayFieldSurface(
                  sprayPoints: const [],
                  highlightX: _pendingX,
                  highlightY: _pendingY,
                  onTapDown: (details) {
                    final field = FieldCoordConverter.canvasToField(details.localPosition, size);
                    setState(() {
                      _pendingX = field.dx;
                      _pendingY = field.dy;
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _pendingX == null ? 'Click field to set location' : 'New: (${_pendingX!.round()}, ${_pendingY!.round()})',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ]);

    final actions = ResponsiveRow(breakpoint: 300, stackedGap: 8, children: [
      Expanded(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
          onPressed: () async {
            final current = session.pitches[selIndex];
            final updated = current.copyWith(
              xCoord: _pendingX,
              yCoord: _pendingY,
              battedType: _battedType,
            );
            await session.updatePitchAt(selIndex, updated);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
            }
          },
          child: const Text('Save Changes'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.colError,
            side: const BorderSide(color: AppColors.colError),
          ),
          onPressed: () => setState(() {
            _pendingX = null;
            _pendingY = null;
          }),
          child: const Text('Clear Spray'),
        ),
      ),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        // Wide panel: facts on the left, field on the right. Narrow: stacked.
        if (c.maxWidth >= 600) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 4, child: details),
            const SizedBox(width: 10),
            Expanded(flex: 6, child: spray),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [details, spray]);
      }),
      actions,
    ]);
  }
}
