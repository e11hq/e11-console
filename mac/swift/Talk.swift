// E11 Console for Mac — E11 Talk inside the Mac app (Haris 2026-11-05/06: "linked to the phone, as WhatsApp links a
// computer"; the blue button below Trash). Not on the website. The Mac must be signed in to E11 Console as the same
// person as the phone: the Mac shows a code, E11 Talk on the iPhone scans it (Settings → Linked devices → Link a Mac),
// the phone hands over its chats (the last 90 days), and from then on this Mac gets every new message itself — kept in
// this Mac's own folder, cleared after 90 days, like the phone. Signing out of E11 Console here, someone else signing in,
// or unlinking from the phone takes the link and the chats away.
import Cocoa
import WebKit
import AVFoundation
import CoreImage

// ---------- the same messages as the phone's (talk/App/Talk.swift) ----------
struct TFile: Codable { var id: String; var name: String; var size: Int; var kind: String; var w: Double?; var h: Double?; var secs: Double?; var wave: String? }
struct TReply: Codable { var id: String; var by: String; var text: String; var kind: String }
struct TMsg: Codable {
  var id: String; var cid: String?; var seq: Int; var by: String; var at: Double; var kind: String; var text: String
  var file: TFile?; var reply: TReply?; var mentions: [String]
  var edited = false, deleted = false, pending = false, failed = false
  var reactions: [String: String] = [:]
  enum K: String, CodingKey { case id, cid, seq, by, at, kind, text, file, reply, mentions, edited, deleted, pending, failed, reactions }
  init(id: String, cid: String?, seq: Int, by: String, at: Double, kind: String, text: String, file: TFile?, reply: TReply?, mentions: [String]) {
    self.id = id; self.cid = cid; self.seq = seq; self.by = by; self.at = at; self.kind = kind; self.text = text; self.file = file; self.reply = reply; self.mentions = mentions
  }
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    id = try c.decode(String.self, forKey: .id); cid = try c.decodeIfPresent(String.self, forKey: .cid)
    seq = (try? c.decodeIfPresent(Int.self, forKey: .seq)) ?? 0; by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? ""
    at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0; kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "text"
    text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
    file = try? c.decodeIfPresent(TFile.self, forKey: .file); reply = try? c.decodeIfPresent(TReply.self, forKey: .reply)
    mentions = (try? c.decodeIfPresent([String].self, forKey: .mentions)) ?? []
    edited = (try? c.decodeIfPresent(Bool.self, forKey: .edited)) ?? false; deleted = (try? c.decodeIfPresent(Bool.self, forKey: .deleted)) ?? false
    pending = (try? c.decodeIfPresent(Bool.self, forKey: .pending)) ?? false; failed = (try? c.decodeIfPresent(Bool.self, forKey: .failed)) ?? false
    reactions = (try? c.decodeIfPresent([String: String].self, forKey: .reactions)) ?? [:]
  }
}
struct TLog: Codable {
  var msgs: [TMsg] = []
  var readBy: [String: String] = [:]
  var myRead: String?
  init() {}
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    msgs = (try? c.decodeIfPresent([TMsg].self, forKey: .msgs)) ?? []
    readBy = (try? c.decodeIfPresent([String: String].self, forKey: .readBy)) ?? [:]
    myRead = try? c.decodeIfPresent(String.self, forKey: .myRead)
  }
  enum K: String, CodingKey { case msgs, readBy, myRead }
}
struct TGroup { let id: String, client: String, name: String, members: [String], createdAt: Double, mutedUntil: Double?, withClient: Bool
  var muted: Bool { (mutedUntil ?? 0) > Date().timeIntervalSince1970 * 1000 } }
struct TPerson { let id: String, name: String, role: String, contact: Bool }

extension Notification.Name {
  static let macTalk = Notification.Name("e11.talk.lists")       // the groups, counts, link state
  static let macTalkGroup = Notification.Name("e11.talk.group")  // object: a group id — its messages
}

// ---------- this Mac's copy and its connection ----------
final class MacTalk: NSObject, URLSessionDataDelegate {
  static let shared = MacTalk()
  private let host = URL(string: SERVER)?.host ?? "server"
  private let fm = FileManager.default
  private(set) var me: TPerson?
  private(set) var groups: [String: TGroup] = [:]
  private(set) var people: [String: TPerson] = [:]
  private(set) var clients: [String: String] = [:]
  private var logs: [String: TLog] = [:]
  var openGroup: String?                 // (the chat on screen: no notification for it, read as it comes)
  var notify: ((String, String, String) -> Void)?   // title, body, group

  var macId: String? { get { defaults.string(forKey: "talk_mac:" + host) } set { defaults.set(newValue, forKey: "talk_mac:" + host) } }
  private var owner: String? { get { defaults.string(forKey: "talk_owner:" + host) } set { defaults.set(newValue, forKey: "talk_owner:" + host) } }
  private var lastSeq: Int { get { defaults.integer(forKey: "talk_seq:" + host) } set { defaults.set(newValue, forKey: "talk_seq:" + host) } }
  var linked: Bool { macId != nil }

  lazy var dir: URL = {
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("E11 Console", isDirectory: true)
      .appendingPathComponent("E11 Talk", isDirectory: true).appendingPathComponent(host, isDirectory: true)
    try? fm.createDirectory(at: base.appendingPathComponent("files", isDirectory: true), withIntermediateDirectories: true)
    return base
  }()
  func local(_ id: String) -> URL { dir.appendingPathComponent("files", isDirectory: true).appendingPathComponent(id.replacingOccurrences(of: "/", with: "_")) }
  private func logFile(_ g: String) -> URL { dir.appendingPathComponent("g-\(g).json") }
  private var stateFile: URL { dir.appendingPathComponent("state.json") }

  // ---------- requests: with this Mac's E11 Console sign-in (the window's cookies), and its link ----------
  private lazy var session: URLSession = {
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 60; c.httpShouldSetCookies = false; c.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: c)
  }()
  private var cookie = ""
  private func withCookies(_ go: @escaping () -> Void) {
    DispatchQueue.main.async {
      WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cs in
        let h = self.host
        self.cookie = cs.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return h == d || h.hasSuffix("." + d) }
          .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        go()
      }
    }
  }
  func request(_ path: String, method: String = "GET", json: Any? = nil, body: Data? = nil, device: Bool = true) -> URLRequest {
    var r = URLRequest(url: URL(string: SERVER + path)!)
    r.httpMethod = method
    if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
    if device, let m = macId { r.setValue(m, forHTTPHeaderField: "X-Talk-Mac") }
    if let j = json, let d = try? JSONSerialization.data(withJSONObject: j) { r.httpBody = d; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let b = body { r.httpBody = b; r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
    return r
  }
  func call(_ path: String, method: String = "GET", json: Any? = nil, device: Bool = true, _ done: @escaping (Int, [String: Any]?) -> Void) {
    withCookies {
      self.session.dataTask(with: self.request(path, method: method, json: json, device: device)) { d, resp, _ in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        DispatchQueue.main.async {
          if code == 410 || (j?["unlinked"] as? Bool) == true { self.unlinked(); done(code, nil); return }
          done(code, j)
        }
      }.resume()
    }
  }
  func act(_ b: [String: Any], _ done: @escaping ([String: Any]?) -> Void = { _ in }) { call("/api/talk/act", method: "POST", json: b) { _, j in done(j) } }

  // ---------- linking (the Mac shows a code; the phone scans it) ----------
  func newCode(_ done: @escaping (String?, String?) -> Void) {
    let name = Host.current().localizedName ?? "Mac"
    call("/api/talk/link/code", method: "POST", json: ["name": name], device: false) { code, j in
      if let c = j?["code"] as? String { done(c, nil) }
      else { done(nil, (j?["error"] as? String) ?? (code == 401 || code == 403 ? "Sign in to E11 Console first" : "Can’t reach E11 Console — check the connection")) }
    }
  }
  func codeStatus(_ code: String, _ done: @escaping (String?, Bool) -> Void) {
    call("/api/talk/link/status?code=" + code, device: false) { _, j in done(j?["mac"] as? String, (j?["expired"] as? Bool) == true) }
  }
  func linkedNow(_ id: String) {
    macId = id; lastSeq = 0; owner = nil
    start()
  }

  // ---------- going ----------
  private var started = false
  func start() {
    guard linked else { return }
    if !started { started = true; loadLocal(); prune() }
    refresh { self.sync() }
    listen()
  }
  func loadLocal() {
    if let d = try? Data(contentsOf: stateFile), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { take(j, save: false) }
  }
  func refresh(_ done: (() -> Void)? = nil) {
    call("/api/talk/state") { _, j in
      if let j = j, (j["ok"] as? Bool) == true {
        let mid = (j["me"] as? [String: Any])?["id"] as? String
        // someone else signed in to E11 Console on this Mac: not their chats — the link is gone
        if let o = self.owner, let m = mid, o != m { self.unlinked(); done?(); return }
        if self.owner == nil { self.owner = mid }
        self.take(j, save: true)
      }
      done?()
    }
  }
  private func take(_ j: [String: Any], save: Bool) {
    func person(_ p: [String: Any]) -> TPerson? {
      guard let id = p["id"] as? String else { return nil }
      return TPerson(id: id, name: p["name"] as? String ?? "", role: p["role"] as? String ?? "", contact: (p["contact"] as? Bool) == true)
    }
    if let m = j["me"] as? [String: Any] { me = person(m) }
    var ps: [String: TPerson] = [:]
    for p in (j["people"] as? [[String: Any]]) ?? [] { if let x = person(p) { ps[x.id] = x } }
    people = ps
    var cs: [String: String] = [:]
    for c in (j["clients"] as? [[String: Any]]) ?? [] { if let id = c["id"] as? String { cs[id] = c["name"] as? String ?? "" } }
    clients = cs
    var gs: [String: TGroup] = [:]
    for g in (j["groups"] as? [[String: Any]]) ?? [] {
      guard let id = g["id"] as? String else { continue }
      gs[id] = TGroup(id: id, client: g["client"] as? String ?? "", name: g["name"] as? String ?? "", members: g["members"] as? [String] ?? [],
                      createdAt: g["createdAt"] as? Double ?? 0, mutedUntil: g["mutedUntil"] as? Double, withClient: (g["withClient"] as? Bool) == true)
    }
    groups = gs
    if save, let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: stateFile, options: .atomic) }
    changed()
  }
  func changed() { NotificationCenter.default.post(name: .macTalk, object: nil) }

  func log(_ g: String) -> TLog {
    if let l = logs[g] { return l }
    let l = (try? Data(contentsOf: logFile(g))).flatMap { try? JSONDecoder().decode(TLog.self, from: $0) } ?? TLog()
    logs[g] = l
    return l
  }
  private func save(_ g: String) { if let l = logs[g], let d = try? JSONEncoder().encode(l) { try? d.write(to: logFile(g), options: .atomic) } }

  // ---------- events: picked up, their files fetched, then the server told this Mac has them ----------
  private var syncing = false, again = false
  func sync() {
    guard linked else { return }
    if syncing { again = true; return }
    syncing = true
    call("/api/talk/sync?after=\(lastSeq)") { _, j in
      guard let j = j, (j["ok"] as? Bool) == true else { self.syncing = false; return }
      let evs = (j["events"] as? [[String: Any]]) ?? []
      var touched = Set<String>(), groupChanged = false, wanted: [String] = []
      for e in evs { if let g = self.apply(e, &groupChanged, &wanted) { touched.insert(g) } }
      touched.forEach { self.save($0); NotificationCenter.default.post(name: .macTalkGroup, object: $0) }
      if !touched.isEmpty { self.changed() }
      if groupChanged { self.refresh() }
      let last = j["last"] as? Int ?? self.lastSeq
      // (the server lets a file go once every device has it: this Mac fetches its copies before it says so)
      self.fetchAll(wanted) {
        if last > self.lastSeq { self.lastSeq = last; self.call("/api/talk/ack", method: "POST", json: ["upto": last]) { _, _ in } }
        self.syncing = false
        if (j["more"] as? Bool) == true || self.again { self.again = false; self.sync() }
      }
    }
  }
  private func apply(_ e: [String: Any], _ groupChanged: inout Bool, _ wanted: inout [String]) -> String? {
    guard let type = e["type"] as? String else { return nil }
    if type == "history" { history(e, &wanted); return nil }
    guard let g = e["group"] as? String else { return nil }
    let by = e["by"] as? String ?? "", seq = e["seq"] as? Int ?? 0, at = (e["at"] as? Double) ?? Date().timeIntervalSince1970 * 1000
    if type == "group" { groupChanged = true; return nil }
    if type == "gone" { logs[g] = nil; try? fm.removeItem(at: logFile(g)); groupChanged = true; return nil }
    var l = log(g)
    let id = e["id"] as? String ?? ""
    switch type {
    case "msg":
      let f = (e["file"] as? [String: Any]).flatMap { f -> TFile? in
        guard let fid = f["id"] as? String else { return nil }
        return TFile(id: fid, name: f["name"] as? String ?? "File", size: f["size"] as? Int ?? 0, kind: f["kind"] as? String ?? "file", w: f["w"] as? Double, h: f["h"] as? Double, secs: f["secs"] as? Double, wave: f["wave"] as? String)
      }
      let r = (e["reply"] as? [String: Any]).flatMap { r -> TReply? in
        guard let rid = r["id"] as? String, !rid.isEmpty else { return nil }
        return TReply(id: rid, by: r["by"] as? String ?? "", text: r["text"] as? String ?? "", kind: r["kind"] as? String ?? "text")
      }
      let m = TMsg(id: id, cid: e["cid"] as? String, seq: seq, by: by, at: at, kind: e["kind"] as? String ?? "text", text: e["text"] as? String ?? "", file: f, reply: r, mentions: e["mentions"] as? [String] ?? [])
      if let i = l.msgs.firstIndex(where: { $0.id == id || ($0.pending && m.cid != nil && $0.cid == m.cid) }) {
        var keep = m; keep.reactions = l.msgs[i].reactions
        if let old = l.msgs[i].file?.id, let new = m.file?.id, old != new { try? fm.copyItem(at: local(old), to: local(new)) }
        l.msgs[i] = keep
      } else {
        l.msgs.append(m)
        if by != me?.id, m.kind != "sys", !(openGroup == g && NSApp.isActive), let gg = groups[g], !gg.muted || m.mentions.contains(me?.id ?? "-") {
          let who = people[by]?.name ?? "Someone"
          notify?(gg.name, "\(who): \(MacTalk.preview(m))", g)
        }
      }
      if let f = f, f.size < 300 * 1024 * 1024 { wanted.append(f.id) }
    case "edit": if let i = l.msgs.firstIndex(where: { $0.id == id }) { l.msgs[i].text = e["text"] as? String ?? l.msgs[i].text; l.msgs[i].edited = true }
    case "del":
      if let i = l.msgs.firstIndex(where: { $0.id == id }) {
        if let f = l.msgs[i].file { try? fm.removeItem(at: local(f.id)) }
        l.msgs[i].deleted = true; l.msgs[i].text = ""; l.msgs[i].file = nil; l.msgs[i].reply = nil
      }
    case "react":
      if let i = l.msgs.firstIndex(where: { $0.id == id }) { if let em = e["emoji"] as? String, !em.isEmpty { l.msgs[i].reactions[by] = em } else { l.msgs[i].reactions[by] = nil } }
    case "read":
      if let up = e["upto"] as? String { if by == me?.id { l.myRead = up } else { l.readBy[by] = up } }
    default: return nil
    }
    logs[g] = l
    return g
  }
  // the phone's chats, handed over when this Mac was linked: added to what's here
  private func history(_ e: [String: Any], _ wanted: inout [String]) {
    for gj in (e["groups"] as? [[String: Any]]) ?? [] {
      guard let g = gj["group"] as? String, let d = try? JSONSerialization.data(withJSONObject: gj), let h = try? JSONDecoder().decode(TLog.self, from: d) else { continue }
      var l = log(g)
      let have = Set(l.msgs.map { $0.id })
      l.msgs += h.msgs.filter { !have.contains($0.id) && !$0.pending }
      l.msgs.sort { $0.at < $1.at }
      for (k, v) in h.readBy where l.readBy[k] == nil { l.readBy[k] = v }
      if l.myRead == nil { l.myRead = h.myRead }
      logs[g] = l; save(g)
      NotificationCenter.default.post(name: .macTalkGroup, object: g)
    }
    wanted += (e["files"] as? [String]) ?? []
    changed()
  }
  private func fetchAll(_ ids: [String], _ done: @escaping () -> Void) {
    var left = ids.filter { !fm.fileExists(atPath: local($0).path) }
    func next() {
      guard !left.isEmpty else { done(); return }
      let id = left.removeFirst()
      file(id) { _ in next() }
    }
    next()
  }
  func file(_ id: String, _ done: @escaping (URL?) -> Void) {
    let to = local(id)
    if fm.fileExists(atPath: to.path) { done(to); return }
    withCookies {
      self.session.downloadTask(with: self.request("/api/talk/file/" + id)) { tmp, resp, _ in
        guard let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else { DispatchQueue.main.async { done(nil) }; return }
        try? self.fm.removeItem(at: to); try? self.fm.moveItem(at: tmp, to: to)
        DispatchQueue.main.async { done(to) }
      }.resume()
    }
  }

  // ---------- live: the server says when there's something (and when the link is gone) ----------
  private var stream: URLSessionDataTask?, streamSession: URLSession?, buf = ""
  func listen() {
    guard linked, stream == nil else { return }
    withCookies {
      let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 3600; c.timeoutIntervalForResource = 24 * 3600; c.httpShouldSetCookies = false
      let s = URLSession(configuration: c, delegate: self, delegateQueue: .main)
      var r = self.request("/api/talk/stream"); r.setValue("text/event-stream", forHTTPHeaderField: "Accept"); r.timeoutInterval = 3600
      self.streamSession = s; self.stream = s.dataTask(with: r); self.stream?.resume()
    }
  }
  func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    if (response as? HTTPURLResponse)?.statusCode == 410 { unlinked(); completionHandler(.cancel); return }
    completionHandler(.allow)
  }
  func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    buf += String(decoding: data, as: UTF8.self)
    while let r = buf.range(of: "\n\n") {
      let block = String(buf[..<r.lowerBound]); buf = String(buf[r.upperBound...])
      if block.contains("event: unlinked") { unlinked(); return }
      if block.contains("event: talk") { sync() }
    }
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    stream = nil; streamSession?.invalidateAndCancel(); streamSession = nil; buf = ""
    guard linked else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.listen(); self?.sync() }
  }

  // ---------- the link gone (unlinked from the phone, someone else signed in, signed out): its chats go too ----------
  func unlinked() {
    guard linked else { return }
    macId = nil; owner = nil; lastSeq = 0; started = false
    stream?.cancel(); stream = nil
    logs = [:]; groups = [:]; people = [:]; me = nil
    try? fm.removeItem(at: dir)
    lazyReset()
    changed()
  }
  private func lazyReset() { try? fm.createDirectory(at: dir.appendingPathComponent("files", isDirectory: true), withIntermediateDirectories: true) }
  // E11 Console signed out on this Mac: tell the server (while the sign-in still works), then forget
  func signedOut() {
    guard linked else { return }
    let r = request("/api/talk/link/leave", method: "POST", json: [:])
    session.dataTask(with: r).resume()
    unlinked()
  }

  // ---------- what this Mac does ----------
  func send(_ g: String, text: String, reply: TMsg?, fileURL: URL? = nil) {
    guard let me = me else { return }
    let cid = UUID().uuidString
    var l = log(g)
    var file: TFile?
    var kind = "text"
    if let u = fileURL {
      let ext = u.pathExtension.lowercased()
      kind = ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) ? "photo" : ["mov", "mp4", "m4v"].contains(ext) ? "video" : "file"
      let size = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
      var w: Double?, h: Double?
      if kind == "photo", let img = NSImage(contentsOf: u), let rep = img.representations.first { w = Double(rep.pixelsWide); h = Double(rep.pixelsHigh) }
      file = TFile(id: "local-" + cid, name: u.lastPathComponent, size: size, kind: kind, w: w, h: h, secs: nil, wave: nil)
      try? fm.copyItem(at: u, to: local(file!.id))
    }
    var m = TMsg(id: "local-" + cid, cid: cid, seq: Int.max, by: me.id, at: Date().timeIntervalSince1970 * 1000, kind: kind, text: text, file: file,
                 reply: reply.map { TReply(id: $0.id, by: $0.by, text: MacTalk.preview($0), kind: $0.kind) }, mentions: [])
    m.pending = true
    l.msgs.append(m); logs[g] = l; save(g)
    NotificationCenter.default.post(name: .macTalkGroup, object: g); changed()
    let go = { (fileId: String?) in
      var b: [String: Any] = ["act": "send", "group": g, "text": text, "cid": cid, "mentions": [String]()]
      if let r = m.reply { b["reply"] = ["id": r.id, "by": r.by, "text": r.text, "kind": r.kind] }
      if let f = file, let fid = fileId { var fd: [String: Any] = ["id": fid, "kind": f.kind]; fd["w"] = f.w; fd["h"] = f.h; b["file"] = fd }
      self.act(b) { j in if (j?["ok"] as? Bool) == true { self.sync() } else { self.mark(g, cid) } }
    }
    if let f = file, let data = try? Data(contentsOf: local(f.id), options: .mappedIfSafe) {
      upload(data, name: f.name) { fid in
        guard let fid = fid else { self.mark(g, cid); return }
        try? self.fm.copyItem(at: self.local(f.id), to: self.local(fid))
        go(fid)
      }
    } else { go(nil) }
  }
  private func mark(_ g: String, _ cid: String) {
    var l = log(g)
    if let i = l.msgs.firstIndex(where: { $0.cid == cid && $0.pending }) { l.msgs[i].failed = true; logs[g] = l; save(g); NotificationCenter.default.post(name: .macTalkGroup, object: g) }
  }
  private func upload(_ data: Data, name: String, done: @escaping (String?) -> Void) {
    let piece = 4 * 1024 * 1024
    func next(_ id: String?, _ offset: Int) {
      let end = min(data.count, offset + piece), last = end >= data.count
      var q = "/api/talk/upload?offset=\(offset)&name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "file")"
      if let id = id { q += "&id=\(id)" }
      if last { q += "&last=1" }
      withCookies {
        self.session.dataTask(with: self.request(q, method: "POST", body: data.subdata(in: offset..<end))) { d, _, _ in
          let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
          DispatchQueue.main.async {
            guard (j?["ok"] as? Bool) == true, let fid = j?["id"] as? String else { done(nil); return }
            if last { done(fid) } else { next(fid, end) }
          }
        }.resume()
      }
    }
    next(nil, 0)
  }
  func react(_ g: String, _ m: TMsg, _ emoji: String) {
    let mine = log(g).msgs.first { $0.id == m.id }?.reactions[me?.id ?? ""]
    act(["act": "react", "group": g, "id": m.id, "emoji": mine == emoji ? "" : emoji]) { _ in self.sync() }
  }
  func deleteForEveryone(_ g: String, _ m: TMsg) {
    act(["act": "del", "group": g, "id": m.id]) { j in if (j?["ok"] as? Bool) != true { NSSound.beep() }; self.sync() }
  }
  // seen up to here (as on the phone: the others see ✓✓ — staff only, the server sees to that)
  func read(_ g: String) {
    var l = log(g)
    guard let last = l.msgs.last(where: { !$0.pending }), l.myRead != last.id else { return }
    l.myRead = last.id; logs[g] = l; save(g); changed()
    act(["act": "read", "group": g, "upto": last.id])
  }

  // ---------- for the screens ----------
  func unread(_ g: String) -> Int {
    let l = log(g), my = me?.id ?? ""
    let from = l.myRead.flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 + 1 } ?? 0
    return l.msgs[min(from, l.msgs.count)...].filter { $0.by != my && $0.kind != "sys" && !$0.deleted }.count
  }
  var totalUnread: Int { linked ? groups.keys.reduce(0) { $0 + unread($1) } : 0 }
  func last(_ g: String) -> TMsg? { log(g).msgs.last }
  func activity(_ g: TGroup) -> Double { max(last(g.id)?.at ?? 0, g.createdAt) }
  var sortedGroups: [TGroup] { groups.values.sorted { activity($0) > activity($1) } }
  func name(_ id: String) -> String { id == me?.id ? "You" : people[id]?.name ?? "Someone" }
  static func preview(_ m: TMsg) -> String {
    if m.deleted { return "This message was deleted" }
    switch m.kind {
    case "photo": return m.text.isEmpty ? "📷 Photo" : "📷 " + m.text
    case "video": return m.text.isEmpty ? "🎥 Video" : "🎥 " + m.text
    case "voice": return "🎤 Voice message"
    case "file": return "📄 " + (m.file?.name ?? "File")
    default: return m.text
    }
  }
  // every message 90 days after it was sent: gone from this Mac too (as on the phone)
  func prune() {
    let cut = Date().timeIntervalSince1970 * 1000 - 90 * 86400000
    for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("g-") {
      let g = String(f.dropFirst(2).dropLast(5))
      var l = log(g)
      let old = l.msgs.filter { $0.at < cut && !$0.pending }
      guard !old.isEmpty else { continue }
      for m in old { if let fl = m.file { try? fm.removeItem(at: local(fl.id)) } }
      let ids = Set(old.map { $0.id })
      l.msgs.removeAll { ids.contains($0.id) }
      logs[g] = l; save(g)
    }
  }
}

// ======================================================================================================================
// ---------- the screen: the link code, or the chats (groups on the left, the chat on the right) ----------
let TALK_BG = dynColor(NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1), NSColor(srgbRed: 0.047, green: 0.051, blue: 0.059, alpha: 1))
let TALK_PANE = dynColor(.white, NSColor(white: 0.09, alpha: 1))
let TALK_THEIRS = dynColor(.white, NSColor(white: 0.17, alpha: 1))
let TALK_LINE = dynColor(NSColor(white: 0, alpha: 0.09), NSColor(white: 1, alpha: 0.09))
let TALK_NAMES: [NSColor] = [0x2f6fe4, 0xd9480f, 0x2b8a3e, 0xae3ec9, 0xe8590c, 0x0c8599, 0xc2255c, 0x5f3dc4].map {
  NSColor(srgbRed: CGFloat(($0 >> 16) & 255) / 255, green: CGFloat(($0 >> 8) & 255) / 255, blue: CGFloat($0 & 255) / 255, alpha: 1)
}
func talkColor(_ id: String) -> NSColor { TALK_NAMES[abs(id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % TALK_NAMES.count] }
func talkTime(_ ms: Double) -> String {
  let d = Date(timeIntervalSince1970: ms / 1000), f = DateFormatter(), cal = Calendar.current
  if cal.isDateInToday(d) { f.dateFormat = "HH:mm" } else if cal.isDateInYesterday(d) { return "Yesterday" }
  else if Date().timeIntervalSince(d) < 6 * 86400 { f.dateFormat = "EEEE" } else { f.dateFormat = "d MMM" }
  return f.string(from: d)
}

final class TalkView: NSView {
  private let link = TalkLinkView()
  private let left = NSView(), right = NSView()
  private let title = NSTextField(labelWithString: "E11 Talk")
  private let listScroll = NSScrollView(), list = NSTableView()
  private let chat = TalkChatView()
  private let empty = NSTextField(labelWithString: "")
  private var rows: [TGroup] = []
  var current: String? { didSet { MacTalk.shared.openGroup = current } }
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = TALK_BG.cgColor
    title.font = .systemFont(ofSize: 22, weight: .bold)
    let col = NSTableColumn(identifier: .init("g")); list.addTableColumn(col)
    list.headerView = nil; list.rowHeight = 62; list.intercellSpacing = .zero; list.backgroundColor = .clear
    list.selectionHighlightStyle = .none; list.dataSource = self; list.delegate = self
    listScroll.documentView = list; listScroll.drawsBackground = false; listScroll.hasVerticalScroller = true; listScroll.autohidesScrollers = true
    left.addSubview(title); left.addSubview(listScroll)
    empty.font = .systemFont(ofSize: 14); empty.textColor = .secondaryLabelColor; empty.alignment = .center
    empty.stringValue = "Pick a chat on the left"
    right.addSubview(empty); right.addSubview(chat)
    chat.isHidden = true
    [left, right, link].forEach { addSubview($0) }
    NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .macTalk, object: nil)
    reload()
  }
  required init?(coder: NSCoder) { nil }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); layer?.backgroundColor = TALK_BG.cgColor; needsDisplay = true }
  override func layout() {
    super.layout()
    let W = bounds.width, H = bounds.height
    link.frame = bounds
    let lw: CGFloat = min(340, max(280, W * 0.32))
    left.frame = NSRect(x: 0, y: 0, width: lw, height: H)
    right.frame = NSRect(x: lw, y: 0, width: W - lw, height: H)
    title.sizeToFit(); title.frame.origin = NSPoint(x: 18, y: 12 + (36 - title.frame.height) / 2)
    listScroll.frame = NSRect(x: 0, y: 56, width: lw, height: H - 56)
    list.tableColumns.first?.width = lw
    chat.frame = right.bounds
    empty.sizeToFit(); empty.frame = NSRect(x: 0, y: (H - empty.frame.height) / 2, width: right.bounds.width, height: empty.frame.height)
  }
  override func draw(_ r: NSRect) {
    TALK_LINE.setFill(); NSRect(x: left.frame.maxX - 0.5, y: 0, width: 0.5, height: bounds.height).fill()
  }
  @objc func reload() {
    let T = MacTalk.shared
    link.isHidden = T.linked; left.isHidden = !T.linked; right.isHidden = !T.linked
    if !T.linked { current = nil; if window != nil { link.begin() } ; return }
    link.stop()
    rows = T.sortedGroups
    list.reloadData()
    if let c = current, T.groups[c] == nil { show(nil) }
  }
  func show(_ g: String?) {
    current = g
    chat.isHidden = g == nil; empty.isHidden = g != nil
    if let g = g { chat.open(g); MacTalk.shared.read(g) }
    list.reloadData()
  }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); reload() }
}
extension TalkView: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in t: NSTableView) -> Int { rows.count }
  func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
    let v = (t.makeView(withIdentifier: .init("gc"), owner: nil) as? TalkGroupCell) ?? TalkGroupCell()
    v.identifier = .init("gc")
    let g = rows[row]; v.set(g, selected: g.id == current)
    return v
  }
  func tableView(_ t: NSTableView, shouldSelectRow row: Int) -> Bool { show(rows[row].id); return false }
}

final class TalkGroupCell: NSView {
  private var g: TGroup?, selected = false
  override var isFlipped: Bool { true }
  func set(_ g: TGroup, selected: Bool) { self.g = g; self.selected = selected; needsDisplay = true }
  override func draw(_ r: NSRect) {
    guard let g = g else { return }
    let T = MacTalk.shared
    if selected { dynColor(NSColor(white: 0, alpha: 0.07), NSColor(white: 1, alpha: 0.09)).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 10, yRadius: 10).fill() }
    // the group's letter in its colour
    let av = NSRect(x: 18, y: (bounds.height - 40) / 2, width: 40, height: 40)
    talkColor(g.id).setFill(); NSBezierPath(ovalIn: av).fill()
    let letter = NSAttributedString(string: String(g.name.prefix(1)).uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.white])
    let ls = letter.size(); letter.draw(at: NSPoint(x: av.midX - ls.width / 2, y: av.midY - ls.height / 2))
    let x: CGFloat = 70, w = bounds.width - x - 16
    let n = T.unread(g.id)
    let time = NSAttributedString(string: T.last(g.id).map { talkTime($0.at) } ?? "", attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: n > 0 ? TALK_BLUE : NSColor.secondaryLabelColor])
    let tsz = time.size(); time.draw(at: NSPoint(x: bounds.width - 16 - tsz.width, y: 12))
    let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
    NSAttributedString(string: g.name, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: para])
      .draw(in: NSRect(x: x, y: 10, width: w - tsz.width - 8, height: 19))
    let client = T.clients[g.client].map { $0 + " · " } ?? ""
    let prev = T.last(g.id).map { ($0.by == T.me?.id ? "You: " : $0.kind == "sys" ? "" : (T.people[$0.by]?.name.split(separator: " ").first.map(String.init) ?? "") + ": ") + MacTalk.preview($0) } ?? "No messages yet"
    var pw = w
    if n > 0 {
      let c = NSAttributedString(string: "\(n)", attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: NSColor.white])
      let cs = c.size(), bw = max(20, ceil(cs.width) + 10)
      let pill = NSRect(x: bounds.width - 16 - bw, y: 33, width: bw, height: 20)
      TALK_BLUE.setFill(); NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
      c.draw(at: NSPoint(x: pill.midX - cs.width / 2, y: pill.midY - cs.height / 2)); pw -= bw + 8
    }
    let line = NSMutableAttributedString(string: client, attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: para])
    line.append(NSAttributedString(string: prev.replacingOccurrences(of: "\n", with: " "), attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]))
    line.draw(in: NSRect(x: x, y: 34, width: pw, height: 18))
  }
}

// ---------- not linked yet: the code to scan ----------
final class TalkLinkView: NSView {
  private let qr = NSImageView(), head = NSTextField(labelWithString: "Use E11 Talk on this Mac")
  private let steps = NSTextField(wrappingLabelWithString: ""), note = NSTextField(labelWithString: "")
  private var code: String?, poll: Timer?, renew: Timer?, live = false
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    head.font = .systemFont(ofSize: 26, weight: .bold)
    steps.font = .systemFont(ofSize: 15); steps.textColor = .secondaryLabelColor
    steps.stringValue = "1  Open E11 Talk on your iPhone\n2  Go to Settings → Linked devices → Link a Mac\n3  Point your phone at this code\n\nThis Mac must be signed in to E11 Console as you. Your chats come over from your phone, and new messages come here even when your phone is off."
    note.font = .systemFont(ofSize: 13); note.textColor = .tertiaryLabelColor
    qr.imageScaling = .scaleProportionallyUpOrDown
    qr.wantsLayer = true; qr.layer?.backgroundColor = NSColor.white.cgColor; qr.layer?.cornerRadius = 16
    [head, steps, note, qr].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { nil }
  override func layout() {
    super.layout()
    let W = bounds.width, H = bounds.height
    let s: CGFloat = 264, tw: CGFloat = min(420, W - s - 120)
    let total = tw + 60 + s, x0 = (W - total) / 2, y0 = (H - s) / 2
    head.sizeToFit(); head.frame.origin = NSPoint(x: x0, y: y0)
    steps.preferredMaxLayoutWidth = tw
    let sh = steps.sizeThatFits(NSSize(width: tw, height: 1000)).height
    steps.frame = NSRect(x: x0, y: head.frame.maxY + 16, width: tw, height: sh)
    note.sizeToFit(); note.frame.origin = NSPoint(x: x0, y: steps.frame.maxY + 14)
    qr.frame = NSRect(x: x0 + tw + 60, y: y0, width: s, height: s)
  }
  func begin() {
    guard !live else { return }
    live = true
    fresh()
    renew = Timer.scheduledTimer(withTimeInterval: 100, repeats: true) { [weak self] _ in self?.fresh() }
    poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.check() }
  }
  func stop() { live = false; poll?.invalidate(); renew?.invalidate(); poll = nil; renew = nil; code = nil }
  private func fresh() {
    note.stringValue = "Getting a code…"; needsLayout = true
    MacTalk.shared.newCode { [weak self] c, err in
      guard let self = self, self.live else { return }
      self.code = c
      if let c = c { self.qr.image = TalkLinkView.qrImage("e11talk-link:" + c); self.note.stringValue = "The code changes every 2 minutes." }
      else { self.qr.image = nil; self.note.stringValue = err ?? "" }
      self.needsLayout = true
    }
  }
  private func check() {
    guard let c = code else { return }
    MacTalk.shared.codeStatus(c) { [weak self] mac, expired in
      guard let self = self, self.live, self.code == c else { return }
      if let m = mac { self.stop(); self.note.stringValue = "Linked — your chats are coming over…"; MacTalk.shared.linkedNow(m) }
      else if expired { self.fresh() }
    }
  }
  static func qrImage(_ s: String) -> NSImage? {
    guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    f.setValue(Data(s.utf8), forKey: "inputMessage"); f.setValue("M", forKey: "inputCorrectionLevel")
    guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
    let rep = NSCIImageRep(ciImage: out)
    let img = NSImage(size: NSSize(width: out.extent.width + 120, height: out.extent.height + 120))
    img.lockFocus(); NSColor.white.setFill(); NSRect(origin: .zero, size: img.size).fill()
    rep.draw(in: NSRect(x: 60, y: 60, width: out.extent.width, height: out.extent.height)); img.unlockFocus()
    return img
  }
}

// ---------- a chat: its messages and the box to write in ----------
enum TalkItem { case day(String), msg(String) }
final class TalkChatView: NSView, NSTextFieldDelegate {
  private(set) var group = ""
  private let head = NSView(), name = NSTextField(labelWithString: ""), sub = NSTextField(labelWithString: "")
  private let scroll = NSScrollView(), table = NSTableView()
  private let bar = NSView(), box = NSTextField(), attach = NSButton(), sendB = NSButton()
  private let replyV = NSView(), replyL = NSTextField(labelWithString: ""), replyX = NSButton()
  private var items: [TalkItem] = [], msgs: [String: TMsg] = [:]
  private var replying: TMsg? { didSet { replyV.isHidden = replying == nil; replyL.stringValue = replying.map { "Replying to \(MacTalk.shared.name($0.by)): \(MacTalk.preview($0))" } ?? ""; needsLayout = true } }
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    name.font = .systemFont(ofSize: 15, weight: .semibold); sub.font = .systemFont(ofSize: 12); sub.textColor = .secondaryLabelColor
    sub.lineBreakMode = .byTruncatingTail; name.lineBreakMode = .byTruncatingTail
    head.addSubview(name); head.addSubview(sub)
    let col = NSTableColumn(identifier: .init("m")); table.addTableColumn(col)
    table.headerView = nil; table.intercellSpacing = .zero; table.backgroundColor = .clear; table.selectionHighlightStyle = .none
    table.dataSource = self; table.delegate = self
    table.usesAutomaticRowHeights = false
    scroll.documentView = table; scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    box.placeholderString = "Message"; box.font = .systemFont(ofSize: 14); box.delegate = self; box.focusRingType = .none
    box.bezelStyle = .roundedBezel; box.isBordered = true; box.lineBreakMode = .byWordWrapping; box.usesSingleLineMode = false; box.cell?.wraps = true; box.cell?.isScrollable = false
    if #available(macOS 11.0, *) {
      attach.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attach"); sendB.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")
      replyX.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cancel")
    }
    [attach, sendB, replyX].forEach { $0.isBordered = false; $0.bezelStyle = .regularSquare; $0.imageScaling = .scaleProportionallyUpOrDown }
    sendB.contentTintColor = TALK_BLUE; attach.contentTintColor = .secondaryLabelColor; replyX.contentTintColor = .tertiaryLabelColor
    attach.target = self; attach.action = #selector(pick); sendB.target = self; sendB.action = #selector(sendNow)
    replyX.target = self; replyX.action = #selector(cancelReply)
    replyL.font = .systemFont(ofSize: 12); replyL.textColor = .secondaryLabelColor; replyL.lineBreakMode = .byTruncatingTail
    replyV.addSubview(replyL); replyV.addSubview(replyX); replyV.isHidden = true
    [box, attach, sendB, replyV].forEach { bar.addSubview($0) }
    [scroll, head, bar].forEach { addSubview($0) }
    registerForDraggedTypes([.fileURL])
    NotificationCenter.default.addObserver(self, selector: #selector(groupChanged(_:)), name: .macTalkGroup, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(header), name: .macTalk, object: nil)
  }
  required init?(coder: NSCoder) { nil }
  override func layout() {
    super.layout()
    let W = bounds.width, H = bounds.height
    head.frame = NSRect(x: 0, y: 0, width: W, height: 56)
    name.frame = NSRect(x: 20, y: 10, width: W - 40, height: 20); sub.frame = NSRect(x: 20, y: 30, width: W - 40, height: 16)
    let rh: CGFloat = replyV.isHidden ? 0 : 26
    let bh: CGFloat = 54 + rh
    bar.frame = NSRect(x: 0, y: H - bh, width: W, height: bh)
    replyV.frame = NSRect(x: 54, y: 6, width: W - 108, height: 22)
    replyL.frame = NSRect(x: 0, y: 3, width: replyV.bounds.width - 26, height: 16); replyX.frame = NSRect(x: replyV.bounds.width - 18, y: 3, width: 16, height: 16)
    attach.frame = NSRect(x: 16, y: rh + 14, width: 24, height: 24)
    sendB.frame = NSRect(x: W - 44, y: rh + 12, width: 28, height: 28)
    box.frame = NSRect(x: 52, y: rh + 12, width: W - 52 - 56, height: 28)
    scroll.frame = NSRect(x: 0, y: 56, width: W, height: H - 56 - bh)
    let was = table.tableColumns.first?.width ?? 0
    table.tableColumns.first?.width = W
    if abs(was - W) > 1 { table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<items.count)) }
  }
  override func draw(_ r: NSRect) {
    TALK_PANE.setFill(); head.frame.fill(); bar.frame.fill()
    TALK_LINE.setFill(); NSRect(x: 0, y: head.frame.maxY - 0.5, width: bounds.width, height: 0.5).fill(); NSRect(x: 0, y: bar.frame.minY, width: bounds.width, height: 0.5).fill()
  }
  func open(_ g: String) {
    let changed = g != group
    group = g
    if changed { replying = nil; box.stringValue = "" }
    header()
    reload(scrollToEnd: true)
    window?.makeFirstResponder(box)
  }
  @objc private func header() {
    let T = MacTalk.shared
    guard let g = T.groups[group] else { return }
    name.stringValue = g.name
    let names = g.members.filter { $0 != T.me?.id }.compactMap { T.people[$0]?.name.split(separator: " ").first.map(String.init) } + ["You"]
    sub.stringValue = (T.clients[g.client].map { $0 + " · " } ?? "") + names.joined(separator: ", ")
    box.placeholderString = g.withClient ? "Message — client can see this" : "Message"
  }
  @objc private func groupChanged(_ n: Notification) {
    guard (n.object as? String) == group, !isHidden else { return }
    let atEnd = scroll.contentView.bounds.maxY >= table.frame.height - 40
    reload(scrollToEnd: atEnd)
    if window?.isKeyWindow == true { MacTalk.shared.read(group) }
  }
  private func reload(scrollToEnd: Bool) {
    let l = MacTalk.shared.log(group)
    var out: [TalkItem] = [], last = ""
    let f = DateFormatter(); f.dateStyle = .medium; f.doesRelativeDateFormatting = true
    msgs = [:]
    for m in l.msgs {
      let day = f.string(from: Date(timeIntervalSince1970: m.at / 1000))
      if day != last { out.append(.day(day)); last = day }
      out.append(.msg(m.id)); msgs[m.id] = m
    }
    items = out
    table.reloadData()
    if scrollToEnd { DispatchQueue.main.async { self.table.scrollRowToVisible(max(0, self.items.count - 1)) } }
  }
  private func msgBefore(_ row: Int) -> TMsg? {
    guard row > 0, case .msg(let id) = items[row - 1] else { return nil }
    return msgs[id]
  }
  // ---------- writing ----------
  func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
    if sel == #selector(NSResponder.insertNewline(_:)) {
      if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { textView.insertNewlineIgnoringFieldEditor(nil); return true }
      sendNow(); return true
    }
    if sel == #selector(NSResponder.cancelOperation(_:)), replying != nil { replying = nil; return true }
    return false
  }
  @objc func sendNow() {
    let t = box.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    MacTalk.shared.send(group, text: t, reply: replying)
    box.stringValue = ""; replying = nil
    reload(scrollToEnd: true)
  }
  @objc private func cancelReply() { replying = nil }
  @objc private func pick() {
    let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false
    p.beginSheetModal(for: window!) { r in if r == .OK { self.sendFiles(p.urls) } }
  }
  private func sendFiles(_ urls: [URL]) {
    for u in urls { MacTalk.shared.send(group, text: "", reply: nil, fileURL: u) }
    reload(scrollToEnd: true)
  }
  override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
  override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
    guard let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
    sendFiles(urls); return true
  }
  // ---------- a message: right-click ----------
  func menu(for m: TMsg) -> NSMenu {
    let menu = NSMenu()
    let T = MacTalk.shared
    menu.addItem(TalkMenuItem("Reply") { [weak self] in self?.replying = m; self?.window?.makeFirstResponder(self?.box) })
    let r = NSMenuItem(title: "React", action: nil, keyEquivalent: ""); let rm = NSMenu()
    for e in ["👍", "❤️", "😂", "😮", "😢", "🙏"] { rm.addItem(TalkMenuItem(e) { [weak self] in guard let self = self else { return }; T.react(self.group, m, e) }) }
    r.submenu = rm; menu.addItem(r)
    if !m.text.isEmpty { menu.addItem(TalkMenuItem("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.text, forType: .string) }) }
    if let f = m.file {
      menu.addItem(TalkMenuItem("Open") { [weak self] in self?.openFile(f) })
      menu.addItem(TalkMenuItem("Save to Downloads") {
        T.file(f.id) { u in
          guard let u = u, let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { NSSound.beep(); return }
          let to = URL(fileURLWithPath: uniquePath(dl.path, f.name)); try? FileManager.default.copyItem(at: u, to: to)
          NSWorkspace.shared.activateFileViewerSelecting([to])
        }
      })
    }
    if m.by == T.me?.id && !m.deleted && !m.pending && Date().timeIntervalSince1970 * 1000 - m.at < 2 * 86400000 {
      menu.addItem(.separator())
      menu.addItem(TalkMenuItem("Delete for everyone") { [weak self] in guard let self = self else { return }; T.deleteForEveryone(self.group, m) })
    }
    return menu
  }
  private var player: AVAudioPlayer?, playing: String?
  func openFile(_ f: TFile) {
    MacTalk.shared.file(f.id) { u in
      guard let u = u else { NSSound.beep(); return }
      if f.kind == "voice" {
        if self.playing == f.id { self.player?.stop(); self.playing = nil; return }
        self.player = try? AVAudioPlayer(contentsOf: u); self.player?.play(); self.playing = f.id; return
      }
      // (opened with the right app: the file keeps its name in a temporary folder)
      let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("E11 Talk", isDirectory: true).appendingPathComponent(f.id, isDirectory: true)
      try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
      let named = tmp.appendingPathComponent(f.name.isEmpty ? "file" : f.name)
      if !FileManager.default.fileExists(atPath: named.path) { try? FileManager.default.copyItem(at: u, to: named) }
      NSWorkspace.shared.open(named)
    }
  }
}
extension TalkChatView: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in t: NSTableView) -> Int { items.count }
  func tableView(_ t: NSTableView, heightOfRow row: Int) -> CGFloat {
    switch items[row] {
    case .day: return 36
    case .msg(let id): guard let m = msgs[id] else { return 0 }; return TalkBubble.height(m, prev: msgBefore(row), width: t.tableColumns.first?.width ?? 600)
    }
  }
  func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
    switch items[row] {
    case .day(let s):
      let v = TalkDay(); v.text = s; return v
    case .msg(let id):
      let v = (t.makeView(withIdentifier: .init("b"), owner: nil) as? TalkBubble) ?? TalkBubble()
      v.identifier = .init("b"); v.chat = self
      if let m = msgs[id] { v.set(m, prev: msgBefore(row), group: group) }
      return v
    }
  }
  func tableView(_ t: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
final class TalkMenuItem: NSMenuItem {
  private let run: () -> Void
  init(_ title: String, _ run: @escaping () -> Void) { self.run = run; super.init(title: title, action: #selector(go), keyEquivalent: ""); target = self }
  required init(coder: NSCoder) { fatalError() }
  @objc private func go() { run() }
}
final class TalkDay: NSView {
  var text = ""
  override var isFlipped: Bool { true }
  override func draw(_ r: NSRect) {
    let a = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
    let s = a.size(), pill = NSRect(x: (bounds.width - s.width) / 2 - 10, y: (bounds.height - 22) / 2, width: s.width + 20, height: 22)
    TALK_PANE.setFill(); NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
    a.draw(at: NSPoint(x: pill.minX + 10, y: pill.midY - s.height / 2))
  }
}

// one message, drawn: the name (others', when it changes), a reply's quote, a photo / file / voice message, the words,
// the time (✓ / ✓✓ on mine), reactions under it
final class TalkBubble: NSView {
  weak var chat: TalkChatView?
  private var m: TMsg?, prev: TMsg?, group = ""
  private var photoRect = NSRect.zero, fileRect = NSRect.zero
  static var images = NSCache<NSString, NSImage>()
  override var isFlipped: Bool { true }
  func set(_ m: TMsg, prev: TMsg?, group: String) { self.m = m; self.prev = prev; self.group = group; needsDisplay = true }

  struct Shape { var bubble: NSRect; var nameH: CGFloat; var quoteH: CGFloat; var media: NSSize; var fileH: CGFloat; var textRect: NSRect; var footY: CGFloat; var reactH: CGFloat; var total: CGFloat }
  static let textFont = NSFont.systemFont(ofSize: 14)
  static func text(_ m: TMsg, mine: Bool) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.lineSpacing = 1.5
    if m.deleted { return NSAttributedString(string: m.by == MacTalk.shared.me?.id ? "You deleted this message" : "This message was deleted", attributes: [.font: NSFont.systemFont(ofSize: 13.5).italic, .foregroundColor: mine ? NSColor(white: 1, alpha: 0.75) : NSColor.secondaryLabelColor, .paragraphStyle: p]) }
    return NSAttributedString(string: m.text, attributes: [.font: textFont, .foregroundColor: mine ? NSColor.white : NSColor.labelColor, .paragraphStyle: p])
  }
  static func shape(_ m: TMsg, prev: TMsg?, width W: CGFloat) -> Shape {
    let T = MacTalk.shared, mine = m.by == T.me?.id
    let maxW = min(520, max(240, (W - 40) * 0.66))
    let showName = !mine && m.kind != "sys" && (prev?.by != m.by || prev?.kind == "sys")
    let nameH: CGFloat = showName ? 18 : 0
    let quoteH: CGFloat = m.reply != nil && !m.deleted ? 44 : 0
    var media = NSSize.zero
    if !m.deleted, let f = m.file, f.kind == "photo" || f.kind == "video" {
      let w0 = f.w ?? 300, h0 = f.h ?? 220, k = min(300 / max(w0, 1), 300 / max(h0, 1), 1.0)
      media = NSSize(width: max(140, w0 * k), height: max(100, h0 * k))
    }
    let fileH: CGFloat = !m.deleted && (m.file?.kind == "file" || m.file?.kind == "voice") ? 46 : 0
    let t = text(m, mine: mine)
    let hasText = !(m.text.isEmpty && !m.deleted)
    let tb = hasText ? t.boundingRect(with: NSSize(width: maxW - 24, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading]) : .zero
    let foot = NSAttributedString(string: "00:00 ✓✓", attributes: [.font: NSFont.systemFont(ofSize: 10.5)]).size().width + (m.edited ? 40 : 0)
    var bw = max(ceil(tb.width) + 24, media.width + 8, fileH > 0 ? 240 : 0, quoteH > 0 ? 200 : 0, foot + 24, showName ? 120 : 0)
    bw = min(bw, maxW)
    var y: CGFloat = 6 + nameH
    let qy = y; y += quoteH
    if media.width > 0 { y += 4 + media.height }
    if fileH > 0 { y += 4 + fileH }
    let textRect = NSRect(x: 12, y: y + (hasText ? 6 : 0), width: bw - 24, height: ceil(tb.height))
    y = textRect.maxY + 4
    let footY = y; y += 16
    _ = qy
    let reactH: CGFloat = m.reactions.isEmpty || m.deleted ? 0 : 22
    let x = mine ? W - 18 - bw : 18
    let top: CGFloat = prev?.by == m.by && prev?.kind != "sys" ? 2 : 8
    let bubble = NSRect(x: x, y: top, width: bw, height: y)
    return Shape(bubble: bubble, nameH: nameH, quoteH: quoteH, media: media, fileH: fileH, textRect: textRect, footY: footY, reactH: reactH, total: top + y + reactH + 2)
  }
  static func height(_ m: TMsg, prev: TMsg?, width: CGFloat) -> CGFloat {
    if m.kind == "sys" { return 30 }
    return shape(m, prev: prev, width: width).total
  }
  override func draw(_ r: NSRect) {
    guard let m = m else { return }
    let T = MacTalk.shared, mine = m.by == T.me?.id
    if m.kind == "sys" {
      let a = NSAttributedString(string: m.text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
      let s = a.size(); a.draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2)); return
    }
    let sh = TalkBubble.shape(m, prev: prev, width: bounds.width)
    let b = sh.bubble
    (mine ? TALK_BLUE : TALK_THEIRS).setFill()
    NSBezierPath(roundedRect: b, xRadius: 14, yRadius: 14).fill()
    let ink: NSColor = mine ? .white : .labelColor, dim: NSColor = mine ? NSColor(white: 1, alpha: 0.75) : .secondaryLabelColor
    var y = b.minY + 6
    if sh.nameH > 0 {
      let p = T.people[m.by]
      let a = NSMutableAttributedString(string: p?.name ?? "Someone", attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: talkColor(m.by)])
      if let role = p.map({ $0.contact ? ($0.role.isEmpty ? "Client" : $0.role + " · Client") : $0.role }), !role.isEmpty {
        a.append(NSAttributedString(string: " · " + role, attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: talkColor(m.by).withAlphaComponent(0.75)]))
      }
      a.draw(in: NSRect(x: b.minX + 12, y: y, width: b.width - 24, height: 16)); y += sh.nameH
    }
    if sh.quoteH > 0, let rp = m.reply {
      let q = NSRect(x: b.minX + 6, y: y, width: b.width - 12, height: 40)
      (mine ? NSColor(white: 1, alpha: 0.18) : dynColor(NSColor(white: 0, alpha: 0.05), NSColor(white: 1, alpha: 0.07))).setFill()
      NSBezierPath(roundedRect: q, xRadius: 8, yRadius: 8).fill()
      (mine ? NSColor.white : talkColor(rp.by)).setFill(); NSRect(x: q.minX, y: q.minY + 4, width: 3, height: q.height - 8).fill()
      NSAttributedString(string: T.name(rp.by), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: mine ? NSColor.white : talkColor(rp.by)]).draw(in: NSRect(x: q.minX + 10, y: q.minY + 4, width: q.width - 16, height: 16))
      let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
      NSAttributedString(string: rp.text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: dim, .paragraphStyle: para]).draw(in: NSRect(x: q.minX + 10, y: q.minY + 20, width: q.width - 16, height: 16))
      y += sh.quoteH
    }
    photoRect = .zero; fileRect = .zero
    if sh.media.width > 0, let f = m.file {
      let pr = NSRect(x: b.minX + 4, y: y + 4, width: b.width - 8, height: sh.media.height)
      photoRect = pr
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(roundedRect: pr, xRadius: 11, yRadius: 11).addClip()
      if f.kind == "photo", let img = image(f.id) { img.draw(in: pr, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
      else {
        NSColor(white: 0, alpha: 0.25).setFill(); pr.fill()
        let label = f.kind == "video" ? (FileManager.default.fileExists(atPath: T.local(f.id).path) ? "▶︎  Video — click to play" : "🎥  Video — on your phone") : "Loading…"
        let a = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
        let s = a.size(); a.draw(at: NSPoint(x: pr.midX - s.width / 2, y: pr.midY - s.height / 2))
      }
      NSGraphicsContext.restoreGraphicsState()
      y += 4 + sh.media.height
    }
    if sh.fileH > 0, let f = m.file {
      let fr = NSRect(x: b.minX + 6, y: y + 4, width: b.width - 12, height: 42)
      fileRect = fr
      (mine ? NSColor(white: 1, alpha: 0.16) : dynColor(NSColor(white: 0, alpha: 0.05), NSColor(white: 1, alpha: 0.07))).setFill()
      NSBezierPath(roundedRect: fr, xRadius: 9, yRadius: 9).fill()
      let voice = f.kind == "voice"
      let icon = voice ? (chatPlaying(f.id) ? "⏸" : "▶︎") : "📄"
      NSAttributedString(string: icon, attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: ink]).draw(at: NSPoint(x: fr.minX + 10, y: fr.minY + 9))
      let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingMiddle
      let title = voice ? "Voice message" : f.name
      NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: ink, .paragraphStyle: para]).draw(in: NSRect(x: fr.minX + 40, y: fr.minY + 5, width: fr.width - 50, height: 17))
      let detail = voice ? String(format: "%d:%02d", Int(f.secs ?? 0) / 60, Int(f.secs ?? 0) % 60) : ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file)
      NSAttributedString(string: detail, attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: dim]).draw(at: NSPoint(x: fr.minX + 40, y: fr.minY + 23))
    }
    if sh.textRect.height > 0 {
      TalkBubble.text(m, mine: mine).draw(with: NSRect(x: b.minX + sh.textRect.minX, y: b.minY + sh.textRect.minY, width: sh.textRect.width, height: sh.textRect.height + 4), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
    // the time, "Edited", ✓ / ✓✓ (blue once everyone has seen it — mine)
    var foot = (m.edited && !m.deleted ? "Edited " : "") + talkClock(m.at)
    var footColor = dim
    if mine && !m.deleted {
      if m.pending { foot += m.failed ? "  ⚠︎ Not sent" : "  🕓" }
      else {
        let l = T.log(group), g = T.groups[group]
        let others = (g?.members ?? []).filter { $0 != m.by }
        let idx = l.msgs.firstIndex { $0.id == m.id } ?? 0
        let all = !others.isEmpty && others.allSatisfy { p in l.readBy[p].flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 >= idx } ?? false }
        foot += all ? "  ✓✓" : "  ✓"
        if all { footColor = NSColor(srgbRed: 0.75, green: 0.92, blue: 1, alpha: 1) }
      }
    }
    let fa = NSAttributedString(string: foot, attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: footColor])
    let fs = fa.size(); fa.draw(at: NSPoint(x: b.maxX - 10 - fs.width, y: b.minY + sh.footY - 2))
    if sh.reactH > 0 {
      let counts = Dictionary(grouping: m.reactions.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
      let s = counts.map { $0.1 > 1 ? "\($0.0) \($0.1)" : $0.0 }.joined(separator: " ")
      let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13)])
      let asz = a.size(), pill = NSRect(x: mine ? b.maxX - asz.width - 20 : b.minX + 8, y: b.maxY - 4, width: asz.width + 14, height: 22)
      TALK_PANE.setFill(); NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
      TALK_LINE.setStroke(); NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).stroke()
      a.draw(at: NSPoint(x: pill.minX + 7, y: pill.midY - asz.height / 2))
    }
  }
  private func chatPlaying(_ id: String) -> Bool { false }
  private func image(_ id: String) -> NSImage? {
    if let i = TalkBubble.images.object(forKey: id as NSString) { return i }
    let u = MacTalk.shared.local(id)
    if let i = NSImage(contentsOf: u) { TalkBubble.images.setObject(i, forKey: id as NSString); return i }
    MacTalk.shared.file(id) { [weak self] got in if got != nil { self?.needsDisplay = true } }
    return nil
  }
  override func mouseDown(with e: NSEvent) {
    guard let m = m else { return }
    let p = convert(e.locationInWindow, from: nil)
    if e.modifierFlags.contains(.control) { rightMouseDown(with: e); return }
    if let f = m.file, photoRect.contains(p) || fileRect.contains(p) { chat?.openFile(f); needsDisplay = true }
  }
  override func rightMouseDown(with e: NSEvent) {
    guard let m = m, m.kind != "sys", let c = chat else { return }
    NSMenu.popUpContextMenu(c.menu(for: m), with: e, for: self)
  }
}
func talkClock(_ ms: Double) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date(timeIntervalSince1970: ms / 1000)) }
extension NSFont {
  var italic: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask) }
}
