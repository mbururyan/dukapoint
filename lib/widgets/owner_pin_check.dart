import 'package:flutter/material.dart';

import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'pin_pad.dart';

/// Asks for the owner PIN before opening an owner page from the drawer.
/// Returns true straight away if the owner area is already open.
///
/// Unlike the Owner tab, a right PIN here does NOT unlock the owner area.
/// It lets you through this once. Otherwise the cashier standing at the
/// till after the owner looked at Inventory could walk into the Owner tab
/// or edit prices without a PIN, because nothing would lock it again.
Future<bool> confirmOwnerPin(BuildContext context, {required String reason}) async {
  final session = SessionService.instance;
  if (session.ownerAccess) return true;
  if (!session.ownerHasPin) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("The owner hasn't set a PIN yet. Switch to the owner to set one.")),
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

class _OwnerPinSheet extends StatefulWidget {
  const _OwnerPinSheet({required this.reason});

  final String reason;

  @override
  State<_OwnerPinSheet> createState() => _OwnerPinSheetState();
}

class _OwnerPinSheetState extends State<_OwnerPinSheet> {
  static const _maxTries = 5;
  static const _lockFor = Duration(seconds: 30);

  // Static, so closing and reopening the sheet doesn't reset the count:
  // otherwise someone could guess forever, five tries at a time.
  static int _fails = 0;
  static DateTime? _lockedUntil;

  String _pin = '';
  String? _error;

  bool get _locked => _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  @override
  void initState() {
    super.initState();
    if (_locked) _error = 'Too many wrong tries. Wait 30 seconds.';
  }

  /// Checks against every active owner (a shop may have two), without
  /// touching the session's unlocked flag.
  bool _matches(String pin) {
    final session = SessionService.instance;
    return session.staff.any((s) => s.isOwner && s.hasPin && session.checkPin(s, pin));
  }

  void _press(String key) {
    if (_locked) {
      setState(() => _error = 'Too many wrong tries. Wait 30 seconds.');
      return;
    }
    setState(() {
      _error = null;
      _pin = applyPinKey(_pin, key);
    });
    if (_pin.length < 4) return;

    final pin = _pin;
    setState(() => _pin = '');
    if (_matches(pin)) {
      _fails = 0;
      Navigator.pop(context, true);
      return;
    }
    _fails++;
    setState(() {
      if (_fails >= _maxTries) {
        _fails = 0;
        _lockedUntil = DateTime.now().add(_lockFor);
        _error = 'Too many wrong tries. Wait 30 seconds.';
      } else {
        _error = 'Wrong owner PIN. ${_maxTries - _fails} tries left.';
      }
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
              'Needed ${widget.reason}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 20),
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