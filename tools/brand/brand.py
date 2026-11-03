"""Pursee's logo: a kiss-lock coin purse with a capital P cut out of it, in white
on a violet tile. Drawn here once in a 1000 x 1000 box, then written out as every
icon the app, the stores and the site use, so a change here reaches all of them
at once.

    pip install pillow playwright
    python3 tools/brand/brand.py

Writes:
- web/assets/brand/monee-icon.svg   the logo as it is shown: white on a violet tile
- web/assets/brand/monee-mark.svg   the purse alone, in violet (for print)
- app/lib/ui/brand_mark.dart        the same shapes as Flutter paths
- the logo and the bare purse inside web/home.html
- the app, Android, iPhone, web app and site icons (PNG and favicon.ico)
"""
import io
import os
import re
import struct

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

MAIN = '#6D4AE8'     # the tile
DEEP = '#5634C7'     # the tile's lower corner
WHITE = '#FFFFFF'

# The purse: a filled body, two clasp posts with a ball on each, and two cuts
# through it: the line under the frame and the P. Strokes have round ends.
BODY = ('M 238 392 C 322 312 678 312 762 392 C 846 466 872 598 864 690 '
        'C 856 802 772 852 648 852 L 352 852 C 228 852 144 802 136 690 C 128 598 154 466 238 392 Z')
POSTS = 'M 482 340 L 474 284 M 518 340 L 526 284'
POST_W = 38
BALLS = ((463, 262), (537, 262))
BALL_R = 48
FRAME = 'M 186 452 C 316 372 684 372 814 452'
FRAME_W = 30
P = 'M 412 488 L 412 762 M 412 488 L 510 488 C 570 488 610 528 610 586 C 610 644 570 684 510 684 L 412 684'
P_W = 88
SHIFT = -38             # the purse sits a little higher than centre, for balance


def cut_mask(uid):
    """The two cuts as an SVG mask, in the purse's own 1000 x 1000 space."""
    return (f'<mask id="{uid}" maskUnits="userSpaceOnUse" x="0" y="0" width="1000" height="1000">'
            '<rect width="1000" height="1000" fill="#fff" stroke="none"/>'
            f'<path d="{FRAME}" fill="none" stroke="#000" stroke-width="{FRAME_W}" stroke-linecap="round"/>'
            f'<path d="{P}" fill="none" stroke="#000" stroke-width="{P_W}" stroke-linecap="round" stroke-linejoin="round"/>'
            '</mask>')


def purse(fg, uid):
    balls = ''.join(f'<circle cx="{x}" cy="{y}" r="{BALL_R}" fill="{fg}" stroke="none"/>' for x, y in BALLS)
    return (f'<g mask="url(#{uid})"><path d="{BODY}" fill="{fg}" stroke="none"/>'
            f'<path d="{POSTS}" fill="none" stroke="{fg}" stroke-width="{POST_W}" stroke-linecap="round"/>{balls}</g>')


def place(scale):
    t = 500 - 500 * scale
    return f'translate({round(t, 2):g} {round(t + SHIFT * scale, 2):g}) scale({scale:g})'


def svg(size, bg=None, fg=WHITE, scale=0.78, radius=0.0):
    tile = ''
    if bg:
        rx = 1000 * radius
        tile = ('<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
                f'<stop offset="0" stop-color="{MAIN}"/><stop offset="1" stop-color="{DEEP}"/></linearGradient></defs>'
                f'<rect width="1000" height="1000" rx="{rx}" fill="url(#g)"/>') if bg == 'tile' else \
               f'<rect width="1000" height="1000" rx="{rx}" fill="{bg}"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="{size}" height="{size}">'
            f'{tile}<defs>{cut_mask("cut")}</defs><g transform="{place(scale)}">{purse(fg, "cut")}</g></svg>')


TILE = dict(bg='tile', fg=WHITE, scale=0.74)
ROUND = 0.24


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


def dart():
    balls = ', '.join(f'Offset({x}, {y})' for x, y in BALLS)
    return f'''// Written by tools/brand/brand.py. Do not edit by hand.
import 'dart:ui';

// The purse of the logo in a 1000 x 1000 box.

/// The body, filled.
Path purseeBody() => {dart_path(BODY)};

/// The two clasp posts, as strokes with round ends, with a ball on each.
Path purseePosts() => {dart_path(POSTS)};
const double purseePostStroke = {POST_W};
const List<Offset> purseeBalls = [{balls}];
const double purseeBallRadius = {BALL_R};

/// The line under the frame and the P, cut out of the purse as strokes.
Path purseeFrame() => {dart_path(FRAME)};
const double purseeFrameStroke = {FRAME_W};
Path purseeP() => {dart_path(P)};
const double purseePStroke = {P_W};

const double purseeShift = {SHIFT};
const int purseeMainColour = 0xFF6D4AE8;
const int purseeDeepColour = 0xFF5634C7;
'''


def site():
    """The logo and the bare purse as symbols in web/home.html."""
    path = os.path.join(ROOT, 'web/home.html')
    html = open(path).read()
    logo = ('<symbol id="logo" viewBox="0 0 1000 1000"><rect width="1000" height="1000" rx="240" fill="url(#logoG)" stroke="none"/>'
            f'<g transform="{place(TILE["scale"])}">{purse("#fff", "purseCut")}</g></symbol>')
    bare = (f'<symbol id="i-p" viewBox="0 0 1000 1000"><g transform="translate(0 {SHIFT})">'
            f'{purse("currentColor", "purseCut")}</g></symbol>')
    html = re.sub(r'<symbol id="logo".*?</symbol>', lambda m: logo, html, count=1, flags=re.S)
    html = re.sub(r'<symbol id="i-p".*?</symbol>', lambda m: bare, html, count=1, flags=re.S)
    html = re.sub(r'<mask id="purseCut".*?</mask>\n?', '', html, flags=re.S)
    html = html.replace('</linearGradient>\n', '</linearGradient>\n' + cut_mask('purseCut') + '\n', 1)
    open(path, 'w').write(html)


def main():
    os.makedirs(os.path.join(ROOT, 'web/assets/brand'), exist_ok=True)
    with open(os.path.join(ROOT, 'web/assets/brand/monee-icon.svg'), 'w') as f:
        f.write(svg(1000, **TILE, radius=ROUND).replace(' width="1000" height="1000"', '', 1))
    with open(os.path.join(ROOT, 'web/assets/brand/monee-mark.svg'), 'w') as f:
        f.write(svg(1000, fg=MAIN, scale=1.0).replace(' width="1000" height="1000"', '', 1))
    with open(os.path.join(ROOT, 'app/lib/ui/brand_mark.dart'), 'w') as f:
        f.write(dart())
    site()

    out = {}

    def want(path, size, **kw):
        out[os.path.join(ROOT, path)] = (size, kw)

    want('app/assets/brand/icon.png', 1024, **TILE)
    want('app/assets/brand/mark.png', 512, **TILE, radius=ROUND)
    want('app/assets/brand/icon-foreground.png', 1024, fg=WHITE, scale=0.48)
    for d, s in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        want(f'app/android/app/src/main/res/mipmap-{d}/ic_launcher.png', s, **TILE, radius=0.22)
        want(f'app/android/app/src/main/res/mipmap-{d}/ic_launcher_foreground.png', int(s * 108 / 48), fg=WHITE, scale=0.48)
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
    want('app/web/icons/Icon-maskable-192.png', 192, bg='tile', fg=WHITE, scale=0.56)
    want('app/web/icons/Icon-maskable-512.png', 512, bg='tile', fg=WHITE, scale=0.56)
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
    print('web/favicon.ico, web/assets/brand/monee-*.svg, web/home.html, app/lib/ui/brand_mark.dart')


if __name__ == '__main__':
    main()
