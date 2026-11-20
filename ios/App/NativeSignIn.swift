import UIKit
import LocalAuthentication

/* The app's own sign-in screen (Haris 2026-11-20 09:11: "follow exactly the mockup" — native-signin-3 for E11 Console,
   talk-signin-2 for E11 Talk). The same file in both apps. It does what our sign-in page did, through the same server
   calls the page made (/oidc/api/start · password · code · owner · setpw · device · who, with the sign-in request Cloudflare
   started), so who may sign in, and how, stays exactly as it was:
   · email and password; no password yet → the admin's 4-digit code (the owner: the owner code), then a new password
   · this phone's key (E11 Console's, or a client contact's own in E11 Talk): "Welcome back" — Face ID, the key instead of
     the password; "Use Password" and "Not …?" go to the form
   · E11 Talk with E11 Console's key on the phone: "Continue as …" — Face ID, then Console's key
   Once the server says where to go next, the app's web view follows it out of sight (Cloudflare's last step) and the screen
   stays, its button turning, with "Signing in…" under it, until the app's own screens come. */

struct SignInBrand {
  let app: String            // "E11 Console" / "E11 Talk"
  let subtitle: String
  let glow: UIColor          // the soft glow at the top: Console purple, Talk blue
  let emailWord: String      // "work email" / "email" (the page's own words)
  let faceReason: String     // what Face ID says: "Sign in to E11 Console"
}

/// Our sign-in server's own calls — the ones its page made — with the request Cloudflare started (from /oidc/authorize)
final class SignInAPI {
  var base: String
  var req: [String: String]
  init(base: String, req: [String: String]) { self.base = base; self.req = req }
  // (the screen can be up before the sign-in request has come — Haris 2026-11-20 12:07: instant sign-in; a call made
  //  before it waits, and goes the moment it's here)
  private var waiting: [() -> Void] = []
  func set(base b: String, req r: [String: String]) {
    base = b; req = r
    let w = waiting; waiting = []; w.forEach { $0() }
  }
  func post(_ what: String, _ body: [String: Any], _ done: @escaping ([String: Any]?) -> Void) {
    guard !base.isEmpty else { waiting.append { [weak self] in self?.post(what, body, done) }; return }
    guard let u = URL(string: base + "/oidc/api/" + what) else { return done(nil) }
    var b = body; b["req"] = req
    var r = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.httpBody = try? JSONSerialization.data(withJSONObject: b)
    URLSession.shared.dataTask(with: r) { d, _, _ in
      let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      DispatchQueue.main.async { done(j) }
    }.resume()
  }
}

/// What the screen asks and the server's answers — the page's steps, in the app
final class SignInFlow {
  let screen: SignInScreen
  let api: SignInAPI
  let brand: SignInBrand
  var key: String?               // this phone's own key: "Welcome back" + Face ID
  var continueKey: String?       // E11 Talk: E11 Console's key on this phone — "Continue as …"
  var onRedirect: ((URL) -> Void)?
  var onKeyGone: (() -> Void)?   // the phone's own key no longer counts (a password set again, or left the team)
  var onRestart: (() -> Void)?   // the sign-in request ran out: the app asks for a new one (the screen stays)
  var onReview: (() -> Void)?
  private var email = UserDefaults.standard.string(forKey: "e11_signin_email") ?? ""
  private var owner = false
  private var ticket = ""
  private var who: (name: String, color: UIColor?)?

  init(brand: SignInBrand, api: SignInAPI, frame: CGRect) {
    self.brand = brand; self.api = api
    screen = SignInScreen(brand: brand, frame: frame)
    screen.onSignIn = { [weak self] e, p in self?.signIn(e, p) }
    screen.onUseCode = { [weak self] e in self?.useCode(e) }
    screen.onCode = { [weak self] c in self?.code(c) }
    screen.onSetPassword = { [weak self] p in self?.setPassword(p) }
    screen.onFaceID = { [weak self] in self?.faceID() }
    screen.onUsePassword = { [weak self] in guard let self = self else { return }; self.screen.show(.form, email: self.email, focusPassword: true) }
    screen.onNotMe = { [weak self] in self?.screen.show(.form, email: "") }
    screen.onBack = { [weak self] in guard let self = self else { return }; self.screen.show(.form, email: self.email) }
    screen.onReview = { [weak self] in self?.onReview?() }
  }

  // the first screen: "Continue as …" (Talk, with Console's key), "Welcome back" (this phone's key), else the form
  private(set) var begun = false
  /// the name kept from last time for this key — the screen can show "Welcome back, <name>" before the server is asked
  static func knows(_ key: String?) -> Bool {
    guard let k = key, let w = UserDefaults.standard.dictionary(forKey: "e11_signin_who") else { return false }
    return (w["key"] as? String) == String(k.prefix(12)) && !((w["name"] as? String) ?? "").isEmpty
  }
  func begin() {
    begun = true
    if let k = continueKey ?? key {
      // (shown once, with who it is already in — or after 1.5 s without them, the name following when it comes: it
      //  showed "Continue?" first and crossfaded to the name, the two titles over each other — Haris 2026-11-20 10:19)
      let m: SignInScreen.Mode = continueKey != nil ? .continueAs : .welcome
      // (the name kept from the last answer for this key: shown at once — on a cold start the answer came late, and it
      //  said "Welcome back" with no name: Haris 2026-11-20 11:38)
      if let w = UserDefaults.standard.dictionary(forKey: "e11_signin_who"), (w["key"] as? String) == String(k.prefix(12)),
         let n = w["name"] as? String, !n.isEmpty {
        who = (n, UIColor(signInHex: w["color"] as? String))
        if let e = w["email"] as? String, !e.isEmpty { email = e }
      }
      var shown = false
      let first = { [weak self] in
        guard let self = self, !shown else { return }
        shown = true
        self.screen.show(m, email: m == .continueAs && self.who == nil ? "" : self.email, name: self.who?.name, color: self.who?.color)
      }
      api.post("who", ["key": k]) { [weak self] j in
        guard let self = self else { return }
        if (j?["ok"] as? Bool) == true, let n = j?["name"] as? String, !n.isEmpty {
          let same = self.who?.name == n
          self.who = (n, UIColor(signInHex: j?["color"] as? String))
          // (the key's own email — the server says it since 2026-11-20; kept for the form's Email too)
          if let e = j?["email"] as? String, !e.isEmpty { self.email = e; UserDefaults.standard.set(e, forKey: "e11_signin_email") }
          UserDefaults.standard.set(["key": String(k.prefix(12)), "name": n, "color": j?["color"] as? String ?? "", "email": self.email], forKey: "e11_signin_who")
          if shown, !same { self.screen.setPerson(name: n, color: self.who?.color, email: self.email) }
        }
        first()
      }
      if who != nil { first() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { first() } }
    } else {
      screen.show(.form, email: email)
    }
  }
  // the sign-in request was made again (the app's web view came back to our sign-in): the screen stays as it is
  func renewed() { if screen.isWaiting { screen.setBusy(false); screen.showError("That didn’t work — try again.") } }

  private func failText(_ j: [String: Any]?) -> String {
    guard let j = j else { return "Can’t reach \(brand.app). Check your internet connection and try again." }
    let e = j["error"] as? String ?? ""
    if e.hasPrefix("Open E11") { onRestart?(); return "That took a while — please try again." }
    return e.isEmpty ? "That didn’t work — try again." : e
  }
  private func done(_ j: [String: Any]?) {
    if let to = (j?["redirect"] as? String).flatMap(URL.init(string:)) {
      screen.setWaiting(true)
      onRedirect?(to)
    } else { screen.setBusy(false); screen.showError(failText(j)) }
  }

  private func signIn(_ e: String, _ p: String) {
    let e = e.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !e.isEmpty else { return screen.showError("Enter your \(brand.emailWord).") }
    screen.setBusy(true)
    api.post("start", ["email": e]) { [weak self] j in
      guard let self = self else { return }
      guard (j?["ok"] as? Bool) == true else { self.screen.setBusy(false); return self.screen.showError(self.failText(j)) }
      self.email = j?["email"] as? String ?? e; self.owner = (j?["owner"] as? Bool) == true
      UserDefaults.standard.set(self.email, forKey: "e11_signin_email")
      // (no password set yet: the admin's code first, as the page did)
      guard (j?["password"] as? Bool) == true else { self.screen.setBusy(false); return self.screen.show(.code(owner: self.owner), email: self.email) }
      guard !p.isEmpty else { self.screen.setBusy(false); return self.screen.showError("Enter your password.") }
      self.api.post("password", ["email": self.email, "password": p]) { [weak self] j in self?.done(j) }
    }
  }
  private func useCode(_ e: String) {
    let e = e.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !e.isEmpty else { return screen.showError("Enter your \(brand.emailWord) first.") }
    screen.setBusy(true, link: true)
    api.post("start", ["email": e]) { [weak self] j in
      guard let self = self else { return }
      self.screen.setBusy(false)
      guard (j?["ok"] as? Bool) == true else { return self.screen.showError(self.failText(j)) }
      self.email = j?["email"] as? String ?? e; self.owner = (j?["owner"] as? Bool) == true
      UserDefaults.standard.set(self.email, forKey: "e11_signin_email")
      self.screen.show(.code(owner: self.owner), email: self.email)
    }
  }
  private func code(_ c: String) {
    screen.setBusy(true)
    api.post(owner ? "owner" : "code", ["email": email, "code": c]) { [weak self] j in
      guard let self = self else { return }
      self.screen.setBusy(false)
      guard (j?["ok"] as? Bool) == true, let t = j?["ticket"] as? String else { self.screen.clearCode(); return self.screen.showError(self.failText(j)) }
      self.ticket = t
      self.screen.show(.setPassword, email: self.email)
    }
  }
  private func setPassword(_ p: String) {
    screen.setBusy(true)
    api.post("setpw", ["ticket": ticket, "password": p]) { [weak self] j in self?.done(j) }
  }
  // Face ID (or the passcode), then the key in place of the password
  private func faceID() {
    guard let k = continueKey ?? key else { return screen.show(.form, email: email) }
    let ctx = LAContext(); ctx.localizedFallbackTitle = "Use Passcode"
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return screen.show(.form, email: email, focusPassword: true) }
    screen.setBusy(true)
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: brand.faceReason) { ok, _ in
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        guard ok else { return self.screen.setBusy(false) }   // (cancelled: the screen stays — try again, or Use Password)
        self.api.post("device", ["key": k]) { [weak self] j in
          guard let self = self else { return }
          if j?["redirect"] is String { return self.done(j) }
          self.screen.setBusy(false)
          guard j != nil else { return self.screen.showError(self.failText(nil)) }
          // (the key no longer counts — a password set again with a code, or left the team: gone, and the form)
          if self.continueKey == nil { self.key = nil; self.onKeyGone?() } else { self.continueKey = nil }
          self.screen.show(.form, email: self.email)
          self.screen.showError("Please sign in with your password.")
        }
      }
    }
  }
}

/// The screen itself — the mock-ups: the app's icon (or your initials), the greeting, the title, one glass card, the buttons
final class SignInScreen: UIView, UITextFieldDelegate, UIGestureRecognizerDelegate {
  enum Mode: Equatable { case form, code(owner: Bool), setPassword, welcome, continueAs }
  var onSignIn: ((String, String) -> Void)?
  var onUseCode: ((String) -> Void)?
  var onCode: ((String) -> Void)?
  var onSetPassword: ((String) -> Void)?
  var onFaceID: (() -> Void)?
  var onUsePassword: (() -> Void)?
  var onNotMe: (() -> Void)?
  var onBack: (() -> Void)?
  var onReview: (() -> Void)?
  private(set) var mode: Mode = .form
  private(set) var isWaiting = false
  private var hasShown = false
  private var isPersonNow = false, typingUp = false, kbTop: CGFloat = .greatestFiniteMagnitude
  private let loading = UIActivityIndicatorView(style: .medium)
  private let brand: SignInBrand
  private var email = "", name = "", color: UIColor?

  private let bg = CAGradientLayer(), glow = CAGradientLayer()
  private let scroll = UIScrollView(), stack = UIStackView()
  private let icon = UIImageView(image: UIImage(named: "SignInIcon"))
  private let avatar = UIView(), avatarL = UILabel(), badge = UIImageView(image: UIImage(named: "SignInIcon"))
  private let greet = UILabel(), titleL = UILabel(), sub = UILabel()
  private let card = UIView(), sep = UIView()
  private let f1 = UITextField(), f2 = UITextField()
  private let codeRow = UIStackView()
  private var boxes: [DigitBox] = []
  private let mainB = UIButton(type: .system), secondB = UIButton(type: .system), linkB = UIButton(type: .system)
  private let errL = UILabel(), foot = UILabel(), waitL = UILabel()
  private let reviewB = UIButton(type: .system), backB = UIButton(type: .system)
  private lazy var peeker = SignInPeeker(talk: brand.app == "E11 Talk")   // the little peeker over the keyboard (SignInPeeker.swift)

  init(brand: SignInBrand, frame: CGRect) {
    self.brand = brand
    super.init(frame: frame)
    accessibilityIdentifier = "native-signin"
    layer.addSublayer(bg); layer.addSublayer(glow)
    glow.type = .radial
    glow.startPoint = CGPoint(x: 0.5, y: 0); glow.endPoint = CGPoint(x: 1.4, y: 0.42)
    bg.startPoint = CGPoint(x: 0.5, y: 0); bg.endPoint = CGPoint(x: 0.5, y: 1); bg.locations = [0, 0.55, 1]

    scroll.alwaysBounceVertical = true; scroll.keyboardDismissMode = .interactive; scroll.showsVerticalScrollIndicator = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroll)
    stack.axis = .vertical; stack.alignment = .center; stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)

    // the app's icon — 96, its rounded corners
    icon.contentMode = .scaleAspectFill; icon.clipsToBounds = true
    icon.layer.cornerRadius = 23; icon.layer.cornerCurve = .continuous
    // your initials (Welcome back / Continue as), the app's icon on its corner
    avatar.layer.cornerRadius = 52; avatar.layer.borderWidth = 4
    avatarL.font = .systemFont(ofSize: 38, weight: .semibold); avatarL.textColor = .white; avatarL.textAlignment = .center
    badge.contentMode = .scaleAspectFill; badge.clipsToBounds = true
    badge.layer.cornerRadius = 11; badge.layer.cornerCurve = .continuous; badge.layer.borderWidth = 3
    [avatarL, badge].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; avatar.addSubview($0) }

    greet.font = .systemFont(ofSize: 13, weight: .semibold); greet.textColor = .secondaryLabel; greet.textAlignment = .center
    titleL.font = .systemFont(ofSize: 34, weight: .bold); titleL.textAlignment = .center; titleL.numberOfLines = 0
    titleL.adjustsFontForContentSizeCategory = false
    sub.font = .systemFont(ofSize: 16); sub.textColor = .secondaryLabel; sub.textAlignment = .center; sub.numberOfLines = 0

    // one glass card, two rows
    card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous; card.layer.borderWidth = 0.5
    for f in [f1, f2] {
      f.font = .systemFont(ofSize: 17); f.delegate = self; f.clearButtonMode = .whileEditing
      f.autocorrectionType = .no; f.spellCheckingType = .no
      f.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(f)
      f.addAction(UIAction { [weak self, weak f] _ in if let f = f { self?.peeker.typed(in: f) } }, for: .editingChanged)
    }
    sep.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(sep)

    codeRow.axis = .horizontal; codeRow.spacing = 12
    for i in 0..<4 {
      let b = DigitBox()
      b.font = .systemFont(ofSize: 28, weight: .semibold); b.textAlignment = .center
      b.keyboardType = .numberPad; b.textContentType = i == 0 ? .oneTimeCode : nil
      b.layer.cornerRadius = 12; b.layer.cornerCurve = .continuous
      b.delegate = self; b.tag = 100 + i
      b.onBackEmpty = { [weak self] in self?.backFrom(i) }
      b.accessibilityLabel = "Digit \(i + 1)"
      b.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 58), b.heightAnchor.constraint(equalToConstant: 66)])
      boxes.append(b); codeRow.addArrangedSubview(b)
    }

    var mc = UIButton.Configuration.filled()
    mc.cornerStyle = .capsule; mc.baseBackgroundColor = .label; mc.baseForegroundColor = .systemBackground
    mc.imagePadding = 10; mc.imagePlacement = .leading
    mc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in var a = a; a.font = .systemFont(ofSize: 17, weight: .bold); return a }
    mainB.configuration = mc
    mainB.addAction(UIAction { [weak self] _ in self?.mainTapped() }, for: .primaryActionTriggered)
    var sc = UIButton.Configuration.filled()
    sc.cornerStyle = .capsule; sc.baseBackgroundColor = .tertiarySystemFill; sc.baseForegroundColor = .label
    sc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in var a = a; a.font = .systemFont(ofSize: 17, weight: .semibold); return a }
    secondB.configuration = sc
    secondB.addAction(UIAction { [weak self] _ in self?.endEditing(true); self?.onUsePassword?() }, for: .primaryActionTriggered)
    var lc = UIButton.Configuration.plain(); lc.baseForegroundColor = .label
    lc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in var a = a; a.font = .systemFont(ofSize: 16, weight: .semibold); return a }
    linkB.configuration = lc
    linkB.addAction(UIAction { [weak self] _ in self?.linkTapped() }, for: .primaryActionTriggered)

    errL.font = .systemFont(ofSize: 14, weight: .medium); errL.textColor = .systemRed; errL.textAlignment = .center; errL.numberOfLines = 0
    foot.font = .systemFont(ofSize: 13); foot.textColor = .secondaryLabel; foot.textAlignment = .center; foot.numberOfLines = 0
    waitL.font = .systemFont(ofSize: 14); waitL.textColor = .secondaryLabel; waitL.textAlignment = .center; waitL.text = "Signing in…"

    var rc = UIButton.Configuration.plain(); rc.baseForegroundColor = .secondaryLabel
    rc.attributedTitle = AttributedString("App Review sign-in", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14)]))
    reviewB.configuration = rc
    reviewB.accessibilityIdentifier = "review-sign-in"
    reviewB.addAction(UIAction { [weak self] _ in self?.endEditing(true); self?.onReview?() }, for: .primaryActionTriggered)
    reviewB.translatesAutoresizingMaskIntoConstraints = false
    addSubview(reviewB)

    var bc = UIButton.Configuration.filled(); bc.cornerStyle = .capsule; bc.baseBackgroundColor = .secondarySystemBackground; bc.baseForegroundColor = .label
    bc.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
    backB.configuration = bc
    backB.accessibilityLabel = "Back"
    backB.addAction(UIAction { [weak self] _ in self?.endEditing(true); self?.onBack?() }, for: .primaryActionTriggered)
    backB.translatesAutoresizingMaskIntoConstraints = false
    addSubview(backB)

    // the peeker: over the whole screen, but only its own body takes a touch
    peeker.translatesAutoresizingMaskIntoConstraints = false
    addSubview(peeker)
    // the keyboard up: as the canvas — the icon fades away and the page moves up as one, the card and its button above the
    // keyboard with the peeker's room under them; no scrolling while typing (Haris 2026-11-20 10:35: it scrolled a lot)
    // a tap anywhere away from typing puts the keyboard down, and only that — never the button under the finger (the
    // apps' rule; Haris 2026-11-20 11:09: "how can i put the keyboard down again?")
    let away = UITapGestureRecognizer(target: self, action: #selector(tapAway))
    away.cancelsTouchesInView = true; away.delegate = self
    addGestureRecognizer(away)
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in self?.keyboardMoved(n) }
    nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] n in self?.keyboardMoved(n, gone: true) }

    for v in [icon, avatar, greet, titleL, sub, card, codeRow, errL, mainB, secondB, linkB, foot, waitL] as [UIView] { stack.addArrangedSubview(v) }
    stack.alpha = 0; reviewB.alpha = 0; backB.isHidden = true   // (nothing until the first step is shown)
    loading.hidesWhenStopped = true; loading.translatesAutoresizingMaskIntoConstraints = false; addSubview(loading)
    NSLayoutConstraint.activate([loading.centerXAnchor.constraint(equalTo: centerXAnchor), loading.centerYAnchor.constraint(equalTo: centerYAnchor)])
    let side: CGFloat = 22
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: topAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 60),
      scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -90),
      stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -2 * side).withPriority(.defaultHigh),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
      icon.widthAnchor.constraint(equalToConstant: 96), icon.heightAnchor.constraint(equalToConstant: 96),
      avatar.widthAnchor.constraint(equalToConstant: 104), avatar.heightAnchor.constraint(equalToConstant: 104),
      avatarL.centerXAnchor.constraint(equalTo: avatar.centerXAnchor), avatarL.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
      badge.widthAnchor.constraint(equalToConstant: 38), badge.heightAnchor.constraint(equalToConstant: 38),
      badge.trailingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 4), badge.bottomAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 4),
      greet.widthAnchor.constraint(equalTo: stack.widthAnchor), titleL.widthAnchor.constraint(equalTo: stack.widthAnchor),
      sub.widthAnchor.constraint(equalTo: stack.widthAnchor), errL.widthAnchor.constraint(equalTo: stack.widthAnchor),
      foot.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28), waitL.widthAnchor.constraint(equalTo: stack.widthAnchor),
      card.widthAnchor.constraint(equalTo: stack.widthAnchor),
      mainB.widthAnchor.constraint(equalTo: stack.widthAnchor), mainB.heightAnchor.constraint(equalToConstant: 56),
      secondB.widthAnchor.constraint(equalTo: stack.widthAnchor), secondB.heightAnchor.constraint(equalToConstant: 52),
      f1.topAnchor.constraint(equalTo: card.topAnchor), f1.heightAnchor.constraint(equalToConstant: 56),
      f1.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), f1.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
      sep.topAnchor.constraint(equalTo: f1.bottomAnchor), sep.heightAnchor.constraint(equalToConstant: 0.5),
      sep.leadingAnchor.constraint(equalTo: card.leadingAnchor), sep.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      f2.topAnchor.constraint(equalTo: sep.bottomAnchor), f2.heightAnchor.constraint(equalToConstant: 56),
      f2.leadingAnchor.constraint(equalTo: f1.leadingAnchor), f2.trailingAnchor.constraint(equalTo: f1.trailingAnchor),
      f2.bottomAnchor.constraint(equalTo: card.bottomAnchor),
      reviewB.centerXAnchor.constraint(equalTo: centerXAnchor),
      reviewB.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
      backB.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
      backB.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      backB.widthAnchor.constraint(equalToConstant: 44), backB.heightAnchor.constraint(equalToConstant: 44),
      peeker.topAnchor.constraint(equalTo: topAnchor), peeker.bottomAnchor.constraint(equalTo: bottomAnchor),
      peeker.leadingAnchor.constraint(equalTo: leadingAnchor), peeker.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    // (the spaces between, as the mock-ups)
    stack.setCustomSpacing(26, after: icon); stack.setCustomSpacing(26, after: avatar)
    stack.setCustomSpacing(6, after: greet); stack.setCustomSpacing(6, after: titleL)
    stack.setCustomSpacing(26, after: sub); stack.setCustomSpacing(18, after: card); stack.setCustomSpacing(18, after: codeRow)
    stack.setCustomSpacing(10, after: errL); stack.setCustomSpacing(12, after: mainB); stack.setCustomSpacing(12, after: secondB)
    stack.setCustomSpacing(6, after: linkB); stack.setCustomSpacing(12, after: foot)
    paint()
  }
  required init?(coder: NSCoder) { fatalError() }

  // the colours: the app's light or dark (E11 Console: its own setting; E11 Talk: the phone's)
  private func paint() {
    let t = traitCollection, dark = t.userInterfaceStyle == .dark
    bg.colors = dark ? [UIColor(signInHex: "#141320"), UIColor(signInHex: "#0c0c12"), UIColor(signInHex: "#09090d")].map { ($0 ?? .black).cgColor }
                     : [UIColor(signInHex: "#f6f6fa"), UIColor(signInHex: "#fbfbfd"), UIColor.white].map { ($0 ?? .white).cgColor }
    glow.colors = [brand.glow.withAlphaComponent(dark ? 0.30 : 0.16).cgColor, brand.glow.withAlphaComponent(0).cgColor]
    card.backgroundColor = dark ? UIColor.white.withAlphaComponent(0.08) : .white
    card.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.16) : UIColor.black.withAlphaComponent(0.07)).cgColor
    card.layer.shadowColor = UIColor.black.cgColor; card.layer.shadowOpacity = dark ? 0 : 0.06
    card.layer.shadowRadius = 14; card.layer.shadowOffset = CGSize(width: 0, height: 4)
    sep.backgroundColor = dark ? UIColor.white.withAlphaComponent(0.16) : UIColor.black.withAlphaComponent(0.08)
    for b in boxes {
      b.backgroundColor = dark ? UIColor.white.withAlphaComponent(0.08) : .white
      b.layer.borderColor = b.isFirstResponder ? UIColor.label.resolvedColor(with: t).cgColor : (dark ? UIColor.white.withAlphaComponent(0.16) : UIColor.black.withAlphaComponent(0.08)).cgColor
      b.layer.borderWidth = b.isFirstResponder ? 2 : 0.5
    }
    let base = (dark ? UIColor(signInHex: "#121118") : UIColor(signInHex: "#f6f6fa")) ?? .systemBackground
    avatar.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.22) : UIColor.black.withAlphaComponent(0.06)).cgColor
    badge.layer.borderColor = base.cgColor
    icon.layer.shadowOpacity = 0
    for f in [f1, f2] {
      f.textColor = .label; f.tintColor = .label
      f.attributedPlaceholder = NSAttributedString(string: f.placeholder ?? "", attributes: [.foregroundColor: UIColor.secondaryLabel])
      (f.leftView?.subviews.first as? UIImageView)?.tintColor = .secondaryLabel
    }
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) { super.traitCollectionDidChange(p); paint() }
  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    bg.frame = bounds; glow.frame = bounds
    CATransaction.commit()
  }

  private func greeting() -> String {
    let h = Calendar.current.component(.hour, from: Date())
    return h < 12 ? "GOOD MORNING" : h < 17 ? "GOOD AFTERNOON" : "GOOD EVENING"
  }
  private var first: String { name.split(separator: " ").first.map(String.init) ?? "" }
  private static func initials(_ n: String) -> String {
    // (a middle "Al" skipped, as everywhere: Yousef Al Hwij → YH)
    var w = n.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init).filter { !$0.isEmpty }
    if w.count > 2, w[1].lowercased() == "al" { w.remove(at: 1) }
    let a = w.first?.first.map(String.init) ?? "", b = w.count > 1 ? (w[1].first.map(String.init) ?? "") : ""
    return (a + b).uppercased()
  }
  private func field(_ f: UITextField, _ placeholder: String, symbol: String) {
    f.placeholder = placeholder
    let iv = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)))
    // (the icon, then room before the words — they sat right against it: Haris 2026-11-20 10:35)
    iv.contentMode = .center; iv.frame = CGRect(x: 0, y: 0, width: 26, height: 24)
    let lv = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: 24)); lv.addSubview(iv)
    f.leftView = lv; f.leftViewMode = .always
  }

  // show a step — crossfaded, as the page's steps faded in
  func show(_ m: Mode, email e: String, name n: String? = nil, color c: UIColor? = nil, focusPassword: Bool = false) {
    mode = m; email = e; if let n = n { name = n }; if let c = c { color = c }
    isWaiting = false
    errL.text = nil; errL.isHidden = true; waitL.isHidden = true
    setBusy(false)
    let isForm = m == .form, isSet = m == .setPassword, isCode: Bool = { if case .code = m { return true }; return false }()
    let isPerson = m == .welcome || m == .continueAs
    let firstTime = !hasShown; hasShown = true
    loading.stopAnimating()
    isPersonNow = isPerson
    // (a step that opens the keyboard at once: no icon to show for a moment and take away again)
    let willType = isCode || isSet || (isForm && focusPassword && !e.isEmpty)
    let apply = {
      self.icon.isHidden = isPerson || self.typingUp || willType; self.icon.alpha = (self.typingUp || willType) ? 0 : 1; self.avatar.isHidden = !isPerson
      self.greet.isHidden = !(isForm || isPerson); self.greet.text = self.greeting()
      self.card.isHidden = !(isForm || isSet); self.codeRow.isHidden = !isCode
      self.secondB.isHidden = m != .welcome
      self.linkB.isHidden = !(isForm || m == .welcome)
      self.backB.isHidden = !isCode
      self.reviewB.isHidden = !(isForm || isPerson)
      var mc = self.mainB.configuration
      mc?.image = nil
      switch m {
      case .form:
        self.titleL.text = "Sign in to\n\(self.brand.app)"; self.sub.text = self.brand.subtitle
        mc?.title = "Sign In"
        self.linkB.configuration?.title = "Use a Sign-in Code"
        self.foot.text = "New here, or forgot your password? Ask your admin for a sign-in code."
        self.field(self.f1, "Email", symbol: "envelope"); self.field(self.f2, "Password", symbol: "lock")
        self.f1.text = e; self.f2.text = ""
        self.f1.keyboardType = .emailAddress; self.f1.textContentType = .username; self.f1.autocapitalizationType = .none
        self.f1.isSecureTextEntry = false; self.f1.returnKeyType = .next
        self.f2.keyboardType = .default; self.f2.textContentType = .password; self.f2.isSecureTextEntry = true; self.f2.returnKeyType = .go
      case .code(let owner):
        self.titleL.text = owner ? "Enter your owner code" : "Enter your code"
        self.sub.text = owner ? "Your own 4 digits, for \(e) — always the same, never runs out" : "The 4-digit sign-in code your admin gave you for \(e)"
        mc?.title = "Continue"
        self.foot.text = owner ? "Then set a password, and add the team from the owner’s view.\n5 wrong tries lock it for an hour — never for good."
                               : "A code works once, only for this email, for 24 hours.\nAfter 5 wrong tries it stops — ask for a new one."
        self.boxes.forEach { $0.text = "" }
      case .setPassword:
        self.titleL.text = "Set your password"
        self.sub.text = "The app opens once it’s set. Next time, sign in with your email and this password."
        mc?.title = "Set Password"
        self.foot.text = "At least 8 characters. Your old password stops working, and you’re signed out everywhere else."
        self.field(self.f1, "New password", symbol: "lock"); self.field(self.f2, "Confirm password", symbol: "lock")
        self.f1.text = ""; self.f2.text = ""
        for f in [self.f1, self.f2] { f.keyboardType = .default; f.textContentType = .newPassword; f.isSecureTextEntry = true }
        self.f1.returnKeyType = .next; self.f2.returnKeyType = .go
      case .welcome:
        self.titleL.text = self.first.isEmpty ? "Welcome back" : "Welcome back,\n\(self.first)"
        self.sub.text = e
        mc?.title = "Sign in with \(Self.bioName)"; mc?.image = UIImage(systemName: Self.bioSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        self.secondB.configuration?.title = "Use Password"
        self.linkB.configuration?.title = self.first.isEmpty ? "Not you?" : "Not \(self.first)?"
        self.foot.text = nil
      case .continueAs:
        self.titleL.text = self.first.isEmpty ? "Continue?" : "Continue as\n\(self.first)?"
        self.sub.text = "You’re signed in to E11 Console\non this iPhone" + (e.isEmpty ? "" : " as \(e)")
        mc?.title = self.first.isEmpty ? "Continue" : "Continue as \(self.first)"
        mc?.image = UIImage(systemName: Self.bioSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        self.foot.text = "\(self.brand.app) is always the account E11 Console is signed in as — to change it, sign out of E11 Console."
      }
      self.mainB.configuration = mc
      self.foot.isHidden = (self.foot.text ?? "").isEmpty
      self.avatarL.text = Self.initials(self.name)
      self.avatar.backgroundColor = self.color ?? self.brand.glow
      self.paint()
      self.layoutIfNeeded()
    }
    // the new step put in place, with nothing moving
    let commit = {
      UIView.performWithoutAnimation {
        apply()
        self.stack.setCustomSpacing(isPerson ? 70 : 26, after: self.sub)
        self.layoutIfNeeded()
        // (the top of the page, under the status bar's room — .zero put it under the status bar and it sprang down a
        //  moment later: Haris 2026-11-20 10:19)
        self.scroll.setContentOffset(CGPoint(x: 0, y: -self.scroll.adjustedContentInset.top), animated: false)
        if self.typingUp { self.fitToKeyboard() }
      }
    }
    if firstTime {
      commit()
      UIView.animate(withDuration: 0.25) { self.stack.alpha = 1; self.reviewB.alpha = 1 }
    } else {
      // (the old step fades out, then the new one fades in — a crossfade drew both over each other, the icon over the
      //  picture and the two titles: Haris 2026-11-20 11:38, "Use Password" / "Not you?")
      UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState]) { self.stack.alpha = 0 } completion: { _ in
        commit()
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.stack.alpha = 1 }
      }
    }
    if isCode { DispatchQueue.main.async { self.boxes.first?.becomeFirstResponder() } }
    else if isSet { DispatchQueue.main.async { self.f1.becomeFirstResponder() } }
    else if isForm, focusPassword, !e.isEmpty { DispatchQueue.main.async { self.f2.becomeFirstResponder() } }
  }
  // who "Welcome back" / "Continue as" is, once the server has said
  func setPerson(name n: String, color c: UIColor?, email e: String) {
    guard mode == .welcome || mode == .continueAs else { name = n; color = c; return }
    show(mode, email: e, name: n, color: c)
  }

  private static var bioType: LABiometryType { let c = LAContext(); var e: NSError?; _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e); return c.biometryType }
  private static var bioName: String { switch bioType { case .faceID: return "Face ID"; case .touchID: return "Touch ID"; default: return "Passcode" } }
  private static var bioSymbol: String { switch bioType { case .faceID: return "faceid"; case .touchID: return "touchid"; default: return "lock" } }

  /// waiting for the server before the first step (the first time on this phone): only a small spinner
  // (only after 0.3 s — a quick answer shows no spinner at all: Haris 2026-11-20 12:11)
  func setLoading(_ on: Bool) {
    guard on else { loading.stopAnimating(); return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self, !self.hasShown else { return }
      self.loading.startAnimating()
    }
  }
  func showError(_ t: String?) {
    errL.text = t; errL.isHidden = (t ?? "").isEmpty
    if !errL.isHidden { UINotificationFeedbackGenerator().notificationOccurred(.error) }
  }
  // the button turning while the server answers — everything else waits
  func setBusy(_ on: Bool, link: Bool = false) {
    var c = mainB.configuration; c?.showsActivityIndicator = on && !link; mainB.configuration = c
    for v in [mainB, secondB, linkB, reviewB, backB] as [UIControl] { v.isEnabled = !on }
    [f1, f2].forEach { $0.isEnabled = !on }
    boxes.forEach { $0.isEnabled = !on }
    if on { errL.isHidden = true }
    if !on { isWaiting = false; waitL.isHidden = true }
  }
  // signed in: the server's next page is being followed — the button keeps turning, "Signing in…" under it, until the
  // app's own screens come (Haris 09:12: "if there will be wait user should see something")
  func setWaiting(_ on: Bool) {
    setBusy(on)
    isWaiting = on
    endEditing(true)
    UIView.animate(withDuration: 0.2) { self.waitL.isHidden = !on; self.layoutIfNeeded() }
  }
  func clearCode() { boxes.forEach { $0.text = "" }; boxes.first?.becomeFirstResponder() }

  private func mainTapped() {
    switch mode {
    case .form: endEditing(true); onSignIn?(f1.text ?? "", f2.text ?? "")
    case .code:
      let c = boxes.map { $0.text ?? "" }.joined()
      guard c.count == 4 else { return showError("Enter all 4 digits.") }
      endEditing(true); onCode?(c)
    case .setPassword:
      let a = f1.text ?? "", b = f2.text ?? ""
      guard a.count >= 8 else { return showError("At least 8 characters.") }
      guard a == b else { return showError("The two passwords aren’t the same.") }
      endEditing(true); onSetPassword?(a)
    case .welcome, .continueAs: onFaceID?()
    }
  }
  private func linkTapped() {
    switch mode {
    case .form: endEditing(true); onUseCode?(f1.text ?? "")
    case .welcome: endEditing(true); onNotMe?()
    default: break
    }
  }

  // ---- typing ----
  func textFieldShouldReturn(_ f: UITextField) -> Bool {
    peeker.key("\n", numbers: false)
    if f === f1 { f2.becomeFirstResponder() } else if f === f2 { mainTapped() }
    return false
  }
  func textFieldDidBeginEditing(_ f: UITextField) {
    paint()
    peeker.forget(f)
  }

  // the keyboard came, moved or went: the icon away (or back) and the page placed, with the keyboard's own timing
  private func keyboardMoved(_ n: Notification, gone: Bool = false) {
    guard window != nil else { return }
    var up = false
    if !gone, let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
      let k = convert(end, from: nil)
      up = k.height > 120 && k.minY < bounds.maxY - 50
      if up { kbTop = k.minY }
    }
    let dur = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
    let curve = (n.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
    typingUp = up
    UIView.animate(withDuration: dur, delay: 0, options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState, .allowUserInteraction]) {
      self.fitToKeyboard()
    }
  }
  @objc private func tapAway() { endEditing(true) }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
    guard typingUp else { return false }
    let p = t.location(in: self)
    for v in [card, codeRow] as [UIView] where !v.isHidden { if v.convert(v.bounds, to: self).contains(p) { return false } }
    if peeker.point(inside: convert(p, to: peeker), with: nil) { return false }   // (holding the peeker)
    return true
  }
  private func fitToKeyboard() {
    icon.isHidden = isPersonNow || typingUp; icon.alpha = typingUp ? 0 : 1
    scroll.isScrollEnabled = !typingUp
    layoutIfNeeded()
    let top = -scroll.adjustedContentInset.top
    guard typingUp else { scroll.contentOffset = CGPoint(x: 0, y: top); return }
    // the page's last line just above the keyboard — the peeker sits over its end (Haris 2026-11-20 11:09: there was a lot
    // of room under the last line, "let it cover it, it's fine")
    let room: CGFloat = 14
    let last = [foot, linkB, secondB, mainB].first { !$0.isHidden } ?? mainB
    let bottom = last.convert(last.bounds, to: scroll).maxY - scroll.contentOffset.y + scroll.frame.minY   // (where it is on the screen now)
    let need = bottom + room - kbTop
    // (down too, not only up: with the icon gone the page can be short, and the last line sat well above the keyboard —
    //  Haris 2026-11-20 11:32)
    scroll.contentOffset = CGPoint(x: 0, y: scroll.contentOffset.y + need)
  }
  func textFieldDidEndEditing(_ f: UITextField) { paint() }
  // the code's four boxes: one digit each, on to the next; four pasted (or filled from Messages) go in at once; the
  // fourth sends it, as the page did
  func textField(_ f: UITextField, shouldChangeCharactersIn range: NSRange, replacementString s: String) -> Bool {
    guard let b = f as? DigitBox, let i = boxes.firstIndex(of: b) else { return true }
    let d = s.filter(\.isNumber)
    peeker.key(s.isEmpty ? "⌫" : String(d.last ?? "0"), numbers: true)
    if s.isEmpty { b.text = ""; return false }
    guard !d.isEmpty else { return false }
    for (j, ch) in d.prefix(4 - i).enumerated() { boxes[i + j].text = String(ch) }
    let next = min(3, i + d.count)
    if boxes.allSatisfy({ !($0.text ?? "").isEmpty }) { mainTapped() } else { boxes[next].becomeFirstResponder() }
    return false
  }
  private func backFrom(_ i: Int) {
    guard i > 0 else { return }
    peeker.key("⌫", numbers: true)
    boxes[i - 1].text = ""; boxes[i - 1].becomeFirstResponder()
  }
}

/// one box of the code: Delete on an empty box goes back to the one before
final class DigitBox: UITextField {
  var onBackEmpty: (() -> Void)?
  override func deleteBackward() {
    if (text ?? "").isEmpty { onBackEmpty?() } else { super.deleteBackward() }
  }
  override func caretRect(for position: UITextPosition) -> CGRect { .zero }
}

private extension NSLayoutConstraint {
  func withPriority(_ p: UILayoutPriority) -> NSLayoutConstraint { priority = p; return self }
}
extension UIColor {
  convenience init?(signInHex h: String?) {
    guard var s = h?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
  }
}
