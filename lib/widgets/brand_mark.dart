import 'package:flutter/material.dart';

/// The DukaPoint logo (R1A, the same picture as the app icon) plus name.
/// Same look as the web boot loader and the splash, so nothing jumps when
/// one hands over to the next.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The launcher icon file itself, so the logo can never drift away
        // from the icon on the home screen. The file is a full square;
        // the rounding is done here, like a phone launcher does.
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.25),
          child: Image.asset(
            'assets/icon/icon.png',
            width: size,
            height: size,
            // A 1024px image shrunk to ~56px: medium filtering keeps the
            // thin barcode lines from shimmering.
            filterQuality: FilterQuality.medium,
          ),
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