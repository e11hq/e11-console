import Foundation
import Security

/* The unread widget's own small store (Haris 2026-11-24: "Talk's widget for unread messages in groups") — shared by the
   app, its notification helper (E11TalkNotify) and the widget (E11TalkWidget), in Talk's own Keychain, which all three
   already share (no new permission). Three kinds of item:
   - the app's summary of the groups (service "ae.e11.talk.widget", one item): each group's name, picture's stand-in,
     unread count, newest line and time, and until when it's muted — written whenever the counts change;
   - a message that came with its notification while Talk was closed (service "ae.e11.talk.widget.new", one per message):
     written by the notification helper; the app lets each go once it has that message itself;
   - each group's picture, small (service "ae.e11.talk.widget.pic", one per group): written by the app.
   Muted groups never show in the widget (Haris 2026-11-24). */
enum WidgetStore {
  static let kind = "TalkUnread"
  static let summaryService = "ae.e11.talk.widget"
  static let newService = "ae.e11.talk.widget.new"
  static let picService = "ae.e11.talk.widget.pic"

  struct Summary: Codable, Equatable {
    var at: Double                  // (when it was written, ms)
    var contact: Bool               // (a client contact: every group's picture is "E11." on black, as in the app)
    var groups: [G]
  }
  struct G: Codable, Equatable {
    var id: String
    var name: String
    var letters: String             // (the picture's stand-in: its letters on its colour, as the app's Avatar)
    var color: String               // ("#RRGGBB")
    var unread: Int                 // (-1: marked unread — the dot alone)
    var line: String                // (the newest message, as the group's row shows it — only for a group with unread)
    var lastAt: Double              // (ms)
    var mutedUntil: Double?         // (ms)
    var pic: Bool                   // (its small picture is kept: picService, account = id)
    func muted(_ nowMs: Double) -> Bool { (mutedUntil ?? 0) > nowMs }
  }
  struct New: Codable, Equatable {
    var g: String                   // (group)
    var id: String                  // (message)
    var at: Double                  // (ms)
    var title: String               // (the group's name, from the notification)
    var line: String                // ("Yousef: the message")
  }

  // ---------- the Keychain ----------
  static func put(_ service: String, _ account: String, _ d: Data) {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    let st = SecItemUpdate(q as CFDictionary, [kSecValueData as String: d] as CFDictionary)
    if st == errSecItemNotFound {
      var add = q; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(add as CFDictionary, nil)
    }
  }
  static func get(_ service: String, _ account: String) -> Data? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
    return out as? Data
  }
  static func all(_ service: String) -> [(account: String, data: Data)] {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                            kSecReturnData as String: true, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
    return items.compactMap { i in
      guard let a = i[kSecAttrAccount as String] as? String, let d = i[kSecValueData as String] as? Data else { return nil }
      return (a, d)
    }
  }
  static func drop(_ service: String, _ account: String? = nil) {
    var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    if let a = account { q[kSecAttrAccount as String] = a }
    SecItemDelete(q as CFDictionary)
  }

  // ---------- the pieces ----------
  static var summary: Summary? { WidgetStore.get(summaryService, "summary").flatMap { try? JSONDecoder().decode(Summary.self, from: $0) } }
  static var news: [New] { all(newService).compactMap { try? JSONDecoder().decode(New.self, from: $0.data) } }
  static func keepNew(_ n: New) { if let d = try? JSONEncoder().encode(n) { put(newService, n.id, d) } }
  static func dropNew(_ id: String) { drop(newService, id) }
  static func clearAll() { drop(summaryService); drop(newService); drop(picService) }

  // a name's letters, as the app's (a middle "Al" skipped — Haris 2026-11-08)
  static func initials(_ s: String) -> String {
    let all = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    guard let first = all.first else { return "" }
    let next = all.dropFirst().first { $0.lowercased() != "al" } ?? all.dropFirst().first
    return (String(first.prefix(1)) + (next.map { String($0.prefix(1)) } ?? "")).uppercased()
  }
  // "Yousef Al Hwij: the message" (the notification's words) → "Yousef: the message" (the group row's)
  static func shortLine(_ body: String) -> String {
    guard let r = body.range(of: ": ") else { return body }
    let who = body[..<r.lowerBound], first = who.split(separator: " ").first.map(String.init) ?? String(who)
    return first + ": " + body[r.upperBound...]
  }
}
