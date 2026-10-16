import 'package:cloud_firestore/cloud_firestore.dart';

/// One shop's settings. Lives at shops/{shopId}. You create it from the
/// console when activating a shop; the owner can later edit the receipt
/// fields, but never status or paidUntil (security rules block that).
class Shop {
  const Shop({
    required this.id,
    required this.code,
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
  // Short code that starts every receipt number (DMD-K7-000124). Set by
  // you in the console when activating the shop; the app can't change it.
  final String code;
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
    final name = (d['name'] as String?) ?? 'Unnamed shop';
    return Shop(
      id: doc.id,
      code: _code(d['code'] as String?, name),
      // Fallbacks so a half-filled console doc shows blanks instead of crashing.
      name: name,
      address: (d['address'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      tillNumber: (d['tillNumber'] as String?) ?? '',
      receiptFooter: (d['receiptFooter'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'suspended',
      paidUntil: (d['paidUntil'] as Timestamp?)?.toDate(),
      suppliers: ((d['suppliers'] as List?) ?? const []).whereType<String>().toList()..sort(),
    );
  }

  /// The console value, cleaned to letters/digits in capitals. If you
  /// forgot to set one, fall back to the first 3 letters of the name, so
  /// selling never stops over a missing setup field.
  static String _code(String? raw, String name) {
    final clean = (raw ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.isNotEmpty) return clean;
    final fromName = name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    return fromName.isEmpty ? 'DKP' : fromName.substring(0, fromName.length < 3 ? fromName.length : 3);
  }
}