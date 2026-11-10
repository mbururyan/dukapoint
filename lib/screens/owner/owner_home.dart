import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/plan_service.dart';
import '../../services/printer_service.dart';
import '../../services/sales_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/printer_chip.dart';
import '../../widgets/sales_charts.dart';
import '../../widgets/status_banners.dart';
import 'printer_screen.dart';
import 'renew_sheet.dart';
import 'sales_summary_screen.dart';
import 'sales_trend.dart';
import 'shop_settings_screen.dart';
import 'staff_screen.dart';
import 'stock_history_screen.dart';
import 'inventory_screen.dart';


/// Wireframe G1: the Owner tab as a front door. Today's sales and the
/// week's shape up top, then a grid of tiles that each open their own page.
/// The detail lives in those pages; this screen only answers "how are we
/// doing, and is anything wrong?".
class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key});

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  // One listener for the last 7 days, made once. It covers the chart,
  // today's total, "vs yesterday" and today's voids, so this tab costs one
  // query however much it shows.
  late final Stream<List<Sale>> _week = SalesService.instance.salesFrom(
    SalesService.dayKey(_daysAgo(6)),
  );

  static DateTime _daysAgo(int n) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - n);
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<List<Sale>>(
          stream: _week,
          builder: (context, snap) {
            if (snap.hasError) {
              return _SalesHero.message('Could not load sales.\n${snap.error}', onTap: () => _open(const SalesSummaryScreen()));
            }
            if (!snap.hasData) {
              return _SalesHero.message(null, onTap: () => _open(const SalesSummaryScreen()));
            }
            final sales = snap.data!;
            final todayKey = SalesService.dayKey(DateTime.now());
            final voided = SalesTrend.voidedOn(sales, todayKey);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Only on days with voids: a strip that's always there
                // stops being read.
                if (voided.isNotEmpty) ...[
                  _VoidsStrip(voided: voided),
                  const SizedBox(height: 10),
                ],
                _SalesHero(sales: sales, onTap: () => _open(const SalesSummaryScreen())),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        _pair(
          _GridTile.featured(
            icon: Icons.warehouse_outlined,
            title: 'Inventory',
            subtitle: 'Stock value, low and out, reorder',
            // The page itself arrives in step 13b.
            onTap: () => _open(const InventoryScreen()),
          ),
          const _PlanTile(),
        ),
        const SizedBox(height: 10),
        _pair(
          _GridTile(
            icon: Icons.history,
            title: 'Stock history',
            subtitle: 'Deliveries, fixes and voids',
            onTap: () => _open(const StockHistoryScreen()),
          ),
          _GridTile(
            icon: Icons.badge_outlined,
            title: 'Cashiers',
            subtitle: 'Add, PINs, product access',
            onTap: () => _open(const StaffScreen()),
          ),
        ),
        const SizedBox(height: 10),
        _pair(
          _GridTile(
            icon: Icons.storefront_outlined,
            title: 'Shop settings',
            subtitle: 'Receipt, M-Pesa, owner PIN',
            onTap: () => _open(const ShopSettingsScreen()),
          ),
          ListenableBuilder(
            // Live, like the chip on Sell: the owner sees "Off" here the
            // moment the printer drops, not after reopening the tab.
            listenable: PrinterService.instance,
            builder: (context, _) {
              final p = PrinterService.instance;
              final look = printerLook(p.status);
              return _GridTile(
                icon: Icons.print_outlined,
                title: 'Printer',
                subtitle: !p.supported
                    ? 'Phone only'
                    : p.printer == null
                        ? 'None chosen'
                        : '${look.label} · ${p.printer!.name}',
                onTap: () => _open(const PrinterScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Two tiles side by side, as tall as the taller one, so a tile with a
  /// two-line subtitle doesn't leave its neighbour looking short.
  static Widget _pair(Widget a, Widget b) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        ),
      );
}

// -------------------------------------------------------------------------
// The big card: today's money and the last 7 days
// -------------------------------------------------------------------------

class _SalesHero extends StatelessWidget {
  const _SalesHero({required List<Sale> this.sales, required this.onTap}) : message = null;

  /// Loading (null) or an error, in the same frame so the screen doesn't jump.
  const _SalesHero.message(this.message, {required this.onTap}) : sales = null;

  final List<Sale>? sales;
  final String? message;
  final VoidCallback onTap;

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.primary, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _IconBox(icon: Icons.insights_outlined),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Sales summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.inkSoft),
                ],
              ),
              const SizedBox(height: 10),
              if (sales == null)
                SizedBox(
                  height: 150,
                  child: Center(
                    child: message == null
                        ? const CircularProgressIndicator()
                        : Text(message!, style: const TextStyle(color: AppColors.inkSoft)),
                  ),
                )
              else
                ..._body(sales!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(List<Sale> sales) {
    final now = DateTime.now();
    final todayKey = SalesService.dayKey(now);
    final count = SalesTrend.countOn(sales, todayKey);
    final total = SalesTrend.totalOn(sales, todayKey);
    final change = SalesTrend.changeVsYesterday(sales, now);
    final days = SalesTrend.byDay(sales, DateTime(now.year, now.month, now.day - 6), now);

    return [
      Text(
        'Today so far · $count ${count == 1 ? 'sale' : 'sales'}',
        style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
      ),
      Text(ksh(total), style: AppTheme.mono(size: 30)),
      if (change != null) ChangeLine(change: change, size: 12.5),
      const SizedBox(height: 12),
      Semantics(
        // Screen readers get the numbers the bars stand for.
        label: 'Last 7 days: ${days.map((d) => '${_wd[d.day.weekday - 1]} ${ksh(d.total)}').join(', ')}',
        child: ExcludeSemantics(
          child: ColumnBars(
            values: [for (final d in days) d.total],
            labels: [
              for (var i = 0; i < days.length; i++) i == days.length - 1 ? 'Today' : _wd[days[i].day.weekday - 1],
            ],
            height: 80,
            lastIsPartial: true,
            // No onSelect: the whole card is one tap to Sales summary,
            // where the chart can be read bar by bar.
          ),
        ),
      ),
    ];
  }
}

/// "1 voided today · Ksh 2,500". Red, the anti-fraud alert: a cashier
/// quietly voiding cash sales and pocketing the money is the classic
/// till fraud, so the owner sees it the moment they open this tab.
class _VoidsStrip extends StatelessWidget {
  const _VoidsStrip({required this.voided});

  final List<Sale> voided;

  @override
  Widget build(BuildContext context) {
    final n = voided.length;
    final sum = voided.fold<int>(0, (s, v) => s + v.total);
    return Material(
      color: const Color(0xFFFEE4E2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showVoidedSales(context, voided, 'today'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.block, size: 20, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$n voided today · ${ksh(sum)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' · tap to see why'),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13.5, color: AppColors.danger),
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

// -------------------------------------------------------------------------
// The plan tile: colour-coded, always tappable to pay
// -------------------------------------------------------------------------

class _PlanTile extends StatelessWidget {
  const _PlanTile();

  static const _redBg = Color(0xFFFEE4E2);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // A new paidUntil set in the console turns this green without a restart.
      listenable: Listenable.merge([SessionService.instance, PlanService.instance]),
      builder: (context, _) {
        final shop = SessionService.instance.shop;
        if (shop == null) return const SizedBox.shrink();
        final s = PlanService.instance.stateFor(shop);
        final until = s.paidUntil;

        // Green = fine, amber = last 7 days, red = act now. Every state has
        // its own icon and words too, so colour never carries it alone.
        // To make the last 7 days red instead of amber, change the two
        // warning colours in the endingSoon line to _redBg / AppColors.danger.
        final (bg, fg, icon, title, sub, button) = switch (s.phase) {
          PlanPhase.unset => (AppColors.surfaceMuted, AppColors.ink, Icons.help_outline, 'Plan', 'Not set up yet', null),
          PlanPhase.active => (
              AppColors.successBg,
              AppColors.success,
              Icons.verified_outlined,
              'Plan active',
              'Paid to ${planDate(until!)}',
              null,
            ),
          PlanPhase.endingSoon => (
              AppColors.warningBg,
              AppColors.warning,
              Icons.schedule,
              s.daysLeft == 0 ? 'Ends today' : 'Ends in ${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'}',
              'Paid to ${planDate(until!)}',
              'Renew',
            ),
          PlanPhase.grace => (
              _redBg,
              AppColors.danger,
              Icons.error_outline,
              'Plan ended',
              'Selling pauses ${planDate(s.pauseOn!)}',
              'Pay now',
            ),
          PlanPhase.paused => (_redBg, AppColors.danger, Icons.pause_circle_outline, 'Selling paused', 'Pay to unlock', 'Pay now'),
          PlanPhase.suspended => (_redBg, AppColors.danger, Icons.block, 'On hold', 'Contact DukaPoint', null),
        };

        return _GridTile(
          icon: icon,
          title: title,
          subtitle: sub,
          bg: bg,
          fg: fg,
          button: button,
          // Every state opens Renew: it shows the Paybill to pay early,
          // and "contact DukaPoint" when payment details aren't set.
          onTap: () => showRenewSheet(context),
        );
      },
    );
  }
}

// -------------------------------------------------------------------------
// Tiles
// -------------------------------------------------------------------------

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.bg,
    this.fg,
    this.button,
  }) : highlight = false;

  /// The analytics tiles: white with a plum border, like the Sales card,
  /// so the "look at me" tiles stand apart from plain menu tiles.
  const _GridTile.featured({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  })  : bg = null,
        fg = null,
        button = null,
        highlight = true;

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Status colours (the plan tile). Null = the normal menu look.
  final Color? bg;
  final Color? fg;

  /// A small solid label like "Pay now". Not a separate button: the
  /// whole tile is the tap target, this just says what the tap does.
  final String? button;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final coloured = fg != null;
    final ink = fg ?? AppColors.ink;
    final soft = fg ?? AppColors.inkSoft;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: highlight
          ? const BorderSide(color: AppColors.primary, width: 2)
          : BorderSide(color: coloured ? fg!.withValues(alpha: 0.35) : AppColors.border, width: coloured ? 1.5 : 1),
    );

    return Material(
      color: bg ?? (highlight ? AppColors.surface : AppColors.surfaceMuted),
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconBox(icon: icon, color: fg, onColour: coloured),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: soft),
                ],
              ),
              const SizedBox(height: 10),
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: soft)),
              if (button != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    button!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, this.color, this.onColour = false});

  final IconData icon;
  final Color? color;

  /// On a coloured tile the box goes white, so the icon still pops.
  final bool onColour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: onColour ? Colors.white : AppColors.primaryTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: color ?? AppColors.primary),
    );
  }
}