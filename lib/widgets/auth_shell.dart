import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'glow.dart';

/// Shared look for login / sign-up: dark background, faint watermark logos,
/// and a centered white card (responsive: phone, tablet, desktop).
class AuthShell extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const AuthShell({super.key, required this.child, this.maxWidth = 440});

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
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  margin: const EdgeInsets.all(16),
                  padding: EdgeInsets.all(Responsive.isPhone(context) ? 20 : 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppGlow.shadowsRaised,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Red (error) or green (success) message box used on the auth screens.
class AuthMessage extends StatelessWidget {
  final String text;
  final bool success;
  const AuthMessage({super.key, required this.text, this.success = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        border: Border.all(color: success ? AppColors.colSuccess : AppColors.colError),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: success ? AppColors.perfExcellent : AppColors.colError,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
