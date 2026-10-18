// Storage for bullpen data. Uses the app's existing Supabase project and
// auth. Every row carries the account owner's id (`user_id`, checked by Row
// Level Security - see supabase_bullpen_schema.sql) AND the pitcher's id
// (`pitcher_id`). The "userId" parameters/fields below hold the PITCHER id. Kept behind an
// interface so the rules and screens can be tested without a network.

import '../services/supabase_config.dart';
import 'bullpen_models.dart';
import 'plan_models.dart';

abstract class BullpenRepository {
  Future<List<BullpenSession>> loadSessions(String userId);
  Future<List<BullpenPitch>> loadPitches(String userId);
  Future<List<ChallengeAttempt>> loadAttempts(String userId);
  Future<void> saveSession(BullpenSession s);
  Future<void> savePitch(BullpenPitch p);
  Future<void> deletePitch(String id);

  /// Also removes the session's pitches.
  Future<void> deleteSession(String id);
  Future<void> saveAttempt(ChallengeAttempt a);
  Future<BullpenPlan?> loadPlan(String userId);
  Future<void> savePlan(String userId, BullpenPlan? plan);
}

class SupabaseBullpenRepository implements BullpenRepository {
  static const _page = 1000;

  Future<List<Map<String, dynamic>>> _all(String table, String userId, String order) async {
    final out = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final rows = await sb
          .from(table)
          .select()
          .eq('pitcher_id', userId)
          .order(order)
          .range(from, from + _page - 1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      out.addAll(list);
      if (list.length < _page) break;
      from += _page;
    }
    return out;
  }

  @override
  Future<List<BullpenSession>> loadSessions(String userId) async =>
      (await _all('bullpen_sessions', userId, 'started_at')).map(BullpenSession.fromRow).toList();

  @override
  Future<List<BullpenPitch>> loadPitches(String userId) async =>
      (await _all('bullpen_pitches', userId, 'ts')).map(BullpenPitch.fromRow).toList();

  @override
  Future<List<ChallengeAttempt>> loadAttempts(String userId) async =>
      (await _all('challenge_attempts', userId, 'ended_at')).map(ChallengeAttempt.fromRow).toList();

  /// Rows are stamped with the signed-in ACCOUNT id as user_id; the model's own
  /// userId (the pitcher id) goes to pitcher_id.
  Map<String, dynamic> _owned(Map<String, dynamic> row) =>
      {...row, 'user_id': sb.auth.currentUser!.id};

  @override
  Future<void> saveSession(BullpenSession s) => sb.from('bullpen_sessions').upsert(_owned(s.toRow()));

  @override
  Future<void> savePitch(BullpenPitch p) => sb.from('bullpen_pitches').upsert(_owned(p.toRow()));

  @override
  Future<void> deletePitch(String id) => sb.from('bullpen_pitches').delete().eq('id', id);

  @override
  Future<void> deleteSession(String id) async {
    await sb.from('bullpen_pitches').delete().eq('session_id', id);
    await sb.from('bullpen_sessions').delete().eq('id', id);
  }

  @override
  Future<void> saveAttempt(ChallengeAttempt a) => sb.from('challenge_attempts').upsert(_owned(a.toRow()));

  // The plan is a small blob, so it lives in the pitcher's settings jsonb
  // (same place as custom pitch types) - no extra table needed.
  @override
  Future<BullpenPlan?> loadPlan(String userId) async {
    final row = await sb.from('pitchers').select('settings').eq('id', userId).single();
    final settings = (row['settings'] as Map<String, dynamic>?) ?? {};
    final j = settings['bullpenPlan'];
    return j is Map ? BullpenPlan.fromJson(j.cast<String, dynamic>()) : null;
  }

  @override
  Future<void> savePlan(String userId, BullpenPlan? plan) async {
    final row = await sb.from('pitchers').select('settings').eq('id', userId).single();
    final settings = Map<String, dynamic>.from((row['settings'] as Map<String, dynamic>?) ?? {});
    if (plan == null) {
      settings.remove('bullpenPlan');
    } else {
      settings['bullpenPlan'] = plan.toJson();
    }
    await sb.from('pitchers').update({'settings': settings}).eq('id', userId);
  }
}

/// In-memory stand-in used by tests (and handy for demos).
class InMemoryBullpenRepository implements BullpenRepository {
  final Map<String, BullpenSession> sessions = {};
  final Map<String, BullpenPitch> pitches = {};
  final Map<String, ChallengeAttempt> attempts = {};
  BullpenPlan? plan;

  /// When true every write throws, to test failure handling.
  bool failWrites = false;

  void _check() {
    if (failWrites) throw Exception('write failed');
  }

  @override
  Future<List<BullpenSession>> loadSessions(String userId) async =>
      sessions.values.where((s) => s.userId == userId).toList();
  @override
  Future<List<BullpenPitch>> loadPitches(String userId) async =>
      pitches.values.where((p) => p.userId == userId).toList();
  @override
  Future<List<ChallengeAttempt>> loadAttempts(String userId) async =>
      attempts.values.where((a) => a.userId == userId).toList();
  @override
  Future<void> saveSession(BullpenSession s) async {
    _check();
    sessions[s.id] = s;
  }

  @override
  Future<void> savePitch(BullpenPitch p) async {
    _check();
    pitches[p.id] = p;
  }

  @override
  Future<void> deletePitch(String id) async {
    _check();
    pitches.remove(id);
  }

  @override
  Future<void> deleteSession(String id) async {
    _check();
    pitches.removeWhere((_, p) => p.sessionId == id);
    sessions.remove(id);
  }

  @override
  Future<void> saveAttempt(ChallengeAttempt a) async {
    _check();
    attempts[a.id] = a;
  }

  @override
  Future<BullpenPlan?> loadPlan(String userId) async => plan;
  @override
  Future<void> savePlan(String userId, BullpenPlan? p) async {
    _check();
    plan = p;
  }
}
