import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/sale.dart';
import 'cart_service.dart';
import 'device_service.dart';
import 'session_service.dart';

/// Saves finished sales, voids them, and keeps stock in step.
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
    String? channel,
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
            countedAs: l.product.countedAs,
            source: l.product.source,
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
      channel: channel,
      status: 'paid',
      dayKey: dayKey(now),
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

  /// Cancels a paid sale and puts every item's stock back, logging each
  /// return in Stock history. Returns the cancelled sale straight away,
  /// even offline, so the receipt can show CANCELLED at once.
  ///
  /// Call only after the owner has approved (requireOwner). The owner is
  /// recorded as approver; whoever is on shift is recorded as requester.
  Sale voidSale(Sale sale, {required String reason, String? note}) {
    final session = SessionService.instance;
    final shopRef = _db.collection('shops').doc(session.shop!.id);
    final owner = session.ownerRecord;
    final approver = {'id': owner?.id ?? '', 'name': owner?.name ?? ''};
    final requester = session.actor;
    final now = DateTime.now();
    final cleanNote = (note == null || note.trim().isEmpty) ? null : note.trim();

    // ONE batch, unlike record(): all of it happens or none of it does.
    // If the server refuses the cancel (already voided on another phone,
    // or older than 8 days), the stock must NOT come back either, or the
    // shelf count would be wrong twice over.
    final batch = _db.batch();

    batch.update(shopRef.collection('sales').doc(sale.id), {
      // Exactly these keys and nothing else: the security rules reject a
      // cancel that touches the total, the items or anything else.
      'status': 'cancelled',
      'cancelReason': reason,
      'cancelNote': cleanNote,
      'cancelledBy': approver,
      'requestedBy': requester,
      'cancelledAtClient': Timestamp.fromDate(now),
      'cancelledAt': FieldValue.serverTimestamp(),
    });

    for (final i in sale.items) {
      // Increment, not "set": a sale of the same item on another phone at
      // the same moment must still count.
      batch.update(shopRef.collection('products').doc(i.productId), {
        'stock': FieldValue.increment(i.qty),
        // soldCount is NOT reduced: the cancelled sale still mentions this
        // product, so it must stay protected from deletion.
        'updatedBy': approver,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Same shape as CatalogService's history entries, plus the receipt.
      batch.set(shopRef.collection('stockMoves').doc(), {
        'productId': i.productId,
        'productName': i.name,
        'unit': i.unit,
        'qty': i.qty,
        'type': 'void',
        'supplier': null,
        'unitCost': null,
        'note': cleanNote == null ? reason : '$reason: $cleanNote',
        'receiptNo': sale.receiptNo,
        'saleId': sale.id,
        'by': approver,
        'createdAtClient': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Not awaited: works offline, sent when the network is back.
    batch.commit().then((_) {}, onError: (e) => debugPrint('Void of ${sale.receiptNo} failed: $e'));

    return sale.cancelledCopy(
      reason: reason,
      note: cleanNote,
      approvedBy: approver['name']!,
      requestedBy: requester['name'] ?? '',
      when: now,
    );
  }

  /// Every sale from [fromDay] (inclusive) up to now, live.
  ///
  /// Works because dayKeys are written year-month-day ("2026-10-21"), so
  /// comparing them as text gives the same order as comparing dates. One
  /// range on one field needs no special Firestore index.
  ///
  /// Status isn't filtered here (that would need a composite index); the
  /// dashboard keeps only 'paid' sales itself.
  Stream<List<Sale>> salesFrom(String fromDay) {
    return _db
        .collection('shops')
        .doc(SessionService.instance.shop!.id)
        .collection('sales')
        .where('dayKey', isGreaterThanOrEqualTo: fromDay)
        .snapshots()
        .map((q) => q.docs.map(Sale.fromDoc).toList());
  }

  /// One day's sales, live, for the Sales tab. Equality on one field:
  /// no special Firestore index needed.
  ///
  /// Includes metadata changes so a sale's "not sent yet" tag clears the
  /// moment it reaches the server (that's a metadata change, not a data one).
  Stream<List<Sale>> salesOn(String day) {
    return _db
        .collection('shops')
        .doc(SessionService.instance.shop!.id)
        .collection('sales')
        .where('dayKey', isEqualTo: day)
        .snapshots(includeMetadataChanges: true)
        .map((q) => q.docs.map(Sale.fromDoc).toList());
  }

  /// The shop's local calendar day, used to fetch "today's sales" cheaply.
  static String dayKey(DateTime t) {
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    return '${t.year}-$m-$d';
  }
}