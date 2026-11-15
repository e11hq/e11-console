#!/usr/bin/env python3
# The smoother text — CHOSEN for every Mac page (Haris 2026-11-15 10:49: "i love the smoothest one"): the same Home, only the page's text changed (the sidebar,
# locked, untouched) — Apple's own spacing (no hand-set letter-spacing), semibold not bold, softer text in dark, a little
# more room between lines, the Mac's own font smoothing.
import os, re
P = os.path.join(os.path.dirname(__file__), 'project')
def smooth(src, look, h=1300):
    i = src.index('position: absolute; left: 260px; right: 0; top: 52px')
    i = src.rfind('<div', 0, i)
    head, body = src[:i], src[i:]
    body = body.replace('font-weight: 700', 'font-weight: 600')
    body = re.sub(r'letter-spacing: -?[0-9.]+px;?', '', body)
    fg, dim = (('rgba(255,255,255,0.88)', 'rgba(235,235,245,0.55)') if look == 'dark' else ('rgba(0,0,0,0.85)', 'rgba(60,60,67,0.62)'))
    body = body.replace('#98989d' if look == 'dark' else '#6e6e73', dim)
    body = body.replace('position: absolute; left: 260px; right: 0; top: 52px;',
                        f'position: absolute; left: 260px; right: 0; top: 52px; color: {fg}; line-height: 1.3; -webkit-font-smoothing: auto; font-family: system-ui, -apple-system, \'SF Pro Text\', sans-serif;', 1)
    out = (head + body).replace('height: 1250px; background:', f'height: {h}px; background:', 1).replace('"height":1250', f'"height":{h}')
    return out
# run after gen_hybrid.py: every board gets it
for f, look, h in [('Hybrid', 'dark', 1300), ('HybridLight', 'light', 1300), ('Member', 'dark', 1230), ('MemberLight', 'light', 1230)]:
    pth = os.path.join(P, f + '.dc.html')
    s = open(pth).read()
    if '-webkit-font-smoothing: auto' not in s: open(pth, 'w').write(smooth(s, look, h))
print('ok')
