import UIKit

/* "Show them the chat history?" (Haris 2026-11-20 21:47–21:53, plan claude/talk-share-history-plan.md): after adding people,
   the group's messages from the chosen days go to them from this phone — what this phone has (never more than 90 days, not
   deleted ones), with their files' keys; files still on the server download as usual, gone ones can be asked of the group.
   Carried on when Talk opens again if it couldn't be sent (kept for an hour, the server's limit). */
enum ShareHistory {
  private static let waitKey = "talk_history_waiting"
  static func send(_ g: String, to ids: [String], days: Int) {
    let since = Date().timeIntervalSince1970 * 1000 - Double(min(days, 90)) * 86400000
    let msgs = Talk.shared.log(g).msgs.filter { $0.at >= since && !$0.deleted && !$0.pending && $0.kind != "sys" && $0.goneForMe != true && !$0.id.hasPrefix("hist-") }
    guard !msgs.isEmpty else { return }
    var keys: [String: String] = [:]
    var list: [[String: Any]] = []
    for m in msgs {
      guard let d = try? JSONEncoder().encode(m), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
      list.append(j)
      for fid in [m.file?.id, m.link?.img, m.link?.icon].compactMap({ $0 }) { if let k = FileKeys.get(fid) { keys[fid] = k } }
    }
    let body: [String: Any] = ["group": g, "to": ids, "msgs": list, "keys": keys, "since": since]
    let bg = UIApplication.shared.beginBackgroundTask(withName: "talk-history") {}
    Net.shared.post("/api/talk/history/share", body) { j in
      DispatchQueue.main.async {
        UIApplication.shared.endBackgroundTask(bg)
        if (j?["ok"] as? Bool) == true { toast("Chat history shared"); return }
        // (couldn't reach the server: tried again when Talk opens, within the hour)
        if j == nil { var w = UserDefaults.standard.array(forKey: waitKey) as? [[String: Any]] ?? []; w.append(["g": g, "to": ids, "days": days, "at": Date().timeIntervalSince1970]); UserDefaults.standard.set(w, forKey: waitKey) }
        else { toast(j?["error"] as? String ?? "Couldn’t share the history") }
      }
    }
  }
  // (sent later: the ones that couldn't go, still within the hour)
  static func retry() {
    let w = UserDefaults.standard.array(forKey: waitKey) as? [[String: Any]] ?? []
    guard !w.isEmpty else { return }
    UserDefaults.standard.removeObject(forKey: waitKey)
    for x in w where Date().timeIntervalSince1970 - ((x["at"] as? Double) ?? 0) < 3300 {
      if let g = x["g"] as? String, let to = x["to"] as? [String], let d = x["days"] as? Int { send(g, to: to, days: d) }
    }
  }
}
