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

MARK = 'M274.8 108.1 L274.2 108.8 L274.4 130.5 L275.2 131.2 L296.8 131.1 L297.4 130.2 L297.2 108.5 L296.6 108.0Z M212.8 2.0 L211.6 3.2 L211.9 24.5 L218.6 25.2 L224.8 28.0 L229.2 32.2 L231.4 36.0 L232.6 40.0 L232.8 130.6 L233.4 131.9 L254.8 131.9 L255.9 130.4 L255.9 43.5 L254.9 35.5 L253.2 29.8 L250.0 22.6 L247.8 19.2 L242.4 13.1 L237.6 9.2 L232.4 6.2 L225.0 3.5 L219.0 2.2Z M149.8 2.0 L148.6 3.2 L148.9 24.5 L155.6 25.2 L161.8 28.0 L166.2 32.2 L168.4 36.0 L169.6 40.0 L169.8 130.6 L170.4 131.9 L191.8 131.9 L192.9 130.4 L192.9 43.5 L191.9 35.5 L190.2 29.8 L187.0 22.6 L184.8 19.2 L179.4 13.1 L174.6 9.2 L169.4 6.2 L162.0 3.5 L156.0 2.2Z M11.6 8.8 L7.8 12.8 L3.9 18.6 L1.4 24.8 L0.0 31.5 L0.0 98.4 L1.1 104.1 L2.8 108.9 L5.4 113.8 L8.4 117.9 L13.5 122.8 L17.9 125.6 L23.2 128.0 L31.5 129.9 L129.2 129.8 L129.9 128.9 L129.9 107.9 L128.9 106.8 L34.1 106.8 L30.5 105.9 L27.1 103.8 L24.6 100.9 L23.0 96.1 L22.9 71.5 L23.6 70.4 L105.8 70.1 L106.5 69.2 L106.6 48.4 L105.8 47.0 L24.1 47.0 L22.9 45.9 L22.9 34.6 L23.6 31.1 L25.6 27.6 L28.9 24.8 L34.1 23.1 L128.9 23.1 L129.9 22.0 L129.8 0.6 L128.9 0.0 L31.5 0.0 L27.5 0.6 L20.1 3.1 L17.0 4.8Z'

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
            + item('house', 'Home', on=True) + item('tray', 'Inbox', '3', red=True) + item('sun', 'E11 Day', '7') + item('check', 'My Tasks', '8') + item('cal', 'Content plans', '1', red=True)
            + head('Clients', True) + client('#0E3E8C', 'Northline Motors') + client('#C8102E', 'Kestrel Foods') + client('#3E7D44', 'Pinecrest')
            + '<div style="margin-top: auto"></div>' + head('Library') + item('folder', 'Client Assets', sub='Logos · Guidelines · Fonts') + item('dollar', 'Finance', sub='Dashboard · Clients · Expenses') + item('trash', 'Trash')
            + f'<div style="margin-top: 10px; border-top: 0.5px solid {t["sideLine"]}; padding: 10px 8px 0; display: flex; flex-direction: column; gap: 6px">'
            + f'<div style="display: flex; align-items: center; gap: 9px"><span style="width: 28px; height: 28px; border-radius: 14px; background: #7D5BD9; color: #fff; font-size: 11px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center">AM</span>'
            + f'<div><div style="font-size: 13px; font-weight: 600">Alex Morgan</div><div style="font-size: 11px; color: {t["dim"]}">Super Admin</div></div></div>'
            + f'<div style="font-size: 11px; color: {t["dim"]}"><span style="color: #30d158">●</span> Synced · E11 Server</div></div></div>')
    def tb(inner, w=None):
        return (f'<span style="height: 30px; {"width: 30px;" if not w else ""} padding: 0 {10 if w else 0}px; border-radius: 15px; background: {t["glass"]}; box-shadow: inset 0 0 0 0.5px {t["glassLine"]}; '
                f'display: inline-flex; align-items: center; justify-content: center; gap: 6px; font-size: 13px">{inner}</span>')
    toolbar = (f'<div style="position: absolute; left: 248px; right: 0; top: 0; height: 52px; display: flex; align-items: center; gap: 10px; padding: 0 16px; z-index: 2">'
               f'<span style="font-size: 15px; font-weight: 700">Home</span>'
               f'<span style="margin-left: auto"></span>'
               + tb(sym('plus', t['fg']) + 'New Task', w=1) + tb(sym('moon', t['fg']))
               + tb(sym('bubble', t['fg']) + 'Talk <span style="min-width: 18px; height: 18px; border-radius: 9px; background: #ff3b30; color: #fff; font-size: 11px; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; padding: 0 5px; box-sizing: border-box">5</span>', w=1)
               + f'<span style="width: 220px; height: 30px; border-radius: 15px; background: {t["field"]}; display: inline-flex; align-items: center; gap: 6px; padding: 0 10px; box-sizing: border-box; font-size: 13px; color: {t["dim"]}">{sym("search", t["dim"])}Search tasks<span style="margin-left: auto; font-size: 11px">⌘K</span></span>'
               + f'<svg viewBox="0 0 297.5 132.0" style="height: 18px; width: auto; margin-left: 6px; flex: none" aria-hidden="true"><path fill="{"#fff" if look == "dark" else "#000"}" fill-rule="evenodd" d="{MARK}"/></svg>'
               + '</div>')
    # the website's Home (an Admin's: layout A, home.js viewLead), restyled for the Mac (inside the web view)
    orange, red, green, purple = '#ff9f0a', ('#ff453a' if look == 'dark' else '#e0352b'), ('#30d158' if look == 'dark' else '#28a745'), '#bf5af2'
    yellow = '#ffd60a' if look == 'dark' else '#b98900'
    def card(inner, extra=''):
        return f'<div style="background: {t["card"]}; border-radius: 12px; padding: 14px 16px; box-sizing: border-box; {extra}">{inner}</div>'
    def h2(title, right=''):
        return f'<div style="display: flex; align-items: center; gap: 10px; margin-bottom: 10px"><span style="font-size: 15px; font-weight: 700">{title}</span>{right}</div>'
    def av(ini, c, sz=24, ml=0):
        return f'<span style="width: {sz}px; height: {sz}px; border-radius: {sz//2}px; background: {c}; color: #fff; font-size: {int(sz*0.4)}px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; margin-left: {ml}px; box-shadow: 0 0 0 2px {t["card"]}">{ini}</span>'
    def pill(text, c):
        return f'<span style="font-size: 11px; font-weight: 600; color: {c}; background: color-mix(in srgb, {c} 16%, transparent); padding: 3px 8px; border-radius: 10px; white-space: nowrap">{text}</span>'
    def stat(color, icon, label, n, note, nc, sel=False):
        return card(f'<div style="display: flex; align-items: center; gap: 12px"><span style="width: 36px; height: 36px; border-radius: 10px; background: color-mix(in srgb, {color} 18%, transparent); display: inline-flex; align-items: center; justify-content: center">{sym(icon, color)}</span>'
                    f'<div><div style="font-size: 12px; color: {t["dim"]}">{label}</div><div style="display: flex; align-items: baseline; gap: 8px"><span style="font-size: 22px; font-weight: 700">{n}</span><span style="font-size: 12px; color: {nc}">{note}</span></div></div></div>', 'flex: 1')
    seg = ''.join(f'<span style="padding: 3px 10px; border-radius: 6px; font-size: 12px; {"background:" + t["win"] + "; box-shadow: 0 0.5px 2px rgba(0,0,0,0.25); font-weight: 600;" if on else ""}">{l} <span style="color: {red if l == "Overdue" else t["dim"]}">{n}</span></span>'
                  for l, n, on in [('Overdue', 2, False), ('Today', 3, False), ('This week', 9, True), ('All open', 24, False)])
    seg = f'<span style="display: inline-flex; padding: 2px; border-radius: 8px; background: {t["field"]}">{seg}</span><span style="margin-left: auto; font-size: 12px; color: {A}">See All</span>'
    def row(i, c, name, sub, cm, fl, avs, st, sc):
        bg = t['row'] if i % 2 else 'transparent'
        return (f'<div style="display: grid; grid-template-columns: 10px 1fr 70px 76px 96px; gap: 12px; align-items: center; height: 44px; padding: 0 10px; border-radius: 7px; background: {bg}">'
                f'<span style="width: 9px; height: 9px; border-radius: 3px; background: {c}"></span>'
                f'<span style="min-width: 0"><div style="font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{name}</div><div style="font-size: 11px; color: {t["dim"]}">{sub}</div></span>'
                f'<span style="font-size: 11px; color: {t["dim"]}">💬 {cm} · 📎 {fl}</span><span style="display: flex">{avs}</span><span>{pill(st, sc)}</span></div>')
    N, K, P = '#0E3E8C', '#C8102E', '#3E7D44'
    rows = (row(0, N, 'Winter Drive Campaign – Key Visual', f'Northline Motors · by Sam Rivera · due <span style="color: {t["fg"]}">Today</span>', 6, 4, av('JL', '#E67E22') + av('MK', '#16A085', ml=-6), 'In Review', yellow)
            + row(1, N, 'Launch socials — 6 posts', f'Northline Motors · due <span style="color: {t["fg"]}">Today</span>', 3, 2, av('RT', '#8E44AD'), 'In Progress', orange)
            + row(2, K, 'December content plan', f'Kestrel Foods · by Dana Cole · due <span style="color: {t["fg"]}">Today</span>', 1, 0, av('MK', '#16A085'), 'To Do', t['dim'])
            + row(3, P, 'Website — homepage copy', f'Pinecrest · due <span style="color: {red}">Thu, Nov 12</span>', 9, 3, av('JL', '#E67E22'), 'In Progress', orange)
            + row(4, K, 'Menu photography retouch', 'Kestrel Foods · due Mon, Nov 16', 2, 12, av('AB', '#2980B9') + av('RT', '#8E44AD', ml=-6), 'In Progress', orange)
            + row(5, N, 'Dealer event invitation', 'Northline Motors · by Sam Rivera · due Wed, Nov 18', 0, 1, av('AB', '#2980B9'), 'To Do', t['dim'])
            + f'<div style="font-size: 12px; color: {t["dim"]}; padding: 8px 10px 0">+3 more · See all</div>')
    bars = ''.join(f'<span style="flex: 1; height: {h}%; border-radius: 2px; background: {A if i < 14 else t["line"]}; opacity: {1 if i < 14 else 1}"></span>'
                   for i, h in enumerate([20, 45, 30, 60, 50, 8, 5, 55, 70, 40, 85, 65, 10, 30] + [4] * 16))
    chart = card(f'<div style="display: flex; gap: 36px; align-items: flex-end">'
                 + ''.join(f'<div><div style="font-size: 12px; color: {t["dim"]}">{l}</div><div style="display: flex; align-items: baseline; gap: 6px"><span style="font-size: 20px; font-weight: 700">{v}</span>{c}</div></div>'
                           for l, v, c in [('Completed', 41, f'<span style="font-size: 11px; color: {green}">+12%</span>'), ('On time', '86%', f'<span style="font-size: 11px; color: {green}">+4%</span>'), ('Overdue', 2, '')])
                 + f'<div style="margin-left: auto; text-align: right"><span style="font-size: 28px; font-weight: 700">41</span> <span style="font-size: 12px; color: {t["dim"]}">tasks completed · November</span></div></div>'
                 + f'<div style="margin: 12px 0 10px; display: inline-flex; padding: 2px; border-radius: 8px; background: {t["field"]}">'
                 + ''.join(f'<span style="padding: 3px 10px; border-radius: 6px; font-size: 12px; {"background:" + t["win"] + "; box-shadow: 0 0.5px 2px rgba(0,0,0,0.25); font-weight: 600;" if i == 0 else ""}">{l}</span>' for i, l in enumerate(['Completed by the team', 'Tasks created', 'Sent for CD review']))
                 + f'</div><div style="display: flex; align-items: flex-end; gap: 4px; height: 90px">{bars}</div>')
    days = ''.join(f'<div style="flex: 1; text-align: center; padding: 6px 0; border-radius: 9px; {"background:" + A + "; color: #fff;" if d == "Mo" else ""}"><div style="font-size: 11px; {"" if d == "Mo" else "color:" + t["dim"]}">{d}</div><div style="font-size: 16px; font-weight: 600">{n}</div></div>'
                   for d, n in [('Mo', 16), ('Tu', 17), ('We', 18), ('Th', 19), ('Fr', 20)])
    def ag(c, name, sub, avs):
        return f'<div style="display: flex; align-items: center; gap: 10px; padding: 7px 0; border-top: 0.5px solid {t["line"]}"><span style="width: 3px; height: 30px; border-radius: 2px; background: {c}"></span><div style="flex: 1; min-width: 0"><div style="font-size: 13px; font-weight: 600">{name}</div><div style="font-size: 11px; color: {t["dim"]}">{sub}</div></div>{avs}</div>'
    sched = card(h2('Schedule', f'<span style="margin-left: auto; font-size: 12px; color: {t["dim"]}">Monday</span>') + f'<div style="display: flex; gap: 4px; margin-bottom: 8px">{days}</div>'
                 + ag(K, 'Menu photography retouch', 'In Progress · Waiting for client', av('AB', '#2980B9', 22)) + ag(N, 'Showroom banner resize', 'To Do', av('JL', '#E67E22', 22)) + ag(P, 'Brand guidelines v2', 'In Review', av('MK', '#16A085', 22)))
    def cl(c, ini, name, o, pc):
        return f'<div style="display: flex; align-items: center; gap: 10px; padding: 6px 0"><span style="width: 30px; height: 30px; border-radius: 8px; background: {c}; color: #fff; font-size: 11px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center">{ini}</span><div style="flex: 1"><div style="font-size: 13px; font-weight: 600">{name}</div><div style="font-size: 11px; color: {t["dim"]}">{o} open · {pc}% done</div><div style="margin-top: 4px; height: 3px; border-radius: 2px; background: {t["line"]}"><div style="width: {pc}%; height: 100%; border-radius: 2px; background: {c}"></div></div></div></div>'
    clients = card(extra='flex: 1', inner=h2('Clients', f'<span style="font-size: 12px; color: {t["dim"]}">3</span>') + cl(N, 'NM', 'Northline Motors', 11, 64) + cl(K, 'KF', 'Kestrel Foods', 8, 52) + cl(P, 'PC', 'Pinecrest', 5, 71))
    content = (f'<div style="position: absolute; left: 248px; right: 0; top: 52px; bottom: 0; background: {t["content"]}; border-top: 0.5px solid {t["line"]}; padding: 20px 24px; box-sizing: border-box; display: flex; flex-direction: column; gap: 14px; overflow: hidden">'
               f'<div><div style="font-size: 12px; color: {t["dim"]}">Saturday, November 14</div><div style="font-size: 26px; font-weight: 700; letter-spacing: -0.3px">Good evening, Alex</div></div>'
               f'<div style="display: flex; gap: 12px">{stat(A, "cal", "Team tasks due today", 3, "2 overdue", red)}{stat(green, "check", "Finished by your team", 14, "↑ 4 vs last week", green)}{stat(orange, "sun", "Waiting for CD review", 2, "oldest 3 hours ago", orange)}</div>'
               f'<div style="display: grid; grid-template-columns: 1fr 330px; gap: 14px; align-items: stretch">'
               f'<div style="display: flex; flex-direction: column; gap: 14px; min-width: 0">{card(h2("Team’s tasks", seg) + rows)}{chart}</div>'
               f'<div style="display: flex; flex-direction: column; gap: 14px">{sched}{clients}</div></div></div>')
    # a right-click menu: Apple's own, the website's choices
    menu = (f'<div style="position: absolute; left: 560px; top: 372px; width: 220px; padding: 5px 0; border-radius: 10px; background: {"rgba(40,40,44,0.96)" if look == "dark" else "rgba(250,250,252,0.97)"}; '
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
