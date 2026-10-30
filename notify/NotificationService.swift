// The Notification Service Extension (iPhone app and Mac App Store app): sees each E11 Console notification just
// before it shows, and tells the server it arrived (/api/apns/ack with the notification's id and this device's
// address). Apple keeps only the newest notification for a phone / Mac that was offline; when that one arrives and
// is confirmed, the server sends again the ones before it that never did — so nothing is missed (Haris, 2026-10-30).
// The notification itself is shown unchanged. Asks with the app's own sign-in (WidgetShare, the shared Keychain).
import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private var handler: ((UNNotificationContent) -> Void)?
  private var content: UNNotificationContent?
  private let lock = NSLock()

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    handler = contentHandler
    content = request.content
    let e = request.content.userInfo["e11"] as? [String: Any] ?? [:]
    guard let pid = e["pid"] as? String, !pid.isEmpty,
          let s = WidgetShare.signIn(), let url = URL(string: s.server + "/api/apns/ack"),
          let tok = WidgetShare.read("apnsToken").flatMap({ String(data: $0, encoding: .utf8) }), !tok.isEmpty else { return finish() }
    var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !s.cookie.isEmpty { r.setValue(s.cookie, forHTTPHeaderField: "Cookie") }
    r.httpBody = try? JSONSerialization.data(withJSONObject: ["token": tok, "pid": pid])
    URLSession.shared.dataTask(with: r) { [weak self] _, _, _ in self?.finish() }.resume()
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
}
