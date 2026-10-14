import '../widgets/orange_glow_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/skoutar_logo.dart';
import '../utils/responsive.dart';
import 'signup_screen.dart';
import 'home_shell.dart';

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

  Future<void> _doLogin() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    final session = context.read<AppSession>();
    final result = await session.auth.login(_emailCtrl.text, _passCtrl.text);
    setState(() => _loading = false);
    if (!mounted) return;
    if (result.success && result.user != null) {
      await session.login(result.user!);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } else {
      setState(() => _error = result.message ?? 'Invalid username or password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          // Large faint watermark logo behind everything, matching the
          // "behind the screen → watermarked version" rule.
          Positioned(
            right: -80,
            bottom: -60,
            child: Image.asset('assets/images/logo_watermark.png', width: 420),
          ),
          Positioned(
            left: -100,
            top: -80,
            child: Image.asset('assets/images/logo_watermark.png', width: 320),
          ),
          SafeArea(child: Center(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Container(
            width: 400,
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
                SkoutarLogo(height: 100),
                const SizedBox(height: 8),
                const Text('Sign in to your account',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 20),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', hintText: 'you@example.com'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  onSubmitted: (_) => _doLogin(),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SignupScreen()),
                  ),
                  child: const Text("Don't have an account? Sign up →"),
                ),
              ],
            ),
          ),
        ),
      )),
        ],
      ),
    );
  }
}
