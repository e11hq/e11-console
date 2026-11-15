// E11 Console for Mac — the sidebar as the Mac's own (Mac app 12, Haris 2026-10-30), drawn here from what the page sends
// (command "sidebar": its rows, counts, clients, profile, Synced line), so anything the page adds to its own sidebar shows
// here without a new Mac app. Clicks go back to the page (window.__e11Side). The page hides its own sidebar meanwhile.
// Mac app 13 — as Claude's (Haris 2026-11-15 13:20–13:30, mock-ups S1–S4 approved): edge to edge; its top row the window's
// buttons, the sidebar button, ‹ › and light / dark as two buttons (no New task); the sidebar button hides it completely
// (the button and ‹ › stay over the page's top-left), and with the pointer on that button or the window's left edge it
// shows over the page until the pointer leaves; clicked, it's shown again. Shown at first, then as each person left it.
import Cocoa

// colours that follow the window's light / dark look
func dynColor(_ light: NSColor, _ dark: NSColor) -> NSColor {
  NSColor(name: nil) { ap in ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
}
let SIDE_ACCENT = NSColor(srgbRed: 0.486, green: 0.424, blue: 1, alpha: 1)
let SIDE_RED = NSColor(srgbRed: 0.898, green: 0.282, blue: 0.302, alpha: 1)
let SIDE_SEL = dynColor(NSColor(white: 0, alpha: 0.075), NSColor(white: 1, alpha: 0.11))
let SIDE_HOVER = dynColor(NSColor(white: 0, alpha: 0.04), NSColor(white: 1, alpha: 0.06))
let SIDE_BTN = dynColor(NSColor(white: 1, alpha: 0.75), NSColor(white: 1, alpha: 0.07))
let SIDE_BTN_EDGE = dynColor(NSColor(white: 0, alpha: 0.08), NSColor(white: 1, alpha: 0.12))
let SIDE_LINE = dynColor(NSColor(white: 0, alpha: 0.10), NSColor(white: 1, alpha: 0.12))

// the page's icon names → the Mac's own symbols (anything new: a plain circle until it's added here)
func sideSymbol(_ name: String, _ size: CGFloat = 14, _ weight: NSFont.Weight = .regular) -> NSImage? {
  let map = ["home": "house", "inbox": "tray", "shield": "checkmark.shield", "sun": "sun.max", "moon": "moon",
             "check-circle": "checkmark.circle", "theme-auto": "circle.lefthalf.filled", "cal": "calendar", "assets": "square.grid.2x2", "trash": "trash",
             "folder": "folder", "coin": "dollarsign.circle", "users": "person.2", "user": "person", "plus": "plus",
             "edit": "square.and.pencil", "compose": "square.and.pencil", "sidebar": "sidebar.left", "chev": "chevron.down",
             "download": "arrow.down.circle", "info": "info.circle", "logout": "rectangle.portrait.and.arrow.right",
             "reply": "arrowshape.turn.up.left", "link": "link", "bell": "bell", "star": "star", "copy": "doc.on.doc",
             "eye": "eye", "lock": "lock", "settings": "gearshape", "archive": "archivebox", "flag": "flag"]
  let sym = map[name] ?? (name.isEmpty ? "circle" : name)
  guard #available(macOS 11.0, *) else { return nil }
  let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
  return img?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
}
func sideColor(_ v: Any?) -> NSColor? {
  guard let a = v as? [NSNumber], a.count >= 3 else { return nil }
  return NSColor(srgbRed: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: 1)
}
func sideImage(_ v: Any?) -> NSImage? {
  guard let s = v as? String, let comma = s.firstIndex(of: ","), let d = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
  return NSImage(data: d)
}
func sideLabel(_ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .labelColor) -> NSTextField {
  let t = NSTextField(labelWithString: "")
  t.font = .systemFont(ofSize: size, weight: weight)
  t.textColor = color
  t.lineBreakMode = .byTruncatingTail
  t.maximumNumberOfLines = 1
  return t
}

class FlippedView: NSView { override var isFlipped: Bool { true } }

// One clickable thing in the sidebar (a row, a round button, the profile): hover and pressed looks, click, right-click
class SideHit: FlippedView {
  var onClick: (() -> Void)?
  var onMenu: ((NSEvent) -> Void)?
  var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
  var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }
  override var mouseDownCanMoveWindow: Bool { false }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }
  override func mouseEntered(with e: NSEvent) { hovering = true }
  override func mouseExited(with e: NSEvent) { hovering = false }
  override func mouseDown(with e: NSEvent) {
    if e.modifierFlags.contains(.control), let m = onMenu { m(e); return }
    pressed = true
  }
  override func mouseDragged(with e: NSEvent) { pressed = bounds.contains(convert(e.locationInWindow, from: nil)) }
  override func mouseUp(with e: NSEvent) {
    let inside = bounds.contains(convert(e.locationInWindow, from: nil))
    pressed = false
    if inside { onClick?() }
  }
  override func rightMouseDown(with e: NSEvent) { if let m = onMenu { m(e) } else { super.rightMouseDown(with: e) } }
}

// a plain button of the top row (the sidebar button, ‹ ›): Apple's rounded hover, no border
final class SideIcon: SideHit {
  let img = NSImageView()
  var onHover: ((Bool) -> Void)?
  var enabled = true { didSet { img.alphaValue = enabled ? 1 : 0.35 } }
  init(_ image: NSImage?, _ tip: String) {
    super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
    toolTip = tip
    img.imageScaling = .scaleNone
    img.contentTintColor = .secondaryLabelColor
    img.image = image
    addSubview(img)
  }
  required init?(coder: NSCoder) { nil }
  override func layout() { super.layout(); img.frame = bounds }
  override func mouseEntered(with e: NSEvent) { super.mouseEntered(with: e); onHover?(true) }
  override func mouseExited(with e: NSEvent) { super.mouseExited(with: e); onHover?(false) }
  override func mouseUp(with e: NSEvent) { if enabled { super.mouseUp(with: e) } else { pressed = false } }
  override func draw(_ r: NSRect) {
    guard enabled, hovering || pressed else { return }
    (pressed ? SIDE_SEL : SIDE_HOVER).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
  }
  // Claude's sidebar button: a rounded box with a short bar near its left (template: it follows light / dark)
  static let sidebarImage: NSImage = {
    let i = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
      NSColor.black.setStroke()
      let box = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 1.75, width: 16.5, height: 12.5), xRadius: 3.5, yRadius: 3.5); box.lineWidth = 1.5; box.stroke()
      let bar = NSBezierPath(); bar.move(to: NSPoint(x: 6.5, y: 5.6)); bar.line(to: NSPoint(x: 6.5, y: 10.4)); bar.lineWidth = 1.5; bar.lineCapStyle = .round; bar.stroke()
      return true
    }
    i.isTemplate = true
    return i
  }()
}

// the sidebar button and ‹ › — at the top of the shown sidebar, and over the page's top-left while it's hidden
final class SideTopRow: FlippedView {
  static let X: CGFloat = 84, W: CGFloat = 92, H: CGFloat = 28   // (from the window's left edge, after its buttons)
  let toggle = SideIcon(SideIcon.sidebarImage, "Hide sidebar")
  let back = SideIcon(sideSymbol("chevron.left", 12, .medium), "Back (⌘[)")
  let fwd = SideIcon(sideSymbol("chevron.right", 12, .medium), "Forward (⌘])")
  override init(frame: NSRect) {
    super.init(frame: frame)
    toggle.img.contentTintColor = .labelColor
    [toggle, back, fwd].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { nil }
  override func layout() {
    super.layout()
    toggle.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
    back.frame = NSRect(x: 38, y: 0, width: 22, height: 28)
    fwd.frame = NSRect(x: 62, y: 0, width: 22, height: 28)
  }
  func set(back b: Bool, fwd f: Bool, hidden: Bool) {
    back.enabled = b; fwd.enabled = f
    toggle.toolTip = hidden ? "Show sidebar" : "Hide sidebar"
  }
}

// the window's left edge while the sidebar is hidden: the pointer there shows it
final class SideEdge: NSView {
  var onEnter: (() -> Void)?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }
  override func mouseEntered(with e: NSEvent) { onEnter?() }
}

// one row: an icon / colour dot / logo, the name and a count (red badge for what needs attention)
final class SideRow: SideHit {
  let icon = NSImageView(), title = sideLabel(13.5), count = sideLabel(12.5, .regular, .tertiaryLabelColor)
  let badge = FlippedView(), badgeText = sideLabel(11, .semibold, .white)
  var dot: NSColor?, logo: NSImage?, selected = false, hot = false
  // drag to reorder (clients, Admins: the page says which rows can be dragged)
  var key = "", canDrag = false
  var lifted = false { didSet { if lifted != oldValue { needsDisplay = true; shadowed(lifted) } } }
  var onDrag: ((SideRow, NSEvent, Int) -> Void)?   // 0 picked up · 1 moved · 2 let go
  private var downAt: NSPoint?, dragging = false
  override func mouseDown(with e: NSEvent) { downAt = e.locationInWindow; dragging = false; super.mouseDown(with: e) }
  override func mouseDragged(with e: NSEvent) {
    guard canDrag, let d = downAt else { super.mouseDragged(with: e); return }
    if !dragging && abs(e.locationInWindow.y - d.y) > 4 { dragging = true; pressed = false; onDrag?(self, e, 0) }
    if dragging { onDrag?(self, e, 1) } else { super.mouseDragged(with: e) }
  }
  override func mouseUp(with e: NSEvent) {
    downAt = nil
    if dragging { dragging = false; pressed = false; onDrag?(self, e, 2); return }
    super.mouseUp(with: e)
  }
  private func shadowed(_ on: Bool) {
    wantsLayer = true
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = on ? 0.25 : 0
    layer?.shadowRadius = on ? 8 : 0
    layer?.shadowOffset = CGSize(width: 0, height: -2)
  }
  init() {
    super.init(frame: .zero)
    icon.imageScaling = .scaleNone
    icon.contentTintColor = SIDE_ACCENT
    badge.wantsLayer = true
    badge.layer?.backgroundColor = SIDE_RED.cgColor
    badgeText.alignment = .center
    badge.addSubview(badgeText)
    [icon, title, count, badge].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { nil }
  func set(_ e: [String: Any]) {
    let name = e["title"] as? String ?? ""
    title.stringValue = name
    selected = (e["sel"] as? Bool) == true
    title.font = .systemFont(ofSize: 13.5, weight: selected ? .semibold : .regular)
    dot = sideColor(e["c"]); logo = sideImage(e["logo"])
    icon.image = dot == nil && logo == nil ? sideSymbol(e["ic"] as? String ?? "", 14) : nil
    let n = e["n"] as? String ?? ""
    hot = (e["hot"] as? Bool) == true && !n.isEmpty
    count.stringValue = hot ? "" : n
    badgeText.stringValue = n
    badge.isHidden = !hot
    key = e["k"] as? String ?? ""
    canDrag = (e["drag"] as? Bool) == true
    needsLayout = true; needsDisplay = true
  }
  override func layout() {
    super.layout()
    let h = bounds.height, w = bounds.width
    icon.frame = NSRect(x: 7, y: 0, width: 22, height: h)
    var right = w - 9
    if !badge.isHidden {
      badgeText.sizeToFit()
      let bw = max(22, ceil(badgeText.frame.width) + 12)
      badge.frame = NSRect(x: right - bw + 3, y: (h - 18) / 2, width: bw, height: 18)
      badge.layer?.cornerRadius = 9
      badgeText.frame = NSRect(x: 0, y: (18 - badgeText.frame.height) / 2, width: bw, height: badgeText.frame.height)
      right = badge.frame.minX - 6
    } else if !count.stringValue.isEmpty {
      count.sizeToFit()
      count.frame = NSRect(x: right - count.frame.width, y: (h - count.frame.height) / 2, width: count.frame.width, height: count.frame.height)
      right = count.frame.minX - 6
    }
    title.sizeToFit()
    let th = title.frame.height
    title.frame = NSRect(x: 35, y: (h - th) / 2, width: max(0, right - 35), height: th)
  }
  override func draw(_ r: NSRect) {
    if lifted {
      // (picked up: a solid card of the panel's own colour, so it reads above the others)
      dynColor(NSColor(white: 0.97, alpha: 1), NSColor(white: 0.22, alpha: 1)).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    }
    if selected || hovering || pressed {
      let fill: NSColor = pressed ? SIDE_SEL : selected ? SIDE_SEL : SIDE_HOVER
      fill.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    }
    let cx: CGFloat = 18, cy = bounds.midY
    if let l = logo {
      let s: CGFloat = 18
      let rect = NSRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5).addClip()
      l.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      NSGraphicsContext.restoreGraphicsState()
    } else if let d = dot {
      let s: CGFloat = 10
      d.setFill(); NSBezierPath(ovalIn: NSRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)).fill()
    }
  }
}

// a heading ("Clients", "Library") with an optional +
final class SideHead: FlippedView {
  let title = sideLabel(11, .semibold, .secondaryLabelColor)
  let add = SideHit()
  let plus = NSImageView()
  override init(frame: NSRect) {
    super.init(frame: frame)
    plus.imageScaling = .scaleNone; plus.contentTintColor = .secondaryLabelColor; plus.image = sideSymbol("plus", 11, .semibold)
    add.addSubview(plus)
    addSubview(title); addSubview(add)
  }
  required init?(coder: NSCoder) { nil }
  override func layout() {
    super.layout()
    title.sizeToFit()
    title.frame = NSRect(x: 9, y: bounds.height - title.frame.height - 4, width: bounds.width - 40, height: title.frame.height)
    add.frame = NSRect(x: bounds.width - 26, y: bounds.height - 24, width: 22, height: 22)
    plus.frame = add.bounds
  }
}

// a thin line (the footer's top edge)
final class SideLine: FlippedView { override func draw(_ r: NSRect) { SIDE_LINE.setFill(); bounds.fill() } }

// the profile at the bottom: picture or initials, name, role
final class SideMe: SideHit {
  let name = sideLabel(13, .semibold), role = sideLabel(11.5, .regular, .secondaryLabelColor)
  let chev = NSImageView()
  var photo: NSImage?, initials = "", color = NSColor.systemRed
  override init(frame: NSRect) {
    super.init(frame: frame)
    chev.imageScaling = .scaleNone; chev.contentTintColor = .tertiaryLabelColor; chev.image = sideSymbol("chev", 10, .semibold)
    [name, role, chev].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { nil }
  var avatarRect: NSRect { NSRect(x: 8, y: (bounds.height - 30) / 2, width: 30, height: 30) }
  override func layout() {
    super.layout()
    let x = avatarRect.maxX + 10, w = bounds.width - x - 26
    name.sizeToFit(); role.sizeToFit()
    let total = name.frame.height + role.frame.height
    name.frame = NSRect(x: x, y: (bounds.height - total) / 2, width: w, height: name.frame.height)
    role.frame = NSRect(x: x, y: name.frame.maxY, width: w, height: role.frame.height)
    chev.frame = NSRect(x: bounds.width - 24, y: 0, width: 16, height: bounds.height)
  }
  override func draw(_ r: NSRect) {
    if hovering || pressed { (pressed ? SIDE_SEL : SIDE_HOVER).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill() }
    let a = avatarRect
    let clip = NSBezierPath(ovalIn: a)
    if let p = photo {
      NSGraphicsContext.saveGraphicsState(); clip.addClip()
      p.draw(in: a, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      NSGraphicsContext.restoreGraphicsState()
    } else {
      color.setFill(); clip.fill()
      let s = NSAttributedString(string: initials, attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: NSColor.white])
      let sz = s.size()
      s.draw(at: NSPoint(x: a.midX - sz.width / 2, y: a.midY - sz.height / 2))
    }
  }
}

// the top row and empty parts of the panel move the window (double-click zooms), like a title bar
final class SideInner: FlippedView {
  override var mouseDownCanMoveWindow: Bool { true }
  override func mouseDown(with e: NSEvent) {
    if e.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: e) }
  }
}

protocol SidebarHost: AnyObject {
  func sideCall(_ args: [String: Any], _ done: ((Any?) -> Void)?)
  func sideLayoutChanged(animated: Bool)
}

final class Sidebar: NSView {
  static let WIDE: CGFloat = 244, INSET: CGFloat = 8, TOP: CGFloat = 44
  weak var host: SidebarHost?
  var on = false
  var hiddenMode = false          // (the page's "collapsed": hidden completely)
  private(set) var peeking = false
  var shown: Bool { on && (!hiddenMode || peeking) }
  let row = SideTopRow(), hiddenRow = SideTopRow(), edgeHot = SideEdge()
  let themeSeg = NSSegmentedControl()
  private var peekArmed = true, peekEnd: DispatchWorkItem?
  private(set) var model: [String: Any] = [:]
  let inner = SideInner()
  private var backdrop: NSView!
  private let edge = NSBox()   // (the line between the sidebar and the page)
  let scroll = NSScrollView()
  let list = FlippedView()
  let footLine = SideLine()
  let me = SideMe()
  let syncDot = FlippedView(), syncText = sideLabel(11.5, .regular, .secondaryLabelColor), copy = sideLabel(11, .regular, .tertiaryLabelColor)
  let sync = SideHit()
  private var rows: [NSView] = []
  var menuToken = 0
  // a row being dragged: it, the run of rows it can move among, where those sit, where it was grabbed
  private var drag: (row: SideRow, from: Int, group: [SideRow], slots: [CGFloat], grab: CGFloat)?
  private var pendingModel: [String: Any]?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    // edge to edge (Haris 2026-11-15 13:06 / 13:08: "can we make the whole sidebar edge to edge so its not floating on top"):
    // Apple's sidebar material from the window's top, left and bottom edges to a thin line beside the page — what's in it
    // stays exactly where it was (8 in from those edges), so nothing inside moves
    let v = NSVisualEffectView()
    v.material = .sidebar; v.blendingMode = .behindWindow; v.state = .followsWindowActiveState
    v.addSubview(inner)
    backdrop = v
    addSubview(backdrop)
    edge.boxType = .separator
    addSubview(edge)
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.borderType = .noBorder
    scroll.documentView = list
    scroll.contentView.drawsBackground = false
    // the clients fade away at the list's edges instead of being cut (only where there's more to scroll to)
    scroll.wantsLayer = true
    scroll.layer?.mask = fade
    scroll.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    [scroll, row, themeSeg, footLine, me, sync, copy].forEach { inner.addSubview($0) }
    // light / dark: Apple's two-button control (as Claude's pair)
    themeSeg.segmentCount = 2
    themeSeg.setImage(sideSymbol("sun", 12.5), forSegment: 0); themeSeg.setImage(sideSymbol("moon", 12.5), forSegment: 1)
    themeSeg.setToolTip("Light", forSegment: 0); themeSeg.setToolTip("Dark", forSegment: 1)
    themeSeg.trackingMode = .selectOne
    themeSeg.controlSize = .small
    themeSeg.target = self; themeSeg.action = #selector(pickTheme)
    for r in [row, hiddenRow] {
      r.toggle.onClick = { [weak self] in self?.host?.sideCall(["kind": "collapse"], nil) }
      r.back.onClick = { [weak self] in self?.host?.sideCall(["kind": "back"], nil) }
      r.fwd.onClick = { [weak self] in self?.host?.sideCall(["kind": "fwd"], nil) }
    }
    // hidden: the pointer on the sidebar button (once it has left it after hiding) or the left edge shows it over the page
    hiddenRow.toggle.onHover = { [weak self] inside in
      guard let self = self else { return }
      if inside { if self.peekArmed { self.peek(true) } } else { self.peekArmed = true }
    }
    edgeHot.onEnter = { [weak self] in self?.peek(true) }
    sync.addSubview(syncDot); sync.addSubview(syncText)
    syncDot.wantsLayer = true; syncDot.layer?.cornerRadius = 3.5
    me.onClick = { [weak self] in self?.openMenu("me", from: self?.me, at: nil) }
    me.onMenu = { [weak self] e in self?.openMenu("me", from: self?.me, at: e) }
    sync.onClick = { [weak self] in self?.host?.sideCall(["kind": "sync"], nil) }
    isHidden = true
  }
  required init?(coder: NSCoder) { nil }


  var width: CGFloat { Sidebar.WIDE }
  // where the page starts (the window's left edge to the page): beside the sidebar when it's shown, else the edge
  var pageX: CGFloat { on && !hiddenMode ? Sidebar.INSET + width : 0 }
  @objc func pickTheme() { host?.sideCall(["kind": "theme", "mode": themeSeg.selectedSegment == 0 ? "light" : "dark"], nil) }

  /* ---------- hidden: shown over the page while the pointer is on it ---------- */
  func peek(_ on: Bool) {
    peekEnd?.cancel(); peekEnd = nil
    guard self.on, hiddenMode, on != peeking else { return }
    peeking = on
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = on ? 0.22 : 0
    layer?.shadowRadius = on ? 20 : 0
    layer?.shadowOffset = CGSize(width: 6, height: 0)
    host?.sideLayoutChanged(animated: true)
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }
  override func mouseEntered(with e: NSEvent) { peekEnd?.cancel(); peekEnd = nil }
  override func mouseExited(with e: NSEvent) {
    guard peeking else { return }
    let w = DispatchWorkItem { [weak self] in self?.peek(false) }
    peekEnd = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
  }

  /* ---------- the page's model ---------- */
  func apply(_ m: [String: Any]) {
    if drag != nil { pendingModel = m; return }   // (after the drag)
    let wasOn = on, wasHidden = hiddenMode
    model = m
    on = (m["on"] as? Bool) == true
    hiddenMode = (m["collapsed"] as? Bool) == true
    if !hiddenMode { peeking = false; layer?.shadowOpacity = 0 }
    if hiddenMode && !wasHidden { peekArmed = false; peeking = false }   // (just hidden with the pointer on the button: not shown again until it leaves)
    hiddenRow.isHidden = !(on && hiddenMode); edgeHot.isHidden = hiddenRow.isHidden
    guard on else { isHidden = true; if wasOn { host?.sideLayoutChanged(animated: false) }; return }
    themeSeg.selectedSegment = (m["light"] as? Bool) == true ? 0 : 1
    let b = (m["back"] as? Bool) == true, f = (m["fwd"] as? Bool) == true
    row.set(back: b, fwd: f, hidden: hiddenMode); hiddenRow.set(back: b, fwd: f, hidden: hiddenMode)
    buildRows()
    let me0 = m["me"] as? [String: Any] ?? [:]
    me.name.stringValue = me0["name"] as? String ?? ""
    me.role.stringValue = me0["role"] as? String ?? ""
    me.photo = sideImage(me0["photo"])
    me.initials = me0["initials"] as? String ?? ""
    me.color = sideColor(me0["color"]) ?? .systemRed
    me.toolTip = "Profile, team and sign out"
    me.needsLayout = true; me.needsDisplay = true
    let s = m["sync"] as? [String: Any] ?? [:]
    syncText.stringValue = s["text"] as? String ?? ""
    syncDot.layer?.backgroundColor = (sideColor(s["rgb"]) ?? .systemGreen).cgColor
    sync.toolTip = s["tip"] as? String
    copy.stringValue = m["copy"] as? String ?? ""
    if !wasOn || wasHidden != hiddenMode { host?.sideLayoutChanged(animated: wasOn) }
    needsLayout = true
    inner.needsLayout = true
  }

  private func buildRows() {
    rows.forEach { $0.removeFromSuperview() }
    rows = []
    for e in model["items"] as? [[String: Any]] ?? [] {
      if (e["t"] as? String) == "h" {
        let h = SideHead()
        h.title.stringValue = (e["title"] as? String ?? "")
        let add = e["add"] as? String
        h.add.isHidden = add == nil
        h.add.toolTip = e["addTip"] as? String
        if let k = add { h.add.onClick = { [weak self] in self?.host?.sideCall(["kind": "go", "key": k], nil) } }
        rows.append(h)
      } else {
        let r = SideRow()
        r.set(e)
        let k = e["k"] as? String ?? ""
        r.onClick = { [weak self] in self?.host?.sideCall(["kind": "go", "key": k], nil) }
        r.onDrag = { [weak self] row, ev, phase in self?.dragRow(row, ev, phase) }
        if (e["menu"] as? Bool) == true { r.onMenu = { [weak self, weak r] ev in self?.openMenu(k, from: r, at: ev) } }
        rows.append(r)
      }
    }
    // only the clients scroll (Haris, 2026-10-31): the rows above their heading stay at the top, the ones after them
    // (Library) at the bottom
    let firstClient = rows.firstIndex { r in ((r as? SideRow)?.key ?? "").hasPrefix("project:") || (r as? SideRow)?.key == "act:new-project" }
    if let fc = firstClient {
      let start = fc
      let end = rows[start...].firstIndex { $0 is SideHead } ?? rows.count
      mid = start..<end
    } else { mid = rows.count..<rows.count }
    for (i, v) in rows.enumerated() { let into: NSView = mid.contains(i) ? list : inner; into.addSubview(v) }
  }
  private var mid: Range<Int> = 0..<0
  private func rowHeight(_ v: NSView, first: Bool) -> CGFloat {
    if v is SideHead { return first ? 22 : 30 }
    return 30
  }
  private func place(_ v: NSView, _ y: CGFloat, _ W: CGFloat) {
    v.frame = v is SideHead ? NSRect(x: 10, y: y, width: W - 20, height: v.frame.height) : NSRect(x: 10, y: y, width: W - 20, height: 30)
    v.needsLayout = true
  }

  /* ---------- layout ---------- */
  override func layout() {
    super.layout()
    backdrop.frame = bounds
    inner.frame = NSRect(x: Sidebar.INSET, y: Sidebar.INSET, width: max(0, bounds.width - Sidebar.INSET), height: max(0, bounds.height - Sidebar.INSET * 2))
    edge.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
    let W = inner.bounds.width, H = inner.bounds.height
    // top row: the window's buttons at its left (placed by the app), then the sidebar button and ‹ ›; light / dark at its right
    row.frame = NSRect(x: SideTopRow.X - Sidebar.INSET, y: (Sidebar.TOP - SideTopRow.H) / 2, width: SideTopRow.W, height: SideTopRow.H)
    themeSeg.sizeToFit()
    themeSeg.frame = NSRect(x: W - 10 - themeSeg.frame.width, y: (Sidebar.TOP - themeSeg.frame.height) / 2, width: themeSeg.frame.width, height: themeSeg.frame.height)
    let y = Sidebar.TOP + 8
    // the footer
    let footH: CGFloat = 92
    let footY = H - footH
    footLine.frame = NSRect(x: 19, y: footY, width: W - 38, height: 0.5)
    me.frame = NSRect(x: 10, y: footY + 8, width: W - 20, height: 42)
    do {
      sync.frame = NSRect(x: 10, y: me.frame.maxY + 2, width: W - 20, height: 18)
      syncDot.frame = NSRect(x: 11, y: 5.5, width: 7, height: 7)
      syncText.sizeToFit()
      syncText.frame = NSRect(x: 25, y: (18 - syncText.frame.height) / 2, width: sync.bounds.width - 30, height: syncText.frame.height)
      copy.sizeToFit()
      copy.frame = NSRect(x: 20, y: sync.frame.maxY + 1, width: W - 40, height: copy.frame.height)
    }
    // the rows above the clients at the top, the ones after them at the bottom, the clients scrolling between
    let lo = min(mid.lowerBound, rows.count), hi = min(mid.upperBound, rows.count)
    var ty = y
    for (i, v) in rows[0..<lo].enumerated() {
      let hh = rowHeight(v, first: i == 0)
      if v is SideHead { v.frame.size.height = hh }
      place(v, ty, W); ty += hh
    }
    let after = Array(rows[hi...])
    var bh: CGFloat = 0
    for v in after { bh += rowHeight(v, first: false) }
    var by = footY - 6 - bh
    for v in after {
      let hh = rowHeight(v, first: false)
      if v is SideHead { v.frame.size.height = hh }
      place(v, by, W); by += hh
    }
    scroll.frame = NSRect(x: 0, y: ty, width: W, height: max(0, footY - 6 - bh - ty))
    if drag != nil { return }   // (the clients stay where the drag has them)
    var ly: CGFloat = 0
    for v in rows[lo..<hi] {
      let hh = rowHeight(v, first: false)
      place(v, ly, W); ly += hh
    }
    list.frame = NSRect(x: 0, y: 0, width: W, height: max(ly + 4, scroll.contentSize.height))
    updateFade()
  }
  private let fade = CAGradientLayer()
  @objc private func scrolled(_ n: Notification) {
    updateFade()
    // (scrolling under a still pointer: only the row now under it looks hovered — the ones it passed over lit up and
    //  stayed lit, Haris 2026-10-31)
    let at = window?.mouseLocationOutsideOfEventStream
    for case let r as SideHit in list.subviews { r.hovering = at.map { r.bounds.contains(r.convert($0, from: nil)) } ?? false }
  }
  private func updateFade() {
    let h = scroll.bounds.height
    guard h > 0 else { return }
    let y = scroll.contentView.bounds.origin.y, end = list.frame.height - scroll.contentView.bounds.height
    let more = (above: y > 1, below: y < end - 1)
    let f = NSNumber(value: Double(min(28, h / 3) / h))
    let solid = NSColor.black.cgColor, gone = NSColor.clear.cgColor
    CATransaction.begin(); CATransaction.setDisableActions(true)
    fade.frame = scroll.bounds
    // (the scroll view's layer runs bottom to top)
    fade.startPoint = CGPoint(x: 0.5, y: 0); fade.endPoint = CGPoint(x: 0.5, y: 1)
    let bottomFirst = !scroll.isFlipped
    let low = bottomFirst ? more.below : more.above, high = bottomFirst ? more.above : more.below
    fade.colors = [low ? gone : solid, solid, solid, high ? gone : solid]
    fade.locations = [0, f, NSNumber(value: 1 - f.doubleValue), 1]
    CATransaction.commit()
  }

  /* ---------- drag to reorder: picked up, the others slide aside, let go: the page saves the new order ---------- */
  private func nearest(_ y: CGFloat, _ slots: [CGFloat]) -> Int {
    var best = 0
    for (i, s) in slots.enumerated() where abs(s - y) < abs(slots[best] - y) { best = i }
    return best
  }
  func dragRow(_ r: SideRow, _ e: NSEvent, _ phase: Int) {
    let p = list.convert(e.locationInWindow, from: nil)
    switch phase {
    case 0:
      guard let i = rows.firstIndex(where: { $0 === r }) else { return }
      var a = i, b = i
      while a > 0, let x = rows[a - 1] as? SideRow, x.canDrag { a -= 1 }
      while b < rows.count - 1, let x = rows[b + 1] as? SideRow, x.canDrag { b += 1 }
      let group = rows[a...b].compactMap { $0 as? SideRow }
      guard group.count > 1 else { return }
      drag = (r, a, group, group.map { $0.frame.minY }, p.y - r.frame.minY)
      list.addSubview(r, positioned: .above, relativeTo: nil)
      r.lifted = true
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    case 1:
      guard let d = drag else { return }
      r.frame.origin.y = min(max(p.y - d.grab, d.slots.first!), d.slots.last!)
      let target = nearest(r.frame.minY, d.slots)
      let others = d.group.filter { $0 !== r }
      var j = 0
      NSAnimationContext.runAnimationGroup { c in
        c.duration = 0.15; c.allowsImplicitAnimation = true
        for (k, y) in d.slots.enumerated() where k != target { others[j].animator().frame.origin.y = y; j += 1 }
      }
    default:
      guard let d = drag else { return }
      let target = nearest(r.frame.minY, d.slots)
      var order = d.group.filter { $0 !== r }
      order.insert(r, at: target)
      NSAnimationContext.runAnimationGroup({ c in
        c.duration = 0.15; c.allowsImplicitAnimation = true
        r.animator().frame.origin.y = d.slots[target]
      }) { r.lifted = false }
      rows.replaceSubrange(d.from..<(d.from + d.group.count), with: order as [NSView])
      drag = nil
      if order.map({ $0.key }) != d.group.map({ $0.key }) { host?.sideCall(["kind": "reorder", "keys": order.map { $0.key }], nil) }
      if let m = pendingModel { pendingModel = nil; apply(m) }
    }
  }

  /* ---------- menus: the page's own options, shown as the Mac's menu ---------- */
  func openMenu(_ key: String, from v: NSView?, at ev: NSEvent?) {
    guard let v = v, let win = window else { return }
    let inWin = v.convert(v.bounds, to: nil)
    let yTop = win.contentView.map { $0.bounds.height - inWin.maxY } ?? 0
    host?.sideCall(["kind": "menu", "key": key, "y": Double(yTop + inWin.height)]) { [weak self] r in
      guard let self = self, let s = r as? String, !s.isEmpty, let d = s.data(using: .utf8),
            let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
      let menu = self.makeMenu(m)
      if let e = ev { NSMenu.popUpContextMenu(menu, with: e, for: v) }
      else {
        // (low in the window — the profile — it opens upwards, inside the window; higher up, downwards)
        let up = inWin.midY < win.frame.height / 2, h = menu.size.height
        let y: CGFloat = v.isFlipped ? (up ? -h - 4 : v.bounds.height + 4) : (up ? v.bounds.height + h + 4 : -4)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: v)
      }
    }
  }
  private func makeMenu(_ m: [String: Any]) -> NSMenu {
    let id = (m["id"] as? NSNumber)?.intValue ?? 0
    let menu = NSMenu()
    menu.autoenablesItems = false
    var lastSep = true
    for it in m["list"] as? [[String: Any]] ?? [] {
      if it["sep"] != nil { if !lastSep { menu.addItem(.separator()); lastSep = true }; continue }
      let label = it["label"] as? String ?? ""
      let mi = NSMenuItem(title: label, action: #selector(pick(_:)), keyEquivalent: "")
      mi.target = self
      mi.representedObject = ["kind": "pick", "m": id, "i": it["i"] ?? 0] as [String: Any]
      if let ic = it["icon"] as? String, !ic.isEmpty { mi.image = sideSymbol(ic, 13) }
      if (it["danger"] as? Bool) == true {
        mi.attributedTitle = NSAttributedString(string: label, attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)])
        if let img = mi.image { mi.image = img.tinted(.systemRed) }
      }
      menu.addItem(mi); lastSep = false
    }
    // the client's colours as a row of dots right in the menu, like Finder's tags (a submenu of them came out
    // empty — Haris, 2026-10-31); the current one ringed
    if let colors = m["colors"] as? [String], !colors.isEmpty {
      let row = SwatchRow(colors: colors, cur: m["cur"] as? String)
      row.onPick = { [weak self] c in self?.host?.sideCall(["kind": "swatch", "m": id, "c": c], nil) }
      let ci = NSMenuItem()
      ci.view = row
      // (after the first option, as on the page)
      menu.insertItem(ci, at: min(1, menu.numberOfItems))
    }
    while let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    return menu
  }
  @objc func pick(_ sender: NSMenuItem) {
    guard let a = sender.representedObject as? [String: Any] else { return }
    host?.sideCall(a, nil)
  }
  static func hexColor(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
  }
  static func swatch(_ hex: String) -> NSImage {
    let col = hexColor(hex)
    return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in col.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill(); return true }
  }

  // for the self-test: what's shown
  func snapshot() -> [String: Any] {
    let names = rows.compactMap { ($0 as? SideRow)?.title.stringValue }
    let heads = rows.compactMap { ($0 as? SideHead)?.title.stringValue }
    let hot = rows.compactMap { $0 as? SideRow }.filter { !$0.badge.isHidden }.map { $0.badgeText.stringValue }
    let glass = false   // (edge to edge: Apple's sidebar material, not a floating glass panel)
    return ["on": on, "hidden": hiddenMode, "shown": shown, "width": frame.width, "x": frame.minX, "rows": names, "heads": heads, "hot": hot,
            "me": me.name.stringValue, "sync": syncText.stringValue, "copy": copy.stringValue, "glass": glass]
  }
}

// a row of colour dots inside a menu: click one to pick it (the menu closes)
final class SwatchRow: NSView {
  let colors: [String], cur: String?
  var onPick: ((String) -> Void)?
  private var hover = -1 { didSet { if hover != oldValue { needsDisplay = true } } }
  static let D: CGFloat = 16, GAP: CGFloat = 10, PAD: CGFloat = 14
  init(colors: [String], cur: String?) {
    self.colors = colors; self.cur = cur?.lowercased()
    super.init(frame: NSRect(x: 0, y: 0, width: SwatchRow.PAD * 2 + CGFloat(colors.count) * (SwatchRow.D + SwatchRow.GAP) - SwatchRow.GAP, height: 32))
  }
  required init?(coder: NSCoder) { nil }
  private func rect(_ i: Int) -> NSRect {
    NSRect(x: SwatchRow.PAD + CGFloat(i) * (SwatchRow.D + SwatchRow.GAP), y: (bounds.height - SwatchRow.D) / 2, width: SwatchRow.D, height: SwatchRow.D)
  }
  private func index(_ e: NSEvent) -> Int {
    let p = convert(e.locationInWindow, from: nil)
    for i in colors.indices where rect(i).insetBy(dx: -GAPHALF, dy: -6).contains(p) { return i }
    return -1
  }
  private var GAPHALF: CGFloat { SwatchRow.GAP / 2 }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
  }
  override func mouseMoved(with e: NSEvent) { hover = index(e) }
  override func mouseExited(with e: NSEvent) { hover = -1 }
  override func mouseUp(with e: NSEvent) {
    let i = index(e)
    guard i >= 0 else { return }
    onPick?(colors[i])
    enclosingMenuItem?.menu?.cancelTracking()
  }
  override func draw(_ r: NSRect) {
    for (i, c) in colors.enumerated() {
      let rc = rect(i)
      if c.lowercased() == cur || i == hover {
        let ring = NSBezierPath(ovalIn: rc.insetBy(dx: -3, dy: -3))
        ring.lineWidth = 1.5
        (c.lowercased() == cur ? NSColor.labelColor : NSColor.tertiaryLabelColor).setStroke(); ring.stroke()
      }
      Sidebar.hexColor(c).setFill(); NSBezierPath(ovalIn: rc).fill()
    }
  }
}

extension NSImage {
  func tinted(_ c: NSColor) -> NSImage {
    let img = self.copy() as! NSImage
    img.isTemplate = false
    img.lockFocus()
    c.set()
    NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
    img.unlockFocus()
    return img
  }
}
