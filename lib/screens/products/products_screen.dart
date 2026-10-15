import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/catalog_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/owner_pin_sheet.dart';
import '../scan/scan_screen.dart';
import 'product_form_screen.dart';
import 'product_picker_sheet.dart';
import 'receive_stock_sheet.dart';

/// Wireframe 7. Everyone can look up prices and stock here. Adding or
/// editing needs product access: the owner, or a cashier the owner trusts
/// with it; anyone else is asked for the owner PIN.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  bool _lowOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Product? product, {String? initialCode}) async {
    final ok = await requireProductAccess(
      context,
      reason: product == null ? 'to add a product' : 'to edit ${product.name}',
    );
    if (!ok || !mounted) return;
    // The form pops with a short message ("Sugar 1kg saved" / "... deleted").
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product, initialCode: initialCode)),
    );
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Edit product button: check access first (so a cashier without it
  /// isn't shown a picker they can't use), then pick, then edit.
  Future<void> _pickAndEdit() async {
    final ok = await requireProductAccess(context, reason: 'to edit a product');
    if (!ok || !mounted) return;
    final product = await showProductPicker(context, title: 'Edit which product?');
    if (product == null || !mounted) return;
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// A delivery arrived for this product. Same access rule as editing.
  Future<void> _addStock(Product product) async {
    final ok = await requireProductAccess(context, reason: 'to add stock to ${product.name}');
    if (!ok || !mounted) return;
    final message = await showReceiveStock(context, product);
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Price check: scan an item to jump to it. If it isn't in the list yet,
  /// offer to add it with the barcode already filled in.
  Future<void> _scanToFind() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    if (CatalogService.instance.byCode(code) != null) {
      setState(() {
        _lowOnly = false;
        _search.text = code;
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No product with barcode $code'),
        action: SnackBarAction(label: 'Add it', onPressed: () => _open(null, initialCode: code)),
      ),
    );
  }

  List<Product> _filter(List<Product> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((p) {
      if (_lowOnly && !p.isLow) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogService.instance;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: FloatingActionButton.extended(
                // Two FABs on one screen each need their own heroTag, or
                // Flutter errors when the page transition animates them.
                heroTag: 'addProduct',
                onPressed: () => _open(null),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FloatingActionButton.extended(
                heroTag: 'editProduct',
                onPressed: _pickAndEdit,
                backgroundColor: AppColors.accent,
                // Dark text on amber: white on amber is too faint to read.
                foregroundColor: AppColors.ink,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit product'),
              ),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: catalog,
        builder: (context, _) {
          final shown = _filter(catalog.products);
          final activeCount = catalog.products.where((p) => p.active).length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search name or barcode',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? IconButton(
                            tooltip: 'Scan to find',
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanToFind,
                          )
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text('Low stock (${catalog.lowCount})'),
                      selected: _lowOnly,
                      onSelected: (v) => setState(() => _lowOnly = v),
                      selectedColor: AppColors.warningBg,
                      checkmarkColor: AppColors.warning,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${shown.length} of $activeCount products',
                      style: const TextStyle(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: !catalog.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : shown.isEmpty
                        ? _Empty(hasAny: catalog.products.isNotEmpty)
                        : ListView.separated(
                            // Room under the last row so the two buttons never cover it.
                            padding: const EdgeInsets.only(bottom: 104),
                            itemCount: shown.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => _ProductRow(
                              product: shown[i],
                              onEdit: () => _open(shown[i]),
                              onAddStock: () => _addStock(shown[i]),
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onEdit, required this.onAddStock});

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final unit = p.isKg ? ' kg' : '';
    return InkWell(
      onTap: onEdit, // tapping the row still edits, as before
      child: Opacity(
        opacity: p.active ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(p.code, style: AppTheme.mono(size: 12, weight: FontWeight.w400, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    p.isKg ? '${ksh(p.price)} /kg' : ksh(p.price),
                    style: AppTheme.mono(size: 16),
                  ),
                  const SizedBox(height: 4),
                  if (!p.active)
                    const _Tag(text: 'Hidden', fg: AppColors.inkSoft, bg: AppColors.surfaceMuted)
                  else if (p.isLow)
                    _Tag(text: '${qty(p.stock)}$unit left', fg: AppColors.warning, bg: AppColors.warningBg)
                  else
                    Text('${qty(p.stock)}$unit in stock', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                ],
              ),
              const SizedBox(width: 4),
              // Hidden products can't be restocked until they're made
              // available again, so a delivery isn't booked to a dead item.
              if (p.active)
                IconButton(
                  tooltip: 'Add stock',
                  onPressed: onAddStock,
                  icon: const Icon(Icons.add_box_outlined, color: AppColors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.fg, required this.bg});

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasAny});

  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          hasAny ? 'No products match.' : 'No products yet.\nTap "Add product" to add the first one.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}