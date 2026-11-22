import Foundation

/* A photo starts going up while it's still on the send screen (Haris 2026-11-22 13:22, WhatsApp's way): made ready exactly
   as it would be on Send (ChatVC.ready), locked and put in R2 — everything but "it's all there", which waits for Send and
   then carries the message (one call). Send before it's up: the bubble shows its ring and carries on from where it got to.
   A change on the screen (HD on / off, the photo edited, taken out) or the screen closed: that one is stopped and let go
   (what had gone up is never used — the server lets unused uploads go). Anything that didn't work: Send goes the usual way.
   Photos only for now; videos keep their own way (made smaller behind their bubble). Main thread only. */
final class PreUpload {
  private static var jobs: [String: PreUpload] = [:]   // by the send screen's item key

  let key: String, url: URL, hd: Bool
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

  private init(key: String, url: URL, hd: Bool) { self.key = key; self.url = url; self.hd = hd }

  // the send screen's photos as they are now: each one going up (once), anything no longer there stopped
  static func sync(_ items: [SendPreviewVC.Item]) {
    var want = Set<String>()
    for it in items where it.kind == "photo" && it.coming == nil {
      want.insert(it.key)
      if let j = jobs[it.key], j.url == it.url, j.hd == it.hd { continue }
      jobs[it.key]?.cancel()
      let j = PreUpload(key: it.key, url: it.url, hd: it.hd); jobs[it.key] = j; j.start(name: it.name)
    }
    for (k, j) in jobs where !want.contains(k) { j.cancel(); jobs[k] = nil }
  }
  // the screen closed without sending: all let go
  static func dropAll() { jobs.values.forEach { $0.cancel() }; jobs = [:] }
  // Send: the one for this photo, if it's the same photo at the same quality and still good
  static func take(key: String, url: URL, hd: Bool) -> PreUpload? {
    guard let j = jobs.removeValue(forKey: key) else { return nil }
    guard j.url == url, j.hd == hd, !j.cancelled, !j.failedEarly else { j.cancel(); return nil }
    return j
  }

  private func start(name: String) {
    ChatVC.readyQ.async { [weak self] in
      guard let self = self else { return }
      let r = ChatVC.ready(self.url, kind: "photo", name: name, hd: self.hd, id: self.tmpId)
      DispatchQueue.main.async {
        guard !self.cancelled else { return }
        guard let r = r, r.kind == "photo" else { self.failedEarly = true; return }
        self.ready = r
        Net.shared.uploadMsg(r.data, name: r.name, stop: self.tmpId, message: { [weak self] fid, key in self?.message?(fid, key) ?? [:] },
                             gate: { [weak self] open in DispatchQueue.main.async { guard let self = self, !self.cancelled else { return }; if self.attached { open() } else { self.gate = open } } },
                             progress: { [weak self] p in DispatchQueue.main.async { self?.lastProgress = p; self?.onProgress?(p) } }) { [weak self] fid, key in
          DispatchQueue.main.async {
            guard let self = self, !self.cancelled else { return }
            if self.attached { self.done?(fid, key) } else { self.ended = (fid, key); if fid == nil { self.failedEarly = true } }
          }
        }
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
    if let r = ready { try? FileManager.default.removeItem(at: r.local) }
  }
}
