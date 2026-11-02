"""Monee's logo: a rounded lowercase m with a coin for its dot, in white on a
violet tile. Drawn here once as strokes in a 1000 x 1000 box, then written out
as every icon the app, the stores and the site use, so a change here reaches
all of them at once.

    pip install pillow playwright
    python3 tools/brand/brand.py

Writes:
- web/assets/brand/monee-icon.svg   the logo as it is shown: white on a violet tile
- web/assets/brand/monee-mark.svg   the m and the coin alone, in violet (for print)
- app/lib/ui/brand_mark.dart        the same strokes as Flutter paths
- the app, Android, iPhone, web app and site icons (PNG and favicon.ico)
"""
import io
import os
import struct

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

MAIN = '#6D4AE8'     # the tile
DEEP = '#5634C7'     # the tile's lower corner
WHITE = '#FFFFFF'

# The m: three stems joined by two arches, drawn as one stroke with round
# ends. The coin sits above the right stem, like the dot of an i.
STROKE = 112
M_PATH = ('M 245 760 L 245 488 '
          'C 245 392 305 338 372 338 C 442 338 500 392 500 488 L 500 760 '
          'M 500 488 C 500 392 560 338 628 338 C 696 338 755 392 755 488 L 755 760')
COIN = (755, 196, 64)   # x, y, radius
SHIFT = 22              # the whole mark sits a little lower than centre, for balance


def mark(fg, scale=1.0):
    t = 500 - 500 * scale
    return (f'<g transform="translate({t} {t + SHIFT * scale}) scale({scale})">'
            f'<path d="{M_PATH}" fill="none" stroke="{fg}" stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<circle cx="{COIN[0]}" cy="{COIN[1]}" r="{COIN[2]}" fill="{fg}"/></g>')


def svg(size, bg=None, fg=WHITE, scale=0.78, radius=0.0):
    tile = ''
    if bg:
        rx = 1000 * radius
        tile = ('<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
                f'<stop offset="0" stop-color="{MAIN}"/><stop offset="1" stop-color="{DEEP}"/></linearGradient></defs>'
                f'<rect width="1000" height="1000" rx="{rx}" fill="url(#g)"/>') if bg == 'tile' else \
               f'<rect width="1000" height="1000" rx="{rx}" fill="{bg}"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="{size}" height="{size}">'
            f'{tile}{mark(fg, scale)}</svg>')


TILE = dict(bg='tile', fg=WHITE, scale=0.62)
ROUND = 0.24


def dart():
    return '''// Written by tools/brand/brand.py. Do not edit by hand.
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

const double moneeStroke = %d;
const Offset moneeCoin = Offset(%d, %d);
const double moneeCoinRadius = %d;
const double moneeShift = %d;
const int moneeMainColour = 0xFF6D4AE8;
const int moneeDeepColour = 0xFF5634C7;
''' % (STROKE, COIN[0], COIN[1], COIN[2], SHIFT)


def main():
    os.makedirs(os.path.join(ROOT, 'web/assets/brand'), exist_ok=True)
    with open(os.path.join(ROOT, 'web/assets/brand/monee-icon.svg'), 'w') as f:
        f.write(svg(1000, **TILE, radius=ROUND).replace(' width="1000" height="1000"', ''))
    with open(os.path.join(ROOT, 'web/assets/brand/monee-mark.svg'), 'w') as f:
        f.write(svg(1000, fg=MAIN, scale=1.0).replace(' width="1000" height="1000"', ''))
    with open(os.path.join(ROOT, 'app/lib/ui/brand_mark.dart'), 'w') as f:
        f.write(dart())

    out = {}

    def want(path, size, **kw):
        out[os.path.join(ROOT, path)] = (size, kw)

    want('app/assets/brand/icon.png', 1024, **TILE)
    want('app/assets/brand/mark.png', 512, **TILE, radius=ROUND)
    want('app/assets/brand/icon-foreground.png', 1024, fg=WHITE, scale=0.42)
    for d, s in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        want(f'app/android/app/src/main/res/mipmap-{d}/ic_launcher.png', s, **TILE, radius=0.22)
        want(f'app/android/app/src/main/res/mipmap-{d}/ic_launcher_foreground.png', int(s * 108 / 48), fg=WHITE, scale=0.42)
    for name, s in {'20x20@1x': 20, '20x20@2x': 40, '20x20@3x': 60, '29x29@1x': 29, '29x29@2x': 58, '29x29@3x': 87,
                    '40x40@1x': 40, '40x40@2x': 80, '40x40@3x': 120, '60x60@2x': 120, '60x60@3x': 180,
                    '76x76@1x': 76, '76x76@2x': 152, '83.5x83.5@2x': 167, '1024x1024@1x': 1024}.items():
        want(f'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{name}.png', s, **TILE)
    for suffix, s in {'': 96, '@2x': 192, '@3x': 288}.items():
        want(f'app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', s, **TILE, radius=ROUND)
    want('app/web/favicon.png', 32, bg='tile', fg=WHITE, scale=0.8, radius=0.22)
    want('app/web/icons/mark.png', 192, **TILE, radius=ROUND)
    want('app/web/icons/Icon-192.png', 192, **TILE, radius=0.22)
    want('app/web/icons/Icon-512.png', 512, **TILE, radius=0.22)
    want('app/web/icons/Icon-maskable-192.png', 192, bg='tile', fg=WHITE, scale=0.5)
    want('app/web/icons/Icon-maskable-512.png', 512, bg='tile', fg=WHITE, scale=0.5)
    want('app/web/icons/apple-touch-icon.png', 180, **TILE)
    want('web/assets/brand/icon-64.png', 64, **TILE, radius=ROUND)
    want('web/assets/brand/icon-128.png', 128, **TILE, radius=ROUND)
    want('web/assets/brand/touch-180.png', 180, **TILE)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()

        def render(size, **kw):
            page.set_viewport_size({'width': size, 'height': size})
            page.set_content(f'<html><body style="margin:0;background:transparent">{svg(size, **kw)}</body></html>')
            png = page.screenshot(omit_background=True, clip={'x': 0, 'y': 0, 'width': size, 'height': size})
            im = Image.open(io.BytesIO(png))
            return im.convert('RGB') if kw.get('bg') and not kw.get('radius') else im.convert('RGBA')

        for path, (size, kw) in out.items():
            os.makedirs(os.path.dirname(path), exist_ok=True)
            render(size, **kw).save(path, optimize=True)
            print(os.path.relpath(path, ROOT), size)
        ico = {s: render(s, bg='tile', fg=WHITE, scale=0.8, radius=0.22) for s in (16, 32, 48)}
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
    print('web/favicon.ico, web/assets/brand/monee-*.svg, app/lib/ui/brand_mark.dart')


if __name__ == '__main__':
    main()
