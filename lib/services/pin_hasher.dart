import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Turns a 4-digit PIN into a hash so the plain PIN is never stored.
///
/// Mixing in the shop and staff IDs means two cashiers who both pick 1234
/// get different hashes, and a hash copied from one person's record won't
/// work for anyone else.
///
/// Honest limit: there are only 10,000 possible PINs, so this stops casual
/// reading of the database, not a determined attacker. The real protection
/// is that only the shop's own login can read its staff records at all.
String hashPin({required String shopId, required String staffId, required String pin}) {
  return sha256.convert(utf8.encode('dukapoint:$shopId:$staffId:$pin')).toString();
}