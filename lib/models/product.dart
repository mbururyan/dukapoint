import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/counting.dart';

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
    required this.countedAs,
    required this.source,
    required this.active,
    required this.soldCount,
    required this.updatedByName,
    required this.createdAt,
  });

  final String code; // barcode = document ID, can't change after creation
  final String name;
  final int price; // whole shillings
  final int? buyPrice; // optional, owner-only, for profit
  final double stock; // double because kg items can be 2.5
  final double lowStockAt;
  final String unit; // 'piece' | 'kg'
  // The word for one of these, singular: 'bag', 'packet', 'bottle'...
  // Only used for per-piece products; per-kg ones always say kg.
  // Products saved before step 10 have none and read as 'item'.
  final String countedAs;
  // Brand or maker: 'FCL', 'De Heus', 'EABL'. Optional (null for loose
  // items). Not the delivery supplier: that lives on each delivery.
  final String? source;
  final bool active; // false = hidden from selling
  // How many sales included this product. Kept by the sales step (step 5).
  // 0 = never sold, so it's safe to delete (a typo or test item).
  final int soldCount;
  final String? updatedByName; // who last added/edited it, for the owner
  // Null for a moment after adding offline, until the server stamps it.
  // Sorting treats null as "just now", so a new product still shows first.
  final DateTime? createdAt;

  bool get isKg => unit == 'kg';
  bool get isLow => active && stock <= lowStockAt;
  bool get canDelete => soldCount == 0;

  /// "12 bags", "3.5 kg": stock in the product's own words.
  String get stockText => countOf(stock, unit: unit, word: countedAs);

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final word = (d['countedAs'] as String?)?.trim() ?? '';
    final src = (d['source'] as String?)?.trim() ?? '';
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
      countedAs: word.isEmpty ? 'item' : word,
      source: src.isEmpty ? null : src,
      active: (d['active'] as bool?) ?? true,
      soldCount: ((d['soldCount'] as num?) ?? 0).toInt(),
      updatedByName: (d['updatedBy'] as Map<String, dynamic>?)?['name'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}