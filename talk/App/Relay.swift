import UIKit

/* E11 Talk on Cloudflare (TALK-CF-A, Haris 2026-11-21/22 — project doc claude/talk-cloudflare-relay-plan.md).
   Talk's hub runs on Cloudflare (talkline.e11hq.com), near the team: messages, ✓✓, read, typing go phone → Cloudflare →
   phone, and keep going when the office's internet is down. The office keeps a full copy.
   - Only for the live server (talk.e11hq.com); the test server and App Review stay as they are.
   - The hub answers the same calls as the office (state, act, sync, ack, got, files…), with the same answers.
   - Before the owner's switch-over, or while the office has taken over (a Cloudflare free limit), the hub says so (409
     "office") — the app goes to the office as before, and asks the office every 2 minutes whether the hub has it again.
   - The hub not answering, or refusing: the office, the same way. Nothing is ever lost — the office passes anything it
     isn't in charge of to the hub. */
enum Relay {
  static let base = "https://talkline.e11hq.com"
  // (the calls the hub answers — everything else stays the office's: notifications, Macs, the office network…)
  private static let paths = ["/api/talk/state", "/api/talk/act", "/api/talk/sync", "/api/talk/ack", "/api/talk/got",
                              "/api/talk/r2/start", "/api/talk/r2/done", "/api/talk/ask", "/api/talk/asks", "/api/talk/resend/start", "/api/talk/history/share"]
  static var live: Bool { Server.url == "https://talk.e11hq.com" }
  // in use now (false: the office — until it says the hub has Talk)
  private(set) static var on = UserDefaults.standard.object(forKey: "relay-on") as? Bool ?? false
  private static var checkedAt = Date.distantPast
  static func handles(_ path: String) -> Bool {
    guard live, on else { return false }
    let p = path.split(separator: "?").first.map(String.init) ?? path
    // (a message's file: the hub sends the phone straight to R2 — one trip, and it works with the office down; Haris
    //  2026-11-22 11:26 "all together")
    return paths.contains(p) || p.hasPrefix("/api/talk/file/")
  }
  static func off(_ why: String) {
    guard on else { return }
    on = false; UserDefaults.standard.set(false, forKey: "relay-on")
    NSLog("E11 Talk relay: the office (%@)", why)
    DispatchQueue.main.async { Net.shared.listen() }
  }
  private static func set(_ v: Bool) {
    guard v != on else { return }
    on = v; UserDefaults.standard.set(v, forKey: "relay-on")
    DispatchQueue.main.async { Net.shared.listen() }
  }
  // the office says who has Talk now — at the start, coming back, and every 2 minutes while the office has it
  static func check(force: Bool = false) {
    guard live, force || Date().timeIntervalSince(checkedAt) > 120 else { return }
    checkedAt = Date()
    var r = URLRequest(url: URL(string: Server.url + "/api/talk/relay/mode")!)
    if let c = Net.shared.cookie { r.setValue(c, forHTTPHeaderField: "Cookie") }
    r.timeoutInterval = 8
    URLSession.shared.dataTask(with: r) { d, resp, _ in
      guard (resp as? HTTPURLResponse)?.statusCode == 200, let d = d,
            let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let m = j["mode"] as? String else { return }
      set(m == "hub")
    }.resume()
  }
  // the hub's answer says "go to the office" (before the switch-over, the office took over, a limit, not reachable)
  static func refused(_ http: HTTPURLResponse?, _ j: [String: Any]?, _ err: Error?) -> Bool {
    if err != nil && http == nil { return true }
    guard let h = http else { return false }
    if h.statusCode == 409, j?["office"] as? Bool == true { return true }
    return h.statusCode == 429 || h.statusCode == 503 || h.statusCode == 502 || h.statusCode == 504
  }
}

// ---------- the live line to the hub: a WebSocket (Cloudflare keeps it asleep when quiet — nothing used) ----------
final class RelayLine: NSObject, URLSessionWebSocketDelegate {
  private var task: URLSessionWebSocketTask?
  private var session: URLSession?
  private var ping: Timer?
  private let text: (String) -> Void, ended: (Bool) -> Void
  private var opened = false
  var isOpen: Bool { opened && !done }
  init(text: @escaping (String) -> Void, ended: @escaping (_ opened: Bool) -> Void) { self.text = text; self.ended = ended }
  func open() {
    var r = URLRequest(url: URL(string: Relay.base.replacingOccurrences(of: "https://", with: "wss://") + "/line")!)
    if let c = Net.shared.cookie { r.setValue(c, forHTTPHeaderField: "Cookie") }
    r.setValue(Net.deviceKey, forHTTPHeaderField: "X-Talk-Device")
    let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    let t = s.webSocketTask(with: r)
    session = s; task = t
    t.resume(); receive()
  }
  func close() { ping?.invalidate(); ping = nil; task?.cancel(with: .goingAway, reason: nil); task = nil; session?.invalidateAndCancel(); session = nil }
  private func receive() {
    task?.receive { [weak self] r in
      guard let self = self else { return }
      switch r {
      case .success(.string(let s)): if s != "pong" { self.text(s) }; self.receive()
      case .success(.data(let d)): self.text(String(decoding: d, as: UTF8.self)); self.receive()
      case .failure: self.finish()
      @unknown default: self.receive()
      }
    }
  }
  func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
    opened = true
    // ("ping" every 25 s keeps the line open through phone networks — Cloudflare answers it without waking the hub)
    DispatchQueue.main.async { self.ping = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in self?.task?.send(.string("ping")) { _ in } } }
  }
  func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) { finish() }
  private var done = false
  private func finish() {
    guard !done else { return }
    done = true
    DispatchQueue.main.async { self.ping?.invalidate(); self.ping = nil }
    ended(opened)
  }
}
