import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/shop.dart';
import '../models/staff.dart';
import 'cart_service.dart';
import 'catalog_service.dart';
import 'pin_hasher.dart';

/// Holds who is using the app right now: which shop this phone belongs to,
/// its staff list, and which staff member is on shift.
///
/// One shared instance, loaded once after sign-in, so screens read
/// SessionService.instance.shop instead of each fetching it from Firestore.
class SessionService extends ChangeNotifier {
  SessionService._();
  static final instance = SessionService._();

  final _db = FirebaseFirestore.instance;

  Shop? shop;
  List<Staff> staff = []; // active only: who can sign in at the PIN screen
  List<Staff> allStaff = []; // includes deactivated: for the owner's staff list
  Staff? current; // null = nobody on shift, show the PIN screen

  // True after someone types the owner PIN on the Owner tab during a
  // cashier's shift. Cleared when the tab is left or the shift ends, so
  // the owner area never stays open for the next person at the till.
  bool _ownerUnlocked = false;

  StreamSubscription? _shopSub;
  StreamSubscription? _staffSub;

  CollectionReference<Map<String, dynamic>> get _staffRef =>
      _db.collection('shops').doc(shop!.id).collection('staff');

  /// Loads the shop for this login. Returns null on success, or a message
  /// to show the user if the login isn't linked to a usable shop.
  Future<String?> load(String uid) async {
    await _cancelStreams();

    // get() asks the server first and falls back to the phone's cache when
    // offline, so after the first sign-in this works with no internet.
    final userDoc = await _db.collection('users').doc(uid).get();
    final shopId = userDoc.data()?['shopId'] as String?;
    if (shopId == null) {
      return 'This login is not linked to a shop yet. Contact DukaPoint.';
    }

    final shopRef = _db.collection('shops').doc(shopId);
    final shopSnap = await shopRef.get();
    if (!shopSnap.exists) {
      return 'Shop "$shopId" was not found. Contact DukaPoint.';
    }
    shop = Shop.fromDoc(shopSnap);

    // Live listeners, so a change you make in the console (paidUntil, a new
    // cashier) reaches the phone without a restart.
    _shopSub = shopRef.snapshots().listen((s) {
      if (!s.exists) return;
      shop = Shop.fromDoc(s);
      notifyListeners();
    });

    _staffSub = shopRef.collection('staff').snapshots().listen((q) {
      final list = q.docs.map(Staff.fromDoc).toList();
      // Active first, then cashiers before owner, then by name.
      list.sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        if (a.isOwner != b.isOwner) return a.isOwner ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      allStaff = list;
      staff = list.where((s) => s.active).toList();

      // If the person on shift was deactivated, end their shift.
      if (current != null && !staff.any((s) => s.id == current!.id)) {
        current = null;
        _ownerUnlocked = false;
      }
      notifyListeners();
    });

    // Start syncing the product list as soon as we know the shop, so it's
    // already in memory (and cached for offline) before the first scan.
    CatalogService.instance.start(shopId);

    notifyListeners();
    return null;
  }

  // ---------- PINs and shifts ----------

  bool checkPin(Staff who, String pin) {
    return who.pinHash == hashPin(shopId: shop!.id, staffId: who.id, pin: pin);
  }

  /// Saves a new PIN. Deliberately NOT awaited by callers: offline, a
  /// Firestore write only completes once the server confirms it, which
  /// could be hours away. The phone's cache updates instantly either way.
  Future<void> setPin(Staff who, String pin) {
    return _staffRef.doc(who.id).update({'pinHash': hashPin(shopId: shop!.id, staffId: who.id, pin: pin)});
  }

  void startShift(Staff who) {
    current = who;
    _ownerUnlocked = false;
    // Every shift starts with an empty cart, so a sale is always recorded
    // under the person who actually rang it up, whichever way the last
    // shift ended (Switch, deactivation, sign-out).
    CartService.instance.clear();
    notifyListeners();
  }

  void endShift() {
    current = null;
    _ownerUnlocked = false;
    notifyListeners();
  }

  // ---------- Owner access ----------

  /// The owner area is open if the owner is the one on shift, or if the
  /// owner PIN was typed on the Owner tab during someone else's shift.
  bool get ownerAccess => (current?.isOwner ?? false) || _ownerUnlocked;

  bool get ownerHasPin => staff.any((s) => s.isOwner && s.hasPin);

  /// Can whoever is on shift add/edit/delete products without the owner PIN?
  bool get canManageProducts => ownerAccess || (current?.canManageProducts ?? false);

  /// Checks [pin] against every active owner (a shop may have two).
  bool unlockOwner(String pin) {
    for (final o in staff.where((s) => s.isOwner && s.hasPin)) {
      if (checkPin(o, pin)) {
        _ownerUnlocked = true;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void lockOwner() {
    if (!_ownerUnlocked) return;
    _ownerUnlocked = false;
    notifyListeners();
  }

  // ---------- Managing staff (owner only, enforced by the Owner tab) ----------
  // None of these are awaited by the screens, for the same offline reason
  // as setPin. The staff listener above redraws the list instantly.

  Future<void> addCashier(String name) {
    return _staffRef.add({
      'name': name.trim(),
      'role': 'cashier',
      'active': true,
      // No pinHash: the cashier sets their own PIN the first time they
      // tap their name on the PIN screen.
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deactivate instead of delete: old sales keep pointing at this person,
  /// and "sales by cashier" must still show their name months later.
  Future<void> setActive(Staff who, bool active) {
    return _staffRef.doc(who.id).update({'active': active});
  }

  /// Clears the PIN so the person sets a new one at their next shift.
  Future<void> resetPin(Staff who) {
    return _staffRef.doc(who.id).update({'pinHash': FieldValue.delete()});
  }

  Future<void> setCanManageProducts(Staff who, bool allowed) {
    return _staffRef.doc(who.id).update({'canManageProducts': allowed});
  }

  /// Who is doing a write right now, stamped onto products so the owner
  /// can see who last changed a price.
  Map<String, String> get actor => {
        'id': current?.id ?? '',
        'name': current?.name ?? '',
      };

  // ---------- Cleanup ----------

  Future<void> clear() async {
    await _cancelStreams();
    CatalogService.instance.stop();
    shop = null;
    staff = [];
    allStaff = [];
    current = null;
    _ownerUnlocked = false;
    notifyListeners();
  }

  Future<void> _cancelStreams() async {
    await _shopSub?.cancel();
    await _staffSub?.cancel();
    _shopSub = null;
    _staffSub = null;
  }
}