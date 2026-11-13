import UIKit

/* The startup screen (Haris 2026-11-06: "same like E11 Console but without ticking part"): E11 Console's design — the
   icon putting itself together, the greeting with the first name, today's date, the thin bar filling while the chats
   load, "Tap to skip" — without "Getting your day ready" and its rows. Light or dark as the phone is. It plays out once
   the chat list is ready (from the phone's own copy, so usually at once), straight into Chats. */
final class SplashView: UIView {
  var onDone: (() -> Void)?
  private let tile = CALayer(), bubble = CALayer(), letters = CALayer()
  private let icon = CALayer()
  private let greet = UILabel(), date = UILabel(), hint = UILabel()
  private let bar = UIView(), fill = UIView()
  private var frac: CGFloat = 0
  private var ready = false, minTimeOver = false, leaving = false
  private let reduce = UIAccessibility.isReduceMotionEnabled
  // the first start only (nothing of this account on the phone yet): Apple's spinner and "Setting up your account" in the
  // thin bar's place, once the icon has put itself together — as E11 Console's first start (Haris 2026-11-13)
  private let setupRow = UIStackView(), spinner = UIActivityIndicatorView(style: .medium), setupL = UILabel()
  private var setupOn = false

  static func greeting(_ name: String?) -> String {
    let h = Calendar.current.component(.hour, from: Date())
    let part = h < 5 ? "Working late" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    let first = (name ?? "").split(separator: " ").first.map(String.init) ?? ""
    return first.isEmpty ? part : "\(part), \(first)"
  }

  init(name: String?) {
    super.init(frame: .zero)
    backgroundColor = .systemBackground
    for (l, n) in [(tile, "TalkTile"), (bubble, "TalkBubble"), (letters, "TalkLetters")] {
      l.contents = UIImage(named: n)?.cgImage; l.contentsGravity = .resizeAspect; l.contentsScale = 3
      icon.addSublayer(l)
    }
    layer.addSublayer(icon)
    greet.attributedText = NSAttributedString(string: SplashView.greeting(name), attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .kern: -0.39, .foregroundColor: UIColor.label])
    greet.textAlignment = .center; greet.adjustsFontSizeToFitWidth = true; greet.minimumScaleFactor = 0.7
    let df = DateFormatter(); df.setLocalizedDateFormatFromTemplate("EEEEMMMd")
    date.text = df.string(from: Date()); date.font = .systemFont(ofSize: 13.5); date.textColor = .secondaryLabel; date.textAlignment = .center
    bar.backgroundColor = .tertiarySystemFill; bar.layer.cornerRadius = 1.5; bar.clipsToBounds = true
    fill.backgroundColor = Look.accent; bar.addSubview(fill)
    hint.text = "Tap to skip"; hint.font = .systemFont(ofSize: 11.5); hint.textColor = .tertiaryLabel; hint.textAlignment = .center
    setupL.text = "Setting up your account"
    setupL.font = .preferredFont(forTextStyle: .footnote); setupL.adjustsFontForContentSizeCategory = true; setupL.textColor = .secondaryLabel
    setupRow.axis = .vertical; setupRow.alignment = .center; setupRow.spacing = 12
    setupRow.addArrangedSubview(spinner); setupRow.addArrangedSubview(setupL)
    setupRow.alpha = 0; setupRow.isHidden = true
    [greet, date, bar, hint, setupRow].forEach { addSubview($0) }
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(skip)))
    accessibilityLabel = "E11 Talk is opening"
    assemble()
    progress(0.35)
    DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0.3 : 1.25)) { [weak self] in self?.minTimeOver = true; self?.maybeGo() }
  }
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height, w = min(W - 40, 400)
    let gh = ceil(UIFont.systemFont(ofSize: 26, weight: .semibold).lineHeight), dh = ceil(UIFont.systemFont(ofSize: 13.5).lineHeight)
    let total: CGFloat = 132 + 22 + gh + 6 + dh + 30 + 3
    var y = ((H - total) / 2).rounded()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    icon.frame = CGRect(x: (W - 132) / 2, y: y, width: 132, height: 132)
    for l in [tile, bubble, letters] { l.bounds = CGRect(x: 0, y: 0, width: 132, height: 132); l.position = CGPoint(x: 66, y: 66) }
    CATransaction.commit()
    y += 132 + 22
    greet.frame = CGRect(x: (W - w) / 2 - 10, y: y, width: w + 20, height: gh); y += gh + 6
    date.frame = CGRect(x: (W - w) / 2, y: y, width: w, height: dh); y += dh + 30
    bar.frame = CGRect(x: (W - w) / 2, y: y, width: w, height: 3)
    let rs = setupRow.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    setupRow.frame = CGRect(x: 20, y: y - 6, width: W - 40, height: rs.height)
    fill.frame = CGRect(x: 0, y: 0, width: w * frac, height: 3)
    hint.frame = CGRect(x: 20, y: H - 22 - safeAreaInsets.bottom - 15, width: W - 40, height: 15)
  }

  // the icon putting itself together: the tile, the bubble springing in from below, then the E11 letters
  private func assemble() {
    guard !reduce else { return }
    func anim(_ l: CALayer, _ key: String, from: Any, to: Any, delay: Double, dur: Double, spring: Bool = false) {
      let a: CABasicAnimation
      if spring { let s = CASpringAnimation(keyPath: key); s.damping = 11; s.stiffness = 170; s.mass = 1; a = s; a.duration = s.settlingDuration } else { a = CABasicAnimation(keyPath: key); a.duration = dur; a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1) }
      a.fromValue = from; a.toValue = to; a.beginTime = CACurrentMediaTime() + delay; a.fillMode = .backwards
      l.add(a, forKey: key)
    }
    anim(tile, "transform.scale", from: 0.82, to: 1, delay: 0, dur: 0.45)
    anim(tile, "opacity", from: 0, to: 1, delay: 0, dur: 0.3)
    anim(bubble, "transform.scale", from: 0.3, to: 1, delay: 0.18, dur: 0.6, spring: true)
    anim(bubble, "transform.translation.y", from: 30, to: 0, delay: 0.18, dur: 0.6, spring: true)
    anim(bubble, "opacity", from: 0, to: 1, delay: 0.18, dur: 0.22)
    anim(letters, "transform.scale", from: 0.6, to: 1, delay: 0.5, dur: 0.45, spring: true)
    anim(letters, "opacity", from: 0, to: 1, delay: 0.5, dur: 0.25)
    for v in [greet, date] { v.alpha = 0; v.transform = CGAffineTransform(translationX: 0, y: 8) }
    UIView.animate(withDuration: 0.45, delay: 0.55, options: [.curveEaseOut]) { [weak self] in
      [self?.greet, self?.date].forEach { $0?.alpha = 1; $0?.transform = .identity }
    }
  }
  func progress(_ f: CGFloat) {
    frac = max(frac, min(1, f))
    UIView.animate(withDuration: 0.35) { self.fill.frame.size.width = self.bar.bounds.width * self.frac }
  }
  func setName(_ name: String?) { greet.attributedText = NSAttributedString(string: SplashView.greeting(name), attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .kern: -0.39, .foregroundColor: UIColor.label]); greet.textAlignment = .center }
  // a first start: the spinner and its words take the bar's place once the icon has put itself together
  func setup() {
    guard !setupOn else { return }
    setupOn = true
    DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0 : 0.95)) { [weak self] in
      guard let self = self, !self.leaving else { return }
      self.spinner.startAnimating(); self.setupRow.isHidden = false
      self.setNeedsLayout(); self.layoutIfNeeded()
      UIView.animate(withDuration: 0.3) { self.setupRow.alpha = 1; self.bar.alpha = 0 }
    }
  }
  // the chat list is ready
  func finish() { ready = true; progress(1); maybeGo() }
  private func maybeGo() { if ready && minTimeOver { go() } }
  @objc private func skip() { go() }
  private func go() {
    guard !leaving else { return }
    leaving = true
    progress(1)
    UIView.animate(withDuration: 0.3, delay: 0.1, options: [.curveEaseIn]) { self.alpha = 0 } completion: { _ in self.removeFromSuperview(); self.onDone?() }
  }
}
