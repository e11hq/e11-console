import UIKit
import AVFoundation
import UniformTypeIdentifiers

/* The comment box, the app's own (step 3, Haris 2026-10-31 / 2026-11-01): the Claude app's box — rounded, 16 from
   each side, + on the left (Apple's menu: Camera · Photos · Files), the mic on the right turning into ↑ once something is typed.
   Replying-to line above it, @ people listed above it, waiting files as tiles inside it with their upload bar.
   Voice messages WhatsApp's way: hold the mic to record (red dot, timer, live waveform), slide left to cancel, slide up
   to lock and let go (then 🗑 or ↑). Sent straight to the server (/api/home/act comment / editComment); files and
   voice uploaded by the app itself. */
// every upload in the app, as the downloads: one bar at the bottom — what's going up, how much of how much, and Cancel
// (Haris 2026-11-09: "upload progress … and cancel same as download, to all uploads")
final class UploadCenter {
  static let shared = UploadCenter()
  struct Job { var name: String; var size: Int64; var sent: Int64; var cancelled: Bool }
  private(set) var jobs: [UUID: Job] = [:]
  func begin(_ name: String, _ size: Int64) -> UUID { let id = UUID(); jobs[id] = Job(name: name, size: size, sent: 0, cancelled: false); Main.shared.paintUploadHUD(); return id }
  func step(_ id: UUID, _ sent: Int64) { guard jobs[id] != nil else { return }; jobs[id]?.sent = sent; Main.shared.paintUploadHUD() }
  func end(_ id: UUID) { jobs[id] = nil; Main.shared.paintUploadHUD() }
  func cancelled(_ id: UUID) -> Bool { jobs[id]?.cancelled ?? true }
  private(set) var cancels = 0   // (how many times Cancel was tapped — a run of uploads stops when it changes)
  func cancelAll() { cancels += 1; for k in jobs.keys { jobs[k]?.cancelled = true }; Main.shared.paintUploadHUD() }
}
enum Uploader {
  // a file on the phone → the server (2 MB at a time) → its path there. Cancel (the bar at the bottom): it stops before
  // the next piece and says it didn't go (done(nil)), as a failed upload
  static func send(_ url: URL, name: String, task: String, dest: String? = nil, cookies: @escaping (@escaping (String) -> Void) -> Void, progress: @escaping (Double) -> Void, done: @escaping (String?) -> Void) {
    let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    let job = UploadCenter.shared.begin(name, size)
    let finish: (String?) -> Void = { p in UploadCenter.shared.end(job); done(p) }
    func piece(_ offset: Int64, _ path: String?) {
      if UploadCenter.shared.cancelled(job) { return finish(nil) }
      guard let fh = try? FileHandle(forReadingFrom: url) else { return finish(nil) }
      try? fh.seek(toOffset: UInt64(offset))
      let data = (try? fh.read(upToCount: 2 * 1024 * 1024)) ?? Data()
      try? fh.close()
      var q = URLComponents(string: serverURL() + "/api/host/writeChunkBin")!
      // (into a Client Assets folder: its place on the server, dest — Client Assets on the phone, shell 32)
      var qi = [URLQueryItem(name: dest == nil ? "taskId" : "dest", value: dest ?? task), URLQueryItem(name: "name", value: name), URLQueryItem(name: "offset", value: String(offset))]
      if let p = path { qi.append(URLQueryItem(name: "path", value: p)) }
      q.queryItems = qi
      cookies { c in
        var r = URLRequest(url: q.url!); r.httpMethod = "POST"; r.httpBody = data
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type"); if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
        URLSession.shared.dataTask(with: r) { d, resp, _ in
          let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
          DispatchQueue.main.async {
            guard ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200, let p = j?["path"] as? String else { return finish(nil) }
            let next = offset + Int64(data.count)
            UploadCenter.shared.step(job, next)
            progress(size > 0 ? Double(next) / Double(size) : 1)
            if next < size && !data.isEmpty { piece(next, p) } else { finish(p) }
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
  var filesFor: (() -> [[String: Any]])?   // the task's files, for # (Haris 2026-11-02: picked, a card on the comment)
  var cookies: (@escaping (String) -> Void) -> Void = { $0("") }
  var onSend: (([String: Any], @escaping (Bool) -> Void) -> Void)?   // the act body → sent?
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
  private let mentions = PickList()
  private var files: [DraftFile] = []
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
    else { glass.effect = UIBlurEffect(style: .systemThickMaterial); box.layer.borderWidth = 1; box.followLook("border") { [weak box] tc in box?.layer.setBorder(UIColor.separator.withAlphaComponent(0.4), tc) } }
    glass.layer.cornerRadius = 30; glass.layer.cornerCurve = .continuous; glass.clipsToBounds = true
    glass.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(glass)
    NSLayoutConstraint.activate([glass.leadingAnchor.constraint(equalTo: box.leadingAnchor), glass.trailingAnchor.constraint(equalTo: box.trailingAnchor), glass.topAnchor.constraint(equalTo: box.topAnchor), glass.bottomAnchor.constraint(equalTo: box.bottomAnchor)])
    text.font = .systemFont(ofSize: 17); text.backgroundColor = .clear; text.delegate = self
    text.onPasteFiles = { [weak self] in self?.pasteFiles() ?? false }
    text.onPasteRich = { [weak self] runs in self?.pasteRich(runs) ?? false }
    text.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0); text.textContainer.lineFragmentPadding = 0
    text.isScrollEnabled = false
    placeholder.text = "Comment"; placeholder.font = .systemFont(ofSize: 17); placeholder.textColor = .secondaryLabel
    for (b, sym) in [(plus, "plus"), (right, "mic")] {
      b.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
      b.tintColor = .label; b.backgroundColor = .tertiarySystemFill; b.layer.cornerRadius = 18
    }
    // (+ opens Apple's own menu — Camera · Photos · Files — then Apple's camera, photo picker and Files: Haris 2026-11-09)
    let src: (String, String, String) -> UIAction = { key, title, sym in
      UIAction(title: title, image: UIImage(systemName: sym)) { [weak self] _ in self?.attach(key) }
    }
    plus.menu = UIMenu(children: [src("camera", "Camera", "camera"), src("photos", "Photos", "photo.on.rectangle"), src("files", "Files", "folder")])
    plus.showsMenuAsPrimaryAction = true
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
    mentions.isHidden = true
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
      plus.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8), plus.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8), plus.widthAnchor.constraint(equalToConstant: 36), plus.heightAnchor.constraint(equalToConstant: 36),
      right.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8), right.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8), right.widthAnchor.constraint(equalToConstant: 36), right.heightAnchor.constraint(equalToConstant: 36),
      // "(picture) Replying to Sara ✕": a grey pill filling the buttons' row between + and ↑ (mock-up "Task Comments — fully
      // Apple", approved 2026-11-09)
      replyPill.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 8), replyPill.centerYAnchor.constraint(equalTo: plus.centerYAnchor),
      replyPill.heightAnchor.constraint(equalToConstant: 36), replyPill.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
      { let f = self.replyPill.trailingAnchor.constraint(equalTo: self.right.leadingAnchor, constant: -8); f.priority = .defaultHigh; return f }(),
    ])
    // the two shapes (Haris 2026-11-04): compact — one pill, + · "Comment or hold to talk" · mic — unless the keyboard is up,
    // something is typed, files are attached or a voice message is recording; then the full box, as before
    fullCons = [plus.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 6),
                placeholder.leadingAnchor.constraint(equalTo: text.leadingAnchor), placeholder.topAnchor.constraint(equalTo: text.topAnchor, constant: 4)]
    compactCons = [plus.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
                   placeholder.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 12), placeholder.centerYAnchor.constraint(equalTo: plus.centerYAnchor),
                   placeholder.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8)]
    NSLayoutConstraint.activate(compactCons); text.alpha = 0; tilesScroll.alpha = 0; replyPill.alpha = 0
    self.tilesScroll = tilesScroll
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
  private var fullCons: [NSLayoutConstraint] = [], compactCons: [NSLayoutConstraint] = []
  private(set) var compact = true
  private weak var tilesScroll: UIScrollView?
  private var wantsCompact: Bool { !text.isFirstResponder && (text.text ?? "").isEmpty && files.isEmpty && recorder == nil }
  // (from one shape to the other with the box's own spring, as the keyboard moves it)
  func paintShape(animated: Bool = true) {
    let c = wantsCompact
    guard c != compact else { return }
    compact = c
    if c { NSLayoutConstraint.deactivate(fullCons); NSLayoutConstraint.activate(compactCons) } else { NSLayoutConstraint.deactivate(compactCons); NSLayoutConstraint.activate(fullCons) }
    let fade = { self.text.alpha = c ? 0 : 1; self.tilesScroll?.alpha = c ? 0 : 1; self.replyPill.alpha = c ? 0 : 1 }
    if animated && window != nil {
      UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { fade(); self.superview?.layoutIfNeeded() }
    } else { fade(); superview?.layoutIfNeeded() }
  }
  func textViewDidBeginEditing(_ tv: UITextView) { paintShape() }
  func textViewDidEndEditing(_ tv: UITextView) { DispatchQueue.main.async { [weak self] in self?.paintShape() } }
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
      // (the mic as a line icon — Haris 2026-11-02; the change a little quicker than iPhone's default)
      let img = UIImage(systemName: send ? "arrow.up" : "mic", withConfiguration: UIImage.SymbolConfiguration(pointSize: send ? 14 : 15, weight: send ? .bold : .medium))
      if #available(iOS 17.0, *), !first, let iv = right.imageView, let img = img {
        iv.setSymbolImage(img, contentTransition: .replace.downUp, options: .speed(1.6))
        right.setImage(img, for: .normal)
      } else { right.setImage(img, for: .normal) }
      let paint = { self.right.backgroundColor = send ? .label : .tertiarySystemFill; self.right.tintColor = send ? .systemBackground : .label }
      if first { paint() } else { UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: paint) }
    }
    holdG?.isEnabled = !send
    placeholder.isHidden = !(text.text ?? "").isEmpty
    placeholder.text = parentId != nil || replyTo != nil ? "Reply or hold to talk" : "Comment or hold to talk"
    paintShape()
  }
  @objc private func tappedBox() { if !text.isFirstResponder { text.becomeFirstResponder() } }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
    var v = t.view
    while let x = v, x !== box { if x is UIControl || x === text || x === tiles { return false }; v = x.superview }
    return true
  }
  // Coming in (Haris, 2026-11-02): her picture fades in in a small round pill by the +, then the pill stretches to the
  // right, and the words fade in — iPhone's spring. Cancelled: the same, backwards.
  private lazy var pillNarrow = replyPill.widthAnchor.constraint(equalToConstant: 36)
  private var pillShownFor: String?
  private func paintReply() {
    replyLine.isHidden = true
    replyPill.clipsToBounds = true
    guard let r = replyTo else {
      guard pillShownFor != nil, !replyPill.isHidden, window != nil else { pillShownFor = nil; replyPill.isHidden = true; paintSend(); return }
      pillShownFor = nil
      let words = replyPill.viewWithTag(51)
      UIView.animate(withDuration: 0.12) { words?.alpha = 0 }
      pillNarrow.isActive = true
      UIView.animate(withDuration: 0.36, delay: 0.04, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { self.box.layoutIfNeeded() } completion: { _ in
        guard self.replyTo == nil else { return }
        UIView.animate(withDuration: 0.16, animations: { self.replyPill.alpha = 0; self.replyPill.transform = CGAffineTransform(scaleX: 0.7, y: 0.7) }) { _ in
          guard self.replyTo == nil else { return }
          self.replyPill.isHidden = true; self.replyPill.alpha = 1; self.replyPill.transform = .identity; self.pillNarrow.isActive = false
        }
      }
      paintSend(); return
    }
    let coming = pillShownFor == nil && window != nil
    pillShownFor = r.id
    replyPill.subviews.forEach { $0.removeFromSuperview() }
    replyPill.isHidden = false
    do {
      // one line, as the mock-up (Haris 2026-11-09): their picture, "Replying to Sara", and ✕ at the end — the pill tapped
      // stops replying
      let l = UILabel(); l.isUserInteractionEnabled = false
      let a = NSMutableAttributedString(string: "Replying to ", attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.label])
      a.append(NSAttributedString(string: r.name, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.label]))
      l.attributedText = a; l.lineBreakMode = .byTruncatingTail
      l.setContentCompressionResistancePriority(UILayoutPriority(740), for: .horizontal)
      let x = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
      x.tintColor = .secondaryLabel; x.isUserInteractionEnabled = false; x.setContentHuggingPriority(.required, for: .horizontal)
      let words = UIStackView(arrangedSubviews: [l, UIView(), x]); words.spacing = 6; words.alignment = .center; words.isUserInteractionEnabled = false; words.tag = 51
      let av = CommentCell.avatar(replyPerson ?? ["initials": String(r.name.prefix(1)).uppercased()], 26); av.isUserInteractionEnabled = false
      let row = UIStackView(arrangedSubviews: [av, words]); row.spacing = 7; row.alignment = .center; row.isUserInteractionEnabled = false
      row.translatesAutoresizingMaskIntoConstraints = false; replyPill.addSubview(row)
      // (while it's a small circle, only the picture shows — the words past its right edge, as it stretches out)
      let trail = row.trailingAnchor.constraint(equalTo: replyPill.trailingAnchor, constant: -12); trail.priority = .defaultHigh
      NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: replyPill.leadingAnchor, constant: 5), trail, row.centerYAnchor.constraint(equalTo: replyPill.centerYAnchor)])
      replyPill.accessibilityLabel = "Replying to \(r.name). Tap to stop replying"
      if coming {
        pillNarrow.isActive = true
        words.alpha = 0; replyPill.alpha = 0; replyPill.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        box.layoutIfNeeded()
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { self.replyPill.alpha = 1; self.replyPill.transform = .identity }
        pillNarrow.isActive = false
        UIView.animate(withDuration: 0.5, delay: 0.14, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { self.box.layoutIfNeeded() }
        UIView.animate(withDuration: 0.28, delay: 0.3, options: [.curveEaseOut, .allowUserInteraction]) { words.alpha = 1 }
      } else { pillNarrow.isActive = false }
    }
    paintSend()
  }
  func textViewDidChange(_ tv: UITextView) {
    let h = min(max(30, tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)).height), 130)
    tv.isScrollEnabled = h >= 130
    if textH.constant != h { textH.constant = h; superview?.layoutIfNeeded() }
    // (what's written kept on the phone a moment after typing stops)
    draftSave?.cancel()
    let w = DispatchWorkItem { [weak self] in guard let self = self, !self.draftKey.isEmpty, self.editing == nil else { return }; self.keepCurrent() }
    draftSave = w; DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    paintSend()
    lookForMention()
  }
  // (typing after a mention, or where one was deleted: plain words again, not the mention's blue — Haris 2026-11-02)
  func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText t: String) -> Bool {
    if !t.isEmpty, tv.typingAttributes[MENTION_KEY] != nil || (tv.typingAttributes[.foregroundColor] as? UIColor) == .systemBlue {
      tv.typingAttributes = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label]
    }
    return true
  }
  func setText(_ a: NSAttributedString) { text.attributedText = a; textViewDidChange(text) }

  // ---------- @ people (above the box) ----------
  private func lookForMention() {
    let r = text.selectedRange
    let before = (text.text as NSString).substring(to: min(r.location, (text.text as NSString).length))
    if let m = before.range(of: "(^|\\s)#([^\\s#@]*)$", options: .regularExpression) {
      let typed = String(before[m]).trimmingCharacters(in: .whitespacesAndNewlines)
      let hits = DescEditor.fileHits(filesFor?() ?? [], String(typed.dropFirst()).lowercased())
      guard !hits.isEmpty else { mentions.isHidden = true; return }
      let at = (before as NSString).length - (typed as NSString).length
      mentions.rows = hits.map { f in PickList.file(f) { [weak self] in self?.pickFile(f, at: at) } }
      mentions.isHidden = false
      return
    }
    guard let m = before.range(of: "@([A-Za-z]*)$", options: .regularExpression) else { mentions.isHidden = true; return }
    let q = String(before[m].dropFirst()).lowercased()
    let hits = mentionable.filter { q.isEmpty || ($0["name"] as? String ?? "").lowercased().split(separator: " ").contains { $0.hasPrefix(q) } }.prefix(4)
    guard !hits.isEmpty else { mentions.isHidden = true; return }
    let at = (before as NSString).length - q.count - 1
    mentions.rows = hits.map { p in PickList.person(p) { [weak self] in self?.insertMention(p, at: at) } }
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

  // a file picked from the # list: the #word goes, the file is added to this comment as a card (the same file)
  private func pickFile(_ f: [String: Any], at: Int) {
    let r = text.selectedRange
    let m = NSMutableAttributedString(attributedString: text.attributedText)
    m.deleteCharacters(in: NSRange(location: at, length: r.location - at))
    text.attributedText = m
    text.selectedRange = NSRange(location: at, length: 0)
    text.typingAttributes = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label]
    mentions.isHidden = true
    UISelectionFeedbackGenerator().selectionChanged()
    if let path = f["file"] as? String, !files.contains(where: { $0.path == path }) {
      let uid = UUID().uuidString
      files.append((uid: uid, name: f["name"] as? String ?? "File", size: Int64(f["size"] as? Int ?? 0), path: path, progress: 1, failed: false, thumb: nil))
      upDone[uid] = path
      paintTiles()
      let pic = (f["thumbUrl"] as? String) ?? (CommentCell.isPic(f["name"] as? String ?? "") ? f["url"] as? String : nil)
      if let p = pic { FeedLoader.shared.image(p) { [weak self] img in guard let self = self, let img = img, let i = self.files.firstIndex(where: { $0.uid == uid }) else { return }; self.files[i].thumb = img; self.paintTiles() } }
    }
    textViewDidChange(text)
  }

  // ---------- files ----------
  private func attach(_ source: String) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    guard let vc = window?.rootViewController else { return }
    var top = vc; while let p = top.presentedViewController { top = p }
    Picker.shared.pick(from: top, single: false, source: source) { [weak self] r in
      for f in (r["files"] as? [[String: Any]]) ?? [] {
        guard let self = self, let tok = f["token"] as? String, let url = Picker.shared.url(tok) else { continue }
        self.addFile(url, name: f["name"] as? String ?? "File", voice: nil)
      }
      self?.text.becomeFirstResponder()
    }
  }
  // copied words with mentions or chips: the words and mentions where the cursor is; each chip's file added to the
  // comment, as # does here (Haris 2026-11-02 — a file from another task: the same file, nothing uploaded)
  private func pasteRich(_ runs: [[String: Any]]) -> Bool {
    let words = runs.filter { $0["ref"] == nil }
    let ins = DescEditor.attributed(words, done: false, size: 17)
    let r = text.selectedRange
    let m = NSMutableAttributedString(attributedString: text.attributedText ?? NSAttributedString())
    guard NSMaxRange(r) <= m.length else { return false }
    m.replaceCharacters(in: r, with: ins)
    text.attributedText = m
    text.selectedRange = NSRange(location: r.location + ins.length, length: 0)
    text.typingAttributes = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label]
    let known = filesFor?() ?? []
    for case let f as [String: Any] in runs.compactMap({ $0["ref"] }) {
      guard let path = f["path"] as? String, !files.contains(where: { $0.path == path }) else { continue }
      let uid = UUID().uuidString
      files.append((uid: uid, name: f["name"] as? String ?? "File", size: Int64((f["size"] as? NSNumber)?.intValue ?? 0), path: path, progress: 1, failed: false, thumb: nil))
      upDone[uid] = path
      let k = known.first { ($0["file"] as? String) == path }
      let pic = (k?["thumbUrl"] as? String) ?? (CommentCell.isPic(f["name"] as? String ?? "") ? k?["url"] as? String : nil)
      if let p = pic { FeedLoader.shared.image(p) { [weak self] img in guard let self = self, let img = img, let i = self.files.firstIndex(where: { $0.uid == uid }) else { return }; self.files[i].thumb = img; self.paintTiles() } }
    }
    paintTiles()
    textViewDidChange(text)
    return true
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
      } else { self.updateDraftFile(uid, path: path) }
      if path != nil, !waiting { Main.playUploaded(); UINotificationFeedbackGenerator().notificationOccurred(.success) }
      if path == nil, !waiting { self.onToast?("Upload failed — try again") }
      self.flushOutbox()
    }
  }
  // (each file's tile kept while it shows the same — an upload's progress makes only its own tile again, at each whole
  //  percent; the others stay: only what changed changes, Haris 2026-11-08)
  private var tileMade: [String: (view: UIView, sig: String)] = [:]
  private func paintTiles() {
    var views: [UIView] = []
    var keep = tileMade; tileMade = [:]
    for f in files {
      let sig = "\(Int(f.progress * 100))|\(f.failed)|\(f.thumb != nil)|\(f.name)"
      if let k = keep.removeValue(forKey: f.uid) {
        if k.sig == sig { tileMade[f.uid] = k; views.append(k.view); continue }
        k.view.removeFromSuperview()
      }
      let t = makeTile(f)
      tileMade[f.uid] = (t, sig); views.append(t)
    }
    keep.values.forEach { $0.view.removeFromSuperview() }
    for v in tiles.arrangedSubviews where !views.contains(where: { $0 === v }) { v.removeFromSuperview() }
    for (i, v) in views.enumerated() where i >= tiles.arrangedSubviews.count || tiles.arrangedSubviews[i] !== v { tiles.insertArrangedSubview(v, at: i) }
    let want: CGFloat = files.isEmpty ? 0 : 68   // (the 64 tiles, a little room under)
    if tilesH.constant != want { tilesH.constant = want; superview?.layoutIfNeeded() }
    paintSend()
  }
  private func makeTile(_ f: DraftFile) -> UIView {
    do {
      let uid = f.uid
      let t = UIView(); t.backgroundColor = .tertiarySystemFill; t.layer.cornerRadius = 12
      t.translatesAutoresizingMaskIntoConstraints = false
      // (64, as the mock-up — Haris 2026-11-10: a picture itself; any other file its type badge with its name under it)
      let S: CGFloat = 64
      t.widthAnchor.constraint(equalToConstant: S).isActive = true; t.heightAnchor.constraint(equalToConstant: S).isActive = true
      let ext = (f.name as NSString).pathExtension.uppercased()
      let l = UILabel(); l.text = ""; l.font = .systemFont(ofSize: 11, weight: .bold); l.textColor = .secondaryLabel; l.textAlignment = .center
      l.frame = CGRect(x: 0, y: 0, width: S, height: S)
      if f.thumb == nil {
        let badge = PaddedLabel(); badge.text = ext.isEmpty ? "FILE" : String(ext.prefix(4)); badge.font = .systemFont(ofSize: 8.5, weight: .bold); badge.textColor = .white
        badge.backgroundColor = ext == "PDF" ? .systemRed : ext == "AI" ? .systemOrange : .systemGray; badge.layer.cornerRadius = 4; badge.clipsToBounds = true
        badge.textAlignment = .center; badge.frame = CGRect(x: (S - 26) / 2, y: 9, width: 26, height: 30)
        let nm = UILabel(); nm.text = f.name; nm.font = .systemFont(ofSize: 10); nm.textColor = .secondaryLabel; nm.textAlignment = .center; nm.lineBreakMode = .byTruncatingMiddle
        nm.frame = CGRect(x: 4, y: 42, width: S - 8, height: 14)
        t.addSubview(badge); t.addSubview(nm)
      }
      if let th = f.thumb {
        let iv = UIImageView(image: th); iv.contentMode = .scaleAspectFill; iv.clipsToBounds = true; iv.layer.cornerRadius = 12; iv.frame = l.frame; t.addSubview(iv)
        if f.progress < 1 && !f.failed { let dim = UIView(frame: l.frame); dim.backgroundColor = UIColor.black.withAlphaComponent(0.35); dim.layer.cornerRadius = 12; t.addSubview(dim); l.textColor = .white } else { l.isHidden = true }
      }
      t.addSubview(l)
      if f.progress < 1 && !f.failed {
        if f.thumb != nil { l.text = "\(Int(f.progress * 100))%" }
        let bar = UIProgressView(progressViewStyle: .bar); bar.progress = Float(f.progress); bar.frame = CGRect(x: 7, y: S - 9, width: S - 14, height: 3)
        bar.layer.cornerRadius = 1.5; bar.clipsToBounds = true; t.addSubview(bar)
      }
      if f.failed { l.text = "!"; l.font = .systemFont(ofSize: 20, weight: .bold); l.textColor = .systemRed }
      // the ✕: a dark circle with a thin white edge and a white ✕ — clear on any picture, dark or light (as Photos' and
      // Messages' own remove buttons; Haris, 2026-11-02)
      let x = UIButton(type: .custom)
      x.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)), for: .normal); x.tintColor = .white
      x.backgroundColor = UIColor.black.withAlphaComponent(0.62); x.layer.cornerRadius = 11
      x.layer.borderWidth = 1.5; x.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
      x.layer.shadowColor = UIColor.black.cgColor; x.layer.shadowOpacity = 0.25; x.layer.shadowRadius = 2; x.layer.shadowOffset = .zero
      x.frame = CGRect(x: S - 25, y: 3, width: 22, height: 22)   // (inside the tile's corner: nothing of it or its shadow cut off)
      x.addAction(UIAction { [weak self] _ in self?.files.removeAll { $0.uid == uid }; self?.paintTiles() }, for: .touchUpInside)
      t.addSubview(x)
      return t
    }
  }

  // ---------- send ----------
  private func sendTapped() {
    guard hasSomething else { return }
    if editing == nil { CommentSound.send() }   // (a new comment, not an edit: the send sound — Haris 2026-11-09)
    if editing == nil, files.contains(where: { $0.path == nil && !$0.failed }) { sendEarly(); return }
    let a = text.attributedText ?? NSAttributedString()
    let html = DescEditor.html(a), plain = (text.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    var body: [String: Any] = ["act": editing != nil ? "editComment" : "comment", "id": taskId, "html": html, "text": plain]
    if let e = editing { body["value"] = e } else {
      body["files"] = files.compactMap { f in f.path.map { ["name": f.name, "size": f.size, "path": $0] as [String: Any] } }
      if let p = parentId ?? replyTo?.id { body["parentId"] = p }
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let key = draftKey   // (the box may be on another task by the time it's sent — sent from the "not sent" alert)
    // a new comment shows in the list at once and the box empties — the server's answer only confirms it (it took a
    // while: Haris, 2026-11-02); not sent: it goes from the list and the words come back into the box
    if editing == nil, !files.contains(where: { $0.path == nil && !$0.failed }) {
      let pendingId = "pending-" + UUID().uuidString
      let thread = parentId ?? replyTo?.id
      let cards: [[String: Any]] = files.filter { $0.path != nil }.map { f in
        var c: [String: Any] = ["id": f.uid, "name": f.name, "size": f.size, "pending": false]
        if let t = f.thumb { FeedLoader.shared.setLocal("local:" + f.uid, t); c["thumbUrl"] = "local:" + f.uid }
        return c
      }
      let keep = (text: a, files: files, reply: replyTo)
      onPendingFiles?(pendingId, thread, plain, cards)
      if key == draftKey { clear() } else { ComposeBox.drafts[key] = nil; ComposeBox.acked[key] = nil; ComposeBox.saveDrafts() }
      onSend?(body) { [weak self] ok in
        guard let self = self else { return }
        self.onPendingEnd?(pendingId, ok)
        if ok { UINotificationFeedbackGenerator().notificationOccurred(.success); return }
        if self.draftKey == key, (self.text.text ?? "").isEmpty { self.files = keep.files; self.paintTiles(); self.setText(keep.text); self.replyTo = keep.reply }
      }
      return
    }
    right.isEnabled = false
    onSend?(body) { [weak self] ok in
      guard let self = self else { return }
      self.right.isEnabled = true
      guard ok else { return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      if key == self.draftKey { self.clear() } else { ComposeBox.drafts[key] = nil; ComposeBox.acked[key] = nil; ComposeBox.saveDrafts() }
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
  // what's written but not sent stays with its task (and thread) — its words and its files — kept on the phone, so it's
  // still there after the app is closed (as the website keeps its drafts)
  typealias DraftFile = (uid: String, name: String, size: Int64, path: String?, progress: Double, failed: Bool, thumb: UIImage?)
  private static var drafts: [String: (text: NSAttributedString, files: [DraftFile])] = [:]
  private static var acked: [String: String] = [:]   // "Keep as draft": not asked again until it changes
  private static var draftsLoaded = false
  private var draftKey = ""
  private var draftSave: DispatchWorkItem?
  func switchTo(task: String, parent: String?) {
    ComposeBox.loadDrafts()
    if !draftKey.isEmpty, editing == nil { keepCurrent() }
    taskId = task; parentId = parent
    draftKey = task + "|" + (parent ?? "")
    if editing == nil {
      let d = ComposeBox.drafts[draftKey]
      files = d?.files ?? []; paintTiles()
      setText(d?.text ?? NSAttributedString(string: ""))
    }
  }
  private func keepCurrent() {
    let empty = (text.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty
    if empty { ComposeBox.drafts[draftKey] = nil }
    else { let t: NSAttributedString = text.attributedText ?? NSAttributedString(); ComposeBox.drafts[draftKey] = (text: t, files: files) }
    ComposeBox.saveDrafts()
  }
  func clear() {
    if !draftKey.isEmpty { ComposeBox.drafts[draftKey] = nil; ComposeBox.acked[draftKey] = nil }
    text.attributedText = NSAttributedString(string: ""); files = []; replyTo = nil; editing = nil; paintTiles(); textViewDidChange(text)
    ComposeBox.saveDrafts()
  }
  // ---------- an unsent comment, on leaving its task (Haris, 2026-11-02 — as the website's "Your comment hasn't been sent")
  struct Unsent { let key: String; let words: String; let files: [String]; let uploading: Int; let reply: Bool; let current: Bool }
  private static func sig(_ words: String, _ files: [DraftFile]) -> String { words + "|" + files.map { $0.uid }.joined(separator: ",") }
  // what's written for this task and not sent (the box's own first), unless kept as a draft as it is now
  func unsent(task: String) -> Unsent? {
    guard editing == nil else { return nil }
    if !draftKey.isEmpty { keepCurrent() }
    let keys = ComposeBox.drafts.keys.filter { $0.hasPrefix(task + "|") }.sorted { a, b in (a == draftKey ? 0 : 1, a) < (b == draftKey ? 0 : 1, b) }
    for k in keys {
      guard let d = ComposeBox.drafts[k] else { continue }
      let words = d.text.string.trimmingCharacters(in: .whitespacesAndNewlines)
      if words.isEmpty && d.files.isEmpty { continue }
      if ComposeBox.acked[k] == ComposeBox.sig(words, d.files) { continue }
      let parent = String(k.dropFirst(task.count + 1))
      return Unsent(key: k, words: words, files: d.files.map { $0.name }, uploading: d.files.filter { $0.path == nil && !$0.failed }.count, reply: !parent.isEmpty || (k == draftKey && replyTo != nil), current: k == draftKey)
    }
    return nil
  }
  func keepDraft(_ u: Unsent) { ComposeBox.acked[u.key] = ComposeBox.sig(u.words, ComposeBox.drafts[u.key]?.files ?? []); ComposeBox.saveDrafts() }
  func sendDraft(_ u: Unsent) { if u.current { sendTapped() } }
  // kept on the phone: the words (with their look) and the files already uploaded
  private static func saveDrafts() {
    var out: [String: Any] = [:]
    for (k, d) in drafts {
      let words = (try? NSKeyedArchiver.archivedData(withRootObject: d.text, requiringSecureCoding: false))?.base64EncodedString() ?? ""
      out[k] = ["w": words, "f": d.files.compactMap { f in f.path.map { ["n": f.name, "s": f.size, "p": $0] as [String: Any] } }, "a": acked[k] ?? ""]
    }
    UserDefaults.standard.set(out, forKey: "e11-comment-drafts")
  }
  private static func loadDrafts() {
    guard !draftsLoaded else { return }
    draftsLoaded = true
    for (k, v) in (UserDefaults.standard.dictionary(forKey: "e11-comment-drafts") ?? [:]) {
      guard let d = v as? [String: Any] else { continue }
      let t = (d["w"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: $0) } ?? NSAttributedString()
      let fs: [DraftFile] = ((d["f"] as? [[String: Any]]) ?? []).map { f in (uid: UUID().uuidString, name: f["n"] as? String ?? "File", size: (f["s"] as? NSNumber)?.int64Value ?? 0, path: f["p"] as? String, progress: 1, failed: false, thumb: nil) }
      drafts[k] = (t, fs)
      if let a = d["a"] as? String, !a.isEmpty { acked[k] = a }
    }
  }
  // an upload finishing for a file that's in a kept draft now (the box moved on to another task)
  private func updateDraftFile(_ uid: String, path: String?) {
    for (k, d) in ComposeBox.drafts { if let i = d.files.firstIndex(where: { $0.uid == uid }) {
      var fs = d.files; if let p = path { fs[i].path = p; fs[i].progress = 1 } else { fs[i].failed = true }
      ComposeBox.drafts[k] = (d.text, fs); ComposeBox.saveDrafts()
    } }
  }

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
          self.paintShape(animated: false)   // (the full box first: the recording fills it)
          self.showRecording()
        } catch { self.onToast?("Couldn’t start recording") }
      }
    }
  }
  private func showRecording() {
    recView.subviews.forEach { $0.removeFromSuperview() }
    // (as the mock-up, Haris 2026-11-10: on the box's own glass — the red dot, the time, the wave in grey; "‹ Slide to
    //  cancel" in the buttons' row; the mic grown and red under the finger; the lock above it)
    recView.backgroundColor = .clear; recView.layer.cornerRadius = 30; recView.clipsToBounds = true
    // (the box's own words and pieces go while it records — on the glass they showed through: Haris 2026-11-10)
    underWas = under.map { $0.alpha }
    UIView.animate(withDuration: 0.18) { self.under.forEach { $0.alpha = 0 } }
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
    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      self.right.transform = CGAffineTransform(scaleX: 1.35, y: 1.35); self.right.backgroundColor = .systemRed; self.right.tintColor = .white
    }
    // the lock: slide up to it to let go and keep recording
    lockHint.subviews.forEach { $0.removeFromSuperview() }
    if #available(iOS 26.0, *) { lockHint.effect = UIGlassEffect(style: .regular) } else { lockHint.effect = UIBlurEffect(style: .systemThinMaterial) }
    lockHint.clipsToBounds = true; lockHint.layer.cornerRadius = 20; lockHint.layer.cornerCurve = .continuous
    let lk = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
    let up = UIImageView(image: UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
    [lk, up].forEach { $0.tintColor = .secondaryLabel; $0.contentMode = .center }
    let col = UIStackView(arrangedSubviews: [lk, up]); col.axis = .vertical; col.distribution = .fillEqually
    col.frame = CGRect(x: 0, y: 6, width: 40, height: 64); lockHint.contentView.addSubview(col)
    let r = right.convert(right.bounds, to: self)
    lockHint.frame = CGRect(x: r.midX - 20, y: r.minY - 96, width: 40, height: 76)
    lockHint.alpha = 0; addSubview(lockHint)
    UIView.animate(withDuration: 0.25, delay: 0.1) { self.lockHint.alpha = 1 }
  }
  private let lockHint = UIVisualEffectView(effect: nil)
  // (what's under the recording in the box: the +, the words, the placeholder, the files, the reply line)
  private var underWas: [CGFloat] = []   // (as they were, put back after)
  private var under: [UIView] { [plus, text, placeholder, replyPill] + (tilesScroll.map { [$0] } ?? []) }
  // (the mic back to itself, the + back — recording over or locked)
  private func micBack() {
    UIView.animate(withDuration: 0.22) {
      self.right.transform = .identity; self.lockHint.alpha = 0
      self.right.backgroundColor = self.showingSend == true ? .label : .tertiarySystemFill; self.right.tintColor = self.showingSend == true ? .systemBackground : .label
    } completion: { _ in if self.recorder == nil || self.locked { self.lockHint.removeFromSuperview() } }
  }
  private func meter() {
    guard let r = recorder else { return }
    r.updateMeters()
    let s = Int(Date().timeIntervalSince(recStart)); recTime.text = String(format: "%d:%02d", s / 60, s % 60)
    let lvl = CGFloat(max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50)))
    let bar = UIView(); bar.backgroundColor = .secondaryLabel; bar.layer.cornerRadius = 1.5
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
    micBack()
    // locked: 🗑 on the left, ↑ on the right (the finger can go)
    lockTrash.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
    lockTrash.tintColor = .label; lockTrash.backgroundColor = .tertiarySystemFill; lockTrash.layer.cornerRadius = 18
    lockTrash.frame = plus.frame
    lockTrash.addAction(UIAction { [weak self] _ in self?.stopRecording(send: false) }, for: .touchUpInside)
    lockSend.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
    lockSend.tintColor = .systemBackground; lockSend.backgroundColor = .label; lockSend.layer.cornerRadius = 18   // (as the box's ↑)
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
    defer { DispatchQueue.main.async { [weak self] in self?.paintShape() } }
    recDot.layer.removeAllAnimations()
    recView.removeFromSuperview(); lockTrash.removeFromSuperview(); lockSend.removeFromSuperview(); recHint.isHidden = false
    micBack()
    let was = underWas; underWas = []
    UIView.animate(withDuration: 0.18) { for (v, a) in zip(self.under, was) { v.alpha = a } }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    guard send, dur >= 0.8 else { if send { onToast?("Hold to record, let go to send") }; try? FileManager.default.removeItem(at: url); return }
    // straight up, then sent as its own comment (a reply where the box is replying)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let name = "Voice message.m4a"
    // (in the comments at once, pulsing while it goes up)
    let pendingId = "pending-" + UUID().uuidString
    let thread = parentId ?? replyTo?.id   // (a reply shows in its thread, not in the list)
    onPending?(pendingId, thread, dur)
    CommentSound.send()
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
        VoiceBubble.loading(icon)
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
  // (iPhone's own symbol animations, iOS 17 and later; before that, the symbol simply changes)
  static func loading(_ v: UIImageView) { if #available(iOS 17.0, *) { indefinite(v, .variableColor.iterative.dimInactiveLayers) } }
  @available(iOS 17.0, *)
  private static func indefinite<T: IndefiniteSymbolEffect & SymbolEffect>(_ v: UIImageView, _ e: T) { v.addSymbolEffect(e, options: .repeating) }
  static func change(_ v: UIImageView, to name: String) {
    guard let i = sym(name) else { return }
    if #available(iOS 17.0, *) { v.removeAllSymbolEffects(); v.setSymbolImage(i, contentTransition: .replace.downUp) } else { v.image = i }
  }
  static func sym(_ n: String) -> UIImage? { UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)) }
  // sent (Haris, 2026-11-02): it starts as the pulsing one was — dimmer, ••• — and settles: the pulse eases out and the
  // ••• turns into ▶ (iPhone's own symbol change)
  func arrived() {
    alpha = 0.7
    icon.image = VoiceBubble.sym("ellipsis")
    VoiceBubble.loading(icon)
    play.isUserInteractionEnabled = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self = self else { return }
      UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { self.alpha = 1 }
      VoiceBubble.change(self.icon, to: "play.fill")
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
    VoiceBubble.change(icon, to: playing ? "pause.fill" : "play.fill")
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
  // copied words with mentions or file chips (in E11, anywhere): back as they were (Haris 2026-11-02)
  var onPasteRich: (([[String: Any]]) -> Bool)?
  private var selectedRich: NSAttributedString? {
    let r = selectedRange
    guard r.length > 0, let a = attributedText, NSMaxRange(r) <= a.length else { return nil }
    return a.attributedSubstring(from: r)
  }
  override func copy(_ sender: Any?) {
    let sub = selectedRich
    super.copy(sender)
    if let s = sub { RichClip.put(s) }
  }
  override func cut(_ sender: Any?) {
    let sub = selectedRich
    super.cut(sender)
    if let s = sub { RichClip.put(s) }
  }
  private var hasFiles: Bool {
    let pb = UIPasteboard.general
    return FileClip.current != nil || pb.hasImages || pb.types.contains { t in guard let u = UTType(t) else { return false }; return !u.conforms(to: .text) && (u.conforms(to: .data) || u.conforms(to: .content)) }
  }
  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(paste(_:)) && hasFiles { return true }   // (copied words: Paste is iPhone's own already — and reading the clipboard here would ask "Allow Paste?")
    return super.canPerformAction(action, withSender: sender)
  }
  override func paste(_ sender: Any?) {
    if let h = onPasteRich, let runs = RichClip.runs(), h(runs) { return }
    if hasFiles, onPasteFiles?() == true { return }
    super.paste(sender)
  }
}

// the @ people / # files above the comment box: Apple's own list rows (picture, name, the line under it) in a small
// Apple list in the task cards' colour — up to four, narrowing as you type; tapped, Apple's highlight (Haris 2026-11-09)
final class PickList: UITableView, UITableViewDataSource, UITableViewDelegate {
  struct Row { let key: String; let title: String; let sub: String?; let image: UIImage?; let path: String?; let round: Bool; let pick: () -> Void }
  static let rowH: CGFloat = 52
  var rows: [Row] = [] {
    didSet {
      // (only what changed is set again — the same people / files keep their rows)
      if rows.map({ $0.key }) != oldValue.map({ $0.key }) { reloadData(); invalidateIntrinsicContentSize() }
    }
  }
  private var pics: [String: UIImage] = [:]
  init() {
    super.init(frame: .zero, style: .plain)
    dataSource = self; delegate = self
    rowHeight = PickList.rowH; estimatedRowHeight = 0
    isScrollEnabled = false
    backgroundColor = HomeLook(Main.shared.lookBoth).card
    layer.cornerRadius = 16; layer.cornerCurve = .continuous
    separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0); separatorColor = HomeLook.line
    insetsContentViewsToSafeArea = false; contentInsetAdjustmentBehavior = .never
    sectionHeaderTopPadding = 0
    register(UITableViewCell.self, forCellReuseIdentifier: "r")
  }
  required init?(coder: NSCoder) { fatalError() }
  // (one way to make the rows, for the comment box and the description alike)
  static func person(_ p: [String: Any], pick: @escaping () -> Void) -> Row {
    let id = p["id"] as? String ?? ""
    let ph = p["photo"] as? String
    return Row(key: "p:" + id, title: p["name"] as? String ?? "", sub: id == CommentCell.creator ? "Creator" : (p["role"] as? String).flatMap { $0.isEmpty ? nil : $0 },
               image: initials(p), path: (ph?.hasPrefix("/") == true) ? ph : nil, round: true, pick: pick)
  }
  static func file(_ f: [String: Any], pick: @escaping () -> Void) -> Row {
    let n = f["name"] as? String ?? "File"
    let (sym, col) = DescEditor.kind(n)
    let pic = (f["thumbUrl"] as? String) ?? (CommentCell.isPic(n) ? f["url"] as? String : nil)
    return Row(key: "f:" + (f["file"] as? String ?? n), title: n, sub: TaskPage.size(f["size"] as? Int ?? 0),
               image: UIImage(systemName: sym)?.withTintColor(col, renderingMode: .alwaysOriginal), path: pic, round: false, pick: pick)
  }
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(min(rows.count, 4)) * PickList.rowH) }
  func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { min(rows.count, 4) }
  func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let cell = t.dequeueReusableCell(withIdentifier: "r", for: ip)
    let r = rows[ip.row]
    var c = cell.defaultContentConfiguration()
    c.text = r.title
    c.textProperties.font = .systemFont(ofSize: 16, weight: .medium)
    c.textProperties.numberOfLines = 1; c.textProperties.lineBreakMode = .byTruncatingMiddle
    c.secondaryText = r.sub
    c.secondaryTextProperties.color = r.sub == "Creator" ? .systemOrange : .secondaryLabel
    c.image = r.path.flatMap { pics[$0] } ?? r.image
    c.imageProperties.maximumSize = CGSize(width: 32, height: 32)
    c.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 32)
    c.imageProperties.cornerRadius = r.round ? 16 : 6
    cell.contentConfiguration = c
    cell.backgroundColor = .clear
    if let p = r.path, pics[p] == nil {
      FeedLoader.shared.image(p) { [weak self] img in
        guard let self = self, let img = img else { return }
        self.pics[p] = img
        if let i = self.rows.firstIndex(where: { $0.path == p }), i < 4 { self.reconfigureRows(at: [IndexPath(row: i, section: 0)]) }
      }
    }
    return cell
  }
  func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
    t.deselectRow(at: ip, animated: true)
    rows[ip.row].pick()
  }
  // a person's initials on their colour, as their picture is drawn everywhere (Al skipped — the server's initials)
  static func initials(_ p: [String: Any]) -> UIImage {
    let side: CGFloat = 32
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
      TaskPage.rgb(p["color"]).setFill()
      UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
      let t = (p["initials"] as? String ?? "?") as NSString
      let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: side * 0.38, weight: .semibold), .foregroundColor: UIColor.white]
      let sz = t.size(withAttributes: a)
      t.draw(at: CGPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2), withAttributes: a)
    }
  }
}
