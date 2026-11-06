import UIKit

/* What the app knows: the groups (from the server — who's in which, admins, pins, mutes) and the messages (on this
   phone only — WhatsApp's way: the server passes each one on and lets it go once every member's phone has it).
   Everything new comes as events (server/src/talk.js): applied here, kept on the phone, then the server is told
   (ack) so it can let them go. */
struct Person { let id: String; let name: String; let role: String; let photo: String?; let color: String?; let gone: Bool; var contact: Bool = false; var client: String? = nil }
struct Contact { let id: String; let name: String; let email: String; let client: String; let groups: Int }
struct Client { let id: String; let name: String; let color: String?; let logo: String? }
struct Group {
  let id: String, client: String, name: String, creator: String, creatorAdmin: Bool, second: String?, admins: [String], pic: String?
  let createdAt: Double, lastAt: Double, members: [String], pinnedAt: Double?, mutedUntil: Double?
  var withClient: Bool = false   // (a client contact is in it: the Clients tab)
  var muted: Bool { (mutedUntil ?? 0) > Date().timeIntervalSince1970 * 1000 }
}

struct Msg: Codable, Equatable {
  var id: String
  var cid: String?
  var seq: Int
  var by: String
  var at: Double
  var kind: String              // text, photo, video, file, voice, sys
  var text: String
  var file: FileRef?
  var reply: Reply?
  var mentions: [String]
  var edited: Bool = false
  var deleted: Bool = false
  var reactions: [String: String] = [:]   // person → emoji
  var pending: Bool = false               // (sent from here, not through yet)
  var failed: Bool = false
  struct FileRef: Codable, Equatable { var id: String; var name: String; var size: Int; var kind: String; var w: Double?; var h: Double?; var secs: Double?; var wave: String? = nil }
  struct Reply: Codable, Equatable { var id: String; var by: String; var text: String; var kind: String }
}

struct GroupLog: Codable {
  var msgs: [Msg] = []
  var readBy: [String: String] = [:]   // person → the last message they've seen (id)
  var myRead: String?                   // the last message I've seen
}

extension Notification.Name {
  static let talkChanged = Notification.Name("talk.changed")        // the lists
  static let talkGroup = Notification.Name("talk.group")            // object: group id — its messages
  static let talkGone = Notification.Name("talk.gone")              // object: group id
}

final class Talk {
  static let shared = Talk()
  private(set) var me: Person?
  private(set) var canMake = false, boss = false, isContact = false
  private(set) var contacts: [Contact] = []
  private(set) var pinnedClientGroups: [String] = []
  private(set) var clients: [String: Client] = [:]
  private(set) var clientOrder: [String] = []
  private(set) var groups: [String: Group] = [:]
  private(set) var people: [String: Person] = [:]
  private(set) var pinnedGroups: [String] = [], pinnedClients: [String] = []
  private var logs: [String: GroupLog] = [:]
  private var lastSeq: Int { get { UserDefaults.standard.integer(forKey: "talk_seq_" + Server.host) } set { UserDefaults.standard.set(newValue, forKey: "talk_seq_" + Server.host) } }

  private let dir: URL = {
    let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("talk", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }()
  private var stateFile: URL { dir.appendingPathComponent("state-\(Server.host).json") }
  private func logFile(_ g: String) -> URL { dir.appendingPathComponent("g-\(g).json") }

  // ---------- from the phone first (at once), then the server ----------
  func loadLocal() {
    if let d = try? Data(contentsOf: stateFile), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { take(j, save: false) }
  }
  func log(_ g: String) -> GroupLog {
    if let l = logs[g] { return l }
    let l = (try? Data(contentsOf: logFile(g))).flatMap { try? JSONDecoder().decode(GroupLog.self, from: $0) } ?? GroupLog()
    logs[g] = l
    return l
  }
  private var dirty = Set<String>()
  private func saveSoon(_ g: String) {
    dirty.insert(g)
    saveJob?.cancel()
    let w = DispatchWorkItem { [weak self] in self?.flush() }
    saveJob = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
  }
  private var saveJob: DispatchWorkItem?
  func flush() {
    for g in dirty { if let l = logs[g], let d = try? JSONEncoder().encode(l) { try? d.write(to: logFile(g), options: .atomic) } }
    dirty.removeAll()
  }

  func refresh(_ done: (() -> Void)? = nil) {
    Net.shared.get("/api/talk/state") { [weak self] j in
      if let j = j, (j["ok"] as? Bool) == true { self?.take(j, save: true) }
      done?()
    }
  }
  private func take(_ j: [String: Any], save: Bool) {
    func person(_ p: [String: Any]) -> Person? {
      guard let id = p["id"] as? String else { return nil }
      return Person(id: id, name: p["name"] as? String ?? "", role: p["role"] as? String ?? "", photo: p["photo"] as? String, color: p["color"] as? String, gone: (p["gone"] as? Bool) == true,
                    contact: (p["contact"] as? Bool) == true, client: p["client"] as? String)
    }
    if let m = j["me"] as? [String: Any] { me = person(m); canMake = (m["canMake"] as? Bool) == true; boss = (m["boss"] as? Bool) == true; isContact = (m["contact"] as? Bool) == true }
    contacts = ((j["contacts"] as? [[String: Any]]) ?? []).compactMap { c in
      guard let id = c["id"] as? String else { return nil }
      return Contact(id: id, name: c["name"] as? String ?? "", email: c["email"] as? String ?? "", client: c["client"] as? String ?? "", groups: c["groups"] as? Int ?? 0)
    }
    var cs: [String: Client] = [:], order: [String] = []
    for c in (j["clients"] as? [[String: Any]]) ?? [] { if let id = c["id"] as? String { cs[id] = Client(id: id, name: c["name"] as? String ?? "", color: c["color"] as? String, logo: c["logo"] as? String); order.append(id) } }
    clients = cs; clientOrder = order
    var ps: [String: Person] = [:]
    for p in (j["people"] as? [[String: Any]]) ?? [] { if let x = person(p) { ps[x.id] = x } }
    people = ps
    var gs: [String: Group] = [:]
    for g in (j["groups"] as? [[String: Any]]) ?? [] {
      guard let id = g["id"] as? String else { continue }
      gs[id] = Group(id: id, client: g["client"] as? String ?? "", name: g["name"] as? String ?? "", creator: g["creator"] as? String ?? "",
                     creatorAdmin: (g["creatorAdmin"] as? Bool) ?? true, second: g["second"] as? String, admins: g["admins"] as? [String] ?? [],
                     pic: g["pic"] as? String, createdAt: (g["createdAt"] as? Double) ?? 0, lastAt: (g["lastAt"] as? Double) ?? 0,
                     members: g["members"] as? [String] ?? [], pinnedAt: g["pinnedAt"] as? Double, mutedUntil: g["mutedUntil"] as? Double, withClient: (g["withClient"] as? Bool) == true)
    }
    groups = gs
    if let p = j["pins"] as? [String: Any] { pinnedGroups = p["groups"] as? [String] ?? []; pinnedClients = p["clients"] as? [String] ?? []; pinnedClientGroups = p["clientGroups"] as? [String] ?? [] }
    if save, let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: stateFile, options: .atomic) }
    NotificationCenter.default.post(name: .talkChanged, object: nil)
  }

  // ---------- events ----------
  private var syncing = false, again = false
  func sync(_ done: (() -> Void)? = nil) {
    if syncing { again = true; done?(); return }
    syncing = true
    Net.shared.get("/api/talk/sync?after=\(lastSeq)") { [weak self] j in
      guard let self = self else { return }
      self.syncing = false
      guard let j = j, (j["ok"] as? Bool) == true else { done?(); return }
      let evs = (j["events"] as? [[String: Any]]) ?? []
      var touched = Set<String>(), groupChanged = false
      for e in evs { if let g = self.apply(e, &groupChanged) { touched.insert(g) } }
      self.flush()
      let last = j["last"] as? Int ?? self.lastSeq
      if last > self.lastSeq { self.lastSeq = last; Net.shared.post("/api/talk/ack", ["upto": last]) }
      touched.forEach { NotificationCenter.default.post(name: .talkGroup, object: $0) }
      if !touched.isEmpty { NotificationCenter.default.post(name: .talkChanged, object: nil); self.badge() }
      if groupChanged { self.refresh() }
      if (j["more"] as? Bool) == true || self.again { self.again = false; self.sync(done) } else { done?() }
    }
  }
  private func apply(_ e: [String: Any], _ groupChanged: inout Bool) -> String? {
    guard let g = e["group"] as? String, let type = e["type"] as? String else { return nil }
    let by = e["by"] as? String ?? "", seq = e["seq"] as? Int ?? 0, at = (e["at"] as? Double) ?? Date().timeIntervalSince1970 * 1000
    if type == "group" { groupChanged = true; return nil }
    if type == "gone" { logs[g] = nil; try? FileManager.default.removeItem(at: logFile(g)); groupChanged = true; NotificationCenter.default.post(name: .talkGone, object: g); return nil }
    var l = log(g)
    let id = e["id"] as? String ?? ""
    switch type {
    case "msg":
      let f = (e["file"] as? [String: Any]).flatMap { f -> Msg.FileRef? in
        guard let fid = f["id"] as? String else { return nil }
        return Msg.FileRef(id: fid, name: f["name"] as? String ?? "File", size: f["size"] as? Int ?? 0, kind: f["kind"] as? String ?? "file", w: f["w"] as? Double, h: f["h"] as? Double, secs: f["secs"] as? Double, wave: f["wave"] as? String)
      }
      let r = (e["reply"] as? [String: Any]).flatMap { r -> Msg.Reply? in
        guard let rid = r["id"] as? String, !rid.isEmpty else { return nil }
        return Msg.Reply(id: rid, by: r["by"] as? String ?? "", text: r["text"] as? String ?? "", kind: r["kind"] as? String ?? "text")
      }
      let m = Msg(id: id, cid: e["cid"] as? String, seq: seq, by: by, at: at, kind: e["kind"] as? String ?? "text", text: e["text"] as? String ?? "",
                  file: f, reply: r, mentions: e["mentions"] as? [String] ?? [])
      if let i = l.msgs.firstIndex(where: { $0.id == id || ($0.pending && m.cid != nil && $0.cid == m.cid) }) {
        // (one of mine sent from here: it keeps its place, with the server's id; a photo keeps the copy it was sent from)
        var keep = m; keep.reactions = l.msgs[i].reactions
        if let old = l.msgs[i].file?.id, let new = m.file?.id, old != new { try? FileManager.default.copyItem(at: Net.local(old), to: Net.local(new)) }
        l.msgs[i] = keep
      } else { l.msgs.append(m) }
    case "edit": if let i = l.msgs.firstIndex(where: { $0.id == id }) { l.msgs[i].text = e["text"] as? String ?? l.msgs[i].text; l.msgs[i].edited = true }
    case "del":
      if let i = l.msgs.firstIndex(where: { $0.id == id }) {
        if let f = l.msgs[i].file { try? FileManager.default.removeItem(at: Net.local(f.id)) }
        l.msgs[i].deleted = true; l.msgs[i].text = ""; l.msgs[i].file = nil; l.msgs[i].reply = nil
      }
    case "react":
      if let i = l.msgs.firstIndex(where: { $0.id == id }) { if let em = e["emoji"] as? String, !em.isEmpty { l.msgs[i].reactions[by] = em } else { l.msgs[i].reactions[by] = nil } }
    case "read": if let up = e["upto"] as? String { l.readBy[by] = up }
    default: return nil
    }
    logs[g] = l
    saveSoon(g)
    return g
  }

  // ---------- sending from here: shown at once, then the server's copy takes its place ----------
  func send(_ g: String, text: String, reply: Msg? = nil, mentions: [String] = [], file: Msg.FileRef? = nil, localFile: URL? = nil, upload: Data? = nil, progress: ((Double) -> Void)? = nil) {
    guard let me = me else { return }
    let cid = UUID().uuidString
    var l = log(g)
    var m = Msg(id: "local-" + cid, cid: cid, seq: Int.max, by: me.id, at: Date().timeIntervalSince1970 * 1000, kind: file?.kind ?? "text", text: text, file: file,
                reply: reply.map { Msg.Reply(id: $0.id, by: $0.by, text: Talk.preview($0), kind: $0.kind) }, mentions: mentions, pending: true)
    if let lf = localFile, let f = file { try? FileManager.default.copyItem(at: lf, to: Net.local(f.id)) }
    l.msgs.append(m); logs[g] = l; saveSoon(g)
    NotificationCenter.default.post(name: .talkGroup, object: g); NotificationCenter.default.post(name: .talkChanged, object: nil)
    let go = { (fileId: String?) in
      var b: [String: Any] = ["act": "send", "group": g, "text": text, "cid": cid, "mentions": mentions]
      if let r = m.reply { b["reply"] = ["id": r.id, "by": r.by, "text": r.text, "kind": r.kind] }
      if let f = file, let fid = fileId { var fd: [String: Any] = ["id": fid, "kind": f.kind]; fd["w"] = f.w; fd["h"] = f.h; fd["secs"] = f.secs; fd["wave"] = f.wave; b["file"] = fd }
      Net.shared.act(b) { [weak self] j in
        guard let self = self else { return }
        if (j?["ok"] as? Bool) == true { self.sync() } else { self.mark(g, cid, failed: true) }
      }
    }
    if let data = upload, let f = file {
      Net.shared.upload(data, name: f.name, progress: { p in progress?(p) }) { [weak self] fid in
        guard let fid = fid else { self?.mark(g, cid, failed: true); return }
        try? FileManager.default.copyItem(at: Net.local(f.id), to: Net.local(fid))
        m.file?.id = fid
        go(fid)
      }
    } else { go(nil) }
  }
  private func mark(_ g: String, _ cid: String, failed: Bool) {
    var l = log(g)
    if let i = l.msgs.firstIndex(where: { $0.cid == cid && $0.pending }) { l.msgs[i].failed = failed; logs[g] = l; saveSoon(g); NotificationCenter.default.post(name: .talkGroup, object: g) }
  }
  func retry(_ g: String, _ m: Msg) {
    deleteForMe(g, m)
    send(g, text: m.text, reply: nil)
  }
  func deleteForMe(_ g: String, _ m: Msg) {
    var l = log(g); l.msgs.removeAll { $0.id == m.id }; logs[g] = l; saveSoon(g)
    if let f = m.file { try? FileManager.default.removeItem(at: Net.local(f.id)) }
    NotificationCenter.default.post(name: .talkGroup, object: g); NotificationCenter.default.post(name: .talkChanged, object: nil)
  }
  // seen up to the newest: the others see "Seen by"; my unread count goes
  func markRead(_ g: String) {
    var l = log(g)
    guard let last = l.msgs.last(where: { !$0.pending }), l.myRead != last.id else { return }
    l.myRead = last.id; logs[g] = l; saveSoon(g)
    if last.by != me?.id { Net.shared.act(["act": "read", "group": g, "upto": last.id]) }
    NotificationCenter.default.post(name: .talkChanged, object: nil); badge()
  }

  // ---------- 90 days (Haris 2026-11-05): every message deletes itself 90 days after it was sent, on every phone, with
  // its photo / file / voice note — so phones don't fill up. Checked whenever the app opens. ----------
  func prune() {
    let cut = Date().timeIntervalSince1970 * 1000 - 90 * 86400000
    for g in groups.keys {
      var l = log(g)
      let old = l.msgs.filter { $0.at < cut && !$0.pending }
      guard !old.isEmpty else { continue }
      for m in old { if let f = m.file { try? FileManager.default.removeItem(at: Net.local(f.id)) } }
      let ids = Set(old.map { $0.id })
      l.msgs.removeAll { ids.contains($0.id) }
      logs[g] = l; saveSoon(g)
    }
    // (groups this phone no longer has — gone, left: their chats go too)
    if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
      for f in files where f.hasPrefix("g-") && f.hasSuffix(".json") {
        let g = String(f.dropFirst(2).dropLast(5))
        if groups[g] == nil && !groups.isEmpty { logs[g] = nil; try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
      }
    }
  }

  // ---------- search: the messages on this phone ----------
  func search(_ q: String, in only: String? = nil) -> [(String, Msg)] {
    let n = q.trimmingCharacters(in: .whitespaces)
    guard n.count >= 2 else { return [] }
    var out: [(String, Msg)] = []
    for g in (only.map { [$0] } ?? Array(groups.keys)) {
      for m in log(g).msgs where !m.deleted && m.kind != "sys" {
        let hay = m.text + " " + (m.file?.name ?? "")
        if hay.range(of: n, options: [.caseInsensitive, .diacriticInsensitive]) != nil { out.append((g, m)) }
      }
    }
    return out.sorted { $0.1.at > $1.1.at }
  }

  // ---------- for the lists ----------
  func unread(_ g: String) -> Int {
    let l = log(g), my = me?.id ?? ""
    let from = l.myRead.flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 + 1 } ?? 0
    return l.msgs[min(from, l.msgs.count)...].filter { $0.by != my && $0.kind != "sys" && !$0.deleted }.count
  }
  func mentionsMe(_ g: String) -> Bool {
    let l = log(g), my = me?.id ?? ""
    let from = l.myRead.flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 + 1 } ?? 0
    return l.msgs[min(from, l.msgs.count)...].contains { $0.mentions.contains(my) }
  }
  func last(_ g: String) -> Msg? { log(g).msgs.last }
  // newest activity first: the last message, or when the group was made / changed
  func activity(_ g: Group) -> Double { max(last(g.id)?.at ?? 0, g.createdAt) }
  // (tab: nil — every group; false — the Groups tab: groups without a client contact; true — the Clients tab)
  func groups(of client: String, withClient: Bool? = nil) -> [Group] { groups.values.filter { $0.client == client && (withClient == nil || $0.withClient == withClient!) }.sorted { activity($0) > activity($1) } }
  func clientActivity(_ c: String, withClient: Bool? = nil) -> Double { groups(of: c, withClient: withClient).map { activity($0) }.max() ?? 0 }
  func clientUnread(_ c: String, withClient: Bool? = nil) -> Int { groups(of: c, withClient: withClient).reduce(0) { $0 + unread($1.id) } }
  func myClients(withClient: Bool? = nil) -> [String] { Set(groups.values.filter { withClient == nil || $0.withClient == withClient! }.map { $0.client }).filter { clients[$0] != nil }.sorted { clientActivity($0, withClient: withClient) > clientActivity($1, withClient: withClient) } }
  var myClients: [String] { myClients() }
  var totalUnread: Int { groups.keys.reduce(0) { $0 + unread($1) } }
  func badge() { UIApplication.shared.applicationIconBadgeNumber = totalUnread }
  func name(_ id: String) -> String { id == me?.id ? "You" : people[id]?.name ?? "Someone" }
  func isAdmin(_ g: Group) -> Bool { g.admins.contains(me?.id ?? "") }
  func canManage(_ g: Group) -> Bool { isAdmin(g) || boss }

  static func preview(_ m: Msg) -> String {
    if m.deleted { return "This message was deleted" }
    switch m.kind {
    case "photo": return m.text.isEmpty ? "📷 Photo" : "📷 " + m.text
    case "video": return m.text.isEmpty ? "🎥 Video" : "🎥 " + m.text
    case "voice": return "🎤 Voice message"
    case "file": return "📄 " + (m.file?.name ?? "File")
    default: return m.text
    }
  }
  func signOut() {
    Net.shared.stopListening(); Net.shared.cookie = nil
    logs = [:]; groups = [:]; me = nil
    try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: Net.filesDir)
    UserDefaults.standard.removeObject(forKey: "talk_seq_" + Server.host)
  }
}

// ---------- small shared pieces ----------
enum Look {
  static let accent = UIColor(red: 0.18, green: 0.44, blue: 0.89, alpha: 1)   // E11 Talk's blue (#2f6fe4)
  static let mine = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.16, green: 0.38, blue: 0.85, alpha: 1) : UIColor(red: 0.18, green: 0.44, blue: 0.89, alpha: 1) }
  static let theirs = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : .white }
  static let chatBg = UIColor { $0.userInterfaceStyle == .dark ? .black : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1) }
  static func hex(_ s: String?) -> UIColor? {
    guard var h = s?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
    h.removeFirst(); if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
  }
  // a name's colour in a group (the same person, the same colour)
  static let nameColors: [UIColor] = [.systemPurple, .systemOrange, .systemTeal, .systemPink, .systemGreen, .systemIndigo, .systemBrown, .systemRed]
  static func color(for id: String) -> UIColor { nameColors[abs(id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % nameColors.count] }
  static func initials(_ s: String) -> String {
    let w = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
    return w.map { String($0.prefix(1)) }.joined().uppercased()
  }
  static func time(_ ms: Double, short: Bool = true) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current, f = DateFormatter()
    if cal.isDateInToday(d) { f.timeStyle = .short; f.dateStyle = .none }
    else if cal.isDateInYesterday(d) { return "Yesterday" }
    else if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 { f.dateFormat = "EEE" }
    else { f.dateFormat = short ? "MMM d" : "MMM d, yyyy" }
    return f.string(from: d)
  }
  static func clock(_ ms: Double) -> String { let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f.string(from: Date(timeIntervalSince1970: ms / 1000)) }
  static func day(_ ms: Double) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    let f = DateFormatter(); f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "MMM d, yyyy"
    return f.string(from: d)
  }
}

// a round picture: a photo / logo, or initials on a colour
final class Avatar: UIView {
  private let img = UIImageView(), lbl = UILabel()
  private var want: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    img.contentMode = .scaleAspectFill; addSubview(img)
    lbl.textAlignment = .center; lbl.textColor = .white; lbl.adjustsFontSizeToFitWidth = true; lbl.minimumScaleFactor = 0.5; addSubview(lbl)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.width / 2
    img.frame = bounds; lbl.frame = bounds.insetBy(dx: 3, dy: 0)
    lbl.font = .systemFont(ofSize: bounds.width * 0.36, weight: .semibold)
  }
  func set(name: String, color: UIColor, picture: String?, talkFile: String? = nil) {
    lbl.text = Look.initials(name); backgroundColor = color
    img.image = nil; img.isHidden = true; lbl.isHidden = false
    let key = talkFile ?? picture
    want = key
    if let f = talkFile {
      Net.shared.file(f) { [weak self] url in guard let self = self, self.want == key, let u = url, let i = UIImage(contentsOfFile: u.path) else { return }; self.img.image = i; self.img.isHidden = false; self.lbl.isHidden = true }
    } else if let p = picture {
      Net.shared.picture(p) { [weak self] i in guard let self = self, self.want == key, let i = i else { return }; self.img.image = i; self.img.isHidden = false; self.lbl.isHidden = true }
    }
  }
  // a group: its own picture, else its client's logo, else a letter on the client's colour
  func set(group g: Group) {
    let c = Talk.shared.clients[g.client]
    if g.pic != nil { set(name: g.name, color: Look.hex(c?.color) ?? Look.accent, picture: nil, talkFile: g.pic) }
    else if c?.logo != nil { set(name: c?.name ?? g.name, color: Look.hex(c?.color) ?? Look.accent, picture: c?.logo) }
    else { lbl.text = String(g.name.prefix(1)).uppercased(); backgroundColor = Look.hex(c?.color) ?? Look.accent; img.isHidden = true; lbl.isHidden = false; want = nil }
  }
  func set(client c: Client) { set(name: c.name, color: Look.hex(c.color) ?? Look.accent, picture: c.logo) }
  func set(person p: Person?) { set(name: p?.name ?? "?", color: Look.color(for: p?.id ?? ""), picture: p?.photo) }
}

// a short line at the bottom (as Console's toasts)
func toast(_ text: String, in v: UIView? = nil) {
  guard let host = v ?? UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
  let l = PaddedLabel(); l.text = text; l.font = .systemFont(ofSize: 15, weight: .medium); l.textColor = .label; l.numberOfLines = 2; l.textAlignment = .center
  l.backgroundColor = .secondarySystemGroupedBackground; l.layer.cornerRadius = 14; l.layer.masksToBounds = true
  let w = min(host.bounds.width - 48, l.sizeThatFits(CGSize(width: host.bounds.width - 48, height: 80)).width + 32)
  let h = l.sizeThatFits(CGSize(width: w, height: 80)).height + 20
  l.frame = CGRect(x: (host.bounds.width - w) / 2, y: host.bounds.height - host.safeAreaInsets.bottom - 110 - h, width: w, height: h)
  l.alpha = 0; host.addSubview(l)
  UIView.animate(withDuration: 0.18) { l.alpha = 1 }
  DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { UIView.animate(withDuration: 0.2, animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() } }
}
final class PaddedLabel: UILabel {
  override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 16, dy: 10)) }
  override func sizeThatFits(_ size: CGSize) -> CGSize { let s = super.sizeThatFits(CGSize(width: size.width - 32, height: size.height)); return CGSize(width: s.width + 32, height: s.height) }
}
