// E11 Console for Mac — the app's parts outside its window (Haris 2026-11-18):
// · the menu bar item (canvas "Menu bar item — Mac", B5): the e11. wordmark with the unread count in a red circle as tall as
//   it, nothing behind them; a click drops a small panel of ours on Apple's own glass (Liquid Glass on macOS 26, Apple's
//   material before): the newest unread Inbox updates with faces, what's due today with status pills, Open E11 Console and
//   New Task. Live; signed out: no item. View › Show in Menu Bar takes it away and back.
// · Spotlight (canvas "Spotlight — Mac", S1–S3): the tasks, clients and Client Assets folders and files this person can see,
//   in the Mac's own Spotlight; opened in the app. Kept on this Mac only; signing out takes it all away.
// · Dragging files out to Finder (canvas "Drag out to Finder — Mac", D1–D4): a file or a folder (with its files) dragged out
//   of the window lands as the real file wherever it's dropped; drags inside the window stay the page's own.
// The page sends what to show (commands bar / spotlight / signedOut / dragOut — web/macnative.js).
import Cocoa
import WebKit
import CoreSpotlight
import UniformTypeIdentifiers
import CryptoKit

/* ================= the menu bar item ================= */
final class MenuBar: NSObject {
  static let shared = MenuBar()
  weak var main: NSWindow?
  var act: (([String: Any]) -> Void)?   // a row or a button picked: the page does it (window.__e11Bar)
  var openApp: (() -> Void)?
  private var item: NSStatusItem?
  private let mark = NSImageView(), badge = BarBadge()
  private var model: [String: Any] = [:]
  private var panel: BarPanel?
  private var watch: [Any] = []
  var off: Bool { defaults.bool(forKey: "e11_bar_off") }

  // the e11. wordmark (web/logo-wordmark.png without CONSOLE), as Apple's own menu bar pictures: drawn in the bar's colour
  static let wordmark: NSImage? = {
    guard let d = Data(base64Encoded: WORDMARK_B64), let im = NSImage(data: d) else { return nil }
    im.size = NSSize(width: 13 * 301 / 136, height: 13)
    im.isTemplate = true
    return im
  }()

  // the page's model: { on, count, inbox: { n, rows }, day: { title, n, rows }, canNew, sync }
  func apply(_ a: [String: Any]) {
    model = a
    let show = (a["on"] as? Bool) == true && !off
    if !show { hide(); return }
    if item == nil { make() }
    count((a["count"] as? NSNumber)?.intValue ?? 0)
    panel?.fill(model)
  }
  func hide() {
    closePanel()
    if let it = item { NSStatusBar.system.removeStatusItem(it); item = nil }
  }
  func toggleShown() {
    defaults.set(!off, forKey: "e11_bar_off")
    if off { hide() } else { apply(model) }
  }
  private func make() {
    let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item = it
    guard let b = it.button else { return }
    b.image = nil; b.title = ""
    b.target = self; b.action = #selector(clicked(_:))
    b.sendAction(on: [.leftMouseDown, .rightMouseDown])
    b.setAccessibilityLabel("E11 Console")
    mark.image = MenuBar.wordmark
    mark.imageScaling = .scaleProportionallyUpOrDown
    b.addSubview(mark); b.addSubview(badge)
  }
  private func count(_ n: Int) {
    guard let it = item, let b = it.button else { return }
    // (no count in the menu bar — only the E11. mark; the unread count stays in the panel: Haris 2026-11-19 13:48)
    badge.text = ""
    badge.isHidden = true
    let pad: CGFloat = 6, w: CGFloat = 13 * 301 / 136, bw = badge.isHidden ? 0 : badge.width
    it.length = pad + w + (bw > 0 ? 4 + bw : 0) + pad
    let h = b.bounds.height > 0 ? b.bounds.height : NSStatusBar.system.thickness
    mark.frame = NSRect(x: pad, y: ((h - 13) / 2).rounded(), width: w, height: 13)
    // (centred as the wordmark is, nothing nudged — the nudge put it a point low: Haris 2026-11-19 13:25)
    badge.frame = NSRect(x: pad + w + 4, y: ((h - 13) / 2).rounded(), width: bw, height: 13)
    b.setAccessibilityLabel(n > 0 ? "E11 Console, \(n) unread" : "E11 Console")
  }
  @objc private func clicked(_ s: Any?) {
    if panel != nil { closePanel() } else { openPanel() }
  }
  private func openPanel() {
    guard let b = item?.button, let bw = b.window else { return }
    let p = BarPanel()
    // (the Mac's own light or dark — the menu bar's — not the app's: Haris 2026-11-19 12:28)
    p.appearance = MenuBar.system()
    p.pick = { [weak self] a in
      guard let self = self else { return }
      self.closePanel()
      if (a["k"] as? String) == "app" { self.openApp?(); return }
      self.act?(a)
    }
    p.fill(model)
    let r = bw.convertToScreen(b.convert(b.bounds, to: nil))
    let vis = (bw.screen ?? NSScreen.main)?.visibleFrame ?? r
    let size = p.frame.size
    var x = r.midX - size.width / 2
    x = max(vis.minX + 8, min(x, vis.maxX - size.width - 8))
    p.setFrameTopLeftPoint(NSPoint(x: x, y: r.minY - 6))
    panel = p
    watchTheme()
    b.highlight(true)
    p.orderFrontRegardless(); p.makeKey()
    // (a click anywhere else, Esc, or the app's window coming forward: it goes)
    if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.closePanel() }) { watch.append(g) }
    if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] e in
      guard let self = self, let p = self.panel else { return e }
      if e.type == .keyDown { if e.keyCode == 53 { self.closePanel(); return nil }; return e }
      if e.window !== p && e.window !== self.item?.button?.window { self.closePanel() }
      return e
    }) { watch.append(l) }
  }
  func closePanel() {
    watch.forEach { NSEvent.removeMonitor($0) }; watch = []
    item?.button?.highlight(false)
    panel?.orderOut(nil); panel = nil
  }
  func follow(_ ap: NSAppearance?) { panel?.appearance = MenuBar.system(); panel?.fill(model) }
  static func system() -> NSAppearance? {
    NSAppearance(named: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .darkAqua : .aqua)
  }
  private var themeWatch: Any?
  func watchTheme() {
    guard themeWatch == nil else { return }
    themeWatch = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
      guard let self = self, let p = self.panel else { return }
      p.appearance = MenuBar.system(); let m = self.model; p.fill([:]); p.fill(m)
    }
  }
}

// the count: white on red, a circle as tall as the wordmark (a pill for two or three figures)
final class BarBadge: NSView {
  var text = "" { didSet { needsDisplay = true } }
  var width: CGFloat {
    let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 9.5, weight: .bold)]).width
    return max(13, (w + 6).rounded(.up))
  }
  override func draw(_ r: NSRect) {
    NSColor.systemRed.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    let f = NSFont.systemFont(ofSize: 9.5, weight: .bold)
    let at: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor.white]
    let s = (text as NSString).size(withAttributes: at)
    // (the digits centred by their own height, not the line's — they sat 1.5 pt high: Haris 2026-11-19 13:41)
    let y = (bounds.height - f.capHeight) / 2 + f.descender
    (text as NSString).draw(at: NSPoint(x: ((bounds.width - s.width) / 2).rounded(), y: (y * 2).rounded() / 2), withAttributes: at)
  }
}

// Apple's own glass for the panel: Liquid Glass on macOS 26, the popover material before it — in the app's light or dark
func barGlass() -> NSView {
  #if compiler(>=6.2)
  if #available(macOS 26.0, *) { let g = NSGlassEffectView(); g.cornerRadius = 16; return g }
  #endif
  let f = NSVisualEffectView(); f.material = .popover; f.blendingMode = .behindWindow; f.state = .active
  f.wantsLayer = true; f.layer?.cornerRadius = 16; f.layer?.masksToBounds = true
  return f
}
func barPut(_ v: NSView, in g: NSView) {
  #if compiler(>=6.2)
  if #available(macOS 26.0, *), let gl = g as? NSGlassEffectView { gl.contentView = v; return }
  #endif
  g.addSubview(v)
}

final class BarPanel: NSPanel {
  var pick: (([String: Any]) -> Void)?
  private let glass = barGlass(), body = FlippedView()
  private var rows: [String: BarRow] = [:]   // (kept by what they show: drawn again only when that changes)
  private var sig = ""
  static let W: CGFloat = 360
  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: BarPanel.W, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isOpaque = false; backgroundColor = .clear; hasShadow = true
    level = .popUpMenu; isReleasedWhenClosed = false
    collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    let root = NSView(frame: NSRect(x: 0, y: 0, width: BarPanel.W, height: 200))
    root.autoresizingMask = [.width, .height]
    // (cut to the glass's own rounded shape — a square edge showed round it: Haris 2026-11-19 12:28)
    root.wantsLayer = true; root.layer?.cornerRadius = 16; root.layer?.cornerCurve = .continuous; root.layer?.masksToBounds = true
    glass.frame = root.bounds; glass.autoresizingMask = [.width, .height]
    root.addSubview(glass)
    body.frame = glass.bounds; body.autoresizingMask = [.width, .height]
    barPut(body, in: glass)
    contentView = root
  }
  override var canBecomeKey: Bool { true }

  func fill(_ m: [String: Any]) {
    let s = jsonString(m)
    if s == sig { return }
    sig = s
    var used = Set<String>()
    var y: CGFloat = 8
    let W = BarPanel.W, inset: CGFloat = 8
    func put(_ key: String, _ sg: String, _ h: CGFloat, _ make: () -> BarRow) {
      var r = rows[key]
      if r == nil || r!.sig != sg { r?.removeFromSuperview(); r = make(); r!.sig = sg; rows[key] = r; body.addSubview(r!) }
      r!.frame = NSRect(x: inset, y: y, width: W - inset * 2, height: h)
      used.insert(key); y += h
    }
    NSAnimationContext.beginGrouping(); NSAnimationContext.current.duration = 0
    // the app: its icon, its name, how it's syncing
    let sync = m["sync"] as? String ?? ""
    put("head", "h|" + sync, 36) { BarRow.head(sync) }
    let ib = m["inbox"] as? [String: Any] ?? [:], ibRows = ib["rows"] as? [[String: Any]] ?? []
    let n = (ib["n"] as? NSNumber)?.intValue ?? 0
    put("ibh", "ih|\(n)", 24) { BarRow.section("Inbox", n > 0 ? "\(n) unread" : "", "Open Inbox", ["k": "inbox"], self.pick) }
    if ibRows.isEmpty { put("ib0", "i0", 30) { BarRow.note("Nothing unread — you’re all caught up") } }
    for (i, r) in ibRows.enumerated() { put("ib:" + (r["id"] as? String ?? "\(i)"), jsonString(r), 44) { BarRow.update(r, self.pick) } }
    put("sep", "sep", 13) { BarRow.sep() }
    let dy = m["day"] as? [String: Any] ?? [:], dyRows = dy["rows"] as? [[String: Any]] ?? []
    let dn = (dy["n"] as? NSNumber)?.intValue ?? 0, dt = dy["title"] as? String ?? "E11 Day"
    put("dyh", "dh|\(dn)|" + dt, 24) { BarRow.section(dt, dn > 0 ? "\(dn) due today" : "", "Open " + dt, ["k": "day"], self.pick) }
    if dyRows.isEmpty { put("dy0", "d0", 30) { BarRow.note("Nothing due today") } }
    for (i, r) in dyRows.enumerated() { put("dy:" + (r["id"] as? String ?? "\(i)"), jsonString(r), 44) { BarRow.task(r, self.pick) } }
    let canNew = (m["canNew"] as? Bool) == true
    y += 6
    put("btns", "b|\(canNew)", 34) { BarRow.buttons(canNew, self.pick) }
    y += 8
    for (k, r) in rows where !used.contains(k) { r.removeFromSuperview(); rows[k] = nil }
    NSAnimationContext.endGrouping()
    let top = frame.maxY
    setFrame(NSRect(x: frame.minX, y: top - y, width: W, height: y), display: true)
    invalidateShadow()   // (its shadow from its rounded shape, as it is now)
  }
}

// one line of the panel; clickable when it has something to do
final class BarRow: FlippedView {
  var sig = ""
  var onClick: (() -> Void)?
  private var hover = false { didSet { needsDisplay = true } }
  private var area: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let a = area { removeTrackingArea(a) }
    guard onClick != nil else { return }
    area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area!)
  }
  override func mouseEntered(with e: NSEvent) { hover = true }
  override func mouseExited(with e: NSEvent) { hover = false }
  override func mouseDown(with e: NSEvent) {}
  override func mouseUp(with e: NSEvent) { if onClick != nil, bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() } }
  override func draw(_ r: NSRect) {
    guard hover, onClick != nil, !isButtons else { return }
    NSColor.labelColor.withAlphaComponent(0.08).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
  }
  var isButtons = false

  static func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ c: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: size, weight: weight); l.textColor = c
    l.lineBreakMode = .byTruncatingTail; l.maximumNumberOfLines = 1
    l.cell?.truncatesLastVisibleLine = true
    return l
  }
  static func head(_ sync: String) -> BarRow {
    let v = BarRow()
    let ic = NSImageView(frame: NSRect(x: 6, y: 7, width: 22, height: 22))
    ic.image = NSApp.applicationIconImage
    v.addSubview(ic)
    let t = label(APP_NAME, 13, .semibold); t.frame = NSRect(x: 34, y: 9, width: 200, height: 18); v.addSubview(t)
    let s = label(sync, 11.5, .regular, .secondaryLabelColor); s.alignment = .right
    s.frame = NSRect(x: 150, y: 10, width: BarPanel.W - 16 - 150 - 8, height: 16); s.autoresizingMask = [.minXMargin]; v.addSubview(s)
    return v
  }
  static func section(_ title: String, _ n: String, _ link: String, _ act: [String: Any], _ pick: (([String: Any]) -> Void)?) -> BarRow {
    let v = BarRow()
    let t = label(title, 12, .semibold); t.sizeToFit(); t.frame.origin = NSPoint(x: 8, y: 4); v.addSubview(t)
    let c = label(n, 11.5, .regular, .secondaryLabelColor); c.sizeToFit(); c.frame.origin = NSPoint(x: t.frame.maxX + 6, y: 5); v.addSubview(c)
    let b = BarLink(link) { pick?(act) }
    b.sizeToFit(); b.frame.origin = NSPoint(x: BarPanel.W - 16 - 8 - b.frame.width, y: 4); v.addSubview(b)
    return v
  }
  static func note(_ s: String) -> BarRow {
    let v = BarRow()
    let l = label(s, 12, .regular, .secondaryLabelColor); l.frame = NSRect(x: 8, y: 7, width: BarPanel.W - 32, height: 16); v.addSubview(l)
    return v
  }
  static func sep() -> BarRow {
    let v = BarRow()
    let line = NSBox(frame: NSRect(x: 8, y: 6, width: BarPanel.W - 32, height: 1)); line.boxType = .separator
    v.addSubview(line)
    return v
  }
  // two lines after a lead (a face, or a client's colour), something at the end
  private static func two(_ lead: NSView, _ a: NSAttributedString, _ b: String, _ tail: NSView?) -> BarRow {
    let v = BarRow()
    lead.frame.origin = NSPoint(x: 8, y: 9); v.addSubview(lead)
    let tw = tail.map { $0.frame.width + 10 } ?? 0
    let l1 = NSTextField(labelWithAttributedString: a)
    l1.lineBreakMode = .byTruncatingTail; l1.maximumNumberOfLines = 1; l1.cell?.truncatesLastVisibleLine = true
    l1.frame = NSRect(x: 44, y: 6, width: BarPanel.W - 16 - 44 - 8 - tw, height: 17); v.addSubview(l1)
    let l2 = label(b, 11, .regular, .secondaryLabelColor)
    l2.frame = NSRect(x: 44, y: 23, width: BarPanel.W - 16 - 44 - 8 - tw, height: 15); v.addSubview(l2)
    if let t = tail { t.frame.origin = NSPoint(x: BarPanel.W - 16 - 8 - t.frame.width, y: ((44 - t.frame.height) / 2).rounded()); v.addSubview(t) }
    return v
  }
  // an Inbox update: their face, who and what, which task and when, the blue dot
  static func update(_ r: [String: Any], _ pick: (([String: Any]) -> Void)?) -> BarRow {
    let face = BarFace(r)
    let s = NSMutableAttributedString()
    let who = r["who"] as? String ?? "", what = r["what"] as? String ?? ""
    if !who.isEmpty { s.append(NSAttributedString(string: who + " ", attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: NSColor.labelColor])) }
    s.append(NSAttributedString(string: what, attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.labelColor]))
    let dot = NSView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    dot.wantsLayer = true; dot.layer?.cornerRadius = 3.5; dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    let v = two(face, s, r["sub"] as? String ?? "", dot)
    let id = r["id"] as? String ?? ""
    v.onClick = { pick?(["k": "notif", "id": id]) }
    v.setAccessibilityRole(.button); v.setAccessibilityLabel("\(who) \(what)")
    return v
  }
  // a task due today: its client's colour, its name, its client, its status as a pill
  static func task(_ r: [String: Any], _ pick: (([String: Any]) -> Void)?) -> BarRow {
    let lead = NSView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
    let sq = NSView(frame: NSRect(x: 8, y: 8, width: 10, height: 10))
    sq.wantsLayer = true; sq.layer?.cornerRadius = 3; sq.layer?.backgroundColor = (TrashWindow.color(r["dot"] as? String) ?? .systemGray).cgColor
    lead.addSubview(sq)
    let s = NSAttributedString(string: r["title"] as? String ?? "", attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.labelColor])
    var pill: NSView?
    if let p = r["pill"] as? [String: Any], let t = p["t"] as? String, !t.isEmpty { pill = BarPill(t, TrashWindow.color(p["c"] as? String) ?? .systemGray) }
    let v = two(lead, s, r["sub"] as? String ?? "", pill)
    let id = r["id"] as? String ?? ""
    v.onClick = { pick?(["k": "task", "id": id]) }
    v.setAccessibilityRole(.button); v.setAccessibilityLabel(r["title"] as? String ?? "")
    return v
  }
  static func buttons(_ canNew: Bool, _ pick: (([String: Any]) -> Void)?) -> BarRow {
    let v = BarRow(); v.isButtons = true
    let W = BarPanel.W - 16 - 16
    let open = BarButton("Open E11 Console", primary: false) { pick?(["k": "app"]) }
    if canNew {
      let nw = BarButton("New Task", primary: true) { pick?(["k": "new"]) }
      let w = (W - 8) / 2
      open.frame = NSRect(x: 8, y: 3, width: w, height: 28); nw.frame = NSRect(x: 8 + w + 8, y: 3, width: w, height: 28)
      v.addSubview(open); v.addSubview(nw)
    } else { open.frame = NSRect(x: 8, y: 3, width: W, height: 28); v.addSubview(open) }
    return v
  }
}

// a person's face: their photo, or their initials on their colour (as the page's)
final class BarFace: NSView {
  init(_ r: [String: Any]) {
    super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
    wantsLayer = true; layer?.cornerRadius = 13; layer?.masksToBounds = true
    layer?.backgroundColor = (TrashWindow.color(r["color"] as? String) ?? .systemGray).cgColor
    let ini = NSTextField(labelWithString: r["ini"] as? String ?? "")
    ini.font = .systemFont(ofSize: 10, weight: .semibold); ini.textColor = .white; ini.alignment = .center
    ini.frame = NSRect(x: 0, y: 6, width: 26, height: 14)
    addSubview(ini)
    if let u = r["pic"] as? String, !u.isEmpty {
      MacLoad.image(u) { [weak self] im in
        guard let self = self, let im = im else { return }
        ini.removeFromSuperview()
        self.layer?.contentsGravity = .resizeAspectFill
        self.layer?.contents = im.layerContents(forContentsScale: self.window?.backingScaleFactor ?? 2)
      }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
}
// a status as a pill: white words on its colour (as the page's task rows)
final class BarPill: NSView {
  private let t: String, c: NSColor
  private static let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
  init(_ t: String, _ c: NSColor) {
    self.t = t; self.c = c
    let w = (t as NSString).size(withAttributes: [.font: BarPill.font]).width
    super.init(frame: NSRect(x: 0, y: 0, width: (w + 14).rounded(.up), height: 18))
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ r: NSRect) {
    c.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    let at: [NSAttributedString.Key: Any] = [.font: BarPill.font, .foregroundColor: NSColor.white]
    let s = (t as NSString).size(withAttributes: at)
    (t as NSString).draw(at: NSPoint(x: ((bounds.width - s.width) / 2).rounded(), y: ((bounds.height - s.height) / 2).rounded()), withAttributes: at)
  }
}
// "Open Inbox": blue words
final class BarLink: NSTextField {
  private var run: (() -> Void)?
  convenience init(_ s: String, _ run: @escaping () -> Void) {
    self.init(labelWithString: s)
    self.run = run
    font = .systemFont(ofSize: 11.5); textColor = .controlAccentColor
    setAccessibilityRole(.button)
  }
  override func mouseDown(with e: NSEvent) {}
  override func mouseUp(with e: NSEvent) { if bounds.contains(convert(e.locationInWindow, from: nil)) { run?() } }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
// the two buttons: round, the app's accent for New Task
final class BarButton: NSView {
  private let t: String, primary: Bool, run: () -> Void
  private var down = false { didSet { needsDisplay = true } }
  init(_ t: String, primary: Bool, _ run: @escaping () -> Void) {
    self.t = t; self.primary = primary; self.run = run
    super.init(frame: .zero)
    setAccessibilityRole(.button); setAccessibilityLabel(t)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func mouseDown(with e: NSEvent) { down = true }
  override func mouseUp(with e: NSEvent) { down = false; if bounds.contains(convert(e.locationInWindow, from: nil)) { run() } }
  override func draw(_ r: NSRect) {
    let bg: NSColor = primary ? .controlAccentColor : NSColor.labelColor.withAlphaComponent(0.1)
    (down ? bg.withAlphaComponent(primary ? 0.8 : 0.16) : bg).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    let at: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: primary ? NSColor.white : NSColor.labelColor]
    let s = (t as NSString).size(withAttributes: at)
    (t as NSString).draw(at: NSPoint(x: ((bounds.width - s.width) / 2).rounded(), y: ((bounds.height - s.height) / 2).rounded()), withAttributes: at)
  }
}

/* ================= Spotlight ================= */
enum Spot {
  static let domain = "ae.e11.console"
  private static let index = CSSearchableIndex.default()
  private static var sigs: [String: String] = (defaults.dictionary(forKey: "e11_spot") as? [String: String]) ?? [:]
  private static var thumbQ: [(String, String, CSSearchableItem)] = [], thumbing = false
  // the page's list: { who: "<server>|<user>", items: [{ id, title, desc, keys, ext, kind, thumb, ini, color }] }
  static func update(_ a: [String: Any]) {
    let who = a["who"] as? String ?? ""
    guard !who.isEmpty, let list = a["items"] as? [[String: Any]] else { return }
    if defaults.string(forKey: "e11_spot_who") != who { clear(); defaults.set(who, forKey: "e11_spot_who") }
    var now: [String: String] = [:], add: [CSSearchableItem] = []
    for it in list {
      guard let id = it["id"] as? String, !id.isEmpty else { continue }
      let sg = SHA256.hash(data: Data(jsonString(it).utf8)).map { String(format: "%02x", $0) }.joined()
      now[id] = sg
      if sigs[id] == sg { continue }
      let item = searchable(id, it)
      add.append(item)
      if let t = it["thumb"] as? String, !t.isEmpty { thumbQ.append((id, t, item)) }
    }
    let gone = sigs.keys.filter { now[$0] == nil }
    sigs = now
    defaults.set(sigs, forKey: "e11_spot")
    if !gone.isEmpty { index.deleteSearchableItems(withIdentifiers: Array(gone), completionHandler: nil) }
    stride(from: 0, to: add.count, by: 400).forEach { i in Spot.index.indexSearchableItems(Array(add[i..<min(i + 400, add.count)]), completionHandler: nil) }
    nextThumb()
  }
  private static func searchable(_ id: String, _ it: [String: Any]) -> CSSearchableItem {
    let ext = it["ext"] as? String ?? ""
    let type: UTType = !ext.isEmpty ? (UTType(filenameExtension: ext) ?? .data) : (it["kind"] as? String) == "Folder" ? .folder : .item
    let at = CSSearchableItemAttributeSet(contentType: type)
    at.title = it["title"] as? String
    at.displayName = it["title"] as? String
    at.contentDescription = it["desc"] as? String
    at.keywords = it["keys"] as? [String]
    if let ini = it["ini"] as? String, !ini.isEmpty { at.thumbnailData = circle(ini, TrashWindow.color(it["color"] as? String) ?? .systemGray) }
    return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: at)
  }
  // a client: its initials on its colour, as the page's
  private static func circle(_ s: String, _ c: NSColor) -> Data? {
    let im = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { r in
      c.setFill(); NSBezierPath(ovalIn: r).fill()
      let at: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: NSColor.white]
      let z = (s as NSString).size(withAttributes: at)
      (s as NSString).draw(at: NSPoint(x: (r.width - z.width) / 2, y: (r.height - z.height) / 2), withAttributes: at)
      return true
    }
    guard let t = im.tiffRepresentation, let b = NSBitmapImageRep(data: t) else { return nil }
    return b.representation(using: .png, properties: [:])
  }
  // photos: their own small picture, fetched one at a time with the app's sign-in
  private static func nextThumb() {
    guard !thumbing, !thumbQ.isEmpty else { return }
    thumbing = true
    let (id, url, item) = thumbQ.removeFirst()
    MacLoad.data(url) { d in
      if let d = d, Spot.sigs[id] != nil { item.attributeSet.thumbnailData = d; Spot.index.indexSearchableItems([item], completionHandler: nil) }
      Spot.thumbing = false
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Spot.nextThumb() }
    }
  }
  static func clear() {
    thumbQ = []; sigs = [:]
    defaults.removeObject(forKey: "e11_spot"); defaults.removeObject(forKey: "e11_spot_who")
    index.deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: nil)
  }
  // a Spotlight result opened: its id, for the page
  static func picked(_ u: NSUserActivity) -> String? {
    guard u.activityType == CSSearchableItemActionType else { return nil }
    return u.userInfo?[CSSearchableItemActivityIdentifier] as? String
  }
}

/* ================= dragging files out to Finder ================= */
// (the drag notes taken out once the drag to Finder worked — Haris 2026-11-19 20:50: nothing written)
enum DragLog {
  @inline(__always) static func note(_ s: @autoclosure () -> String) {}
}

// a file { name, url, size } or a folder { name, folder: true, files: [...], folders: [...] } from the page, promised to
// wherever it's dropped and fetched with the app's sign-in once it is
final class OutPromise: NSObject, NSFilePromiseProviderDelegate {
  let item: [String: Any]
  init(_ item: [String: Any]) { self.item = item }
  func filePromiseProvider(_ p: NSFilePromiseProvider, fileNameForType t: String) -> String { DragLog.note("Finder asked the name: \(item["name"] ?? "-") type=\(t)"); return FileDrag.safe(item["name"] as? String ?? "file") }
  func filePromiseProvider(_ p: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler done: @escaping (Error?) -> Void) {
    // (dropped back on the window itself: the page's own drop, nothing fetched)
    DragLog.note("Finder asked for the file at \(url.path) inside=\(FileDrag.inside)")
    if FileDrag.inside { return done(NSError(domain: "E11Console", code: 1, userInfo: [NSLocalizedDescriptionKey: "Dropped in the app"])) }
    let ok = FileDrag.write(item, to: url)
    DragLog.note("file written: \(ok)")
    ok ? done(nil) : done(NSError(domain: "E11Console", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn’t download " + (item["name"] as? String ?? "the file")]))
  }
  func operationQueue(for p: NSFilePromiseProvider) -> OperationQueue { FileDrag.queue }
}

enum FileDrag {
  static let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .userInitiated; return q }()
  static var inside = false          // the drop is on the app's own window
  static var keep: [OutPromise] = [], keepP: [NSFilePromiseProvider] = []   // (kept till the next drag: written after it ends)
  static func safe(_ n: String) -> String {
    let s = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
    return s.isEmpty || s.hasPrefix(".") ? "file" + s : s
  }
  static func providers(_ items: [[String: Any]]) -> [NSFilePromiseProvider] {
    keep = items.map { OutPromise($0) }
    keepP = keep.map { d in
      let folder = (d.item["folder"] as? Bool) == true
      let ext = ((d.item["name"] as? String ?? "") as NSString).pathExtension
      let type = folder ? UTType.folder.identifier : (UTType(filenameExtension: ext) ?? .data).identifier
      return NSFilePromiseProvider(fileType: type, delegate: d)
    }
    return keepP
  }
  // (on the promises' queue: waits for each file)
  static func write(_ item: [String: Any], to url: URL) -> Bool {
    if (item["folder"] as? Bool) == true {
      do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch { return false }
      var ok = true
      for f in item["files"] as? [[String: Any]] ?? [] { ok = write(f, to: free(url, safe(f["name"] as? String ?? "file"))) && ok }
      for f in item["folders"] as? [[String: Any]] ?? [] { ok = write(f, to: free(url, safe(f["name"] as? String ?? "Folder"))) && ok }
      return ok
    }
    guard let s = item["url"] as? String, let src = URL(string: s) else { DragLog.note("no url for \(item["name"] ?? "-")"); return false }
    let size = (item["size"] as? NSNumber)?.int64Value ?? 0
    // Finder's own progress on the file's icon while it comes down
    _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    let pr = Progress(totalUnitCount: max(size, 1))
    pr.kind = .file; pr.fileOperationKind = .downloading; pr.fileURL = url
    pr.publish()
    defer { pr.unpublish() }
    // (from Cloudflare R2 when it has a fast copy: asked with r2=1, the sign-in never going along to R2 — R2Redirect; if R2
    //  doesn't answer well, the office is asked as before — Haris 2026-11-20 23:13, the Mac round)
    func fetch(_ from: URL, viaR2: Bool) -> Bool {
      var r = URLRequest(url: from)
      r.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: MacLoad.mine(src))
      let wait = DispatchSemaphore(value: 0)
      var ok = false
      let task = URLSession.shared.downloadTask(with: r) { tmp, resp, err in
        defer { wait.signal() }
        DragLog.note("download\(viaR2 ? " (R2 asked)" : ""): status=\((resp as? HTTPURLResponse)?.statusCode ?? -1) host=\((resp as? HTTPURLResponse)?.url?.host ?? "-") error=\(err?.localizedDescription ?? "-")")
        guard err == nil, let tmp = tmp, ((resp as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2 else { return }
        do { _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp); ok = true } catch {
          try? FileManager.default.removeItem(at: url)
          ok = (try? FileManager.default.moveItem(at: tmp, to: url)) != nil
        }
      }
      if viaR2, #available(macOS 12.0, *) { task.delegate = R2Redirect.shared }
      let watch = task.progress.observe(\.completedUnitCount) { p, _ in pr.completedUnitCount = p.completedUnitCount }
      task.resume()
      wait.wait()
      watch.invalidate()
      return ok
    }
    // (a task's own redirect handling is macOS 12+: older Macs keep the office)
    var fast = src
    if #available(macOS 12.0, *) { fast = R2Redirect.ask(src) }
    var ok = false
    if fast != src { ok = fetch(fast, viaR2: true); if !ok { pr.completedUnitCount = 0; _ = FileManager.default.createFile(atPath: url.path, contents: nil) } }
    if !ok { ok = fetch(src, viaR2: false) }
    if !ok { try? FileManager.default.removeItem(at: url); return false }
    var u = url, rv = URLResourceValues()
    rv.quarantineProperties = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String, kLSQuarantineAgentNameKey as String: APP_NAME]
    try? u.setResourceValues(rv)
    return true
  }
  // (two files of the same name in one folder: the second "name 2", as Finder)
  static func free(_ dir: URL, _ name: String) -> URL {
    var u = dir.appendingPathComponent(name), i = 2
    let ext = (name as NSString).pathExtension, base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
    while FileManager.default.fileExists(atPath: u.path) { u = dir.appendingPathComponent(base + " \(i)" + (ext.isEmpty ? "" : "." + ext)); i += 1 }
    return u
  }
  // a drag of the app's own native views (the preview's name, a Trash window's file)
  static func begin(_ items: [[String: Any]], from v: NSView, event e: NSEvent, image: NSImage?) {
    guard !items.isEmpty else { return }
    let p = v.convert(e.locationInWindow, from: nil)
    let first = items[0]
    let ext = ((first["name"] as? String ?? "") as NSString).pathExtension
    let pic = image ?? ((first["folder"] as? Bool) == true ? NSWorkspace.shared.icon(for: .folder) : NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data))
    let dItems = providers(items).enumerated().map { (i, pv) -> NSDraggingItem in
      let d = NSDraggingItem(pasteboardWriter: pv)
      d.setDraggingFrame(NSRect(x: p.x - 32 + CGFloat(i * 6), y: p.y - 32 - CGFloat(i * 6), width: 64, height: 64), contents: i == 0 ? pic : nil)
      return d
    }
    _ = v.beginDraggingSession(with: dItems, event: e, source: OutSource.shared)
  }
}
// (the app's drag of the page's files: a copy to Finder, a move inside the window — where the page takes it)
final class NativeSource: NSObject, NSDraggingSource {
  weak var web: E11WebView?
  init(_ w: E11WebView) { web = w }
  func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { c == .outsideApplication ? .copy : .move }
  func draggingSession(_ s: NSDraggingSession, movedTo p: NSPoint) { web?.nativeMoved(p) }
  func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation op: NSDragOperation) { web?.nativeEnded(p, op) }
}
// (where the app's drag starts from: over the whole page, never in the way of a click)
final class DragHost: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ p: NSPoint) -> NSView? { nil }
}
extension FileDrag {
  // the file small, as Finder's: its picture, and its name under it on blue (as the page's own — Haris 19:24)
  static func ghost(_ pic: NSImage?, name: String, items: [[String: Any]]) -> NSImage {
    let first = items.first ?? [:]
    let ext = ((first["name"] as? String ?? "") as NSString).pathExtension
    let p = pic ?? ((first["folder"] as? Bool) == true ? NSWorkspace.shared.icon(for: .folder) : NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data))
    let w: CGFloat = 96, h = max(24, min(120, (w * p.size.height / max(1, p.size.width)).rounded()))
    let font = NSFont.systemFont(ofSize: 11), attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let nm = NSAttributedString(string: name, attributes: attrs)
    let tw = min(124, ceil(nm.size().width) + 12), th: CGFloat = 16
    let W = max(w, tw) + 28, H = 6 + h + 4 + th + 6
    return NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
      let pr = NSRect(x: (W - w) / 2, y: 6, width: w, height: h)
      NSGraphicsContext.saveGraphicsState()
      let sh = NSShadow(); sh.shadowBlurRadius = 6; sh.shadowOffset = NSSize(width: 0, height: -3); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.set()
      NSColor.white.setFill(); NSBezierPath(roundedRect: pr, xRadius: 6, yRadius: 6).fill()
      NSGraphicsContext.restoreGraphicsState()
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(roundedRect: pr, xRadius: 6, yRadius: 6).addClip()
      p.draw(in: pr)
      NSGraphicsContext.restoreGraphicsState()
      let lr = NSRect(x: (W - tw) / 2, y: pr.maxY + 4, width: tw, height: th)
      NSColor.controlAccentColor.setFill(); NSBezierPath(roundedRect: lr, xRadius: 4, yRadius: 4).fill()
      let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingMiddle; para.alignment = .center
      var a2 = attrs; a2[.paragraphStyle] = para
      NSAttributedString(string: name, attributes: a2).draw(in: lr.insetBy(dx: 6, dy: 1))
      return true
    }
  }
}
final class OutSource: NSObject, NSDraggingSource {
  static let shared = OutSource()
  func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { c == .outsideApplication ? .copy : [] }
}

// The page's own web view, which can also drag its files out: when the page says a drag it starts is of files (command
// dragOut, sent just before its drag), the drag carries them too as Apple's file promises — inside the window the page
// sees only its own drag, as before (the drop is shown its own data, not the promises).
final class E11WebView: WKWebView, NSDraggingSource {
  var outItems: [[String: Any]]?, outAt = Date.distantPast
  private var ours: NSDraggingSession?
  private var ownPB: NSPasteboard?
  private func take() -> [[String: Any]]? {
    defer { outItems = nil }
    DragLog.note("drag started: page's files=\(outItems?.count ?? -1) age=\(String(format: "%.2f", Date().timeIntervalSince(outAt)))s")
    guard let it = outItems, !it.isEmpty, Date().timeIntervalSince(outAt) < 4 else { return nil }
    return it
  }
  // the page's drag data, copied (for the drop inside the window) — once into the drag, once for the page to read
  private func copyItem(_ pb: NSPasteboard) -> NSPasteboardItem {
    let pi = NSPasteboardItem()
    for t in pb.types ?? [] { if let d = pb.data(forType: t) { pi.setData(d, forType: t) } }
    return pi
  }
  private func keepOwn(_ pb: NSPasteboard) {
    let own = NSPasteboard.withUniqueName()
    own.clearContents()
    own.writeObjects([copyItem(pb)])
    ownPB = own
  }
  // (WebKit starts the page's drags with the older dragImage:at:offset:event:pasteboard:source:slideBack:, which Swift can't
  //  override by its name — put in by the runtime once, the old one called for every other drag)
  static let hook: Void = {
    let sel = NSSelectorFromString("dragImage:at:offset:event:pasteboard:source:slideBack:")
    guard let m = class_getInstanceMethod(WKWebView.self, sel) else { return }
    typealias Old = @convention(c) (AnyObject, Selector, NSImage, NSPoint, NSSize, NSEvent, NSPasteboard, AnyObject, ObjCBool) -> Void
    let call = unsafeBitCast(method_getImplementation(m), to: Old.self)
    let blk: @convention(block) (AnyObject, NSImage, NSPoint, NSSize, NSEvent, NSPasteboard, AnyObject, ObjCBool) -> Void = { me, im, at, off, ev, pb, src, slide in
      if let w = me as? E11WebView, w.outDrag(im, at, ev, pb, slide.boolValue) { return }
      call(me, sel, im, at, off, ev, pb, src, slide)
    }
    class_addMethod(E11WebView.self, sel, imp_implementationWithBlock(blk), method_getTypeEncoding(m))
  }()
  override init(frame: CGRect, configuration: WKWebViewConfiguration) {
    _ = E11WebView.hook
    super.init(frame: frame, configuration: configuration)
  }
  required init?(coder: NSCoder) { super.init(coder: coder) }
  // (the page's drag, of files: one session of ours carrying the page's own data and the files)
  fileprivate func outDrag(_ anImage: NSImage, _ viewLocation: NSPoint, _ event: NSEvent, _ pboard: NSPasteboard, _ slideFlag: Bool) -> Bool {
    guard let items = take() else { return false }
    // (only the files go in the drag — the page's own data kept apart, shown to the page alone when it's dropped back on
    //  the window. Its own item went too: Finder counted 2 for one file and took neither — Haris 2026-11-19 12:20)
    keepOwn(pboard)
    let sz = anImage.size
    let frame = NSRect(x: viewLocation.x, y: isFlipped ? viewLocation.y - sz.height : viewLocation.y, width: sz.width, height: sz.height)
    let all = FileDrag.providers(items).enumerated().map { i, pv -> NSDraggingItem in
      let d = NSDraggingItem(pasteboardWriter: pv); d.setDraggingFrame(frame, contents: i == 0 ? anImage : nil); return d
    }
    legacy = true
    DragLog.note("our drag (older kind): \(all.count) file(s) \(items.map { "\($0["name"] ?? "-")" })")
    ours = beginDraggingSession(with: all, event: event, source: self)
    ours?.animatesToStartingPositionsOnCancelOrFail = slideFlag
    return true
  }
  // (and newer WebKits may this way: the files added to its own items)
  override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: NSDraggingSource) -> NSDraggingSession {
    if ours == nil, let files = take() {
      keepOwn(NSPasteboard(name: .drag))
      let f = items.first?.draggingFrame ?? .zero, pic = items.first?.imageComponentsProvider
      let all = FileDrag.providers(files).enumerated().map { i, pv -> NSDraggingItem in
        let d = NSDraggingItem(pasteboardWriter: pv); d.draggingFrame = f; if i == 0 { d.imageComponentsProvider = pic }; return d
      }
      DragLog.note("our drag (newer kind): \(all.count) file(s) \(files.map { "\($0["name"] ?? "-")" })")
      let s = super.beginDraggingSession(with: all, event: event, source: source)
      ours = s; legacy = false
      DragLog.note("drag pasteboard \(s.draggingPasteboard.name.rawValue): items=\(s.draggingPasteboard.pasteboardItems?.count ?? -1) " + (s.draggingPasteboard.pasteboardItems ?? []).enumerated().map { "#\($0.offset) \($0.element.types.map { $0.rawValue })" }.joined(separator: " "))
      return s
    }
    return super.beginDraggingSession(with: items, event: event, source: source)
  }
  private var legacy = true   // (our session stands in for WebKit's older kind of drag: it's told what that would have been)

  // ---- as the drag's source: WebKit told what it would be told for its own drags; the files go out as a copy ----
  private func superIMP(_ name: String) -> (Selector, IMP)? {
    let sel = NSSelectorFromString(name)
    guard let m = class_getInstanceMethod(WKWebView.self, sel) else { return nil }
    return (sel, method_getImplementation(m))
  }
  private func old(_ s: NSDraggingSession) -> Bool { s === ours && legacy }
  func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation {
    var op: NSDragOperation = .copy
    if old(s) {
      if let (sel, imp) = superIMP("draggingSourceOperationMaskForLocal:") {
        typealias F = @convention(c) (AnyObject, Selector, ObjCBool) -> UInt
        op = NSDragOperation(rawValue: unsafeBitCast(imp, to: F.self)(self, sel, ObjCBool(c == .withinApplication)))
      } else { op = [.copy, .move, .generic] }
    } else if let (sel, imp) = superIMP("draggingSession:sourceOperationMaskForDraggingContext:") {
      typealias F = @convention(c) (AnyObject, Selector, NSDraggingSession, Int) -> UInt
      op = NSDragOperation(rawValue: unsafeBitCast(imp, to: F.self)(self, sel, s, c.rawValue))
    }
    let out = s === ours && c == .outsideApplication ? op.union(.copy) : op
    if c == .outsideApplication { DragLog.note("allowed outside: ours=\(s === ours) op=\(out.rawValue)") }
    return out
  }
  func draggingSession(_ s: NSDraggingSession, willBeginAt p: NSPoint) {
    if s === ours { DragLog.note("as it began — drag pasteboard items=\(s.draggingPasteboard.pasteboardItems?.count ?? -1) " + (s.draggingPasteboard.pasteboardItems ?? []).enumerated().map { "#\($0.offset) \($0.element.types.map { $0.rawValue })" }.joined(separator: " ")) }
    // (WebKit wrote its own page data over the drag after it started, so Finder saw no file at all and turned it down —
    //  measured in the drag notes, Haris 2026-11-19 19:59: the files put back as the drag begins; the page's own data is
    //  kept apart already, for a drop back on the window)
    if s === ours, !FileDrag.keepP.isEmpty {
      let pb = s.draggingPasteboard
      if !(pb.types ?? []).contains(NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")) {
        pb.clearContents(); pb.writeObjects(FileDrag.keepP)
        DragLog.note("files put back — drag pasteboard items=\(pb.pasteboardItems?.count ?? -1) " + (pb.pasteboardItems ?? []).enumerated().map { "#\($0.offset) \($0.element.types.map { $0.rawValue })" }.joined(separator: " "))
      }
    }
    if old(s) {
      if let (sel, imp) = superIMP("draggedImage:beganAt:") { typealias F = @convention(c) (AnyObject, Selector, NSImage?, NSPoint) -> Void; unsafeBitCast(imp, to: F.self)(self, sel, nil, p) }
    } else if let (sel, imp) = superIMP("draggingSession:willBeginAtPoint:") { typealias F = @convention(c) (AnyObject, Selector, NSDraggingSession, NSPoint) -> Void; unsafeBitCast(imp, to: F.self)(self, sel, s, p) }
  }
  func draggingSession(_ s: NSDraggingSession, movedTo p: NSPoint) {
    if old(s) {
      if let (sel, imp) = superIMP("draggedImage:movedTo:") { typealias F = @convention(c) (AnyObject, Selector, NSImage?, NSPoint) -> Void; unsafeBitCast(imp, to: F.self)(self, sel, nil, p) }
    } else if let (sel, imp) = superIMP("draggingSession:movedToPoint:") { typealias F = @convention(c) (AnyObject, Selector, NSDraggingSession, NSPoint) -> Void; unsafeBitCast(imp, to: F.self)(self, sel, s, p) }
  }
  func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation op: NSDragOperation) {
    let mine = s === ours
    DragLog.note("drag ended: ours=\(mine) operation=\(op.rawValue) (0 = turned down)")
    if old(s) {
      if let (sel, imp) = superIMP("draggedImage:endedAt:operation:") { typealias F = @convention(c) (AnyObject, Selector, NSImage?, NSPoint, UInt) -> Void; unsafeBitCast(imp, to: F.self)(self, sel, nil, p, op.rawValue) }
    } else if let (sel, imp) = superIMP("draggingSession:endedAtPoint:operation:") { typealias F = @convention(c) (AnyObject, Selector, NSDraggingSession, NSPoint, UInt) -> Void; unsafeBitCast(imp, to: F.self)(self, sel, s, p, op.rawValue) }
    if mine { ours = nil; legacy = true; ownPB = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 1) { FileDrag.inside = false } }
  }

  // ---- the app's own drag of the page's files (command dragNative — Haris 2026-11-19 20:10): the page stops its web
  //  drag, and the drag is started here as Finder's, its file promises written by AppKit alone, so WebKit never writes
  //  over them. Over the window, the page is told where it is (Client Assets lights the folder it would go in) and where
  //  it was let go; nothing of it reaches WebKit's own drop. ----
  private var lastMouse: NSEvent?
  override func mouseDown(with e: NSEvent) { lastMouse = e; super.mouseDown(with: e) }
  override func mouseDragged(with e: NSEvent) { lastMouse = e; super.mouseDragged(with: e) }
  private lazy var dragHost: DragHost = { let h = DragHost(frame: bounds); h.autoresizingMask = [.width, .height]; addSubview(h); return h }()
  fileprivate var native: NSDraggingSession?
  private var nativeSrc: NativeSource?
  fileprivate var hotOK = false
  private var asking = false, askAgain: NSPoint?
  private func isNative(_ d: NSDraggingInfo?) -> Bool { if let s = native, let d = d { return d.draggingSequenceNumber == s.draggingSequenceNumber }; return false }
  // (a point on the screen as the page's own: its spot in the page, and whether it's over the page at all)
  private func pagePoint(_ screen: NSPoint) -> (x: Double, y: Double, inside: Bool) {
    guard let w = window else { return (0, 0, false) }
    let wp = w.convertPoint(fromScreen: screen), vp = convert(wp, from: nil), z = max(0.1, pageZoom)
    return (Double(vp.x / z), Double((isFlipped ? vp.y : bounds.height - vp.y) / z), w.isVisible && bounds.contains(vp))
  }
  func nativeDrag(_ items: [[String: Any]], rect r: CGRect, name: String, done: @escaping (Bool) -> Void) {
    guard native == nil, let e = lastMouse, NSEvent.pressedMouseButtons & 1 == 1 else {
      DragLog.note("app's drag: not started — mouse=\(lastMouse != nil) held=\(NSEvent.pressedMouseButtons & 1)"); return done(false)
    }
    let z = max(0.1, pageZoom)
    let go: (NSImage?) -> Void = { [weak self] pic in
      guard let self = self else { return done(false) }
      guard NSEvent.pressedMouseButtons & 1 == 1, self.native == nil else { DragLog.note("app's drag: let go before it began"); return done(false) }
      let img = FileDrag.ghost(pic, name: name, items: items)
      let p = self.dragHost.convert(e.locationInWindow, from: nil), sz = img.size
      let all = FileDrag.providers(items).enumerated().map { i, pv -> NSDraggingItem in
        let d = NSDraggingItem(pasteboardWriter: pv)
        d.setDraggingFrame(NSRect(x: p.x - sz.width / 2 + CGFloat(i * 6), y: p.y - sz.height / 2 + CGFloat(i * 6), width: sz.width, height: sz.height), contents: i == 0 ? img : nil)
        return d
      }
      let src = NativeSource(self)
      self.nativeSrc = src; self.hotOK = false
      let s = self.dragHost.beginDraggingSession(with: all, event: e, source: src)
      s.animatesToStartingPositionsOnCancelOrFail = true
      self.native = s
      DragLog.note("app's drag began: \(items.map { "\($0["name"] ?? "-")" }) pasteboard items=\(s.draggingPasteboard.pasteboardItems?.count ?? -1) " + (s.draggingPasteboard.pasteboardItems ?? []).enumerated().map { "#\($0.offset) \($0.element.types.map { $0.rawValue })" }.joined(separator: " "))
      done(true)
    }
    guard r.width > 1, r.height > 1 else { return go(nil) }
    let c = WKSnapshotConfiguration()
    c.rect = CGRect(x: r.minX * z, y: r.minY * z, width: r.width * z, height: r.height * z)
    c.afterScreenUpdates = false
    takeSnapshot(with: c) { im, _ in go(im) }
  }
  fileprivate func nativeMoved(_ p: NSPoint) {
    if asking { askAgain = p; return }
    asking = true
    let q = pagePoint(p)
    evaluateJavaScript("window.__e11DragAt ? window.__e11DragAt(\(q.x), \(q.y), \(q.inside)) : false") { [weak self] r, _ in
      guard let self = self else { return }
      self.hotOK = q.inside && (r as? Bool) == true
      self.asking = false
      if let n = self.askAgain { self.askAgain = nil; if self.native != nil { self.nativeMoved(n) } }
    }
  }
  fileprivate func nativeEnded(_ p: NSPoint, _ op: NSDragOperation) {
    let q = pagePoint(p)
    DragLog.note("app's drag ended: operation=\(op.rawValue) (1 copy to Finder, 16 moved in the app, 0 turned down) over the page=\(q.inside)")
    native = nil; nativeSrc = nil; hotOK = false; askAgain = nil
    evaluateJavaScript("window.__e11DragEnd && window.__e11DragEnd(\(q.x), \(q.y), \(q.inside), \(op.rawValue))", completionHandler: nil)
    // (the press WebKit saw never had its letting go — given it, far off the page, so nothing under it is clicked)
    if let w = window, let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10000, y: -10000), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) { super.mouseUp(with: up) }
    lastMouse = nil
  }

  // ---- as the drop's destination: our drag over the window shows the page only its own data ----
  private func seen(_ d: NSDraggingInfo) -> NSDraggingInfo {
    guard let s = ours, let pb = ownPB, d.draggingSequenceNumber == s.draggingSequenceNumber else { return d }
    return OwnDrag(d, pb)
  }
  override func draggingEntered(_ d: NSDraggingInfo) -> NSDragOperation { isNative(d) ? (hotOK ? .move : []) : super.draggingEntered(seen(d)) }
  override func draggingUpdated(_ d: NSDraggingInfo) -> NSDragOperation { isNative(d) ? (hotOK ? .move : []) : super.draggingUpdated(seen(d)) }
  override func draggingExited(_ d: NSDraggingInfo?) { if isNative(d) { return }; super.draggingExited(d.map { seen($0) }) }
  override func prepareForDragOperation(_ d: NSDraggingInfo) -> Bool { isNative(d) ? hotOK : super.prepareForDragOperation(seen(d)) }
  override func performDragOperation(_ d: NSDraggingInfo) -> Bool {
    if isNative(d) { return hotOK }
    if ours != nil { FileDrag.inside = true }
    return super.performDragOperation(seen(d))
  }
  override func concludeDragOperation(_ d: NSDraggingInfo?) { if isNative(d) { return }; super.concludeDragOperation(d.map { seen($0) }) }
}

// the drag as the page is shown it: everything as it is, but the page's own data only
private final class OwnDrag: NSObject, NSDraggingInfo {
  let real: NSDraggingInfo, pb: NSPasteboard
  init(_ r: NSDraggingInfo, _ p: NSPasteboard) { real = r; pb = p }
  var draggingDestinationWindow: NSWindow? { real.draggingDestinationWindow }
  var draggingSourceOperationMask: NSDragOperation { real.draggingSourceOperationMask }
  var draggingLocation: NSPoint { real.draggingLocation }
  var draggedImageLocation: NSPoint { real.draggedImageLocation }
  var draggedImage: NSImage? { real.draggedImage }
  var draggingPasteboard: NSPasteboard { pb }
  var draggingSource: Any? { real.draggingSource }
  var draggingSequenceNumber: Int { real.draggingSequenceNumber }
  func slideDraggedImage(to p: NSPoint) { real.slideDraggedImage(to: p) }
  var draggingFormation: NSDraggingFormation { get { real.draggingFormation } set { real.draggingFormation = newValue } }
  var animatesToDestination: Bool { get { real.animatesToDestination } set { real.animatesToDestination = newValue } }
  var numberOfValidItemsForDrop: Int { get { real.numberOfValidItemsForDrop } set { real.numberOfValidItemsForDrop = newValue } }
  func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
    let keep = classes.filter { ObjectIdentifier($0) != ObjectIdentifier(NSFilePromiseReceiver.self) }
    if keep.isEmpty { return }
    real.enumerateDraggingItems(options: options, for: view, classes: keep, searchOptions: searchOptions, using: block)
  }
  var springLoadingHighlight: NSSpringLoadingHighlight { real.springLoadingHighlight }
  func resetSpringLoading() { real.resetSpringLoading() }
}

// (web/logo-wordmark.png's E11. part, white on clear: the menu bar item's picture)
let WORDMARK_B64 = "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"

/* Our files through Cloudflare R2 when dragged out to Finder (server 1.9.114+, consoler2.js — Haris 2026-11-20 23:13). The
   server sends a file asked for with r2=1 to R2's own short-lived address while R2 has a fast copy (else answers from the
   office, as before). The sign-in cookie, set on the request by hand, never goes along to R2: the redirect to another
   address is made as a fresh request with only that address. */
final class R2Redirect: NSObject, URLSessionTaskDelegate {
  static let shared = R2Redirect()
  func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest n: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    guard let u = n.url, u.host != task.originalRequest?.url?.host else { return completionHandler(n) }
    var c = URLRequest(url: u); c.httpMethod = n.httpMethod ?? "GET"; c.timeoutInterval = n.timeoutInterval
    completionHandler(c)
  }
  // one of the server's files (/__file/…) asked for with r2=1; anything else as it is
  static func ask(_ url: URL) -> URL {
    guard url.path.hasPrefix("/__file/"), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    var q = c.queryItems ?? []
    if !q.contains(where: { $0.name == "r2" }) { q.append(URLQueryItem(name: "r2", value: "1")) }
    c.queryItems = q
    return c.url ?? url
  }
}
