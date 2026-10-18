import '../models/pitcher.dart';
import 'supabase_config.dart';

/// Reads and changes the pitcher profiles under the signed-in account.
/// Creating / editing / removing goes through server functions that validate
/// the input and enforce the plan's pitcher limit.
class PitcherService {
  Future<List<Pitcher>> loadPitchers() async {
    final rows = await sb
        .from('pitchers')
        .select()
        .isFilter('archived_at', null)
        .order('created_at');
    return (rows as List)
        .map((r) => Pitcher.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Safety net for accounts that somehow have no pitcher yet.
  Future<void> ensureDefaultPitcher() async {
    await sb.rpc('ensure_default_pitcher');
  }

  Future<String> addPitcher(PitcherDraft d) async {
    final r = await sb.rpc('add_pitcher', params: {
      'p_display_name': d.name.trim(),
      'p_username': d.username.trim(),
      'p_sports': (d.sports.toList()..sort()),
      'p_throws_hand': d.hand,
    });
    return r.toString();
  }

  Future<void> updatePitcher(String id, PitcherDraft d) async {
    await sb.rpc('update_pitcher', params: {
      'p_id': id,
      'p_display_name': d.name.trim(),
      'p_username': d.username.trim(),
      'p_sports': (d.sports.toList()..sort()),
      'p_throws_hand': d.hand,
    });
  }

  Future<void> archivePitcher(String id) async {
    await sb.rpc('archive_pitcher', params: {'p_id': id});
  }

  /// Plain-language message for an error thrown by the calls above.
  static String friendlyError(Object e) {
    final msg = e is PostgrestException ? e.message : e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('duplicate key') || lower.contains('pitchers_owner_username_uq')) {
      return 'Another pitcher on this account already uses that username.';
    }
    if (lower.contains('could not find the function') || lower.contains('pgrst202')) {
      return 'The database update for pitcher profiles has not been installed yet.';
    }
    return msg.replaceAll(RegExp(r'^Exception:\s*'), '');
  }
}
