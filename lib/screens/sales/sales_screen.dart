import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/sales_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/status_banners.dart';
import '../sell/receipt_screen.dart';

/// Wireframe 6. One day's sales, newest first. Tap a sale to see its
/// receipt again (and reprint it, once the printer arrives in step 6).
///
/// Cashiers see their own sales only; the owner on shift sees everyone's.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late DateTime _day;
  late Stream<List<Sale>> _sales;
  String _filter = 'all'; // 'all' | 'cash' | 'mpesa'

  @override
  void initState() {
    super.initState();
    _setDay(DateTime.now(), rebuild: false);
  }

  void _setDay(DateTime d, {bool rebuild = true}) {
    _day = DateTime(d.year, d.month, d.day);
    // A new listener only when the day changes, never on every redraw.
    _sales = SalesService.instance.salesOn(SalesService.dayKey(_day));
    if (rebuild) setState(() {});
  }

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year && _day.month == now.month && _day.day == now.day;
  }

  String get _dayLabel {
    if (_isToday) return 'Today';
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    if (_day.year == yesterday.year && _day.month == yesterday.month && _day.day == yesterday.day) {
      return 'Yesterday';
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[_day.weekday - 1]} ${_day.day} ${months[_day.month - 1]}';
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) _setDay(picked);
  }

  /// What this person is allowed to see, then the cash / M-Pesa filter.
  List<Sale> _visible(List<Sale> all) {
    final session = SessionService.instance;
    final seeAll = session.ownerAccess;
    final me = session.current?.id;
    final list = all.where((s) {
      if (!seeAll && s.cashierId != me) return false;
      if (_filter == 'cash' && s.method != 'cash') return false;
      if (_filter == 'mpesa' && s.method == 'cash') return false;
      return true;
    }).toList();
    // Newest first, by the phone time the sale was made.
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;

    // Rebuild when the shift changes: a different person sees different sales.
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        children: [
          const SyncBanner(),
          // ---- Day picker ----
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  onPressed: () => _setDay(_day.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(_dayLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(foregroundColor: AppColors.ink),
                  ),
                ),
                IconButton(
                  tooltip: 'Next day',
                  // Can't look at sales from the future.
                  onPressed: _isToday ? null : () => _setDay(_day.add(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              session.ownerAccess ? 'All cashiers' : 'Your sales · ${session.current?.name ?? ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: StreamBuilder<List<Sale>>(
              stream: _sales,
              builder: (context, snap) {
                if (snap.hasError) return _Message('Could not load sales.\n${snap.error}');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                final shown = _visible(snap.data!);
                // Totals ignore anything not paid (cancelled, or pending
                // M-Pesa prompts later). Cancelled sales stay in the list.
                final paid = shown.where((s) => s.status == 'paid');
                final cancelledCount = shown.where((s) => s.isCancelled).length;
                final total = paid.fold<int>(0, (t, s) => t + s.total);
                final cash = paid.where((s) => s.method == 'cash').fold<int>(0, (t, s) => t + s.total);
                final mpesa = total - cash;

                return Column(
                  children: [
                    // ---- Summary ----
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _Stat(label: 'Total', value: kes(total)),
                          const SizedBox(width: 8),
                          _Stat(label: 'Cash', value: kes(cash)),
                          const SizedBox(width: 8),
                          _Stat(label: 'M-Pesa', value: kes(mpesa)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('All')),
                          ButtonSegment(value: 'cash', label: Text('Cash')),
                          ButtonSegment(value: 'mpesa', label: Text('M-Pesa')),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) => setState(() => _filter = s.first),
                      ),
                    ),
                    if (cancelledCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${paid.length} ${paid.length == 1 ? 'sale' : 'sales'} · '
                            '$cancelledCount cancelled (not in the totals)',
                            style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),

                    // ---- List ----
                    Expanded(
                      child: shown.isEmpty
                          ? _Message(_isToday ? 'No sales yet today.' : 'No sales on this day.')
                          : ListView.separated(
                              itemCount: shown.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) => _SaleRow(
                                sale: shown[i],
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => ReceiptScreen(sale: shown[i], viewOnly: true)),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale, required this.onTap});

  final Sale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = sale;
    final method = s.method == 'cash' ? 'Cash' : 'M-Pesa${s.mpesaCode == null ? '' : ' ${s.mpesaCode}'}';
    // Line 3: who, when, how much stuff. The cashier's name shows even to
    // cashiers (who only see their own sales) because it's what was asked
    // for and it keeps every row the same shape.
    final details = [
      if (s.cashierName.isNotEmpty) s.cashierName,
      dayTime(s.at),
      s.countText,
    ].join(' · ');
    final cancelled = s.isCancelled;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line 1: what was bought. That's what people remember
                  // ("the man who bought two bags of layers mash").
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (cancelled) ...[
                        const SizedBox(width: 6),
                        const _CancelledTag(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Line 2: which receipt, how it was paid.
                  Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: s.receiptNo, style: AppTheme.mono(size: 13, weight: FontWeight.w500)),
                              TextSpan(text: ' · $method'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      // Saved on the phone only, so far. Clears by itself
                      // once it reaches the server.
                      if (s.pendingSync) ...[
                        const SizedBox(width: 6),
                        const _NotSentTag(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(details, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              ksh(s.total),
              style: AppTheme.mono(
                size: 16,
                color: cancelled ? AppColors.inkSoft : AppColors.ink,
              ).copyWith(decoration: cancelled ? TextDecoration.lineThrough : null),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _NotSentTag extends StatelessWidget {
  const _NotSentTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(6)),
      child: const Text(
        '⟳ not sent yet',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning),
      ),
    );
  }
}

class _CancelledTag extends StatelessWidget {
  const _CancelledTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: const Color(0xFFFEE4E2), borderRadius: BorderRadius.circular(6)),
      child: const Text(
        'CANCELLED',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.danger),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
            const SizedBox(height: 2),
            Text(value, style: AppTheme.mono(size: 16)),
          ],
        ),
      ),
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