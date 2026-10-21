import 'package:flutter/material.dart';

const _shopCyan = Color(0xFF6EE7F9);
const _shopViolet = Color(0xFF9D8CFF);

/// The Shop stays intentionally reserved until its product rules and catalog
/// are defined. It must not simulate currency, purchases, streaks, or rewards.
class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 130),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xCC273C72), Color(0xCC17162F), Color(0xAA101A2B)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.storefront_rounded, size: 34, color: _shopCyan),
                SizedBox(height: 16),
                Text(
                  'THE GALAXY SHOP',
                  style: TextStyle(letterSpacing: 2.5, fontWeight: FontWeight.w900, fontSize: 12, color: _shopCyan),
                ),
                SizedBox(height: 10),
                Text(
                  'Something wonderful, when it is ready.',
                  style: TextStyle(fontSize: 25, height: 1.15, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 12),
                Text(
                  'This space is reserved for a real, verified catalog. The experience and its rules are still being designed.',
                  style: TextStyle(color: Colors.white70, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _shopViolet.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _shopViolet.withValues(alpha: 0.22)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, color: _shopViolet),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No simulated coins, prices, purchases, streaks, or rewards. Nothing is sold or installed from this screen.',
                    style: TextStyle(color: Colors.white70, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
