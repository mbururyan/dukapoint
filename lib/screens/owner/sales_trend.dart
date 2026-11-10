import '../../models/sale.dart';
import '../../services/sales_service.dart';

/// One day's takings, for the "by day" charts.
class DayTotal {
  const DayTotal(this.day, this.total);

  final DateTime day;
  final int total;
}

/// Sums for the charts: by day, by hour, and "vs yesterday at this time".
///
/// Kept apart from DashboardStats on purpose: that class answers "what
/// happened in this period", this one answers "how does it move over time".
/// Both count PAID sales only, so the numbers always agree.
class SalesTrend {
  SalesTrend._();

  static Iterable<Sale> _paid(Iterable<Sale> sales) => sales.where((s) => s.status == 'paid');

  /// Every calendar day from [from] to [to], both included, with zero for
  /// days with no sales. Zero days must be there: a chart that skips them
  /// would hide exactly the slow days the owner should notice.
  static List<DayTotal> byDay(List<Sale> sales, DateTime from, DateTime to) {
    final sums = <String, int>{};
    for (final s in _paid(sales)) {
      sums[s.dayKey] = (sums[s.dayKey] ?? 0) + s.total;
    }
    final out = <DayTotal>[];
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    // DateTime(y, m, d + 1) instead of add(Duration(days: 1)): it stays on
    // midnight even on days a phone's clock jumps (time zone changes).
    while (!d.isAfter(end)) {
      out.add(DayTotal(d, sums[SalesService.dayKey(d)] ?? 0));
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }

  /// 24 slots (midnight to 11pm) of one day's takings.
  static List<int> byHour(List<Sale> sales, String dayKey) {
    final out = List<int>.filled(24, 0);
    for (final s in _paid(sales)) {
      if (s.dayKey == dayKey) out[s.at.hour] += s.total;
    }
    return out;
  }

  static int totalOn(List<Sale> sales, String dayKey) =>
      _paid(sales).where((s) => s.dayKey == dayKey).fold(0, (sum, s) => sum + s.total);

  static int countOn(List<Sale> sales, String dayKey) =>
      _paid(sales).where((s) => s.dayKey == dayKey).length;

  /// Today against yesterday UP TO THE SAME TIME of day. Comparing half a
  /// day with a whole one would make every morning look like a bad day.
  /// Null when yesterday had nothing by now: "+∞%" helps nobody.
  static int? changeVsYesterday(List<Sale> sales, DateTime now) {
    final todayKey = SalesService.dayKey(now);
    final yKey = SalesService.dayKey(DateTime(now.year, now.month, now.day - 1));
    final cutoff = now.hour * 60 + now.minute;

    var today = 0;
    var yesterday = 0;
    for (final s in _paid(sales)) {
      if (s.dayKey == todayKey) today += s.total;
      if (s.dayKey == yKey && s.at.hour * 60 + s.at.minute <= cutoff) yesterday += s.total;
    }
    if (yesterday == 0) return null;
    return ((today - yesterday) * 100 / yesterday).round();
  }

  /// Voided sales on one day, newest first, for the red strip.
  static List<Sale> voidedOn(List<Sale> sales, String dayKey) =>
      sales.where((s) => s.isCancelled && s.dayKey == dayKey).toList()..sort((a, b) => b.at.compareTo(a.at));
}