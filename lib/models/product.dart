import 'package:cloud_firestore/cloud_firestore.dart';

/// One item the shop sells. Lives at shops/{shopId}/products/{code}, where
/// the document ID IS the barcode (or a generated in-store code starting 20).
class Product {
  const Product({
    required this.code,
    required this.name,
    required this.price,
    required this.buyPrice,
    required this.stock,
    required this.lowStockAt,
    required this.unit,
    required this.active,
    required this.soldCount,
    required this.updatedByName,
  });

  final String code; // barcode = document ID, can't change after creation
  final String name;
  final int price; // whole shillings
  final int? buyPrice; // optional, owner-only, for profit
  final double stock; // double because kg items can be 2.5
  final double lowStockAt;
  final String unit; // 'piece' | 'kg'
  final bool active; // false = hidden from selling
  // How many sales included this product. Kept by the sales step (step 5).
  // 0 = never sold, so it's safe to delete (a typo or test item).
  final int soldCount;
  final String? updatedByName; // who last added/edited it, for the owner

  bool get isKg => unit == 'kg';
  bool get isLow => active && stock <= lowStockAt;
  bool get canDelete => soldCount == 0;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Product(
      code: doc.id,
      name: (d['name'] as String?) ?? 'Unnamed',
      // Firestore may hand back 190 or 190.0 depending on how it was
      // written (console vs app), so read numbers as num and convert.
      price: ((d['price'] as num?) ?? 0).round(),
      buyPrice: (d['buyPrice'] as num?)?.round(),
      stock: ((d['stock'] as num?) ?? 0).toDouble(),
      lowStockAt: ((d['lowStockAt'] as num?) ?? 0).toDouble(),
      unit: (d['unit'] as String?) ?? 'piece',
      active: (d['active'] as bool?) ?? true,
      soldCount: ((d['soldCount'] as num?) ?? 0).toInt(),
      updatedByName: (d['updatedBy'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}