import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/counting.dart';

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
    this.countedAs = 'item',
    this.source,
  });

  final String productId;
  final String name;
  final String unit; // 'piece' | 'kg'
  // The product's word at the time of the sale ('bag'). Copied like the
  // price, so this sale keeps saying "3 bags" even if the product is later
  // changed to "sacks". Sales from before step 10 read as 'item'.
  final String countedAs;
  // The product's brand at the time of the sale, copied for the same reason
  // as the price. Null for loose items and for sales from before step 10c
  // (the By source report then falls back to the product's current source).
  final String? source;
  final double qty;
  final int price; // per piece / per kg, whole shillings
  final int? buyPrice; // for profit later; never printed
  final int lineTotal;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'unit': unit,
        'countedAs': countedAs,
        'source': source,
        'qty': qty,
        'price': price,
        'buyPrice': buyPrice,
        'lineTotal': lineTotal,
      };

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        productId: (m['productId'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        unit: (m['unit'] as String?) ?? 'piece',
        countedAs: ((m['countedAs'] as String?) ?? '').isEmpty ? 'item' : m['countedAs'] as String,
        source: ((m['source'] as String?) ?? '').isEmpty ? null : m['source'] as String,
        qty: ((m['qty'] as num?) ?? 0).toDouble(),
        price: ((m['price'] as num?) ?? 0).round(),
        buyPrice: (m['buyPrice'] as num?)?.round(),
        lineTotal: ((m['lineTotal'] as num?) ?? 0).round(),
      );
}

/// A finished sale. Lives at shops/{shopId}/sales/{autoId}.
/// Shape agreed in the data model on Tuesday; nothing here is optional
/// except the payment details that only apply to one method, and the
/// cancel details that only exist once a sale is voided (step 10).
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
    required this.channel,
    required this.status,
    required this.dayKey,
    required this.at,
    this.cancelReason,
    this.cancelNote,
    this.cancelledByName,
    this.requestedByName,
    this.cancelledAt,
    this.pendingSync = false,
  });

  /// How far back a sale can be voided. The security rules allow 8 days,
  /// one spare, so a void made offline still gets through a day later.
  static const voidWindow = Duration(days: 7);

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
  final String? mpesaCode; // M-Pesa only
  // Which M-Pesa type the customer paid to: 'till' | 'paybill' | 'pochi'.
  // Null for cash. Sales saved before this existed read as 'till'.
  final String? channel;
  final String status; // 'pending' | 'paid' | 'cancelled'
  final String dayKey; // '2026-10-15', the shop's local date
  final DateTime at; // phone time when the sale was made

  // Only set once a sale is voided. Written by SalesService.voidSale, never
  // at checkout, so they're not in toMap().
  final String? cancelReason; // 'Wrong item' | 'Customer returned' | ...
  final String? cancelNote; // free text, required for 'Other'
  final String? cancelledByName; // the owner who approved
  final String? requestedByName; // whoever was on shift and asked
  final DateTime? cancelledAt;

  /// Saved on this phone but not on the server yet (made offline). Comes
  /// from Firestore's metadata, not the data, so it's never stored.
  final bool pendingSync;

  bool get isCancelled => status == 'cancelled';

  /// "Sow & Weaner 70kg + 2 more": the sales list title. Counts lines,
  /// not pieces, because "+ 2 more" means two other products.
  String get title {
    if (items.isEmpty) return receiptNo;
    final more = items.length - 1;
    return more == 0 ? items.first.name : '${items.first.name} + $more more';
  }

  /// "4 bags, 1 packet, 2.5 kg".
  String get countText =>
      countSummary(items.map((i) => (qty: i.qty, unit: i.unit, word: i.countedAs)));

  /// Paid, and recent enough. Pending M-Pesa prompts (later) can't be
  /// voided: there's no money in yet, they just expire.
  bool get canVoid => status == 'paid' && DateTime.now().difference(at) <= voidWindow;

  /// The same sale, as it looks after voiding. Lets the receipt screen
  /// show CANCELLED at once, even offline, without re-reading Firestore.
  Sale cancelledCopy({
    required String reason,
    String? note,
    required String approvedBy,
    required String requestedBy,
    required DateTime when,
  }) {
    return Sale(
      id: id,
      receiptNo: receiptNo,
      deviceCode: deviceCode,
      cashierId: cashierId,
      cashierName: cashierName,
      items: items,
      itemCount: itemCount,
      total: total,
      method: method,
      tendered: tendered,
      change: change,
      mpesaCode: mpesaCode,
      channel: channel,
      status: 'cancelled',
      dayKey: dayKey,
      at: at,
      cancelReason: reason,
      cancelNote: note,
      cancelledByName: approvedBy,
      requestedByName: requestedBy,
      cancelledAt: when,
    );
  }

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
          'channel': channel,
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
    String? nameIn(String key) => (d[key] as Map<String, dynamic>?)?['name'] as String?;
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
      channel: (pay['channel'] as String?) ?? (pay['method'] == 'till' ? 'till' : null),
      status: (d['status'] as String?) ?? 'paid',
      dayKey: (d['dayKey'] as String?) ?? '',
      at: (d['createdAtClient'] as Timestamp?)?.toDate() ?? DateTime.now(),
      cancelReason: d['cancelReason'] as String?,
      cancelNote: d['cancelNote'] as String?,
      cancelledByName: nameIn('cancelledBy'),
      requestedByName: nameIn('requestedBy'),
      cancelledAt: (d['cancelledAtClient'] as Timestamp?)?.toDate(),
      pendingSync: doc.metadata.hasPendingWrites,
    );
  }
}