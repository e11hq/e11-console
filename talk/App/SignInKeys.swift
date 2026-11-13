import UIKit
import WebKit
import LocalAuthentication
import Security

/* The shared sign-in (plan: project doc claude/talk-shared-sign-in-plan.md, Haris 2026-11-13).
   · Staff: E11 Talk is always the account E11 Console is signed in as. Console keeps its device key in a Keychain group
     both apps share; on our sign-in page E11 Talk shows board 53 — that person, "Continue as …" — then Face ID, and the
     key signs Talk in. No Console key on the phone: our page as usual.
   · Client contacts (no E11 Console): our page — email, password; the first time the admin's 4-digit code and a new
     password. Then Talk keeps its own device key, and Face ID signs it back in. */
enum SignInKeys {
  // E11 Console's host for this E11 Talk's server (talk-test → test, talk → console)
  static var consoleHost: String { Server.review ? Server.host : Server.host.hasPrefix("talk-test.") ? "test.e11hq.com" : "console.e11hq.com" }
  // the server E11 Console is on and its sign-in's cookies — what Console shares with its widget (its WidgetShare)
  static var consoleSignIn: (server: String, cookie: String)? {
    guard let s = read(service: "ae.e11.console.widget", account: "signin", group: shared), let d = s.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: String], let sv = o["server"], !sv.isEmpty else { return nil }
    return (sv, o["cookie"] ?? "")
  }
  // on the App Review copy: E11 Console's own review sign-in, carried over (its e11_rv cookie) — Haris 2026-11-13 "Both ways"
  static var consoleReviewCookie: String? {
    guard Server.review, let c = consoleSignIn, URL(string: c.server)?.host == Server.host else { return nil }
    return c.cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("e11_rv=") && $0.count > 7 }
  }
  private static var shared: String? { (Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String).flatMap { $0.contains("$(") ? nil : $0 } }
  // E11 Console's key on this phone (its own service and account, in the shared group)
  static var consoleKey: String? { read(service: "ae.e11.console.signin", account: "signin-key:" + consoleHost, group: shared) }
  // E11 Talk's own — a client contact's
  static var ownKey: String? { read(service: "ae.e11.talk.signin", account: "signin-key:" + Server.host, group: nil) }
  static func keepOwn(_ k: String?) { write(k, service: "ae.e11.talk.signin", account: "signin-key:" + Server.host) }

  private static func read(service: String, account: String, group: String?) -> String? {
    var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    if let g = group { q[kSecAttrAccessGroup as String] = g }
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }
  private static func write(_ k: String?, service: String, account: String) {
    let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    SecItemDelete(base as CFDictionary)
    guard let k = k, let d = k.data(using: .utf8) else { return }
    var add = base; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }

  // signed in as a client contact: Talk's own key — kept while still good, else a new one
  static func refreshOwn() {
    guard Talk.shared.isContact else { return }
    var b: [String: Any] = ["name": UIDevice.current.name]
    if let k = ownKey { b["key"] = k }
    Net.shared.post("/api/talk/device", b) { j in
      if (j?["ok"] as? Bool) == true, let k = j?["key"] as? String, k != ownKey { keepOwn(k) }
    }
  }
  // signing out: Talk's own key let go (E11 Console's stays Console's)
  static func dropOwn() {
    guard let k = ownKey else { return }
    Net.shared.post("/api/talk/device", ["drop": true, "key": k]) { _ in }
    keepOwn(nil)
  }
  static func isSigninHost(_ h: String) -> Bool { h.hasPrefix("signin.") || h.hasPrefix("signin-") }
}

/* Board 53: E11 Talk's logo and line; the person E11 Console is signed in as (their picture, name, "Signed in to E11
   Console on this iPhone"); Continue as <first name>; the line under it. Over the sign-in page, until Face ID is done. */
final class ContinueView: UIView {
  var onContinue: (() -> Void)?
  private let logo = UIImageView(image: UIImage(named: "TalkMark")), titleL = UILabel(), sub = UILabel()
  private let card = UIView(), pic = UILabel(), name = UILabel(), line = UILabel()
  private let go = UIButton(type: .system), foot = UILabel()
  init(name n: String, color: UIColor) {
    super.init(frame: .zero)
    backgroundColor = .systemGroupedBackground
    logo.contentMode = .scaleAspectFit
    titleL.text = "E11 Talk"; titleL.font = .systemFont(ofSize: 34, weight: .bold); titleL.textAlignment = .center
    sub.text = "Chats with the team and our clients"; sub.font = .systemFont(ofSize: 17); sub.textColor = .secondaryLabel; sub.textAlignment = .center
    card.backgroundColor = .secondarySystemGroupedBackground; card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous
    pic.text = Look.initials(n); pic.textAlignment = .center; pic.textColor = .white; pic.font = .systemFont(ofSize: 18, weight: .semibold)
    pic.backgroundColor = color; pic.layer.cornerRadius = 25; pic.clipsToBounds = true
    name.text = n; name.font = .systemFont(ofSize: 17, weight: .semibold)
    line.text = "Signed in to E11 Console on this iPhone"; line.font = .systemFont(ofSize: 14); line.textColor = .secondaryLabel; line.numberOfLines = 2
    [pic, name, line].forEach { card.addSubview($0) }
    var c = UIButton.Configuration.filled(); c.cornerStyle = .capsule; c.buttonSize = .large
    c.title = "Continue as " + (n.split(separator: " ").first.map(String.init) ?? n)
    c.baseBackgroundColor = Look.accent
    go.configuration = c
    go.addAction(UIAction { [weak self] _ in self?.onContinue?() }, for: .touchUpInside)
    foot.text = "E11 Talk is always the account E11 Console is signed in as — to change it, sign out of E11 Console. Client contacts (no E11 Console) sign in to E11 Talk only: email, password — the first time, the sign-in code and a new password."
    foot.font = .systemFont(ofSize: 13); foot.textColor = .secondaryLabel; foot.textAlignment = .center; foot.numberOfLines = 0
    [logo, titleL, sub, card, go, foot].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let s = safeAreaInsets, W = bounds.width
    logo.frame = CGRect(x: (W - 84) / 2, y: s.top + 70, width: 84, height: 84)
    titleL.frame = CGRect(x: 20, y: logo.frame.maxY + 24, width: W - 40, height: 41)
    sub.frame = CGRect(x: 20, y: titleL.frame.maxY + 6, width: W - 40, height: 22)
    card.frame = CGRect(x: 16, y: sub.frame.maxY + 40, width: W - 32, height: 82)
    pic.frame = CGRect(x: 16, y: 16, width: 50, height: 50)
    name.frame = CGRect(x: 80, y: 18, width: card.bounds.width - 96, height: 22)
    line.frame = CGRect(x: 80, y: 42, width: card.bounds.width - 96, height: 20)
    go.frame = CGRect(x: 16, y: card.frame.maxY + 24, width: W - 32, height: 52)
    let fh = ceil(foot.sizeThatFits(CGSize(width: W - 64, height: 300)).height)
    foot.frame = CGRect(x: 32, y: bounds.height - s.bottom - 24 - fh, width: W - 64, height: fh)
  }
}

extension SignInVC {
  /* our sign-in page about to open (Cloudflare sent the app to it): named E11 Talk's; with E11 Console's key on this
     phone, board 53 over it; with Talk's own (a client contact's), Face ID straight away; else the page as usual */
  func takeOver(_ u: URL, web: WKWebView) -> Bool {
    guard SignInKeys.isSigninHost(u.host ?? ""), u.path == "/oidc/authorize", var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return false }
    if !(c.queryItems ?? []).contains(where: { $0.name == "app" }) {
      c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "app", value: "talk")]
      if let to = c.url { web.load(URLRequest(url: to)) }
      return true
    }
    guard !passed.contains(u.absoluteString) else { return false }
    var req: [String: String] = [:]
    for it in c.queryItems ?? [] where it.name != "app" { req[it.name] = it.value ?? "" }
    let api = { (what: String) in URL(string: "\(u.scheme ?? "https")://\(u.host ?? "")/oidc/api/\(what)")! }
    let show = { [weak self] in self?.passed.insert(u.absoluteString); self?.cover?.removeFromSuperview(); self?.cover = nil; web.load(URLRequest(url: u)) }
    let post = { (what: String, body: [String: Any], done: @escaping ([String: Any]?) -> Void) in
      var r = URLRequest(url: api(what), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
      r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
      r.httpBody = try? JSONSerialization.data(withJSONObject: body)
      URLSession.shared.dataTask(with: r) { d, _, _ in
        let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        DispatchQueue.main.async { done(j) }
      }.resume()
    }
    // (Face ID, then the key in place of the password — our page only if that doesn't work)
    let faceID = { (k: String, own: Bool) in
      let ctx = LAContext(); ctx.localizedFallbackTitle = "Use Passcode"
      var err: NSError?
      guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { show(); return }
      ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Sign in to E11 Talk") { ok, _ in
        DispatchQueue.main.async {
          guard ok else { if own { show() }; return }   // (cancelled: board 53 stays, Continue tries again; a client: the page)
          post("device", ["req": req, "key": k]) { j in
            if (j?["ok"] as? Bool) == true, let to = (j?["redirect"] as? String).flatMap(URL.init(string:)) { web.load(URLRequest(url: to)); return }
            if own, j != nil { SignInKeys.keepOwn(nil) }   // (Talk's own key no longer counts: gone)
            show()
          }
        }
      }
    }
    if let k = SignInKeys.consoleKey {
      UserDefaults.standard.set(true, forKey: "talk_via_console")   // (signed in through E11 Console: it signs Talk out too)
      post("who", ["req": req, "key": k]) { [weak self] j in
        guard let self = self, (j?["ok"] as? Bool) == true, let n = j?["name"] as? String else { show(); return }
        let v = ContinueView(name: n, color: Look.hex(j?["color"] as? String) ?? Look.accent)
        v.frame = self.view.bounds; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]; v.alpha = 0
        v.onContinue = { faceID(k, false) }
        self.cover?.removeFromSuperview(); self.cover = v
        self.view.addSubview(v)
        UIView.animate(withDuration: Crossfade.time) { v.alpha = 1 }
      }
      return true
    }
    if let k = SignInKeys.ownKey { faceID(k, true); return true }
    return false
  }
}

/* A client contact's sign-in code (board 51, the approved "Sign-in — fully Apple" sheet, as E11 Console's): Apple's sheet
   with Sign-in Code · Done; the person; the four digits (each box its own view — on the glass sheet a label's own
   background came out reversed in E11 Console); when it stops working; Copy Message and Share… (Apple's buttons). */
final class SigninCodeVC: UIViewController {
  private let s: [String: Any]
  init(_ signin: [String: Any]) { s = signin; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Sign-in Code"
    view.backgroundColor = .systemGroupedBackground
    navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let code = s["code"] as? String ?? "", name = s["name"] as? String ?? "", email = s["email"] as? String ?? ""
    let message = s["message"] as? String ?? "", until = s["until"] as? String ?? "", newUser = (s["newUser"] as? Bool) == true
    let first = name.split(separator: " ").first.map(String.init) ?? name
    let circle = UILabel(); circle.text = Look.initials(name); circle.textAlignment = .center; circle.textColor = .white
    circle.font = .systemFont(ofSize: 15, weight: .semibold); circle.backgroundColor = Look.clientInk; circle.layer.cornerRadius = 22; circle.clipsToBounds = true
    circle.widthAnchor.constraint(equalToConstant: 44).isActive = true; circle.heightAnchor.constraint(equalToConstant: 44).isActive = true
    let who = UILabel(); who.text = name; who.font = .preferredFont(forTextStyle: .headline)
    let sub = UILabel(); sub.text = "\(email) · \(newUser ? "New client contact" : "Forgot password")"; sub.font = .preferredFont(forTextStyle: .subheadline); sub.textColor = .secondaryLabel
    sub.adjustsFontSizeToFitWidth = true; sub.minimumScaleFactor = 0.8
    let names = UIStackView(arrangedSubviews: [who, sub]); names.axis = .vertical; names.spacing = 2
    let person = UIStackView(arrangedSubviews: [circle, names]); person.spacing = 12; person.alignment = .center
    let digits = UIStackView(arrangedSubviews: code.map { ch -> UIView in
      let box = UIView(); box.backgroundColor = Look.dyn(0x2C2C2E, 0xF2F2F7); box.layer.cornerRadius = 14; box.layer.cornerCurve = .continuous
      let l = UILabel(); l.text = String(ch); l.textAlignment = .center; l.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold); l.textColor = .label
      l.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(l)
      NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: box.centerXAnchor), l.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                                   box.widthAnchor.constraint(equalToConstant: 60), box.heightAnchor.constraint(equalToConstant: 68)])
      return box
    })
    digits.spacing = 12; digits.isAccessibilityElement = true; digits.accessibilityLabel = "Code " + code.map(String.init).joined(separator: " ")
    let note = UILabel(); note.numberOfLines = 0; note.textAlignment = .center; note.font = .preferredFont(forTextStyle: .footnote); note.textColor = .secondaryLabel
    note.text = "Works once, only for \(first), until \(until). A new code cancels this one."
    var cc = UIButton.Configuration.filled(); cc.title = "Copy Message"; cc.cornerStyle = .capsule; cc.buttonSize = .large
    let copy = UIButton(configuration: cc)
    copy.addAction(UIAction { [weak copy] _ in
      UIPasteboard.general.string = message
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      var c = cc; c.title = "Copied"; c.image = UIImage(systemName: "checkmark"); c.imagePadding = 6
      if let b = copy { UIView.transition(with: b, duration: Crossfade.time, options: .transitionCrossDissolve) { b.configuration = c } }
    }, for: .primaryActionTriggered)
    var sc = UIButton.Configuration.gray(); sc.title = "Share…"; sc.cornerStyle = .capsule; sc.buttonSize = .large
    let share = UIButton(configuration: sc)
    share.addAction(UIAction { [weak self, weak share] _ in
      let a = UIActivityViewController(activityItems: [message], applicationActivities: nil)
      a.popoverPresentationController?.sourceView = share
      self?.present(a, animated: true)
    }, for: .primaryActionTriggered)
    let foot = UILabel(); foot.numberOfLines = 0; foot.textAlignment = .center; foot.font = .preferredFont(forTextStyle: .footnote); foot.textColor = .secondaryLabel
    foot.text = "Ready to send on WhatsApp. They sign in to E11 Talk only."   // (short, so it fits the half-height sheet — Haris 2026-11-13)
    let stack = UIStackView(arrangedSubviews: [person, digits, note, copy, share, foot])
    stack.axis = .vertical; stack.alignment = .center; stack.spacing = 18; stack.setCustomSpacing(10, after: copy)
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    let g = view.layoutMarginsGuide
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
      stack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -8),
      copy.widthAnchor.constraint(equalTo: stack.widthAnchor), share.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }
  static func present(_ signin: [String: Any], from vc: UIViewController) {
    let n = UINavigationController(rootViewController: SigninCodeVC(signin))
    if let sh = n.sheetPresentationController { sh.detents = [.medium(), .large()]; sh.prefersGrabberVisible = true }   // (half height first, as E11 Console's — Haris 2026-11-13)
    vc.present(n, animated: true)
  }
}
