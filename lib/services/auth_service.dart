import '../models/user.dart';
import 'supabase_config.dart';

/// Result wrapper — mirrors the R `check_creds()` return shape
/// (list(result=TRUE/FALSE, message=..., user_info=...)).
class AuthResult {
  final bool success;
  final String? message;
  final AppUser? user;
  AuthResult({required this.success, this.message, this.user});
}

/// ══════════════════════════════════════════════════════════════
/// AUTH SERVICE
///
/// Backed by Supabase Auth + a `public.profiles` table (see
/// supabase_schema.sql), instead of the old local SHA-256 scheme.
/// Login is by EMAIL now (Supabase Auth's native identifier) — the
/// app-level "username" is a separate display field stored on the
/// profile row, unchanged elsewhere in the app.
///
/// Anything that would need the service-role key must never happen in this
/// (public, static-hosted) app — that key is never embedded here.
/// ══════════════════════════════════════════════════════════════
class AuthService {
  /// Builds an [AppUser] from the current Supabase session + a fetched
  /// `profiles` row. Throws if there's no logged-in session.
  Future<AppUser> _currentAppUser() async {
    final authUser = sb.auth.currentUser!;
    final profile =
        await sb.from('profiles').select().eq('id', authUser.id).single();
    return AppUser.fromSupabase(
      id: authUser.id,
      email: authUser.email ?? '',
      profile: profile,
    );
  }

  /// Call once at startup: if a Supabase session was persisted from a
  /// previous visit (same browser/device), rebuilds the [AppUser] from
  /// it so the person doesn't have to log in again. Returns null if
  /// there's no existing session.
  Future<AppUser?> restoreSession() async {
    if (sb.auth.currentSession == null) return null;
    try {
      return await _currentAppUser();
    } catch (_) {
      return null; // stale/invalid session — fall back to the login screen
    }
  }

  Future<AuthResult> login(String email, String password) async {
    try {
      final res = await sb.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.user == null) {
        return AuthResult(success: false, message: 'Invalid email or password.');
      }
      final user = await _currentAppUser();
      if (!user.isActive) {
        await sb.auth.signOut();
        return AuthResult(success: false, message: 'Account inactive. Contact support.');
      }
      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, message: e.message);
    } catch (e) {
      return AuthResult(success: false, message: 'Invalid email or password.');
    }
  }

  Future<void> logout() => sb.auth.signOut();

  /// Self-serve signup — creates a `basic` tier account directly (no
  /// admin needed). Supabase sends its own confirmation email unless
  /// "Confirm email" is turned off in Auth settings.
  Future<AuthResult> signUp({
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
    UserTier tier = UserTier.basic,
  }) async {
    if (username.trim().isEmpty) {
      return AuthResult(success: false, message: 'Username is required.');
    }
    if (email.trim().isEmpty) {
      return AuthResult(success: false, message: 'Email is required.');
    }
    if (password.length < 6) {
      return AuthResult(success: false, message: 'Password must be at least 6 characters.');
    }
    if (password != confirmPassword) {
      return AuthResult(success: false, message: 'Passwords do not match.');
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username.trim())) {
      return AuthResult(success: false, message: 'Username: letters, numbers, underscore only.');
    }
    try {
      final res = await sb.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': username.trim()}, // read by the handle_new_user trigger
      );
      if (res.user == null) {
        return AuthResult(success: false, message: 'Sign up failed.');
      }
      // The trigger creates the profiles row, but it fills pitcher_display_name
      // from username/email before we know if this call also wants a custom tier.
      if (tier != UserTier.basic) {
        await sb.from('profiles').update({'tier': tier.label}).eq('id', res.user!.id);
      }
      final msg = res.session == null
          ? 'Account created! Check your email to confirm, then log in.'
          : 'Account created! You can log in now.';
      return AuthResult(success: true, message: msg);
    } on AuthException catch (e) {
      return AuthResult(success: false, message: e.message);
    }
  }

  // ── USER TIER / STATUS ───────────────────────────────────────
  // Plain table write — RLS decides who may do it. Kept for the billing
  // integration (see BillingService), which syncs a subscriber's own
  // tier/status here once a payment provider is wired up.

  Future<void> adminUpdateUser(
    String userId, {
    UserTier? tier,
    SubStatus? status,
  }) async {
    final patch = <String, dynamic>{};
    if (tier != null) patch['tier'] = tier.label;
    if (status != null) patch['status'] = status.label;
    if (patch.isEmpty) return;
    await sb.from('profiles').update(patch).eq('id', userId);
  }
}
