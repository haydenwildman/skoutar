import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'stats_service.dart';

/// Builds the "What This Means" / "Color Guide" text shown by the
/// press-and-hold popup ([StatHoldInfo]).
///
/// NOTHING here defines a color rule. Every cutoff is read from the code that
/// actually colors the screen: tier ladders are probed straight from
/// [perfHex] (so inclusive/exclusive edges are exact), and the
/// relationship-based colors read the constants in stats_service.dart that the
/// color functions themselves use.
///
/// Text format understood by the popup:
///   `## Heading`            bold section heading
///   `{c:AARRGGBB} text`     line with a color swatch
///   anything else           plain text

const List<Color> _tierColors = [
  AppColors.perfPoor,
  AppColors.perfBelowAvg,
  AppColors.perfAverage,
  AppColors.perfGood,
  AppColors.perfExcellent,
];
const List<String> _tierNames = ['Red', 'Orange', 'Yellow', 'Light green', 'Dark green'];
const List<String> _tierLabels = ['Poor', 'Below average', 'Average', 'Good', 'Excellent'];
const Color noDataGray = Color(0xFFE5E7EB);

/// A line with a color swatch in front of it.
String swatchLine(Color c, String text) =>
    '{c:${c.value.toRadixString(16).padLeft(8, '0')}} $text';

/// Plain-English name of a perf-palette color (for "this box is ..." lines).
String colorNameOf(Color c) {
  final i = _tierColors.indexOf(c);
  if (i >= 0) return _tierNames[i];
  if (c == AppColors.tint) return 'cream (no color)';
  if (c == noDataGray) return 'gray (no data)';
  return 'this color';
}

/// Joins a stat's meaning and its color guide under the standard headings.
/// With no color guide the meaning is returned untouched.
String composeHoldInfo({String? what, String? colorGuide}) {
  if (colorGuide == null || colorGuide.trim().isEmpty) return what ?? '';
  final b = StringBuffer();
  if (what != null && what.trim().isNotEmpty) {
    b.write('## What This Means\n$what\n\n');
  }
  b.write('## Color Guide\n$colorGuide');
  return b.toString();
}

const Set<String> _avgStyleStats = {
  'AVG', 'OBP_allowed', 'SLG', 'batter_AVG', 'batter_OBP', 'batter_SLG', 'batter_OPS', 'batter_BABIP',
};

String _fmt(String stat, double v) {
  if (_avgStyleStats.contains(stat)) {
    final t = v.toStringAsFixed(3);
    return t.startsWith('0.') ? t.substring(1) : t;
  }
  if (stat == 'ERA' || stat == 'WHIP') return v.toStringAsFixed(2);
  if (stat == 'PPA') return v.toStringAsFixed(1);
  if (stat == 'seq_score') return v.toStringAsFixed(0);
  return '${v.toStringAsFixed(0)}%';
}

String _rangeText(String stat, List<double> c, List<bool> up, int i) {
  String f(int k) => _fmt(stat, c[k]);
  if (i == 0) return up[0] ? 'below ${f(0)}' : '${f(0)} or lower';
  if (i == 4) return up[3] ? '${f(3)} or higher' : 'above ${f(3)}';
  final a = i - 1;
  final b = i;
  if (up[a] && up[b]) return '${f(a)} to just under ${f(b)}';
  if (!up[a] && !up[b]) return 'over ${f(a)} up to ${f(b)}';
  final lo = up[a] ? '${f(a)} or higher' : 'above ${f(a)}';
  final hi = up[b] ? 'below ${f(b)}' : '${f(b)} or lower';
  return '$lo and $hi';
}

/// One swatch line per tier, best color first, with the exact cutoffs
/// [perfHex] uses for [stat]. Empty if [stat] has no tier ladder.
List<String> statTierLines(String stat) {
  final b = statTierBounds(stat);
  if (b == null) return const [];
  final cuts = [b[1], b[2], b[3], b[4]]..sort();
  int tierAt(double v) => perfTierIndexOf(perfHex(stat, v));
  const eps = 1e-6;
  // up[i]: a value exactly on cuts[i] is graded like the values just above it.
  final up = [for (final c in cuts) tierAt(c) == tierAt(c + eps)];
  final reps = <double>[
    cuts[0] - 1,
    (cuts[0] + cuts[1]) / 2,
    (cuts[1] + cuts[2]) / 2,
    (cuts[2] + cuts[3]) / 2,
    cuts[3] + 1,
  ];
  final byTier = <int, String>{};
  for (var i = 0; i < 5; i++) {
    byTier[tierAt(reps[i])] = _rangeText(stat, cuts, up, i);
  }
  return [
    for (var t = 4; t >= 0; t--)
      if (byTier[t] != null)
        swatchLine(_tierColors[t], '${_tierNames[t]} (${_tierLabels[t]}): ${byTier[t]}'),
  ];
}

/// Color guide for a stat graded by [perfHex]. [bar] adds how the progress bar
/// maps onto the cutoffs; [note] adds one clarifying line (e.g. which scale a
/// stat borrows).
String statColorGuide(String stat, {bool bar = false, String? note}) {
  final lines = statTierLines(stat);
  if (lines.isEmpty) return '';
  final b = StringBuffer();
  b.writeln(statLowerIsBetter(stat) ? 'Lower values are better.' : 'Higher values are better.');
  if (note != null) b.writeln(note);
  for (final l in lines) {
    b.writeln(l);
  }
  b.writeln(swatchLine(noDataGray, 'Gray: no data yet (N/A)'));
  if (bar) {
    final max = statScaleMaxFor(stat);
    b.write('The dot marks the real value on a 0 to ${max == null ? '' : _fmt(stat, max)} scale; '
        'the band behind it is split at these same cutoffs. The solid fill starts at the red end '
        '(${statLowerIsBetter(stat) ? 'right' : 'left'} side) and runs to the dot.');
  }
  return b.toString().trimRight();
}

String _pctRamp(double? v) => v == null ? 'n/a' : '${v.toStringAsFixed(0)}%';

/// Swing % — colored by Whiff %, scaled by how often hitters swing.
String swingPctColorGuide() {
  final dg = _pctRamp(rampRateToReach(4, 4, swingRampLow, swingRampHigh));
  final lg = _pctRamp(rampRateToReach(3, 3, swingRampLow, swingRampHigh));
  final or = _pctRamp(rampRateToReach(1, 1, swingRampLow, swingRampHigh));
  final rd = _pctRamp(rampRateToReach(0, 0, swingRampLow, swingRampHigh));
  return 'Swing % is not good or bad by itself. The color grades the result of those swings '
      '(Whiff %), and Swing % decides how strongly that grade shows.\n'
      'Step 1 - Whiff % grade:\n'
      '${statTierLines('whiff_pct').join('\n')}\n'
      'Step 2 - Swing % strength: at ${swingRampLow.toStringAsFixed(0)}% or lower the box stays yellow '
      'whatever the Whiff % is; at ${swingRampHigh.toStringAsFixed(0)}% or higher it shows the full '
      'Whiff % color; in between it blends toward yellow.\n'
      'Dark green or red appears from about $dg or $rd Swing %; light green or orange from about $lg or $or.\n'
      '${swatchLine(noDataGray, 'Gray: no swing/whiff data yet')}';
}

List<String> _ladderLines(List<double> cuts, String Function(double) f) {
  return [
    swatchLine(AppColors.perfExcellent, 'Dark green: ${f(cuts[3])} or higher'),
    swatchLine(AppColors.perfGood, 'Light green: ${f(cuts[2])} to just under ${f(cuts[3])}'),
    swatchLine(AppColors.perfAverage, 'Yellow: ${f(cuts[1])} to just under ${f(cuts[2])}'),
    swatchLine(AppColors.perfBelowAvg, 'Orange: ${f(cuts[0])} to just under ${f(cuts[1])}'),
    swatchLine(AppColors.perfPoor, 'Red: below ${f(cuts[0])}'),
  ];
}

String _p(double v) => '${v.toStringAsFixed(0)}%';

/// Take % — colored by how many takes were called strikes.
String takePctColorGuide() {
  final dg = _pctRamp(rampRateToReach(4, 4, takeRampLow, takeRampHigh));
  final rd = _pctRamp(rampRateToReach(0, 0, takeRampLow, takeRampHigh));
  return 'Take % is not good or bad by itself. The color grades what the takes were: '
      'called strikes (good) or balls (bad). Take % decides how strongly that grade shows.\n'
      'Step 1 - share of takes that were called strikes (called strikes ÷ takes):\n'
      '${_ladderLines(takeStrikeCuts, _p).join('\n')}\n'
      'Step 2 - Take % strength: at ${_p(takeRampLow)} or lower the box stays yellow; at '
      '${_p(takeRampHigh)} or higher it shows the full color above; in between it blends toward yellow '
      '(dark green or red from about $dg / $rd Take %).\n'
      '${swatchLine(noDataGray, 'Gray: no takes yet')}';
}

/// Foul % — a plain ladder, high is red.
String foulPctColorGuide() {
  return 'Higher Foul % is worse: hitters are making contact without putting the ball in play.\n'
      '${swatchLine(AppColors.perfPoor, 'Red: ${_p(foulCuts[2])} or higher')}\n'
      '${swatchLine(AppColors.perfBelowAvg, 'Orange: ${_p(foulCuts[1])} to just under ${_p(foulCuts[2])}')}\n'
      '${swatchLine(AppColors.perfAverage, 'Yellow: ${_p(foulCuts[0])} to just under ${_p(foulCuts[1])}')}\n'
      '${swatchLine(AppColors.tint, 'Cream (no color): below ${_p(foulCuts[0])}')}\n'
      '${swatchLine(noDataGray, 'Gray: no swings yet')}';
}

/// In Play % — colored by the out rate on those balls in play.
String inPlayPctColorGuide() {
  final dg = _pctRamp(rampRateToReach(4, 4, inPlayRampLow, inPlayRampHigh));
  final rd = _pctRamp(rampRateToReach(0, 0, inPlayRampLow, inPlayRampHigh));
  return 'In Play % is not good or bad by itself. The color grades what happened on the balls in play: '
      'outs (good) or hits (bad). In Play % decides how strongly that grade shows.\n'
      'Step 1 - out rate on balls in play (outs ÷ balls in play with a result):\n'
      '${_ladderLines(bipOutCuts, _p).join('\n')}\n'
      'Step 2 - In Play % strength: at ${_p(inPlayRampLow)} or lower the box stays yellow; at '
      '${_p(inPlayRampHigh)} or higher it shows the full color above; in between it blends toward yellow '
      '(dark green or red from about $dg / $rd In Play %).\n'
      '${swatchLine(noDataGray, 'Gray: no balls in play yet')}';
}

/// Swatch lines naming each pitch type's own color.
String pitchColorLines(Iterable<String> pitchTypes) {
  return [
    for (final pt in pitchTypes) swatchLine(AppColors.pitchColor(pt), pt.toUpperCase()),
  ].join('\n');
}

/// "Color shows which pitch" guide for charts/bars colored by pitch type.
String pitchTypeColorGuide(Iterable<String> pitchTypes) {
  return 'Each color is a pitch type, not a good/bad grade. The same pitch keeps the same color '
      'on every screen, so there are no performance cutoffs here.\n'
      '${pitchColorLines(pitchTypes)}';
}

/// Spray chart fill colors (what happened on the ball in play).
String sprayFillColorGuide() {
  return [
    swatchLine(AppColors.sprayColor('1b'), 'Green: Single'),
    swatchLine(AppColors.sprayColor('2b'), 'Blue: Double'),
    swatchLine(AppColors.sprayColor('3b'), 'Purple: Triple'),
    swatchLine(AppColors.sprayColor('hr'), 'Orange: Home run'),
    swatchLine(AppColors.sprayColor('e'), 'Yellow: Error'),
    swatchLine(AppColors.sprayColor('fc'), "Gray: Fielder's choice"),
    swatchLine(AppColors.sprayColor('out'), 'Red: Out (ground out, fly out, line out, double play)'),
  ].join('\n');
}

/// Spray chart rings (which pitch was hit). [pitchTypes] is the list of pitch
/// types actually present in the data being shown.
String sprayRingColorGuide(Iterable<String> pitchTypes) {
  return '${pitchColorLines(pitchTypes)}\n'
      'Custom pitches use the color chosen for them.';
}
