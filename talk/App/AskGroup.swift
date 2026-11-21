import UIKit

/* "Ask the group" (Haris 2026-11-20 21:36, plan claude/talk-ask-the-group-plan.md). A photo, video, voice message or file
   that's gone from the server (everyone had it plus a day, or 30 days untouched) can come back from a phone in the same group
   that still has it — for 90 days after it was sent; after that it's gone for good.
   - Asking: a tap on one that's No longer available → "Ask the group" → "Asking the group…"; it comes back by itself
     (the server tells this phone: the "back" event) and downloads as usual.
   - Answering: the server wakes the phones that had it (a quiet notification) and every phone looks whenever Talk opens;
     a phone that has the file sends it again, straight to R2, locked, under the file's own id. Photos and voice messages go
     on any network; videos and files over 20 MB wait for Wi-Fi unless "use mobile data" is on. */
enum AskGroup {
  static let days: Double = 90
  private static let askedKey = "talk_asked_files", backKey = "talk_back_files"
  // (asked from this phone: when — shown as "Asking the group…" for 7 days)
  private static var asked: [String: Double] = (UserDefaults.standard.dictionary(forKey: askedKey) as? [String: Double]) ?? [:]
  // (came back: no longer counted as gone, whatever its age — the newest 2000)
  private static var back: [String] = UserDefaults.standard.stringArray(forKey: backKey) ?? []
  private static var backSet = Set(UserDefaults.standard.stringArray(forKey: backKey) ?? [])
  static func isBack(_ id: String) -> Bool { backSet.contains(id) }
  static func isAsking(_ id: String) -> Bool { (asked[id] ?? 0) > Date().timeIntervalSince1970 - 7 * 86400 && !isBack(id) }
  // can still be asked for: within 90 days of sending, not deleted
  static func can(_ m: Msg) -> Bool { m.file != nil && !m.deleted && Date().timeIntervalSince1970 * 1000 - m.at < days * 86400000 }

  // asked from the chat: the sheet, then the ask
  static func offer(_ m: Msg, group: String, from vc: UIViewController) {
    guard let f = m.file else { return }
    if isAsking(f.id) { toast("Asking the group…"); return }
    guard can(m) else { toast("No longer available — it’s older than 90 days"); return }
    let a = UIAlertController(title: "No longer available", message: "It isn’t on the server any more. A phone in this group that still has it can send it again.", preferredStyle: .actionSheet)
    a.addAction(UIAlertAction(title: "Ask the group", style: .default) { _ in ask(f, group: group) })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    vc.present(a, animated: true)
  }
  static func ask(_ f: Msg.FileRef, group: String) {
    Net.shared.post("/api/talk/ask", ["group": group, "file": f.id]) { j in
      DispatchQueue.main.async {
        guard (j?["ok"] as? Bool) == true else { toast(j?["error"] as? String ?? "Couldn’t ask — try again"); return }
        if (j?["here"] as? Bool) == true { cameBack(f.id); Downloads.shared.start(f.id, size: f.size); return }
        asked[f.id] = Date().timeIntervalSince1970
        asked = asked.filter { $0.value > Date().timeIntervalSince1970 - 8 * 86400 }
        UserDefaults.standard.set(asked, forKey: askedKey)
        toast((j?["phones"] as? Int) == 0 ? "Asked — nobody in the group has it on their phone now" : "Asking the group…")
        NotificationCenter.default.post(name: .talkFile, object: f.id)
      }
    }
  }
  // the server's "back": the file is on the server again — its key kept, no longer gone, downloaded
  static func cameBack(_ id: String, key: String? = nil, lock: String? = nil, size: Int = 0) {
    if let k = key { FileKeys.set(id, lock == "p" ? "p:" + k : k) }
    if !backSet.contains(id) {
      back.append(id); if back.count > 2000 { back.removeFirst(back.count - 2000) }; backSet = Set(back)
      UserDefaults.standard.set(back, forKey: backKey)
    }
    asked[id] = nil; UserDefaults.standard.set(asked, forKey: askedKey)
    Downloads.shared.unGone(id)
    Downloads.shared.start(id, size: size)
    NotificationCenter.default.post(name: .talkFile, object: id)
  }

  // ---------- answering (the quiet notification, and whenever Talk opens) ----------
  private static var checking = false
  static func check(_ done: (() -> Void)? = nil) {
    guard Net.shared.signedIn, !checking else { done?(); return }
    checking = true
    Net.shared.get("/api/talk/asks") { j in
      DispatchQueue.main.async {
        let asks = (j?["asks"] as? [[String: Any]]) ?? []
        answer(asks[...]) { checking = false; done?() }
      }
    }
  }
  private static func answer(_ list: ArraySlice<[String: Any]>, _ done: @escaping () -> Void) {
    guard let a = list.first else { return done() }
    let rest = list.dropFirst()
    guard let id = a["file"] as? String, FileManager.default.fileExists(atPath: Net.local(id).path) else { return answer(rest, done) }
    let size = a["size"] as? Int ?? 0, kind = a["kind"] as? String ?? "file"
    // (videos and files over 20 MB: on Wi-Fi, or with mobile data allowed)
    if !(kind == "photo" || kind == "voice" || size <= 20 * 1024 * 1024 || !Auto.onMobile || TalkPrefs.useMobile) { return answer(rest, done) }
    guard let d = try? Data(contentsOf: Net.local(id), options: .alwaysMapped) else { return answer(rest, done) }
    let bg = UIApplication.shared.beginBackgroundTask(withName: "talk-ask") {}
    Net.shared.uploadMsg(d, name: a["name"] as? String ?? "File", back: id, progress: { _ in }) { _, _ in
      UIApplication.shared.endBackgroundTask(bg)
      answer(rest, done)
    }
  }
}
