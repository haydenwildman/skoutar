/// ══════════════════════════════════════════════════════════════
/// LEGAL + ACCOUNT RULES — one place to edit.
///
/// Fill in [termsUrl] and [privacyUrl] once the real documents are
/// published. Bump [termsVersion] every time either document changes:
/// the version string is stored with each person's acceptance
/// (profiles.terms_version / terms_accepted_at).
/// ══════════════════════════════════════════════════════════════
class LegalConfig {
  static const String termsVersion = '2026-10-draft';
  static const String termsUrl = ''; // TODO: https://.../terms
  static const String privacyUrl = ''; // TODO: https://.../privacy

  static const int minPasswordLength = 10;
  static const int usernameMin = 3;
  static const int usernameMax = 20;
}
