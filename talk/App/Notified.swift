import UserNotifications

/* A message deleted for everyone: its notification, if it's still on the lock screen or in Notification Centre, taken away
   (Haris 2026-11-22 16:22). With Talk closed, the server replaces it in place with a quiet "This message was deleted" (the
   same collapse id); once Talk is open, those go too. */
enum Notified {
  static func clear(_ msgId: String) {
    let c = UNUserNotificationCenter.current()
    c.getDeliveredNotifications { ns in
      let ids = ns.filter { (($0.request.content.userInfo["e11"] as? [String: Any])?["msgId"] as? String) == msgId }.map { $0.request.identifier }
      if !ids.isEmpty { c.removeDeliveredNotifications(withIdentifiers: ids) }
    }
  }
  static func clearDeleted() {
    let c = UNUserNotificationCenter.current()
    c.getDeliveredNotifications { ns in
      let ids = ns.filter { (($0.request.content.userInfo["e11"] as? [String: Any])?["kind"] as? String) == "talkdel" }.map { $0.request.identifier }
      if !ids.isEmpty { c.removeDeliveredNotifications(withIdentifiers: ids) }
    }
  }
}
