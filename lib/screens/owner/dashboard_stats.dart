import '../../models/sale.dart';

/// Totals for the owner dashboard, worked out from a list of sales.
/// Kept apart from the screen so the sums are easy to read and check.
class CashierTotal {
  CashierTotal(this.name);
  final String name;
  int sales = 0;
  int total = 0;
}

class ItemTotal {
  ItemTotal(this.name, this.unit);
  final String name;
  final String unit;
  double qty = 0;
  int revenue = 0;
}

/// One product's share of a brand's sales, for the By source card.
class SourceItem {
  SourceItem(this.name, this.unit, this.word);
  final String name;
  final String unit;
  final String word; // 'bag', 'bottle'... for "12 bags"
  double qty = 0;
  int revenue = 0;
}

/// One brand's sales in the period. [name] is null for "No source".
class SourceTotal {
  SourceTotal(this.name);
  final String? name;
  int revenue = 0;
  final Map<String, SourceItem> _items = {};

  int get itemCount => _items.length;

  /// Best sellers within this brand, by money taken.
  List<SourceItem> topItems([int n = 3]) {
    final list = _items.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list.take(n).toList();
  }
}

class DashboardStats {
  DashboardStats._();

  int count = 0;
  int total = 0;
  int cash = 0;
  int mpesa = 0;

  int profit = 0;
  int linesWithCost = 0; // how many sold lines had a buying price
  int linesTotal = 0;

  final Map<String, CashierTotal> _cashiers = {};
  final Map<String, ItemTotal> _items = {};

  /// Voided sales in the period, newest first. Kept apart from the money
  /// figures so the owner sees them as their own alert, not a smaller total.
  final List<Sale> voided = [];
  int voidTotal = 0;

  // Keyed by lower-case brand so "FCL" on one sale and "Fcl" on an older
  // one still add up together; '' is "No source".
  final Map<String, SourceTotal> _sources = {};

  /// Biggest brand first; "No source" always last, whatever its size.
  List<SourceTotal> get bySource {
    final list = _sources.values.toList()
      ..sort((a, b) {
        if ((a.name == null) != (b.name == null)) return a.name == null ? 1 : -1;
        return b.revenue.compareTo(a.revenue);
      });
    return list;
  }

  /// Worth showing the card only once at least one product has a brand;
  /// otherwise it would be a single grey "No source 100%" bar.
  bool get hasSources => _sources.values.any((s) => s.name != null);

  bool get isEmpty => count == 0;

  /// Profit is only honest if it says how much of the sales it covers:
  /// lines with no buying price add sales but no cost, so they'd inflate it.
  bool get profitIsPartial => linesWithCost < linesTotal;

  List<CashierTotal> get byCashier => _cashiers.values.toList()..sort((a, b) => b.total.compareTo(a.total));

  /// Top sellers by money taken, not quantity: "40 sweets" shouldn't
  /// outrank "3 bags of feed" just because sweets are counted in ones.
  List<ItemTotal> topItems([int n = 5]) {
    final list = _items.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list.take(n).toList();
  }

  /// [currentSourceOf] gives a product's brand as it is today. It's only
  /// used for sale lines saved before brands existed (no source on the
  /// line), so those older sales still land under the right brand.
  factory DashboardStats.from(List<Sale> sales, {String? Function(String productId)? currentSourceOf}) {
    final s = DashboardStats._();
    for (final sale in sales) {
      if (sale.isCancelled) {
        s.voided.add(sale);
        s.voidTotal += sale.total;
        continue;
      }
      // Pending (M-Pesa prompt not confirmed yet) and cancelled sales are
      // not money in the till, so they stay out of every figure here.
      if (sale.status != 'paid') continue;

      s.count++;
      s.total += sale.total;
      if (sale.method == 'cash') {
        s.cash += sale.total;
      } else {
        s.mpesa += sale.total; // till now, STK prompt later
      }

      final who = s._cashiers.putIfAbsent(sale.cashierId, () => CashierTotal(sale.cashierName));
      who.sales++;
      who.total += sale.total;

      for (final i in sale.items) {
        s.linesTotal++;
        if (i.buyPrice != null) {
          s.linesWithCost++;
          s.profit += i.lineTotal - (i.buyPrice! * i.qty).round();
        }
        final item = s._items.putIfAbsent(i.productId, () => ItemTotal(i.name, i.unit));
        item.qty += i.qty;
        item.revenue += i.lineTotal;

        final brand = i.source ?? currentSourceOf?.call(i.productId);
        final src = s._sources.putIfAbsent(brand?.toLowerCase() ?? '', () => SourceTotal(brand));
        src.revenue += i.lineTotal;
        final si = src._items.putIfAbsent(i.productId, () => SourceItem(i.name, i.unit, i.countedAs));
        si.qty += i.qty;
        si.revenue += i.lineTotal;
      }
    }
    // Newest void first: the one the owner most likely wants to check.
    s.voided.sort((a, b) => (b.cancelledAt ?? b.at).compareTo(a.cancelledAt ?? a.at));
    return s;
  }
}