#!/usr/bin/env python3
# The sidebar as Claude's (Haris 2026-11-15 13:20) — after gen_hybrid.py and gen_smooth.py: the page beside a pinned sidebar
# (252, edge to edge), or the whole window wide when it's hidden (the window's row over its top-left), or under it shown
# floating; the H2 search popup and the right-click menu left out of these boards.
import os, re
P = os.path.join(os.path.dirname(__file__), 'project')
for f, page_left, bar_left in [('SidePinned', 252, 252), ('SidePinnedDark', 252, 252), ('SideHidden', 0, 190), ('SidePeek', 0, 190)]:
    p = os.path.join(P, f + '.dc.html'); s = open(p).read()
    if 'data-side-done' in s: continue
    s = s.replace('position: absolute; left: 260px; right: 0; top: 0; height: 52px', f'position: absolute; left: {bar_left}px; right: 0; top: 0; height: 52px')
    s = s.replace('position: absolute; left: 260px; right: 0; top: 52px', f'position: absolute; left: {page_left}px; right: 0; top: 52px')
    s = s.replace('<x-dc>', '<x-dc data-side-done>', 1)
    open(p, 'w').write(s)
print('ok')
