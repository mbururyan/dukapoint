import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shop.dart';

/// Where a shop is in its paid plan.
enum PlanPhase {
  unset, // no paidUntil yet (you haven't set it): sells normally
  active, // more than 7 days left
  endingSoon, // last 7 days: owner sees a countdown
  grace, // ended up to 14 days ago: everyone sees it, still sells
  paused, // grace over: new sales stop
  suspended, // you set status to 'suspended': stops at once
}

class PlanState {
  const PlanState(this.phase, {this.paidUntil, this.daysLeft = 0, this.pauseOn});

  final PlanPhase phase;
  final DateTime? paidUntil; // last paid day
  final int daysLeft; // days to paidUntil; negative once it's passed
  final DateTime? pauseOn; // first day new sales stop (grace only)

  bool get canSell => phase != PlanPhase.paused && phase != PlanPhase.suspended;
  int get daysSinceEnd => -daysLeft;
}

/// What a shop pays you and where. One record you edit in the console
/// (config/billing), so the price or Paybill can change without an update.
class BillingInfo {
  const BillingInfo({required this.paybill, required this.amount});
  final String paybill;
  final int amount; // Ksh per month
}

/// Works out the plan phase, using a clock that can't be wound back.
///
/// Each time the app starts online it asks Firestore for the real time and
/// remembers the latest one seen. "Now" is never earlier than that, so
/// setting the phone's date back doesn't undo a pause. (Someone who stays
/// offline for weeks isn't stopped; their sales still reach you later.)
class PlanService extends ChangeNotifier {
  PlanService._();
  static final instance = PlanService._();

  static const warnDays = 7;
  static const graceDays = 14;
  static const _seenKey = 'serverTimeSeen';

  final _db = FirebaseFirestore.instance;
  late SharedPreferences _prefs;
  DateTime? _serverSeen;
  BillingInfo? billing;

  /// Your number for the drawer's Help (config/billing, field supportPhone),
  /// e.g. "0712345678". Null until you add it in the console.
  String? supportPhone;

  StreamSubscription? _authSub;
  StreamSubscription? _userSub;
  StreamSubscription? _billingSub;

  /// Call once in main(), after Firebase is set up.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final ms = _prefs.getInt(_seenKey);
    if (ms != null) _serverSeen = DateTime.fromMillisecondsSinceEpoch(ms);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  /// Today, but never before the latest real time this phone has seen.
  DateTime get now {
    final phone = DateTime.now();
    final seen = _serverSeen;
    return (seen != null && seen.isAfter(phone)) ? seen : phone;
  }

  PlanState stateFor(Shop shop) {
    if (!shop.isActive) return const PlanState(PlanPhase.suspended);
    final until = shop.paidUntil;
    if (until == null) return const PlanState(PlanPhase.unset);

    // Whole days, phone-local: paid "until 30 Nov" means all of 30 Nov.
    final n = now;
    final today = DateTime(n.year, n.month, n.day);
    final end = DateTime(until.year, until.month, until.day);
    final daysLeft = end.difference(today).inDays;

    if (daysLeft > warnDays) return PlanState(PlanPhase.active, paidUntil: end, daysLeft: daysLeft);
    if (daysLeft >= 0) return PlanState(PlanPhase.endingSoon, paidUntil: end, daysLeft: daysLeft);
    final pauseOn = end.add(const Duration(days: graceDays + 1));
    if (-daysLeft <= graceDays) {
      return PlanState(PlanPhase.grace, paidUntil: end, daysLeft: daysLeft, pauseOn: pauseOn);
    }
    return PlanState(PlanPhase.paused, paidUntil: end, daysLeft: daysLeft, pauseOn: pauseOn);
  }

  // -------------------------------------------------------------------

  void _onUser(User? user) {
    _userSub?.cancel();
    _billingSub?.cancel();
    if (user == null) return;

    final ref = _db.collection('users').doc(user.uid);
    // Ask the server to stamp the real time on this login's record. It only
    // arrives once online; until then the last remembered time is used.
    ref.update({'lastSeenAt': FieldValue.serverTimestamp()}).then((_) {}, onError: (_) {});
    _userSub = ref.snapshots(includeMetadataChanges: true).listen((s) {
      // Pending = still our own unsent write, with no real time in it yet.
      if (s.metadata.hasPendingWrites) return;
      final t = (s.data()?['lastSeenAt'] as Timestamp?)?.toDate();
      if (t != null) _remember(t);
    });

    _billingSub = _db.collection('config').doc('billing').snapshots().listen((s) {
      final d = s.data();
      final paybill = (d?['paybill'] as String?)?.trim() ?? '';
      billing = paybill.isEmpty
          ? null
          : BillingInfo(paybill: paybill, amount: ((d?['amount'] as num?) ?? 0).round());
      final phone = (d?['supportPhone'] as String?)?.replaceAll(RegExp(r'\s+'), '') ?? '';
      supportPhone = phone.isEmpty ? null : phone;
      notifyListeners();
    }, onError: (_) {});
  }

  void _remember(DateTime t) {
    if (_serverSeen != null && !t.isAfter(_serverSeen!)) return; // only forwards
    _serverSeen = t;
    _prefs.setInt(_seenKey, t.millisecondsSinceEpoch);
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    _billingSub?.cancel();
    super.dispose();
  }
}