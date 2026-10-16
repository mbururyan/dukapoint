import 'package:cloud_firestore/cloud_firestore.dart';

/// One line on a sale: a COPY of the product as sold. Old receipts stay
/// correct after prices change, and a reprint never has to look anything up.
class SaleItem {
  const SaleItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.price,
    required this.buyPrice,
    required this.lineTotal,
  });

  final String productId;
  final String name;
  final String unit; // 'piece' | 'kg'
  final double qty;
  final int price; // per piece / per kg, whole shillings
  final int? buyPrice; // for profit later; never printed
  final int lineTotal;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'unit': unit,
        'qty': qty,
        'price': price,
        'buyPrice': buyPrice,
        'lineTotal': lineTotal,
      };

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        productId: (m['productId'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        unit: (m['unit'] as String?) ?? 'piece',
        qty: ((m['qty'] as num?) ?? 0).toDouble(),
        price: ((m['price'] as num?) ?? 0).round(),
        buyPrice: (m['buyPrice'] as num?)?.round(),
        lineTotal: ((m['lineTotal'] as num?) ?? 0).round(),
      );
}

/// A finished sale. Lives at shops/{shopId}/sales/{autoId}.
/// Shape agreed in the data model on Tuesday; nothing here is optional
/// except the payment details that only apply to one method.
class Sale {
  const Sale({
    required this.id,
    required this.receiptNo,
    required this.deviceCode,
    required this.cashierId,
    required this.cashierName,
    required this.items,
    required this.itemCount,
    required this.total,
    required this.method,
    required this.tendered,
    required this.change,
    required this.mpesaCode,
    required this.status,
    required this.dayKey,
    required this.at,
  });

  final String id;
  final String receiptNo; // e.g. DMD-K7-000124
  final String deviceCode; // the phone tag (K7): which phone rang it up
  final String cashierId;
  final String cashierName;
  final List<SaleItem> items;
  final int itemCount;
  final int total;
  final String method; // 'cash' | 'till' | 'stk'
  final int? tendered; // cash only
  final int? change; // cash only
  final String? mpesaCode; // till only
  final String status; // 'pending' | 'paid' | 'cancelled'
  final String dayKey; // '2026-10-15', the shop's local date
  final DateTime at; // phone time when the sale was made

  Map<String, dynamic> toMap() => {
        'receiptNo': receiptNo,
        'deviceCode': deviceCode,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'items': items.map((i) => i.toMap()).toList(),
        'itemCount': itemCount,
        'total': total,
        'payment': {
          'method': method,
          'tendered': tendered,
          'change': change,
          'mpesaCode': mpesaCode,
          'phone': null, // filled by the M-Pesa prompt, later
        },
        'status': status,
        'dayKey': dayKey,
        // Phone time: a sale made offline keeps the time it really happened.
        'createdAtClient': Timestamp.fromDate(at),
        // Server time: arrives when synced; a cross-check on the phone clock.
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory Sale.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final pay = (d['payment'] as Map<String, dynamic>?) ?? const {};
    return Sale(
      id: doc.id,
      receiptNo: (d['receiptNo'] as String?) ?? '',
      deviceCode: (d['deviceCode'] as String?) ?? '',
      cashierId: (d['cashierId'] as String?) ?? '',
      cashierName: (d['cashierName'] as String?) ?? '',
      items: ((d['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SaleItem.fromMap)
          .toList(),
      itemCount: ((d['itemCount'] as num?) ?? 0).toInt(),
      total: ((d['total'] as num?) ?? 0).round(),
      method: (pay['method'] as String?) ?? 'cash',
      tendered: (pay['tendered'] as num?)?.round(),
      change: (pay['change'] as num?)?.round(),
      mpesaCode: pay['mpesaCode'] as String?,
      status: (d['status'] as String?) ?? 'paid',
      dayKey: (d['dayKey'] as String?) ?? '',
      at: (d['createdAtClient'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}