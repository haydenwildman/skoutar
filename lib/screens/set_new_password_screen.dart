import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glow.dart';
import '../widgets/orange_glow_button.dart';
import '../widgets/password_field.dart';
import '../widgets/skoutar_logo.dart';

/// Shown after someone follows a password-reset email link
/// (Supabase fires AuthChangeEvent.passwordRecovery).
class SetNewPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SetNewPasswordScreen({super.key, required this.onDone});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_passCtrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AppSession>().auth;
    final res = await auth.setNewPassword(_passCtrl.text);
    if (!mounted) return;
    if (res.success) {
      // Sign out so the person logs in fresh with the new password.
      try {
        await sb.auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      widget.onDone();
    } else {
      setState(() {
        _loading = false;
        _error = res.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              margin: const EdgeInsets.all(16),
              padding: EdgeInsets.all(Responsive.isPhone(context) ? 20 : 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppGlow.shadowsRaised,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkoutarLogo(height: 80),
                  const SizedBox(height: 8),
                  const Text('Set a new password',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink)),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        border: Border.all(color: AppColors.colError),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.colError,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                  PasswordField(controller: _passCtrl, label: 'New password'),
                  const SizedBox(height: 10),
                  PasswordField(
                    controller: _pass2Ctrl,
                    label: 'Confirm new password',
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OrangeGlowButton(
                      onPressed: _loading ? null : _save,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.brandOrangeDeep))
                          : const Text('Update Password'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
