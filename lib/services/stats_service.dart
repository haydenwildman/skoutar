import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/pitch_event.dart';
import '../theme/app_theme.dart';
import 'sequence_scoring.dart';

/// ══════════════════════════════════════════════════════════════
/// STATS SERVICE
///
/// This file is a line-by-line port of the calculation logic that lived
/// in the R Shiny app's `process_data()`, `perf_hex()`, `ov_stats`,
/// `cnt_data`, `pitch_sum`, `game_log_data`, and `seq_data` reactives.
///
/// IMPORTANT: per the project brief, these formulas are preserved exactly
/// (same thresholds, same numerator/denominator definitions) rather than
/// simplified. Do not "clean up" the threshold ladders below — they are
/// intentionally piecewise to match the original color-coding behavior.
/// ══════════════════════════════════════════════════════════════

/// Performance-tier color lookup — exact port of R's `perf_hex()`.
/// [stat] must be one of: ERA, WHIP, K_pct, BB_pct, whiff_pct, f_strike,
/// kbb_pct, AVG, OBP_allowed, SLG, PPA, usage_predictability, seq_score,
/// ball_pct, chase_pct, contact_pct, gb_pct, fb_pct, ld_pct.
Color perfHex(String stat, double? value) {
  if (value == null || value.isNaN) return const Color(0xFFE5E7EB);
  final v = value;
  switch (stat) {
    case 'ERA':
      if (v < 2.0) return AppColors.perfExcellent;
      if (v < 3.5) return AppColors.perfGood;
      if (v < 5.0) return AppColors.perfAverage;
      if (v < 6.5) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'WHIP':
      if (v < 1.0) return AppColors.perfExcellent;
      if (v < 1.2) return AppColors.perfGood;
      if (v < 1.4) return AppColors.perfAverage;
      if (v < 1.6) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'K_pct':
      if (v > 30) return AppColors.perfExcellent;
      if (v > 22) return AppColors.perfGood;
      if (v > 15) return AppColors.perfAverage;
      if (v > 10) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'BB_pct':
      if (v < 5) return AppColors.perfExcellent;
      if (v < 8) return AppColors.perfGood;
      if (v < 12) return AppColors.perfAverage;
      if (v < 16) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'whiff_pct':
      if (v > 35) return AppColors.perfExcellent;
      if (v > 27) return AppColors.perfGood;
      if (v > 18) return AppColors.perfAverage;
      if (v > 10) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'f_strike':
      if (v > 68) return AppColors.perfExcellent;
      if (v > 60) return AppColors.perfGood;
      if (v > 50) return AppColors.perfAverage;
      if (v > 42) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'kbb_pct':
      if (v > 20) return AppColors.perfExcellent;
      if (v > 14) return AppColors.perfGood;
      if (v > 8) return AppColors.perfAverage;
      if (v > 2) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'AVG':
      if (v < .200) return AppColors.perfExcellent;
      if (v < .250) return AppColors.perfGood;
      if (v < .290) return AppColors.perfAverage;
      if (v < .330) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'OBP_allowed':
      if (v < .270) return AppColors.perfExcellent;
      if (v < .320) return AppColors.perfGood;
      if (v < .370) return AppColors.perfAverage;
      if (v < .420) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'SLG':
      if (v < .300) return AppColors.perfExcellent;
      if (v < .380) return AppColors.perfGood;
      if (v < .450) return AppColors.perfAverage;
      if (v < .520) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'PPA':
      // Pitches per plate appearance — lower is more efficient.
      if (v < 3.3) return AppColors.perfExcellent;
      if (v < 3.7) return AppColors.perfGood;
      if (v < 4.0) return AppColors.perfAverage;
      if (v < 4.3) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'usage_predictability':
      // Higher usage of a single pitch at a single count = more predictable
      // = worse. Used by the pitch-usage heat map (item 11).
      if (v >= 70) return AppColors.perfPoor;
      if (v >= 55) return AppColors.perfBelowAvg;
      if (v >= 40) return AppColors.perfAverage;
      if (v >= 25) return AppColors.perfGood;
      return AppColors.perfExcellent;
    case 'seq_score':
      // Pitch-sequencing quality score (0-100). Higher = better sequencing.
      if (v >= 75) return AppColors.perfExcellent;
      if (v >= 60) return AppColors.perfGood;
      if (v >= 45) return AppColors.perfAverage;
      if (v >= 30) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'ball_pct':
      // Ball % — lower is better (better command).
      if (v < 30) return AppColors.perfExcellent;
      if (v < 38) return AppColors.perfGood;
      if (v < 45) return AppColors.perfAverage;
      if (v < 52) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'chase_pct':
      // Chase % — higher is better (hitters expanding the zone).
      if (v > 35) return AppColors.perfExcellent;
      if (v > 27) return AppColors.perfGood;
      if (v > 18) return AppColors.perfAverage;
      if (v > 10) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'contact_pct':
      // Contact % — lower is better (harder pitch to hit).
      if (v < 60) return AppColors.perfExcellent;
      if (v < 70) return AppColors.perfGood;
      if (v < 78) return AppColors.perfAverage;
      if (v < 85) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'gb_pct':
      // Ground Ball % — higher is better (weak, low-damage contact).
      if (v > 55) return AppColors.perfExcellent;
      if (v > 45) return AppColors.perfGood;
      if (v > 38) return AppColors.perfAverage;
      if (v > 30) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'fb_pct':
      // Fly Ball % — lower is better (less HR/extra-base risk).
      if (v < 25) return AppColors.perfExcellent;
      if (v < 32) return AppColors.perfGood;
      if (v < 40) return AppColors.perfAverage;
      if (v < 48) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'out_pct':
      // Out % of plate appearances (batter retired) — higher is better. It is the
      // complement of on-base rate, so the cutoffs mirror OBP_allowed
      // (.270 / .320 / .370 / .420 -> 73 / 68 / 63 / 58 % outs).
      if (v > 73) return AppColors.perfExcellent;
      if (v > 68) return AppColors.perfGood;
      if (v > 63) return AppColors.perfAverage;
      if (v > 58) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;
    case 'ld_pct':
      // Line Drive % — lower is better (highest-AVG batted-ball type).
      if (v < 15) return AppColors.perfExcellent;
      if (v < 20) return AppColors.perfGood;
      if (v < 25) return AppColors.perfAverage;
      if (v < 30) return AppColors.perfBelowAvg;
      return AppColors.perfPoor;

    // ── Batter History "Overall Stats" — these grade a batter's own
    // offensive numbers, but from the PITCHER's point of view (this app
    // is a pitcher's tool): a high AVG/OBP/SLG/OPS/BB%/BABIP against is
    // bad news for the pitcher (red), a high K% against is good news for
    // the pitcher (green). Same breakpoint numbers as a plain hitter-view
    // grading would use — only which tier color lands on which end is
    // flipped. Kept as separate keys rather than reusing AVG/OBP_allowed/
    // SLG/BB_pct/K_pct so the two stat sample sizes (this one batter vs.
    // the pitcher's full-season aggregate) never collide.
    case 'batter_AVG':
      if (v >= .350) return AppColors.perfPoor;
      if (v >= .300) return AppColors.perfBelowAvg;
      if (v >= .250) return AppColors.perfAverage;
      if (v >= .200) return AppColors.perfGood;
      return AppColors.perfExcellent;
    case 'batter_OBP':
      if (v >= .430) return AppColors.perfPoor;
      if (v >= .380) return AppColors.perfBelowAvg;
      if (v >= .330) return AppColors.perfAverage;
      if (v >= .280) return AppColors.perfGood;
      return AppColors.perfExcellent;
    case 'batter_SLG':
      if (v >= .550) return AppColors.perfPoor;
      if (v >= .450) return AppColors.perfBelowAvg;
      if (v >= .380) return AppColors.perfAverage;
      if (v >= .300) return AppColors.perfGood;
      return AppColors.perfExcellent;
    case 'batter_OPS':
      if (v >= .950) return AppColors.perfPoor;
      if (v >= .800) return AppColors.perfBelowAvg;
      if (v >= .700) return AppColors.perfAverage;
      if (v >= .600) return AppColors.perfGood;
      return AppColors.perfExcellent;
    case 'batter_BB_pct':
      // A higher walk rate against is worse for the pitcher (loss of
      // control / free baserunners).
      if (v >= 15) return AppColors.perfPoor;
      if (v >= 10) return AppColors.perfBelowAvg;
      if (v >= 7) return AppColors.perfAverage;
      if (v >= 4) return AppColors.perfGood;
      return AppColors.perfExcellent;
    case 'batter_K_pct':
      // A higher strikeout rate against is better for the pitcher —
      // same direction as the pitcher's own K_pct above.
      if (v <= 12) return AppColors.perfPoor;
      if (v <= 18) return AppColors.perfBelowAvg;
      if (v <= 24) return AppColors.perfAverage;
      if (v <= 30) return AppColors.perfGood;
      return AppColors.perfExcellent;
    case 'batter_BABIP':
      if (v >= .360) return AppColors.perfPoor;
      if (v >= .320) return AppColors.perfBelowAvg;
      if (v >= .290) return AppColors.perfAverage;
      if (v >= .260) return AppColors.perfGood;
      return AppColors.perfExcellent;
    default:
      return const Color(0xFFE5E7EB);
  }
}

// ── Relationship-based colors for the Pitch Breakdown grid ──────────────
// Swing %, Take %, Foul % and In Play % aren't good or bad on their own: they
// depend on what happened on those swings / takes / balls in play. These
// helpers grade the *result* with the app's existing five-tier palette and
// only let a high rate reach green (or red) when the rate itself is high;
// a low rate is pulled toward the neutral middle tier because it says little.

const List<Color> _tierPalette = [
  AppColors.perfPoor,
  AppColors.perfBelowAvg,
  AppColors.perfAverage,
  AppColors.perfGood,
  AppColors.perfExcellent,
];

const Color _noDataColor = Color(0xFFE5E7EB);

/// Tier 0 (poor) .. 4 (excellent): how many of the four ascending [cuts]
/// [v] reaches.
int _ladderTier(double v, List<double> cuts) => cuts.where((c) => v >= c).length;

/// 0..1 weight: 0 at/below [lo], 1 at/above [hi].
double _rateWeight(double v, double lo, double hi) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();

/// Moves [tier] toward the middle tier by (1 - [weight]).
Color _tierColorWeighted(int tier, double weight) =>
    _tierPalette[(2 + (tier - 2) * weight).round().clamp(0, 4)];

// Cut points / ramps used by the relationship colors below. They are the exact
// numbers the color functions already used inline; they live here so the
// tap-and-hold color guides read the same values the colors are built from.
const double swingRampLow = 25, swingRampHigh = 50;
const List<double> takeStrikeCuts = [25, 35, 45, 55];
const double takeRampLow = 30, takeRampHigh = 60;
const List<double> foulCuts = [20, 28, 35]; // yellow / orange / red start
const List<double> bipOutCuts = [58, 65, 70, 75];
const double inPlayRampLow = 10, inPlayRampHigh = 22;

/// Tier index (0 = red .. 4 = dark green) of a perf-palette color, or -1.
int perfTierIndexOf(Color c) => _tierPalette.indexOf(c);

/// Lowest rate on the [lo]..[hi] ramp at which a box whose graded stat sits in
/// [tier] (0-4) already shows tier [target]; null if it never does. Uses the
/// same blending function as the colors themselves.
double? rampRateToReach(int tier, int target, double lo, double hi) {
  for (var i = 0; i <= 100; i++) {
    final w = i / 100;
    if (_tierPalette.indexOf(_tierColorWeighted(tier, w)) == target) {
      return lo + (hi - lo) * w;
    }
  }
  return null;
}

/// Swing %: judged by Whiff %. High Swing % + high Whiff % = green; high
/// Swing % + low Whiff % = orange/red; a low Swing % stays near neutral.
Color swingPctColor(double? swingPct, double? whiffPct) {
  if (swingPct == null || whiffPct == null) return _noDataColor;
  final whiffTier = _tierPalette.indexOf(perfHex('whiff_pct', whiffPct));
  return _tierColorWeighted(whiffTier, _rateWeight(swingPct, swingRampLow, swingRampHigh));
}

/// Take %: judged by how many of the takes were strikes. High Take % made of
/// called strikes = green; high Take % made of balls = orange/red; a low
/// Take % stays near neutral.
Color takePctColor(double? takePct, double? takeStrikePct) {
  if (takePct == null || takeStrikePct == null) return _noDataColor;
  final tier = _ladderTier(takeStrikePct, takeStrikeCuts);
  return _tierColorWeighted(tier, _rateWeight(takePct, takeRampLow, takeRampHigh));
}

/// Foul %: high = red (contact without putting it in play), easing off
/// through orange and yellow to no color at all as the rate drops.
Color foulPctColor(double? foulPct) {
  if (foulPct == null) return _noDataColor;
  if (foulPct >= foulCuts[2]) return AppColors.perfPoor;
  if (foulPct >= foulCuts[1]) return AppColors.perfBelowAvg;
  if (foulPct >= foulCuts[0]) return AppColors.perfAverage;
  return AppColors.tint;
}

/// In Play %: judged by the out rate on those balls in play. High In Play %
/// with mostly outs = green; high In Play % with lots of hits = orange/red;
/// a low In Play % stays near neutral.
Color inPlayPctColor(double? inPlayPct, double? bipOutPct) {
  if (inPlayPct == null || bipOutPct == null) return _noDataColor;
  final tier = _ladderTier(bipOutPct, bipOutCuts);
  return _tierColorWeighted(tier, _rateWeight(inPlayPct, inPlayRampLow, inPlayRampHigh));
}

/// Control points describing each stat's tier cut-offs (used for the bar's
/// colored bands and to infer its direction). Six numbers per
/// stat: point 0 = a worst-practical value (bottom of the Poor tier),
/// points 1-4 = the exact same tier cutoffs used in [perfHex] (the
/// Poor/BelowAvg, BelowAvg/Average, Average/Good and Good/Excellent
/// boundaries), point 5 = a best-practical value (top of the Excellent
/// tier). The list may count up or down — direction is inferred from
/// whether the first or last point is larger. Keep points 1-4 in sync
/// with the thresholds in [perfHex] if those ever change.
const Map<String, List<double>> _statProgressBounds = {
  'ERA': [9.0, 6.5, 5.0, 3.5, 2.0, 0.0],
  'WHIP': [2.2, 1.6, 1.4, 1.2, 1.0, 0.6],
  'K_pct': [0, 10, 15, 22, 30, 45],
  'BB_pct': [20, 16, 12, 8, 5, 0],
  'whiff_pct': [0, 10, 18, 27, 35, 50],
  'f_strike': [30, 42, 50, 60, 68, 80],
  'kbb_pct': [-5, 2, 8, 14, 20, 30],
  'AVG': [0.400, 0.330, 0.290, 0.250, 0.200, 0.150],
  'OBP_allowed': [0.480, 0.420, 0.370, 0.320, 0.270, 0.200],
  'SLG': [0.600, 0.520, 0.450, 0.380, 0.300, 0.200],
  'PPA': [5.0, 4.3, 4.0, 3.7, 3.3, 2.8],
  'usage_predictability': [100, 70, 55, 40, 25, 0],
  'seq_score': [0, 30, 45, 60, 75, 100],
  'ball_pct': [65, 52, 45, 38, 30, 15],
  'chase_pct': [0, 10, 18, 27, 35, 50],
  'contact_pct': [95, 85, 78, 70, 60, 45],
  'gb_pct': [15, 30, 38, 45, 55, 70],
  'fb_pct': [60, 48, 40, 32, 25, 10],
  'ld_pct': [40, 30, 25, 20, 15, 5],
  'out_pct': [40, 58, 63, 68, 73, 90],
  // Batter History "Overall Stats" — pitcher's-point-of-view direction,
  // the reverse of a plain hitter-view scale. Keep in sync with the
  // batter_* cases in perfHex above (same breakpoint numbers, flipped).
  'batter_AVG': [0.450, 0.350, 0.300, 0.250, 0.200, 0.100],
  'batter_OBP': [0.550, 0.430, 0.380, 0.330, 0.280, 0.150],
  'batter_SLG': [0.750, 0.550, 0.450, 0.380, 0.300, 0.150],
  'batter_OPS': [1.200, 0.950, 0.800, 0.700, 0.600, 0.400],
  'batter_BB_pct': [25, 15, 10, 7, 4, 0],
  'batter_K_pct': [0, 12, 18, 24, 30, 45],
  'batter_BABIP': [0.450, 0.360, 0.320, 0.290, 0.260, 0.150],
};

/// The "natural" full scale of each graded stat's progress bar: the bar runs
/// from 0 to this value. True percentages always use 0-100 (a 35% stat fills
/// 35% of the bar no matter what the current maximum happens to be); rate
/// stats use a practical ceiling (ERA 10.00+, WHIP 2.50, AVG .500 ...).
const Map<String, double> _statScaleMax = {
  'ERA': 10.0,
  'WHIP': 2.5,
  'K_pct': 100,
  'BB_pct': 100,
  'whiff_pct': 100,
  'f_strike': 100,
  'kbb_pct': 100,
  'AVG': 0.500,
  'OBP_allowed': 0.600,
  'SLG': 1.000,
  'PPA': 6.0,
  'usage_predictability': 100,
  'seq_score': 100,
  'ball_pct': 100,
  'chase_pct': 100,
  'contact_pct': 100,
  'gb_pct': 100,
  'fb_pct': 100,
  'ld_pct': 100,
  'out_pct': 100,
  'batter_AVG': 0.500,
  'batter_OBP': 0.600,
  'batter_SLG': 1.000,
  'batter_OPS': 1.500,
  'batter_BB_pct': 100,
  'batter_K_pct': 100,
  'batter_BABIP': 0.500,
};

/// True when a LOWER value is better for [stat] (ERA, WHIP, BB%, AVG against,
/// ...). Derived from the same tier table [perfHex] is built on, so the
/// direction can never disagree with the colors: the control points count
/// down for lower-is-better stats and up for higher-is-better ones.
bool statLowerIsBetter(String? stat) {
  final bounds = stat == null ? null : _statProgressBounds[stat];
  if (bounds == null) return false;
  return bounds.first > bounds.last;
}

/// Where [value] sits on [stat]'s natural 0..1 scale (value / scale max,
/// clamped). This is the *actual value's* position — it never changes with
/// whether the stat is good or bad; the tier colors behind the marker carry
/// that meaning. Returns null for stats with no scale or a missing value.
double? statValueFraction(String? stat, double? value) {
  if (stat == null || value == null || value.isNaN) return null;
  final max = _statScaleMax[stat];
  if (max == null || max <= 0) return null;
  return (value / max).clamp(0.0, 1.0).toDouble();
}

/// The five tier colors for [stat] ordered LEFT -> RIGHT along its bar.
/// Lower-is-better: green on the left, red on the right.
/// Higher-is-better: red on the left, green on the right.
List<Color> statTierColorsLeftToRight(String stat) {
  const best = [
    AppColors.perfExcellent,
    AppColors.perfGood,
    AppColors.perfAverage,
    AppColors.perfBelowAvg,
    AppColors.perfPoor,
  ];
  return statLowerIsBetter(stat) ? best : best.reversed.toList();
}

/// The four tier cut-offs as ascending 0..1 positions along the bar (the
/// exact same cut-offs [perfHex] uses), so the colored bands behind the
/// marker line up with the tier the value is actually graded in.
List<double> statTierCutoffFractions(String stat) {
  final bounds = _statProgressBounds[stat];
  final max = _statScaleMax[stat];
  if (bounds == null || max == null || max <= 0) return const [0.2, 0.4, 0.6, 0.8];
  final cuts = [for (var i = 1; i <= 4; i++) (bounds[i] / max).clamp(0.0, 1.0).toDouble()]..sort();
  return cuts;
}

/// The six control points for [stat] (see [_statProgressBounds]); null if none.
List<double>? statTierBounds(String stat) => _statProgressBounds[stat];

/// The natural full-scale maximum of [stat]'s progress bar; null if none.
double? statScaleMaxFor(String stat) => _statScaleMax[stat];

/// Whether [stat] has a progress-bar scale (all graded stats do).
bool statHasScale(String? stat) => stat != null && _statScaleMax.containsKey(stat);

/// Short "what good/bad looks like" hint for a perf-tier [stat], shown
/// under each [PerfStatBar] so a raw value can be judged against a
/// benchmark instead of read in isolation. Mirrors the tier thresholds in
/// [perfHex] exactly — keep the two in sync if thresholds ever change.
String? statScaleHint(String stat) {
  switch (stat) {
    case 'ERA':
      return 'Elite < 2.00  ·  Poor 6.50+';
    case 'WHIP':
      return 'Elite < 1.00  ·  Poor 1.60+';
    case 'K_pct':
      return 'Elite 30%+  ·  Poor ≤ 10%';
    case 'BB_pct':
      return 'Elite < 5%  ·  Poor 16%+';
    case 'whiff_pct':
      return 'Elite 35%+  ·  Poor ≤ 10%';
    case 'f_strike':
      return 'Elite 68%+  ·  Poor ≤ 42%';
    case 'kbb_pct':
      return 'Elite 20%+  ·  Poor ≤ 2%';
    case 'AVG':
      return 'Elite < .200  ·  Poor .330+';
    case 'OBP_allowed':
      return 'Elite < .270  ·  Poor .420+';
    case 'SLG':
      return 'Elite < .300  ·  Poor .520+';
    case 'PPA':
      return 'Elite < 3.3  ·  Poor 4.3+';
    case 'usage_predictability':
      return 'Elite < 25%  ·  Poor 70%+';
    case 'seq_score':
      return 'Elite 75+  ·  Poor < 30';
    case 'ball_pct':
      return 'Elite < 30%  ·  Poor 52%+';
    case 'chase_pct':
      return 'Elite 35%+  ·  Poor ≤ 10%';
    case 'contact_pct':
      return 'Elite < 60%  ·  Poor 85%+';
    case 'gb_pct':
      return 'Elite 55%+  ·  Poor ≤ 30%';
    case 'fb_pct':
      return 'Elite < 25%  ·  Poor 48%+';
    case 'ld_pct':
      return 'Elite < 15%  ·  Poor 30%+';
    case 'out_pct':
      return 'Elite 73%+  ·  Poor ≤ 58%';
    case 'batter_AVG':
      return 'Elite .350+  ·  Poor < .200';
    case 'batter_OBP':
      return 'Elite .430+  ·  Poor < .280';
    case 'batter_SLG':
      return 'Elite .550+  ·  Poor < .300';
    case 'batter_OPS':
      return 'Elite .950+  ·  Poor < .600';
    case 'batter_BB_pct':
      return 'Elite 15%+  ·  Poor < 4%';
    case 'batter_K_pct':
      return 'Elite ≤ 12%  ·  Poor 30%+';
    case 'batter_BABIP':
      return 'Elite .360+  ·  Poor < .260';
    default:
      return null;
  }
}

/// One "final" row per plate appearance (the last pitch of each PA),
/// equivalent to the R `final` dataframe.
class PAResult {
  final PitchEvent event;
  final int ab;
  final int hit;
  final int k;
  final int bb;
  final int hbp;
  final int tb;

  PAResult(this.event)
      : ab = (event.outcome == 'bb' || event.outcome == 'hbp') ? 0 : 1,
        hit = PitchEvent.hitOutcomes.contains(event.outcome) ? 1 : 0,
        k = PitchEvent.kOutcomes.contains(event.outcome) ? 1 : 0,
        bb = event.outcome == 'bb' ? 1 : 0,
        hbp = event.outcome == 'hbp' ? 1 : 0,
        tb = event.totalBases;
}

class OverviewStats {
  final String ipDisplay;
  final double? era;
  final double? whip;
  final double? avg;
  final double? slg;
  final double? ppa;
  final double? kPct;
  final double? bbPct;
  final double? kbb;
  final double? whiffPct;
  final double? fStrikePct;

  OverviewStats({
    required this.ipDisplay,
    required this.era,
    required this.whip,
    required this.avg,
    required this.slg,
    required this.ppa,
    required this.kPct,
    required this.bbPct,
    required this.kbb,
    required this.whiffPct,
    required this.fStrikePct,
  });
}

class StatsService {
  /// Filters out pickoff/throwout rows -> pure pitch events.
  static List<PitchEvent> pitchesOnly(List<PitchEvent> data) =>
      data.where((e) => e.eventType == 'pitch').toList();

  /// Real pitches only: pitch rows minus dead-ball ('dk' = no pitch thrown)
  /// rows. Used by the per-pitch-type / per-count / per-sequence analyses so a
  /// no-pitch event can never inflate a pitch bucket.
  static List<PitchEvent> _livePitches(List<PitchEvent> data) =>
      pitchesOnly(data).where((e) => e.call != 'dk').toList();

  /// Completed plate appearances, excluding dead-ball ('dk') endings, which
  /// are not an at-bat result for any pitch type.
  static List<PAResult> _finalPAsLive(List<PitchEvent> data) =>
      finalPAs(data).where((r) => r.event.outcome != 'dk').toList();

  /// The bucket a pitch belongs to: its pitch type, lower-cased so 'FB' and
  /// 'fb' can never split into two buckets; a missing type is 'other'.
  static String _bucketKey(PitchEvent e) {
    final t = (e.pitchType ?? '').toLowerCase().trim();
    return t.isEmpty ? 'other' : t;
  }

  /// Pickoff / caught-stealing / throw-out rows (each is worth 1 out),
  /// mirrors `po_rows`. 'to' is the legacy Caught Stealing event type;
  /// 'txo' is the newer, distinct Throw Out event type.
  static List<PitchEvent> pickoffRows(List<PitchEvent> data) => data
      .where((e) => e.eventType == 'po' || e.eventType == 'to' || e.eventType == 'txo')
      .toList();

  /// Final pitch of every plate appearance, mirrors R's `final` dataframe.
  static List<PAResult> finalPAs(List<PitchEvent> data) {
    final finals = data.where((e) => e.isFinalPitchOfPA);
    // group by (game, gameNumber, batter, batterNumber, paId) and take last
    final grouped = groupBy(
      finals,
      (PitchEvent e) => '${e.game}|${e.gameNumber}|${e.batter}|${e.batterNumber}|${e.paId}',
    );
    return grouped.values
        .map((list) {
          list.sort((a, b) => (a.pitchNum ?? 0).compareTo(b.pitchNum ?? 0));
          return PAResult(list.last);
        })
        .toList();
  }

  /// Outs recorded from balls in play / strikeouts (pitch rows only).
  static int outsFromPitches(List<PitchEvent> data) {
    int total = 0;
    for (final e in data.where((e) => e.eventType == 'pitch')) {
      if (e.outcome == 'dp') {
        total += 2;
      } else if (e.outcome != null &&
          {'k', 'kl', 'go', 'fo', 'lo', 'fc'}.contains(e.outcome)) {
        total += 1;
      }
    }
    return total;
  }

  /// Full season/game overview — port of `ov_stats` reactive.
  static OverviewStats overview(List<PitchEvent> data) {
    final pitchOuts = outsFromPitches(data);
    final poOuts = pickoffRows(data).length;
    final totalOuts = pitchOuts + poOuts;
    final ip = totalOuts / 3.0;

    final runs = pitchesOnly(data).fold<double>(0, (s, e) => s + e.er);
    final era = ip > 0 ? _round(runs * 9 / ip, 2) : null;

    final finals = finalPAs(data);
    final pa = finals.length;
    final ab = finals.fold<int>(0, (s, r) => s + r.ab);
    final h = finals.fold<int>(0, (s, r) => s + r.hit);
    final bb = finals.fold<int>(0, (s, r) => s + r.bb);
    final hbp = finals.fold<int>(0, (s, r) => s + r.hbp);
    final tb = finals.fold<int>(0, (s, r) => s + r.tb);
    final k = finals.fold<int>(0, (s, r) => s + r.k);

    final whip = ip > 0 ? _round((bb + h) / ip, 3) : null;
    final avg = ab > 0 ? _round(h / ab, 3) : null;
    final slg = ab > 0 ? _round(tb / ab, 3) : null;

    final pitchRows = pitchesOnly(data);
    final ppa = (pa > 0 && pitchRows.isNotEmpty)
        ? _round(pitchRows.length / pa, 2)
        : null;

    final kPct = pa > 0 ? _round(k / pa * 100, 1) : null;
    final bbPct = pa > 0 ? _round(bb / pa * 100, 1) : null;
    final kbb =
        (kPct != null && bbPct != null) ? _round(kPct - bbPct, 1) : null;

    // Swing/whiff: swing = call in {ss, f, ip}; whiff = call == ss.
    final swings =
        pitchRows.where((e) => {'ss', 'f', 'ip'}.contains(e.call)).length;
    final whiffs = pitchRows.where((e) => e.call == 'ss').length;
    final whiffPct = swings > 0 ? _round(whiffs / swings * 100, 1) : null;

    // First-pitch-swing % (approximation of R's F-Strike%): fraction of PAs
    // where the batter swung, was called out, or put it in play on pitch #1.
    final firstPitches =
        pitchRows.where((e) => e.pitchNum == 1).toList();
    double? fStrike;
    if (firstPitches.isNotEmpty) {
      final fpsCount = firstPitches
          .where((e) => {'ss', 'sl', 'f', 'ip'}.contains(e.call))
          .length;
      fStrike = _round(fpsCount / firstPitches.length * 100, 1);
    }

    final ipWhole = totalOuts ~/ 3;
    final ipRemainder = totalOuts % 3;

    return OverviewStats(
      ipDisplay: '$ipWhole.$ipRemainder',
      era: era,
      whip: whip,
      avg: avg,
      slg: slg,
      ppa: ppa,
      kPct: kPct,
      bbPct: bbPct,
      kbb: kbb,
      whiffPct: whiffPct,
      fStrikePct: fStrike,
    );
  }

  /// Pitch arsenal summary — usage%, strike/ball/swing/take, whiff%, foul%,
  /// in-play%, contact%, batted-ball mix, K%/BB%, and BAA, all broken out
  /// per pitch type. Extended port of the R app's `pitch_sum` reactive to
  /// cover every metric on the "Pitch Breakdown" info-button reference sheet.
  ///
  /// Shared calc for one row of the pitch-breakdown table — either a single
  /// pitch type's rows ([list]/[finList]) or, when called with every pitch
  /// and every final PA regardless of type, the "Overall" combined row.
  static Map<String, dynamic> _pitchBreakdownRow(
    String type,
    List<PitchEvent> list,
    List<PAResult> finList,
    int totalPitches,
  ) {
    final n = list.length;
    final usagePct = _round(n / totalPitches * 100, 1);

    final strikes = list.where((e) => {'ss', 'sl', 'f', 'ip'}.contains(e.call)).length;
    final balls = list.where((e) => e.call == 'b').length;
    final swings = list.where((e) => {'ss', 'f', 'ip'}.contains(e.call)).length;
    final takes = list.where((e) => {'b', 'sl'}.contains(e.call)).length;
    final whiffs = list.where((e) => e.call == 'ss').length;
    final fouls = list.where((e) => e.call == 'f').length;
    final inPlay = list.where((e) => e.call == 'ip').length;
    final contact = fouls + inPlay;

    final battedBalls = list.where((e) => e.call == 'ip' && e.battedType != null).toList();
    final bbTotal = battedBalls.length;
    final gb = battedBalls.where((e) => e.battedType == 'gb').length;
    final fb = battedBalls.where((e) => e.battedType == 'fb').length;
    final ld = battedBalls.where((e) => e.battedType == 'ld').length;
    final pu = battedBalls.where((e) => e.battedType == 'pu').length;

    final whiffPct = swings > 0 ? _round(whiffs / swings * 100, 1) : null;
    final foulPct = swings > 0 ? _round(fouls / swings * 100, 1) : null;
    final contactPct = swings > 0 ? _round(contact / swings * 100, 1) : null;

    // Supporting rates for the relationship-based Swing/Take/In Play colors
    // (display only — none of the existing stats above are affected).
    final takeStrikes = list.where((e) => e.call == 'sl').length;
    final bipResults = list
        .where((e) => e.call == 'ip' && e.outcome != null && e.outcome!.isNotEmpty)
        .toList();
    final bipOuts =
        bipResults.where((e) => PitchEvent.ballInPlayOutOutcomes.contains(e.outcome)).length;

    final finAB = finList.fold<int>(0, (s, r) => s + r.ab);
    final finH = finList.fold<int>(0, (s, r) => s + r.hit);
    final avg = finAB > 0 ? _round(finH / finAB, 3) : null;
    final finPA = finList.length;
    final finK = finList.fold<int>(0, (s, r) => s + r.k);
    final finBB = finList.fold<int>(0, (s, r) => s + r.bb);

    return {
      'pitchType': type,
      'n': n,
      'swingsN': swings,
      'battedBallsN': bbTotal,
      'paN': finPA,
      'abN': finAB,
      'usagePct': usagePct,
      'strikePct': _round(strikes / n * 100, 1),
      'ballPct': _round(balls / n * 100, 1),
      'swingPct': _round(swings / n * 100, 1),
      'takePct': _round(takes / n * 100, 1),
      'whiffPct': whiffPct,
      'foulPct': foulPct,
      'inPlayPct': _round(inPlay / n * 100, 1),
      'contactPct': contactPct,
      'groundBallPct': bbTotal > 0 ? _round(gb / bbTotal * 100, 1) : null,
      'flyBallPct': bbTotal > 0 ? _round(fb / bbTotal * 100, 1) : null,
      'lineDrivePct': bbTotal > 0 ? _round(ld / bbTotal * 100, 1) : null,
      'popupPct': bbTotal > 0 ? _round(pu / bbTotal * 100, 1) : null,
      'avgAgainst': avg,
      // Share of takes that were called strikes (vs balls) / share of balls
      // in play that were outs. Null with no takes / no balls in play.
      'takeStrikePct': takes > 0 ? _round(takeStrikes / takes * 100, 1) : null,
      'bipOutPct': bipResults.isNotEmpty ? _round(bipOuts / bipResults.length * 100, 1) : null,
      'kPct': finPA > 0 ? _round(finK / finPA * 100, 1) : null,
      'bbPct': finPA > 0 ? _round(finBB / finPA * 100, 1) : null,
    };
  }

  static List<Map<String, dynamic>> pitchBreakdown(List<PitchEvent> data) {
    final pitches = _livePitches(data);
    if (pitches.isEmpty) return [];
    // Each pitch goes into exactly one bucket: its own pitch type. A plate
    // appearance's result (hit, K, BB) goes to the bucket of the pitch that
    // ENDED it, never to the other pitches thrown earlier in the at-bat.
    final byType = groupBy(pitches, _bucketKey);
    final finals = _finalPAsLive(data);
    final finalsByType = groupBy(finals, (PAResult r) => _bucketKey(r.event));
    final totalPitches = pitches.length;

    return byType.entries.map((entry) {
      final type = entry.key;
      final list = entry.value;
      final finList = finalsByType[type] ?? [];
      return _pitchBreakdownRow(type, list, finList, totalPitches);
    }).toList()
      ..sort((a, b) =>
          (b['usagePct'] as double).compareTo(a['usagePct'] as double));
  }

  /// Same shape as one [pitchBreakdown] row, but combined across every
  /// pitch type — used for the Stats Per Pitch table's "Overall" row.
  static Map<String, dynamic>? pitchBreakdownOverall(List<PitchEvent> data) {
    final pitches = _livePitches(data);
    if (pitches.isEmpty) return null;
    final finals = _finalPAsLive(data);
    return _pitchBreakdownRow('Overall', pitches, finals, pitches.length);
  }

  /// Ahead / Behind / Even count-bucket OBP — port of `cnt_data`.
  /// A PA is "ahead" if the pitcher ever reached 2 strikes before 2 balls,
  /// "behind" if 2 balls before 2 strikes, else "even".
  static Map<String, dynamic> countApproach(List<PitchEvent> data) {
    final pitches = pitchesOnly(data);
    final byPA = groupBy(
      pitches,
      (PitchEvent e) => '${e.game}|${e.gameNumber}|${e.batter}|${e.batterNumber}|${e.paId}',
    );
    final finals = finalPAs(data);
    final finalByKey = {
      for (final r in finals)
        '${r.event.game}|${r.event.gameNumber}|${r.event.batter}|${r.event.batterNumber}|${r.event.paId}':
            r
    };

    int aheadPA = 0, behindPA = 0, evenPA = 0;
    int aheadOB = 0, behindOB = 0, evenOB = 0;
    int fpsCount = 0, fpsTotal = 0, fpsOB = 0;

    for (final entry in byPA.entries) {
      final list = entry.value..sort((a, b) => (a.pitchNum ?? 0).compareTo(b.pitchNum ?? 0));
      int balls = 0, strikes = 0;
      String cat = 'even';
      for (final p in list) {
        if (p.call == 'b') {
          balls++;
        } else if ({'ss', 'sl', 'f'}.contains(p.call) && strikes < 2) {
          strikes++;
        }
        if (strikes >= 2 && balls < 2) cat = 'ahead';
        if (balls >= 2 && strikes < 2) cat = 'behind';
      }
      final res = finalByKey[entry.key];
      if (res == null) continue;
      final onBase = (res.hit == 1 || res.bb == 1 || res.hbp == 1) ? 1 : 0;

      if (cat == 'ahead') {
        aheadPA++;
        aheadOB += onBase;
      } else if (cat == 'behind') {
        behindPA++;
        behindOB += onBase;
      } else {
        evenPA++;
        evenOB += onBase;
      }

      fpsTotal++;
      final firstPitch = list.first;
      final swungFirst = {'ss', 'sl', 'f', 'ip'}.contains(firstPitch.call);
      if (swungFirst) {
        fpsCount++;
        fpsOB += onBase;
      }
    }

    double? obp(int ob, int n) => n > 0 ? _round(ob / n, 3) : null;

    return {
      'totalPA': aheadPA + behindPA + evenPA,
      'aheadPA': aheadPA,
      'behindPA': behindPA,
      'evenPA': evenPA,
      'aheadOBP': obp(aheadOB, aheadPA),
      'behindOBP': obp(behindOB, behindPA),
      'evenOBP': obp(evenOB, evenPA),
      'fpsPct': fpsTotal > 0 ? _round(fpsCount / fpsTotal * 100, 1) : null,
      'fpsOBP': obp(fpsOB, fpsCount),
    };
  }

  /// Two grouped count-situation stats requested for the Count & Approach
  /// screen: "Two-Strike Count %" (0-2 or 1-2 reached) and "Hitter's Count %"
  /// (2-0 or 2-1 reached). Mirrors the ahead/behind bucket logic but keyed
  /// on the exact ball-strike state reached during the PA rather than the
  /// broader ahead/behind/even categorization.
  static Map<String, dynamic> groupedCountStats(List<PitchEvent> data) {
    final pitches = pitchesOnly(data);
    final byPA = groupBy(
      pitches,
      (PitchEvent e) => '${e.game}|${e.gameNumber}|${e.batter}|${e.batterNumber}|${e.paId}',
    );
    final finals = finalPAs(data);
    final finalByKey = {
      for (final r in finals)
        '${r.event.game}|${r.event.gameNumber}|${r.event.batter}|${r.event.batterNumber}|${r.event.paId}':
            r
    };

    int twoStrikePA = 0, twoStrikeOB = 0;
    int hittersPA = 0, hittersOB = 0;
    int totalPA = 0;

    for (final entry in byPA.entries) {
      final list = entry.value..sort((a, b) => (a.pitchNum ?? 0).compareTo(b.pitchNum ?? 0));
      final res = finalByKey[entry.key];
      if (res == null) continue;
      totalPA++;
      final onBase = (res.hit == 1 || res.bb == 1 || res.hbp == 1) ? 1 : 0;

      int ballsBefore = 0, strikesBefore = 0;
      bool reachedTwoStrike = false;
      bool reachedHittersCount = false;
      for (final p in list) {
        final countStr = '$ballsBefore-$strikesBefore';
        if (countStr == '0-2' || countStr == '1-2') reachedTwoStrike = true;
        if (countStr == '2-0' || countStr == '2-1') reachedHittersCount = true;
        if (p.call == 'b') {
          ballsBefore++;
        } else if ({'ss', 'sl', 'f'}.contains(p.call) && strikesBefore < 2) {
          strikesBefore++;
        }
      }
      if (reachedTwoStrike) {
        twoStrikePA++;
        twoStrikeOB += onBase;
      }
      if (reachedHittersCount) {
        hittersPA++;
        hittersOB += onBase;
      }
    }

    double? obp(int ob, int n) => n > 0 ? _round(ob / n, 3) : null;
    double? pct(int n, int tot) => tot > 0 ? _round(n / tot * 100, 1) : null;

    return {
      'twoStrikePA': twoStrikePA,
      'twoStrikePct': pct(twoStrikePA, totalPA),
      'twoStrikeOBP': obp(twoStrikeOB, twoStrikePA),
      'hittersCountPA': hittersPA,
      'hittersCountPct': pct(hittersPA, totalPA),
      'hittersCountOBP': obp(hittersOB, hittersPA),
    };
  }

  /// Pitch-usage heat map by count — port of the R app's
  /// `count_heatmap_ui`, extended (per item 11) with Strike% and BAA
  /// alongside Usage% for each (count, pitch type) cell.
  ///
  /// BAA per cell uses ONLY the pitch thrown in that count: an at-bat's hit or
  /// out is credited to the single pitch that ended it (the count it was
  /// thrown at and its pitch type), never to the earlier pitches of the same
  /// at-bat. A cell shows BAA once at least one at-bat ended on that pitch at
  /// that count; with none it stays null (blank), not 0.
  static Map<String, dynamic> countHeatmap(List<PitchEvent> data) {
    final pitches = _livePitches(data);
    final byPA = groupBy(
      pitches,
      (PitchEvent e) => '${e.game}|${e.gameNumber}|${e.batter}|${e.batterNumber}|${e.paId}',
    );

    // cellKey -> counts
    final cellN = <String, int>{};
    final cellStrikes = <String, int>{};
    final cellAB = <String, int>{};
    final cellHits = <String, int>{};
    final countAB = <String, int>{};
    final countHits = <String, int>{};
    final countTotals = <String, int>{};
    final countStrikes = <String, int>{};
    final pitchTypesSeen = <String>{};

    for (final entry in byPA.entries) {
      final list = entry.value..sort((a, b) => (a.pitchNum ?? 0).compareTo(b.pitchNum ?? 0));
      // The pitch that ENDED this at-bat: the last pitch carrying a result
      // (same rule finalPAs uses). Only this one pitch may add to AB/hits, so a
      // plate appearance can never be counted twice, and an unfinished one
      // (no result yet) adds nothing.
      PitchEvent? finalPitch;
      for (final p in list) {
        if (p.isFinalPitchOfPA) finalPitch = p;
      }
      int ballsBefore = 0, strikesBefore = 0;
      for (final p in list) {
        final countStr = '$ballsBefore-$strikesBefore';
        final pt = _bucketKey(p);
        pitchTypesSeen.add(pt);
        final cellKey = '$countStr|$pt';
        cellN[cellKey] = (cellN[cellKey] ?? 0) + 1;
        countTotals[countStr] = (countTotals[countStr] ?? 0) + 1;
        final isStrike = {'ss', 'sl', 'f', 'ip'}.contains(p.call);
        if (isStrike) {
          cellStrikes[cellKey] = (cellStrikes[cellKey] ?? 0) + 1;
          countStrikes[countStr] = (countStrikes[countStr] ?? 0) + 1;
        }
        if (identical(p, finalPitch)) {
          // Official at-bat = every result except a walk or hit-by-pitch
          // (strikeouts, outs in play, errors and hits all count).
          final ab = (p.outcome == 'bb' || p.outcome == 'hbp') ? 0 : 1;
          final hit = PitchEvent.hitOutcomes.contains(p.outcome) ? 1 : 0;
          cellAB[cellKey] = (cellAB[cellKey] ?? 0) + ab;
          cellHits[cellKey] = (cellHits[cellKey] ?? 0) + hit;
          countAB[countStr] = (countAB[countStr] ?? 0) + ab;
          countHits[countStr] = (countHits[countStr] ?? 0) + hit;
        }
        if (p.call == 'b') {
          ballsBefore++;
        } else if ({'ss', 'sl', 'f'}.contains(p.call) && strikesBefore < 2) {
          strikesBefore++;
        }
      }
    }

    const allCounts = [
      '0-0', '0-1', '0-2', '1-0', '1-1', '1-2', '2-0', '2-1', '2-2', '3-0', '3-1', '3-2'
    ];
    final pitchTypes = pitchTypesSeen.toList()..sort();

    final cells = <String, Map<String, dynamic>>{};
    for (final countStr in allCounts) {
      final tot = countTotals[countStr] ?? 0;
      for (final pt in pitchTypes) {
        final key = '$countStr|$pt';
        final n = cellN[key] ?? 0;
        if (n == 0) continue;
        final strikes = cellStrikes[key] ?? 0;
        final ab = cellAB[key] ?? 0;
        final hits = cellHits[key] ?? 0;
        cells[key] = {
          'count': countStr,
          'pitchType': pt,
          'n': n,
          'totalAtCount': tot,
          'usagePct': tot > 0 ? _round(n / tot * 100, 0) : null,
          // Same ratios to one decimal (Count Tendencies shows 66.7%, not 67%).
          // usagePct = pitches of this type at this count ÷ ALL pitches at this count.
          'usagePct1': tot > 0 ? _round(n / tot * 100, 1) : null,
          'strikes': strikes,
          'strikePct1': _round(strikes / n * 100, 1),
          'strikePct': _round(strikes / n * 100, 0),
          'baa': ab >= 1 ? _round(hits / ab, 3) : null,
          'ab': ab,
          'hits': hits,
        };
      }
    }

    // BAA for each count with every pitch type combined: hits ÷ official
    // at-bats whose FINAL pitch was thrown at that count. Null (blank) when no
    // at-bat ended at that count.
    final countBaa = <String, Map<String, dynamic>>{
      for (final c in allCounts)
        c: {
          'ab': countAB[c] ?? 0,
          'hits': countHits[c] ?? 0,
          'baa': (countAB[c] ?? 0) >= 1 ? _round((countHits[c] ?? 0) / countAB[c]!, 3) : null,
        },
    };

    return {
      'counts': allCounts,
      'pitchTypes': pitchTypes,
      'countTotals': countTotals,
      'countStrikes': countStrikes,
      'cells': cells,
      'countBaa': countBaa,
    };
  }


  static List<Map<String, dynamic>> gameLog(List<PitchEvent> data) {
    final games = groupBy(data, (PitchEvent e) => '${e.game}|${e.gameNumber}');
    final rows = <Map<String, dynamic>>[];
    // preserve chronological order of first appearance
    final orderedKeys = <String>[];
    for (final e in data) {
      final key = '${e.game}|${e.gameNumber}';
      if (!orderedKeys.contains(key)) orderedKeys.add(key);
    }
    for (final key in orderedKeys) {
      final gameData = games[key]!;
      final opponent = gameData.first.game;
      final gnum = gameData.first.gameNumber;
      final pitchOuts = outsFromPitches(gameData);
      final poOuts = pickoffRows(gameData).length;
      final totalOuts = pitchOuts + poOuts;
      final ip = totalOuts / 3.0;
      final er = pitchesOnly(gameData).fold<double>(0, (s, e) => s + e.er);
      final era = ip > 0 ? _round(er * 9 / ip, 2) : null;
      final finals = finalPAs(gameData);
      final pa = finals.length;
      final h = finals.fold<int>(0, (s, r) => s + r.hit);
      final bb = finals.fold<int>(0, (s, r) => s + r.bb);
      final k = finals.fold<int>(0, (s, r) => s + r.k);
      final whip = ip > 0 ? _round((h + bb) / ip, 3) : null;
      // Everything else reuses the shared per-game calculations (overview +
      // the all-pitches breakdown row) so these numbers can never disagree
      // with the Overview / Pitch Breakdown tabs.
      final ov = overview(gameData);
      final pb = pitchBreakdownOverall(gameData);
      final hbpN = finals.fold<int>(0, (s, r) => s + r.hbp);
      final abN = finals.fold<int>(0, (s, r) => s + r.ab);
      int outcomeCount(String o) => finals.where((r) => r.event.outcome == o).length;
      // Called strikes ÷ real pitches (same pitch set as Strike % / Ball %).
      final livePitches = _livePitches(gameData);
      final calledStrikes = livePitches.where((e) => e.call == 'sl').length;
      rows.add({
        'calledStrikePct':
            livePitches.isNotEmpty ? _round(calledStrikes / livePitches.length * 100, 1) : null,
        'pitches': pb == null ? 0 : pb['n'],
        'ab': abN,
        'doubles': outcomeCount('2b'),
        'triples': outcomeCount('3b'),
        'hr': outcomeCount('hr'),
        'hbp': hbpN,
        'po': pickoffRows(gameData).length,
        'obp': pa > 0 ? _round((h + bb + hbpN) / pa, 3) : null,
        'avg': ov.avg,
        'slg': ov.slg,
        'ppa': ov.ppa,
        'kbb': ov.kbb,
        'whiffPct': ov.whiffPct,
        'fStrikePct': ov.fStrikePct,
        'strikePct': pb?['strikePct'],
        'ballPct': pb?['ballPct'],
        'swingPct': pb?['swingPct'],
        'foulPct': pb?['foulPct'],
        'inPlayPct': pb?['inPlayPct'],
        'contactPct': pb?['contactPct'],
        'bipOutPct': pb?['bipOutPct'],
        'groundBallPct': pb?['groundBallPct'],
        'flyBallPct': pb?['flyBallPct'],
        'lineDrivePct': pb?['lineDrivePct'],
        'opponent': opponent,
        'gameNumber': gnum,
        'ip': '${totalOuts ~/ 3}.${totalOuts % 3}',
        'er': er,
        'era': era,
        'whip': whip,
        'pa': pa,
        'h': h,
        'bb': bb,
        'k': k,
        'kPct': pa > 0 ? _round(k / pa * 100, 1) : null,
        'bbPct': pa > 0 ? _round(bb / pa * 100, 1) : null,
      });
    }
    return rows;
  }

  /// Speed/shape tier for each pitch type — used to detect whether a
  /// sequence changes speeds/looks between consecutive pitches. This is an
  /// approximation (the app doesn't track actual velocity), but it reflects
  /// real scouting logic: fastballs are the "fast" tier, everything else is
  /// a distinct off-speed/breaking tier, and a sequence that alternates
  /// tiers disrupts hitter timing more than one that doesn't.
  static const Map<String, String> _speedTier = {
    'fb': 'fast',
    'sl': 'breaking',
    'cv': 'slow_breaking',
    'ch': 'offspeed',
  };
  static String _tierFor(String pt) => _speedTier[pt] ?? 'offspeed';

  /// Opening-sequence analysis. A "sequence" is the FIRST THREE pitch types of
  /// a completed plate appearance that lasted at least three pitches (e.g.
  /// FB→CV→CV). Unfinished plate appearances and dead-ball rows are ignored.
  ///
  /// SCORE (0-100) — the average of the new per-plate-appearance decision
  /// score (see `sequence_scoring.dart` for the full formula, rules and the
  /// 30/25/20/10/15 component weights) over every plate appearance that
  /// opened this way. It is NOT a function of results alone: count
  /// management, the batter's own history with each pitch, how each pitch
  /// follows the previous response, and predictability are all evaluated, and
  /// the result is only 15 of 100 points. Missing data is dropped and the
  /// remaining weights re-normalised, never counted as bad.
  ///
  /// Descriptive fields kept for the scouting report / cards:
  ///  - outPct / kPct: share of those PAs ending in an out / strikeout.
  ///  - strikePct: share of the sequence's own 3 pitches that were strikes.
  ///  - weakContactPct: of those ending on a ball in play with a known
  ///    batted-ball type, the share that were ground balls.
  ///  - speedChanges / uniqueTypes / repeatAll3: shape facts (descriptive
  ///    only — they no longer add or subtract points by themselves).
  ///
  /// `history`: pass the FULL (year-filtered) pitch list when `data` is a
  /// team/game subset so the batter-matchup history can see earlier games.
  /// `lowSample` is true when n < 3.
  static List<Map<String, dynamic>> pitchSequencing(
    List<PitchEvent> data, {
    List<PitchEvent>? history,
  }) {
    final shown = {for (final e in data) e.id};
    final scored = SequenceScoring.scoreAll(history ?? data)
        .where((s) => shown.contains(s.pitches.first.id))
        .toList();
    const notOuts = {'1b', '2b', '3b', 'hr', 'bb', 'hbp', 'e'};
    const strikeCalls = {'ss', 'sl', 'f', 'ip'};

    final bySeq = <String, List<PaScore>>{};
    for (final s in scored) {
      if (!s.completed || s.pitches.length < 3 || !s.hasScore) continue;
      bySeq.putIfAbsent(s.openingSequence, () => []).add(s);
    }

    final result = <Map<String, dynamic>>[];
    for (final entry in bySeq.entries) {
      final list = entry.value;
      final n = list.length;
      var outs = 0, ks = 0, weak = 0, hard = 0, strikes = 0;
      for (final s in list) {
        final last = s.pitches.last;
        if (!notOuts.contains(last.outcome)) outs++;
        if (PitchEvent.kOutcomes.contains(last.outcome)) ks++;
        if (last.call == 'ip' && last.battedType != null) {
          if ({'gb', 'pu'}.contains(last.battedType)) {
            weak++;
          } else {
            hard++;
          }
        }
        strikes += s.pitches.take(3).where((e) => strikeCalls.contains(e.call)).length;
      }
      final types = list.first.pitches.take(3).map(_bucketKey).toList();
      final tiers = types.map(_tierFor).toList();
      var speedChanges = 0;
      for (var i = 1; i < tiers.length; i++) {
        if (tiers[i] != tiers[i - 1]) speedChanges++;
      }
      final uniqueTypes = types.toSet().length;
      final bip = weak + hard;

      // Mean PA score; component averages count a not-evaluated component as
      // 0 earned / 0 available so that Σ avgEarned == mean score exactly.
      final meanScore = list.fold<double>(0, (a, s) => a + s.score!) / n;
      final comps = <String, Map<String, dynamic>>{};
      for (final k in SeqWeights.keys) {
        var earned = 0.0, avail = 0.0, valSum = 0.0;
        var evalN = 0;
        var anyLimited = false;
        for (final s in list) {
          final c = s.components[k]!;
          if (c.evaluated) {
            earned += c.earned!;
            avail += c.maxPoints!;
            valSum += c.value!;
            evalN++;
            if (c.limitedConfidence) anyLimited = true;
          }
        }
        comps[k] = {
          'label': SeqWeights.labels[k],
          'nominal': SeqWeights.byKey[k],
          'avgEarned': earned / n,
          'avgMax': avail / n,
          'avgValue': evalN > 0 ? valSum / evalN : null,
          'evaluatedPAs': evalN,
          'limited': anyLimited,
        };
      }

      // Reasons grouped by code, most frequent first; the text shown is the
      // first one recorded (it is generated from real calculations).
      final grouped = <String, Map<String, dynamic>>{};
      for (final s in list) {
        final seenCodes = <String>{};
        for (final note in s.notes) {
          final g = grouped.putIfAbsent(note.code, () => {
                'polarity': note.polarity,
                'component': note.component,
                'text': note.text,
                'count': 0,
              });
          if (seenCodes.add(note.code)) g['count'] = (g['count'] as int) + 1;
        }
      }
      final reasons = grouped.values.toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      final reduced = list.where((s) => s.reducedConfidence).length;
      result.add({
        'seq': entry.key,
        'count': n,
        'outPct': _round(outs / n * 100, 0),
        'kPct': _round(ks / n * 100, 0),
        'strikePct': _round(strikes / (n * 3) * 100, 0),
        'weakContactPct': bip > 0 ? _round(weak / bip * 100, 0) : null,
        'speedChanges': speedChanges,
        'uniqueTypes': uniqueTypes,
        'repeatAll3': uniqueTypes == 1,
        'lowSample': n < 3,
        'score': _round(meanScore, 1),
        'components': comps,
        'reasons': reasons,
        'reducedConfidencePAs': reduced,
        'paScores': list,
      });
    }
    result.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return result;
  }

  /// Put-away pitch: distribution of final pitch type on strikeouts.
  static List<Map<String, dynamic>> putAwayPitch(List<PitchEvent> data) {
    final finals = finalPAs(data).where((r) => r.k == 1).toList();
    if (finals.isEmpty) return [];
    final byType = groupBy(finals, (PAResult r) => r.event.pitchType ?? 'other');
    final total = finals.length;
    return byType.entries.map((e) {
      return {
        'pitchType': e.key,
        'count': e.value.length,
        'ofTotal': total,
        'pct': _round(e.value.length / total * 100, 1),
      };
    }).toList()
      ..sort((a, b) => (b['pct'] as double).compareTo(a['pct'] as double));
  }

  /// First-pitch strike% by pitch type: of all pitch #1's thrown of a
  /// given type, what share were strikes (called, swinging, foul, or in
  /// play). Same shape/style as [putAwayPitch] so both render with the
  /// same bar UI.
  static List<Map<String, dynamic>> firstPitchStrikeByType(List<PitchEvent> data) {
    final firstPitches = pitchesOnly(data).where((e) => e.pitchNum == 1).toList();
    if (firstPitches.isEmpty) return [];
    final byType = groupBy(firstPitches, (PitchEvent e) => e.pitchType ?? 'other');
    final total = firstPitches.length;
    return byType.entries.map((e) {
      final list = e.value;
      final strikes = list.where((p) => {'ss', 'sl', 'f', 'ip'}.contains(p.call)).length;
      return {
        'pitchType': e.key,
        'count': list.length,
        'ofTotal': total,
        'pct': _round(strikes / list.length * 100, 1),
      };
    }).toList()
      ..sort((a, b) => (b['pct'] as double).compareTo(a['pct'] as double));
  }

  /// Per-batter (jersey #) breakdown — used by Scouting Report's
  /// "Key Hitters" table and Game Input's batter-history panel.
  static List<Map<String, dynamic>> batterStats(List<PitchEvent> data) {
    final finals = finalPAs(data);
    final byJersey = groupBy(finals, (PAResult r) => r.event.batterNumber ?? -1);
    return byJersey.entries.where((e) => e.key != -1).map((entry) {
      final list = entry.value;
      final pa = list.length;
      final ab = list.fold<int>(0, (s, r) => s + r.ab);
      final h = list.fold<int>(0, (s, r) => s + r.hit);
      final bb = list.fold<int>(0, (s, r) => s + r.bb);
      final hbp = list.fold<int>(0, (s, r) => s + r.hbp);
      final k = list.fold<int>(0, (s, r) => s + r.k);
      final xbh = list
          .where((r) => {'2b', '3b', 'hr'}.contains(r.event.outcome))
          .length;
      return {
        'jersey': entry.key,
        'pa': pa,
        'ab': ab,
        'h': h,
        'bb': bb,
        'hbp': hbp,
        'k': k,
        'xbh': xbh,
        'avg': ab > 0 ? _round(h / ab, 3) : null,
        'obp': (ab + bb + hbp) > 0 ? _round((h + bb + hbp) / (ab + bb + hbp), 3) : null,
      };
    }).toList()
      ..sort((a, b) => (b['pa'] as int).compareTo(a['pa'] as int));
  }

  /// Opposing-hitters' approach tendencies vs. this pitcher — port of the
  /// R app's aggressive_early / chase_offspeed / sit_fastball heuristics.
  static Map<String, dynamic> scoutingApproach(List<PitchEvent> data) {
    final pitches = pitchesOnly(data);
    final byPA = groupBy(
      pitches,
      (PitchEvent e) => '${e.game}|${e.gameNumber}|${e.batter}|${e.batterNumber}|${e.paId}',
    );

    int firstPitchSwings = 0, firstPitchTotal = 0;
    int behindCountFbCount = 0, behindCountTotal = 0;

    for (final entry in byPA.entries) {
      final list = entry.value..sort((a, b) => (a.pitchNum ?? 0).compareTo(b.pitchNum ?? 0));
      if (list.isEmpty) continue;
      firstPitchTotal++;
      if ({'ss', 'f', 'ip'}.contains(list.first.call)) firstPitchSwings++;

      int ballsBefore = 0, strikesBefore = 0;
      for (final p in list) {
        final behind = ballsBefore >= 2 && strikesBefore < 2;
        if (behind) {
          behindCountTotal++;
          if ((p.pitchType ?? '').toLowerCase() == 'fb') behindCountFbCount++;
        }
        if (p.call == 'b') {
          ballsBefore++;
        } else if ({'ss', 'sl', 'f'}.contains(p.call) && strikesBefore < 2) {
          strikesBefore++;
        }
      }
    }

    // Off-speed chase: average whiff% on cv/ch/sl pitches.
    final offspeed = pitches.where((e) => {'cv', 'ch', 'sl'}.contains(e.pitchType)).toList();
    double? offspeedWhiffPct;
    if (offspeed.isNotEmpty) {
      final sw = offspeed.where((e) => {'ss', 'f', 'ip'}.contains(e.call)).length;
      final wh = offspeed.where((e) => e.call == 'ss').length;
      if (sw >= 3) offspeedWhiffPct = _round(wh / sw * 100, 1);
    }

    final fbBehindPct = behindCountTotal >= 5 ? _round(behindCountFbCount / behindCountTotal * 100, 1) : null;

    return {
      'aggressiveEarly': firstPitchTotal >= 5 ? (firstPitchSwings / firstPitchTotal) > 0.45 : null,
      'chaseOffspeed': offspeedWhiffPct != null ? offspeedWhiffPct > 28 : null,
      'sitFastball': fbBehindPct != null ? fbBehindPct > 60 : null,
      'fbBehindPct': fbBehindPct,
    };
  }

  /// Which ball-strike count has done the most damage (highest OBP)
  /// against this pitcher, minimum 2 PAs reaching that count.
  static Map<String, dynamic>? topDamageCount(List<PitchEvent> data) {
    final pitches = pitchesOnly(data);
    final byPA = groupBy(
      pitches,
      (PitchEvent e) => '${e.game}|${e.gameNumber}|${e.batter}|${e.batterNumber}|${e.paId}',
    );
    final finals = finalPAs(data);
    final finalByKey = {
      for (final r in finals)
        '${r.event.game}|${r.event.gameNumber}|${r.event.batter}|${r.event.batterNumber}|${r.event.paId}':
            r
    };

    final obByCount = <String, int>{};
    final nByCount = <String, int>{};
    for (final entry in byPA.entries) {
      final list = entry.value..sort((a, b) => (a.pitchNum ?? 0).compareTo(b.pitchNum ?? 0));
      final res = finalByKey[entry.key];
      if (res == null || list.isEmpty) continue;
      int ballsBefore = 0, strikesBefore = 0;
      for (final p in list) {
        if (p.call == 'b') {
          ballsBefore++;
        } else if ({'ss', 'sl', 'f'}.contains(p.call) && strikesBefore < 2) {
          strikesBefore++;
        }
      }
      final finalCount = '$ballsBefore-$strikesBefore';
      final onBase = (res.hit == 1 || res.bb == 1 || res.hbp == 1) ? 1 : 0;
      nByCount[finalCount] = (nByCount[finalCount] ?? 0) + 1;
      obByCount[finalCount] = (obByCount[finalCount] ?? 0) + onBase;
    }

    Map<String, dynamic>? best;
    for (final key in nByCount.keys) {
      final n = nByCount[key]!;
      if (n < 2) continue;
      final obp = _round((obByCount[key] ?? 0) / n, 3);
      if (best == null || obp > (best['obp'] as double)) {
        best = {'count': key, 'n': n, 'obp': obp};
      }
    }
    return best;
  }

  /// Game-by-game trend (AVG / K% / BB%) vs. a specific opponent — used by
  /// the Scouting Report's Adjustment Notes section.
  static List<Map<String, dynamic>> opponentGameTrend(List<PitchEvent> data) {
    final byGame = groupBy(data, (PitchEvent e) => e.gameNumber);
    final gameNums = byGame.keys.toList()..sort();
    return gameNums.map((gnum) {
      final gameData = byGame[gnum]!;
      final finals = finalPAs(gameData);
      final ab = finals.fold<int>(0, (s, r) => s + r.ab);
      final h = finals.fold<int>(0, (s, r) => s + r.hit);
      final k = finals.fold<int>(0, (s, r) => s + r.k);
      final bb = finals.fold<int>(0, (s, r) => s + r.bb);
      final pa = finals.length;
      return {
        'game': gnum,
        'avg': ab > 0 ? _round(h / ab, 3) : null,
        'kPct': pa > 0 ? _round(k / pa * 100, 1) : null,
        'bbPct': pa > 0 ? _round(bb / pa * 100, 1) : null,
      };
    }).toList();
  }


  static double _round(double v, int places) {
    final mod = 1.0 * (places == 0 ? 1 : (places == 1 ? 10 : (places == 2 ? 100 : 1000)));
    return (v * mod).round() / mod;
  }
}
