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

    final filterCard = GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Filter', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Text('${candidates.length} of ${all.length} at-bats',
                  style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
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
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: activeGame,
                    decoration: const InputDecoration(labelText: 'Game #'),
                    items: gameNums
                        .map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _gameNum = v!;
                      _jersey = 'All';
                    }),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: activeJersey,
                    decoration: const InputDecoration(labelText: 'Jersey #'),
                    items: jerseys
                        .map((j) => DropdownMenuItem(
                            value: j, child: Text(j == 'All' ? 'All' : '#$j', overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _jersey = v!),
                  ),
                ),
                const YearFilterDropdown(),
                if (activeTeam != 'All' || activeGame != 'All' || activeJersey != 'All')
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _team = 'All';
                      _gameNum = 'All';
                      _jersey = 'All';
                    }),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: const Text('Show all'),
                  ),
              ],
            ),
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

  Widget _body(BuildContext context, AppSession session, List<int> candidates) {
    return ResponsiveRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: GlowCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select At-Bat', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height * (Responsive.isPhone(context) ? 0.4 : 0.6))
                        .clamp(260.0, 560.0)
                        .toDouble(),
                    child: candidates.isEmpty
                        ? const Center(
                            child: Text('No balls-in-play match these filters.', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: candidates.length,
                            itemBuilder: (context, idx) {
                              final ri = candidates[idx];
                              final row = session.pitches[ri];
                              final selected = _selectedIndex == ri;
                              final hasSpray = row.xCoord != null && row.yCoord != null;
                              return InkWell(
                                onTap: () => setState(() {
                                  _selectedIndex = ri;
                                  _pendingX = row.xCoord;
                                  _pendingY = row.yCoord;
                                  _battedType = row.battedType ?? 'gb';
                                }),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: selected ? AppColors.ink : Colors.white,
                                    border: Border.all(color: AppColors.colBorder, width: 2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text('${idx + 1}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: selected ? Colors.white : AppColors.colText)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${row.game} G${row.gameNumber} | #${row.batterNumber}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: selected ? Colors.white : AppColors.colText)),
                                            Text('${row.pitchType} / ${row.outcome}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: selected ? Colors.white70 : Colors.grey)),
                                          ],
                                        ),
                                      ),
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
                                        child: Icon(
                                        hasSpray
                                            ? Icons.check_circle_outline
                                            : Icons.remove_circle_outline,
                                        size: 16,
                                        color: hasSpray
                                            ? AppColors.perfExcellent
                                            : AppColors.colMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 7,
          child: GlowCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Edit Selected At-Bat', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (_selectedIndex == null)
                    const Text('Tap a row to select.', style: TextStyle(color: Colors.grey))
                  else ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _battedType,
                      decoration: const InputDecoration(labelText: 'Batted Type'),
                      items: const [
                        DropdownMenuItem(value: 'gb', child: Text('Ground Ball', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'ld', child: Text('Line Drive', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'fb', child: Text('Fly Ball', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _battedType = v!),
                    ),
                    const SizedBox(height: 8),
                    const Text('Click field to mark landing spot:', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                              final field =
                                  FieldCoordConverter.canvasToField(details.localPosition, size);
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
                    const SizedBox(height: 8),
                    Text(_pendingX == null
                        ? 'Click field to set location'
                        : 'New: (${_pendingX!.round()}, ${_pendingY!.round()})'),
                    const SizedBox(height: 8),
                    ResponsiveRow(breakpoint: 300, stackedGap: 8, children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.colSuccess),
                          onPressed: () async {
                            final row = session.pitches[_selectedIndex!];
                            final updated = row.copyWith(
                              xCoord: _pendingX,
                              yCoord: _pendingY,
                              battedType: _battedType,
                            );
                            await session.updatePitchAt(_selectedIndex!, updated);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Saved!')));
                            }
                          },
                          child: const Text('Save Changes'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.colError),
                          onPressed: () => setState(() {
                            _pendingX = null;
                            _pendingY = null;
                          }),
                          child: const Text('Clear Spray'),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
