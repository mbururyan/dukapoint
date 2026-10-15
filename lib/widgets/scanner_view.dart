import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Live camera that reports barcodes. Used full-screen by ScanScreen and
/// embedded in the top of the Sell screen.
class ScannerView extends StatefulWidget {
  const ScannerView({
    super.key,
    required this.onCode,
    this.repeatGap = const Duration(milliseconds: 1500),
    this.hint = 'Point at a barcode',
  });

  final ValueChanged<String> onCode;

  /// The same code seen again within this window is ignored.
  final Duration repeatGap;
  final String hint;

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> with WidgetsBindingObserver {
  // Retail barcodes plus Code 128 (common on feed bags and shelf labels).
  // Leaving out QR and others makes detection faster and avoids reading
  // the QR on an M-Pesa poster as a product.
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
  );

  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// Release the camera when the app goes to the background (a call, the
  /// M-Pesa app...) and take it back on return. Without this the camera can
  /// stay locked, or come back frozen, after switching apps mid-sale.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.start().catchError((_) {}));
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_controller.stop().catchError((_) {}));
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final code = b.rawValue?.trim();
      if (code == null || code.isEmpty) continue;

      // The camera reports the same barcode 10-30 times a second while it
      // is in view. Without this gap, one scan would add many items.
      // We use a time window instead of the package's "noDuplicates" mode
      // on purpose: that mode ignores a code until a DIFFERENT one is seen,
      // which would block scanning two packets of the same sugar in a row.
      final now = DateTime.now();
      if (code == _lastCode && now.difference(_lastAt) < widget.repeatGap) return;
      _lastCode = code;
      _lastAt = now;

      HapticFeedback.mediumImpact(); // a buzz so the cashier knows it read
      widget.onCode(code);
      return; // one code per frame is enough
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // Viewfinder frame: purely a guide for where to hold the barcode.
        IgnorePointer(
          child: Center(
            child: Container(
              width: 260,
              height: 130,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Text(
            widget.hint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14, shadows: [Shadow(blurRadius: 4)]),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filledTonal(
            tooltip: 'Torch',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ),
      ],
    );
  }
}