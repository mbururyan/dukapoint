import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/receipt_text.dart';

/// Wireframe 5. Shown right after a sale is saved, and again when a past
/// sale is opened from the Sales tab. The paper card shows the exact text
/// that step 6 will send to the printer.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.sale, this.viewOnly = false});

  final Sale sale;

  /// True when opened from the Sales tab: a past sale being looked at
  /// (or reprinted), not one that was just paid for.
  final bool viewOnly;

  String get _summary {
    switch (sale.method) {
      case 'cash':
        return 'Cash · ${ksh(sale.total)} · Change ${ksh(sale.change ?? 0)}';
      case 'till':
        return 'M-Pesa · ${ksh(sale.total)} · ${sale.mpesaCode ?? ''}';
      default:
        return ksh(sale.total);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = SessionService.instance.shop!;
    final text = buildReceiptText(sale, shop);

    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      body: SafeArea(
        child: Column(
          children: [
            // ---- Success header ----
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: viewOnly ? AppColors.surfaceMuted : AppColors.success,
                    child: Icon(
                      viewOnly ? Icons.receipt_long_outlined : Icons.check,
                      color: viewOnly ? AppColors.ink : Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    viewOnly ? sale.receiptNo : 'Payment received',
                    style: viewOnly
                        ? AppTheme.mono(size: 20)
                        : const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(_summary, style: const TextStyle(fontSize: 15, color: AppColors.inkSoft)),
                ],
              ),
            ),
            const Divider(height: 1),

            // ---- The receipt, as it will print ----
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      text,
                      // Monospace so the columns line up exactly like the
                      // printer's fixed-width font will.
                      style: AppTheme.mono(size: 12.5, weight: FontWeight.w400).copyWith(height: 1.45),
                    ),
                  ),
                ),
              ),
            ),

            // ---- Actions ----
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      // Printing is step 6; the button is here so the layout
                      // doesn't change when it arrives.
                      onPressed: null,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print (step 6)'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      // After a sale: back to an empty Sell screen (the cart
                      // was already cleared). From Sales: back to the list.
                      onPressed: () => Navigator.pop(context),
                      child: Text(viewOnly ? 'Close' : 'New sale'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}