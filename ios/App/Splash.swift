import UIKit

/* ================= The startup screen, drawn by the app itself (22+, Haris 2026-10-31) =================
   It shows the moment the app opens — before the page has loaded behind it — in the same design as the page's own
   (web/index.html #splash, styles.css .sp-*): the E11 icon assembling (its pieces rendered from the page's picture by
   ios/tools/splash-layers.js, moved here as the page moves them), the greeting with the first name, today's date,
   "Getting your day ready" with its four rows, the bar, "Tap to skip". The page does the work underneath and tells it
   what to show (the "splash" command: hello / memo / greet / tick / status / out). What it needs before the page is
   there — the look, the name, the CD's row, each day's greeting and sunrise / sunset — the page leaves for the next
   start (memo, kept in UserDefaults). Not here (only on the page): the seasonal looks. */
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

  struct Look {
    let bg, card, line, row, text, dim, hint, track, accent, now, nowInk, spin: UIColor
  }
  static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
  }
  // (styles.css #splash / #splash.light)
  static let dark = Look(bg: hex(0x0c0d0f), card: hex(0x0f1013), line: hex(0x1d1f24), row: hex(0x16171b), text: hex(0xe9eaee), dim: hex(0x8b8e98),
                         hint: hex(0x7d808a), track: hex(0x1d1f24), accent: hex(0x7c6cff), now: hex(0x16152a), nowInk: hex(0xc9c0ff), spin: hex(0x2c2f37))
  static let lightLook = Look(bg: hex(0xffffff), card: hex(0xf7f7f8), line: hex(0xe6e6ea), row: hex(0xefeff2), text: hex(0x17181b), dim: hex(0x6e717a),
                              hint: hex(0x6e717a), track: hex(0xe6e6ea), accent: hex(0x5b4bd6), now: hex(0xf0eeff), nowInk: hex(0x4c3cc7), spin: hex(0xd4d4da))
  static let green = hex(0x3ddc97)

  let light: Bool
  let L: Look
  let t0 = CACurrentMediaTime()
  var onSkip: (() -> Void)?
  var onRetry: (() -> Void)?
  private(set) var leaving = false
  private let reduce = UIAccessibility.isReduceMotionEnabled
  private let icon = CALayer()
  private let greet = UILabel(), date = UILabel()
  private let card = UIView(), head = UIView(), headL = UILabel(), headN = UILabel()
  private var rows: [SplashRow] = []
  private let bar = UIView(), barFill = UIView()
  private let hint = UILabel()
  private let warn = UIView(), warnL = UILabel(), retry = UIButton(type: .system)
  private var barFrac: CGFloat = 0
  private var ticked = 0

  init(memo m: [String: Any]) {
    let today = (m["days"] as? [String: Any])?[SplashView.dayKey()] as? [String: Any]
    let mode = m["themeMode"] as? String ?? "dark"
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
    // the greeting: the day's occasion, or the time of day; with the first name (an occasion that stands alone: without)
    let h = Calendar.current.component(.hour, from: Date())
    let occ = (today?["g"] as? String) ?? ""
    let part = !occ.isEmpty ? occ : h < 5 ? "Working late" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    let name = m["name"] as? String ?? ""
    setGreeting(!name.isEmpty && (today?["alone"] as? Bool) != true ? "\(part), \(name)" : part)
    greet.textColor = L.text; greet.textAlignment = .center; greet.numberOfLines = 1; greet.adjustsFontSizeToFitWidth = true; greet.minimumScaleFactor = 0.7
    let df = DateFormatter(); df.setLocalizedDateFormatFromTemplate("EEEEMMMd")
    date.text = df.string(from: Date()); date.font = .systemFont(ofSize: 13.5); date.textColor = L.dim; date.textAlignment = .center
    addSubview(greet); addSubview(date)
    // the card: "Getting your day ready" and its four rows
    card.backgroundColor = L.card; card.layer.borderColor = L.line.cgColor; card.layer.borderWidth = 1; card.layer.cornerRadius = 10; card.clipsToBounds = true
    headL.text = "Getting your day ready"; headL.font = .systemFont(ofSize: 12); headL.textColor = L.dim
    headN.text = "0/4"; headN.font = .monospacedSystemFont(ofSize: 12, weight: .regular); headN.textColor = L.dim; headN.textAlignment = .right
    head.addSubview(headL); head.addSubview(headN)
    let hl = UIView(); hl.backgroundColor = L.line; hl.tag = 9; head.addSubview(hl)
    card.addSubview(head)
    for (i, t) in ["Clients", "Your tasks", "Inbox", (m["cd"] as? Bool) == true ? "Review requests" : "Client Assets"].enumerated() {
      let r = SplashRow(label: t, look: L, first: i == 0); rows.append(r); card.addSubview(r)
    }
    addSubview(card)
    bar.backgroundColor = L.track; bar.layer.cornerRadius = 1.5; bar.clipsToBounds = true
    barFill.backgroundColor = L.accent; bar.addSubview(barFill); addSubview(bar)
    hint.text = "Tap to skip"; hint.font = .systemFont(ofSize: 11.5); hint.textColor = L.hint; hint.textAlignment = .center
    addSubview(hint)
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
    entrance()
  }
  required init?(coder: NSCoder) { fatalError() }

  func setGreeting(_ s: String) {
    greet.attributedText = NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .kern: -0.39, .foregroundColor: L.text])
    greet.textAlignment = .center
  }

  // ---------- where things go (styles.css .sp-center: one column, centred on the screen) ----------
  private let unit: CGFloat = 132.0 / 824.0          // the icon's picture: 824 units across = 132 pt
  private var canvas: CGFloat { 1024 * unit }        // each piece's picture: 100 units more all round (shadows)
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    let w = min(W - 40, 400)
    let gh = ceil(UIFont.systemFont(ofSize: 26, weight: .semibold).lineHeight), dh = ceil(UIFont.systemFont(ofSize: 13.5).lineHeight)
    let cardH: CGFloat = 1 + 38 + 1 + 46 * 4 + 1
    let total = 132 + 22 + gh + 6 + dh + 30 + cardH + 22 + 3
    var y = ((H - total) / 2).rounded()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    icon.bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    icon.position = CGPoint(x: W / 2, y: y + 66)
    CATransaction.commit()
    y += 132 + 22
    let x = (W - w) / 2
    setFrame(greet, CGRect(x: x - 10, y: y, width: w + 20, height: gh)); y += gh + 6
    setFrame(date, CGRect(x: x, y: y, width: w, height: dh)); y += dh + 30
    setFrame(card, CGRect(x: x, y: y, width: w, height: cardH))
    head.frame = CGRect(x: 0, y: 0, width: w, height: 39)
    headL.frame = CGRect(x: 16, y: 0, width: w - 80, height: 38)
    headN.frame = CGRect(x: w - 76, y: 0, width: 60, height: 38)
    head.viewWithTag(9)?.frame = CGRect(x: 0, y: 38, width: w, height: 1)
    for (i, r) in rows.enumerated() { r.frame = CGRect(x: 0, y: 39 + CGFloat(i) * 46, width: w, height: 46) }
    y += cardH + 22
    setFrame(bar, CGRect(x: x, y: y, width: w, height: 3))
    barFill.frame = CGRect(x: 0, y: 0, width: w * barFrac, height: 3)
    let hb = H - 22 - safeAreaInsets.bottom
    setFrame(hint, CGRect(x: 20, y: hb - 15, width: W - 40, height: 15))
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
  // (a frame set while its entrance animation may run: the animation moves it relative to it)
  private func setFrame(_ v: UIView, _ f: CGRect) { if v.frame != f { v.frame = f } }

  // ---------- the icon assembling (styles.css spFile / spCardG / spCardY / spFront / spTile / spE11 / spLine / spCheck) ----------
  private let easeOut2 = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
  private let spring = CAMediaTimingFunction(controlPoints: 0.3, 1.5, 0.5, 1)
  private let cssEase = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
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
  // the greeting, the date, the card, the bar and the hint come up after the icon (spUp)
  private func entrance() {
    let items: [(UIView, Double)] = [(greet, 1.75), (date, 1.82), (card, 1.9), (bar, 1.95), (hint, 2.2)]
    for (v, d) in items {
      if reduce { continue }
      let up = CAKeyframeAnimation(keyPath: "transform.translation.y"); up.values = [8, 0]; up.keyTimes = [0, 1]; up.timingFunctions = [cssEase]
      let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = [0, 1]; op.keyTimes = [0, 1]; op.timingFunctions = [cssEase]
      let g = CAAnimationGroup(); g.animations = [up, op]; g.duration = 0.5
      g.beginTime = v.layer.convertTime(t0, from: nil) + d; g.fillMode = .both; g.isRemovedOnCompletion = false
      v.layer.add(g, forKey: "up")
    }
  }

  // ---------- what the page says ----------
  func command(_ a: [String: Any]) {
    if let g = a["greet"] as? String, !g.isEmpty { setGreeting(g) }
    if let l4 = a["label4"] as? String, rows.count == 4 { rows[3].setLabel(l4) }
    if let i = a["tick"] as? Int, rows.indices.contains(i) {
      rows.forEach { $0.setNow(false) }
      rows[i].tick(value: a["value"] as? String ?? "")
      rows[i].setNow(true)
      ticked = max(ticked, i + 1)
      headN.text = "\((a["n"] as? Int) ?? i + 1)/\(rows.count)"
      barFrac = CGFloat(ticked) / CGFloat(rows.count)
      UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) { self.barFill.frame.size.width = self.bar.bounds.width * self.barFrac }
    }
    if let st = a["status"] as? String {
      // the connection message in place of "Tap to skip" (with Try again while it's waiting)
      warnL.text = st
      warn.isHidden = st.isEmpty; hint.isHidden = !st.isEmpty
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
    ["light": light, "greet": greet.text ?? "", "date": date.text ?? "", "rows": rows.map { $0.label.text ?? "" }, "values": rows.map { $0.value.text ?? "" },
     "ticked": ticked, "n": headN.text ?? "", "iconLayers": (icon.sublayers?.count ?? 0) + ((icon.sublayers?[3].sublayers?.count) ?? 0),
     "iconTop": icon.position.y - 66, "cardTop": card.frame.minY, "cardBottom": card.frame.maxY, "barBottom": bar.frame.maxY,
     "hint": hint.isHidden ? (warnL.text ?? "") : (hint.text ?? ""), "width": bounds.width, "height": bounds.height]
  }
}

// one row of the card: the spinner (a tick once done), the name, what was found
final class SplashRow: UIView {
  let label = UILabel(), value = UILabel()
  private let L: SplashView.Look
  private let box = CALayer(), spin = CALayer(), ring = CAShapeLayer(), arc = CAShapeLayer(), done = CAShapeLayer(), tickMark = CAShapeLayer(), glow = CAShapeLayer()
  private let nowBar = UIView()
  private var isDone = false, isNow = false
  init(label t: String, look: SplashView.Look, first: Bool) {
    L = look
    super.init(frame: .zero)
    if !first { let line = UIView(); line.backgroundColor = L.row; line.frame = CGRect(x: 0, y: 0, width: 2000, height: 1); line.autoresizingMask = [.flexibleWidth]; addSubview(line) }
    nowBar.backgroundColor = L.accent; nowBar.isHidden = true; addSubview(nowBar)
    label.font = .systemFont(ofSize: 14); setLabel(t)
    value.font = .monospacedSystemFont(ofSize: 12, weight: .regular); value.textColor = L.dim; value.text = "…"; value.textAlignment = .right
    addSubview(label); addSubview(value)
    // the box: a turning ring with an accent quarter (.sp-box), a green tick once done
    let c = CGPoint(x: 9, y: 9)
    glow.path = UIBezierPath(arcCenter: c, radius: 13, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
    glow.fillColor = UIColor(red: 61 / 255, green: 220 / 255, blue: 151 / 255, alpha: 0.18).cgColor; glow.isHidden = true
    ring.path = UIBezierPath(arcCenter: c, radius: 8, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
    ring.fillColor = nil; ring.strokeColor = L.spin.cgColor; ring.lineWidth = 2
    arc.path = UIBezierPath(arcCenter: c, radius: 8, startAngle: -.pi * 3 / 4, endAngle: -.pi / 4, clockwise: true).cgPath
    arc.fillColor = nil; arc.strokeColor = L.accent.cgColor; arc.lineWidth = 2
    spin.frame = CGRect(x: 0, y: 0, width: 18, height: 18); spin.addSublayer(ring); spin.addSublayer(arc)
    let r = CABasicAnimation(keyPath: "transform.rotation.z"); r.fromValue = 0; r.toValue = CGFloat.pi * 2; r.duration = 0.8; r.repeatCount = .infinity
    spin.add(r, forKey: "spin")
    done.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 18, height: 18)).cgPath; done.fillColor = SplashView.green.cgColor
    let k: CGFloat = 10.0 / 16.0, o: CGFloat = 4
    let p = UIBezierPath(); p.move(to: CGPoint(x: o + 3.5 * k, y: o + 8.5 * k)); p.addLine(to: CGPoint(x: o + 6.5 * k, y: o + 11.5 * k)); p.addLine(to: CGPoint(x: o + 12.5 * k, y: o + 4.5 * k))
    tickMark.path = p.cgPath; tickMark.fillColor = nil; tickMark.strokeColor = SplashView.hex(0x0c0d0f).cgColor; tickMark.lineWidth = 2.6 * k; tickMark.lineCap = .round; tickMark.lineJoin = .round
    done.addSublayer(tickMark); done.isHidden = true
    done.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
    box.addSublayer(glow); box.addSublayer(spin); box.addSublayer(done)
    layer.addSublayer(box)
  }
  required init?(coder: NSCoder) { fatalError() }
  func setLabel(_ t: String) { label.attributedText = styled(t) }
  private func styled(_ t: String) -> NSAttributedString {
    var at: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: isDone && !isNow ? L.dim : L.text]
    if isDone && !isNow { at[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; at[.strikethroughColor] = L.spin }
    return NSAttributedString(string: t, attributes: at)
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let h = bounds.height, w = bounds.width
    nowBar.frame = CGRect(x: 0, y: 0, width: 2, height: h)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    box.frame = CGRect(x: 16, y: (h - 18) / 2, width: 18, height: 18)
    CATransaction.commit()
    let vs = value.sizeThatFits(CGSize(width: w, height: h))
    value.frame = CGRect(x: w - 16 - vs.width, y: 0, width: vs.width, height: h)
    label.frame = CGRect(x: 46, y: 0, width: max(0, w - 46 - vs.width - 28), height: h)
  }
  func tick(value v: String) {
    value.text = v
    if !isDone {
      isDone = true
      spin.isHidden = true; done.isHidden = false
      let a = CABasicAnimation(keyPath: "transform.scale"); a.fromValue = 0.5; a.toValue = 1; a.duration = 0.35
      a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.3)
      done.add(a, forKey: "tick")
    }
    setLabel(label.text ?? "")
    setNeedsLayout()
  }
  // the row being ticked: lit up, with an accent edge (.sp-row.now)
  func setNow(_ on: Bool) {
    isNow = on
    UIView.animate(withDuration: 0.25) { self.backgroundColor = on ? self.L.now : .clear }
    nowBar.isHidden = !on
    glow.isHidden = !(on && isDone)
    value.textColor = on ? L.nowInk : L.dim
    setLabel(label.text ?? "")
  }
}
