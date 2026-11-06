import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// What the person chose in the void sheet.
class VoidChoice {
  const VoidChoice(this.reason, this.note);
  final String reason;
  final String? note;
}

/// Wireframe step 10, screen 2: "Void this sale?" with a reason.
/// Returns null if the sheet is closed. Approval (owner PIN) and the
/// actual void happen afterwards, in the receipt screen.
Future<VoidChoice?> askVoidReason(BuildContext context, Sale sale) {
  return showModalBottomSheet<VoidChoice>(
    context: context,
    isScrollControlled: true, // lets the sheet rise above the keyboard
    showDragHandle: true,
    builder: (_) => _VoidSheet(sale: sale),
  );
}

class _VoidSheet extends StatefulWidget {
  const _VoidSheet({required this.sale});

  final Sale sale;

  @override
  State<_VoidSheet> createState() => _VoidSheetState();
}

class _VoidSheetState extends State<_VoidSheet> {
  // Fixed wording on purpose: the same four phrases every time means the
  // owner can later count "how many voids were Test sale vs Wrong item".
  static const _reasons = ['Wrong item', 'Customer returned', 'Wrong amount', 'Test sale', 'Other'];

  final _note = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _needsNote => _reason == 'Other';
  bool get _ready => _reason != null && (!_needsNote || _note.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    final isMpesa = s.method != 'cash';
    // The owner on shift approves just by tapping; anyone else needs the
    // owner's PIN next, so the button says what happens.
    final ownerHere = SessionService.instance.ownerAccess;

    return Padding(
      // Keeps the note field visible when the keyboard opens.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Void this sale?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${s.receiptNo} · ${ksh(s.total)} · ${s.itemCount} ${s.itemCount == 1 ? 'item' : 'items'}\n'
                'Stock goes back on the shelf.',
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 14),
              const Text('Why?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _reasons)
                    ChoiceChip(
                      label: Text(r),
                      selected: _reason == r,
                      onSelected: (_) => setState(() => _reason = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _needsNote ? 'What happened? (needed)' : 'Details (optional)',
                ),
              ),
              if (isMpesa) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'M-Pesa sale: DukaPoint can\'t send money back. Refund ${ksh(s.total)} to the customer '
                    'from the shop\'s M-Pesa yourself.',
                    style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.warning),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _ready ? () => Navigator.pop(context, VoidChoice(_reason!, _note.text)) : null,
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                child: Text(ownerHere ? 'Void sale' : 'Owner PIN to approve'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}