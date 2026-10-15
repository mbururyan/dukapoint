import 'package:flutter/material.dart';

import '../../models/stock_move.dart';
import '../../services/catalog_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Owner > Stock history. Every delivery and correction, newest first,
/// with who did it. This is how an owner who isn't in the shop all day
/// spots "40 bags arrived but only 35 are on the shelf".
class StockHistoryScreen extends StatefulWidget {
  const StockHistoryScreen({super.key});

  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  // Created once: building the stream inside build() would restart the
  // Firestore listener on every redraw.
  late final Stream<List<StockMove>> _moves = CatalogService.instance.recentMoves();
  String _filter = 'all'; // 'all' | 'received' | 'correction'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock history', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'received', label: Text('Received')),
                ButtonSegment(value: 'correction', label: Text('Corrections')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<StockMove>>(
              stream: _moves,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _Message('Could not load stock history.\n${snap.error}');
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!.where((m) => _filter == 'all' || m.type == _filter).toList();
                if (list.isEmpty) {
                  return const _Message('Nothing here yet.\nDeliveries added with "Add stock" show up here.');
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _MoveRow(move: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.move});

  final StockMove move;

  @override
  Widget build(BuildContext context) {
    final m = move;
    final unit = m.unit == 'kg' ? ' kg' : '';
    final up = m.qty > 0;

    // Line 2 reads like a sentence: "Received from FCL · Ksh 3,200 each"
    final what = m.isReceived
        ? (m.supplier == null ? 'Received' : 'Received from ${m.supplier}')
        : 'Correction';
    final cost = m.unitCost == null ? '' : ' · ${ksh(m.unitCost!)} each';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.productName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('$what$cost', style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  [m.byName, dayTime(m.at), if (m.note != null) m.note!].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${signedQty(m.qty)}$unit',
            // Colour plus the +/- sign, so it reads without relying on colour.
            style: AppTheme.mono(size: 18, color: up ? AppColors.success : AppColors.danger),
          ),
        ],
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