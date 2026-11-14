import UIKit
import WebKit

/* E11 Talk's own sign-in for now (Haris 2026-11-06): the same as E11 Console's — Cloudflare's page asks for your work
   email and sends a one-time code. Once it's done, its sign-in is kept in the Keychain (about a month, then again).
   Before the App Store it becomes shared with E11 Console (signed in to one, signed in to both). */
final class SignInVC: UIViewController, WKNavigationDelegate {
  var onDone: (() -> Void)?
  var passed = Set<String>()   // (our sign-in page let through as it is — Face ID cancelled, or a key that no longer counts)
  var cover: UIView?           // (board 53 over the page)
  private var web: WKWebView!
  // (no header of Talk's own over the page: the page is the whole screen, as in E11 Console — mock-up "Talk — Sign-in, in
  //  Talk's colours", Haris 2026-11-14; it said "Sign in" twice)
  private let spin = UIActivityIndicatorView(style: .medium)
  private let reviewB = UIButton(configuration: .plain())   // ("App Review sign-in", as E11 Console has under its page)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let cfg = WKWebViewConfiguration()
    cfg.websiteDataStore = .nonPersistent()   // (nothing kept by the page itself — only the sign-in, by the app)
    web = WKWebView(frame: .zero, configuration: cfg)
    web.navigationDelegate = self
    web.isOpaque = false; web.backgroundColor = .systemBackground; web.scrollView.backgroundColor = .systemBackground
    view.addSubview(web); view.addSubview(spin)
    var rc = UIButton.Configuration.plain()
    rc.attributedTitle = AttributedString("App Review sign-in", attributes: AttributeContainer([.font: UIFont.preferredFont(forTextStyle: .footnote)]))
    rc.baseForegroundColor = .secondaryLabel
    reviewB.configuration = rc
    reviewB.addAction(UIAction { [weak self] _ in self?.reviewSignIn() }, for: .primaryActionTriggered)
    view.addSubview(reviewB)
    // (on the App Review copy there's no page of ours to show: its own sign-in, at once)
    if Server.review { web.isHidden = true }
    else { spin.startAnimating(); web.load(URLRequest(url: URL(string: Server.url + "/api/talk/state")!)) }
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if Server.review, presentedViewController == nil, !asked { asked = true; reviewSignIn() }
  }
  private var asked = false

  /* App Review sign-in (Haris 2026-11-13 "Both ways"): the reviewer's email and password for the App Review copy, in
     Apple's own alert — the same account as E11 Console's "App Review sign-in". Talk then stays on that copy until
     signing out. (Signed in to Console's App Review copy already: Talk takes that sign-in by itself, no alert.) */
  private func reviewSignIn(error: String? = nil, email: String = "") {
    let a = UIAlertController(title: "App Review Sign-in", message: error ?? "The email and password given to App Review.", preferredStyle: .alert)
    a.addTextField { t in t.placeholder = "Email"; t.text = email; t.keyboardType = .emailAddress; t.textContentType = .username; t.autocapitalizationType = .none; t.autocorrectionType = .no }
    a.addTextField { t in t.placeholder = "Password"; t.isSecureTextEntry = true; t.textContentType = .password }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak self, weak a] _ in
      let em = a?.textFields?[0].text ?? "", pw = a?.textFields?[1].text ?? ""
      self?.reviewSend(em, pw)
    })
    present(a, animated: true)
  }
  private func reviewSend(_ email: String, _ password: String) {
    spin.startAnimating()
    var r = URLRequest(url: URL(string: Server.reviewURL + "/review/api/sign-in")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
    URLSession.shared.dataTask(with: r) { d, _, _ in
      let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.spin.stopAnimating()
        guard (j?["ok"] as? Bool) == true, let tok = j?["token"] as? String, !tok.isEmpty else {
          self.reviewSignIn(error: (j?["error"] as? String) ?? "Couldn’t reach the App Review copy. Check your internet connection and try again.", email: email)
          return
        }
        UserDefaults.standard.set(true, forKey: "talk_review")
        Server.follow()
        Net.shared.cookie = "e11_rv=" + tok
        self.onDone?()
      }
    }.resume()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let s = view.safeAreaInsets, W = view.bounds.width
    let rs = reviewB.sizeThatFits(CGSize(width: W - 40, height: 44))
    reviewB.frame = CGRect(x: (W - rs.width) / 2, y: view.bounds.height - s.bottom - rs.height - 4, width: rs.width, height: rs.height)
    web.frame = CGRect(x: 0, y: s.top, width: W, height: reviewB.frame.minY - s.top - 4)
    spin.center = CGPoint(x: W / 2, y: web.frame.midY)
  }
  // our server's answer to /api/talk/ is for the app to read, never to be seen: the page fades away as it comes in (its
  // words showed for a moment after Sign In — Haris 2026-11-14), and fades back for any page of the sign-in
  func webView(_ w: WKWebView, decidePolicyFor r: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    let answer = r.isForMainFrame && r.response.url?.host == Server.host && (r.response.url?.path.hasPrefix("/api/talk/") ?? false)
      && (r.response.mimeType ?? "").contains("json")
    if r.isForMainFrame, (answer ? 0 : 1) != w.alpha {
      UIView.animate(withDuration: Crossfade.time, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { w.alpha = answer ? 0 : 1 }
      if answer { spin.startAnimating() }
    }
    decisionHandler(.allow)
  }
  func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
    if w.alpha == 1 { spin.stopAnimating() }
    guard let u = w.url, u.host == Server.host, u.path.hasPrefix("/api/talk/") else { return }
    // back on our server with an answer: the sign-in is done — keep its cookies
    w.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cs in
      let mine = cs.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return Server.host == d || Server.host.hasSuffix("." + d) }
      guard !mine.isEmpty else { return }
      Net.shared.cookie = mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
      w.evaluateJavaScript("document.body.innerText") { r, _ in
        let txt = r as? String ?? ""
        if txt.contains("\"ok\":true") { self?.onDone?() }
        else if txt.contains("No E11 Console account") || txt.contains("No E11 Talk account") {
          let a = UIAlertController(title: "No account for this email", message: "Sign in with the email E11 gave you — your E11 Console email, or, for a client, the email E11 added you with.", preferredStyle: .alert)
          a.addAction(UIAlertAction(title: "OK", style: .default) { _ in Net.shared.cookie = nil; w.load(URLRequest(url: URL(string: Server.url + "/api/talk/state")!)) })
          self?.present(a, animated: true)
        }
      }
    }
  }
  // (only Cloudflare's sign-in and E11 Talk's own address in here: after the code, Cloudflare sends you back to where
  //  its sign-in belongs — the E11 Console website (test.e11hq.com, or "/" of this server) — so that's turned back to
  //  E11 Talk; the Cloudflare session just made signs it in at once, no second code. Haris 2026-11-06: "taking me to
  //  website after logging in")
  private var turnedBack = 0
  func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard a.targetFrame?.isMainFrame != false, let u = a.request.url, let host = u.host else { decisionHandler(.allow); return }
    // (our own sign-in page — the shared sign-in: board 53 or Face ID first, else the page itself)
    if SignInKeys.isSigninHost(host) {
      if takeOver(u, web: w) { decisionHandler(.cancel) } else { decisionHandler(.allow) }
      return
    }
    let cloudflare = host.hasSuffix("cloudflareaccess.com") || u.path.hasPrefix("/cdn-cgi/")
    let ours = host == Server.host && u.path.hasPrefix("/api/talk/")
    if cloudflare || ours || turnedBack >= 3 { decisionHandler(.allow); return }
    decisionHandler(.cancel)
    turnedBack += 1
    spin.startAnimating()
    w.load(URLRequest(url: URL(string: Server.url + "/api/talk/state")!))
  }
  func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { failed(e) }
  func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { failed(e) }
  private func failed(_ e: Error) {
    spin.stopAnimating()
    let ne = e as NSError
    if ne.code == NSURLErrorCancelled || (ne.domain == "WebKitErrorDomain" && ne.code == 102) { return }   // (a page turned back above)
    let a = UIAlertController(title: "Can’t reach E11 Talk", message: "Check your internet connection and try again.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Try again", style: .default) { [weak self] _ in self?.spin.startAnimating(); self?.web.load(URLRequest(url: URL(string: Server.url + "/api/talk/state")!)) })
    present(a, animated: true)
  }
}
