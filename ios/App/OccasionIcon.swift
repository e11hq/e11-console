import UIKit

/* The app's icon on occasions (Haris 2026-11-19 09:42 / 09:56): E11 Console's 16 seasonal icons — UAE National Day, Ramadan,
   the Eids, Diwali, Christmas, the staff's national days… — on their own days, as the website and the Mac app show them.
   The server sends their days for the next two months by the website's own rules, or the owner's pick (My profile › Mac
   app icon); kept here, so each time the app comes to the front the icon for today (Dubai) is worked out on the phone.
   iPhone shows its own small notice on each switch — nothing of the app's own. */
enum OccasionIcon {
  static let known: Set<String> = ["national-day", "ramadan", "eid-al-fitr", "eid-al-adha", "islamic-new-year", "womens-day", "diwali",
                                   "christmas", "new-year", "pakistan", "india", "syria", "lebanon", "armenia", "algeria", "south-africa"]
  private static let saved = "e11-occasion-icons"
  private static var busy = false
  // what the server sent ({pick, days: [{sid, from, to}]}) — kept, then the icon brought up to date
  static func take(_ j: Any?) {
    guard let d = j as? [String: Any], JSONSerialization.isValidJSONObject(d), let data = try? JSONSerialization.data(withJSONObject: d) else { return }
    UserDefaults.standard.set(data, forKey: saved)
    apply()
  }
  // today's (Dubai): the owner's pick, else the occasion whose days hold today — the one that started latest
  static func wanted() -> String? {
    guard let data = UserDefaults.standard.data(forKey: saved), let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    if let p = j["pick"] as? String { return known.contains(p) ? p : nil }
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Dubai"); f.dateFormat = "yyyy-MM-dd"
    let today = f.string(from: Date())
    var best: (sid: String, from: String)?
    for d in (j["days"] as? [[String: Any]]) ?? [] {
      guard let s = d["sid"] as? String, known.contains(s), let a = d["from"] as? String, let b = d["to"] as? String, a <= today, today <= b else { continue }
      if best == nil || a > best!.from { best = (s, a) }
    }
    return best?.sid
  }
  // (only while the app is in front — iPhone allows it then; once at a time)
  static func apply() {
    if !Thread.isMainThread { DispatchQueue.main.async { apply() }; return }
    let app = UIApplication.shared
    guard app.supportsAlternateIcons, app.applicationState == .active, !busy else { return }
    // (no occasion: "Occasion-everyday" — the normal icon, as an icon of its own — not back to the app's own (nil):
    //  Haris's phone kept showing the Lebanon icon in notifications, of both apps, days after they went back to the
    //  normal one, through a restart and a reinstall; iPhone renews its notifications' copy on a change to an icon, not on
    //  a change back to none — Haris 2026-11-25 22:03)
    let name = "Occasion-" + (wanted() ?? "everyday")
    guard app.alternateIconName != name else { return }
    busy = true
    app.setAlternateIconName(name) { _ in DispatchQueue.main.async { busy = false } }
  }
}
