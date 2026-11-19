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
          let server = Self.keychain("notify-server"), let host = URL(string: server)?.host,
          let url = URL(string: server + "/api/talk/got") else { return finish() }
    var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    if let c = Self.keychain("cookie-" + host) { r.setValue(c, forHTTPHeaderField: "Cookie") }
    r.httpBody = try? JSONSerialization.data(withJSONObject: ["groupId": gid, "msgId": mid])
    let cfg = URLSessionConfiguration.ephemeral
    cfg.httpCookieStorage = nil; cfg.httpShouldSetCookies = false
    URLSession(configuration: cfg).dataTask(with: r) { [weak self] _, _, _ in self?.finish() }.resume()
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
