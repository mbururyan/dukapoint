import 'package:flutter/material.dart';

import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'pin_pad.dart';

/// Asks for the owner PIN for ONE action (e.g. editing a product) and
/// returns true if it was right. Unlike the Owner tab, this unlocks
/// nothing afterwards: the next protected action asks again.
///
/// If the owner is on shift (or already unlocked the Owner tab), it
/// returns true straight away without showing anything.
Future<bool> requireOwner(BuildContext context, {required String reason}) async {
  final session = SessionService.instance;
  if (session.ownerAccess) return true;

  if (!session.ownerHasPin) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("The owner hasn't set a PIN yet.")),
    );
    return false;
  }

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OwnerPinSheet(reason: reason),
  );
  return ok ?? false;
}

/// Gate for adding/editing/deleting products. The owner, or a cashier the
/// owner marked "Can manage products", goes straight through. Anyone else
/// gets the owner PIN pad for this one action.
Future<bool> requireProductAccess(BuildContext context, {required String reason}) {
  if (SessionService.instance.canManageProducts) return Future.value(true);
  return requireOwner(context, reason: reason);
}

class _OwnerPinSheet extends StatefulWidget {
  const _OwnerPinSheet({required this.reason});

  final String reason;

  @override
  State<_OwnerPinSheet> createState() => _OwnerPinSheetState();
}

class _OwnerPinSheetState extends State<_OwnerPinSheet> {
  static const _maxTries = 5;

  String _pin = '';
  String? _error;
  int _fails = 0;

  void _press(String key) {
    setState(() {
      _error = null;
      _pin = applyPinKey(_pin, key);
    });
    if (_pin.length < 4) return;

    final session = SessionService.instance;
    final pin = _pin;
    final ok = session.staff.any((s) => s.isOwner && s.hasPin && session.checkPin(s, pin));
    if (ok) {
      Navigator.pop(context, true);
      return;
    }

    _fails++;
    if (_fails >= _maxTries) {
      // Just close; the cashier can't keep guessing from here.
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _pin = '';
      _error = 'Wrong owner PIN. ${_maxTries - _fails} tries left.';
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
            const Text(
              'Owner PIN',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              widget.reason,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppColors.inkSoft),
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