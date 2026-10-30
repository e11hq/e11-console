// The file preview on the iPhone app (18+, Haris 2026-10-30): today's preview — × · "3 of 8" · ⋯ at the top, the name
// and details, the strip of files, Copy and Download at the bottom — drawn by iOS. Pictures zoom and swipe like Photos
// (pinch, double-tap, iOS's own paging); videos and sounds play in Apple's own player; PDF / Word / Excel / PowerPoint
// show the server's page pictures in a zoomable scroll; anything else shows its card, as today. Tap hides the bars;
// pull down to close. The page sends the files (absolute addresses on the server) and does Copy / Download / ⋯ itself
// (window.__e11Preview); files are fetched with the app's own sign-in (its cookies).
import UIKit
import AVKit
import WebKit

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
  static func data(_ s: String, _ done: @escaping (Data?) -> Void) {
    guard let url = URL(string: s) else { return done(nil) }
    if let d = cache.object(forKey: s as NSString) { return done(d as Data) }
    var r = URLRequest(url: url)
    r.allHTTPHeaderFields = headers(url)
    URLSession.shared.dataTask(with: r) { data, resp, _ in
      let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
      let d = ok ? data : nil
      if let d { cache.setObject(d as NSData, forKey: s as NSString) }
      DispatchQueue.main.async { done(d) }
    }.resume()
  }
  static func image(_ s: String?, _ done: @escaping (UIImage?) -> Void) {
    guard let s, !s.isEmpty else { return done(nil) }
    data(s) { d in done(d.flatMap { UIImage(data: $0) }) }
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
  var onPlay: (([String: Any]) -> Void)?
  var onPages: ((String) -> Void)?
  private var mode = ""   // image / pages / card / text

  override init(frame: CGRect) {
    super.init(frame: frame)
    zoomer.delegate = self
    zoomer.minimumZoomScale = 1; zoomer.maximumZoomScale = 4
    zoomer.showsHorizontalScrollIndicator = false; zoomer.showsVerticalScrollIndicator = false
    zoomer.contentInsetAdjustmentBehavior = .never
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
    cardType.font = .systemFont(ofSize: 28, weight: .bold); cardType.textColor = .secondaryLabel
    cardNote.font = .systemFont(ofSize: 15); cardNote.textColor = .secondaryLabel; cardNote.numberOfLines = 0; cardNote.textAlignment = .center
    [cardPic, cardType, cardNote].forEach { cardStack.addArrangedSubview($0) }
    contentView.addSubview(cardStack)
    play.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)), for: .normal)
    play.tintColor = .white
    play.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    play.layer.cornerRadius = 38
    play.addAction(UIAction { [weak self] _ in guard let self else { return }; self.onPlay?(self.file) }, for: .touchUpInside)
    contentView.addSubview(play)
    textView.isEditable = false; textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular); textView.backgroundColor = .clear
    textView.textContainerInset = UIEdgeInsets(top: 110, left: 14, bottom: 200, right: 14)
    contentView.addSubview(textView)
    contentView.addSubview(spinner)
    let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
    dbl.numberOfTapsRequired = 2
    zoomer.addGestureRecognizer(dbl)
  }
  required init?(coder: NSCoder) { fatalError() }
  var doubleTapGesture: UITapGestureRecognizer? { zoomer.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first { $0.numberOfTapsRequired == 2 } }

  func show(_ f: [String: Any]) {
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
    case "video", "audio":
      mode = "card"
      card(f, note: nil)
      play.isHidden = false
    case "pages":
      mode = "pages"
      pagesStack.isHidden = false
      spinner.startAnimating()
      if let id = f["id"] as? String { onPages?(id) }
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
    let my = token
    PreviewLoad.image(f["cover"] as? String) { [weak self] img in
      guard let self, self.token == my, let img else { return }
      self.cardPic.image = img; self.cardPic.isHidden = false; self.cardType.isHidden = true; self.setNeedsLayout()
    }
    cardType.isHidden = false
  }
  // the server's page pictures arrived (PDF / Office)
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
    play.frame = CGRect(x: b.midX - 38, y: b.midY - 38, width: 76, height: 76)
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
      content.frame = CGRect(x: 0, y: 0, width: b.width, height: h + 220)
      pagesStack.frame = CGRect(x: 12, y: 110, width: w, height: h)
      zoomer.contentSize = content.frame.size
    }
  }
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
  private var files: [[String: Any]]
  private var at: Int
  private let event: ([String: Any]) -> Void
  private let dark: Bool
  private var pages: [String: ([String], String?)] = [:]
  private let pager: UICollectionView
  private let strip: UICollectionView
  private let topBar = UIView(), bottomBar = UIView()
  private let closeB = UIButton(type: .system), moreB = UIButton(type: .system)
  private let count = UILabel(), name = UILabel(), details = UILabel()
  private let copyB = UIButton(type: .system), dlB = UIButton(type: .system)
  private let toast = UILabel()
  private var barsHidden = false
  private var closed = false
  private var pull: UIPanGestureRecognizer?

  init(_ a: [String: Any], dark: Bool, event: @escaping ([String: Any]) -> Void) {
    files = a["files"] as? [[String: Any]] ?? []
    at = max(0, min(files.count - 1, (a["at"] as? NSNumber)?.intValue ?? 0))
    self.event = event
    self.dark = dark
    let pl = UICollectionViewFlowLayout(); pl.scrollDirection = .horizontal; pl.minimumLineSpacing = 0
    pager = UICollectionView(frame: .zero, collectionViewLayout: pl)
    let sl = UICollectionViewFlowLayout(); sl.scrollDirection = .horizontal; sl.minimumLineSpacing = 6; sl.itemSize = CGSize(width: 44, height: 44)
    strip = UICollectionView(frame: .zero, collectionViewLayout: sl)
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = dark ? .dark : .light
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
  }
  required init?(coder: NSCoder) { fatalError() }
  override var prefersStatusBarHidden: Bool { barsHidden }
  override var preferredStatusBarStyle: UIStatusBarStyle { dark ? .lightContent : .darkContent }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    pager.backgroundColor = .clear
    pager.isPagingEnabled = true
    pager.showsHorizontalScrollIndicator = false
    pager.contentInsetAdjustmentBehavior = .never
    pager.dataSource = self; pager.delegate = self
    pager.register(PreviewCell.self, forCellWithReuseIdentifier: PreviewCell.id)
    pager.frame = view.bounds; pager.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(pager)
    // the bars
    for bar in [topBar, bottomBar] {
      bar.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.88)
      bar.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(bar)
    }
    func circle(_ b: UIButton, _ sym: String) {
      b.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
      b.tintColor = .label; b.backgroundColor = .tertiarySystemFill; b.layer.cornerRadius = 20
      b.translatesAutoresizingMaskIntoConstraints = false
      b.widthAnchor.constraint(equalToConstant: 40).isActive = true; b.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }
    circle(closeB, "xmark"); circle(moreB, "ellipsis")
    closeB.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
    moreB.addAction(UIAction { [weak self] _ in self?.send("more") }, for: .touchUpInside)
    count.font = .systemFont(ofSize: 15, weight: .semibold); count.textColor = .secondaryLabel; count.translatesAutoresizingMaskIntoConstraints = false
    [closeB, count, moreB].forEach { topBar.addSubview($0) }
    name.font = .systemFont(ofSize: 15, weight: .semibold); name.lineBreakMode = .byTruncatingMiddle
    details.font = .systemFont(ofSize: 12.5); details.textColor = .secondaryLabel
    strip.backgroundColor = .clear; strip.showsHorizontalScrollIndicator = false
    strip.dataSource = self; strip.delegate = self
    strip.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "th")
    strip.isHidden = files.count < 2
    func pill(_ b: UIButton, _ sym: String, _ t: String) {
      var c = UIButton.Configuration.gray()
      c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)); c.imagePadding = 6
      c.title = t; c.cornerStyle = .capsule; c.baseForegroundColor = .label
      b.configuration = c
      b.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    pill(copyB, "doc.on.doc", "Copy"); pill(dlB, "arrow.down.circle", "Download")
    copyB.addAction(UIAction { [weak self] _ in self?.send("copy"); self?.flash("Copied — paste it into a comment or description") }, for: .touchUpInside)
    dlB.addAction(UIAction { [weak self] _ in self?.send("dl") }, for: .touchUpInside)
    let btns = UIStackView(arrangedSubviews: [copyB, dlB]); btns.axis = .horizontal; btns.spacing = 10; btns.distribution = .fillEqually
    let meta = UIStackView(arrangedSubviews: [name, details]); meta.axis = .vertical; meta.spacing = 2
    let col = UIStackView(arrangedSubviews: [meta, strip, btns]); col.axis = .vertical; col.spacing = 12
    col.translatesAutoresizingMaskIntoConstraints = false
    bottomBar.addSubview(col)
    toast.font = .systemFont(ofSize: 14, weight: .medium); toast.textColor = .white; toast.textAlignment = .center
    toast.backgroundColor = UIColor.black.withAlphaComponent(0.78); toast.layer.cornerRadius = 18; toast.clipsToBounds = true
    toast.alpha = 0; toast.numberOfLines = 2
    toast.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(toast)
    let g = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      topBar.topAnchor.constraint(equalTo: view.topAnchor), topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      topBar.bottomAnchor.constraint(equalTo: g.topAnchor, constant: 56),
      closeB.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16), closeB.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
      moreB.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16), moreB.centerYAnchor.constraint(equalTo: closeB.centerYAnchor),
      count.centerXAnchor.constraint(equalTo: topBar.centerXAnchor), count.centerYAnchor.constraint(equalTo: closeB.centerYAnchor),
      bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      col.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12), col.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
      col.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16), col.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -8),
      strip.heightAnchor.constraint(equalToConstant: 44),
      toast.centerXAnchor.constraint(equalTo: view.centerXAnchor), toast.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14),
      toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48), toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
    ])
    // tap: hide / show the bars; pull down: close
    let tap = UITapGestureRecognizer(target: self, action: #selector(toggleBars))
    tap.delegate = self
    pager.addGestureRecognizer(tap)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(pulled(_:)))
    pan.delegate = self
    view.addGestureRecognizer(pan)
    pull = pan
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let l = pager.collectionViewLayout as? UICollectionViewFlowLayout, l.itemSize != view.bounds.size { l.itemSize = view.bounds.size; l.invalidateLayout() }
    toast.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
  }
  private var placed = false
  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    if !placed && view.bounds.width > 0 {
      placed = true
      pager.layoutIfNeeded()
      pager.scrollToItem(at: IndexPath(item: at, section: 0), at: .left, animated: false)
      refreshBars()
    }
  }
  private func send(_ ev: String) {
    guard at < files.count, let id = files[at]["id"] as? String else { return }
    event(["ev": ev, "id": id])
  }
  private func refreshBars() {
    guard at < files.count else { return }
    let f = files[at]
    count.text = files.count > 1 ? "\(at + 1) of \(files.count)" : ""
    name.text = f["name"] as? String
    details.text = f["meta"] as? String
    strip.reloadData()
    if files.count > 1 { strip.scrollToItem(at: IndexPath(item: at, section: 0), at: .centeredHorizontally, animated: true) }
    event(["ev": "at", "id": f["id"] as? String ?? ""])
  }
  func flash(_ s: String) {
    toast.text = "   " + s + "   "
    UIView.animate(withDuration: 0.2) { self.toast.alpha = 1 }
    UIView.animate(withDuration: 0.3, delay: 2, options: []) { self.toast.alpha = 0 }
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
      pager.reloadData(); strip.isHidden = files.count < 2
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
    if let p = presentingViewController { p.dismiss(animated: true) } else { dismiss(animated: true) }
  }

  /* ---------- the pages and the strip ---------- */
  func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { files.count }
  func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
    let f = files[ip.item]
    if cv === strip {
      let c = cv.dequeueReusableCell(withReuseIdentifier: "th", for: ip)
      c.contentView.subviews.forEach { $0.removeFromSuperview() }
      c.contentView.layer.cornerRadius = 8; c.contentView.clipsToBounds = true
      c.contentView.backgroundColor = .tertiarySystemFill
      c.contentView.layer.borderWidth = ip.item == at ? 2 : 0
      c.contentView.layer.borderColor = UIColor.label.cgColor
      let iv = UIImageView(frame: c.contentView.bounds); iv.contentMode = .scaleAspectFill; iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      c.contentView.addSubview(iv)
      let l = UILabel(frame: c.contentView.bounds); l.text = ((f["ext"] as? String) ?? "").uppercased(); l.font = .systemFont(ofSize: 10, weight: .bold)
      l.textColor = .secondaryLabel; l.textAlignment = .center; l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      c.contentView.addSubview(l)
      let id = f["id"] as? String
      PreviewLoad.image((f["thumb"] as? String) ?? (f["cover"] as? String)) { [weak c, weak cv] img in
        guard let c, let cv, let img, let now = cv.indexPath(for: c), now.item < self.files.count, (self.files[now.item]["id"] as? String) == id else { return }
        iv.image = img; l.isHidden = true
      }
      return c
    }
    let c = cv.dequeueReusableCell(withReuseIdentifier: PreviewCell.id, for: ip) as! PreviewCell
    c.onPlay = { [weak self] f in self?.playMedia(f) }
    c.onPages = { [weak self, weak c] id in
      guard let self else { return }
      if let p = self.pages[id] { c?.setPages(p.0, note: p.1) } else { self.event(["ev": "pages", "id": id]) }
    }
    c.show(f)
    if let tap = (pager.gestureRecognizers ?? []).first(where: { $0 is UITapGestureRecognizer && ($0 as! UITapGestureRecognizer).numberOfTapsRequired == 1 }) as? UITapGestureRecognizer, let dbl = c.doubleTapGesture { tap.require(toFail: dbl) }
    return c
  }
  func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt ip: IndexPath) -> CGSize { cv === strip ? CGSize(width: 44, height: 44) : view.bounds.size }
  func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
    guard cv === strip, ip.item != at else { return }
    at = ip.item
    pager.scrollToItem(at: ip, at: .left, animated: false)
    refreshBars()
  }
  func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
    guard sv === pager else { return }
    let n = Int((sv.contentOffset.x / max(1, sv.bounds.width)).rounded())
    if n != at, n >= 0, n < files.count { at = n; UISelectionFeedbackGenerator().selectionChanged(); refreshBars() }
  }

  /* ---------- playing a video or a sound: Apple's own player ---------- */
  private func playMedia(_ f: [String: Any]) {
    guard let s = f["src"] as? String, let url = URL(string: s) else { return }
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
    UIView.animate(withDuration: 0.2) {
      self.topBar.alpha = self.barsHidden ? 0 : 1
      self.bottomBar.alpha = self.barsHidden ? 0 : 1
      self.setNeedsStatusBarAppearanceUpdate()
    }
  }
  private var current: PreviewCell? { pager.visibleCells.compactMap { $0 as? PreviewCell }.first { pager.indexPath(for: $0)?.item == at } }
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g === pull, let p = pull else { return true }
    let v = p.velocity(in: view)
    guard v.y > 0, abs(v.y) > abs(v.x) * 1.2 else { return false }
    if let c = current, c.isZoomed || !c.atTop { return false }
    return true
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { g !== pull }
  @objc private func pulled(_ g: UIPanGestureRecognizer) {
    let dy = max(0, g.translation(in: view).y)
    switch g.state {
    case .changed:
      pager.transform = CGAffineTransform(translationX: 0, y: dy).scaledBy(x: 1 - min(0.15, dy / 2000), y: 1 - min(0.15, dy / 2000))
      let k = 1 - min(1, dy / 400)
      view.backgroundColor = UIColor.systemBackground.withAlphaComponent(k)
      topBar.alpha = barsHidden ? 0 : k; bottomBar.alpha = barsHidden ? 0 : k
    case .ended, .cancelled:
      if dy > 120 || g.velocity(in: view).y > 900 { close(); return }
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
        self.pager.transform = .identity
        self.view.backgroundColor = .systemBackground
        self.topBar.alpha = self.barsHidden ? 0 : 1; self.bottomBar.alpha = self.barsHidden ? 0 : 1
      }
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
