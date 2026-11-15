// E11 Console for Mac — the startup screen drawn by the app itself (Mac app 14, Haris 2026-11-15 14:43): the iPhone's own —
// the E11 icon assembling (the same pieces and timings as ios/App/Splash.swift, Haris: "iPhone's: logo only"), on Home's
// own background in the page's light / dark (14:45). The page and the sidebar are made behind it meanwhile; it goes once
// the page says it's ready (command "splash", out) and the icon has finished, so the sidebar is already there as it fades.
// Pictures: mac/splash/*.png (copied from the iPhone app's Spl* pictures). Without them (the Terminal test rig): none.
import Cocoa

final class MacSplash: NSView {
  // Home's own background (home.css --mc-content): #1c1c1e dark, white light
  static let bg = dynColor(.white, NSColor(srgbRed: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255, alpha: 1))
  static func image(_ name: String) -> NSImage? {
    guard let u = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "splash") ?? Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
    return NSImage(contentsOf: u)
  }
  static var available: Bool { image("SplTile") != nil }

  let t0 = CACurrentMediaTime()
  private(set) var leaving = false
  var ready = false
  var onSkip: (() -> Void)?
  private let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  var iconTime: Double { reduce ? 0.3 : 2.15 }
  private let icon = CALayer()
  // still loading once the icon has finished (Haris 2026-11-15 15:11): Apple's small spinner and "Starting up" under it
  private let spinner = NSProgressIndicator(), startingL = NSTextField(labelWithString: "Starting up"), waitRow = NSView()
  private var files: [CALayer] = []
  private let unit: CGFloat = 132.0 / 824.0          // the icon's picture: 824 units across = 132 pt
  private var canvas: CGFloat { 1024 * unit }        // each piece's picture: 100 units more all round (shadows)

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.addSublayer(icon)
    buildIcon()
    spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
    startingL.font = .systemFont(ofSize: 12); startingL.textColor = .secondaryLabelColor; startingL.alignment = .center
    waitRow.addSubview(spinner); waitRow.addSubview(startingL)
    waitRow.wantsLayer = true; waitRow.alphaValue = 0; waitRow.isHidden = true
    addSubview(waitRow)
    DispatchQueue.main.asyncAfter(deadline: .now() + iconTime) { [weak self] in self?.showWaiting() }
    setAccessibilityLabel("E11 Console is opening")
  }
  required init?(coder: NSCoder) { nil }
  override var mouseDownCanMoveWindow: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  // Home's background and the files' pictures in the window's look, again as it changes
  override func updateLayer() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      self.layer?.backgroundColor = MacSplash.bg.cgColor
    }
    let light = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for (i, f) in files.enumerated() { f.contents = MacSplash.image("SplFile\(i + 1)\(light ? "Light" : "Dark")") }
    CATransaction.commit()
  }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
  override func layout() {
    super.layout()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    icon.bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    icon.position = CGPoint(x: bounds.midX.rounded(), y: bounds.midY.rounded())
    CATransaction.commit()
    // (under the icon: its picture is 132 pt high)
    startingL.sizeToFit()
    let rowH: CGFloat = 16 + 10 + startingL.frame.height
    waitRow.frame = NSRect(x: 0, y: (bounds.midY - 66 - 28 - rowH).rounded(), width: bounds.width, height: rowH)
    spinner.frame = NSRect(x: (bounds.width - 16) / 2, y: rowH - 16, width: 16, height: 16)
    startingL.frame = NSRect(x: 0, y: 0, width: bounds.width, height: startingL.frame.height)
  }
  // a click: skip, once the page is there to show
  override func mouseUp(with e: NSEvent) { if ready && !leaving { onSkip?() } }

  /* ---------- the icon's pieces (the iPhone's numbers: 1024-unit pictures, y from the top — turned to the Mac's y up) ---------- */
  private let easeOut2 = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
  private let spring = CAMediaTimingFunction(controlPoints: 0.3, 1.5, 0.5, 1)
  private func piece(_ name: String, anchor: CGPoint = CGPoint(x: 512, y: 512)) -> CALayer {
    let l = CALayer()
    if !name.isEmpty { l.contents = MacSplash.image(name) }
    l.contentsGravity = .resize
    l.bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    l.anchorPoint = CGPoint(x: anchor.x / 1024, y: 1 - anchor.y / 1024)
    l.position = CGPoint(x: anchor.x * unit, y: canvas - anchor.y * unit)
    return l
  }
  private func buildIcon() {
    let tile = piece("SplTile"), green = piece("SplGreen"), yellow = piece("SplYellow")
    let front = CALayer(); front.bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas); front.position = CGPoint(x: canvas / 2, y: canvas / 2)
    let base = piece("SplFront"), e11 = piece("SplE11")
    let l1 = piece("SplLine1", anchor: CGPoint(x: 322, y: 675)), l2 = piece("SplLine2", anchor: CGPoint(x: 322, y: 715))
    let check = piece("SplCheck", anchor: CGPoint(x: 692, y: 695))
    [base, e11, l1, l2, check].forEach { front.addSublayer($0) }
    [tile, green, yellow, front].forEach { icon.addSublayer($0) }
    // the five files flying in (PNG, MP4, PDF, DOCX, AI): from off the screen, shrinking into the middle
    let fly: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [(-1824, -1032, -28, -326, -230), (1992, -912, 24, 230, -213), (-2064, 600, 18, -241, 8), (1872, 1032, -20, 333, 70), (144, -1968, 10, -39, -367)]
    for _ in 1...5 { let f = piece("", anchor: CGPoint(x: 512, y: 505)); f.opacity = 0; icon.addSublayer(f); files.append(f) }
    if reduce { return }
    let deg = CGFloat.pi / 180
    // (y and turning the other way round from the iPhone's: the Mac's y goes up)
    for (i, f) in files.enumerated() {
      let (x, y, r, mx, my) = fly[i]
      keyframes(f, delay: Double(i) * 0.07, dur: 0.82, t: easeOut2, times: [0, 0.12, 0.62, 0.9, 1], [
        ("transform.translation.x", [x, x * 0.8, mx, 0, 0].map { $0 * unit }),
        ("transform.translation.y", [y, y * 0.8, my, 10, 10].map { -$0 * unit }),
        ("transform.rotation.z", [r, r * 0.8, r * 0.3, 0, 0].map { -$0 * deg }),
        ("transform.scale", [1, 1, 0.8, 0.5, 0.42]),
        ("opacity", [0, 1, 1, 1, 0])])
    }
    keyframes(green, delay: 0.7, dur: 0.52, t: spring, times: [0, 1], [("transform.translation.y", [-30 * unit, 0]), ("transform.rotation.z", [12 * deg, 0]), ("transform.scale", [0.45, 1]), ("opacity", [0, 1])])
    keyframes(yellow, delay: 0.76, dur: 0.52, t: spring, times: [0, 1], [("transform.translation.y", [-30 * unit, 0]), ("transform.rotation.z", [-10 * deg, 0]), ("transform.scale", [0.45, 1]), ("opacity", [0, 1])])
    keyframes(front, delay: 0.82, dur: 0.56, t: easeOut2, times: [0, 0.7, 1], [("transform.translation.y", [-40 * unit, 6 * unit, 0]), ("transform.scale", [0.5, 1.03, 1]), ("opacity", [0, 1, 1])])
    keyframes(tile, delay: 0.9, dur: 0.62, t: easeOut2, times: [0, 0.75, 1], [("transform.scale", [0.55, 1.03, 1]), ("opacity", [0, 1, 1])])
    keyframes(e11, delay: 1.22, dur: 0.42, t: easeOut2, times: [0, 1], [("transform.translation.y", [-16 * unit, 0]), ("opacity", [0, 1])])
    keyframes(l1, delay: 1.38, dur: 0.38, t: easeOut2, times: [0, 1], [("transform.scale.x", [0, 1]), ("opacity", [0, 1])])
    keyframes(l2, delay: 1.47, dur: 0.38, t: easeOut2, times: [0, 1], [("transform.scale.x", [0, 1]), ("opacity", [0, 1])])
    keyframes(check, delay: 1.6, dur: 0.38, t: spring, times: [0, 1], [("transform.scale", [0, 1]), ("opacity", [0, 1])])
  }
  // one CSS animation: its keyframes, held at the first one until it starts (fill-mode both); the layer left as it ends
  private func keyframes(_ l: CALayer, delay: Double, dur: Double, t: CAMediaTimingFunction, times: [NSNumber], _ keys: [(String, [CGFloat])]) {
    let g = CAAnimationGroup()
    g.animations = keys.map { kv -> CAAnimation in
      let (k, v) = kv
      let a = CAKeyframeAnimation(keyPath: k)
      a.values = v; a.keyTimes = times
      a.timingFunctions = Array(repeating: t, count: max(1, times.count - 1))
      a.duration = dur
      return a
    }
    g.duration = dur
    g.beginTime = t0 + delay
    g.fillMode = .both
    g.isRemovedOnCompletion = false
    for (k, v) in keys where k == "opacity" { l.opacity = Float(v.last ?? 1) }
    l.add(g, forKey: "sp")
  }

  private func showWaiting() {
    guard !ready, !leaving else { return }
    waitRow.isHidden = false; spinner.startAnimation(nil)
    NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; self.waitRow.animator().alphaValue = 1 }
  }
  // how long until it has gone, if it's told to go now (the icon finishes first, then a 0.45 s fade)
  func goneIn(fast: Bool = false) -> Double { (fast ? 0 : max(0, iconTime - (CACurrentMediaTime() - t0))) + (fast ? 0.2 : 0.45) }
  func leave(fast: Bool = false, then: @escaping () -> Void) {
    if leaving { return }
    let wait = fast ? 0 : max(0, iconTime - (CACurrentMediaTime() - t0))
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      guard let self = self, !self.leaving else { return }
      self.leaving = true
      self.spinner.stopAnimation(nil)
      NSAnimationContext.runAnimationGroup({ c in
        c.duration = fast ? 0.2 : 0.45
        c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.animator().alphaValue = 0
      }, completionHandler: { self.removeFromSuperview(); then() })
    }
  }
  // (for the self-test)
  func geo() -> [String: Any] { ["ready": ready, "leaving": leaving, "age": CACurrentMediaTime() - t0, "layers": icon.sublayers?.count ?? 0] }
}
