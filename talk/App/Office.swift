import Foundation
import CryptoKit

/* In the office: a file sent or fetched straight to and from the office server over the office network, as E11 Console's
   apps (Haris 2026-11-17 20:13; plan: project doc claude/office-network-iphone-plan.md). Before a file goes up or comes
   down, the app asks the server for a pass (/api/talk/local/ticket): only in the office does it get one — with the office
   server's address and the fingerprint of its own certificate, the only one trusted there. Out of the office, anything
   that doesn't work, or "Don't Allow" to iPhone's local-network question: the usual way, by itself. */
final class Office: NSObject, URLSessionDelegate {
  static let shared = Office()
  struct Pass { let url: String; let token: String; let cert: String }
  // (out of the office — or the office route didn't work from here: not asked again for a while)
  private var notUntil = Date.distantPast
  private var pins: [String: String] = [:]   // the office server's address → its certificate's fingerprint
  // its own connection: the office server's certificate trusted by its fingerprint
  lazy var session: URLSession = {
    let c = URLSessionConfiguration.default
    c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.requestCachePolicy = .reloadIgnoringLocalCacheData
    c.timeoutIntervalForRequest = 20
    return URLSession(configuration: c, delegate: self, delegateQueue: nil)
  }()
  // a pass for one file (kind "up", or kind "file" with its id); nil: the usual way
  func pass(_ body: [String: Any], _ done: @escaping (Pass?) -> Void) {
    guard Date() >= notUntil else { return done(nil) }
    var r = Net.shared.request("/api/talk/local/ticket", method: "POST", json: body)
    r.timeoutInterval = 8
    URLSession.shared.dataTask(with: r) { [weak self] d, resp, _ in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      var p: Pass?
      if code == 200, let url = j?["url"] as? String, url.hasPrefix("https://"), let t = j?["token"] as? String, let c = j?["cert"] as? String, !c.isEmpty {
        p = Pass(url: url, token: t, cert: c.lowercased())
      }
      DispatchQueue.main.async {
        guard let self = self else { return done(nil) }
        if code == 409 { self.notUntil = Date().addingTimeInterval(120) }   // (not in the office)
        if let p = p, let host = URL(string: p.url)?.host { self.pins[host] = p.cert }
        done(p)
      }
    }.resume()
  }
  // (tried and didn't work — no network to the office server, or not allowed: the usual way for ten minutes)
  func failed() { DispatchQueue.main.async { self.notUntil = Date().addingTimeInterval(600) } }
  func urlSession(_ s: URLSession, didReceive ch: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard ch.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else { return completionHandler(.performDefaultHandling, nil) }
    let pin = DispatchQueue.main.sync { pins[ch.protectionSpace.host] }
    guard let pin = pin, let trust = ch.protectionSpace.serverTrust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
      return completionHandler(.cancelAuthenticationChallenge, nil)
    }
    let fp = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
    completionHandler(fp == pin ? .useCredential : .cancelAuthenticationChallenge, fp == pin ? URLCredential(trust: trust) : nil)
  }
}
