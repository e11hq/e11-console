// The file preview on the iPhone app (18+, Haris 2026-10-30): today's preview — × · "3 of 8" · ⋯ at the top, the name
// and details, the strip of files, Copy and Download at the bottom — drawn by iOS. Pictures zoom and swipe like Photos
// (pinch, double-tap, iOS's own paging); videos play in place (as E11 Talk's), sounds in Apple's own player; PDF / Word / Excel / PowerPoint
// show the server's page pictures in a zoomable scroll; anything else shows its card, as today. Tap hides the bars;
// pull down to close. The page sends the files (absolute addresses on the server) and does Copy / Download / ⋯ itself
// (window.__e11Preview); files are fetched with the app's own sign-in (its cookies).
import UIKit
import UIKit.UIGestureRecognizerSubclass
import AVKit
import WebKit
import CryptoKit
import PDFKit

/* ---------- fetching from the server with the app's sign-in ---------- */
enum PreviewLoad {
  static let cache = NSCache<NSString, NSData>()
  static var cookies: [HTTPCookie] = []
  static func refreshCookies(_ store: WKHTTPCookieStore, _ then: @escaping () -> Void) {
    store.getAllCookies { c in cookies = c; DispatchQueue.main.async { then() } }
  }
  static func headers(_ url: URL) -> [String: String] {
    let host = url.host ?? ""
    let mine = cookies.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return host == d || host.hasSuffix("." + d) }
    return HTTPCookie.requestHeaderFields(with: mine)
  }
  // (only what arrived whole is kept — Haris 2026-11-23 11:18: a picture cut off part way, a strip at the top and black below,
  //  was kept on the phone and shown that way from then on. Whole: no error, all the bytes the server said, and a PNG (the
  //  server's own pictures) that reaches its own end — JPEGs aren't read for it: a camera's can carry more after their end — a server can send a file that was still being written, complete as far as it knows)
  static func whole(_ d: Data, _ res: URLResponse?, _ err: Error?) -> Bool {
    if err != nil { return false }
    // (the length is the one sent — compressed, it isn't the picture's own, so it isn't compared then)
    let packed = ((res as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding") ?? "identity").lowercased() != "identity"
    if !packed, let n = res?.expectedContentLength, n > 0, Int64(d.count) != n { return false }
    let b = [UInt8](d.prefix(8))
    if b.count >= 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 {   // PNG: ends with its IEND mark
      return d.count >= 12 && d.suffix(12).prefix(8).elementsEqual([0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44])
    }
    return true
  }
  static func data(_ s: String, _ done: @escaping (Data?) -> Void) {
    guard let url = URL(string: s) else { return done(nil) }
    if let d = cache.object(forKey: s as NSString) { return done(d as Data) }
    // (kept on the phone too, up to 25 MB a file — opened again after the app restarts or updates, it's there at once:
    //  Haris 2026-11-05)
    if let d = DiskPics.get("pv:" + s) { cache.setObject(d as NSData, forKey: s as NSString); return done(d) }
    var r = URLRequest(url: url)
    r.allHTTPHeaderFields = headers(url)
    URLSession.shared.dataTask(with: r) { data, resp, err in
      let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
      let d = ok ? data : nil
      if let d, whole(d, resp, err) { cache.setObject(d as NSData, forKey: s as NSString); if d.count <= 25_000_000 { DiskPics.put("pv:" + s, d) } }
      DispatchQueue.main.async { done(d) }
    }.resume()
  }
  // (pictures ready to draw, the last few opened — opened again, it's there sharp at once: Haris 2026-11-19 11:15)
  static let pics: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 16; return c }()
  static func image(_ s: String?, _ done: @escaping (UIImage?) -> Void) {
    guard let s, !s.isEmpty else { return done(nil) }
    if let i = pics.object(forKey: s as NSString) { return done(i) }
    // (an SVG drawn once is kept as a picture, as the lists' loader keeps it — opened again, no redraw: Haris 2026-11-21 00:20)
    if let png = DiskPics.get("pvsvg:" + s), let i = UIImage(data: png) { pics.setObject(i, forKey: s as NSString); return done(i) }
    data(s) { d in
      if let d = d, UIImage(data: d) == nil, SVGRaster.looksLikeSVG(d, path: s) {   // (an SVG, drawn on the phone)
        SVGRaster.shared.image(d, max: 1400) { img in
          if let img { pics.setObject(img, forKey: s as NSString); if let png = img.pngData() { DiskPics.put("pvsvg:" + s, png) } }
          done(img)
        }
        return
      }
      let i = d.flatMap { UIImage(data: $0) }.map { $0.preparingForDisplay() ?? $0 }
      if let i { pics.setObject(i, forKey: s as NSString) }
      done(i)
    }
  }
  // the full picture when the phone has it already (ready to draw) — nil otherwise, nothing fetched
  static func ready(_ s: String?) -> UIImage? {
    guard let s, !s.isEmpty else { return nil }
    if let i = pics.object(forKey: s as NSString) { return i }
    guard let d = (cache.object(forKey: s as NSString) as Data?) ?? DiskPics.get("pv:" + s), let raw = UIImage(data: d) else { return nil }
    cache.setObject(d as NSData, forKey: s as NSString)
    let i = raw.preparingForDisplay() ?? raw
    pics.setObject(i, forKey: s as NSString); return i
  }
}

/* ---------- one file's page ---------- */
final class PreviewCell: UICollectionViewCell, UIScrollViewDelegate {
  static let id = "pv"
  let zoomer = UIScrollView()
  private let content = UIView()
  private let imageView = UIImageView()
  private let pagesStack = UIStackView()
  private let cardStack = UIStackView()
  private let cardPic = UIImageView()
  private let cardType = UILabel()
  private let cardNote = UILabel()
  private let play = UIButton(type: .custom)
  private let textView = UITextView()
  private let spinner = UIActivityIndicatorView(style: .large)
  private var file: [String: Any] = [:]
  private var token = 0
  var onPlay: (([String: Any]) -> Void)?   // (a sound: Apple's own player)
  // a video plays here, in place, as E11 Talk's (Haris 2026-11-15: "it should play in the same preview as Talk"): the
  // moment it's on show, Apple's player layer over its first picture, fading in once its first frame is there; the buttons
  // step aside once it plays; ▶ once paused or ended, ⏸ while it plays and the buttons show
  final class PlayerView: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; var pl: AVPlayerLayer { layer as! AVPlayerLayer } }
  private var player: AVPlayer?, playerView: PlayerView?, ready: NSKeyValueObservation?, rateObs: NSKeyValueObservation?, ended: NSObjectProtocol?
  private var want = false, atEnd = false, held = false
  var onPlaying: (() -> Void)?
  var onPlayer: (() -> Void)?   // (its player made — the preview's seek bar follows it)
  var avPlayer: AVPlayer? { player }
  // (sound and picture together, as E11 Talk's — Haris 2026-11-23: it plays only once the picture has landed and its first
  //  frame is ready; the still stays only until then, the frame taking its place at once — no fade)
  var landed = true { didSet { go() } }
  private func go() {
    guard want, landed, !held, let p = player, playerView?.pl.isReadyForDisplay == true, p.timeControlStatus == .paused else { return }
    p.play()
  }
  var chrome = true { didSet { button(animated: true) } }
  // (the preview's own buttons, asked each time: ⏸ shows only while they show — never out of step with them, Haris 2026-11-21)
  var barsShown: (() -> Bool)?
  private var isVideo: Bool { (file["kind"] as? String) == "video" }
  var onPages: ((String) -> Void)?
  private var mode = ""   // image / pages / card / text

  override init(frame: CGRect) {
    super.init(frame: frame)
    zoomer.delegate = self
    zoomer.minimumZoomScale = 1; zoomer.maximumZoomScale = 4
    zoomer.showsHorizontalScrollIndicator = false; zoomer.showsVerticalScrollIndicator = false
    zoomer.contentInsetAdjustmentBehavior = .never
    if #available(iOS 26.0, *) { zoomer.topEdgeEffect.isHidden = true; zoomer.bottomEdgeEffect.isHidden = true; textView.topEdgeEffect.isHidden = true; textView.bottomEdgeEffect.isHidden = true }
    zoomer.frame = contentView.bounds; zoomer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    contentView.addSubview(zoomer)
    zoomer.addSubview(content)
    imageView.contentMode = .scaleAspectFit
    content.addSubview(imageView)
    pagesStack.axis = .vertical; pagesStack.spacing = 10
    content.addSubview(pagesStack)
    cardStack.axis = .vertical; cardStack.alignment = .center; cardStack.spacing = 14
    cardPic.contentMode = .scaleAspectFit; cardPic.layer.cornerRadius = 14; cardPic.clipsToBounds = true
    cardPic.translatesAutoresizingMaskIntoConstraints = false
    cardPic.widthAnchor.constraint(equalToConstant: 240).isActive = true
    cardPic.heightAnchor.constraint(equalToConstant: 240).isActive = true
    // (light words on the viewer's black — Talk's viewer is black in light and dark alike)
    cardType.font = .systemFont(ofSize: 28, weight: .bold); cardType.textColor = UIColor(white: 1, alpha: 0.62)
    cardNote.font = .systemFont(ofSize: 15); cardNote.textColor = UIColor(white: 1, alpha: 0.62); cardNote.numberOfLines = 0; cardNote.textAlignment = .center
    [cardPic, cardType, cardNote].forEach { cardStack.addArrangedSubview($0) }
    contentView.addSubview(cardStack)
    SymSwap.set(play, UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)), animated: false); play.accessibilityLabel = "Play"
    play.tintColor = .white
    play.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    play.layer.cornerRadius = 35   // (Talk's size: 70, its symbol 24 semibold — Haris 2026-11-21)
    play.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      guard self.isVideo else { self.onPlay?(self.file); return }
      if (self.player?.timeControlStatus ?? .paused) != .paused { self.want = false; self.held = true; self.player?.pause(); self.button(animated: true) } else { self.held = false; self.start() }
    }, for: .touchUpInside)
    contentView.addSubview(play)
    textView.isEditable = false; textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular); textView.backgroundColor = .clear; textView.textColor = .white
    textView.textContainerInset = UIEdgeInsets(top: 110, left: 14, bottom: 200, right: 14)
    contentView.addSubview(textView)
    spinner.color = .white; contentView.addSubview(spinner)
    let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
    dbl.numberOfTapsRequired = 2
    zoomer.addGestureRecognizer(dbl)
  }
  required init?(coder: NSCoder) { fatalError() }
  // what a pull down moves: the picture (Talk's — it follows the finger), else the whole page
  var dragView: UIView { mode == "image" ? imageView : contentView }
  // the picture on show and where it sits on the screen (the preview flies back from it)
  var shownPicture: (UIImage, CGRect)? {
    guard mode == "image", !imageView.isHidden, let img = imageView.image, img.size.width > 0, img.size.height > 0 else { return nil }
    return (img, imageView.convert(AVMakeRect(aspectRatio: img.size, insideRect: imageView.bounds), to: nil))
  }
  var doubleTapGesture: UITapGestureRecognizer? { zoomer.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first { $0.numberOfTapsRequired == 2 } }

  // on show: it plays (from the phone's copy when it's kept — MediaKeep — else streamed, signed in); off show: it pauses
  func start() {
    guard isVideo else { return }
    want = true
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    if let p = player { if atEnd { atEnd = false; p.seek(to: .zero) }; go(); return }
    load()
  }
  // (as the preview starts opening: the player made and readied, not playing — it plays the moment the picture has landed,
  //  as E11 Talk's)
  func prepare() { guard isVideo, player == nil else { return }; load() }
  private func load() {
    guard let s = file["src"] as? String, let url0 = URL(string: s) else { return }
    let kept = MediaKeep.local(s)
    if kept == nil { MediaKeep.fetch(s) }
    let url = kept ?? url0
    let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: PreviewLoad.cookies.filter { c in
      let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
      return (url.host ?? "") == d || (url.host ?? "").hasSuffix("." + d)
    }])
    let p = AVPlayer(playerItem: AVPlayerItem(asset: asset)); p.actionAtItemEnd = .pause
    let v = PlayerView(); v.pl.player = p; v.pl.videoGravity = .resizeAspect; v.alpha = 0; v.isUserInteractionEnabled = false
    v.frame = imageView.bounds; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    imageView.addSubview(v)   // (inside the picture: it follows the finger when pulled down, and flies back with it)
    player = p; playerView = v
    ready = v.pl.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
      guard l.isReadyForDisplay else { return }
      DispatchQueue.main.async { self?.spinner.stopAnimating(); v.alpha = 1; self?.go() }   // (its first frame in place of the still at once, then it plays)
    }
    rateObs = p.observe(\.timeControlStatus, options: [.new]) { [weak self] pl, _ in
      DispatchQueue.main.async { guard let self = self else { return }; if pl.timeControlStatus == .playing { self.onPlaying?() }; self.button(animated: true) }
    }
    ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in self?.atEnd = true; self?.button(animated: true) }
    onPlayer?()
    go()
  }
  // the seek bar (E11 Talk's): dragged — paused while the finger is on it, on from there when it's let go (if it was playing)
  private var wasPlaying = false
  func scrubBegin() { wasPlaying = player?.timeControlStatus != .paused; player?.pause() }
  func scrub(to t: Double) {
    atEnd = false
    player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    button(animated: true)
  }
  // (let go: playing on if it was playing; otherwise paused where it was let go, with its ▶ — after the end, a drag back
  //  had left it paused with no ▶ and no way to play: Haris 2026-11-25 20:19)
  func scrubEnd() {
    if wasPlaying, want, !held { player?.play() }
    else if !wasPlaying, player != nil { held = true; button(animated: true) }
  }
  func stop() { want = false; held = false; player?.pause(); button(animated: false) }
  private func stopVideo() {
    player?.pause(); playerView?.removeFromSuperview()
    if let e = ended { NotificationCenter.default.removeObserver(e) }
    player = nil; playerView = nil; ready = nil; rateObs = nil; ended = nil; want = false; atEnd = false; held = false
  }
  // ▶ once paused with ⏸ or ended; ⏸ while it plays and the buttons show; nothing while it plays on its own or loads
  private func button(animated: Bool) {
    guard isVideo else { return }
    let playing = player?.timeControlStatus == .playing
    let name = playing ? "pause.fill" : "play.fill"
    let alpha: CGFloat = playing ? ((barsShown?() ?? chrome) ? 1 : 0) : (held || atEnd ? 1 : 0)
    guard play.alpha != alpha || play.accessibilityIdentifier != name else { return }
    // (▶ ↔ ⏸ with the shared swap, SymSwap; the button fading as it comes or goes — Haris 2026-11-17)
    if play.accessibilityIdentifier != name {
      SymSwap.set(play, UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)), animated: animated && play.alpha > 0 && alpha > 0)
      play.accessibilityIdentifier = name; play.accessibilityLabel = playing ? "Pause" : "Play"
    }
    if animated { UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { self.play.alpha = alpha } } else { play.alpha = alpha }
  }
  deinit { if let e = ended { NotificationCenter.default.removeObserver(e) } }

  func show(_ f: [String: Any]) {
    stopVideo()
    file = f; token += 1
    let my = token
    zoomer.setZoomScale(1, animated: false)
    imageView.image = nil; imageView.isHidden = true
    pagesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }; pagesStack.isHidden = true
    cardStack.isHidden = true; play.isHidden = true; textView.isHidden = true; zoomer.isHidden = false
    spinner.stopAnimating()
    let kind = f["kind"] as? String ?? "other"
    switch kind {
    case "image":
      mode = "image"
      imageView.isHidden = false
      // the small picture at once, then the sharp one
      PreviewLoad.image(f["thumb"] as? String) { [weak self] img in guard let self, self.token == my, self.imageView.image == nil, let img else { return }; self.imageView.image = img; self.setNeedsLayout() }
      spinner.startAnimating()
      PreviewLoad.image(f["src"] as? String) { [weak self] img in guard let self, self.token == my else { return }; self.spinner.stopAnimating(); if let img { self.imageView.image = img; self.setNeedsLayout() } }
    case "video":
      // (its first picture filling the page, as a photo; it plays here once it's on show — start())
      mode = "image"
      imageView.isHidden = false
      if let cv = f["cover"] as? String, !cv.isEmpty {
        PreviewLoad.image(cv) { [weak self] img in guard let self, self.token == my else { return }; if let img { self.imageView.image = img; self.setNeedsLayout() } }
      }
      play.isHidden = false; play.alpha = 0
      spinner.startAnimating()
    case "audio":
      mode = "card"
      card(f, note: nil)
      play.isHidden = false
    case "pages":
      mode = "pages"
      pagesStack.isHidden = false
      spinner.startAnimating()
      // (a PDF: drawn on the phone from the file itself — kept on the phone after the first time — instead of waiting for
      //  the server to make pictures of its pages; they stayed on the spinner, Haris 2026-11-06. Office files: the server's)
      if (f["ext"] as? String) == "pdf", let src = f["src"] as? String, !src.isEmpty {
        PreviewLoad.data(src) { [weak self] d in
          guard let self, self.token == my else { return }
          guard let d = d, let doc = PDFDocument(data: d), doc.pageCount > 0 else { if let id = f["id"] as? String { self.onPages?(id) }; return }
          self.showPDF(doc, my)
        }
      } else if let id = f["id"] as? String { onPages?(id) }
    case "text":
      mode = "text"
      zoomer.isHidden = true; textView.isHidden = false; textView.text = ""
      spinner.startAnimating()
      PreviewLoad.data(f["src"] as? String ?? "") { [weak self] d in guard let self, self.token == my else { return }; self.spinner.stopAnimating(); self.textView.text = d.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    default:
      mode = "card"
      card(f, note: f["note"] as? String ?? "Download it to see the whole file.")
    }
    setNeedsLayout()
  }
  private func card(_ f: [String: Any], note: String?) {
    zoomer.isHidden = true
    cardStack.isHidden = false
    cardType.text = ((f["ext"] as? String) ?? "file").uppercased()
    cardNote.text = note; cardNote.isHidden = note == nil
    cardPic.image = nil; cardPic.isHidden = true
    cardType.isHidden = false
    let my = token
    PreviewLoad.image(f["cover"] as? String) { [weak self] img in
      guard let self, self.token == my, let img else { return }
      self.cardPic.image = img; self.cardPic.isHidden = false; self.cardType.isHidden = true; self.setNeedsLayout()
    }
  }
  // the server's page pictures arrived (PDF / Office)
  // a PDF's pages, drawn here (the first 40, as the server's), each one as it's ready
  private func showPDF(_ doc: PDFDocument, _ my: Int) {
    spinner.stopAnimating()
    pagesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let n = min(doc.pageCount, 40)
    let W: CGFloat = 1240
    for i in 0..<n {
      guard let pg = doc.page(at: i) else { continue }
      let b = pg.bounds(for: .mediaBox)
      let iv = UIImageView(); iv.contentMode = .scaleAspectFit; iv.backgroundColor = .white
      iv.translatesAutoresizingMaskIntoConstraints = false
      iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: b.width > 0 ? b.height / b.width : 1.414).isActive = true
      pagesStack.addArrangedSubview(iv)
      DispatchQueue.global(qos: .userInitiated).async { [weak self, weak iv] in
        let scale = b.width > 0 ? W / b.width : 1
        let img = pg.thumbnail(of: CGSize(width: b.width * scale, height: b.height * scale), for: .mediaBox)
        DispatchQueue.main.async { guard let self, self.token == my else { return }; iv?.image = img }
      }
    }
    if doc.pageCount > n { let l = UILabel(); l.text = "Showing the first \(n) of \(doc.pageCount) pages — download it for the rest."; l.font = .systemFont(ofSize: 13); l.textColor = .secondaryLabel; l.numberOfLines = 0; l.textAlignment = .center; pagesStack.addArrangedSubview(l) }
    setNeedsLayout()
  }
  func setPages(_ urls: [String], note: String?) {
    let my = token
    spinner.stopAnimating()
    pagesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    if urls.isEmpty {
      mode = "card"; card(file, note: note ?? "This file couldn’t be previewed — download it to see it."); return
    }
    for u in urls {
      let iv = UIImageView(); iv.contentMode = .scaleAspectFit; iv.backgroundColor = .white
      iv.translatesAutoresizingMaskIntoConstraints = false
      let ratio = iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: 1.414)   // (A4 until the picture says otherwise)
      ratio.isActive = true
      pagesStack.addArrangedSubview(iv)
      PreviewLoad.image(u) { [weak self, weak iv] img in
        guard let self, self.token == my, let iv, let img, img.size.width > 0 else { return }
        iv.image = img
        ratio.isActive = false
        iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width).isActive = true
        self.setNeedsLayout()
      }
    }
    if let note { let l = UILabel(); l.text = note; l.font = .systemFont(ofSize: 13); l.textColor = .secondaryLabel; l.numberOfLines = 0; l.textAlignment = .center; pagesStack.addArrangedSubview(l) }
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let b = contentView.bounds
    spinner.center = CGPoint(x: b.midX, y: b.midY)
    play.frame = CGRect(x: b.midX - 35, y: b.midY - 35, width: 70, height: 70)
    textView.frame = b
    cardStack.frame = CGRect(x: 30, y: b.midY - 180, width: b.width - 60, height: 360)
    guard zoomer.zoomScale == 1 else { return }
    if mode == "image" {
      content.frame = CGRect(origin: .zero, size: b.size)
      imageView.frame = content.bounds
      zoomer.contentSize = b.size
    } else if mode == "pages" {
      let w = b.width - 24
      let h = pagesStack.systemLayoutSizeFitting(CGSize(width: w, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
      // (pages that fit on the screen sit in its middle, as a photo does — a wide banner was stuck at the top: Haris
      //  2026-11-02; longer ones scroll from under the top bar)
      let fits = h + 220 <= b.height
      content.frame = CGRect(x: 0, y: 0, width: b.width, height: fits ? b.height : h + 220)
      pagesStack.frame = CGRect(x: 12, y: fits ? (b.height - h) / 2 : 110, width: w, height: h)
      zoomer.contentSize = content.frame.size
    }
  }
  // (a video zooms as a photo does, playing or paused — its player is inside the picture; ▶ / ⏸ stays in the middle at its own
  //  size: as E11 Talk's, Haris 2026-11-18 21:47)
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { mode == "image" || mode == "pages" ? content : nil }
  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    // (a zoomed-out picture stays in the middle)
    let b = scrollView.bounds.size, c = content.frame.size
    content.center = CGPoint(x: max(c.width, b.width) / 2, y: mode == "image" ? max(c.height, b.height) / 2 : c.height / 2)
  }
  @objc private func doubleTap(_ g: UITapGestureRecognizer) {
    guard mode == "image" || mode == "pages" else { return }
    if zoomer.zoomScale > 1 { zoomer.setZoomScale(1, animated: true); return }
    let p = g.location(in: content), s: CGFloat = 2.5
    let w = zoomer.bounds.width / s, h = zoomer.bounds.height / s
    zoomer.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
  }
  var isZoomed: Bool { zoomer.zoomScale > 1.01 }
  var atTop: Bool { mode != "pages" || zoomer.contentOffset.y <= 1 }
  override func prepareForReuse() { super.prepareForReuse(); token += 1 }
}

/* ---------- the preview ---------- */
final class PreviewVC: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
  /* (Haris 2026-11-15: "keep the buttons as Console's, but copy the same preview from Talk" — E11 Talk's PhotoViewerVC:
     its strip, its pull down where the picture follows the finger, its flights in and out, its timings; Console's own
     buttons — ‹ · ••• · Copy Link · Download — and its PDFs, documents and text inside it) */
  private var files: [[String: Any]]
  private var at: Int
  private let event: ([String: Any]) -> Void
  private var pages: [String: ([String], String?)] = [:]
  private let pager: UICollectionView
  // (E11 Talk's strip, as it is: a sliding row of small pictures, 26 × 36, 3 apart — the one on show with a white edge)
  private let strip = UIScrollView(), stripRow = UIStackView()
  private var stripPlaced = false
  // (as E11 Talk's photo viewer — Haris 2026-11-15: "the preview same as Talk's, with glass buttons"): black, ‹ · the
  //  file's name and its line · ••• at the top on a soft shade; the strip and Copy Link · Download as Apple's glass at the
  //  foot on the same shade turned upside down; a tap hides and shows them)
  private let topBar = UIView(), bottomBar = UIView(), topShade = Shade(), footShade = Shade()
  private let closeB = UIButton(type: .system), moreB = UIButton(type: .system)
  private let name = UILabel(), details = UILabel()
  private let copyB = UIButton(type: .system), dlB = UIButton(type: .system)
  // a video's time played · seek bar · its length, above the strip (E11 Talk's, as it is — Haris 2026-11-23); others: not there
  private let seek = UIView(), played = UILabel(), length = UILabel(), bar = UISlider()
  private var seekH: NSLayoutConstraint!, ticks: Any?, ticking: AVPlayer?, dragging = false
  // (false while the picture flies out — a video waits for it to land before it plays)
  private var landed = true
  final class Shade: UIView { override class var layerClass: AnyClass { CAGradientLayer.self } }
  // the picture the file was opened from (its own small picture on the page): the preview flies out of it and back into it
  weak var source: UIImageView?
  // (each file's mark, in the preview's order — FileTouch.key)
  var keys: [String] = []
  private var openedAt = -1
  var flies: Bool {
    guard let s = source, s.window != nil, s.image != nil, at < files.count else { return false }
    let k = files[at]["kind"] as? String ?? ""
    return k == "image" || (k == "video" && !((files[at]["cover"] as? String) ?? "").isEmpty)
  }
  private let toast = UILabel()
  // (how far up the foot reaches: the downloads' bar sits just above it — Haris 2026-11-21)
  var footHeight: CGFloat { view.bounds.height - bottomBar.frame.minY }
  private var barsHidden = false
  private var closed = false
  // (the self-test's reading — ios/walktest.py --apple: how it opened and, once closed, how it went)
  static var lastClose = ""
  var walkInfo: [String: Any] { ["shown": true, "source": source != nil, "sourceWindow": source?.window != nil, "openedAt": openedAt, "at": at, "key": keys[safe: at] ?? "", "flies": flies,
                                 "src": (files[safe: at]?["src"] as? String) ?? "", "name": (files[safe: at]?["name"] as? String) ?? "", "kind": (files[safe: at]?["kind"] as? String) ?? ""] }
  private var pull: UIPanGestureRecognizer?

  init(_ a: [String: Any], event: @escaping ([String: Any]) -> Void) {
    files = a["files"] as? [[String: Any]] ?? []
    at = max(0, min(files.count - 1, (a["at"] as? NSNumber)?.intValue ?? 0))
    self.event = event
    let pl = UICollectionViewFlowLayout(); pl.scrollDirection = .horizontal; pl.minimumLineSpacing = 0
    pager = UICollectionView(frame: .zero, collectionViewLayout: pl)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
    modalPresentationCapturesStatusBarAppearance = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override var prefersStatusBarHidden: Bool { barsHidden }
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    pager.backgroundColor = .clear
    pager.isPagingEnabled = true
    pager.showsHorizontalScrollIndicator = false
    pager.contentInsetAdjustmentBehavior = .never
    // (Apple's shade under the status bar off — the top has its own soft shade; both showed, two shadows: Haris 2026-11-15)
    if #available(iOS 26.0, *) { pager.topEdgeEffect.isHidden = true; pager.bottomEdgeEffect.isHidden = true; strip.topEdgeEffect.isHidden = true; strip.bottomEdgeEffect.isHidden = true; strip.leftEdgeEffect.isHidden = true; strip.rightEdgeEffect.isHidden = true }
    pager.dataSource = self; pager.delegate = self
    pager.register(PreviewCell.self, forCellWithReuseIdentifier: PreviewCell.id)
    pager.frame = view.bounds; pager.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(pager)
    // the top: ‹ · the name and its line · ••• (Apple's own glass, as Talk's viewer; before iOS 26 the grey capsule)
    func glass(_ b: UIButton, _ sym: String, _ label: String, size: CGFloat = 42, red: Bool = false) {
      var c: UIButton.Configuration
      if #available(iOS 26.0, *) { c = .glass() } else { c = .gray(); c.cornerStyle = .capsule; c.baseForegroundColor = .white; c.background.backgroundColor = UIColor(white: 0.16, alpha: 0.8) }
      // (the icon at Apple's own size and weight, as Photos — 15 regular in the 42 circle; it was 17 semibold, tight: Haris 2026-11-21 19:38)
      c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: size > 44 ? 20 : 15, weight: .regular)); c.contentInsets = .zero
      if red { c.baseForegroundColor = .systemRed }
      b.configuration = c; b.accessibilityLabel = label; b.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: size), b.heightAnchor.constraint(equalToConstant: size)])
    }
    glass(closeB, "chevron.left", "Back"); glass(moreB, "ellipsis", "More")
    closeB.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
    moreB.addAction(UIAction { [weak self] _ in self?.send("more") }, for: .touchUpInside)
    name.font = .systemFont(ofSize: 17, weight: .semibold); name.textColor = .white; name.textAlignment = .center; name.lineBreakMode = .byTruncatingMiddle
    details.font = .systemFont(ofSize: 13); details.textColor = UIColor(white: 0.62, alpha: 1); details.textAlignment = .center
    let names = UIStackView(arrangedSubviews: [name, details]); names.axis = .vertical; names.alignment = .center
    [closeB, names, moreB].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; topBar.addSubview($0) }
    // the foot: the strip · Copy Link and Download (Talk's Share / Delete places, each Apple's own glass)
    strip.showsHorizontalScrollIndicator = false
    stripRow.axis = .horizontal; stripRow.spacing = 3; stripRow.alignment = .center
    buildStrip()
    stripRow.translatesAutoresizingMaskIntoConstraints = false; strip.addSubview(stripRow)
    strip.isHidden = files.count < 2
    // (the same size as the top's ‹ and ••• — Haris 2026-11-15)
    // (Copy Link as two pages — option C; Share as Talk's — Haris 2026-11-21)
    glass(copyB, "doc.on.doc", "Copy Link"); glass(dlB, "square.and.arrow.up", "Share")
    copyB.addAction(UIAction { [weak self] _ in self?.send("copy") }, for: .touchUpInside)   // (its words when the link is on the clipboard)
    dlB.addAction(UIAction { [weak self] _ in self?.send("dl") }, for: .touchUpInside)
    let tools = UIStackView(arrangedSubviews: [copyB, dlB]); tools.axis = .horizontal; tools.distribution = .equalSpacing; tools.alignment = .center
    for l in [played, length] { l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium); l.textColor = .white; l.translatesAutoresizingMaskIntoConstraints = false; seek.addSubview(l) }
    played.text = "0:00"; length.textAlignment = .right
    bar.minimumTrackTintColor = .white; bar.maximumTrackTintColor = UIColor(white: 1, alpha: 0.3)
    let knob = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14)).image { _ in UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 14, height: 14)).fill() }
    bar.setThumbImage(knob, for: .normal); bar.setThumbImage(knob, for: .highlighted)
    bar.translatesAutoresizingMaskIntoConstraints = false; seek.addSubview(bar); seek.clipsToBounds = true
    bar.addAction(UIAction { [weak self] _ in guard let self else { return }; self.dragging = true; self.current?.scrubBegin() }, for: .touchDown)
    // (only while the finger is on the bar: iPhone's slider sends "value changed" again after the finger is lifted, and each one
    //  jumped the video back to where the knob sat — the first frames twice after dragging to the start; measured in the
    //  simulator with the same slider, Haris 2026-11-23 13:25)
    bar.addAction(UIAction { [weak self] _ in guard let self, self.dragging else { return }; self.played.text = PreviewVC.clock(Double(self.bar.value)); self.current?.scrub(to: Double(self.bar.value)) }, for: .valueChanged)
    bar.addAction(UIAction { [weak self] _ in guard let self else { return }; self.dragging = false; self.current?.scrubEnd() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    NSLayoutConstraint.activate([
      played.leadingAnchor.constraint(equalTo: seek.leadingAnchor, constant: 18), played.centerYAnchor.constraint(equalTo: seek.centerYAnchor), played.widthAnchor.constraint(equalToConstant: 44),
      length.trailingAnchor.constraint(equalTo: seek.trailingAnchor, constant: -18), length.centerYAnchor.constraint(equalTo: seek.centerYAnchor), length.widthAnchor.constraint(equalToConstant: 44),
      bar.leadingAnchor.constraint(equalTo: played.trailingAnchor, constant: 8), bar.trailingAnchor.constraint(equalTo: length.leadingAnchor, constant: -8), bar.centerYAnchor.constraint(equalTo: seek.centerYAnchor),
    ])
    seek.isHidden = true
    [seek, strip, tools].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; bottomBar.addSubview($0) }
    for bar in [topBar, bottomBar] { bar.translatesAutoresizingMaskIntoConstraints = false; bar.clipsToBounds = false; view.addSubview(bar) }
    // (the soft shades under the buttons, Talk's: coming and going with them)
    let g0 = topShade.layer as! CAGradientLayer
    g0.colors = [UIColor(white: 0, alpha: 0.5).cgColor, UIColor(white: 0, alpha: 0.18).cgColor, UIColor.clear.cgColor]; g0.locations = [0, 0.55, 1]
    topShade.isUserInteractionEnabled = false; topBar.insertSubview(topShade, at: 0)
    let g1 = footShade.layer as! CAGradientLayer
    g1.colors = g0.colors?.reversed(); g1.locations = [0, 0.45, 1]
    footShade.isUserInteractionEnabled = false; bottomBar.insertSubview(footShade, at: 0)
    toast.font = .systemFont(ofSize: 14, weight: .medium); toast.textColor = .white; toast.textAlignment = .center
    toast.backgroundColor = UIColor.black.withAlphaComponent(0.78); toast.layer.cornerRadius = 18; toast.clipsToBounds = true
    toast.alpha = 0; toast.numberOfLines = 2
    toast.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(toast)
    let g = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      topBar.topAnchor.constraint(equalTo: g.topAnchor), topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), topBar.heightAnchor.constraint(equalToConstant: 58),
      closeB.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16), closeB.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      moreB.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16), moreB.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      names.centerXAnchor.constraint(equalTo: topBar.centerXAnchor), names.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      names.leadingAnchor.constraint(greaterThanOrEqualTo: closeB.trailingAnchor, constant: 8), names.trailingAnchor.constraint(lessThanOrEqualTo: moreB.leadingAnchor, constant: -8),
      bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bottomBar.bottomAnchor.constraint(equalTo: g.bottomAnchor),
      seek.topAnchor.constraint(equalTo: bottomBar.topAnchor), seek.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor), seek.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
      strip.topAnchor.constraint(equalTo: seek.bottomAnchor), strip.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor), strip.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor), strip.heightAnchor.constraint(equalToConstant: 40),
      stripRow.centerYAnchor.constraint(equalTo: strip.centerYAnchor), stripRow.leadingAnchor.constraint(equalTo: strip.contentLayoutGuide.leadingAnchor, constant: 14),
      stripRow.trailingAnchor.constraint(equalTo: strip.contentLayoutGuide.trailingAnchor, constant: -14), stripRow.topAnchor.constraint(equalTo: strip.contentLayoutGuide.topAnchor, constant: 2),
      tools.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 10), tools.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 34), tools.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -34),
      tools.heightAnchor.constraint(equalToConstant: 42), tools.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -4),
      toast.centerXAnchor.constraint(equalTo: view.centerXAnchor), toast.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14),
      toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48), toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
    ])
    seekH = seek.heightAnchor.constraint(equalToConstant: 0); seekH.isActive = true
    // tap: hide / show the bars; pull down: close
    let tap = UITapGestureRecognizer(target: self, action: #selector(toggleBars))
    tap.delegate = self
    pager.addGestureRecognizer(tap)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(pulled(_:)))
    pan.delegate = self
    view.addGestureRecognizer(pan)
    pull = pan
  }
  // (the one on show always in the strip's middle, as Photos — Haris 2026-11-15: room at both ends, so the first and the
  //  last can come to the middle too)
  private func centreStrip() {
    let pad = max(0, strip.bounds.width / 2 - 27)
    guard abs(strip.contentInset.left - pad) > 0.5 else { return }
    strip.contentInset = UIEdgeInsets(top: 0, left: pad, bottom: 0, right: pad)
    if stripPlaced { placeStrip(animated: false) }
  }
  private func placeStrip(animated: Bool) {
    guard let b = stripRow.arrangedSubviews[safe: at] else { return }
    strip.setContentOffset(CGPoint(x: stripRow.frame.minX + b.frame.midX - strip.bounds.width / 2, y: 0), animated: animated)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    centreStrip()
    if let l = pager.collectionViewLayout as? UICollectionViewFlowLayout, l.itemSize != view.bounds.size { l.itemSize = view.bounds.size; l.invalidateLayout() }
    topShade.frame = CGRect(x: 0, y: -topBar.frame.minY, width: view.bounds.width, height: topBar.frame.maxY + 30)
    footShade.frame = CGRect(x: 0, y: -30, width: view.bounds.width, height: view.bounds.height - bottomBar.frame.minY + 30)
    toast.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
  }
  // opening: the picture flies from where it was tapped to its place, the black and the buttons coming in with it, the page
  // fading in over it once it has landed (E11 Talk's "Opening a photo" — Haris 2026-11-15)
  var startImage: UIImage?   // (the best picture of the opened file already on the phone — set by whoever opens it)
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    guard flies, let src = source, var img = src.image else { return }
    // (a photo the phone has already: it flies out sharp, and the page under it is the same picture — it flew out small and
    //  turned sharp as it landed, every time: Haris 2026-11-19 11:15)
    if at < files.count, (files[at]["kind"] as? String) == "image", let full = PreviewLoad.ready(files[at]["src"] as? String) { startImage = full }
    // (the best picture of it the phone already holds, in its own shape: a Recently added or search row's picture is a small
    //  square cut, and it flew out as a big blurry square before the file came — Haris 2026-11-17 09:38)
    if let better = startImage,
       better.size.width * better.scale > img.size.width * img.scale * 1.3 || abs(better.size.width / max(1, better.size.height) - img.size.width / max(1, img.size.height)) > 0.05 { img = better }
    openedAt = at
    view.layoutIfNeeded()
    let fly = UIImageView(image: img); fly.contentMode = .scaleAspectFill; fly.clipsToBounds = true
    fly.layer.cornerRadius = src.layer.cornerRadius; fly.layer.cornerCurve = src.layer.cornerCurve
    fly.frame = src.convert(src.bounds, to: nil)
    view.insertSubview(fly, aboveSubview: pager)
    pager.alpha = 0; topBar.alpha = 0; bottomBar.alpha = 0; view.backgroundColor = .clear; src.alpha = 0
    setLanded(false)
    let to = AVMakeRect(aspectRatio: img.size, insideRect: view.bounds)
    UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0) {
      fly.frame = to; fly.layer.cornerRadius = 0; self.view.backgroundColor = .black; self.topBar.alpha = 1; self.bottomBar.alpha = 1
    } completion: { _ in
      self.setLanded(true)
      UIView.animate(withDuration: 0.18, animations: { self.pager.alpha = 1 }) { _ in fly.removeFromSuperview(); src.alpha = 1 }
    }
  }
  private func setLanded(_ on: Bool) { landed = on; for c in pager.visibleCells { (c as? PreviewCell)?.landed = on } }
  private var placed = false
  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    if !placed && view.bounds.width > 0 {
      placed = true
      pager.layoutIfNeeded()
      pager.scrollToItem(at: IndexPath(item: at, section: 0), at: .left, animated: false)
      pager.layoutIfNeeded()   // (the cell on show made now — a video readied while the preview opens)
      refreshBars()
    }
  }
  private func send(_ ev: String) {
    guard at < files.count, let id = files[at]["id"] as? String else { return }
    event(["ev": ev, "id": id])
  }
  // the strip's pictures (Talk's): each a small button, its own small picture (or its kind's letters till it comes)
  private func buildStrip() {
    stripRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (i, f) in files.enumerated() {
      let b = UIButton(type: .custom); b.tag = i; b.imageView?.contentMode = .scaleAspectFill; b.clipsToBounds = true; b.layer.cornerRadius = 4
      b.backgroundColor = UIColor(white: 0.2, alpha: 1)
      b.setTitle(((f["ext"] as? String) ?? "").uppercased(), for: .normal); b.titleLabel?.font = .systemFont(ofSize: 7, weight: .bold); b.setTitleColor(UIColor(white: 1, alpha: 0.6), for: .normal)
      b.widthAnchor.constraint(equalToConstant: 26).isActive = true; b.heightAnchor.constraint(equalToConstant: 36).isActive = true
      b.addAction(UIAction { [weak self] a in guard let t = (a.sender as? UIView)?.tag else { return }; self?.go(t) }, for: .touchUpInside)
      PreviewLoad.image([f["thumb"] as? String, f["cover"] as? String].compactMap { $0 }.first { !$0.isEmpty }) { [weak b] img in
        guard let b = b, let img = img else { return }
        b.setTitle(nil, for: .normal); b.setImage(img, for: .normal)
      }
      stripRow.addArrangedSubview(b)
    }
  }
  private func go(_ i: Int) {
    guard i != at, i >= 0, i < files.count else { return }
    at = i
    pager.scrollToItem(at: IndexPath(item: i, section: 0), at: .left, animated: false)
    refreshBars()
  }
  // the one on show plays (a video), the others pause
  private func playCurrent() {
    for c in pager.visibleCells {
      guard let pc = c as? PreviewCell, let ip = pager.indexPath(for: pc) else { continue }
      if ip.item == at { if appeared { pc.start() } else { pc.prepare() } } else { pc.stop() }
    }
    let video = at < files.count && (files[at]["kind"] as? String) == "video"
    let h: CGFloat = video ? 34 : 0
    if let sh = seekH, sh.constant != h {
      sh.constant = h
      // (the foot grew or shrank: the downloads' bar above it placed again)
      if appeared { DispatchQueue.main.async { self.view.layoutIfNeeded(); NotificationCenter.default.post(name: PreviewVC.cameOrWent, object: nil) } }
    }
    seek.isHidden = !video
    follow(video ? current : nil)
  }
  // the seek row follows the video on show: its length, and where it is, ten times a second (E11 Talk's)
  private func follow(_ pc: PreviewCell?) {
    if let o = ticks, let p = ticking { p.removeTimeObserver(o) }
    ticks = nil; ticking = nil
    let p = pc?.avPlayer
    var len = 0.0
    if let d = p?.currentItem?.duration, d.isNumeric, d.seconds > 0 { len = d.seconds }
    bar.minimumValue = 0; bar.maximumValue = Float(max(len, 0.1))
    length.text = PreviewVC.clock(len)
    let now = p.map { $0.currentTime().seconds } ?? 0
    if !dragging { bar.value = Float(now.isFinite ? now : 0); played.text = PreviewVC.clock(now.isFinite ? now : 0) }
    guard let pl = p else { return }
    ticking = pl
    ticks = pl.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
      guard let self, !self.dragging else { return }
      if let d = pl.currentItem?.duration, d.isNumeric, d.seconds > 0, abs(Double(self.bar.maximumValue) - d.seconds) > 0.05 {
        self.bar.maximumValue = Float(d.seconds); self.length.text = PreviewVC.clock(d.seconds)
      }
      self.bar.value = Float(t.seconds); self.played.text = PreviewVC.clock(t.seconds)
    }
  }
  static func clock(_ s: Double) -> String { let n = Int((s.isFinite ? s : 0).rounded(.down)); return String(format: "%d:%02d", n / 60, n % 60) }
  private var appeared = false
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); appeared = true; playCurrent(); NotificationCenter.default.post(name: PreviewVC.cameOrWent, object: nil) }
  override func viewDidDisappear(_ a: Bool) { super.viewDidDisappear(a); NotificationCenter.default.post(name: PreviewVC.cameOrWent, object: nil) }
  static let cameOrWent = Notification.Name("PreviewVC.cameOrWent")
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); for c in pager.visibleCells { (c as? PreviewCell)?.stop() }; follow(nil) }
  private func refreshBars() {
    guard at < files.count else { return }
    playCurrent()
    let f = files[at]
    name.text = f["name"] as? String
    details.text = f["meta"] as? String
    // (Talk's: the one on show its white edge; the strip centred on it — in place as the preview opens, sliding only when
    //  you move between files)
    for (i, b) in stripRow.arrangedSubviews.enumerated() { b.layer.borderWidth = i == at ? 1.5 : 0; b.layer.borderColor = UIColor.white.cgColor }
    if let b = stripRow.arrangedSubviews[safe: at], files.count > 1 {
      if !stripPlaced { view.layoutIfNeeded() } else { strip.layoutIfNeeded() }
      centreStrip()
      placeStrip(animated: stripPlaced)
      stripPlaced = true
    }
    event(["ev": "at", "id": f["id"] as? String ?? ""])
  }
  // (E11 Talk's note: its look, its timing, centred just above the foot — the old one sat off-centre, Haris 2026-11-21 19:23)
  private var shownNote: UILabel?
  func flash(_ s: String) {
    shownNote?.removeFromSuperview()
    let l = PaddedLabel(); l.insets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    l.text = s; l.font = .systemFont(ofSize: 15, weight: .medium); l.textColor = .label; l.numberOfLines = 2; l.textAlignment = .center
    l.backgroundColor = .secondarySystemGroupedBackground; l.layer.cornerRadius = 14; l.layer.masksToBounds = true
    l.overrideUserInterfaceStyle = .dark   // (the viewer is black in light and dark alike)
    let W = view.bounds.width
    let w = min(W - 48, l.sizeThatFits(CGSize(width: W - 48, height: 80)).width)
    let h = l.sizeThatFits(CGSize(width: w, height: 80)).height + 20
    l.frame = CGRect(x: (W - w) / 2, y: bottomBar.frame.minY - 12 - h, width: w, height: h)
    l.alpha = 0; view.addSubview(l); shownNote = l
    UIView.animate(withDuration: 0.18) { l.alpha = 1 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { UIView.animate(withDuration: 0.2, animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() } }
  }

  /* ---------- from the page ---------- */
  func set(_ a: [String: Any]) {
    if let id = a["id"] as? String, let urls = a["pages"] as? [String] {
      pages[id] = (urls, a["note"] as? String)
      for c in pager.visibleCells { if let pc = c as? PreviewCell, let ip = pager.indexPath(for: pc), ip.item < files.count, (files[ip.item]["id"] as? String) == id { pc.setPages(urls, note: a["note"] as? String) } }
    }
    if let gone = a["remove"] as? String, let i = files.firstIndex(where: { ($0["id"] as? String) == gone }) {
      files.remove(at: i)
      if files.isEmpty { return close() }
      at = min(at, files.count - 1)
      pager.reloadData(); buildStrip(); strip.isHidden = files.count < 2
      pager.layoutIfNeeded(); pager.scrollToItem(at: IndexPath(item: at, section: 0), at: .left, animated: false)
      refreshBars()
    }
    if let rows = a["info"] as? [[String]] {
      let al = UIAlertController(title: "File info", message: rows.map { "\($0.first ?? ""): \($0.last ?? "")" }.joined(separator: "\n"), preferredStyle: .alert)
      al.addAction(UIAlertAction(title: "Done", style: .default))
      (presentedViewController ?? self).present(al, animated: true)
    }
    if (a["close"] as? Bool) == true { close() }
    if let msg = a["toast"] as? String { flash(msg) }
  }
  func close() {
    guard !closed else { return }
    closed = true
    event(["ev": "closed"])
    // (the one it was opened on, its picture there: back into the picture it came out of — the black and the buttons going
    //  with it; else the fade as before)
    // (swiped to another file: back into that file's own picture on the page when it's there — Haris 2026-11-15)
    // (opened by a link from another app: no picture found as it opened — the folder behind still coming in — so it's looked
    //  for now, by the file's mark, as a swiped-to one: it faded instead of flying home, Haris 2026-11-16)
    let back = homePicture()
    // (opened without flying — by a link — but its picture is on the page now: back into it all the same)
    PreviewVC.lastClose = "back:\(back != nil) window:\(back?.window != nil) picture:\(current?.shownPicture != nil) openedAt:\(openedAt) source:\(source != nil)"
    if openedAt >= 0 || source == nil, let src = back, src.window != nil, let (pic, from) = current?.shownPicture {
      if pullHome !== src { pullHome?.alpha = 1 }
      let fly = UIImageView(image: pic); fly.contentMode = .scaleAspectFill; fly.clipsToBounds = true; fly.layer.cornerCurve = src.layer.cornerCurve
      fly.frame = from
      view.insertSubview(fly, aboveSubview: pager); pager.alpha = 0; src.alpha = 0
      let to = src.convert(src.bounds, to: nil), radius = src.layer.cornerRadius
      UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
        fly.frame = to; fly.layer.cornerRadius = radius; self.view.backgroundColor = .clear; self.topBar.alpha = 0; self.bottomBar.alpha = 0; self.toast.alpha = 0; self.shownNote?.alpha = 0
      } completion: { _ in
        src.alpha = 1
        if let p = self.presentingViewController { p.dismiss(animated: false) } else { self.dismiss(animated: false) }
      }
      return
    }
    pullHome?.alpha = 1   // (no flight after all: the picture hidden as it was pulled shown again)
    UIView.animate(withDuration: 0.2, animations: { self.view.alpha = 0 }) { _ in
      if let p = self.presentingViewController { p.dismiss(animated: false) } else { self.dismiss(animated: false) }
    }
  }

  /* ---------- the pages and the strip ---------- */
  func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { files.count }
  func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
    let f = files[ip.item]
    let c = cv.dequeueReusableCell(withReuseIdentifier: PreviewCell.id, for: ip) as! PreviewCell
    c.onPlay = { [weak self] f in self?.playMedia(f) }
    c.onPlaying = { [weak self] in if self?.barsHidden == false { self?.toggleBars() } }
    c.chrome = !barsHidden
    c.landed = landed
    c.onPlayer = { [weak self, weak c] in guard let self, let c, self.current === c else { return }; self.follow(c) }
    c.barsShown = { [weak self] in self.map { !$0.barsHidden && !$0.closed } ?? false }
    c.onPages = { [weak self, weak c] id in
      guard let self else { return }
      if let p = self.pages[id] { c?.setPages(p.0, note: p.1) } else {
        self.event(["ev": "pages", "id": id])
        // (pages the phone kept come back at once, while this cell is still being made — not yet on screen, so set() didn't
        //  reach it and an Office file sat on the spinner from its second opening on: Haris 2026-11-21 00:05)
        if let p = self.pages[id] { c?.setPages(p.0, note: p.1) }
      }
    }
    c.show(f)
    if let tap = (pager.gestureRecognizers ?? []).first(where: { $0 is UITapGestureRecognizer && ($0 as! UITapGestureRecognizer).numberOfTapsRequired == 1 }) as? UITapGestureRecognizer, let dbl = c.doubleTapGesture { tap.require(toFail: dbl) }
    return c
  }
  func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt ip: IndexPath) -> CGSize { view.bounds.size }
  func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
    guard sv === pager else { return }
    let n = Int((sv.contentOffset.x / max(1, sv.bounds.width)).rounded())
    if n != at, n >= 0, n < files.count { at = n; UISelectionFeedbackGenerator().selectionChanged(); refreshBars() }
  }

  /* ---------- playing a video or a sound: Apple's own player ---------- */
  private func playMedia(_ f: [String: Any]) {
    guard let s = f["src"] as? String, let url0 = URL(string: s) else { return }
    // (kept on the phone after the first time: played again — even after the app restarts — from the phone at once;
    //  Haris 2026-11-06)
    let kept = MediaKeep.local(s)
    if kept == nil { MediaKeep.fetch(s) }
    let url = kept ?? url0
    let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: PreviewLoad.cookies.filter { c in
      let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
      return (url.host ?? "") == d || (url.host ?? "").hasSuffix("." + d)
    }])
    let p = AVPlayerViewController()
    p.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    present(p, animated: true) { p.player?.play() }
  }

  /* ---------- tap, pull down ---------- */
  @objc private func toggleBars() {
    barsHidden.toggle()
    for c in pager.subviews.compactMap({ $0 as? PreviewCell }) { c.chrome = !barsHidden }
    UIView.animate(withDuration: 0.2) {
      self.topBar.alpha = self.barsHidden ? 0 : 1
      self.bottomBar.alpha = self.barsHidden ? 0 : 1
      self.setNeedsStatusBarAppearanceUpdate()
    }
  }
  private var current: PreviewCell? { pager.visibleCells.compactMap { $0 as? PreviewCell }.first { pager.indexPath(for: $0)?.item == at } }
  // ---------- pulled down (Talk's): the picture follows the finger, the black and the buttons fade; far enough — back into
  // the picture it came out of ----------
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g === pull, let p = pull else { return true }
    if let c = current, c.isZoomed || !c.atTop { return false }
    let v = p.velocity(in: view)
    return v.y > abs(v.x) * 1.2
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { g !== pull }
  // the picture on the page it flies back into: the one it came out of, else the file's own by its mark
  private func homePicture() -> UIImageView? {
    let win = source?.window ?? presentingViewController?.view.window ?? view.window
    return (at == openedAt ? source : nil) ?? keys[safe: at].flatMap { FileTouch.marked($0, in: win) }
  }
  private weak var pullHome: UIImageView?
  @objc private func pulled(_ g: UIPanGestureRecognizer) {
    guard let page = current else { return }
    let t = g.translation(in: view), k = max(0, min(1, t.y / 400)), v = page.dragView
    switch g.state {
    case .began:
      // (its spot on the page empty from the moment it's pulled, as Photos — it showed behind while pulling, then went as
      //  the flight began and came back as it landed: Haris 2026-11-16)
      if openedAt >= 0 || source == nil, let h = homePicture(), h.window != nil, current?.shownPicture != nil { h.alpha = 0; pullHome = h }
    case .changed:
      v.transform = CGAffineTransform(translationX: t.x, y: t.y).scaledBy(x: 1 - k * 0.3, y: 1 - k * 0.3)
      view.backgroundColor = UIColor.black.withAlphaComponent(1 - k)
      topBar.alpha = barsHidden ? 0 : max(0, 1 - k * 3); bottomBar.alpha = topBar.alpha
    case .ended, .cancelled:
      if t.y > 110 || g.velocity(in: view).y > 900 { close(); return }
      UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
        v.transform = .identity; self.view.backgroundColor = .black
        self.topBar.alpha = self.barsHidden ? 0 : 1; self.bottomBar.alpha = self.topBar.alpha
      } completion: { _ in self.pullHome?.alpha = 1; self.pullHome = nil }   // (let go short: back on the page, behind the black)
    default: break
    }
  }
}

extension PreviewVC {
  // (self-test: a picture-less card and a page file, so the bars and the strip can be seen)
  static func selfArgs() -> [String: Any] {
    let f1: [String: Any] = ["id": "s1", "name": "Spring launch brief.pdf", "kind": "other", "ext": "pdf", "meta": "1.2 MB · Sara · 2h ago"]
    let f2: [String: Any] = ["id": "s2", "name": "Logo lockup.ai", "kind": "other", "ext": "ai", "meta": "4.8 MB · Omar · yesterday"]
    let f3: [String: Any] = ["id": "s3", "name": "Moodboard.zip", "kind": "other", "ext": "zip", "meta": "22 MB · Areej · Oct 28"]
    return ["files": [f1, f2, f3], "at": 1]
  }
}

/* Videos and sounds opened in the preview, kept on the phone (Haris 2026-11-06: "files opening on preview are being loaded
   every time — they should stay in phone's data for fast preview"): the first play streams as before while the file is
   saved in the background (its light copy for a video, up to 300 MB); after that it plays from the phone. Kept in the
   app's caches (iPhone may clear them when it's short of space), at most 2 GB — the oldest go first. */
enum MediaKeep {
  private static let dir: URL = {
    let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("media", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }()
  private static var busy = Set<String>()
  private static func file(_ s: String) -> URL {
    let ext = (URL(string: s)?.pathExtension.lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "mp4"
    return dir.appendingPathComponent(SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() + "." + ext)
  }
  static func local(_ s: String) -> URL? {
    let f = file(s)
    guard FileManager.default.fileExists(atPath: f.path) else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: f.path)   // (recently played: kept longest)
    return f
  }
  static func fetch(_ s: String) {
    guard let url = URL(string: s), !busy.contains(s) else { return }
    busy.insert(s)
    var r = URLRequest(url: url); r.allHTTPHeaderFields = PreviewLoad.headers(url)
    URLSession.shared.downloadTask(with: r) { tmp, resp, err in
      defer { DispatchQueue.main.async { busy.remove(s) } }
      guard err == nil, let tmp = tmp, ((resp as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2,
            let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? NSNumber)?.intValue, size > 0, size <= 300_000_000,
            (resp?.expectedContentLength ?? -1) <= 0 || Int64(size) == resp?.expectedContentLength || ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding") ?? "identity").lowercased() != "identity" else { return }   // (kept only whole)
      let f = file(s)
      try? FileManager.default.removeItem(at: f)
      try? FileManager.default.moveItem(at: tmp, to: f)
      trim()
    }.resume()
  }
  // (signing out, or someone else starting here: none of the one before's left — Haris 2026-11-11)
  static func clear() {
    DispatchQueue.global(qos: .utility).async {
      let fm = FileManager.default
      for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: u) }
    }
  }
  // (at most 2 GB: the least recently played go first)
  private static func trim() {
    let fm = FileManager.default
    guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
    var items = list.compactMap { u -> (URL, Int, Date)? in
      guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
      return (u, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
    }
    var total = items.reduce(0) { $0 + $1.1 }
    items.sort { $0.2 < $1.2 }
    while total > 2_000_000_000, let first = items.first { try? fm.removeItem(at: first.0); total -= first.1; items.removeFirst() }
  }
}


/* Where the last finger came down, anywhere in the app (a recogniser that only looks and never takes the touch — it fails at
   once): the file preview flies out of the picture that was tapped, as E11 Talk's (Haris 2026-11-15). */
final class FileTouch: UIGestureRecognizer {
  private static weak var view: UIView?
  private static var point: CGPoint = .zero, at = Date.distantPast
  // (the self-test's finger: the touch a real tap would leave — on the row's picture, at its middle)
  static func note(_ cell: UIView?) {
    guard let c = cell else { return }
    var ivs: [UIImageView] = []; func walk(_ v: UIView) { if let iv = v as? UIImageView { ivs.append(iv) }; v.subviews.forEach(walk) }; walk(c)
    let v: UIView = ivs.first { $0.image != nil } ?? c
    view = v; point = v.convert(CGPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil); at = Date()
  }
  static func watch(_ w: UIWindow) {
    let g = FileTouch(target: nil, action: nil); g.cancelsTouchesInView = false; g.delaysTouchesBegan = false; g.delaysTouchesEnded = false
    w.addGestureRecognizer(g)
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    if let t = touches.first { FileTouch.view = t.view; FileTouch.point = t.location(in: nil); FileTouch.at = Date() }
    state = .failed
  }
  override func canPrevent(_ g: UIGestureRecognizer) -> Bool { false }
  override func canBePrevented(by g: UIGestureRecognizer) -> Bool { false }
  // each file's own small picture on a page, marked with the file it shows (as E11 Talk's chat knows each message's
  // picture): swiped to another file, the preview flies back into that file's picture by its mark — never guessed from
  // the pictures' places (it guessed, and faded whenever the row or grid didn't hold exactly the preview's files)
  private static var markKey = 0
  static func key(_ f: [String: Any]) -> String {
    for k in ["id", "file", "path"] { if let v = f[k] as? String, !v.isEmpty { return v } }
    return ""
  }
  static func mark(_ iv: UIImageView, _ f: [String: Any]) { objc_setAssociatedObject(iv, &markKey, key(f), .OBJC_ASSOCIATION_COPY_NONATOMIC) }
  // (an Apple list cell's picture marked with the file it shows, the others in it cleared — a reused cell carries no old mark:
  //  Recently added, search's files and Overview's latest fly out of and back into their row's picture, as a task's files —
  //  Haris 2026-11-17 08:34)
  static func markCell(_ cell: UIView, _ f: [String: Any]?) {
    var ivs: [UIImageView] = []
    func walk(_ v: UIView) { if let iv = v as? UIImageView { ivs.append(iv) }; v.subviews.forEach(walk) }
    walk(cell)
    for iv in ivs { objc_setAssociatedObject(iv, &markKey, nil, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    if let f = f, let iv = ivs.first(where: { $0.image != nil && $0.bounds.width >= 20 }) ?? ivs.first(where: { $0.image != nil }) { mark(iv, f) }
  }
  static func markOf(_ iv: UIImageView) -> String? { objc_getAssociatedObject(iv, &markKey) as? String }   // (the self-test reads a picture's mark)
  static func marked(_ key: String, in w: UIWindow?) -> UIImageView? {
    guard !key.isEmpty, let w = w else { return nil }
    func walk(_ v: UIView) -> UIImageView? {
      if v.isHidden || v.alpha < 0.01 { return nil }
      if let iv = v as? UIImageView, iv.image != nil, (objc_getAssociatedObject(iv, &markKey) as? String) == key,
         iv.convert(iv.bounds, to: nil).intersects(w.bounds) { return iv }
      for c in v.subviews { if let x = walk(c) { return x } }
      return nil
    }
    return walk(w)
  }
  // the picture under the last touch (a moment ago): the touched view's own, one inside it under the finger, or one a few
  // steps up that holds the finger's spot
  static func picture() -> UIImageView? {
    guard Date().timeIntervalSince(at) < 3, let v = view, v.window != nil else { return nil }
    func good(_ x: UIView) -> UIImageView? {
      guard let iv = x as? UIImageView, iv.image != nil, !iv.isHidden, iv.alpha > 0.01, iv.bounds.width > 8 else { return nil }
      return iv.convert(iv.bounds, to: nil).contains(point) ? iv : nil
    }
    func inside(_ x: UIView, _ depth: Int) -> UIImageView? {
      if let iv = good(x) { return iv }
      guard depth > 0 else { return nil }
      for c in x.subviews.reversed() { if let iv = inside(c, depth - 1) { return iv } }
      return nil
    }
    var x: UIView? = v
    for _ in 0..<4 { guard let y = x else { break }; if let iv = inside(y, 4) { return iv }; x = y.superview }
    return nil
  }
}


extension Array {
  subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
