import UIKit
import Network
import AVFoundation
import CoreImage

/* Auto-download (mock-up "Talk — Auto-download", Haris 2026-11-13 17:48 "yes"): each kind's own switch in Settings › Storage
   and Data — Photos and Videos on, Files off at the start — and Use Mobile Data for all of them (off: they wait for Wi-Fi).
   Voice messages always come. One not downloaded: its little blurred picture (a file: WhatsApp's round ↓), a tap downloads
   it with a ring that fills (a tap on the ring stops it). The server keeps it for this phone until it's downloaded, at most
   30 days from sending; after that: No longer available. Opening, playing or sharing one always downloads it first. */
extension Notification.Name { static let talkFile = Notification.Name("talk.file") }   // object: the file's id — downloading, here, or gone

enum Auto {
  static let keep: Double = 30 * 86400 * 1000   // (the server's: 30 days from sending)
  private static let monitor = NWPathMonitor()
  private(set) static var onMobile = false
  // (watching the network: mobile data → Wi-Fi brings what waited for it)
  private static var started = false
  static func startOnce() {
    guard !started else { return }; started = true
    monitor.pathUpdateHandler = { p in
      let m = p.status == .satisfied && p.usesInterfaceType(.cellular) && !p.usesInterfaceType(.wifi) && !p.usesInterfaceType(.wiredEthernet)
      DispatchQueue.main.async {
        let was = onMobile; onMobile = m
        if was && !m { Talk.shared.catchUp() }
      }
    }
    monitor.start(queue: DispatchQueue(label: "talk.path"))
  }
  // this kind's switch
  static func on(_ kind: String) -> Bool {
    switch kind {
    case "voice": return true
    case "photo": return TalkPrefs.autoPhotos
    case "video": return TalkPrefs.autoVideos
    default: return TalkPrefs.autoFiles
    }
  }
  // downloads by itself now (its switch, and the network)
  static func now(_ kind: String) -> Bool { kind == "voice" || (on(kind) && (TalkPrefs.useMobile || !onMobile)) }
  // on this phone (one of yours being sent: its own copy)
  static func here(_ f: Msg.FileRef) -> Bool { f.id.hasPrefix("local-") || FileManager.default.fileExists(atPath: Net.local(f.id).path) }
  // no longer on the server for this phone
  static func gone(_ m: Msg) -> Bool {
    guard let f = m.file, !here(f) else { return false }
    if AskGroup.isBack(f.id) { return false }   // (asked back from the group: here again — AskGroup)
    return Downloads.shared.isGone(f.id) || Date().timeIntervalSince1970 * 1000 - m.at > keep
  }
  enum State: Equatable { case here, auto, wait, loading(Int64, Int64), gone }
  static func state(_ m: Msg) -> State {
    guard let f = m.file else { return .here }
    // (one of yours going up: the same ring as a download, filling as it goes — Haris 2026-11-16)
    if m.pending, !m.failed, let u = Uploads.going[f.id] { return .loading(u.0, u.1) }
    if here(f) { return .here }
    if let g = Downloads.shared.got[f.id] { return .loading(g.0, g.1) }
    if gone(m) { return .gone }
    return now(m.kind) ? .auto : .wait
  }
  static func size(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

/* leaving Talk (another app, the home screen): counted, so a send that stopped because of it isn't called failed — it goes
   on by itself when Talk is back (Haris 2026-11-21 13:18: "failed sent while we switched apps (should not happen)") */
enum BgWatch {
  static var left = 0
  private static var waiting: [() -> Void] = []
  static func whenBack(_ f: @escaping () -> Void) {
    if UIApplication.shared.applicationState == .active { f() } else { waiting.append(f) }
  }
  static func back() { let w = waiting; waiting = []; w.forEach { $0() } }
}

/* a file of yours going up: how far it is, for the same ring as a download (Haris 2026-11-16) — set as each part goes,
   gone once it's on the server; each change told to the bubbles showing it, as a download's */
enum Uploads {
  private(set) static var going: [String: (Int64, Int64)] = [:]
  private static var told: [String: Int] = [:]
  static func set(_ id: String, _ frac: Double, total: Int) {
    let pct = Int(frac * 100)
    guard told[id] != pct else { return }   // (told each whole percent — no more often)
    told[id] = pct; going[id] = (Int64(Double(total) * min(1, frac)), Int64(total))
    NotificationCenter.default.post(name: .talkFile, object: id)
  }
  static func end(_ id: String) {
    guard going[id] != nil else { return }
    going[id] = nil; told[id] = nil
    NotificationCenter.default.post(name: .talkFile, object: id)
  }
  // a video being made smaller before it goes: "Preparing · 40%" on its ring (the second number -1 says so) — it showed
  // "Zero KB of" the original's size the whole time (Haris 2026-11-21 12:56)
  static func prep(_ id: String, _ frac: Double) {
    let pct = Int(min(1, max(0, frac)) * 100)
    DispatchQueue.main.async {
      guard !isStopped(id), told[id] != -1 - pct else { return }
      told[id] = -1 - pct; going[id] = (Int64(pct), -1)
      NotificationCenter.default.post(name: .talkFile, object: id)
    }
  }
  // ✕ on one of yours going up: it stops — the making-smaller and the upload — and the message goes (Haris 2026-11-21 12:56:
  // "the x when video is uploading on bubble does nothing")
  private static let lock = NSLock()
  private static var stopped = Set<String>(), tasks: [String: [URLSessionTask]] = [:]
  static func isStopped(_ id: String?) -> Bool { guard let id = id else { return false }; lock.lock(); defer { lock.unlock() }; return stopped.contains(id) }
  static func add(_ t: URLSessionTask, to id: String?) {
    guard let id = id else { return }
    lock.lock(); let gone = stopped.contains(id); if !gone { tasks[id, default: []].append(t) }; lock.unlock()
    if gone { t.cancel() }
  }
  static func stop(_ id: String) {
    lock.lock(); stopped.insert(id); let ts = tasks.removeValue(forKey: id) ?? []; lock.unlock()
    ts.forEach { $0.cancel() }
    end(id)
  }
  static func done(_ id: String) { lock.lock(); tasks[id] = nil; lock.unlock() }
}

/* a file downloaded on a tap (or as Wi-Fi comes back): how far it is, for the ring; stopped with the ring */
final class Downloads: NSObject, URLSessionDownloadDelegate {
  static let shared = Downloads()
  private var tasks: [String: URLSessionDownloadTask] = [:]
  private var ids: [Int: String] = [:]
  private(set) var got: [String: (Int64, Int64)] = [:]
  private var waiters: [String: [(Bool) -> Void]] = [:]
  private var lastPost: [String: CFTimeInterval] = [:]
  // (iPhone's own background downloads: a download goes on with Talk closed or the phone locked, and Talk is woken to put it
  //  in place — Haris 2026-11-21 15:34; each task carries its file's id, so one finished after Talk was closed is still known)
  private lazy var session: URLSession = {
    let c = URLSessionConfiguration.background(withIdentifier: Downloads.sessionId)
    c.isDiscretionary = false; c.sessionSendsLaunchEvents = true; c.timeoutIntervalForRequest = 60
    return URLSession(configuration: c, delegate: self, delegateQueue: .main)
  }()
  static let sessionId = "ae.e11.talk.downloads"
  private var wake: (() -> Void)?
  func woken(_ f: @escaping () -> Void) { wake = f; _ = session }
  func start() {
    // (at launch: what iPhone was downloading for us, known again — its ring shows where it is)
    session.getAllTasks { ts in DispatchQueue.main.async {
      for t in ts { if let id = t.taskDescription, let d = t as? URLSessionDownloadTask, self.tasks[id] == nil { self.tasks[id] = d; self.ids[d.taskIdentifier] = id; self.got[id] = (d.countOfBytesReceived, d.countOfBytesExpectedToReceive) } }
    } }
  }
  func urlSessionDidFinishEvents(forBackgroundURLSession s: URLSession) {
    let f = wake; wake = nil
    DispatchQueue.main.async { f?() }
  }
  private func idOf(_ t: URLSessionTask) -> String? { ids[t.taskIdentifier] ?? t.taskDescription }
  private var goneIds: [String] = UserDefaults.standard.stringArray(forKey: "talk_gone_files") ?? []
  private lazy var goneSet = Set(goneIds)
  func isGone(_ id: String) -> Bool { goneSet.contains(id) }
  // (back on the server — Ask the group: no longer gone)
  func unGone(_ id: String) {
    guard goneSet.contains(id) else { return }
    goneIds.removeAll { $0 == id }; goneSet.remove(id); UserDefaults.standard.set(goneIds, forKey: "talk_gone_files")
  }
  func running(_ id: String) -> Bool { tasks[id] != nil }
  func start(_ id: String, size: Int, done: ((Bool) -> Void)? = nil) {
    if FileManager.default.fileExists(atPath: Net.local(id).path) { done?(true); return }
    if let d = done { waiters[id, default: []].append(d) }
    guard tasks[id] == nil else { return }
    let t = session.downloadTask(with: Net.shared.request("/api/talk/file/" + id + "?r2=1&pieces=1"))   // (?r2=1: straight from R2 — R2Files; pieces=1: this phone unlocks a big file in pieces)
    t.taskDescription = id
    tasks[id] = t; ids[t.taskIdentifier] = id; got[id] = (0, Int64(size))
    t.resume(); post(id)
  }
  func cancel(_ id: String) { tasks[id]?.cancel() }
  // (off to R2 for the file: without this server's sign-in)
  func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest n: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(CleanRedirect.clean(n))
  }
  private func post(_ id: String) { NotificationCenter.default.post(name: .talkFile, object: id) }
  func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData d: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
    guard let id = idOf(t) else { return }
    got[id] = (w, e > 0 ? e : got[id]?.1 ?? 0)
    // (the ring a few times a second — not on every piece)
    let now = CACurrentMediaTime()
    if now - (lastPost[id] ?? 0) > 0.1 { lastPost[id] = now; post(id) }
  }
  func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
    guard let id = idOf(t) else { return }
    let code = (t.response as? HTTPURLResponse)?.statusCode ?? 0
    if code == 200 {
      FileLock.openInPlace(id, at: loc)   // (sent locked: opened with its key)
      let to = Net.local(id); try? FileManager.default.removeItem(at: to); try? FileManager.default.moveItem(at: loc, to: to)
    } else if code == 404 || code == 410 {
      // (the server has let it go: No longer available — remembered, the newest 2000)
      goneSet.insert(id); goneIds.append(id); if goneIds.count > 2000 { goneIds.removeFirst(goneIds.count - 2000); goneSet = Set(goneIds) }
      UserDefaults.standard.set(goneIds, forKey: "talk_gone_files")
    }
  }
  func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
    guard let id = ids.removeValue(forKey: t.taskIdentifier) ?? t.taskDescription else { return }
    tasks[id] = nil; got[id] = nil; lastPost[id] = nil
    let ok = FileManager.default.fileExists(atPath: Net.local(id).path)
    let w = waiters.removeValue(forKey: id) ?? []
    post(id); w.forEach { $0(ok) }
    if !ok, (e as? URLError)?.code != .cancelled, !isGone(id), UIApplication.shared.applicationState == .active { toast("Couldn’t download it — try again") }
  }
}

/* a photo's or video's tiny picture, made on the phone that sends it — shown blurred until the real one is downloaded */
enum Thumb {
  // a video's frame taker: an HDR video's frame turned into standard colour by iPhone's own video tools as it's taken — the
  //  same way as before 236, when thumbnails were right (Haris 2026-11-22 15:56); converting the frame after didn't help
  static func frames(_ asset: AVAsset) -> AVAssetImageGenerator {
    let g = AVAssetImageGenerator(asset: asset); g.appliesPreferredTrackTransform = true
    if let t = asset.tracks(withMediaType: .video).first, t.hasMediaCharacteristic(.containsHDRVideo) {
      let c = AVMutableVideoComposition(propertiesOf: asset)
      c.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2; c.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2; c.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
      g.videoComposition = c
    }
    return g
  }
  static func make(_ url: URL, kind: String) -> String? {
    var img: UIImage?
    if kind == "photo" {
      img = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) }.map { UIImage(cgImage: $0) }
    } else if kind == "video" {
      let g = Thumb.frames(AVURLAsset(url: url)); g.maximumSize = CGSize(width: 32, height: 32)
      g.requestedTimeToleranceBefore = .positiveInfinity; g.requestedTimeToleranceAfter = .positiveInfinity
      img = (try? g.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)).map { UIImage(cgImage: $0) }
    }
    guard let i = img, let d = i.jpegData(compressionQuality: 0.5), d.count < 2900 else { return nil }
    return d.base64EncodedString()
  }
  // a sharp small preview, about 320 px across, sent with the message so the other phones show it at once instead of the
  // blur (WhatsApp's — Haris 2026-11-21 13:09, 15:18); a JPEG kept under 36 KB
  static func preview(_ url: URL, kind: String) -> String? {
    var cg: CGImage?
    if kind == "photo" {
      cg = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary) }
    } else if kind == "video" {
      let g = Thumb.frames(AVURLAsset(url: url)); g.maximumSize = CGSize(width: 320, height: 320)
      g.requestedTimeToleranceBefore = .positiveInfinity; g.requestedTimeToleranceAfter = .positiveInfinity
      do { cg = try g.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) }
      catch { Diag.note("Sharp preview: the frame couldn't be taken — \((error as NSError).localizedDescription) (file: \(url.lastPathComponent))") }
      Diag.variants(url)   // (the test page: the same frame four ways)
    }
    guard let c = cg else { return nil }
    let i = UIImage(cgImage: c)
    for q in [0.6, 0.45, 0.3] as [CGFloat] { if let d = i.jpegData(compressionQuality: q), d.count <= 35_000 { return d.base64EncodedString() } }
    if kind == "video" { Diag.note("Sharp preview: too big even at the lowest quality") }
    return nil
  }
  private static let made = NSCache<NSString, UIImage>()
  private static let ctx = CIContext()   // (one, kept — making one for each picture is slow)
  // (blurred once, kept)
  static func image(_ f: Msg.FileRef) -> UIImage? {
    if let i = made.object(forKey: f.id as NSString) { return i }
    // (the sharp preview when it came with the message — no blur)
    if let s = f.prev, let d = Data(base64Encoded: s), let p = UIImage(data: d) { made.setObject(p, forKey: f.id as NSString); return p }
    guard let s = f.thumb, let d = Data(base64Encoded: s), let small = UIImage(data: d), let ci = CIImage(image: small) else { return nil }
    let k: CGFloat = 8, ext = ci.extent
    let up = ci.transformed(by: CGAffineTransform(scaleX: k, y: k)).clampedToExtent()
    guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: up, kCIInputRadiusKey: 14])?.outputImage,
          let cg = Thumb.ctx.createCGImage(blur, from: CGRect(x: 0, y: 0, width: ext.width * k, height: ext.height * k)) else { return nil }
    let i = UIImage(cgImage: cg); made.setObject(i, forKey: f.id as NSString); return i
  }
}

/* over a photo or video not on the phone: ↓ and its size (Apple's blur, a capsule); downloading: a ring that fills, ✕ to
   stop, how much below; gone: No longer available over its place */
final class DownloadBadge: UIView {
  private let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let pillIcon = UIImageView(image: UIImage(systemName: "arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)))
  private let pillText = UILabel()
  private let disc = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let track = CAShapeLayer(), arc = CAShapeLayer()
  private let stop = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)))
  private let howMuch = InsetLabel(dx: 9, dy: 3)
  private let goneBox = UIView(), goneIcon = UIImageView(), goneTitle = UILabel(), goneLine = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    pill.clipsToBounds = true; pill.layer.cornerRadius = 22
    pillIcon.tintColor = .white; pillText.textColor = .white; pillText.font = .systemFont(ofSize: 15, weight: .semibold)
    [pillIcon, pillText].forEach { pill.contentView.addSubview($0) }
    disc.clipsToBounds = true; disc.layer.cornerRadius = 26
    for (l, c, w) in [(track, UIColor.white.withAlphaComponent(0.25), CGFloat(3)), (arc, UIColor.white, CGFloat(3))] {
      l.fillColor = UIColor.clear.cgColor; l.strokeColor = c.cgColor; l.lineWidth = w; l.lineCap = .round
      disc.contentView.layer.addSublayer(l)
    }
    stop.tintColor = .white; disc.contentView.addSubview(stop)
    howMuch.font = .systemFont(ofSize: 12, weight: .semibold); howMuch.textColor = .white
    howMuch.backgroundColor = UIColor.black.withAlphaComponent(0.5); howMuch.layer.cornerRadius = 11; howMuch.clipsToBounds = true
    goneBox.backgroundColor = .secondarySystemBackground
    goneIcon.image = UIImage(systemName: "icloud.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)); goneIcon.tintColor = .secondaryLabel; goneIcon.contentMode = .center
    goneTitle.font = .systemFont(ofSize: 16, weight: .semibold); goneTitle.textColor = .label; goneTitle.text = "No longer available"; goneTitle.textAlignment = .center
    goneLine.font = .systemFont(ofSize: 13); goneLine.textColor = .secondaryLabel; goneLine.text = "It wasn’t downloaded within 30 days"; goneLine.textAlignment = .center; goneLine.numberOfLines = 2
    [goneIcon, goneTitle, goneLine].forEach { goneBox.addSubview($0) }
    [goneBox, pill, disc, howMuch].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  private(set) var state: Auto.State = .here
  // (why it's gone: past 30 days, or the server let it go sooner — an older app's way)
  var why = "It wasn’t downloaded within 30 days" { didSet { goneLine.text = why; setNeedsLayout() } }
  func set(_ s: Auto.State, size: Int) {
    state = s
    pill.isHidden = s != .wait; goneBox.isHidden = s != .gone
    var loading = false
    if case .loading(let w, let e) = s {
      loading = true
      if e < 0 {
        // (being made smaller first: how far, in percent)
        arc.strokeEnd = CGFloat(min(1, max(0.02, Double(w) / 100)))
        howMuch.text = "Preparing · \(w)%"
      } else {
        let total = max(e, 1)
        arc.strokeEnd = CGFloat(min(1, max(0.02, Double(w) / Double(total))))
        howMuch.text = Auto.size(w) + " of " + Auto.size(total)
      }
    }
    disc.isHidden = !loading; howMuch.isHidden = !loading
    pillText.text = Auto.size(Int64(size))
    isHidden = s == .here || s == .auto
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let b = bounds, c = CGPoint(x: b.midX, y: b.midY)
    pillText.sizeToFit()
    let pw = 12 + 18 + 7 + pillText.bounds.width + 16
    pill.frame = CGRect(x: (c.x - pw / 2).rounded(), y: (c.y - 22).rounded(), width: pw, height: 44)
    pillIcon.frame = CGRect(x: 12, y: 13, width: 18, height: 18); pillText.frame = CGRect(x: 37, y: 0, width: pillText.bounds.width, height: 44)
    disc.frame = CGRect(x: (c.x - 26).rounded(), y: (c.y - 26).rounded(), width: 52, height: 52)
    let p = UIBezierPath(arcCenter: CGPoint(x: 26, y: 26), radius: 22, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
    track.path = p; arc.path = p; track.frame = disc.bounds; arc.frame = disc.bounds
    stop.frame = CGRect(x: 16, y: 16, width: 20, height: 20); stop.contentMode = .center
    howMuch.sizeToFit()
    howMuch.frame = CGRect(x: (c.x - howMuch.bounds.width / 2).rounded(), y: disc.frame.maxY + 10, width: howMuch.bounds.width, height: 22)
    goneBox.frame = b
    let small = b.height < 170
    goneIcon.frame = CGRect(x: 0, y: (c.y - (small ? 30 : 44)).rounded(), width: b.width, height: 30)
    goneTitle.frame = CGRect(x: 16, y: goneIcon.frame.maxY + 6, width: b.width - 32, height: 21)
    goneLine.isHidden = small
    goneLine.frame = CGRect(x: 24, y: goneTitle.frame.maxY + 2, width: b.width - 48, height: 36); goneLine.sizeToFit()
    goneLine.frame = CGRect(x: 24, y: goneTitle.frame.maxY + 2, width: b.width - 48, height: goneLine.bounds.height)
  }
}

/* a file's card: WhatsApp's round ↓ becomes a ring that fills, a small ■ to stop it */
final class DownloadRing: UIView {
  private let track = CAShapeLayer(), arc = CAShapeLayer(), square = UIView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    for l in [track, arc] { l.fillColor = UIColor.clear.cgColor; l.lineCap = .round; layer.addSublayer(l) }
    track.lineWidth = 1.6; arc.lineWidth = 2.2
    square.layer.cornerRadius = 2; addSubview(square)
  }
  required init?(coder: NSCoder) { fatalError() }
  var ink: UIColor = .label { didSet { tint() } }
  private func tint() {
    arc.strokeColor = ink.resolvedColor(with: traitCollection).cgColor
    track.strokeColor = ink.withAlphaComponent(0.2).resolvedColor(with: traitCollection).cgColor
    square.backgroundColor = ink
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) { super.traitCollectionDidChange(p); tint() }
  func set(_ frac: Double) { arc.strokeEnd = CGFloat(min(1, max(0.02, frac))) }
  override func layoutSubviews() {
    super.layoutSubviews()
    let r = min(bounds.width, bounds.height) / 2 - 1.2, c = CGPoint(x: bounds.midX, y: bounds.midY)
    let p = UIBezierPath(arcCenter: c, radius: r, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
    track.path = p; arc.path = p; track.frame = bounds; arc.frame = bounds
    square.frame = CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)
  }
}

/* a file handed out of Talk (Save / Share): under its own name; a HEIC photo as a JPEG, so any computer opens it (Windows
   can't always) — Haris 2026-11-21 12:27 */
// iPhone's Save / Share sheet — and, once it's done, where it went: "Saved to Photos" or "Saved to Files", only for those two
// (a PDF is never offered Photos by iPhone, so it never says Photos — Haris 2026-11-21)
enum ShareOut {
  static func sheet(_ items: [Any]) -> UIActivityViewController {
    let a = UIActivityViewController(activityItems: items, applicationActivities: nil)
    a.completionWithItemsHandler = { type, done, _, _ in
      guard done, let t = type else { return }
      if t == .saveToCameraRoll { toast("Saved to Photos") }
      else if t.rawValue.localizedCaseInsensitiveContains("SaveToFiles") { toast("Saved to Files") }
    }
    return a
  }
}

enum ShareCopy {
  static func named(_ f: Msg.FileRef, from url: URL) -> URL {
    let tmp = FileManager.default.temporaryDirectory
    if f.kind == "photo", (f.name as NSString).pathExtension.lowercased() == "heic",
       let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
       let d = UIImage(cgImage: cg).jpegData(compressionQuality: 0.9) {
      let out = tmp.appendingPathComponent((f.name as NSString).deletingPathExtension + ".jpg")
      try? FileManager.default.removeItem(at: out)
      if (try? d.write(to: out)) != nil { return out }
    }
    let named = tmp.appendingPathComponent(f.name)
    try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
    return named
  }
}
