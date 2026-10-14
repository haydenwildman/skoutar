import '../widgets/orange_glow_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/app_session.dart';
import '../services/billing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';
import '../widgets/skoutar_logo.dart';
import '../utils/responsive.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  UserTier _plan = UserTier.basic;
  String? _message;
  bool _success = false;
  bool _loading = false;

  Future<void> _doSignup() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final session = context.read<AppSession>();
    final result = await session.auth.signUp(
      username: _userCtrl.text,
      email: _emailCtrl.text,
      password: _passCtrl.text,
      confirmPassword: _pass2Ctrl.text,
      tier: _plan,
    );
    setState(() {
      _loading = false;
      _message = result.message;
      _success = result.success;
    });
  }

  Widget _planCard({
    required UserTier tier,
    required String name,
    required String price,
    required String features,
  }) {
    final selected = _plan == tier;
    return InkWell(
      onTap: () => setState(() => _plan = tier),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? AppColors.ink : AppColors.colBorder,
              width: 2),
          borderRadius: BorderRadius.circular(10),
          color: selected ? AppColors.tint : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.ink)),
            const SizedBox(height: 2),
            Text(price, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 6),
            Text(features, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
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
            width: 440,
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
                SkoutarLogo(height: 88),
                const SizedBox(height: 8),
                const Text('Create Account',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text('SKOUTAR — Start for free',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 20),
                if (_message != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: _success
                          ? const Color(0xFFF0FDF4)
                          : const Color(0xFFFEF2F2),
                      border: Border.all(
                          color: _success
                              ? AppColors.colSuccess
                              : AppColors.colError),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_message!,
                        style: TextStyle(
                            color: _success
                                ? AppColors.perfExcellent
                                : AppColors.colError,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Username', hintText: 'e.g. CoachMike')),
                const SizedBox(height: 10),
                TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email', hintText: 'you@example.com')),
                const SizedBox(height: 10),
                TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 10),
                TextField(
                    controller: _pass2Ctrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm Password')),
                const Divider(height: 28),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Choose your plan:',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const SizedBox(height: 8),
                _planCard(
                  tier: UserTier.basic,
                  name: 'Basic — ${PricingConfig.priceLabel(UserTier.basic)}',
                  price: PricingConfig.priceLabel(UserTier.basic),
                  features:
                      'Game Input  Overview  Spray Chart  Game Logs',
                ),
                _planCard(
                  tier: UserTier.plus,
                  name: 'Plus — ${PricingConfig.priceLabel(UserTier.plus)}',
                  price: PricingConfig.priceLabel(UserTier.plus),
                  features:
                      'Everything in Basic  Count & Approach  Pitch Sequencing  Scouting Reports',
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OrangeGlowButton(
                    onPressed: _loading ? null : _doSignup,
                    child: const Text('Create Account →'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('← Back to Login'),
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
