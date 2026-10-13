import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pin_pad.dart';
import 'owner_home.dart';

/// What the Owner tab shows. If the owner is on shift, or has typed their
/// PIN here, it shows the owner area. Otherwise it asks for the owner PIN.
///
/// This is an app-level lock, not server security (data-model decision 7):
/// it keeps cashiers out of staff management at the counter.
class OwnerGate extends StatefulWidget {
  const OwnerGate({super.key});

  @override
  State<OwnerGate> createState() => _OwnerGateState();
}

class _OwnerGateState extends State<OwnerGate> {
  static const _maxTries = 5;
  static const _lockFor = Duration(seconds: 30);

  final _session = SessionService.instance;

  String _pin = '';
  String? _error;
  int _fails = 0;
  DateTime? _lockedUntil;
  Timer? _lockTimer;

  bool get _locked => _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  void _press(String key) {
    if (_locked) return;
    setState(() {
      _error = null;
      _pin = applyPinKey(_pin, key);
    });
    if (_pin.length < 4) return;

    final pin = _pin;
    setState(() => _pin = '');
    if (_session.unlockOwner(pin)) {
      _fails = 0;
      return; // the ListenableBuilder below swaps in the owner area
    }

    _fails++;
    setState(() {
      if (_fails >= _maxTries) {
        _fails = 0;
        _lockedUntil = DateTime.now().add(_lockFor);
        _error = 'Too many wrong tries. Wait 30 seconds.';
        _lockTimer?.cancel();
        _lockTimer = Timer(_lockFor, () {
          if (mounted) {
            setState(() {
              _lockedUntil = null;
              _error = null;
            });
          }
        });
      } else {
        _error = 'Wrong owner PIN. ${_maxTries - _fails} tries left.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        if (_session.ownerAccess) return const OwnerHome();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 40, color: AppColors.primary),
              const SizedBox(height: 12),
              const Text(
                'Owner only',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter the owner PIN to manage cashiers and see reports.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 24),
              if (!_session.ownerHasPin)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "The owner hasn't set a PIN yet. Tap Switch at the top, choose the owner, and set one there.",
                    style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.warning),
                  ),
                )
              else ...[
                PinDots(filled: _pin.length),
                const SizedBox(height: 12),
                SizedBox(
                  height: 22,
                  child: Text(
                    _error ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                PinKeypad(enabled: !_locked, onKey: _press),
              ],
            ],
          ),
        );
      },
    );
  }
}