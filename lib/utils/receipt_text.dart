import '../models/sale.dart';
import '../models/shop.dart';
import 'format.dart';

/// The receipt as plain text, 32 characters wide: what fits on 58mm paper
/// in the printer's normal font. The screen shows exactly this text, so
/// what the cashier sees is what will print in step 6.
const receiptWidth = 32;

String buildReceiptText(Sale sale, Shop shop) {
  final out = StringBuffer();
  final line = '-' * receiptWidth;

  void center(String s) {
    if (s.trim().isEmpty) return;
    for (final part in _wrap(s, receiptWidth)) {
      final pad = ((receiptWidth - part.length) / 2).floor();
      out.writeln('${' ' * pad}$part');
    }
  }

  void leftRight(String left, String right) {
    final space = receiptWidth - right.length - 1;
    final l = left.length > space ? left.substring(0, space) : left;
    out.writeln('$l${' ' * (receiptWidth - l.length - right.length)}$right');
  }

  center(shop.name.toUpperCase());
  center(shop.address);
  if (shop.phone.isNotEmpty) center('Tel ${shop.phone}');
  if (shop.tillNumber.isNotEmpty) center('Buy Goods Till ${shop.tillNumber}');
  out.writeln(line);

  leftRight('Receipt', sale.receiptNo);
  leftRight('Date', _receiptDate(sale.at));
  leftRight('Served by', sale.cashierName);
  out.writeln(line);

  for (final i in sale.items) {
    for (final part in _wrap(i.name, receiptWidth)) {
      out.writeln(part);
    }
    final calc = i.unit == 'kg' ? '  ${qty(i.qty)}kg x ${kes(i.price)}' : '  ${qty(i.qty)} x ${kes(i.price)}';
    leftRight(calc, kes(i.lineTotal));
  }
  out.writeln(line);

  leftRight('TOTAL', 'Ksh ${kes(sale.total)}');
  if (sale.method == 'cash') {
    leftRight('Cash', kes(sale.tendered ?? sale.total));
    leftRight('Change', kes(sale.change ?? 0));
  } else if (sale.method == 'till') {
    leftRight('M-Pesa', kes(sale.total));
    leftRight('Code', sale.mpesaCode ?? '');
  }
  out.writeln(line);

  center(shop.receiptFooter);
  // Until eTIMS is integrated, say so plainly: protects the shop and you.
  center('This is not a tax invoice');
  center('Powered by DukaPoint');
  return out.toString().trimRight();
}

/// "15/10/2026 15:52", the format people expect on a Kenyan receipt.
String _receiptDate(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Breaks long text (a long product name) into lines that fit the paper,
/// at spaces where possible.
List<String> _wrap(String text, int width) {
  final words = text.trim().split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';
  for (var w in words) {
    while (w.length > width) {
      // A single word longer than the paper: hard-split it.
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(w.substring(0, width));
      w = w.substring(width);
    }
    if (current.isEmpty) {
      current = w;
    } else if (current.length + 1 + w.length <= width) {
      current = '$current $w';
    } else {
      lines.add(current);
      current = w;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}