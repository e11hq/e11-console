import UIKit
import WidgetKit

/* The unread widget's summary, written by the app (Shared/WidgetStore.swift; Haris 2026-11-24). Whenever the counts
   change (.talkChanged, a moment after — one write for a burst) and when Talk goes to the background: each group's name,
   picture's stand-in, unread, newest line and time, and its mute; the messages the notification helper kept for the widget
   that the app now has itself let go; the groups' small pictures kept up to date. The widget is asked to redraw only when
   something it shows changed. Main thread. Nothing else in the app reads any of this. */
enum WidgetFeed {
  private static var started = false, soon = false
  private static var lastSummary: WidgetStore.Summary?

  static func start() {
    if !started {
      started = true
      NotificationCenter.default.addObserver(forName: .talkChanged, object: nil, queue: .main) { _ in WidgetFeed.later() }
    }
    write()
  }
  private static func later() {
    guard !soon else { return }
    soon = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { WidgetFeed.soon = false; WidgetFeed.write() }
  }

  static func write() {
    let T = Talk.shared
    guard T.me != nil else { return }
    let now = Date().timeIntervalSince1970 * 1000
    var gs: [WidgetStore.G] = []
    for g in T.groups.values {
      let u = T.unreadShown(g.id)
      var line = ""
      if u != 0, let m = T.last(g.id) { line = lineFor(m) }
      let look = standIn(g)
      gs.append(WidgetStore.G(id: g.id, name: g.name, letters: look.letters, color: look.color, unread: u, line: line,
                              lastAt: T.activity(g), mutedUntil: g.mutedUntil, pic: pics[g.id] != nil))
    }
    gs.sort { $0.lastAt > $1.lastAt }
    // (the messages kept by the notification helper that the app has now: let go — counted in the summary from here on)
    var changed = false
    for n in WidgetStore.news {
      let have = T.groups[n.g] != nil && T.log(n.g).msgs.contains { $0.id == n.id }
      if have || now - n.at > 3 * 86_400_000 { WidgetStore.dropNew(n.id); changed = true }
    }
    let s = WidgetStore.Summary(at: now, contact: T.isContact, groups: gs)
    if s.contact != lastSummary?.contact || s.groups != lastSummary?.groups {
      if let d = try? JSONEncoder().encode(s) { WidgetStore.put(WidgetStore.summaryService, "summary", d) }
      lastSummary = s; changed = true
    }
    if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind) }
    keepPictures(gs.filter { !$0.muted(now) })
  }

  // signed out: nothing of the chats left for the widget
  static func clear() {
    WidgetStore.clearAll(); lastSummary = nil; pics = [:]
    WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
  }

  // the newest message as the group's row shows it (Lists' makeGroupModel)
  private static func lineFor(_ m: Msg) -> String {
    let T = Talk.shared
    if m.kind == "sys" { return Talk.preview(m) }
    if m.by == T.me?.id { return "You: " + Talk.preview(m) }
    let p = T.people[m.by], first = String(T.name(m.by).split(separator: " ").first ?? "")
    let who = p?.contact == true ? "\(first) (\(p?.client.flatMap { T.clients[$0]?.name } ?? "Client"))" : first
    return "\(who): " + Talk.preview(m)
  }
  // the picture's stand-in, as Avatar.set(group:): the group's initials (its own picture), its client's (a logo), else
  // its first letter — on the client's colour
  private static func standIn(_ g: Group) -> (letters: String, color: String) {
    let c = Talk.shared.clients[g.client]
    let color = Look.hex(c?.color) != nil ? (c?.color ?? "#2F6FE4") : "#2F6FE4"
    if g.pic != nil { return (Look.initials(g.name), color) }
    if c?.logo != nil { return (Look.initials(c?.name ?? g.name), color) }
    return (String(g.name.prefix(1)).uppercased(), color)
  }

  // ---------- the groups' small pictures ----------
  // (kept for the groups with unread and the 40 most recently active, muted ones aside; a picture made again only when
  //  what it's made from changes — the group's picture or its client's logo)
  private static var pics: [String: String] {
    get { UserDefaults.standard.dictionary(forKey: "talk_widget_pics") as? [String: String] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: "talk_widget_pics") }
  }
  private static var making = Set<String>()
  private static func keepPictures(_ gs: [WidgetStore.G]) {
    let T = Talk.shared
    var want = Set(gs.filter { $0.unread != 0 }.map { $0.id })
    for g in gs.prefix(40) { want.insert(g.id) }
    var have = pics
    for (id, _) in have where !want.contains(id) || T.isContact { WidgetStore.drop(WidgetStore.picService, id); have[id] = nil }
    pics = have
    guard !T.isContact else { return }   // (a client contact: "E11." on black for every group — drawn by the widget)
    for id in want {
      guard let g = T.groups[id], !making.contains(id) else { continue }
      let c = T.clients[g.client]
      let key = g.pic.map { "f:" + $0 } ?? c?.logo.map { "l:" + $0 }
      if key == have[id] { continue }
      guard let k = key else { WidgetStore.drop(WidgetStore.picService, id); var p = pics; p[id] = nil; pics = p; continue }
      making.insert(id)
      let done = { (i: UIImage?) in
        WidgetFeed.making.remove(id)
        guard let i = i, let d = WidgetFeed.small(i) else { return }
        WidgetStore.put(WidgetStore.picService, id, d)
        var p = WidgetFeed.pics; p[id] = k; WidgetFeed.pics = p
        WidgetFeed.lastSummary = nil; WidgetFeed.later()   // (the summary says it has a picture now: written again, the widget redrawn)
      }
      if let f = g.pic {
        Net.shared.file(f) { u in done(u.flatMap { UIImage(contentsOfFile: $0.path) }) }
      } else if let logo = c?.logo {
        Net.shared.picture(logo) { i in done(i.map { Avatar.inCircle($0) }) }
      }
    }
  }
  // 120 × 120, filled and cut to a square, as a JPEG — a few KB
  private static func small(_ i: UIImage) -> Data? {
    let side: CGFloat = 120, s = i.size
    guard s.width > 0, s.height > 0 else { return nil }
    let k = max(side / s.width, side / s.height), w = s.width * k, h = s.height * k
    let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
    let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { _ in
      UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
      i.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    }
    return out.jpegData(compressionQuality: 0.75)
  }
}
