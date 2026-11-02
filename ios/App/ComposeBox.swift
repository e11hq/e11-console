import UIKit
import AVFoundation
import UniformTypeIdentifiers

/* The comment box, the app's own (step 3, Haris 2026-10-31 / 2026-11-01): the Claude app's box — rounded, 16 from
   each side, + on the left (the one Attach Files sheet), the mic on the right turning into ↑ once something is typed.
   Replying-to line above it, @ people listed above it, waiting files as tiles inside it with their upload bar.
   Voice messages WhatsApp's way: hold the mic to record (red dot, timer, live waveform), slide left to cancel, slide up
   to lock and let go (then 🗑 or ↑). Sent straight to the server (/api/home/act comment / editComment); files and
   voice uploaded by the app itself. */
enum Uploader {
  // a file on the phone → the server (2 MB at a time) → its path there
  static func send(_ url: URL, name: String, task: String, cookies: @escaping (@escaping (String) -> Void) -> Void, progress: @escaping (Double) -> Void, done: @escaping (String?) -> Void) {
    let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    func piece(_ offset: Int64, _ path: String?) {
      guard let fh = try? FileHandle(forReadingFrom: url) else { return done(nil) }
      try? fh.seek(toOffset: UInt64(offset))
      let data = (try? fh.read(upToCount: 2 * 1024 * 1024)) ?? Data()
      try? fh.close()
      var q = URLComponents(string: serverURL() + "/api/host/writeChunkBin")!
      var qi = [URLQueryItem(name: "taskId", value: task), URLQueryItem(name: "name", value: name), URLQueryItem(name: "offset", value: String(offset))]
      if let p = path { qi.append(URLQueryItem(name: "path", value: p)) }
      q.queryItems = qi
      cookies { c in
        var r = URLRequest(url: q.url!); r.httpMethod = "POST"; r.httpBody = data
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type"); if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
        URLSession.shared.dataTask(with: r) { d, resp, _ in
          let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
          DispatchQueue.main.async {
            guard ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200, let p = j?["path"] as? String else { return done(nil) }
            let next = offset + Int64(data.count)
            progress(size > 0 ? Double(next) / Double(size) : 1)
            if next < size && !data.isEmpty { piece(next, p) } else { done(p) }
          }
        }.resume()
      }
    }
    piece(0, nil)
  }
}

final class ComposeBox: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
  var taskId = ""
  var parentId: String?                 // a thread page's: every reply goes to it
  var replyTo: (id: String, name: String)? { didSet { paintReply() } }
  var replyPerson: [String: Any]?                 // (who's being replied to: their picture or initials in the pill)
  private let replyPill = UIButton(type: .custom)
  var editing: String? { didSet { paintSend() } }
  var mentionable: [[String: Any]] = []
  var cookies: (@escaping (String) -> Void) -> Void = { $0("") }
  var onSend: (([String: Any], @escaping (Bool) -> Void) -> Void)?   // the act body → sent?
  var onAttach: ((@escaping (String) -> Void) -> Void)?             // the Attach Files sheet → camera / photos / files
  var present: ((UIViewController) -> Void)?
  var onToast: ((String) -> Void)?
  var onPending: ((String, String?, Double) -> Void)?   // a voice message on its way: (its id, the thread it's in, its length)
  var onPendingEnd: ((String, Bool) -> Void)?          // …sent (true) or not

  private let box = UIView()
  let text = PasteTextView()
  private let placeholder = UILabel()
  private let plus = UIButton(type: .system), right = UIButton(type: .system)
  private let replyLine = UIStackView(), replyLabel = UILabel()
  private let tiles = UIStackView()
  private let mentions = UIStackView()
  private var files: [(uid: String, name: String, size: Int64, path: String?, progress: Double, failed: Bool, thumb: UIImage?)] = []
  // uploads finished or failed (by their id) — kept even once the box is cleared, for comments sent before they were up
  private var upDone: [String: String] = [:], upFailed = Set<String>()
  private var outbox: [(pendingId: String, body: [String: Any], files: [(uid: String, name: String, size: Int64)])] = []
  var onPendingFiles: ((String, String?, String, [[String: Any]]) -> Void)?   // a comment sent while its files upload: (id, thread, words, its cards)
  private var textH: NSLayoutConstraint!
  private var tilesH: NSLayoutConstraint!

  override init(frame: CGRect) {
    super.init(frame: frame)
    // Liquid Glass, as the Claude app's box (iOS 26's own; before it a frosted material)
    box.backgroundColor = .clear
    box.layer.cornerRadius = 30; box.layer.cornerCurve = .continuous
    let glass = UIVisualEffectView(effect: nil)
    if #available(iOS 26.0, *) { let g = UIGlassEffect(style: .regular); g.isInteractive = true; glass.effect = g }
    else { glass.effect = UIBlurEffect(style: .systemThickMaterial); box.layer.borderWidth = 1; box.layer.borderColor = UIColor.separator.withAlphaComponent(0.4).cgColor }
    glass.layer.cornerRadius = 30; glass.layer.cornerCurve = .continuous; glass.clipsToBounds = true
    glass.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(glass)
    NSLayoutConstraint.activate([glass.leadingAnchor.constraint(equalTo: box.leadingAnchor), glass.trailingAnchor.constraint(equalTo: box.trailingAnchor), glass.topAnchor.constraint(equalTo: box.topAnchor), glass.bottomAnchor.constraint(equalTo: box.bottomAnchor)])
    text.font = .systemFont(ofSize: 17); text.backgroundColor = .clear; text.delegate = self
    text.onPasteFiles = { [weak self] in self?.pasteFiles() ?? false }
    text.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0); text.textContainer.lineFragmentPadding = 0
    text.isScrollEnabled = false
    placeholder.text = "Comment"; placeholder.font = .systemFont(ofSize: 17); placeholder.textColor = .secondaryLabel
    for (b, sym) in [(plus, "plus"), (right, "mic.fill")] {
      b.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
      b.tintColor = .label; b.backgroundColor = .tertiarySystemFill; b.layer.cornerRadius = 18
    }
    plus.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.attach() }, for: .touchUpInside)
    right.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .touchUpInside)
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdMic(_:))); hold.minimumPressDuration = 0.18
    right.addGestureRecognizer(hold); holdG = hold
    tiles.spacing = 8; tiles.alignment = .center
    replyLabel.font = .systemFont(ofSize: 13); replyLabel.textColor = .secondaryLabel
    let x = UIButton(type: .system); x.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal); x.tintColor = .secondaryLabel
    x.addAction(UIAction { [weak self] _ in self?.replyTo = nil }, for: .touchUpInside)
    replyLine.addArrangedSubview(replyLabel); replyLine.addArrangedSubview(UIView()); replyLine.addArrangedSubview(x)
    replyLine.isHidden = true
    // (on its own glass capsule, so it reads over the comments behind it)
    replyLine.isLayoutMarginsRelativeArrangement = true; replyLine.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 10)
    let rg = UIVisualEffectView(effect: nil)
    if #available(iOS 26.0, *) { rg.effect = UIGlassEffect(style: .regular) } else { rg.effect = UIBlurEffect(style: .systemThickMaterial) }
    rg.layer.cornerRadius = 16; rg.layer.cornerCurve = .continuous; rg.clipsToBounds = true
    rg.translatesAutoresizingMaskIntoConstraints = false; rg.isUserInteractionEnabled = false
    replyLine.insertSubview(rg, at: 0)
    NSLayoutConstraint.activate([rg.leadingAnchor.constraint(equalTo: replyLine.leadingAnchor), rg.trailingAnchor.constraint(equalTo: replyLine.trailingAnchor), rg.topAnchor.constraint(equalTo: replyLine.topAnchor), rg.bottomAnchor.constraint(equalTo: replyLine.bottomAnchor)])
    mentions.axis = .vertical; mentions.backgroundColor = .secondarySystemGroupedBackground; mentions.layer.cornerRadius = 16; mentions.clipsToBounds = true; mentions.isHidden = true
    let tilesScroll = UIScrollView(); tilesScroll.showsHorizontalScrollIndicator = false
    tilesScroll.addSubview(tiles); tiles.translatesAutoresizingMaskIntoConstraints = false
    let v = UIStackView(arrangedSubviews: [mentions, box]); v.axis = .vertical; v.spacing = 8
    [plus, right, text, placeholder, tilesScroll, replyPill].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; box.addSubview($0) }
    v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v)
    textH = text.heightAnchor.constraint(equalToConstant: 30)
    tilesH = tilesScroll.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      tilesScroll.topAnchor.constraint(equalTo: box.topAnchor, constant: 10), tilesScroll.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12), tilesScroll.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12), tilesH,
      tiles.leadingAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.leadingAnchor), tiles.trailingAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.trailingAnchor), tiles.topAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.topAnchor), tiles.bottomAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.bottomAnchor), tiles.heightAnchor.constraint(equalTo: tilesScroll.heightAnchor),
      text.topAnchor.constraint(equalTo: tilesScroll.bottomAnchor, constant: 4), text.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14), text.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14), textH,
      placeholder.leadingAnchor.constraint(equalTo: text.leadingAnchor), placeholder.topAnchor.constraint(equalTo: text.topAnchor, constant: 4),
      plus.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8), plus.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8), plus.widthAnchor.constraint(equalToConstant: 36), plus.heightAnchor.constraint(equalToConstant: 36),
      right.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8), right.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8), right.widthAnchor.constraint(equalToConstant: 36), right.heightAnchor.constraint(equalToConstant: 36),
      plus.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 6),
      // "Replying to Carine (picture)": a grey pill in the buttons' row, where the Claude app has its model's
      replyPill.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 8), replyPill.centerYAnchor.constraint(equalTo: plus.centerYAnchor),
      replyPill.heightAnchor.constraint(equalToConstant: 36), replyPill.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
    ])
    replyPill.backgroundColor = .tertiarySystemFill; replyPill.layer.cornerRadius = 18; replyPill.layer.cornerCurve = .continuous
    replyPill.isHidden = true
    // (tapped: no longer a reply — an ordinary comment)
    replyPill.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.replyPerson = nil; self?.replyTo = nil }, for: .touchUpInside)
    // a tap anywhere on the box is a tap in it: the keyboard comes up (its buttons and files keep their own taps)
    let tapBox = UITapGestureRecognizer(target: self, action: #selector(tappedBox)); tapBox.delegate = self; tapBox.cancelsTouchesInView = false
    box.addGestureRecognizer(tapBox)
    paintSend()
  }
  required init?(coder: NSCoder) { fatalError() }
  override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? { let v = super.hitTest(p, with: e); return v === self ? nil : v }

  // ---------- typing ----------
  var hasSomething: Bool { !(text.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty }
  private var showingSend: Bool?
  private func paintSend() {
    let send = hasSomething || editing != nil
    // mic ↔ ↑ as the Claude app does: the symbol swaps with iPhone's own replace effect while the circle fills
    if showingSend != send {
      let first = showingSend == nil
      showingSend = send
      let img = UIImage(systemName: send ? "arrow.up" : "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: send ? 14 : 13.5, weight: send ? .bold : .semibold))
      if #available(iOS 17.0, *), !first, let iv = right.imageView, let img = img {
        iv.setSymbolImage(img, contentTransition: .replace.downUp)
        right.setImage(img, for: .normal)
      } else { right.setImage(img, for: .normal) }
      let paint = { self.right.backgroundColor = send ? .label : .tertiarySystemFill; self.right.tintColor = send ? .systemBackground : .label }
      if first { paint() } else { UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: paint) }
    }
    holdG?.isEnabled = !send
    placeholder.isHidden = !(text.text ?? "").isEmpty
    placeholder.text = parentId != nil || replyTo != nil ? "Reply" : "Comment"
  }
  @objc private func tappedBox() { if !text.isFirstResponder { text.becomeFirstResponder() } }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
    var v = t.view
    while let x = v, x !== box { if x is UIControl || x === text || x === tiles { return false }; v = x.superview }
    return true
  }
  private func paintReply() {
    replyLine.isHidden = true
    replyPill.subviews.forEach { $0.removeFromSuperview() }
    replyPill.isHidden = replyTo == nil
    if let r = replyTo {
      let l = UILabel(); l.isUserInteractionEnabled = false
      let s = NSMutableAttributedString(string: "Replying to ", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel])
      s.append(NSAttributedString(string: r.name, attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor.label]))
      l.attributedText = s; l.lineBreakMode = .byTruncatingTail
      let av = CommentCell.avatar(replyPerson ?? ["initials": String(r.name.prefix(1)).uppercased()], 24); av.isUserInteractionEnabled = false
      let row = UIStackView(arrangedSubviews: [l, av]); row.spacing = 8; row.alignment = .center; row.isUserInteractionEnabled = false
      row.translatesAutoresizingMaskIntoConstraints = false; replyPill.addSubview(row)
      NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: replyPill.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: replyPill.trailingAnchor, constant: -6), row.centerYAnchor.constraint(equalTo: replyPill.centerYAnchor)])
      replyPill.accessibilityLabel = "Replying to \(r.name). Tap to stop replying"
    }
    paintSend()
  }
  func textViewDidChange(_ tv: UITextView) {
    let h = min(max(30, tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)).height), 130)
    tv.isScrollEnabled = h >= 130
    if textH.constant != h { textH.constant = h; superview?.layoutIfNeeded() }
    paintSend()
    lookForMention()
  }
  func setText(_ a: NSAttributedString) { text.attributedText = a; textViewDidChange(text) }

  // ---------- @ people (above the box) ----------
  private func lookForMention() {
    let r = text.selectedRange
    let before = (text.text as NSString).substring(to: min(r.location, (text.text as NSString).length))
    guard let m = before.range(of: "@([A-Za-z]*)$", options: .regularExpression) else { mentions.isHidden = true; return }
    let q = String(before[m].dropFirst()).lowercased()
    let hits = mentionable.filter { q.isEmpty || ($0["name"] as? String ?? "").lowercased().split(separator: " ").contains { $0.hasPrefix(q) } }.prefix(4)
    mentions.arrangedSubviews.forEach { $0.removeFromSuperview() }
    guard !hits.isEmpty else { mentions.isHidden = true; return }
    let at = (before as NSString).length - q.count - 1
    for p in hits {
      let row = TaskRow()
      let l = UILabel(); l.text = p["name"] as? String; l.font = .systemFont(ofSize: 16, weight: .medium)
      let h = UIStackView(arrangedSubviews: [CommentCell.avatar(p, 28), l]); h.spacing = 10; h.alignment = .center
      h.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(h)
      NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), h.topAnchor.constraint(equalTo: row.topAnchor, constant: 8), h.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8), h.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor)])
      row.onTap = { [weak self] in self?.insertMention(p, at: at) }
      mentions.addArrangedSubview(row)
    }
    mentions.isHidden = false
  }
  private func insertMention(_ p: [String: Any], at: Int) {
    let r = text.selectedRange
    let m = NSMutableAttributedString(attributedString: text.attributedText)
    let name = "@" + (p["name"] as? String ?? "")
    let base: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label]
    var a = base; a[MENTION_KEY] = p["id"] as? String ?? ""; a[.foregroundColor] = UIColor.systemBlue
    m.replaceCharacters(in: NSRange(location: at, length: r.location - at), with: NSAttributedString(string: name, attributes: a))
    m.insert(NSAttributedString(string: " ", attributes: base), at: at + (name as NSString).length)
    text.attributedText = m
    text.selectedRange = NSRange(location: at + (name as NSString).length + 1, length: 0)
    text.typingAttributes = base
    mentions.isHidden = true
    UISelectionFeedbackGenerator().selectionChanged()
    textViewDidChange(text)
  }

  // ---------- files ----------
  private func attach() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    onAttach?({ [weak self] source in
      guard let self = self, let vc = self.window?.rootViewController else { return }
      var top = vc; while let p = top.presentedViewController { top = p }
      Picker.shared.pick(from: top, single: false, source: source) { [weak self] r in
        for f in (r["files"] as? [[String: Any]]) ?? [] {
          guard let self = self, let tok = f["token"] as? String, let url = Picker.shared.url(tok) else { continue }
          self.addFile(url, name: f["name"] as? String ?? "File", voice: nil)
        }
        self?.text.becomeFirstResponder()
      }
    })
  }
  // a file pasted (a picture, or one copied from a preview: its own name): added as if picked
  private func pasteFiles() -> Bool {
    let pb = UIPasteboard.general
    // a file copied in the app: that same file, at once (nothing uploaded)
    if let f = FileClip.current, let path = f["file"] as? String {
      if files.contains(where: { $0.path == path }) { return true }
      let size = Int64(f["size"] as? Int ?? 0)
      let uid = UUID().uuidString
      files.append((uid: uid, name: f["name"] as? String ?? "File", size: size, path: path, progress: 1, failed: false, thumb: nil))
      upDone[uid] = path
      paintTiles()
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      let pic = (f["thumbUrl"] as? String) ?? (CommentCell.isPic(f["name"] as? String ?? "") ? f["url"] as? String : nil)
      if let p = pic { FeedLoader.shared.image(p) { [weak self] img in guard let self = self, let img = img, let i = self.files.firstIndex(where: { $0.uid == uid }) else { return }; self.files[i].thumb = img; self.paintTiles() } }
      return true
    }
    var added = false
    for (k, item) in pb.items.enumerated() {
      // (words are the text box's own)
      guard let type = item.keys.first(where: { t in guard let u = UTType(t) else { return false }; return !u.conforms(to: .text) }) else { continue }
      var data: Data? = item[type] as? Data
      if data == nil, let img = item[type] as? UIImage { data = img.pngData() }
      guard let d = data else { continue }
      let ext = (item[type] is UIImage) ? "png" : (UTType(type)?.preferredFilenameExtension ?? "dat")
      var name = (FileClip.change == pb.changeCount && k == 0 ? FileClip.name : nil) ?? (UTType(type)?.conforms(to: .image) == true ? "Pasted image.\(ext)" : "Pasted file.\(ext)")
      if (name as NSString).pathExtension.isEmpty { name += "." + ext }
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paste-\(UUID().uuidString)", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let u = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
      guard (try? d.write(to: u)) != nil else { continue }
      addFile(u, name: u.lastPathComponent, voice: nil)
      added = true
    }
    return added
  }
  private func addFile(_ url: URL, name: String, voice: Double?) {
    let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    // (a picture shows itself in its tile straight away)
    var thumb: UIImage?
    if CommentCell.isPic(name), let img = UIImage(contentsOfFile: url.path) { thumb = img.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? img }
    else if CommentCell.isVideo(name) {
      // (a video: its first frame)
      let g = AVAssetImageGenerator(asset: AVURLAsset(url: url)); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 240, height: 240)
      if let cg = try? g.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) { thumb = UIImage(cgImage: cg) }
    }
    let uid = UUID().uuidString
    files.append((uid: uid, name: name, size: size, path: nil, progress: 0, failed: false, thumb: thumb))
    if let t = thumb { FeedLoader.shared.setLocal("local:" + uid, t) }   // (its card in the comments, if sent before it's up)
    paintTiles()
    Uploader.send(url, name: name, task: taskId, cookies: cookies, progress: { [weak self] p in
      UploadRing.post(uid, p)
      guard let self = self, let i = self.files.firstIndex(where: { $0.uid == uid }) else { return }
      self.files[i].progress = p; self.paintTiles()
    }) { [weak self] path in
      guard let self = self else { return }
      if let p = path { self.upDone[uid] = p; UploadRing.post(uid, 1) } else { self.upFailed.insert(uid) }
      let waiting = self.outbox.contains { $0.files.contains { $0.uid == uid } }
      if let i = self.files.firstIndex(where: { $0.uid == uid }) {
        if let p = path { self.files[i].path = p; self.files[i].progress = 1 } else { self.files[i].failed = true }
        self.paintTiles()
      }
      if path != nil, !waiting { Main.playUploaded(); UINotificationFeedbackGenerator().notificationOccurred(.success) }
      if path == nil, !waiting { self.onToast?("Upload failed — try again") }
      self.flushOutbox()
    }
  }
  private func paintTiles() {
    tiles.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for f in files {
      let uid = f.uid
      let t = UIView(); t.backgroundColor = .tertiarySystemFill; t.layer.cornerRadius = 12
      t.translatesAutoresizingMaskIntoConstraints = false
      t.widthAnchor.constraint(equalToConstant: 56).isActive = true; t.heightAnchor.constraint(equalToConstant: 56).isActive = true
      let ext = (f.name as NSString).pathExtension.uppercased()
      let l = UILabel(); l.text = ext.isEmpty ? "FILE" : String(ext.prefix(4)); l.font = .systemFont(ofSize: 11, weight: .bold); l.textColor = .secondaryLabel; l.textAlignment = .center
      l.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
      if let th = f.thumb {
        let iv = UIImageView(image: th); iv.contentMode = .scaleAspectFill; iv.clipsToBounds = true; iv.layer.cornerRadius = 12; iv.frame = l.frame; t.addSubview(iv)
        if f.progress < 1 && !f.failed { let dim = UIView(frame: l.frame); dim.backgroundColor = UIColor.black.withAlphaComponent(0.35); dim.layer.cornerRadius = 12; t.addSubview(dim); l.textColor = .white } else { l.isHidden = true }
      }
      t.addSubview(l)
      if f.progress < 1 && !f.failed { l.text = "\(Int(f.progress * 100))%"; if f.thumb == nil { l.textColor = .label }; let bar = UIProgressView(progressViewStyle: .bar); bar.progress = Float(f.progress); bar.frame = CGRect(x: 8, y: 46, width: 40, height: 3); t.addSubview(bar) }
      if f.failed { l.textColor = .systemRed }
      // the ✕: a dark circle with a thin white edge and a white ✕ — clear on any picture, dark or light (as Photos' and
      // Messages' own remove buttons; Haris, 2026-11-02)
      let x = UIButton(type: .custom)
      x.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)), for: .normal); x.tintColor = .white
      x.backgroundColor = UIColor.black.withAlphaComponent(0.62); x.layer.cornerRadius = 11
      x.layer.borderWidth = 1.5; x.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
      x.layer.shadowColor = UIColor.black.cgColor; x.layer.shadowOpacity = 0.25; x.layer.shadowRadius = 2; x.layer.shadowOffset = .zero
      x.frame = CGRect(x: 38, y: -4, width: 22, height: 22)
      x.addAction(UIAction { [weak self] _ in self?.files.removeAll { $0.uid == uid }; self?.paintTiles() }, for: .touchUpInside)
      t.addSubview(x)
      tiles.addArrangedSubview(t)
    }
    let want: CGFloat = files.isEmpty ? 0 : 60
    if tilesH.constant != want { tilesH.constant = want; superview?.layoutIfNeeded() }
    paintSend()
  }

  // ---------- send ----------
  private func sendTapped() {
    guard hasSomething else { return }
    if editing == nil, files.contains(where: { $0.path == nil && !$0.failed }) { sendEarly(); return }
    let a = text.attributedText ?? NSAttributedString()
    let html = DescEditor.html(a), plain = (text.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    var body: [String: Any] = ["act": editing != nil ? "editComment" : "comment", "id": taskId, "html": html, "text": plain]
    if let e = editing { body["value"] = e } else {
      body["files"] = files.compactMap { f in f.path.map { ["name": f.name, "size": f.size, "path": $0] as [String: Any] } }
      if let p = parentId ?? replyTo?.id { body["parentId"] = p }
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    right.isEnabled = false
    onSend?(body) { [weak self] ok in
      guard let self = self else { return }
      self.right.isEnabled = true
      if ok { UINotificationFeedbackGenerator().notificationOccurred(.success); self.clear() }
    }
  }
  // sent while files are still uploading (Haris, 2026-11-02): the comment goes into the feed at once, its cards pulsing
  // with their rings; it's sent to the server the moment the last one is up (one that fails: the comment doesn't go)
  private func sendEarly() {
    let a = text.attributedText ?? NSAttributedString()
    let html = DescEditor.html(a), plain = (text.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let keep = files.filter { !$0.failed }
    var body: [String: Any] = ["act": "comment", "id": taskId, "html": html, "text": plain]
    let thread = parentId ?? replyTo?.id
    if let p = thread { body["parentId"] = p }
    let pendingId = "pending-" + UUID().uuidString
    let cards: [[String: Any]] = keep.map { f in
      var c: [String: Any] = ["id": f.uid, "name": f.name, "size": f.size, "pending": f.path == nil]
      if f.thumb != nil { FeedLoader.shared.setLocal("local:" + f.uid, f.thumb!); c["thumbUrl"] = "local:" + f.uid }
      return c
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    outbox.append((pendingId: pendingId, body: body, files: keep.map { (uid: $0.uid, name: $0.name, size: $0.size) }))
    onPendingFiles?(pendingId, thread, plain, cards)
    clear()
    flushOutbox()
  }
  private func flushOutbox() {
    for o in outbox {
      if o.files.contains(where: { upFailed.contains($0.uid) }) {
        outbox.removeAll { $0.pendingId == o.pendingId }
        onPendingEnd?(o.pendingId, false); onToast?("A file didn’t upload, so the comment wasn’t sent — try again")
        continue
      }
      guard o.files.allSatisfy({ upDone[$0.uid] != nil }) else { continue }
      outbox.removeAll { $0.pendingId == o.pendingId }
      var body = o.body
      body["files"] = o.files.map { ["name": $0.name, "size": $0.size, "path": upDone[$0.uid]!] as [String: Any] }
      onSend?(body) { [weak self] ok in
        self?.onPendingEnd?(o.pendingId, ok)
        if ok { Main.playUploaded(); UINotificationFeedbackGenerator().notificationOccurred(.success) }
      }
    }
  }
  // what's written but not sent stays with its task (and thread) while the app is open
  private static var drafts: [String: NSAttributedString] = [:]
  private var draftKey = ""
  func switchTo(task: String, parent: String?) {
    if !draftKey.isEmpty, editing == nil { ComposeBox.drafts[draftKey] = text.attributedText }
    taskId = task; parentId = parent
    draftKey = task + "|" + (parent ?? "")
    if editing == nil { setText(ComposeBox.drafts[draftKey] ?? NSAttributedString(string: "")) }
  }
  func clear() {
    if !draftKey.isEmpty { ComposeBox.drafts[draftKey] = nil }
    text.attributedText = NSAttributedString(string: ""); files = []; replyTo = nil; editing = nil; paintTiles(); textViewDidChange(text) }

  // ---------- voice: hold to record, slide left to cancel, up to lock ----------
  private var holdG: UILongPressGestureRecognizer?
  private var recorder: AVAudioRecorder?, recURL: URL?, recStart = Date(), recTimer: Timer?, locked = false, cancelled = false
  private let recView = UIView(), recDot = UIView(), recTime = UILabel(), recWave = UIStackView(), recHint = UILabel()
  private let lockTrash = UIButton(type: .system), lockSend = UIButton(type: .system)
  @objc private func holdMic(_ g: UILongPressGestureRecognizer) {
    let p = g.location(in: box), start = CGPoint(x: right.frame.midX, y: right.frame.midY)
    switch g.state {
    case .began: startRecording()
    case .changed:
      guard recorder != nil, !locked else { return }
      let dx = p.x - start.x, dy = p.y - start.y
      recHint.alpha = max(0.3, 1 + dx / 160)
      if dx < -110 { cancelled = true; stopRecording(send: false); UINotificationFeedbackGenerator().notificationOccurred(.warning) }
      else if dy < -70 { lockRecording() }
    case .ended: if recorder != nil && !locked { stopRecording(send: !cancelled) }
    case .cancelled, .failed: if recorder != nil && !locked { stopRecording(send: false) }
    default: break
    }
  }
  private func startRecording() {
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] ok in
      DispatchQueue.main.async {
        guard let self = self else { return }
        guard ok else { self.onToast?("Allow the microphone in Settings to record"); return }
        guard self.holdG?.state == .began || self.holdG?.state == .changed else { return }   // (let go already)
        do {
          try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
          try AVAudioSession.sharedInstance().setActive(true)
          let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
          let r = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
          r.isMeteringEnabled = true
          r.record()
          self.recorder = r; self.recURL = url; self.recStart = Date(); self.locked = false; self.cancelled = false
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          self.showRecording()
        } catch { self.onToast?("Couldn’t start recording") }
      }
    }
  }
  private func showRecording() {
    recView.subviews.forEach { $0.removeFromSuperview() }
    recView.backgroundColor = .secondarySystemGroupedBackground; recView.layer.cornerRadius = 30; recView.clipsToBounds = true
    recView.frame = box.bounds; box.addSubview(recView)
    recDot.backgroundColor = .systemRed; recDot.layer.cornerRadius = 5; recDot.frame = CGRect(x: 18, y: 22, width: 10, height: 10)
    recTime.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium); recTime.frame = CGRect(x: 36, y: 12, width: 50, height: 30); recTime.text = "0:00"
    recWave.spacing = 2; recWave.alignment = .center; recWave.frame = CGRect(x: 92, y: 12, width: box.bounds.width - 160, height: 30)
    recWave.arrangedSubviews.forEach { $0.removeFromSuperview() }
    recHint.text = "‹ Slide to cancel"; recHint.font = .systemFont(ofSize: 14); recHint.textColor = .secondaryLabel; recHint.frame = CGRect(x: 92, y: box.bounds.height - 44, width: 160, height: 36)
    [recDot, recTime, recWave, recHint].forEach { recView.addSubview($0) }
    UIView.animate(withDuration: 0.6, delay: 0, options: [.repeat, .autoreverse]) { self.recDot.alpha = 0.25 }
    recTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.meter() }
    box.bringSubviewToFront(right)
  }
  private func meter() {
    guard let r = recorder else { return }
    r.updateMeters()
    let s = Int(Date().timeIntervalSince(recStart)); recTime.text = String(format: "%d:%02d", s / 60, s % 60)
    let lvl = CGFloat(max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50)))
    let bar = UIView(); bar.backgroundColor = .systemBlue; bar.layer.cornerRadius = 1.5
    bar.translatesAutoresizingMaskIntoConstraints = false
    bar.widthAnchor.constraint(equalToConstant: 3).isActive = true; bar.heightAnchor.constraint(equalToConstant: 4 + lvl * 24).isActive = true
    recWave.addArrangedSubview(bar)
    let maxBars = Int(recWave.bounds.width / 5)
    while recWave.arrangedSubviews.count > maxBars { recWave.arrangedSubviews.first?.removeFromSuperview() }
    if s >= 300 { lockedSend() }   // (5 minutes at most)
  }
  private func lockRecording() {
    locked = true
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    recHint.isHidden = true
    // locked: 🗑 on the left, ↑ on the right (the finger can go)
    lockTrash.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
    lockTrash.tintColor = .label; lockTrash.backgroundColor = .tertiarySystemFill; lockTrash.layer.cornerRadius = 18
    lockTrash.frame = plus.frame
    lockTrash.addAction(UIAction { [weak self] _ in self?.stopRecording(send: false) }, for: .touchUpInside)
    lockSend.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
    lockSend.tintColor = .white; lockSend.backgroundColor = .systemBlue; lockSend.layer.cornerRadius = 18
    lockSend.frame = right.frame
    lockSend.addAction(UIAction { [weak self] _ in self?.lockedSend() }, for: .touchUpInside)
    recView.addSubview(lockTrash); recView.addSubview(lockSend)
    recView.frame = box.bounds
    box.bringSubviewToFront(recView)
  }
  private func lockedSend() { stopRecording(send: true) }
  private func stopRecording(send: Bool) {
    guard let r = recorder, let url = recURL else { return }
    let dur = r.currentTime
    r.stop(); recorder = nil; recTimer?.invalidate(); recTimer = nil
    recDot.layer.removeAllAnimations()
    recView.removeFromSuperview(); lockTrash.removeFromSuperview(); lockSend.removeFromSuperview(); recHint.isHidden = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    guard send, dur >= 0.8 else { if send { onToast?("Hold to record, let go to send") }; try? FileManager.default.removeItem(at: url); return }
    // straight up, then sent as its own comment (a reply where the box is replying)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let name = "Voice message.m4a"
    // (in the comments at once, pulsing while it goes up)
    let pendingId = "pending-" + UUID().uuidString
    let thread = parentId ?? replyTo?.id   // (a reply shows in its thread, not in the list)
    onPending?(pendingId, thread, dur)
    Uploader.send(url, name: name, task: taskId, cookies: cookies, progress: { _ in }) { [weak self] path in
      guard let self = self else { return }
      try? FileManager.default.removeItem(at: url)
      guard let p = path else { self.onPendingEnd?(pendingId, false); self.onToast?("The voice message didn’t upload — try again"); return }
      let size = 0
      var body: [String: Any] = ["act": "comment", "id": self.taskId, "html": "", "text": "", "files": [["name": name, "size": size, "path": p, "voice": true, "dur": dur]]]
      if let pid = self.parentId ?? self.replyTo?.id { body["parentId"] = pid }
      self.onSend?(body) { ok in self.onPendingEnd?(pendingId, ok); if ok { UINotificationFeedbackGenerator().notificationOccurred(.success); self.replyTo = nil } }
    }
  }
}

// a voice message in the feed: ▶ · waveform filling blue as it plays · 0:14 / 0:38
final class VoiceBubble: UIView, AVAudioPlayerDelegate {
  private let play = UIButton(type: .system), time = UILabel(), wave = UIStackView(), icon = UIImageView()
  private var player: AVAudioPlayer?, timer: Timer?
  private let path: String, dur: Int
  private var bars: [UIView] = []
  init(path: String, dur: Int, pending: Bool = false) {
    self.path = path; self.dur = dur
    super.init(frame: .zero)
    defer {
      // uploading: the same pill (blue ▶, its length) pulsing softly; it can't be played until it's there
      if pending {
        play.isUserInteractionEnabled = false
        icon.image = VoiceBubble.sym("ellipsis")
        icon.addSymbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
        let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 1; a.toValue = 0.45; a.duration = 0.75
        a.autoreverses = true; a.repeatCount = .infinity; a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(a, forKey: "uploading")
      }
    }
    backgroundColor = .tertiarySystemFill; layer.cornerRadius = 22
    heightAnchor.constraint(equalToConstant: 46).isActive = true
    widthAnchor.constraint(equalToConstant: 260).isActive = true
    // (the ▶ is a picture of its own in the circle, so it can change smoothly: ••• → ▶, ▶ ⇄ ❙❙)
    icon.image = VoiceBubble.sym("play.fill"); icon.tintColor = .white; icon.contentMode = .center; icon.isUserInteractionEnabled = false
    icon.translatesAutoresizingMaskIntoConstraints = false; play.addSubview(icon)
    NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: play.centerXAnchor), icon.centerYAnchor.constraint(equalTo: play.centerYAnchor)])
    play.backgroundColor = .systemBlue; play.layer.cornerRadius = 17
    play.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
    wave.spacing = 2; wave.alignment = .center
    for i in 0..<28 {
      let h = 5 + CGFloat(abs(sin(Double(i) * 1.7) * cos(Double(i) * 0.45))) * 18
      let b = UIView(); b.backgroundColor = .secondaryLabel; b.layer.cornerRadius = 1.5
      b.translatesAutoresizingMaskIntoConstraints = false; b.widthAnchor.constraint(equalToConstant: 3).isActive = true; b.heightAnchor.constraint(equalToConstant: h).isActive = true
      wave.addArrangedSubview(b); bars.append(b)
    }
    time.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium); time.textColor = .secondaryLabel; time.text = VoiceBubble.fmt(dur)
    let h = UIStackView(arrangedSubviews: [play, wave, time]); h.spacing = 8; h.alignment = .center
    h.translatesAutoresizingMaskIntoConstraints = false; addSubview(h)
    NSLayoutConstraint.activate([play.widthAnchor.constraint(equalToConstant: 34), play.heightAnchor.constraint(equalToConstant: 34), h.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), h.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), h.centerYAnchor.constraint(equalTo: centerYAnchor)])
  }
  required init?(coder: NSCoder) { fatalError() }
  static func sym(_ n: String) -> UIImage? { UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)) }
  // sent (Haris, 2026-11-02): it starts as the pulsing one was — dimmer, ••• — and settles: the pulse eases out and the
  // ••• turns into ▶ (iPhone's own symbol change)
  func arrived() {
    alpha = 0.7
    icon.image = VoiceBubble.sym("ellipsis")
    icon.addSymbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
    play.isUserInteractionEnabled = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self = self else { return }
      UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { self.alpha = 1 }
      self.icon.removeAllSymbolEffects()
      self.icon.setSymbolImage(VoiceBubble.sym("play.fill")!, contentTransition: .replace.downUp)
      self.play.isUserInteractionEnabled = true
    }
  }
  static func fmt(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
  private func toggle() {
    if let p = player, p.isPlaying { p.pause(); paint(false); return }
    if let p = player { p.play(); paint(true); return }
    play.isEnabled = false
    FeedLoader.shared.data(path) { [weak self] d in
      guard let self = self else { return }
      self.play.isEnabled = true
      guard let d = d, let p = try? AVAudioPlayer(data: d) else { return }
      try? AVAudioSession.sharedInstance().setCategory(.playback)
      p.delegate = self; self.player = p; p.play(); self.paint(true)
    }
  }
  private func paint(_ playing: Bool) {
    if let i = VoiceBubble.sym(playing ? "pause.fill" : "play.fill") { icon.setSymbolImage(i, contentTransition: .replace.downUp) }
    timer?.invalidate()
    if playing { timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.progress() } }
  }
  private func progress() {
    guard let p = player, p.duration > 0 else { return }
    let f = p.currentTime / p.duration, n = Int(Double(bars.count) * f)
    for (i, b) in bars.enumerated() { b.backgroundColor = i < n ? .systemBlue : .secondaryLabel }
    time.text = VoiceBubble.fmt(Int(p.currentTime)) + " / " + VoiceBubble.fmt(Int(p.duration))
  }
  func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) { paint(false); p.currentTime = 0; bars.forEach { $0.backgroundColor = .secondaryLabel }; time.text = VoiceBubble.fmt(Int(p.duration)) }
}

// what Copy in a preview put on the clipboard: its name (pasted into a comment, the file keeps it)
enum FileClip {
  static var name: String?, change = -1
  static var file: [String: Any]?   // the server's file (Copy in a preview / a file's menu): pasted, that same file
  // (the copy's own: by the clipboard's count, or — when iPhone has moved that on, e.g. syncing the clipboard to your other
  //  devices — by what's on it: "📎 name"; it pasted as those words — Haris, 2026-11-02)
  static var current: [String: Any]? {
    guard let f = file, let n = name else { return nil }
    if change == UIPasteboard.general.changeCount { return f }
    return UIPasteboard.general.hasStrings && UIPasteboard.general.string == "📎 " + n ? f : nil
  }
}
// the comment box's text: a pasted picture or file goes in as an attachment; words paste as words
final class PasteTextView: UITextView {
  var onPasteFiles: (() -> Bool)?
  private var hasFiles: Bool {
    let pb = UIPasteboard.general
    return FileClip.current != nil || pb.hasImages || pb.types.contains { t in guard let u = UTType(t) else { return false }; return !u.conforms(to: .text) && (u.conforms(to: .data) || u.conforms(to: .content)) }
  }
  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(paste(_:)) && hasFiles { return true }
    return super.canPerformAction(action, withSender: sender)
  }
  override func paste(_ sender: Any?) {
    if hasFiles, onPasteFiles?() == true { return }
    super.paste(sender)
  }
}
