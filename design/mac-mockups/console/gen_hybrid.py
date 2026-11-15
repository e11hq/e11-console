#!/usr/bin/env python3
# E11 Console for Mac — the hybrid: Apple's window and toolbar, today's Mac sidebar exactly as it is, around the website's page content restyled
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
      'grid': '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
      'flag': '<path d="M5 21V4h11l-2 4 2 4H5"/>',
      'tick': '<path d="M5 12.5l4.5 4.5L19 7"/>',
      'shield': '<path d="M12 3l8 3v6c0 4.5-3.4 7.8-8 9-4.6-1.2-8-4.5-8-9V6z"/>',
      'users': '<circle cx="9" cy="8" r="3.2"/><path d="M3 19c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5M16 5.2a3 3 0 010 5.6M18 13.8c2 .7 3 2.6 3 5.2"/>',
      'moon': '<path d="M20 14A8 8 0 0110 4a8 8 0 1010 10z"/>',
    }[name]
    return f'<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="{color}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{p}</svg>'

MARK = 'M274.8 108.1 L274.2 108.8 L274.4 130.5 L275.2 131.2 L296.8 131.1 L297.4 130.2 L297.2 108.5 L296.6 108.0Z M212.8 2.0 L211.6 3.2 L211.9 24.5 L218.6 25.2 L224.8 28.0 L229.2 32.2 L231.4 36.0 L232.6 40.0 L232.8 130.6 L233.4 131.9 L254.8 131.9 L255.9 130.4 L255.9 43.5 L254.9 35.5 L253.2 29.8 L250.0 22.6 L247.8 19.2 L242.4 13.1 L237.6 9.2 L232.4 6.2 L225.0 3.5 L219.0 2.2Z M149.8 2.0 L148.6 3.2 L148.9 24.5 L155.6 25.2 L161.8 28.0 L166.2 32.2 L168.4 36.0 L169.6 40.0 L169.8 130.6 L170.4 131.9 L191.8 131.9 L192.9 130.4 L192.9 43.5 L191.9 35.5 L190.2 29.8 L187.0 22.6 L184.8 19.2 L179.4 13.1 L174.6 9.2 L169.4 6.2 L162.0 3.5 L156.0 2.2Z M11.6 8.8 L7.8 12.8 L3.9 18.6 L1.4 24.8 L0.0 31.5 L0.0 98.4 L1.1 104.1 L2.8 108.9 L5.4 113.8 L8.4 117.9 L13.5 122.8 L17.9 125.6 L23.2 128.0 L31.5 129.9 L129.2 129.8 L129.9 128.9 L129.9 107.9 L128.9 106.8 L34.1 106.8 L30.5 105.9 L27.1 103.8 L24.6 100.9 L23.0 96.1 L22.9 71.5 L23.6 70.4 L105.8 70.1 L106.5 69.2 L106.6 48.4 L105.8 47.0 L24.1 47.0 L22.9 45.9 L22.9 34.6 L23.6 31.1 L25.6 27.6 L28.9 24.8 L34.1 23.1 L128.9 23.1 L129.9 22.0 L129.8 0.6 L128.9 0.0 L31.5 0.0 L27.5 0.6 L20.1 3.1 L17.0 4.8Z'

H = 1250

WHO = {'lead': ('#7D5BD9', 'AM', 'Alex Morgan', 'Super Admin'), 'member': ('#E67E22', 'JL', 'Jamie Lowe', 'Production'), 'office': ('#2C7A7B', 'NH', 'Nadine Hale', 'Office Admin')}

def board(look, page='lead'):
    t = T[look]; A = t['accent']
    # TODAY'S Mac sidebar, exactly as it is (mac/swift/Sidebar.swift — Haris 2026-11-15: "sidebar will remain exactly as now"):
    # a floating glass panel 244 wide, 8 in; top row 44 (the window's buttons left; theme · New task · collapse as round
    # glass buttons right); rows 30 tall, the page's icons as SF Symbols in E11 purple, 13.5 names, counts 12.5 grey or a red
    # badge; headings 11 semibold; the clients scroll between; Library at the bottom; the footer: you, Synced, © E11 Agency.
    PUR = '#7c6cff'
    ter = 'rgba(235,235,245,0.30)' if look == 'dark' else 'rgba(60,60,67,0.30)'
    sec = 'rgba(235,235,245,0.60)' if look == 'dark' else 'rgba(60,60,67,0.60)'
    selbg = 'rgba(255,255,255,0.11)' if look == 'dark' else 'rgba(0,0,0,0.075)'
    btnbg = 'rgba(255,255,255,0.07)' if look == 'dark' else 'rgba(255,255,255,0.75)'
    btnedge = 'rgba(255,255,255,0.12)' if look == 'dark' else 'rgba(0,0,0,0.08)'
    def ic(name):
        return sym(name, PUR).replace('width="15" height="15"', 'width="14" height="14"')
    def item(icon, name, count='', on=False, red=False):
        bg = f'background: {selbg};' if on else ''
        c = (f'<span style="margin-left: auto; min-width: 22px; height: 18px; border-radius: 9px; background: #e5484d; color: #fff; font-size: 11px; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; padding: 0 6px; box-sizing: border-box; margin-right: -3px">{count}</span>' if red
             else f'<span style="margin-left: auto; font-size: 12.5px; color: {ter}">{count}</span>') if count else ''
        lead = icon if icon.startswith('<') else ic(icon)
        return (f'<div style="display: flex; align-items: center; height: 30px; padding: 0 9px 0 0; border-radius: 9px; {bg}">'
                f'<span style="width: 36px; display: inline-flex; justify-content: center">{lead}</span>'
                f'<span style="font-size: 13.5px; {"font-weight: 600;" if on else ""} white-space: nowrap">{name}</span>{c}</div>')
    def head(s, plus=False, first=False):
        p = f'<span style="margin-left: auto; margin-right: 4px; display: inline-flex">{sym("plus", sec).replace("width=\"15\" height=\"15\"", "width=\"11\" height=\"11\"").replace("stroke-width=\"1.9\"", "stroke-width=\"2.6\"")}</span>' if plus else ''
        return f'<div style="display: flex; align-items: flex-end; height: {22 if first else 30}px; padding: 0 0 4px 9px; box-sizing: border-box; font-size: 11px; font-weight: 600; color: {sec}">{s}{p}</div>'
    def dot(c):
        return f'<span style="width: 10px; height: 10px; border-radius: 5px; background: {c}"></span>'
    def rb(name):
        return f'<span style="width: 30px; height: 30px; border-radius: 15px; background: {btnbg}; box-shadow: inset 0 0 0 0.5px {btnedge}; display: inline-flex; align-items: center; justify-content: center">{sym(name, sec).replace("width=\"15\" height=\"15\"", "width=\"14\" height=\"14\"")}</span>'
    side = (f'<div style="position: absolute; left: 8px; top: 8px; bottom: 8px; width: 244px; border-radius: 18px; background: {t["side"]}; backdrop-filter: blur(30px); '
            f'box-shadow: inset 0 0 0 0.5px {t["sideLine"]}, 0 8px 28px rgba(0,0,0,0.18); box-sizing: border-box; display: flex; flex-direction: column; z-index: 3">'
            '<div style="height: 44px; display: flex; align-items: center; gap: 8px; padding: 0 10px 0 16px; flex: none"><span style="width: 12px; height: 12px; border-radius: 6px; background: #ff5f57"></span><span style="width: 12px; height: 12px; border-radius: 6px; background: #febc2e"></span><span style="width: 12px; height: 12px; border-radius: 6px; background: #28c840"></span>'
            f'<span style="margin-left: auto; display: flex; gap: 6px">{rb("moon")}{rb("plus") if page != "office" else ""}{rb("sidebar")}</span></div>'
            '<div style="padding: 8px 10px 0; display: flex; flex-direction: column; flex: 1; min-height: 0">'
            + ((item('house', 'Home', on=True) + item('tray', 'Inbox', '3', red=True) + item('sun', 'E11 Day' if page == 'lead' else 'My Day', '7' if page == 'lead' else '4') + item('check', 'My Tasks', '8' if page == 'lead' else '5') + item('cal', 'Content plans', '1', red=True)
            + head('Clients', True) + item(dot('#0E3E8C'), 'Northline Motors', '11') + item(dot('#C8102E'), 'Kestrel Foods', '8') + item(dot('#3E7D44'), 'Pinecrest', '5')
            + '<div style="margin-top: auto"></div>' + head('Library') + item('grid', 'Client Assets', '13') + (item('dollar', 'Finance') if page == 'lead' else '') + item('trash', 'Trash', '3')) if page != 'office' else
              (item('house', 'Home', on=True) + item('tray', 'Inbox', '3', red=True)
               + head('Finance') + item('house', 'Dashboard') + item('folder', 'Clients') + item('users', 'Reimbursements', '4') + item('dollar', 'Expenses')
               + '<div style="margin-top: auto"></div>' + head('Library') + item('grid', 'Client Assets', '13') + item('trash', 'Trash', '3')))
            + '<div style="height: 6px; flex: none"></div></div>'
            + f'<div style="height: 92px; flex: none; position: relative; padding: 0 10px">'
            + f'<div style="position: absolute; left: 19px; right: 19px; top: 0; height: 0.5px; background: {t["sideLine"]}"></div>'
            + f'<div style="margin-top: 8px; height: 42px; display: flex; align-items: center; padding: 0 8px; gap: 10px"><span style="width: 30px; height: 30px; border-radius: 15px; background: {WHO[page][0]}; color: #fff; font-size: 12.5px; font-weight: 600; display: inline-flex; align-items: center; justify-content: center">{WHO[page][1]}</span>'
            + f'<div style="flex: 1"><div style="font-size: 13px; font-weight: 600">{WHO[page][2]}</div><div style="font-size: 11.5px; color: {sec}">{WHO[page][3]}</div></div><span style="color: {ter}; font-size: 10px">⌄</span></div>'
            + f'<div style="margin-top: 2px; height: 18px; display: flex; align-items: center; gap: 7px; padding-left: 1px"><span style="width: 7px; height: 7px; border-radius: 4px; background: #30d158"></span><span style="font-size: 11.5px; color: {sec}">Synced · E11 Server</span></div>'
            + f'<div style="padding-left: 10px; font-size: 11px; color: {ter}">© 2026 E11 Agency</div></div></div>')
    def tb(inner, w=None):
        return (f'<span style="height: 30px; {"width: 30px;" if not w else ""} padding: 0 {10 if w else 0}px; border-radius: 15px; background: {t["glass"]}; box-shadow: inset 0 0 0 0.5px {t["glassLine"]}; '
                f'display: inline-flex; align-items: center; justify-content: center; gap: 6px; font-size: 13px">{inner}</span>')
    searching = look == 'light' and page == 'lead'
    toolbar = (f'<div style="position: absolute; left: 260px; right: 0; top: 0; height: 52px; display: flex; align-items: center; gap: 10px; padding: 0 16px; z-index: 2">'
               f'<span style="font-size: 15px; font-weight: 700">Home</span>'
               f'<span style="margin-left: auto"></span>'
                              + tb(sym('bubble', t['fg']) + 'Talk <span style="min-width: 18px; height: 18px; border-radius: 9px; background: #ff3b30; color: #fff; font-size: 11px; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; padding: 0 5px; box-sizing: border-box">5</span>', w=1)
               + ('' if page == 'office' else f'<span style="width: 220px; height: 30px; border-radius: 15px; background: {t["field"]}; {"box-shadow: 0 0 0 3px color-mix(in srgb, " + A + " 45%, transparent);" if searching else ""} display: inline-flex; align-items: center; gap: 6px; padding: 0 10px; box-sizing: border-box; font-size: 13px; color: {t["dim"]}">{sym("search", t["dim"])}{"<span style=" + chr(34) + "color:" + t["fg"] + chr(34) + ">maya</span>" if searching else "Search tasks"}<span style="margin-left: auto; font-size: 11px">⌘K</span></span>')
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
    def row(i, c, name, sub, cm, fl, avs, st, sc, cd=None, tag=None, late=False):
        # as the iPhone's task rows (Haris 10:41): the CD chip after the client line, the Urgent / P1 tag, an overdue row's faint red
        bg = (f'rgba(229,72,77,{0.10 if look == "dark" else 0.06})' if late else (t['row'] if i % 2 else 'transparent'))
        yel = '#ffd60a' if look == 'dark' else '#b98900'
        cdc = (f'<span style="margin-left: 7px; vertical-align: middle; display: inline-flex; align-items: center; gap: 3px; height: 16px; padding: 0 6px; border-radius: 4px; font-size: 10.5px; font-weight: 700; color: {yel}; background: color-mix(in srgb, {yel} 16%, transparent)">{"✓ " if cd[1] else ""}{cd[0]}</span>') if cd else ''
        tg = ''
        if tag:
            u = tag == 'Urgent'
            tc = ('#ff9494' if look == 'dark' else '#d9363e') if u else t['dim']
            tb = 'rgba(229,72,77,0.16)' if u else t['field']
            tg = f'<span style="margin-left: 8px; font-size: 11px; line-height: 16px; font-weight: 700; padding: 0 7px; border-radius: 5px; color: {tc}; background: {tb}">{tag}</span>'
        return (f'<div style="display: grid; grid-template-columns: 10px 1fr 70px 76px 96px; gap: 12px; align-items: center; height: 56px; padding: 0 10px; border-radius: 8px; background: {bg}">'
                f'<span style="width: 9px; height: 9px; border-radius: 3px; background: {c}"></span>'
                f'<span style="min-width: 0; display: flex; flex-direction: column; gap: 4px"><div style="font-size: 13px; line-height: 18px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: flex; align-items: center">{name}{tg}</div><div style="font-size: 11.5px; line-height: 16px; color: {t["dim"]}; white-space: nowrap">{sub}{cdc}</div></span>'
                f'<span style="font-size: 11px; color: {t["dim"]}">💬 {cm} · 📎 {fl}</span><span style="display: flex">{avs}</span><span>{pill(st, sc)}</span></div>')
    N, K, P = '#0E3E8C', '#C8102E', '#3E7D44'
    rows = (row(0, N, 'Winter Drive Campaign – Key Visual', f'Northline Motors · by Sam Rivera · due <span style="color: {t["fg"]}">Today</span>', 6, 4, av('JL', '#E67E22') + av('MK', '#16A085', ml=-6), 'In Review', yellow, cd=('CD', False), tag='Urgent')
            + row(1, N, 'Launch socials — 6 posts', f'Northline Motors · due <span style="color: {t["fg"]}">Today</span>', 3, 2, av('RT', '#8E44AD'), 'In Progress', orange)
            + row(2, K, 'December content plan', f'Kestrel Foods · by Dana Cole · due <span style="color: {t["fg"]}">Today</span>', 1, 0, av('MK', '#16A085'), 'To Do', t['dim'])
            + row(3, P, 'Website — homepage copy', f'Pinecrest · due <span style="color: {red}">Thu, Nov 12</span>', 9, 3, av('JL', '#E67E22'), 'In Progress', orange, tag='P1', late=True)
            + row(4, K, 'Menu photography retouch', 'Kestrel Foods · due Mon, Nov 16', 2, 12, av('AB', '#2980B9') + av('RT', '#8E44AD', ml=-6), 'In Progress', orange, cd=('CD', True))
            + row(5, N, 'Dealer event invitation', 'Northline Motors · by Sam Rivera · due Wed, Nov 18', 0, 1, av('AB', '#2980B9'), 'To Do', t['dim'])
            + f'<div style="font-size: 12px; color: {t["dim"]}; padding: 8px 10px 0">+3 more · See all</div>')
    vals = [1, 3, 2, 4, 3, 0, 0, 4, 5, 3, 6, 4, 1, 2, 0]
    NDAYS = 30
    bars = ''.join(f'<span style="flex: 1; height: {max(3, v / 6 * 100) if i < len(vals) else 3}%; border-radius: 2px; background: {A if i < len(vals) else t["line"]}; opacity: {0.55 if i < len(vals) else 1}"></span>' for i, v in enumerate(vals + [0] * (NDAYS - len(vals))))
    # the website's line: a 5-day running average over the bars, and the busiest day's flag
    avg = [sum(vals[max(0, i - 2):i + 3]) / len(vals[max(0, i - 2):i + 3]) for i in range(len(vals))]
    X = lambda i: (i + 0.5) / NDAYS * 100
    Y = lambda v: 100 - v / 6 * 88
    path = f'M{X(0):.2f},{Y(avg[0]):.2f}' + ''.join(f' C{(X(i-1)+X(i))/2:.2f},{Y(avg[i-1]):.2f} {(X(i-1)+X(i))/2:.2f},{Y(avg[i]):.2f} {X(i):.2f},{Y(avg[i]):.2f}' for i in range(1, len(avg)))
    pk = vals.index(max(vals))
    peak = (f'<div style="position: absolute; left: {X(pk)}%; top: -26px; transform: translateX(-50%); display: flex; flex-direction: row; align-items: center; gap: 4px; white-space: nowrap; font-size: 10px; color: {t["dim"]}">'
            f'<span style="width: 20px; height: 20px; border-radius: 10px; background: {t["win"]}; box-shadow: 0 0 0 0.5px {t["line"]}, 0 2px 6px rgba(0,0,0,0.2); display: inline-flex; align-items: center; justify-content: center">{sym("flag", A).replace(chr(34)+"15"+chr(34), chr(34)+"11"+chr(34))}</span><em style="font-style: normal">Busiest day</em></div>')
    ticks = ''.join(f'<span>Nov {d}</span>' for d in [1, 8, 15, 22, 30])
    chart = card(extra='display: flex; flex-direction: column', inner=f'<div style="display: flex; gap: 36px; align-items: flex-end">'
                 + ''.join(f'<div><div style="font-size: 12px; color: {t["dim"]}">{l}</div><div style="display: flex; align-items: baseline; gap: 6px"><span style="font-size: 20px; font-weight: 700">{v}</span>{c}</div></div>'
                           for l, v, c in [('Completed', 41, f'<span style="font-size: 11px; color: {green}">+12%</span>'), ('On time', '86%', f'<span style="font-size: 11px; color: {green}">+4%</span>'), ('Overdue', 2, '')])
                 + f'<div style="margin-left: auto; text-align: right"><span style="font-size: 28px; font-weight: 700">41</span> <span style="font-size: 12px; color: {t["dim"]}">tasks completed · November</span></div></div>'
                 + f'<div style="margin: 12px 0 34px; align-self: flex-start; display: inline-flex; padding: 2px; border-radius: 8px; background: {t["field"]}">'
                 + ''.join(f'<span style="padding: 3px 10px; border-radius: 6px; font-size: 12px; {"background:" + t["win"] + "; box-shadow: 0 0.5px 2px rgba(0,0,0,0.25); font-weight: 600;" if i == 0 else ""}">{l}</span>' for i, l in enumerate(['Completed by the team', 'Tasks created', 'Sent for CD review']))
                 + f'</div><div style="position: relative; height: 150px"><div style="position: absolute; inset: 0; display: flex; align-items: flex-end; gap: 4px">{bars}</div>'
                 + f'<svg viewBox="0 0 100 100" preserveAspectRatio="none" style="position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible" aria-hidden="true"><path d="{path}" fill="none" stroke="{A}" stroke-width="2" vector-effect="non-scaling-stroke"/></svg>{peak}</div>'
                 + f'<div style="display: flex; justify-content: space-between; margin-top: 6px; font-size: 10.5px; color: {t["dim"]}">{ticks}</div>')
    def act(ini, c, who, what, task, when, quote='', file=''):
        q = f'<div style="font-size: 12px; color: {t["dim"]}; margin-top: 2px">“{quote}”</div>' if quote else ''
        f = (f'<div style="margin-top: 5px; display: inline-flex; align-items: center; gap: 7px; padding: 5px 9px; border-radius: 8px; background: {t["field"]}; font-size: 11.5px">'
             f'<span style="font-weight: 600">{file[0]}</span><span style="color: {t["dim"]}">{file[1]}</span></div>') if file else ''
        return (f'<div style="display: flex; gap: 10px; padding: 9px 0; border-top: 0.5px solid {t["line"]}">{av(ini, c, 32)}'
                f'<div style="flex: 1; min-width: 0; font-size: 13px"><b>{who}</b> <span style="color: {t["dim"]}">{what}</span> <span style="color: {A}">{task}</span>{q}{f}</div>'
                f'<span style="font-size: 11.5px; color: {t["dim"]}; white-space: nowrap">{when}</span></div>')
    acts = card(extra='flex: 1', inner=h2('Recent activity', f'<span style="margin-left: auto; font-size: 12px; color: {A}">Open Inbox</span>')
                + act('JL', '#E67E22', 'Jamie Lowe', 'commented on', 'Winter Drive Campaign – Key Visual', '12m ago', quote='Second round of the visual is up — the darker sky version.')
                + act('MK', '#16A085', 'Maya Kent', 'attached a file to', 'December content plan', '1h ago', file=('Dec-plan-v2.pdf', '2.4 MB'))
                + act('RT', '#8E44AD', 'Rui Tan', 'moved', 'Launch socials — 6 posts', '3h ago')
                + act('AB', '#2980B9', 'Ana Brooks', 'mentioned you on', 'Menu photography retouch', 'Yesterday', quote='@Alex can we push the client call to Monday?'))
    days = ''.join(f'<div style="flex: 1; text-align: center; padding: 6px 0; border-radius: 9px; {"background:" + A + "; color: #fff;" if d == "Mo" else ""}"><div style="font-size: 11px; {"" if d == "Mo" else "color:" + t["dim"]}">{d}</div><div style="font-size: 16px; font-weight: 600">{n}</div></div>'
                   for d, n in [('Mo', 16), ('Tu', 17), ('We', 18), ('Th', 19), ('Fr', 20)])
    def ag(c, name, sub, avs):
        return f'<div style="display: flex; align-items: center; gap: 10px; padding: 7px 0; border-top: 0.5px solid {t["line"]}"><span style="width: 3px; height: 30px; border-radius: 2px; background: {c}"></span><div style="flex: 1; min-width: 0"><div style="font-size: 13px; font-weight: 600">{name}</div><div style="font-size: 11px; color: {t["dim"]}">{sub}</div></div>{avs}</div>'
    sched = card(h2('Schedule', f'<span style="margin-left: auto; font-size: 12px; color: {t["dim"]}">Monday</span>') + f'<div style="display: flex; gap: 4px; margin-bottom: 8px">{days}</div>'
                 + ag(K, 'Menu photography retouch', 'In Progress · Waiting for client', av('AB', '#2980B9', 22)) + ag(N, 'Showroom banner resize', 'To Do', av('JL', '#E67E22', 22)) + ag(P, 'Brand guidelines v2', 'In Review', av('MK', '#16A085', 22)))
    def cl(c, ini, name, o, pc):
        return f'<div style="display: flex; align-items: center; gap: 10px; padding: 6px 0"><span style="width: 30px; height: 30px; border-radius: 8px; background: {c}; color: #fff; font-size: 11px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center">{ini}</span><div style="flex: 1"><div style="font-size: 13px; font-weight: 600">{name}</div><div style="font-size: 11px; color: {t["dim"]}">{o} open · {pc}% done</div><div style="margin-top: 4px; height: 3px; border-radius: 2px; background: {t["line"]}"><div style="width: {pc}%; height: 100%; border-radius: 2px; background: {c}"></div></div></div></div>'
    clients = card(h2('Clients', f'<span style="font-size: 12px; color: {t["dim"]}">3</span>') + cl(N, 'NM', 'Northline Motors', 11, 64) + cl(K, 'KF', 'Kestrel Foods', 8, 52) + cl(P, 'PC', 'Pinecrest', 5, 71))
    def ck(text, task, on=False):
        box = (f'<span style="width: 16px; height: 16px; border-radius: 4px; flex: none; display: inline-flex; align-items: center; justify-content: center; '
               + (f'background: {A}">' + sym('tick', '#fff').replace('width="15" height="15"', 'width="11" height="11"') if on else f'box-shadow: inset 0 0 0 1px {t["ter"]}">') + '</span>')
        return (f'<div style="display: flex; gap: 10px; align-items: flex-start; padding: 6px 0">{box}<div style="min-width: 0"><div style="font-size: 13px; {"text-decoration: line-through; color:" + t["dim"] + ";" if on else ""}">{text}</div>'
                f'<div style="font-size: 11px; color: {t["dim"]}">{task}</div></div></div>')
    checklist = card(h2('Checklist', f'<span style="margin-left: auto; font-size: 12px; color: {t["dim"]}">1 of 4 done</span>')
                     + ck('Export the 1080 × 1350 cuts', 'Launch socials — 6 posts') + ck('Send the call sheet to the crew', 'Menu photography retouch')
                     + ck('Check the CTA on mobile', 'Website — homepage copy') + ck('Approve the sky colour', 'Winter Drive Campaign – Key Visual', on=True))
    hero = (f'<div style="flex: 1; border-radius: 12px; padding: 16px; box-sizing: border-box; color: #fff; background: linear-gradient(140deg, #5b4ee0, #2f7bff)">'
            f'<div style="font-size: 15px; font-weight: 700">Team on time</div>'
            f'<div style="display: flex; align-items: center; gap: 12px; margin: 8px 0 10px"><span style="font-size: 40px; font-weight: 700; letter-spacing: -1px">86%</span><span style="font-size: 12px; opacity: 0.85; line-height: 1.3">+4% vs<br>October</span></div>'
            f'<div style="display: flex; margin-bottom: 10px">' + ''.join(av(i, c, 30, ml=(0 if k == 0 else -8)) .replace(f'box-shadow: 0 0 0 2px {t["card"]}', 'box-shadow: 0 0 0 2px #4766e9') for k, (i, c) in enumerate([('JL', '#E67E22'), ('MK', '#16A085'), ('RT', '#8E44AD'), ('AB', '#2980B9'), ('SR', '#C0392B')])) + '</div>'
            f'<div style="font-size: 12px; opacity: 0.9">Team tasks that were finished by their due date this month</div></div>')
    btn = lambda label, primary=False: (f'<span style="height: 28px; padding: 0 12px; white-space: nowrap; border-radius: 7px; font-size: 13px; display: inline-flex; align-items: center; '
                                         + (f'background: {A}; color: #fff; font-weight: 500">' if primary else f'background: {t["glass"]}; box-shadow: inset 0 0 0 0.5px {t["glassLine"]}">') + label + '</span>')
    content = (f'<div style="position: absolute; left: 260px; right: 0; top: 52px; bottom: 0; background: {t["content"]}; border-top: 0.5px solid {t["line"]}; padding: 20px 24px 8px; box-sizing: border-box; display: flex; flex-direction: column; gap: 14px; overflow: hidden">'
               f'<div style="display: flex; align-items: flex-end"><div><div style="font-size: 12px; color: {t["dim"]}">Saturday, November 14</div><div style="font-size: 26px; font-weight: 700; letter-spacing: -0.3px">Good evening, Alex</div></div>'
               f'<div style="margin-left: auto; display: flex; gap: 8px">{btn("E11 Day")}{btn("+ New task", True)}</div></div>'
               f'<div style="display: flex; gap: 12px">{stat(A, "cal", "Team tasks due today", 3, "2 overdue", red)}{stat(green, "check", "Finished by your team", 14, "↑ 4 vs last week", green)}{stat(orange, "shield", "Waiting for CD review", 2, "oldest 3 hours ago", orange)}</div>'
               f'<div style="display: grid; grid-template-columns: 1fr 330px; gap: 14px; align-items: stretch; flex: 1; min-height: 0">'
               f'<div style="display: flex; flex-direction: column; gap: 14px; min-width: 0">{card(h2("Team’s tasks", seg) + rows)}{chart}{acts}</div>'
               f'<div style="display: flex; flex-direction: column; gap: 14px">{sched}{clients}{checklist}{hero}</div></div></div>')
    if page == 'member':
        def chipx(text, c=None, solid=False):
            c = c or t['dim']
            return f'<span style="font-size: 11px; font-weight: 600; padding: 3px 9px; border-radius: 10px; color: {"#fff" if solid else c}; background: {c if solid else "color-mix(in srgb, " + c + " 15%, transparent)"}">{text}</span>'
        cbox = lambda on: (f'<span style="width: 16px; height: 16px; border-radius: 4px; flex: none; display: inline-flex; align-items: center; justify-content: center; '
                           + (f'background: {A}">' + sym('tick', '#fff').replace('width="15" height="15"', 'width="11" height="11"') if on else f'box-shadow: inset 0 0 0 1px {t["ter"]}">') + '</span>')
        nitems = [('Hero visual — sky version', True), ('Logo lock-up on dark', True), ('Export 1080 × 1350 and 1080 × 1920', False), ('Send to the CD', False)]
        upnext = card(extra='display: grid; grid-template-columns: 1fr 260px; gap: 22px', inner=
            f'<div style="display: flex; flex-direction: column; gap: 10px; min-width: 0"><div style="display: flex; gap: 6px; flex-wrap: wrap">{chipx("Up next", A, True)}{chipx("Urgent", red)}{chipx("Due Today", orange)}{chipx("Second round", purple)}{chipx("In Progress")}</div>'
            f'<div style="font-size: 22px; font-weight: 700; letter-spacing: -0.2px">Winter Drive Campaign – Key Visual</div>'
            f'<div style="font-size: 12.5px; color: {t["dim"]}">Northline Motors · Created by Sam Rivera · 4 files · 6 comments · needs CD review</div>'
            f'<div style="display: flex; gap: 8px; margin-top: 4px">{btn("Submit files for review", True)}{btn("Open task")}<span style="height: 28px; padding: 0 6px; font-size: 13px; display: inline-flex; align-items: center; gap: 6px; color: {A}">Next task → <small style="color: {t["dim"]}">1 of 5</small></span></div></div>'
            f'<div style="display: flex; flex-direction: column; gap: 7px; font-size: 12.5px"><div style="display: flex; color: {t["dim"]}"><span>Checklist</span><span style="margin-left: auto">2/4</span></div>'
            f'<div style="height: 4px; border-radius: 2px; background: {t["line"]}"><div style="width: 50%; height: 100%; border-radius: 2px; background: {A}"></div></div>'
            + ''.join(f'<div style="display: flex; gap: 8px; align-items: center">{cbox(on)}<span style="{"text-decoration: line-through; color:" + t["dim"] if on else ""}">{x}</span></div>' for x, on in nitems) + '</div>')
        lanes = [('Second round', purple, 2, ['Winter Drive Campaign – Key Visual', 'Dealer event invitation'], True), ('Waiting for client', orange, 2, ['Menu photography retouch', 'Brand guidelines v2'], False), ('Brief to come', '#64d2ff', 1, ['Showroom banner resize'], False)]
        lane = lambda name, c, n, ts, on: (f'<div style="padding: 10px; border-radius: 10px; background: {t["field"] if on else "transparent"}; box-shadow: inset 0 0 0 {"1.5px " + A if on else "0.5px " + t["line"]}; display: flex; flex-direction: column; gap: 6px; min-width: 0">'
            f'<div style="display: flex; align-items: center; gap: 6px; font-size: 12.5px; font-weight: 600"><span style="width: 8px; height: 8px; border-radius: 4px; background: {c}"></span>{name}<b style="margin-left: auto">{n}</b></div>'
            + ''.join(f'<div style="font-size: 12px; padding: 4px 8px; border-left: 3px solid {N}; border-radius: 3px; background: {t["card"]}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{x}</div>' for x in ts) + '</div>')
        lrow = lambda c, name, cl, due, dc=None: f'<div style="display: grid; grid-template-columns: 10px 1fr 150px 90px; gap: 10px; align-items: center; padding: 7px 4px; border-top: 0.5px solid {t["line"]}; font-size: 13px"><span style="width: 8px; height: 8px; border-radius: 3px; background: {c}"></span><span>{name}</span><span style="font-size: 12px; color: {t["dim"]}">{cl}</span><span style="font-size: 12px; color: {dc or t["dim"]}">{due}</span></div>'
        pipeline = card(h2('My pipeline', f'<span style="margin-left: auto; font-size: 12px; color: {t["dim"]}">5 open</span>')
            + f'<div style="font-size: 12px; color: {t["dim"]}; margin: -6px 0 10px">Your open tasks grouped by their Task Update · click one</div>'
            + f'<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; margin-bottom: 8px">' + ''.join(lane(*x) for x in lanes) + '</div>'
            + lrow(N, 'Winter Drive Campaign – Key Visual', 'Northline Motors', 'Today', orange) + lrow(N, 'Dealer event invitation', 'Northline Motors', 'Wed, Nov 18'))
        post = lambda kind, name, c=N, done=False, late=False: f'<div style="font-size: 11.5px; padding: 6px 8px; border-left: 3px solid {c}; border-radius: 4px; background: {t["field"]}; {"opacity: .55;" if done else ""}"><div style="font-size: 10.5px; color: {red if late else t["dim"]}">{kind}</div>{name}</div>'
        wk = [('Mon 16', [post('Due · Second round', 'Winter Drive Campaign – Key Visual')]), ('Tue 17', [post('Starts', 'Showroom banner resize', P)]), ('Wed 18', [post('Due', 'Dealer event invitation'), post('Due · Waiting for client', 'Menu photography retouch', K)]), ('Thu 19', []), ('Fri 20', [post('Done', 'Brand guidelines v2', P, done=True)])]
        week = card(h2('My week', f'<span style="margin-left: auto; font-size: 12px; color: {t["dim"]}">16 Nov – 20 Nov</span>')
            + f'<div style="font-size: 12px; color: {t["dim"]}; margin: -6px 0 10px">Your tasks on their due date (and start date) · grey = already done</div>'
            + '<div style="display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 8px">' + ''.join(f'<div style="display: flex; flex-direction: column; gap: 6px; min-width: 0"><div style="font-size: 11.5px; font-weight: 600; color: {t["dim"]}">{d}</div><div style="min-height: 120px; padding: 6px; border-radius: 9px; box-shadow: inset 0 0 0 0.5px {t["line"]}; display: flex; flex-direction: column; gap: 6px">{"".join(ps)}</div></div>' for d, ps in wk) + '</div>')
        macts = card(extra='flex: 1', inner=h2('Recent activity', f'<span style="margin-left: auto; font-size: 12px; color: {A}">Open Inbox</span>')
            + act('SR', '#C0392B', 'Sam Rivera', 'assigned you', 'Dealer event invitation', '25m ago')
            + act('AM', '#7D5BD9', 'Alex Morgan', 'mentioned you on', 'Winter Drive Campaign – Key Visual', '1h ago', quote='@Jamie the client loves the darker sky — go with it.')
            + act('DC', '#2C3E50', 'Dana Cole', 'approved', 'Brand guidelines v2', 'Yesterday')
            + act('MK', '#16A085', 'Maya Kent', 'commented on', 'Menu photography retouch', 'Yesterday', quote='Shoot moved to Wednesday.'))
        ring = 2 * 3.14159 * 15.9
        rev = card(h2('My CD reviews') + f'<div style="display: flex; gap: 14px; align-items: center"><svg width="74" height="74" viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="15.9" fill="none" stroke="{t["line"]}" stroke-width="3.2"/><circle cx="18" cy="18" r="15.9" fill="none" stroke="{green}" stroke-width="3.2" stroke-linecap="round" stroke-dasharray="{0.67 * ring:.1f} {ring:.1f}" transform="rotate(-90 18 18)"/><text x="18" y="20.6" text-anchor="middle" font-size="8" font-weight="700" fill="{t["fg"]}">67%</text></svg>'
            f'<div style="font-size: 12.5px; line-height: 1.6"><b>Approved first time</b><br>4 approved · 2 amended<br>1 waiting with the CD<br><small style="color: {t["dim"]}">Your submissions in November</small></div></div>')
        amends = card(h2('Amendments to fix', f'<span style="margin-left: auto; min-width: 20px; height: 20px; border-radius: 10px; background: {red}; color: #fff; font-size: 11px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center">1</span>')
            + f'<div style="font-size: 13px; font-weight: 600">Dealer event invitation</div><div style="display: flex; gap: 8px; margin-top: 6px; font-size: 12.5px; color: {t["dim"]}">{av("DC", "#2C3E50", 26)}<span>“Make the date bigger and use the brand red for the RSVP.”</span></div>')
        thumb = lambda ext, name, c: f'<div style="border-radius: 9px; overflow: hidden; background: linear-gradient(140deg, {c}, color-mix(in srgb, {c} 55%, #000)); aspect-ratio: 4 / 3; position: relative"><span style="position: absolute; left: 7px; top: 7px; font-size: 10px; font-weight: 700; color: #fff; background: rgba(0,0,0,0.35); padding: 2px 6px; border-radius: 5px">{ext}</span><span style="position: absolute; left: 7px; right: 7px; bottom: 6px; font-size: 11px; color: #fff; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{name}</span></div>'
        files = card(h2('Latest files', f'<span style="margin-left: auto; font-size: 12px; color: {t["dim"]}">on your tasks</span>') + '<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px">' + thumb('PNG', 'KV-sky-dark.png', '#1d3b6e') + thumb('PDF', 'Dealer-invite-v3.pdf', '#8e2b2b') + thumb('JPG', 'Menu-hero-02.jpg', '#6b4a2b') + thumb('MP4', 'Launch-reel.mp4', '#2b5e4a') + '</div>')
        hrow = lambda ok, name, d: f'<div style="display: flex; align-items: center; gap: 8px; font-size: 12px; padding: 3px 0"><span style="width: 16px; height: 16px; border-radius: 8px; background: {"rgba(255,255,255,0.22)" if ok else "rgba(255,90,90,0.5)"}; display: inline-flex; align-items: center; justify-content: center; font-size: 9px">{"✓" if ok else "!"}</span><span style="flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{name}</span><em style="font-style: normal; opacity: .8">{d}</em></div>'
        streak = (f'<div style="flex: 1; border-radius: 12px; padding: 16px; box-sizing: border-box; color: #fff; background: linear-gradient(140deg, #5b4ee0, #2f7bff)">'
            f'<div style="font-size: 15px; font-weight: 700">On-time streak</div><div style="display: flex; align-items: center; gap: 12px; margin: 6px 0 10px"><span style="font-size: 40px; font-weight: 700">6</span><span style="font-size: 12px; opacity: .85; line-height: 1.3">tasks in a row finished<br>by their due date</span></div>'
            + hrow(True, 'Brand guidelines v2', 'Fri 13') + hrow(True, 'Launch socials — 6 posts', 'Thu 12') + hrow(True, 'Website — homepage copy', 'Wed 11') + hrow(True, 'Showroom banner — round 1', 'Tue 10') + hrow(False, 'Menu shoot call sheet', 'Mon 2') + '</div>')
        content = (f'<div style="position: absolute; left: 260px; right: 0; top: 52px; bottom: 0; background: {t["content"]}; border-top: 0.5px solid {t["line"]}; padding: 20px 24px 8px; box-sizing: border-box; display: flex; flex-direction: column; gap: 14px; overflow: hidden">'
                   f'<div style="display: flex; align-items: flex-end"><div><div style="font-size: 12px; color: {t["dim"]}">Saturday, November 14 · Production</div><div style="font-size: 26px; font-weight: 700; letter-spacing: -0.3px">Good evening, Jamie</div></div>'
                   f'<div style="margin-left: auto; display: flex; gap: 8px">{btn("My Day")}{btn("+ New task", True)}</div></div>'
                   f'<div style="display: grid; grid-template-columns: 1fr 330px; gap: 14px; align-items: stretch; flex: 1; min-height: 0">'
                   f'<div style="display: flex; flex-direction: column; gap: 14px; min-width: 0">{upnext}{pipeline}{week}{macts}</div>'
                   f'<div style="display: flex; flex-direction: column; gap: 14px">{rev}{amends}{files}{streak}</div></div></div>')
    if page == 'office':
        def tile(n, label, sub, tone):
            return card(extra='flex: 1', inner=f'<div style="display: flex; align-items: center; gap: 14px"><span style="font-size: 28px; font-weight: 700; color: {tone}">{n}</span><div><div style="font-size: 13px; font-weight: 600">{label}</div><div style="font-size: 12px; color: {t["dim"]}">{sub}</div></div></div>')
        segx = lambda items, on: f'<span style="margin-left: auto; display: inline-flex; padding: 2px; border-radius: 8px; background: {t["field"]}">' + ''.join(f'<span style="padding: 3px 10px; border-radius: 6px; font-size: 12px; {"background:" + t["win"] + "; box-shadow: 0 0.5px 2px rgba(0,0,0,0.25); font-weight: 600;" if x == on else ""}">{x}</span>' for x in items) + '</span>'
        ext = lambda e, c: f'<span style="width: 38px; height: 30px; border-radius: 7px; background: {c}; color: #fff; font-size: 10px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; flex: none">{e}</span>'
        def frow(e, c, name, where, when, sel=False):
            det = (f'<div style="margin: 2px 0 6px 48px; padding: 10px 12px; border-radius: 9px; background: {t["field"]}; font-size: 12px; display: grid; grid-template-columns: 70px 1fr; gap: 4px 10px">'
                   f'<span style="color: {t["dim"]}">Added by</span><span>Maya Kent</span><span style="color: {t["dim"]}">Added</span><span>14 November 2026</span><span style="color: {t["dim"]}">Size</span><span>1.2 MB</span><span style="color: {t["dim"]}">Folder</span><span>Northline Motors › Logos</span>'
                   f'<span></span><span style="display: flex; gap: 6px; margin-top: 6px">{btn("Open folder")}{btn("Download")}</span></div>') if sel else ''
            return (f'<div style="display: flex; align-items: center; gap: 10px; padding: 7px 8px; border-radius: 8px; {"background:" + t["sel"] + ";" if sel else ""}">{ext(e, c)}'
                    f'<div style="flex: 1; min-width: 0"><div style="font-size: 13px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{name}</div><div style="font-size: 11.5px; color: {t["dim"]}">{where}</div></div><span style="font-size: 11.5px; color: {t["dim"]}">{when}</span></div>' + det)
        chips = ''.join(f'<span style="display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 14px; font-size: 12px; {"background:" + A + "; color: #fff;" if on else "background:" + t["field"] + ";"}"><i style="width: 8px; height: 8px; border-radius: 4px; background: {"#fff" if on else c}"></i>{n}</span>' for n, c, on in [('All clients', '#9aa0ab', True), ('Northline Motors', N, False), ('Kestrel Foods', K, False), ('Pinecrest', P, False)])
        assets = card(extra='display: flex; flex-direction: column; min-height: 0', inner=h2('Latest in Client Assets', f'<span style="margin-left: auto; font-size: 12px; color: {t["dim"]}">128 files</span>')
            + f'<div style="display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 10px">{chips}</div>'
            + frow('SVG', N, 'Northline-logo-white.svg', 'Northline Motors › Logos · Maya', '2h ago', sel=True) + frow('PDF', K, 'Kestrel-brand-guidelines-2026.pdf', 'Kestrel Foods › Guidelines · Ana', '5h ago')
            + frow('OTF', P, 'Pinecrest-Serif-Bold.otf', 'Pinecrest › Fonts · Rui', 'Yesterday') + frow('PNG', N, 'Showroom-banner-1920.png', 'Northline Motors › Banners · Jamie', 'Thu') + frow('JPG', K, 'Menu-hero-02.jpg', 'Kestrel Foods › Photos · Maya', 'Wed'))
        def nrow(ini, c, text, kind, when, unread=True):
            return (f'<div style="display: flex; align-items: center; gap: 10px; padding: 8px 6px; border-top: 0.5px solid {t["line"]}">{av(ini, c, 28)}'
                    f'<div style="flex: 1; min-width: 0"><div style="font-size: 13px; {"font-weight: 600;" if unread else ""}">{text}</div><div style="font-size: 11.5px; color: {t["dim"]}">{kind} · {when}</div></div>'
                    + (f'<span style="width: 8px; height: 8px; border-radius: 4px; background: {A}"></span>' if unread else '') + '</div>')
        inbox = card(extra='display: flex; flex-direction: column; min-height: 0', inner=h2('Inbox', segx(['Unread', 'All'], 'Unread'))
            + nrow('JL', '#E67E22', 'Jamie Lowe submitted his November claim', 'Expense claim', '20m ago')
            + nrow('MK', '#16A085', 'Maya Kent added 3 files to Northline Motors › Logos', 'Client Assets', '2h ago')
            + nrow('RT', '#8E44AD', 'Rui Tan submitted his November claim', 'Expense claim', '4h ago')
            + f'<div style="margin-top: auto; padding-top: 10px; border-top: 0.5px solid {t["line"]}; display: flex; font-size: 12px; color: {t["dim"]}"><span>Open an update to see it</span><span style="margin-left: auto; color: {A}">Mark all read</span></div>')
        sub_c, ok_c, paid_c = orange, green, A
        def crow(ini, c, name, items, amt, state, act=''):
            pc = {'Submitted': sub_c, 'HR approved': ok_c, 'Paid': paid_c}[state]
            a = f'<span style="font-size: 11.5px; padding: 3px 9px; border-radius: 6px; background: {t["glass"]}; box-shadow: inset 0 0 0 0.5px {t["glassLine"]}">{act}</span>' if act else ''
            return (f'<div style="display: flex; align-items: center; gap: 10px; padding: 8px 6px; border-top: 0.5px solid {t["line"]}">{av(ini, c, 28)}'
                    f'<div style="flex: 1; min-width: 0"><div style="font-size: 13px; font-weight: 600">{name}</div><div style="font-size: 11.5px; color: {t["dim"]}; white-space: nowrap">{items} · AED {amt}</div></div>{pill(state, pc)}{a}</div>')
        fin = card(extra='display: flex; flex-direction: column; min-height: 0', inner=h2('Finance · November', segx(['Claims', 'Expenses'], 'Claims'))
            + f'<div style="display: flex; height: 8px; border-radius: 4px; overflow: hidden; margin: 2px 0 8px"><span style="width: 50%; background: {sub_c}"></span><span style="width: 25%; background: {ok_c}"></span><span style="width: 25%; background: {paid_c}"></span></div>'
            + f'<div style="display: flex; gap: 12px; font-size: 12px; color: {t["dim"]}; margin-bottom: 6px"><span><b style="color: {sub_c}">2</b> submitted</span><span><b style="color: {ok_c}">1</b> HR approved</span><span><b style="color: {paid_c}">1</b> paid</span><span style="margin-left: auto; color: {t["fg"]}; font-weight: 600">AED  3,140.00</span></div>'
            + crow('AB', '#2980B9', 'Ana Brooks', '3 items', '420.00', 'Paid') + crow('JL', '#E67E22', 'Jamie Lowe', '5 items', '1,260.00', 'Submitted', 'HR approve')
            + crow('MK', '#16A085', 'Maya Kent', '2 items', '310.00', 'HR approved', 'Mark paid') + crow('RT', '#8E44AD', 'Rui Tan', '4 items', '1,150.00', 'Submitted', 'HR approve')
            + f'<div style="margin-top: auto; padding-top: 10px; border-top: 0.5px solid {t["line"]}; display: flex; gap: 8px">{btn("Open Dashboard")}{btn("All reimbursements")}</div>')
        osearch = f'<span style="width: 360px; height: 32px; border-radius: 9px; background: {t["field"]}; display: inline-flex; align-items: center; gap: 7px; padding: 0 11px; box-sizing: border-box; font-size: 13px; white-space: nowrap; color: {t["dim"]}">{sym("search", t["dim"])}Search Client Assets — e.g. “northline logo svg”</span>'
        content = (f'<div style="position: absolute; left: 260px; right: 0; top: 52px; bottom: 0; background: {t["content"]}; border-top: 0.5px solid {t["line"]}; padding: 20px 24px 8px; box-sizing: border-box; display: flex; flex-direction: column; gap: 14px; overflow: hidden">'
                   f'<div style="display: flex; align-items: flex-end"><div><div style="font-size: 12px; color: {t["dim"]}">Saturday, November 14 · Office Admin</div><div style="font-size: 26px; font-weight: 700; letter-spacing: -0.3px">Good evening, Nadine</div></div>'
                   f'<div style="margin-left: auto">{osearch}</div></div>'
                   f'<div style="display: flex; gap: 12px">{tile(3, "Clients", "in Client Assets", "#8b7cf6")}{tile(3, "Unread", "in your Inbox", red)}{tile(17, "Team members", "Open Team page", A)}{tile(2, "Claims to approve", "November", orange)}</div>'
                   f'<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; flex: 1; min-height: 0">{assets}{inbox}{fin}</div></div>')
    # search (Haris 10:41): people too, and where each was found — as the iPhone's
    def sr(lead, title, sub, found=''):
        f = f'<div style="font-size: 11px; color: {t["dim"]}; margin-top: 1px">{found}</div>' if found else ''
        return f'<div style="display: flex; gap: 10px; align-items: center; padding: 6px 10px; margin: 0 6px; border-radius: 7px">{lead}<div style="min-width: 0; flex: 1"><div style="font-size: 13px">{title}</div><div style="font-size: 11px; color: {t["dim"]}">{sub}</div>{f}</div></div>'
    sh = lambda x: f'<div style="padding: 8px 16px 3px; font-size: 11px; font-weight: 600; color: {t["dim"]}">{x}</div>'
    mark = lambda x: f'<mark style="background: rgba(255,214,10,0.45); color: inherit; border-radius: 2px; padding: 0 1px">{x}</mark>'
    stico = lambda c: f'<span style="width: 22px; height: 22px; display: inline-flex; align-items: center; justify-content: center"><span style="width: 14px; height: 14px; border-radius: 7px; box-shadow: inset 0 0 0 2px {c}"></span></span>'
    search_pop = (f'<div style="position: absolute; right: 74px; top: 46px; width: 360px; padding: 4px 0 8px; border-radius: 12px; background: rgba(250,250,252,0.98); box-shadow: 0 0 0 0.5px {t["glassLine"]}, 0 14px 40px rgba(0,0,0,0.22); z-index: 9">'
                  + sh('People') + sr(av('MK', '#16A085', 26), mark('Maya') + ' Kent', 'Production · 4 open tasks')
                  + sh('Tasks') + sr(stico(orange), 'Menu photography retouch', 'Kestrel Foods · due Mon, Nov 16', f'Found in: assigned to {mark("Maya")} Kent')
                  + sr(stico(t['dim']), 'December content plan', 'Kestrel Foods · due Today', f'Found in a comment: “{mark("Maya")} will send the second draft…”')
                  + sr(stico(yellow), 'Brand guidelines v2', 'Pinecrest · In Review', f'Found in a file: Guidelines-{mark("Maya")}-notes.pdf')
                  + f'<div style="margin: 6px 16px 0; padding-top: 7px; border-top: 0.5px solid {t["line"]}; font-size: 12px; color: {A}">See all results for “maya”</div></div>') if searching else ''
    # a right-click menu: Apple's own, the website's choices
    menu = (f'<div style="position: absolute; left: 560px; top: 372px; width: 220px; padding: 5px 0; border-radius: 10px; background: {"rgba(40,40,44,0.96)" if look == "dark" else "rgba(250,250,252,0.97)"}; '
            f'box-shadow: 0 0 0 0.5px {t["glassLine"]}, 0 12px 36px rgba(0,0,0,0.3); z-index: 9; font-size: 13px">'
            + ''.join(f'<div style="padding: 4px 12px; margin: 0 5px; border-radius: 5px; {"background:" + A + "; color: #fff;" if i == 0 else ""}">{x}</div>' if x != '-' else f'<div style="height: 0.5px; background: {t["line"]}; margin: 4px 10px"></div>'
                      for i, x in enumerate(['Open Task', '-', 'Status  ›', 'Mark Complete', 'Due Date…', '-', 'Attach Files…', 'Copy Link', '-', 'Trash']))
            + '</div>') if look == 'dark' and page == 'lead' else ''
    body = (f'<div style="width: 1440px; height: {H}px; background: {t["desk"]}; position: relative; overflow: hidden; font-family: -apple-system, \'SF Pro Text\', \'Helvetica Neue\', Inter, sans-serif; color: {t["fg"]}">'
            f'<div style="position: absolute; inset: 0; background: {t["win"]}; border-radius: 14px; overflow: hidden">{side}{toolbar}{content}{menu}{search_pop}</div></div>')
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>E11 Console for Mac — Home ({page}, {look})</title><script src="./support.js"></script></head>
<body><x-dc><helmet><style>body{{margin:0}}</style></helmet>
{body}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":{H}}}}}'>
class Component extends DCLogic {{ renderVals() {{ return {{}}; }} }}
</script></body></html>
'''

open(os.path.join(P, 'Hybrid.dc.html'), 'w').write(board('dark'))
open(os.path.join(P, 'HybridLight.dc.html'), 'w').write(board('light'))
open(os.path.join(P, 'Member.dc.html'), 'w').write(board('dark', 'member'))
open(os.path.join(P, 'MemberLight.dc.html'), 'w').write(board('light', 'member'))
H = 900
open(os.path.join(P, 'Office.dc.html'), 'w').write(board('dark', 'office'))
open(os.path.join(P, 'OfficeLight.dc.html'), 'w').write(board('light', 'office'))
print('ok')
