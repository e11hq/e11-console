import UIKit

/* Home straight from the server (25+): the app asks the server for its Home (/api/home — worked out there with the
   website's own rules, web/rules.js) and sends Done / reopen / Due / Delete / Undo there itself (/api/home/act), signed
   in as the app is (its Cloudflare cookie). Changes show at once; they're kept on the phone until the server has them,
   so closing the app with no signal loses nothing — they go when the connection is back. The page behind still says
   when Home is on screen, and still does everything else on it (opening a task, search, + New task, Copy link,
   attaching files). The server can switch this off (the app then uses the page's Home as before). */
final class ServerHome {
  // (each waiting action belongs to one server and one person: another sign-in or server never sends it)
  struct Op: Codable { var op: String; var act: String; var id: String; var due: String?; var clientApproval: String?; var trashId: String?; var server: String?; var me: String? }
  private static let QUEUE = "e11HomeQueue"

  var cookies: (@escaping (String) -> Void) -> Void = { $0("") }
  var onModel: (([String: Any]) -> Void)?         // a new Home to draw (the server's, with what's still waiting on top)
  var onToast: ((String, String?, (() -> Void)?) -> Void)?   // a short message (and its button)
  var onAsk: ((String, @escaping (String?) -> Void) -> Void)?   // "Did the client approve?" → 'yes' | 'none' | nil
  var onOff: (() -> Void)?                        // switched off (or no Home for this person): the page's Home again
  private(set) var off = false                    // the server switched it off
  private(set) var model: [String: Any]?          // the server's last Home (as it sent it)
  private var server = serverURL()                // (the server that Home is from)
  private var confirmedMe: String?                // who the server says is signed in (this session)
  private var lastRev = 0                         // (an older answer never replaces a newer one)
  private var queue: [Op] = []
  private var sending = false, fetching = false, fetchAgain = false
  private var retry: Timer?

  init() {
    if let d = defaults.data(forKey: ServerHome.QUEUE), let q = try? JSONDecoder().decode([Op].self, from: d) { queue = q }
    if let m = ServerHome.loadCache() { model = m }
  }
  var on: Bool { !off && model != nil && server == serverURL() }
  var me: String? { model?["me"] as? String }
  // another server chosen (Settings, the App Review copy): that one's own Home and nothing of the other's
  private func checkServer() {
    guard server != serverURL() else { return }
    server = serverURL(); model = ServerHome.loadCache(); confirmedMe = nil; lastRev = 0; off = false
  }
  var shown: [String: Any]? { model.map { overlay($0) } }

  // ---------- the last Home, kept on the phone ----------
  private static var cacheFile: URL? { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("home-" + serverURL().replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression) + ".json") }
  private static func loadCache() -> [String: Any]? {
    guard let f = cacheFile, let d = try? Data(contentsOf: f), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
    return m
  }
  private func saveCache(_ m: [String: Any]) {
    guard let f = ServerHome.cacheFile, let d = try? JSONSerialization.data(withJSONObject: m) else { return }
    try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? d.write(to: f, options: .atomic)
  }

  // ---------- asking the server ----------
  private func request(_ path: String, body: [String: Any]?, _ done: @escaping ([String: Any]?) -> Void) {
    cookies { cookie in
      guard let url = URL(string: serverURL() + path) else { return done(nil) }
      var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
      r.setValue("application/json", forHTTPHeaderField: "Accept")
      if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
      if let b = body { r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: b) }
      URLSession.shared.dataTask(with: r) { d, resp, _ in
        let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200
        let j = ok ? d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
        // (no answer at all = no connection: tried again later; any other answer that isn't ours — an error page, a
        //  sign-in page — isn't tried again)
        DispatchQueue.main.async { self.lastNoAnswer = resp == nil; done(j) }
      }.resume()
    }
  }
  private var lastNoAnswer = false
  // a fresh Home (when the app opens or comes back, and whenever the page hears of a change)
  func refresh() {
    checkServer()
    if fetching { fetchAgain = true; return }
    fetching = true
    request("/api/home", body: nil) { [weak self] j in
      guard let self = self else { return }
      self.fetching = false
      if let j = j, (j["ok"] as? Bool) == true {
        if (j["off"] as? Bool) == true || j["home"] is NSNull || j["home"] == nil {
          // (switched off, or no Home for this person: the page's own again — and nothing kept of it)
          let was = self.on
          self.off = true; self.model = nil; self.confirmedMe = nil
          if let f = ServerHome.cacheFile { try? FileManager.default.removeItem(at: f) }
          if was { self.onOff?() }
        } else if let h = j["home"] as? [String: Any] {
          self.off = false
          self.confirmedMe = h["me"] as? String
          self.take(h, rev: j["rev"] as? Int ?? 0)
        }
      }
      if self.fetchAgain { self.fetchAgain = false; self.refresh() }
      else if !self.queue.isEmpty { self.send() }
    }
  }
  private func take(_ h: [String: Any], rev: Int) {
    if rev < lastRev { return }   // (an answer that left before a newer one)
    lastRev = rev
    model = h; saveCache(h)
    onModel?(overlay(h))
  }

  // ---------- doing things ----------
  func act(_ act: String, _ id: String, due: String? = nil, clientApproval: String? = nil, trashId: String? = nil) {
    queue.append(Op(op: UUID().uuidString, act: act, id: id, due: due, clientApproval: clientApproval, trashId: trashId, server: serverURL(), me: me))
    keep()
    if let m = model { onModel?(overlay(m)) }   // (shown at once)
    send()
  }
  private func keep() { if let d = try? JSONEncoder().encode(queue) { defaults.set(d, forKey: ServerHome.QUEUE) } }
  // one at a time, in order; no answer (no signal) → kept, tried again in a while
  func send() {
    checkServer()
    // (only once the server has said who's signed in; another person's or server's waiting actions are dropped)
    guard let who = confirmedMe else { if !queue.isEmpty { refresh() }; return }
    let before = queue.count
    queue.removeAll { ($0.server != nil && $0.server != serverURL()) || ($0.me != nil && $0.me != who) }
    if queue.count != before { keep() }
    guard !sending, let o = queue.first else { return }
    sending = true
    var b: [String: Any] = ["op": o.op, "act": o.act, "id": o.id]
    if let v = o.due { b["due"] = v } else if o.act == "due" { b["due"] = NSNull() }
    if let v = o.clientApproval { b["clientApproval"] = v }
    if let v = o.trashId { b["trashId"] = v }
    request("/api/home/act", body: b) { [weak self] j in
      guard let self = self else { return }
      self.sending = false
      guard let j = j else {
        if self.lastNoAnswer {
          self.retry?.invalidate()
          self.retry = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.send() }
        } else {
          // (an answer that isn't ours: not tried again — Home as the server has it)
          if !self.queue.isEmpty { self.queue.removeFirst(); self.keep() }
          self.onToast?("Couldn’t save that — try again", nil, nil)
          self.refresh(); self.send()
        }
        return
      }
      if !self.queue.isEmpty { self.queue.removeFirst(); self.keep() }
      let ok = (j["ok"] as? Bool) == true
      if !ok, (j["need"] as? String) == "clientApproval" {
        // completing a task the CD approved: the client's approval first (kept with the final files)
        self.onAsk?(o.id) { [weak self] ans in
          guard let self = self else { return }
          if let a = ans { self.act("done", o.id, clientApproval: a) } else if let m = self.model { self.onModel?(self.overlay(m)) }
        }
      } else if !ok {
        self.onToast?(j["error"] as? String ?? "That didn’t work", nil, nil)
      } else if let msgs = j["messages"] as? [String], let first = msgs.first {
        // Undo: a completed task reopened, a deleted one back from the Trash
        if o.act == "done" { self.onToast?(first, "Undo") { [weak self] in self?.act("reopen", o.id) } }
        else if o.act == "delete", let tr = j["undo"] as? String { self.onToast?(first, "Undo") { [weak self] in self?.act("undoDelete", o.id, trashId: tr) } }
        else { self.onToast?(first, nil, nil) }
        msgs.dropFirst().forEach { self.onToast?($0, nil, nil) }
      }
      if let h = j["home"] as? [String: Any] { self.take(h, rev: j["rev"] as? Int ?? 0) } else if let m = self.model { self.onModel?(self.overlay(m)) }
      self.send()
    }
  }
  func waiting(_ id: String) -> Bool { queue.contains { $0.id == id } }

  // ---------- what's still waiting, shown on top of the server's Home ----------
  private func overlay(_ h: [String: Any]) -> [String: Any] {
    guard !queue.isEmpty else { return h }
    var m = h
    var groups = (h["groups"] as? [[String: Any]]) ?? []
    var stats = (h["stats"] as? [Int]) ?? [0, 0, 0]
    func find(_ id: String) -> (Int, Int)? {
      for (gi, g) in groups.enumerated() { if let ci = (g["cards"] as? [[String: Any]] ?? []).firstIndex(where: { ($0["id"] as? String) == id }) { return (gi, ci) } }
      return nil
    }
    // (a card taken off: the boxes' numbers follow — a client's run under Today counts in Due today)
    func remove(_ gi: Int, _ ci: Int) -> [String: Any] {
      var cards = groups[gi]["cards"] as? [[String: Any]] ?? []
      let c = cards.remove(at: ci)
      groups[gi]["cards"] = cards; groups[gi]["n"] = cards.count
      if (groups[gi]["today"] as? Bool) == true, stats.count > 0 { stats[0] = max(0, stats[0] - 1) }
      if (groups[gi]["name"] as? String) == "Overdue", stats.count > 1 { stats[1] = max(0, stats[1] - 1) }
      if cards.isEmpty, (groups[gi]["anchor"] as? Bool) != true { groups.remove(at: gi) }
      return c
    }
    for o in queue {
      switch o.act {
      case "done":
        // (a completed task leaves Home)
        if let (gi, ci) = find(o.id) { _ = remove(gi, ci) }
      case "reopen":
        guard let (gi, ci) = find(o.id) else { continue }
        var cards = groups[gi]["cards"] as? [[String: Any]] ?? []
        cards[ci]["done"] = false; groups[gi]["cards"] = cards
      case "delete":
        if let (gi, ci) = find(o.id) { _ = remove(gi, ci) }
      case "due":
        guard let (gi, ci) = find(o.id) else { continue }
        var cards = groups[gi]["cards"] as? [[String: Any]] ?? []
        var c = cards[ci]
        c["due"] = o.due ?? ""
        var meta = (c["meta"] as? [[String: Any]] ?? []).filter { $0["b"] == nil }
        if let d = o.due, (c["inline"] as? Bool) != true {
          let i = meta.firstIndex(where: { ($0["cm"] as? Bool) == true }) ?? meta.count
          meta.insert(["t": ServerHome.label(d), "b": "plain"], at: i)
        }
        c["meta"] = meta; cards[ci] = c; groups[gi]["cards"] = cards
      default: break
      }
    }
    m["groups"] = groups; m["stats"] = stats
    return m
  }
  // a due date as the cards say it (Today, Tomorrow, Friday, Nov 23) — until the server's own comes back
  static func label(_ d: String) -> String {
    let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    guard let day = f.date(from: d) else { return d }
    let n = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: day).day ?? 0
    if n == 0 { return "Today" }
    if n == 1 { return "Tomorrow" }
    if n == -1 { return "Yesterday" }
    f.dateFormat = n > 1 && n < 7 ? "EEEE" : (Calendar.current.component(.year, from: day) == Calendar.current.component(.year, from: Date()) ? "MMM d" : "MMM d, yyyy")
    return f.string(from: day)
  }

  // ---------- photos (the server sends where they are; fetched once, signed in) ----------
  private var pics: [String: String] = [:], asking = Set<String>()
  func photos(_ people: [String: [String: Any]], _ done: @escaping ([String: [String: Any]]) -> Void) {
    var out = people
    for (id, p) in people {
      guard let u = p["photo"] as? String, u.hasPrefix("/") else { continue }
      if let d = pics[u] { out[id]?["photo"] = d; continue }
      out[id]?["photo"] = nil
      guard !asking.contains(u) else { continue }
      asking.insert(u)
      cookies { cookie in
        guard let url = URL(string: serverURL() + u) else { return }
        var r = URLRequest(url: url); if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
        URLSession.shared.dataTask(with: r) { [weak self] d, _, _ in
          guard let d = d, let img = UIImage(data: d) else { DispatchQueue.main.async { self?.asking.remove(u) }; return }   // (tried again next time)
          let side: CGFloat = 72, k = min(img.size.width, img.size.height)
          let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            img.draw(in: CGRect(x: -(img.size.width - k) / 2 * side / k, y: -(img.size.height - k) / 2 * side / k, width: img.size.width * side / k, height: img.size.height * side / k))
          }
          guard let jpg = small.jpegData(compressionQuality: 0.85) else { return }
          DispatchQueue.main.async {
            guard let self = self else { return }
            self.pics[u] = "data:image/jpeg;base64," + jpg.base64EncodedString()
            var again = people; for (i, q) in people where (q["photo"] as? String) == u { again[i]?["photo"] = self.pics[u] }
            done(again.mapValues { q in var q = q; if let s = q["photo"] as? String, s.hasPrefix("/") { q["photo"] = self.pics[s] }; return q })
          }
        }.resume()
      }
    }
    done(out)
  }
}
