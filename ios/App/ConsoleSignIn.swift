import UIKit
import WebKit

// E11 Console's side of the app's own sign-in (NativeSignIn.swift — Haris 2026-11-20 09:11, mock-up native-signin-3):
// our sign-in page about to open → the app's own screen over everything instead; the web view follows the server's next
// page out of sight (Cloudflare's last step); the screen goes once the app is back on our site with its startup screen.
enum ConsoleSignIn {
  static var flow: SignInFlow?
  static let brand = SignInBrand(app: "E11 Console", subtitle: "Your agency’s work, in one place.",
                                 glow: UIColor(red: 110 / 255, green: 96 / 255, blue: 230 / 255, alpha: 1),
                                 emailWord: "work email", faceReason: "Sign in to E11 Console")

  static func takeOver(_ u: URL, web: WKWebView, main: Main) -> Bool {
    guard u.path == "/oidc/authorize", let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return false }
    var req: [String: String] = [:]
    for it in c.queryItems ?? [] { req[it.name] = it.value ?? "" }
    let base = "\(u.scheme ?? "https")://\(u.host ?? "")"
    // (already showing — a new sign-in request: the screen stays as it is, with the new request; put up already on signing
    //  out, still empty: its first step now)
    if let f = flow { f.api.base = base; f.api.req = req; if f.begun { f.renewed() } else { f.begin() }; return true }
    let f = make(main: main, web: web, base: base, req: req)
    f.screen.alpha = 0
    main.splashGone(fast: true)
    f.begin()
    UIView.animate(withDuration: 0.25) { f.screen.alpha = 1 }
    return true
  }
  // signing out: the sign-in screen up at once, its background only, until the sign-in request comes — there was a
  // black screen for a moment and the sign-in came late (Haris 2026-11-20 11:38)
  static func prepare(main: Main) {
    guard flow == nil else { return }
    let f = make(main: main, web: main.web, base: "", req: [:])
    f.screen.alpha = 0
    UIView.animate(withDuration: 0.2) { f.screen.alpha = 1 }
  }
  private static func make(main: Main, web: WKWebView, base: String, req: [String: String]) -> SignInFlow {
    let f = SignInFlow(brand: brand, api: SignInAPI(base: base, req: req), frame: main.view.bounds)
    f.key = DeviceKey.key
    f.onRedirect = { [weak web] to in web?.load(URLRequest(url: to)) }
    f.onKeyGone = { DeviceKey.forget() }
    f.onRestart = { [weak main] in main?.loadHome() }
    f.onReview = { [weak main] in dismiss(animated: false); main?.toReview() }
    let s = f.screen
    s.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    s.frame = main.view.bounds
    main.view.addSubview(s)
    main.reviewLink.isHidden = true
    flow = f
    return f
  }
  // back on our site (the startup screen is over it by now): the sign-in screen goes
  static func dismiss(animated: Bool = true) {
    guard let f = flow else { return }
    flow = nil
    let s = f.screen
    s.endEditing(true)
    guard animated else { s.removeFromSuperview(); return }
    UIView.animate(withDuration: 0.25, animations: { s.alpha = 0 }) { _ in s.removeFromSuperview() }
  }
}
