import UIKit
import LinkPresentation
import SafariServices

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
  var contact: SharedContact? = nil       // (a contact card, from the + sheet — Haris 2026-11-16)
  var place: SharedPlace? = nil           // (a place: your current location or one nearby)
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
  struct LinkPrev: Codable, Equatable, Hashable { var url: String; var title: String?; var site: String?; var video: Bool; var img: String?; var icon: String?; var e11: String? = nil; var pic: String? = nil; var client: String? = nil; var sub: String? = nil; var state: String? = nil }   // (client / sub / state: an E11 link's live card — "ok", "off", "gone", "none": no such link)   // (pic: an E11 link's picture, its page's own — a web address)   // (e11: one of our own links — "file" / "folder", its card from the server)
  struct FileRef: Codable, Equatable { var id: String; var name: String; var size: Int; var kind: String; var w: Double?; var h: Double?; var secs: Double?; var wave: String? = nil; var thumb: String? = nil
    var orig: String? = nil   // (sent as the original on purpose: "ProRes RAW" — its bubble says so)
    var prev: String? = nil   // (a sharp small preview, about 320 px — shown at once on phones that haven't downloaded it)
  }
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
      if let p = g["pic"] as? String, let k = g["picKey"] as? String { FileKeys.set(p, k) }   // (its picture locked in R2 — R2Files)
      gs[id] = Group(id: id, client: g["client"] as? String ?? "", name: g["name"] as? String ?? "", creator: g["creator"] as? String ?? "",
                     creatorAdmin: (g["creatorAdmin"] as? Bool) ?? true, second: g["second"] as? String, admins: g["admins"] as? [String] ?? [],
                     pic: g["pic"] as? String, createdAt: (g["createdAt"] as? Double) ?? 0, lastAt: (g["lastAt"] as? Double) ?? 0,
                     members: g["members"] as? [String] ?? [], pinnedAt: g["pinnedAt"] as? Double, mutedUntil: g["mutedUntil"] as? Double, withClient: (g["withClient"] as? Bool) == true,
                     pin: (g["pin"] as? [String: Any]).flatMap { p in (p["id"] as? String).map { Group.Pin(id: $0, by: p["by"] as? String ?? "", text: p["text"] as? String ?? "", kind: p["kind"] as? String ?? "text", pinnedBy: p["pinnedBy"] as? String ?? "") } }, about: g["about"] as? String)
    }
    groups = gs
    if let p = j["pins"] as? [String: Any] { pinnedGroups = p["groups"] as? [String] ?? []; pinnedClients = p["clients"] as? [String] ?? []; pinnedClientGroups = p["clientGroups"] as? [String] ?? []; pinnedClientsTab = p["clientsTab"] as? [String] ?? [] }
    if save, let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: stateFile, options: .atomic) }
    OccasionIcon.take(j["icons"])   // (the app's icon on occasions)
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
      /* "Got it" at once, as WhatsApp: the messages show straight away, with their blurred pictures, and the photos, videos,
         voice notes and files come behind them, three at a time (catchUp, with their rings) — they waited for every file
         first, and on a slow line your own messages stayed on the clock behind them (Haris 2026-11-20 16:58). The server
         keeps each file until every phone has downloaded it, and a day more (1.9.111). Only a link's small preview picture
         and site icon still come first. A file that can't be fetched now: tried again by the next catchUp. */
      let files = evs.flatMap { e -> [String] in
        guard (e["type"] as? String) == "msg" else { return [] }
        let k = e["link"] as? [String: Any]
        return [(k?["img"] as? [String: Any])?["id"] as? String, (k?["icon"] as? [String: Any])?["id"] as? String]
          .compactMap { $0 }.filter { !$0.hasPrefix("local-") && !FileManager.default.fileExists(atPath: Net.local($0).path) }
      }
      self.syncing = true
      self.fetch(files) { [weak self] ok in
        guard let self = self else { return }
        self.syncing = false
        if ok, last > self.lastSeq { self.lastSeq = last; Net.shared.post("/api/talk/ack", ["upto": last]) }
        if !touched.isEmpty { self.catchUp() }
        // (more only when this one brought some — a server that said "more" with nothing kept the phone asking again at once,
        //  over and over, found 2026-11-13)
        if ok && (((j["more"] as? Bool) == true && !evs.isEmpty) || self.again) { self.again = false; self.sync(done) } else { self.again = false; done?() }
      }
    }
  }
  // Auto-download: what a switch or the network kept back, now that it may come (the last 30 days; three at a time)
  private var catching = false, catchAgain = false
  func catchUp() {
    guard me != nil else { return }
    if catching { catchAgain = true; return }   // (new ones while some are coming: looked at again once those are in)
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
      if want.isEmpty && running == 0 { catching = false; if catchAgain { catchAgain = false; catchUp() }; return }
      // (Wi-Fi gone again, or a switch turned off: the rest wait)
      while running < 3, let w = want.first {
        want.removeFirst()
        guard Auto.now(w.kind) else { continue }
        running += 1
        Downloads.shared.start(w.id, size: w.size) { _ in running -= 1; next() }
      }
      if running == 0 { catching = false; if catchAgain { catchAgain = false; catchUp() } }
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
        if let k = f["key"] as? String { FileKeys.set(fid, (f["lock"] as? String) == "p" ? "p:" + k : k) }   // (locked in R2: its key — R2Files; in pieces: "p:")
        var ref = Msg.FileRef(id: fid, name: f["name"] as? String ?? "File", size: f["size"] as? Int ?? 0, kind: f["kind"] as? String ?? "file", w: f["w"] as? Double, h: f["h"] as? Double, secs: f["secs"] as? Double, wave: f["wave"] as? String, thumb: f["thumb"] as? String)
        ref.orig = f["orig"] as? String; ref.prev = f["prev"] as? String
        return ref
      }
      let r = (e["reply"] as? [String: Any]).flatMap { r -> Msg.Reply? in
        guard let rid = r["id"] as? String, !rid.isEmpty else { return nil }
        return Msg.Reply(id: rid, by: r["by"] as? String ?? "", text: r["text"] as? String ?? "", kind: r["kind"] as? String ?? "text")
      }
      var m = Msg(id: id, cid: e["cid"] as? String, seq: seq, by: by, at: at, kind: e["kind"] as? String ?? "text", text: e["text"] as? String ?? "",
                  file: f, reply: r, mentions: e["mentions"] as? [String] ?? [], fwd: (e["fwd"] as? Bool) == true ? true : nil)
      m.album = e["album"] as? String
      m.task = Msg.TaskCard(e["task"] as? [String: Any])
      m.contact = SharedContact(e["contact"] as? [String: Any]); m.place = SharedPlace(e["location"] as? [String: Any])
      // (their message is here: they've stopped typing)
      // (gone from the typers before the chat draws the message, so the message takes the dots' place in the same move —
      //  told a moment later for the line under the group's name: Haris 2026-11-16)
      Talk.shared.stoppedTyping(g, by, quiet: true)
      DispatchQueue.main.async { NotificationCenter.default.post(name: .talkTyping, object: g) }
      if let k = e["link"] as? [String: Any], let u = k["url"] as? String {
        // (its picture and icon locked in R2: their keys — R2Files)
        for x in [k["img"], k["icon"]] { if let x = x as? [String: Any], let fid = x["id"] as? String, let key = x["key"] as? String { FileKeys.set(fid, key) } }
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
    case "history":
      // ("Show them the chat history?": the group's earlier messages, shared by the person who added this one — placed in
      //  time order before what came after, read, with a line saying who shared them; their files' keys — Haris 2026-11-20)
      let old = ((e["msgs"] as? [[String: Any]]) ?? []).compactMap { j -> Msg? in
        guard let d = try? JSONSerialization.data(withJSONObject: j), var m = try? JSONDecoder().decode(Msg.self, from: d) else { return nil }
        m.pending = false; m.failed = false; m.goneForMe = nil
        return m
      }
      for (fid, k) in (e["keys"] as? [String: String]) ?? [:] { FileKeys.set(fid, k) }
      let have = Set(l.msgs.map { $0.id })
      let add = old.filter { !have.contains($0.id) }.sorted { $0.seq < $1.seq }
      if let first = add.first, let newest = add.last {
        let since = (e["since"] as? Double) ?? first.at
        let day = DateFormatter(); day.dateFormat = "d MMM"
        let who = people[by]?.name ?? "Someone"
        let line = Msg(id: "hist-" + first.id, cid: nil, seq: first.seq, by: by, at: first.at - 1, kind: "sys", text: "\(who) shared the history from \(day.string(from: Date(timeIntervalSince1970: since / 1000)))", file: nil, reply: nil, mentions: [])
        // (in before the messages that came after them; one of yours still going up stays where it is, at the end)
        let at = l.msgs.firstIndex { $0.pending || $0.seq > newest.seq } ?? l.msgs.count
        l.msgs.insert(contentsOf: [line] + add, at: at)
        if l.myRead == nil { l.myRead = newest.id }   // (old messages: read)
      }
    case "back":
      // (a file asked back from the group is on the server again — AskGroup)
      if let fid = e["file"] as? String {
        let size = l.msgs.first(where: { $0.file?.id == fid })?.file?.size ?? 0
        DispatchQueue.main.async { AskGroup.cameBack(fid, key: e["key"] as? String, lock: e["lock"] as? String, size: size) }
      }
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
        // (read on another of your phones: read here too — this phone's count, its icon badge and E11 Console's Talk button
        //  stayed on the old number while the same account was on two phones: Haris 2026-11-21 11:40)
        if by == me?.id, let ui = l.msgs.firstIndex(where: { $0.id == up }),
           l.myRead.flatMap({ r in l.msgs.firstIndex { $0.id == r } }).map({ ui > $0 }) ?? true {
          l.myRead = up; _ = unmark(g)
          DispatchQueue.main.async { NotificationCenter.default.post(name: .talkChanged, object: nil); Talk.shared.badge() }
        }
        var marks = l.readAt ?? [:]; marks[by, default: []].append(.init(upto: up, at: at)); marks[by] = Array(marks[by]!.suffix(300)); l.readAt = marks
      }
    case "got":
      // (a phone has the messages up to here — Message info's Delivered to)
      // (the same "got" comes twice — first on the live line, then in the sync — kept once)
      if let up = e["upto"] as? String, l.gotAt?[by]?.last?.upto != up { var marks = l.gotAt ?? [:]; marks[by, default: []].append(.init(upto: up, at: at)); marks[by] = Array(marks[by]!.suffix(300)); l.gotAt = marks }
    default: return nil
    }
    logs[g] = l
    saveSoon(g)
    return g
  }

  // ---------- sending from here: shown at once, then the server's copy takes its place ----------
  func send(_ g: String, text: String, reply: Msg? = nil, mentions: [String] = [], file: Msg.FileRef? = nil, localFile: URL? = nil, upload: Data? = nil, fwd: Bool = false, album: String? = nil, task: Msg.TaskCard? = nil, link: LinkPrevMaker.Pick = .auto, contact: SharedContact? = nil, place: SharedPlace? = nil, progress: ((Double) -> Void)? = nil,
            prepare: ((@escaping (URL?) -> Void) -> Void)? = nil) {
    // (prepare: the file made ready behind its bubble — a video's 720p / 1080p copy — the bubble shown at once with its ring
    //  at the start, then sent up: Haris 2026-11-16, "it stays for long and nothing happens")
    guard let me = me else { return }
    let cid = UUID().uuidString
    var l = log(g)
    var m = Msg(id: "local-" + cid, cid: cid, seq: Int.max, by: me.id, at: Date().timeIntervalSince1970 * 1000, kind: file?.kind ?? (contact != nil ? "contact" : place != nil ? "location" : "text"), text: text, file: file,
                reply: reply.map { Msg.Reply(id: $0.id, by: $0.by, text: Talk.preview($0), kind: $0.kind) }, mentions: mentions, pending: true, fwd: fwd ? true : nil)
    m.album = album; m.task = task; m.contact = contact; m.place = place
    // (a link's card goes out at its own size from the first moment — Haris 2026-11-16: "can the cards already be sent in
    //  their own height"): our own file / folder link with the card this phone already has, else the card's place with a
    //  light passing over it until the server's card comes; a task this phone knows, its card; a web link with the preview
    //  read in the box, that preview at once (its picture from the phone, sent up behind it), else the card's place
    //  while it's read — none found: the plain link again)
    var given: LinkPrevMaker.Ready? = nil
    if file == nil, !fwd, task == nil, contact == nil, place == nil, let u = LinkPrevMaker.firstLink(text) {
      let s = u.absoluteString
      if LinkPrevMaker.ours(u) {
        if !isContact, let base = Talk.e11Base(text) {
          m.link = Talk.liveLinks[base] ?? Msg.LinkPrev(url: base, title: nil, site: nil, video: false, img: nil, icon: nil, e11: base.lowercased().contains("/d/") ? "folder" : "file", state: "reading")
        } else if !isContact, groups[g]?.withClient != true, let id = Talk.e11Task(text), let t = Talk.live[id] {
          m.task = t
        }
      } else if case .given(let r) = link, r.prev.url == s {
        given = r
        var p = r.prev
        if let d = r.img { let id = "lp-" + cid; try? d.write(to: Net.local(id)); p.img = id }
        if let d = r.icon { let id = "li-" + cid; try? d.write(to: Net.local(id)); p.icon = id }
        m.link = p
      } else if case .none = link {
      } else {
        m.link = Msg.LinkPrev(url: s, title: nil, site: nil, video: false, img: nil, icon: nil, state: "reading")
      }
    }
    if let lf = localFile, let f = file { try? FileManager.default.copyItem(at: lf, to: Net.local(f.id)) }
    // (a photo's or video's tiny picture goes with it — shown blurred on phones that haven't downloaded it yet)
    let thumb = file?.thumb ?? (file.flatMap { f in localFile.flatMap { Thumb.make($0, kind: f.kind) } })
    l.msgs.append(m); logs[g] = l; saveSoon(g)
    NotificationCenter.default.post(name: .talkGroup, object: g); NotificationCenter.default.post(name: .talkChanged, object: nil)
    var linkBody: [String: Any]? = nil
    var fileKey: String? = nil   // (the file's lock, when it went to R2 — R2Files)
    let go = { (fileId: String?) in
      var b: [String: Any] = ["act": "send", "group": g, "text": text, "cid": cid, "mentions": mentions]
      if let lb = linkBody { b["link"] = lb }
      if let a = album { b["album"] = a }
      if let t = task { b["task"] = ["id": t.id] }
      if let c = contact { b["contact"] = c.json }
      if let p = place { b["location"] = p.json }
      if fwd { b["fwd"] = true }
      if let r = m.reply { b["reply"] = ["id": r.id, "by": r.by, "text": r.text, "kind": r.kind] }
      if let f = file, let fid = fileId { var fd: [String: Any] = ["id": fid, "kind": f.kind]; fd["w"] = f.w; fd["h"] = f.h; fd["secs"] = f.secs; fd["wave"] = f.wave; fd["thumb"] = thumb; fd["orig"] = Talk.origSaid[f.id] ?? f.orig
        // (the sharp preview, from what was really sent — the photo with its mark, the video made smaller in its colours)
        if f.kind == "photo" || f.kind == "video" { fd["prev"] = f.prev ?? Thumb.preview(Net.local(fid), kind: f.kind) }
        // (locked in pieces — "p:" before its key on the phone: the server's word for it is lock "p")
        if let k = fileKey { if k.hasPrefix("p:") { fd["key"] = String(k.dropFirst(2)); fd["lock"] = "p" } else { fd["key"] = k } }
        b["file"] = fd }
      Net.shared.act(b) { [weak self] j in
        guard let self = self else { return }
        // (the send sound once the server has it — not while the clock shows it on its way; every kind, Haris 2026-11-12)
        if (j?["ok"] as? Bool) == true { DispatchQueue.main.async { ChatSound.send() }; self.sync() } else { self.mark(g, cid, failed: true) }
      }
    }
    // (it didn't go: if Talk was left meanwhile, again when Talk is back — else the red !, a tap: Send again / Delete)
    var again: (() -> Void)?, tries = 0, leftAt = BgWatch.left, attempt = 0, failedAt = -1
    let failed = { [weak self] in
      if let f = file, Uploads.isStopped(f.id) { return }
      guard failedAt != attempt else { return }   // (one word per try — three parts failing together said it three times)
      failedAt = attempt
      if BgWatch.left != leftAt, tries < 3, let a = again {
        tries += 1
        BgWatch.whenBack { leftAt = BgWatch.left; attempt += 1; a() }
      } else { self?.mark(g, cid, failed: true) }
    }
    // (iPhone's extra time after leaving Talk, held until the file is up — it was let go the moment the upload began, so a
    //  switch of apps stopped it at once; Haris 2026-11-21 13:37)
    let keepGoing = { () -> () -> Void in
      var id = UIBackgroundTaskIdentifier.invalid
      id = UIApplication.shared.beginBackgroundTask(withName: "talk-send") { UIApplication.shared.endBackgroundTask(id); id = .invalid }
      return { if id != .invalid { UIApplication.shared.endBackgroundTask(id); id = .invalid } }
    }
    let up = { (data: Data, f: Msg.FileRef, finished: @escaping () -> Void) in
      Uploads.set(f.id, 0, total: data.count)
      var going = true   // (a late word of progress after it's up doesn't bring the ring back)
      Net.shared.uploadMsg(data, name: f.name, stop: f.id, progress: { p in guard going else { return }; progress?(p); Uploads.set(f.id, p, total: data.count) }) { fid, key in
        going = false; Uploads.end(f.id); Uploads.done(f.id)
        defer { finished() }
        if Uploads.isStopped(f.id) { return }   // (its ✕: stopped)
        if let fid = fid, let key = key { FileKeys.set(fid, key); fileKey = key }
        guard let fid = fid else { failed(); return }
        try? FileManager.default.copyItem(at: Net.local(f.id), to: Net.local(fid))
        m.file?.id = fid
        go(fid)
      }
    }
    if let prep = prepare, let f = file {
      // (started over if Talk was left while it was made smaller: made smaller again from the picked original, which prep
      //  keeps; left while it was going up: only the upload again, from the copy already made)
      again = {
        Uploads.set(f.id, 0, total: max(1, f.size))
        let end = keepGoing()
        prep { made in
          if Uploads.isStopped(f.id) { end(); return }   // (its ✕ while it was being made smaller)
          // (mapped, not read whole: a big video's pieces are read from the disk as they go up — Haris 2026-11-21)
          guard let made = made, let d = try? Data(contentsOf: made, options: .alwaysMapped) else { Uploads.end(f.id); end(); failed(); return }
          // (what goes up is what the phone keeps for it)
          if made != Net.local(f.id) { try? FileManager.default.removeItem(at: Net.local(f.id)); try? FileManager.default.copyItem(at: made, to: Net.local(f.id)); Talk.madeReady.insert(f.id) }
          again = { let end2 = keepGoing(); if let d2 = try? Data(contentsOf: Net.local(f.id), options: .alwaysMapped) { up(d2, f, end2) } else { end2(); self.mark(g, cid, failed: true) } }
          up(d, f, end)
        }
      }
      again?()
    } else if let data = upload, let f = file {
      again = { let end = keepGoing(); up(data, f, end) }
      again?()
    } else if file == nil, !fwd, task == nil, contact == nil, place == nil, let u = LinkPrevMaker.firstLink(text), !LinkPrevMaker.ours(u), { if case .none = link { return false }; return true }() {
      // (words with a link: its preview — read in the box while it was typed, as far as it got (WhatsApp's), or else read
      //  here first — the picture and the site's icon sent up as files, then the message with it)
      let handle: (Msg.LinkPrev?, Data?, Data?) -> Void = { [weak self] prev, img, icon in
        // (nothing found: the card's place goes and it's the plain link again)
        guard let self = self, var prev = prev else { self?.local(g, m.id) { $0.link = nil }; go(nil); return }
        // (read just now: its card shown at once, the picture and icon from the phone, while they're sent up)
        if given == nil {
          var shown = prev
          if let d = img { let id = "lp-" + cid; try? d.write(to: Net.local(id)); shown.img = id }
          if let d = icon { let id = "li-" + cid; try? d.write(to: Net.local(id)); shown.icon = id }
          self.local(g, m.id) { $0.link = shown }
        }
        // (straight to R2, locked, as the message's own files — its key goes with the link; Haris 2026-11-21)
        var keys: [String: String] = [:]
        let up = { (d: Data?, name: String, local: String, done: @escaping (String?) -> Void) in
          guard let d = d else { done(nil); return }
          Net.shared.uploadMsg(d, name: name, progress: { _ in }) { fid, key in
            if let fid = fid, let key = key { FileKeys.set(fid, key); keys[fid] = key }
            // (the picture already shown under its phone name kept under its new one too — nothing blinks as it changes)
            if let fid = fid {
              try? d.write(to: Net.local(fid)); BubbleCell.alias(local, fid)
              DispatchQueue.main.asyncAfter(deadline: .now() + 30) { try? FileManager.default.removeItem(at: Net.local(local)) }
            }
            done(fid)
          }
        }
        up(img, "preview.jpg", "lp-" + cid) { imgId in
          up(icon, "icon.png", "li-" + cid) { iconId in
            prev.img = imgId; prev.icon = iconId
            var lb: [String: Any] = ["url": prev.url, "video": prev.video]
            lb["title"] = prev.title; lb["site"] = prev.site
            let ref = { (i: String) -> [String: Any] in var r: [String: Any] = ["id": i]; if let k = keys[i] { r["key"] = k }; return r }
            if let i = imgId { lb["img"] = ref(i) }; if let i = iconId { lb["icon"] = ref(i) }
            linkBody = lb
            self.local(g, m.id) { $0.link = prev }
            go(nil)
          }
        }
      }
      if case .given(let r) = link, r.prev.url == u.absoluteString { handle(r.prev, r.img, r.icon) } else { LinkPrevMaker.make(u, done: handle) }
    } else { go(nil) }
  }
  private func mark(_ g: String, _ cid: String, failed: Bool) {
    var l = log(g)
    if let i = l.msgs.firstIndex(where: { $0.cid == cid && $0.pending }) { l.msgs[i].failed = failed; if failed, l.msgs[i].link?.state == "reading" { l.msgs[i].link = nil }; logs[g] = l; saveSoon(g); NotificationCenter.default.post(name: .talkGroup, object: g) }
  }
  // (sent in HD from this phone — kept for Send again; this time Talk is open)
  static var sentHD = Set<String>()
  // (a video whose phone copy is already the made-smaller one — with its watermark: Send again sends it as it is)
  static var madeReady = Set<String>()
  // (a ProRes that went at full size after all: its label, "Original · …", instead of "From …")
  static var origSaid: [String: String] = [:]
  // ✕ on one of yours going up: stopped — the red !, then Send again or Delete (Haris 2026-11-21 13:18)
  func stopped(_ g: String, _ m: Msg) { if let c = m.cid { mark(g, c, failed: true) } }
  func retry(_ g: String, _ m: Msg) {
    deleteForMe(g, m)
    send(g, text: m.text, reply: nil, contact: m.contact, place: m.place)
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
        var hay = m.text + " " + (m.file?.name ?? "") + " " + (m.contact?.name ?? "") + " " + (m.place.map { ($0.name ?? "") + " " + ($0.addr ?? "") } ?? "")
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
  // (and the server's own last activity — right after a fresh sign-in the messages aren't on the phone yet, and the clients
  //  came out in the order their groups were made: Haris 2026-11-14)
  func activity(_ g: Group) -> Double { max(last(g.id)?.at ?? 0, g.lastAt, g.createdAt) }
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
    case "contact": return "👤 " + (m.contact?.name ?? "Contact")
    case "location": return "📍 " + (m.place?.name ?? "Location")
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
  // Signing out keeps this account's chats on the phone, out of sight (Haris 2026-11-14: "I want this"): the same account
  // signing in again finds them all at once, no restore; another account signing in — they're wiped first, never seen
  // (SceneDelegate.start asks the server who it is before anything of the phone's is read). The sign-in running out keeps
  // them too, as before.
  static var keptFor: String? {
    get { UserDefaults.standard.string(forKey: "talk_kept_for") }
    set { UserDefaults.standard.set(newValue, forKey: "talk_kept_for") }
  }
  func signOut() {
    Net.shared.stopListening(); Net.shared.cookie = nil
    flush()
    if let id = me?.id ?? Talk.keptFor { Talk.keptFor = id } else { wipe() }   // (nobody known: nothing kept)
    logs = [:]; groups = [:]; me = nil; Talk.cards = Cards()   // (starred kept with the chats: read again only when wiped)
  }
  // another account signing in on this phone: the last one's chats, files and place in the server's history gone
  func wipe() {
    Talk.keptFor = nil
    logs = [:]; groups = [:]; me = nil
    try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: Net.filesDir)
    // (and made again at once: it was only made when the app started, so after signing out and in again without closing
    //  the app nothing could be kept — a restore's photos, a photo sent, group pictures: Haris 2026-11-14)
    try? FileManager.default.createDirectory(at: Net.filesDir, withIntermediateDirectories: true)
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
  static let mention = dyn(0x82B4FF, 0x1F63D6)       // an @mention: our bubble's blue, toned for each look — white on your own bubble (Haris 2026-11-15)
  static let theirs = dyn(0x262628, 0xFFFFFF)        // everyone else's
  static let chatBg = dyn(0x0A0A0A, 0xF2F2F7)        // behind the chat
  static let field = dyn(0x2B2B2B, 0xFFFFFF)         // the message box
  static let dayChip = dyn(0x1C1C1E, 0xFFFFFF)       // "Today", "Yesterday"
  static let downBtn = dyn(0x2C2C2E, 0xFFFFFF)       // the scroll-down button
  static let clientInk = dyn(0xE2B676, 0xA8692A)     // "Client can see this group", a client's "Client" — a soft amber, not the loud orange (Haris 2026-11-15)
  static let roleInk = UIColor.systemGray
  static let linkInk = dyn(0x6FB6FF, 0x007AFF)        // a link in someone else's message            // a role under a name (#8E8E93)
  static let mineTime = UIColor { $0.userInterfaceStyle == .dark ? rgb(0xA9C3E6) : UIColor.white.withAlphaComponent(0.8) }
  // ✓✓ read by everyone: a bright aqua that stands apart from our blue bubble (Haris 2026-11-12)
  static let readTick = dyn(0x6FF2FF, 0xA8FFF4)
  // a person's colour: their initials' colour in E11 Console (Haris 2026-11-11), else one picked from their id
  static func person(_ id: String) -> UIColor { hex(Talk.shared.people[id]?.color) ?? color(for: id) }
  // a person's colour for words — a name over a bubble, the reply strip and the quoted reply: WhatsApp's own calm palette,
  // taken from its group chats in dark and light (Haris 2026-11-15, its screenshots; sky, pink and orange ours, made the same way), one
  // colour for each person, always the same (from their id)
  static let namePalette: [UIColor] = [
    dyn(0x68A4F0, 0x285CB8),   // blue
    dyn(0x64CC70, 0x408458),   // green
    dyn(0x68C0B4, 0x388074),   // teal
    dyn(0xF4D084, 0x98703C),   // sand
    dyn(0xE47C84, 0xBC283C),   // rose
    dyn(0xEC987C, 0xB45838),   // peach
    dyn(0xA090F4, 0x5C48D4),   // lilac
    dyn(0x6FC8E8, 0x1F7A9E),   // sky
    dyn(0xE88CC8, 0xA8327A),   // pink
    dyn(0xF2A65A, 0xA8600F),   // orange
  ]
  static func nameInk(_ id: String) -> UIColor { namePalette[abs(id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % namePalette.count] }
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
    want = key; standIn = nil
    if let f = talkFile { loadFile(f, key, tries: 3) }
    else if let p = picture { load(p, key, tries: 3) }
  }
  // (a group's picture tried again by itself too — the first ask right after signing in can miss, and it stayed initials
  //  until the app came back from the background: Haris 2026-11-14)
  private func loadFile(_ f: String, _ key: String?, tries: Int) {
    var now = true
    Net.shared.file(f) { [weak self] url in
      guard let self = self, self.want == key else { return }
      guard let u = url, let i = UIImage(contentsOfFile: u.path) else {
        // (a group's picture that can't be had: its client's logo meanwhile, as a group without one — Haris 2026-11-14)
        if let p = self.standIn { self.standIn = nil; self.loadLogo(p, key) }
        if tries > 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.loadFile(f, key, tries: tries - 1) } }
        return
      }
      self.isLogo = false
      self.reveal(i, fade: !now)
    }
    now = false
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
  // (the client's logo, shown while a group's own picture can't be had)
  private var standIn: String?
  private func loadLogo(_ p: String, _ key: String?) {
    Net.shared.picture(p) { [weak self] i in
      guard let self = self, self.want == key, let i = i, self.img.isHidden else { return }
      self.isLogo = true; self.reveal(Avatar.inCircle(i), fade: true)
    }
  }
  // a group: its own picture, else its client's logo, else a letter on the client's colour
  func set(group g: Group) {
    let c = Talk.shared.clients[g.client]
    if g.pic != nil { set(name: g.name, color: Look.hex(c?.color) ?? Look.accent, picture: nil, talkFile: g.pic); standIn = c?.logo }
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
// a link tapped: an E11 Console file, folder or task link opens in E11 Console only while it's signed in on this phone; otherwise
// in Apple's Safari sheet here, as without the app (Haris 2026-11-16 — a client contact with Console on the phone but not
// signed in got its sign-in page and never the file). Every other link as before.
func openLink(_ u: URL) {
  if Talk.isE11Any(u.absoluteString), SignInKeys.consoleKey == nil,
     let top = topScreen(UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController) {
    top.present(SFSafariViewController(url: u), animated: true); return
  }
  UIApplication.shared.open(u)
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
    coming(false)   // (the light passing over its place goes as the picture fades in — or as it turns out not to come)
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
  // what the box read for a link while it was typed (WhatsApp's card above the box, Haris 2026-11-15): given to send as
  // it is at that moment — or nothing, if nothing was read yet or its card was closed with ✕
  struct Ready { var prev: Msg.LinkPrev; var img: Data?; var icon: Data? }
  enum Pick { case auto, given(Ready), none }
  // read while the words are still in the box: the title and site first, then the picture and the icon as each comes
  @discardableResult
  static func read(_ url: URL, step: @escaping (Ready) -> Void, done: @escaping () -> Void = {}) -> LPMetadataProvider {
    let p = LPMetadataProvider(); p.timeout = 20
    p.startFetchingMetadata(for: url) { md, _ in
      guard let md = md else { DispatchQueue.main.async { done() }; return }
      let all = DispatchGroup()
      let site = (md.url ?? url).host?.replacingOccurrences(of: "www.", with: "")
      var r = Ready(prev: Msg.LinkPrev(url: url.absoluteString, title: md.title, site: site, video: md.videoProvider != nil || md.remoteVideoURL != nil, img: nil, icon: nil), img: nil, icon: nil)
      DispatchQueue.main.async { step(r) }
      if let ip = md.iconProvider, ip.canLoadObject(ofClass: UIImage.self) {
        all.enter(); ip.loadObject(ofClass: UIImage.self) { o, _ in let d = (o as? UIImage).flatMap { shrink($0, 64)?.pngData() }; DispatchQueue.main.async { if d != nil { r.icon = d; step(r) }; all.leave() } }
      }
      if let ip = md.imageProvider, ip.canLoadObject(ofClass: UIImage.self) {
        all.enter(); ip.loadObject(ofClass: UIImage.self) { o, _ in let d = (o as? UIImage).flatMap { shrink($0, 800)?.jpegData(compressionQuality: 0.75) }; DispatchQueue.main.async { if d != nil { r.img = d; step(r) }; all.leave() } }
      }
      all.notify(queue: .main) { done() }
    }
    return p
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
  // a message, or its ✓✓ / read / reaction / edit / delete, that came on the live line itself: shown at once, without
  // waiting for the sync — which still follows and collects it, kept once (Haris 2026-11-21 12:08 ✓✓; 12:33 "lets go with A")
  private static let liveTypes: Set<String> = ["msg", "got", "read", "react", "edit", "del"]
  func live(_ e: [String: Any]) {
    guard me != nil, let t = e["type"] as? String, Talk.liveTypes.contains(t) else { return }
    var groupChanged = false
    guard let g = apply(e, &groupChanged) else { return }
    flush()
    NotificationCenter.default.post(name: .talkGroup, object: g)
    if t == "msg" || t == "del" { NotificationCenter.default.post(name: .talkChanged, object: nil); badge() }
    if t == "msg" { catchUp() }   // (its photo or video starts coming at once)
  }
  func typed(_ g: String, _ by: String) {
    guard by != me?.id else { return }
    let was = typers(g)
    Talk.typingNow[g, default: [:]][by] = Date().timeIntervalSince1970 + 5
    if typers(g) != was { NotificationCenter.default.post(name: .talkTyping, object: g) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.1) { [weak self] in self?.expireTyping(g) }
  }
  func stoppedTyping(_ g: String, _ by: String, quiet: Bool = false) {
    guard Talk.typingNow[g]?.removeValue(forKey: by) != nil, !quiet else { return }
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
  // (the link as the server reads it out of the words — its card is kept under that address: a file's or folder's, or a task's id)
  private static let e11Any = try! NSRegularExpression(pattern: "https?://files(?:-test)?\\.e11hq\\.com/([tfd])/([A-Za-z0-9_%.-]{1,120})", options: [.caseInsensitive])
  private static func e11Hit(_ text: String) -> (kind: String, tok: String, url: String)? {
    let ns = text as NSString
    guard let h = e11Any.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (ns.substring(with: h.range(at: 1)).lowercased(), ns.substring(with: h.range(at: 2)).removingPercentEncoding ?? ns.substring(with: h.range(at: 2)), ns.substring(with: h.range))
  }
  /* an E11 file or folder link being written: its card asked for already, so the message goes with it at its own size
     — turned off, deleted, or no such link: the short card at once, never the tall one first (Haris 2026-11-16) */
  private static var peeking = Set<String>(), peekSoon: DispatchWorkItem?
  func peekE11(_ text: String, group g: String) {
    Talk.peekSoon?.cancel()
    guard !isContact, let base = Talk.e11Base(text), Talk.liveLinks[base] == nil, !Talk.peeking.contains(base) else { return }
    // (once the words stop changing for a moment — a link typed by hand isn't asked for at every letter)
    let w = DispatchWorkItem { [weak self] in self?.peekNow(base, g) }
    Talk.peekSoon = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
  }
  private func peekNow(_ base: String, _ g: String) {
    guard Talk.liveLinks[base] == nil, !Talk.peeking.contains(base) else { return }
    Talk.peeking.insert(base)
    Net.shared.act(["act": "linkCards", "group": g, "urls": [base]]) { j in
      let cards = ((j?["cards"] as? [[String: Any]]) ?? []).compactMap { Talk.linkCard($0) }
      DispatchQueue.main.async {
        Talk.peeking.remove(base)
        for c in cards where Talk.liveLinks[c.url] == nil { Talk.liveLinks[c.url] = c }
      }
    }
  }
  static func e11Base(_ text: String) -> String? { e11Hit(text).flatMap { $0.kind == "t" ? nil : $0.url } }
  static func e11Task(_ text: String) -> String? { e11Hit(text).flatMap { $0.kind == "t" ? $0.tok : nil } }
  // (any of E11 Console's own links — a file's, a folder's or a task's: where it opens follows Console's sign-in)
  static func isE11Any(_ url: String) -> Bool { e11Hit(url).map { url.lowercased().hasPrefix($0.url.lowercased()) } ?? false }
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
