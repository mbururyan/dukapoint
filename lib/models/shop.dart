import 'package:cloud_firestore/cloud_firestore.dart';

/// One shop's settings. Lives at shops/{shopId}.
///
/// You create it in the console when activating a shop and set the fields
/// only you control: code, status, paidUntil (security rules stop the app
/// changing those). The owner edits the rest in Owner > Shop settings.
class Shop {
  const Shop({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.phone,
    required this.receiptFooter,
    required this.mpesaType,
    required this.tillNumber,
    required this.paybillNumber,
    required this.paybillAccount,
    required this.pochiNumber,
    required this.status,
    required this.paidUntil,
    required this.suppliers,
  });

  final String id;
  // Short code that starts every receipt number (DMD-K7-000124).
  final String code;
  final String name;
  final String address;
  final String phone;
  final String receiptFooter;

  // How customers pay by M-Pesa at this shop. Only the fields for the
  // chosen type are used; the others are kept in case the shop switches.
  final String mpesaType; // 'till' | 'paybill' | 'pochi'
  final String tillNumber;
  final String paybillNumber;
  final String paybillAccount;
  final String pochiNumber;

  final String status; // 'active' | 'suspended'
  final DateTime? paidUntil;
  // Supplier names used on past deliveries (FCL, Unga, De Heus...), offered
  // as suggestions so the same supplier isn't typed five different ways.
  final List<String> suppliers;

  bool get isActive => status == 'active';

  /// True when the chosen M-Pesa type has the number it needs.
  bool get mpesaReady => switch (mpesaType) {
        'paybill' => paybillNumber.isNotEmpty,
        'pochi' => pochiNumber.isNotEmpty,
        _ => tillNumber.isNotEmpty,
      };

  /// Short name for the type: on the checkout button and the receipt.
  String get mpesaTypeLabel => switch (mpesaType) {
        'paybill' => 'Paybill',
        'pochi' => 'Pochi',
        _ => 'Till',
      };

  /// How to pay, as receipt/checkout lines, e.g.
  ///   ["Buy Goods Till 123456"]
  ///   ["Paybill 247247", "Account DMD"]
  ///   ["Pochi la Biashara 0712 345 678"]
  /// Empty if the number hasn't been set.
  List<String> get mpesaLines {
    switch (mpesaType) {
      case 'paybill':
        if (paybillNumber.isEmpty) return const [];
        return ['Paybill $paybillNumber', if (paybillAccount.isNotEmpty) 'Account $paybillAccount'];
      case 'pochi':
        return pochiNumber.isEmpty ? const [] : ['Pochi la Biashara $pochiNumber'];
      default:
        return tillNumber.isEmpty ? const [] : ['Buy Goods Till $tillNumber'];
    }
  }

  factory Shop.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    String str(String key) => (d[key] as String?)?.trim() ?? '';
    final name = (d['name'] as String?) ?? 'Unnamed shop';
    final type = str('mpesaType');
    return Shop(
      id: doc.id,
      code: _code(d['code'] as String?, name),
      name: name,
      address: str('address'),
      phone: str('phone'),
      receiptFooter: str('receiptFooter'),
      // Shops set up before this field existed only had a till number.
      mpesaType: const ['till', 'paybill', 'pochi'].contains(type) ? type : 'till',
      tillNumber: str('tillNumber'),
      paybillNumber: str('paybillNumber'),
      paybillAccount: str('paybillAccount'),
      pochiNumber: str('pochiNumber'),
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