import '../models/pitch_event.dart';

/// SKOUTAR Pitch Sequencing score — an explainable 0-100 evaluation of the
/// pitch-calling DECISIONS in one plate appearance (PA), built only from data
/// SKOUTAR already records (pitch type, call, count, outcome, batter jersey).
/// No velocity, movement or location is required or assumed.
///
/// ── Formula ────────────────────────────────────────────────────────────
/// Five components are each normalised to 0..1 (1 = best for the pitcher):
///
///   count    (30)  count-state transitions on non-terminal pitches
///   matchup  (25)  pitch type vs. the batter's own history with it
///   setup    (20)  each pitch's choice given the previous pitch's response
///   predict  (10)  deduct-only: ineffective repeated patterns
///   result   (15)  how the PA ended (balls in play discounted)
///
///   score = 100 x  Σ(weight_i x value_i)  /  Σ(weight_i)      over the
///   components that CAN be evaluated for this PA.
///
/// With all five evaluated, Σ weight = 100 so score = Σ points exactly. When a
/// component lacks data it is dropped and the remaining weights are
/// re-normalised (so missing data never counts as a bad result); the PA is then
/// marked reduced-confidence and the UI shows the coverage. A PA with fewer
/// than [SeqConfig.minComponents] evaluable components or less than
/// [SeqConfig.minCoverage] points of weight is not scored at all.
///
/// Every number below is an initial PRODUCT-DESIGN value, not a validated
/// one. Change them here only.

/// Component weights (sum = 100). Edit to recalibrate.
class SeqWeights {
  static const double count = 30;
  static const double matchup = 25;
  static const double setup = 20;
  static const double predict = 10;
  static const double result = 15;

  static const List<String> keys = ['count', 'matchup', 'setup', 'predict', 'result'];
  static const Map<String, double> byKey = {
    'count': count,
    'matchup': matchup,
    'setup': setup,
    'predict': predict,
    'result': result,
  };
  static const Map<String, String> labels = {
    'count': 'Count management',
    'matchup': 'Batter matchup',
    'setup': 'Setup & response',
    'predict': 'Predictability',
    'result': 'Result',
  };
  static double get total => byKey.values.fold(0.0, (a, b) => a + b);
}

/// Thresholds, shrinkage constants and lookup tables.
class SeqConfig {
  // Count value: pitcher-favourability of a ball-strike count, 0..1.
  //   V(b, s) = 0.5 + perStrike*s - perBall*b
  static const double countPerStrike = 0.14;
  static const double countPerBall = 0.12;
  static const double hitterCountMax = 0.30; // 2-0, 3-0, 3-1
  static const double pitcherCountMin = 0.64; // 0-1, 0-2, 1-2
  static const double hitterNeedStrikeMax = 0.40; // counts where a strike is needed
  static const double countDeltaScale = 0.40; // delta of this size = full swing

  // Evidence shrinkage: value = 0.5 + (mean-0.5) * n/(n+k)
  static const double kCount = 2;
  static const double kSetup = 1;

  // Batter-vs-pitch-type statistics (batter's PRIOR pitches only).
  static const double kRate = 10; // pseudo-observations pulling toward reference
  static const int minSwings = 3, sufficientSwings = 8;
  static const int minAb = 3, sufficientAb = 6;
  static const int minPitches = 3, sufficientPitches = 8;
  static const int minRefSample = 20; // sample needed for the reference rate

  // Predictability.
  static const int streakLen = 3;
  static const double streakPenalty = 0.35;
  static const double usageShare = 0.65;
  static const int usageDecisive = 8;
  static const int patternMinAll = 10;
  static const int patternMinBatter = 2;
  static const double patternAllPenalty = 0.20;
  static const double patternBatterPenalty = 0.30;

  // Result.
  static const double inPlayShrink = 0.6; // balls in play are noisy

  // Scoring gate.
  static const double minCoverage = 40;
  static const int minComponents = 2;

  /// Pitcher-view value of how a PA ended (before in-play shrinkage).
  static const Map<String, double> resultValue = {
    'k': 1.0, 'kl': 1.0, 'dp': 0.95, 'go': 0.78, 'fo': 0.72, 'lo': 0.65,
    'fc': 0.5, 'e': 0.5, 'hbp': 0.15, 'bb': 0.0,
    '1b': 0.2, '2b': 0.08, '3b': 0.03, 'hr': 0.0,
  };
  static const Set<String> inPlayOutcomes = {
    '1b', '2b', '3b', 'hr', 'go', 'fo', 'lo', 'dp', 'fc', 'e',
  };
  static const Set<String> hitOutcomes = {'1b', '2b', '3b', 'hr'};
  static const Set<String> outInPlay = {'go', 'fo', 'lo', 'dp', 'fc'};
  static const Set<String> batterFavorable = {'1b', '2b', '3b', 'hr', 'bb', 'hbp', 'e'};

  /// Speed/shape tier (same tiers as StatsService's variety logic).
  static const Map<String, String> tier = {
    'fb': 'fast', 'sl': 'breaking', 'cv': 'slow_breaking', 'ch': 'offspeed',
  };
}

enum SeqPolarity { positive, review, limited, neutral }

/// One human-readable reason. Created ONLY when its condition is met by the
/// actual calculation (never from a template).
class SeqNote {
  final SeqPolarity polarity;
  final String component; // key in SeqWeights
  final String code; // stable id, used to group notes across PAs
  final String text;
  const SeqNote(this.polarity, this.component, this.code, this.text);
}

/// One component's result for one PA.
class SeqComponent {
  final String key;
  final double? value; // 0..1, null = not evaluated
  final bool limitedConfidence; // evaluated, but on small samples
  final double? earned; // points contributed to the final score
  final double? maxPoints; // points available after re-normalisation
  final String? skipReason;

  const SeqComponent({
    required this.key,
    required this.value,
    required this.limitedConfidence,
    required this.earned,
    required this.maxPoints,
    required this.skipReason,
  });

  bool get evaluated => value != null;
  String get label => SeqWeights.labels[key]!;
  double get nominalWeight => SeqWeights.byKey[key]!;
}

/// The full, explainable evaluation of one plate appearance.
class PaScore {
  final String key;
  final String team;
  final int gameNumber;
  final int season;
  final int? jersey;
  final bool completed;
  final String? finalOutcome;
  final List<PitchEvent> pitches;
  final List<(int, int)> countsBefore;
  final double? score; // null = not scoreable (see [unscoredReason])
  final String? unscoredReason;
  final double coverage; // Σ nominal weight of evaluated components
  final Map<String, SeqComponent> components;
  final List<SeqNote> notes;
  final int order; // chronological index among all PAs

  const PaScore({
    required this.key,
    required this.team,
    required this.gameNumber,
    required this.season,
    required this.jersey,
    required this.completed,
    required this.finalOutcome,
    required this.pitches,
    required this.countsBefore,
    required this.score,
    required this.unscoredReason,
    required this.coverage,
    required this.components,
    required this.notes,
    required this.order,
  });

  bool get hasScore => score != null;

  /// 'High' = every component evaluated on adequate samples; 'Moderate' =
  /// most weight evaluated; otherwise 'Low'.
  String get confidence {
    if (!hasScore) return 'None';
    final anyLimited = components.values.any((c) => c.evaluated && c.limitedConfidence);
    final frac = coverage / SeqWeights.total;
    if (frac >= 0.999 && !anyLimited) return 'High';
    if (frac >= 0.70) return 'Moderate';
    return 'Low';
  }

  bool get reducedConfidence => hasScore && confidence != 'High';

  String get openingSequence => pitches.take(3).map(_typeKey).map((t) => t.toUpperCase()).join('→');
}

String _typeKey(PitchEvent e) {
  final t = (e.pitchType ?? '').toLowerCase().trim();
  return t.isEmpty ? 'other' : t;
}

/// Running counts of one pitch type's results.
class _Tally {
  int n = 0, swings = 0, whiffs = 0, called = 0, ab = 0, hits = 0;
  void add(PitchEvent p) {
    n++;
    if (p.call == 'ss' || p.call == 'f' || p.call == 'ip') swings++;
    if (p.call == 'ss') whiffs++;
    if (p.call == 'sl') called++;
    final o = p.outcome;
    if (o != null && o.isNotEmpty && o != 'bb' && o != 'hbp') {
      ab++;
      if (SeqConfig.hitOutcomes.contains(o)) hits++;
    }
  }
}

/// Everything known BEFORE the PA currently being scored (chronological).
class _History {
  final Map<String, Map<String, _Tally>> batterType = {}; // 'team|jersey' -> type
  final Map<String, _Tally> pitcherType = {};
  final _Tally pitcherAll = _Tally();
  final Map<String, Map<String, int>> countUsage = {}; // 'b-s' -> type -> n
  final Map<String, Map<String, List<int>>> countResult = {}; // 'b-s' -> type -> [succ, fail]
  final Map<String, List<int>> patternAll = {}; // pattern -> [n, batterFavourable]
  final Map<String, List<int>> patternBatter = {}; // 'team|jersey|pattern'
}

class SequenceScoring {
  SequenceScoring._();

  // ───────────────────────── helpers ─────────────────────────

  static double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
  static double _shrink(int n, double k) => n / (n + k);

  /// Pitcher-favourability of a count, 0..1 (higher = better for pitcher).
  static double countValue(int balls, int strikes) =>
      0.5 + SeqConfig.countPerStrike * strikes - SeqConfig.countPerBall * balls;

  /// 'hitter' | 'even' | 'pitcher'
  static String countCategory(int b, int s) {
    final v = countValue(b, s);
    if (v <= SeqConfig.hitterCountMax) return 'hitter';
    if (v >= SeqConfig.pitcherCountMin) return 'pitcher';
    return 'even';
  }

  static String _catName(String c) => switch (c) {
        'hitter' => "a hitter's count",
        'pitcher' => "a pitcher's count",
        _ => 'an even count',
      };

  static String _tier(String t) => SeqConfig.tier[t] ?? 'offspeed';

  /// Balls-strikes BEFORE each pitch, using the same rules the app already
  /// uses elsewhere (a foul with two strikes does not add a strike).
  static List<(int, int)> countsBefore(List<PitchEvent> pitches) {
    int b = 0, s = 0;
    final out = <(int, int)>[];
    for (final p in pitches) {
      out.add((b, s));
      switch (p.call) {
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
    }
    return out;
  }

  /// +1 success, -1 failure, 0 neutral — deliberately execution-agnostic:
  /// a ball with two strikes and any foul are neutral.
  static int _pitchSuccess(PitchEvent p, int strikesBefore) {
    switch (p.call) {
      case 'ss':
      case 'sl':
        return 1;
      case 'b':
        return strikesBefore < 2 ? -1 : 0;
      case 'ip':
        if (SeqConfig.outInPlay.contains(p.outcome)) return 1;
        if (SeqConfig.hitOutcomes.contains(p.outcome)) return -1;
        return 0;
      case 'hbp':
        return -1;
      default:
        return 0;
    }
  }

  static bool _isTerminal(PitchEvent p) => (p.outcome ?? '').isNotEmpty;

  // ───────────────────── plate-appearance split ─────────────────────

  /// Splits logged pitch rows into plate appearances, in chronological order.
  /// Same approach as BatterHistoryService: a PA is a run of pitches ending at
  /// the first pitch carrying an outcome; a change of the stored PA sequence
  /// number (`batter`) also starts a new PA. Dead-ball ('dk') rows are not
  /// pitches; a PA that ends on one is dropped (not an at-bat result).
  static List<List<PitchEvent>> splitPlateAppearances(List<PitchEvent> data) {
    final open = <String, List<PitchEvent>>{};
    final openSeq = <String, int>{};
    final all = <List<PitchEvent>>[];
    final voided = <List<PitchEvent>>{};
    for (final p in data) {
      if (p.eventType != 'pitch') continue;
      final gk = '${p.game}|${p.gameNumber}|${p.season}';
      if (p.call == 'dk') {
        final cur = open[gk];
        if (cur != null && p.isFinalPitchOfPA) {
          voided.add(cur);
          open.remove(gk);
          openSeq.remove(gk);
        }
        continue;
      }
      var cur = open[gk];
      if (cur == null || openSeq[gk] != p.batter) {
        cur = <PitchEvent>[];
        open[gk] = cur;
        openSeq[gk] = p.batter;
        all.add(cur);
      }
      cur.add(p);
      if (p.isFinalPitchOfPA) {
        open.remove(gk);
        openSeq.remove(gk);
      }
    }
    return [
      for (final pa in all)
        if (pa.isNotEmpty && !voided.contains(pa)) pa,
    ];
  }

  static int? _jerseyOf(List<PitchEvent> pa) {
    for (final p in pa.reversed) {
      if (p.batterNumber != null) return p.batterNumber;
    }
    return null;
  }

  // ─────────────────────────── entry points ───────────────────────────

  /// Scores every plate appearance in [data] (chronological order is the
  /// order of the list). Batter history for the matchup component is built
  /// from the PAs BEFORE each one only, keyed by opponent team + jersey #, so
  /// nothing from the PA being scored (or later ones) leaks into it. Pass the
  /// full (year-filtered) history even when only some games will be shown.
  static List<PaScore> scoreAll(List<PitchEvent> data) {
    final pas = splitPlateAppearances(data);
    final h = _History();
    final out = <PaScore>[];
    for (var i = 0; i < pas.length; i++) {
      final pa = pas[i];
      out.add(_scorePa(pa, h, i));
      // Only finished PAs feed the history (a partial PA is not a result).
      if (pa.any((p) => _isTerminal(p))) _updateHistory(pa, h);
    }
    return out;
  }

  // ─────────────────────────── scoring one PA ───────────────────────────

  static PaScore _scorePa(List<PitchEvent> pit, _History h, int order) {
    final cts = countsBefore(pit);
    final first = pit.first;
    final jersey = _jerseyOf(pit);
    final team = first.game;
    final completed = _isTerminal(pit.last);
    final finalOutcome = completed ? pit.last.outcome : null;
    final notes = <SeqNote>[];
    final values = <String, double>{};
    final limited = <String, bool>{};
    final skip = <String, String>{};

    // ── 1. Count management (non-terminal pitches only) ──────────────
    final cvals = <double>[];
    for (var i = 0; i < pit.length; i++) {
      final p = pit[i];
      if (_isTerminal(p)) continue; // ending a PA is credited once, in Result
      final (b, s) = cts[i];
      if (s == 2 && (p.call == 'b' || p.call == 'f')) {
        cvals.add(0.5); // two strikes: a ball or a foul is not a mistake
        continue;
      }
      final nb = p.call == 'b' ? b + 1 : b;
      final ns = (p.call == 'ss' || p.call == 'sl' || p.call == 'f') ? (s < 2 ? s + 1 : 2) : s;
      final d = countValue(nb, ns) - countValue(b, s);
      cvals.add(_clamp01(0.5 + d / SeqConfig.countDeltaScale));
      final c0 = countCategory(b, s), c1 = countCategory(nb, ns);
      if (c0 != c1) {
        const rank = {'hitter': 0, 'even': 1, 'pitcher': 2};
        final up = rank[c1]! > rank[c0]!;
        notes.add(SeqNote(
          up ? SeqPolarity.positive : SeqPolarity.review,
          'count',
          up ? 'count_up' : 'count_down',
          '${up ? 'Moved' : 'Slipped'} from ${_catName(c0)} ($b-$s) to ${_catName(c1)} ($nb-$ns).',
        ));
      }
    }
    // Straight-balls run (flag only; never claims to know why).
    var run = 0, bestRun = 0, bestEnd = -1;
    for (var i = 0; i < pit.length; i++) {
      run = pit[i].call == 'b' ? run + 1 : 0;
      if (run > bestRun) {
        bestRun = run;
        bestEnd = i;
      }
    }
    if (bestRun >= 3) {
      final i0 = bestEnd - bestRun + 1;
      final seg = pit.sublist(i0, bestEnd + 1);
      final (b0, s0) = cts[i0];
      var rep = false;
      for (var j = 1; j < seg.length; j++) {
        if (_typeKey(seg[j]) == _typeKey(seg[j - 1])) rep = true;
      }
      final types = seg.map((e) => _typeKey(e).toUpperCase()).join(', ');
      final reach = b0 + bestRun >= 4 ? 'ball four' : 'the count ${b0 + bestRun}-$s0';
      notes.add(SeqNote(
        SeqPolarity.review,
        'count',
        'ball_run',
        '$bestRun straight balls ($types)${rep ? ' with a repeated pitch type' : ''} led to $reach. '
            "Location and intended pitch aren't tracked, so a poor decision can't be told apart from a missed spot.",
      ));
    }
    if (cvals.isNotEmpty) {
      final m = cvals.reduce((a, b) => a + b) / cvals.length;
      values['count'] = 0.5 + (m - 0.5) * _shrink(cvals.length, SeqConfig.kCount);
    } else {
      skip['count'] = 'No pitch before the last one to judge a count change.';
    }

    // ── 2. Setup & response ────────────────────────────────────────────
    final svals = <double>[];
    final setupNotes = <String, SeqNote>{};
    for (var i = 1; i < pit.length; i++) {
      final prev = pit[i - 1], cur = pit[i];
      final (b, s) = cts[i];
      final pt = _typeKey(prev), ct = _typeKey(cur);
      final rel = ct == pt ? 'S' : (_tier(ct) != _tier(pt) ? 'T' : 'D');
      double v;
      switch (prev.call) {
        case 'ss':
          v = rel == 'S' ? (s == 2 ? 0.90 : 0.85) : (rel == 'T' ? 0.62 : 0.60);
          if (rel == 'S') {
            notes.add(SeqNote(SeqPolarity.positive, 'setup', 'repeat_after_whiff',
                'Repeating the ${ct.toUpperCase()} was supported by the previous swing and miss.'));
          }
          break;
        case 'sl':
          v = rel == 'S' ? 0.55 : (rel == 'T' ? 0.72 : 0.66);
          if (rel == 'T') {
            notes.add(SeqNote(SeqPolarity.positive, 'setup', 'change_after_take',
                'Changed the look (${pt.toUpperCase()}→${ct.toUpperCase()}) after the batter took a strike.'));
          }
          break;
        case 'f':
          var fk = 0, fj = i - 1;
          while (fj >= 0 && pit[fj].call == 'f' && _typeKey(pit[fj]) == pt) {
            fk++;
            fj--;
          }
          if (fk >= 2) {
            v = rel == 'S' ? 0.30 : (rel == 'T' ? 0.75 : 0.68);
            if (rel == 'S') {
              setupNotes['same_after_fouls'] = SeqNote(SeqPolarity.review, 'setup', 'same_after_fouls',
                  '${ct.toUpperCase()} thrown again after $fk straight fouls on it — the batter may be timing it.');
            } else {
              notes.add(SeqNote(SeqPolarity.positive, 'setup', 'change_after_fouls',
                  'Changed pitch type after $fk straight fouls on the ${pt.toUpperCase()}.'));
            }
          } else {
            v = rel == 'S' ? 0.55 : (rel == 'T' ? 0.62 : 0.58);
          }
          break;
        case 'b':
          var bm = 0, bj = i - 1;
          while (bj >= 0 && pit[bj].call == 'b' && _typeKey(pit[bj]) == pt) {
            bm++;
            bj--;
          }
          if (rel == 'S') {
            v = bm >= 2 ? 0.30 : 0.48;
            if (bm >= 2) {
              setupNotes['repeat_after_misses'] = SeqNote(SeqPolarity.review, 'setup', 'repeat_after_misses',
                  '${ct.toUpperCase()} repeated after $bm straight balls with it ($b-$s); '
                      "location/intent aren't tracked, so execution vs. decision can't be separated.");
            }
          } else {
            v = rel == 'T' ? 0.58 : 0.55;
          }
          break;
        default:
          continue; // no meaningful response to set up from
      }
      svals.add(v);
    }
    notes.addAll(setupNotes.values);
    if (svals.isNotEmpty) {
      final m = svals.reduce((a, b) => a + b) / svals.length;
      values['setup'] = 0.5 + (m - 0.5) * _shrink(svals.length, SeqConfig.kSetup);
    } else {
      skip['setup'] = 'Needs at least two pitches with a response to react to.';
    }

    // ── 3. Batter matchup ───────────────────────────────────────────────
    final mvals = <double>[];
    final limitedTypes = <String>{};
    if (jersey == null) {
      skip['matchup'] = 'No batter jersey # recorded for this plate appearance.';
    } else {
      final bkey = '$team|$jersey';
      for (var i = 0; i < pit.length; i++) {
        final p = pit[i];
        final t = _typeKey(p);
        final (b, s) = cts[i];
        final bt = h.batterType[bkey]?[t];
        final pt = h.pitcherType[t];
        _Tally? refFor(bool Function(_Tally) ok) {
          if (pt != null && ok(pt)) return pt;
          if (ok(h.pitcherAll)) return h.pitcherAll;
          return null;
        }

        final refW = refFor((x) => x.swings >= SeqConfig.minRefSample);
        final refA = refFor((x) => x.ab >= SeqConfig.minRefSample);
        final refN = refFor((x) => x.n >= SeqConfig.minRefSample);
        // signal: (value01, sufficient, adjustedRate, sample)
        final sig = <String, (double, bool, double, int)>{};
        if (bt != null) {
          if (bt.swings >= SeqConfig.minSwings && refW != null) {
            final rr = refW.whiffs / refW.swings;
            final adj = (bt.whiffs + SeqConfig.kRate * rr) / (bt.swings + SeqConfig.kRate);
            sig['whiff'] = (_clamp01(0.5 + (adj - rr) / 0.5), bt.swings >= SeqConfig.sufficientSwings, adj, bt.swings);
          }
          if (bt.ab >= SeqConfig.minAb && refA != null && refA.ab > 0) {
            final rr = refA.hits / refA.ab;
            final adj = (bt.hits + SeqConfig.kRate * rr) / (bt.ab + SeqConfig.kRate);
            sig['baa'] = (_clamp01(0.5 - (adj - rr) / 0.5), bt.ab >= SeqConfig.sufficientAb, adj, bt.ab);
          }
          if (bt.n >= SeqConfig.minPitches && refN != null) {
            final rr = refN.called / refN.n;
            final adj = (bt.called + SeqConfig.kRate * rr) / (bt.n + SeqConfig.kRate);
            sig['called'] = (_clamp01(0.5 + (adj - rr) / 0.5), bt.n >= SeqConfig.sufficientPitches, adj, bt.n);
          }
        }
        // Which signals matter depends on what the count asks of the pitch.
        final Map<String, double> w;
        if (s == 2) {
          w = {'whiff': 0.6, 'baa': 0.4};
        } else if (countValue(b, s) <= SeqConfig.hitterNeedStrikeMax) {
          w = {'called': 0.5, 'baa': 0.5};
        } else {
          w = {'whiff': 0.4, 'called': 0.2, 'baa': 0.4};
        }
        final use = <String, double>{
          for (final e in w.entries)
            if (sig.containsKey(e.key)) e.key: e.value,
        };
        if (use.isEmpty) {
          limitedTypes.add(t);
          continue;
        }
        final tw = use.values.reduce((a, b) => a + b);
        var v = 0.0;
        for (final e in use.entries) {
          v += e.value * sig[e.key]!.$1;
        }
        mvals.add(v / tw);
        if (use.keys.any((k) => !sig[k]!.$2)) limitedTypes.add(t);
        final whiff = sig['whiff'];
        if (use.containsKey('whiff') && whiff != null && whiff.$2 && whiff.$1 >= 0.62) {
          notes.add(SeqNote(SeqPolarity.positive, 'matchup', 'whiff_high',
              'Batter has a high whiff rate vs ${t.toUpperCase()} (${(whiff.$3 * 100).round()}% adjusted, ${whiff.$4} swings).'));
        }
        final baa = sig['baa'];
        if (use.containsKey('baa') && baa != null && baa.$2 && baa.$1 <= 0.38) {
          notes.add(SeqNote(SeqPolarity.review, 'matchup', 'baa_high',
              'Batter has hit ${t.toUpperCase()} well (${baa.$3.toStringAsFixed(3)} adjusted BAA, ${baa.$4} AB).'));
        }
      }
      if (mvals.isNotEmpty) {
        values['matchup'] = mvals.reduce((a, b) => a + b) / mvals.length;
        limited['matchup'] = limitedTypes.isNotEmpty;
      } else {
        skip['matchup'] = 'Not enough prior results for this batter against these pitch types.';
      }
      if (limitedTypes.isNotEmpty) {
        final names = (limitedTypes.toList()..sort()).map((e) => e.toUpperCase()).join(', ');
        notes.add(SeqNote(SeqPolarity.limited, 'matchup', 'limited_matchup',
            'Insufficient batter-specific history for $names.'));
      }
    }

    // ── 4. Predictability (deduct-only; each check needs enough data) ──
    final pen = <double>[];
    var predEvaluable = false;
    if (pit.length >= SeqConfig.streakLen) {
      predEvaluable = true;
      var i = 0;
      while (i < pit.length) {
        var j = i;
        while (j + 1 < pit.length && _typeKey(pit[j + 1]) == _typeKey(pit[i])) {
          j++;
        }
        final len = j - i + 1;
        if (len >= SeqConfig.streakLen) {
          var succ = 0, fail = 0;
          for (var q = i; q <= j; q++) {
            final sc = _pitchSuccess(pit[q], cts[q].$2);
            if (sc > 0) succ++;
            if (sc < 0) fail++;
          }
          final dec = succ + fail;
          final t = _typeKey(pit[i]).toUpperCase();
          if (dec >= 2 && fail / dec >= 0.5) {
            pen.add(SeqConfig.streakPenalty);
            notes.add(SeqNote(SeqPolarity.review, 'predict', 'streak_ineffective',
                '$t thrown $len times in a row without success.'));
          } else if (dec >= 2 && succ / dec >= 0.6) {
            notes.add(SeqNote(SeqPolarity.positive, 'predict', 'streak_effective',
                'Repeated $t stayed effective ($succ of $dec decisive pitches successful).'));
          }
        }
        i = j + 1;
      }
    }
    for (var i = 0; i < pit.length; i++) {
      final (b, s) = cts[i];
      final ck = '$b-$s';
      final usage = h.countUsage[ck];
      if (usage == null) continue;
      final tot = usage.values.fold<int>(0, (a, c) => a + c);
      if (tot < SeqConfig.minRefSample) continue;
      predEvaluable = true;
      final t = _typeKey(pit[i]);
      final share = (usage[t] ?? 0) / tot;
      final res = h.countResult[ck]?[t] ?? const [0, 0];
      final dec = res[0] + res[1];
      if (share >= SeqConfig.usageShare && dec >= SeqConfig.usageDecisive && res[1] / dec >= 0.5) {
        pen.add(0.25 * (share - SeqConfig.usageShare) / (1 - SeqConfig.usageShare) + 0.10);
        notes.add(SeqNote(SeqPolarity.review, 'predict', 'usage_ineffective',
            '${t.toUpperCase()} is used ${(share * 100).round()}% of the time at $b-$s and has been working poorly there.'));
      }
    }
    if (pit.length >= 3 && completed) {
      final pat = pit.take(3).map(_typeKey).join('>');
      final all = h.patternAll[pat];
      if (all != null && all[0] >= SeqConfig.patternMinAll) {
        predEvaluable = true;
        if (all[1] / all[0] >= 0.5) {
          pen.add(SeqConfig.patternAllPenalty);
          notes.add(SeqNote(SeqPolarity.review, 'predict', 'pattern_all',
              'This opening pattern has produced batter-favorable results ${all[1]} of ${all[0]} times.'));
        }
      }
      if (jersey != null) {
        final bp = h.patternBatter['$team|$jersey|$pat'];
        if (bp != null && bp[0] >= SeqConfig.patternMinBatter) {
          predEvaluable = true;
          if (bp[1] / bp[0] >= 0.6) {
            pen.add(SeqConfig.patternBatterPenalty);
            notes.add(SeqNote(SeqPolarity.review, 'predict', 'pattern_batter',
                'The same opening pattern has produced batter-favorable results ${bp[1]} of ${bp[0]} times against this batter.'));
          }
        }
      }
    }
    if (predEvaluable) {
      values['predict'] = _clamp01(1 - pen.fold<double>(0, (a, b) => a + b));
    } else {
      skip['predict'] = 'Needs a 3+ pitch at-bat or enough pitch-by-count history.';
    }

    // ── 5. Result (credited once; balls in play discounted) ─────────────
    if (completed) {
      final raw = SeqConfig.resultValue[finalOutcome];
      if (raw != null) {
        final inPlay = SeqConfig.inPlayOutcomes.contains(finalOutcome);
        values['result'] = inPlay ? 0.5 + (raw - 0.5) * SeqConfig.inPlayShrink : raw;
        if (finalOutcome == 'k' || finalOutcome == 'kl') {
          notes.add(const SeqNote(SeqPolarity.positive, 'result', 'result_k', 'Plate appearance ended in a strikeout.'));
        } else if (finalOutcome == 'bb') {
          notes.add(const SeqNote(SeqPolarity.review, 'result', 'result_bb', 'Plate appearance ended in a walk.'));
        } else if (inPlay) {
          notes.add(const SeqNote(SeqPolarity.neutral, 'result', 'result_bip',
              'Ended on contact — weighted at 60% because balls in play are noisy; this does not by itself judge the pitch choices.'));
        }
      } else {
        skip['result'] = 'Outcome not recognised.';
      }
    } else {
      skip['result'] = 'Plate appearance not finished.';
    }

    // ── combine ──────────────────────────────────────────────────────────
    final coverage = values.keys.fold<double>(0, (a, k) => a + SeqWeights.byKey[k]!);
    double? score;
    String? unscoredReason;
    final comps = <String, SeqComponent>{};
    if (values.length < SeqConfig.minComponents || coverage < SeqConfig.minCoverage) {
      unscoredReason = 'Not enough information to score this at-bat (only ${values.length} of 5 components could be evaluated).';
    } else {
      var sum = 0.0;
      for (final k in values.keys) {
        sum += SeqWeights.byKey[k]! * values[k]!;
      }
      score = sum * 100.0 / coverage;
    }
    for (final k in SeqWeights.keys) {
      final v = values[k];
      comps[k] = SeqComponent(
        key: k,
        value: v,
        limitedConfidence: limited[k] ?? false,
        earned: (v != null && score != null) ? 100.0 * SeqWeights.byKey[k]! * v / coverage : null,
        maxPoints: (v != null && score != null) ? 100.0 * SeqWeights.byKey[k]! / coverage : null,
        skipReason: v == null ? skip[k] : null,
      );
    }

    // De-duplicate identical notes, keeping order.
    final seen = <String>{};
    final uniq = <SeqNote>[
      for (final n in notes)
        if (seen.add('${n.code}|${n.text}')) n,
    ];

    return PaScore(
      key: '${first.game}|${first.gameNumber}|${first.season}|${first.id}',
      team: team,
      gameNumber: first.gameNumber,
      season: first.season,
      jersey: jersey,
      completed: completed,
      finalOutcome: finalOutcome,
      pitches: pit,
      countsBefore: cts,
      score: score,
      unscoredReason: unscoredReason,
      coverage: coverage,
      components: comps,
      notes: uniq,
      order: order,
    );
  }

  // ─────────────────────────── history update ───────────────────────────

  static void _updateHistory(List<PitchEvent> pit, _History h) {
    final cts = countsBefore(pit);
    final jersey = _jerseyOf(pit);
    final team = pit.first.game;
    for (var i = 0; i < pit.length; i++) {
      final p = pit[i];
      final t = _typeKey(p);
      if (jersey != null) {
        h.batterType.putIfAbsent('$team|$jersey', () => {}).putIfAbsent(t, () => _Tally()).add(p);
      }
      h.pitcherType.putIfAbsent(t, () => _Tally()).add(p);
      h.pitcherAll.add(p);
      final ck = '${cts[i].$1}-${cts[i].$2}';
      final u = h.countUsage.putIfAbsent(ck, () => {});
      u[t] = (u[t] ?? 0) + 1;
      final sc = _pitchSuccess(p, cts[i].$2);
      final r = h.countResult.putIfAbsent(ck, () => {}).putIfAbsent(t, () => [0, 0]);
      if (sc > 0) r[0]++;
      if (sc < 0) r[1]++;
    }
    if (pit.length >= 3 && _isTerminal(pit.last)) {
      final pat = pit.take(3).map(_typeKey).join('>');
      final fav = SeqConfig.batterFavorable.contains(pit.last.outcome) ? 1 : 0;
      final a = h.patternAll.putIfAbsent(pat, () => [0, 0]);
      a[0]++;
      a[1] += fav;
      if (jersey != null) {
        final b = h.patternBatter.putIfAbsent('$team|$jersey|$pat', () => [0, 0]);
        b[0]++;
        b[1] += fav;
      }
    }
  }
}
