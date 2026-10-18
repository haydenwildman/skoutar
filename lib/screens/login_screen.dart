import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/auth_service.dart';
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
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
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
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _passCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _doLogin(),
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
