import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glow.dart';

/// Port of the R app's Plus-tier lock banner shown on gated tabs.
class PlusLockCard extends StatelessWidget {
  final String feature;
  const PlusLockCard({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14100D), AppColors.ink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppGlow.shadows,
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: Colors.white, size: 36),
          const SizedBox(height: 10),
          const Text('Plus Feature',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 6),
          Text('Upgrade to Plus to unlock $feature.',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
