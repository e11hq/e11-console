import UIKit
import AVKit
import QuickLook

/* Sending a photo, video or file: a preview first (approved mock-up "Talk send preview", Haris 2026-11-12 — WhatsApp's
   layout). What was picked, large, on black; a caption for each; a strip of them with + when there are several; along
   the top ✕, save, HD, Markup (photos — Apple's own, crop inside it) or trim (videos — Apple's own), and take this one
   out; at the foot the caption box, the chat it goes to and send. Apple's parts throughout: Apple's glass buttons, text
   field, paging scroll view, Quick Look's Markup, Apple's video editor and player. */
final class SendPreviewVC: UIViewController, UIScrollViewDelegate, UITextFieldDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate,
                           UIVideoEditorControllerDelegate, UINavigationControllerDelegate {
  struct Item { var url: URL; var kind: String; var name: String; var caption = ""; var hd = false }
  private(set) var items: [Item]
  private var at = 0
  private let to: String
  var onSend: (([Item]) -> Void)?
  var onAddMore: (() -> Void)?

  private let pager = UIScrollView(), strip = UIScrollView(), stripRow = UIStackView()
  private var pages: [UIView] = []
  private let caption = UITextField(), captionBox = UIView(), chip = UILabel(), sendB = UIButton(type: .system)
  private let closeB = UIButton(type: .system), saveB = UIButton(type: .system), hdB = UIButton(type: .system),
              editB = UIButton(type: .system), trashB = UIButton(type: .system)
  private let tools = UIStackView()
  private var foot: NSLayoutConstraint!

  init(items: [Item], to: String) { self.items = items; self.to = to; super.init(nibName: nil, bundle: nil); modalPresentationStyle = .fullScreen }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    // (on black in both looks, as Photos' and WhatsApp's — its own colours set, nothing forced)
    caption.keyboardAppearance = .dark
    pager.isPagingEnabled = true; pager.showsHorizontalScrollIndicator = false; pager.delegate = self
    pager.contentInsetAdjustmentBehavior = .never
    view.addSubview(pager)

    // the top: ✕ — and the tools
    func round(_ b: UIButton, _ sym: String?, _ label: String) {
      var c = UIButton.Configuration.gray(); c.cornerStyle = .capsule; c.baseForegroundColor = .white
      c.background.backgroundColor = UIColor(white: 0.24, alpha: 0.75)
      if let s = sym { c.image = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)) }
      c.contentInsets = .zero; b.configuration = c; b.accessibilityLabel = label
      b.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 38), b.heightAnchor.constraint(equalToConstant: 38)])
    }
    round(closeB, "xmark", "Close"); round(saveB, "arrow.down.to.line", "Save to Photos"); round(hdB, nil, "Send in HD")
    round(editB, "pencil.tip.crop.circle", "Markup"); round(trashB, "trash", "Remove")
    trashB.configuration?.baseForegroundColor = .systemRed
    closeB.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    saveB.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)
    hdB.addAction(UIAction { [weak self] _ in self?.toggleHD() }, for: .touchUpInside)
    editB.addAction(UIAction { [weak self] _ in self?.edit() }, for: .touchUpInside)
    trashB.addAction(UIAction { [weak self] _ in self?.removeCurrent() }, for: .touchUpInside)
    tools.axis = .horizontal; tools.spacing = 8
    [saveB, hdB, editB, trashB].forEach { tools.addArrangedSubview($0) }
    [closeB, tools].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }

    // the strip of what was picked, with +
    strip.showsHorizontalScrollIndicator = false
    stripRow.axis = .horizontal; stripRow.spacing = 6; stripRow.alignment = .center
    stripRow.translatesAutoresizingMaskIntoConstraints = false; strip.addSubview(stripRow)
    strip.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(strip)

    // the foot: the caption box (⊕ adds more), the chat it goes to, send
    captionBox.backgroundColor = UIColor(white: 0.06, alpha: 1); captionBox.layer.cornerRadius = 20; captionBox.layer.cornerCurve = .continuous
    captionBox.layer.borderWidth = 0.5; captionBox.layer.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
    let more = UIButton(type: .system)
    more.setImage(UIImage(systemName: "plus.square.on.square", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
    more.tintColor = UIColor(white: 0.8, alpha: 1); more.accessibilityLabel = "Add more"
    more.addAction(UIAction { [weak self] _ in self?.onAddMore?() }, for: .touchUpInside)
    caption.attributedPlaceholder = NSAttributedString(string: "Add a caption…", attributes: [.foregroundColor: UIColor(white: 0.55, alpha: 1)])
    caption.textColor = .white; caption.font = .systemFont(ofSize: 17); caption.delegate = self; caption.returnKeyType = .done
    caption.addAction(UIAction { [weak self] _ in guard let self = self, self.items.indices.contains(self.at) else { return }; self.items[self.at].caption = self.caption.text ?? "" }, for: .editingChanged)
    [more, caption].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; captionBox.addSubview($0) }
    // (⊕ at its own size on the left, the words from just after it — ⊕ had been stretched to the middle, Haris 2026-11-12)
    more.setContentHuggingPriority(.required, for: .horizontal); more.setContentCompressionResistancePriority(.required, for: .horizontal)
    caption.setContentHuggingPriority(.defaultLow, for: .horizontal)
    chip.text = "  " + to + "  "; chip.font = .systemFont(ofSize: 14, weight: .medium); chip.textColor = .white
    chip.backgroundColor = UIColor(white: 0.17, alpha: 1); chip.layer.cornerRadius = 10; chip.layer.masksToBounds = true
    var sc = UIButton.Configuration.filled(); sc.cornerStyle = .capsule; sc.baseBackgroundColor = .white; sc.baseForegroundColor = .black
    sc.image = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)); sc.contentInsets = .zero
    sendB.configuration = sc; sendB.accessibilityLabel = "Send"
    sendB.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
    [captionBox, chip, sendB].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }

    let g = view.safeAreaLayoutGuide
    foot = chip.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
    NSLayoutConstraint.activate([
      closeB.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 14), closeB.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
      tools.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -14), tools.centerYAnchor.constraint(equalTo: closeB.centerYAnchor),
      captionBox.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12), captionBox.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
      captionBox.heightAnchor.constraint(equalToConstant: 40), captionBox.bottomAnchor.constraint(equalTo: chip.topAnchor, constant: -12),
      more.leadingAnchor.constraint(equalTo: captionBox.leadingAnchor, constant: 12), more.centerYAnchor.constraint(equalTo: captionBox.centerYAnchor),
      caption.leadingAnchor.constraint(equalTo: more.trailingAnchor, constant: 10), caption.trailingAnchor.constraint(equalTo: captionBox.trailingAnchor, constant: -12),
      caption.centerYAnchor.constraint(equalTo: captionBox.centerYAnchor),
      chip.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 14), chip.heightAnchor.constraint(equalToConstant: 30), foot,
      sendB.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -14), sendB.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
      sendB.widthAnchor.constraint(equalToConstant: 46), sendB.heightAnchor.constraint(equalToConstant: 46),
      strip.leadingAnchor.constraint(equalTo: view.leadingAnchor), strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      strip.heightAnchor.constraint(equalToConstant: 50), strip.bottomAnchor.constraint(equalTo: captionBox.topAnchor, constant: -12),
      stripRow.topAnchor.constraint(equalTo: strip.contentLayoutGuide.topAnchor), stripRow.bottomAnchor.constraint(equalTo: strip.contentLayoutGuide.bottomAnchor),
      // (the row at its own width, centred while it fits, scrolling once it's wider — it was stretched to the screen's
      //  width and its + grew to fill it, Haris 2026-11-12)
      stripRow.centerXAnchor.constraint(equalTo: strip.contentLayoutGuide.centerXAnchor),
      stripRow.leadingAnchor.constraint(greaterThanOrEqualTo: strip.contentLayoutGuide.leadingAnchor, constant: 14),
      strip.contentLayoutGuide.widthAnchor.constraint(greaterThanOrEqualTo: strip.frameLayoutGuide.widthAnchor),
      { let c = strip.contentLayoutGuide.widthAnchor.constraint(equalTo: stripRow.widthAnchor, constant: 28); c.priority = .defaultHigh; return c }(),
      stripRow.heightAnchor.constraint(equalTo: strip.frameLayoutGuide.heightAnchor),
    ])
    // (a tap on the picture puts the keyboard away)
    pager.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapPage(_:))))
    rebuild()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    pager.frame = view.bounds
    for (i, p) in pages.enumerated() { p.frame = CGRect(x: CGFloat(i) * view.bounds.width, y: 0, width: view.bounds.width, height: view.bounds.height) }
    pager.contentSize = CGSize(width: view.bounds.width * CGFloat(pages.count), height: view.bounds.height)
  }

  // ---------- the pages and the strip ----------
  private func rebuild() {
    pages.forEach { $0.removeFromSuperview() }
    pages = items.map { page(for: $0) }
    pages.forEach { pager.addSubview($0) }
    stripRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
    if items.count > 1 || items.first?.kind != "file" {
      for (i, it) in items.enumerated() {
        let b = UIButton(type: .custom); b.tag = i
        b.setImage(thumb(it), for: .normal); b.imageView?.contentMode = .scaleAspectFill; b.clipsToBounds = true
        b.layer.cornerRadius = 8; b.layer.cornerCurve = .continuous
        b.widthAnchor.constraint(equalToConstant: 46).isActive = true; b.heightAnchor.constraint(equalToConstant: 46).isActive = true
        b.addAction(UIAction { [weak self] a in guard let t = (a.sender as? UIView)?.tag else { return }; self?.go(t, animated: true) }, for: .touchUpInside)
        stripRow.addArrangedSubview(b)
      }
      let plus = UIButton(type: .system)
      plus.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
      plus.tintColor = .white; plus.backgroundColor = UIColor(white: 0.24, alpha: 0.75); plus.layer.cornerRadius = 8; plus.accessibilityLabel = "Add more"
      plus.widthAnchor.constraint(equalToConstant: 46).isActive = true; plus.heightAnchor.constraint(equalToConstant: 46).isActive = true
      plus.addAction(UIAction { [weak self] _ in self?.onAddMore?() }, for: .touchUpInside)
      stripRow.addArrangedSubview(plus)
    }
    strip.isHidden = items.count < 2
    view.setNeedsLayout(); view.layoutIfNeeded()
    go(min(at, max(0, items.count - 1)), animated: false)
  }
  // more picked from the chat's pickers (⊕ / +): added at the end, shown
  func add(_ more: [Item]) {
    guard !more.isEmpty else { return }
    items += more; rebuild(); go(items.count - 1, animated: true)
  }
  private func page(for it: Item) -> UIView {
    let v = UIView()
    switch it.kind {
    case "photo":
      let iv = UIImageView(image: UIImage(contentsOfFile: it.url.path)); iv.contentMode = .scaleAspectFit
      iv.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(iv)
      NSLayoutConstraint.activate([iv.leadingAnchor.constraint(equalTo: v.leadingAnchor), iv.trailingAnchor.constraint(equalTo: v.trailingAnchor),
                                   iv.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor, constant: 60), iv.bottomAnchor.constraint(equalTo: v.safeAreaLayoutGuide.bottomAnchor, constant: -170)])
    case "video":
      let iv = UIImageView(image: thumb(it)); iv.contentMode = .scaleAspectFit
      let play = UIButton(type: .custom)
      var pc = UIButton.Configuration.filled(); pc.cornerStyle = .capsule; pc.baseBackgroundColor = UIColor(white: 0, alpha: 0.45); pc.baseForegroundColor = .white
      pc.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)); play.configuration = pc
      play.addAction(UIAction { [weak self] _ in self?.playCurrent() }, for: .touchUpInside)
      [iv, play].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; v.addSubview($0) }
      NSLayoutConstraint.activate([iv.leadingAnchor.constraint(equalTo: v.leadingAnchor), iv.trailingAnchor.constraint(equalTo: v.trailingAnchor),
                                   iv.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor, constant: 60), iv.bottomAnchor.constraint(equalTo: v.safeAreaLayoutGuide.bottomAnchor, constant: -170),
                                   play.centerXAnchor.constraint(equalTo: iv.centerXAnchor), play.centerYAnchor.constraint(equalTo: iv.centerYAnchor),
                                   play.widthAnchor.constraint(equalToConstant: 60), play.heightAnchor.constraint(equalToConstant: 60)])
    default:
      // a file: its kind, name and size on a card; a tap opens it in Quick Look to check
      let card = UIView(); card.backgroundColor = UIColor(white: 0.11, alpha: 1); card.layer.cornerRadius = 20; card.layer.cornerCurve = .continuous
      let icon = UIImageView(image: UIImage(systemName: "doc.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44))); icon.tintColor = Look.accent
      let n = UILabel(); n.text = it.name; n.textColor = .white; n.font = .systemFont(ofSize: 17, weight: .semibold); n.textAlignment = .center; n.numberOfLines = 2
      let size = (try? it.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
      let s = UILabel(); s.text = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) + " · " + it.url.pathExtension.uppercased()
      s.textColor = UIColor(white: 0.6, alpha: 1); s.font = .systemFont(ofSize: 14); s.textAlignment = .center
      let st = UIStackView(arrangedSubviews: [icon, n, s]); st.axis = .vertical; st.spacing = 10; st.alignment = .center
      [card, st].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }; v.addSubview(card); card.addSubview(st)
      NSLayoutConstraint.activate([card.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 36), card.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -36),
                                   card.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -40),
                                   st.topAnchor.constraint(equalTo: card.topAnchor, constant: 28), st.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
                                   st.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), st.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)])
      card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(lookCurrent)))
    }
    return v
  }
  private func thumb(_ it: Item) -> UIImage? {
    switch it.kind {
    case "photo": return UIImage(contentsOfFile: it.url.path)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
    case "video":
      let g = AVAssetImageGenerator(asset: AVURLAsset(url: it.url)); g.appliesPreferredTrackTransform = true
      return (try? g.copyCGImage(at: .zero, actualTime: nil)).map { UIImage(cgImage: $0) }
    default: return UIImage(systemName: "doc.fill")
    }
  }
  private func go(_ i: Int, animated: Bool) {
    guard items.indices.contains(i) else { return }
    at = i
    pager.setContentOffset(CGPoint(x: CGFloat(i) * view.bounds.width, y: 0), animated: animated)
    showCurrent()
  }
  func scrollViewDidEndDecelerating(_ s: UIScrollView) {
    guard s === pager, view.bounds.width > 0 else { return }
    at = Int(round(s.contentOffset.x / view.bounds.width)); showCurrent()
  }
  // the tools and the caption for the one shown
  private func showCurrent() {
    guard items.indices.contains(at) else { return }
    let it = items[at]
    caption.text = it.caption
    saveB.isHidden = it.kind == "file"; hdB.isHidden = it.kind == "file"; editB.isHidden = it.kind == "file"
    editB.configuration?.image = UIImage(systemName: it.kind == "video" ? "scissors" : "pencil.tip.crop.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
    editB.accessibilityLabel = it.kind == "video" ? "Trim" : "Markup"
    var hc = hdB.configuration
    hc?.attributedTitle = AttributedString("HD", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 11, weight: .bold)]))
    hc?.background.backgroundColor = it.hd ? .white : UIColor(white: 0.24, alpha: 0.75); hc?.baseForegroundColor = it.hd ? .black : .white
    hdB.configuration = hc
    for (i, b) in stripRow.arrangedSubviews.enumerated() where i < items.count {
      b.layer.borderWidth = i == at ? 2 : 0; b.layer.borderColor = UIColor.white.cgColor
    }
  }
  @objc private func tapPage(_ g: UITapGestureRecognizer) { caption.resignFirstResponder() }
  func textFieldShouldReturn(_ t: UITextField) -> Bool { t.resignFirstResponder(); return true }

  // ---------- the tools ----------
  private func toggleHD() {
    guard items.indices.contains(at) else { return }
    items[at].hd.toggle(); UISelectionFeedbackGenerator().selectionChanged(); showCurrent()
    toast(items[at].hd ? "Sends in HD — full quality" : "Sends in standard quality")
  }
  private func save() {
    guard items.indices.contains(at) else { return }
    let it = items[at]
    if it.kind == "photo", let i = UIImage(contentsOfFile: it.url.path) { UIImageWriteToSavedPhotosAlbum(i, nil, nil, nil); toast("Saved to Photos") }
    else if it.kind == "video", UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(it.url.path) { UISaveVideoAtPathToSavedPhotosAlbum(it.url.path, nil, nil, nil); toast("Saved to Photos") }
  }
  private func removeCurrent() {
    guard items.indices.contains(at) else { return }
    items.remove(at: at)
    if items.isEmpty { dismiss(animated: true); return }
    at = min(at, items.count - 1); rebuild()
  }
  private func edit() {
    guard items.indices.contains(at) else { return }
    let it = items[at]
    if it.kind == "video" {
      guard UIVideoEditorController.canEditVideo(atPath: it.url.path) else { return }
      let e = UIVideoEditorController(); e.videoPath = it.url.path; e.delegate = self; e.videoQuality = .typeHigh
      present(e, animated: true)
    } else { look(editing: true) }
  }
  // Apple's Markup (Quick Look's editing) — crop, draw and text are inside it; saved back over the photo
  private var looking: URL?
  private func look(editing: Bool) {
    guard items.indices.contains(at) else { return }
    looking = items[at].url
    let q = QLPreviewController(); q.dataSource = self; q.delegate = self
    present(q, animated: true) { if editing { q.setEditing(true, animated: true) } }
  }
  @objc private func lookCurrent() { look(editing: false) }
  func numberOfPreviewItems(in c: QLPreviewController) -> Int { looking == nil ? 0 : 1 }
  func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { looking! as NSURL }
  func previewController(_ c: QLPreviewController, editingModeFor item: QLPreviewItem) -> QLPreviewItemEditingMode { items[safe: at]?.kind == "photo" ? .updateContents : .disabled }
  func previewController(_ c: QLPreviewController, didUpdateContentsOf item: QLPreviewItem) { DispatchQueue.main.async { self.rebuild() } }
  func videoEditorController(_ e: UIVideoEditorController, didSaveEditedVideoToPath path: String) {
    let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: out)
    if items.indices.contains(at) { items[at].url = out }
    e.dismiss(animated: true) { self.rebuild() }
  }
  func videoEditorControllerDidCancel(_ e: UIVideoEditorController) { e.dismiss(animated: true) }
  private func playCurrent() {
    guard let it = items[safe: at] else { return }
    let p = AVPlayerViewController(); p.player = AVPlayer(url: it.url)
    present(p, animated: true) { p.player?.play() }
  }

  private func send() {
    if items.indices.contains(at) { items[at].caption = caption.text ?? "" }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let all = items
    dismiss(animated: true) { [weak self] in self?.onSend?(all) }
  }
}
