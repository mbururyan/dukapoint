import 'dart:math';

/// In-store codes for items without a barcode (feed bags, loose maize...).
///
/// Format: a valid 13-digit EAN-13 starting with "20". GS1 reserves the
/// 20-29 prefixes for in-store use, so these can never clash with a real
/// product's barcode, and any scanner can read them if printed later.
///
/// Random rather than counting up (2000000000001, ...2): a counter would
/// need one shared number that every phone agrees on, which breaks when
/// phones are offline. 10 random digits = 10 billion options, and the
/// caller still checks the catalogue for the (tiny) chance of a repeat.
String generateShopCode() {
  final rnd = Random.secure();
  final body = StringBuffer('20');
  for (var i = 0; i < 10; i++) {
    body.write(rnd.nextInt(10));
  }
  final twelve = body.toString();
  return '$twelve${ean13CheckDigit(twelve)}';
}

/// The 13th digit of an EAN-13: weights 1,3,1,3... across the first 12.
int ean13CheckDigit(String twelveDigits) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = twelveDigits.codeUnitAt(i) - 48;
    sum += i.isEven ? d : d * 3;
  }
  return (10 - sum % 10) % 10;
}

/// What a code may contain. Letters, digits and dashes only: the code
/// becomes a Firestore document ID, where "/" would break the path.
final _allowed = RegExp(r'^[A-Za-z0-9-]{4,32}$');

String? validateCode(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Scan, type, or generate a code';
  if (!_allowed.hasMatch(v)) return 'Use 4–32 letters, numbers or dashes';
  return null;
}