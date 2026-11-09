import UIKit

/* ================= The startup screen, drawn by the app itself (22+, Haris 2026-10-31) =================
   Every start: after iPhone's own launch screen (LaunchBackground, both looks), the E11 icon assembling (its pieces
   rendered from the page's picture by ios/tools/splash-layers.js) — only the icon, then it goes (Haris 2026-11-09: "Logo
   only, then go"; the animated logo stays, Haris 2026-11-09). A tap skips it once the app's screens are there.
   Fully the app's (Haris 2026-11-09, the startup screen as page 1): no website driving it; the phone's light / dark, never
   chosen by itself — its colour holds both looks and the files' pictures follow (Look.swift). The first start only (no
   copy on the phone yet): Apple's spinner and "Setting up your account" under the logo until the copy is in. No
   connection then: Apple's own unavailable view, "Can't reach E11", with Try again. */
final class SplashView: UIView {
  static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
  }
  // (styles.css #splash / #splash.light — one colour holding both looks, as iPhone's own launch screen behind it:
  //  LaunchBackground has the same two)
  static let bg = Look.c(hex(0x0c0d0f), .white)
  static let green = hex(0x3ddc97)   // (the green tick — used elsewhere too)

  let t0 = CACurrentMediaTime()
  var onSkip: (() -> Void)?
  var onRetry: (() -> Void)?
  private(set) var leaving = false
  private let reduce = UIAccessibility.isReduceMotionEnabled
  private var iconTime: Double { reduce ? 0.3 : 2.15 }   // (as AppDelegate.quickSplash: the logo on its own until then)
  private let icon = CALayer()
  private var files: [CALayer] = []
  // the first start only (no copy on the phone yet): Apple's spinner and "Setting up your account" under the logo, once it
  // has assembled (Haris 2026-11-09)
  private let setupRow = UIStackView(), spinner = UIActivityIndicatorView(style: .medium), setupL = UILabel()
  private(set) var setupAsked = false, setupSeen = false
  // no connection on a first start: Apple's own "unavailable" view (iOS 17+), with Try again
  private var offlineView: UIView?

  init() {
    super.init(frame: .zero)
    backgroundColor = SplashView.bg
    setupL.text = "Setting up your account"
    setupL.font = .preferredFont(forTextStyle: .footnote); setupL.adjustsFontForContentSizeCategory = true
    setupL.textColor = .secondaryLabel
    setupRow.axis = .vertical; setupRow.alignment = .center; setupRow.spacing = 12
    setupRow.addArrangedSubview(spinner); setupRow.addArrangedSubview(setupL)
    setupRow.alpha = 0; setupRow.isHidden = true
    addSubview(setupRow)
    buildIcon()
    layer.addSublayer(icon)
    accessibilityLabel = "E11 Console is opening"
  }
  required init?(coder: NSCoder) { fatalError() }

  // the five files' pictures are drawn for each look: set in the phone's look, and again when it changes (Apple can't
  // switch a layer's picture by itself — Look.swift)
  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    followLook("files") { [weak self] tc in
      guard let self = self else { return }
      let light = tc.userInterfaceStyle == .light
      CATransaction.begin(); CATransaction.setDisableActions(true)
      for (i, f) in self.files.enumerated() { f.contents = UIImage(named: "SplFile\(i + 1)\(light ? "Light" : "Dark")")?.cgImage }
      CATransaction.commit()
    }
  }

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
    // (the spinner and its words under the logo: the icon's picture is 132 pt high)
    let rs = setupRow.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    setupRow.frame = CGRect(x: 20, y: (H / 2).rounded() + 66 + 28, width: W - 40, height: rs.height)
    offlineView?.frame = bounds
  }

  // ---------- the first start: setting up ----------
  func setup(_ on: Bool) {
    if on == setupAsked { return }
    setupAsked = on
    if !on { spinner.stopAnimating(); setupRow.isHidden = true; setupRow.alpha = 0; return }
    // (once the logo has assembled — it's on its own until then)
    let wait = max(0, iconTime - (CACurrentMediaTime() - t0))
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      guard let self = self, self.setupAsked, !self.leaving else { return }
      self.setupSeen = true
      self.spinner.startAnimating(); self.setupRow.isHidden = false
      self.setNeedsLayout(); self.layoutIfNeeded()
      UIView.animate(withDuration: 0.3) { self.setupRow.alpha = 1 }
    }
  }

  // ---------- no connection on a first start ----------
  func offline(_ on: Bool) {
    if !on {
      guard let v = offlineView else { return }
      offlineView = nil
      UIView.animate(withDuration: 0.25, animations: { v.alpha = 0 }) { _ in v.removeFromSuperview() }
      return
    }
    if let v = offlineView { setOffline(v, trying: false); return }
    let v = makeOffline()
    v.frame = bounds; v.alpha = 0
    addSubview(v); offlineView = v
    UIView.animate(withDuration: 0.25) { v.alpha = 1 }
  }
  // Try again tapped: Apple's spinner in the button until the answer
  func trying() { if let v = offlineView { setOffline(v, trying: true) } }
  private var offTitle: String { "Can’t reach E11" }
  private var offText: String { "Your account sets up the first time you open the app. Check your connection and try again." }
  private func makeOffline() -> UIView {
    if #available(iOS 17.0, *) {
      let v = UIContentUnavailableView(configuration: offlineConfig(trying: false))
      return v
    }
    // (iOS 16: Apple's own parts laid out as the unavailable view does)
    let v = UIView(); v.backgroundColor = SplashView.bg
    let st = UIStackView(); st.axis = .vertical; st.alignment = .center; st.spacing = 8
    let img = UIImageView(image: UIImage(systemName: "wifi.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44)))
    img.tintColor = .secondaryLabel
    let t = UILabel(); t.text = offTitle; let tf = UIFont.preferredFont(forTextStyle: .title2); t.font = tf.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? tf; t.textAlignment = .center
    let d = UILabel(); d.text = offText; d.font = .preferredFont(forTextStyle: .body); d.textColor = .secondaryLabel; d.numberOfLines = 0; d.textAlignment = .center
    let b = UIButton(configuration: retryConfig(trying: false), primaryAction: UIAction { [weak self] _ in self?.onRetry?() })
    b.tag = 17
    [img, t, d, b].forEach { st.addArrangedSubview($0) }
    st.setCustomSpacing(16, after: img); st.setCustomSpacing(20, after: d)
    st.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(st)
    NSLayoutConstraint.activate([st.centerYAnchor.constraint(equalTo: v.centerYAnchor), st.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 40), st.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -40)])
    return v
  }
  private func retryConfig(trying: Bool) -> UIButton.Configuration {
    var b = UIButton.Configuration.gray()
    b.title = "Try again"; b.cornerStyle = .capsule
    b.showsActivityIndicator = trying
    return b
  }
  @available(iOS 17.0, *)
  private func offlineConfig(trying: Bool) -> UIContentUnavailableConfiguration {
    var c = UIContentUnavailableConfiguration.empty()
    c.image = UIImage(systemName: "wifi.slash")
    c.text = offTitle
    c.secondaryText = offText
    c.button = retryConfig(trying: trying)
    c.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.onRetry?() }
    c.background.backgroundColor = SplashView.bg
    return c
  }
  private func setOffline(_ v: UIView, trying: Bool) {
    if #available(iOS 17.0, *), let u = v as? UIContentUnavailableView { u.configuration = offlineConfig(trying: trying); return }
    if let b = v.viewWithTag(17) as? UIButton { b.configuration = retryConfig(trying: trying); b.isEnabled = !trying }
  }

  // ---------- the icon assembling (styles.css spFile / spCardG / spCardY / spFront / spTile / spE11 / spLine / spCheck) ----------
  private let easeOut2 = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
  private let spring = CAMediaTimingFunction(controlPoints: 0.3, 1.5, 0.5, 1)
  private func piece(_ name: String, anchor: CGPoint = CGPoint(x: 512, y: 512)) -> CALayer {
    let l = CALayer()
    if !name.isEmpty { l.contents = UIImage(named: name)?.cgImage }
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
    for _ in 1...5 { let f = piece("", anchor: CGPoint(x: 512, y: 505)); f.opacity = 0; icon.addSublayer(f); files.append(f) }
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
  // tapping anywhere: skip, once the app's screens are there to show (Try again is a button of its own)
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
    var w: CGFloat = 0; SplashView.bg.resolvedColor(with: traitCollection).getWhite(&w, alpha: nil)
    return ["style": traitCollection.userInterfaceStyle == .light ? 1 : 2, "bg": w, "forced": overrideUserInterfaceStyle == .unspecified ? 0 : 1,
     "files": files.filter { $0.contents != nil }.count, "logoOnly": true, "iconLayers": (icon.sublayers?.count ?? 0) + ((icon.sublayers?[3].sublayers?.count) ?? 0),
     "iconMid": icon.position.y, "offline": offlineView != nil, "setupAsked": setupAsked, "setupSeen": setupSeen, "age": CACurrentMediaTime() - t0,
     "width": bounds.width, "height": bounds.height]
  }
}
