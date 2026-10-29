// Shared between the apps (iPhone, Mac App Store) and their widgets: where the widget finds the server and the
// app's own sign-in, and the last summary it showed. Kept in a shared Keychain group (both the app and its widget
// list it in keychain-access-groups); readable after the first unlock so the widget can refresh on a locked phone.
// The sign-in is the app's Cloudflare cookie (and the App Review copy's own cookie): the widget asks the server
// with it, read only (/api/widget). When it runs out, the widget keeps the last numbers until the app is opened.
import Foundation
import Security
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetShare {
  static let service = "ae.e11.console.widget"
  // "<Team ID>.ae.e11.console.shared" — from the Info.plist (E11KeychainGroup = $(AppIdentifierPrefix)ae.e11.console.shared)
  static var group: String? { Bundle.main.object(forInfoDictionaryKey: "E11KeychainGroup") as? String }

  private static func query(_ account: String) -> [String: Any] {
    var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    if let g = group, !g.hasPrefix("$(") { q[kSecAttrAccessGroup as String] = g }
    #if os(macOS)
    q[kSecUseDataProtectionKeychain as String] = true
    #endif
    return q
  }
  static func write(_ account: String, _ data: Data) {
    let q = query(account)
    let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
    if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
      var add = q; attrs.forEach { add[$0.key] = $0.value }
      SecItemAdd(add as CFDictionary, nil)
    }
  }
  static func read(_ account: String) -> Data? {
    var q = query(account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: AnyObject?
    return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
  }
  static func remove(_ account: String) { SecItemDelete(query(account) as CFDictionary) }

  // the app: the server it shows and the cookies for it (called when a page of ours finishes loading, and on leaving)
  static func saveSignIn(server: String, cookies: [HTTPCookie]) {
    guard let host = URL(string: server)?.host else { return }
    let mine = cookies.filter { c in
      let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
      return (host == d || host.hasSuffix("." + d)) && (c.expiresDate.map { $0 > Date() } ?? true)
    }
    let header = mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    let old = read("signin").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
    let next = ["server": server, "cookie": header]
    if old != next, let d = try? JSONSerialization.data(withJSONObject: next) {
      write("signin", d)
      if old["server"] != server { remove("cache") }   // another server: forget the other one's numbers
    }
    reloadWidgets()
  }
  static func signIn() -> (server: String, cookie: String)? {
    guard let d = read("signin"), let o = try? JSONSerialization.jsonObject(with: d) as? [String: String], let s = o["server"], !s.isEmpty else { return nil }
    return (s, o["cookie"] ?? "")
  }
  static func reloadWidgets() {
    #if canImport(WidgetKit)
    if #available(iOS 14.0, macOS 11.0, *) { WidgetCenter.shared.reloadAllTimelines() }
    #endif
  }
}
