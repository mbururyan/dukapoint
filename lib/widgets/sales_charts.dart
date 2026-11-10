import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Chart colours. One blue for every single-series chart, checked with the
/// dataviz validator. Not plum (that means "button" in this app) and not
/// amber or green (those mean cash and M-Pesa).
class ChartColors {
  ChartColors._();

  static const bar = Color(0xFF2A78D6);
  // Today's bar, while the day isn't over. Lighter so a half-day doesn't
  // read as a bad day; the bold "Today" under it says why.
  static const barPartial = Color(0xFF9CC3EE);
  static const stub = Color(0xFFE5E7EB); // zero, or hours still to come
  static const grid = Color(0xFFE5E7EB);
}

/// 13400 -> "13.4k", 16000 -> "16k", 950 -> "950". For axis labels and
/// tight spots only; anywhere there's room, use ksh() for the full amount.
String shortKsh(int v) {
  if (v >= 1000000) return '${_oneDecimal(v / 1000000)}M';
  if (v >= 1000) return '${_oneDecimal(v / 1000)}k';
  return '$v';
}

String _oneDecimal(double x) {
  final s = x >= 100 ? x.round().toString() : x.toStringAsFixed(1);
  // "14.0" -> "14": a trailing .0 is noise on a phone screen.
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

// -------------------------------------------------------------------------
// Column bars: 7 days on the Owner tab, sales by hour on Sales summary
// -------------------------------------------------------------------------

/// Vertical bars from a shared baseline, tallest bar = full height.
/// No y-axis: the exact figure is one tap away ([onSelect]) and the busiest
/// bar is named in words above the chart, so gridlines would only add noise.
class ColumnBars extends StatefulWidget {
  const ColumnBars({
    super.key,
    required this.values,
    required this.labels,
    this.height = 90,
    this.lastIsPartial = false,
    this.futureFrom,
    this.onSelect,
  });

  final List<int> values;

  /// One per bar; '' leaves that bar unlabelled (hourly bars label every 3rd).
  final List<String> labels;
  final double height;

  /// Draw the last bar lighter: today, still going.
  final bool lastIsPartial;

  /// Bars from this index on haven't happened yet (later hours today):
  /// drawn as flat stubs so the day's shape stays honest.
  final int? futureFrom;

  /// Called with the tapped bar, or null when it's tapped again. Leave null
  /// to make the bars not tappable (the Owner tab card is tapped as a whole).
  final ValueChanged<int?>? onSelect;

  @override
  State<ColumnBars> createState() => _ColumnBarsState();
}

class _ColumnBarsState extends State<ColumnBars> {
  int? _selected;

  bool _isFuture(int i) => widget.futureFrom != null && i >= widget.futureFrom!;

  void _tap(int i) {
    if (widget.onSelect == null || _isFuture(i)) return;
    setState(() => _selected = _selected == i ? null : i);
    widget.onSelect!(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    final max = widget.values.fold<int>(0, math.max);
    // Wide gaps for a week, narrow for 15-ish hours, so bars stay chunky.
    final gap = n <= 8 ? 5.0 : 2.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  // The whole column is the tap target, not just the bar:
                  // a short bar is a tiny thing to hit with a thumb.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onSelect == null ? null : () => _tap(i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gap),
                      child: Align(alignment: Alignment.bottomCenter, child: _bar(i, n, max)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: ChartColors.grid),
        const SizedBox(height: 4),
        SizedBox(
          height: 16,
          // Labels are centred under their bar but may be wider than it
          // ("11am" over a 14px bar), so they're placed freely, not boxed in.
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth / n;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < n; i++)
                    if (widget.labels[i].isNotEmpty)
                      Positioned(
                        left: w * i + w / 2 - 24,
                        width: 48,
                        top: 0,
                        child: Text(
                          widget.labels[i],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.lastIsPartial && i == n - 1 ? AppColors.ink : AppColors.inkSoft,
                            fontWeight: widget.lastIsPartial && i == n - 1 ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bar(int i, int n, int max) {
    final v = widget.values[i];
    final flat = _isFuture(i) || v == 0 || max == 0;
    // A sale of Ksh 50 on a Ksh 20,000 day still shows as a sliver, not
    // nothing: "there were sales" and "there were none" must look different.
    final h = flat ? 2.0 : math.max(4.0, v / max * widget.height);
    final color = flat
        ? ChartColors.stub
        : (widget.lastIsPartial && i == n - 1 ? ChartColors.barPartial : ChartColors.bar);
    final dimmed = _selected != null && _selected != i;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: dimmed ? 0.4 : 1,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.vertical(top: Radius.circular(flat ? 1 : 4)),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Trend line: sales by day for "7 days" and "This month"
// -------------------------------------------------------------------------

/// One blue line over faint gridlines, the last point marked. Tap or drag
/// along it to read any day ([onSelect] gets the index).
class TrendLine extends StatefulWidget {
  const TrendLine({
    super.key,
    required this.values,
    required this.labels,
    this.height = 150,
    this.onSelect,
  });

  final List<int> values;
  final List<String> labels; // '' = unlabelled
  final double height;
  final ValueChanged<int?>? onSelect;

  @override
  State<TrendLine> createState() => _TrendLineState();
}

class _TrendLineState extends State<TrendLine> {
  int? _selected;

  void _pick(double dx, double width) {
    final n = widget.values.length;
    if (n == 0) return;
    final i = _LinePainter.indexAt(dx, width, n);
    if (i == _selected) return;
    setState(() => _selected = i);
    widget.onSelect?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition.dx, w),
          // Sideways drags only, so scrolling the page up and down still works.
          onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, w),
          child: CustomPaint(
            size: Size(w, widget.height),
            painter: _LinePainter(values: widget.values, labels: widget.labels, selected: _selected),
          ),
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.values, required this.labels, required this.selected});

  final List<int> values;
  final List<String> labels;
  final int? selected;

  // Room for "20k" on the left and the day labels underneath.
  static const _left = 34.0;
  static const _right = 10.0;
  static const _top = 8.0;
  static const _bottom = 22.0;

  static double _x(int i, int n, double width) {
    final plotW = width - _left - _right;
    return n == 1 ? _left + plotW / 2 : _left + plotW * i / (n - 1);
  }

  static int indexAt(double dx, double width, int n) {
    if (n == 1) return 0;
    final plotW = width - _left - _right;
    return ((dx - _left) / plotW * (n - 1)).round().clamp(0, n - 1);
  }

  /// The top gridline: a round number at or above the biggest day,
  /// so the axis reads 0 / 10k / 20k rather than 0 / 8.2k / 16.4k.
  static int _niceMax(int max) {
    if (max <= 0) return 1000;
    final mag = math.pow(10, (math.log(max) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (m * mag >= max) return (m * mag).round();
    }
    return (10 * mag).round();
  }

  void _text(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.center, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: 10.5,
          color: bold ? AppColors.ink : AppColors.inkSoft,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final top = _niceMax(values.fold<int>(0, math.max));
    final plotH = size.height - _top - _bottom;
    double y(int v) => _top + plotH * (1 - v / top);

    // Gridlines and their labels: 0, half, top. Faint on purpose.
    final grid = Paint()
      ..color = ChartColors.grid
      ..strokeWidth = 1;
    for (final v in [0, top ~/ 2, top]) {
      final gy = y(v);
      canvas.drawLine(Offset(_left, gy), Offset(size.width - _right, gy), grid);
      _text(canvas, shortKsh(v), Offset(_left - 6, gy), align: TextAlign.right);
    }

    // The guide for a tapped day, under the line.
    if (selected != null) {
      final sx = _x(selected!, n, size.width);
      canvas.drawLine(Offset(sx, _top), Offset(sx, _top + plotH), grid..strokeWidth = 1.5);
    }

    final line = Paint()
      ..color = ChartColors.bar
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (n > 1) {
      final path = Path()..moveTo(_x(0, n, size.width), y(values[0]));
      for (var i = 1; i < n; i++) {
        path.lineTo(_x(i, n, size.width), y(values[i]));
      }
      canvas.drawPath(path, line);
    }

    // Last point (today) always marked; the tapped point too. A white ring
    // keeps the dot readable where it sits on the line.
    void dot(int i, double r) {
      final c = Offset(_x(i, n, size.width), y(values[i]));
      canvas.drawCircle(c, r + 2, Paint()..color = Colors.white);
      canvas.drawCircle(c, r, Paint()..color = ChartColors.bar);
    }

    dot(n - 1, 4);
    if (selected != null && selected != n - 1) dot(selected!, 4.5);

    // Day labels, the last one bold ("Today").
    final ly = size.height - _bottom / 2 + 2;
    for (var i = 0; i < n; i++) {
      if (labels[i].isEmpty) continue;
      final lx = _x(i, n, size.width).clamp(_left, size.width - 12).toDouble();
      _text(canvas, labels[i], Offset(lx, ly), bold: i == n - 1);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.selected != selected || old.values != values || old.labels != labels;
}