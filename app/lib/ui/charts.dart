import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// One slice of the pie.
class Slice {
  const Slice(this.label, this.value, this.color);
  final String label;
  final num value;
  final Color color;
}

/// A pie with its labels outside, joined to their slices by thin lines, like
/// the Stats tab. Small slices beyond the first few share no label.
class PieChart extends StatelessWidget {
  const PieChart({super.key, required this.slices, this.height = 260, this.maxLabels = 8});
  final List<Slice> slices;
  final double height;
  final int maxLabels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _PiePainter(slices, maxLabels)),
    );
  }
}

class _PiePainter extends CustomPainter {
  /// Drawn at night: a switch repaints it.
  final bool night = K.dark;

  _PiePainter(this.slices, this.maxLabels);
  final List<Slice> slices;
  final int maxLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<num>(0, (a, s) => a + s.value);
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.height / 2 - 34, size.width / 2 - 110).clamp(40.0, 140.0).toDouble();
    if (total <= 0) {
      canvas.drawCircle(c, r, Paint()..color = K.surface2);
      return;
    }
    var a = -math.pi / 2;
    final labels = <(double, Slice)>[];
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = 2 * math.pi * (s.value / total);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, sweep, true, Paint()..color = s.color);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, sweep, true,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      if (i < maxLabels && s.value / total >= 0.004) labels.add((a + sweep / 2, s));
      a += sweep;
    }
    // Labels on two sides, spread so they never sit on each other.
    final left = labels.where((l) => math.cos(l.$1) < 0).toList()..sort((x, y) => math.sin(x.$1).compareTo(math.sin(y.$1)));
    final right = labels.where((l) => math.cos(l.$1) >= 0).toList()..sort((x, y) => math.sin(x.$1).compareTo(math.sin(y.$1)));
    void side(List<(double, Slice)> list, bool isLeft) {
      const gap = 30.0;
      final ys = <double>[];
      for (final l in list) {
        var y = c.dy + (r + 18) * math.sin(l.$1);
        if (ys.isNotEmpty && y < ys.last + gap) y = ys.last + gap;
        ys.add(y);
      }
      // Pull the column back inside the box when it ran over the bottom.
      final over = ys.isEmpty ? 0.0 : ys.last - (size.height - 14);
      for (var i = 0; i < ys.length; i++) {
        if (over > 0) ys[i] -= over;
      }
      for (var i = 0; i < list.length; i++) {
        final (ang, s) = list[i];
        final edge = Offset(c.dx + r * math.cos(ang), c.dy + r * math.sin(ang));
        final x = isLeft ? c.dx - r - 24 : c.dx + r + 24;
        final y = ys[i];
        canvas.drawPath(
            Path()
              ..moveTo(edge.dx, edge.dy)
              ..quadraticBezierTo(x + (isLeft ? 10 : -10), edge.dy, x, y),
            Paint()
              ..color = s.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
        // Rounded to one place first, as the server's percent is, so the label matches the list's pill.
        final pct = (1000 * s.value / total).round() / 10;
        final tp = TextPainter(
          text: TextSpan(children: [
            TextSpan(text: s.label, style: T.tiny.copyWith(color: K.ink, fontWeight: FontWeight.w700)),
            TextSpan(text: '\n${pct < 10 ? pct.toStringAsFixed(1) : pct.round()}%', style: T.tiny),
          ]),
          textDirection: TextDirection.ltr,
          textAlign: isLeft ? TextAlign.right : TextAlign.left,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: math.max(40, (isLeft ? x - 6 : size.width - x - 6)));
        final tx = isLeft ? x - 4 - tp.width : x + 4;
        tp.paint(canvas, Offset(tx, y - tp.height / 2));
      }
    }

    side(left, true);
    side(right, false);
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.slices != slices || old.night != night;
}

/// A point on a line or a bar in a row.
class ChartPoint {
  const ChartPoint(this.label, this.value, {this.value2});
  final String label;
  final num value;

  /// A second series (expenses beside income, liabilities beside assets).
  final num? value2;
}

/// A simple line chart with dots, the labels along the bottom and the highest
/// value at the top left. Draws a second line when the points carry value2.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.points, this.height = 180, this.color, this.color2, this.format});
  final List<ChartPoint> points;
  final double height;
  final Color? color;
  final Color? color2;
  final String Function(num)? format;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _LinePainter(points, color ?? K.blue, color2 ?? K.expense, format)));
}

class _LinePainter extends CustomPainter {
  /// Drawn at night: a switch repaints it.
  final bool night = K.dark;

  _LinePainter(this.points, this.color, this.color2, this.format);
  final List<ChartPoint> points;
  final Color color;
  final Color color2;
  final String Function(num)? format;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const top = 22.0, bottom = 22.0, side = 8.0;
    final vals = [for (final p in points) p.value, for (final p in points) if (p.value2 != null) p.value2!];
    var hi = vals.reduce(math.max).toDouble(), lo = math.min(0, vals.reduce(math.min)).toDouble();
    if (hi == lo) hi = lo + 1;
    final w = size.width - side * 2, h = size.height - top - bottom;
    double x(int i) => side + (points.length == 1 ? w / 2 : w * i / (points.length - 1));
    double y(num v) => top + h * (1 - (v - lo) / (hi - lo));
    final grid = Paint()
      ..color = K.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final gy = top + h * i / 2;
      canvas.drawLine(Offset(side, gy), Offset(size.width - side, gy), grid);
    }
    if (lo < 0) canvas.drawLine(Offset(side, y(0)), Offset(size.width - side, y(0)), grid..color = K.border2);
    void line(num Function(ChartPoint) v, Color col) {
      final p = Path();
      for (var i = 0; i < points.length; i++) {
        final o = Offset(x(i), y(v(points[i])));
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeJoin = StrokeJoin.round);
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(Offset(x(i), y(v(points[i]))), 3.2, Paint()..color = col);
      }
    }

    line((p) => p.value, color);
    if (points.any((p) => p.value2 != null)) line((p) => p.value2 ?? 0, color2);
    final every = (points.length / 6).ceil().clamp(1, 100);
    for (var i = 0; i < points.length; i += every) {
      final tp = TextPainter(text: TextSpan(text: points[i].label, style: T.tiny), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset((x(i) - tp.width / 2).clamp(0, size.width - tp.width), size.height - bottom + 6));
    }
    final f = format ?? (num v) => v.round().toString();
    final tp = TextPainter(text: TextSpan(text: f(hi), style: T.tiny), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(side, 2));
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.points != points || old.night != night;
}

/// Bars in a row (two per label when value2 is given), for income against
/// expenses month by month.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.points, this.height = 180, this.color, this.color2});
  final List<ChartPoint> points;
  final double height;
  final Color? color;
  final Color? color2;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _BarPainter(points, color ?? K.income, color2 ?? K.expense)));
}

class _BarPainter extends CustomPainter {
  /// Drawn at night: a switch repaints it.
  final bool night = K.dark;

  _BarPainter(this.points, this.color, this.color2);
  final List<ChartPoint> points;
  final Color color;
  final Color color2;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const bottom = 22.0, top = 8.0;
    final hi = [for (final p in points) p.value, for (final p in points) p.value2 ?? 0].fold<num>(1, (a, b) => math.max(a, b.abs()));
    final h = size.height - bottom - top;
    final slot = size.width / points.length;
    final two = points.any((p) => p.value2 != null);
    final bw = math.min(18.0, slot * (two ? 0.3 : 0.5));
    for (var i = 0; i < points.length; i++) {
      final cx = slot * i + slot / 2;
      void bar(num v, double dx, Color c) {
        final bh = h * (v.abs() / hi);
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(cx + dx - bw / 2, top + h - bh, bw, bh), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
            Paint()..color = c);
      }

      if (two) {
        bar(points[i].value, -bw / 2 - 1, color);
        bar(points[i].value2 ?? 0, bw / 2 + 1, color2);
      } else {
        bar(points[i].value, 0, color);
      }
      if (points.length <= 12 || i % 2 == 0) {
        final tp = TextPainter(text: TextSpan(text: points[i].label, style: T.tiny), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, size.height - bottom + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.points != points || old.night != night;
}
