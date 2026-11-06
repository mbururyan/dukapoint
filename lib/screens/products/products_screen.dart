import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The sort choices, in menu order. [short] is what the sort button shows,
/// so the cashier always knows why the list is in the order it is.
enum _Sort {
  newest('Recently added', 'Newest'),
  name('Name A–Z', 'A–Z'),
  priceUp('Price: low to high', 'Price ↑'),
  priceDown('Price: high to low', 'Price ↓'),
  lowStock('Lowest stock first', 'Low stock'),
  bestSellers('Best sellers', 'Best sellers');

  const _Sort(this.label, this.short);
  final String label;
  final String short;
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const _sortKey = 'productSort';

  final _search = TextEditingController();
  bool _lowOnly = false;
  _Sort _sort = _Sort.newest;

  @override
  void initState() {
    super.initState();
    _loadSort();
  }

  /// The choice is per phone (SharedPreferences), not per shop: the owner
  /// may like A–Z on their phone while the till phone shows newest.
  Future<void> _loadSort() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sortKey);
    final match = _Sort.values.where((s) => s.name == saved);
    if (match.isNotEmpty && mounted) setState(() => _sort = match.first);
  }

  Future<void> _setSort(_Sort s) async {
    setState(() => _sort = s);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortKey, s.name);
  }

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
    final list = all.where((p) {
      if (_lowOnly && !p.isLow) return false;
      if (q.isEmpty) return true;
      // Brand too, so typing "FCL" lists every FCL product.
      return p.name.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q) ||
          (p.source?.toLowerCase().contains(q) ?? false);
    }).toList();

    // A product added offline has no server date yet: count it as newest.
    final now = DateTime.now();
    int byName(Product a, Product b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    list.sort((a, b) {
      // Hidden products always sink to the bottom, whatever the sort.
      if (a.active != b.active) return a.active ? -1 : 1;
      final r = switch (_sort) {
        _Sort.newest => (b.createdAt ?? now).compareTo(a.createdAt ?? now),
        _Sort.name => 0,
        _Sort.priceUp => a.price.compareTo(b.price),
        _Sort.priceDown => b.price.compareTo(a.price),
        _Sort.lowStock => a.stock.compareTo(b.stock),
        _Sort.bestSellers => b.soldCount.compareTo(a.soldCount),
      };
      // Ties (same price, same stock...) fall back to A–Z, so the order
      // never jumps around between refreshes.
      return r != 0 ? r : byName(a, b);
    });
    return list;
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
                    hintText: 'Search name, brand or barcode',
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
                    Expanded(
                      child: Text(
                        '${shown.length} of $activeCount',
                        style: const TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                    PopupMenuButton<_Sort>(
                      tooltip: 'Sort products',
                      initialValue: _sort,
                      onSelected: _setSort,
                      itemBuilder: (_) => [
                        for (final s in _Sort.values)
                          PopupMenuItem(
                            value: s,
                            child: Row(
                              children: [
                                Expanded(child: Text(s.label)),
                                if (s == _sort) const Icon(Icons.check, size: 18, color: AppColors.primary),
                              ],
                            ),
                          ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort, size: 18, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              _sort.short,
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
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
                    // "FCL · 2000000001210": brand first, in ink, because
                    // it's the part people actually read; the code is grey.
                    Text.rich(
                      TextSpan(
                        children: [
                          if (p.source != null)
                            TextSpan(
                              text: '${p.source} · ',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                          TextSpan(
                            text: p.code,
                            style: AppTheme.mono(size: 12, weight: FontWeight.w400, color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                    _Tag(text: '${p.stockText} left', fg: AppColors.warning, bg: AppColors.warningBg)
                  else
                    Text('${p.stockText} in stock', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
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