import UIKit
import LinkPresentation

/* What the app knows: the groups (from the server — who's in which, admins, pins, mutes) and the messages (on this
   phone only — WhatsApp's way: the server passes each one on and lets it go once every member's phone has it).
   Everything new comes as events (server/src/talk.js): applied here, kept on the phone, then the server is told
   (ack) so it can let them go. */
struct Person { let id: String; let name: String; let role: String; let photo: String?; let color: String?; let gone: Bool; var contact: Bool = false; var client: String? = nil
  var away: String? = nil }   // (Out of Office in E11 Console: the day they're back, 'YYYY-MM-DD' — Haris 2026-11-13)
// a person's picture: their E11 Console photo — a client contact's is their client's logo (Client Assets), else initials
extension Person {
  var picture: String? { contact ? client.flatMap { Talk.shared.clients[$0]?.logo } : photo }
  // "Out of office until Fri 20 Nov" while it lasts (until 9:00 AM Dubai that day), else nil
  var awayLine: String? {
    guard let d = away, d.count == 10 else { return nil }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Dubai"); f.dateFormat = "yyyy-MM-dd HH:mm"
    guard let ends = f.date(from: d + " 09:00"), Date() < ends else { return nil }
    let g = DateFormatter(); g.locale = Locale(identifier: "en_GB"); g.timeZone = TimeZone(identifier: "Asia/Dubai"); g.dateFormat = "EEE d MMM"
    return "Out of office until " + g.string(from: ends)
  }
}
struct Contact { let id: String; let name: String; let email: String; let client: String; let groups: Int }
struct LinkedMac { let id: String; let name: String; let linkedAt: Double; let seenAt: Double }
struct Client { let id: String; let name: String; let color: String?; let logo: String? }
struct Group {
  let id: String, client: String, name: String, creator: String, creatorAdmin: Bool, second: String?, admins: [String], pic: String?
  let createdAt: Double, lastAt: Double, members: [String], pinnedAt: Double?, mutedUntil: Double?
  var withClient: Bool = false   // (a client contact is in it: the Clients tab)
  // (its pinned message — one, anyone in the group pins it; a line of what it says, from the phone that pinned it)
  var pin: Pin? = nil
  // (its description — set by its admins, shown on the card at the start of its chat: board 4)
  var about: String? = nil
  struct Pin: Equatable { let id: String; let by: String; let text: String; let kind: String; let pinnedBy: String }
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
  var goneForMe: Bool? = nil             // (deleted for me: "You deleted this message" stays in its place)
  var fwd: Bool? = nil                    // (forwarded from another chat: "Forwarded" over it)
  var album: String? = nil              // (photos and videos sent together: one album in the chat — Haris 2026-11-12)
  var link: LinkPrev? = nil               // (a link's preview, made on the sender's phone — option B, Haris 2026-11-12)
  var task: TaskCard? = nil               // (an E11 Console task shared with # — staff groups only; the card the server made)
  struct TaskCard: Codable, Equatable, Hashable {
    var id: String; var title: String; var client: String; var status: String; var color: String; var due: String?; var done: Bool; var people: [String]
    init?(_ j: [String: Any]?) {
      guard let j = j, let id = j["id"] as? String else { return nil }
      self.id = id; title = j["title"] as? String ?? "Task"; client = j["client"] as? String ?? ""; status = j["status"] as? String ?? ""
      color = j["color"] as? String ?? "#87909e"; due = j["due"] as? String; done = (j["done"] as? Bool) == true; people = j["people"] as? [String] ?? []
    }
    // the task's own link — it opens in E11 Console (its app takes /t/ links; the website otherwise)
    var url: URL? {
      let files = Server.host.contains("test") ? "files-test.e11hq.com" : "files.e11hq.com"
      return URL(string: "https://\(files)/t/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id))
    }
  }
  struct LinkPrev: Codable, Equatable, Hashable { var url: String; var title: String?; var site: String?; var video: Bool; var img: String?; var icon: String?; var e11: String? = nil; var pic: String? = nil; var client: String? = nil; var sub: String? = nil; var state: String? = nil }   // (client / sub / state: an E11 link's live card — "ok", "off", "gone")   // (pic: an E11 link's picture, its page's own — a web address)   // (e11: one of our own links — "file" / "folder", its card from the server)
  struct FileRef: Codable, Equatable { var id: String; var name: String; var size: Int; var kind: String; var w: Double?; var h: Double?; var secs: Double?; var wave: String? = nil; var thumb: String? = nil }
  struct Reply: Codable, Equatable { var id: String; var by: String; var text: String; var kind: String }
}

struct GroupLog: Codable {
  var msgs: [Msg] = []
  var readBy: [String: String] = [:]   // person → the last message they've seen (id)
  var myRead: String?                   // the last message I've seen
  // when each person read (and their phone got) up to which message — for Message info's times; the newest 300 each
  var readAt: [String: [Mark]]? = nil
  var gotAt: [String: [Mark]]? = nil
  struct Mark: Codable { var upto: String; var at: Double }
  // when a person read / got message `id` (the first mark at or after it), else nil
  func time(_ marks: [String: [Mark]]?, _ p: String, _ id: String) -> Double? {
    guard let ms = marks?[p], let i = msgs.firstIndex(where: { $0.id == id }) else { return nil }
    let pos = Dictionary(msgs.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    return ms.first { (pos[$0.upto] ?? -1) >= i }?.at
  }
  // has a person read up to message `id`?
  func read(_ p: String, _ id: String) -> Bool {
    guard let r = readBy[p], let ri = msgs.firstIndex(where: { $0.id == r }), let i = msgs.firstIndex(where: { $0.id == id }) else { return false }
    return ri >= i
  }
}

extension Notification.Name {
  static let talkChanged = Notification.Name("talk.changed")        // the lists
  static let talkGroup = Notification.Name("talk.group")            // object: group id — its messages
  static let talkTasks = Notification.Name("talk.tasks")            // tasks changed in E11 Console
  static let talkTyping = Notification.Name("talk.typing")          // object: group id — who is typing there changed
  static let talkGone = Notification.Name("talk.gone")              // object: group id
  static let talkRefused = Notification.Name("talk.refused")        // object: the server's words
}

final class Talk {
  static let shared = Talk()
  private(set) var me: Person?
  var mutedMentions = true            // (Settings › Notifications: an @mention in a muted group still comes — kept on the server)
  private(set) var myEmail: String?   // (a client contact's, for Settings' card — the board)
  private(set) var canMake = false, boss = false, isContact = false
  private(set) var contacts: [Contact] = []
  private(set) var pinnedClientGroups: [String] = []
  private(set) var clients: [String: Client] = [:]
  private(set) var macs: [LinkedMac] = []
  private(set) var clientOrder: [String] = []
  private(set) var groups: [String: Group] = [:]
  private(set) var people: [String: Person] = [:]
  private(set) var pinnedGroups: [String] = [], pinnedClients: [String] = [], pinnedClientsTab: [String] = []
  // (each tab its own pinned clients — Haris 2026-11-13)
  func pinned(clientsTab: Bool) -> [String] { clientsTab ? pinnedClientsTab : pinnedClients }
  private var logs: [String: GroupLog] = [:]
  private var lastSeq: Int { get { UserDefaults.standard.integer(forKey: "talk_seq_" + Server.host) } set { UserDefaults.standard.set(newValue, forKey: "talk_seq_" + Server.host) } }

  private let dir: URL = {
    let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("talk", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }()
  private var stateFile: URL { dir.appendingPathComponent("state-\(Server.host).json") }
  // ---------- starred messages (hold a message › Star; Settings › Starred Messages) ----------
  struct Starred: Codable, Equatable { var group: String; var id: String; var by: String; var at: Double; var text: String; var kind: String; var starredAt: Double }
  private var starFile: URL { dir.appendingPathComponent("starred-\(Server.host).json") }
  private(set) lazy var starred: [Starred] = (try? Data(contentsOf: starFile)).flatMap { try? JSONDecoder().decode([Starred].self, from: $0) } ?? []
  func isStarred(_ g: String, _ id: String) -> Bool { starred.contains { $0.group == g && $0.id == id } }
  func toggleStar(_ g: String, _ m: Msg) {
    if isStarred(g, m.id) { starred.removeAll { $0.group == g && $0.id == m.id } }
    else { starred.insert(Starred(group: g, id: m.id, by: m.by, at: m.at, text: Talk.preview(m), kind: m.kind, starredAt: Date().timeIntervalSince1970 * 1000), at: 0) }
    if let d = try? JSONEncoder().encode(starred) { try? d.write(to: starFile, options: .atomic) }
    NotificationCenter.default.post(name: .talkGroup, object: g)
  }
  // (unstarred from Starred Messages — the chat's ★ and the list both brought up to date)
  func unstar(_ g: String, _ id: String) {
    starred.removeAll { $0.group == g && $0.id == id }
    if let d = try? JSONEncoder().encode(starred) { try? d.write(to: starFile, options: .atomic) }
    NotificationCenter.default.post(name: .talkGroup, object: g)
  }
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
      // (signed in, but the email isn't anyone's in E11 Talk — said plainly, never an empty list)
      else if let e = j?["error"] as? String, e.hasPrefix("No E11 Talk account") { NotificationCenter.default.post(name: .talkRefused, object: e) }
      done?()
    }
  }
  private func take(_ j: [String: Any], save: Bool) {
    func person(_ p: [String: Any]) -> Person? {
      guard let id = p["id"] as? String else { return nil }
      return Person(id: id, name: p["name"] as? String ?? "", role: p["role"] as? String ?? "", photo: p["photo"] as? String, color: p["color"] as? String, gone: (p["gone"] as? Bool) == true,
                    contact: (p["contact"] as? Bool) == true, client: p["client"] as? String, away: p["away"] as? String)
    }
    if let m = j["me"] as? [String: Any] { me = person(m); canMake = (m["canMake"] as? Bool) == true; boss = (m["boss"] as? Bool) == true; isContact = (m["contact"] as? Bool) == true; myEmail = m["email"] as? String; mutedMentions = ((m["opts"] as? [String: Any])?["mutedMentions"] as? Bool) ?? true }
    contacts = ((j["contacts"] as? [[String: Any]]) ?? []).compactMap { c in
      guard let id = c["id"] as? String else { return nil }
      return Contact(id: id, name: c["name"] as? String ?? "", email: c["email"] as? String ?? "", client: c["client"] as? String ?? "", groups: c["groups"] as? Int ?? 0)
    }
    macs = ((j["macs"] as? [[String: Any]]) ?? []).compactMap { m in
      guard let id = m["id"] as? String else { return nil }
      return LinkedMac(id: id, name: m["name"] as? String ?? "Mac", linkedAt: m["linkedAt"] as? Double ?? 0, seenAt: m["seenAt"] as? Double ?? 0)
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
                     members: g["members"] as? [String] ?? [], pinnedAt: g["pinnedAt"] as? Double, mutedUntil: g["mutedUntil"] as? Double, withClient: (g["withClient"] as? Bool) == true,
                     pin: (g["pin"] as? [String: Any]).flatMap { p in (p["id"] as? String).map { Group.Pin(id: $0, by: p["by"] as? String ?? "", text: p["text"] as? String ?? "", kind: p["kind"] as? String ?? "text", pinnedBy: p["pinnedBy"] as? String ?? "") } }, about: g["about"] as? String)
    }
    groups = gs
    if let p = j["pins"] as? [String: Any] { pinnedGroups = p["groups"] as? [String] ?? []; pinnedClients = p["clients"] as? [String] ?? []; pinnedClientGroups = p["clientGroups"] as? [String] ?? []; pinnedClientsTab = p["clientsTab"] as? [String] ?? [] }
    if save, let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: stateFile, options: .atomic) }
    NotificationCenter.default.post(name: .talkChanged, object: nil)
  }

  // ---------- events ----------
  private var syncing = false, again = false
  var holdSync = false   // (a new phone deciding whether to restore from iCloud: nothing comes in until it has)
  // the files of new messages onto this phone, three at a time; ok when every one arrived
  private func fetch(_ ids: [String], _ done: @escaping (Bool) -> Void) {
    guard !ids.isEmpty else { done(true); return }
    var left = ids, running = 0, failed = false
    func next() {
      if left.isEmpty && running == 0 { done(!failed); return }
      while running < 3, let id = left.first {
        left.removeFirst(); running += 1
        Net.shared.fetch(id) { ok in running -= 1; if !ok { failed = true }; next() }
      }
    }
    next()
  }
  func sync(_ done: (() -> Void)? = nil) {
    if holdSync { done?(); return }
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
      touched.forEach { NotificationCenter.default.post(name: .talkGroup, object: $0) }
      if !touched.isEmpty { NotificationCenter.default.post(name: .talkChanged, object: nil); self.badge() }
      if groupChanged { self.refresh() }
      /* "Got it" only once the photos, videos, voice notes and files that came are on this phone: the server lets a
         message's file go as soon as every phone has said so — said before the file was fetched, it was gone ("That file
         isn't on the server any more", Haris 2026-11-12). A file that can't be fetched now: nothing said, so the same
         messages come again on the next sync and it's tried again. */
      let files = evs.flatMap { e -> [String] in
        guard (e["type"] as? String) == "msg" else { return [] }
        let k = e["link"] as? [String: Any]
        // (a link's preview picture and site icon too; a photo, video or file only when Auto-download takes it now — the
        //  rest stay on the server for this phone, downloaded with a tap or once Wi-Fi is back)
        let fileId = Auto.now(e["kind"] as? String ?? "file") ? (e["file"] as? [String: Any])?["id"] as? String : nil
        return [fileId, (k?["img"] as? [String: Any])?["id"] as? String, (k?["icon"] as? [String: Any])?["id"] as? String]
          .compactMap { $0 }.filter { !$0.hasPrefix("local-") && !FileManager.default.fileExists(atPath: Net.local($0).path) }
      }
      self.syncing = true
      self.fetch(files) { [weak self] ok in
        guard let self = self else { return }
        self.syncing = false
        if ok, last > self.lastSeq { self.lastSeq = last; Net.shared.post("/api/talk/ack", ["upto": last]) }
        // (more only when this one brought some — a server that said "more" with nothing kept the phone asking again at once,
        //  over and over, found 2026-11-13)
        if ok && (((j["more"] as? Bool) == true && !evs.isEmpty) || self.again) { self.again = false; self.sync(done) } else { self.again = false; done?() }
      }
    }
  }
  // Auto-download: what a switch or the network kept back, now that it may come (the last 30 days; three at a time)
  private var catching = false
  func catchUp() {
    guard !catching, me != nil else { return }
    let since = Date().timeIntervalSince1970 * 1000 - Auto.keep
    var want: [(id: String, size: Int, kind: String)] = []
    for g in groups.keys {
      for m in log(g).msgs.reversed() {
        guard m.at > since else { break }
        guard let f = m.file, !m.deleted, !m.pending, Auto.now(m.kind), !Auto.here(f), !Downloads.shared.isGone(f.id), !Downloads.shared.running(f.id) else { continue }
        want.append((f.id, f.size, m.kind))
      }
    }
    guard !want.isEmpty else { return }
    catching = true
    var running = 0
    func next() {
      if want.isEmpty && running == 0 { catching = false; return }
      // (Wi-Fi gone again, or a switch turned off: the rest wait)
      while running < 3, let w = want.first {
        want.removeFirst()
        guard Auto.now(w.kind) else { continue }
        running += 1
        Downloads.shared.start(w.id, size: w.size) { _ in running -= 1; next() }
      }
      if running == 0 { catching = false }
    }
    next()
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
        return Msg.FileRef(id: fid, name: f["name"] as? String ?? "File", size: f["size"] as? Int ?? 0, kind: f["kind"] as? String ?? "file", w: f["w"] as? Double, h: f["h"] as? Double, secs: f["secs"] as? Double, wave: f["wave"] as? String, thumb: f["thumb"] as? String)
      }
      let r = (e["reply"] as? [String: Any]).flatMap { r -> Msg.Reply? in
        guard let rid = r["id"] as? String, !rid.isEmpty else { return nil }
        return Msg.Reply(id: rid, by: r["by"] as? String ?? "", text: r["text"] as? String ?? "", kind: r["kind"] as? String ?? "text")
      }
      var m = Msg(id: id, cid: e["cid"] as? String, seq: seq, by: by, at: at, kind: e["kind"] as? String ?? "text", text: e["text"] as? String ?? "",
                  file: f, reply: r, mentions: e["mentions"] as? [String] ?? [], fwd: (e["fwd"] as? Bool) == true ? true : nil)
      m.album = e["album"] as? String
      m.task = Msg.TaskCard(e["task"] as? [String: Any])
      // (their message is here: they've stopped typing)
      DispatchQueue.main.async { Talk.shared.stoppedTyping(g, by) }
      if let k = e["link"] as? [String: Any], let u = k["url"] as? String {
        m.link = Msg.LinkPrev(url: u, title: k["title"] as? String, site: k["site"] as? String, video: (k["video"] as? Bool) == true,
                              img: (k["img"] as? [String: Any])?["id"] as? String, icon: (k["icon"] as? [String: Any])?["id"] as? String, e11: k["e11"] as? String,
                              pic: (k["pic"] as? String).flatMap { $0.hasPrefix("https://") ? $0 : nil })
        m.link?.client = k["client"] as? String; m.link?.sub = k["sub"] as? String; m.link?.state = k["state"] as? String
      }
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
        if isStarred(g, id) { starred.removeAll { $0.group == g && $0.id == id }; if let d = try? JSONEncoder().encode(starred) { try? d.write(to: starFile, options: .atomic) } }
      }
    case "react":
      if let i = l.msgs.firstIndex(where: { $0.id == id }) { if let em = e["emoji"] as? String, !em.isEmpty { l.msgs[i].reactions[by] = em } else { l.msgs[i].reactions[by] = nil } }
    case "read":
      if let up = e["upto"] as? String {
        l.readBy[by] = up
        var marks = l.readAt ?? [:]; marks[by, default: []].append(.init(upto: up, at: at)); marks[by] = Array(marks[by]!.suffix(300)); l.readAt = marks
      }
    case "got":
      // (a phone has the messages up to here — Message info's Delivered to)
      if let up = e["upto"] as? String { var marks = l.gotAt ?? [:]; marks[by, default: []].append(.init(upto: up, at: at)); marks[by] = Array(marks[by]!.suffix(300)); l.gotAt = marks }
    default: return nil
    }
    logs[g] = l
    saveSoon(g)
    return g
  }

  // ---------- sending from here: shown at once, then the server's copy takes its place ----------
  func send(_ g: String, text: String, reply: Msg? = nil, mentions: [String] = [], file: Msg.FileRef? = nil, localFile: URL? = nil, upload: Data? = nil, fwd: Bool = false, album: String? = nil, task: Msg.TaskCard? = nil, progress: ((Double) -> Void)? = nil) {
    guard let me = me else { return }
    let cid = UUID().uuidString
    var l = log(g)
    var m = Msg(id: "local-" + cid, cid: cid, seq: Int.max, by: me.id, at: Date().timeIntervalSince1970 * 1000, kind: file?.kind ?? "text", text: text, file: file,
                reply: reply.map { Msg.Reply(id: $0.id, by: $0.by, text: Talk.preview($0), kind: $0.kind) }, mentions: mentions, pending: true, fwd: fwd ? true : nil)
    m.album = album; m.task = task
    if let lf = localFile, let f = file { try? FileManager.default.copyItem(at: lf, to: Net.local(f.id)) }
    // (a photo's or video's tiny picture goes with it — shown blurred on phones that haven't downloaded it yet)
    let thumb = file?.thumb ?? (file.flatMap { f in localFile.flatMap { Thumb.make($0, kind: f.kind) } })
    l.msgs.append(m); logs[g] = l; saveSoon(g)
    NotificationCenter.default.post(name: .talkGroup, object: g); NotificationCenter.default.post(name: .talkChanged, object: nil)
    var linkBody: [String: Any]? = nil
    let go = { (fileId: String?) in
      var b: [String: Any] = ["act": "send", "group": g, "text": text, "cid": cid, "mentions": mentions]
      if let lb = linkBody { b["link"] = lb }
      if let a = album { b["album"] = a }
      if let t = task { b["task"] = ["id": t.id] }
      if fwd { b["fwd"] = true }
      if let r = m.reply { b["reply"] = ["id": r.id, "by": r.by, "text": r.text, "kind": r.kind] }
      if let f = file, let fid = fileId { var fd: [String: Any] = ["id": fid, "kind": f.kind]; fd["w"] = f.w; fd["h"] = f.h; fd["secs"] = f.secs; fd["wave"] = f.wave; fd["thumb"] = thumb; b["file"] = fd }
      Net.shared.act(b) { [weak self] j in
        guard let self = self else { return }
        // (the send sound once the server has it — not while the clock shows it on its way; every kind, Haris 2026-11-12)
        if (j?["ok"] as? Bool) == true { DispatchQueue.main.async { ChatSound.send() }; self.sync() } else { self.mark(g, cid, failed: true) }
      }
    }
    if let data = upload, let f = file {
      Net.shared.upload(data, name: f.name, progress: { p in progress?(p) }) { [weak self] fid in
        guard let fid = fid else { self?.mark(g, cid, failed: true); return }
        try? FileManager.default.copyItem(at: Net.local(f.id), to: Net.local(fid))
        m.file?.id = fid
        go(fid)
      }
    } else if file == nil, !fwd, task == nil, let u = LinkPrevMaker.firstLink(text), !LinkPrevMaker.ours(u) {
      // (words with a link: its preview made here first — the picture and the site's icon sent up as files — then the
      //  message with it; the clock shows meanwhile, and the message goes without a preview if none comes)
      LinkPrevMaker.make(u) { [weak self] prev, img, icon in
        guard let self = self, var prev = prev else { go(nil); return }
        let up = { (d: Data?, name: String, done: @escaping (String?) -> Void) in
          guard let d = d else { done(nil); return }
          Net.shared.upload(d, name: name, progress: { _ in }) { fid in if let fid = fid { try? d.write(to: Net.local(fid)) }; done(fid) }
        }
        up(img, "preview.jpg") { imgId in
          up(icon, "icon.png") { iconId in
            prev.img = imgId; prev.icon = iconId
            var lb: [String: Any] = ["url": prev.url, "video": prev.video]
            lb["title"] = prev.title; lb["site"] = prev.site
            if let i = imgId { lb["img"] = ["id": i] }; if let i = iconId { lb["icon"] = ["id": i] }
            linkBody = lb
            self.local(g, m.id) { $0.link = prev }
            go(nil)
          }
        }
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
  // what you do shows at once (the rule of every page): the change on this phone first, the server's answer after — a
  // refusal puts the message back as it was
  @discardableResult func local(_ g: String, _ id: String, _ change: (inout Msg) -> Void) -> Msg? {
    var l = log(g); guard let i = l.msgs.firstIndex(where: { $0.id == id }) else { return nil }
    let was = l.msgs[i]; change(&l.msgs[i]); logs[g] = l; saveSoon(g)
    NotificationCenter.default.post(name: .talkGroup, object: g); NotificationCenter.default.post(name: .talkChanged, object: nil)
    return was
  }
  func putBack(_ g: String, _ m: Msg) { local(g, m.id) { $0 = m } }
  // deleted for me: it stays in its place as "You deleted this message" (Haris 2026-11-12), its words and file gone from
  // this phone; one never sent (still on its way, or failed) simply goes
  func deleteForMe(_ g: String, _ m: Msg) {
    var l = log(g)
    // (a message already deleted — its "deleted" line — goes from my chat altogether, as WhatsApp's)
    if m.pending || m.deleted { l.msgs.removeAll { $0.id == m.id } }
    else if let i = l.msgs.firstIndex(where: { $0.id == m.id }) {
      l.msgs[i].deleted = true; l.msgs[i].goneForMe = true; l.msgs[i].text = ""; l.msgs[i].file = nil; l.msgs[i].reply = nil; l.msgs[i].reactions = [:]
    }
    logs[g] = l; saveSoon(g)
    if let f = m.file { try? FileManager.default.removeItem(at: Net.local(f.id)) }
    NotificationCenter.default.post(name: .talkGroup, object: g); NotificationCenter.default.post(name: .talkChanged, object: nil)
  }
  // seen up to the newest: the others see "Seen by"; my unread count goes
  func markRead(_ g: String) {
    var l = log(g)
    if unmark(g) { NotificationCenter.default.post(name: .talkChanged, object: nil); badge() }
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
        var hay = m.text + " " + (m.file?.name ?? "")
        // (staff: an E11 link card's file or folder name and client, and a task card's title, as they are now — Haris 2026-11-13)
        if !isContact {
          if let l = m.link.map({ liveLink($0) }), l.e11 != nil { hay += " " + (l.title ?? "") + " " + (l.client ?? "") }
          if let t = m.task.map({ liveTask($0) }) { hay += " " + t.title + " " + t.client }
        }
        if hay.range(of: n, options: [.caseInsensitive, .diacriticInsensitive]) != nil { out.append((g, m)) }
      }
    }
    return out.sorted { $0.1.at > $1.1.at }
  }

  // ---------- for the lists ----------
  // (Mark as Unread — WhatsApp's, Haris 2026-11-13: a chat you've read marked to come back to; a dot on its row with no
  //  number, counted as 1 everywhere (the tabs, the app's badge, E11 Console's Talk button) until the chat is opened again.
  //  Kept on this phone.)
  private var markKey: String { "talk_marked_unread_" + Server.host }
  private(set) lazy var marked: Set<String> = Set(UserDefaults.standard.stringArray(forKey: markKey) ?? [])
  func markUnread(_ g: String) {
    guard realUnread(g) == 0, !marked.contains(g) else { return }
    marked.insert(g); UserDefaults.standard.set(Array(marked), forKey: markKey)
    NotificationCenter.default.post(name: .talkChanged, object: nil); badge()
  }
  private func unmark(_ g: String) -> Bool {
    guard marked.remove(g) != nil else { return false }
    UserDefaults.standard.set(Array(marked), forKey: markKey); return true
  }
  func unread(_ g: String) -> Int { max(realUnread(g), marked.contains(g) ? 1 : 0) }
  // what a row shows: the number, or -1 for the dot alone (marked unread)
  func unreadShown(_ g: String) -> Int { let r = realUnread(g); return r > 0 ? r : marked.contains(g) ? -1 : 0 }
  func clientUnreadShown(_ c: String, withClient: Bool? = nil) -> Int {
    let gs = groups(of: c, withClient: withClient), r = gs.reduce(0) { $0 + realUnread($1.id) }
    return r > 0 ? r : gs.contains { marked.contains($0.id) } ? -1 : 0
  }
  func realUnread(_ g: String) -> Int {
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
  func badge() { UIApplication.shared.applicationIconBadgeNumber = totalUnread; tellUnread() }
  // (your count to the server, for E11 Console's Talk button — only when it changed, a moment after; staff only, as client
  //  contacts have no E11 Console — Haris 2026-11-13)
  private var toldUnread: (Int, Int)?, tellSoon = false
  private func tellUnread() {
    guard !isContact, me != nil, !tellSoon else { return }
    tellSoon = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self = self else { return }
      self.tellSoon = false
      let now = (self.totalUnread, self.lastSeq)
      if let t = self.toldUnread, t == now { return }
      Net.shared.act(["act": "unread", "n": now.0, "seq": now.1]) { [weak self] j in if (j?["ok"] as? Bool) == true { DispatchQueue.main.async { self?.toldUnread = now } } }
    }
  }
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
    default: if let t = m.task, m.text.isEmpty { return "☑️ " + t.title }; return m.text
    }
  }
  // ---------- for the iCloud backup (Backup.swift) ----------
  var localDir: URL { dir }
  var syncedUpTo: Int { get { lastSeq } set { lastSeq = newValue } }
  // nothing of this account on the phone yet (a new phone, or signed in again)
  var isFresh: Bool { lastSeq == 0 && ((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.allSatisfy { !$0.hasPrefix("g-") } ?? true) }
  // the files the chats point to (videos only when asked)
  func fileIds(videos: Bool) -> Set<String> {
    flush()
    var out = Set<String>()
    let fs = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    for f in fs where f.hasPrefix("g-") && f.hasSuffix(".json") {
      let g = String(f.dropFirst(2).dropLast(5))
      for m in log(g).msgs where !m.deleted { if let r = m.file, videos || m.kind != "video" { out.insert(r.id) } }
    }
    return out
  }
  // ---------- a Mac just linked: the chats to hand it (each group's messages, who's seen what) and their files ----------
  func handOver() -> (groups: [[String: Any]], files: [(id: String, name: String)]) {
    flush()
    var gs: [[String: Any]] = [], files: [(String, String)] = [], seen = Set<String>()
    for g in groups.keys {
      let l = log(g)
      guard let d = try? JSONEncoder().encode(l), var j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
      j["msgs"] = ((j["msgs"] as? [[String: Any]]) ?? []).filter { ($0["pending"] as? Bool) != true }
      j["group"] = g
      gs.append(j)
      for m in l.msgs where !m.deleted && !m.pending && m.kind != "video" {
        if let f = m.file, !seen.contains(f.id), FileManager.default.fileExists(atPath: Net.local(f.id).path) { seen.insert(f.id); files.append((f.id, f.name)) }
      }
    }
    return (gs, files)
  }
  func reloadFromDisk() {
    logs = [:]
    loadLocal()
    NotificationCenter.default.post(name: .talkChanged, object: nil)
  }
  func signOut() {
    Net.shared.stopListening(); Net.shared.cookie = nil
    logs = [:]; groups = [:]; me = nil
    try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: Net.filesDir)
    UserDefaults.standard.removeObject(forKey: "talk_seq_" + Server.host)
    VoiceHeard.clear(); starred = []; Talk.cards = Cards()
  }
}

// ---------- small shared pieces ----------
enum Look {
  static let accent = UIColor(red: 0.18, green: 0.44, blue: 0.89, alpha: 1)   // E11 Talk's blue (#2f6fe4)
  // the chat's colours, from the approved design (canvas "E11 Talk — design", 2026-11-11): dark · light
  static func dyn(_ dark: UInt32, _ light: UInt32) -> UIColor { UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) } }
  static func rgb(_ v: UInt32, _ a: CGFloat = 1) -> UIColor { UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a) }
  static let mine = dyn(0x2B5FA3, 0x2F7BFF)          // your bubbles
  static let theirs = dyn(0x262628, 0xFFFFFF)        // everyone else's
  static let chatBg = dyn(0x0A0A0A, 0xF2F2F7)        // behind the chat
  static let field = dyn(0x2B2B2B, 0xFFFFFF)         // the message box
  static let dayChip = dyn(0x1C1C1E, 0xFFFFFF)       // "Today", "Yesterday"
  static let downBtn = dyn(0x2C2C2E, 0xFFFFFF)       // the scroll-down button
  static let clientInk = dyn(0xFFB340, 0xD97A00)     // "Client can see this group", a client's "Client"
  static let roleInk = UIColor.systemGray
  static let linkInk = dyn(0x6FB6FF, 0x007AFF)        // a link in someone else's message            // a role under a name (#8E8E93)
  static let mineTime = UIColor { $0.userInterfaceStyle == .dark ? rgb(0xA9C3E6) : UIColor.white.withAlphaComponent(0.8) }
  // ✓✓ read by everyone: a bright aqua that stands apart from our blue bubble (Haris 2026-11-12)
  static let readTick = dyn(0x6FF2FF, 0xA8FFF4)
  // a person's colour: their initials' colour in E11 Console (Haris 2026-11-11), else one picked from their id
  static func person(_ id: String) -> UIColor { hex(Talk.shared.people[id]?.color) ?? color(for: id) }
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
    let all = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    guard let first = all.first else { return "" }
    let next = all.dropFirst().first { $0.lowercased() != "al" } ?? all.dropFirst().first
    return (String(first.prefix(1)) + (next.map { String($0.prefix(1)) } ?? "")).uppercased()
  }
  // (the date and time words: one formatter of each kind, made once and kept — a new one for every message and every
  //  bubble's time was a good part of a long chat's opening, Haris 2026-11-13; made again if the phone's language or
  //  time zone changes)
  private static var fmts: [String: DateFormatter] = [:]
  private static var fmtFor = ""
  private static func fmt(_ k: String) -> DateFormatter {
    let now = Locale.current.identifier + "|" + TimeZone.current.identifier
    if now != fmtFor { fmts = [:]; fmtFor = now }
    if let f = fmts[k] { return f }
    let f = DateFormatter()
    if k == "clock" { f.timeStyle = .short; f.dateStyle = .none } else { f.dateFormat = k }
    fmts[k] = f; return f
  }
  static func time(_ ms: Double, short: Bool = true) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current
    if cal.isDateInToday(d) { return fmt("clock").string(from: d) }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 { return fmt("EEE").string(from: d) }
    return fmt(short ? "MMM d" : "MMM d, yyyy").string(from: d)
  }
  static func clock(_ ms: Double) -> String { fmt("clock").string(from: Date(timeIntervalSince1970: ms / 1000)) }
  static func day(_ ms: Double) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    return fmt(cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "MMM d, yyyy").string(from: d)
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
    // (a client's logo on E11 Agency: a rounded square, the design's board 1 — 14 on 52; everywhere else a circle)
    layer.cornerRadius = square ? bounds.width * 14 / 52 : bounds.width / 2; layer.cornerCurve = square ? .continuous : .circular
    img.frame = bounds; lbl.frame = bounds.insetBy(dx: 3, dy: 0)
    lbl.font = .systemFont(ofSize: bounds.width * 0.36, weight: .semibold)
  }
  // (a logo — a client's — is shown whole inside the circle on the client's colour, never cut: Haris 2026-11-13)
  private var isLogo = false
  var square = false { didSet { setNeedsLayout() } }
  func set(name: String, color: UIColor, picture: String?, talkFile: String? = nil, logo: Bool = false) {
    lbl.text = Look.initials(name); backgroundColor = color; isLogo = logo
    img.image = nil; img.isHidden = true; lbl.isHidden = false
    let key = talkFile ?? picture
    want = key
    if let f = talkFile {
      var now = true
      Net.shared.file(f) { [weak self] url in guard let self = self, self.want == key, let u = url, let i = UIImage(contentsOfFile: u.path) else { return }; self.reveal(i, fade: !now) }
      now = false
    } else if let p = picture { load(p, key, tries: 3) }
  }
  // the picture in place of the initials — one already on the phone just there, one arriving later fading in over them
  // (the no-snap rule, Haris 2026-11-13)
  private func reveal(_ i: UIImage, fade: Bool) {
    let set = { self.img.image = i; self.img.isHidden = false; self.lbl.isHidden = true }
    if fade, window != nil { UIView.transition(with: self, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction], animations: set) } else { set() }
  }
  // (a picture that didn't come is tried again by itself, a little later — never left as initials until the page is
  //  opened again: E11 Console's lesson, build 1690)
  private func load(_ p: String, _ key: String?, tries: Int) {
    var now = true
    Net.shared.picture(p) { [weak self] i in
      guard let self = self, self.want == key else { return }
      guard let i = i else { if tries > 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.load(p, key, tries: tries - 1) } }; return }
      self.reveal(self.isLogo ? Avatar.inCircle(i) : i, fade: !now)
    }
    now = false
  }
  // a picture straight in (one just picked, before it's uploaded)
  func show(_ i: UIImage) { want = nil; img.image = i; img.isHidden = false; lbl.isHidden = true }
  // a logo drawn whole in the middle of a circle: its corners inside it, with a little room
  static func inCircle(_ raw: UIImage, side: CGFloat = 120) -> UIImage {
    let i = BubbleCell.trimmed(raw)
    let s = i.size; guard s.width > 0, s.height > 0 else { return i }
    let k = side * 0.8 / (s.width * s.width + s.height * s.height).squareRoot()
    let w = s.width * k, h = s.height * k
    // (the circle around it in the logo's own background colour too, as its link card — Haris 2026-11-13)
    let bg = BubbleCell.edgeColour(i)
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
      if let c = bg { c.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: side, height: side)) }
      i.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    }
  }
  // a group: its own picture, else its client's logo, else a letter on the client's colour
  func set(group g: Group) {
    let c = Talk.shared.clients[g.client]
    if g.pic != nil { set(name: g.name, color: Look.hex(c?.color) ?? Look.accent, picture: nil, talkFile: g.pic) }
    else if c?.logo != nil { set(name: c?.name ?? g.name, color: Look.hex(c?.color) ?? Look.accent, picture: c?.logo, logo: true) }
    else { lbl.text = String(g.name.prefix(1)).uppercased(); backgroundColor = Look.hex(c?.color) ?? Look.accent; img.isHidden = true; lbl.isHidden = false; want = nil }
  }
  // a client contact's picture for every group (board 14): "E11." on black
  func setE11() { lbl.text = "E11."; backgroundColor = .black; lbl.textColor = .white; img.isHidden = true; lbl.isHidden = false; want = nil }
  func set(client c: Client) { set(name: c.name, color: Look.hex(c.color) ?? Look.accent, picture: c.logo, logo: true) }
  func set(person p: Person?) { set(name: p?.name ?? "?", color: p.map { Look.person($0.id) } ?? Look.accent, picture: p?.picture, logo: p?.contact == true) }
}

// a short line at the bottom (as Console's toasts)
func toast(_ text: String, in v: UIView? = nil) {
  guard let host = v ?? UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
  let l = PaddedLabel(); l.text = text; l.font = .systemFont(ofSize: 15, weight: .medium); l.textColor = .label; l.numberOfLines = 2; l.textAlignment = .center
  l.backgroundColor = .secondarySystemGroupedBackground; l.layer.cornerRadius = 14; l.layer.masksToBounds = true
  let w = min(host.bounds.width - 48, l.sizeThatFits(CGSize(width: host.bounds.width - 48, height: 80)).width + 32)
  let h = l.sizeThatFits(CGSize(width: w, height: 80)).height + 20
  // (just above whatever is at the bottom of the screen on show — the tab bar, a chat's message bar, or the bottom edge; a
  //  fixed height left it floating high on pages with neither, as Group Info — Haris 2026-11-13)
  let room: CGFloat = {
    guard v == nil, let top = topScreen((host as? UIWindow)?.rootViewController ?? host.window?.rootViewController) else { return 16 }
    if top is ChatVC { return 76 }
    if let tb = top.tabBarController, !tb.tabBar.isHidden, tb.tabBar.alpha > 0, !(top.navigationController?.viewControllers.contains { $0.hidesBottomBarWhenPushed } ?? false) {
      return max(16, tb.tabBar.frame.height - host.safeAreaInsets.bottom + 12)
    }
    return 16
  }()
  l.frame = CGRect(x: (host.bounds.width - w) / 2, y: host.bounds.height - host.safeAreaInsets.bottom - room - h, width: w, height: h)
  l.alpha = 0; host.addSubview(l)
  UIView.animate(withDuration: 0.18) { l.alpha = 1 }
  DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { UIView.animate(withDuration: 0.2, animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() } }
}
// the screen on show: through what's presented, a navigation's top and a tab's selected
func topScreen(_ vc: UIViewController?) -> UIViewController? {
  if let p = vc?.presentedViewController, !p.isBeingDismissed { return topScreen(p) }
  if let n = vc as? UINavigationController { return topScreen(n.visibleViewController) ?? n }
  if let t = vc as? UITabBarController { return topScreen(t.selectedViewController) ?? t }
  return vc
}
// a picture landing after its view is up fades in (the no-snap rule, Haris 2026-11-13); off screen, or replacing one already
// shown, it's just set
extension UIImageView {
  func land(_ i: UIImage?) {
    guard window != nil, i != nil, image == nil else { image = i; return }
    UIView.transition(with: self, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.image = i }
  }
}
final class PaddedLabel: UILabel {
  override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 16, dy: 10)) }
  override func sizeThatFits(_ size: CGSize) -> CGSize { let s = super.sizeThatFits(CGSize(width: size.width - 32, height: size.height)); return CGSize(width: s.width + 32, height: s.height) }
}

// a link's preview, read by Apple's own link reader (LinkPresentation) on the sender's phone — the picture, the title,
// the site, its icon, whether it's a video (Apple gives no length, nor a description)
enum LinkPrevMaker {
  // (our own E11 links — a file, a folder, a task: the server makes their card, as no phone can read those pages)
  static func ours(_ u: URL) -> Bool { ["files.e11hq.com", "files-test.e11hq.com"].contains(u.host ?? "") }
  static func firstLink(_ text: String) -> URL? {
    guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    return d.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url }.first { $0.scheme?.hasPrefix("http") == true }
  }
  static func make(_ url: URL, done: @escaping (Msg.LinkPrev?, Data?, Data?) -> Void) {
    let p = LPMetadataProvider(); p.timeout = 6
    p.startFetchingMetadata(for: url) { md, _ in
      guard let md = md else { DispatchQueue.main.async { done(nil, nil, nil) }; return }
      let site = (md.url ?? url).host?.replacingOccurrences(of: "www.", with: "")
      let prev = Msg.LinkPrev(url: url.absoluteString, title: md.title, site: site, video: md.videoProvider != nil || md.remoteVideoURL != nil, img: nil, icon: nil)
      let group = DispatchGroup()
      var img: Data?, icon: Data?
      if let ip = md.imageProvider, ip.canLoadObject(ofClass: UIImage.self) {
        group.enter(); ip.loadObject(ofClass: UIImage.self) { o, _ in img = (o as? UIImage).flatMap { shrink($0, 800)?.jpegData(compressionQuality: 0.75) }; group.leave() }
      }
      if let ip = md.iconProvider, ip.canLoadObject(ofClass: UIImage.self) {
        group.enter(); ip.loadObject(ofClass: UIImage.self) { o, _ in icon = (o as? UIImage).flatMap { shrink($0, 64)?.pngData() }; group.leave() }
      }
      group.notify(queue: .main) { done(prev, img, icon) }
    }
  }
  private static func shrink(_ i: UIImage, _ w: CGFloat) -> UIImage? {
    let k = min(1, w / max(1, i.size.width)), size = CGSize(width: i.size.width * k, height: i.size.height * k)
    let f = UIGraphicsImageRendererFormat(); f.scale = 1
    return UIGraphicsImageRenderer(size: size, format: f).image { _ in i.draw(in: CGRect(origin: .zero, size: size)) }
  }
}

// ---------- typing (step 5, Haris 2026-11-12): told by the server as it happens, kept only here, for 5 seconds unless told
// again; gone at once when their message comes ----------
extension Talk {
  private static var typingNow: [String: [String: Double]] = [:]
  func typed(_ g: String, _ by: String) {
    guard by != me?.id else { return }
    let was = typers(g)
    Talk.typingNow[g, default: [:]][by] = Date().timeIntervalSince1970 + 5
    if typers(g) != was { NotificationCenter.default.post(name: .talkTyping, object: g) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.1) { [weak self] in self?.expireTyping(g) }
  }
  func stoppedTyping(_ g: String, _ by: String) {
    guard Talk.typingNow[g]?.removeValue(forKey: by) != nil else { return }
    NotificationCenter.default.post(name: .talkTyping, object: g)
  }
  private func expireTyping(_ g: String) {
    let t = Date().timeIntervalSince1970
    let gone = (Talk.typingNow[g] ?? [:]).filter { $0.value <= t }.map { $0.key }
    guard !gone.isEmpty else { return }
    gone.forEach { Talk.typingNow[g]?.removeValue(forKey: $0) }
    NotificationCenter.default.post(name: .talkTyping, object: g)
  }
  func typers(_ g: String) -> [String] {
    let t = Date().timeIntervalSince1970
    return (Talk.typingNow[g] ?? [:]).filter { $0.value > t }.map { $0.key }.sorted()
  }
  // "Omar is typing…", "Lana and Nadia are typing…", "Lana and 2 others are typing…" — first names
  func typingLine(_ g: String) -> String? {
    let ns = typers(g).map { String(name($0).split(separator: " ").first ?? "Someone") }
    switch ns.count {
    case 0: return nil
    case 1: return "\(ns[0]) is typing…"
    case 2: return "\(ns[0]) and \(ns[1]) are typing…"
    default: return "\(ns[0]) and \(ns.count - 1) others are typing…"
    }
  }
}

// ---------- E11 link cards as their files and folders are now (Haris 2026-11-13): asked for with the task cards ----------
extension Talk {
  // (kept on the phone, so a chat opens with its cards as they were last — drawn at their full size at once; only kept in
  //  memory, the cards opened bare after a fresh start and grew when the server's answer came, moving the chat: Haris
  //  2026-11-13. Gone with the rest of the phone's copy on sign-out.)
  struct Cards: Codable { var links: [String: Msg.LinkPrev] = [:]; var tasks: [String: Msg.TaskCard] = [:] }
  private static var cardsFile: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("talk", isDirectory: true).appendingPathComponent("cards-\(Server.host).json")
  }
  static var cards: Cards = (try? Data(contentsOf: cardsFile)).flatMap { try? JSONDecoder().decode(Cards.self, from: $0) } ?? Cards()
  static func saveCards() {
    let c = cards
    DispatchQueue.global(qos: .utility).async { if let d = try? JSONEncoder().encode(c) { try? d.write(to: cardsFile, options: .atomic) } }
  }
  private static var liveLinks: [String: Msg.LinkPrev] { get { cards.links } set { cards.links = newValue } }
  // (an E11 link sent before the cards came — its message has no card of its own — gets its live card too: Haris 2026-11-13)
  static let e11Pattern = try! NSRegularExpression(pattern: "^https?://files(-test)?\\.e11hq\\.com/[fd]/", options: [.caseInsensitive])
  static func isE11(_ url: String) -> Bool { e11Pattern.firstMatch(in: url, range: NSRange(location: 0, length: (url as NSString).length)) != nil }
  func liveLink(_ l: Msg.LinkPrev) -> Msg.LinkPrev { l.e11 == nil && !Talk.isE11(l.url) ? l : Talk.liveLinks[l.url] ?? l }
  static func linkCard(_ k: [String: Any]) -> Msg.LinkPrev? {
    guard let u = k["url"] as? String else { return nil }
    var l = Msg.LinkPrev(url: u, title: k["title"] as? String, site: k["site"] as? String, video: false, img: nil, icon: nil, e11: k["e11"] as? String,
                         pic: (k["pic"] as? String).flatMap { $0.hasPrefix("https://") ? $0 : nil })
    l.client = k["client"] as? String; l.sub = k["sub"] as? String; l.state = k["state"] as? String
    return l
  }
  func refreshLinks(_ g: String) {
    let urls = Array(Set(log(g).msgs.compactMap { m in m.deleted ? nil : m.link.flatMap { $0.e11 != nil || Talk.isE11($0.url) ? $0.url : nil } }))
    guard !urls.isEmpty else { return }
    Net.shared.act(["act": "linkCards", "group": g, "urls": urls]) { j in
      let cards = ((j?["cards"] as? [[String: Any]]) ?? []).compactMap { Talk.linkCard($0) }
      DispatchQueue.main.async {
        var changed = false
        for c in cards where Talk.liveLinks[c.url] != c { Talk.liveLinks[c.url] = c; changed = true }
        if changed { Talk.saveCards(); NotificationCenter.default.post(name: .talkGroup, object: g) }
      }
    }
  }
}

// ---------- task cards as their tasks are now (Haris 2026-11-12): asked for as a chat opens and when the app comes back ----------
extension Talk {
  private static var live: [String: Msg.TaskCard] { get { cards.tasks } set { cards.tasks = newValue } }
  func liveTask(_ t: Msg.TaskCard) -> Msg.TaskCard { Talk.live[t.id] ?? t }
  func refreshTasks(_ g: String) {
    let ids = Array(Set(log(g).msgs.compactMap { $0.deleted ? nil : $0.task?.id }))
    guard !ids.isEmpty, groups[g]?.withClient != true, !isContact else { return }
    Net.shared.act(["act": "taskCards", "group": g, "ids": ids]) { j in
      let cards = ((j?["cards"] as? [[String: Any]]) ?? []).compactMap { Msg.TaskCard($0) }
      DispatchQueue.main.async {
        var changed = false
        for c in cards where Talk.live[c.id] != c { Talk.live[c.id] = c; changed = true }
        if changed { Talk.saveCards(); NotificationCenter.default.post(name: .talkGroup, object: g) }
      }
    }
  }
}
