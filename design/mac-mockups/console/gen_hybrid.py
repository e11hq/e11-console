#!/usr/bin/env python3
# E11 Console for Mac — the hybrid: Apple's window, toolbar and sidebar (native) around the website's page content restyled
# for the Mac. Boards H1 (dark) and H2 (light), both E11 Day.
import os
P = os.path.join(os.path.dirname(__file__), 'project')

T = {
 'dark': dict(win='#1e1e20', side='rgba(46,46,50,0.72)', sideLine='rgba(255,255,255,0.10)', fg='#f5f5f7', dim='#98989d', ter='#636366',
              content='#1c1c1e', row='rgba(255,255,255,0.035)', line='rgba(255,255,255,0.07)', sel='rgba(255,255,255,0.10)', glass='rgba(255,255,255,0.08)',
              glassLine='rgba(255,255,255,0.12)', field='rgba(118,118,128,0.24)', card='#2a2a2d', accent='#0a84ff', desk='linear-gradient(135deg,#2b2350,#0f1a33 55%,#0b2a2a)'),
 'light': dict(win='#ffffff', side='rgba(236,236,240,0.78)', sideLine='rgba(0,0,0,0.08)', fg='#1d1d1f', dim='#6e6e73', ter='#aeaeb2',
               content='#ffffff', row='rgba(0,0,0,0.025)', line='rgba(0,0,0,0.07)', sel='rgba(0,0,0,0.07)', glass='rgba(255,255,255,0.7)',
               glassLine='rgba(0,0,0,0.10)', field='rgba(118,118,128,0.12)', card='#f5f5f7', accent='#007aff', desk='linear-gradient(135deg,#c9d6ff,#e2e2f5 50%,#d6efe9)'),
}

def sym(name, color):
    p = {
      'house': '<path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z"/>',
      'tray': '<path d="M3 13l3-8h12l3 8v6H3z M3 13h5l1 3h6l1-3h5"/>',
      'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2"/>',
      'check': '<circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/>',
      'cal': '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>',
      'folder': '<path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>',
      'dollar': '<circle cx="12" cy="12" r="9"/><path d="M15 9c-1-1-5-1.5-5 1s5 1.5 5 4-4 2-5 1M12 6v12"/>',
      'trash': '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
      'plus': '<path d="M12 5v14M5 12h14"/>',
      'search': '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
      'bubble': '<path d="M4 5h16v11H9l-5 4z"/>',
      'sidebar': '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16"/>',
      'moon': '<path d="M20 14A8 8 0 0110 4a8 8 0 1010 10z"/>',
    }[name]
    return f'<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="{color}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{p}</svg>'

def board(look):
    t = T[look]; A = t['accent']
    def item(icon, name, count='', on=False, red=False, sub=''):
        bg = f'background: {t["sel"]};' if on else ''
        c = (f'<span style="margin-left: auto; font-size: 12px; {"min-width: 18px; height: 18px; border-radius: 9px; background: #ff3b30; color: #fff; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; padding: 0 5px; box-sizing: border-box" if red else "color: " + t["dim"]}">{count}</span>') if count else ''
        s2 = f'<div style="font-size: 11px; color: {t["dim"]}">{sub}</div>' if sub else ''
        return (f'<div style="display: flex; align-items: center; gap: 9px; padding: 5px 10px; border-radius: 7px; font-size: 13px; {bg}">{sym(icon, A)}'
                f'<div style="flex: 1; min-width: 0"><div>{name}</div>{s2}</div>{c}</div>')
    def head(s, plus=False):
        p = f'<span style="margin-left: auto; color: {t["dim"]}">{sym("plus", t["dim"])}</span>' if plus else ''
        return f'<div style="display: flex; align-items: center; padding: 14px 10px 4px; font-size: 11px; font-weight: 600; color: {t["dim"]}">{s}{p}</div>'
    def client(c, n):
        return f'<div style="display: flex; align-items: center; gap: 9px; padding: 5px 10px; font-size: 13px"><span style="width: 15px; height: 15px; border-radius: 4px; background: {c}"></span>{n}</div>'
    side = (f'<div style="position: absolute; left: 8px; top: 8px; bottom: 8px; width: 232px; border-radius: 16px; background: {t["side"]}; backdrop-filter: blur(30px); '
            f'box-shadow: inset 0 0 0 0.5px {t["sideLine"]}, 0 8px 28px rgba(0,0,0,0.18); padding: 12px 8px; box-sizing: border-box; display: flex; flex-direction: column; z-index: 3">'
            '<div style="display: flex; gap: 8px; padding: 4px 8px 14px"><span style="width: 12px; height: 12px; border-radius: 6px; background: #ff5f57"></span><span style="width: 12px; height: 12px; border-radius: 6px; background: #febc2e"></span><span style="width: 12px; height: 12px; border-radius: 6px; background: #28c840"></span>'
            f'<span style="margin-left: auto">{sym("sidebar", t["dim"])}</span></div>'
            + item('house', 'Home') + item('tray', 'Inbox', '3', red=True) + item('sun', 'E11 Day', '7', on=True) + item('check', 'My Tasks', '8') + item('cal', 'Content plans', '1', red=True)
            + head('Clients', True) + client('#0E3E8C', 'Northline Motors') + client('#C8102E', 'Kestrel Foods') + client('#3E7D44', 'Pinecrest')
            + head('Library') + item('folder', 'Client Assets', sub='Logos · Guidelines · Fonts') + item('dollar', 'Finance', sub='Dashboard · Clients · Expenses') + item('trash', 'Trash')
            + f'<div style="margin-top: auto; border-top: 0.5px solid {t["sideLine"]}; padding: 10px 8px 0; display: flex; flex-direction: column; gap: 6px">'
            + f'<div style="display: flex; align-items: center; gap: 9px"><span style="width: 28px; height: 28px; border-radius: 14px; background: #7D5BD9; color: #fff; font-size: 11px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center">AM</span>'
            + f'<div><div style="font-size: 13px; font-weight: 600">Alex Morgan</div><div style="font-size: 11px; color: {t["dim"]}">Super Admin</div></div></div>'
            + f'<div style="font-size: 11px; color: {t["dim"]}"><span style="color: #30d158">●</span> Synced · E11 Server</div></div></div>')
    def tb(inner, w=None):
        return (f'<span style="height: 30px; {"width: 30px;" if not w else ""} padding: 0 {10 if w else 0}px; border-radius: 15px; background: {t["glass"]}; box-shadow: inset 0 0 0 0.5px {t["glassLine"]}; '
                f'display: inline-flex; align-items: center; justify-content: center; gap: 6px; font-size: 13px">{inner}</span>')
    toolbar = (f'<div style="position: absolute; left: 248px; right: 0; top: 0; height: 52px; display: flex; align-items: center; gap: 10px; padding: 0 16px; z-index: 2">'
               f'<span style="font-size: 15px; font-weight: 700">E11 Day</span><span style="font-size: 12px; color: {t["dim"]}">Saturday, 14 November</span>'
               f'<span style="margin-left: auto"></span>'
               + tb(sym('plus', t['fg']) + 'New Task', w=1) + tb(sym('moon', t['fg']))
               + tb(sym('bubble', t['fg']) + 'Talk <span style="min-width: 18px; height: 18px; border-radius: 9px; background: #ff3b30; color: #fff; font-size: 11px; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; padding: 0 5px; box-sizing: border-box">5</span>', w=1)
               + f'<span style="width: 220px; height: 30px; border-radius: 15px; background: {t["field"]}; display: inline-flex; align-items: center; gap: 6px; padding: 0 10px; box-sizing: border-box; font-size: 13px; color: {t["dim"]}">{sym("search", t["dim"])}Search tasks<span style="margin-left: auto; font-size: 11px">⌘K</span></span>'
               + '</div>')
    # the website's E11 Day, restyled for the Mac (inside the web view)
    days = ''.join(
        f'<div style="flex: 1; text-align: center; padding: 7px 0; border-radius: 9px; {"background:" + A + "; color: #fff;" if d == "Sat" else ""}">'
        f'<div style="font-size: 11px; {"" if d == "Sat" else "color:" + t["dim"]}">{d}</div><div style="font-size: 17px; font-weight: 600">{n}</div>'
        f'<div style="height: 6px; font-size: 9px; line-height: 6px">{dots}</div></div>'
        for d, n, dots in [('Mon', 9, '•'), ('Tue', 10, ''), ('Wed', 11, '••'), ('Thu', 12, ''), ('Fri', 13, '•'), ('Sat', 14, '•••'), ('Sun', 15, '•')])
    def grp(label, color, n, open_=True):
        return (f'<div style="display: flex; align-items: center; gap: 8px; padding: 10px 12px 6px; font-size: 13px; font-weight: 600">'
                f'<span style="color: {t["dim"]}; font-size: 11px; width: 10px">{"▾" if open_ else "▸"}</span><span style="color: {color}">{label}</span>'
                f'<span style="color: {t["dim"]}; font-weight: 400">{n}</span></div>')
    def trow(i, name, status, sc, client, due, dc, pr, pc):
        bg = t['row'] if i % 2 else 'transparent'
        return (f'<div style="display: grid; grid-template-columns: 1fr 120px 150px 90px 110px; align-items: center; height: 30px; padding: 0 12px; font-size: 13px; background: {bg}; border-radius: 6px">'
                f'<span style="display: flex; align-items: center; gap: 8px"><span style="width: 14px; height: 14px; border-radius: 7px; border: 1.5px solid {t["ter"]}"></span>{name}</span>'
                f'<span style="color: {sc}">{status}</span><span>{client}</span><span style="color: {dc}">{due}</span><span style="color: {pc}">{pr}</span></div>')
    orange, red, yellow = '#ff9f0a', '#ff453a', '#ffd60a' if look == 'dark' else '#c79500'
    content = (f'<div style="position: absolute; left: 248px; right: 0; top: 52px; bottom: 0; background: {t["content"]}; border-top: 0.5px solid {t["line"]}; padding: 18px 24px; box-sizing: border-box; display: flex; flex-direction: column; gap: 14px">'
               f'<div style="display: flex; align-items: center; gap: 8px"><span style="color: {t["dim"]}">‹</span><div style="flex: 1; display: flex; gap: 6px">{days}</div><span style="color: {t["dim"]}">›</span>'
               f'<span style="margin-left: 8px; padding: 4px 12px; border-radius: 7px; background: {t["field"]}; font-size: 12px">Today</span></div>'
               f'<div style="display: flex; align-items: center; gap: 14px; padding: 12px 14px; border-radius: 12px; background: {t["card"]}">'
               f'<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="16" fill="none" stroke="{t["line"]}" stroke-width="4"/><circle cx="20" cy="20" r="16" fill="none" stroke="#30d158" stroke-width="4" stroke-dasharray="29 100" transform="rotate(-90 20 20)" stroke-linecap="round"/><text x="20" y="24" font-size="10" font-weight="700" text-anchor="middle" fill="{t["fg"]}">29%</text></svg>'
               f'<div style="flex: 1"><div style="font-size: 13px"><b>2</b> of <b>7</b> planned tasks done today</div><div style="margin-top: 6px; height: 4px; border-radius: 2px; background: {t["line"]}"><div style="width: 29%; height: 100%; border-radius: 2px; background: #30d158"></div></div></div>'
               f'<span style="font-size: 12px; color: {red}">2 overdue</span><span style="font-size: 12px; color: {t["dim"]}">3 due</span><span style="font-size: 12px; color: #30d158">2 completed</span></div>'
               f'<div style="height: 30px; border-radius: 8px; background: {t["field"]}; display: flex; align-items: center; gap: 8px; padding: 0 10px; font-size: 13px; color: {t["dim"]}">{sym("plus", t["dim"])}Add a task for today…</div>'
               f'<div><div style="display: grid; grid-template-columns: 1fr 120px 150px 90px 110px; padding: 0 12px 6px; font-size: 11px; font-weight: 600; color: {t["dim"]}; border-bottom: 0.5px solid {t["line"]}"><span>Name</span><span>Status</span><span>Client</span><span>Due</span><span>Priority</span></div>'
               + grp('Overdue', red, 2) + trow(0, 'Website — homepage copy', 'In Progress', orange, 'Pinecrest', 'Thu', red, '⚑ Priority 1', orange) + trow(1, 'Shoot day call sheet', 'To Do', t['dim'], 'Northline Motors', 'Fri', red, 'No priority', t['dim'])
               + grp('Due today', A, 3) + trow(0, 'Winter Drive Campaign – Key Visual', 'In Review', yellow, 'Northline Motors', 'Today', t['fg'], '⚑ Urgent', red)
               + trow(1, 'Launch socials — 6 posts', 'In Progress', orange, 'Northline Motors', 'Today', t['fg'], 'No priority', t['dim']) + trow(0, 'December content plan', 'To Do', t['dim'], 'Kestrel Foods', 'Today', t['fg'], 'No priority', t['dim'])
               + grp('In progress (started, due later)', '#bf5af2', 1, False) + grp('Completed', '#30d158', 2, False) + '</div></div>')
    # a right-click menu: Apple's own, the website's choices
    menu = (f'<div style="position: absolute; left: 640px; top: 520px; width: 220px; padding: 5px 0; border-radius: 10px; background: {"rgba(40,40,44,0.96)" if look == "dark" else "rgba(250,250,252,0.97)"}; '
            f'box-shadow: 0 0 0 0.5px {t["glassLine"]}, 0 12px 36px rgba(0,0,0,0.3); z-index: 9; font-size: 13px">'
            + ''.join(f'<div style="padding: 4px 12px; margin: 0 5px; border-radius: 5px; {"background:" + A + "; color: #fff;" if i == 0 else ""}">{x}</div>' if x != '-' else f'<div style="height: 0.5px; background: {t["line"]}; margin: 4px 10px"></div>'
                      for i, x in enumerate(['Open Task', 'Status  ›', 'Mark Complete', '-', 'Copy Link']))
            + '</div>') if look == 'dark' else ''
    body = (f'<div style="width: 1440px; height: 900px; background: {t["desk"]}; position: relative; overflow: hidden; font-family: -apple-system, \'SF Pro Text\', \'Helvetica Neue\', Inter, sans-serif; color: {t["fg"]}">'
            f'<div style="position: absolute; inset: 0; background: {t["win"]}; border-radius: 14px; overflow: hidden">{side}{toolbar}{content}{menu}</div></div>')
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>E11 Console for Mac — hybrid ({look})</title><script src="./support.js"></script></head>
<body><x-dc><helmet><style>body{{margin:0}}</style></helmet>
{body}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":900}}}}'>
class Component extends DCLogic {{ renderVals() {{ return {{}}; }} }}
</script></body></html>
'''

open(os.path.join(P, 'Hybrid.dc.html'), 'w').write(board('dark'))
open(os.path.join(P, 'HybridLight.dc.html'), 'w').write(board('light'))
print('ok')
