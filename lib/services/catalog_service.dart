import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../models/stock_move.dart';
import 'session_service.dart';

/// The shop's whole product list, kept in memory and live-synced, plus the
/// writes that change products and stock.
///
/// Why in memory: a scan at the till must find the product instantly,
/// online or offline. Looking it up in a Map is instant; asking Firestore
/// per scan is not, and fails offline for anything not cached.
/// A duka has hundreds of products, not millions, so this is cheap.
class CatalogService extends ChangeNotifier {
  CatalogService._();
  static final instance = CatalogService._();

  final _db = FirebaseFirestore.instance;

  String? _shopId;
  StreamSubscription? _sub;
  Map<String, Product> _byCode = {};
  List<Product> products = []; // sorted: active first, then by name
  bool loaded = false;

  DocumentReference<Map<String, dynamic>> get _shopRef => _db.collection('shops').doc(_shopId);
  CollectionReference<Map<String, dynamic>> get _ref => _shopRef.collection('products');
  CollectionReference<Map<String, dynamic>> get _moves => _shopRef.collection('stockMoves');

  void start(String shopId) {
    if (_shopId == shopId && _sub != null) return;
    stop();
    _shopId = shopId;
    _sub = _ref.snapshots().listen((q) {
      final list = q.docs.map(Product.fromDoc).toList();
      list.sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      products = list;
      _byCode = {for (final p in list) p.code: p};
      loaded = true;
      notifyListeners();
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _shopId = null;
    _byCode = {};
    products = [];
    loaded = false;
    notifyListeners();
  }

  Product? byCode(String code) => _byCode[code.trim()];

  int get lowCount => products.where((p) => p.isLow).length;

  // ---------------------------------------------------------------------
  // Writes. None are awaited by screens: offline they only finish when
  // the server confirms. The listener above updates the list instantly.
  // Batches are used where two documents must change together: Firestore
  // queues a batch offline and applies all of it or none of it.
  // ---------------------------------------------------------------------

  Future<void> create({
    required String code,
    required String name,
    required int price,
    required int? buyPrice,
    required double stock,
    required double lowStockAt,
    required String unit,
  }) {
    final actor = SessionService.instance.actor;
    return _ref.doc(code).set({
      'name': name,
      'nameLower': name.toLowerCase(),
      'price': price,
      'buyPrice': buyPrice,
      'stock': stock,
      'lowStockAt': lowStockAt,
      'unit': unit,
      'active': true,
      'soldCount': 0,
      'createdBy': actor,
      'updatedBy': actor,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Edits everything except the code (it's the document ID).
  /// Stock here is SET to what was typed: it's a deliberate correction
  /// (a count found 2 bags short), so the difference is logged as one.
  Future<void> update({
    required Product before,
    required String name,
    required int price,
    required int? buyPrice,
    required double stock,
    required double lowStockAt,
    required String unit,
    required bool active,
  }) {
    final actor = SessionService.instance.actor;
    final batch = _db.batch();
    batch.update(_ref.doc(before.code), {
      'name': name,
      'nameLower': name.toLowerCase(),
      'price': price,
      'buyPrice': buyPrice,
      'stock': stock,
      'lowStockAt': lowStockAt,
      'unit': unit,
      'active': active,
      // Now that trusted cashiers can change prices, record who did it.
      'updatedBy': actor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final delta = stock - before.stock;
    if (delta != 0) {
      batch.set(_moves.doc(), _move(
        productId: before.code,
        productName: name,
        unit: unit,
        qty: delta,
        type: 'correction',
        actor: actor,
      ));
    }
    return batch.commit();
  }

  /// A delivery arrived: add [qty] to stock and log where it came from.
  ///
  /// Uses an increment, not "set stock to X": if another phone sells one
  /// of these at the same moment, both changes survive. Setting a number
  /// would let one phone silently overwrite the other.
  Future<void> receiveStock({
    required Product product,
    required double qty,
    String? supplier,
    int? unitCost,
    String? note,
  }) {
    final actor = SessionService.instance.actor;
    final batch = _db.batch();

    batch.update(_ref.doc(product.code), {
      'stock': FieldValue.increment(qty),
      // A new delivery price becomes the product's buying price, so the
      // profit figures follow what the shop is actually paying now.
      if (unitCost != null) 'buyPrice': unitCost,
      if (supplier != null) 'lastSupplier': supplier,
      'updatedBy': actor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(_moves.doc(), _move(
      productId: product.code,
      productName: product.name,
      unit: product.unit,
      qty: qty,
      type: 'received',
      actor: actor,
      supplier: supplier,
      unitCost: unitCost,
      note: note,
    ));

    // Remember the supplier for next time's suggestions. arrayUnion adds
    // it only if it isn't already in the list, and works offline.
    if (supplier != null) {
      batch.update(_shopRef, {'suppliers': FieldValue.arrayUnion([supplier])});
    }
    return batch.commit();
  }

  /// Only for products never sold; the screen hides the button otherwise,
  /// and the security rules refuse it too (soldCount must be 0).
  Future<void> delete(String code) {
    return _ref.doc(code).delete();
  }

  /// Newest stock changes first, for the owner's Stock history screen.
  Stream<List<StockMove>> recentMoves({int limit = 200}) {
    return _moves
        .orderBy('createdAtClient', descending: true)
        .limit(limit)
        .snapshots()
        .map((q) => q.docs.map(StockMove.fromDoc).toList());
  }

  Map<String, dynamic> _move({
    required String productId,
    required String productName,
    required String unit,
    required double qty,
    required String type,
    required Map<String, String> actor,
    String? supplier,
    int? unitCost,
    String? note,
  }) {
    return {
      'productId': productId,
      'productName': productName,
      'unit': unit,
      'qty': qty,
      'type': type,
      'supplier': supplier,
      'unitCost': unitCost,
      'note': note,
      'by': actor,
      // Ordering uses the phone's clock so offline entries sort correctly
      // the moment they're made; the server time is kept as a cross-check.
      'createdAtClient': Timestamp.now(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}