import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pin_pad.dart';

/// Asks for a new 4-digit PIN twice and returns it once both entries match,
/// or null if the sheet is closed. Saving it is up to the caller.
///
/// Used for "Change owner PIN" in Shop settings. The person is already
/// inside the owner area, so the old PIN isn't asked for again.
Future<String?> askNewPin(BuildContext context, {required String forName}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewPinSheet(forName: forName),
  );
}

class _NewPinSheet extends StatefulWidget {
  const _NewPinSheet({required this.forName});

  final String forName;

  @override
  State<_NewPinSheet> createState() => _NewPinSheetState();
}

class _NewPinSheetState extends State<_NewPinSheet> {
  String _pin = '';
  String? _first;
  String? _error;

  void _press(String key) {
    setState(() {
      _error = null;
      _pin = applyPinKey(_pin, key);
    });
    if (_pin.length < 4) return;

    final pin = _pin;
    if (_first == null) {
      setState(() {
        _first = pin;
        _pin = '';
      });
      return;
    }
    if (pin == _first) {
      Navigator.pop(context, pin);
      return;
    }
    setState(() {
      _first = null;
      _pin = '';
      _error = "PINs didn't match. Start again.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _first == null ? 'New PIN for ${widget.forName}' : 'Enter it again',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            PinDots(filled: _pin.length),
            const SizedBox(height: 10),
            SizedBox(
              height: 22,
              child: Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            PinKeypad(enabled: true, onKey: _press),
          ],
        ),
      ),
    );
  }
}