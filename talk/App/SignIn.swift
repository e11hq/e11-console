import UIKit
import WebKit

/* E11 Talk's own sign-in for now (Haris 2026-11-06): the same as E11 Console's — Cloudflare's page asks for your work
   email and sends a one-time code. Once it's done, its sign-in is kept in the Keychain (about a month, then again).
   Before the App Store it becomes shared with E11 Console (signed in to one, signed in to both). */
final class SignInVC: UIViewController, WKNavigationDelegate {
  var onDone: (() -> Void)?
  private var web: WKWebView!
  private let top = UIView(), logo = UIImageView(), titleL = UILabel(), sub = UILabel(), spin = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let cfg = WKWebViewConfiguration()
    cfg.websiteDataStore = .nonPersistent()   // (nothing kept by the page itself — only the sign-in, by the app)
    web = WKWebView(frame: .zero, configuration: cfg)
    web.navigationDelegate = self
    web.isOpaque = false; web.backgroundColor = .systemBackground; web.scrollView.backgroundColor = .systemBackground
    logo.image = UIImage(named: "TalkMark"); logo.contentMode = .scaleAspectFit
    titleL.text = "Sign in to E11 Talk"; titleL.font = .systemFont(ofSize: 22, weight: .bold); titleL.textAlignment = .center
    sub.text = "With your work email — a one-time code is sent to it."; sub.font = .systemFont(ofSize: 15); sub.textColor = .secondaryLabel; sub.textAlignment = .center; sub.numberOfLines = 2
    [logo, titleL, sub].forEach { top.addSubview($0) }
    view.addSubview(top); view.addSubview(web); view.addSubview(spin)
    spin.startAnimating()
    web.load(URLRequest(url: URL(string: Server.url + "/api/talk/state")!))
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let s = view.safeAreaInsets, W = view.bounds.width
    top.frame = CGRect(x: 0, y: s.top + 20, width: W, height: 170)
    logo.frame = CGRect(x: (W - 72) / 2, y: 0, width: 72, height: 72)
    titleL.frame = CGRect(x: 20, y: 86, width: W - 40, height: 30)
    sub.frame = CGRect(x: 32, y: 120, width: W - 64, height: 44)
    web.frame = CGRect(x: 0, y: top.frame.maxY + 6, width: W, height: view.bounds.height - top.frame.maxY - 6)
    spin.center = CGPoint(x: W / 2, y: web.frame.minY + 60)
  }
  func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
    spin.stopAnimating()
    guard let u = w.url, u.host == Server.host, u.path.hasPrefix("/api/talk/") else { return }
    // back on our server with an answer: the sign-in is done — keep its cookies
    w.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cs in
      let mine = cs.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return Server.host == d || Server.host.hasSuffix("." + d) }
      guard !mine.isEmpty else { return }
      Net.shared.cookie = mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
      w.evaluateJavaScript("document.body.innerText") { r, _ in
        let txt = r as? String ?? ""
        if txt.contains("\"ok\":true") { self?.onDone?() }
        else if txt.contains("No E11 Console account") {
          let a = UIAlertController(title: "No account for this email", message: "E11 Talk uses your E11 Console account. Ask an Admin to add you on the Team page.", preferredStyle: .alert)
          a.addAction(UIAlertAction(title: "OK", style: .default) { _ in Net.shared.cookie = nil; w.load(URLRequest(url: URL(string: Server.url + "/api/talk/state")!)) })
          self?.present(a, animated: true)
        }
      }
    }
  }
  func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { failed(e) }
  func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { failed(e) }
  private func failed(_ e: Error) {
    spin.stopAnimating()
    if (e as NSError).code == NSURLErrorCancelled { return }
    let a = UIAlertController(title: "Can’t reach E11 Talk", message: "Check your internet connection and try again.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Try again", style: .default) { [weak self] _ in self?.spin.startAnimating(); self?.web.load(URLRequest(url: URL(string: Server.url + "/api/talk/state")!)) })
    present(a, animated: true)
  }
}
