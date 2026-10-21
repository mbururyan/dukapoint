import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/catalog_service.dart';
import '../../services/sales_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'dashboard_stats.dart';
import 'staff_screen.dart';
import 'stock_history_screen.dart';

/// Wireframe 9: the owner's view. Sales for a period, how they were paid,
/// who sold, what sold, what's running low, and the plan status.
/// Live: a sale rung up on the till phone appears here within seconds.
class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key});

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

enum _Range { today, week, month }

class _OwnerHomeState extends State<OwnerHome> {
  _Range _range = _Range.today;
  late Stream<List<Sale>> _sales;

  @override
  void initState() {
    super.initState();
    _sales = _streamFor(_range);
  }

  /// The first day of the range, as a dayKey. "7 days" means today plus
  /// the six before it, so it always shows a full week whatever the weekday.
  Stream<List<Sale>> _streamFor(_Range r) {
    final now = DateTime.now();
    final from = switch (r) {
      _Range.today => now,
      _Range.week => now.subtract(const Duration(days: 6)),
      _Range.month => DateTime(now.year, now.month, 1),
    };
    return SalesService.instance.salesFrom(SalesService.dayKey(from));
  }

  void _pick(_Range r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      // A new listener only when the range changes, never on every redraw.
      _sales = _streamFor(r);
    });
  }

  String get _rangeLabel => switch (_range) {
        _Range.today => 'today',
        _Range.week => 'last 7 days',
        _Range.month => 'this month',
      };

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;
    final ownerOnShift = session.current?.isOwner ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<_Range>(
          segments: const [
            ButtonSegment(value: _Range.today, label: Text('Today')),
            ButtonSegment(value: _Range.week, label: Text('7 days')),
            ButtonSegment(value: _Range.month, label: Text('This month')),
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
            final stats = DashboardStats.from(snap.data!);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SalesCard(stats: stats, rangeLabel: _rangeLabel),
                const SizedBox(height: 12),
                const _AlertsRow(),
                if (!stats.isEmpty) ...[
                  const SizedBox(height: 12),
                  _ByCashierCard(stats: stats),
                  const SizedBox(height: 12),
                  _TopItemsCard(stats: stats),
                ],
              ],
            );
          },
        ),

        const SizedBox(height: 20),
        _MenuTile(
          icon: Icons.badge_outlined,
          title: 'Cashiers',
          subtitle: 'Add, deactivate, reset PINs, product access',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StaffScreen())),
        ),
        _MenuTile(
          icon: Icons.history,
          title: 'Stock history',
          subtitle: 'Deliveries and corrections, with who did them',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StockHistoryScreen())),
        ),
        // Only when a cashier is on shift and the owner unlocked this tab
        // with their PIN: lets the owner close it before handing back.
        if (!ownerOnShift)
          _MenuTile(
            icon: Icons.lock_outline,
            title: 'Lock owner area',
            subtitle: 'Also locks by itself when you leave this tab',
            onTap: session.lockOwner,
          ),
      ],
    );
  }
}

// -------------------------------------------------------------------------
// Sales card: the headline number, the cash / M-Pesa split, profit
// -------------------------------------------------------------------------

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.stats, required this.rangeLabel});

  final DashboardStats stats;
  final String rangeLabel;

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
// Low stock + plan status
// -------------------------------------------------------------------------

class _AlertsRow extends StatelessWidget {
  const _AlertsRow();

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogService.instance;
    final shop = SessionService.instance.shop;

    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final low = catalog.products.where((p) => p.isLow).toList();
        final names = low.take(3).map((p) => p.name).join(', ');
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Tile(
                bg: low.isEmpty ? AppColors.surfaceMuted : AppColors.warningBg,
                fg: low.isEmpty ? AppColors.ink : AppColors.warning,
                icon: low.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                title: 'Low stock',
                value: low.isEmpty ? 'All good' : '${low.length} ${low.length == 1 ? 'item' : 'items'}',
                note: low.isEmpty ? 'Nothing below its warning level' : '$names${low.length > 3 ? '…' : ''}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _PlanTile(paidUntil: shop?.paidUntil)),
          ],
        );
      },
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.paidUntil});

  final DateTime? paidUntil;

  @override
  Widget build(BuildContext context) {
    final until = paidUntil;
    if (until == null) {
      return const _Tile(
        bg: AppColors.surfaceMuted,
        fg: AppColors.ink,
        icon: Icons.help_outline,
        title: 'DukaPoint plan',
        value: 'Not set',
        note: 'Contact DukaPoint',
      );
    }
    final today = DateTime.now();
    final daysLeft = DateTime(until.year, until.month, until.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    final dateText = '${until.day} ${_month(until.month)} ${until.year}';

    // Status colours always come with an icon and words, never colour alone.
    if (daysLeft < 0) {
      return _Tile(
        bg: const Color(0xFFFEE4E2),
        fg: AppColors.danger,
        icon: Icons.error_outline,
        title: 'DukaPoint plan',
        value: 'Expired',
        note: 'Ended $dateText',
      );
    }
    if (daysLeft <= 7) {
      return _Tile(
        bg: AppColors.warningBg,
        fg: AppColors.warning,
        icon: Icons.schedule,
        title: 'DukaPoint plan',
        value: daysLeft == 0 ? 'Ends today' : '$daysLeft days left',
        note: 'Paid until $dateText',
      );
    }
    return _Tile(
      bg: AppColors.successBg,
      fg: AppColors.success,
      icon: Icons.verified_outlined,
      title: 'DukaPoint plan',
      value: 'Active',
      note: 'Paid until $dateText',
    );
  }

  static String _month(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.title,
    required this.value,
    required this.note,
  });

  final Color bg;
  final Color fg;
  final IconData icon;
  final String title;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg))),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg)),
          const SizedBox(height: 2),
          Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// By cashier + top items
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

// -------------------------------------------------------------------------
// Shared bits
// -------------------------------------------------------------------------

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

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}