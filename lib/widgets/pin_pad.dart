import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The four PIN dots. Shared by the cashier PIN screen and the owner gate.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? AppColors.ink : AppColors.surface,
              border: Border.all(color: i < filled ? AppColors.ink : AppColors.borderStrong, width: 2),
            ),
          ),
      ],
    );
  }
}

/// 3x4 number pad. Sends '0'-'9', 'C' (clear) or 'del' (backspace).
class PinKeypad extends StatelessWidget {
  const PinKeypad({super.key, required this.enabled, required this.onKey});

  final bool enabled;
  final ValueChanged<String> onKey;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['C', '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  for (final k in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: SizedBox(
                          height: 64,
                          child: TextButton(
                            onPressed: enabled ? () => onKey(k) : null,
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.surfaceMuted,
                              foregroundColor: AppColors.ink,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: k == 'del'
                                ? const Icon(Icons.backspace_outlined, semanticLabel: 'Delete last digit')
                                : Text(k, style: AppTheme.mono(size: 26, weight: FontWeight.w500)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Applies one keypad press to a PIN string. Kept here so both PIN screens
/// treat C / backspace / the 4-digit cap exactly the same way.
String applyPinKey(String pin, String key) {
  if (key == 'C') return '';
  if (key == 'del') return pin.isEmpty ? pin : pin.substring(0, pin.length - 1);
  return pin.length < 4 ? pin + key : pin;
}