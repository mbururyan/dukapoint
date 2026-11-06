import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/plan_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/status_banners.dart';

/// Wireframe step 11, screen 2. How to pay for DukaPoint: your Paybill,
/// the shop's code as the account, and the amount. After Daraja, the
/// greyed button sends an M-Pesa prompt and the plan extends by itself;
/// until then you extend paidUntil in the console when the money lands.
Future<void> showRenewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _RenewSheet(),
  );
}

class _RenewSheet extends StatelessWidget {
  const _RenewSheet();

  @override
  Widget build(BuildContext context) {
    final plan = PlanService.instance;
    return ListenableBuilder(
      listenable: plan, // the price/Paybill can arrive after the sheet opens
      builder: (context, _) {
        final shop = SessionService.instance.shop!;
        final s = plan.stateFor(shop);
        final bill = plan.billing;
        final until = s.paidUntil;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Renew DukaPoint', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (bill != null && bill.amount > 0) '${ksh(bill.amount)} a month',
                    if (until != null) (s.daysLeft >= 0 ? 'paid until ${planDate(until)}' : 'ended ${planDate(until)}'),
                  ].join(' · '),
                  style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 14),
                if (bill == null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                    child: const Text(
                      'Payment details aren\'t set up yet. Contact DukaPoint to renew.',
                      style: TextStyle(fontSize: 15, height: 1.4),
                    ),
                  )
                else ...[
                  _CopyRow(label: 'Paybill', value: bill.paybill),
                  // The shop's receipt code as account: it's short, already
                  // unique per shop, and it's how a payment finds its shop.
                  _CopyRow(label: 'Account', value: shop.code),
                  if (bill.amount > 0) _CopyRow(label: 'Amount', value: ksh(bill.amount), copyText: '${bill.amount}'),
                  const SizedBox(height: 10),
                  const Text(
                    'M-Pesa › Lipa na M-Pesa › Pay Bill. Type the account exactly as shown so the payment '
                    'finds your shop. Your plan is extended once the payment is confirmed.',
                    style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft),
                  ),
                ],
                const SizedBox(height: 16),
                // Kept visible but off, so owners know a one-tap way is coming.
                const FilledButton(
                  onPressed: null,
                  child: Text('Send M-Pesa prompt · coming soon'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Label, big number, and a copy button: saves typing a 6-digit Paybill.
class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, this.copyText});

  final String label;
  final String value;
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.inkSoft))),
          Text(value, style: AppTheme.mono(size: 20)),
          IconButton(
            tooltip: 'Copy $label',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyText ?? value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
            },
          ),
        ],
      ),
    );
  }
}