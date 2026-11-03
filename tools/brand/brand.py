"""Pursee's logo: a 3D violet leather wallet with stitching, a snap strap, and
a card and a bank note sticking out of the top, on a light lilac tile. Drawn
here once in a 1000 x 1000 box, then written out as every icon the app, the
stores and the site use, so a change here reaches all of them at once.

    pip install pillow playwright
    python3 tools/brand/brand.py

Writes:
- web/assets/brand/monee-icon.svg   the logo as it is shown: the wallet on the tile
- web/assets/brand/monee-mark.svg   the wallet alone (for print)
- app/lib/ui/brand_mark.dart        the same drawing as a Flutter painter
- the logo and the flat wallet inside web/home.html
- the app, Android, iPhone, web app and site icons (PNG and favicon.ico)
"""
import io
import os
import re
import struct
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

TILE_TOP, TILE_BOTTOM = '#F7F3FF', '#DCD0FF'   # the tile, top left to bottom right
ANDROID_BG = '#EEE8FF'                          # the tile as one colour, behind Android's adaptive icon

# The wallet, in its own 1000 x 1000 space.
BODY = ('M 262 430 L 738 430 C 784 430 812 458 812 504 L 812 762 C 812 808 784 836 738 836 '
        'L 262 836 C 216 836 188 808 188 762 L 188 504 C 188 458 216 430 262 430 Z')
SHADE = 'M 188 836 L 812 836 L 812 700 C 640 760 360 760 188 700 Z'
STITCH = ('M 268 462 L 732 462 C 762 462 780 480 780 510 L 780 756 C 780 786 762 804 732 804 '
          'L 268 804 C 238 804 220 786 220 756 L 220 510 C 220 480 238 462 268 462 Z')
STRAP = 'M 560 560 L 820 560 C 862 560 884 584 884 620 L 884 650 C 884 686 862 710 820 710 L 560 710 Z'
STRAP_STITCH = 'M 580 588 L 816 588 C 842 588 856 602 856 622 L 856 648 C 856 668 842 682 816 682 L 580 682'
CENTRE = (536, 566)   # the middle of the wallet with its card, note and strap
WALLET = 0.9          # how big the wallet sits on the tile


def place(scale):
    return f'translate({500 - CENTRE[0] * scale:g} {500 - CENTRE[1] * scale:g}) scale({scale:g})'


def defs(p):
    """Gradients, blurs, the body clip and the flat wallet's cuts, ids prefixed with p."""
    return f'''<linearGradient id="{p}t" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{TILE_TOP}"/><stop offset="1" stop-color="{TILE_BOTTOM}"/></linearGradient>
<radialGradient id="{p}tl" cx=".3" cy=".15" r=".8"><stop offset="0" stop-color="#fff" stop-opacity=".6"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
<radialGradient id="{p}l" cx=".3" cy=".22" r=".95"><stop offset="0" stop-color="#9C82FF"/><stop offset=".55" stop-color="#6040E0"/><stop offset="1" stop-color="#341597"/></radialGradient>
<linearGradient id="{p}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5534CF"/><stop offset="1" stop-color="#2C1185"/></linearGradient>
<linearGradient id="{p}card" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#A08BFF"/><stop offset="1" stop-color="#5B3BD6"/></linearGradient>
<linearGradient id="{p}bill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#B8EBC6"/><stop offset="1" stop-color="#4FA86E"/></linearGradient>
<linearGradient id="{p}chip" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFF1C2"/><stop offset="1" stop-color="#D9A030"/></linearGradient>
<radialGradient id="{p}m" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#FFF4CC"/><stop offset=".45" stop-color="#F7C653"/><stop offset="1" stop-color="#A86A08"/></radialGradient>
<filter id="{p}soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="22"/></filter>
<filter id="{p}blur" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="9"/></filter>
<clipPath id="{p}c"><path d="{BODY}"/></clipPath>
<mask id="{p}cut" maskUnits="userSpaceOnUse" x="0" y="0" width="1000" height="1000"><rect width="1000" height="1000" fill="#fff" stroke="none"/><path d="{STRAP}" fill="none" stroke="#000" stroke-width="26"/><circle cx="800" cy="635" r="22" fill="#000" stroke="none"/></mask>'''


def tile(p, radius):
    rx = f'{1000 * radius:g}'
    return (f'<rect width="1000" height="1000" rx="{rx}" fill="url(#{p}t)" stroke="none"/>'
            f'<rect width="1000" height="1000" rx="{rx}" fill="url(#{p}tl)" stroke="none"/>')


def wallet(p):
    """The wallet in full colour and light."""
    return f'''<g stroke="none"><ellipse cx="520" cy="872" rx="330" ry="40" fill="#5A3FC8" opacity=".45" filter="url(#{p}soft)"/>
<g transform="rotate(-7 430 420)"><rect x="250" y="300" width="380" height="220" rx="22" fill="url(#{p}bill)"/>
<rect x="276" y="324" width="328" height="172" rx="12" fill="none" stroke="#2F7A4A" stroke-opacity=".45" stroke-width="7"/>
<circle cx="440" cy="400" r="34" fill="none" stroke="#2F7A4A" stroke-opacity=".45" stroke-width="7"/></g>
<g transform="rotate(9 600 400)"><rect x="410" y="272" width="380" height="250" rx="30" fill="url(#{p}card)"/>
<rect x="452" y="318" width="74" height="56" rx="12" fill="url(#{p}chip)"/>
<path d="M 430 292 L 770 292" stroke="#fff" stroke-opacity=".45" stroke-width="8" stroke-linecap="round"/></g>
<path d="{BODY}" fill="#000" opacity=".25" transform="translate(0 -10)" filter="url(#{p}blur)"/>
<path d="{BODY}" fill="url(#{p}l)"/>
<g clip-path="url(#{p}c)"><path d="{SHADE}" fill="#000" opacity=".16" filter="url(#{p}blur)"/>
<path d="M 200 444 L 800 444" stroke="#fff" stroke-opacity=".35" stroke-width="10" stroke-linecap="round"/></g>
<path d="{STITCH}" fill="none" stroke="#E3D9FF" stroke-opacity=".8" stroke-width="7" stroke-dasharray="20 14" stroke-linecap="round"/>
<ellipse cx="320" cy="540" rx="96" ry="40" fill="#fff" opacity=".38" transform="rotate(-18 320 540)" filter="url(#{p}blur)"/>
<path d="{STRAP}" fill="#000" opacity=".35" transform="translate(-6 12)" filter="url(#{p}blur)"/>
<path d="{STRAP}" fill="url(#{p}s)"/>
<path d="{STRAP_STITCH}" fill="none" stroke="#E3D9FF" stroke-opacity=".8" stroke-width="6" stroke-dasharray="16 12" stroke-linecap="round"/>
<path d="M 575 574 L 818 574" stroke="#fff" stroke-opacity=".25" stroke-width="8" stroke-linecap="round"/>
<circle cx="800" cy="641" r="40" fill="#000" opacity=".35" filter="url(#{p}blur)"/>
<circle cx="800" cy="635" r="38" fill="url(#{p}m)"/>
<circle cx="800" cy="635" r="20" fill="none" stroke="#A86A08" stroke-opacity=".5" stroke-width="6"/>
<circle cx="787" cy="620" r="8" fill="#fff" opacity=".9"/></g>'''


def flat(p, fg):
    """The wallet in one colour: note and card lighter, the strap cut free."""
    return (f'<g stroke="none" mask="url(#{p}cut)">'
            f'<rect x="250" y="300" width="380" height="220" rx="22" fill="{fg}" opacity=".35" transform="rotate(-7 430 420)"/>'
            f'<rect x="410" y="272" width="380" height="250" rx="30" fill="{fg}" opacity=".6" transform="rotate(9 600 400)"/>'
            f'<path d="{BODY}" fill="{fg}"/><path d="{STRAP}" fill="{fg}"/></g>')


def svg(size, p='w', bg=True, scale=WALLET, radius=0.24, mono=None):
    art = flat(p, mono) if mono else wallet(p)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="{size}" height="{size}">'
            f'<defs>{defs(p)}</defs>{tile(p, radius) if bg else ""}<g transform="{place(scale)}">{art}</g></svg>')


def dart_path(d):
    """An SVG path made of M, L, C and Z as Flutter path calls."""
    toks = d.split()
    calls, i = [], 0
    while i < len(toks):
        op = toks[i]
        n = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}[op]
        args = ', '.join(toks[i + 1:i + 1 + n])
        calls.append({'M': 'moveTo', 'L': 'lineTo', 'C': 'cubicTo', 'Z': 'close'}[op] + f'({args})')
        i += 1 + n
    return 'Path()\n' + '\n'.join(f'  ..{c}' for c in calls)


def colour(hex6, alpha=1.0):
    return f'Color(0x{round(alpha * 255):02X}{hex6.lstrip("#").upper()})'


def dart():
    return f'''// Written by tools/brand/brand.py. Do not edit by hand.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Paints the logo, the wallet on the lilac tile, in a square of [size].
/// [radius] is the tile's corner radius as a share of the side.
void paintPurseeTile(Canvas c, double size, {{double radius = 0.24}}) {{
  c.save();
  c.scale(size / 1000);
  final tile = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1000, 1000), Radius.circular(1000 * radius));
  c.drawRRect(tile, Paint()..shader = Gradient.linear(Offset.zero, const Offset(1000, 1000), const [{colour(TILE_TOP)}, {colour(TILE_BOTTOM)}]));
  c.drawRRect(tile, Paint()..shader = Gradient.radial(const Offset(300, 150), 800, const [{colour('FFFFFF', .6)}, {colour('FFFFFF', 0)}]));
  c.translate({500 - CENTRE[0] * WALLET:g}, {500 - CENTRE[1] * WALLET:g});
  c.scale({WALLET});
  paintPurseeWallet(c);
  c.restore();
}}

/// Paints the wallet in its own 1000 x 1000 space.
void paintPurseeWallet(Canvas c) {{
  c.drawOval(Rect.fromCenter(center: const Offset(520, 872), width: 660, height: 80), _blur({colour('5A3FC8', .45)}, 22));

  // The bank note.
  c.save();
  _rotate(c, -7, const Offset(430, 420));
  const bill = Rect.fromLTWH(250, 300, 380, 220);
  c.drawRRect(RRect.fromRectAndRadius(bill, const Radius.circular(22)),
      Paint()..shader = Gradient.linear(bill.topCenter, bill.bottomCenter, const [{colour('B8EBC6')}, {colour('4FA86E')}]));
  final ink = _line({colour('2F7A4A', .45)}, 7, cap: StrokeCap.butt);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(276, 324, 328, 172), const Radius.circular(12)), ink);
  c.drawCircle(const Offset(440, 400), 34, ink);
  c.restore();

  // The card.
  c.save();
  _rotate(c, 9, const Offset(600, 400));
  const card = Rect.fromLTWH(410, 272, 380, 250);
  c.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(30)),
      Paint()..shader = Gradient.linear(card.topLeft, card.bottomRight, const [{colour('A08BFF')}, {colour('5B3BD6')}]));
  const chip = Rect.fromLTWH(452, 318, 74, 56);
  c.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(12)),
      Paint()..shader = Gradient.linear(chip.topLeft, chip.bottomRight, const [{colour('FFF1C2')}, {colour('D9A030')}]));
  c.drawLine(const Offset(430, 292), const Offset(770, 292), _line({colour('FFFFFF', .45)}, 8));
  c.restore();

  // The wallet itself.
  final body = _body();
  c.drawPath(body.shift(const Offset(0, -10)), _blur({colour('000000', .25)}));
  c.drawPath(body, Paint()..shader = _radial(body.getBounds(), .3, .22, .95,
      const [{colour('9C82FF')}, {colour('6040E0')}, {colour('341597')}], const [0, .55, 1]));
  c.save();
  c.clipPath(body);
  c.drawPath({dart_path(SHADE)}, _blur({colour('000000', .16)}));
  c.drawLine(const Offset(200, 444), const Offset(800, 444), _line({colour('FFFFFF', .35)}, 10));
  c.restore();
  c.drawPath(_dashed({dart_path(STITCH)}, 20, 14), _line({colour('E3D9FF', .8)}, 7));
  c.save();
  _rotate(c, -18, const Offset(320, 540));
  c.drawOval(Rect.fromCenter(center: const Offset(320, 540), width: 192, height: 80), _blur({colour('FFFFFF', .38)}));
  c.restore();

  // The strap and its snap.
  final strap = {dart_path(STRAP)};
  c.drawPath(strap.shift(const Offset(-6, 12)), _blur({colour('000000', .35)}));
  final sb = strap.getBounds();
  c.drawPath(strap, Paint()..shader = Gradient.linear(sb.topCenter, sb.bottomCenter, const [{colour('5534CF')}, {colour('2C1185')}]));
  c.drawPath(_dashed({dart_path(STRAP_STITCH)}, 16, 12), _line({colour('E3D9FF', .8)}, 6));
  c.drawLine(const Offset(575, 574), const Offset(818, 574), _line({colour('FFFFFF', .25)}, 8));
  c.drawCircle(const Offset(800, 641), 40, _blur({colour('000000', .35)}));
  c.drawCircle(const Offset(800, 635), 38, Paint()..shader = _radial(Rect.fromCircle(center: const Offset(800, 635), radius: 38), .35, .3, .8,
      const [{colour('FFF4CC')}, {colour('F7C653')}, {colour('A86A08')}], const [0, .45, 1]));
  c.drawCircle(const Offset(800, 635), 20, _line({colour('A86A08', .5)}, 6, cap: StrokeCap.butt));
  c.drawCircle(const Offset(787, 620), 8, Paint()..color = {colour('FFFFFF', .9)});
}}

Path _body() => {dart_path(BODY)};

Paint _blur(Color colour, [double sigma = 9]) => Paint()
  ..color = colour
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

Paint _line(Color colour, double width, {{StrokeCap cap = StrokeCap.round}}) => Paint()
  ..color = colour
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = cap;

void _rotate(Canvas c, double degrees, Offset around) {{
  c.translate(around.dx, around.dy);
  c.rotate(degrees * math.pi / 180);
  c.translate(-around.dx, -around.dy);
}}

/// A radial gradient stretched over [box] the way SVG draws one in the
/// shape's own box: centre at ([cx], [cy]) and radius [r], as shares of it.
Shader _radial(Rect box, double cx, double cy, double r, List<Color> colours, List<double> stops) =>
    Gradient.radial(Offset.zero, 1, colours, stops, TileMode.clamp, Float64List.fromList([
      box.width * r, 0, 0, 0, //
      0, box.height * r, 0, 0, //
      0, 0, 1, 0, //
      box.left + box.width * cx, box.top + box.height * cy, 0, 1, //
    ]));

Path _dashed(Path path, double on, double off) {{
  final out = Path();
  for (final m in path.computeMetrics()) {{
    for (var d = 0.0; d < m.length; d += on + off) {{
      out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
    }}
  }}
  return out;
}}
'''


def site(path, p='pw'):
    """Puts the logo and the flat wallet into a page that has the site's hidden
    sprite (web/home.html, or the share picture's page)."""
    html = open(path).read()
    html = re.sub(r'<mask id="purseCut".*?</mask>\n?', '', html, flags=re.S)
    html = re.sub(r'<!-- brand -->.*?<!-- /brand -->\n?', '', html, flags=re.S)
    sprite = '<svg width="0" height="0" aria-hidden="true" style="position:absolute"><defs>\n'
    assert sprite in html, f'no sprite in {path}'
    html = html.replace(sprite, sprite + f'<!-- brand -->{defs(p)}<!-- /brand -->\n', 1)
    logo = (f'<symbol id="logo" viewBox="0 0 1000 1000">{tile(p, .24)}'
            f'<g transform="{place(WALLET)}">{wallet(p)}</g></symbol>')
    bare = f'<symbol id="i-p" viewBox="0 0 1000 1000"><g transform="{place(.95)}">{flat(p, "currentColor")}</g></symbol>'
    html = re.sub(r'<symbol id="logo".*?</symbol>', lambda m: logo, html, count=1, flags=re.S)
    html = re.sub(r'<symbol id="i-p".*?</symbol>', lambda m: bare, html, count=1, flags=re.S)
    open(path, 'w').write(html)


def main():
    os.makedirs(os.path.join(ROOT, 'web/assets/brand'), exist_ok=True)
    with open(os.path.join(ROOT, 'web/assets/brand/monee-icon.svg'), 'w') as f:
        f.write(svg(1000).replace(' width="1000" height="1000"', '', 1))
    with open(os.path.join(ROOT, 'web/assets/brand/monee-mark.svg'), 'w') as f:
        f.write(svg(1000, bg=False, scale=1.0).replace(' width="1000" height="1000"', '', 1))
    with open(os.path.join(ROOT, 'app/lib/ui/brand_mark.dart'), 'w') as f:
        f.write(dart())
    site(os.path.join(ROOT, 'web/home.html'))

    out = {}

    def want(path, size, **kw):
        out[os.path.join(ROOT, path)] = (size, kw)

    full = dict(radius=0)          # iPhone and store icons: square, the system rounds them
    rounded = dict(radius=0.22)    # icons nobody rounds for us
    alone = dict(bg=False, scale=0.62)   # Android's adaptive layers: inside the safe circle
    want('app/assets/brand/icon.png', 1024, **full)
    want('app/assets/brand/mark.png', 512)
    want('app/assets/brand/icon-foreground.png', 1024, **alone)
    for d, s in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        want(f'app/android/app/src/main/res/mipmap-{d}/ic_launcher.png', s, **rounded)
        want(f'app/android/app/src/main/res/mipmap-{d}/ic_launcher_foreground.png', int(s * 108 / 48), **alone)
        want(f'app/android/app/src/main/res/mipmap-{d}/ic_launcher_monochrome.png', int(s * 108 / 48), **alone, mono='#fff')
    for name, s in {'20x20@1x': 20, '20x20@2x': 40, '20x20@3x': 60, '29x29@1x': 29, '29x29@2x': 58, '29x29@3x': 87,
                    '40x40@1x': 40, '40x40@2x': 80, '40x40@3x': 120, '60x60@2x': 120, '60x60@3x': 180,
                    '76x76@1x': 76, '76x76@2x': 152, '83.5x83.5@2x': 167, '1024x1024@1x': 1024}.items():
        want(f'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{name}.png', s, **full)
    for suffix, s in {'': 96, '@2x': 192, '@3x': 288}.items():
        want(f'app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', s)
    want('app/web/favicon.png', 32, scale=0.98, **rounded)
    want('app/web/icons/mark.png', 192)
    want('app/web/icons/Icon-192.png', 192, **rounded)
    want('app/web/icons/Icon-512.png', 512, **rounded)
    want('app/web/icons/Icon-maskable-192.png', 192, scale=0.8, **full)
    want('app/web/icons/Icon-maskable-512.png', 512, scale=0.8, **full)
    want('app/web/icons/apple-touch-icon.png', 180, **full)
    want('web/assets/brand/icon-64.png', 64)
    want('web/assets/brand/icon-128.png', 128)
    want('web/assets/brand/touch-180.png', 180, **full)

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page()

        def render(size, **kw):
            page.set_viewport_size({'width': size, 'height': size})
            page.set_content(f'<html><body style="margin:0;background:transparent">{svg(size, **kw)}</body></html>')
            png = page.screenshot(omit_background=True, clip={'x': 0, 'y': 0, 'width': size, 'height': size})
            im = Image.open(io.BytesIO(png))
            square = kw.get('bg', True) and kw.get('radius', 0.24) == 0
            return im.convert('RGB') if square else im.convert('RGBA')

        for path, (size, kw) in out.items():
            os.makedirs(os.path.dirname(path), exist_ok=True)
            render(size, **kw).save(path, optimize=True)
            print(os.path.relpath(path, ROOT), size)
        ico = {s: render(s, scale=0.98, radius=0.22) for s in (16, 32, 48)}
        browser.close()

    blobs = []
    for s, im in ico.items():
        b = io.BytesIO()
        im.save(b, format='PNG')
        blobs.append((s, b.getvalue()))
    head = struct.pack('<HHH', 0, 1, len(blobs))
    offset = 6 + 16 * len(blobs)
    entries, data = b'', b''
    for s, blob in blobs:
        entries += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(blob), offset + len(data))
        data += blob
    with open(os.path.join(ROOT, 'web/favicon.ico'), 'wb') as f:
        f.write(head + entries + data)
    print('web/favicon.ico, web/assets/brand/monee-*.svg, web/home.html, app/lib/ui/brand_mark.dart')


if __name__ == '__main__':
    if len(sys.argv) > 1:
        for page in sys.argv[1:]:   # put the logo into other pages with the sprite, like the share picture's
            site(page)
    else:
        main()
