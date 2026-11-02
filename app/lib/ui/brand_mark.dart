// Written by tools/brand/brand.py. Do not edit by hand.
import 'dart:ui';

/// The m of the logo in a 1000 x 1000 box, as one stroke with round ends.
Path moneeM() => Path()
  ..moveTo(245, 760)
  ..lineTo(245, 488)
  ..cubicTo(245, 392, 305, 338, 372, 338)
  ..cubicTo(442, 338, 500, 392, 500, 488)
  ..lineTo(500, 760)
  ..moveTo(500, 488)
  ..cubicTo(500, 392, 560, 338, 628, 338)
  ..cubicTo(696, 338, 755, 392, 755, 488)
  ..lineTo(755, 760);

const double moneeStroke = 112;
const Offset moneeCoin = Offset(755, 196);
const double moneeCoinRadius = 64;
const double moneeShift = 22;
const int moneeMainColour = 0xFF6D4AE8;
const int moneeDeepColour = 0xFF5634C7;
