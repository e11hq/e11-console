#!/usr/bin/env python3
# "Team on time" → Team goals achieved: four ways, less loud than the purple-blue panel (Haris 2026-11-15 13:49)
import os
P = os.path.join(os.path.dirname(__file__), 'project')
T = {'dark': dict(bg='#1c1c1e', card='#2a2a2d', fg='rgba(255,255,255,0.88)', dim='rgba(235,235,245,0.55)', line='rgba(255,255,255,0.07)', blue='#0a84ff', green='#30d158', field='rgba(118,118,128,0.24)'),
     'light': dict(bg='#ffffff', card='#f5f5f7', fg='rgba(0,0,0,0.85)', dim='rgba(60,60,67,0.62)', line='rgba(0,0,0,0.07)', blue='#007aff', green='#28a745', field='rgba(118,118,128,0.12)')}
AV = [('YH', '#ff8fc7'), ('MJ', '#8e6e53'), ('AR', '#7a3b2e'), ('LR', '#b0a49a'), ('AS', '#6b7a5a')]
def avs(t, ring):
    return '<div style="display: flex">' + ''.join(f'<span style="width: 30px; height: 30px; border-radius: 15px; margin-left: {0 if i == 0 else -8}px; background: {c}; color: #fff; font-size: 11px; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; box-shadow: 0 0 0 2px {ring}">{n}</span>' for i, (n, c) in enumerate(AV)) + f'<span style="width: 30px; height: 30px; border-radius: 15px; margin-left: -8px; background: {t["field"]}; color: {t["dim"]}; font-size: 11px; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; box-shadow: 0 0 0 2px {ring}">+3</span></div>'
TROPHY = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 3h10v2h3v3a4 4 0 0 1-4 4h-.3A5 5 0 0 1 13 14.9V17h3v2H8v-2h3v-2.1A5 5 0 0 1 8.3 12H8a4 4 0 0 1-4-4V5h3V3zm0 4H6v1a2 2 0 0 0 1 1.7V7zm10 0v2.7A2 2 0 0 0 18 8V7h-1z"/></svg>'
def card(t, look, v):
    pct, delta = '93%', '+16% vs October'
    sub = f'<div style="font-size: 12px; color: {t["dim"]}; line-height: 1.35">Team tasks finished by their due date this month</div>'
    if v == 'A':   # the card's own colour, the number in green, a thin progress bar
        return (f'<div style="background: {t["card"]}; border-radius: 12px; padding: 16px; display: flex; flex-direction: column; gap: 10px">'
                f'<div style="display: flex; align-items: center; gap: 8px; font-size: 15px; font-weight: 600"><span style="color: {t["green"]}">{TROPHY}</span>Team goals achieved</div>'
                f'<div style="display: flex; align-items: baseline; gap: 10px"><span style="font-size: 40px; font-weight: 600; color: {t["green"]}">{pct}</span><span style="font-size: 12px; color: {t["green"]}">↑ {delta}</span></div>'
                f'<div style="height: 6px; border-radius: 3px; background: {t["field"]}"><div style="width: 93%; height: 100%; border-radius: 3px; background: {t["green"]}"></div></div>'
                + avs(t, t['card']) + sub + '</div>')
    if v == 'B':   # a soft tint of E11 purple behind, the number in purple
        tint = 'rgba(124,108,255,0.14)' if look == 'dark' else 'rgba(124,108,255,0.10)'
        pur = '#a99cff' if look == 'dark' else '#5a46d6'
        return (f'<div style="background: linear-gradient(160deg, {tint}, {t["card"]} 75%); background-color: {t["card"]}; box-shadow: inset 0 0 0 0.5px rgba(124,108,255,0.30); border-radius: 12px; padding: 16px; display: flex; flex-direction: column; gap: 10px">'
                f'<div style="font-size: 15px; font-weight: 600">Team goals achieved</div>'
                f'<div style="display: flex; align-items: baseline; gap: 10px"><span style="font-size: 40px; font-weight: 600; color: {pur}">{pct}</span><span style="font-size: 12px; color: {t["dim"]}">{delta}</span></div>'
                + avs(t, t['card']) + sub + '</div>')
    if v == 'C':   # Apple's activity ring
        r, c = 30, 2 * 3.14159 * 30
        return (f'<div style="background: {t["card"]}; border-radius: 12px; padding: 16px; display: flex; flex-direction: column; gap: 12px">'
                f'<div style="font-size: 15px; font-weight: 600">Team goals achieved</div>'
                f'<div style="display: flex; align-items: center; gap: 14px"><svg width="76" height="76" viewBox="0 0 76 76" aria-hidden="true"><circle cx="38" cy="38" r="{r}" fill="none" stroke="{t["field"]}" stroke-width="9"/>'
                f'<circle cx="38" cy="38" r="{r}" fill="none" stroke="{t["green"]}" stroke-width="9" stroke-linecap="round" stroke-dasharray="{c * 0.93:.1f} {c:.1f}" transform="rotate(-90 38 38)"/>'
                f'<text x="38" y="43" text-anchor="middle" font-size="15" font-weight="600" fill="{t["fg"]}">93%</text></svg>'
                f'<div><div style="font-size: 13px; font-weight: 600">On time this month</div><div style="font-size: 12px; color: {t["green"]}">↑ {delta}</div></div></div>'
                + avs(t, t['card']) + sub + '</div>')
    # D: a quiet card with one bright line of colour at its top, the number large in the text colour
    return (f'<div style="background: {t["card"]}; border-radius: 12px; padding: 16px; display: flex; flex-direction: column; gap: 10px; position: relative; overflow: hidden">'
            f'<div style="position: absolute; left: 0; right: 0; top: 0; height: 3px; background: linear-gradient(90deg, #5b4ee0, #2f7bff)"></div>'
            f'<div style="font-size: 15px; font-weight: 600">Team goals achieved</div>'
            f'<div style="display: flex; align-items: baseline; gap: 10px"><span style="font-size: 40px; font-weight: 600">{pct}</span><span style="font-size: 12px; font-weight: 600; color: {t["green"]}; background: color-mix(in srgb, {t["green"]} 16%, transparent); padding: 2px 7px; border-radius: 8px">↑ 16%</span></div>'
            + avs(t, t['card']) + sub + '</div>')
def board():
    rows = ''
    for look in ['dark', 'light']:
        t = T[look]
        cells = ''.join(f'<div style="display: flex; flex-direction: column; gap: 8px"><div style="font-size: 13px; font-weight: 600; color: {t["dim"]}">{v} · {lab}</div>{card(t, look, v)}</div>'
                        for v, lab in [('A', 'Green, a progress bar'), ('B', 'A soft purple tint'), ('C', "Apple's activity ring"), ('D', 'Quiet card, a line of colour')])
        rows += f'<div style="background: {t["bg"]}; color: {t["fg"]}; padding: 28px; display: grid; grid-template-columns: repeat(4, 330px); gap: 24px">{cells}</div>'
    body = f'<div style="width: 1440px; font-family: -apple-system, \'SF Pro Text\', system-ui, sans-serif; line-height: 1.3">{rows}</div>'
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Team goals achieved — four ways</title><script src="./support.js"></script></head>
<body><x-dc><helmet><style>body{{margin:0}}</style></helmet>
{body}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":760}}}}'>
class Component extends DCLogic {{ renderVals() {{ return {{}}; }} }}
</script></body></html>
'''
open(os.path.join(P, 'TeamGoal.dc.html'), 'w').write(board())
print('ok')
