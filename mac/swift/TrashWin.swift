// E11 Console for Mac — a deleted task from the Trash in its own Mac window (canvas "Trash — Mac" T4, Haris 2026-11-18 16:27:
// "T4, T7 as native windows"), as Client Assets' Get Info window (Info.swift): Apple's title bar and traffic lights, the task's
// name as its title, moved anywhere, several open at once, closed with the red dot, ⌘W or Esc; light and dark by itself.
// Inside, view only, as the board and the website's Trash view (app.js trashTaskView): "In the Trash · deleted by … · N days
// left" with Restore, then Client, Status, Assignees, Dates, Tags, Description, Subtasks, Checklist, Attachments (a click
// previews it — the Mac's preview, the task's files), Comments. The page sends what to show (command trashWindow, again
// whenever it changes; trashClose when it's gone) and is told of Restore / a preview / a close (window.__e11Trash).
// Also here: Apple's own alert for the Trash's questions (command alert — T7): its own window, the page's title and words,
// the first button Apple's red "destructive" one when asked, Cancel with Esc.
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
    w.delegate = self
    w.onRestore = { [weak self] in self?.event?(["key": key, "act": "restore"]) }
    w.onFile = { [weak self] id in self?.event?(["key": key, "act": "preview", "file": id]) }
    w.fill(a)
    // (beside the middle of the app's window, each next one a little lower and to the right — as Finder's)
    if let m = main {
      let n = CGFloat(wins.count) * 24, f = w.frame
      w.setFrameOrigin(NSPoint(x: m.frame.midX - f.width / 2 + 130 + n, y: m.frame.maxY - f.height - 40 - n))
    } else { w.center() }
    wins[key] = w
    w.makeKeyAndOrderFront(nil)
    return true
  }
  func close(_ key: String) { wins[key]?.close() }
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
    al.addButton(withTitle: a["cancel"] as? String ?? "Cancel")
    if (a["destructive"] as? Bool) == true, #available(macOS 11.0, *) { ok.hasDestructiveAction = true }
    DispatchQueue.main.async {
      let r = al.runModal()
      done(["ok": true, "pressed": r == .alertFirstButtonReturn])
    }
  }
}

final class TrashWindow: NSWindow {
  let key: String
  var onRestore: (() -> Void)?
  var onFile: ((String) -> Void)?
  private let stack = NSStackView()
  private let scroll = NSScrollView()
  private let W: CGFloat = 560
  private var lastJSON = ""

  init(key: String) {
    self.key = key
    super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    tabbingMode = .disallowed
    minSize = NSSize(width: 600, height: 320)
    let root = NSVisualEffectView()
    root.material = .windowBackground; root.blendingMode = .behindWindow; root.state = .followsWindowActiveState
    contentView = root
    let doc = FlippedView()
    doc.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    doc.addSubview(stack)
    scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    scroll.documentView = doc
    scroll.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
      doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
      stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  // (Esc closes it, as Get Info)
  override func keyDown(with e: NSEvent) { if e.keyCode == 53 { performClose(nil) } else { super.keyDown(with: e) } }

  private func label(_ s: String, _ font: NSFont, _ color: NSColor = .labelColor, wrap: Bool = true, width: CGFloat? = nil) -> NSTextField {
    let t = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
    t.font = font; t.textColor = color; t.isSelectable = true
    if wrap { t.preferredMaxLayoutWidth = width ?? W }
    return t
  }
  private func gap(_ h: CGFloat) -> NSView { let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; v.heightAnchor.constraint(equalToConstant: h).isActive = true; return v }
  private func add(_ v: NSView, full: Bool = false) {
    v.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(v)
    if full { v.widthAnchor.constraint(equalToConstant: W).isActive = true }
  }
  private func symbol(_ name: String, _ color: NSColor, _ size: CGFloat = 13) -> NSImageView {
    let v = NSImageView()
    if let im = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .regular)) { v.image = im }
    v.contentTintColor = color
    v.translatesAutoresizingMaskIntoConstraints = false
    v.setContentHuggingPriority(.required, for: .horizontal)
    return v
  }
  private func pill(_ s: String, bg: NSColor, fg: NSColor) -> NSView {
    let t = label(s, .systemFont(ofSize: 11, weight: .semibold), fg, wrap: false)
    let p = NSView(); p.wantsLayer = true
    p.layer?.backgroundColor = bg.cgColor; p.layer?.cornerRadius = 9
    t.translatesAutoresizingMaskIntoConstraints = false; p.addSubview(t)
    NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: p.leadingAnchor, constant: 8), t.trailingAnchor.constraint(equalTo: p.trailingAnchor, constant: -8),
                                 t.topAnchor.constraint(equalTo: p.topAnchor, constant: 2), t.bottomAnchor.constraint(equalTo: p.bottomAnchor, constant: -2)])
    p.setContentHuggingPriority(.required, for: .horizontal)
    return p
  }
  private func section(_ title: String, _ n: Int?) {
    let t = NSMutableAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
    if let n = n { t.append(NSAttributedString(string: "  \(n)", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])) }
    let l = NSTextField(labelWithAttributedString: t)
    add(gap(16)); add(l); add(gap(6))
  }
  private func line(_ s: String, _ done: Bool) {
    let mark = symbol(done ? "checkmark" : "circle", done ? .systemGreen : .tertiaryLabelColor, done ? 12 : 11)
    let t = label(s, .systemFont(ofSize: 13), done ? .secondaryLabelColor : .labelColor, width: W - 24)
    if done { t.attributedStringValue = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]) }
    let row = NSStackView(views: [mark, t]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 3, left: 0, bottom: 3, right: 0)
    mark.widthAnchor.constraint(equalToConstant: 14).isActive = true
    add(row)
  }
  private func chips(_ files: [[String: Any]]) -> NSView {
    let flow = FlowView(width: W - 40)
    for f in files {
      let c = FileChip(f)
      c.onClick = { [weak self] id in self?.onFile?(id) }
      flow.addSubview(c)
    }
    flow.translatesAutoresizingMaskIntoConstraints = false
    flow.heightAnchor.constraint(equalToConstant: flow.fit()).isActive = true
    flow.widthAnchor.constraint(equalToConstant: W - 40).isActive = true
    return flow
  }

  func fill(_ a: [String: Any]) {
    let json = (try? JSONSerialization.data(withJSONObject: a.filter { $0.key != "update" }, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    if json == lastJSON { return }   // (sent again unchanged: nothing redrawn)
    lastJSON = json
    title = a["title"] as? String ?? "Untitled task"
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

    // In the Trash · deleted by … · N days left — Restore
    let bar = NSView(); bar.wantsLayer = true
    bar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor; bar.layer?.cornerRadius = 10
    let bin = symbol("trash", .systemRed, 13)
    let bt = label(a["bar"] as? String ?? "", .systemFont(ofSize: 12.5), .labelColor, width: W - 160)
    var views: [NSView] = [bin, bt]
    if (a["canRestore"] as? Bool) == true {
      let b = NSButton(title: "Restore", target: self, action: #selector(restore))
      b.bezelStyle = .push; b.bezelColor = .controlAccentColor
      b.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil); b.imagePosition = .imageLeading
      b.setContentHuggingPriority(.required, for: .horizontal)
      views.append(b)
    }
    let bs = NSStackView(views: views); bs.orientation = .horizontal; bs.alignment = .centerY; bs.spacing = 10
    bs.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(bs)
    NSLayoutConstraint.activate([bs.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12), bs.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
                                 bs.topAnchor.constraint(equalTo: bar.topAnchor, constant: 6), bs.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -6)])
    bt.setContentHuggingPriority(.defaultLow, for: .horizontal)
    add(bar, full: true)
    add(gap(14))

    // the task's rows
    func prop(_ k: String, _ v: NSView) {
      let kl = label(k, .systemFont(ofSize: 13), .secondaryLabelColor, wrap: false)
      kl.widthAnchor.constraint(equalToConstant: 110).isActive = true
      let r = NSStackView(views: [kl, v]); r.orientation = .horizontal; r.alignment = .centerY; r.spacing = 12
      r.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
      let sep = NSBox(); sep.boxType = .separator
      add(sep, full: true); add(r, full: true)
    }
    prop("Client", label(a["client"] as? String ?? "", .systemFont(ofSize: 13), wrap: false))
    let stColor = Self.color(a["statusColor"] as? String) ?? .systemGray
    prop("Status", pill(a["status"] as? String ?? "", bg: stColor, fg: .white))
    let people = (a["people"] as? [String]) ?? []
    prop("Assignees", label(people.isEmpty ? "Nobody" : people.joined(separator: ", "), .systemFont(ofSize: 13), people.isEmpty ? .secondaryLabelColor : .labelColor, width: W - 130))
    if let d = a["dates"] as? String, !d.isEmpty { prop("Dates", label(d, .systemFont(ofSize: 13), wrap: false)) }
    let tags = (a["tags"] as? [String]) ?? []
    if !tags.isEmpty {
      let ts = NSStackView(views: tags.map { t in t.lowercased() == "urgent" ? pill(t, bg: NSColor.systemRed.withAlphaComponent(0.15), fg: .systemRed) : pill(t, bg: NSColor.quaternaryLabelColor, fg: .labelColor) })
      ts.orientation = .horizontal; ts.spacing = 6
      prop("Tags", ts)
    }

    if let d = a["desc"] as? String, !d.isEmpty { section("Description", nil); add(label(d, .systemFont(ofSize: 13))) }
    let subs = (a["subtasks"] as? [[String: Any]]) ?? []
    if !subs.isEmpty { section("Subtasks", subs.count); subs.forEach { line($0["t"] as? String ?? "", ($0["done"] as? Bool) == true) } }
    let check = (a["checklist"] as? [[String: Any]]) ?? []
    if !check.isEmpty { section("Checklist", nil); check.forEach { line($0["t"] as? String ?? "", ($0["done"] as? Bool) == true) } }
    let files = (a["files"] as? [[String: Any]]) ?? []
    if !files.isEmpty { section("Attachments", files.count); add(chips(files)) }
    let cms = (a["comments"] as? [[String: Any]]) ?? []
    section("Comments", cms.count)
    if cms.isEmpty { add(label("No comments", .systemFont(ofSize: 13), .secondaryLabelColor)) }
    for (i, c) in cms.enumerated() {
      if i > 0 { add(gap(10)) }
      let head = NSMutableAttributedString(string: c["name"] as? String ?? "", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
      head.append(NSAttributedString(string: " · " + (c["when"] as? String ?? ""), attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
      add(NSTextField(labelWithAttributedString: head)); add(gap(3))
      if let t = c["text"] as? String, !t.isEmpty { add(label(t, .systemFont(ofSize: 13))) }
      let cf = (c["files"] as? [[String: Any]]) ?? []
      if !cf.isEmpty { add(gap(6)); add(chips(cf)) }
    }

    stack.layoutSubtreeIfNeeded()
    let want = min(stack.fittingSize.height + 40, (screen ?? NSScreen.main).map { $0.visibleFrame.height - 80 } ?? 830, 830)
    if !isVisible { setContentSize(NSSize(width: W + 40, height: max(320, want))) }
  }
  @objc func restore() { onRestore?() }

  static func color(_ s: String?) -> NSColor? {
    guard var h = s?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
    h.removeFirst()
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
  }
}


/* the files, as the page's chips: a photo its own small picture, anything else its coloured badge; wrapping onto lines */
private final class FlowView: NSView {
  let width: CGFloat
  init(width: CGFloat) { self.width = width; super.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  @discardableResult func fit() -> CGFloat {
    var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0
    for v in subviews {
      let s = v.fittingSize
      if x > 0 && x + s.width > width { x = 0; y += h + 6; h = 0 }
      v.frame = NSRect(x: x, y: y, width: s.width, height: s.height)
      x += s.width + 6; h = max(h, s.height)
    }
    return y + h
  }
  override func layout() { super.layout(); fit() }
}

private final class FileChip: NSView {
  var onClick: ((String) -> Void)?
  private let id: String
  private let pic = NSView()
  init(_ f: [String: Any]) {
    id = f["id"] as? String ?? ""
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 7
    layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    toolTip = "Preview " + (f["name"] as? String ?? "")
    pic.wantsLayer = true; pic.layer?.cornerRadius = 5; pic.layer?.masksToBounds = true
    pic.translatesAutoresizingMaskIntoConstraints = false
    addSubview(pic)
    let name = NSTextField(labelWithString: f["name"] as? String ?? "")
    name.font = .systemFont(ofSize: 12); name.lineBreakMode = .byTruncatingMiddle
    name.translatesAutoresizingMaskIntoConstraints = false
    addSubview(name)
    NSLayoutConstraint.activate([
      pic.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3), pic.centerYAnchor.constraint(equalTo: centerYAnchor),
      pic.widthAnchor.constraint(equalToConstant: 20), pic.heightAnchor.constraint(equalToConstant: 20),
      name.leadingAnchor.constraint(equalTo: pic.trailingAnchor, constant: 6), name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
      name.centerYAnchor.constraint(equalTo: centerYAnchor), name.widthAnchor.constraint(lessThanOrEqualToConstant: 170),
      heightAnchor.constraint(equalToConstant: 26),
    ])
    let ext = (f["ext"] as? String ?? "").uppercased()
    pic.layer?.backgroundColor = (TrashWindow.color(f["color"] as? String) ?? .systemGray).cgColor
    let badge = NSTextField(labelWithString: String(ext.prefix(4)))
    badge.font = .systemFont(ofSize: 7.5, weight: .bold); badge.textColor = .white; badge.alignment = .center
    badge.translatesAutoresizingMaskIntoConstraints = false
    pic.addSubview(badge)
    NSLayoutConstraint.activate([badge.centerXAnchor.constraint(equalTo: pic.centerXAnchor), badge.centerYAnchor.constraint(equalTo: pic.centerYAnchor)])
    if let u = f["pic"] as? String, !u.isEmpty {
      MacLoad.image(u) { [weak self] im in
        guard let self = self, let im = im else { return }
        badge.removeFromSuperview()
        self.pic.layer?.backgroundColor = NSColor.clear.cgColor
        self.pic.layer?.contentsGravity = .resizeAspectFill
        self.pic.layer?.contents = im.layerContents(forContentsScale: self.window?.backingScaleFactor ?? 2)
      }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func mouseDown(with e: NSEvent) { layer?.opacity = 0.7 }
  override func mouseUp(with e: NSEvent) {
    layer?.opacity = 1
    if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?(id) }
  }
}
