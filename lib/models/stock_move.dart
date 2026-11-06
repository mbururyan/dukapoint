import 'package:cloud_firestore/cloud_firestore.dart';

/// One change to a product's stock, kept for the owner's stock history.
/// Lives at shops/{shopId}/stockMoves/{autoId}. Never edited or deleted.
///
/// Sales are NOT logged here: every sale is already its own record in
/// /sales, so logging it twice would double the writes for no new info.
/// Voids ARE logged: stock going back up is a change the owner should
/// see in Stock history, with the receipt it came from.
class StockMove {
  const StockMove({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.qty,
    required this.type,
    required this.supplier,
    required this.unitCost,
    required this.note,
    required this.byName,
    required this.at,
    this.receiptNo,
  });

  final String id;
  final String productId;
  final String productName; // copied in, so history survives renames
  final String unit; // 'piece' | 'kg'
  final double qty; // signed: +40 received, -2 correction
  final String type; // 'created' | 'received' | 'correction' | 'void'
  final String? supplier;
  final int? unitCost; // buying price per unit on this delivery
  final String? note;
  final String byName;
  final DateTime at;
  final String? receiptNo; // voids only: which cancelled sale it came from

  bool get isReceived => type == 'received';
  bool get isCreated => type == 'created'; // a new product's opening stock
  bool get isVoid => type == 'void'; // stock back from a cancelled sale

  factory StockMove.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return StockMove(
      id: doc.id,
      productId: (d['productId'] as String?) ?? '',
      productName: (d['productName'] as String?) ?? 'Unknown product',
      unit: (d['unit'] as String?) ?? 'piece',
      qty: ((d['qty'] as num?) ?? 0).toDouble(),
      type: (d['type'] as String?) ?? 'correction',
      supplier: d['supplier'] as String?,
      unitCost: (d['unitCost'] as num?)?.round(),
      note: d['note'] as String?,
      byName: ((d['by'] as Map<String, dynamic>?)?['name'] as String?) ?? '',
      // Client time, not server time: a delivery logged offline must show
      // when it happened, not hours later when the phone reconnected.
      at: (d['createdAtClient'] as Timestamp?)?.toDate() ?? DateTime.now(),
      receiptNo: d['receiptNo'] as String?,
    );
  }
}