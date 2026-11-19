// E11 Console for Mac — a deleted task from the Trash in its own Mac window (canvas "Trash — Mac" T4, Haris 2026-11-18 16:27:
// "T4, T7 as native windows"), as Client Assets' Get Info window (Info.swift): Apple's title bar and traffic lights, the task's
// name as its title, moved anywhere, several open at once, closed with the red dot, ⌘W or Esc; light and dark by itself.
// Inside, view only, as the board and the website's Trash view (app.js trashTaskView): "In the Trash · deleted by … · N days
// left" with Restore, then Client, Status, Assignees, Dates, Tags, Description, Subtasks, Checklist, Attachments (a click
// previews it — the Mac's preview, the task's files), Comments. The page sends what to show (command trashWindow, again
// whenever it changes; trashClose when it's gone) and is told of Restore / a preview / a close (window.__e11Trash).
// Also here: Apple's own alert (command alert) — the Trash's questions (T7) and Update Ready (Haris 2026-11-18 17:04: Reload ·
// What's New · Later): its own window, the page's title and words, the first button Apple's red "destructive" one when
// asked, the last one with Esc.
import Cocoa

final class TrashWindows: NSObject, NSWindowDelegate {
  static let shared = TrashWindows()
  var wins: [String: TrashWindow] = [:]
  var event: (([String: Any]) -> Void)?
  weak var main: NSWindow?

  func show(_ a: [String: Any]) -> Bool {
    guard let key = a["key"] as? String else { return false }
    if let w = wins[key] {
      w.fill(a)
      if (a["update"] as? Bool) != true { w.makeKeyAndOrderFront(nil) }
      return true
    }
    if (a["update"] as? Bool) == true { return true }   // (closed meanwhile: nothing to update)
    let w = TrashWindow(key: key)
    w.appearance = main?.appearance   // (the app's own light / dark, not only the Mac's — Haris 2026-11-18 17:13)
    w.delegate = self
    w.onRestore = { [weak self] in self?.event?(["key": key, "act": "restore"]) }
    w.onForever = { [weak self] in self?.event?(["key": key, "act": "forever"]) }
    w.onFile = { [weak self] id in self?.event?(["key": key, "act": "preview", "file": id]) }
    w.fill(a)
    // (beside the middle of the app's window, each next one a little lower and to the right — as Finder's)
    if let m = main {
      let n = CGFloat(wins.count) * 24, f = w.frame
      w.setFrameOrigin(NSPoint(x: m.frame.midX - f.width / 2 + 130 + n, y: m.frame.maxY - f.height - 40 - n))
    } else { w.center() }
    wins[key] = w
    w.makeKeyAndOrderFront(nil)
    // (its height checked once it's up: the bar alone means it was squeezed — given its height again)
    DispatchQueue.main.async { if w.contentLayoutRect.height < 300 { w.setContentSize(NSSize(width: w.frame.width, height: 640)) } }
    return true
  }
  func close(_ key: String) { wins[key]?.close() }
  // (the app's look changed: its windows follow)
  func follow(_ a: NSAppearance?) { wins.values.forEach { $0.appearance = a; $0.refill() } }
  func windowWillClose(_ n: Notification) {
    guard let w = n.object as? TrashWindow else { return }
    wins[w.key] = nil
    event?(["key": w.key, "act": "closed"])
    if let m = main, wins.isEmpty { m.makeKeyAndOrderFront(nil) }
  }

  // Apple's own alert, its own window (T7): pressed = the first button
  static func alert(_ a: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    let al = NSAlert()
    al.alertStyle = .informational
    al.messageText = a["title"] as? String ?? ""
    al.informativeText = a["body"] as? String ?? ""
    let ok = al.addButton(withTitle: a["ok"] as? String ?? "OK")
    // (a middle button when asked — Update Ready's What's New; the last one is always the way out, with Esc)
    let other = (a["other"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    if let o = other { al.addButton(withTitle: o) }
    let cancel = al.addButton(withTitle: a["cancel"] as? String ?? "Cancel")
    cancel.keyEquivalent = "\u{1b}"
    // (no red "destructive" button — too loud: Haris 2026-11-18 17:14; the first button is Apple's usual one)
    _ = ok
    let main = TrashWindows.shared.main
    al.window.appearance = main?.appearance   // (the app's own light / dark)
    let show = {
      let r = al.runModal()
      let which = r == .alertFirstButtonReturn ? "ok" : (other != nil && r == .alertSecondButtonReturn) ? "other" : "cancel"
      done(["ok": true, "pressed": which == "ok", "button": which])
    }
    // (asked to wait while E11 Console is behind other apps — Update Ready: the Dock icon bounces once and the alert comes
    //  as you come back, never over another app)
    if (a["whenFront"] as? Bool) == true, !NSApp.isActive {
      NSApp.requestUserAttention(.informationalRequest)
      var token: NSObjectProtocol?
      token = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
        if let t = token { NotificationCenter.default.removeObserver(t) }
        DispatchQueue.main.async { show() }
      }
      return
    }
    DispatchQueue.main.async { show() }
  }
}

// (W2 on "Deleted task window — Mac", Haris 2026-11-18 19:16): the window's own bar — the task's name, "In the Trash · read
// only" under it, Delete Forever… and Restore at its right; a soft orange note of who deleted it and when it goes; the task's
// name big with its client above and its status and tags as pills; Assignees and Dates in Apple's grouped box; Description,
// Subtasks and Checklist in boxes; files as pictures with their sizes; the comments as bubbles with faces in their own
// column on the right.
final class TrashWindow: NSWindow, NSToolbarDelegate {
  let key: String
  var onRestore: (() -> Void)?
  var onForever: (() -> Void)?
  var onFile: ((String) -> Void)?
  private let stack = NSStackView(), side = NSStackView()
  private let scroll = NSScrollView(), sideScroll = NSScrollView()
  private let L: CGFloat = 630, R: CGFloat = 294   // (the two columns' widths inside their margins)
  private var lastJSON = "", last: [String: Any] = [:]
  private var canRestore = false, canForever = false

  init(key: String) {
    self.key = key
    super.init(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    tabbingMode = .disallowed
    minSize = NSSize(width: 1000, height: 360)
    contentMinSize = NSSize(width: 1000, height: 320)
    let root = NSVisualEffectView()
    root.material = .windowBackground; root.blendingMode = .behindWindow; root.state = .followsWindowActiveState
    contentView = root
    func column(_ sc: NSScrollView, _ st: NSStackView, _ inset: CGFloat) -> FlippedView {
      let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false
      st.orientation = .vertical; st.alignment = .leading; st.spacing = 0; st.translatesAutoresizingMaskIntoConstraints = false
      doc.addSubview(st)
      sc.drawsBackground = false; sc.hasVerticalScroller = true; sc.autohidesScrollers = true
      sc.documentView = doc; sc.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(sc)
      NSLayoutConstraint.activate([
        doc.leadingAnchor.constraint(equalTo: sc.contentView.leadingAnchor), doc.trailingAnchor.constraint(equalTo: sc.contentView.trailingAnchor),
        doc.topAnchor.constraint(equalTo: sc.contentView.topAnchor),
        st.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: inset), st.trailingAnchor.constraint(lessThanOrEqualTo: doc.trailingAnchor, constant: -inset),
        st.topAnchor.constraint(equalTo: doc.topAnchor, constant: 16), st.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20),
      ])
      return doc
    }
    _ = column(scroll, stack, 20)
    _ = column(sideScroll, side, 18)
    // the comments' column: its own shade and a line at its left
    let shade = NSView(); shade.wantsLayer = true; shade.translatesAutoresizingMaskIntoConstraints = false
    shade.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
    let line = NSBox(); line.boxType = .separator; line.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(shade, positioned: .below, relativeTo: sideScroll); root.addSubview(line)
    sideShade = shade
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: sideScroll.leadingAnchor),
      scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      // (never smaller than this: the scroll areas have no height of their own, and the window came up as its bar alone —
      //  Haris 2026-11-19 12:24)
      root.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
      sideScroll.widthAnchor.constraint(equalToConstant: R + 36), sideScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      sideScroll.topAnchor.constraint(equalTo: root.topAnchor), sideScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      shade.leadingAnchor.constraint(equalTo: sideScroll.leadingAnchor), shade.trailingAnchor.constraint(equalTo: sideScroll.trailingAnchor),
      shade.topAnchor.constraint(equalTo: sideScroll.topAnchor), shade.bottomAnchor.constraint(equalTo: sideScroll.bottomAnchor),
      line.widthAnchor.constraint(equalToConstant: 1), line.trailingAnchor.constraint(equalTo: sideScroll.leadingAnchor),
      line.topAnchor.constraint(equalTo: sideScroll.topAnchor), line.bottomAnchor.constraint(equalTo: sideScroll.bottomAnchor),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  private var sideShade: NSView?
  // (Esc closes it, as Get Info)
  override func keyDown(with e: NSEvent) { if e.keyCode == 53 { performClose(nil) } else { super.keyDown(with: e) } }

  // ---- the window's own bar: Delete Forever… and Restore ----
  private static let forever = NSToolbarItem.Identifier("forever"), restoreId = NSToolbarItem.Identifier("restore")
  private func makeBar() {
    let tb = NSToolbar(identifier: "e11-trash-task")
    tb.delegate = self; tb.displayMode = .iconOnly; tb.allowsUserCustomization = false
    toolbar = tb
    if #available(macOS 11.0, *) { toolbarStyle = .unified }
  }
  func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace] + (canForever ? [Self.forever] : []) + (canRestore ? [Self.restoreId] : [])
  }
  func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.forever, Self.restoreId] }
  func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    let it = NSToolbarItem(itemIdentifier: id)
    let b: NSButton
    if id == Self.forever {
      b = NSButton(title: "Delete Forever…", target: self, action: #selector(foreverPicked))
      b.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
    } else {
      b = NSButton(title: "Restore", target: self, action: #selector(restore))
      b.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
      b.bezelColor = .controlAccentColor; b.keyEquivalent = "\r"
    }
    b.bezelStyle = .rounded; b.imagePosition = .imageLeading
    it.view = b; it.label = b.title
    return it
  }

  // ---- pieces ----
  private func label(_ s: String, _ font: NSFont, _ color: NSColor = .labelColor, wrap: Bool = true, width: CGFloat? = nil) -> NSTextField {
    let t = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
    t.font = font; t.textColor = color; t.isSelectable = true
    if wrap { t.preferredMaxLayoutWidth = width ?? L }
    if !wrap { t.lineBreakMode = .byTruncatingTail }
    return t
  }
  private func gap(_ h: CGFloat) -> NSView { let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; v.heightAnchor.constraint(equalToConstant: h).isActive = true; return v }
  private func add(_ v: NSView, _ to: NSStackView? = nil, width: CGFloat? = nil) {
    v.translatesAutoresizingMaskIntoConstraints = false
    (to ?? stack).addArrangedSubview(v)
    if let w = width { v.widthAnchor.constraint(equalToConstant: w).isActive = true }
  }
  private func symbol(_ name: String, _ color: NSColor, _ size: CGFloat = 13, _ weight: NSFont.Weight = .regular) -> NSImageView {
    let v = NSImageView()
    if let im = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: weight)) { v.image = im }
    v.contentTintColor = color
    v.translatesAutoresizingMaskIntoConstraints = false
    v.setContentHuggingPriority(.required, for: .horizontal)
    return v
  }
  private func pill(_ s: String, bg: NSColor, fg: NSColor) -> NSView {
    let t = label(s, .systemFont(ofSize: 11.5, weight: .semibold), fg, wrap: false)
    let p = NSView(); p.wantsLayer = true
    p.layer?.backgroundColor = bg.cgColor; p.layer?.cornerRadius = 10
    t.translatesAutoresizingMaskIntoConstraints = false; p.addSubview(t)
    NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: p.leadingAnchor, constant: 9), t.trailingAnchor.constraint(equalTo: p.trailingAnchor, constant: -9),
                                 t.topAnchor.constraint(equalTo: p.topAnchor, constant: 2), t.bottomAnchor.constraint(equalTo: p.bottomAnchor, constant: -2)])
    p.setContentHuggingPriority(.required, for: .horizontal)
    return p
  }
  private func row(_ views: [NSView], _ spacing: CGFloat = 8) -> NSStackView {
    let r = NSStackView(views: views); r.orientation = .horizontal; r.alignment = .centerY; r.spacing = spacing
    return r
  }
  // a caption over a box: DESCRIPTION, SUBTASKS 1 OF 2…
  private func cap(_ t: String, _ n: String? = nil, _ to: NSStackView? = nil) {
    let s = NSMutableAttributedString(string: t.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor, .kern: 0.3])
    if let n = n { s.append(NSAttributedString(string: "  " + n.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor, .kern: 0.3])) }
    add(gap(18), to); add(row([gap(0), NSTextField(labelWithAttributedString: s)], 4), to); add(gap(7), to)
  }
  // Apple's grouped box (as System Settings): rows with hairlines between them
  private func box(_ rows: [NSView], width: CGFloat) -> NSView {
    let b = NSView(); b.wantsLayer = true
    b.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
    b.layer?.cornerRadius = 12; b.layer?.borderWidth = 0.5; b.layer?.borderColor = NSColor.separatorColor.cgColor
    let st = NSStackView(); st.orientation = .vertical; st.alignment = .leading; st.spacing = 0; st.translatesAutoresizingMaskIntoConstraints = false
    for (i, r) in rows.enumerated() {
      if i > 0 { let sep = NSBox(); sep.boxType = .separator; sep.translatesAutoresizingMaskIntoConstraints = false; st.addArrangedSubview(sep); sep.widthAnchor.constraint(equalToConstant: width).isActive = true }
      r.translatesAutoresizingMaskIntoConstraints = false; st.addArrangedSubview(r)
    }
    b.addSubview(st)
    NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo: b.leadingAnchor), st.trailingAnchor.constraint(equalTo: b.trailingAnchor),
                                 st.topAnchor.constraint(equalTo: b.topAnchor), st.bottomAnchor.constraint(equalTo: b.bottomAnchor),
                                 b.widthAnchor.constraint(equalToConstant: width)])
    return b
  }
  private func padded(_ v: NSView, _ h: CGFloat, _ x: CGFloat = 14) -> NSView {
    let w = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; w.addSubview(v)
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: w.leadingAnchor, constant: x), v.trailingAnchor.constraint(lessThanOrEqualTo: w.trailingAnchor, constant: -x),
                                 v.centerYAnchor.constraint(equalTo: w.centerYAnchor), w.heightAnchor.constraint(greaterThanOrEqualToConstant: h),
                                 v.topAnchor.constraint(greaterThanOrEqualTo: w.topAnchor, constant: 8), v.bottomAnchor.constraint(lessThanOrEqualTo: w.bottomAnchor, constant: -8)])
    return w
  }
  private func faceView(_ f: [String: Any], _ s: CGFloat) -> NSView {
    let v = BarFace(f)
    if s != 26 { v.layer?.cornerRadius = s / 2 }
    v.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: s), v.heightAnchor.constraint(equalToConstant: s)])
    return v
  }
  private func todo(_ s: String, _ done: Bool) -> NSView {
    let mark: NSView
    if done {
      let c = NSView(); c.wantsLayer = true; c.layer?.cornerRadius = 8; c.layer?.backgroundColor = NSColor.systemGreen.cgColor
      let ck = symbol("checkmark", .white, 9, .bold); c.addSubview(ck)
      NSLayoutConstraint.activate([ck.centerXAnchor.constraint(equalTo: c.centerXAnchor), ck.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
      mark = c
    } else {
      let c = NSView(); c.wantsLayer = true; c.layer?.cornerRadius = 8; c.layer?.borderWidth = 1.5; c.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
      mark = c
    }
    mark.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([mark.widthAnchor.constraint(equalToConstant: 16), mark.heightAnchor.constraint(equalToConstant: 16)])
    let t = label(s, .systemFont(ofSize: 13), done ? .secondaryLabelColor : .labelColor, width: L - 60)
    if done { t.attributedStringValue = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]) }
    return padded(row([mark, t], 10), 36)
  }
  private func tiles(_ files: [[String: Any]], big: Bool, width: CGFloat) -> NSView {
    let flow = FlowView(width: width, spacing: 12)
    for f in files {
      let c = FileTile(f, big: big)
      c.onClick = { [weak self] id in self?.onFile?(id) }
      flow.addSubview(c)
    }
    flow.translatesAutoresizingMaskIntoConstraints = false
    flow.heightAnchor.constraint(equalToConstant: flow.fit()).isActive = true
    flow.widthAnchor.constraint(equalToConstant: width).isActive = true
    return flow
  }

  func refill() { let a = last; lastJSON = ""; fill(a) }
  func fill(_ a: [String: Any]) {
    let json = (try? JSONSerialization.data(withJSONObject: a.filter { $0.key != "update" }, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    if json == lastJSON { return }   // (sent again unchanged: nothing redrawn)
    lastJSON = json; last = a
    let cr = (a["canRestore"] as? Bool) == true, cf = (a["canForever"] as? Bool) == true
    if toolbar == nil || cr != canRestore || cf != canForever { canRestore = cr; canForever = cf; makeBar() }
    title = a["title"] as? String ?? "Untitled task"
    if #available(macOS 11.0, *) { subtitle = a["sub"] as? String ?? "In the Trash · read only" }
    // (the colours as the app's light or dark has them)
    let draw = { self.build(a) }
    let ap = appearance ?? NSApp.effectiveAppearance
    if #available(macOS 11.0, *) { ap.performAsCurrentDrawingAppearance(draw) } else { draw() }
    sideShade?.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
    stack.layoutSubtreeIfNeeded(); side.layoutSubtreeIfNeeded()
    let want = min(max(stack.fittingSize.height, side.fittingSize.height) + 60, (screen ?? NSScreen.main).map { $0.visibleFrame.height - 80 } ?? 820, 820)
    if !isVisible { setContentSize(NSSize(width: 1000, height: max(360, want))) }
  }
  private func build(_ a: [String: Any]) {
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    side.arrangedSubviews.forEach { $0.removeFromSuperview() }

    // who deleted it, when it goes — soft orange, no red
    let note = NSView(); note.wantsLayer = true
    note.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor; note.layer?.cornerRadius = 10
    let nt = NSMutableAttributedString(string: a["noteB"] as? String ?? "", attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: NSColor.systemOrange])
    nt.append(NSAttributedString(string: a["note"] as? String ?? (a["bar"] as? String ?? ""), attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.systemOrange]))
    let ntl = NSTextField(wrappingLabelWithString: ""); ntl.attributedStringValue = nt; ntl.preferredMaxLayoutWidth = L - 60; ntl.isSelectable = true
    let nr = row([symbol("clock", .systemOrange, 13), ntl], 10); nr.translatesAutoresizingMaskIntoConstraints = false; note.addSubview(nr)
    NSLayoutConstraint.activate([nr.leadingAnchor.constraint(equalTo: note.leadingAnchor, constant: 14), nr.trailingAnchor.constraint(lessThanOrEqualTo: note.trailingAnchor, constant: -14),
                                 nr.topAnchor.constraint(equalTo: note.topAnchor, constant: 10), nr.bottomAnchor.constraint(equalTo: note.bottomAnchor, constant: -10)])
    add(note, width: L)
    add(gap(16))

    // the task: its client above, its name big, its status and tags as pills
    let client = a["client"] as? String ?? ""
    if !client.isEmpty {
      let sq = NSView(); sq.wantsLayer = true; sq.layer?.cornerRadius = 3
      sq.layer?.backgroundColor = (Self.color(a["clientColor"] as? String) ?? .systemGray).cgColor
      sq.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([sq.widthAnchor.constraint(equalToConstant: 9), sq.heightAnchor.constraint(equalToConstant: 9)])
      add(row([gap(0), sq, label(client, .systemFont(ofSize: 12), .secondaryLabelColor, wrap: false)], 7)); add(gap(5))
    }
    add(label(a["title"] as? String ?? "Untitled task", .systemFont(ofSize: 22, weight: .bold), .labelColor, width: L)); add(gap(8))
    var pills: [NSView] = [pill(a["status"] as? String ?? "", bg: Self.color(a["statusColor"] as? String) ?? .systemGray, fg: .white)]
    for t in (a["tags"] as? [String]) ?? [] { pills.append(t.lowercased() == "urgent" ? pill(t, bg: NSColor.systemRed.withAlphaComponent(0.16), fg: .systemRed) : pill(t, bg: NSColor.quaternaryLabelColor, fg: .labelColor)) }
    add(row(pills, 6)); add(gap(16))

    // Assignees and Dates, Apple's grouped box
    func prop(_ ic: String, _ k: String, _ v: NSView) -> NSView {
      let kl = row([symbol(ic, .tertiaryLabelColor, 12), label(k, .systemFont(ofSize: 12.5), .secondaryLabelColor, wrap: false)], 7)
      kl.translatesAutoresizingMaskIntoConstraints = false; kl.widthAnchor.constraint(equalToConstant: 118).isActive = true
      return padded(row([kl, v], 12), 40)
    }
    let faces = (a["faces"] as? [[String: Any]]) ?? []
    var who: NSView
    if faces.isEmpty {
      let ppl = (a["people"] as? [String]) ?? []
      who = label(ppl.isEmpty ? "Nobody" : ppl.joined(separator: ", "), .systemFont(ofSize: 13), ppl.isEmpty ? .secondaryLabelColor : .labelColor, width: L - 170)
    } else {
      who = row(faces.flatMap { f -> [NSView] in [faceView(f, 22), label(f["name"] as? String ?? "", .systemFont(ofSize: 13), wrap: false), gap(0)] }, 7)
    }
    var props = [prop("person", "Assignees", who)]
    if let d = a["dates"] as? String, !d.isEmpty { props.append(prop("calendar", "Dates", label(d, .systemFont(ofSize: 13), wrap: false))) }
    add(box(props, width: L))

    if let d = a["desc"] as? String, !d.isEmpty { cap("Description"); add(box([padded(label(d, .systemFont(ofSize: 13), width: L - 28), 40)], width: L)) }
    for (k, t) in [("subtasks", "Subtasks"), ("checklist", "Checklist")] {
      let list = (a[k] as? [[String: Any]]) ?? []
      if list.isEmpty { continue }
      cap(t, "\(list.filter { ($0["done"] as? Bool) == true }.count) of \(list.count)")
      add(box(list.map { todo($0["t"] as? String ?? "", ($0["done"] as? Bool) == true) }, width: L))
    }
    let files = (a["files"] as? [[String: Any]]) ?? []
    if !files.isEmpty { cap("Files", "\(files.count)"); add(tiles(files, big: true, width: L)) }

    // the comments, their own column: faces and bubbles
    let cms = (a["comments"] as? [[String: Any]]) ?? []
    cap("Comments", cms.isEmpty ? nil : "\(cms.count)", side)
    if cms.isEmpty { add(label("No comments", .systemFont(ofSize: 13), .secondaryLabelColor, width: R), side) }
    for (i, c) in cms.enumerated() {
      if i > 0 { add(gap(14), side) }
      let head = NSMutableAttributedString(string: c["name"] as? String ?? "", attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: NSColor.labelColor])
      head.append(NSAttributedString(string: " · " + (c["when"] as? String ?? ""), attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
      let col = NSStackView(); col.orientation = .vertical; col.alignment = .leading; col.spacing = 5
      col.addArrangedSubview(NSTextField(labelWithAttributedString: head))
      if let t = c["text"] as? String, !t.isEmpty {
        let bub = NSView(); bub.wantsLayer = true; bub.layer?.cornerRadius = 14
        if #available(macOS 10.13, *) { bub.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner, .layerMaxXMaxYCorner] }
        bub.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        let tl = label(t, .systemFont(ofSize: 13), .labelColor, width: R - 38 - 24); tl.translatesAutoresizingMaskIntoConstraints = false; bub.addSubview(tl)
        NSLayoutConstraint.activate([tl.leadingAnchor.constraint(equalTo: bub.leadingAnchor, constant: 12), tl.trailingAnchor.constraint(equalTo: bub.trailingAnchor, constant: -12),
                                     tl.topAnchor.constraint(equalTo: bub.topAnchor, constant: 8), tl.bottomAnchor.constraint(equalTo: bub.bottomAnchor, constant: -8)])
        col.addArrangedSubview(bub)
      }
      let cf = (c["files"] as? [[String: Any]]) ?? []
      if !cf.isEmpty { col.addArrangedSubview(tiles(cf, big: false, width: R - 38)) }
      let r = NSStackView(views: [faceView(c, 28), col]); r.orientation = .horizontal; r.alignment = .top; r.spacing = 10
      add(r, side)
    }
  }
  @objc func restore() { onRestore?() }
  @objc func foreverPicked() { onForever?() }

  static func color(_ s: String?) -> NSColor? {
    guard var h = s?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
    h.removeFirst()
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
  }
}

/* the files, wrapping onto lines */
private final class FlowView: NSView {
  let width: CGFloat, spacing: CGFloat
  init(width: CGFloat, spacing: CGFloat = 6) { self.width = width; self.spacing = spacing; super.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  @discardableResult func fit() -> CGFloat {
    var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0
    for v in subviews {
      let s = v.fittingSize
      if x > 0 && x + s.width > width { x = 0; y += h + spacing; h = 0 }
      v.frame = NSRect(x: x, y: y, width: s.width, height: s.height)
      x += s.width + spacing; h = max(h, s.height)
    }
    return y + h
  }
  override func layout() { super.layout(); fit() }
}

// a file as a picture (W2): its own picture (a photo, a video's cover, a document's first page) or its coloured badge, its name
// and size under it; a click previews it, a drag takes the file itself out to Finder. In a comment: the picture only.
private final class FileTile: NSView {
  var onClick: ((String) -> Void)?
  private let id: String, f: [String: Any], big: Bool
  private let pic = NSView()
  private var start: NSPoint?, shown: NSImage?
  init(_ f: [String: Any], big: Bool) {
    id = f["id"] as? String ?? ""; self.f = f; self.big = big
    let w: CGFloat = big ? 132 : 120, ph: CGFloat = big ? 92 : 80
    super.init(frame: NSRect(x: 0, y: 0, width: w, height: big ? ph + 40 : ph))
    toolTip = f["name"] as? String
    pic.frame = NSRect(x: 0, y: big ? 40 : 0, width: w, height: ph)
    pic.wantsLayer = true; pic.layer?.cornerRadius = 9; pic.layer?.masksToBounds = true
    pic.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    addSubview(pic)
    // (no picture of its own, or not yet: a page with its kind, in its colour)
    let page = NSView(frame: NSRect(x: (w - 44) / 2, y: (ph - 56) / 2, width: 44, height: 56))
    page.wantsLayer = true; page.layer?.cornerRadius = 4; page.layer?.backgroundColor = NSColor.white.cgColor
    page.shadow = NSShadow(); page.layer?.shadowOpacity = 0.3; page.layer?.shadowRadius = 2; page.layer?.shadowOffset = CGSize(width: 0, height: -1)
    let ext = NSTextField(labelWithString: String((f["ext"] as? String ?? "").uppercased().prefix(4)))
    ext.font = .systemFont(ofSize: 9.5, weight: .heavy); ext.textColor = TrashWindow.color(f["color"] as? String) ?? .systemGray; ext.alignment = .center
    ext.frame = NSRect(x: 0, y: 6, width: 44, height: 13)
    page.addSubview(ext); pic.addSubview(page)
    if big {
      let n = NSTextField(labelWithString: f["name"] as? String ?? "")
      n.font = .systemFont(ofSize: 12); n.lineBreakMode = .byTruncatingMiddle
      n.frame = NSRect(x: 0, y: 18, width: w, height: 16); addSubview(n)
      let z = NSTextField(labelWithString: f["sz"] as? String ?? "")
      z.font = .systemFont(ofSize: 11); z.textColor = .secondaryLabelColor
      z.frame = NSRect(x: 0, y: 2, width: w, height: 14); addSubview(z)
    }
    if let u = f["pic"] as? String, !u.isEmpty {
      MacLoad.image(u) { [weak self] im in
        guard let self = self, let im = im else { return }
        page.removeFromSuperview(); self.shown = im
        self.pic.layer?.contentsGravity = .resizeAspectFill
        self.pic.layer?.contents = im.layerContents(forContentsScale: self.window?.backingScaleFactor ?? 2)
      }
    }
    setAccessibilityRole(.button); setAccessibilityLabel("Preview " + (f["name"] as? String ?? ""))
  }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: NSSize { frame.size }
  override var fittingSize: NSSize { frame.size }
  override func mouseDown(with e: NSEvent) { pic.alphaValue = 0.75; start = e.locationInWindow }
  override func mouseDragged(with e: NSEvent) {
    guard let s = start, hypot(e.locationInWindow.x - s.x, e.locationInWindow.y - s.y) > 3, let u = f["dl"] as? String, !u.isEmpty else { return }
    start = nil; pic.alphaValue = 1
    FileDrag.begin([["name": f["name"] as? String ?? "file", "url": u, "size": f["size"] ?? 0]], from: self, event: e, image: shown)
  }
  override func mouseUp(with e: NSEvent) {
    pic.alphaValue = 1
    if start != nil, bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?(id) }
    start = nil
  }
}
