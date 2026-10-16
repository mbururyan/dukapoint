import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/sale.dart';
import 'cart_service.dart';
import 'device_service.dart';
import 'session_service.dart';

/// Saves finished sales and updates stock.
class SalesService {
  SalesService._();
  static final instance = SalesService._();

  final _db = FirebaseFirestore.instance;

  /// Records the current cart as a paid sale and returns it for the
  /// receipt screen. Returns immediately, even offline: the writes are
  /// queued on the phone and sent when the network is back.
  Sale record({
    required List<CartLine> lines,
    required String method,
    int? tendered,
    int? change,
    String? mpesaCode,
  }) {
    final session = SessionService.instance;
    final shopRef = _db.collection('shops').doc(session.shop!.id);
    final now = DateTime.now();
    final total = lines.fold<int>(0, (s, l) => s + l.total);

    final saleRef = shopRef.collection('sales').doc(); // ID made on the phone, no network needed
    final sale = Sale(
      id: saleRef.id,
      receiptNo: DeviceService.instance.nextReceiptNo(session.shop!.code),
      deviceCode: DeviceService.instance.tag,
      cashierId: session.current?.id ?? '',
      cashierName: session.current?.name ?? '',
      items: [
        for (final l in lines)
          SaleItem(
            productId: l.code,
            name: l.product.name,
            unit: l.product.unit,
            qty: l.qty,
            price: l.unitPrice,
            buyPrice: l.product.buyPrice,
            lineTotal: l.total,
          ),
      ],
      itemCount: lines.fold<int>(0, (s, l) => s + (l.product.isKg ? 1 : l.qty.round())),
      total: total,
      method: method,
      tendered: tendered,
      change: change,
      mpesaCode: mpesaCode,
      status: 'paid',
      dayKey: _dayKey(now),
      at: now,
    );

    // 1. The sale itself, on its own. Nothing else in this method can
    //    make it fail, which matters more than anything: it's the money.
    saleRef.set(sale.toMap()).then((_) {}, onError: (e) => debugPrint('Sale ${sale.receiptNo} failed: $e'));

    // 2. Stock, one separate write per product. If a product was deleted
    //    on another phone, only ITS update fails; the sale and the other
    //    products are untouched. Increments, so two phones selling the
    //    same item at once both count.
    for (final l in lines) {
      shopRef.collection('products').doc(l.code).update({
        'stock': FieldValue.increment(-l.qty),
        'soldCount': FieldValue.increment(1), // also locks it against deletion
        'lastSoldAt': FieldValue.serverTimestamp(),
      }).then((_) {}, onError: (e) => debugPrint('Stock update for ${l.code} failed: $e'));
    }

    return sale;
  }

  /// The shop's local calendar day, used to fetch "today's sales" cheaply.
  static String _dayKey(DateTime t) {
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    return '${t.year}-$m-$d';
  }
}