/// Shared number and date formatting so money, quantities and times look
/// the same on every screen (and later on the receipt).

/// 1045 -> "1,045". Whole shillings only, by design (no cents).
String kes(int amount) {
  final s = amount.abs().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  return amount < 0 ? '-$s' : s;
}

/// 1045 -> "Ksh 1,045". Use this wherever a price is shown on its own.
String ksh(int amount) => 'Ksh ${kes(amount)}';

/// 2.0 -> "2", 2.5 -> "2.5", 2.25 -> "2.25". Stock and kg quantities.
String qty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
}

/// +40 -> "+40", -2.5 -> "-2.5". For stock changes.
String signedQty(double value) => value > 0 ? '+${qty(value)}' : qty(value);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "15 Oct, 14:52". Hand-rolled rather than adding the intl package for
/// one format; the phone's local time is what the shop cares about.
String dayTime(DateTime t) {
  final local = t.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]}, $hh:$mm';
}