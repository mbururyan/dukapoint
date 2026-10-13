import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/staff.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pin_pad.dart';

/// Wireframe 2. Pick who's selling, enter their 4-digit PIN.
/// Someone without a PIN yet sets one here (enter it twice).
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const _maxTries = 5;
  static const _lockFor = Duration(seconds: 30);

  final _session = SessionService.instance;

  String? _selectedId;
  String _pin = '';
  String? _firstPin; // holds the first entry while setting a new PIN
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

  Staff? _selected(List<Staff> staff) {
    if (staff.isEmpty) return null;
    for (final s in staff) {
      if (s.id == _selectedId) return s;
    }
    return staff.first;
  }

  void _pick(Staff s) {
    setState(() {
      _selectedId = s.id;
      _pin = '';
      _firstPin = null;
      _error = null;
    });
  }

  void _press(String key, Staff who) {
    if (_locked) return;
    setState(() {
      _error = null;
      _pin = applyPinKey(_pin, key);
    });
    // Submit on the 4th digit: one less tap per shift change than the
    // wireframe's "Start selling" button.
    if (_pin.length == 4) _submit(who);
  }

  void _submit(Staff who) {
    final pin = _pin;

    if (!who.hasPin) {
      if (_firstPin == null) {
        setState(() {
          _firstPin = pin;
          _pin = '';
        });
        return;
      }
      if (pin != _firstPin) {
        setState(() {
          _error = "PINs didn't match. Start again.";
          _firstPin = null;
          _pin = '';
        });
        return;
      }
      _session.setPin(who, pin); // not awaited on purpose, see SessionService.setPin
      _enter(who);
      return;
    }

    if (_session.checkPin(who, pin)) {
      _enter(who);
      return;
    }

    _fails++;
    setState(() {
      _pin = '';
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
        _error = 'Wrong PIN. ${_maxTries - _fails} tries left.';
      }
    });
  }

  void _enter(Staff who) {
    _fails = 0;
    _session.startShift(who); // AuthGate is listening and shows the app
  }

  Future<void> _confirmSignOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign this phone out?'),
        content: const Text('You will need the shop email and password to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (yes == true) await AuthService.instance.signOut();
  }

  String _prompt(Staff who) {
    if (who.hasPin) return 'Enter PIN for ${who.name}';
    return _firstPin == null ? 'Set a 4-digit PIN for ${who.name}' : 'Enter the same PIN again';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final shop = _session.shop;
        final staff = _session.staff;
        final who = _selected(staff);

        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              // Scrollable but fills the screen: on small phones the keypad
              // can scroll instead of overflowing with yellow stripes.
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            (shop?.name ?? '').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text("Who's selling?", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 20),
                          if (who == null)
                            const Text(
                              'No staff are set up for this shop yet. Contact DukaPoint.',
                              style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
                            )
                          else ...[
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final s in staff) _StaffChip(staff: s, selected: s.id == who.id, onTap: () => _pick(s)),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              _prompt(who),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
                            ),
                            const SizedBox(height: 14),
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
                            PinKeypad(enabled: !_locked, onKey: (k) => _press(k, who)),
                          ],
                          const Spacer(),
                          TextButton(
                            onPressed: _confirmSignOut,
                            child: const Text('Sign this phone out of the shop'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StaffChip extends StatelessWidget {
  const _StaffChip({required this.staff, required this.selected, required this.onTap});

  final Staff staff;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.ink;
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.ink : AppColors.border, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(staff.name, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(
                staff.isOwner ? 'Owner' : 'Cashier',
                style: TextStyle(color: selected ? Colors.white70 : AppColors.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}