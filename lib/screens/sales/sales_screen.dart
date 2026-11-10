import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../services/sales_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/status_banners.dart';
import '../sell/receipt_screen.dart';

/// Wireframe 6. One day's sales, newest first. Tap a sale to see its
/// receipt again and reprint it.
///
/// Each day is a page: swipe right for yesterday and earlier, left to come
/// back towards today. The arrows and the calendar still work for anyone
/// who doesn't think to swipe, and for jumping far back.
///
/// Cashiers see their own sales only; the owner on shift sees everyone's.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  // Nobody has sales from before DukaPoint existed.
  static final _firstDay = DateTime(2026, 1, 1);

  // Page 0 is today, page 1 yesterday, and so on. With reverse: true on
  // the PageView, page 1 sits to the LEFT of page 0, so a swipe to the
  // right goes back in time, like turning back the pages of a book.
  final _page = PageController();
  late DateTime _base = _todayDate(); // the day page 0 shows
  int _index = 0;
  String _filter = 'all'; // 'all' | 'cash' | 'mpesa'
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _scheduleMidnight();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _page.dispose();
    super.dispose();
  }

  static DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Whole calendar days from [a] to [b]. Done in UTC so a clock change
  /// can never turn a day into 23 or 25 hours and throw the count off.
  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  DateTime _dayAt(int i) => DateTime(_base.year, _base.month, _base.day - i);
  int _indexOf(DateTime d) => _daysBetween(d, _base);
  int get _pageCount => _daysBetween(_firstDay, _base) + 1;

  DateTime get _day => _dayAt(_index);

  /// The tab stays open for days on a till phone. At midnight page 0 must
  /// become the new day: someone watching "Today" moves on to the new today;
  /// someone looking at an older day stays on that same date.
  void _scheduleMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      final keep = _index == 0 ? null : _day;
      setState(() {
        _base = _todayDate();
        _index = keep == null ? 0 : _indexOf(keep);
      });
      if (_page.hasClients) _page.jumpToPage(_index);
      _scheduleMidnight();
    });
  }

  void _goTo(int i, {bool animate = true}) {
    if (i < 0 || i >= _pageCount || !_page.hasClients) return;
    // Next to each other: slide, so it feels like the swipe. Far away (the
    // calendar): jump, rather than whizzing past 40 days of pages.
    if (animate && (i - _index).abs() == 1) {
      _page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _page.jumpToPage(i);
    }
  }

  String get _dayLabel {
    if (_index == 0) return 'Today';
    if (_index == 1) return 'Yesterday';
    final d = _day;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _firstDay,
      lastDate: _base,
    );
    if (picked != null) _goTo(_indexOf(picked), animate: false);
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
                  onPressed: _index >= _pageCount - 1 ? null : () => _goTo(_index + 1),
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
                  onPressed: _index == 0 ? null : () => _goTo(_index - 1),
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

          // ---- One page per day ----
          Expanded(
            child: PageView.builder(
              controller: _page,
              reverse: true,
              itemCount: _pageCount,
              // Fires once the swipe passes halfway, so the date above
              // changes as the new day slides in, not after it settles.
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final day = _dayAt(i);
                return _DayPage(
                  // Keyed by date: after midnight, page 0 is a new day and
                  // must get a fresh listener, not keep yesterday's.
                  key: ValueKey(SalesService.dayKey(day)),
                  day: day,
                  isToday: i == 0,
                  filter: _filter,
                  onFilter: (f) => setState(() => _filter = f),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One day's totals, filter and list. Each page listens to its own day,
/// and only while it's on screen or being swiped in: PageView builds the
/// page next door during a swipe and drops pages that scroll away, so
/// flicking back through a month doesn't leave 30 listeners running.
class _DayPage extends StatefulWidget {
  const _DayPage({
    super.key,
    required this.day,
    required this.isToday,
    required this.filter,
    required this.onFilter,
  });

  final DateTime day;
  final bool isToday;

  /// Shared by all pages, so "M-Pesa only" stays on while you swipe.
  final String filter;
  final ValueChanged<String> onFilter;

  @override
  State<_DayPage> createState() => _DayPageState();
}

class _DayPageState extends State<_DayPage> {
  // Made once per page, never on a redraw.
  late final Stream<List<Sale>> _sales = SalesService.instance.salesOn(SalesService.dayKey(widget.day));

  /// What this person is allowed to see, then the cash / M-Pesa filter.
  List<Sale> _visible(List<Sale> all) {
    final session = SessionService.instance;
    final seeAll = session.ownerAccess;
    final me = session.current?.id;
    final filter = widget.filter;
    final list = all.where((s) {
      if (!seeAll && s.cashierId != me) return false;
      if (filter == 'cash' && s.method != 'cash') return false;
      if (filter == 'mpesa' && s.method == 'cash') return false;
      return true;
    }).toList();
    // Newest first, by the phone time the sale was made.
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Sale>>(
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
                selected: {widget.filter},
                onSelectionChanged: (s) => widget.onFilter(s.first),
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
                  ? _Message(widget.isToday ? 'No sales yet today.' : 'No sales on this day.')
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