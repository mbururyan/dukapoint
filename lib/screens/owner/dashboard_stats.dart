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

  factory DashboardStats.from(List<Sale> sales) {
    final s = DashboardStats._();
    for (final sale in sales) {
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
      }
    }
    return s;
  }
}