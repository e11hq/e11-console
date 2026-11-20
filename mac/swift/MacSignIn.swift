#if APPSTORE
import AppKit
import WebKit
import LocalAuthentication
import Security

/* The Mac app's own sign-in screen (Haris 2026-11-20 12:37: "make the native mac app signing same theme as IOS apps without
   the doodle" — the iPhone apps' NativeSignIn.swift, in AppKit; the window's centred column). It does what our sign-in page
   did, through the same server calls the page made (/oidc/api/start · password · code · owner · setpw · device · who, with
   the sign-in request Cloudflare started), so who may sign in, and how, stays exactly as it was:
   · email and password; no password yet → the admin's 4-digit code (the owner: the owner code), then a new password
   · this Mac's key: "Welcome back" — Touch ID (or the Mac's password), the key instead of the password
   · signing out keeps the key; it goes only when another account signs in on this Mac (or by itself)
   · signed out (or never signed in) on this Mac: the screen at once, the server asked behind it
   Once the server says where to go next, the web view follows it out of sight (Cloudflare's last step) and the screen stays,
   its button turning, with "Signing in…" under it, until the app's own page is back. */

// ---- this Mac's sign-in key (the iPhone's DeviceKey) ----
enum MacKey {
  private static let service = "ae.e11.console.signin"
  private static var account: String { "signin-key:" + (URL(string: SERVER)?.host ?? "") }
  private static func base(_ acc: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: acc,
     kSecUseDataProtectionKeychain as String: true]
  }
  static var key: String? {
    var q = base(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }
  static func keep(_ k: String?) {
    SecItemDelete(base(account) as CFDictionary)
    guard let k = k else { return }
    var add = base(account); add[kSecValueData as String] = Data(k.utf8); add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }
  // signed out on this Mac (or never signed in — the app's first run here): the sign-in screen can come at once
  static var firstRun = false
  static var signedOut: Bool {
    get { defaults.object(forKey: "e11_signin_out_" + (URL(string: SERVER)?.host ?? "")) as? Bool ?? firstRun }
    set { defaults.set(newValue, forKey: "e11_signin_out_" + (URL(string: SERVER)?.host ?? "")) }
  }
  // signed in (the app's page is here): this Mac's key — kept while still good, else a new one; another account's before
  // it let go, here and on the server
  static func refresh(_ store: WKHTTPCookieStore) {
    signedOut = false
    guard let u = URL(string: SERVER + "/api/signin/device") else { return }
    let old = key
    store.getAllCookies { cookies in
      let host = u.host ?? ""
      let mine = cookies.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return host == d || host.hasSuffix("." + d) }
      func post(_ body: [String: Any], _ done: @escaping ([String: Any]?) -> Void) {
        var r = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        HTTPCookie.requestHeaderFields(with: mine).forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { d, _, _ in
          let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
          DispatchQueue.main.async { done(j) }
        }.resume()
      }
      var b: [String: Any] = ["name": Host.current().localizedName ?? "Mac"]
      if let k = old { b["key"] = k }
      post(b) { j in
        guard (j?["ok"] as? Bool) == true, let k = j?["key"] as? String else { return }
        if let o = old, o != k { post(["drop": true, "key": o]) { _ in } }
        if k != key { keep(k) }
      }
    }
  }
}

// ---- the server's calls (the page's), with the request Cloudflare started; a call before it has come waits ----
final class MacSignInAPI {
  var base: String, req: [String: String]
  private var waiting: [() -> Void] = []
  init(base: String, req: [String: String]) { self.base = base; self.req = req }
  func set(base b: String, req r: [String: String]) { base = b; req = r; let w = waiting; waiting = []; w.forEach { $0() } }
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

// ---- E11 Console's side: the screen over the window, and away once the app's page is back ----
enum MacSignIn {
  static var flow: MacSignInFlow?
  static var showing: Bool { flow != nil }

  // our sign-in page about to open: the app's own screen instead
  static func takeOver(_ u: URL, app: App) -> Bool {
    guard u.path == "/oidc/authorize", let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return false }
    var req: [String: String] = [:]
    for it in c.queryItems ?? [] { req[it.name] = it.value ?? "" }
    let base = "\(u.scheme ?? "https")://\(u.host ?? "")"
    MacKey.signedOut = true
    app.endSplash(fast: true)
    if let f = flow { f.api.set(base: base, req: req); if f.begun { f.renewed() } else { f.begin() }; return true }
    let f = make(app: app, base: base, req: req)
    f.screen.alphaValue = 0
    f.begin()
    NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; f.screen.animator().alphaValue = 1 }
    return true
  }
  // signed out on this Mac (or never signed in): the screen at once — "Welcome back" with the name kept from last time,
  // else a small spinner (only after 0.3 s) until the first step; no startup screen before it
  static func prepare(app: App) {
    guard flow == nil else { return }
    let f = make(app: app, base: "", req: [:])
    if f.key != nil, MacSignInFlow.knows(f.key) { f.begin() } else { f.screen.setLoading(true) }
  }
  private static func make(app: App, base: String, req: [String: String]) -> MacSignInFlow {
    let cv = app.window.contentView!
    let f = MacSignInFlow(api: MacSignInAPI(base: base, req: req), frame: cv.bounds)
    f.key = MacKey.key
    f.onRedirect = { [weak app] to in app?.web.load(URLRequest(url: to)) }
    f.onKeyGone = { MacKey.keep(nil) }
    f.onRestart = { [weak app] in app?.loadHome() }
    f.onReview = { [weak app] in dismiss(animated: false); app?.toReview() }
    f.screen.autoresizingMask = [.width, .height]
    cv.addSubview(f.screen, positioned: .above, relativeTo: nil)
    flow = f
    return f
  }
  // the app's own page is back: the screen goes
  static func dismiss(animated: Bool = true) {
    guard let f = flow else { return }
    flow = nil
    let s = f.screen
    s.window?.makeFirstResponder(nil)
    guard animated else { s.removeFromSuperview(); return }
    NSAnimationContext.runAnimationGroup({ c in c.duration = 0.25; s.animator().alphaValue = 0 }, completionHandler: { s.removeFromSuperview() })
  }
}

// ---- what the screen asks and the server's answers (the iPhone's SignInFlow) ----
final class MacSignInFlow {
  let screen: MacSignInScreen
  let api: MacSignInAPI
  var key: String?
  var onRedirect: ((URL) -> Void)?, onKeyGone: (() -> Void)?, onRestart: (() -> Void)?, onReview: (() -> Void)?
  private var email = UserDefaults.standard.string(forKey: "e11_signin_email") ?? ""
  private var owner = false, ticket = ""
  private var who: (name: String, color: NSColor?, photo: NSImage?)?
  // (the person's photo, as the server sent it: data:image/…;base64,…)
  static func photo(_ s: String?) -> NSImage? {
    guard let s = s, let i = s.range(of: "base64,") else { return nil }
    guard let im = Data(base64Encoded: String(s[i.upperBound...])).flatMap(NSImage.init(data:)), im.size.width > 0, im.size.height > 0 else { return nil }
    // (its middle square, to fill the circle)
    let side = min(im.size.width, im.size.height)
    let from = NSRect(x: (im.size.width - side) / 2, y: (im.size.height - side) / 2, width: side, height: side)
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { r in im.draw(in: r, from: from, operation: .copy, fraction: 1); return true }
  }
  private(set) var begun = false

  static func knows(_ key: String?) -> Bool {
    guard let k = key, let w = UserDefaults.standard.dictionary(forKey: "e11_signin_who") else { return false }
    return (w["key"] as? String) == String(k.prefix(12)) && !((w["name"] as? String) ?? "").isEmpty
  }

  init(api: MacSignInAPI, frame: NSRect) {
    self.api = api
    screen = MacSignInScreen(frame: frame)
    screen.onSignIn = { [weak self] e, p in self?.signIn(e, p) }
    screen.onUseCode = { [weak self] e in self?.useCode(e) }
    screen.onCode = { [weak self] c in self?.code(c) }
    screen.onSetPassword = { [weak self] p in self?.setPassword(p) }
    screen.onTouchID = { [weak self] in self?.touchID() }
    screen.onUsePassword = { [weak self] in guard let self = self else { return }; self.screen.show(.form, email: self.email, focusPassword: true) }
    screen.onNotMe = { [weak self] in self?.screen.show(.form, email: "") }
    screen.onBack = { [weak self] in guard let self = self else { return }; self.screen.show(.form, email: self.email) }
    screen.onReview = { [weak self] in self?.onReview?() }
  }

  func begin() {
    begun = true
    guard let k = key else { return screen.show(.form, email: email) }
    if let w = UserDefaults.standard.dictionary(forKey: "e11_signin_who"), (w["key"] as? String) == String(k.prefix(12)),
       let n = w["name"] as? String, !n.isEmpty {
      who = (n, NSColor(signInHex: w["color"] as? String), Self.photo(w["photo"] as? String))
      if let e = w["email"] as? String, !e.isEmpty { email = e }
    }
    var shown = false
    let first = { [weak self] in
      guard let self = self, !shown else { return }
      shown = true
      self.screen.photo = self.who?.photo
      self.screen.show(.welcome, email: self.email, name: self.who?.name, color: self.who?.color)
    }
    api.post("who", ["key": k]) { [weak self] j in
      guard let self = self else { return }
      if (j?["ok"] as? Bool) == true, let n = j?["name"] as? String, !n.isEmpty {
        let ph = j?["photo"] as? String
        let same = self.who?.name == n && (self.who?.photo != nil) == (ph != nil)
        self.who = (n, NSColor(signInHex: j?["color"] as? String), Self.photo(ph))
        if let e = j?["email"] as? String, !e.isEmpty { self.email = e; UserDefaults.standard.set(e, forKey: "e11_signin_email") }
        UserDefaults.standard.set(["key": String(k.prefix(12)), "name": n, "color": j?["color"] as? String ?? "", "email": self.email, "photo": ph ?? ""], forKey: "e11_signin_who")
        if shown, !same { self.screen.photo = self.who?.photo; self.screen.show(.welcome, email: self.email, name: n, color: self.who?.color) }
      }
      first()
    }
    if who != nil { first() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { first() } }
  }
  func renewed() { if screen.isWaiting { screen.setBusy(false); screen.showError("That didn’t work — try again.") } }

  private func failText(_ j: [String: Any]?) -> String {
    guard let j = j else { return "Can’t reach E11 Console. Check your internet connection and try again." }
    let e = j["error"] as? String ?? ""
    if e.hasPrefix("Open E11") { onRestart?(); return "That took a while — please try again." }
    return e.isEmpty ? "That didn’t work — try again." : e
  }
  private func done(_ j: [String: Any]?) {
    if let to = (j?["redirect"] as? String).flatMap(URL.init(string:)) { screen.setWaiting(true); onRedirect?(to) }
    else { screen.setBusy(false); screen.showError(failText(j)) }
  }
  private func signIn(_ e: String, _ p: String) {
    let e = e.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !e.isEmpty else { return screen.showError("Enter your work email.") }
    screen.setBusy(true)
    api.post("start", ["email": e]) { [weak self] j in
      guard let self = self else { return }
      guard (j?["ok"] as? Bool) == true else { self.screen.setBusy(false); return self.screen.showError(self.failText(j)) }
      self.email = j?["email"] as? String ?? e; self.owner = (j?["owner"] as? Bool) == true
      UserDefaults.standard.set(self.email, forKey: "e11_signin_email")
      guard (j?["password"] as? Bool) == true else { self.screen.setBusy(false); return self.screen.show(.code(owner: self.owner), email: self.email) }
      guard !p.isEmpty else { self.screen.setBusy(false); return self.screen.showError("Enter your password.") }
      self.api.post("password", ["email": self.email, "password": p]) { [weak self] j in self?.done(j) }
    }
  }
  private func useCode(_ e: String) {
    let e = e.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !e.isEmpty else { return screen.showError("Enter your work email first.") }
    screen.setBusy(true)
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
  // Touch ID (or the Mac's password), then the key in place of the password
  private func touchID() {
    guard let k = key else { return screen.show(.form, email: email) }
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return screen.show(.form, email: email, focusPassword: true) }
    screen.setBusy(true)
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "sign in to E11 Console") { ok, _ in
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        guard ok else { return self.screen.setBusy(false) }
        self.api.post("device", ["key": k]) { [weak self] j in
          guard let self = self else { return }
          if j?["redirect"] is String { return self.done(j) }
          self.screen.setBusy(false)
          guard j != nil else { return self.screen.showError(self.failText(nil)) }
          self.key = nil; self.onKeyGone?()
          self.screen.show(.form, email: self.email)
          self.screen.showError("Please sign in with your password.")
        }
      }
    }
  }
}

// ---- the screen: the iPhone screen's look — the glow, the icon (or your initials), the greeting, one glass card ----
final class MacSignInScreen: NSView, NSTextFieldDelegate {
  enum Mode: Equatable { case form, code(owner: Bool), setPassword, welcome }
  var onSignIn: ((String, String) -> Void)?, onUseCode: ((String) -> Void)?, onCode: ((String) -> Void)?, onSetPassword: ((String) -> Void)?
  var onTouchID: (() -> Void)?, onUsePassword: (() -> Void)?, onNotMe: (() -> Void)?, onBack: (() -> Void)?, onReview: (() -> Void)?
  private(set) var mode: Mode = .form
  private(set) var isWaiting = false
  private var hasShown = false
  private var name = "", color: NSColor?

  private let bg = CAGradientLayer(), glow = CAGradientLayer()
  private let stack = NSStackView()
  private let avatarCircle = NSView(), avatarImg = NSImageView()
  /// the person's profile photo — in the circle in place of the initials (Haris 2026-11-20 14:13)
  var photo: NSImage?
  private let icon = NSImageView(), avatar = NSView(), avatarL = NSTextField(labelWithString: ""), badge = NSImageView()
  private let greet = NSTextField(labelWithString: ""), titleL = NSTextField(wrappingLabelWithString: ""), sub = NSTextField(wrappingLabelWithString: "")
  private let card = NSView(), sep = NSView()
  private let emailF = NSTextField(), pwF = NSSecureTextField(), pw2F = NSSecureTextField()
  private let icon1 = NSImageView(), icon2 = NSImageView()
  // the code: four boxes, one digit each, as the iPhone's (Haris 2026-11-20 12:46)
  private let codeRow = NSStackView()
  private var boxes: [DigitField] = []
  private let mainB = PillButton(), secondB = PillButton(), linkB = NSButton(title: "", target: nil, action: nil)
  private let errL = NSTextField(wrappingLabelWithString: ""), foot = NSTextField(wrappingLabelWithString: ""), waitL = NSTextField(labelWithString: "Signing in…")
  private let reviewB = NSButton(title: "App Review sign-in", target: nil, action: nil), backB = NSButton(title: "", target: nil, action: nil)
  private let loading = NSProgressIndicator()

  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.addSublayer(bg); layer?.addSublayer(glow)
    glow.type = .radial; glow.startPoint = CGPoint(x: 0.5, y: 0); glow.endPoint = CGPoint(x: 1.4, y: 0.42)
    bg.startPoint = CGPoint(x: 0.5, y: 0); bg.endPoint = CGPoint(x: 0.5, y: 1); bg.locations = [0, 0.55, 1]

    icon.image = NSApp.applicationIconImage; icon.imageScaling = .scaleProportionallyUpOrDown
    avatarCircle.wantsLayer = true; avatarCircle.layer?.cornerRadius = 52; avatarCircle.layer?.borderWidth = 4
    avatarL.font = .systemFont(ofSize: 38, weight: .semibold); avatarL.textColor = .white; avatarL.alignment = .center
    badge.image = NSApp.applicationIconImage; badge.imageScaling = .scaleProportionallyUpOrDown
    badge.wantsLayer = true; badge.layer?.cornerRadius = 10; badge.layer?.masksToBounds = true
    avatarImg.imageScaling = .scaleAxesIndependently; avatarImg.wantsLayer = true; avatarImg.layer?.cornerRadius = 52; avatarImg.layer?.masksToBounds = true; avatarImg.isHidden = true
    for v in [avatarCircle, avatarImg, avatarL, badge] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; avatar.addSubview(v) }

    greet.font = .systemFont(ofSize: 13, weight: .semibold); greet.textColor = .secondaryLabelColor; greet.alignment = .center
    titleL.font = .systemFont(ofSize: 34, weight: .bold); titleL.alignment = .center; titleL.textColor = .labelColor
    sub.font = .systemFont(ofSize: 16); sub.textColor = .secondaryLabelColor; sub.alignment = .center

    card.wantsLayer = true; card.layer?.cornerRadius = 26; card.layer?.borderWidth = 0.5
    for f in [emailF, pwF, pw2F] as [NSTextField] {
      f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none; f.font = .systemFont(ofSize: 17)
      f.delegate = self; f.target = self; f.action = #selector(fieldReturn(_:)); f.cell?.usesSingleLineMode = true; f.cell?.isScrollable = true
      f.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(f)
    }
    for i in [icon1, icon2] { i.contentTintColor = .secondaryLabelColor; i.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(i) }
    sep.wantsLayer = true; sep.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(sep)

    codeRow.orientation = .horizontal; codeRow.spacing = 12
    for i in 0..<4 {
      let b = DigitField()
      b.cell = VCenterCell(textCell: ""); b.isEditable = true; b.isSelectable = true
      b.font = .systemFont(ofSize: 28, weight: .semibold); b.alignment = .center
      b.isBordered = false; b.drawsBackground = false; b.focusRingType = .none; b.wantsLayer = true
      b.layer?.cornerRadius = 12; b.layer?.borderWidth = 0.5; b.delegate = self; b.tag = 100 + i
      b.cell?.usesSingleLineMode = true
      b.onFocus = { [weak self] in self?.markBoxes() }
      b.setAccessibilityLabel("Digit \(i + 1)")
      b.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 58), b.heightAnchor.constraint(equalToConstant: 66)])
      boxes.append(b); codeRow.addArrangedSubview(b)
    }

    mainB.target = self; mainB.action = #selector(mainTapped)
    secondB.target = self; secondB.action = #selector(secondTapped); secondB.filled = false
    linkB.isBordered = false; linkB.target = self; linkB.action = #selector(linkTapped)
    errL.font = .systemFont(ofSize: 14, weight: .medium); errL.textColor = .systemRed; errL.alignment = .center
    foot.font = .systemFont(ofSize: 13); foot.textColor = .secondaryLabelColor; foot.alignment = .center
    waitL.font = .systemFont(ofSize: 14); waitL.textColor = .secondaryLabelColor; waitL.alignment = .center

    reviewB.isBordered = false; reviewB.font = .systemFont(ofSize: 13, weight: .medium); reviewB.contentTintColor = .secondaryLabelColor
    reviewB.target = self; reviewB.action = #selector(reviewTapped); reviewB.setAccessibilityIdentifier("review-sign-in")
    backB.isBordered = false; backB.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
    backB.target = self; backB.action = #selector(backTapped)
    loading.style = .spinning; loading.controlSize = .small; loading.isDisplayedWhenStopped = false

    stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 0
    for v in [icon, avatar, greet, titleL, sub, card, codeRow, errL, mainB, secondB, linkB, foot, waitL] as [NSView] { stack.addArrangedSubview(v) }
    for v in [stack, reviewB, backB, loading] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
    let W: CGFloat = 400
    let center = stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20); center.priority = .defaultLow
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor), center,
      stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 60),
      stack.widthAnchor.constraint(equalToConstant: W),
      icon.widthAnchor.constraint(equalToConstant: 96), icon.heightAnchor.constraint(equalToConstant: 96),
      avatar.widthAnchor.constraint(equalToConstant: 104), avatar.heightAnchor.constraint(equalToConstant: 104),
      avatarCircle.leadingAnchor.constraint(equalTo: avatar.leadingAnchor), avatarCircle.trailingAnchor.constraint(equalTo: avatar.trailingAnchor),
      avatarImg.leadingAnchor.constraint(equalTo: avatar.leadingAnchor), avatarImg.trailingAnchor.constraint(equalTo: avatar.trailingAnchor),
      avatarImg.topAnchor.constraint(equalTo: avatar.topAnchor), avatarImg.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
      avatarCircle.topAnchor.constraint(equalTo: avatar.topAnchor), avatarCircle.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
      avatarL.centerXAnchor.constraint(equalTo: avatar.centerXAnchor), avatarL.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
      badge.widthAnchor.constraint(equalToConstant: 38), badge.heightAnchor.constraint(equalToConstant: 38),
      badge.trailingAnchor.constraint(equalTo: avatar.trailingAnchor), badge.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
      greet.widthAnchor.constraint(equalTo: stack.widthAnchor), titleL.widthAnchor.constraint(equalTo: stack.widthAnchor),
      sub.widthAnchor.constraint(equalTo: stack.widthAnchor), errL.widthAnchor.constraint(equalTo: stack.widthAnchor),
      foot.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28), waitL.widthAnchor.constraint(equalTo: stack.widthAnchor),
      card.widthAnchor.constraint(equalTo: stack.widthAnchor), card.heightAnchor.constraint(equalToConstant: 112.5),
      mainB.widthAnchor.constraint(equalTo: stack.widthAnchor), mainB.heightAnchor.constraint(equalToConstant: 52),
      secondB.widthAnchor.constraint(equalTo: stack.widthAnchor), secondB.heightAnchor.constraint(equalToConstant: 48),
      icon1.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), icon1.centerYAnchor.constraint(equalTo: card.topAnchor, constant: 28),
      icon2.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), icon2.centerYAnchor.constraint(equalTo: card.topAnchor, constant: 84.5),
      icon1.widthAnchor.constraint(equalToConstant: 22), icon2.widthAnchor.constraint(equalToConstant: 22),
      sep.topAnchor.constraint(equalTo: card.topAnchor, constant: 56), sep.heightAnchor.constraint(equalToConstant: 0.5),
      sep.leadingAnchor.constraint(equalTo: card.leadingAnchor), sep.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      reviewB.centerXAnchor.constraint(equalTo: centerXAnchor), reviewB.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
      backB.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 90), backB.centerYAnchor.constraint(equalTo: topAnchor, constant: 24),
      loading.centerXAnchor.constraint(equalTo: centerXAnchor), loading.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    for f in [emailF, pwF, pw2F] as [NSTextField] {
      NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 56), f.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)])
    }
    NSLayoutConstraint.activate([
      emailF.centerYAnchor.constraint(equalTo: icon1.centerYAnchor), pwF.centerYAnchor.constraint(equalTo: icon2.centerYAnchor),
      pw2F.centerYAnchor.constraint(equalTo: icon2.centerYAnchor),
    ])
    stack.setCustomSpacing(26, after: icon); stack.setCustomSpacing(26, after: avatar)
    stack.setCustomSpacing(6, after: greet); stack.setCustomSpacing(6, after: titleL)
    stack.setCustomSpacing(26, after: sub); stack.setCustomSpacing(18, after: card); stack.setCustomSpacing(18, after: codeRow)
    stack.setCustomSpacing(10, after: errL); stack.setCustomSpacing(12, after: mainB); stack.setCustomSpacing(10, after: secondB)
    stack.setCustomSpacing(8, after: linkB); stack.setCustomSpacing(12, after: foot)
    stack.alphaValue = 0; reviewB.alphaValue = 0; backB.isHidden = true   // (nothing until the first step is shown)
    paint()
  }
  required init?(coder: NSCoder) { fatalError() }

  // the colours: the app's light or dark
  private func paint() {
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    effectiveAppearance.performAsCurrentDrawingAppearance {
      bg.colors = (dark ? [hex(0x141320), hex(0x0c0c12), hex(0x09090d)] : [hex(0xf6f6fa), hex(0xfbfbfd), NSColor.white]).map { $0.cgColor }
      let g = NSColor(srgbRed: 110 / 255, green: 96 / 255, blue: 230 / 255, alpha: 1)
      glow.colors = [g.withAlphaComponent(dark ? 0.30 : 0.16).cgColor, g.withAlphaComponent(0).cgColor]
      card.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.white).cgColor
      card.layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.07)).cgColor
      sep.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.08)).cgColor
      avatarCircle.layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.06)).cgColor
      avatarCircle.layer?.backgroundColor = (color ?? g).cgColor
    }
    mainB.paint(); secondB.paint()
    markBoxes()
  }
  // the boxes: the one being typed in has the text's colour round it
  private func markBoxes() {
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    effectiveAppearance.performAsCurrentDrawingAppearance {
      for b in boxes {
        let on = b.currentEditor() != nil
        b.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.white).cgColor
        b.layer?.borderColor = on ? NSColor.labelColor.cgColor : (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.08)).cgColor
        b.layer?.borderWidth = on ? 2 : 0.5
      }
    }
  }
  private func hex(_ v: Int) -> NSColor { NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1) }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); paint() }
  override func layout() {
    super.layout()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    bg.frame = bounds; glow.frame = bounds
    CATransaction.commit()
  }
  // (clicks never reach the page under it)
  override func hitTest(_ p: NSPoint) -> NSView? { super.hitTest(p) ?? self }
  override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(nil) }

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
  private func setIcon(_ v: NSImageView, _ symbol: String) { v.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) }
  private func placeholder(_ f: NSTextField, _ t: String) {
    f.placeholderAttributedString = NSAttributedString(string: t, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 17)])
  }

  // a step: the old one fades out, the new one in
  func show(_ m: Mode, email e: String, name n: String? = nil, color c: NSColor? = nil, focusPassword: Bool = false) {
    mode = m; if let n = n { name = n }; if let c = c { color = c }
    isWaiting = false
    let isForm = m == .form, isSet = m == .setPassword, isCode: Bool = { if case .code = m { return true }; return false }()
    let isPerson = m == .welcome
    let firstTime = !hasShown; hasShown = true
    loading.stopAnimation(nil)
    let commit = {
      self.errL.stringValue = ""; self.errL.isHidden = true; self.waitL.alphaValue = 0
      self.setBusy(false)
      self.icon.isHidden = isPerson; self.avatar.isHidden = !isPerson
      self.greet.isHidden = !(isForm || isPerson); self.greet.stringValue = self.greeting()
      self.card.isHidden = !(isForm || isSet); self.codeRow.isHidden = !isCode
      self.secondB.isHidden = m != .welcome
      self.linkB.isHidden = !(isForm || m == .welcome)
      self.backB.isHidden = !isCode
      self.reviewB.isHidden = !(isForm || isPerson)
      self.emailF.isHidden = isSet; self.pw2F.isHidden = !isSet
      switch m {
      case .form:
        self.titleL.stringValue = "Sign in to\nE11 Console"; self.sub.stringValue = "Your agency’s work, in one place."
        self.mainB.set("Sign In")
        self.link("Use a Sign-in Code")
        self.foot.stringValue = "New here, or forgot your password? Ask your admin for a sign-in code."
        self.setIcon(self.icon1, "envelope"); self.setIcon(self.icon2, "lock")
        self.placeholder(self.emailF, "Email"); self.placeholder(self.pwF, "Password")
        self.emailF.stringValue = e; self.pwF.stringValue = ""
      case .code(let owner):
        self.titleL.stringValue = owner ? "Enter your owner code" : "Enter your code"
        self.sub.stringValue = owner ? "Your own 4 digits, for \(e) — always the same, never runs out" : "The 4-digit sign-in code your admin gave you for \(e)"
        self.mainB.set("Continue")
        self.foot.stringValue = owner ? "Then set a password, and add the team from the owner’s view.\n5 wrong tries lock it for an hour — never for good."
                                      : "A code works once, only for this email, for 24 hours.\nAfter 5 wrong tries it stops — ask for a new one."
        self.boxes.forEach { $0.stringValue = "" }
      case .setPassword:
        self.titleL.stringValue = "Set your password"
        self.sub.stringValue = "The app opens once it’s set. Next time, sign in with your email and this password."
        self.mainB.set("Set Password")
        self.foot.stringValue = "At least 8 characters. Your old password stops working, and you’re signed out everywhere else."
        self.setIcon(self.icon1, "lock"); self.setIcon(self.icon2, "lock")
        self.placeholder(self.pwF, "New password"); self.placeholder(self.pw2F, "Confirm password")
        self.pwF.stringValue = ""; self.pw2F.stringValue = ""
      case .welcome:
        self.titleL.stringValue = self.first.isEmpty ? "Welcome back" : "Welcome back,\n\(self.first)"
        self.sub.stringValue = e
        self.mainB.set("Sign in with Touch ID", symbol: "touchid")
        self.secondB.set("Use Password")
        self.link(self.first.isEmpty ? "Not you?" : "Not \(self.first)?")
        self.foot.stringValue = ""
      }
      self.foot.isHidden = self.foot.stringValue.isEmpty
      self.avatarL.stringValue = Self.initials(self.name)
      self.avatarImg.image = self.photo; self.avatarImg.isHidden = self.photo == nil; self.avatarL.isHidden = self.photo != nil
      self.stack.setCustomSpacing(isPerson ? 70 : 26, after: self.sub)
      self.paint()
      self.layoutSubtreeIfNeeded()
      // (where typing starts)
      if isCode { self.window?.makeFirstResponder(self.boxes[0]) }
      else if isSet { self.window?.makeFirstResponder(self.pwF) }
      else if isForm { self.window?.makeFirstResponder(focusPassword && !e.isEmpty ? self.pwF : self.emailF) }
      else { self.window?.makeFirstResponder(nil) }
    }
    if firstTime {
      commit()
      NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; self.stack.animator().alphaValue = 1; self.reviewB.animator().alphaValue = 1 }
    } else {
      NSAnimationContext.runAnimationGroup({ c in c.duration = 0.12; self.stack.animator().alphaValue = 0 }, completionHandler: {
        commit()
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.2; self.stack.animator().alphaValue = 1 }
      })
    }
  }
  private func link(_ t: String) {
    linkB.attributedTitle = NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.labelColor])
  }
  // (waiting for the server before the first step: a small spinner, only after 0.3 s)
  func setLoading(_ on: Bool) {
    guard on else { loading.stopAnimation(nil); return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self, !self.hasShown else { return }
      self.loading.startAnimation(nil)
    }
  }
  func showError(_ t: String?) {
    errL.stringValue = t ?? ""; errL.isHidden = (t ?? "").isEmpty
    if !errL.isHidden { NSSound.beep() }
  }
  func setBusy(_ on: Bool) {
    mainB.busy = on
    for b in [mainB, secondB, linkB, reviewB, backB] as [NSButton] { b.isEnabled = !on }
    for f in [emailF, pwF, pw2F] + boxes as [NSTextField] { f.isEnabled = !on }
    if on { errL.isHidden = true }
    if !on { isWaiting = false; waitL.alphaValue = 0 }
  }
  // ("Signing in…" fades in its own kept room — the page jumped as it came: Haris 2026-11-20 13:49)
  func setWaiting(_ on: Bool) { setBusy(on); isWaiting = on; window?.makeFirstResponder(nil); NSAnimationContext.runAnimationGroup { c in c.duration = 0.2; waitL.animator().alphaValue = on ? 1 : 0 } }
  func clearCode() { boxes.forEach { $0.stringValue = "" }; window?.makeFirstResponder(boxes[0]) }

  @objc private func mainTapped() {
    switch mode {
    case .form: onSignIn?(emailF.stringValue, pwF.stringValue)
    case .code:
      let c = boxes.map { $0.stringValue }.joined().filter(\.isNumber)
      guard c.count == 4 else { return showError("Enter all 4 digits.") }
      onCode?(c)
    case .setPassword:
      let a = pwF.stringValue, b = pw2F.stringValue
      guard a.count >= 8 else { return showError("At least 8 characters.") }
      guard a == b else { return showError("The two passwords aren’t the same.") }
      onSetPassword?(a)
    case .welcome: onTouchID?()
    }
  }
  @objc private func secondTapped() { onUsePassword?() }
  @objc private func linkTapped() {
    switch mode {
    case .form: onUseCode?(emailF.stringValue)
    case .welcome: onNotMe?()
    default: break
    }
  }
  @objc private func reviewTapped() { onReview?() }
  @objc private func backTapped() { onBack?() }
  // Return: the email → the password; the password → Sign In
  @objc private func fieldReturn(_ f: NSTextField) {
    if f === emailF { window?.makeFirstResponder(pwF) }
    else if f === pwF, mode == .setPassword { window?.makeFirstResponder(pw2F) }
    else { mainTapped() }
  }
  // the code's four boxes: one digit each, on to the next; four pasted go in at once; the fourth sends it (as the iPhone's)
  func controlTextDidChange(_ n: Notification) {
    guard let b = n.object as? DigitField, let i = boxes.firstIndex(of: b) else { return }
    let d = b.stringValue.filter(\.isNumber)
    guard !d.isEmpty else { b.stringValue = ""; return }
    for (j, ch) in d.prefix(4 - i).enumerated() { boxes[i + j].stringValue = String(ch) }
    if boxes.allSatisfy({ !$0.stringValue.isEmpty }) { window?.makeFirstResponder(nil); markBoxes(); mainTapped() }
    else { window?.makeFirstResponder(boxes[min(3, i + d.count)]) }
  }
  // Delete in an empty box goes back to the one before (and clears it); Return sends the code
  func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
    guard let b = c as? DigitField, let i = boxes.firstIndex(of: b) else { return false }
    if sel == #selector(NSResponder.deleteBackward(_:)), b.stringValue.isEmpty, i > 0 {
      boxes[i - 1].stringValue = ""; window?.makeFirstResponder(boxes[i - 1]); return true
    }
    if sel == #selector(NSResponder.insertNewline(_:)) { mainTapped(); return true }
    return false
  }
  func controlTextDidEndEditing(_ n: Notification) { if n.object is DigitField { DispatchQueue.main.async { self.markBoxes() } } }
}

// a text cell whose words sit in the middle of its height (the code's digits sat at the top of their boxes)
final class VCenterCell: NSTextFieldCell {
  private func mid(_ r: NSRect) -> NSRect {
    let h = cellSize(forBounds: r).height
    guard h < r.height else { return r }
    return NSRect(x: r.minX, y: r.minY + (r.height - h) / 2, width: r.width, height: h)
  }
  override func drawingRect(forBounds r: NSRect) -> NSRect { mid(super.drawingRect(forBounds: r)) }
  override func edit(withFrame r: NSRect, in v: NSView, editor t: NSText, delegate d: Any?, event e: NSEvent?) {
    super.edit(withFrame: mid(r), in: v, editor: t, delegate: d, event: e)
  }
  override func select(withFrame r: NSRect, in v: NSView, editor t: NSText, delegate d: Any?, start s: Int, length l: Int) {
    super.select(withFrame: mid(r), in: v, editor: t, delegate: d, start: s, length: l)
  }
}

// one box of the code: tells the screen when it's being typed in (its outline)
final class DigitField: NSTextField {
  var onFocus: (() -> Void)?
  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    DispatchQueue.main.async { self.onFocus?() }
    return ok
  }
}

// the capsule buttons: the main one in the text's colour, the second a soft grey
final class PillButton: NSButton {
  var filled = true
  private let spin = NSProgressIndicator()
  private var label = "", symbol: String?
  var busy = false { didSet { if busy { spin.startAnimation(nil) } else { spin.stopAnimation(nil) }; render() } }
  init() {
    super.init(frame: .zero)
    isBordered = false; wantsLayer = true; layer?.cornerRadius = 26; layer?.cornerCurve = .continuous
    spin.style = .spinning; spin.controlSize = .small; spin.isDisplayedWhenStopped = false
    spin.translatesAutoresizingMaskIntoConstraints = false; addSubview(spin)
    NSLayoutConstraint.activate([spin.centerXAnchor.constraint(equalTo: centerXAnchor), spin.centerYAnchor.constraint(equalTo: centerYAnchor)])
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ t: String, symbol s: String? = nil) { label = t; symbol = s; render() }
  private func render() {
    let fg: NSColor = filled ? dynColor(.white, .black) : .labelColor
    if busy { attributedTitle = NSAttributedString(string: ""); image = nil; return }
    // (the symbol and the words together, in the middle — the symbol sat at the button's left edge: Haris 2026-11-20 13:49)
    let font = NSFont.systemFont(ofSize: 16, weight: filled ? .bold : .semibold)
    let t = NSMutableAttributedString()
    if let s = symbol, let img = NSImage(systemSymbolName: s, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .medium).applying(.init(paletteColors: [fg]))) {
      let a = NSTextAttachment(); a.image = img
      a.bounds = NSRect(x: 0, y: (font.capHeight - img.size.height) / 2, width: img.size.width, height: img.size.height)
      t.append(NSAttributedString(attachment: a)); t.append(NSAttributedString(string: "  ", attributes: [.font: font]))
    }
    t.append(NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: fg]))
    let ps = NSMutableParagraphStyle(); ps.alignment = .center
    t.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: t.length))
    attributedTitle = t; image = nil
    spin.appearance = NSAppearance(named: filled ? (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .aqua : .darkAqua) : effectiveAppearance.name)
  }
  func paint() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = (filled ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.08)).cgColor
    }
    render()
  }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); paint() }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

extension NSColor {
  convenience init?(signInHex h: String?) {
    guard var s = h?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
  }
}
#endif
