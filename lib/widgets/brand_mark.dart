import 'package:flutter/material.dart';

/// The DukaPoint mark (design 4e): amber scanner corners around rising
/// white barcode bars, on deep plum.
///
/// Drawn in code rather than loaded from a PNG, so it's sharp at any size
/// (login, loading screen, receipts later) and adds nothing to the app size.
/// The geometry is a 100 x 100 design, scaled to [size]; it matches
/// assets/icon/dukapoint_icon.svg exactly, so the app icon, splash and
/// in-app mark are the same drawing.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.tile = true});

  final double size;

  /// Draw the rounded plum square behind the mark. Turn off when the mark
  /// already sits on plum (splash-style screens), or it shows as a box
  /// within a box.
  final bool tile;

  static const plum = Color(0xFF4C1D95);
  static const amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'DukaPoint',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MarkPainter(tile: tile)),
      ),
    );
  }
}

/// Shown while the app works out who's signed in and loads the shop.
/// Same plum, mark and position as the native splash, so going from the
/// splash to this screen looks like one continuous screen, not a flash.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: BrandMark.plum,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No tile: the mark already sits on plum.
            BrandMark(size: 120, tile: false),
            SizedBox(height: 12),
            Text(
              'DukaPoint',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 28),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                color: BrandMark.amber,
                backgroundColor: Color(0x33FFFFFF),
                minHeight: 4,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.tile});

  final bool tile;

  // Bar widths like a real barcode (thin and thick), the gap between them,
  // and where the group sits. Heights rise evenly from 14 to 40.
  static const _widths = [5.0, 2.5, 5.0, 2.5, 5.0, 7.0];
  static const _gap = 2.5;
  static const _barsX = 29.0;
  static const _barsW = 42.0;
  static const _base = 72.0;
  static const _hMin = 14.0;
  static const _hMax = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100; // design units -> pixels
    canvas.save();
    canvas.scale(s);

    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(22)),
        Paint()..color = BrandMark.plum,
      );
    }

    // Four scanner corners, 20 units in from each edge, 16 long.
    // Round caps and joins: square ends looked sharp and "technical" at
    // icon size; round ones read friendlier and survive small sizes better.
    final corners = Path()
      ..moveTo(20, 36)..lineTo(20, 20)..lineTo(36, 20)
      ..moveTo(64, 20)..lineTo(80, 20)..lineTo(80, 36)
      ..moveTo(20, 64)..lineTo(20, 80)..lineTo(36, 80)
      ..moveTo(64, 80)..lineTo(80, 80)..lineTo(80, 64);
    canvas.drawPath(
      corners,
      Paint()
        ..color = BrandMark.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The bars.
    final total = _widths.fold<double>(0, (a, b) => a + b) + _gap * (_widths.length - 1);
    final k = _barsW / total;
    final white = Paint()..color = Colors.white;
    var x = _barsX;
    for (var i = 0; i < _widths.length; i++) {
      final h = _hMin + (_hMax - _hMin) * i / (_widths.length - 1);
      final w = _widths[i] * k;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, _base - h, w, h), const Radius.circular(1)),
        white,
      );
      x += (_widths[i] + _gap) * k;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.tile != tile;
}