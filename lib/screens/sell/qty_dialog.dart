import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Asks "how many?" (pieces) or "what weight?" (kg items).
/// Returns the number typed, or null if cancelled.
Future<double?> showQtyDialog(BuildContext context, Product product, {double? initial}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _QtyDialog(product: product, initial: initial),
  );
}

class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.product, this.initial});

  final Product product;
  final double? initial;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final TextEditingController _c;
  String? _error;

  Product get p => widget.product;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial == null ? '' : qty(widget.initial!));
    // Select the old value so typing replaces it instead of appending.
    _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final n = double.tryParse(_c.text.trim());
    if (n == null || n <= 0) {
      setState(() => _error = p.isKg ? 'Enter the weight' : 'Enter a quantity');
      return;
    }
    if (!p.isKg && n != n.roundToDouble()) {
      setState(() => _error = 'Whole numbers only');
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final n = double.tryParse(_c.text.trim());
    final preview = (n != null && n > 0) ? ' = ${ksh((p.price * n).round())}' : '';

    return AlertDialog(
      title: Text(p.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: p.isKg),
            inputFormatters: [
              p.isKg
                  ? FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))
                  : FilteringTextInputFormatter.digitsOnly,
            ],
            style: AppTheme.mono(size: 24, weight: FontWeight.w600),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _ok(),
            decoration: InputDecoration(
              labelText: p.isKg ? 'Weight' : 'Quantity',
              suffixText: p.isKg ? 'kg' : null,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 10),
          // Live total so the cashier can tell the customer before adding.
          Text(
            p.isKg ? '${ksh(p.price)} per kg$preview' : '${ksh(p.price)} each$preview',
            style: const TextStyle(color: AppColors.inkSoft),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _ok,
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}