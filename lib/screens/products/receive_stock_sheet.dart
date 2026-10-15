import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../services/catalog_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Slide-up form for a delivery: how many arrived, from which supplier,
/// at what buying price. Returns a short message for a snackbar, or null.
Future<String?> showReceiveStock(BuildContext context, Product product) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true, // lets the sheet rise above the keyboard
    showDragHandle: true,
    builder: (_) => _ReceiveStockSheet(product: product),
  );
}

class _ReceiveStockSheet extends StatefulWidget {
  const _ReceiveStockSheet({required this.product});

  final Product product;

  @override
  State<_ReceiveStockSheet> createState() => _ReceiveStockSheetState();
}

class _ReceiveStockSheetState extends State<_ReceiveStockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  late final TextEditingController _cost;
  final _note = TextEditingController();
  String _supplier = '';

  Product get p => widget.product;

  @override
  void initState() {
    super.initState();
    // Pre-filled with the current buying price: most deliveries cost the
    // same as last time, so usually it's just a glance and Save.
    _cost = TextEditingController(text: p.buyPrice?.toString() ?? '');
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _validateQty(String? v) {
    final n = double.tryParse(v?.trim() ?? '');
    if (n == null || n <= 0) return 'How many arrived?';
    if (!p.isKg && n != n.roundToDouble()) return 'Whole numbers for pieces';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final qtyIn = double.parse(_qty.text.trim());
    final supplier = _supplier.trim().replaceAll(RegExp(r'\s+'), ' ');
    final costText = _cost.text.trim();
    final note = _note.text.trim();

    CatalogService.instance.receiveStock(
      product: p,
      qty: qtyIn,
      supplier: supplier.isEmpty ? null : supplier,
      unitCost: costText.isEmpty ? null : int.parse(costText),
      note: note.isEmpty ? null : note,
    ); // not awaited: works offline

    final unit = p.isKg ? ' kg' : '';
    final now = qty(p.stock + qtyIn);
    Navigator.pop(context, 'Added ${qty(qtyIn)}$unit to ${p.name} (now $now$unit)');
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = SessionService.instance.shop?.suppliers ?? const <String>[];
    final unit = p.isKg ? 'kg' : null;

    return Padding(
      // Push the sheet up by the keyboard's height so the Save button stays visible.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add stock', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${p.name} · now ${qty(p.stock)}${unit == null ? '' : ' kg'} in stock',
                  style: const TextStyle(fontSize: 15, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 18),

                TextFormField(
                  controller: _qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                  style: AppTheme.mono(size: 22, weight: FontWeight.w600),
                  decoration: InputDecoration(labelText: 'Quantity received', suffixText: unit),
                  validator: _validateQty,
                ),
                const SizedBox(height: 14),

                // Suggests suppliers used before, but accepts any new name.
                Autocomplete<String>(
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return suppliers;
                    return suppliers.where((s) => s.toLowerCase().contains(q));
                  },
                  onSelected: (s) => _supplier = s,
                  fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                    controller: controller,
                    focusNode: focus,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => _supplier = v,
                    decoration: const InputDecoration(
                      labelText: 'Supplier',
                      hintText: 'e.g. FCL, Unga, De Heus',
                      helperText: 'Optional',
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _cost,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTheme.mono(size: 17, weight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: p.isKg ? 'Buying price per kg' : 'Buying price per unit',
                    prefixText: 'Ksh ',
                    helperText: 'Optional · updates the product\'s buying price',
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Note', hintText: 'e.g. invoice no. 4471', helperText: 'Optional'),
                ),
                const SizedBox(height: 20),

                FilledButton(onPressed: _save, child: const Text('Add to stock')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}