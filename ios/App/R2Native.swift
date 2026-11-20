import Foundation

/* E11 Console's files through Cloudflare R2, on the phone's own screens (server 1.9.114+, consoler2.js — Haris 2026-11-20
   20:36: "do it with care, nothing should break"). Pictures and files are asked for with r2=1: the server then sends the
   phone to R2's own short-lived address while R2 has a fast copy (else answers from the office, as before). The sign-in
   (the Cookie this app sets by hand) never goes along to R2 — CleanRedirect makes a fresh request for R2's address.
   Uploads outside the office go straight into R2 too (Uploader). A server without R2 answers as before. */
final class CleanRedirect: NSObject, URLSessionTaskDelegate {
  static let shared = CleanRedirect()
  func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest n: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(CleanRedirect.clean(n))
  }
  // (to another address than the server: only the address itself, nothing of ours)
  static func clean(_ n: URLRequest) -> URLRequest {
    guard let u = n.url, u.host != URL(string: serverURL())?.host else { return n }
    var c = URLRequest(url: u); c.httpMethod = n.httpMethod ?? "GET"; c.timeoutInterval = n.timeoutInterval
    return c
  }
}

enum R2Files {
  // a file of the server's (/__file/…) asked for with r2=1; anything else as it is
  static func ask(_ url: URL) -> URL {
    guard url.path.hasPrefix("/__file/"), url.host == URL(string: serverURL())?.host,
          var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    var q = c.queryItems ?? []
    if !q.contains(where: { $0.name == "r2" }) { q.append(URLQueryItem(name: "r2", value: "1")) }
    c.queryItems = q
    return c.url ?? url
  }
  // the shared session's fetch, R2's way when it's a file; the redirect cleaned (its own delegate, this task only)
  // (if R2 doesn't answer well, the office is asked as before — a picture never goes missing because of R2)
  static func dataTask(_ r: URLRequest, _ done: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
    let plain = r
    var r = r
    if let u = r.url { r.url = ask(u) }
    let asked = r.url != plain.url
    let t = URLSession.shared.dataTask(with: r) { d, resp, e in
      let h = resp as? HTTPURLResponse
      let fromR2 = h?.url.map { $0.host != URL(string: serverURL())?.host } ?? false
      if asked, fromR2 || h == nil, h?.statusCode != 200 {
        URLSession.shared.dataTask(with: plain, completionHandler: done).resume()
        return
      }
      done(d, resp, e)
    }
    t.delegate = CleanRedirect.shared
    return t
  }
  // a small JSON ask of the server (the upload's start and end), on the main thread
  static func post(_ path: String, _ body: [String: Any], cookie: String, _ done: @escaping ([String: Any]?, Int) -> Void) {
    guard let url = URL(string: serverURL() + path) else { return done(nil, 0) }
    var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue("application/json", forHTTPHeaderField: "Accept")
    if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
    r.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: r) { d, resp, _ in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      DispatchQueue.main.async { done(j, code) }
    }.resume()
  }
}
