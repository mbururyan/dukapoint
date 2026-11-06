import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../services/catalog_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/counting.dart';
import '../../utils/format.dart';
import '../../utils/shop_code.dart';
import '../scan/scan_screen.dart';

/// Wireframe 8. Add a new product, or edit one (when [product] is given).
/// Pops with a short message ("X saved" / "X deleted") for the list's snackbar.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.initialCode});

  final Product? product;

  /// Pre-fills the barcode for a new product, e.g. after scanning an item
  /// that wasn't found in the Products search.
  final String? initialCode;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _buyPrice;
  late final TextEditingController _stock;
  late final TextEditingController _lowAt;
  late final TextEditingController _source;
  final _sourceFocus = FocusNode();
  late String _unit;
  late String _countedAs;
  late bool _active;

  // The usual shop words. Anything else goes through "Other…".
  static const _words = ['item', 'bag', 'packet', 'bottle', 'tin', 'sack'];

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _code = TextEditingController(text: p?.code ?? widget.initialCode ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _source = TextEditingController(text: p?.source ?? '');
    _price = TextEditingController(text: p == null ? '' : '${p.price}');
    _buyPrice = TextEditingController(text: p?.buyPrice?.toString() ?? '');
    _stock = TextEditingController(text: p == null ? '' : qty(p.stock));
    _lowAt = TextEditingController(text: p == null ? '5' : qty(p.lowStockAt));
    _unit = p?.unit ?? 'piece';
    _countedAs = p?.countedAs ?? 'item';
    _active = p?.active ?? true;
  }

  /// "Other…": the owner types their own word, e.g. "crate" or "roll".
  Future<void> _otherWord() async {
    final controller = TextEditingController(text: _words.contains(_countedAs) ? '' : _countedAs);
    final word = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Counted as'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(hintText: 'e.g. crate', helperText: 'One of them, not many: "crate", not "crates"'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Use')),
        ],
      ),
    );
    controller.dispose();
    // Lower case and single spaces, so "Crate " and "crate" are one word
    // when sales get counted up.
    final clean = (word ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isNotEmpty && mounted) setState(() => _countedAs = clean);
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _price, _buyPrice, _stock, _lowAt, _source]) {
      c.dispose();
    }
    _sourceFocus.dispose();
    super.dispose();
  }

  void _generateCode() {
    final catalog = CatalogService.instance;
    var code = generateShopCode();
    // Practically never loops, but costs nothing to be sure.
    while (catalog.byCode(code) != null) {
      code = generateShopCode();
    }
    setState(() => _code.text = code);
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    setState(() => _code.text = code);
    // Tell them right away rather than only when they press Save.
    final existing = CatalogService.instance.byCode(code);
    if (existing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('That barcode is already saved as "${existing.name}".')),
      );
    }
  }

  String? _validateNewCode(String? v) {
    final basic = validateCode(v);
    if (basic != null || _isEdit) return basic;
    // Checked against the in-memory catalogue, so it works offline.
    final existing = CatalogService.instance.byCode(v!.trim());
    if (existing != null) return 'Already saved as "${existing.name}". Edit that one instead.';
    return null;
  }

  String? _validatePrice(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n <= 0) return 'Enter a price in shillings';
    return null;
  }

  String? _validateOptionalInt(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n < 0) return 'Whole shillings only';
    return null;
  }

  String? _validateQty(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    final n = double.tryParse(t);
    if (n == null || n < 0) return 'Enter a number';
    if (_unit == 'piece' && n != n.roundToDouble()) return 'Whole numbers for pieces';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final code = _code.text.trim();
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final price = int.parse(_price.text.trim());
    final buy = _buyPrice.text.trim().isEmpty ? null : int.parse(_buyPrice.text.trim());
    final stock = double.parse(_stock.text.trim());
    final lowAt = double.parse(_lowAt.text.trim());
    final catalog = CatalogService.instance;

    // Not awaited: works offline, the list updates from the phone's cache.
    if (_isEdit) {
      catalog.update(
        // The whole "before" product, so a changed stock figure can be
        // logged as a correction of the right size.
        before: widget.product!,
        name: name,
        price: price,
        buyPrice: buy,
        stock: stock,
        lowStockAt: lowAt,
        unit: _unit,
        countedAs: _countedAs,
        source: _source.text,
        active: _active,
      );
    } else {
      catalog.create(
        code: code,
        name: name,
        price: price,
        buyPrice: buy,
        stock: stock,
        lowStockAt: lowAt,
        unit: _unit,
        countedAs: _countedAs,
        source: _source.text,
      );
    }
    Navigator.pop(context, '$name saved');
  }

  Future<void> _delete() async {
    final p = widget.product!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        content: const Text("It has never been sold, so nothing else depends on it. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    CatalogService.instance.delete(p.code); // not awaited: works offline
    Navigator.pop(context, '${p.name} deleted');
  }

  @override
  Widget build(BuildContext context) {
    final perKg = _unit == 'kg' ? ' per kg' : '';
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit product' : 'New product', style: const TextStyle(fontWeight: FontWeight.w700)),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const _Group('What it is'),
              // ---- Barcode ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _code,
                      // The code is the document ID: changing it would mean a
                      // different product. To "change" one, hide this product
                      // and add a new one.
                      readOnly: _isEdit,
                      style: AppTheme.mono(size: 17, weight: FontWeight.w500),
                      decoration: InputDecoration(
                        labelText: 'Barcode',
                        helperText: _isEdit ? "A product's barcode can't be changed" : null,
                        hintText: _isEdit ? null : 'Scan or type',
                        filled: _isEdit,
                        fillColor: _isEdit ? AppColors.surfaceMuted : null,
                      ),
                      validator: _validateNewCode,
                    ),
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _scan,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 56),
                          backgroundColor: AppColors.ink,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan'),
                      ),
                    ),
                  ],
                ],
              ),
              // A real button, full width and amber (the same colour as Edit
              // product), not a small link: shops that don't use barcodes at
              // all tap this for every product, so it has to be easy to hit.
              if (!_isEdit) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _generateCode,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('No barcode? Make a shop code'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.warningBg, // pale amber
                    foregroundColor: AppColors.ink, // dark text: readable on amber
                    side: const BorderSide(color: AppColors.accent, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // ---- Name ----
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Product name', hintText: 'e.g. Sow & Weaner 70kg'),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 16),

              // ---- Source ----
              // Right under the name: people say them together ("FCL Sow
              // & Weaner"). Suggestions only appear while typing.
              _SourceField(controller: _source, focusNode: _sourceFocus),
              const SizedBox(height: 20),

              const _Group("How it's sold"),
              // ---- Unit ----
              const Text('Sold by', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  // "By count" now that the word (bag, packet...) is chosen below.
                  ButtonSegment(value: 'piece', label: Text('By count'), icon: Icon(Icons.inventory_2_outlined)),
                  ButtonSegment(value: 'kg', label: Text('Weight (kg)'), icon: Icon(Icons.scale_outlined)),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => setState(() => _unit = s.first),
              ),

              // ---- Counted as (per-piece only) ----
              if (_unit == 'piece') ...[
                const SizedBox(height: 16),
                const Text('Counted as', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final w in _words)
                      ChoiceChip(
                        label: Text(w),
                        selected: _countedAs == w,
                        onSelected: (_) => setState(() => _countedAs = w),
                      ),
                    // A typed word shows as its own selected chip; tapping
                    // it (or "Other…") lets the owner change it.
                    ChoiceChip(
                      label: Text(_words.contains(_countedAs) ? 'Other…' : _countedAs),
                      selected: !_words.contains(_countedAs),
                      onSelected: (_) => _otherWord(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Shows as "3 bags" on sales and stock. Leave it on "item" if unsure.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ],
              const SizedBox(height: 16),

              const _Group('Price'),
              // ---- Prices ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      style: AppTheme.mono(size: 17, weight: FontWeight.w500),
                      decoration: InputDecoration(labelText: 'Selling price$perKg', prefixText: 'Ksh '),
                      validator: _validatePrice,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _buyPrice,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      style: AppTheme.mono(size: 17, weight: FontWeight.w500),
                      decoration: InputDecoration(labelText: 'Buying price', prefixText: 'Ksh ', helperText: 'Optional'),
                      validator: _validateOptionalInt,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 4),
              const _Group('Stock'),
              // ---- Stock ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: decimals,
                      style: AppTheme.mono(size: 17, weight: FontWeight.w500),
                      decoration: InputDecoration(
                        labelText: 'Stock on hand',
                        suffixText: _unit == 'kg' ? 'kg' : plural(_countedAs),
                        // Steer deliveries to "Add stock" so they get a supplier
                        // and show as "received", not as a correction.
                        helperText: _isEdit ? 'Corrections only' : null,
                      ),
                      validator: _validateQty,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lowAt,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: decimals,
                      style: AppTheme.mono(size: 17, weight: FontWeight.w500),
                      decoration: InputDecoration(
                        labelText: 'Warn when at',
                        suffixText: _unit == 'kg' ? 'kg' : plural(_countedAs),
                      ),
                      validator: _validateQty,
                    ),
                  ),
                ],
              ),

              // ---- Hide (edit only) ----
              if (_isEdit) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Available for sale', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Turn off to hide it from selling. Past sales keep it.'),
                ),
              ],

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Buying price is only seen by the owner. It lets the dashboard show profit, not just sales.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkSoft),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: Text(_isEdit ? 'Save changes' : 'Save product')),

              // ---- Delete / audit (edit only) ----
              if (_isEdit) ...[
                const SizedBox(height: 12),
                if (widget.product!.canDelete)
                  OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete product'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      minimumSize: const Size.fromHeight(50),
                    ),
                  )
                else
                  // Once sold, sales and stock history depend on it: hide instead.
                  Text(
                    'Sold ${widget.product!.soldCount} times, so it can only be hidden, not deleted.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                if (widget.product!.updatedByName != null && widget.product!.updatedByName!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Last changed by ${widget.product!.updatedByName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small grey section label ("WHAT IT IS") that breaks up the long form.
/// Just a label: nothing to tap.
class _Group extends StatelessWidget {
  const _Group(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.inkSoft),
      ),
    );
  }
}

/// Plain text field for the brand. While typing, brands already used on
/// other products drop down underneath; nothing shows when it's not being
/// typed in. Saving also matches "fcl" to an existing "FCL" (in
/// CatalogService), so a skipped suggestion still doesn't split a brand.
class _SourceField extends StatelessWidget {
  const _SourceField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final known = CatalogService.instance.knownSources;
    return LayoutBuilder(
      // The width, so the dropdown lines up exactly under the field.
      builder: (context, box) => RawAutocomplete<String>(
        textEditingController: controller,
        focusNode: focusNode,
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          if (q.isEmpty) return const Iterable<String>.empty();
          // Starts-with first ("Fc" -> FCL), then contains ("heus" ->
          // De Heus). An exact match isn't offered: it's already typed.
          final starts = known.where((s) => s.toLowerCase().startsWith(q));
          final contains = known.where((s) => !s.toLowerCase().startsWith(q) && s.toLowerCase().contains(q));
          return [...starts, ...contains].where((s) => s.toLowerCase() != q).take(5);
        },
        fieldViewBuilder: (context, textController, node, onSubmit) => TextFormField(
          controller: textController,
          focusNode: node,
          textCapitalization: TextCapitalization.words,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: 'Source (brand / maker)',
            hintText: 'e.g. FCL, De Heus, EABL',
            helperText: 'Optional. Leave blank for loose items.',
            counterText: '', // the 30-letter limit doesn't need a counter
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth, maxHeight: 240),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      title: Text(o),
                      onTap: () => onSelected(o),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}