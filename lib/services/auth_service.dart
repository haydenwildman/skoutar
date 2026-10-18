import '../models/pitcher.dart';
import '../models/user.dart';
import 'legal_config.dart';
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
  /// `profiles` row + the server-computed entitlement. Throws if there's no
  /// logged-in session.
  Future<AppUser> _currentAppUser() async {
    final authUser = sb.auth.currentUser!;
    var profile =
        await sb.from('profiles').select().eq('id', authUser.id).single();

    // Self-serve sign-ups record their choices (sports, throwing hand, plan,
    // terms version) in auth metadata. The first time they have a session, the
    // server validates those and writes them to the profile / subscription.
    final meta = authUser.userMetadata ?? const <String, dynamic>{};
    if (profile['terms_accepted_at'] == null && meta['terms_version'] != null) {
      try {
        await sb.rpc('complete_signup');
        profile = await sb.from('profiles').select().eq('id', authUser.id).single();
      } catch (_) {
        // Migration not installed yet, or validation failed: keep the account
        // usable at the basic level; nothing is granted.
      }
    }

    // Server decides what this person is entitled to (live trial/subscription).
    Map<String, dynamic>? entitlement;
    try {
      final r = await sb.rpc('get_my_entitlement');
      if (r is Map) entitlement = Map<String, dynamic>.from(r);
    } catch (_) {
      entitlement = null; // function not installed yet -> basic access
    }

    return AppUser.fromSupabase(
      id: authUser.id,
      email: authUser.email ?? '',
      profile: profile,
      entitlement: entitlement,
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
    } on PostgrestException catch (e) {
      // The password was accepted but loading the account data failed (for
      // example, no profile row exists yet). Say so instead of blaming the password.
      try {
        await sb.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      return AuthResult(
        success: false,
        message: 'Your login worked, but your account data could not be loaded '
            '(code ${e.code ?? 'unknown'}). Please contact support.',
      );
    } catch (e) {
      try {
        await sb.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      return AuthResult(
        success: false,
        message: 'Could not log in. Check your connection and try again.',
      );
    }
  }

  Future<void> logout() => sb.auth.signOut();

  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _usernameRe = RegExp(r'^[A-Za-z0-9_]+$');

  static bool isValidEmail(String s) => _emailRe.hasMatch(s.trim());

  /// Returns an error message, or null if the username looks valid.
  static String? validateUsername(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return 'Username is required.';
    if (u.length < LegalConfig.usernameMin || u.length > LegalConfig.usernameMax) {
      return 'Username must be ${LegalConfig.usernameMin}-${LegalConfig.usernameMax} characters.';
    }
    if (!_usernameRe.hasMatch(u)) return 'Username: letters, numbers, underscore only.';
    return null;
  }

  /// Returns an error message, or null if the password is acceptable.
  static String? validatePassword(String p) {
    if (p.length < LegalConfig.minPasswordLength) {
      return 'Password must be at least ${LegalConfig.minPasswordLength} characters.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      return 'Password needs at least one letter and one number.';
    }
    return null;
  }

  /// Self-serve sign-up. Supabase Auth stores the owner's password (hashed).
  /// The plan and pitcher profiles are saved in auth metadata and written to
  /// the database by the server function complete_signup(), which re-validates
  /// everything (including the plan's pitcher limit). Choosing a plan only
  /// records WHICH plan was picked: no payment is taken here.
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String confirmPassword,
    required List<PitcherDraft> pitchers,
    required String planId,
    required int pitcherLimit,
    required String termsVersion,
  }) async {
    if (!isValidEmail(email)) {
      return AuthResult(success: false, message: 'Enter a valid email address.');
    }
    final pErr = validatePassword(password);
    if (pErr != null) return AuthResult(success: false, message: pErr);
    if (password != confirmPassword) {
      return AuthResult(success: false, message: 'Passwords do not match.');
    }
    if (pitchers.isEmpty) {
      return AuthResult(success: false, message: 'Add at least one pitcher.');
    }
    if (pitchers.length > pitcherLimit) {
      return AuthResult(success: false, message: 'That plan allows up to $pitcherLimit pitchers.');
    }
    final seen = <String>{};
    for (final d in pitchers) {
      final err = d.validate();
      if (err != null) return AuthResult(success: false, message: err);
      if (!seen.add(d.username.trim().toLowerCase())) {
        return AuthResult(success: false, message: 'Each pitcher needs a different username.');
      }
    }
    try {
      final res = await sb.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          // The profile row (created by the existing sign-up trigger) still gets
          // a username: use the first pitcher's.
          'username': pitchers.first.username.trim(),
          'plan_id': planId,
          'terms_version': termsVersion,
          'pitchers': pitchers.map((d) => d.toJson()).toList(),
        },
      );
      final user = res.user;
      if (user == null) {
        return AuthResult(success: false, message: 'Sign up failed. Please try again.');
      }
      // Supabase hides whether an email is registered; an empty identities list
      // means the address already has an account.
      if (user.identities != null && user.identities!.isEmpty) {
        return AuthResult(
          success: false,
          message: 'An account may already exist for that email. Try logging in or resetting your password.',
        );
      }
      if (res.session != null) {
        // Email confirmation is off: finish setup now, then return to login so
        // there is one consistent path in.
        try {
          await sb.rpc('complete_signup');
        } catch (_) {}
        await sb.auth.signOut(scope: SignOutScope.local);
        return AuthResult(success: true, message: 'Account created! You can log in now.');
      }
      return AuthResult(
        success: true,
        message: 'Account created! Check your email to confirm, then log in.',
      );
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('database error')) {
        return AuthResult(
          success: false,
          message: 'That email or username is already in use, or sign-up is not fully set up yet.',
        );
      }
      return AuthResult(success: false, message: e.message);
    } catch (_) {
      return AuthResult(success: false, message: 'Could not create the account. Check your connection and try again.');
    }
  }

  /// Sends a password-reset email. The message is the same whether or not the
  /// address has an account, so this can't be used to discover who is registered.
  Future<AuthResult> sendPasswordReset(String email) async {
    if (!isValidEmail(email)) {
      return AuthResult(success: false, message: 'Enter a valid email address.');
    }
    try {
      await sb.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      // Surface rate-limit style errors; hide "unknown user" style ones.
      if (e.statusCode == '429' || e.message.toLowerCase().contains('rate')) {
        return AuthResult(success: false, message: 'Too many requests. Please wait a few minutes and try again.');
      }
    } catch (_) {}
    return AuthResult(
      success: true,
      message: 'If an account exists for that email, a reset link is on its way.',
    );
  }

  /// Used by the "set new password" screen after following a reset link.
  Future<AuthResult> setNewPassword(String password) async {
    final err = validatePassword(password);
    if (err != null) return AuthResult(success: false, message: err);
    try {
      await sb.auth.updateUser(UserAttributes(password: password));
      return AuthResult(success: true, message: 'Password updated.');
    } on AuthException catch (e) {
      return AuthResult(success: false, message: e.message);
    } catch (_) {
      return AuthResult(success: false, message: 'Could not update the password.');
    }
  }

  /// Permanently deletes the signed-in person's data and login (server-side
  /// delete_my_account()). Refuses while a paid subscription is active.
  Future<AuthResult> deleteAccount() async {
    try {
      await sb.rpc('delete_my_account');
    } on PostgrestException catch (e) {
      return AuthResult(success: false, message: e.message);
    } catch (_) {
      return AuthResult(success: false, message: 'Could not delete the account. Please try again.');
    }
    try {
      await sb.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    return AuthResult(success: true, message: 'Your account has been deleted.');
  }

  // NOTE: the old client-side adminUpdateUser() (tier/status writes) was
  // removed on purpose. Tier and subscription status are now changed ONLY by
  // trusted server code (SQL functions / a payment webhook using the service
  // role), never by the app.
}
