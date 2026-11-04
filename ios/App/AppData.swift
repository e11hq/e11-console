import Foundation
import JavaScriptCore
import UIKit

/* The app's own copy of the data (iOS app data plan, step 1 — Haris, 2026-11-01: "lightning fast, light on the server,
   then no website behind the app"). Got exactly as the website gets it: one download of everything this person may see
   (/api/snapshot), then the live stream of changes (/api/events?since=rev). Kept on the phone (saved to disk, shown
   at once the next time) inside iPhone's own JavaScript engine, with the website's own files: web/rules.js (the rules)
   and web/appview.js (the app's screens — the same file the server's routes use, so the two can't disagree). The
   screens are then worked out here, with no request; changes still go to the server, which checks each one.
   Server switch: kv `app-copy` = off (GET /api/appcopy) → the app asks the server for each screen again, as before. */
final class AppData: NSObject, URLSessionDataDelegate {
  static let shared = AppData()

  private let q = DispatchQueue(label: "e11.appdata")      // (the engine is used on this one queue only)
  private var ctx: JSContext?
  private var cookies: (@escaping (String) -> Void) -> Void = { $0("") }
  private(set) var me: String?
  private var started = false, loading = false
  private var copyReady = false                             // (read on the main thread: set there)
  var ready: Bool { copyReady }
  // the app draws its own tab bar from the copy (Part B step 1) — on unless the server says off
  var tabsOn: Bool { (UserDefaults.standard.object(forKey: "app-tabs") as? Bool) ?? true }
  private var listeners: [UUID: () -> Void] = [:]

  private var dir: URL {
    let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("e11-copy", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }

  // ---------- starting: the saved copy at once, then up to date from the server ----------
  func start(me: String, cookies: @escaping (@escaping (String) -> Void) -> Void) {
    self.cookies = cookies
    if started && self.me == me { return }
    let switching = self.me != nil && self.me != me
    self.me = me; started = true
    if switching { if Thread.isMainThread { copyReady = false } else { DispatchQueue.main.async { self.copyReady = false } }; stopStream() }
    // (the saved copy at once — step 3: the app opens on it, before any answer from the server; switched off on the
    //  server, it's put away again)
    q.async { self.boot(me: me) }
    request("/api/appcopy") { [weak self] j in
      guard let self = self else { return }
      if (j?["on"] as? Bool) == false { self.started = false; self.stopStream(); DispatchQueue.main.async { self.copyReady = false } }
      // (the app's own tab bar — Part B step 1; off on the server: the page's again)
      let t = (j?["tabs"] as? Bool) != false
      DispatchQueue.main.async { if UserDefaults.standard.object(forKey: "app-tabs") as? Bool != t { UserDefaults.standard.set(t, forKey: "app-tabs") }; self.changed() }
    }
    if !watching {
      watching = true
      NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.wake() }
      NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep() }
    }
  }
  private var watching = false
  private func boot(me: String) {
    // the engine with the website's files: the saved ones at once, then the server's (a new version comes in by itself)
    let saved = ["rules.js", "appview.js"].map { (try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8)) ?? "" }
    if saved.allSatisfy({ !$0.isEmpty }) { makeEngine(saved[0], saved[1]) }
    // the saved copy (if it's this person's)
    // Kept between launches (Haris, 2026-11-02: "only update what changed, without re-downloading all"): with a saved
    // copy, the app asks only for what changed since it (the stream's "since"); the server sends a fresh download only
    // when it must — what this person may see changed, or the copy is from before a restore. A week-old copy: a fresh one.
    var fromSaved = false
    let file = dir.appendingPathComponent("copy-\(me).json")
    if ctx != nil, let raw = try? String(contentsOf: file, encoding: .utf8), !raw.isEmpty {
      if call("E11AppView.load", [raw]) != nil {
        markReady(); changed()   // (the screens waiting on it — a quick start — drawn from it now)
        let age = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        fromSaved = age < 7 * 24 * 3600 && accessMark != nil
      }
    }
    fetchScripts { [weak self] in
      guard let self = self else { return }
      if self.ctx == nil { return }
      if fromSaved && ((self.call("E11AppView.rev", []) as? NSNumber)?.intValue ?? 0) > 0 { self.openStream() } else { self.download() }
    }
  }
  private func makeEngine(_ rules: String, _ view: String) {
    let keep = ctx.flatMap { _ in call("E11AppView.save", []) as? String } ?? ""
    let c = JSContext()!
    c.exceptionHandler = { _, e in NSLog("app copy: %@", e?.toString() ?? "") }
    c.evaluateScript(rules); c.evaluateScript(view)
    guard c.objectForKeyedSubscript("E11AppView")?.isUndefined == false, c.objectForKeyedSubscript("E11Rules")?.isUndefined == false else { return }
    ctx = c
    if !keep.isEmpty { _ = call("E11AppView.load", [keep]) }
  }
  // the website's two files, from the server (kept for next time)
  private func fetchScripts(_ then: @escaping () -> Void) {
    var got: [String: String] = [:]
    let group = DispatchGroup()
    for f in ["rules.js", "appview.js"] {
      group.enter()
      raw("/\(f)?v=\(Int(Date().timeIntervalSince1970 / 3600))") { s in if let s = s, s.contains("E11") { got[f] = s }; group.leave() }
    }
    group.notify(queue: q) { [weak self] in
      guard let self = self else { return }
      if let r = got["rules.js"], let v = got["appview.js"] {
        let old = ["rules.js", "appview.js"].map { (try? String(contentsOf: self.dir.appendingPathComponent($0), encoding: .utf8)) ?? "" }
        if old != [r, v] || self.ctx == nil {
          try? r.write(to: self.dir.appendingPathComponent("rules.js"), atomically: true, encoding: .utf8)
          try? v.write(to: self.dir.appendingPathComponent("appview.js"), atomically: true, encoding: .utf8)
          self.makeEngine(r, v)
        }
      }
      then()
    }
  }
  // everything this person may see, once (and again when the server says to)
  private func download() {
    guard let me = me, !loading else { return }
    loading = true
    raw("/api/snapshot") { [weak self] s in
      guard let self = self else { return }
      self.q.async {
        self.loading = false
        guard let s = s, s.hasPrefix("{"), self.ctx != nil else { self.retryLater(); return }
        // (who it's for goes in with it: a copy is only ever used for that person)
        guard self.callFn("(function(raw, me){ var s = JSON.parse(raw); if (!s.ok || !s.data) return null; s.me = me; return E11AppView.load(s); })", [s, me]) != nil else { self.retryLater(); return }
        if let m = self.newMark { self.accessMark = m; self.newMark = nil }
        self.markReady(); self.saveNow(); self.changed()
        self.openStream()
      }
    }
  }
  private func retryLater() { q.asyncAfter(deadline: .now() + 20) { [weak self] in if self?.started == true { self?.download() } } }
  private func markReady() { DispatchQueue.main.async { let was = self.copyReady; self.copyReady = true; if !was { self.changed() } } }

  // ---------- the live stream: the changes as they happen (the website's own) ----------
  private var stream: URLSessionDataTask?
  private var session: URLSession?
  private var buffer = ""
  private var backoff: Double = 2
  private func openStream() {
    guard stream == nil, let me = me, started else { return }
    let rev = (call("E11AppView.rev", []) as? NSNumber)?.intValue ?? 0
    onMain { self.cookies { [weak self] cookie in
      guard let self = self else { return }
      let mark = self.accessMark.map { "&access=" + $0 } ?? ""
      guard let url = URL(string: serverURL() + "/api/events?since=\(rev)&client=ios-\(me)" + mark) else { return }
      self.q.async {
        guard self.stream == nil else { return }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 90; cfg.timeoutIntervalForResource = 24 * 3600
        let ses = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = ses; self.buffer = ""
        let t = ses.dataTask(with: r); self.stream = t; t.resume()
      }
    } }
  }
  private func stopStream() { q.async { self.stream?.cancel(); self.stream = nil; self.session?.invalidateAndCancel(); self.session = nil } }
  func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    q.async {
      guard dataTask === self.stream else { return }
      self.backoff = 2
      self.buffer += String(decoding: data, as: UTF8.self)
      while let r = self.buffer.range(of: "\n\n") {
        let block = String(self.buffer[..<r.lowerBound]); self.buffer.removeSubrange(..<r.upperBound)
        var ev = "message", body = ""
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
          if line.hasPrefix("event:") { ev = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
          else if line.hasPrefix("data:") { body += line.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        }
        self.handle(ev, body)
      }
    }
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    q.async {
      guard task === self.stream else { return }
      self.stream = nil
      // (gone: back again in a moment — longer each time, up to half a minute)
      let wait = self.backoff; self.backoff = min(30, self.backoff * 2)
      self.q.asyncAfter(deadline: .now() + wait) { [weak self] in if self?.inBackground == false { self?.openStream() } }
    }
  }
  private func handle(_ ev: String, _ body: String) {
    switch ev {
    case "changes":
      if callFn("(function(raw){ var d = JSON.parse(raw); return E11AppView.apply(d.changes, d.rev); })", [body]) != nil { saveSoon(); changed() }
    case "resync":
      download()
    case "hello":
      guard let d = body.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { break }
      // (a new mark is kept only once the copy that goes with it is in: the server sends a fresh download for it)
      if let a = j["access"] as? String { if accessMark == nil || accessMark == a { accessMark = a } else { newMark = a } }
      // (the server's history is behind this copy — a restore: start again from a fresh download)
      if let srv = j["rev"] as? Int, let mine = (call("E11AppView.rev", []) as? NSNumber)?.intValue, srv < mine { download() }
    default: break
    }
  }
  private var inBackground = false
  private var newMark: String?
  // what this person may see, as the server marks it (kept with the copy; sent back when the stream opens)
  private var accessMark: String? {
    get { me.flatMap { UserDefaults.standard.string(forKey: "app-copy-access-\($0)") } }
    set { if let me = me { UserDefaults.standard.set(newValue, forKey: "app-copy-access-\(me)") } }
  }
  private func wake() { q.async { self.inBackground = false; if self.started && self.stream == nil { self.backoff = 2; self.openStream() } } }
  private func sleep() { q.async { self.inBackground = true }; saveNow(); stopStream() }

  // ---------- keeping it ----------
  private var saveItem: DispatchWorkItem?
  private func saveSoon() {
    saveItem?.cancel()
    let w = DispatchWorkItem { [weak self] in self?.saveNow() }
    saveItem = w; q.asyncAfter(deadline: .now() + 4, execute: w)
  }
  private func saveNow() {
    q.async {
      guard let me = self.me, let s = self.call("E11AppView.save", []) as? String, !s.isEmpty else { return }
      try? s.write(to: self.dir.appendingPathComponent("copy-\(me).json"), atomically: true, encoding: .utf8)
    }
  }

  // ---------- the screens, from the copy (main thread) ----------
  // → (ready, the model): not ready — ask the server as before; ready with nil — not there / not for this person
  func screen(_ kind: String, _ a: String? = nil, _ b: String? = nil) -> (ready: Bool, model: [String: Any]?) {
    guard copyReady else { return (false, nil) }
    let out: String? = q.sync { call("E11AppView.screen", [kind, a ?? NSNull(), b ?? NSNull()]) as? String }
    guard let s = out, !s.isEmpty, let d = s.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return (false, nil) }
    if j["error"] != nil { return (false, nil) }   // (something it couldn't work out: the server's instead)
    return (true, j["model"] as? [String: Any])
  }
  // how far the copy has caught up with the server (its last change)
  var rev: Int { guard copyReady else { return 0 }; return q.sync { (call("E11AppView.rev", []) as? NSNumber)?.intValue ?? 0 } }
  // something changed (the stream, a download): whoever's showing a screen from the copy redraws
  @discardableResult func listen(_ f: @escaping () -> Void) -> UUID { let id = UUID(); listeners[id] = f; return id }
  func stopListening(_ id: UUID) { listeners[id] = nil }
  private var changePending = false
  // a copy saved on this phone for this person (step 3: then the app can open on its own screens at once)
  func hasSaved(_ me: String) -> Bool {
    FileManager.default.fileExists(atPath: dir.appendingPathComponent("copy-\(me).json").path) && FileManager.default.fileExists(atPath: dir.appendingPathComponent("appview.js").path)
  }
  // what the server said an action of ours changed: into the copy at once, every screen redrawn (step 3). Its place
  // in the history (rev) isn't moved on — the stream still brings everything in order.
  func applyLocal(_ changes: [[String: Any]]) {
    guard copyReady, !changes.isEmpty, let d = try? JSONSerialization.data(withJSONObject: changes) else { return }
    let raw = String(decoding: d, as: UTF8.self)
    gen += 1   // (at once: a screen asked for right after is worked out again, with these in)
    q.async {
      if self.callFn("(function(raw){ return E11AppView.apply(JSON.parse(raw), 0); })", [raw]) != nil { self.saveSoon(); self.changed() }
    }
  }
  // (one more each time the copy changes — a screen worked out from an unchanged copy isn't worked out again: that
  //  took the main thread a moment and stalled the top buttons' animation coming back from a task, Haris's film 19:36)
  private(set) var gen = 0
  private func changed() {
    DispatchQueue.main.async {
      self.gen += 1
      if self.changePending { return }
      self.changePending = true
      // (a burst of changes: one redraw)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.changePending = false; self.listeners.values.forEach { $0() } }
    }
  }

  // ---------- the engine ----------
  private func call(_ path: String, _ args: [Any]) -> Any? {
    guard let c = ctx else { return nil }
    let parts = path.split(separator: ".").map(String.init)
    guard parts.count == 2, let obj = c.objectForKeyedSubscript(parts[0]), let fn = obj.objectForKeyedSubscript(parts[1]), !fn.isUndefined else { return nil }
    let r = fn.call(withArguments: args)
    if c.exception != nil { c.exception = nil; return nil }
    guard let v = r, !v.isUndefined, !v.isNull else { return nil }
    return v.toObject()
  }
  private func callFn(_ src: String, _ args: [Any]) -> Any? {
    guard let c = ctx, let fn = c.evaluateScript(src), !fn.isUndefined else { return nil }
    let r = fn.call(withArguments: args)
    if c.exception != nil { c.exception = nil; return nil }
    guard let v = r, !v.isUndefined, !v.isNull else { return nil }
    return v.toObject()
  }

  // ---------- the server ----------
  private func raw(_ path: String, _ done: @escaping (String?) -> Void) {
    onMain { self.cookies { cookie in
      guard let url = URL(string: serverURL() + path) else { return done(nil) }
      var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
      if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
      URLSession.shared.dataTask(with: r) { d, resp, _ in
        let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200
        done(ok ? d.map { String(decoding: $0, as: UTF8.self) } : nil)
      }.resume()
    } }
  }
  private func onMain(_ f: @escaping () -> Void) { if Thread.isMainThread { f() } else { DispatchQueue.main.async(execute: f) } }
  private func request(_ path: String, _ done: @escaping ([String: Any]?) -> Void) {
    raw(path) { s in
      let j = s.flatMap { $0.data(using: .utf8) }.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
      DispatchQueue.main.async { done(j) }
    }
  }
}
