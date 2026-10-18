import '../widgets/orange_glow_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/pitch_event.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../utils/responsive.dart';

/// Direct CSV-style editor — port of the R app's "Edit Raw Data" DT table.
/// Double-click (double-tap on touch screens) any value to edit just that
/// value in place; the pencil opens the full row dialog (every field at once),
/// the trash icon deletes the row, and "+ Add Row" logs a pitch manually
/// without going through Game Input.
class EditRawDataScreen extends StatefulWidget {
  const EditRawDataScreen({super.key});

  @override
  State<EditRawDataScreen> createState() => _EditRawDataScreenState();
}

class _EditRawDataScreenState extends State<EditRawDataScreen> {
  static const _uuid = Uuid();
  static const handOptions = ['L', 'R', 'S'];
  static const eventTypeOptions = ['pitch', 'po', 'to', 'txo', 'bk'];
  static const callOptions = ['b', 'ss', 'sl', 'f', 'ip', 'hbp', 'dk'];
  static const outcomeOptions = [
    '', '1b', '2b', '3b', 'hr', 'go', 'fo', 'lo', 'dp', 'e', 'fc', 'bb',
    'hbp', 'k', 'kl', 'dk', 'po_out', 'po_safe', 'to', 'txo', 'bk'
  ];

  /// Opens the Add/Edit row dialog.
  /// - [existing] + [index]: edit that row in place.
  /// - [insertIndex] (new row only): insert the new row at that position
  ///   in the log instead of appending it to the end.
  Future<void> _openRowDialog(BuildContext context,
      {PitchEvent? existing, int? index, int? insertIndex}) async {
    final session = context.read<AppSession>();
    final isNew = existing == null;

    // The pitcher's own custom pitch types + any pitch type codes already
    // present in the data (covers rows logged before presets were removed).
    final pitchTypeOptions = <String>{
      ...session.customPitchTypes.map((c) => c.toLowerCase()),
      ...session.pitches.map((p) => (p.pitchType ?? '').toLowerCase()).where((s) => s.isNotEmpty),
    }.toList()
      ..sort();

    // No presets exist, so a pitcher with no pitch types yet gets "(none)".
    final startingPitchType = existing?.pitchType ?? (pitchTypeOptions.isNotEmpty ? pitchTypeOptions.first : '');
    if (!pitchTypeOptions.contains(startingPitchType)) pitchTypeOptions.insert(0, startingPitchType);

    final gameCtrl = TextEditingController(text: existing?.game ?? session.currentOpponent);
    final gameNumCtrl = TextEditingController(text: '${existing?.gameNumber ?? session.currentGameNumber}');
    final batterCtrl = TextEditingController(text: '${existing?.batter ?? session.completedPAs}');
    final jerseyCtrl = TextEditingController(text: '${existing?.batterNumber ?? ''}');
    final orderCtrl = TextEditingController(text: '${existing?.battingOrder ?? 1}');
    final pitchNumCtrl = TextEditingController(text: '${existing?.pitchNum ?? 1}');
    final outsCtrl = TextEditingController(text: '${existing?.outs ?? 0}');
    final erCtrl = TextEditingController(text: '${existing?.er ?? 0}');
    final seasonCtrl = TextEditingController(text: '${existing?.season ?? DateTime.now().year}');

    String hand = existing?.hand ?? 'R';
    String eventType = existing?.eventType ?? 'pitch';
    String pitchType = startingPitchType;
    String call = existing?.call ?? 'ip';
    String outcome = existing?.outcome ?? '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        Widget field(String label, TextEditingController c, {TextInputType? kb}) => SizedBox(
              width: 130,
              child: TextField(
                controller: c,
                keyboardType: kb,
                decoration: InputDecoration(labelText: label),
              ),
            );
        Widget dropdown(String label, String value, List<String> opts, ValueChanged<String> onChanged) =>
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: value,
                decoration: InputDecoration(labelText: label),
                items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o.isEmpty ? '(none)' : o, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setDialogState(() => onChanged(v!)),
              ),
            );

        return AlertDialog(
          title: Text(isNew
              ? (insertIndex != null ? 'Insert Row Here' : 'Add Row')
              : 'Edit Row'),
          content: SizedBox(
            width: Responsive.dialogWidth(ctx, 480),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  field('Opponent', gameCtrl),
                  field('Game #', gameNumCtrl, kb: TextInputType.number),
                  field('Year', seasonCtrl, kb: TextInputType.number),
                  field('Batter Seq', batterCtrl, kb: TextInputType.number),
                  field('Jersey #', jerseyCtrl, kb: TextInputType.number),
                  field('Order (1-9)', orderCtrl, kb: TextInputType.number),
                  dropdown('Hand', hand, handOptions, (v) => hand = v),
                  dropdown('Event Type', eventType, eventTypeOptions, (v) => eventType = v),
                  field('Pitch # in AB', pitchNumCtrl, kb: TextInputType.number),
                  dropdown('Pitch Type', pitchType, pitchTypeOptions, (v) => pitchType = v),
                  dropdown('Call', call, callOptions, (v) => call = v),
                  dropdown('Outcome', outcome, outcomeOptions, (v) => outcome = v),
                  field('Outs', outsCtrl, kb: TextInputType.number),
                  field('ER', erCtrl, kb: const TextInputType.numberWithOptions(decimal: true)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            OrangeGlowButton(
              onPressed: () async {
                final event = PitchEvent(
                  id: existing?.id ?? _uuid.v4(),
                  userId: session.activePitcherId,
                  game: gameCtrl.text.trim().isEmpty ? 'Unknown' : gameCtrl.text.trim(),
                  gameNumber: int.tryParse(gameNumCtrl.text) ?? 1,
                  batter: int.tryParse(batterCtrl.text) ?? 1,
                  batterNumber: int.tryParse(jerseyCtrl.text),
                  battingOrder: int.tryParse(orderCtrl.text) ?? 1,
                  hand: hand,
                  eventType: eventType,
                  pitchNum: int.tryParse(pitchNumCtrl.text) ?? 1,
                  pitchType: pitchType,
                  call: call,
                  outcome: outcome.isEmpty ? null : outcome,
                  ab: (outcome.isNotEmpty && !{'bb', 'hbp'}.contains(outcome)) ? 1 : 0,
                  outs: int.tryParse(outsCtrl.text) ?? 0,
                  er: double.tryParse(erCtrl.text) ?? 0,
                  xCoord: existing?.xCoord,
                  yCoord: existing?.yCoord,
                  battedType: existing?.battedType,
                  inning: existing?.inning,
                  paId: existing?.paId ?? 0,
                  season: int.tryParse(seasonCtrl.text) ?? DateTime.now().year,
                  timestamp: existing?.timestamp,
                );
                if (isNew) {
                  if (insertIndex != null) {
                    await session.insertPitchAt(insertIndex, event);
                  } else {
                    await session.addManualPitch(event);
                  }
                } else {
                  await session.updatePitchAt(index!, event);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isNew ? (insertIndex != null ? 'Insert' : 'Add') : 'Save'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final session = context.read<AppSession>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ALL pitches?'),
        content: Text(
          'This permanently removes all ${session.pitches.length} rows — every pitch, '
          'pickoff, and throwout logged for this account, whether it came from Game '
          'Input or was typed in here. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: AppColors.colError)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await session.deleteAllPitches();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('All pitches deleted.')));
      }
    }
  }

  // ── Inline (double-click) editing ───────────────────────────────────

  /// The editable columns, in display order. [flex] sets each column's share
  /// of the available width, so the table always fits the screen.
  List<_Field> _fields(List<String> pitchTypeOptions) => [
        _Field('season', 'Year', 'Year', _Kind.integer, 10,
            shown: (e) => '${e.season}',
            editValue: (e) => '${e.season}',
            validate: (v) => _intIn(v, 1900, 2100, 'Year must be a whole number from 1900 to 2100.')),
        _Field('game', 'Opponent', 'Game', _Kind.text, 22,
            shown: (e) => e.game,
            editValue: (e) => e.game,
            validate: (v) => v.isEmpty ? 'Opponent can\'t be empty.' : null),
        _Field('gameNumber', 'Game #', 'G#', _Kind.integer, 8,
            shown: (e) => '${e.gameNumber}',
            editValue: (e) => '${e.gameNumber}',
            validate: (v) => _intIn(v, 1, 999, 'Game # must be a whole number of 1 or more.')),
        _Field('batter', 'Batter Seq', 'Batter', _Kind.integer, 10,
            shown: (e) => '${e.batter}',
            editValue: (e) => '${e.batter}',
            validate: (v) => _intIn(v, 0, 99999, 'Batter sequence must be a whole number of 0 or more.')),
        _Field('batterNumber', 'Jersey #', 'Jersey', _Kind.integer, 10,
            shown: (e) => '${e.batterNumber ?? "-"}',
            editValue: (e) => '${e.batterNumber ?? ''}',
            validate: (v) => v.isEmpty ? null : _intIn(v, 0, 999, 'Jersey # must be a whole number (or empty).')),
        _Field('battingOrder', 'Order (1-9)', 'Order', _Kind.integer, 9,
            shown: (e) => '${e.battingOrder}',
            editValue: (e) => '${e.battingOrder}',
            validate: (v) => _intIn(v, 1, 9, 'Batting order must be 1 to 9.')),
        _Field('hand', 'Hand', 'Hand', _Kind.dropdown, 9,
            shown: (e) => e.hand,
            editValue: (e) => e.hand,
            options: handOptions),
        _Field('eventType', 'Event Type', 'Type', _Kind.dropdown, 11,
            shown: (e) => e.eventType,
            editValue: (e) => e.eventType,
            options: eventTypeOptions),
        _Field('pitchNum', 'Pitch # in AB', 'P#', _Kind.integer, 8,
            shown: (e) => '${e.pitchNum ?? "-"}',
            editValue: (e) => '${e.pitchNum ?? ''}',
            validate: (v) => v.isEmpty ? null : _intIn(v, 1, 99, 'Pitch # must be a whole number from 1 to 99 (or empty).')),
        _Field('pitchType', 'Pitch Type', 'Pitch', _Kind.dropdown, 11,
            shown: (e) => (e.pitchType ?? '').toUpperCase(),
            editValue: (e) => e.pitchType ?? '',
            options: pitchTypeOptions),
        _Field('call', 'Call', 'Call', _Kind.dropdown, 10,
            shown: (e) => e.call ?? '',
            editValue: (e) => e.call ?? '',
            options: callOptions),
        _Field('outcome', 'Outcome', 'Outcome', _Kind.dropdown, 15,
            shown: (e) => e.outcome ?? '',
            editValue: (e) => e.outcome ?? '',
            options: outcomeOptions),
        _Field('outs', 'Outs', 'Outs', _Kind.integer, 8,
            shown: (e) => '${e.outs}',
            editValue: (e) => '${e.outs}',
            validate: (v) => _intIn(v, 0, 3, 'Outs must be 0 to 3.')),
        _Field('er', 'ER', 'ER', _Kind.decimal, 8,
            shown: (e) => '${e.er}',
            editValue: (e) => '${e.er}',
            validate: (v) {
              final d = double.tryParse(v);
              return (d == null || d < 0) ? 'ER must be a number of 0 or more.' : null;
            }),
      ];

  static String? _intIn(String v, int lo, int hi, String message) {
    final n = int.tryParse(v);
    return (n == null || n < lo || n > hi) ? message : null;
  }

  /// Builds the updated event for one edited field. Every other field is
  /// carried over unchanged (including spray coordinates, batted type, inning,
  /// plate-appearance id and timestamp). Editing the outcome also refreshes
  /// the at-bat flag exactly like the full row dialog does.
  PitchEvent _applyEdit(PitchEvent e, String key, String v) {
    var game = e.game;
    var gameNumber = e.gameNumber;
    var batter = e.batter;
    int? batterNumber = e.batterNumber;
    var battingOrder = e.battingOrder;
    var hand = e.hand;
    var eventType = e.eventType;
    int? pitchNum = e.pitchNum;
    String? pitchType = e.pitchType;
    String? call = e.call;
    String? outcome = e.outcome;
    var ab = e.ab;
    var outs = e.outs;
    var er = e.er;
    var season = e.season;
    switch (key) {
      case 'season':
        season = int.parse(v);
        break;
      case 'game':
        game = v;
        break;
      case 'gameNumber':
        gameNumber = int.parse(v);
        break;
      case 'batter':
        batter = int.parse(v);
        break;
      case 'batterNumber':
        batterNumber = v.isEmpty ? null : int.parse(v);
        break;
      case 'battingOrder':
        battingOrder = int.parse(v);
        break;
      case 'hand':
        hand = v;
        break;
      case 'eventType':
        eventType = v;
        break;
      case 'pitchNum':
        pitchNum = v.isEmpty ? null : int.parse(v);
        break;
      case 'pitchType':
        pitchType = v;
        break;
      case 'call':
        call = v;
        break;
      case 'outcome':
        outcome = v.isEmpty ? null : v;
        ab = (outcome != null && !{'bb', 'hbp'}.contains(outcome)) ? 1 : 0;
        break;
      case 'outs':
        outs = int.parse(v);
        break;
      case 'er':
        er = double.parse(v);
        break;
    }
    return PitchEvent(
      id: e.id,
      userId: e.userId,
      game: game,
      gameNumber: gameNumber,
      batter: batter,
      batterNumber: batterNumber,
      battingOrder: battingOrder,
      hand: hand,
      eventType: eventType,
      pitchNum: pitchNum,
      pitchType: pitchType,
      call: call,
      outcome: outcome,
      ab: ab,
      outs: outs,
      er: er,
      xCoord: e.xCoord,
      yCoord: e.yCoord,
      battedType: e.battedType,
      inning: e.inning,
      paId: e.paId,
      season: season,
      timestamp: e.timestamp,
    );
  }

  /// Saves one edited cell through the app's normal update path
  /// (AppSession.updatePitchAt), so it persists and every other screen
  /// recalculates from the updated data.
  Future<void> _saveCell(int index, _Field f, String value) async {
    final session = context.read<AppSession>();
    if (index < 0 || index >= session.pitches.length) return;
    final updated = _applyEdit(session.pitches[index], f.key, value);
    try {
      await session.updatePitchAt(index, updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Couldn\'t save that change: $e')));
      }
    }
  }

  Future<void> _confirmDeleteRow(BuildContext context, int i) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete row?'),
        content: const Text('This permanently removes this pitch, whether it was '
            'logged from Game Input or added here.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<AppSession>().deletePitchAt(i);
    }
  }

  Widget _rowActions(BuildContext context, List<PitchEvent> data, int i) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'Insert row below this one',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.playlist_add, size: 18),
        onPressed: () => _openRowDialog(context, insertIndex: i + 1),
      ),
      IconButton(
        tooltip: 'Edit every field of this row',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.edit_outlined, size: 18),
        onPressed: () => _openRowDialog(context, existing: data[i], index: i),
      ),
      IconButton(
        tooltip: 'Delete row',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.delete_outline, color: AppColors.colError, size: 18),
        onPressed: () => _confirmDeleteRow(context, i),
      ),
    ]);
  }

  /// Wide screens: a header + one compact line per row, columns sized by flex
  /// so everything (all fields and the row buttons) fits without sideways
  /// scrolling. Narrow screens: each row becomes a card of labeled values.
  Widget _table(BuildContext context, List<PitchEvent> data, List<_Field> fields, double width) {
    const actionsW = 104.0;
    final wide = width >= 900;

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.ink,
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              for (final f in fields)
                Expanded(
                  flex: f.flex,
                  child: Tooltip(
                    message: f.label,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(f.short,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                ),
              const SizedBox(width: actionsW),
            ]),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.length,
            itemBuilder: (context, i) {
              final e = data[i];
              return Container(
                key: ValueKey('row-${e.id}'),
                decoration: BoxDecoration(
                  color: i.isEven ? Colors.white : AppColors.surfaceAlt,
                  border: const Border(bottom: BorderSide(color: AppColors.colBorder)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  for (final f in fields)
                    Expanded(
                      flex: f.flex,
                      child: _InlineCell(
                        key: ValueKey('${e.id}|${f.key}'),
                        field: f,
                        event: e,
                        onCommit: (v) => _saveCell(i, f, v),
                      ),
                    ),
                  SizedBox(width: actionsW, child: _rowActions(context, data, i)),
                ]),
              );
            },
          ),
        ],
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: data.length,
      itemBuilder: (context, i) {
        final e = data[i];
        return Container(
          key: ValueKey('card-${e.id}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.colBorder, width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in fields)
                SizedBox(
                  width: f.key == 'game' ? 150 : 92,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(f.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
                    ),
                    _InlineCell(
                      key: ValueKey('${e.id}|${f.key}|card'),
                      field: f,
                      event: e,
                      onCommit: (v) => _saveCell(i, f, v),
                    ),
                  ]),
                ),
            ]),
            Align(alignment: Alignment.centerRight, child: _rowActions(context, data, i)),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final data = session.pitches;

    // Same option set the Add/Edit dialog uses (custom pitch types + any
    // pitch type already in the data).
    final pitchTypeOptions = <String>{
      ...session.customPitchTypes.map((c) => c.toLowerCase()),
      ...data.map((p) => (p.pitchType ?? '').toLowerCase()).where((s) => s.isNotEmpty),
    }.toList()
      ..sort();
    final fields = _fields(pitchTypeOptions);

    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Direct Pitch Log Editor', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${data.length} rows logged', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            // ── Actions row — Add Row and Delete All live together here,
            // right above the table they act on.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _openRowDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Row (end)'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.colSuccess),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openRowDialog(context, insertIndex: 0),
                  icon: const Icon(Icons.vertical_align_top, size: 16),
                  label: const Text('Insert at Top'),
                ),
                OutlinedButton.icon(
                  onPressed: data.isEmpty ? null : () => _confirmDeleteAll(context),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('Delete All'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.colError),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Double-click (or double-tap) a value to edit it. Typed values: Enter saves, Esc cancels. '
              'Choice values (Hand, Type, Pitch, Call, Outcome) open a menu: pick one to save, click away to cancel. '
              'The pencil edits every field of a row at once.',
              style: TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            if (data.isEmpty)
              const Text('No data yet.', style: TextStyle(color: Colors.grey))
            else
              LayoutBuilder(builder: (context, constraints) => _table(context, data, fields, constraints.maxWidth)),
          ],
        ),
      ),
    );
  }
}

enum _Kind { text, integer, decimal, dropdown }

/// One editable column of the raw-data grid.
class _Field {
  final String key; // which PitchEvent field this edits
  final String label; // full name (header tooltip / card label)
  final String short; // compact header text
  final _Kind kind;
  final int flex; // share of the row width
  final String Function(PitchEvent) shown;
  final String Function(PitchEvent) editValue;
  final String? Function(String)? validate; // null result = valid
  final List<String> options; // dropdown choices

  const _Field(
    this.key,
    this.label,
    this.short,
    this.kind,
    this.flex, {
    required this.shown,
    required this.editValue,
    this.validate,
    this.options = const [],
  });
}

/// A single value in the grid. Normal state: plain text. Double-click:
/// typed fields turn into an input with an orange outline (Enter saves, Esc or
/// clicking away cancels; invalid input turns the outline red and isn't
/// saved); choice fields open a menu at the cell (pick to save, dismiss to
/// cancel) while the cell is outlined. A single click does nothing, so normal
/// scrolling and tapping are unaffected.
class _InlineCell extends StatefulWidget {
  final _Field field;
  final PitchEvent event;
  final Future<void> Function(String value) onCommit;
  const _InlineCell({super.key, required this.field, required this.event, required this.onCommit});

  @override
  State<_InlineCell> createState() => _InlineCellState();
}

class _InlineCellState extends State<_InlineCell> {
  bool _editing = false;
  String? _error;
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_editing) return;
    final f = widget.field;
    if (f.kind == _Kind.dropdown) {
      await _pickFromMenu();
      return;
    }
    _ctrl.text = f.editValue(widget.event);
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  Future<void> _pickFromMenu() async {
    final f = widget.field;
    final current = f.editValue(widget.event);
    // Always offer the row's current value, even if it isn't in the usual list
    // (e.g. a 'po' call on a pickoff row), so nothing is ever un-selectable.
    final opts = <String>[...f.options];
    if (!opts.contains(current)) opts.insert(0, current);

    setState(() => _editing = true);
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height);
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      initialValue: current,
      items: [
        for (final o in opts)
          PopupMenuItem<String>(
            value: o,
            height: 34,
            child: Text(
              o.isEmpty ? '(none)' : (f.key == 'pitchType' ? o.toUpperCase() : o),
              style: TextStyle(fontWeight: o == current ? FontWeight.w800 : FontWeight.w500),
            ),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (picked != null && picked != current) {
      await widget.onCommit(picked);
    }
  }

  Future<void> _commit() async {
    final raw = _ctrl.text.trim();
    final err = widget.field.validate?.call(raw);
    if (err != null) {
      setState(() => _error = err);
      _focus.requestFocus();
      return;
    }
    setState(() {
      _editing = false;
      _error = null;
    });
    if (raw != widget.field.editValue(widget.event)) {
      await widget.onCommit(raw);
    }
  }

  void _cancel() {
    if (!mounted) return;
    setState(() {
      _editing = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final editingTyped = _editing && f.kind != _Kind.dropdown;

    if (editingTyped) {
      return Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _cancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Tooltip(
          message: _error ?? 'Enter to save · Esc to cancel',
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.tint,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _error == null ? AppColors.brandOrangeDeep : AppColors.colError,
                width: 2,
              ),
            ),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              keyboardType: f.kind == _Kind.integer
                  ? TextInputType.number
                  : (f.kind == _Kind.decimal
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
              onEditingComplete: _commit,
              onTapOutside: (_) => _cancel(),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _start,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        decoration: _editing
            ? BoxDecoration(
                color: AppColors.tint,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.brandOrangeDeep, width: 2),
              )
            : null,
        child: Text(
          f.shown(widget.event),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5),
        ),
      ),
    );
  }
}
