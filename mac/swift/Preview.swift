// E11 Console for Mac — the file preview drawn by the app itself (Mac app 13, Haris 2026-11-15 16:06: board P1–P3 "Preview,
// the Mac app's own" approved), as E11 Talk's photo viewer: over the whole window on black, the file flying out of its
// thumbnail and back; its name and details at the top with Copy Link · Download · ••• · ✕ on Apple's glass; a photo in
// Apple's zooming view, a PDF in Apple's PDF view, a video or a sound in Apple's player, Word / Excel / PowerPoint as the
// server's page pictures, text as text, anything else its picture and Download; ‹ › (as the pointer moves), ← →, a
// two-finger swipe or the strip of thumbnails to move; Esc, Space or ✕ to close; everything round the file fading away
// after a moment still. The page sends the files (the same as the iPhone app's: command preview / previewSet) and does
// Copy / Download / ••• itself (window.__e11Preview); files are fetched with the app's own sign-in (its cookies).
import Cocoa
import AVKit
import PDFKit
import WebKit
import UniformTypeIdentifiers

/* ---------- fetching from the server with the app's sign-in ---------- */
enum MacLoad {
  static let cache = NSCache<NSString, NSData>()
  static var cookies: [HTTPCookie] = []
  static func refreshCookies(_ store: WKHTTPCookieStore, _ then: @escaping () -> Void) {
    store.getAllCookies { c in cookies = c; DispatchQueue.main.async { then() } }
  }
  static func mine(_ url: URL) -> [HTTPCookie] {
    let host = url.host ?? ""
    return cookies.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return host == d || host.hasSuffix("." + d) }
  }
  static func data(_ s: String?, _ done: @escaping (Data?) -> Void) {
    guard let s = s, !s.isEmpty, let url = URL(string: s) else { return done(nil) }
    if let d = cache.object(forKey: s as NSString) { return done(d as Data) }
    var r = URLRequest(url: url)
    r.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: mine(url))
    URLSession.shared.dataTask(with: r) { data, resp, _ in
      let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
      let d = ok ? data : nil
      if let d = d { cache.setObject(d as NSData, forKey: s as NSString) }
      DispatchQueue.main.async { done(d) }
    }.resume()
  }
  static func image(_ s: String?, _ done: @escaping (NSImage?) -> Void) { data(s) { d in done(d.flatMap { NSImage(data: $0) }) } }
}

/* ---------- Apple's glass: Liquid Glass on macOS 26 (NSGlassEffectView — Haris 2026-11-15 16:23: "the buttons are not
   glass"), the HUD material before it ---------- */
func pvGlass() -> NSView {
  #if compiler(>=6.2)
  if #available(macOS 26.0, *) { let g = NSGlassEffectView(); g.appearance = NSAppearance(named: .darkAqua); return g }
  #endif
  let f = NSVisualEffectView(); f.material = .hudWindow; f.blendingMode = .withinWindow; f.state = .active; f.appearance = NSAppearance(named: .vibrantDark)
  f.wantsLayer = true; f.layer?.masksToBounds = true
  return f
}
func pvRound(_ v: NSView, _ r: CGFloat) {
  #if compiler(>=6.2)
  if #available(macOS 26.0, *), let g = v as? NSGlassEffectView { g.cornerRadius = r; return }
  #endif
  v.layer?.cornerRadius = r
}
// what sits on a glass: the glass's own content view (Liquid Glass), or simply inside it
func pvPut(_ v: NSView, in g: NSView) {
  #if compiler(>=6.2)
  if #available(macOS 26.0, *), let gl = g as? NSGlassEffectView { gl.contentView = v; return }
  #endif
  g.addSubview(v)
}
final class PvButton: NSView {
  let fx = pvGlass(), label = NSTextField(labelWithString: ""), icon = NSImageView()
  var onClick: (() -> Void)?
  private var hover = false { didSet { alphaValue = hover ? 1 : 0.92 } }
  init(symbol: String, title: String? = nil, tip: String) {
    super.init(frame: .zero)
    addSubview(fx)
    icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
    icon.contentTintColor = .white; icon.imageScaling = .scaleNone
    addSubview(icon)
    label.stringValue = title ?? ""; label.font = .systemFont(ofSize: 13); label.textColor = .white; label.isHidden = title == nil
    addSubview(label)
    toolTip = tip
  }
  required init?(coder: NSCoder) { nil }
  var fit: CGFloat { label.isHidden ? 34 : 14 + 16 + 7 + ceil(label.intrinsicContentSize.width) + 14 }
  override func layout() {
    super.layout()
    fx.frame = bounds; pvRound(fx, bounds.height / 2)
    if label.isHidden { icon.frame = bounds } else {
      icon.frame = NSRect(x: 14, y: 0, width: 16, height: bounds.height)
      let s = label.intrinsicContentSize
      label.frame = NSRect(x: 37, y: (bounds.height - s.height) / 2, width: ceil(s.width) + 2, height: s.height)
    }
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas(); trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }
  override func mouseEntered(with e: NSEvent) { hover = true }
  override func mouseExited(with e: NSEvent) { hover = false }
  override func mouseDown(with e: NSEvent) {}
  override func mouseUp(with e: NSEvent) { if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() } }
}

/* ---------- a photo: Apple's zooming scroll view (pinch, double-click), a sideways swipe moves on when not zoomed ---------- */
final class PvZoom: NSScrollView {
  let img = NSImageView()
  var onSwipe: ((Int) -> Void)?
  private var swipeX: CGFloat = 0, swiped = false
  override init(frame: NSRect) {
    super.init(frame: frame)
    drawsBackground = false; hasVerticalScroller = false; hasHorizontalScroller = false
    allowsMagnification = true; minMagnification = 1; maxMagnification = 6
    img.imageScaling = .scaleProportionallyUpOrDown; img.imageAlignment = .alignCenter
    documentView = img
    contentView.drawsBackground = false
  }
  required init?(coder: NSCoder) { nil }
  override func layout() { super.layout(); if magnification <= 1.001 { img.frame = contentView.bounds } }
  override func mouseDown(with e: NSEvent) {
    if e.clickCount == 2 {
      let p = contentView.convert(e.locationInWindow, from: nil)
      animator().setMagnification(magnification > 1.01 ? 1 : 2.5, centeredAt: p)
    } else { super.mouseDown(with: e) }
  }
  override func scrollWheel(with e: NSEvent) {
    guard magnification <= 1.01, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) || swipeX != 0 else { return super.scrollWheel(with: e) }
    if e.phase == .began { swipeX = 0; swiped = false }
    swipeX += e.scrollingDeltaX
    if !swiped && abs(swipeX) > 60 { swiped = true; onSwipe?(swipeX > 0 ? -1 : 1) }
    if e.phase == .ended || e.phase == .cancelled { swipeX = 0; swiped = false }
  }
}

/* ---------- the preview ---------- */
final class MacPreview: NSView {
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  private var files: [[String: Any]], at: Int
  private let from: NSRect?, openedAt: Int
  var event: (([String: Any]) -> Void)?
  var onGone: (() -> Void)?
  private let back = NSView(), stage = NSView()
  private var content: NSView?
  private var player: AVPlayer?
  private let name = NSTextField(labelWithString: ""), meta = NSTextField(labelWithString: "")
  private let copyB = PvButton(symbol: "link", title: "Copy Link", tip: "Copy a link to this file")
  private let dlB = PvButton(symbol: "arrow.down.to.line", title: "Download", tip: "Download")
  private let moreB = PvButton(symbol: "ellipsis", tip: "More")
  private let closeB = PvButton(symbol: "xmark", tip: "Close (Esc)")
  private let prevB = PvButton(symbol: "chevron.left", tip: "Previous (←)"), nextB = PvButton(symbol: "chevron.right", tip: "Next (→)")
  private let stripFx = pvGlass(), strip = NSView(), hint = NSTextField(labelWithString: "")
  private var thumbs: [NSImageView] = []
  private let pageL = NSTextField(labelWithString: ""), pageFx = pvGlass()
  // (as E11 Talk's viewer: the file the whole window, a soft shade at the top and the foot under the words and buttons)
  private let topShade = PvShade(top: true), footShade = PvShade(top: false)
  private let toastL = NSTextField(labelWithString: "")
  private var pages: [String: ([String], String?)] = [:]
  private var chromeOn = true, hideT: Timer?, leaving = false
  private var chrome: [NSView] { [topShade, footShade, name, meta, copyB, dlB, moreB, closeB, prevB, nextB, stripFx, hint, pageFx] }

  init(files: [[String: Any]], at: Int, from: NSRect?) {
    self.files = files; self.at = max(0, min(at, files.count - 1)); self.from = from; self.openedAt = self.at
    super.init(frame: .zero)
    wantsLayer = true
    back.wantsLayer = true; back.layer?.backgroundColor = NSColor.black.cgColor
    addSubview(back); addSubview(stage); addSubview(topShade); addSubview(footShade)
    for (l, size, w, c) in [(name, 13.0, NSFont.Weight.semibold, NSColor(white: 0.96, alpha: 1)), (meta, 11.5, .regular, NSColor(white: 0.92, alpha: 0.6)), (hint, 11, .regular, NSColor(white: 0.92, alpha: 0.6))] {
      l.font = .systemFont(ofSize: CGFloat(size), weight: w); l.textColor = c; l.alignment = .center; l.lineBreakMode = .byTruncatingMiddle; addSubview(l)
    }
    pvRound(stripFx, 14); pvRound(pageFx, 12)
    pvPut(strip, in: stripFx); addSubview(stripFx)
    pageL.font = .systemFont(ofSize: 12); pageL.textColor = .white
    let pageBox = NSView(); pageBox.addSubview(pageL); pvPut(pageBox, in: pageFx); pageFx.isHidden = true; addSubview(pageFx)
    toastL.font = .systemFont(ofSize: 13, weight: .medium); toastL.textColor = .white; toastL.alignment = .center
    toastL.wantsLayer = true; toastL.drawsBackground = true; toastL.backgroundColor = NSColor(white: 0.12, alpha: 0.9); toastL.layer?.cornerRadius = 15; toastL.layer?.masksToBounds = true
    toastL.alphaValue = 0; addSubview(toastL)
    for b in [copyB, dlB, moreB, closeB, prevB, nextB] { addSubview(b) }
    copyB.onClick = { [weak self] in self?.send("copy") }
    dlB.onClick = { [weak self] in self?.send("dl") }
    moreB.onClick = { [weak self] in
      guard let self = self, let web = self.window?.contentView?.subviews.first(where: { $0 is WKWebView }) as? WKWebView else { self?.send("more"); return }
      // (••• : the page's options as Apple's menu, just under the button — the page's point is in its own CSS pixels)
      let p = web.convert(NSPoint(x: self.moreB.frame.minX, y: self.moreB.frame.maxY + 6), from: self)
      let z = web.pageZoom, flippedY = web.isFlipped ? p.y : web.bounds.height - p.y
      self.send("more", ["x": p.x / z, "y": flippedY / z])
    }
    closeB.onClick = { [weak self] in self?.close() }
    prevB.onClick = { [weak self] in self?.move(-1) }
    nextB.onClick = { [weak self] in self?.move(1) }
    buildStrip()
  }
  required init?(coder: NSCoder) { nil }

  private var cur: [String: Any] { files[at] }
  private func send(_ ev: String, _ extra: [String: Any] = [:]) {
    var a: [String: Any] = ["ev": ev, "id": cur["id"] as? String ?? ""]
    extra.forEach { a[$0] = $1 }
    event?(a)
  }

  /* ---------- where things go ---------- */
  private var stageRect: NSRect {
    let k = cur["kind"] as? String ?? ""
    if k == "pdf" || k == "pages" || k == "text" { return NSRect(x: 0, y: 64, width: bounds.width, height: max(0, bounds.height - 64 - 112)) }
    if k == "image" || k == "video" { return bounds }   // (edge to edge — the words and buttons over it on their shades, 16:23)
    return NSRect(x: 120, y: 80, width: max(0, bounds.width - 240), height: max(0, bounds.height - 80 - 140))
  }
  override func layout() {
    super.layout()
    back.frame = bounds
    stage.frame = stageRect
    topShade.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 120)
    footShade.frame = NSRect(x: 0, y: bounds.height - 190, width: bounds.width, height: 190)
    content?.frame = stage.bounds
    name.frame = NSRect(x: 240, y: 13, width: max(0, bounds.width - 480), height: 18)
    meta.frame = NSRect(x: 240, y: 32, width: max(0, bounds.width - 480), height: 16)
    var x = bounds.width - 16
    for b in [closeB, moreB, dlB, copyB] { let w = b.fit; x -= w; b.frame = NSRect(x: x, y: 13, width: w, height: 34); x -= 8 }
    prevB.frame = NSRect(x: 40, y: (bounds.height - 34) / 2, width: 34, height: 34)
    nextB.frame = NSRect(x: bounds.width - 74, y: (bounds.height - 34) / 2, width: 34, height: 34)
    let sw = thumbs.reduce(CGFloat(6)) { $0 + $1.frame.width + 6 }
    stripFx.frame = NSRect(x: ((bounds.width - sw) / 2).rounded(), y: bounds.height - 22 - 18 - 66, width: sw, height: 66)
    strip.frame = stripFx.bounds
    hint.frame = NSRect(x: 0, y: bounds.height - 22 - 14, width: bounds.width, height: 14)
    let ps = pageL.intrinsicContentSize
    pageFx.frame = NSRect(x: bounds.width - 24 - ps.width - 20, y: (bounds.height - 26) / 2, width: ps.width + 20, height: 26)
    pageL.superview?.frame = pageFx.bounds
    pageL.frame = NSRect(x: 10, y: (26 - ps.height) / 2, width: ps.width + 2, height: ps.height)
    let ts = toastL.intrinsicContentSize
    toastL.frame = NSRect(x: (bounds.width - ts.width - 40) / 2, y: stripFx.frame.minY - 50, width: ts.width + 40, height: 30)
  }

  /* ---------- the strip of thumbnails ---------- */
  private func buildStrip() {
    let many = files.count > 1
    stripFx.isHidden = !many
    thumbs = files.enumerated().map { (i, f) -> NSImageView in
      let v = NSImageView(); v.imageScaling = .scaleProportionallyUpOrDown; v.wantsLayer = true
      v.layer?.cornerRadius = 7; v.layer?.masksToBounds = true; v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
      v.frame = NSRect(x: 0, y: 6, width: 40, height: 54)
      let t = f["thumb"] as? String
      if let t = t, !t.isEmpty { MacLoad.image(t) { [weak v] im in v?.image = im } }
      else { v.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)); v.contentTintColor = .white; v.imageScaling = .scaleNone }
      let g = NSClickGestureRecognizer(target: self, action: #selector(pickThumb(_:))); v.addGestureRecognizer(g)
      v.tag = i
      strip.addSubview(v)
      return v
    }
  }
  @objc private func pickThumb(_ g: NSClickGestureRecognizer) { if let v = g.view { go(v.tag) } }
  private func paintStrip() {
    var x: CGFloat = 6
    for (i, v) in thumbs.enumerated() {
      let on = i == at
      v.frame = NSRect(x: x, y: 6, width: on ? 54 : 40, height: 54); x += v.frame.width + 6
      v.alphaValue = on ? 1 : 0.7
      v.layer?.borderWidth = on ? 2 : 0; v.layer?.borderColor = NSColor.white.cgColor
    }
    hint.stringValue = files.count > 1 ? "\(at + 1) of \(files.count) · ← → to move · Space or Esc to close" : "Space or Esc to close"
    prevB.isHidden = files.count < 2 || at == 0; nextB.isHidden = files.count < 2 || at == files.count - 1
    needsLayout = true
  }

  /* ---------- one file ---------- */
  private func show() {
    player?.pause(); player = nil
    content?.removeFromSuperview(); content = nil
    pageFx.isHidden = true
    let f = cur, k = f["kind"] as? String ?? "other"
    name.stringValue = f["name"] as? String ?? ""
    meta.stringValue = f["meta"] as? String ?? ""
    let v: NSView
    switch k {
    case "image":
      let z = PvZoom(); z.onSwipe = { [weak self] d in self?.move(d) }
      MacLoad.image(f["thumb"] as? String) { [weak z] im in if z?.img.image == nil { z?.img.image = im } }
      MacLoad.image(f["src"] as? String) { [weak z] im in if let im = im { z?.img.image = im } }
      v = z
    case "video", "audio":
      let pv = AVPlayerView(); pv.controlsStyle = .floating; pv.showsFullScreenToggleButton = true
      if let s = f["src"] as? String, let url = URL(string: s) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: MacLoad.mine(url)])
        let p = AVPlayer(playerItem: AVPlayerItem(asset: asset)); pv.player = p; player = p; p.play()
      }
      v = pv
    case "pdf":
      let pdf = PDFView(); pdf.autoScales = true; pdf.displayMode = .singlePageContinuous; pdf.backgroundColor = .black
      MacLoad.data(f["src"] as? String) { [weak self, weak pdf] d in
        guard let pdf = pdf, let d = d, let doc = PDFDocument(data: d) else { self?.fallback(f); return }
        pdf.document = doc; self?.pagesChanged(pdf)
      }
      NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdf, queue: .main) { [weak self, weak pdf] _ in if let pdf = pdf { self?.pagesChanged(pdf) } }
      v = pdf
    case "pages":
      v = pagesView(f)
      let id = f["id"] as? String ?? ""
      if let p = pages[id] { fillPages(v, p.0, p.1) } else { send("pages") }
    case "text":
      let sv = NSTextView.scrollableTextView()
      let tv = sv.documentView as? NSTextView
      tv?.isEditable = false; tv?.drawsBackground = false; tv?.textColor = .white; tv?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
      tv?.textContainerInset = NSSize(width: 120, height: 16)
      sv.drawsBackground = false
      MacLoad.data(f["src"] as? String) { d in tv?.string = d.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
      v = sv
    default:
      v = card(f, note: f["note"] as? String ?? "Download it to see the whole file.")
    }
    content = v
    stage.addSubview(v)
    needsLayout = true
    paintStrip()
    send("at")
  }
  private func fallback(_ f: [String: Any]) {
    guard (cur["id"] as? String) == (f["id"] as? String) else { return }
    content?.removeFromSuperview()
    let v = card(f, note: "This file couldn’t be previewed — download it to see it."); content = v; stage.addSubview(v); needsLayout = true
  }
  private func pagesChanged(_ pdf: PDFView) {
    guard let doc = pdf.document, let p = pdf.currentPage else { return }
    pageL.stringValue = "Page \(doc.index(for: p) + 1) of \(doc.pageCount)"
    pageFx.isHidden = doc.pageCount < 2 || !chromeOn
    needsLayout = true
  }
  // anything else: its picture (or the kind of file) and a word under it
  private func card(_ f: [String: Any], note: String) -> NSView {
    let box = NSView()
    let pic = NSImageView(); pic.imageScaling = .scaleProportionallyUpOrDown
    let cover = (f["cover"] as? String) ?? (f["thumb"] as? String)
    if let c = cover, !c.isEmpty { MacLoad.image(c) { [weak pic] im in pic?.image = im } }
    else { pic.image = NSWorkspace.shared.icon(for: UTType(filenameExtension: (f["ext"] as? String ?? "").lowercased()) ?? UTType.data) }
    let l = NSTextField(wrappingLabelWithString: note); l.textColor = NSColor(white: 0.92, alpha: 0.7); l.alignment = .center; l.font = .systemFont(ofSize: 13)
    box.addSubview(pic); box.addSubview(l)
    box.postsFrameChangedNotifications = true
    NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: box, queue: .main) { [weak box, weak pic, weak l] _ in
      guard let b = box?.bounds else { return }
      pic?.frame = NSRect(x: 0, y: 40, width: b.width, height: max(0, b.height - 40))
      l?.frame = NSRect(x: 0, y: 0, width: b.width, height: 34)
    }
    return box
  }
  // Word / Excel / PowerPoint: the server's page pictures, one under another
  private func pagesView(_ f: [String: Any]) -> NSView {
    let sv = NSScrollView(); sv.drawsBackground = false; sv.hasVerticalScroller = true; sv.autohidesScrollers = true; sv.scrollerStyle = .overlay
    let doc = FlippedView(); sv.documentView = doc
    let spin = NSProgressIndicator(); spin.style = .spinning; spin.controlSize = .small; spin.startAnimation(nil)
    spin.frame = NSRect(x: 0, y: 40, width: 16, height: 16); doc.addSubview(spin)
    return sv
  }
  private func fillPages(_ v: NSView, _ urls: [String], _ note: String?) {
    guard let sv = v as? NSScrollView, let doc = sv.documentView else { return }
    doc.subviews.forEach { $0.removeFromSuperview() }
    let W = min(sv.bounds.width - 80, 900), x = ((sv.bounds.width - W) / 2).rounded()
    var y: CGFloat = 16
    for u in urls {
      let iv = NSImageView(); iv.imageScaling = .scaleProportionallyUpOrDown; iv.wantsLayer = true; iv.layer?.backgroundColor = NSColor.white.cgColor
      iv.frame = NSRect(x: x, y: y, width: W, height: W * 1.294); y += iv.frame.height + 16
      MacLoad.image(u) { [weak iv] im in
        guard let iv = iv, let im = im, im.size.width > 0 else { return }
        iv.image = im
      }
      doc.addSubview(iv)
    }
    if let n = note { let l = NSTextField(wrappingLabelWithString: n); l.textColor = NSColor(white: 0.92, alpha: 0.7); l.alignment = .center
      l.frame = NSRect(x: x, y: y, width: W, height: 30); y += 40; doc.addSubview(l) }
    if urls.isEmpty && note == nil { let l = NSTextField(labelWithString: "This file couldn’t be previewed — download it to see it."); l.textColor = .white; l.frame = NSRect(x: x, y: 40, width: W, height: 20); doc.addSubview(l) }
    doc.frame = NSRect(x: 0, y: 0, width: sv.bounds.width, height: max(y, sv.bounds.height))
  }

  /* ---------- what the page says back ---------- */
  func set(_ a: [String: Any]) {
    if let id = a["id"] as? String, let urls = a["pages"] as? [String] {
      pages[id] = (urls, a["note"] as? String)
      if (cur["id"] as? String) == id, let v = content { fillPages(v, urls, a["note"] as? String) }
    }
    if let rows = a["info"] as? [[String]], let w = window {
      let al = NSAlert(); al.messageText = "File info"; al.informativeText = rows.map { "\($0.first ?? ""): \($0.last ?? "")" }.joined(separator: "\n")
      al.addButton(withTitle: "OK"); al.beginSheetModal(for: w, completionHandler: nil)
    }
    if (a["close"] as? Bool) == true { close() }
    if let msg = a["toast"] as? String { flash(msg) }
  }
  private func flash(_ s: String) {
    toastL.stringValue = s; needsLayout = true; layoutSubtreeIfNeeded()
    NSAnimationContext.runAnimationGroup { c in c.duration = 0.2; self.toastL.animator().alphaValue = 1 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSAnimationContext.runAnimationGroup { c in c.duration = 0.3; self.toastL.animator().alphaValue = 0 } }
  }

  /* ---------- moving, keys, the pointer ---------- */
  private func go(_ i: Int) { guard i >= 0, i < files.count, i != at else { return }; at = i; show(); wake() }
  private func move(_ d: Int) { go(at + d) }
  override func keyDown(with e: NSEvent) {
    switch e.keyCode {
    case 123: move(-1)
    case 124: move(1)
    case 53: close()
    case 49: if player == nil { close() } else if let p = player { p.rate == 0 ? p.play() : p.pause() }
    default: super.keyDown(with: e)
    }
  }
  override func cancelOperation(_ sender: Any?) { close() }
  override func updateTrackingAreas() {
    super.updateTrackingAreas(); trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }
  override func mouseMoved(with e: NSEvent) { wake() }
  // (clicks and scrolls stay here — nothing reaches the page under it)
  override func mouseDown(with e: NSEvent) {}
  override func scrollWheel(with e: NSEvent) {}
  private func wake() {
    if !chromeOn { chromeOn = true; fade(true) }
    hideT?.invalidate()
    hideT = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
      guard let self = self, !self.leaving else { return }
      self.chromeOn = false; self.fade(false)
    }
  }
  private func fade(_ on: Bool) {
    NSAnimationContext.runAnimationGroup { c in
      c.duration = 0.25
      for v in chrome where !(v === pageFx && pageL.stringValue.isEmpty) { v.animator().alphaValue = on ? 1 : 0 }
    }
  }

  /* ---------- opening and closing: out of its thumbnail and back ---------- */
  func open(in host: NSView) {
    frame = host.bounds; autoresizingMask = [.width, .height]
    host.addSubview(self)
    window?.makeFirstResponder(self)
    show(); layoutSubtreeIfNeeded()
    let target = stage.frame
    back.alphaValue = 0; chrome.forEach { $0.alphaValue = 0 }; stage.alphaValue = 0
    let finish = {
      NSAnimationContext.runAnimationGroup { c in
        c.duration = 0.3; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        self.back.animator().alphaValue = 1; self.chrome.forEach { $0.animator().alphaValue = 1 }
      }
      self.wake()
    }
    guard let r = from, r.width > 4, let t = cur["thumb"] as? String ?? cur["cover"] as? String, !t.isEmpty else {
      NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; self.stage.animator().alphaValue = 1 }
      return finish()
    }
    var flown = false
    let fly0: (NSImage?) -> Void = { [weak self] im in
      guard let self = self, !flown else { return }
      flown = true
      guard let im = im else { NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; self.stage.animator().alphaValue = 1 }; return finish() }
      // (as Photos / E11 Talk: the picture cut to the thumbnail's own shape and corners at first, opening out to the whole
      //  picture as it grows — one layer filling its frame, its frame and corners moved by Core Animation; Haris 16:36:
      //  "the coming in from the thumbnail is not looking native")
      let fly = PvFly(im, frame: r, radius: 9)
      self.addSubview(fly)
      finish()
      fly.move(to: self.fit(im.size, in: target), radius: 0, duration: 0.38, timing: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)) {
        self.stage.alphaValue = 1
        fly.removeFromSuperview()
      }
    }
    // (the full picture when it arrives within a moment — the thumbnail, small and cut square, came out blurred and cropped,
    //  16:23 — else the thumbnail)
    if (cur["kind"] as? String) == "image" {
      MacLoad.image(cur["src"] as? String) { im in if let im = im { fly0(im) } }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { MacLoad.image(t) { im in fly0(im) } }
    } else { MacLoad.image(t) { im in fly0(im) } }
  }
  private func fit(_ s: NSSize, in r: NSRect) -> NSRect {
    guard s.width > 0, s.height > 0 else { return r }
    let k = min(r.width / s.width, r.height / s.height)
    let w = s.width * k, h = s.height * k
    return NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
  }
  func close() {
    guard !leaving else { return }
    leaving = true
    hideT?.invalidate(); player?.pause()
    let img = (content as? PvZoom)?.img.image
    let gone = { [weak self] in
      guard let self = self else { return }
      self.removeFromSuperview(); self.event?(["ev": "closed"]); self.onGone?()
    }
    // back into its thumbnail — from exactly where the picture is on screen (not zoomed), closing to the thumbnail's own
    // shape and corners, so nothing jumps at either end (16:36: "going out it jerks because of the size of the image")
    if at == openedAt, let r = from, r.width > 4, let z = content as? PvZoom, z.magnification <= 1.01, let im = img {
      let start = convert(fit(im.size, in: z.bounds), from: z)
      let fly = PvFly(im, frame: start, radius: 0)
      addSubview(fly); stage.alphaValue = 0
      NSAnimationContext.runAnimationGroup { c in
        c.duration = 0.3; self.back.animator().alphaValue = 0; self.chrome.forEach { $0.animator().alphaValue = 0 }
      }
      fly.move(to: r, radius: 9, duration: 0.32, timing: CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1)) { gone() }
    } else {
      NSAnimationContext.runAnimationGroup({ c in c.duration = 0.22; self.animator().alphaValue = 0 }, completionHandler: gone)
    }
  }
}

/* a soft black shade at the top or the foot, under the words and buttons (as E11 Talk's viewer) */
final class PvShade: NSView {
  private let g = CAGradientLayer()
  init(top: Bool) {
    super.init(frame: .zero)
    wantsLayer = true
    g.colors = [NSColor(white: 0, alpha: 0.62).cgColor, NSColor(white: 0, alpha: 0.28).cgColor, NSColor(white: 0, alpha: 0).cgColor]
    g.locations = [0, 0.5, 1]
    // (the view is in a flipped parent, its layer not flipped: y 1 is its top)
    g.startPoint = CGPoint(x: 0.5, y: top ? 1 : 0); g.endPoint = CGPoint(x: 0.5, y: top ? 0 : 1)
    layer?.addSublayer(g)
  }
  required init?(coder: NSCoder) { nil }
  override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); g.frame = bounds; CATransaction.commit() }
  override func hitTest(_ p: NSPoint) -> NSView? { nil }
}

/* the picture flying out of its thumbnail and back: one layer showing the picture cut to fill its frame (as the thumbnail
   shows it), so as its frame goes from the thumbnail's square to the picture's own shape the cut opens out — Core
   Animation moving its bounds, place and corners together, in one timing */
final class PvFly: NSView {
  override var isFlipped: Bool { true }
  init(_ im: NSImage, frame: NSRect, radius: CGFloat) {
    super.init(frame: frame)
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    if layer == nil { layer = CALayer() }
    if let l = layer {
      l.contents = im.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? im
      l.contentsGravity = .resizeAspectFill
      l.masksToBounds = true
      l.cornerRadius = radius
    }
  }
  required init?(coder: NSCoder) { nil }
  // (Apple's own spring, as iPhone's and Photos' zoom — Haris 16:36 / 17:06: the steep ease jumped most of the way in the
  //  first frame, so it looked like a pop, not a flight): the model set at once, Core Animation springing size, place and
  //  corners from where they were
  func move(to r: NSRect, radius: CGFloat, duration: Double, timing: CAMediaTimingFunction, done: @escaping () -> Void) {
    guard let l = layer else { frame = r; done(); return }
    let fromBounds = l.bounds, fromPos = l.position, fromRadius = l.cornerRadius
    CATransaction.begin(); CATransaction.setDisableActions(true)
    frame = r
    l.cornerRadius = radius
    CATransaction.commit()
    let toBounds = l.bounds, toPos = l.position
    CATransaction.begin()
    CATransaction.setCompletionBlock(done)
    func spring(_ key: String, _ a: Any, _ b: Any) -> CASpringAnimation {
      let s = CASpringAnimation(keyPath: key)
      s.mass = 1; s.stiffness = 170; s.damping = 26; s.initialVelocity = 0
      s.fromValue = a; s.toValue = b
      s.duration = min(max(duration, s.settlingDuration), 0.7)
      s.fillMode = .both; s.isRemovedOnCompletion = true
      return s
    }
    l.add(spring("bounds", NSValue(rect: fromBounds), NSValue(rect: toBounds)), forKey: "b")
    l.add(spring("position", NSValue(point: fromPos), NSValue(point: toPos)), forKey: "p")
    l.add(spring("cornerRadius", fromRadius, radius), forKey: "r")
    CATransaction.commit()
  }

}
