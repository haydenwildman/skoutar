import 'bullpen_models.dart';

/// What a recommended bullpen is meant to improve.
enum PlanFocus { command, pitchDevelopment, sequencing, consistency, general }

extension PlanFocusX on PlanFocus {
  String get label => switch (this) {
        PlanFocus.command => 'Command',
        PlanFocus.pitchDevelopment => 'Pitch Development',
        PlanFocus.sequencing => 'Sequencing',
        PlanFocus.consistency => 'Consistency',
        PlanFocus.general => 'General Bullpen',
      };

  /// The bullpen type a plan with this focus is started as.
  BullpenType get bullpenType => switch (this) {
        PlanFocus.command => BullpenType.command,
        PlanFocus.pitchDevelopment => BullpenType.pitchDevelopment,
        PlanFocus.sequencing => BullpenType.sequencing,
        PlanFocus.consistency => BullpenType.command,
        PlanFocus.general => BullpenType.general,
      };
}

/// One block of the plan: N repetitions of one pitch at one target.
class PlanSet {
  final String pitchType;
  final int reps;
  final ZoneTarget target;

  /// What this set is designed to improve (generated from the data, editable).
  final String purpose;

  const PlanSet({required this.pitchType, required this.reps, required this.target, required this.purpose});

  PlanSet copyWith({String? pitchType, int? reps, ZoneTarget? target, String? purpose}) => PlanSet(
        pitchType: pitchType ?? this.pitchType,
        reps: reps ?? this.reps,
        target: target ?? this.target,
        purpose: purpose ?? this.purpose,
      );

  Map<String, dynamic> toJson() => {
        'pitchType': pitchType,
        'reps': reps,
        'target': target.toJson(),
        'purpose': purpose,
      };

  factory PlanSet.fromJson(Map<String, dynamic> j) => PlanSet(
        pitchType: j['pitchType'] as String,
        reps: (j['reps'] as num).toInt(),
        target: ZoneTarget.fromJson((j['target'] as Map).cast<String, dynamic>()),
        purpose: (j['purpose'] as String?) ?? '',
      );
}

class BullpenPlan {
  final PlanFocus focus;
  final List<PlanSet> sets;

  /// Plain-language reasons the plan looks the way it does (from the data).
  final List<String> rationale;
  final DateTime createdAt;

  const BullpenPlan({required this.focus, required this.sets, this.rationale = const [], required this.createdAt});

  int get totalReps => sets.fold(0, (a, s) => a + s.reps);

  BullpenPlan copyWith({PlanFocus? focus, List<PlanSet>? sets}) => BullpenPlan(
        focus: focus ?? this.focus,
        sets: sets ?? this.sets,
        rationale: rationale,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'focus': focus.name,
        'sets': sets.map((s) => s.toJson()).toList(),
        'rationale': rationale,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BullpenPlan.fromJson(Map<String, dynamic> j) => BullpenPlan(
        focus: PlanFocus.values.firstWhere((f) => f.name == j['focus'], orElse: () => PlanFocus.general),
        sets: ((j['sets'] as List?) ?? const []).map((e) => PlanSet.fromJson((e as Map).cast<String, dynamic>())).toList(),
        rationale: ((j['rationale'] as List?) ?? const []).cast<String>(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
