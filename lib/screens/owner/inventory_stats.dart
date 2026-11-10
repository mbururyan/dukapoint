import '../../models/product.dart';
import '../../models/sale.dart';
import '../../services/sales_service.dart';

/// A product with how fast it's selling.
class StockPace {
  const StockPace(this.product, {required this.sold, required this.daysLeft});

  final Product product;

  /// Units sold in the last [InventoryStats.paceDays] days.
  final double sold;

  /// Days until it runs out at that pace. Null when it hasn't sold lately:
  /// "never runs out" would be a lie, it just isn't moving.
  final double? daysLeft;
}

/// One line of a supplier order.
class OrderLine {
  const OrderLine(this.product, this.qty, {required this.why});

  final Product product;

  /// How many to order. Null = "check": no recent sales to work it out
  /// from, so the owner decides rather than the app guessing.
  final double? qty;

  /// "Out", "Low", "~3 days left": why it's on the list.
  final String why;
}

class SourceValue {
  const SourceValue(this.name, this.value);

  final String? name; // null = no source
  final int value; // at cost
}

/// Everything the Inventory page shows, worked out in one pass.
///
/// "Low" and "out" come from the products alone, exactly as on the
/// Products tab, so the counts agree everywhere. Sales only add the pace:
/// days left, order quantities, and what isn't moving.
class InventoryStats {
  InventoryStats._({
    required this.costValue,
    required this.retailValue,
    required this.inStock,
    required this.low,
    required this.out,
    required this.bySource,
    required this.outItems,
    required this.lowItems,
    required this.toOrder,
    required this.notMoving,
    required this.missingCost,
  });

  /// Pace is the last 14 days of sales: long enough that one slow or busy
  /// week doesn't swing it, short enough to follow the season.
  static const paceDays = 14;

  /// Order enough to last this long.
  static const coverDays = 14;

  /// Above its warning level but gone within this many days: still goes
  /// on the order list, so a fast seller is caught early.
  static const soonDays = 7;

  /// No sales in this long = "not moving".
  static const idleDays = 30;

  /// Stock at what it cost (products with a buying price only).
  final int costValue;

  /// The same products at selling price.
  final int retailValue;
  int get profitWaiting => retailValue - costValue;

  final int inStock;
  final int low;
  final int out;

  final List<SourceValue> bySource; // biggest first, "no source" last
  final List<StockPace> outItems; // most missed first
  final List<StockPace> lowItems; // soonest to run out first

  /// Grouped by source, A–Z, "no source" (null key) last.
  final Map<String?, List<OrderLine>> toOrder;
  final List<StockPace> notMoving; // most money tied up first
  final List<Product> missingCost;

  bool get isEmpty => inStock + low + out == 0;

  factory InventoryStats.from(List<Product> products, List<Sale> sales, DateTime now) {
    final paceFrom = SalesService.dayKey(DateTime(now.year, now.month, now.day - (paceDays - 1)));
    final idleFrom = SalesService.dayKey(DateTime(now.year, now.month, now.day - (idleDays - 1)));

    // Units sold per product: recent (for pace) and at all lately (for idle).
    final sold = <String, double>{};
    final soldLately = <String>{};
    for (final s in sales) {
      if (s.status != 'paid' || s.dayKey.compareTo(idleFrom) < 0) continue;
      for (final i in s.items) {
        soldLately.add(i.productId);
        if (s.dayKey.compareTo(paceFrom) >= 0) sold[i.productId] = (sold[i.productId] ?? 0) + i.qty;
      }
    }

    StockPace paceOf(Product p) {
      final n = sold[p.code] ?? 0;
      return StockPace(p, sold: n, daysLeft: n > 0 && p.stock > 0 ? p.stock / (n / paceDays) : null);
    }

    var cost = 0.0, retail = 0.0;
    var inStock = 0, low = 0, out = 0;
    final srcValue = <String?, double>{};
    final outItems = <StockPace>[];
    final lowItems = <StockPace>[];
    final order = <String?, List<OrderLine>>{};
    final idle = <StockPace>[];
    final missing = <Product>[];
    final idleCutoff = DateTime(now.year, now.month, now.day - idleDays);

    for (final p in products) {
      if (!p.active) continue; // hidden items aren't for sale or reordering
      final pace = paceOf(p);
      final isOut = p.stock <= 0;
      final isLow = !isOut && p.stock <= p.lowStockAt;

      if (isOut) {
        out++;
        outItems.add(pace);
      } else if (isLow) {
        low++;
        lowItems.add(pace);
      } else {
        inStock++;
      }

      if (p.stock > 0) {
        if (p.buyPrice == null) {
          missing.add(p);
        } else {
          final c = p.stock * p.buyPrice!;
          cost += c;
          retail += p.stock * p.price;
          srcValue[p.source] = (srcValue[p.source] ?? 0) + c;
        }
        // Not moving: has stock, no sale in 30 days, and isn't brand new
        // (a product added last week hasn't had the chance to sell).
        final created = p.createdAt;
        if (!soldLately.contains(p.code) && (created == null || created.isBefore(idleCutoff))) {
          idle.add(pace);
        }
      }

      // The order list: out, low, or about to be.
      final soon = pace.daysLeft != null && pace.daysLeft! < soonDays;
      if (isOut || isLow || soon) {
        final why = isOut
            ? 'Out'
            : isLow
                ? 'Low'
                : '~${pace.daysLeft!.floor()} ${pace.daysLeft!.floor() == 1 ? 'day' : 'days'} left';
        // Enough for coverDays at the current pace, minus what's on the
        // shelf, rounded UP: nobody orders 23.4 bags, and short is worse
        // than one spare.
        final need = pace.sold / paceDays * coverDays - (p.stock > 0 ? p.stock : 0);
        final qty = pace.sold > 0 && need > 0 ? need.ceilToDouble() : null;
        order.putIfAbsent(p.source, () => []).add(OrderLine(p, qty, why: why));
      }
    }

    outItems.sort((a, b) => b.sold.compareTo(a.sold));
    lowItems.sort((a, b) {
      final da = a.daysLeft ?? double.infinity;
      final db = b.daysLeft ?? double.infinity;
      return da != db ? da.compareTo(db) : a.product.stock.compareTo(b.product.stock);
    });
    idle.sort((a, b) => _tiedUp(b.product).compareTo(_tiedUp(a.product)));
    missing.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final sources = [for (final e in srcValue.entries) SourceValue(e.key, e.value.round())]
      ..sort((a, b) {
        if ((a.name == null) != (b.name == null)) return a.name == null ? 1 : -1;
        return b.value.compareTo(a.value);
      });

    final orderKeys = order.keys.toList()
      ..sort((a, b) {
        if ((a == null) != (b == null)) return a == null ? 1 : -1;
        return a!.toLowerCase().compareTo(b!.toLowerCase());
      });
    for (final lines in order.values) {
      // Real numbers first, "check" items after, so the order reads cleanly.
      lines.sort((a, b) => (a.qty == null ? 1 : 0).compareTo(b.qty == null ? 1 : 0));
    }

    return InventoryStats._(
      costValue: cost.round(),
      retailValue: retail.round(),
      inStock: inStock,
      low: low,
      out: out,
      bySource: sources,
      outItems: outItems,
      lowItems: lowItems,
      toOrder: {for (final k in orderKeys) k: order[k]!},
      notMoving: idle,
      missingCost: missing,
    );
  }

  /// Money sitting on the shelf for one product: at cost when known,
  /// otherwise at selling price, so idle items still sort sensibly.
  static double _tiedUp(Product p) => p.stock * (p.buyPrice ?? p.price);
}