import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/auth_service.dart';
import '../services/remembered_account_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_shell.dart';
import '../widgets/orange_glow_button.dart';
import '../widgets/password_field.dart';
import '../widgets/skoutar_logo.dart';
import 'home_shell.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  String? _error;
  bool _loading = false;

  /// The account that last signed in on this device (email only), if any.
  String? _remembered;

  /// Keep this account as the default next time. Untick on a shared device.
  bool _rememberDevice = true;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  /// Pre-fills the last account. It never signs anyone in: the password is
  /// still required, so focus goes straight to the password field.
  Future<void> _loadRemembered() async {
    final email = await RememberedAccountService.load();
    if (!mounted || email == null) return;
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() {
        _remembered = email;
        _emailCtrl.text = email;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passFocus.requestFocus();
      });
    }
  }

  /// "Not you?": forget the saved account and start with an empty form.
  Future<void> _useDifferentAccount() async {
    await RememberedAccountService.clear();
    if (!mounted) return;
    setState(() {
      _remembered = null;
      _emailCtrl.clear();
      _passCtrl.clear();
      _error = null;
    });
    _emailFocus.requestFocus();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    if (_loading) return;
    if (!AuthService.isValidEmail(_emailCtrl.text)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    final session = context.read<AppSession>();
    final result = await session.auth.login(_emailCtrl.text, _passCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success && result.user != null) {
      try {
        await session.login(result.user!);
      } catch (_) {
        if (!mounted) return;
        setState(() => _error =
            'Signed in, but your data could not be loaded. If this keeps happening, '
            'the latest database update (supabase_pitchers_migration.sql) may not be installed yet.');
        return;
      }
      // Signed in and data loaded: remember this account (or forget the
      // previous one when "remember" is unticked). A different user logging in
      // simply replaces the remembered email.
      if (_rememberDevice) {
        await RememberedAccountService.save(_emailCtrl.text);
      } else {
        await RememberedAccountService.clear();
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } else {
      setState(() => _error = result.message ?? 'Invalid email or password.');
    }
  }

  Future<void> _forgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _emailCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkoutarLogo(height: 100),
          const SizedBox(height: 8),
          const Text('Sign in to your account',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          if (_error != null) AuthMessage(text: _error!),
          if (_remembered != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Last signed in on this device: $_remembered',
                  style: const TextStyle(fontSize: 12, color: AppColors.colMuted)),
            ),
            const SizedBox(height: 6),
          ],
          TextField(
            controller: _emailCtrl,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onChanged: (v) {
              // Typing a different address means a different account.
              if (_remembered != null && v.trim().toLowerCase() != _remembered) {
                setState(() => _remembered = null);
              }
            },
            decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
          ),
          if (_remembered != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading ? null : _useDifferentAccount,
                child: const Text('Not you? Use a different account'),
              ),
            ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _passCtrl,
            focusNode: _passFocus,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _doLogin(),
          ),
          CheckboxListTile(
            value: _rememberDevice,
            onChanged: _loading ? null : (v) => setState(() => _rememberDevice = v ?? true),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Remember my email on this device',
                style: TextStyle(fontSize: 12.5)),
            subtitle: const Text('Your password is never saved. Untick on a shared computer.',
                style: TextStyle(fontSize: 11)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _forgotPassword,
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OrangeGlowButton(
              onPressed: _loading ? null : _doLogin,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.brandOrangeDeep))
                  : const Text('Sign In →'),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: _loading
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    ),
            child: const Text("Don't have an account? Create one →"),
          ),
        ],
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  const _ForgotPasswordDialog({required this.initialEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail);
  String? _message;
  bool _success = false;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final res = await context.read<AppSession>().auth.sendPasswordReset(_emailCtrl.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _success = res.success;
      _message = res.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter your account email and we'll send a reset link."),
            const SizedBox(height: 12),
            if (_message != null) AuthMessage(text: _message!, success: _success),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _loading ? null : _send(),
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_success ? 'Close' : 'Cancel'),
        ),
        TextButton(
          onPressed: _loading ? null : _send,
          child: _loading
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_success ? 'Send again' : 'Send reset link'),
        ),
      ],
    );
  }
}
