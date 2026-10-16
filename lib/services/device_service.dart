import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Things that belong to THIS installation of the app, not to the shop:
/// its short phone tag and its receipt counter. Stored on the phone.
///
/// Receipt numbers look like DMD-K7-000124:
///   DMD    = the shop's code (set by you in the console)
///   K7     = this phone's tag, picked at random the first time it runs
///   000124 = this phone's counter
/// Two phones in one shop have different tags, so they can both sell
/// offline without ever issuing the same number. A reinstall restarts the
/// counter at 1, but under a NEW tag, so numbers still never repeat, and
/// nothing has to be restored from Firestore at sign-in.
class DeviceService {
  DeviceService._();
  static final instance = DeviceService._();

  static const _tagKey = 'deviceTag';
  static const _counterKey = 'receiptCounter';

  // No 0/O or 1/I: a cashier reading a receipt number out over the phone
  // shouldn't have to wonder which one it is.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  late SharedPreferences _prefs;
  late String tag;

  /// Call once in main() before the app starts.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs.getString(_tagKey);
    if (saved != null) {
      tag = saved;
    } else {
      final rnd = Random.secure();
      tag = List.generate(2, (_) => _alphabet[rnd.nextInt(_alphabet.length)]).join();
      await _prefs.setString(_tagKey, tag);
    }
  }

  /// Takes the next number and saves the counter BEFORE the sale is
  /// written, so even if the app crashes mid-sale the number is never
  /// handed out twice.
  String nextReceiptNo(String shopCode) {
    final n = (_prefs.getInt(_counterKey) ?? 0) + 1;
    _prefs.setInt(_counterKey, n);
    return '$shopCode-$tag-${n.toString().padLeft(6, '0')}';
  }
}