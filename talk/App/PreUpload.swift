import Foundation
import AVFoundation

/* A photo starts going up while it's still on the send screen (Haris 2026-11-22 13:22, WhatsApp's way): made ready exactly
   as it would be on Send (ChatVC.ready), locked and put in R2 — everything but "it's all there", which waits for Send and
   then carries the message (one call). Send before it's up: the bubble shows its ring and carries on from where it got to.
   A change on the screen (HD on / off, the photo edited, taken out) or the screen closed: that one is stopped and let go
   (what had gone up is never used — the server lets unused uploads go). Anything that didn't work: Send goes the usual way.
   Videos too (Haris 2026-11-22 13:35): made smaller on the screen (HEVC, as Send would), then sent up the same way; Send
   before it's made: the bubble waits for this copy (its "Preparing" ring) — if it can't be made here, Send makes it as
   always (Apple's preset, or as it is). Main thread only. */
final class PreUpload {
  private static var jobs: [String: PreUpload] = [:]   // by the send screen's item key

  let key: String, url: URL, hd: Bool, kind: String
  let tmpId = "local-" + UUID().uuidString
  private(set) var ready: ChatVC.Ready?
  private(set) var cancelled = false
  private var attached = false, failedEarly = false
  private var gate: (() -> Void)?                         // up, waiting for Send to say "it's all there"
  private var ended: (fid: String?, key: String?)?        // finished (or failed) before Send
  private var lastProgress: Double = 0
  private var onProgress: ((Double) -> Void)?
  private var message: ((String, String) -> [String: Any])?
  private var done: ((String?, String?) -> Void)?
  private var serverId: String?                           // its id on the server, once it has one
  private var made: URL??                                 // a video's copy: made (URL), couldn't be (nil), not yet (unset)
  private var madeWaiters: [(URL?) -> Void] = []

  private init(key: String, url: URL, hd: Bool, kind: String) { self.key = key; self.url = url; self.hd = hd; self.kind = kind }

  // the send screen's photos as they are now: each one going up (once), anything no longer there stopped
  static func sync(_ items: [SendPreviewVC.Item]) {
    var want = Set<String>()
    for it in items where (it.kind == "photo" || it.kind == "video") && it.coming == nil {
      want.insert(it.key)
      if let j = jobs[it.key], j.url == it.url, j.hd == it.hd { continue }
      jobs[it.key]?.cancel()
      let j = PreUpload(key: it.key, url: it.url, hd: it.hd, kind: it.kind); jobs[it.key] = j
      if it.kind == "video" { j.startVideo(name: it.name) } else { j.start(name: it.name) }
    }
    for (k, j) in jobs where !want.contains(k) { j.cancel(); jobs[k] = nil }
  }
  // the screen closed without sending: all let go
  static func dropAll() { jobs.values.forEach { $0.cancel() }; jobs = [:] }
  // Send: the one for this photo, if it's the same photo at the same quality and still good
  static func take(key: String, url: URL, hd: Bool) -> PreUpload? {
    guard let j = jobs.removeValue(forKey: key) else { return nil }
    // (a photo: only once it's made ready — else Send makes it; a video: also while it's still being made — Send waits for it)
    guard j.url == url, j.hd == hd, !j.cancelled, !j.failedEarly, j.kind == "video" || j.ready != nil else { j.cancel(); return nil }
    return j
  }
  // a video's copy, once made here (nil: it couldn't be — Send makes it the usual way)
  func whenMade(_ f: @escaping (URL?) -> Void) {
    if let m = made { f(m) } else { madeWaiters.append(f) }
  }
  fileprivate func startVideo(name: String) {
    let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    let asset = AVURLAsset(url: url)
    // (a ProRes RAW, or anything that can't be made smaller this way: left to Send, as always)
    guard !VideoShrink.isRaw(asset) else { failedEarly = true; settle(nil); return }
    VideoShrink.run(asset, hd: hd, to: out, stop: tmpId, progress: { [tmpId] p in Uploads.prep(tmpId, p) }) { [weak self] ok in
      DispatchQueue.main.async {
        guard let self = self, !self.cancelled else { try? FileManager.default.removeItem(at: out); return }
        guard ok, !Attach.tooBig(out), let d = try? Data(contentsOf: out, options: .alwaysMapped) else {
          try? FileManager.default.removeItem(at: out); self.failedEarly = true; self.settle(nil); return
        }
        self.ready = ChatVC.Ready(id: self.tmpId, data: d, w: nil, h: nil, kind: "video", name: (name as NSString).deletingPathExtension + ".mp4", local: out)
        self.settle(out)
        self.upload(d, name: (name as NSString).deletingPathExtension + ".mp4")
      }
    }
  }
  private func settle(_ u: URL?) { made = .some(u); let w = madeWaiters; madeWaiters = []; w.forEach { $0(u) } }

  private func start(name: String) {
    ChatVC.readyQ.async { [weak self] in
      guard let self = self else { return }
      let r = ChatVC.ready(self.url, kind: "photo", name: name, hd: self.hd, id: self.tmpId)
      DispatchQueue.main.async {
        guard !self.cancelled else { return }
        guard let r = r, r.kind == "photo" else { self.failedEarly = true; return }
        self.ready = r
        self.upload(r.data, name: r.name)
      }
    }
  }
  private func upload(_ data: Data, name: String) {
        Net.shared.uploadMsg(data, name: name, stop: self.tmpId, message: { [weak self] fid, key in self?.message?(fid, key) ?? [:] },
                             gate: { [weak self] open in DispatchQueue.main.async { guard let self = self, !self.cancelled else { return }; if self.attached { open() } else { self.gate = open } } },
                             onId: { [weak self] id in DispatchQueue.main.async { guard let self = self else { return }; self.serverId = id; if self.cancelled { Net.shared.dropUpload(id) } } },
                             progress: { [weak self] p in DispatchQueue.main.async { self?.lastProgress = p; self?.onProgress?(p) } }) { [weak self] fid, key in
          DispatchQueue.main.async {
            guard let self = self, !self.cancelled else { return }
            if self.attached { self.done?(fid, key) } else { self.ended = (fid, key); if fid == nil { self.failedEarly = true } }
          }
        }
  }
  // Send: from here the upload belongs to the message — its ring, its message, its end. False: the usual way instead.
  func attach(progress: @escaping (Double) -> Void, message: @escaping (String, String) -> [String: Any], done: @escaping (String?, String?) -> Void) -> Bool {
    guard !cancelled, !failedEarly, ready != nil, ended == nil || ended?.fid != nil else { cancel(); return false }
    attached = true
    self.onProgress = progress; self.message = message; self.done = done
    progress(lastProgress)
    if let e = ended { done(e.fid, e.key); return true }
    if let g = gate { gate = nil; g() }
    return true
  }
  private func cancel() {
    guard !cancelled else { return }
    cancelled = true; gate = nil
    Uploads.stop(tmpId)
    Net.shared.dropUpload(serverId)   // (what had gone up: let go now, not kept for a day)
    if let r = ready { try? FileManager.default.removeItem(at: r.local) }
    if made == nil { settle(nil) }   // (anyone waiting on a video's copy: made the usual way)
  }
}
