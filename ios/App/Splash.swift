import UIKit

/* ================= The startup screen, drawn by the app itself (22+, Haris 2026-10-31) =================
   It shows the moment the app opens — before the page has loaded behind it — in the same design as the page's own
   (web/index.html #splash, styles.css .sp-*): the E11 icon assembling (its pieces rendered from the page's picture by
   ios/tools/splash-layers.js, moved here as the page moves them) — only the icon, then it goes (Haris 2026-11-09:
   "Logo only, then go" — the greeting, the date, "Getting your day ready" with its four rows, the bar and "Tap to skip"
   taken away on the iPhone; the website and the Mac keep theirs). A tap still skips it. The page's "splash" command:
   hello / memo / status / out. The look (and sunrise / sunset for Automatic) the page leaves for the next start (memo,
   kept in UserDefaults). Not here (only on the page): the seasonal looks. */
final class SplashView: UIView {
  static let KEY = "e11Splash"
  static func memo() -> [String: Any] {
    guard let d = defaults.data(forKey: KEY), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
    return m
  }
  static func save(_ m: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: m) { defaults.set(d, forKey: KEY) }
  }
  static func dayKey(_ d: Date = Date()) -> String {
    let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
  }

  struct Look { let bg: UIColor }
  static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
  }
  // (styles.css #splash / #splash.light)
  static let dark = Look(bg: hex(0x0c0d0f))
  static let lightLook = Look(bg: hex(0xffffff))
  static let green = hex(0x3ddc97)   // (the green tick — used elsewhere too)

  let light: Bool
  let L: Look
  let t0 = CACurrentMediaTime()
  var onSkip: (() -> Void)?
  var onRetry: (() -> Void)?
  private(set) var leaving = false
  private let reduce = UIAccessibility.isReduceMotionEnabled
  private let icon = CALayer()
  private let warn = UIView(), warnL = UILabel(), retry = UIButton(type: .system)

  init(memo m: [String: Any]) {
    let today = (m["days"] as? [String: Any])?[SplashView.dayKey()] as? [String: Any]
    let mode = FOLLOW_DEVICE ? (DEVICE_LIGHT ? "light" : "dark") : m["themeMode"] as? String ?? "dark"
    if mode == "light" { light = true }
    else if mode == "auto" {
      // (the page's Automatic look: light from sunrise to sunset in Dubai; 6 to 18 when it hasn't said)
      let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
      let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
      let mins = { (s: String?, dflt: Int) -> Int in
        guard let s = s, let i = s.firstIndex(of: ":"), let h = Int(s[..<i]), let mm = Int(s[s.index(after: i)...]) else { return dflt }
        return h * 60 + mm
      }
      light = now >= mins(today?["rise"] as? String, 360) && now < mins(today?["set"] as? String, 1080)
    } else { light = false }
    L = light ? SplashView.lightLook : SplashView.dark
    super.init(frame: .zero)
    backgroundColor = L.bg
    warnL.font = .systemFont(ofSize: 13); warnL.textColor = SplashView.hex(0xf2a33a); warnL.numberOfLines = 2; warnL.textAlignment = .center
    var rc = UIButton.Configuration.filled()
    rc.cornerStyle = .capsule; rc.baseBackgroundColor = SplashView.hex(0x5b4bd6); rc.baseForegroundColor = .white
    rc.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
    rc.attributedTitle = AttributedString("Try again", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 13, weight: .semibold)]))
    retry.configuration = rc
    retry.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
    warn.addSubview(warnL); warn.addSubview(retry); warn.isHidden = true
    addSubview(warn)
    buildIcon()
    layer.addSublayer(icon)
    accessibilityLabel = "E11 Console is opening"
  }
  required init?(coder: NSCoder) { fatalError() }

  // ---------- where things go (styles.css .sp-center: one column, centred on the screen) ----------
  private let unit: CGFloat = 132.0 / 824.0          // the icon's picture: 824 units across = 132 pt
  private var canvas: CGFloat { 1024 * unit }        // each piece's picture: 100 units more all round (shadows)
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    // (the icon alone, in the middle of the screen)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    icon.bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    icon.position = CGPoint(x: W / 2, y: (H / 2).rounded())
    CATransaction.commit()
    let hb = H - 22 - safeAreaInsets.bottom
    // the connection message and Try again, side by side (one under the other when it doesn't fit)
    let rs = retry.sizeThatFits(CGSize(width: 200, height: 40))
    let maxL = W - 40 - rs.width - 10
    let ls = warnL.sizeThatFits(CGSize(width: maxL, height: 100))
    let rowW = ls.width + 10 + rs.width
    let wh = max(ls.height, rs.height)
    warn.frame = CGRect(x: (W - rowW) / 2, y: hb - wh, width: rowW, height: wh)
    warnL.frame = CGRect(x: 0, y: (wh - ls.height) / 2, width: ls.width, height: ls.height)
    retry.frame = CGRect(x: ls.width + 10, y: (wh - rs.height) / 2, width: rs.width, height: rs.height)
  }

  // ---------- the icon assembling (styles.css spFile / spCardG / spCardY / spFront / spTile / spE11 / spLine / spCheck) ----------
  private let easeOut2 = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
  private let spring = CAMediaTimingFunction(controlPoints: 0.3, 1.5, 0.5, 1)
  private func piece(_ name: String, anchor: CGPoint = CGPoint(x: 512, y: 512)) -> CALayer {
    let l = CALayer()
    l.contents = UIImage(named: name)?.cgImage
    l.contentsScale = 3; l.contentsGravity = .resize
    l.bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    l.anchorPoint = CGPoint(x: anchor.x / 1024, y: anchor.y / 1024)
    l.position = CGPoint(x: anchor.x * unit, y: anchor.y * unit)
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
    var files: [CALayer] = []
    for i in 1...5 { let f = piece("SplFile\(i)\(light ? "Light" : "Dark")", anchor: CGPoint(x: 512, y: 505)); f.opacity = 0; icon.addSublayer(f); files.append(f) }
    if reduce { return }
    let deg = CGFloat.pi / 180
    for (i, f) in files.enumerated() {
      let (x, y, r, mx, my) = fly[i]
      keyframes(f, delay: Double(i) * 0.07, dur: 0.82, t: easeOut2, times: [0, 0.12, 0.62, 0.9, 1], [
        ("transform.translation.x", [x, x * 0.8, mx, 0, 0].map { $0 * unit }),
        ("transform.translation.y", [y, y * 0.8, my, 10, 10].map { $0 * unit }),
        ("transform.rotation.z", [r, r * 0.8, r * 0.3, 0, 0].map { $0 * deg }),
        ("transform.scale", [1, 1, 0.8, 0.5, 0.42]),
        ("opacity", [0, 1, 1, 1, 0])])
    }
    keyframes(green, delay: 0.7, dur: 0.52, t: spring, times: [0, 1], [("transform.translation.y", [30 * unit, 0]), ("transform.rotation.z", [-12 * deg, 0]), ("transform.scale", [0.45, 1]), ("opacity", [0, 1])])
    keyframes(yellow, delay: 0.76, dur: 0.52, t: spring, times: [0, 1], [("transform.translation.y", [30 * unit, 0]), ("transform.rotation.z", [10 * deg, 0]), ("transform.scale", [0.45, 1]), ("opacity", [0, 1])])
    keyframes(front, delay: 0.82, dur: 0.56, t: easeOut2, times: [0, 0.7, 1], [("transform.translation.y", [40 * unit, -6 * unit, 0]), ("transform.scale", [0.5, 1.03, 1]), ("opacity", [0, 1, 1])])
    keyframes(tile, delay: 0.9, dur: 0.62, t: easeOut2, times: [0, 0.75, 1], [("transform.scale", [0.55, 1.03, 1]), ("opacity", [0, 1, 1])])
    keyframes(e11, delay: 1.22, dur: 0.42, t: easeOut2, times: [0, 1], [("transform.translation.y", [16 * unit, 0]), ("opacity", [0, 1])])
    keyframes(l1, delay: 1.38, dur: 0.38, t: easeOut2, times: [0, 1], [("transform.scale.x", [0, 1]), ("opacity", [0, 1])])
    keyframes(l2, delay: 1.47, dur: 0.38, t: easeOut2, times: [0, 1], [("transform.scale.x", [0, 1]), ("opacity", [0, 1])])
    keyframes(check, delay: 1.6, dur: 0.38, t: spring, times: [0, 1], [("transform.scale", [0, 1]), ("opacity", [0, 1])])
  }
  // one CSS animation: its keyframes (each stretch with the same timing, as CSS does), held at the first one until it
  // starts (fill-mode both); the layer itself is left as it ends
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
    g.beginTime = l.convertTime(t0, from: nil) + delay
    g.fillMode = .both
    g.isRemovedOnCompletion = false
    for (k, v) in keys where k == "opacity" { l.opacity = Float(v.last ?? 1) }
    l.add(g, forKey: "sp")
  }
  // ---------- what the page says ----------
  func command(_ a: [String: Any]) {
    if let st = a["status"] as? String {
      // the connection message under the icon (with Try again while it's waiting)
      warnL.text = st
      warn.isHidden = st.isEmpty
      retry.isHidden = !((a["retry"] as? Bool) ?? false)
      setNeedsLayout()
    }
  }
  // tapping anywhere: skip (Try again is a button of its own)
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if !leaving { onSkip?() } }
  func leave(fast: Bool = false, then: @escaping () -> Void) {
    if leaving { return }
    leaving = true
    isUserInteractionEnabled = false
    UIView.animate(withDuration: fast ? 0.2 : 0.45, delay: 0, options: [.curveEaseInOut]) {
      self.alpha = 0; self.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
    } completion: { _ in self.removeFromSuperview(); then() }
  }
  // (for the self-test)
  func geo() -> [String: Any] {
    ["light": light, "logoOnly": true, "iconLayers": (icon.sublayers?.count ?? 0) + ((icon.sublayers?[3].sublayers?.count) ?? 0),
     "iconMid": icon.position.y, "warn": warn.isHidden ? "" : (warnL.text ?? ""), "subviews": subviews.count, "width": bounds.width, "height": bounds.height]
  }
}
