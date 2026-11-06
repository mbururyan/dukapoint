import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'sales_service.dart';
import 'session_service.dart';

/// Counts sales that are saved on this phone but not yet on the server
/// (made or voided offline), so the cashier knows nothing is lost and why
/// the owner's phone doesn't show them yet.
///
/// Watches the last 8 days of sales: a sale older than that that's still
/// unsent is unlikely, and watching all history would cost reads.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final instance = SyncService._();

  int waiting = 0;

  /// True when the last answer came from the phone's copy, i.e. no
  /// connection to Firestore right now.
  bool offline = false;

  String? _shopId;
  StreamSubscription? _sub;

  /// Call once in main(). Follows the signed-in shop by itself.
  void init() {
    SessionService.instance.addListener(_onSession);
    _onSession();
  }

  void _onSession() {
    final id = SessionService.instance.shop?.id;
    if (id == _shopId) return;
    _shopId = id;
    _sub?.cancel();
    waiting = 0;
    offline = false;
    notifyListeners();
    if (id == null) return;

    final from = SalesService.dayKey(DateTime.now().subtract(const Duration(days: 8)));
    _sub = FirebaseFirestore.instance
        .collection('shops')
        .doc(id)
        .collection('sales')
        .where('dayKey', isGreaterThanOrEqualTo: from)
        // Metadata changes too: "sent" is a metadata change, not a data one,
        // so without this the count would never go back down.
        .snapshots(includeMetadataChanges: true)
        .listen((q) {
      final w = q.docs.where((d) => d.metadata.hasPendingWrites).length;
      final off = q.metadata.isFromCache;
      if (w != waiting || off != offline) {
        waiting = w;
        offline = off;
        notifyListeners();
      }
    }, onError: (_) {});
  }
}