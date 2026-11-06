import 'format.dart';

/// "bag" -> "bags", "box" -> "boxes", "battery" -> "batteries".
/// Simple English rules; good enough for shop words, and the owner types
/// the singular so odd words still read fine ("3 sack" never happens).
String plural(String word) {
  final w = word.trim();
  if (w.isEmpty || w == 'kg') return w;
  final lower = w.toLowerCase();
  if (RegExp(r'(s|x|z|ch|sh)$').hasMatch(lower)) return '${w}es';
  if (RegExp(r'[^aeiou]y$').hasMatch(lower)) return '${w.substring(0, w.length - 1)}ies';
  return '${w}s';
}

/// "1 bag", "3 bags", "2.5 kg". Weighed items always say kg, whatever word
/// the product has, because that's how the scale reads.
String countOf(double q, {required String unit, required String word}) {
  if (unit == 'kg') return '${qty(q)} kg';
  return '${qty(q)} ${q == 1 ? word : plural(word)}';
}

/// One cart or sale line, reduced to what the count summary needs.
typedef CountPart = ({double qty, String unit, String word});

/// "4 bags, 1 packet, 2.5 kg": adds up lines that share a word, so two
/// different feeds sold by the bag read as "4 bags", not "3 bags, 1 bag".
/// All weighed lines are added into one kg figure at the end.
String countSummary(Iterable<CountPart> parts) {
  final byWord = <String, double>{}; // keeps first-seen order
  var kg = 0.0;
  for (final p in parts) {
    if (p.unit == 'kg') {
      kg += p.qty;
    } else {
      byWord[p.word] = (byWord[p.word] ?? 0) + p.qty;
    }
  }
  final out = [
    for (final e in byWord.entries) countOf(e.value, unit: 'piece', word: e.key),
    if (kg > 0) countOf(kg, unit: 'kg', word: 'kg'),
  ];
  return out.join(', ');
}