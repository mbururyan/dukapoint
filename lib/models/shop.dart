import 'package:cloud_firestore/cloud_firestore.dart';

/// One shop's settings. Lives at shops/{shopId}. You create it from the
/// console when activating a shop; the owner can later edit the receipt
/// fields, but never status or paidUntil (security rules block that).
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.tillNumber,
    required this.receiptFooter,
    required this.status,
    required this.paidUntil,
    required this.suppliers,
  });

  final String id;
  final String name;
  final String address;
  final String phone;
  final String tillNumber;
  final String receiptFooter;
  final String status; // 'active' | 'suspended'
  final DateTime? paidUntil;
  // Supplier names used on past deliveries (FCL, Unga, De Heus...), offered
  // as suggestions so the same supplier isn't typed five different ways.
  final List<String> suppliers;

  bool get isActive => status == 'active';

  factory Shop.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Shop(
      id: doc.id,
      // Fallbacks so a half-filled console doc shows blanks instead of crashing.
      name: (d['name'] as String?) ?? 'Unnamed shop',
      address: (d['address'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      tillNumber: (d['tillNumber'] as String?) ?? '',
      receiptFooter: (d['receiptFooter'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'suspended',
      paidUntil: (d['paidUntil'] as Timestamp?)?.toDate(),
      suppliers: ((d['suppliers'] as List?) ?? const []).whereType<String>().toList()..sort(),
    );
  }
}