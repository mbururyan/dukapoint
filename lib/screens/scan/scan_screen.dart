import 'package:flutter/material.dart';

import '../../widgets/scanner_view.dart';

/// Opens the camera full-screen and returns the first barcode it reads,
/// or null if the user closes it.
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const ScanScreen(), fullscreenDialog: true),
  );
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // The scanner can report a second code in the moment before this screen
  // closes; popping twice would close the screen underneath too.
  bool _done = false;

  void _got(String code) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode'),
      ),
      body: ScannerView(onCode: _got, hint: 'Hold the barcode inside the frame'),
    );
  }
}