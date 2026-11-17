// E11 Console for Mac — Client Assets' Info as the Mac's own Get Info window (Haris 2026-11-17 19:53: "can we not have the
// info popup mac native?" → yes; mock-up C5 A). A window of its own, as Finder's ⌘I: Apple's title bar and traffic lights,
// moved anywhere (outside the app's window too), several open at once, closed with the red dot, ⌘W or Esc; light and dark
// by itself. Inside, as the board: the picture big on top (a photo its own, a PDF or Office file the server's first page,
// a folder Apple's folder in E11 blue — green for a task's final files — anything else the Mac's own icon for its kind),
// the name, "kind · size", the Final mark, GENERAL and its rows, Open Task. The page sends what to show (command
// infoWindow, again whenever it changes; infoClose when it's gone) and is told of Open Task / a close (window.__e11Info).
import Cocoa
import WebKit

final class InfoWindows: NSObject, NSWindowDelegate {
  static let shared = InfoWindows()
  var wins: [String: InfoWindow] = [:]
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
    let w = InfoWindow(key: key)
    w.delegate = self
    w.onTask = { [weak self] in self?.event?(["key": key, "act": "task"]) }
    w.fill(a)
    // (in the middle of the app's window, each next one a little lower and to the right — as Finder's)
    if let m = main {
      let n = CGFloat(wins.count) * 24, f = w.frame
      w.setFrameOrigin(NSPoint(x: m.frame.midX - f.width / 2 + n, y: m.frame.midY - f.height / 2 + 60 - n))
    } else { w.center() }
    wins[key] = w
    w.makeKeyAndOrderFront(nil)
    return true
  }
  func close(_ key: String) { wins[key]?.close() }
  func windowWillClose(_ n: Notification) {
    guard let w = n.object as? InfoWindow else { return }
    wins[w.key] = nil
    event?(["key": w.key, "act": "closed"])
    if let m = main, wins.isEmpty { m.makeKeyAndOrderFront(nil) }
  }
}

final class InfoWindow: NSWindow {
  let key: String
  var onTask: (() -> Void)?
  private let stack = NSStackView()
  private let W: CGFloat = 300

  init(key: String) {
    self.key = key
    super.init(contentRect: NSRect(x: 0, y: 0, width: 332, height: 400), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    tabbingMode = .disallowed
    let root = NSVisualEffectView()
    root.material = .windowBackground; root.blendingMode = .behindWindow; root.state = .followsWindowActiveState
    contentView = root
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
      stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
      stack.widthAnchor.constraint(equalToConstant: W),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  // (Esc closes it, as Get Info)
  override func keyDown(with e: NSEvent) { if e.keyCode == 53 { performClose(nil) } else { super.keyDown(with: e) } }

  private func label(_ s: String, _ font: NSFont, _ color: NSColor = .labelColor, wrap: Bool = true) -> NSTextField {
    let t = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
    t.font = font; t.textColor = color; t.isSelectable = true
    if wrap { t.preferredMaxLayoutWidth = W }
    return t
  }
  private func gap(_ h: CGFloat) -> NSView { let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; v.heightAnchor.constraint(equalToConstant: h).isActive = true; return v }

  func fill(_ a: [String: Any]) {
    let title = a["title"] as? String ?? ""
    self.title = title + " Info"
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    // the picture, large on top
    let pic = InfoPicture(a)
    pic.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(pic)
    NSLayoutConstraint.activate([pic.widthAnchor.constraint(equalToConstant: W), pic.heightAnchor.constraint(equalToConstant: 150)])
    stack.addArrangedSubview(gap(12))
    let nm = label(title, .systemFont(ofSize: 14, weight: .semibold)); nm.lineBreakMode = .byCharWrapping
    stack.addArrangedSubview(nm)
    stack.addArrangedSubview(gap(2))
    stack.addArrangedSubview(label(a["sub"] as? String ?? "", .systemFont(ofSize: 12), .secondaryLabelColor))
    if let fin = a["fin"] as? String, !fin.isEmpty {
      stack.addArrangedSubview(gap(6))
      let t = label(fin, .systemFont(ofSize: 10.5, weight: .semibold), .systemGreen, wrap: false)
      let pill = NSView(); pill.wantsLayer = true
      pill.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor; pill.layer?.cornerRadius = 5
      t.translatesAutoresizingMaskIntoConstraints = false; pill.addSubview(t)
      NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6), t.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
                                   t.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2), t.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2)])
      stack.addArrangedSubview(pill)
    }
    stack.addArrangedSubview(gap(12))
    let cap = label("GENERAL", .systemFont(ofSize: 10.5, weight: .semibold), .secondaryLabelColor, wrap: false)
    stack.addArrangedSubview(cap)
    stack.addArrangedSubview(gap(2))
    let rows = (a["rows"] as? [[Any]]) ?? []
    for (i, r) in rows.enumerated() {
      let k = label(String(describing: r.first ?? ""), .systemFont(ofSize: 12.5), .secondaryLabelColor, wrap: false)
      let v = label(String(describing: r.count > 1 ? r[1] : ""), .systemFont(ofSize: 12.5, weight: .medium))
      v.alignment = .right; v.preferredMaxLayoutWidth = W - 110
      k.setContentHuggingPriority(.required, for: .horizontal); k.setContentCompressionResistancePriority(.required, for: .horizontal)
      v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      let line = NSStackView(views: [k, v]); line.orientation = .horizontal; line.alignment = .firstBaseline; line.spacing = 14; line.distribution = .fill
      line.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
      line.translatesAutoresizingMaskIntoConstraints = false
      stack.addArrangedSubview(line)
      line.widthAnchor.constraint(equalToConstant: W).isActive = true
      if i < rows.count - 1 {
        let sep = NSBox(); sep.boxType = .separator; sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep); sep.widthAnchor.constraint(equalToConstant: W).isActive = true
      }
    }
    if (a["task"] as? Bool) == true {
      stack.addArrangedSubview(gap(12))
      let b = NSButton(title: "Open Task", target: self, action: #selector(openTask))
      b.bezelStyle = .rounded
      let wrap = NSStackView(views: [NSView(), b]); wrap.orientation = .horizontal
      wrap.translatesAutoresizingMaskIntoConstraints = false
      stack.addArrangedSubview(wrap); wrap.widthAnchor.constraint(equalToConstant: W).isActive = true
    }
    stack.layoutSubtreeIfNeeded()
    let top = frame.maxY
    setContentSize(NSSize(width: W + 32, height: stack.fittingSize.height + 30))
    if isVisible { setFrameOrigin(NSPoint(x: frame.minX, y: top - frame.height)) }   // (grows down from where it is)
  }
  @objc func openTask() { onTask?(); close() }
}

/* the picture on top: a photo or a page filling it (as the board), a folder or the kind's icon in the middle */
final class InfoPicture: NSView {
  private let img = CALayer()
  init(_ a: [String: Any]) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 9; layer?.masksToBounds = true
    layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    img.contentsGravity = .resizeAspectFill
    layer?.addSublayer(img)
    let draw = a["draw"] as? String ?? ""
    switch draw {
    case "folder", "final-folder":
      // (Apple's folder, in E11 blue — green for a task's final files)
      let tint: NSColor = draw == "final-folder" ? NSColor(red: 0.27, green: 0.75, blue: 0.44, alpha: 1) : NSColor(red: 0.37, green: 0.58, blue: 0.94, alpha: 1)
      if let s = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) { center(tinted(s, tint, 72)) }
    case "font":
      let t = NSTextField(labelWithString: "Aa"); t.font = .systemFont(ofSize: 44, weight: .bold); t.textColor = .labelColor
      t.translatesAutoresizingMaskIntoConstraints = false; addSubview(t)
      NSLayoutConstraint.activate([t.centerXAnchor.constraint(equalTo: centerXAnchor), t.centerYAnchor.constraint(equalTo: centerYAnchor)])
    default:
      // (the kind's own icon first — the picture over it once it has come)
      let ext = a["ext"] as? String ?? ""
      center(NSWorkspace.shared.icon(forFileType: ext.isEmpty ? "public.data" : ext), size: 72)
      if draw == "pic", let u = a["pic"] as? String, !u.isEmpty {
        MacLoad.image(u) { [weak self] im in
          guard let self = self, let im = im else { return }
          self.subviews.forEach { $0.removeFromSuperview() }
          self.img.contents = im.layerContents(forContentsScale: self.window?.backingScaleFactor ?? 2)
          self.img.opacity = 0
          let f = CABasicAnimation(keyPath: "opacity"); f.fromValue = 0; f.toValue = 1; f.duration = 0.18
          self.img.add(f, forKey: "in"); self.img.opacity = 1
        }
      }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); img.frame = bounds; CATransaction.commit() }
  private func tinted(_ s: NSImage, _ c: NSColor, _ size: CGFloat) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    let base = s.withSymbolConfiguration(cfg) ?? s
    let out = NSImage(size: base.size, flipped: false) { r in base.draw(in: r); c.set(); r.fill(using: .sourceAtop); return true }
    return out
  }
  private func center(_ im: NSImage, size: CGFloat? = nil) {
    let v = NSImageView(image: im); v.imageScaling = .scaleProportionallyUpOrDown
    v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v)
    let w = size ?? im.size.width, h = size ?? im.size.height
    NSLayoutConstraint.activate([v.centerXAnchor.constraint(equalTo: centerXAnchor), v.centerYAnchor.constraint(equalTo: centerYAnchor),
                                 v.widthAnchor.constraint(equalToConstant: w), v.heightAnchor.constraint(equalToConstant: h)])
  }
}
