import UIKit
import WebKit
import LocalAuthentication
import Security

// Signed in for good on this iPhone (Haris 2026-11-11, our own sign-in — the plan's step 5): once signed in, the server
// gives this phone a device key, kept in the Keychain (one per server, this phone only). When Cloudflare's sign-in has run
// out and our sign-in page comes up, Face ID / Touch ID (or the passcode) signs the phone back in with the key instead of
// the password. The key stops by itself when the password is set again with a code or the person leaves the team; signing
// out drops it.
enum DeviceKey {
  private static var account: String { "signin-key:" + (URL(string: serverURL())?.host ?? "") }
  private static let service = "ae.e11.console.signin"

  static var key: String? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }
  private static func keep(_ k: String?) {
    let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    SecItemDelete(base as CFDictionary)
    guard let k = k, let d = k.data(using: .utf8) else { return }
    var add = base; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }

  // signed in (the app's start answered): this phone's key — kept while still good, else a new one
  static func refresh(_ main: Main) {
    guard (main.startInfo["signin"] as? Bool) == true else { return }
    var b: [String: Any] = ["name": UIDevice.current.name]
    if let k = key { b["key"] = k }
    main.serverTask.request("/api/signin/device", body: b) { j in
      if let j = j, (j["ok"] as? Bool) == true, let k = j["key"] as? String, k != key { keep(k) }
    }
  }
  // signing out: the key dropped, here and on the server
  static func drop(_ main: Main) {
    guard let k = key else { return }
    main.serverTask.request("/api/signin/device", body: ["drop": true, "key": k]) { _ in }
    keep(nil)
  }

  // Our sign-in page about to open, with a key on this phone: Face ID first, then the key — the page only if that fails
  private static var passed = Set<String>()   // (a page let through once — a failed or cancelled try shows it)
  static func takeOver(_ u: URL, web: WKWebView) -> Bool {
    guard u.path == "/oidc/authorize", let k = key, !passed.contains(u.absoluteString),
          let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return false }
    var req: [String: String] = [:]
    for it in c.queryItems ?? [] { req[it.name] = it.value ?? "" }
    let show = { passed.insert(u.absoluteString); web.load(URLRequest(url: u)) }
    let ctx = LAContext(); ctx.localizedFallbackTitle = "Use Passcode"
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { show(); return true }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Sign in to E11 Console") { ok, _ in
      DispatchQueue.main.async {
        guard ok else { show(); return }
        var r = URLRequest(url: URL(string: "\(u.scheme ?? "https")://\(u.host ?? "")/oidc/api/device")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["req": req, "key": k])
        URLSession.shared.dataTask(with: r) { d, _, _ in
          let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
          DispatchQueue.main.async {
            if (j?["ok"] as? Bool) == true, let to = (j?["redirect"] as? String).flatMap(URL.init(string:)) { web.load(URLRequest(url: to)); return }
            // (the key no longer counts — a password set again, or left the team: gone, and the page as usual)
            if j != nil { keep(nil) }
            show()
          }
        }.resume()
      }
    }
    return true
  }
}
