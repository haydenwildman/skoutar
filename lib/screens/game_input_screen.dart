import '../widgets/orange_glow_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../models/pitch_event.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../utils/responsive.dart';
import '../widgets/baseball_field_painter.dart';
import '../services/batter_history_service.dart';
import '../services/stats_service.dart' show statHasScale;
import '../widgets/tier_scale_bar.dart';
import '../widgets/stat_hold_info.dart';
import '../services/color_guides.dart';
import 'package:intl/intl.dart';

/// The main content area walks through one step at a time instead of
/// showing every control at once (mirrors the redesign's "New Batter →
/// Pitch Type → Call → [Ball In Play] → [Spray Chart] → Pitch Type" flow).
enum _Stage { newBatter, pitchType, call, bip, spray, history }

class GameInputScreen extends StatefulWidget {
  const GameInputScreen({super.key});

  @override
  State<GameInputScreen> createState() => _GameInputScreenState();
}

class _GameInputScreenState extends State<GameInputScreen> {
  // ── Game header edit/new-game dialog controllers ───────────
  final _opponentCtrl = TextEditingController();
  final _gameNumCtrl = TextEditingController(text: '1');

  // ── Batter entry stage controllers ─────────────────────────
  final _jerseyCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '1');
  final _nameCtrl = TextEditingController();

  final _customPitchCtrl = TextEditingController();
  int _erValue = 0;

  String? _pitchType;
  String? _call;
  String? _bipOutcome;
  String? _battedType;
  double? _sprayX;
  double? _sprayY;

  late int _selectedYear;
  int? _lastSyncedOrder;

  /// True once the person has typed in the Order box on the New Batter form —
  /// until then the box simply follows the auto-advanced batting order.
  bool _orderEdited = false;
  late List<int> _yearOptions;

  _Stage _stage = _Stage.pitchType;
  _Stage _stageBeforeHistory = _Stage.pitchType;

  static const pitchTypes = ['FB', 'CV', 'CH', 'SL'];
  static const callButtons = [
    ['Ball', 'b'],
    ['Called Strike', 'sl'],
    ['Swinging Strike', 'ss'],
    ['Foul Ball', 'f'],
    ['Ball In Play', 'ip'],
    ['Hit By Pitch', 'hbp'],
  ];
  static const bipButtonsRow1 = ['1b', '2b', '3b', 'hr'];
  static const bipButtonsRow2 = ['go', 'fo', 'lo', 'fc', 'dp', 'e'];

  // ── Full names for every abbreviated code, used both as button labels
  // (per the redesign's "full words instead of abbreviations" requirement)
  // and as History screen labels. ──
  static const Map<String, String> pitchTypeFullNames = {
    'FB': 'Fastball',
    'CV': 'Curveball',
    'CH': 'Changeup',
    'SL': 'Slider',
  };
  static const Map<String, String> callTooltips = {
    'b': 'Ball — pitch outside the strike zone, not swung at',
    'sl': 'Strike looking — called third strike, batter did not swing',
    'ss': 'Swinging strike — batter swung and missed',
    'f': 'Foul ball',
    'ip': 'Ball In Play — pitch was put into play by the batter',
    'hbp': 'Hit By Pitch',
  };
  static const Map<String, String> callFullNames = {
    'b': 'Ball',
    'sl': 'Called Strike',
    'ss': 'Swinging Strike',
    'f': 'Foul Ball',
    'ip': 'Ball In Play',
    'hbp': 'Hit By Pitch',
    'dk': 'Dead Ball',
  };
  static const Map<String, String> eventTypeFullNames = {
    'po': 'Pickoff',
    'to': 'Caught Stealing',
    'txo': 'Throw Out',
    'bk': 'Balk',
  };
  static const Map<String, String> bipFullNames = {
    '1b': 'Single',
    '2b': 'Double',
    '3b': 'Triple',
    'hr': 'Home Run',
    'go': 'Ground Out',
    'fo': 'Fly Out',
    'lo': 'Line Out',
    'fc': "Fielder's Choice",
    'dp': 'Double Play',
    'e': 'Error',
  };
  static const Map<String, String> outcomeFullNames = {
    '1b': 'Single', '2b': 'Double', '3b': 'Triple', 'hr': 'Home Run',
    'go': 'Ground Out', 'fo': 'Fly Out', 'lo': 'Line Out',
    'fc': "Fielder's Choice", 'dp': 'Double Play', 'e': 'Error',
    'bb': 'Walk', 'hbp': 'Hit By Pitch', 'k': 'Strikeout (Swinging)',
    'kl': 'Strikeout (Looking)', 'dk': 'Dead Ball',
    'po_out': 'Pickoff Out', 'to': 'Caught Stealing', 'txo': 'Throw Out',
    'bk': 'Balk',
  };
  static const Map<String, String> battedTypeFullNames = {
    'gb': 'Ground Ball',
    'ld': 'Line Drive',
    'fb': 'Fly Ball',
  };
  static const Map<String, String> eventTooltips = {
    'po': 'Pickoff — runner picked off base for an out',
    'cs': 'Caught Stealing — runner thrown out attempting to steal',
    'to': 'Throw Out — runner/batter thrown out on a batted ball, not a standard GO/FO/LO out',
    'bk': 'Balk — illegal pitcher motion; logged only, no stat effect',
  };
  static const Map<String, String> handFullNames = {
    'L': 'Left', 'R': 'Right', 'S': 'Switch',
  };
  static const Map<String, String> handTooltips = {
    'L': 'Left-handed batter',
    'R': 'Right-handed batter',
    'S': 'Switch hitter — can bat from either side',
  };

  // ── Result/BIP/event button icons + colors. Pitch-type and BIP colors
  // are pulled live from AppColors (the Spray Chart's own palette) so they
  // can never drift out of sync; call/event buttons use their own separate
  // semantic color system, distinct from the pitch-type palette. Buttons
  // are text-only (no icons or emoji). ──
  static const Map<String, Color> callColor = {
    'b': AppColors.dataBlue,
    'sl': AppColors.perfExcellent,
    'ss': AppColors.perfExcellent,
    'f': AppColors.perfAverage,
    'ip': AppColors.dataNavy,
    'hbp': AppColors.perfPoor,
  };
  static const Map<String, String> eventActionLabels = {
    'po': 'Pickoff',
    'to': 'Caught Stealing',
    'txo': 'Throw Out',
    'bk': 'Balk',
  };

  String _pitchTypeLabel(String? code) {
    return context.read<AppSession>().pitchTypeLabel(code);
  }

  @override
  void initState() {
    super.initState();
    final session = context.read<AppSession>();
    _opponentCtrl.text = session.currentOpponent;
    _gameNumCtrl.text = session.currentGameNumber.toString();
    _selectedYear = session.currentSeason;
    final thisYear = DateTime.now().year;
    _yearOptions = List.generate(9, (i) => thisYear + 2 - i); // thisYear+2 .. thisYear-6
    if (!_yearOptions.contains(_selectedYear)) {
      _yearOptions.insert(0, _selectedYear);
    }
    // Jump straight into batter entry if no batter is up yet; otherwise
    // start on pitch-type entry for whoever's already at bat.
    _stage = session.committedJersey == null ? _Stage.newBatter : _Stage.pitchType;
  }

  @override
  void dispose() {
    _opponentCtrl.dispose();
    _gameNumCtrl.dispose();
    _jerseyCtrl.dispose();
    _orderCtrl.dispose();
    _nameCtrl.dispose();
    _customPitchCtrl.dispose();
    super.dispose();
  }

  // ── Game header actions ─────────────────────────────────────

  Future<void> _openEditGameDialog() async {
    final session = context.read<AppSession>();
    _opponentCtrl.text = session.currentOpponent;
    _gameNumCtrl.text = session.currentGameNumber.toString();
    int editYear = session.currentSeason;
    if (!_yearOptions.contains(editYear)) _yearOptions.insert(0, editYear);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          scrollable: true,
          title: const Text('Edit Current Game'),
          content: SizedBox(
            width: Responsive.dialogWidth(ctx, 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _opponentCtrl,
                  decoration: const InputDecoration(labelText: 'Team Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gameNumCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Game #'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: editYear,
                  decoration: const InputDecoration(labelText: 'Year'),
                  items: _yearOptions
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y', overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => editYear = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            OrangeGlowButton(
              onPressed: () {
                if (_opponentCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
    if (saved == true) {
      await session.editCurrentGameInfo(
          _opponentCtrl.text.trim(), int.tryParse(_gameNumCtrl.text) ?? session.currentGameNumber, editYear);
      _selectedYear = session.currentSeason;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openNewGameDialog() async {
    final session = context.read<AppSession>();
    final newOpponentCtrl = TextEditingController();
    final newGameNumCtrl = TextEditingController(text: '1');
    int newYear = session.currentSeason;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          scrollable: true,
          title: const Text('Start New Game'),
          content: SizedBox(
            width: Responsive.dialogWidth(ctx, 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Your previous game's data is kept — this just starts a fresh one.",
                  style: TextStyle(color: AppColors.colMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newOpponentCtrl,
                  decoration: const InputDecoration(labelText: 'Team Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newGameNumCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Game #'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: newYear,
                  decoration: const InputDecoration(labelText: 'Year'),
                  items: _yearOptions
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y', overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => newYear = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.perfExcellent),
              onPressed: () {
                if (newOpponentCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Start New Game'),
            ),
          ],
        );
      }),
    );
    if (confirmed == true) {
      session.setGame(newOpponentCtrl.text.trim(),
          int.tryParse(newGameNumCtrl.text) ?? 1, newYear);
      _selectedYear = newYear;
      _jerseyCtrl.clear();
      _nameCtrl.clear();
      _orderCtrl.text = '1';
      _orderEdited = false;
      _lastSyncedOrder = null;
      setState(() {
        _pitchType = null;
        _call = null;
        _bipOutcome = null;
        _battedType = null;
        _sprayX = null;
        _sprayY = null;
        _erValue = 0;
        _stage = _Stage.newBatter;
      });
    }
    newOpponentCtrl.dispose();
    newGameNumCtrl.dispose();
  }

  // ── Batter entry ─────────────────────────────────────────────

  void _openBatterEntry() {
    final session = context.read<AppSession>();
    // Prefill with whatever's currently on record, so correcting an
    // existing batter (or picking up a suggested one) doesn't require
    // retyping everything.
    _jerseyCtrl.text = session.committedJersey?.toString() ?? '';
    _orderCtrl.text = session.battingOrderSlot.toString();
    _orderEdited = false;
    _nameCtrl.text = session.committedJersey != null
        ? (session.batterNames[session.committedJersey] ?? '')
        : '';
    setState(() => _stage = _Stage.newBatter);
  }

  void _confirmBatterEntry() {
    final session = context.read<AppSession>();
    final jersey = int.tryParse(_jerseyCtrl.text);
    if (jersey == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a jersey #.')));
      return;
    }
    final typedOrder = int.tryParse(_orderCtrl.text);
    // Blank / invalid / zero falls back to the auto-advanced spot, so the
    // person normally only has to type the jersey #.
    final order = (typedOrder == null || typedOrder < 1) ? session.battingOrderSlot : typedOrder;
    if (!session.lineupLocked) {
      // Bootstraps the very first plate appearance of the lineup.
      session.setBatter(jersey, order);
    } else {
      // Every later batter: correct the auto-advanced slot live, without
      // resetting the count/outs/PA machinery that's already in progress.
      session.updateCommittedJersey(jersey);
      if (order != session.battingOrderSlot) {
        session.updateBattingOrderSlot(order);
      }
    }
    if (_nameCtrl.text.trim().isNotEmpty) {
      session.setBatterName(jersey, _nameCtrl.text.trim());
    }
    _jerseyCtrl.clear();
    _nameCtrl.clear();
    _orderEdited = false;
    _lastSyncedOrder = session.battingOrderSlot;
    _orderCtrl.text = session.battingOrderSlot.toString();
    setState(() => _stage = _Stage.pitchType);
  }

  // ── Pitch entry ──────────────────────────────────────────────

  Future<void> _finishPitch({
    required String call,
    String? bipOutcome,
    double? xCoord,
    double? yCoord,
    String? battedType,
  }) async {
    final session = context.read<AppSession>();
    if (_pitchType == null) return;
    if (session.currentOpponent.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Confirm the game first.')));
      return;
    }
    final result = await session.addPitch(
      pitchType: _pitchType!.toLowerCase(),
      call: call,
      bipOutcome: bipOutcome,
      xCoord: xCoord,
      yCoord: yCoord,
      battedType: battedType,
      er: _erValue.toDouble(),
    );
    if (!mounted) return;
    if (result.endedAB) {
      // The batting order auto-advanced (or wrapped) — put the new spot in the
      // Order box right now, so on the New Batter form the person only has to
      // type the jersey #.
      _orderCtrl.text = result.nextBattingOrder.toString();
      _lastSyncedOrder = result.nextBattingOrder;
      _orderEdited = false;
      _jerseyCtrl.clear();
      _nameCtrl.clear();
    }
    setState(() {
      _pitchType = null;
      _call = null;
      _bipOutcome = null;
      _battedType = null;
      _sprayX = null;
      _sprayY = null;
      _erValue = 0;
      // A batter we have no history for at this lineup spot needs the full
      // entry form; one we've already seen just needs the auto-filled
      // jersey confirmed live in the count bar, so jump straight back to
      // pitch entry for them.
      _stage = (result.endedAB && result.suggestedJersey == null)
          ? _Stage.newBatter
          : _Stage.pitchType;
    });
    if (result.endedAB && result.suggestedJersey != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Spot ${result.nextBattingOrder} — #${result.suggestedJersey} (from history — edit if needed)'),
        duration: const Duration(seconds: 3),
      ));
    } else if (result.endedAB) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Spot ${result.nextBattingOrder} — enter next batter'),
        duration: const Duration(seconds: 2),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pitch logged'), duration: Duration(milliseconds: 700)),
      );
    }
  }

  Future<void> _openCustomPitchMenu(String pt) async {
    final session = context.read<AppSession>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Change Color'),
              onTap: () => Navigator.pop(ctx, 'color'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: AppColors.perfPoor),
              title: const Text('Remove Button'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'color') {
      await _openChangePitchColorDialog(pt);
    } else if (choice == 'remove') {
      if (_pitchType == pt) setState(() => _pitchType = null);
      await session.removeCustomPitchType(pt);
    }
  }

  Future<void> _confirmRemovePitchType(String pt, {required bool isBuiltIn}) async {
    final session = context.read<AppSession>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${_pitchTypeLabel(pt)}" button?'),
        content: const Text(
            'This removes the button from Pitch Type. Pitches already logged with it keep their data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    if (_pitchType == pt) setState(() => _pitchType = null);
    if (isBuiltIn) {
      await session.hideBuiltInPitchType(pt);
    } else {
      await session.removeCustomPitchType(pt);
    }
  }

  /// Opens the "Add New Pitch Type" dialog — a full pitch name (no
  /// character limit) plus a color swatch. The chosen color is stored with
  /// the pitch and used everywhere it appears (button, spray chart,
  /// history, breakdown) via [AppColors.pitchColor].
  Future<void> _openAddPitchTypeDialog() async {
    _customPitchCtrl.clear();
    Color chosen = AppColors.pitchColorPresets[
        DateTime.now().millisecondsSinceEpoch % AppColors.pitchColorPresets.length];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        Future<void> submit() async {
          final session = context.read<AppSession>();
          final name = _customPitchCtrl.text.trim();
          if (name.isEmpty) return;
          if (AppSession.builtInPitchTypeFullNames
              .containsKey(name.toLowerCase())) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"$name" is already a built-in pitch type.')));
            return;
          }
          await session.addCustomPitchType(name, color: chosen);
          _customPitchCtrl.clear();
          if (mounted) Navigator.of(ctx).pop();
        }

        return AlertDialog(
          scrollable: true,
          title: const Text('Add New Pitch Type'),
          content: SizedBox(
            width: Responsive.dialogWidth(ctx, 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _customPitchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Pitch Name (e.g. Knuckleball)'),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 16),
                const Text('Color',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppColors.pitchColorPresets.map((c) {
                    final selected = c.value == chosen.value;
                    return InkWell(
                      onTap: () => setDialogState(() => chosen = c),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: selected ? AppColors.colText : Colors.transparent,
                              width: 2.5),
                        ),
                        child: selected
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            OrangeGlowButton(onPressed: submit, child: const Text('Add')),
          ],
        );
      }),
    );
    setState(() {});
  }

  /// Opens a small dialog to change an existing custom pitch type's color
  /// (reached via long-press → "Change Color" on that pitch's button).
  Future<void> _openChangePitchColorDialog(String key) async {
    final session = context.read<AppSession>();
    Color chosen = AppColors.pitchColor(key);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          scrollable: true,
          title: Text('Color for ${session.pitchTypeLabel(key)}'),
          content: SizedBox(
            width: Responsive.dialogWidth(ctx, 320),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppColors.pitchColorPresets.map((c) {
                final selected = c.value == chosen.value;
                return InkWell(
                  onTap: () => setDialogState(() => chosen = c),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected ? AppColors.colText : Colors.transparent, width: 2.5),
                    ),
                    child: selected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            OrangeGlowButton(
              onPressed: () async {
                await session.setCustomPitchTypeColor(key, chosen);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  // ── Live game/total stat helpers ────────────────────────────
  // "Game" numbers are scoped to the currently open game (opponent +
  // game # + season) and naturally reset the moment a new game starts,
  // since they're derived fresh from session.pitches on every rebuild
  // rather than tracked as separate state. "Total" numbers are never
  // filtered, so they keep accumulating across every game logged.

  bool _isCurrentGame(PitchEvent p, AppSession session) =>
      p.game == session.currentOpponent &&
      p.gameNumber == session.currentGameNumber &&
      p.season == session.currentSeason;

  /// Usage %, strike %, K%, and hits-against for [pt] (e.g. 'FB') in the
  /// current game only — used as the secondary line under each pitch-type
  /// button. K% is null (shown as N/A) rather than 0% when this pitch type
  /// hasn't been thrown yet this game.
  ({int n, double usagePct, double strikePct, double? kPct, int hits})
      _gamePitchTypeStats(AppSession session, String pt) {
    final gamePitches = session.pitches
        .where((p) => p.eventType == 'pitch' && _isCurrentGame(p, session))
        .toList();
    final ofType =
        gamePitches.where((p) => (p.pitchType ?? '') == pt.toLowerCase()).toList();
    final usage = gamePitches.isEmpty ? 0.0 : ofType.length / gamePitches.length * 100;
    final strikes =
        ofType.where((p) => {'ss', 'sl', 'f', 'ip'}.contains(p.call)).length;
    final strikePct = ofType.isEmpty ? 0.0 : strikes / ofType.length * 100;
    // K% — how often THIS pitch, when thrown, was the pitch that recorded
    // the strikeout (i.e. the put-away pitch), out of every time it was
    // thrown this game.
    final strikeouts =
        ofType.where((p) => p.outcome == 'k' || p.outcome == 'kl').length;
    final kPct = ofType.isEmpty ? null : strikeouts / ofType.length * 100;
    final hits = ofType
        .where((p) => p.call == 'ip' && PitchEvent.hitOutcomes.contains(p.outcome))
        .length;
    return (n: ofType.length, usagePct: usage, strikePct: strikePct, kPct: kPct, hits: hits);
  }

  /// Ball%, Strike%, Chase Rate, Foul Ball%, and Hit-By-Pitch% for the
  /// *current game only* — shown under the Call buttons as supporting
  /// info. N/A (rather than 0%) whenever there aren't any pitches yet.
  ///
  /// Chase Rate here is an approximation: this app doesn't track each
  /// pitch's location relative to the strike zone (only where a *batted*
  /// ball landed), so it's computed as (swinging strikes + fouls + balls
  /// in play) ÷ (that same total + called balls) — i.e. how often the
  /// batter swung on a pitch that wasn't a called strike down the middle.
  ({double? ballPct, double? strikePct, double? chasePct, double? foulPct, double? hbpPct})
      _gameCallStats(AppSession session) {
    final gamePitches = session.pitches
        .where((p) => p.eventType == 'pitch' && _isCurrentGame(p, session))
        .toList();
    if (gamePitches.isEmpty) {
      return (ballPct: null, strikePct: null, chasePct: null, foulPct: null, hbpPct: null);
    }
    final total = gamePitches.length;
    int count(bool Function(PitchEvent) f) => gamePitches.where(f).length;
    final balls = count((p) => p.call == 'b');
    final strikes = count((p) => {'ss', 'sl', 'f', 'ip'}.contains(p.call));
    final fouls = count((p) => p.call == 'f');
    final hbp = count((p) => p.call == 'hbp');
    final swings = count((p) => {'ss', 'f', 'ip'}.contains(p.call));
    final chaseDenominator = swings + balls;
    return (
      ballPct: balls / total * 100,
      strikePct: strikes / total * 100,
      chasePct: chaseDenominator == 0 ? null : swings / chaseDenominator * 100,
      foulPct: fouls / total * 100,
      hbpPct: hbp / total * 100,
    );
  }

  Widget _gameCallStatChip(String label, double? pct) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.colBorder),
      ),
      child: Text(
        '$label ${pct == null ? "N/A" : "${pct.round()}%"}',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.colMuted),
      ),
    );
  }

  /// (game count, career total count) for a Ball-In-Play outcome code
  /// (e.g. 'go', 'hr').
  (int, int) _bipCounts(AppSession session, String outcome) {
    final matches = session.pitches.where(
        (p) => p.eventType == 'pitch' && p.call == 'ip' && p.outcome == outcome);
    final game = matches.where((p) => _isCurrentGame(p, session)).length;
    return (game, matches.length);
  }

  /// (game count, career total count) for a non-pitch event type
  /// (po / to / txo / bk).
  (int, int) _eventCounts(AppSession session, String eventType) {
    final matches = session.pitches.where((p) => p.eventType == eventType);
    final game = matches.where((p) => _isCurrentGame(p, session)).length;
    return (game, matches.length);
  }

  // ── Responsive sizing helpers (phone only; desktop values unchanged) ──

  bool get _phone => Responsive.isPhone(context);

  /// Usable width inside a stage card on a phone: screen width minus the
  /// page padding, the card's own padding and its border.
  double get _stageInnerWidth =>
      MediaQuery.sizeOf(context).width - 2 * Responsive.pagePadding(context) - 2 * 16 - 3;

  /// Tile width: the original fixed desktop width, or on phones an equal
  /// share of the card ([phoneColumns] across) so tiles never overflow.
  double _tileWidth(double desktop, {int phoneColumns = 1, double spacing = 10}) {
    if (!_phone) return desktop;
    return ((_stageInnerWidth - spacing * (phoneColumns - 1)) / phoneColumns).floorToDouble();
  }

  /// Text-field width for the batter-entry form: fixed on desktop, full
  /// (or half) width on phones.
  double _fieldWidth(double desktop, {bool half = false, double spacing = 14}) {
    if (!_phone) return desktop;
    return half ? ((_stageInnerWidth - spacing) / 2).floorToDouble() : _stageInnerWidth;
  }

  Widget _maybeExpanded(Widget w) => _phone ? Expanded(child: w) : w;

  // ── Reusable button widgets ──────────────────────────────────

  Widget _bigButton(
    String label, {
    required VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool selected = false,
    String? tooltip,
    Color? idleColor,
  }) {
    final btn = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: BoxConstraints(minWidth: _phone ? 0 : 132, minHeight: 60),
        padding: EdgeInsets.symmetric(horizontal: _phone ? 8 : 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandOrangeDeep : (idleColor ?? AppColors.tint),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppColors.brandOrangeDeep : AppColors.colBorder, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.colText,
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  /// Pitch-type button: left-aligned bold pitch name with a color accent
  /// bar in that pitch's exact Spray Chart color, plus a secondary line of
  /// THIS GAME's usage / strike% / hits for that pitch.
  Widget _pitchTypeTile({
    required String code,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    String? tooltip,
    required ({int n, double usagePct, double strikePct, double? kPct, int hits}) stats,
  }) {
    final color = AppColors.pitchColor(code);
    final kLabel = stats.kPct == null ? 'N/A' : '${stats.kPct!.round()}%';
    final subtitle = stats.n == 0
        ? 'No pitches yet this game'
        : 'Usage ${stats.usagePct.round()}% • Strike ${stats.strikePct.round()}% • K% $kLabel • Hits ${stats.hits}';
    final btn = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: _tileWidth(260),
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 38,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label.toUpperCase(),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.colText)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.colMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  /// Pitch-result ("call") button — deliberately a different visual system
  /// from the pitch-type buttons (white card + circular icon badge,
  /// instead of a tinted card + color accent bar) so the two button
  /// families are never mistaken for each other.
  Widget _resultTile({
    IconData? icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    String? tooltip,
    String? subtitle,
    bool tinted = false,
    bool filled = false,
  }) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: _tileWidth(230, phoneColumns: 2),
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // `filled` = the orange family: orange border, faded center, soft glow
        // (same look as the pitch-type buttons, in orange).
        decoration: filled
            ? orangeGlowDecoration()
            : BoxDecoration(
                color: tinted ? color.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tinted ? color : AppColors.colBorder, width: tinted ? 2 : 1.5),
              ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.colText)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.colMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  /// Ball-In-Play outcome button — uses the exact Spray Chart color for
  /// that outcome, plus a live "Game: X • Total: Y" secondary line.
  Widget _bipTile({
    required String outcome,
    required VoidCallback onTap,
    required AppSession session,
  }) {
    final color = AppColors.sprayColor(outcome);
    final label = bipFullNames[outcome] ?? outcome.toUpperCase();
    final (game, total) = _bipCounts(session, outcome);
    return StatHoldInfo(
      title: label,
      description: composeHoldInfo(
        what: 'Logs the result of the ball in play. The line under the name shows how many of this result this game and in total.',
        colorGuide: 'The tile color is this result\'s color on the Spray Chart (a label, not a good/bad grade):\n${sprayFillColorGuide()}',
      ),
      child: _resultTile(
        label: label,
        color: color,
        onTap: onTap,
        subtitle: 'Game: $game • Total: $total',
        tinted: true,
      ),
    );
  }

  /// Other-event button (Pickoff / Caught Stealing / Throw Out / Balk) —
  /// same family as the result buttons, with a live Game/Total line.
  Widget _eventTile({
    required String eventCode,
    required VoidCallback? onTap,
    required AppSession session,
    String? tooltip,
  }) {
    final (game, total) = _eventCounts(session, eventCode);
    return _resultTile(
      label: eventActionLabels[eventCode] ?? eventCode.toUpperCase(),
      color: AppColors.brandOrangeDeep,
      filled: true,
      onTap: onTap,
      tooltip: tooltip,
      subtitle: 'Game: $game • Total: $total',
    );
  }

  Widget _stageCard({required String title, VoidCallback? onBack, required Widget child}) {
    return GlowCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 300),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (onBack != null) ...[
                    InkWell(
                      onTap: onBack,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.arrow_back, size: 18, color: AppColors.ink),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.colMuted,
                            letterSpacing: 1)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, thickness: 1, color: AppColors.colBorder),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

  /// Header shown once a game is selected: opponent / game / season chips
  /// plus the Edit and New Game buttons.
  ///
  /// NOTE: this used to be a single `Wrap` containing `if (!_phone) const
  /// Spacer()`. `Spacer` is an `Expanded`, which is only valid directly
  /// inside a `Row` / `Column` / `Flex`; a `Wrap` uses `WrapParentData`, so on
  /// any non-phone width (>= 600px — i.e. desktop and tablet) building it
  /// threw a ParentDataWidget / `FlexParentData` cast error and Flutter
  /// replaced the whole Game Input screen with the gray error widget. Phones
  /// skipped the `Spacer`, which is why they were unaffected. On wide screens
  /// we now use a real `Row` so the buttons are still right-aligned.
  Widget _buildConfirmedGameHeader(AppSession session) {
    final chips = <Widget>[
      Chip(
        label: Text('vs ${session.currentOpponent}'),
        backgroundColor: AppColors.perfExcellent,
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      Chip(
        label: Text('Game ${session.currentGameNumber}'),
        backgroundColor: AppColors.ink,
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      Chip(
        label: Text('${session.currentSeason}'),
        backgroundColor: AppColors.brandOrangeDeep,
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    ];
    final editButton = OutlinedButton.icon(
      onPressed: _openEditGameDialog,
      icon: const Icon(Icons.edit, size: 16),
      label: const Text('Edit'),
      style: _phone ? OutlinedButton.styleFrom(minimumSize: const Size(0, 44)) : null,
    );
    final newGameButton = ElevatedButton.icon(
      onPressed: _openNewGameDialog,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.perfExcellent,
        minimumSize: _phone ? const Size(0, 44) : null,
      ),
      icon: const Icon(Icons.add, size: 16),
      label: const Text('New Game'),
    );

    if (_phone) {
      // Phone layout (unchanged): everything wraps together.
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [...chips, editButton, newGameButton],
      );
    }

    // Tablet / desktop: chips on the left (they wrap if the opponent name is
    // long), buttons pinned to the right.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        ),
        const SizedBox(width: 8),
        editButton,
        const SizedBox(width: 8),
        newGameButton,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final gameConfirmed = session.currentOpponent.isNotEmpty;

    // Keep the Order field showing the auto-advanced batting order slot
    // (mirrors the R app auto-incrementing the lineup spot on each new AB)
    // instead of leaving whatever was last typed in the box.
    if (_lastSyncedOrder != session.battingOrderSlot) {
      _lastSyncedOrder = session.battingOrderSlot;
      if (!(_stage == _Stage.newBatter && _orderEdited)) {
        _orderCtrl.text = session.battingOrderSlot.toString();
        _orderEdited = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(session.currentUser?.pitcherDisplayName ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.ink)),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'History',
              onPressed: () => setState(() {
                _stageBeforeHistory = _stage;
                _stage = _Stage.history;
              }),
              icon: const Icon(Icons.history, color: AppColors.ink),
            ),
            OutlinedButton.icon(
              onPressed: () => session.undoLastPitch(),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Undo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.perfBelowAvg,
                minimumSize: _phone ? const Size(0, 44) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── 1. Game header: team/game info + Edit / New Game ──────
        GlowCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: gameConfirmed
                ? _buildConfirmedGameHeader(session)
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: _phone ? double.infinity : 200,
                        child: TextField(
                          controller: _opponentCtrl,
                          decoration: const InputDecoration(labelText: 'Team Name'),
                        ),
                      ),
                      SizedBox(
                        width: _phone ? ((MediaQuery.sizeOf(context).width - 2 * Responsive.pagePadding(context) - 2 * 12 - 3) - 10) / 2 : 110,
                        child: TextField(
                          controller: _gameNumCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Game #'),
                        ),
                      ),
                      SizedBox(
                        width: _phone ? ((MediaQuery.sizeOf(context).width - 2 * Responsive.pagePadding(context) - 2 * 12 - 3) - 10) / 2 : 100,
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: _selectedYear,
                          isDense: true,
                          decoration: const InputDecoration(labelText: 'Year'),
                          items: _yearOptions
                              .map((y) => DropdownMenuItem(value: y, child: Text('$y', overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedYear = v!),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          if (_opponentCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enter a team name first.')));
                            return;
                          }
                          session.setGame(_opponentCtrl.text.trim(),
                              int.tryParse(_gameNumCtrl.text) ?? 1, _selectedYear);
                          setState(() => _stage = _Stage.newBatter);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.perfExcellent,
                          minimumSize: _phone ? Size((MediaQuery.sizeOf(context).width - 2 * Responsive.pagePadding(context) - 2 * 12 - 3), 48) : null,
                        ),
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
          ),
        ),

        // ── 2. Batter + count/outs ─────────────────────────────────
        _buildBatterBar(session),

        // ── 3. Main content area — one stage at a time ─────────────
        _buildMainContent(session),

        // ── 4. Batter History — this game's Team + Jersey # ──
        if (gameConfirmed && session.committedJersey != null) ...[
          const SizedBox(height: 14),
          _buildBatterHistorySection(session),
        ],
      ],
    );
  }

  /// Batter + count + outs bar. Desktop keeps the original single-row
  /// layout. On phones the count and outs are stacked in a right-hand
  /// column so the batter's name and Order / Hand / Faced / Jersey line get
  /// real room and are never truncated to a few characters.
  Widget _buildBatterBar(AppSession session) {
    final phone = _phone;
    final hasBatter = session.committedJersey != null;
    final batterName = hasBatter
        ? (session.batterNames[session.committedJersey!]?.isNotEmpty == true
            ? session.batterNames[session.committedJersey!]!
            : '#${session.committedJersey}')
        : 'No batter set';
    final details =
        'Order ${session.battingOrderSlot} · ${handFullNames[session.hand] ?? session.hand} · Faced ${session.completedPAs}${hasBatter ? "  ·  #${session.committedJersey}" : ""}';

    final iconSize = phone ? 22.0 : 16.0;
    final iconPad = phone ? 8.0 : 2.0;

    final batterInfo = Expanded(
      child: InkWell(
        onTap: session.currentOpponent.isEmpty ? null : _openBatterEntry,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    batterName,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                    maxLines: phone ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    details,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: phone ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );

    final countText = Text('${session.balls}-${session.strikes}',
        style: TextStyle(
            color: Colors.white,
            fontSize: phone ? 30 : 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 2));

    final outsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${session.outs} OUT${session.outs == 1 ? "" : "S"}',
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Decrease outs',
              child: InkWell(
                onTap: session.outs > 0 ? () => session.setOuts(session.outs - 1) : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.all(iconPad),
                  child: Icon(Icons.remove_circle_outline,
                      size: iconSize,
                      color: session.outs > 0 ? Colors.white70 : Colors.white24),
                ),
              ),
            ),
            StatHoldInfo(
              title: 'Outs',
              description: composeHoldInfo(
                what: 'Outs in the current inning. Use the arrows next to the dots to change it.',
                colorGuide: [
                  swatchLine(AppColors.perfAverage, 'Yellow dot: an out already recorded.'),
                  'Empty (outlined) dot: an out still available. Three filled dots end the inning. These are status markers, not graded, so there are no cutoffs.',
                ].join('\n'),
              ),
              child: Row(
              children: List.generate(3, (i) {
                final filled = i < session.outs;
                return Container(
                  margin: const EdgeInsets.only(left: 4),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppColors.perfAverage : Colors.transparent,
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                );
              }),
            ),
            ),
            Tooltip(
              message: 'Increase outs',
              child: InkWell(
                onTap: session.outs < 3 ? () => session.setOuts(session.outs + 1) : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.all(iconPad),
                  child: Icon(Icons.add_circle_outline,
                      size: iconSize,
                      color: session.outs < 3 ? Colors.white70 : Colors.white24),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: phone
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                batterInfo,
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [countText, const SizedBox(height: 2), outsControl],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                batterInfo,
                const SizedBox(width: 14),
                countText,
                const SizedBox(width: 14),
                outsControl,
              ],
            ),
    );
  }

  Widget _buildMainContent(AppSession session) {
    switch (_stage) {
      case _Stage.newBatter:
        return _buildBatterEntryStage(session);
      case _Stage.pitchType:
        return _buildPitchTypeStage(session);
      case _Stage.call:
        return _buildCallStage(session);
      case _Stage.bip:
        return _buildBipStage(session);
      case _Stage.spray:
        return _buildSprayStage(session);
      case _Stage.history:
        return _buildHistoryStage(session);
    }
  }

  // ── Stage 1: New batter entry ───────────────────────────────

  Widget _buildBatterEntryStage(AppSession session) {
    return _stageCard(
      title: 'NEW BATTER',
      onBack: session.committedJersey != null && session.lineupLocked
          ? () => setState(() => _stage = _Stage.pitchType)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Builder(builder: (context) {
            final jerseyField = SizedBox(
              width: _fieldWidth(150, half: true),
              child: TextField(
                controller: _jerseyCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(labelText: 'Jersey #'),
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirmBatterEntry(),
              ),
            );
            final nameField = SizedBox(
              width: _fieldWidth(220),
              child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(labelText: 'Batter Name (optional)'),
              ),
            );
            final orderField = SizedBox(
              width: _fieldWidth(150, half: true),
              child: TextField(
                controller: _orderCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                onChanged: (_) => _orderEdited = true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirmBatterEntry(),
                decoration: InputDecoration(
                    labelText: _phone ? 'Order' : 'Batting Order'),
              ),
            );
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              // Phone: Jersey # and Order side by side, name below.
              children: _phone
                  ? [jerseyField, orderField, nameField]
                  : [jerseyField, nameField, orderField],
            );
          }),
          const SizedBox(height: 8),
          const Text(
            'The batting order advances on its own — just type the jersey #. '
            'Enter 1 to start the lineup over; 10 and up keep counting.',
            style: TextStyle(fontSize: 11.5, color: AppColors.colMuted, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          const Text('Bats',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final h in ['L', 'R', 'S'])
                _maybeExpanded(Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _bigButton(
                    handFullNames[h]!,
                    selected: session.hand == h,
                    onTap: () => session.setHand(h),
                    tooltip: handTooltips[h],
                  ),
                )),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _confirmBatterEntry,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.perfExcellent, padding: const EdgeInsets.symmetric(vertical: 18)),
              child: const Text('Confirm', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stage 2: Pitch type ─────────────────────────────────────

  Widget _buildPitchTypeStage(AppSession session) {
    return _stageCard(
      title: '1 · PITCH TYPE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ...pitchTypes.where((pt) => !session.hiddenBuiltInPitchTypes.contains(pt)).map(
                    (pt) => _pitchTypeTile(
                      code: pt,
                      label: _pitchTypeLabel(pt),
                      stats: _gamePitchTypeStats(session, pt),
                      onTap: () => setState(() {
                        _pitchType = pt;
                        _stage = _Stage.call;
                      }),
                      onLongPress: () => _confirmRemovePitchType(pt, isBuiltIn: true),
                      tooltip: '${_pitchTypeLabel(pt)} — press & hold to remove',
                    ),
                  ),
              ...session.customPitchTypes.map(
                (pt) => _pitchTypeTile(
                  code: pt,
                  label: session.pitchTypeLabel(pt),
                  stats: _gamePitchTypeStats(session, pt),
                  onTap: () => setState(() {
                    _pitchType = pt;
                    _stage = _Stage.call;
                  }),
                  onLongPress: () => _openCustomPitchMenu(pt),
                  tooltip: '${session.pitchTypeLabel(pt)} — press & hold for options',
                ),
              ),
              SizedBox(
                width: _phone ? double.infinity : null,
                child: _bigButton(
                  'Add New Pitch',
                  onTap: _openAddPitchTypeDialog,
                  idleColor: Colors.white,
                ),
              ),
            ],
          ),
          if (session.hiddenBuiltInPitchTypes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => session.restoreBuiltInPitchTypes(),
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore removed pitch types'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('OTHER GAME EVENTS',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _eventTile(
                eventCode: 'po',
                session: session,
                onTap: session.currentOpponent.isEmpty
                    ? null
                    : () async {
                        await session.addPickoff();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Pickoff — 1 out recorded.'),
                            duration: Duration(seconds: 1)));
                      },
                tooltip: eventTooltips['po'],
              ),
              _eventTile(
                eventCode: 'to',
                session: session,
                onTap: session.currentOpponent.isEmpty
                    ? null
                    : () async {
                        await session.addCaughtStealing();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Caught stealing — 1 out recorded.'),
                            duration: Duration(seconds: 1)));
                      },
                tooltip: eventTooltips['cs'],
              ),
              _eventTile(
                eventCode: 'txo',
                session: session,
                onTap: session.currentOpponent.isEmpty
                    ? null
                    : () async {
                        await session.addThrowOut();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Throw out — 1 out recorded.'),
                            duration: Duration(seconds: 1)));
                      },
                // "LAST PLAY" is called out up front and in caps so it's
                // unmistakable this applies to the play that just happened,
                // not the current/next one.
                tooltip:
                    'THROW OUT applies to the LAST PLAY.\n${eventTooltips['to']}',
              ),
              _eventTile(
                eventCode: 'bk',
                session: session,
                onTap: session.currentOpponent.isEmpty
                    ? null
                    : () async {
                        await session.addBalk();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Balk logged.'), duration: Duration(seconds: 1)));
                      },
                tooltip: eventTooltips['bk'],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stage 3: Call ───────────────────────────────────────────

  Widget _erSelector() {
    if (_phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ER on this pitch', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (n) {
              final selected = _erValue == n;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: n < 4 ? 8 : 0),
                  child: InkWell(
                    onTap: () => setState(() => _erValue = n),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.perfBelowAvg : AppColors.tint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: selected ? AppColors.perfBelowAvg : AppColors.brandOrangeDeep,
                            width: 1.5),
                      ),
                      child: Text('$n',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: selected ? Colors.white : AppColors.colText)),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('ER on this pitch',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(width: 10),
        ...List.generate(5, (n) {
          final selected = _erValue == n;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => setState(() => _erValue = n),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.perfBelowAvg : AppColors.tint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: selected ? AppColors.perfBelowAvg : AppColors.brandOrangeDeep, width: 1.5),
                ),
                child: Text('$n',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : AppColors.colText)),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCallStage(AppSession session) {
    final callStats = _gameCallStats(session);
    return _stageCard(
      title: '2 · CALL — ${_pitchTypeLabel(_pitchType)}',
      onBack: () => setState(() {
        _pitchType = null;
        _stage = _Stage.pitchType;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _erSelector(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: callButtons.map((c) {
              final label = c[0];
              final code = c[1];
              return _resultTile(
                label: label,
                // Ball/Strike call section: same filled orange as the other
                // Game Input buttons/events.
                color: AppColors.brandOrangeDeep,
                filled: true,
                tooltip: callTooltips[code],
                onTap: () {
                  if (code == 'ip') {
                    setState(() {
                      _call = 'ip';
                      _stage = _Stage.bip;
                    });
                  } else {
                    _finishPitch(call: code);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          const Text('THIS GAME',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _gameCallStatChip('Ball%', callStats.ballPct),
              _gameCallStatChip('Strike%', callStats.strikePct),
              _gameCallStatChip('Chase', callStats.chasePct),
              _gameCallStatChip('Foul%', callStats.foulPct),
              _gameCallStatChip('HBP%', callStats.hbpPct),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stage 4: Ball In Play outcome ───────────────────────────

  Widget _buildBipStage(AppSession session) {
    return _stageCard(
      title: '3 · BALL IN PLAY — ${_pitchTypeLabel(_pitchType)}',
      onBack: () => setState(() {
        _call = null;
        _stage = _Stage.call;
      }),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [...bipButtonsRow1, ...bipButtonsRow2].map((o) {
          return _bipTile(
            outcome: o,
            session: session,
            onTap: () => setState(() {
              _bipOutcome = o;
              // Auto-select the matching batted-ball type for the outs
              // that clearly imply one — still changeable on the next
              // (spray chart) step.
              const autoBattedType = {'go': 'gb', 'fo': 'fb', 'lo': 'ld'};
              if (autoBattedType.containsKey(o)) _battedType = autoBattedType[o];
              _stage = _Stage.spray;
            }),
          );
        }).toList(),
      ),
    );
  }

  // ── Stage 5: Spray chart ────────────────────────────────────

  Widget _buildSprayStage(AppSession session) {
    return _stageCard(
      title: '4 · MARK LOCATION — ${bipFullNames[_bipOutcome] ?? _bipOutcome ?? ""}',
      onBack: () => setState(() {
        _bipOutcome = null;
        _stage = _Stage.bip;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tap the field to mark where the ball was hit',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.colMuted)),
          const SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (layoutCtx, constraints) {
                    final size = constraints.biggest;
                    return SprayFieldSurface(
                      sprayPoints: const [],
                      highlightX: _sprayX,
                      highlightY: _sprayY,
                      onTapDown: (details) {
                        final field =
                            FieldCoordConverter.canvasToField(details.localPosition, size);
                        setState(() {
                          _sprayX = field.dx;
                          _sprayY = field.dy;
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['gb', 'ld', 'fb'].map((b) {
              final label = {
                'gb': 'Ground Ball',
                'ld': 'Line Drive',
                'fb': 'Fly Ball',
              }[b]!;
              final btn = _bigButton(label,
                  selected: _battedType == b, onTap: () => setState(() => _battedType = b));
              return _phone
                  ? SizedBox(width: _tileWidth(132, phoneColumns: 3, spacing: 8), child: btn)
                  : btn;
            }).toList(),
          ),
          const SizedBox(height: 14),
          _erSelector(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sprayX == null
                  ? null
                  : () => _finishPitch(
                        call: 'ip',
                        bipOutcome: _bipOutcome,
                        xCoord: _sprayX,
                        yCoord: _sprayY,
                        battedType: _battedType,
                      ),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.perfExcellent, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_sprayX == null ? 'Mark a location to continue' : 'Add Pitch',
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stage 6: History ────────────────────────────────────────

  /// Recent-Pitch-History stage: last 10 pitches from the CURRENT GAME
  /// only, newest first, built like a scouting/analysis screen rather than
  /// a plain text list — the most recent pitch gets a large, prominent
  /// card (with its actual spray location if it was put in play), and the
  /// previous nine are shown underneath in a compact, scannable sequence.
  Widget _buildHistoryStage(AppSession session) {
    final all = session.pitches;
    final counts = _computePitchCounts(all);
    final recent = <int>[];
    for (var i = all.length - 1; i >= 0 && recent.length < 10; i--) {
      if (_isCurrentGame(all[i], session)) recent.add(i);
    }

    return _stageCard(
      title: 'HISTORY — LAST ${recent.length} PITCHES THIS GAME',
      onBack: () => setState(() => _stage = _stageBeforeHistory),
      child: recent.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No pitches logged yet this game.', style: TextStyle(color: Colors.grey)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _mostRecentPitchCard(session, all[recent.first], counts[recent.first]),
                if (recent.length > 1) ...[
                  const SizedBox(height: 16),
                  const Text('PREVIOUS PITCHES',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  for (final i in recent.skip(1)) _historySequenceRow(all[i], counts[i]),
                ],
              ],
            ),
    );
  }

  /// The single most recent pitch — large and unmistakably the primary
  /// item on the History screen (spec: "who was hitting, what was the
  /// situation, what did I throw, what happened, where was it hit").
  Widget _mostRecentPitchCard(AppSession session, PitchEvent p, (String, String)? countPair) =>
      StatHoldInfo(
        title: 'Most recent pitch',
        description: composeHoldInfo(
          what: 'The latest pitch or event logged in this at-bat, with its result.',
          colorGuide: _eventColorGuide(p),
        ),
        child: _mostRecentPitchCardBox(session, p, countPair),
      );

  /// Color guide for a logged pitch/event: pitch-type color, or the neutral
  /// color used for non-pitch events.
  String _eventColorGuide(PitchEvent p) {
    if (p.eventType == 'pitch') return pitchTypeColorGuide([p.pitchType ?? 'other']);
    return swatchLine(AppColors.dataNavy,
        'Navy/gray: a non-pitch event (pickoff, caught stealing, throw out, balk). It is a label color, not a good/bad grade.');
  }

  Widget _mostRecentPitchCardBox(AppSession session, PitchEvent p, (String, String)? countPair) {
    final isPitch = p.eventType == 'pitch';
    final color = isPitch ? AppColors.pitchColor(p.pitchType) : AppColors.dataNavy;
    final resultLabel = isPitch
        ? (outcomeFullNames[p.outcome] ?? callFullNames[p.call] ?? (p.outcome ?? p.call ?? ''))
        : (eventTypeFullNames[p.eventType] ?? p.eventType.toUpperCase());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LAST PITCH',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          if (p.batterNumber != null)
            Text('#${p.batterNumber} — ${session.batterNames[p.batterNumber] ?? 'Unknown'}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.ink)),
          if (p.batterNumber != null) ...[
            const SizedBox(height: 2),
            Text(
                '${handFullNames[p.hand] ?? p.hand} • Batting ${_ordinal(p.battingOrder)}',
                style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (countPair != null) _pill('${countPair.$2} Count'),
            _pill('${p.outs} Out${p.outs == 1 ? '' : 's'}'),
            if (p.inning != null) _pill('Inning ${p.inning}'),
          ]),
          const SizedBox(height: 10),
          if (isPitch)
            Text(_pitchTypeLabel(p.pitchType),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: color)),
          Text(resultLabel.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
          if (p.battedType != null) ...[
            const SizedBox(height: 4),
            Text(battedTypeFullNames[p.battedType] ?? p.battedType!,
                style: const TextStyle(fontSize: 13, color: AppColors.colMuted)),
          ],
          if (p.xCoord != null && p.yCoord != null) ...[
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: SprayFieldSurface(sprayPoints: [p]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.colBorder)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink)),
      );

  String _ordinal(int n) {
    if (n <= 0) return '$n';
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// A previous pitch shown as a single dense, scannable sequence line —
  /// e.g. "#27 — Fastball — Ball — 0-0" — so the whole at-bat's shape is
  /// easy to read at a glance underneath the prominent last pitch.
  Widget _historySequenceRow(PitchEvent p, (String, String)? countPair) => StatHoldInfo(
        title: 'Pitch in this at-bat',
        description: composeHoldInfo(
          what: 'One earlier pitch or event from this at-bat, shown as: batter number, pitch, result, batted-ball type and count.',
          colorGuide: _eventColorGuide(p),
        ),
        child: _historySequenceRowBox(p, countPair),
      );

  Widget _historySequenceRowBox(PitchEvent p, (String, String)? countPair) {
    final isPitch = p.eventType == 'pitch';
    final color = isPitch ? AppColors.pitchColor(p.pitchType) : AppColors.colMuted;
    final resultLabel = isPitch
        ? (outcomeFullNames[p.outcome] ?? callFullNames[p.call] ?? (p.outcome ?? p.call ?? ''))
        : (eventTypeFullNames[p.eventType] ?? p.eventType.toUpperCase());
    final parts = <String>[
      if (p.batterNumber != null) '#${p.batterNumber}',
      if (isPitch) _pitchTypeLabel(p.pitchType),
      resultLabel,
      if (p.battedType != null) (battedTypeFullNames[p.battedType] ?? p.battedType!),
      if (countPair != null) countPair.$2,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(parts.join('  —  '),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                overflow: TextOverflow.ellipsis),
          ),
          if (p.inning != null)
            Text('Inn ${p.inning}', style: const TextStyle(fontSize: 10.5, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  /// Reconstructs "count before → count after" for every logged pitch by
  /// replaying the same ball/strike transitions [AppSession.addPitch] uses,
  /// grouped by plate appearance (game + game # + batter + jersey + PA id) —
  /// the count itself isn't stored per-row, only the cumulative outs are.
  Map<int, (String, String)> _computePitchCounts(List<PitchEvent> all) {
    final groups = <String, List<int>>{};
    for (var i = 0; i < all.length; i++) {
      final p = all[i];
      if (p.eventType != 'pitch') continue;
      final key = '${p.game}|${p.gameNumber}|${p.batter}|${p.batterNumber}|${p.paId}';
      groups.putIfAbsent(key, () => []).add(i);
    }
    final result = <int, (String, String)>{};
    for (final idxList in groups.values) {
      int b = 0, s = 0;
      for (final idx in idxList) {
        final before = '$b-$s';
        switch (all[idx].call) {
          case 'b':
            b++;
            break;
          case 'ss':
          case 'sl':
            s++;
            break;
          case 'f':
            if (s < 2) s++;
            break;
        }
        result[idx] = (before, '$b-$s');
      }
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════════
  //  BATTER HISTORY — everything ever logged against this same
  //  Team + Jersey # (both must match), persisting across games.
  //  A compact scouting panel: batter-specific offensive stats, last
  //  at-bat, tendencies and spray chart, with the full sequence history
  //  one tap away in "Previous Sequences". Never suggests what to throw
  //  — informational only.
  // ══════════════════════════════════════════════════════════════════

  Widget _buildBatterHistorySection(AppSession session) {
    final jersey = session.committedJersey!;
    final team = session.currentOpponent;
    final history = BatterHistoryService.build(
      allPitches: session.pitches,
      team: team,
      jersey: jersey,
      gameNumber: session.currentGameNumber,
      season: session.currentSeason,
    );
    final batterName = session.batterNames[jersey];

    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('BATTER HISTORY',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$team · #$jersey',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(height: 1, thickness: 1, color: AppColors.colBorder),
            const SizedBox(height: 8),
            // Compact one-row batter header: "#27 John Smith | Right-Handed | Batting 4th"
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: batterName != null && batterName.isNotEmpty
                        ? '#$jersey $batterName'
                        : '#$jersey',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink),
                  ),
                  if (session.hand.isNotEmpty) ...[
                    const TextSpan(text: '   |   ', style: TextStyle(color: AppColors.colBorder, fontWeight: FontWeight.w900)),
                    TextSpan(
                      text: _handLabel(session.hand),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.colMuted),
                    ),
                  ],
                  const TextSpan(text: '   |   ', style: TextStyle(color: AppColors.colBorder, fontWeight: FontWeight.w900)),
                  TextSpan(
                    text: 'Batting ${_ordinal(session.battingOrderSlot)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.colMuted),
                  ),
                  const TextSpan(text: '   |   ', style: TextStyle(color: AppColors.colBorder, fontWeight: FontWeight.w900)),
                  TextSpan(
                    text: history.timesFaced == 0
                        ? '1st PA this game'
                        : 'PA ${history.currentPlateAppearance} · faced ${history.timesFaced}x',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.brandOrangeDeep),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (!history.hasData) ...[
              const SizedBox(height: 10),
              const Text(
                'First plate appearance of this game — not faced yet. '
                'Their history shows up here the next time they come to the plate.',
                style: TextStyle(fontSize: 12, color: AppColors.colMuted),
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 1, color: AppColors.colBorder),
              const SizedBox(height: 8),
              const Text('OVERALL STATS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              _batterStatsGrid(history.offense),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 1, color: AppColors.colBorder),
              const SizedBox(height: 8),
              // Last At-Bat + Previous Sequences side by side — condenses
              // the vertical space these two related blocks used to take
              // stacked on top of one another.
              LayoutBuilder(builder: (context, c) {
                final lastAtBat = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LAST AT-BAT',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    _atBatCard(history.lastAtBat!, history.jersey),
                  ],
                );
                // Wide: the at-bat takes the room, the "Previous Sequences" tile
                // sits beside it. Narrow (phone): stack them so the sequence
                // chips get the full width.
                if (c.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      lastAtBat,
                      const SizedBox(height: 8),
                      _previousSequencesTile(history),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: lastAtBat),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _previousSequencesTile(history)),
                  ],
                );
              }),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 1, color: AppColors.colBorder),
              const SizedBox(height: 8),
              // Batter Tendencies + Spray Chart side by side when there's
              // spray data; tendencies alone (full width) otherwise.
              if (history.sprayPoints.isNotEmpty)
                LayoutBuilder(builder: (context, c) {
                  final tendencies = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BATTER TENDENCIES',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      _batterTendenciesBlock(history),
                    ],
                  );
                  final spray = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BATTER SPRAY CHART',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190, maxHeight: 190),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: SprayFieldSurface(sprayPoints: history.sprayPoints),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _sprayOutcomeLegend(history.sprayPoints),
                    ],
                  );
                  if (c.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [tendencies, const SizedBox(height: 12), spray],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: tendencies),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: spray),
                    ],
                  );
                })
              else ...[
                const Text('BATTER TENDENCIES',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
                const SizedBox(height: 6),
                _batterTendenciesBlock(history),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Compact "Previous Sequences" tile — sits next to Last At-Bat instead
  /// of a full-width centered button, so the two related blocks share one
  /// row instead of stacking.
  Widget _previousSequencesTile(BatterHistory history) {
    return InkWell(
      onTap: () => _openPreviousSequences(history),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.tint,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PREVIOUS SEQUENCES',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.colMuted, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text('${history.previousSequences.length}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
            const Text('at-bats · tap to view',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
          ],
        ),
      ),
    );
  }

  String _handLabel(String hand) {
    if (hand == 'S') return 'Switch Hitter';
    return '${handFullNames[hand] ?? hand}-Handed';
  }

  /// Baseball-style rate, no leading zero (".286", not "0.286"); "N/A"
  /// when there isn't enough data to calculate it (never a bare "0%").
  String _fmtRate(double? v, {int decimals = 3}) {
    if (v == null) return 'N/A';
    final s = v.toStringAsFixed(decimals);
    return s.startsWith('0.') ? s.substring(1) : s;
  }

  String _fmtPct(double? v) => v == null ? 'N/A' : '${v.toStringAsFixed(1)}%';

  /// Overall Stats — a compact 2-row × 4-column grid (AVG/OBP/SLG/OPS,
  /// then BB%/K%/BABIP/AB), each cell a small color-graded bar so the
  /// value can be read at a glance rather than looked up on a scale.
  /// Grades the BATTER's own offense (batter_* keys — the mirror image of
  /// the pitcher-allowed AVG/OBP/SLG grading used elsewhere in the app).
  Widget _batterStatsGrid(BatterOffenseStats o) {
    final cells = <Widget Function()>[
      () => _miniStatCell('AVG', _fmtRate(o.avg), o.avg, 'batter_AVG'),
      () => _miniStatCell('OBP', _fmtRate(o.obp), o.obp, 'batter_OBP'),
      () => _miniStatCell('SLG', _fmtRate(o.slg), o.slg, 'batter_SLG'),
      () => _miniStatCell('OPS', _fmtRate(o.ops), o.ops, 'batter_OPS'),
      () => _miniStatCell('BB%', _fmtPct(o.bbPct), o.bbPct, 'batter_BB_pct'),
      () => _miniStatCell('K%', _fmtPct(o.kPct), o.kPct, 'batter_K_pct'),
      () => _miniStatCell('BABIP', _fmtRate(o.babip), o.babip, 'batter_BABIP'),
      () => _miniStatCell('AB', '${o.ab}', null, null),
    ];
    // 8 across when there is room, otherwise 4 (two rows), and 2 on very
    // narrow panels — each cell always keeps enough width for its value.
    return LayoutBuilder(builder: (context, c) {
      const gap = 6.0;
      final cols = c.maxWidth >= 640 ? 8 : (c.maxWidth >= 300 ? 4 : 2);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final cell in cells) SizedBox(width: w.floorToDouble(), child: cell())],
      );
    });
  }

  /// One small stat cell: label, value, and a thin tier-colored scale with a
  /// marker at the value ([TierScaleBar], compact) - green end on the left for
  /// lower-is-better stats, on the right for higher-is-better ones. Plain
  /// counts (no [statKey]) render a neutral bar instead. A null [rawValue]
  /// shows "N/A" with a faded scale and no marker.
  Widget _miniStatCell(String label, String display, double? rawValue, String? statKey) {
    final hasValue = display != 'N/A';
    final scaled = statHasScale(statKey);
    const meanings = <String, String>{
      'AVG': 'Batting average: hits ÷ at-bats.',
      'OBP': 'On-base percentage: how often the batter reaches base (hits + walks + hit-by-pitches ÷ plate appearances).',
      'SLG': 'Slugging percentage: total bases ÷ at-bats, so extra-base hits count for more.',
      'OPS': 'On-base plus slugging (OBP + SLG): a single number for overall offense.',
      'BB%': 'Walk percentage: walks ÷ plate appearances.',
      'K%': 'Strikeout percentage: strikeouts ÷ plate appearances.',
      'BABIP': 'Batting average on balls in play: hits on balls put in play (not counting home runs and strikeouts).',
      'AB': 'At-bats this batter has against you.',
    };
    final guide = scaled
        ? statColorGuide(statKey!,
            bar: true,
            note: 'Graded from the PITCHER\'s point of view: a high AVG, OBP, SLG, OPS, BB% or BABIP is red (bad for you), and a high K% is green (good for you).')
        : swatchLine(AppColors.brandOrangeDeep,
            'Orange bar: a plain count. It is not a good/bad grade, so there are no cutoffs.');
    return StatHoldInfo(
      title: label,
      description: composeHoldInfo(
        what: '${meanings[label] ?? label}${hasValue ? '\nThis batter: $display.' : '\nNo data yet (N/A).'}',
        colorGuide: guide,
      ),
      child: _miniStatCellBox(label, display, rawValue, statKey, hasValue, scaled),
    );
  }

  Widget _miniStatCellBox(
      String label, String display, double? rawValue, String? statKey, bool hasValue, bool scaled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.colBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: AppColors.colMuted)),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(display,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: hasValue ? AppColors.colText : AppColors.colMuted)),
          ),
          const SizedBox(height: 4),
          if (scaled)
            TierScaleBar(statKey: statKey!, rawValue: rawValue, valueText: display, compact: true)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 4,
                child: Container(
                  color: hasValue ? AppColors.brandOrangeDeep.withOpacity(0.35) : AppColors.colBorder,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact label for one pitch's result in the sequence line (same existing
  /// terminology as everywhere else; a ball in play is just "BIP").
  String _pitchResultShort(PitchEvent p) {
    if (p.call == 'ip') return 'BIP';
    return callFullNames[p.call] ??
        outcomeFullNames[p.outcome] ??
        (p.outcome ?? p.call ?? '');
  }

  /// One at-bat as a compact card — used for "Last At-Bat" and for every row
  /// of the Previous Sequences list so Batting History looks the same
  /// everywhere:
  ///
  ///   #12 — Smith                                   G4 · 2026 · Mar 3
  ///   [1 FB Called Strike] [2 CH Ball] [3 FB Foul Ball] [4 CV BIP]
  ///   STRIKEOUT (SWINGING)                                    4 pitches
  ///
  /// The sequence wraps onto as many lines as the width needs (no horizontal
  /// overflow on phones), the result is the largest/boldest line, and pitch
  /// type text keeps its existing pitch-type colors.
  Widget _atBatCard(AtBatSequence ab, int jersey) {
    final name = context.read<AppSession>().batterNames[jersey];
    final batter = (name != null && name.isNotEmpty) ? '#$jersey — $name' : '#$jersey';
    final result = ab.finalOutcome != null
        ? (outcomeFullNames[ab.finalOutcome] ?? ab.finalOutcome!.toUpperCase()).toUpperCase()
        : 'IN PROGRESS';
    final n = ab.pitches.length;

    Widget pitchChip(int i) {
      final p = ab.pitches[i];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.colBorder),
        ),
        child: StatHoldInfo(
          title: 'Previous sequence pitch',
          description: composeHoldInfo(
            what: 'One pitch from an earlier plate appearance against this batter: its order, pitch type and result.',
            colorGuide: pitchTypeColorGuide([p.pitchType ?? 'other']),
          ),
          child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '${i + 1}  ',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.colMuted)),
            TextSpan(
                text: _pitchTypeLabel(p.pitchType),
                style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.pitchColor(p.pitchType))),
            TextSpan(
                text: '  ${_pitchResultShort(p)}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
          ]),
          style: const TextStyle(fontSize: 11.5),
        ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: AppColors.brandOrange, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(batter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'G${ab.gameNumber} · ${ab.season} · ${DateFormat('MMM d').format(ab.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.colMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (var i = 0; i < n; i++) pitchChip(i)],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(result,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.3, color: AppColors.ink)),
              ),
              const SizedBox(width: 8),
              Text('$n pitch${n == 1 ? "" : "es"}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _batterTendenciesBlock(BatterHistory history) {
    final t = history.tendencies;
    if (!t.hasData) {
      return const Text('Not enough data yet.', style: TextStyle(fontSize: 12, color: AppColors.colMuted));
    }

    // Whole-percent display ("32%") and baseball-style BAA (".250");
    // "N/A" when there isn't a denominator yet.
    String pct(double? v) => v == null ? 'N/A' : '${v.round()}%';

    Widget pitchStat(String label, String value) => RichText(
          text: TextSpan(
            children: [
              TextSpan(text: '$label ', style: const TextStyle(fontSize: 10.5, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
              TextSpan(
                  text: value,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: AppColors.ink)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 14, runSpacing: 4, children: [
          _tendencyStat('AB', '${t.totalAtBats}'),
          _tendencyStat('Pitches', '${t.totalPitches}'),
          _tendencyStat('K', '${t.strikeouts}'),
          _tendencyStat('BB', '${t.walks}'),
          _tendencyStat('Fouls', '${t.foulBalls}'),
          _tendencyStat('BIP', '${t.ballsInPlay}'),
        ]),
        // One block per pitch type, all three stats computed from this
        // batter's pitches only (see BatterHistoryService).
        for (final ps in t.byPitchType) ...[
          const SizedBox(height: 8),
          StatHoldInfo(
            title: _pitchTypeLabel(ps.pitchType),
            description: composeHoldInfo(
              what: 'This block shows how this batter has done against one pitch type (usage %, whiff %, BAA and more), using only the pitches thrown to this batter.',
              colorGuide: pitchTypeColorGuide([ps.pitchType]),
            ),
            child: Text(
            '${_pitchTypeLabel(ps.pitchType)}'
            '${ps.usagePct != null ? "  ${ps.usagePct!.round()}%" : ""}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.pitchColor(ps.pitchType)),
            ),
          ),
          const SizedBox(height: 2),
          Wrap(spacing: 14, runSpacing: 2, children: [
            pitchStat('Whiff', pct(ps.whiffPct)),
            pitchStat('BAA', _fmtRate(ps.baa)),
            pitchStat('Strike', pct(ps.strikePct)),
          ]),
        ],
      ],
    );
  }

  Widget _tendencyStat(String label, String value) => RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$value ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink)),
            TextSpan(text: label, style: const TextStyle(fontSize: 10.5, color: AppColors.colMuted, fontStyle: FontStyle.italic)),
          ],
        ),
      );

  /// Compact colored-dot legend for the spray chart — one entry per
  /// outcome with its count, instead of an itemized per-point list.
  Widget _sprayOutcomeLegend(List<PitchEvent> sprayPoints) {
    final counts = <String, int>{};
    for (final p in sprayPoints) {
      final key = p.outcome ?? 'other';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: entries.map((e) {
        return StatHoldInfo(
          title: outcomeFullNames[e.key] ?? e.key,
          description: composeHoldInfo(
            what: 'Each dot on the spray chart is one ball in play; the number in brackets is how many of this result there are.',
            colorGuide: 'Dot color = the result (a label, not a good/bad grade):\n${sprayFillColorGuide()}',
          ),
          child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.sprayColor(e.key), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('${outcomeFullNames[e.key] ?? e.key} (${e.value})',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.colMuted)),
          ],
          ),
        );
      }).toList(),
    );
  }

  /// "Every completed at-bat BEFORE Last At-Bat against this Team + Jersey"
  /// view — opened from the Previous Sequences button. Each at-bat is a
  /// compact, collapsed-by-default row ("Game 12 · Ground Out · 4
  /// pitches") that expands to show its full pitch sequence, so a long
  /// history never has to render as a wall of giant cards.
  Future<void> _openPreviousSequences(BatterHistory history) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Previous Sequences — ${history.opponent} #${history.jersey}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: history.previousSequences.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No earlier at-bats yet — the most recent completed one is shown as Last At-Bat.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppColors.colMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          itemCount: history.previousSequences.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _atBatCard(history.previousSequences[i], history.jersey),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
