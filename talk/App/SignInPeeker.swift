import UIKit

/* The sign-in screen's little peeker (Haris 2026-11-20, as the canvas "Sign-in Peeker" v6: "it has to be same in ios apps").
   The same file in both apps — E11 Console's is purple with two tufts, E11 Talk's blue with an ear.
   · nothing there while the keyboard is down; once the keyboard is up it slides in from the right and rests its hands on
     the keyboard's top edge (its body is under the keyboard — nothing of the app can be over iPhone's keyboard)
   · it breathes, sways, blinks and glances around; its eyes and body go to each key typed (roughly — the standard layout)
   · hold it: it shrinks a little (a medium haptic), arms flap and feet kick as you drag it; swipe: it's flung away
   · the keyboard going down takes it away with it; the keyboard coming up again brings it back (after a swipe too)
   Only decoration: it changes nothing about signing in. Reduce Motion: it doesn't come. */
final class SignInPeeker: UIView {
  private let talk: Bool
  private let fig = CALayer(), hands = CALayer()
  private let grad = CAGradientLayer(), bodyMask = CAShapeLayer(), shine = CAShapeLayer()
  private let tuftL = CAShapeLayer(), tuftR = CAShapeLayer()
  private let footL = CAShapeLayer(), footR = CAShapeLayer()
  private let eyeL = CALayer(), eyeR = CALayer(), pupL = CALayer(), pupR = CALayer()
  private let mouth = CAShapeLayer(), handL = CAShapeLayer(), handR = CAShapeLayer()
  private let clip: CALayer = { let c = CALayer(); c.backgroundColor = UIColor.black.cgColor; return c }()
  private var link: CADisplayLink?

  // where it is — springs, as the canvas
  private var x: CGFloat = 0, y: CGFloat = 0, r: CGFloat = 22, vx: CGFloat = 0, vy: CGFloat = 0, vr: CGFloat = 0
  private var s: CGFloat = 1, vs: CGFloat = 0, sq: CGFloat = 0, vsq: CGFloat = 0, tuft: CGFloat = 0, vtuft: CGFloat = 0
  private var hx: CGFloat = 0, hy: CGFloat = 0, vhx: CGFloat = 0, vhy: CGFloat = 0, foot: CGFloat = 0, vfoot: CGFloat = 0
  private var pL = CGPoint(x: 0, y: 3), pR = CGPoint(x: 0, y: 3)
  private enum Mode { case out, peek, hold, fling, gone }
  private var mode: Mode = .gone
  private var kb: CGRect = .null            // the keyboard, in this view
  private var kbUp = false
  private var grab: (dx: CGFloat, dy: CGFloat, px: CGFloat, py: CGFloat, hist: [(CGPoint, CFTimeInterval)])?
  private var keyLook: (p: CGPoint, t: CFTimeInterval)?
  private var glance: (p: CGPoint, t: CFTimeInterval)?
  private var blinkAt: CFTimeInterval = 0, nextBlink: CFTimeInterval = 0
  private var last: CFTimeInterval = 0
  private var lastText: [ObjectIdentifier: String] = [:]
  private let K: CGFloat = 0.75   // its size: 3/4 of the canvas's (Haris 2026-11-20 10:35: "its too big")
  /// the room it needs above the keyboard: 112 while it's there, 0 once the keyboard's gone
  var onRoom: ((CGFloat) -> Void)?

  init(talk: Bool) {
    self.talk = talk
    super.init(frame: .zero)
    backgroundColor = .clear; isAccessibilityElement = false; accessibilityElementsHidden = true
    isUserInteractionEnabled = true
    build()
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(kbWill(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    nc.addObserver(self, selector: #selector(kbDid(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
    nc.addObserver(self, selector: #selector(kbHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { link?.invalidate() }
  // (off the screen: the frame clock stops, so nothing keeps it)
  override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { stop() } }

  // ---- the drawing: the canvas's shapes, in the canvas's units (origin = the middle of its hands' bottom line) ----
  private func colors() -> (a: UIColor, b: UIColor, hand: UIColor) {
    talk ? (UIColor(red: 0.384, green: 0.714, blue: 1, alpha: 1), UIColor(red: 0.137, green: 0.314, blue: 0.894, alpha: 1), UIColor(red: 0.204, green: 0.424, blue: 0.941, alpha: 1))
         : (UIColor(red: 0.647, green: 0.592, blue: 1, alpha: 1), UIColor(red: 0.353, green: 0.263, blue: 0.875, alpha: 1), UIColor(red: 0.420, green: 0.337, blue: 0.918, alpha: 1))
  }
  private func setup(_ l: CALayer) { l.bounds = CGRect(x: -90, y: -120, width: 180, height: 210); l.anchorPoint = CGPoint(x: 0.5, y: 120.0 / 210.0) }
  private func build() {
    let c = colors(), line = UIColor(red: 10 / 255, green: 10 / 255, blue: 30 / 255, alpha: 0.35).cgColor
    setup(fig); setup(hands)
    layer.addSublayer(fig); layer.addSublayer(hands)
    // feet, behind the body
    for (f, cx) in [(footL, CGFloat(-24)), (footR, CGFloat(24))] {
      f.path = UIBezierPath(ovalIn: CGRect(x: cx - 17, y: 56, width: 34, height: 20)).cgPath
      f.fillColor = c.hand.cgColor; f.strokeColor = line; f.lineWidth = 1.5
      fig.addSublayer(f)
    }
    // tufts (Console) / the ear (Talk), behind the body
    for t in [tuftL, tuftR] { fig.addSublayer(t) }
    if talk {
      tuftR.fillColor = c.b.cgColor; tuftR.strokeColor = c.b.cgColor; tuftR.lineWidth = 2; tuftR.lineJoin = .round
    } else {
      tuftL.strokeColor = UIColor(red: 0.949, green: 0.757, blue: 0.306, alpha: 1).cgColor
      tuftR.strokeColor = UIColor(red: 0.247, green: 0.824, blue: 0.627, alpha: 1).cgColor
      for t in [tuftL, tuftR] { t.fillColor = nil; t.lineWidth = 6; t.lineCap = .round }
    }
    // the body: a soft gradient in its round shape
    grad.type = .radial
    grad.colors = [c.a.cgColor, c.b.cgColor]
    grad.frame = CGRect(x: -62, y: -98, width: 124, height: 162)
    grad.startPoint = CGPoint(x: 0.35, y: 0.25); grad.endPoint = CGPoint(x: 1.2, y: 1.1)
    bodyMask.frame = CGRect(x: 0, y: 0, width: 124, height: 162)
    grad.mask = bodyMask
    fig.addSublayer(grad)
    shine.path = UIBezierPath(ovalIn: CGRect(x: -14, y: -8, width: 28, height: 16)).cgPath
    shine.fillColor = UIColor.white.withAlphaComponent(0.22).cgColor
    shine.position = CGPoint(x: -24, y: -74); shine.setAffineTransform(CGAffineTransform(rotationAngle: -25 * .pi / 180))
    fig.addSublayer(shine)
    // eyes: white, a dark pupil with a glint
    for (e, p, cx) in [(eyeL, pupL, CGFloat(-21)), (eyeR, pupR, CGFloat(21))] {
      e.bounds = CGRect(x: -16, y: -16, width: 32, height: 32); e.position = CGPoint(x: cx, y: -52)
      e.cornerRadius = 16; e.backgroundColor = UIColor.white.cgColor
      p.bounds = CGRect(x: -7.6, y: -7.6, width: 15.2, height: 15.2); p.cornerRadius = 7.6
      p.backgroundColor = UIColor(red: 0.082, green: 0.071, blue: 0.122, alpha: 1).cgColor
      let g = CALayer(); g.frame = CGRect(x: 2.6 - 2.4, y: -2.6 - 2.4, width: 4.8, height: 4.8); g.cornerRadius = 2.4
      g.backgroundColor = UIColor.white.cgColor; p.addSublayer(g)
      e.addSublayer(p); fig.addSublayer(e)
    }
    mouth.lineWidth = 3.4; mouth.lineCap = .round
    mouth.strokeColor = UIColor(red: 0.082, green: 0.071, blue: 0.122, alpha: 1).cgColor
    fig.addSublayer(mouth)
    for cx in [CGFloat(-40), 40] {
      let ch = CAShapeLayer(); ch.path = UIBezierPath(ovalIn: CGRect(x: cx - 6, y: -36, width: 12, height: 12)).cgPath
      ch.fillColor = UIColor(red: 1, green: 0.561, blue: 0.694, alpha: 0.5).cgColor; fig.addSublayer(ch)
    }
    // hands: flat underneath, to rest on the keyboard's edge
    for (h, cx) in [(handL, CGFloat(-30)), (handR, CGFloat(30))] {
      let l = cx - 15, rr = cx + 15, p = UIBezierPath()
      p.move(to: CGPoint(x: l + 3, y: 9)); p.addLine(to: CGPoint(x: rr - 3, y: 9))
      p.addQuadCurve(to: CGPoint(x: rr, y: 6), controlPoint: CGPoint(x: rr, y: 9))
      p.addCurve(to: CGPoint(x: cx, y: -9), controlPoint1: CGPoint(x: rr, y: -3), controlPoint2: CGPoint(x: cx + 9, y: -9))
      p.addCurve(to: CGPoint(x: l, y: 6), controlPoint1: CGPoint(x: cx - 9, y: -9), controlPoint2: CGPoint(x: l, y: -3))
      p.addQuadCurve(to: CGPoint(x: l + 3, y: 9), controlPoint: CGPoint(x: l, y: 9)); p.close()
      for dx in [-8, 0, 8] as [CGFloat] { p.move(to: CGPoint(x: cx + dx, y: dx == 0 ? -3 : -2)); p.addLine(to: CGPoint(x: cx + dx, y: 3)) }
      h.path = p.cgPath; h.fillColor = c.hand.cgColor; h.strokeColor = line; h.lineWidth = 1.5; h.lineJoin = .round; h.lineCap = .round
      hands.addSublayer(h)
    }
    fig.isHidden = true; hands.isHidden = true
  }

  // ---- the keyboard ----
  @objc private func kbWill(_ n: Notification) {
    guard let w = window, let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
    let k = convert(w.convert(end, from: w.screen.coordinateSpace), from: w)
    if k.height > 120, k.minY < bounds.maxY - 1 { kb = k }   // (a hardware keyboard's small bar: not a keyboard to sit on)
  }
  @objc private func kbDid(_ n: Notification) {
    guard !kb.isNull, kb.height > 120, !UIAccessibility.isReduceMotionEnabled else { return }
    kbUp = true; onRoom?(112); comeIn()
  }
  @objc private func kbHide(_ n: Notification) {
    kbUp = false; onRoom?(0)
    if mode == .peek { mode = .out; vx += 200 }
  }
  private func rest() -> (x: CGFloat, y: CGFloat, r: CGFloat) { (bounds.maxX - 64 * K - 28, kb.minY - 9 * K, -6)   // (28 in from the edge: its hands off the keyboard's rounded corner — Haris 11:11) }
  private func outSpot() -> (x: CGFloat, y: CGFloat, r: CGFloat) {
    // with the keyboard going down it sinks with it, so its body stays hidden
    (bounds.maxX + 96 * K, kbUp ? kb.minY - 9 * K : bounds.maxY + 140 * K, 22)
  }
  private func comeIn() {
    guard mode != .hold, mode != .peek else { return }
    if mode == .gone || mode == .fling || (mode == .out && x > bounds.maxX + 60) {
      let o = (bounds.maxX + 96 * K, kb.minY - 9 * K); x = o.0; y = o.1; r = 22; vx = 0; vy = 0; vr = 0
    }
    mode = .peek; vx -= 380; vsq += 4
    fig.isHidden = false; hands.isHidden = false
    start()
  }

  // ---- what you type: its eyes go to that part of the keyboard (the standard layout — roughly) ----
  /// a text field's text changed: the key is what was added (or Delete)
  func typed(in f: UITextField) {
    let id = ObjectIdentifier(f), now = f.text ?? "", was = lastText[id] ?? ""
    lastText[id] = now
    if now.count < was.count { key("⌫", numbers: false) }
    else if now.count == was.count + 1, let ch = now.last { key(String(ch), numbers: false) }
    else { hop() }
  }
  func forget(_ f: UITextField) { lastText[ObjectIdentifier(f)] = f.text ?? "" }
  func key(_ k: String, numbers: Bool) {
    hop()
    guard kbUp, !kb.isNull else { return }
    let w = kb.width, keysTop = kb.maxY - (window?.safeAreaInsets.bottom ?? 0 > 0 ? 75 : 45) - 216
    func row(_ i: CGFloat) -> CGFloat { keysTop + 27 + 54 * i }
    var p = CGPoint(x: kb.midX, y: row(1.5))
    let c = k.lowercased()
    if numbers {
      let pad = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
      if let i = pad.firstIndex(of: c) { p = CGPoint(x: kb.minX + w * (CGFloat(i % 3) * 2 + 1) / 6, y: kb.minY + 30 + CGFloat(i / 3) * 56) }
    } else if c == "⌫" { p = CGPoint(x: kb.minX + w * 0.93, y: row(2)) }
    else if c == "\n" { p = CGPoint(x: kb.minX + w * 0.86, y: row(3)) }
    else if c == " " { p = CGPoint(x: kb.midX, y: row(3)) }
    else {
      let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
      let offs: [CGFloat] = [0, 0.5, 1.5]
      if c.count == 1, let ch = c.first, let ri = rows.firstIndex(where: { $0.contains(ch) }), let ci = rows[ri].firstIndex(of: ch) {
        let n = CGFloat(rows[ri].distance(from: rows[ri].startIndex, to: ci))
        p = CGPoint(x: kb.minX + w * (n + 0.5 + offs[ri]) / 10, y: row(CGFloat(ri)))
      } else if c.first?.isNumber == true || "-/:;()$&@\".,?!'".contains(c) { p = CGPoint(x: kb.minX + w * 0.5, y: row(0.5)) }
    }
    keyLook = (p, CACurrentMediaTime())
  }
  private func hop() { if mode == .peek { vsq += 2.2 } }
  private func gaze(_ now: CFTimeInterval) -> CGPoint {
    if let k = keyLook, now - k.t < 1.4 { return k.p }
    let home = CGPoint(x: bounds.midX - 30, y: kb.minY + 110)
    if glance == nil || now - glance!.t > 1.7 + Double.random(in: 0...0.9) {
      let spots = [home, CGPoint(x: 40, y: kb.minY + 60), CGPoint(x: bounds.maxX - 120, y: kb.minY - 260), CGPoint(x: bounds.midX, y: kb.minY - 330), home]
      glance = (spots.randomElement() ?? home, now)
    }
    return glance?.p ?? home
  }

  // ---- hold and swipe ----
  override func point(inside p: CGPoint, with e: UIEvent?) -> Bool {
    guard mode == .peek || mode == .hold, !fig.isHidden else { return false }
    var q = CGPoint(x: p.x - x, y: p.y - y).applying(CGAffineTransform(rotationAngle: -r * .pi / 180)); q.x /= K; q.y /= K
    return q.x > -58 && q.x < 58 && q.y > -100 && q.y < -4
  }
  override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) {
    guard let p = t.first?.location(in: self), mode == .peek else { return }
    mode = .hold
    grab = (p.x - x, p.y - y, p.x, p.y, [(p, CACurrentMediaTime())])
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    start()
  }
  override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) {
    guard let p = t.first?.location(in: self), mode == .hold, var g = grab else { return }
    g.px = p.x; g.py = p.y; g.hist.append((p, CACurrentMediaTime())); if g.hist.count > 6 { g.hist.removeFirst() }
    grab = g
  }
  override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { release() }
  override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { release() }
  private func release() {
    guard mode == .hold, let g = grab, let a = g.hist.first, let b = g.hist.last else { return }
    grab = nil
    let dt = max(0.016, b.1 - a.1)
    var fx = (b.0.x - a.0.x) / dt, fy = (b.0.y - a.0.y) / dt
    let sp = hypot(fx, fy), rs = rest(), moved = hypot(x - rs.x, y - rs.y)
    if sp > 650 || moved > 150 {
      if sp < 650 { let d = max(1, moved); fx = (x - rs.x) / d * 900; fy = (y - rs.y) / d * 900 }
      mode = .fling; vx = fx; vy = fy; vr = fx * 0.6
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    } else {
      mode = kbUp ? .peek : .out; vsq += 3
    }
  }

  // ---- every frame ----
  private func start() {
    guard link == nil else { return }
    last = CACurrentMediaTime()
    let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
    l.add(to: .main, forMode: .common); link = l
  }
  private func stop() { link?.invalidate(); link = nil }
  private func spring(_ k: CGFloat, _ c: CGFloat, _ dt: CGFloat, _ v: inout CGFloat, _ vv: inout CGFloat, _ to: CGFloat) {
    vv += (k * (to - v) - c * vv) * dt; v += vv * dt
  }
  @objc private func tick(_ l: CADisplayLink) {
    let now = l.timestamp, dt = CGFloat(min(0.033, max(0.001, now - last))); last = now
    if nextBlink == 0 { nextBlink = now + 2.2 }
    switch mode {
    case .peek, .out:
      let t = mode == .peek ? rest() : outSpot(), k: CGFloat = mode == .peek ? 120 : 160, c: CGFloat = mode == .peek ? 14 : 20
      spring(k, c, dt, &x, &vx, t.x); spring(k, c, dt, &y, &vy, t.y)
      var lean = t.r + CGFloat(sin(now / 1.1)) * 1.6
      if mode == .peek { lean += max(-12, min(6, (gaze(now).x - x) * 0.05)) }
      spring(90, 12, dt, &r, &vr, lean)
      if mode == .out, x > bounds.maxX + 80 { mode = .gone }
    case .hold:
      if let g = grab {
        spring(900, 48, dt, &x, &vx, g.px - g.dx); spring(900, 48, dt, &y, &vy, g.py - g.dy)
        spring(200, 16, dt, &r, &vr, max(-30, min(30, vx * 0.03)))
      }
    case .fling:
      x += vx * dt; y += vy * dt; vy += 900 * dt; r += vr * dt
      if x < -160 || x > bounds.maxX + 160 || y > bounds.maxY + 160 || y < -200 { mode = .gone }
    case .gone: break
    }
    if mode == .gone { fig.isHidden = true; hands.isHidden = true; stop(); return }

    spring(260, 18, dt, &s, &vs, mode == .hold ? 0.9 : 1)
    spring(220, 9, dt, &sq, &vsq, 0)
    let speed = hypot(vx, vy), stretch = min(0.16, speed / 5000), breathe = CGFloat(sin(now / 0.62)) * 0.018
    let sy = s * (1 + breathe + sq * 0.05 + stretch), sx = s * (1 - breathe * 0.6 - sq * 0.035 - stretch * 0.5)
    let air = mode == .hold || mode == .fling
    CATransaction.begin(); CATransaction.setDisableActions(true)
    // (its body ends at the keyboard's edge — iPhone's keyboard is see-through, and its body showed behind it; held or
    //  flung, all of it)
    if air { if layer.mask != nil { layer.mask = nil } }
    else { clip.frame = CGRect(x: -200, y: -400, width: bounds.width + 400, height: max(0, (kb.isNull ? bounds.maxY : kb.minY) + 400)); if layer.mask !== clip { layer.mask = clip } }
    fig.position = CGPoint(x: x, y: y)
    fig.transform = CATransform3DScale(CATransform3DMakeRotation(r * .pi / 180, 0, 0, 1), sx * K, sy * K, 1)
    hands.position = fig.position
    hands.transform = air ? fig.transform : CATransform3DMakeScale(s * K, s * K, 1)   // on the keyboard's edge: level
    // the body leans a little with its movement
    let ln = max(-14, min(14, -vx * 0.012)), b = UIBezierPath()
    b.move(to: CGPoint(x: ln, y: -98))
    b.addCurve(to: CGPoint(x: 60, y: 10), controlPoint1: CGPoint(x: 40 + ln, y: -98), controlPoint2: CGPoint(x: 62, y: -50))
    b.addCurve(to: CGPoint(x: 0, y: 64), controlPoint1: CGPoint(x: 58, y: 52), controlPoint2: CGPoint(x: 34, y: 64))
    b.addCurve(to: CGPoint(x: -60, y: 10), controlPoint1: CGPoint(x: -34, y: 64), controlPoint2: CGPoint(x: -58, y: 52))
    b.addCurve(to: CGPoint(x: ln, y: -98), controlPoint1: CGPoint(x: -62, y: -50), controlPoint2: CGPoint(x: -40 + ln, y: -98))
    b.close(); b.apply(CGAffineTransform(translationX: 62, y: 98))   // (into the gradient's own box)
    bodyMask.path = b.cgPath
    // tufts / the ear trail behind the movement
    spring(160, 7, dt, &tuft, &vtuft, max(-30, min(30, -vx * 0.04)))
    func rot(_ p: UIBezierPath, _ a: CGFloat, _ cx: CGFloat, _ cy: CGFloat) -> CGPath {
      p.apply(CGAffineTransform(translationX: -cx, y: -cy).concatenating(CGAffineTransform(rotationAngle: a * .pi / 180)).concatenating(CGAffineTransform(translationX: cx, y: cy)))
      return p.cgPath
    }
    if talk {
      let e = UIBezierPath(); e.move(to: CGPoint(x: 8, y: -90))
      e.addQuadCurve(to: CGPoint(x: 60, y: -112), controlPoint: CGPoint(x: 34, y: -104))
      e.addQuadCurve(to: CGPoint(x: 36, y: -66), controlPoint: CGPoint(x: 50, y: -88)); e.close()
      tuftR.path = rot(e, tuft * 0.6, 26, -82)
    } else {
      let a = UIBezierPath(); a.move(to: CGPoint(x: -22, y: -86)); a.addQuadCurve(to: CGPoint(x: -12, y: -100), controlPoint: CGPoint(x: -26, y: -102))
      tuftL.path = rot(a, tuft, -14, -92)
      let c = UIBezierPath(); c.move(to: CGPoint(x: 16, y: -90)); c.addQuadCurve(to: CGPoint(x: 32, y: -88), controlPoint: CGPoint(x: 26, y: -102))
      tuftR.path = rot(c, tuft * 1.2, 20, -90)
    }
    // hands out at its sides and flapping in the air; feet kicking
    let tw = CGFloat(sin(now / 0.07))
    spring(260, 20, dt, &hx, &vhx, air ? -30 : 0); spring(260, 20, dt, &hy, &vhy, air ? -8 + tw * 7 : 0)
    handL.setAffineTransform(air ? rotAbout(-25 + tw * 20, -30, 0).concatenating(CGAffineTransform(translationX: hx, y: hy)) : CGAffineTransform(translationX: hx, y: hy))
    handR.setAffineTransform(air ? rotAbout(25 - tw * 20, 30, 0).concatenating(CGAffineTransform(translationX: -hx, y: -8 - tw * 7)) : CGAffineTransform(translationX: -hx, y: hy))
    spring(200, 14, dt, &foot, &vfoot, air ? CGFloat(sin(now / 0.085)) * 22 : 0)
    footL.setAffineTransform(rotAbout(foot, -24, 54)); footR.setAffineTransform(rotAbout(-foot, 24, 54))
    // eyes: the key typed (or a glance), your finger while held
    var target: CGPoint?
    if mode == .hold, let g = grab { target = CGPoint(x: g.px, y: g.py + 40) } else if mode == .peek { target = gaze(now) }
    let ra = -r * .pi / 180
    for (pp, cx, pl) in [(pL, CGFloat(-21), pupL), (pR, CGFloat(21), pupR)] {
      var gx: CGFloat = 0, gy: CGFloat = 0
      if let t = target {
        let vx0 = t.x - (x + cx), vy0 = t.y - (y - 52)
        let lx = vx0 * cos(ra) - vy0 * sin(ra), ly = vx0 * sin(ra) + vy0 * cos(ra), d = max(1, hypot(lx, ly)), m = min(8, d / 12)
        gx = lx / d * m; gy = ly / d * m
      }
      var q = pp; q.x += (gx - q.x) * min(1, dt * 22); q.y += (gy - q.y) * min(1, dt * 22)
      if cx < 0 { pL = q } else { pR = q }
      pl.position = CGPoint(x: q.x, y: q.y)
      pl.setAffineTransform(CGAffineTransform(scaleX: mode == .fling ? 0.7 : 1, y: mode == .fling ? 0.7 : 1))
    }
    // blinks now and then (squeezed while flung)
    if now > nextBlink { blinkAt = now; nextBlink = now + 2.4 + Double.random(in: 0...2.6) }
    let bt = (now - blinkAt) / 0.15, lid: CGFloat = mode == .fling ? 0.45 : (bt < 1 ? 1 - CGFloat(sin(bt * .pi)) * 0.92 : 1)
    eyeL.setAffineTransform(CGAffineTransform(scaleX: 1, y: lid)); eyeR.setAffineTransform(CGAffineTransform(scaleX: 1, y: lid))
    // a smile, an "o" while held or flung
    if air { mouth.path = UIBezierPath(ovalIn: CGRect(x: -6, y: -34, width: 12, height: 12)).cgPath; mouth.fillColor = mouth.strokeColor }
    else { let m = UIBezierPath(); m.move(to: CGPoint(x: -8, y: -29)); m.addQuadCurve(to: CGPoint(x: 8, y: -29), controlPoint: CGPoint(x: 0, y: -22)); mouth.path = m.cgPath; mouth.fillColor = nil }
    CATransaction.commit()
  }
  private func rotAbout(_ deg: CGFloat, _ cx: CGFloat, _ cy: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: -cx, y: -cy).concatenating(CGAffineTransform(rotationAngle: deg * .pi / 180)).concatenating(CGAffineTransform(translationX: cx, y: cy))
  }
}
