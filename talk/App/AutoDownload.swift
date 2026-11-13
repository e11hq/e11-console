import UIKit
import Network
import AVFoundation

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
    return Downloads.shared.isGone(f.id) || Date().timeIntervalSince1970 * 1000 - m.at > keep
  }
  enum State: Equatable { case here, auto, wait, loading(Int64, Int64), gone }
  static func state(_ m: Msg) -> State {
    guard let f = m.file else { return .here }
    if here(f) { return .here }
    if let g = Downloads.shared.got[f.id] { return .loading(g.0, g.1) }
    if gone(m) { return .gone }
    return now(m.kind) ? .auto : .wait
  }
  static func size(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

/* a file downloaded on a tap (or as Wi-Fi comes back): how far it is, for the ring; stopped with the ring */
final class Downloads: NSObject, URLSessionDownloadDelegate {
  static let shared = Downloads()
  private var tasks: [String: URLSessionDownloadTask] = [:]
  private var ids: [Int: String] = [:]
  private(set) var got: [String: (Int64, Int64)] = [:]
  private var waiters: [String: [(Bool) -> Void]] = [:]
  private var lastPost: [String: CFTimeInterval] = [:]
  private lazy var session: URLSession = {
    let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 60
    return URLSession(configuration: c, delegate: self, delegateQueue: .main)
  }()
  private var goneIds: [String] = UserDefaults.standard.stringArray(forKey: "talk_gone_files") ?? []
  private lazy var goneSet = Set(goneIds)
  func isGone(_ id: String) -> Bool { goneSet.contains(id) }
  func running(_ id: String) -> Bool { tasks[id] != nil }
  func start(_ id: String, size: Int, done: ((Bool) -> Void)? = nil) {
    if FileManager.default.fileExists(atPath: Net.local(id).path) { done?(true); return }
    if let d = done { waiters[id, default: []].append(d) }
    guard tasks[id] == nil else { return }
    let t = session.downloadTask(with: Net.shared.request("/api/talk/file/" + id))
    tasks[id] = t; ids[t.taskIdentifier] = id; got[id] = (0, Int64(size))
    t.resume(); post(id)
  }
  func cancel(_ id: String) { tasks[id]?.cancel() }
  private func post(_ id: String) { NotificationCenter.default.post(name: .talkFile, object: id) }
  func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData d: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
    guard let id = ids[t.taskIdentifier] else { return }
    got[id] = (w, e > 0 ? e : got[id]?.1 ?? 0)
    // (the ring a few times a second — not on every piece)
    let now = CACurrentMediaTime()
    if now - (lastPost[id] ?? 0) > 0.1 { lastPost[id] = now; post(id) }
  }
  func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
    guard let id = ids[t.taskIdentifier] else { return }
    let code = (t.response as? HTTPURLResponse)?.statusCode ?? 0
    if code == 200 {
      let to = Net.local(id); try? FileManager.default.removeItem(at: to); try? FileManager.default.moveItem(at: loc, to: to)
    } else if code == 404 || code == 410 {
      // (the server has let it go: No longer available — remembered, the newest 2000)
      goneSet.insert(id); goneIds.append(id); if goneIds.count > 2000 { goneIds.removeFirst(goneIds.count - 2000); goneSet = Set(goneIds) }
      UserDefaults.standard.set(goneIds, forKey: "talk_gone_files")
    }
  }
  func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
    guard let id = ids.removeValue(forKey: t.taskIdentifier) else { return }
    tasks[id] = nil; got[id] = nil; lastPost[id] = nil
    let ok = FileManager.default.fileExists(atPath: Net.local(id).path)
    let w = waiters.removeValue(forKey: id) ?? []
    post(id); w.forEach { $0(ok) }
    if !ok, (e as? URLError)?.code != .cancelled, !isGone(id) { toast("Couldn’t download it — try again") }
  }
}

/* a photo's or video's tiny picture, made on the phone that sends it — shown blurred until the real one is downloaded */
enum Thumb {
  static func make(_ url: URL, kind: String) -> String? {
    var img: UIImage?
    if kind == "photo" {
      img = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) }.map { UIImage(cgImage: $0) }
    } else if kind == "video" {
      let g = AVAssetImageGenerator(asset: AVURLAsset(url: url)); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 32, height: 32)
      g.requestedTimeToleranceBefore = .positiveInfinity; g.requestedTimeToleranceAfter = .positiveInfinity
      img = (try? g.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)).map { UIImage(cgImage: $0) }
    }
    guard let i = img, let d = i.jpegData(compressionQuality: 0.5), d.count < 2900 else { return nil }
    return d.base64EncodedString()
  }
  private static let made = NSCache<NSString, UIImage>()
  // (blurred once, kept)
  static func image(_ f: Msg.FileRef) -> UIImage? {
    if let i = made.object(forKey: f.id as NSString) { return i }
    guard let s = f.thumb, let d = Data(base64Encoded: s), let small = UIImage(data: d), let ci = CIImage(image: small) else { return nil }
    let k: CGFloat = 8, ext = ci.extent
    let up = ci.transformed(by: CGAffineTransform(scaleX: k, y: k)).clampedToExtent()
    guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: up, kCIInputRadiusKey: 14])?.outputImage,
          let cg = CIContext().createCGImage(blur, from: CGRect(x: 0, y: 0, width: ext.width * k, height: ext.height * k)) else { return nil }
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
  func set(_ s: Auto.State, size: Int) {
    state = s
    pill.isHidden = s != .wait; goneBox.isHidden = s != .gone
    var loading = false
    if case .loading(let w, let e) = s {
      loading = true
      let total = max(e, 1)
      arc.strokeEnd = CGFloat(min(1, max(0.02, Double(w) / Double(total))))
      howMuch.text = Auto.size(w) + " of " + Auto.size(total)
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
