// Written by tools/brand/brand.py. Do not edit by hand.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Paints the logo, the wallet on the lilac tile, in a square of [size].
/// [radius] is the tile's corner radius as a share of the side.
void paintPurseeTile(Canvas c, double size, {double radius = 0.24}) {
  c.save();
  c.scale(size / 1000);
  final tile = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1000, 1000), Radius.circular(1000 * radius));
  c.drawRRect(tile, Paint()..shader = Gradient.linear(Offset.zero, const Offset(1000, 1000), const [Color(0xFFF7F3FF), Color(0xFFDCD0FF)]));
  c.drawRRect(tile, Paint()..shader = Gradient.radial(const Offset(300, 150), 800, const [Color(0x99FFFFFF), Color(0x00FFFFFF)]));
  c.translate(17.6, -9.4);
  c.scale(0.9);
  paintPurseeWallet(c);
  c.restore();
}

/// Paints the wallet in its own 1000 x 1000 space.
void paintPurseeWallet(Canvas c) {
  c.drawOval(Rect.fromCenter(center: const Offset(520, 872), width: 660, height: 80), _blur(Color(0x735A3FC8), 22));

  // The bank note.
  c.save();
  _rotate(c, -7, const Offset(430, 420));
  const bill = Rect.fromLTWH(250, 300, 380, 220);
  c.drawRRect(RRect.fromRectAndRadius(bill, const Radius.circular(22)),
      Paint()..shader = Gradient.linear(bill.topCenter, bill.bottomCenter, const [Color(0xFFB8EBC6), Color(0xFF4FA86E)]));
  final ink = _line(Color(0x732F7A4A), 7, cap: StrokeCap.butt);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(276, 324, 328, 172), const Radius.circular(12)), ink);
  c.drawCircle(const Offset(440, 400), 34, ink);
  c.restore();

  // The card.
  c.save();
  _rotate(c, 9, const Offset(600, 400));
  const card = Rect.fromLTWH(410, 272, 380, 250);
  c.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(30)),
      Paint()..shader = Gradient.linear(card.topLeft, card.bottomRight, const [Color(0xFFA08BFF), Color(0xFF5B3BD6)]));
  const chip = Rect.fromLTWH(452, 318, 74, 56);
  c.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(12)),
      Paint()..shader = Gradient.linear(chip.topLeft, chip.bottomRight, const [Color(0xFFFFF1C2), Color(0xFFD9A030)]));
  c.drawLine(const Offset(430, 292), const Offset(770, 292), _line(Color(0x73FFFFFF), 8));
  c.restore();

  // The wallet itself.
  final body = _body();
  c.drawPath(body.shift(const Offset(0, -10)), _blur(Color(0x40000000)));
  c.drawPath(body, Paint()..shader = _radial(body.getBounds(), .3, .22, .95,
      const [Color(0xFF9C82FF), Color(0xFF6040E0), Color(0xFF341597)], const [0, .55, 1]));
  c.save();
  c.clipPath(body);
  c.drawPath(Path()
  ..moveTo(188, 836)
  ..lineTo(812, 836)
  ..lineTo(812, 700)
  ..cubicTo(640, 760, 360, 760, 188, 700)
  ..close(), _blur(Color(0x29000000)));
  c.drawLine(const Offset(200, 444), const Offset(800, 444), _line(Color(0x59FFFFFF), 10));
  c.restore();
  c.drawPath(_dashed(Path()
  ..moveTo(268, 462)
  ..lineTo(732, 462)
  ..cubicTo(762, 462, 780, 480, 780, 510)
  ..lineTo(780, 756)
  ..cubicTo(780, 786, 762, 804, 732, 804)
  ..lineTo(268, 804)
  ..cubicTo(238, 804, 220, 786, 220, 756)
  ..lineTo(220, 510)
  ..cubicTo(220, 480, 238, 462, 268, 462)
  ..close(), 20, 14), _line(Color(0xCCE3D9FF), 7));
  c.save();
  _rotate(c, -18, const Offset(320, 540));
  c.drawOval(Rect.fromCenter(center: const Offset(320, 540), width: 192, height: 80), _blur(Color(0x61FFFFFF)));
  c.restore();

  // The strap and its snap.
  final strap = Path()
  ..moveTo(560, 560)
  ..lineTo(820, 560)
  ..cubicTo(862, 560, 884, 584, 884, 620)
  ..lineTo(884, 650)
  ..cubicTo(884, 686, 862, 710, 820, 710)
  ..lineTo(560, 710)
  ..close();
  c.drawPath(strap.shift(const Offset(-6, 12)), _blur(Color(0x59000000)));
  final sb = strap.getBounds();
  c.drawPath(strap, Paint()..shader = Gradient.linear(sb.topCenter, sb.bottomCenter, const [Color(0xFF5534CF), Color(0xFF2C1185)]));
  c.drawPath(_dashed(Path()
  ..moveTo(580, 588)
  ..lineTo(816, 588)
  ..cubicTo(842, 588, 856, 602, 856, 622)
  ..lineTo(856, 648)
  ..cubicTo(856, 668, 842, 682, 816, 682)
  ..lineTo(580, 682), 16, 12), _line(Color(0xCCE3D9FF), 6));
  c.drawLine(const Offset(575, 574), const Offset(818, 574), _line(Color(0x40FFFFFF), 8));
  c.drawCircle(const Offset(800, 641), 40, _blur(Color(0x59000000)));
  c.drawCircle(const Offset(800, 635), 38, Paint()..shader = _radial(Rect.fromCircle(center: const Offset(800, 635), radius: 38), .35, .3, .8,
      const [Color(0xFFFFF4CC), Color(0xFFF7C653), Color(0xFFA86A08)], const [0, .45, 1]));
  c.drawCircle(const Offset(800, 635), 20, _line(Color(0x80A86A08), 6, cap: StrokeCap.butt));
  c.drawCircle(const Offset(787, 620), 8, Paint()..color = Color(0xE6FFFFFF));
}

Path _body() => Path()
  ..moveTo(262, 430)
  ..lineTo(738, 430)
  ..cubicTo(784, 430, 812, 458, 812, 504)
  ..lineTo(812, 762)
  ..cubicTo(812, 808, 784, 836, 738, 836)
  ..lineTo(262, 836)
  ..cubicTo(216, 836, 188, 808, 188, 762)
  ..lineTo(188, 504)
  ..cubicTo(188, 458, 216, 430, 262, 430)
  ..close();

Paint _blur(Color colour, [double sigma = 9]) => Paint()
  ..color = colour
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

Paint _line(Color colour, double width, {StrokeCap cap = StrokeCap.round}) => Paint()
  ..color = colour
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = cap;

void _rotate(Canvas c, double degrees, Offset around) {
  c.translate(around.dx, around.dy);
  c.rotate(degrees * math.pi / 180);
  c.translate(-around.dx, -around.dy);
}

/// A radial gradient stretched over [box] the way SVG draws one in the
/// shape's own box: centre at ([cx], [cy]) and radius [r], as shares of it.
Shader _radial(Rect box, double cx, double cy, double r, List<Color> colours, List<double> stops) =>
    Gradient.radial(Offset.zero, 1, colours, stops, TileMode.clamp, Float64List.fromList([
      box.width * r, 0, 0, 0, //
      0, box.height * r, 0, 0, //
      0, 0, 1, 0, //
      box.left + box.width * cx, box.top + box.height * cy, 0, 1, //
    ]));

Path _dashed(Path path, double on, double off) {
  final out = Path();
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d < m.length; d += on + off) {
      out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
    }
  }
  return out;
}
