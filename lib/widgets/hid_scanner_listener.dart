import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Catches barcodes from a scanner gun (USB or Bluetooth).
///
/// A scanner gun pretends to be a keyboard: it "types" the digits very fast
/// and then presses Enter. So we listen for key presses on this screen,
/// collect the characters, and treat Enter as "a barcode just arrived".
/// No special driver or package is needed; it works with any gun set to
/// keyboard (HID) mode, which is how they ship.
class HidScannerListener extends StatefulWidget {
  const HidScannerListener({
    super.key,
    required this.child,
    required this.onScan,
    required this.focusNode,
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<String> onScan;
  final FocusNode focusNode;
  final bool enabled;

  @override
  State<HidScannerListener> createState() => _HidScannerListenerState();
}

class _HidScannerListenerState extends State<HidScannerListener> {
  // A gun types a whole barcode in a few dozen milliseconds. If the gap
  // between two characters is longer than this, the earlier characters
  // were stray key presses, not part of the same barcode: start over.
  static const _maxGap = Duration(milliseconds: 300);

  // Real barcodes are at least this long; shorter means a stray key + Enter.
  static const _minLength = 4;

  final _buffer = StringBuffer();
  DateTime _lastKey = DateTime.fromMillisecondsSinceEpoch(0);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString().trim();
      _buffer.clear();
      if (code.length >= _minLength) widget.onScan(code);
      return KeyEventResult.handled;
    }

    final ch = event.character;
    // Printable characters only; ignore Shift, arrows and the like.
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) {
      final now = DateTime.now();
      if (now.difference(_lastKey) > _maxGap) _buffer.clear();
      _lastKey = now;
      _buffer.write(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}