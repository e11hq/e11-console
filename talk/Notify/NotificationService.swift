// E11 Talk's notification helper (Haris 2026-11-19 21:42): sees each message notification just before it shows, and
// tells the server this phone has the message (/api/talk/got) — so the sender's ✓ turns into ✓✓, and Message info lists
// this person under Delivered to, while E11 Talk is still closed (WhatsApp's way). A message's notification is shown in
// iPhone's chat style — the group's picture with the small Talk icon, its name, the person (Haris 2026-11-24); its words
// unchanged. Asks with E11 Talk's own sign-in: the server and its cookie the app keeps in the Keychain (Net.swift).
import Foundation
import Security
import UserNotifications
import WidgetKit
import Intents
import UIKit

final class NotificationService: UNNotificationServiceExtension {
  private var handler: ((UNNotificationContent) -> Void)?
  private var content: UNNotificationContent?
  private let lock = NSLock()

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    handler = contentHandler
    content = request.content
    let e = request.content.userInfo["e11"] as? [String: Any] ?? [:]
    guard let gid = e["groupId"] as? String, !gid.isEmpty, let mid = e["msgId"] as? String, !mid.isEmpty else { return finish() }
    // (the message itself, when it came with the notification: kept for E11 Talk, which shows it the moment it opens —
    //  Haris 2026-11-22 13:35; in Talk's own Keychain, which this helper already shares)
    if let m = e["m"] as? [String: Any], (m["id"] as? String) == mid, let d = try? JSONSerialization.data(withJSONObject: m), d.count < 16_000 { Self.keep(mid, d) }
    // (the unread widget: this message counted there at once, while Talk is closed — Shared/WidgetStore.swift, Haris
    //  2026-11-24; the app lets it go once it has the message itself. Only a group message's own notification.)
    if request.content.categoryIdentifier == "talk-msg" {
      let at = (e["m"] as? [String: Any])?["at"] as? Double ?? Date().timeIntervalSince1970 * 1000
      WidgetStore.keepNew(WidgetStore.New(g: gid, id: mid, at: at, title: request.content.title, line: WidgetStore.shortLine(request.content.body)))
      WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
      // (shown in iPhone's own chat style: the group's picture with the small Talk icon on it, the group's name, and the
      //  person with their message — Haris 2026-11-24 21:28; what's shown said by the server, as before)
      if let dressed = Self.dress(request.content, gid: gid, by: (e["m"] as? [String: Any])?["by"] as? String) {
        lock.lock(); content = dressed; lock.unlock()
      }
    }
    guard let server = Self.keychain("notify-server"), let host = URL(string: server)?.host else { return finish() }
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
  // iPhone's chat style (a communication notification), laid out as Haris asked (2026-11-25 13:45): the group's picture,
  // big, with the small Talk icon at its bottom-right (iPhone's own); then the group's name, the person's name, and the
  // message alone. (iPhone's group style put the person first and the app's icon in the picture's place — so the
  // conversation is told to iPhone as the group itself, the person's name as the subtitle.)
  private static func dress(_ c: UNNotificationContent, gid: String, by: String?) -> UNNotificationContent? {
    let body = c.body
    let cut = body.range(of: ": ")
    let who = cut.map { String(body[..<$0.lowerBound]) } ?? ""
    let text = cut.map { String(body[$0.upperBound...]) } ?? body
    let group = INPerson(personHandle: INPersonHandle(value: gid, type: .unknown), nameComponents: nil, displayName: c.title,
                         image: groupPicture(gid, title: c.title), contactIdentifier: nil, customIdentifier: gid)
    let me = INPerson(personHandle: INPersonHandle(value: "me", type: .unknown), nameComponents: nil, displayName: nil, image: nil,
                      contactIdentifier: nil, customIdentifier: "me", isMe: true)
    // (iPhone's group style, roles swapped — Haris 2026-11-25 15:14: its first bold line, the "sender", is the group
    //  with its picture; its second, the "group's name", is the person. 269's one-to-one style dropped the person.)
    let intent = INSendMessageIntent(recipients: [me, group], outgoingMessageType: .outgoingMessageText, content: text,
                                     speakableGroupName: who.isEmpty ? nil : INSpeakableString(spokenPhrase: who), conversationIdentifier: gid,
                                     serviceName: nil, sender: group, attachments: nil)
    if !who.isEmpty, let i = group.image { intent.setImage(i, forParameterNamed: \.speakableGroupName) }
    let it = INInteraction(intent: intent, response: nil)
    it.direction = .incoming
    it.donate(completion: nil)
    guard let m = c.mutableCopy() as? UNMutableNotificationContent else { return nil }
    if !who.isEmpty { m.body = text }
    _ = by
    return try? m.updating(from: intent)
  }
  // the group's picture, as the widget keeps it (Shared/WidgetStore.swift); else drawn as the app draws it — its letters on
  // its colour, or "E11." on black for a client contact
  private static func groupPicture(_ gid: String, title: String) -> INImage? {
    let s = WidgetStore.summary, g = s?.groups.first { $0.id == gid }
    if s?.contact != true, let d = WidgetStore.get(WidgetStore.picService, gid) { return INImage(imageData: d) }
    let e11 = s?.contact == true
    let text = e11 ? "E11." : (g?.letters ?? WidgetStore.initials(title))
    var h = (g?.color ?? "#2F6FE4").trimmingCharacters(in: .whitespaces)
    if h.hasPrefix("#") { h.removeFirst() }
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    let v = UInt32(h, radix: 16) ?? 0x2F6FE4
    let bg = e11 ? UIColor.black : UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    let side: CGFloat = 120
    let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
    let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { _ in
      bg.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
      let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: side * (e11 ? 0.3 : 0.4), weight: .semibold), .foregroundColor: UIColor.white]
      let t = NSAttributedString(string: text, attributes: a), ts = t.size()
      t.draw(at: CGPoint(x: (side - ts.width) / 2, y: (side - ts.height) / 2))
    }
    return img.pngData().map { INImage(imageData: $0) }
  }
  private static func keep(_ id: String, _ d: Data) {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ae.e11.talk.inbox", kSecAttrAccount as String: id]
    SecItemDelete(q as CFDictionary)
    var add = q; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
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
