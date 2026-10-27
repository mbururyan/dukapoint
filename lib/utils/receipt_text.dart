import '../models/sale.dart';
import '../models/shop.dart';
import 'format.dart';

/// 58mm paper fits 32 characters a line in the printer's normal font, and
/// 16 in the big (double-width) font used for the shop name and TOTAL.
const receiptWidth = 32;
const receiptBigWidth = 16;

/// One printed line. Text is already padded/centred to its width, so the
/// screen preview, the printer and the shared text all line up the same way.
class ReceiptLine {
  const ReceiptLine(this.text, {this.big = false});
  final String text;

  /// Double width + double height + bold on paper; drawn twice the size on
  /// screen. Only 16 characters fit.
  final bool big;
}

/// The receipt as lines. Screen, printer and Share all start from here, so
/// they can never disagree about what a receipt says.
///
/// [reprint] adds a REPRINT line at the top: a second copy of a receipt
/// shouldn't look like a second purchase if a customer brings it back.
List<ReceiptLine> buildReceiptLines(Sale sale, Shop shop, {bool reprint = false}) {
  final out = <ReceiptLine>[];
  final line = '-' * receiptWidth;

  void center(String s, {bool big = false}) {
    if (s.trim().isEmpty) return;
    final width = big ? receiptBigWidth : receiptWidth;
    for (final part in _wrap(s, width)) {
      final pad = ((width - part.length) / 2).floor();
      out.add(ReceiptLine('${' ' * pad}$part', big: big));
    }
  }

  void leftRight(String left, String right, {int width = receiptWidth, bool big = false}) {
    final space = width - right.length - 1;
    final l = left.length > space ? left.substring(0, space) : left;
    out.add(ReceiptLine('$l${' ' * (width - l.length - right.length)}$right', big: big));
  }

  void plain(String s) => out.add(ReceiptLine(s));

  if (reprint) {
    center('*** REPRINT ***');
    plain('');
  }
  center(shop.name.toUpperCase(), big: true);
  center(shop.address);
  if (shop.phone.isNotEmpty) center('Tel ${shop.phone}');
  // Till / Paybill + account / Pochi number, whichever the shop uses.
  for (final l in shop.mpesaLines) {
    center(l);
  }
  plain(line);

  leftRight('Receipt', sale.receiptNo);
  leftRight('Date', _receiptDate(sale.at));
  leftRight('Served by', sale.cashierName);
  plain(line);

  for (final i in sale.items) {
    for (final part in _wrap(i.name, receiptWidth)) {
      plain(part);
    }
    final calc = i.unit == 'kg' ? '  ${qty(i.qty)}kg x ${kes(i.price)}' : '  ${qty(i.qty)} x ${kes(i.price)}';
    leftRight(calc, kes(i.lineTotal));
  }
  plain(line);

  // In the big font only 16 characters fit: "TOTAL Ksh 12,345" just does.
  // From Ksh 100,000 up there's no room, so the "Ksh" is dropped rather
  // than cutting the amount.
  final withKsh = 'Ksh ${kes(sale.total)}';
  final amount = 'TOTAL'.length + 1 + withKsh.length <= receiptBigWidth ? withKsh : kes(sale.total);
  leftRight('TOTAL', amount, width: receiptBigWidth, big: true);

  if (sale.method == 'cash') {
    leftRight('Cash', kes(sale.tendered ?? sale.total));
    leftRight('Change', kes(sale.change ?? 0));
  } else if (sale.method == 'till') {
    final via = switch (sale.channel) {
      'paybill' => 'M-Pesa Paybill',
      'pochi' => 'M-Pesa Pochi',
      _ => 'M-Pesa',
    };
    leftRight(via, kes(sale.total));
    leftRight('Code', sale.mpesaCode ?? '');
  }
  plain(line);

  center(shop.receiptFooter);
  // Until eTIMS is integrated, say so plainly: protects the shop and you.
  center('This is not a tax invoice');
  center('Powered by DukaPoint');
  return out;
}

/// The same receipt as plain text, for Share (WhatsApp / SMS). Big lines
/// are re-centred to the normal width, since a chat app has no big font.
String buildReceiptText(Sale sale, Shop shop) {
  return buildReceiptLines(sale, shop).map((l) {
    if (!l.big) return l.text;
    final t = l.text.trim();
    final pad = ((receiptWidth - t.length) / 2).floor();
    // TOTAL keeps its left/right layout, just spread to the full width.
    if (t.startsWith('TOTAL')) {
      final amount = t.substring(5).trim();
      final withKsh = amount.startsWith('Ksh') ? amount : 'Ksh $amount';
      return 'TOTAL${' ' * (receiptWidth - 5 - withKsh.length)}$withKsh';
    }
    return '${' ' * (pad < 0 ? 0 : pad)}$t';
  }).join('\n').trimRight();
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