// The Notification Content Extension (iPhone): a notification held opens into Apple's expanded view with this preview in it
// — the same as the Inbox's peek (Haris 2026-11-10: "the same preview as inbox for iphone notifications, if someone long
// press them, with a reply if it was a comment"). The task's client, name, status and due; a comment in full (its pictures
// too) with the one before it, faded, only as much as fits; anything else about a task: its facts and the start of its
// description. Asked of the server with the app's own sign-in (WidgetShare): /api/notif-peek. Apple's own buttons under it
// (Reply · Mark as Read · Open Task — the app's NotifActions). Until the answer is in, the notification's own words.
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
  private let stack = UIStackView()
  private var server = ""
  private var cookie = ""
  private let W = UIScreen.main.bounds.width - 16

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill
    view.addSubview(stack)
  }
  func didReceive(_ n: UNNotification) {
    let c = n.request.content
    // the notification's own words at once (no empty flash), the preview in their place once it's in
    show([words(c.title, c.body)])
    let e = c.userInfo["e11"] as? [String: Any] ?? [:]
    guard let nid = e["nid"] as? String, !nid.isEmpty, let s = WidgetShare.signIn(), let url = URL(string: s.server + "/api/notif-peek") else { return }
    server = s.server; cookie = s.cookie
    var q = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    q.httpMethod = "POST"
    q.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !cookie.isEmpty { q.setValue(cookie, forHTTPHeaderField: "Cookie") }
    q.httpBody = try? JSONSerialization.data(withJSONObject: ["nid": nid])
    URLSession.shared.dataTask(with: q) { [weak self] d, _, _ in
      guard let d = d, let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let p = j["peek"] as? [String: Any] else { return }
      DispatchQueue.main.async { self?.draw(p) }
    }.resume()
  }

  // ---------- drawing ----------
  private func show(_ parts: [UIView], fade: Bool = false) {
    let swap = {
      self.stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
      parts.forEach { self.stack.addArrangedSubview($0) }
      let h = ceil(self.stack.systemLayoutSizeFitting(CGSize(width: self.W, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
      self.stack.frame = CGRect(x: 0, y: 0, width: self.W, height: h)
      self.preferredContentSize = CGSize(width: self.W, height: min(h, UIScreen.main.bounds.height * 0.6))
    }
    if fade { UIView.transition(with: view, duration: 0.2, options: .transitionCrossDissolve, animations: swap) } else { swap() }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    stack.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: max(stack.frame.height, 1))
  }
  private func words(_ title: String, _ body: String) -> UIView {
    let t = UILabel(); t.text = title; t.font = .systemFont(ofSize: 15, weight: .semibold); t.numberOfLines = 2
    let b = UILabel(); b.text = body; b.font = .systemFont(ofSize: 15); b.numberOfLines = 0
    return pad(vstack([t, b], 2), 14)
  }
  private func draw(_ p: [String: Any]) {
    let people = (p["people"] as? [String: [String: Any]]) ?? [:], me = p["me"] as? String ?? ""
    var parts: [UIView] = [head(p), line()]
    let comments = (p["comments"] as? [[String: Any]]) ?? []
    let maxH = UIScreen.main.bounds.height * 0.6
    if comments.isEmpty { parts.append(facts(p, people, me)) }
    else {
      let focus = comment(comments[comments.count - 1], people, me)
      let room = maxH - fit(parts[0]) - 16 - fit(focus)
      parts.append(gap(8))
      if comments.count > 1, room >= 70 {
        // the one before it: only its start, faded — the notified one always whole (as the Inbox's peek)
        let prev = comment(comments[0], people, me); prev.alpha = 0.55
        let full = fit(prev), h = min(full, room, 120)
        let clip = UIView(); clip.clipsToBounds = true
        clip.addSubview(prev); prev.frame = CGRect(x: 0, y: 0, width: W, height: full)
        clip.heightAnchor.constraint(equalToConstant: h).isActive = true
        parts.append(clip)
      }
      parts.append(focus)
      parts.append(gap(8))
    }
    show(parts, fade: true)
  }
  private func fit(_ v: UIView) -> CGFloat { ceil(v.systemLayoutSizeFitting(CGSize(width: W, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height) }
  private func head(_ p: [String: Any]) -> UIView {
    var rows: [UIView] = []
    if let c = p["client"] as? [String: Any] {
      let dot = UIView(); dot.backgroundColor = rgb(c["rgb"]); dot.layer.cornerRadius = 4.5
      dot.widthAnchor.constraint(equalToConstant: 9).isActive = true; dot.heightAnchor.constraint(equalToConstant: 9).isActive = true
      let n = UILabel(); n.text = c["name"] as? String; n.font = .systemFont(ofSize: 13); n.textColor = .secondaryLabel
      let r = UIStackView(arrangedSubviews: [dot, n, UIView()]); r.spacing = 8; r.alignment = .center
      rows.append(r)
    }
    let t = UILabel(); t.text = (p["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled task"
    t.font = .systemFont(ofSize: 19, weight: .bold); t.numberOfLines = 2
    t.setContentCompressionResistancePriority(.required, for: .vertical)
    rows.append(t)
    var chips: [UIView] = []
    let done = (p["done"] as? Bool) == true
    if let s = p["status"] as? [String: Any], let name = s["name"] as? String, !name.isEmpty {
      let col = rgb(s["rgb"]); chips.append(chip(done ? "Done" : name, col.withAlphaComponent(0.18), col))
    }
    if let d = p["dates"] as? [String: Any], let due = d["dueLabel"] as? String, !due.isEmpty, !done {
      let late = (d["late"] as? Bool) == true, today = (d["today"] as? Bool) == true
      let col: UIColor = late ? .systemRed : today ? .systemOrange : .secondaryLabel
      chips.append(chip("Due " + due, (late || today ? col : UIColor.systemGray).withAlphaComponent(0.16), col))
    }
    if !chips.isEmpty { let r = UIStackView(arrangedSubviews: chips + [UIView()]); r.spacing = 6; r.alignment = .center; rows.append(r) }
    let v = vstack(rows, 4)
    return pad(v, 14)
  }
  private func comment(_ it: [String: Any], _ people: [String: [String: Any]], _ me: String) -> UIView {
    let who = it["who"] as? String ?? "", p = people[who] ?? [:]
    let av = avatar(p, 32)
    let name = UILabel(); name.text = who == me ? "You" : (p["name"] as? String ?? "Someone"); name.font = .systemFont(ofSize: 15, weight: .semibold)
    let when = UILabel(); when.text = Self.when(it["at"] as? String ?? ""); when.font = .systemFont(ofSize: 13); when.textColor = .secondaryLabel
    when.setContentHuggingPriority(.required, for: .horizontal)
    let meta = UIStackView(arrangedSubviews: [name, when]); meta.spacing = 6; meta.alignment = .firstBaseline
    var col: [UIView] = [meta]
    let txt = UILabel(); txt.numberOfLines = 0; txt.attributedText = Self.text((it["runs"] as? [[String: Any]]) ?? [], me: me)
    if (txt.attributedText?.length ?? 0) > 0 { col.append(txt) }
    let pics = ((it["files"] as? [[String: Any]]) ?? []).compactMap { f -> String? in
      let n = (f["name"] as? String ?? "").lowercased()
      let pic = ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains((n as NSString).pathExtension)
      return (f["thumbUrl"] as? String) ?? (pic ? (f["url"] as? String)?.replacingOccurrences(of: "?view=1", with: "?w=480") : nil)
    }
    if !pics.isEmpty {
      let r = UIStackView(); r.spacing = 8
      for u in pics.prefix(3) {
        let iv = UIImageView(); iv.backgroundColor = .tertiarySystemFill; iv.layer.cornerRadius = 12; iv.layer.cornerCurve = .continuous; iv.clipsToBounds = true; iv.contentMode = .scaleAspectFill
        iv.widthAnchor.constraint(equalToConstant: 84).isActive = true; iv.heightAnchor.constraint(equalToConstant: 84).isActive = true
        load(u) { iv.image = $0 }
        r.addArrangedSubview(iv)
      }
      r.addArrangedSubview(UIView())
      col.append(r)
    }
    let right = vstack(col, 5)
    let row = UIStackView(arrangedSubviews: [av, right]); row.spacing = 10; row.alignment = .top
    return pad(row, 14, v: 6)
  }
  private func facts(_ p: [String: Any], _ people: [String: [String: Any]], _ me: String) -> UIView {
    let name = { (id: String) -> String in id == me ? "You" : (people[id]?["name"] as? String) ?? "Someone" }
    var rows: [(String, String, UIColor)] = []
    if let c = p["creator"] as? String { rows.append(("Created by", name(c), .label)) }
    let who = ((p["assignees"] as? [String]) ?? []).map(name)
    if !who.isEmpty { rows.append((who.count == 1 ? "Assignee" : "Assignees", ListFormatter.localizedString(byJoining: who), .label)) }
    if let d = p["dates"] as? [String: Any], let due = d["dueLabel"] as? String, !due.isEmpty {
      rows.append(("Due", due, (d["late"] as? Bool) == true ? .systemRed : (d["today"] as? Bool) == true ? .systemOrange : .label))
    }
    if let pr = p["prio"] as? String, !pr.isEmpty { rows.append(("Priority", pr == "Urgent" ? "Urgent" : "Priority \(pr)", pr == "Urgent" || pr == "1" ? .systemRed : .label)) }
    var out: [UIView] = []
    for (i, f) in rows.enumerated() {
      var c = UIListContentConfiguration.valueCell()
      c.text = f.0; c.textProperties.color = .secondaryLabel
      c.secondaryText = f.1; c.secondaryTextProperties.color = f.2; c.secondaryTextProperties.font = .systemFont(ofSize: 17, weight: .medium)
      c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
      out.append(UIListContentView(configuration: c))
      if i < rows.count - 1 { out.append(pad(line(), 0, v: 0, l: 14)) }
    }
    if let d = p["desc"] as? String, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let l = UILabel(); l.text = d; l.numberOfLines = 4; l.font = .systemFont(ofSize: 15); l.textColor = .secondaryLabel
      out.append(pad(l, 14, v: 10))
    } else { out.append(gap(6)) }
    return vstack(out, 0)
  }

  // ---------- pieces ----------
  private func vstack(_ v: [UIView], _ sp: CGFloat) -> UIStackView { let s = UIStackView(arrangedSubviews: v); s.axis = .vertical; s.spacing = sp; s.alignment = .fill; return s }
  private func pad(_ v: UIView, _ h: CGFloat, v vv: CGFloat = 12, l: CGFloat? = nil) -> UIView {
    let s = UIStackView(arrangedSubviews: [v]); s.isLayoutMarginsRelativeArrangement = true
    s.directionalLayoutMargins = NSDirectionalEdgeInsets(top: vv, leading: l ?? h, bottom: vv, trailing: h)
    return s
  }
  private func gap(_ h: CGFloat) -> UIView { let p = UIView(); p.heightAnchor.constraint(equalToConstant: h).isActive = true; return p }
  private func line() -> UIView { let l = UIView(); l.backgroundColor = .separator; l.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true; return l }
  private func chip(_ s: String, _ bg: UIColor, _ fg: UIColor) -> UIView {
    let l = UILabel(); l.text = s; l.font = .systemFont(ofSize: 13, weight: .semibold); l.textColor = fg
    let w = UIView(); w.backgroundColor = bg; w.layer.cornerRadius = 10; w.layer.cornerCurve = .continuous
    w.addSubview(l); l.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: w.leadingAnchor, constant: 9), l.trailingAnchor.constraint(equalTo: w.trailingAnchor, constant: -9), l.topAnchor.constraint(equalTo: w.topAnchor, constant: 3), l.bottomAnchor.constraint(equalTo: w.bottomAnchor, constant: -3)])
    return w
  }
  private func avatar(_ p: [String: Any], _ side: CGFloat) -> UIView {
    let v = UIImageView(); v.layer.cornerRadius = side / 2; v.clipsToBounds = true; v.contentMode = .scaleAspectFill
    v.widthAnchor.constraint(equalToConstant: side).isActive = true; v.heightAnchor.constraint(equalToConstant: side).isActive = true
    v.backgroundColor = rgb(p["color"])
    let ini = UILabel(); ini.text = p["initials"] as? String; ini.font = .systemFont(ofSize: 12, weight: .semibold); ini.textColor = .white; ini.textAlignment = .center
    v.addSubview(ini); ini.frame = CGRect(x: 0, y: 0, width: side, height: side)
    if let ph = p["photo"] as? String, !ph.isEmpty { load(ph) { img in if let img = img { v.image = img; ini.isHidden = true } } }
    return v
  }
  private func rgb(_ a: Any?) -> UIColor {
    guard let a = a as? [NSNumber], a.count >= 3 else { return .systemGray }
    return UIColor(red: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: 1)
  }
  private func load(_ path: String, _ done: @escaping (UIImage?) -> Void) {
    guard let url = URL(string: path.hasPrefix("http") ? path : server + path) else { return done(nil) }
    var q = URLRequest(url: url, timeoutInterval: 15)
    if !cookie.isEmpty { q.setValue(cookie, forHTTPHeaderField: "Cookie") }
    URLSession.shared.dataTask(with: q) { d, _, _ in
      let img = d.flatMap { UIImage(data: $0) }
      DispatchQueue.main.async { done(img) }
    }.resume()
  }
  // a comment's words as the comments page shows them (mentions in blue, bold, italic, links)
  static func text(_ runs: [[String: Any]], me: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for r in runs {
      var font = UIFont.systemFont(ofSize: 16, weight: r["b"] != nil ? .semibold : .regular)
      if r["i"] != nil, let d = font.fontDescriptor.withSymbolicTraits(.traitItalic) { font = UIFont(descriptor: d, size: 16) }
      var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
      if r["u"] != nil { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
      if r["s"] != nil { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      if let u = r["user"] as? String {
        a[.foregroundColor] = UIColor.systemBlue; a[.font] = UIFont.systemFont(ofSize: 16, weight: .medium)
        if u == me { a[.backgroundColor] = UIColor.systemBlue.withAlphaComponent(0.14) }
      } else if r["link"] != nil { a[.foregroundColor] = UIColor.systemBlue }
      out.append(NSAttributedString(string: r["t"] as? String ?? "", attributes: a))
    }
    return out
  }
  // when, as the Inbox says it: 12:30 PM · Yesterday · Friday · Oct 29
  static func when(_ iso: String) -> String {
    let p = ISO8601DateFormatter(); p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = p.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let cal = Calendar.current, f = DateFormatter(); f.locale = Locale(identifier: "en_US")
    if cal.isDateInToday(d) { f.dateFormat = "h:mm a"; return f.string(from: d) }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 99
    if days < 7 { f.dateFormat = "EEEE"; return f.string(from: d) }
    f.dateFormat = "MMM d"; return f.string(from: d)
  }
}
