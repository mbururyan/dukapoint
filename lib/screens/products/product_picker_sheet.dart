import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/catalog_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../scan/scan_screen.dart';

/// Slide-up "which product?" picker: search by name/barcode or scan.
/// Returns the chosen product, or null if closed.
///
/// Used by the Edit product button now; the Sell screen's "No barcode"
/// button can reuse it in step 4 for feed bags and loose items.
Future<Product?> showProductPicker(BuildContext context, {String title = 'Choose a product'}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ProductPicker(title: title),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.title});

  final String title;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final p = CatalogService.instance.byCode(code);
    if (p != null) {
      Navigator.pop(context, p); // exact match: no need to tap it in a list
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No product with barcode $code')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final all = CatalogService.instance.products;
    final shown = q.isEmpty
        ? all
        : all.where((p) => p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        // Tall enough to show a useful list, but leaves the top of the
        // screen visible so it still feels like a sheet, not a new page.
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search name or barcode',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Scan',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scan,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Text('No products match.', style: TextStyle(color: AppColors.inkSoft)),
                    )
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = shown[i];
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(p.code, style: AppTheme.mono(size: 12, weight: FontWeight.w400, color: AppColors.inkSoft)),
                          trailing: Text(
                            p.isKg ? '${ksh(p.price)} /kg' : ksh(p.price),
                            style: AppTheme.mono(size: 15),
                          ),
                          // Hidden products are still pickable here, so they
                          // can be edited and made available again.
                          enabled: true,
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}