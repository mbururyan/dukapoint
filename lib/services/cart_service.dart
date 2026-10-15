import 'package:flutter/foundation.dart';

import '../models/product.dart';

/// One line in the cart.
class CartLine {
  CartLine(this.product, this.qty);

  /// A copy of the product as it was when scanned. The price is locked in
  /// at that moment: if the owner edits the price mid-sale on another
  /// phone, this customer still pays what the cashier told them.
  final Product product;
  double qty;

  String get code => product.code;
  int get unitPrice => product.price;

  /// Whole shillings. Weighed items round to the nearest shilling
  /// (0.75 kg x 130 = 97.5 -> 98), the money rule from the data model.
  int get total => (unitPrice * qty).round();
}

/// The sale being rung up right now. Lives outside any screen, so peeking
/// at another tab mid-sale doesn't lose it. Cleared at checkout (step 5)
/// and whenever a new shift starts.
class CartService extends ChangeNotifier {
  CartService._();
  static final instance = CartService._();

  /// Newest first, so each scan lands at the top where the cashier is looking.
  final List<CartLine> lines = [];

  /// The line last added to, highlighted on screen so the cashier can see
  /// which item a scan just counted.
  String? lastCode;

  bool get isEmpty => lines.isEmpty;

  /// "7 items": pieces count one each; a weighed line counts as one item,
  /// because "2.35 items" means nothing to a customer.
  int get itemCount => lines.fold(0, (sum, l) => sum + (l.product.isKg ? 1 : l.qty.round()));

  int get total => lines.fold(0, (sum, l) => sum + l.total);

  CartLine? lineFor(String code) {
    for (final l in lines) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// Scanning the same item again adds to its line instead of a new line.
  void add(Product product, double qty) {
    final existing = lineFor(product.code);
    if (existing != null) {
      existing.qty += qty;
    } else {
      lines.insert(0, CartLine(product, qty));
    }
    lastCode = product.code;
    notifyListeners();
  }

  /// Sets an exact quantity; zero or less removes the line.
  void setQty(String code, double qty) {
    final line = lineFor(code);
    if (line == null) return;
    if (qty <= 0) {
      lines.remove(line);
    } else {
      line.qty = qty;
      lastCode = code;
    }
    notifyListeners();
  }

  void remove(String code) => setQty(code, 0);

  void clear() {
    if (lines.isEmpty && lastCode == null) return;
    lines.clear();
    lastCode = null;
    notifyListeners();
  }
}