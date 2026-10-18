// App-wide state for the Bullpen and Pitching Analysis tabs.
//
// Every change updates memory first (so the UI is instant) and is then saved
// right away - there is no "save session" step. If a save fails the data
// stays on screen, [syncError] is set, and [retrySync] re-sends the open
// session.

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'bullpen_models.dart';
import 'plan_models.dart';
import 'repository.dart';

class BullpenStore extends ChangeNotifier {
  final BullpenRepository repo;
  final String Function() _userIdOf;

  /// Read each time (not captured once) so a store created a moment before
  /// sign-in finished still talks to Supabase as the right person.
  String get userId => _userIdOf();
  final DateTime Function() _now;
  final String Function() _newId;

  BullpenStore({
    required this.repo,
    String? userId,
    String Function()? userIdProvider,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _userIdOf = userIdProvider ?? (() => userId ?? ''),
        _now = clock ?? DateTime.now,
        _newId = idGenerator ?? (() => const Uuid().v4());

  List<BullpenSession> sessions = [];
  List<BullpenPitch> pitches = [];
  List<ChallengeAttempt> attempts = [];

  /// The latest plan the person generated/edited on Pitching Analysis.
  BullpenPlan? plan;

  /// A plan sent to the Bullpen tab, waiting to be used by the next bullpen.
  BullpenPlan? pendingPlan;

  /// Tab the shell should switch to (set by "Send to Bullpen").
  String? navigateRequest;

  bool loaded = false;
  bool loading = false;
  bool _disposed = false;

  /// Set when the tables couldn't be read (e.g. the SQL hasn't been run yet).
  String? loadError;

  /// Set when the last save failed.
  String? syncError;

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      if (userId.isEmpty) throw StateError('not signed in yet');
      sessions = await repo.loadSessions(userId);
      pitches = await repo.loadPitches(userId);
      attempts = await repo.loadAttempts(userId);
      try {
        plan = await repo.loadPlan(userId);
      } catch (_) {
        plan = null; // plan is optional; never block the tab on it
      }
    } catch (e) {
      loadError = explainBullpenError(e);
    }
    loaded = true;
    loading = false;
    notifyListeners();
  }

  /// Called when a different pitcher becomes active: forgets everything held
  /// for the previous pitcher, then loads the new pitcher's data.
  Future<void> reloadForPitcher() async {
    sessions = [];
    pitches = [];
    attempts = [];
    plan = null;
    pendingPlan = null;
    navigateRequest = null;
    syncError = null;
    loaded = false;
    notifyListeners();
    await load();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ── Reads ──────────────────────────────────────────────────────

  BullpenSession? get activeSession {
    final open = sessions.where((s) => s.isOpen).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return open.isEmpty ? null : open.first;
  }

  List<BullpenPitch> pitchesFor(String sessionId) =>
      pitches.where((p) => p.sessionId == sessionId).toList()..sort((a, b) => a.seq.compareTo(b.seq));

  List<BullpenSession> get finishedSessions =>
      sessions.where((s) => s.status == SessionStatus.finished).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  /// Hand used in the most recent bullpen, so people don't re-pick it.
  String get lastHand {
    if (sessions.isEmpty) return 'R';
    final latest = [...sessions]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return latest.first.throwsHand;
  }

  // ── Saving ─────────────────────────────────────────────────────

  Future<void> _guard(Future<void> Function() save) async {
    try {
      await save();
      syncError = null;
    } catch (e) {
      syncError = 'Could not save to the server: ${explainBullpenError(e)} Your data is still here; tap Retry.';
    }
    notifyListeners();
  }

  Future<void> retrySync() async {
    final s = activeSession;
    if (s != null) {
      await _guard(() async {
        await repo.saveSession(s);
        for (final p in pitchesFor(s.id)) {
          await repo.savePitch(p);
        }
      });
    } else {
      syncError = null;
      notifyListeners();
    }
  }

  // ── Standard bullpen ───────────────────────────────────────────

  Future<BullpenSession> startSession({
    required BullpenType type,
    String? customName,
    required String hand,
    BullpenPlan? usePlan,
  }) async {
    final s = BullpenSession(
      id: _newId(),
      userId: userId,
      type: type,
      customName: customName,
      throwsHand: hand,
      startedAt: _now(),
      plan: usePlan?.toJson(),
    );
    sessions = [...sessions, s];
    notifyListeners();
    await _guard(() => repo.saveSession(s));
    return s;
  }

  void _replaceSession(BullpenSession s) {
    sessions = [for (final x in sessions) x.id == s.id ? s : x];
  }

  Future<BullpenPitch?> addPitch({
    required String pitchType,
    ZoneTarget? target,
    required double actualX,
    required double actualY,
    double? velocity,
    String? result,
    String? notes,
    int? planSetIndex,
  }) async {
    final s = activeSession;
    if (s == null || s.status != SessionStatus.active) return null;
    final seq = pitchesFor(s.id).fold<int>(0, (m, p) => p.seq > m ? p.seq : m) + 1;
    final p = BullpenPitch(
      id: _newId(),
      sessionId: s.id,
      userId: userId,
      seq: seq,
      pitchType: pitchType,
      target: target,
      actualX: actualX,
      actualY: actualY,
      velocity: velocity,
      result: result,
      notes: (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      timestamp: _now(),
      planSetIndex: planSetIndex,
    );
    pitches = [...pitches, p];
    notifyListeners();
    await _guard(() => repo.savePitch(p));
    return p;
  }

  Future<void> undoLast() async {
    final s = activeSession;
    if (s == null) return;
    final list = pitchesFor(s.id);
    if (list.isEmpty) return;
    await deletePitch(list.last.id);
  }

  Future<void> updatePitch(BullpenPitch p) async {
    pitches = [for (final x in pitches) x.id == p.id ? p : x];
    notifyListeners();
    await _guard(() => repo.savePitch(p));
  }

  Future<void> deletePitch(String id) async {
    final gone = pitches.where((p) => p.id == id).toList();
    if (gone.isEmpty) return;
    final sessionId = gone.first.sessionId;
    pitches = pitches.where((p) => p.id != id).toList();
    // Keep the numbering 1..n with no gaps.
    final renumbered = <BullpenPitch>[];
    var n = 1;
    for (final p in pitchesFor(sessionId)) {
      if (p.seq != n) renumbered.add(p.copyWith(seq: n));
      n++;
    }
    if (renumbered.isNotEmpty) {
      pitches = [for (final x in pitches) renumbered.firstWhere((r) => r.id == x.id, orElse: () => x)];
    }
    notifyListeners();
    await _guard(() async {
      await repo.deletePitch(id);
      for (final r in renumbered) {
        await repo.savePitch(r);
      }
    });
  }

  Future<void> pause() async {
    final s = activeSession;
    if (s == null || s.status != SessionStatus.active) return;
    final u = s.copyWith(status: SessionStatus.paused, pausedAt: _now());
    _replaceSession(u);
    notifyListeners();
    await _guard(() => repo.saveSession(u));
  }

  Future<void> resume() async {
    final s = activeSession;
    if (s == null || s.status != SessionStatus.paused) return;
    final extra = s.pausedAt == null ? 0 : _now().difference(s.pausedAt!).inMilliseconds;
    final u = s.copyWith(status: SessionStatus.active, pausedMs: s.pausedMs + extra, clearPausedAt: true);
    _replaceSession(u);
    notifyListeners();
    await _guard(() => repo.saveSession(u));
  }

  /// Ends the bullpen. A bullpen with no pitches is discarded instead of
  /// cluttering history; returns null in that case.
  Future<BullpenSession?> finish() async {
    final s = activeSession;
    if (s == null) return null;
    if (pitchesFor(s.id).isEmpty) {
      await deleteSession(s.id);
      return null;
    }
    var pausedMs = s.pausedMs;
    if (s.status == SessionStatus.paused && s.pausedAt != null) {
      pausedMs += _now().difference(s.pausedAt!).inMilliseconds;
    }
    final u = s.copyWith(status: SessionStatus.finished, endedAt: _now(), pausedMs: pausedMs, clearPausedAt: true);
    _replaceSession(u);
    notifyListeners();
    await _guard(() => repo.saveSession(u));
    return u;
  }

  Future<void> deleteSession(String id) async {
    sessions = sessions.where((s) => s.id != id).toList();
    pitches = pitches.where((p) => p.sessionId != id).toList();
    notifyListeners();
    await _guard(() => repo.deleteSession(id));
  }

  Future<void> updateSessionNotes(String id, String notes) async {
    final s = sessions.firstWhere((x) => x.id == id);
    final u = s.copyWith(notes: notes);
    _replaceSession(u);
    notifyListeners();
    await _guard(() => repo.saveSession(u));
  }

  // ── Game Mode ──────────────────────────────────────────────────

  Future<void> recordAttempt(ChallengeAttempt a) async {
    attempts = [...attempts, a];
    notifyListeners();
    await _guard(() => repo.saveAttempt(a));
  }

  // ── Plans ──────────────────────────────────────────────────────

  Future<void> savePlan(BullpenPlan? p) async {
    plan = p;
    notifyListeners();
    await _guard(() => repo.savePlan(userId, p));
  }

  /// "Send to Bullpen": hands the plan to the Bullpen tab and asks the shell to open it.
  void sendPlanToBullpen(BullpenPlan p) {
    pendingPlan = p;
    navigateRequest = 'Bullpen';
    notifyListeners();
  }

  void requestNavigate(String tab) {
    navigateRequest = tab;
    notifyListeners();
  }

  void clearNavigateRequest() {
    navigateRequest = null;
  }

  BullpenPlan? takePendingPlan() {
    final p = pendingPlan;
    pendingPlan = null;
    return p;
  }
}


/// Turns a raw Supabase/Postgres error into a sentence that says what to fix,
/// followed by the original text so nothing is hidden.
String explainBullpenError(Object e) {
  final raw = '$e';
  final low = raw.toLowerCase();
  String hint;
  if (low.contains('pgrst205') || low.contains('schema cache') || low.contains('does not exist') || low.contains('could not find the table')) {
    hint = 'The Bullpen tables were not found. Run supabase_bullpen_schema.sql in the Supabase SQL editor '
        '(its last line reloads the API schema), wait a few seconds, then retry.';
  } else if (low.contains('42501') || low.contains('permission denied') || low.contains('row-level security')) {
    hint = 'Supabase refused access (permissions / row-level security). Re-run supabase_bullpen_schema.sql so the policies exist.';
  } else if (low.contains('invalid input syntax for type uuid')) {
    hint = 'The signed-in user id was not ready. Sign out and back in, then retry.';
  } else if (low.contains('not signed in')) {
    hint = 'Still signing in. Retry in a moment.';
  } else if (low.contains('socketexception') || low.contains('failed host lookup') || low.contains('clientexception')) {
    hint = 'Could not reach Supabase. Check the internet connection and retry.';
  } else {
    hint = 'Something went wrong talking to Supabase.';
  }
  return '$hint\n\nDetails: $raw';
}
