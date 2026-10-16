import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/cart_service.dart';
import '../../services/catalog_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/hid_scanner_listener.dart';
import '../../widgets/owner_pin_sheet.dart';
import '../../widgets/scanner_view.dart';
import '../products/product_form_screen.dart';
import '../products/product_picker_sheet.dart';
import 'checkout_screen.dart';
import 'qty_dialog.dart';

/// Wireframe 3. Camera on top, cart below, total and Charge at the bottom.
/// Items arrive three ways: camera scan, scanner gun, or "No barcode".
class SellScreen extends StatefulWidget {
  const SellScreen({super.key, required this.active});

  /// True while the Sell tab is the one showing. The shell keeps every tab
  /// alive in the background, so without this the camera would keep
  /// running (and draining the battery) while the cashier is on Products.
  final bool active;

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final _cart = CartService.instance;
  final _catalog = CatalogService.instance;
  final _gunFocus = FocusNode(debugLabel: 'scanner gun');

  bool _cameraOn = true;

  @override
  void didUpdateWidget(SellScreen old) {
    super.didUpdateWidget(old);
    // Coming back to the Sell tab: take keyboard focus back so the scanner
    // gun's "typing" lands here, not in a search box on another tab.
    if (widget.active && !old.active) _gunFocus.requestFocus();
  }

  @override
  void dispose() {
    _gunFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Adding items
  // ---------------------------------------------------------------------

  /// Every scan, from camera or gun, comes through here.
  Future<void> _onCode(String code) async {
    final product = _catalog.byCode(code);
    if (product == null) {
      _unknown(code);
      return;
    }
    await _addProduct(product);
  }

  Future<void> _addProduct(Product product) async {
    if (!product.active) {
      _snack('${product.name} is hidden from sale. Turn it back on in Products.');
      return;
    }
    if (product.isKg) {
      // Weighed items can't just be +1: ask what the scale says.
      final kg = await showQtyDialog(context, product);
      if (kg == null || !mounted) return;
      _cart.add(product, kg);
    } else {
      _cart.add(product, 1);
    }
  }

  void _unknown(String code) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Not in products: $code'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Add product', onPressed: () => _addNew(code)),
        ),
      );
  }

  /// Add a product nobody had entered yet, then drop it straight into the
  /// cart, so the customer at the counter isn't kept waiting twice.
  Future<void> _addNew(String code) async {
    final ok = await requireProductAccess(context, reason: 'to add a new product');
    if (!ok || !mounted) return;
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(initialCode: code)),
    );
    if (saved == null || !mounted) return;
    // The save lands in the phone's cache straight away, so the new
    // product is usually already in the catalogue by the time we look.
    final product = _catalog.byCode(code);
    if (product != null) await _addProduct(product);
  }

  Future<void> _noBarcode() async {
    final product = await showProductPicker(context, title: 'Add which item?');
    if (product != null && mounted) await _addProduct(product);
  }

  // ---------------------------------------------------------------------
  // Changing lines
  // ---------------------------------------------------------------------

  Future<void> _plus(CartLine line) async {
    if (line.product.isKg) {
      await _editQty(line);
    } else {
      _cart.setQty(line.code, line.qty + 1);
    }
  }

  void _minus(CartLine line) {
    // For kg lines "minus one kg" is meaningless; minus removes the line.
    final next = line.product.isKg ? 0.0 : line.qty - 1;
    _cart.setQty(line.code, next);
  }

  /// Tap the quantity to type it: 20 bags is quicker typed than tapped.
  Future<void> _editQty(CartLine line) async {
    final n = await showQtyDialog(context, line.product, initial: line.qty);
    if (n != null) _cart.setQty(line.code, n);
  }

  Future<void> _clear() async {
    if (_cart.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear the cart?'),
        content: Text('${_cart.itemCount} items will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes == true) _cart.clear();
  }

  void _charge() {
    // Checkout reads the cart from CartService directly, so nothing needs
    // passing in. It replaces itself with the receipt when payment is done.
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return HidScannerListener(
      focusNode: _gunFocus,
      enabled: widget.active,
      onScan: _onCode,
      child: ListenableBuilder(
        listenable: _cart,
        builder: (context, _) => Column(
          children: [
            SizedBox(height: 210, child: _cameraArea()),
            _cartHeader(),
            const Divider(height: 1),
            Expanded(child: _cartList()),
            _totalBar(),
          ],
        ),
      ),
    );
  }

  Widget _cameraArea() {
    // Only build the camera while this tab is visible AND the cashier wants
    // it. Not building it releases the camera completely.
    final showCamera = widget.active && _cameraOn;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showCamera)
          ScannerView(onCode: _onCode, hint: 'Scan a barcode')
        else
          Container(
            color: const Color(0xFF1B1D21),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 32),
                const SizedBox(height: 8),
                const Text('Camera off · scanner gun ready', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _cameraOn = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Turn camera on'),
                ),
              ],
            ),
          ),
        if (showCamera)
          Positioned(
            top: 8,
            left: 8,
            child: IconButton.filledTonal(
              tooltip: 'Turn camera off',
              onPressed: () => setState(() => _cameraOn = false),
              icon: const Icon(Icons.videocam_off_outlined),
            ),
          ),
      ],
    );
  }

  Widget _cartHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Cart · ${_cart.itemCount} ${_cart.itemCount == 1 ? 'item' : 'items'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _noBarcode,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('No barcode'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              visualDensity: VisualDensity.compact,
            ),
          ),
          TextButton(
            onPressed: _cart.isEmpty ? null : _clear,
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _cartList() {
    if (_cart.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Cart is empty.\nScan an item, use the scanner gun, or tap "No barcode".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.inkSoft),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _cart.lines.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final line = _cart.lines[i];
        return _LineRow(
          line: line,
          highlighted: line.code == _cart.lastCode,
          // Live stock from the catalogue, not the snapshot in the cart.
          stock: _catalog.byCode(line.code)?.stock,
          onPlus: () => _plus(line),
          onMinus: () => _minus(line),
          onQtyTap: () => _editQty(line),
        );
      },
    );
  }

  Widget _totalBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('Total', style: TextStyle(fontSize: 15, color: AppColors.inkSoft)),
              Text(ksh(_cart.total), style: AppTheme.mono(size: 26)),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _cart.isEmpty ? null : _charge,
            child: Text(_cart.isEmpty ? 'Charge' : 'Charge ${ksh(_cart.total)}'),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.highlighted,
    required this.stock,
    required this.onPlus,
    required this.onMinus,
    required this.onQtyTap,
  });

  final CartLine line;
  final bool highlighted;
  final double? stock;
  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final VoidCallback onQtyTap;

  @override
  Widget build(BuildContext context) {
    final p = line.product;
    final over = stock != null && line.qty > stock!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      color: highlighted ? AppColors.primaryTint : AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  p.isKg ? '@ ${ksh(p.price)} /kg' : '@ ${ksh(p.price)}',
                  style: AppTheme.mono(size: 13, weight: FontWeight.w400, color: AppColors.inkSoft),
                ),
                // A hint, not a block: selling past the recorded stock is
                // allowed (the stock count may simply be out of date).
                if (over)
                  Text(
                    'Only ${qty(stock!)}${p.isKg ? ' kg' : ''} in stock',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: p.isKg ? 'Remove' : 'One less',
                  onPressed: onMinus,
                  icon: Icon(p.isKg ? Icons.close : Icons.remove, size: 20),
                ),
                InkWell(
                  onTap: onQtyTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Text(
                      p.isKg ? '${qty(line.qty)}kg' : qty(line.qty),
                      style: AppTheme.mono(size: 16),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: p.isKg ? 'Change weight' : 'One more',
                  onPressed: onPlus,
                  icon: Icon(p.isKg ? Icons.edit_outlined : Icons.add, size: 20),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 78,
            child: Text(kes(line.total), textAlign: TextAlign.right, style: AppTheme.mono(size: 16)),
          ),
        ],
      ),
    );
  }
}