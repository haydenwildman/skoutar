// Bullpen Game Mode: Strike Streak, Target Accuracy and Pitch Sequencing.
//
// Self-contained and not saved anywhere: no difficulty levels, no history,
// no database writes. Every pitch the person can choose here is one they
// created on Game Input (AppSession.customPitchTypes).
//
// Every target is 8.5 x 12 inches (half the plate width, half the zone height).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import 'bullpen_models.dart';
import 'entry_widgets.dart';
import 'widgets.dart';

/// Target size in zone units: 0.5 x 0.5 = 8.5 in wide x 12 in tall.
const double _kTargetW = 0.5;
const double _kTargetH = 0.5;

/// The 9 target locations, top-left to bottom-right (catcher's view).
/// Centers are chosen so the whole 8.5 x 12 target stays inside the zone.
const List<String> _cellNames = [
  'High Left', 'High Middle', 'High Right',
  'Middle Left', 'Middle', 'Middle Right',
  'Low Left', 'Low Middle', 'Low Right',
];

ZoneTarget _targetForCell(int cell) {
  final col = cell % 3;
  final row = cell ~/ 3;
  final x = 0.25 + col * 0.25; // 0.25, 0.50, 0.75
  final y = 0.75 - row * 0.25; // top row = highest
  return ZoneTarget(x, y, _kTargetW, _kTargetH);
}

class _Throw {
  final double x, y;
  final bool hit;
  const _Throw(this.x, this.y, this.hit);
}

class GameModeView extends StatefulWidget {
  const GameModeView({super.key});

  @override
  State<GameModeView> createState() => _GameModeViewState();
}

class _GameModeViewState extends State<GameModeView> {
  // ── setup ──
  ChallengeMode _mode = ChallengeMode.streak;
  String? _pitch;
  final _goalCtrl = TextEditingController(text: '5'); // streak: strikes in a row
  final _countCtrl = TextEditingController(text: '10'); // accuracy: pitches
  int _startCell = 4;
  int _numLocations = 4;
  int _cell = 4; // accuracy / sequence: the one target location
  final List<String> _seq = [];

  // ── play ──
  bool _playing = false;
  bool _finished = false;
  bool _success = false;
  String _endText = '';
  List<int> _route = []; // streak: the locations the target moves through
  int _routeIdx = 0;
  int _step = 0; // pitches thrown
  int _score = 0;
  int _goal = 0;
  String _currentPitch = '';
  List<String> _playSeq = [];
  final List<_Throw> _log = [];
  double? _px, _py;
  String? _flash;

  @override
  void dispose() {
    _goalCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  int _intOf(TextEditingController c, int fallback, {int min = 1, int max = 200}) {
    final v = int.tryParse(c.text.trim()) ?? fallback;
    return v.clamp(min, max);
  }

  String _pitchFor(List<String> types) =>
      (_pitch != null && types.contains(_pitch)) ? _pitch! : types.first;

  // ── start / play logic ────────────────────────────────────────

  void _start(List<String> types) {
    if (types.isEmpty) return;
    final rng = math.Random();
    setState(() {
      _playing = true;
      _finished = false;
      _success = false;
      _endText = '';
      _step = 0;
      _score = 0;
      _log.clear();
      _px = _py = null;
      _flash = null;
      switch (_mode) {
        case ChallengeMode.streak:
          _goal = _intOf(_goalCtrl, 5);
          _currentPitch = _pitchFor(types);
          // Start location first, then (n - 1) other distinct locations.
          final others = [for (var i = 0; i < 9; i++) if (i != _startCell) i]..shuffle(rng);
          _route = [_startCell, ...others.take(_numLocations - 1)];
          _routeIdx = 0;
          _playSeq = [];
          break;
        case ChallengeMode.accuracy:
          _goal = _intOf(_countCtrl, 10);
          _currentPitch = _pitchFor(types);
          _route = [_cell];
          _routeIdx = 0;
          _playSeq = [];
          break;
        case ChallengeMode.sequence:
          _playSeq = List<String>.from(_seq);
          _goal = _playSeq.length;
          _currentPitch = _playSeq.first;
          _route = [_cell];
          _routeIdx = 0;
          break;
      }
    });
  }

  int get _currentCell => _route[_routeIdx];

  void _submit() {
    if (!_playing || _finished || _px == null) return;
    final target = _targetForCell(_currentCell);
    final hit = target.contains(_px!, _py!);
    setState(() {
      _log.add(_Throw(_px!, _py!, hit));
      _step++;
      if (hit) _score++;
      _flash = hit ? 'Hit!' : 'Missed';
      _px = _py = null;

      switch (_mode) {
        case ChallengeMode.streak:
          if (!hit) {
            _finish(false, 'Missed the target. The streak ended at $_score.');
          } else if (_score >= _goal) {
            _finish(true, 'You threw $_goal in a row.');
          } else {
            _routeIdx = (_routeIdx + 1) % _route.length; // target moves
          }
          break;
        case ChallengeMode.accuracy:
          if (_step >= _goal) {
            final pct = (_score / _goal * 100).round();
            _finish(true, 'You hit $_score of $_goal ($pct%).');
          }
          break;
        case ChallengeMode.sequence:
          if (!hit) {
            _finish(false, 'Missed the target. A miss ends the sequence.');
          } else if (_step >= _goal) {
            _finish(true, 'You hit every pitch in the sequence.');
          } else {
            _currentPitch = _playSeq[_step];
          }
          break;
      }
    });
  }

  void _finish(bool success, String text) {
    _finished = true;
    _success = success;
    _endText = text;
  }

  void _endAttempt() => setState(() {
        _playing = false;
        _finished = false;
      });

  // ── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppSession>();
    // Only the pitcher's own pitches: there are no presets.
    final types = List<String>.from(app.customPitchTypes);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _playing ? _playCard(app) : _setupCard(app, types),
    ]);
  }

  String _ruleText() {
    final size = '${(_kTargetW * ZoneGeo.plateWidthIn).toStringAsFixed(1)} × '
        '${(_kTargetH * ZoneGeo.zoneHeightIn).toStringAsFixed(1)} in';
    switch (_mode) {
      case ChallengeMode.streak:
        return 'Hit the $size target ${_intOf(_goalCtrl, 5)} times in a row. After every hit the target moves to the '
            'next of $_numLocations locations, beginning at ${_cellNames[_startCell]}. One miss ends the attempt.';
      case ChallengeMode.accuracy:
        return 'Throw ${_intOf(_countCtrl, 10)} pitches at one $size target at ${_cellNames[_cell]}. '
            'Your score is how many you hit.';
      case ChallengeMode.sequence:
        return 'Hit a $size target at ${_cellNames[_cell]} with each pitch in your sequence, in order. '
            'Any miss ends the attempt.';
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _numberField(TextEditingController c, String label) => SizedBox(
        width: 200,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _cellGrid(int selected, ValueChanged<int> onTap) => Center(
        child: SizedBox(
          width: 210,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.25,
            children: [
              for (var i = 0; i < 9; i++)
                Semantics(
                  button: true,
                  selected: selected == i,
                  label: _cellNames[i],
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected == i ? AppColors.brandOrangeDeep : Colors.white,
                        border: Border.all(
                            color: selected == i ? AppColors.brandOrangeDeep : AppColors.colBorder, width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_cellNames[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: selected == i ? Colors.white : AppColors.ink)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _setupCard(AppSession app, List<String> types) {
    final noPitches = types.isEmpty;
    final canStart = !noPitches && (_mode != ChallengeMode.sequence || _seq.isNotEmpty);
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Pitching Challenges', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          SegmentedTabs<ChallengeMode>(
            values: ChallengeMode.values,
            value: _mode,
            labelOf: (m) => m.label,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 10),
          Text(_ruleText(), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          if (noPitches) ...[
            const Text(
              'You have no pitch types yet. Add them on Game Input (Add New Pitch), then come back.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.perfPoor),
            ),
            const SizedBox(height: 12),
          ] else ...[
            // ── Strike Streak ──
            if (_mode == ChallengeMode.streak) ...[
              _label('Consecutive strikes to throw'),
              Align(alignment: Alignment.centerLeft, child: _numberField(_goalCtrl, 'Strikes in a row')),
              const SizedBox(height: 12),
              _label('Pitch'),
              PitchTypeChips(
                  types: types,
                  selected: _pitchFor(types),
                  labelOf: app.pitchTypeLabel,
                  onSelected: (t) => setState(() => _pitch = t)),
              const SizedBox(height: 12),
              _label('Starting location'),
              _cellGrid(_startCell, (i) => setState(() => _startCell = i)),
              const SizedBox(height: 12),
              _label('Number of locations'),
              Row(children: [
                IconButton(
                  onPressed: _numLocations > 1 ? () => setState(() => _numLocations--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_numLocations', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                IconButton(
                  onPressed: _numLocations < 9 ? () => setState(() => _numLocations++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('The target moves between this many different spots.',
                      style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
                ),
              ]),
            ],
            // ── Target Accuracy ──
            if (_mode == ChallengeMode.accuracy) ...[
              _label('Pitches in this game'),
              Align(alignment: Alignment.centerLeft, child: _numberField(_countCtrl, 'Number of pitches')),
              const SizedBox(height: 12),
              _label('Pitch'),
              PitchTypeChips(
                  types: types,
                  selected: _pitchFor(types),
                  labelOf: app.pitchTypeLabel,
                  onSelected: (t) => setState(() => _pitch = t)),
              const SizedBox(height: 12),
              _label('Target location'),
              _cellGrid(_cell, (i) => setState(() => _cell = i)),
            ],
            // ── Pitch Sequencing ──
            if (_mode == ChallengeMode.sequence) ...[
              _label('Your sequence (${_seq.length} pitch${_seq.length == 1 ? '' : 'es'})'),
              if (_seq.isEmpty)
                const Text('Tap a pitch below to add it. Add as many as you want.',
                    style: TextStyle(fontSize: 12, color: AppColors.colMuted)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < _seq.length; i++)
                  InputChip(
                    label: Text('${i + 1}. ${app.pitchTypeLabel(_seq[i])}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    side: BorderSide(color: AppColors.pitchColor(_seq[i]), width: 2),
                    onDeleted: () => setState(() => _seq.removeAt(i)),
                    deleteButtonTooltipMessage: '', // no hover tooltip
                  ),
              ]),
              const SizedBox(height: 10),
              _label('Add a pitch'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in types)
                  ActionChip(
                    label: Text(app.pitchTypeLabel(t), style: const TextStyle(fontWeight: FontWeight.w700)),
                    avatar: CircleAvatar(backgroundColor: AppColors.pitchColor(t), radius: 6),
                    onPressed: () => setState(() => _seq.add(t)),
                  ),
              ]),
              if (_seq.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => setState(_seq.clear), child: const Text('Clear sequence')),
                ),
              const SizedBox(height: 12),
              _label('Target location'),
              _cellGrid(_cell, (i) => setState(() => _cell = i)),
            ],
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandOrangeDeep,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: canStart ? () => _start(types) : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Challenge'),
          ),
        ]),
      ),
    );
  }

  // ── play ──────────────────────────────────────────────────────

  Widget _progress(AppSession app) {
    switch (_mode) {
      case ChallengeMode.streak:
        return StatCardGrid(children: [
          BigStatCard(label: 'Current streak', value: '$_score', note: 'goal $_goal'),
          BigStatCard(label: 'Target', value: _cellNames[_currentCell]),
          BigStatCard(label: 'Pitch', value: app.pitchTypeLabel(_currentPitch)),
        ]);
      case ChallengeMode.accuracy:
        return StatCardGrid(children: [
          BigStatCard(label: 'Hits', value: '$_score', note: 'of $_step thrown'),
          BigStatCard(label: 'Pitches left', value: '${_goal - _step}'),
          BigStatCard(label: 'Target', value: _cellNames[_currentCell]),
        ]);
      case ChallengeMode.sequence:
        return Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < _playSeq.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: i < _score
                    ? AppColors.perfGood
                    : (i == _step && !_finished ? AppColors.brandPeach : Colors.white),
                border: Border.all(
                    color: i == _step && !_finished ? AppColors.brandOrangeDeep : AppColors.colBorder, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${i + 1}. ${app.pitchTypeLabel(_playSeq[i])}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
        ]);
    }
  }

  Widget _playCard(AppSession app) {
    final done = _finished;
    final target = _targetForCell(_currentCell);
    final marks = <ZoneMarker>[
      for (final l in _log)
        ZoneMarker(l.x, l.y, l.hit ? AppColors.perfExcellent : AppColors.perfPoor, radius: 6),
      if (_px != null) ZoneMarker(_px!, _py!, AppColors.ink, radius: 8, ring: true),
    ];
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(_mode.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            if (!done) TextButton(onPressed: _endAttempt, child: const Text('End Attempt')),
          ]),
          const SizedBox(height: 6),
          _progress(app),
          const SizedBox(height: 10),
          if (!done) ...[
            Text(
              _mode == ChallengeMode.sequence
                  ? 'Throw ${app.pitchTypeLabel(_currentPitch)} (pitch ${_step + 1} of $_goal) at the orange target, then tap where it landed.'
                  : 'Throw ${app.pitchTypeLabel(_currentPitch)} at the orange target (${_cellNames[_currentCell]}), then tap where it landed.',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
          ],
          StrikeZone(
            semanticsLabel: 'Mark landing spot',
            rects: [ZoneRect(target, AppColors.brandOrangeDeep)],
            markers: marks,
            onPick: done
                ? null
                : (x, y) => setState(() {
                      _px = x;
                      _py = y;
                    }),
          ),
          const SizedBox(height: 8),
          if (!done)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandOrangeDeep,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _px == null ? null : _submit,
              icon: const Icon(Icons.check),
              label: const Text('Submit Pitch'),
            ),
          if (_flash != null && !done)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Last pitch: $_flash',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          if (done)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _success ? AppColors.perfExcellent : AppColors.perfPoor, width: 2),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _mode == ChallengeMode.accuracy
                      ? 'Game complete'
                      : (_success ? 'Challenge passed' : 'Attempt failed'),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: _success ? AppColors.perfExcellent : AppColors.perfPoor),
                ),
                const SizedBox(height: 2),
                Text('$_endText $_step pitch${_step == 1 ? '' : 'es'} thrown.'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandOrangeDeep, foregroundColor: Colors.white),
                      onPressed: () => _start(List<String>.from(app.customPitchTypes)),
                      child: const Text('Try Again'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _endAttempt,
                      child: const Text('Change Challenge'),
                    ),
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}
