import UIKit
import UserNotifications

/* A notification held on the iPhone (Haris 2026-11-10: "the same preview as inbox … with a reply if it was a comment"):
   Apple's expanded notification with the app's preview in it (notifyui/, the Notification Content Extension) and Apple's
   own buttons under it. The server gives each notification its category: a comment's (e11.comment) has Reply · Mark as
   Read · Open Task, anything else about a task (e11.task) Mark as Read · Open Task. Reply and Mark as Read go straight to
   the server with the app's own sign-in, without opening the app; Open Task opens it as a tap does. */
enum NotifActions {
  static func register() {
    let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Reply")
    let read = UNNotificationAction(identifier: "read", title: "Mark as Read", options: [])
    let open = UNNotificationAction(identifier: "open", title: "Open Task", options: [.foreground])
    UNUserNotificationCenter.current().setNotificationCategories([
      UNNotificationCategory(identifier: "e11.comment", actions: [reply, read, open], intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: "e11.task", actions: [read, open], intentIdentifiers: [], options: []),
    ])
  }
  // Reply / Mark as Read: done here (true); Open Task and a tap: the app opens it (false)
  static func handle(_ r: UNNotificationResponse, done: @escaping () -> Void) -> Bool {
    let e = r.notification.request.content.userInfo["e11"] as? [String: Any] ?? [:]
    let nid = e["nid"] as? String ?? "", task = e["taskId"] as? String ?? ""
    switch r.actionIdentifier {
    case "read" where !nid.isEmpty:
      post(["act": "read", "id": nid, "from": "inbox", "op": UUID().uuidString]) { _ in done() }
      return true
    case "reply" where !task.isEmpty:
      let t = ((r as? UNTextInputNotificationResponse)?.userText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !t.isEmpty else { done(); return true }
      var b: [String: Any] = ["act": "comment", "id": task, "page": task, "from": "task", "html": html(t), "text": t, "files": [Any](), "op": UUID().uuidString]
      if let th = e["threadId"] as? String, !th.isEmpty { b["parentId"] = th }
      post(b) { ok in
        if !ok {
          // (not sent: said in a notification of its own, with what was typed — nothing lost)
          let c = UNMutableNotificationContent(); c.title = "Reply not sent"; c.body = t; c.userInfo = r.notification.request.content.userInfo
          UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "reply-failed-" + UUID().uuidString, content: c, trigger: nil))
        }
        if !nid.isEmpty { post(["act": "read", "id": nid, "from": "inbox", "op": UUID().uuidString]) { _ in done() } } else { done() }
      }
      return true
    case "open": return false
    default: return false
    }
  }
  // the words as the comment box sends them: kept as typed, each line its own
  static func html(_ t: String) -> String {
    let esc = t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    return esc.components(separatedBy: "\n").joined(separator: "<br>")
  }
  // straight to the server with the sign-in the app shares with its widget and extensions (WidgetShare)
  static func post(_ body: [String: Any], _ done: @escaping (Bool) -> Void) {
    guard let s = WidgetShare.signIn(), let url = URL(string: s.server + "/api/home/act") else { return done(false) }
    var q = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    q.httpMethod = "POST"
    q.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !s.cookie.isEmpty { q.setValue(s.cookie, forHTTPHeaderField: "Cookie") }
    q.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let bg = UIApplication.shared.beginBackgroundTask(withName: "notif-action")
    URLSession.shared.dataTask(with: q) { d, _, _ in
      let ok = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["ok"] as? Bool == true
      DispatchQueue.main.async { done(ok); UIApplication.shared.endBackgroundTask(bg) }
    }.resume()
  }
}
