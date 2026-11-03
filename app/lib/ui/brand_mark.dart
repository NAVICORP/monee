// Written by tools/brand/brand.py. Do not edit by hand.
import 'dart:ui';

// The purse of the logo in a 1000 x 1000 box.

/// The body, filled.
Path purseeBody() => Path()
  ..moveTo(238, 392)
  ..cubicTo(322, 312, 678, 312, 762, 392)
  ..cubicTo(846, 466, 872, 598, 864, 690)
  ..cubicTo(856, 802, 772, 852, 648, 852)
  ..lineTo(352, 852)
  ..cubicTo(228, 852, 144, 802, 136, 690)
  ..cubicTo(128, 598, 154, 466, 238, 392)
  ..close();

/// The two clasp posts, as strokes with round ends, with a ball on each.
Path purseePosts() => Path()
  ..moveTo(482, 340)
  ..lineTo(474, 284)
  ..moveTo(518, 340)
  ..lineTo(526, 284);
const double purseePostStroke = 38;
const List<Offset> purseeBalls = [Offset(463, 262), Offset(537, 262)];
const double purseeBallRadius = 48;

/// The line under the frame and the P, cut out of the purse as strokes.
Path purseeFrame() => Path()
  ..moveTo(186, 452)
  ..cubicTo(316, 372, 684, 372, 814, 452);
const double purseeFrameStroke = 30;
Path purseeP() => Path()
  ..moveTo(412, 488)
  ..lineTo(412, 762)
  ..moveTo(412, 488)
  ..lineTo(510, 488)
  ..cubicTo(570, 488, 610, 528, 610, 586)
  ..cubicTo(610, 644, 570, 684, 510, 684)
  ..lineTo(412, 684);
const double purseePStroke = 88;

const double purseeShift = -38;
const int purseeMainColour = 0xFF6D4AE8;
const int purseeDeepColour = 0xFF5634C7;
