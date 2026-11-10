import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/catalog_service.dart';
import '../../services/sales_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/counting.dart';
import '../../utils/format.dart';
import '../../widgets/sales_charts.dart';
import '../../widgets/status_banners.dart';
import '../sell/receipt_screen.dart';
import 'dashboard_stats.dart';
import 'sales_trend.dart';

enum SummaryRange { today, week, month }

/// Everything that used to sit on the Owner tab: totals, the cash / M-Pesa
/// split, voids, by cashier, by source, top items. Plus one chart:
/// by hour for Today (when are we busy?), by day otherwise (are we growing?).
class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key, this.initial = SummaryRange.today});

  final SummaryRange initial;

  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  late SummaryRange _range = widget.initial;
  late Stream<List<Sale>> _sales;

  @override
  void initState() {
    super.initState();
    _sales = _streamFor(_range);
  }

  /// First day of the range. "7 days" means today plus the six before it,
  /// so it always shows a full week whatever the weekday.
  DateTime _startOf(SummaryRange r) {
    final now = DateTime.now();
    return switch (r) {
      SummaryRange.today => DateTime(now.year, now.month, now.day),
      SummaryRange.week => DateTime(now.year, now.month, now.day - 6),
      SummaryRange.month => DateTime(now.year, now.month, 1),
    };
  }

  /// Always reaches back to at least yesterday, even for Today: the
  /// "vs yesterday at this time" line needs yesterday's sales. They're
  /// filtered out again before any totals are worked out.
  Stream<List<Sale>> _streamFor(SummaryRange r) {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final start = _startOf(r);
    final from = start.isBefore(yesterday) ? start : yesterday;
    return SalesService.instance.salesFrom(SalesService.dayKey(from));
  }

  void _pick(SummaryRange r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      // A new listener only when the range changes, never on every redraw.
      _sales = _streamFor(r);
    });
  }

  String get _rangeLabel => switch (_range) {
        SummaryRange.today => 'today',
        SummaryRange.week => 'last 7 days',
        SummaryRange.month => 'this month',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<SummaryRange>(
            segments: const [
              ButtonSegment(value: SummaryRange.today, label: Text('Today')),
              ButtonSegment(value: SummaryRange.week, label: Text('7 days')),
              ButtonSegment(value: SummaryRange.month, label: Text('This month')),
            ],
            selected: {_range},
            onSelectionChanged: (s) => _pick(s.first),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Sale>>(
            stream: _sales,
            builder: (context, snap) {
              if (snap.hasError) {
                return _Card(child: Text('Could not load sales.\n${snap.error}'));
              }
              if (!snap.hasData) {
                return const _Card(child: Center(child: CircularProgressIndicator()));
              }
              final now = DateTime.now();
              final all = snap.data!;
              final startKey = SalesService.dayKey(_startOf(_range));
              // dayKeys compare as text in date order ("2026-11-09" < "2026-11-10").
              final inRange = all.where((s) => s.dayKey.compareTo(startKey) >= 0).toList();

              final catalog = CatalogService.instance;
              final stats = DashboardStats.from(
                inRange,
                currentSourceOf: (id) => catalog.byCode(id)?.source,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SalesCard(
                    stats: stats,
                    rangeLabel: _rangeLabel,
                    change: _range == SummaryRange.today ? SalesTrend.changeVsYesterday(all, now) : null,
                  ),
                  const SizedBox(height: 12),
                  // Keyed by range so a tapped bar doesn't carry over to
                  // a chart of a different shape.
                  _ChartCard(key: ValueKey(_range), range: _range, sales: inRange, start: _startOf(_range), now: now),
                  // Only when there's something to see: a permanent "0 voids"
                  // tile would teach the owner to stop looking at it.
                  if (stats.voided.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _VoidsTile(stats: stats, rangeLabel: _rangeLabel),
                  ],
                  if (!stats.isEmpty) ...[
                    const SizedBox(height: 12),
                    _ByCashierCard(stats: stats),
                    if (stats.hasSources) ...[
                      const SizedBox(height: 12),
                      _BySourceCard(stats: stats, rangeLabel: _rangeLabel),
                    ],
                    const SizedBox(height: 12),
                    _TopItemsCard(stats: stats),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Sales card: the headline number, the cash / M-Pesa split, profit
// -------------------------------------------------------------------------

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.stats, required this.rangeLabel, this.change});

  final DashboardStats stats;
  final String rangeLabel;

  /// % vs yesterday at this time. Today only; null hides the line.
  final int? change;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sales · $rangeLabel', style: const TextStyle(color: AppColors.inkSoft)),
              Text('${s.count} ${s.count == 1 ? 'sale' : 'sales'}', style: const TextStyle(color: AppColors.inkSoft)),
            ],
          ),
          const SizedBox(height: 4),
          Text(ksh(s.total), style: AppTheme.mono(size: 34)),
          if (change != null) ...[
            const SizedBox(height: 2),
            ChangeLine(change: change!),
          ],
          if (s.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('No sales yet $rangeLabel.', style: const TextStyle(color: AppColors.inkSoft)),
            )
          else ...[
            const SizedBox(height: 14),
            _SplitBar(cash: s.cash, mpesa: s.mpesa),
            const SizedBox(height: 10),
            // The legend doubles as the table: every value is written out,
            // so nobody has to judge amounts from bar lengths or colour.
            _LegendRow(color: AppColors.cash, label: 'Cash', value: s.cash),
            const SizedBox(height: 6),
            _LegendRow(color: AppColors.mpesa, label: 'M-Pesa', value: s.mpesa),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Est. profit'),
                Text(ksh(s.profit), style: AppTheme.mono(size: 16)),
              ],
            ),
            if (s.profitIsPartial)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Covers ${s.linesWithCost} of ${s.linesTotal} items sold. Add buying prices to the rest for a full figure.',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "▲ 12% vs yesterday at this time". The arrow and the words carry the
/// meaning; the colour only backs them up. Shared with the Owner tab.
class ChangeLine extends StatelessWidget {
  const ChangeLine({super.key, required this.change, this.size = 13});

  final int change;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (text, color) = change > 0
        ? ('▲ $change% vs yesterday at this time', AppColors.success)
        : change < 0
            ? ('▼ ${-change}% vs yesterday at this time', AppColors.danger)
            : ('Same as yesterday at this time', AppColors.inkSoft);
    return Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: color));
  }
}

/// Two-part bar: cash then M-Pesa, each as long as its share.
/// A 2px white gap separates them, and the ends are rounded.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.cash, required this.mpesa});

  final int cash;
  final int mpesa;

  @override
  Widget build(BuildContext context) {
    final total = cash + mpesa;
    if (total == 0) return const SizedBox.shrink();
    return Semantics(
      label: 'Cash ${ksh(cash)}, M-Pesa ${ksh(mpesa)}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 12,
          child: Row(
            children: [
              if (cash > 0) Expanded(flex: cash, child: Container(color: AppColors.cash)),
              if (cash > 0 && mpesa > 0) const SizedBox(width: 2),
              if (mpesa > 0) Expanded(flex: mpesa, child: Container(color: AppColors.mpesa)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        // Values in ink, not in the series colour: amber text on white
        // is too faint to read.
        Text(ksh(value), style: AppTheme.mono(size: 15)),
      ],
    );
  }
}

// -------------------------------------------------------------------------
// The chart: by hour (Today) or by day (7 days, This month)
// -------------------------------------------------------------------------

class _ChartCard extends StatefulWidget {
  const _ChartCard({super.key, required this.range, required this.sales, required this.start, required this.now});

  final SummaryRange range;
  final List<Sale> sales; // already limited to the range
  final DateTime start;
  final DateTime now;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _selected;

  static String _hour(int h) => switch (h) {
        0 => '12am',
        12 => '12pm',
        < 12 => '${h}am',
        _ => '${h - 12}pm',
      };

  static String _hourSpan(int h) => '${_hour(h)}–${_hour((h + 1) % 24)}';

  @override
  Widget build(BuildContext context) {
    return widget.range == SummaryRange.today ? _byHour() : _byDay();
  }

  Widget _byHour() {
    final todayKey = SalesService.dayKey(widget.now);
    final hours = SalesTrend.byHour(widget.sales, todayKey);
    final nowHour = widget.now.hour;

    // Show the working day, stretched if a sale happened outside it:
    // 8am to 8pm normally, earlier or later only when there's a reason.
    var first = 8;
    var last = 20;
    for (var h = 0; h < 24; h++) {
      if (hours[h] > 0) {
        if (h < first) first = h;
        if (h > last) last = h;
      }
    }
    if (nowHour > last) last = nowHour;
    final values = hours.sublist(first, last + 1);
    final labels = [for (var h = first; h <= last; h++) (h - first) % 3 == 0 ? _hour(h) : ''];
    final futureFrom = nowHour + 1 - first;

    var busiest = -1;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > 0 && (busiest < 0 || values[i] > values[busiest])) busiest = i;
    }
    final sel = _selected != null && _selected! < values.length ? _selected : null;

    final caption = sel != null
        ? '${_hourSpan(first + sel)} · ${ksh(values[sel])}'
        : busiest < 0
            ? 'No sales yet today'
            : 'Busiest so far: ${_hourSpan(first + busiest)} · ${ksh(values[busiest])}';

    return _frame(
      title: 'Sales by hour',
      caption: caption,
      chart: ColumnBars(
        values: values,
        labels: labels,
        height: 110,
        futureFrom: futureFrom < values.length ? futureFrom : null,
        onSelect: (i) => setState(() => _selected = i),
      ),
    );
  }

  Widget _byDay() {
    final days = SalesTrend.byDay(widget.sales, widget.start, widget.now);
    final n = days.length;
    final week = widget.range == SummaryRange.week;
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final labels = <String>[];
    for (var i = 0; i < n; i++) {
      if (i == n - 1) {
        labels.add('Today');
      } else if (week) {
        labels.add(wd[days[i].day.weekday - 1]);
      } else {
        // A month: the 1st, 8th, 15th, 22nd... but never one so close to
        // "Today" that the two collide.
        labels.add(i % 7 == 0 && n - 1 - i >= 3 ? '${days[i].day.day}' : '');
      }
    }

    var busiest = -1;
    for (var i = 0; i < n; i++) {
      if (days[i].total > 0 && (busiest < 0 || days[i].total > days[busiest].total)) busiest = i;
    }
    final sel = _selected != null && _selected! < n ? _selected : null;

    final caption = sel != null
        ? '${planDate(days[sel].day)} · ${ksh(days[sel].total)}'
        : busiest < 0
            ? 'No sales in this period'
            : 'Busiest: ${planDate(days[busiest].day)} · ${ksh(days[busiest].total)} · tap the line for any day';

    return _frame(
      title: 'Sales by day',
      caption: caption,
      chart: TrendLine(
        values: [for (final d in days) d.total],
        labels: labels,
        onSelect: (i) => setState(() => _selected = i),
      ),
    );
  }

  Widget _frame({required String title, required String caption, required Widget chart}) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          // The caption is the readout: the busiest slot by default, the
          // tapped one after a tap. Same spot, so nothing jumps around.
          Text(caption, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
          const SizedBox(height: 12),
          chart,
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Voided sales: the anti-fraud alert
// -------------------------------------------------------------------------

/// "2 voided sales · Ksh 3,400". Red so it's noticed even on a day the
/// owner wasn't in the shop: a cashier quietly voiding cash sales and
/// keeping the money is the classic till fraud this exists to catch.
class _VoidsTile extends StatelessWidget {
  const _VoidsTile({required this.stats, required this.rangeLabel});

  final DashboardStats stats;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    final n = stats.voided.length;
    return Material(
      color: const Color(0xFFFEE4E2),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showVoidedSales(context, stats.voided, rangeLabel),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.block, color: AppColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$n voided ${n == 1 ? 'sale' : 'sales'} · ${ksh(stats.voidTotal)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.danger),
                    ),
                    Text(
                      'Not counted in sales $rangeLabel. Tap to see which and why.',
                      style: const TextStyle(fontSize: 13, color: AppColors.danger),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.danger),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list of voided sales, with reason and who asked. Public: the red
/// strip on the Owner tab opens the same sheet.
void showVoidedSales(BuildContext context, List<Sale> voided, String rangeLabel) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Voided sales · $rangeLabel', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final s in voided)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  s.receiptNo,
                  s.cancelReason ?? 'No reason',
                  if ((s.requestedByName ?? '').isNotEmpty) 'asked by ${s.requestedByName}',
                  if (s.cancelledAt != null) dayTime(s.cancelledAt!),
                ].join(' · '),
              ),
              trailing: Text(ksh(s.total), style: AppTheme.mono(size: 15)),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReceiptScreen(sale: s, viewOnly: true)),
                );
              },
            ),
        ],
      ),
    ),
  );
}

// -------------------------------------------------------------------------
// By cashier, by source, top items (moved here unchanged from the Owner tab)
// -------------------------------------------------------------------------

class _ByCashierCard extends StatelessWidget {
  const _ByCashierCard({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('By cashier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final c in stats.byCashier)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: c.name.isEmpty ? 'Unknown' : c.name),
                          TextSpan(
                            text: '  · ${c.sales} ${c.sales == 1 ? 'sale' : 'sales'}',
                            style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(ksh(c.total), style: AppTheme.mono(size: 15)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sales per brand: one ranked bar each, biggest first, amount and share
/// written out so nobody has to judge bar lengths. Tap a brand to see its
/// top three items. Blue on purpose: amber and green already mean cash and
/// M-Pesa on this screen, and plum means "button".
class _BySourceCard extends StatefulWidget {
  const _BySourceCard({required this.stats, required this.rangeLabel});

  final DashboardStats stats;
  final String rangeLabel;

  @override
  State<_BySourceCard> createState() => _BySourceCardState();
}

class _BySourceCardState extends State<_BySourceCard> {
  static const _noSourceBar = Color(0xFF9CA3AF);
  static const _track = Color(0xFFEEF2F7);

  // Which brands are open. By name, so they stay open when new sales
  // arrive and the card rebuilds.
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final sources = widget.stats.bySource;
    final total = widget.stats.total;
    // Bars are scaled to the biggest brand (full width), not to 100% of
    // sales: small brands stay visible next to one dominant one.
    final max = sources.fold<int>(0, (m, s) => s.revenue > m ? s.revenue : m);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('By source', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            'Sales ${widget.rangeLabel} · tap a source for its top items',
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 12),
          for (final s in sources) _row(s, total, max),
        ],
      ),
    );
  }

  Widget _row(SourceTotal s, int total, int max) {
    final key = s.name ?? '';
    final isOpen = _open.contains(key);
    final pct = total == 0 ? 0 : (s.revenue * 100 / total).round();
    final share = max == 0 ? 0.0 : s.revenue / max;
    final label = s.name ?? 'No source';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => isOpen ? _open.remove(key) : _open.add(key)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(isOpen ? Icons.expand_more : Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                const SizedBox(width: 2),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: '  $pct%', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                      ],
                    ),
                  ),
                ),
                // Values in ink, never the bar colour (text stays readable).
                Text(ksh(s.revenue), style: AppTheme.mono(size: 15)),
              ],
            ),
            const SizedBox(height: 6),
            Semantics(
              label: '$label ${ksh(s.revenue)}, $pct percent of sales',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 10,
                  color: _track,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: share.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: s.name == null ? _noSourceBar : ChartColors.bar,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (isOpen) ...[
              const SizedBox(height: 6),
              for (final i in s.topItems())
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 3, 0, 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: i.name),
                              TextSpan(
                                text: ' · ${countOf(i.qty, unit: i.unit, word: i.word)}',
                                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(kes(i.revenue), style: AppTheme.mono(size: 13, weight: FontWeight.w500)),
                    ],
                  ),
                ),
              if (s.itemCount > 3)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 0, 0),
                  child: Text(
                    '+ ${s.itemCount - 3} more ${s.itemCount - 3 == 1 ? 'item' : 'items'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopItemsCard extends StatelessWidget {
  const _TopItemsCard({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final items = stats.topItems();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Top items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          const Text('By money taken', style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          const SizedBox(height: 10),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.name),
                        Text(
                          i.unit == 'kg' ? '${qty(i.qty)} kg sold' : '${qty(i.qty)} sold',
                          style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Text(ksh(i.revenue), style: AppTheme.mono(size: 15)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}