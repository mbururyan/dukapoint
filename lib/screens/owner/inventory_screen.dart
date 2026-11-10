import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/product.dart';
import '../../models/sale.dart';
import '../../services/catalog_service.dart';
import '../../services/sales_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/counting.dart';
import '../../utils/format.dart';
import '../../widgets/sales_charts.dart';
import '../../widgets/status_banners.dart';
import '../products/product_form_screen.dart';
import 'inventory_stats.dart';

/// Wireframes I1 + I2. What's on the shelves, what's run out, what to
/// order from whom, and what isn't selling. Owner only: it shows buying
/// prices.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  static const _redBg = Color(0xFFFEE4E2);

  // 30 days of sales covers both the pace (last 14) and "not moving" (30).
  late final Stream<List<Sale>> _sales = SalesService.instance.salesFrom(
    SalesService.dayKey(_daysAgo(InventoryStats.idleDays - 1)),
  );

  static DateTime _daysAgo(int n) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - n);
  }

  Future<void> _edit(Product p) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)),
    );
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Opens WhatsApp with the order typed out. No number: the owner picks
  /// the rep's chat, and can still edit the message before sending.
  Future<void> _sendOrder(List<OrderLine> lines) async {
    final shop = SessionService.instance.shop;
    final text = [
      'Order from ${shop?.name ?? 'our shop'}',
      planDate(DateTime.now()),
      '',
      for (final l in lines)
        if (l.qty != null) '• ${l.product.name}: ${countOf(l.qty!, unit: l.product.unit, word: l.product.countedAs)}',
      '',
      'Thank you.',
    ].join('\n');
    final ok = await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open WhatsApp on this phone")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: ListenableBuilder(
        // Stock changes (a sale, a delivery) redraw the page straight away.
        listenable: catalog,
        builder: (context, _) => StreamBuilder<List<Sale>>(
          stream: _sales,
          builder: (context, snap) {
            if (snap.hasError) return _Message('Could not load sales.\n${snap.error}');
            if (!snap.hasData || !catalog.loaded) return const Center(child: CircularProgressIndicator());
            final st = InventoryStats.from(catalog.products, snap.data!, DateTime.now());
            if (st.isEmpty) return const _Message('No products yet.\nAdd them on the Products tab.');

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _valueCard(st),
                if (st.bySource.isNotEmpty && st.costValue > 0) ...[
                  const SizedBox(height: 12),
                  _sourceCard(st),
                ],
                if (st.outItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _outCard(st),
                ],
                if (st.lowItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _lowCard(st),
                ],
                if (st.toOrder.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _orderCard(st),
                ],
                if (st.notMoving.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _idleCard(st),
                ],
                if (st.missingCost.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _missingCard(st),
                ],
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Money on the shelves + the three counts
  // ---------------------------------------------------------------------

  Widget _valueCard(InventoryStats st) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Money on the shelves (at cost)', style: TextStyle(color: AppColors.inkSoft)),
          const SizedBox(height: 4),
          Text(ksh(st.costValue), style: AppTheme.mono(size: 30)),
          const SizedBox(height: 6),
          _kv('If it all sells', ksh(st.retailValue)),
          _kv('Profit waiting on shelves', ksh(st.profitWaiting), color: AppColors.success),
          if (st.missingCost.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${st.missingCost.length} ${st.missingCost.length == 1 ? 'item has' : 'items have'} no buying price '
                'and ${st.missingCost.length == 1 ? "isn't" : "aren't"} counted. See the list at the bottom.',
                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Pill(n: st.inStock, label: 'In stock', fg: AppColors.success, bg: AppColors.successBg),
              const SizedBox(width: 8),
              _Pill(n: st.low, label: 'Low', fg: AppColors.warning, bg: AppColors.warningBg),
              const SizedBox(width: 8),
              _Pill(n: st.out, label: 'Out', fg: AppColors.danger, bg: _redBg),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 14))),
            Text(v, style: AppTheme.mono(size: 15, color: color)),
          ],
        ),
      );

  // ---------------------------------------------------------------------
  // Stock value by source: the one chart on this page
  // ---------------------------------------------------------------------

  /// "Which supplier is my money sitting with?" Ranked bars, biggest first,
  /// amounts written out. Scaled to the biggest source, so small ones still
  /// show next to one big one.
  Widget _sourceCard(InventoryStats st) {
    final max = st.bySource.fold<int>(0, (m, s) => s.value > m ? s.value : m);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Stock value by source', sub: 'Where your money is sitting, at cost'),
          const SizedBox(height: 8),
          for (final s in st.bySource)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.name ?? 'No source', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text(ksh(s.value), style: AppTheme.mono(size: 14)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Semantics(
                    label: '${s.name ?? 'No source'} ${ksh(s.value)}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 10,
                        color: const Color(0xFFEEF2F7),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: max == 0 ? 0 : (s.value / max).clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              // Grey for "no source": it's a leftover, not a brand.
                              color: s.name == null ? const Color(0xFF9CA3AF) : ChartColors.bar,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Out of stock, running low
  // ---------------------------------------------------------------------

  String _soldText(StockPace s) {
    final p = s.product;
    final src = p.source == null ? '' : '${p.source} · ';
    return s.sold > 0
        ? '${src}sold ${countOf(s.sold, unit: p.unit, word: p.countedAs)} in ${InventoryStats.paceDays} days'
        : '${src}no sales in ${InventoryStats.paceDays} days';
  }

  Widget _outCard(InventoryStats st) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Out of stock', color: AppColors.danger, sub: 'Most missed first'),
          for (final s in st.outItems)
            _ItemRow(
              title: s.product.name,
              sub: _soldText(s),
              trailing: const _Tag('0 left', fg: AppColors.danger, bg: _redBg),
            ),
        ],
      ),
    );
  }

  Widget _lowCard(InventoryStats st) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Running low', color: AppColors.warning, sub: 'At or below the warning level, soonest to run out first'),
          for (final s in st.lowItems)
            _ItemRow(
              title: s.product.name,
              sub: '${s.product.stockText} left · ${_soldText(s)}',
              trailing: _Tag(_daysLeft(s.daysLeft), fg: AppColors.warning, bg: AppColors.warningBg),
            ),
        ],
      ),
    );
  }

  static String _daysLeft(double? d) {
    if (d == null) return 'low';
    if (d < 1) return '<1 day';
    final n = d.floor();
    return '~$n ${n == 1 ? 'day' : 'days'}';
  }

  // ---------------------------------------------------------------------
  // To order, by source, with a WhatsApp button each
  // ---------------------------------------------------------------------

  Widget _orderCard(InventoryStats st) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title(
            'To order',
            sub: 'Enough for ${InventoryStats.coverDays} days at the current pace. '
                '"Check" = no recent sales to go by.',
          ),
          for (final e in st.toOrder.entries) ...[
            const SizedBox(height: 10),
            Text(
              (e.key ?? 'No source').toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.inkSoft),
            ),
            for (final l in e.value)
              _ItemRow(
                title: l.product.name,
                sub: l.why,
                trailing: Text(
                  l.qty == null ? 'check' : countOf(l.qty!, unit: l.product.unit, word: l.product.countedAs),
                  style: AppTheme.mono(size: 14, color: l.qty == null ? AppColors.inkSoft : AppColors.ink),
                ),
              ),
            // One message per source, so each rep only gets their own
            // items. None for "no source" (who would it go to?) or when
            // every line is a "check".
            if (e.key != null && e.value.any((l) => l.qty != null))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.icon(
                  onPressed: () => _sendOrder(e.value),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mpesa, // WhatsApp-ish green
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(Icons.chat_outlined, size: 20),
                  label: Text('Send ${e.key} order on WhatsApp'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Not moving, missing buying price
  // ---------------------------------------------------------------------

  Widget _idleCard(InventoryStats st) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Not moving', sub: 'No sales in ${InventoryStats.idleDays} days · money tied up'),
          for (final s in st.notMoving)
            _ItemRow(
              title: s.product.name,
              sub: [if (s.product.source != null) s.product.source!, s.product.stockText].join(' · '),
              // At cost when known; otherwise just the count, rather than
              // passing off a selling-price figure as money tied up.
              trailing: s.product.buyPrice == null
                  ? null
                  : Text(kes((s.product.stock * s.product.buyPrice!).round()), style: AppTheme.mono(size: 14)),
            ),
        ],
      ),
    );
  }

  Widget _missingCard(InventoryStats st) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Missing buying price', sub: 'Not counted in the value above · tap to add one'),
          for (final p in st.missingCost)
            _ItemRow(
              title: p.name,
              sub: p.stockText,
              trailing: const Icon(Icons.chevron_right, color: AppColors.inkSoft),
              onTap: () => _edit(p),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Small pieces
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

class _Title extends StatelessWidget {
  const _Title(this.text, {this.sub, this.color});

  final String text;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color ?? AppColors.ink)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.title, required this.sub, this.trailing, this.onTap});

  final String title;
  final String sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.n, required this.label, required this.fg, required this.bg});

  final int n;
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text('$n', style: AppTheme.mono(size: 20, color: fg)),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.fg, required this.bg});

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}