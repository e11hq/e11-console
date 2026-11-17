import Foundation
import CryptoKit

/* In the office: files straight to and from the office NAS over the office network, as the Mac app (Haris 2026-11-17 20:13;
   plan: project doc claude/office-network-iphone-plan.md). Before a file goes up or comes down, the app asks the server for
   a pass (/api/local/ticket): only in the office does it get one — with the NAS's office address and the fingerprint of its
   own certificate, which is the only one trusted there. Out of the office, anything that doesn't work, or "Don't Allow" to
   iPhone's local-network question: the usual way, by itself. Nothing on any screen changes. */
enum Office {
  struct Pass { let url: String; let token: String; let cert: String }
  // (out of the office — or the office route didn't work from here: not asked again for a while)
  static var notUntil = Date.distantPast
  // the office server's certificate, by its address: kept, so iPhone carrying on a transfer with the app away still trusts it
  private static let pinsKey = "office-pins"
  static var pins: [String: String] = (UserDefaults.standard.dictionary(forKey: pinsKey) as? [String: String]) ?? [:] {
    didSet { UserDefaults.standard.set(pins, forKey: pinsKey) }
  }
  // a pass for one file (body: kind "up" with where it goes, or kind "file" with its path); nil: the usual way
  static func pass(_ body: [String: Any], cookie: String, _ done: @escaping (Pass?) -> Void) {
    guard Date() >= notUntil, let u = URL(string: serverURL() + "/api/local/ticket") else { return done(nil) }
    var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = 8
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
    r.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: r) { d, resp, _ in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      var p: Pass?
      if code == 200, let url = j?["url"] as? String, url.hasPrefix("https://"), let t = j?["token"] as? String, let c = j?["cert"] as? String, !c.isEmpty {
        p = Pass(url: url, token: t, cert: c.lowercased())
      }
      DispatchQueue.main.async {
        if code == 409 { notUntil = Date().addingTimeInterval(120) }   // (not in the office)
        if let p = p, let host = URL(string: p.url)?.host, pins[host] != p.cert { pins[host] = p.cert }
        done(p)
      }
    }.resume()
  }
  // (the office route was tried and didn't work — no network to the NAS, or not allowed: the usual way for ten minutes)
  static func failed() { notUntil = Date().addingTimeInterval(600) }
  // the office server's own certificate: trusted only if it's the one the server named (nil: not the office server)
  static func trust(_ ch: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)? {
    guard ch.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let pin = pins[ch.protectionSpace.host] else { return nil }
    guard let trust = ch.protectionSpace.serverTrust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return (.cancelAuthenticationChallenge, nil) }
    let fp = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
    return fp == pin ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
  }
}
