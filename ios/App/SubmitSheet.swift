import UIKit

/* Submit for CD review, the app's own (Haris, 2026-11-01 — mockup dm-mock 2): who the files go to, Camera · Photos ·
   Files, each file uploading with its bar (sent by the app itself, Uploader's pieces, to /api/host/writeChunkBin), Submit
   once all are up → /api/home/act submitReview. Closed before Submit: nothing is sent. */
final class SubmitSheetVC: UIViewController, UISheetPresentationControllerDelegate {
  private let taskId: String, cd: String
  private let onSubmit: ([[String: Any]]) -> Void
  private var items: [(name: String, size: Int64, token: String, progress: Double, path: String?, error: String?)] = []
  private let list = UIStackView(), send = UIButton(type: .system)
  var cookies: (@escaping (String) -> Void) -> Void = { $0("") }
  init(task: String, cd: String, onSubmit: @escaping ([[String: Any]]) -> Void) {
    taskId = task; self.cd = cd; self.onSubmit = onSubmit
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController { sh.detents = [.medium(), .large()]; sh.prefersGrabberVisible = true; sh.delegate = self }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    let title = UILabel(); title.text = "Submit for CD review"; title.font = .systemFont(ofSize: 20, weight: .bold); title.textAlignment = .center
    let close = SheetClose.make(); close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    let sub = UILabel(); sub.numberOfLines = 0; sub.textAlignment = .center; sub.font = .systemFont(ofSize: 15); sub.textColor = .secondaryLabel
    sub.text = cd.isEmpty ? "No Creative Director is set yet — an Admin needs to choose one." : "Your files go to \(cd) (Creative Director) for approval."
    let src = UIStackView(); src.spacing = 10; src.distribution = .fillEqually
    for (t, sym, k) in [("Camera", "camera", "camera"), ("Photos", "photo.on.rectangle", "photos"), ("Files", "folder", "files")] {
      var c = UIButton.Configuration.filled(); c.baseBackgroundColor = .secondarySystemGroupedBackground; c.baseForegroundColor = .label
      c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)); c.imagePlacement = .top; c.imagePadding = 6
      c.attributedTitle = AttributedString(t, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14, weight: .medium)]))
      c.background.cornerRadius = 18; c.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 4, bottom: 14, trailing: 4)
      let b = UIButton(configuration: c); b.addAction(UIAction { [weak self] _ in self?.pick(k) }, for: .touchUpInside)
      src.addArrangedSubview(b)
    }
    list.axis = .vertical; list.spacing = 1; list.backgroundColor = .secondarySystemGroupedBackground; list.layer.cornerRadius = 18; list.clipsToBounds = true
    var c = UIButton.Configuration.filled(); c.cornerStyle = .capsule; c.baseBackgroundColor = .systemBlue
    c.attributedTitle = AttributedString("Submit", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    c.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 20, bottom: 15, trailing: 20)
    send.configuration = c
    send.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
    let v = UIStackView(arrangedSubviews: [sub, src, list, send]); v.axis = .vertical; v.spacing = 16
    [title, close, v].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    NSLayoutConstraint.activate([
      close.topAnchor.constraint(equalTo: view.topAnchor, constant: 16), close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      title.centerYAnchor.constraint(equalTo: close.centerYAnchor), title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      v.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 14), v.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), v.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
    ])
    paint()
  }
  private func pick(_ source: String) {
    Picker.shared.pick(from: self, single: false, source: source) { [weak self] r in
      guard let self = self else { return }
      for f in (r["files"] as? [[String: Any]]) ?? [] {
        guard let tok = f["token"] as? String else { continue }
        self.items.append((name: f["name"] as? String ?? "File", size: (f["size"] as? NSNumber)?.int64Value ?? 0, token: tok, progress: 0, path: nil, error: nil))
        self.upload(self.items.count - 1)
      }
      self.paint()
    }
  }
  // sent as every upload is (Uploader: the first piece makes the file, then three 8 MB pieces side by side — Haris 2026-11-16),
  // each piece by iPhone itself (Transfers: it goes on with the app in the background, Haris 2026-11-10); its own bar here
  private func upload(_ i: Int) {
    guard i < items.count, let url = Picker.shared.url(items[i].token) else { if i < items.count { items[i].error = "File no longer available"; paint() }; return }
    let tok = items[i].token
    Uploader.send(url, name: items[i].name, task: taskId, bar: false, cookies: cookies, progress: { [weak self] p in
      guard let self = self, let k = self.items.firstIndex(where: { $0.token == tok }) else { return }
      // (drawn again only when its whole percent moves)
      let was = Int(self.items[k].progress * 100); self.items[k].progress = min(p, 0.99)
      if Int(self.items[k].progress * 100) != was { self.paint() }
    }) { [weak self] path in
      guard let self = self, let k = self.items.firstIndex(where: { $0.token == tok }) else { return }
      if let path = path { self.items[k].path = path; self.items[k].progress = 1 } else { self.items[k].error = "Upload failed — try again" }
      self.paint()
    }
  }
  private var allUp: Bool { !items.isEmpty && items.allSatisfy { $0.path != nil && $0.error == nil && $0.progress >= 0.999 } }
  private func paint() {
    guard isViewLoaded else { return }
    list.arrangedSubviews.forEach { $0.removeFromSuperview() }
    list.isHidden = items.isEmpty
    for (i, it) in items.enumerated() {
      let ext = (it.name as NSString).pathExtension.uppercased()
      let tag = PaddedLabel(); tag.text = ext.isEmpty ? "FILE" : String(ext.prefix(4)); tag.font = .systemFont(ofSize: 10, weight: .bold); tag.textColor = .white
      tag.backgroundColor = ext == "PDF" ? .systemRed : ext == "AI" ? .systemOrange : .systemGray; tag.layer.cornerRadius = 7; tag.clipsToBounds = true; tag.insets = UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6)
      let n = UILabel(); n.text = it.name; n.font = .systemFont(ofSize: 15, weight: .medium); n.lineBreakMode = .byTruncatingMiddle
      let st = UILabel(); st.font = .systemFont(ofSize: 13); st.textColor = it.error != nil ? .systemRed : .secondaryLabel
      st.text = it.error ?? (it.progress >= 0.999 ? "Uploaded · " + TaskPage.size(Int(it.size)) : "Uploading… \(Int(it.progress * 100))%")
      let bar = UIProgressView(progressViewStyle: .default); bar.progress = Float(it.progress); bar.isHidden = it.progress >= 0.999 || it.error != nil
      let col = UIStackView(arrangedSubviews: [n, st, bar]); col.axis = .vertical; col.spacing = 3
      let x = UIButton(type: .system); x.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal); x.tintColor = .secondaryLabel
      x.addAction(UIAction { [weak self] _ in self?.items.remove(at: i); self?.paint() }, for: .touchUpInside)
      let row = UIStackView(arrangedSubviews: [tag, col, x]); row.spacing = 12; row.alignment = .center
      row.isLayoutMarginsRelativeArrangement = true; row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
      list.addArrangedSubview(row)
    }
    let ok = allUp
    send.isEnabled = ok
    send.configuration?.attributedTitle = AttributedString(items.isEmpty || ok ? "Submit" : "Uploading…", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
  }
  private func submit() {
    guard allUp else { return }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    let files = items.map { ["name": $0.name, "size": $0.size, "path": $0.path ?? ""] as [String: Any] }
    dismiss(animated: true) { self.onSubmit(files) }
  }
}
