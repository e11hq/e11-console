#!/usr/bin/env python3
"""The UAE dirham sign (U+20C3) as a one-character font — E11 Dirham — from the Central Bank of the UAE's symbol
(its official shape, traced as SVG; path below). Used only for that character (the website: unicode-range; the iPhone
app: for that character in any text), until iPhone's / Mac's own fonts have it. Sized as the bank asks: as tall as the
digits (SF / Inter digits ≈ 0.705 em), on their baseline, with the gap before the number built in (0.27 em — a word space).
Run: python3 tools/make-dirham-font.py  → web/fonts/e11-dirham.ttf, .woff"""
import re, sys, pathlib
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path

root = pathlib.Path(__file__).resolve().parent.parent
D = (root / 'tools' / 'dirham-cbuae.svg').read_text()
d = re.search(r' d="([^"]+)"', D).group(1)
VB_H, VB_W = 870.0, 1000.0
UPM, H, LSB, GAP = 1000, 705.0, 30, 270
k = H / VB_H
# (the space after it is part of the sign — the same gap in every font, the bank's: no space character is written after it)
W = round(VB_W * k) + LSB + GAP

def glyph(path=True):
    pen = TTGlyphPen(None)
    if path:
        # SVG y runs down: flip, scale to the digits' height, shift right by the side bearing
        tp = TransformPen(Cu2QuPen(pen, 1.0, reverse_direction=True), (k, 0, 0, -k, LSB, H))
        parse_path(d, tp)
    return pen.glyph()

fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder(['.notdef', 'space', 'uni20C3'])
fb.setupCharacterMap({0x20: 'space', 0x20C3: 'uni20C3'})
fb.setupGlyf({'.notdef': glyph(False), 'space': glyph(False), 'uni20C3': glyph()})
fb.setupHorizontalMetrics({'.notdef': (500, 0), 'space': (250, 0), 'uni20C3': (W, LSB)})
fb.setupHorizontalHeader(ascent=900, descent=-250)
fb.setupNameTable({'familyName': 'E11 Dirham', 'styleName': 'Regular', 'psName': 'E11Dirham-Regular',
                   'copyright': 'UAE dirham sign: Central Bank of the UAE'})
fb.setupOS2(sTypoAscender=900, sTypoDescender=-250, usWinAscent=900, usWinDescent=250, sCapHeight=705, sxHeight=520)
fb.setupPost()
out = root / 'web' / 'fonts'
fb.save(str(out / 'e11-dirham.ttf'))
fb.font.flavor = 'woff'; fb.save(str(out / 'e11-dirham.woff'))
print('made', W, 'wide')
