import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/catalog_service.dart';
import '../../services/plan_service.dart';
import '../../services/sales_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/counting.dart';
import '../../utils/format.dart';
import '../../widgets/status_banners.dart';
import '../sell/receipt_screen.dart';
import 'dashboard_stats.dart';
import 'printer_screen.dart';
import 'renew_sheet.dart';
import 'shop_settings_screen.dart';
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
            final catalog = CatalogService.instance;
            final stats = DashboardStats.from(
              snap.data!,
              currentSourceOf: (id) => catalog.byCode(id)?.source,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SalesCard(stats: stats, rangeLabel: _rangeLabel),
                const SizedBox(height: 12),
                const _AlertsRow(),
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

        const SizedBox(height: 20),
        _MenuTile(
          icon: Icons.storefront_outlined,
          title: 'Shop settings',
          subtitle: 'Receipt header, M-Pesa details, owner PIN',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopSettingsScreen())),
        ),
        _MenuTile(
          icon: Icons.badge_outlined,
          title: 'Cashiers',
          subtitle: 'Add, deactivate, reset PINs, product access',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StaffScreen())),
        ),
        _MenuTile(
          icon: Icons.history,
          title: 'Stock history',
          subtitle: 'Deliveries, corrections and voids, with who did them',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StockHistoryScreen())),
        ),
        _MenuTile(
          icon: Icons.print_outlined,
          title: 'Printer',
          subtitle: "This phone's receipt printer, test print, auto-print",
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterScreen())),
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

    return ListenableBuilder(
      // Plan and session too: a new paidUntil you set in the console shows
      // up here without a restart.
      listenable: Listenable.merge([catalog, SessionService.instance, PlanService.instance]),
      builder: (context, _) {
        final low = catalog.products.where((p) => p.isLow).toList();
        final names = low.take(3).map((p) => p.name).join(', ');
        final shop = SessionService.instance.shop;
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
            Expanded(
              child: shop == null ? const SizedBox.shrink() : _PlanTile(state: PlanService.instance.stateFor(shop)),
            ),
          ],
        );
      },
    );
  }
}

/// The plan, in the owner's words. Tapping opens Renew in every phase
/// where paying makes sense, not only near the end: an owner who wants to
/// pay early can.
class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.state});

  final PlanState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final until = s.paidUntil;
    const red = Color(0xFFFEE4E2);

    // Status colours always come with an icon and words, never colour alone.
    final tile = switch (s.phase) {
      PlanPhase.unset => const _Tile(
          bg: AppColors.surfaceMuted,
          fg: AppColors.ink,
          icon: Icons.help_outline,
          title: 'DukaPoint plan',
          value: 'Not set',
          note: 'Contact DukaPoint',
        ),
      PlanPhase.active => _Tile(
          bg: AppColors.successBg,
          fg: AppColors.success,
          icon: Icons.verified_outlined,
          title: 'DukaPoint plan',
          value: 'Active',
          note: 'Paid until ${planDate(until!)}',
        ),
      PlanPhase.endingSoon => _Tile(
          bg: AppColors.warningBg,
          fg: AppColors.warning,
          icon: Icons.schedule,
          title: 'DukaPoint plan',
          value: s.daysLeft == 0 ? 'Ends today' : '${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'} left',
          note: 'Paid until ${planDate(until!)} · tap to renew',
        ),
      PlanPhase.grace => _Tile(
          bg: red,
          fg: AppColors.danger,
          icon: Icons.error_outline,
          title: 'DukaPoint plan',
          value: 'Ended',
          note: 'Sales pause ${planDate(s.pauseOn!)} · tap to renew',
        ),
      PlanPhase.paused => const _Tile(
          bg: red,
          fg: AppColors.danger,
          icon: Icons.block,
          title: 'DukaPoint plan',
          value: 'Sales paused',
          note: 'Tap to renew',
        ),
      PlanPhase.suspended => const _Tile(
          bg: red,
          fg: AppColors.danger,
          icon: Icons.block,
          title: 'DukaPoint plan',
          value: 'On hold',
          note: 'Contact DukaPoint',
        ),
    };

    // Unset and suspended are yours to sort out, not something to pay for.
    final canRenew = s.phase != PlanPhase.unset && s.phase != PlanPhase.suspended;
    if (!canRenew) return tile;
    return GestureDetector(onTap: () => showRenewSheet(context), child: tile);
  }
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
        onTap: () => _showList(context),
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

  void _showList(BuildContext context) {
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
            for (final s in stats.voided)
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
  static const _bar = Color(0xFF2A78D6); // checked with the dataviz validator
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
                        color: s.name == null ? _noSourceBar : _bar,
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