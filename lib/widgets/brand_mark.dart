import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The DukaPoint logo square plus name. Same look as the web boot loader,
/// so the hand-off from loader to app doesn't jump.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(size * 0.25),
          ),
          child: Icon(Icons.storefront_outlined, color: Colors.white, size: size * 0.58),
        ),
        SizedBox(width: size * 0.25),
        Text(
          'DukaPoint',
          style: TextStyle(fontSize: size * 0.58, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
      ],
    );
  }
}

/// Shown while sign-in state or the shop session is loading.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 56),
            SizedBox(height: 24),
            SizedBox(width: 160, child: LinearProgressIndicator(minHeight: 4)),
          ],
        ),
      ),
    );
  }
}