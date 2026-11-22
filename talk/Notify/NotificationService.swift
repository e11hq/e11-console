// E11 Talk's notification helper (Haris 2026-11-19 21:42): sees each message notification just before it shows, and
// tells the server this phone has the message (/api/talk/got) — so the sender's ✓ turns into ✓✓, and Message info lists
// this person under Delivered to, while E11 Talk is still closed (WhatsApp's way). The notification itself is shown
// unchanged. Asks with E11 Talk's own sign-in: the server and its cookie the app keeps in the Keychain (Net.swift).
import Foundation
import Security
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private var handler: ((UNNotificationContent) -> Void)?
  private var content: UNNotificationContent?
  private let lock = NSLock()

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    handler = contentHandler
    content = request.content
    let e = request.content.userInfo["e11"] as? [String: Any] ?? [:]
    guard let gid = e["groupId"] as? String, !gid.isEmpty, let mid = e["msgId"] as? String, !mid.isEmpty,
          let server = Self.keychain("notify-server"), let host = URL(string: server)?.host else { return finish() }
    // (the notification is never held more than about a second — the ✓✓ follows on its own if the answer is slow;
    //  it waited for it, up to 20 s, and asked the office, which passed it on to Cloudflare: Haris 2026-11-22 13:07)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.finish() }
    let cookie = Self.keychain("cookie-" + host), body = try? JSONSerialization.data(withJSONObject: ["groupId": gid, "msgId": mid])
    // (Talk on Cloudflare: told there first — one trip; refused there or no answer, the office, as before)
    let hub: String? = host == "talk.e11hq.com" ? "https://talkline.e11hq.com" : nil
    let tell = { (base: String, wait: TimeInterval, then: @escaping (Bool) -> Void) in
      guard let url = URL(string: base + "/api/talk/got") else { return then(false) }
      var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: wait)
      r.httpMethod = "POST"
      r.setValue("application/json", forHTTPHeaderField: "Content-Type")
      r.setValue("application/json", forHTTPHeaderField: "Accept")
      if let c = cookie { r.setValue(c, forHTTPHeaderField: "Cookie") }
      r.httpBody = body
      let cfg = URLSessionConfiguration.ephemeral
      cfg.httpCookieStorage = nil; cfg.httpShouldSetCookies = false
      URLSession(configuration: cfg).dataTask(with: r) { d, resp, _ in
        let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && ((d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["ok"] as? Bool) == true
        then(ok)
      }.resume()
    }
    if let h = hub { tell(h, 4) { [weak self] ok in if ok { self?.finish() } else { tell(server, 15) { _ in self?.finish() } } } }
    else { tell(server, 15) { [weak self] _ in self?.finish() } }
  }
  override func serviceExtensionTimeWillExpire() { finish() }
  // show it (once)
  private func finish() {
    lock.lock()
    let h = handler, c = content
    handler = nil
    lock.unlock()
    if let h, let c { h(c) }
  }
  // (E11 Talk's own Keychain items — the same service the app writes them with, Net.swift's Keychain)
  private static func keychain(_ key: String) -> String? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ae.e11.talk", kSecAttrAccount as String: key,
                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }
}
