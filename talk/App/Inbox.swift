import Foundation
import Security

/* Messages that came with their notifications while E11 Talk was closed (Haris 2026-11-22 13:35, WhatsApp's way): the
   notification helper keeps each one in Talk's own Keychain (service "ae.e11.talk.inbox"); Talk shows them the moment it
   opens or comes back — as if from the live line — then lets them go. The sync that follows still brings everything, each
   message kept once (by its id). Main thread. */
enum Inbox {
  static func apply() {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ae.e11.talk.inbox",
                            kSecReturnData as String: true, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]], !items.isEmpty else { return }
    // (each let go first — never shown twice, whatever happens next)
    SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ae.e11.talk.inbox"] as CFDictionary)
    let evs = items.compactMap { i -> [String: Any]? in
      guard let d = i[kSecValueData as String] as? Data else { return nil }
      return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }.sorted { (($0["seq"] as? NSNumber)?.intValue ?? 0) < (($1["seq"] as? NSNumber)?.intValue ?? 0) }
    guard Talk.shared.me != nil else { return }
    for e in evs where (e["type"] as? String) == "msg" { Talk.shared.live(e) }
  }
}
