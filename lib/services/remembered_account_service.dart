import 'package:shared_preferences/shared_preferences.dart';

/// Remembers WHICH account last signed in on this device so the login screen
/// can pre-fill it. Only the email address is stored - never a password, token
/// or any other secret - in the platform's normal local preferences (browser
/// local storage on web). Remembering an account is not signing in: the person
/// still has to enter their password unless Supabase already holds a valid
/// session of its own (see AuthService.restoreSession).
class RememberedAccountService {
  static const _key = 'skoutar.last_account_email';

  /// The last account that signed in on this device, or null.
  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null; // storage unavailable: the login screen just starts empty
    }
  }

  /// Replaces the remembered account (call only after a SUCCESSFUL sign-in).
  static Future<void> save(String email) async {
    final v = email.trim().toLowerCase();
    if (v.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, v);
    } catch (_) {}
  }

  /// Forgets the remembered account (shared devices / "use a different account").
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  // ── Last ACTIVE pitcher profile (Family / Team plans) ───────────────
  // Remembered per signed-in account, as a pitcher id only. This is a
  // convenience for which profile to show first; it grants no access (the
  // pitcher list still comes from Supabase under the signed-in account, and an
  // id that is not in that list is ignored).
  static String _pitcherKey(String accountId) => 'skoutar.last_pitcher.$accountId';

  static Future<String?> loadActivePitcher(String accountId) async {
    if (accountId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_pitcherKey(accountId))?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveActivePitcher(String accountId, String pitcherId) async {
    if (accountId.isEmpty || pitcherId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pitcherKey(accountId), pitcherId);
    } catch (_) {}
  }
}
