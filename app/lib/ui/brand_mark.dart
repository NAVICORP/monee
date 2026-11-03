// Written by tools/brand/brand.py. Do not edit by hand.
import 'dart:ui';

/// The p of the logo in a 1000 x 1000 box, as strokes with round ends.
Path moneeM() => Path()
  ..moveTo(290, 770)
  ..lineTo(290, 230)
  ..moveTo(290, 440)
  ..cubicTo(290, 324, 384, 230, 500, 230)
  ..cubicTo(616, 230, 710, 324, 710, 440)
  ..cubicTo(710, 556, 616, 650, 500, 650)
  ..cubicTo(384, 650, 290, 556, 290, 440);

const double moneeStroke = 112;
const Offset moneeCoin = Offset(500, 440);
const double moneeCoinRadius = 70;
const double moneeShift = 22;
const int moneeMainColour = 0xFF6D4AE8;
const int moneeDeepColour = 0xFF5634C7;
