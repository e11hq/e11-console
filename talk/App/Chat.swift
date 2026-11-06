import UIKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/* A group's chat (the mockups — WhatsApp's way, in E11's colours with SF Symbols): bubbles with the time inside and
   ✓✓ (blue once everyone has seen it), names coloured with their role, a reply's quote (tap: up to the original), photos
   and files, "Edited", "This message was deleted", reactions under the bubble. Swipe a message right to reply; hold it:
   a row of reactions (six quick ones and + for any emoji) and Reply · Copy · Edit (15 minutes) · Info · Delete for
   everyone (about 2 days) · Delete for me. The message bar: + (Photos, Camera, Files), the box, camera and mic; while
   typing, the send button. */
enum ChatItem: Hashable { case day(String), msg(String) }

final class ChatVC: UIViewController, UITableViewDelegate, QLPreviewControllerDataSource {
  let group: String
  private let table = UITableView(frame: .zero, style: .plain)
  private var data: UITableViewDiffableDataSource<Int, ChatItem>!
  private var msgs: [String: Msg] = [:]
  private var sigs: [String: Int] = [:]
  private let bar = MessageBar()
  private var kb: CGFloat = 0
  private var replying: Msg? { didSet { bar.setReply(replying.map { (Talk.shared.name($0.by), Talk.preview($0)) }, editing: false) } }
  private var editingMsg: Msg?
  private var previewURL: URL?
  private let titleV = UIStackView(), titleL = UILabel(), subL = UILabel()

  init(group: String) { self.group = group; super.init(nibName: nil, bundle: nil); hidesBottomBarWhenPushed = true }
  required init?(coder: NSCoder) { fatalError() }
  override var canBecomeFirstResponder: Bool { true }
  override var inputAccessoryView: UIView? { bar }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Look.chatBg
    navigationItem.largeTitleDisplayMode = .never
    table.backgroundColor = .clear; table.separatorStyle = .none; table.keyboardDismissMode = .interactive
    table.delegate = self; table.estimatedRowHeight = 60; table.rowHeight = UITableView.automaticDimension
    table.register(BubbleCell.self, forCellReuseIdentifier: "b"); table.register(DayCell.self, forCellReuseIdentifier: "d")
    table.frame = view.bounds; table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    table.contentInsetAdjustmentBehavior = .automatic
    view.addSubview(table)
    data = UITableViewDiffableDataSource<Int, ChatItem>(tableView: table) { [weak self] tv, ip, item in
      guard let self = self else { return UITableViewCell() }
      switch item {
      case .day(let s): let c = tv.dequeueReusableCell(withIdentifier: "d", for: ip) as! DayCell; c.set(s); return c
      case .msg(let id):
        let c = tv.dequeueReusableCell(withIdentifier: "b", for: ip) as! BubbleCell
        if let m = self.msgs[id], let g = Talk.shared.groups[self.group] { c.set(m, group: g, log: Talk.shared.log(self.group)) }
        c.onReplyTap = { [weak self] rid in self?.jump(to: rid) }
        c.onFileTap = { [weak self] m in self?.open(m) }
        c.onRetry = { [weak self] m in guard let self = self else { return }; Talk.shared.retry(self.group, m) }
        return c
      }
    }
    data.defaultRowAnimation = .fade
    // the title: the group's name, its people under it; a tap: group info
    titleL.font = .systemFont(ofSize: 16, weight: .semibold); subL.font = .systemFont(ofSize: 12); subL.textColor = .secondaryLabel
    titleV.axis = .vertical; titleV.alignment = .center; titleV.addArrangedSubview(titleL); titleV.addArrangedSubview(subL)
    titleV.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(info)))
    navigationItem.titleView = titleV
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "info.circle"), primaryAction: UIAction { [weak self] _ in self?.info() }, menu: nil)
    bar.onSend = { [weak self] t in self?.send(t) }
    bar.onPlus = { [weak self] k in self?.attach(k) }
    bar.onCancelReply = { [weak self] in self?.editingMsg = nil; self?.replying = nil; self?.bar.setReply(nil, editing: false) }
    bar.onMic = { toast("Voice messages come next") }
    NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .talkGroup, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(head), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(gone(_:)), name: .talkGone, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(kbMoved(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    head()
    reload(animated: false)
  }
  override func viewDidAppear(_ a: Bool) {
    super.viewDidAppear(a)
    becomeFirstResponder()
    Talk.shared.markRead(group)
    ChatVC.open = group
  }
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); if ChatVC.open == group { ChatVC.open = nil } }
  static var open: String?
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if !scrolledOnce, data.snapshot().numberOfItems > 0 { scrolledOnce = true; toBottom(false) }
  }
  private var scrolledOnce = false

  @objc private func head() {
    guard let g = Talk.shared.groups[group] else { return }
    titleL.text = g.name
    let names = g.members.filter { $0 != Talk.shared.me?.id }.map { Talk.shared.people[$0]?.name.split(separator: " ").first.map(String.init) ?? "…" } + ["You"]
    subL.text = (Talk.shared.clients[g.client]?.name).map { "\($0) · " } .map { $0 + names.joined(separator: ", ") } ?? names.joined(separator: ", ")
  }
  @objc private func info() { navigationController?.pushViewController(GroupInfoVC(group: group), animated: true) }
  @objc private func gone(_ n: Notification) {
    guard (n.object as? String) == group else { return }
    toast("This group was deleted")
    navigationController?.popToRootViewController(animated: true)
  }
  @objc private func changed(_ n: Notification) {
    guard (n.object as? String) == group else { return }
    let near = table.contentOffset.y + table.bounds.height >= table.contentSize.height - 120
    reload(animated: true)
    if near { toBottom(true) }
    if view.window != nil, UIApplication.shared.applicationState == .active { Talk.shared.markRead(group) }
  }
  // each message kept by its id; only one that shows something new is drawn again
  private func reload(animated: Bool) {
    let l = Talk.shared.log(group)
    var snap = NSDiffableDataSourceSnapshot<Int, ChatItem>(); snap.appendSections([0])
    var lastDay = "", newSigs: [String: Int] = [:], items: [ChatItem] = []
    msgs = [:]
    for m in l.msgs {
      let d = Look.day(m.at)
      if d != lastDay { items.append(.day(d)); lastDay = d }
      msgs[m.id] = m
      var h = Hasher(); h.combine(m.text); h.combine(m.edited); h.combine(m.deleted); h.combine(m.pending); h.combine(m.failed); h.combine(m.reactions); h.combine(m.file?.id)
      h.combine(l.readBy.count); h.combine(Talk.shared.groups[group]?.members.count ?? 0)
      for (k, v) in l.readBy.sorted(by: { $0.key < $1.key }) { h.combine(k); h.combine(v) }
      newSigs[m.id] = h.finalize()
      items.append(.msg(m.id))
    }
    snap.appendItems(items)
    let old = data.snapshot()
    snap.reconfigureItems(items.filter { if case .msg(let id) = $0 { return old.indexOfItem($0) != nil && sigs[id] != newSigs[id] }; return false })
    sigs = newSigs
    data.apply(snap, animatingDifferences: animated && old.numberOfItems > 0)
  }
  private func toBottom(_ animated: Bool) {
    let n = data.snapshot().numberOfItems
    guard n > 0 else { return }
    table.scrollToRow(at: IndexPath(row: n - 1, section: 0), at: .bottom, animated: animated)
  }
  @objc private func kbMoved(_ n: Notification) {
    guard let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
    let cover = max(0, view.bounds.maxY - view.convert(f, from: nil).minY)
    let grew = cover > kb
    kb = cover
    let atEnd = table.contentOffset.y + table.bounds.height >= table.contentSize.height - 40
    table.contentInset.bottom = max(0, cover - view.safeAreaInsets.bottom) + 8
    table.verticalScrollIndicatorInsets.bottom = table.contentInset.bottom
    if grew && (atEnd || table.isTracking == false) && bar.box.isFirstResponder { toBottom(false) }
  }
  private func jump(to id: String) {
    guard let ip = data.indexPath(for: .msg(id)) else { toast("That message isn’t on this phone any more"); return }
    table.scrollToRow(at: ip, at: .middle, animated: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { (self.table.cellForRow(at: ip) as? BubbleCell)?.flash() }
  }

  // ---------- sending ----------
  private func send(_ text: String) {
    if let e = editingMsg {
      editingMsg = nil; bar.setReply(nil, editing: false)
      Net.shared.act(["act": "edit", "msg": e.id, "text": text]) { j in if (j?["ok"] as? Bool) == true { Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t edit it") } }
      return
    }
    Talk.shared.send(group, text: text, reply: replying)
    replying = nil
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    toBottom(true)
  }
  private func attach(_ kind: String) {
    switch kind {
    case "photos":
      var c = PHPickerConfiguration(); c.selectionLimit = 10; c.filter = .any(of: [.images, .videos])
      let p = PHPickerViewController(configuration: c); p.delegate = self; present(p, animated: true)
    case "camera":
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else { toast("No camera here"); return }
      let p = UIImagePickerController(); p.sourceType = .camera; p.mediaTypes = ["public.image", "public.movie"]; p.delegate = self; present(p, animated: true)
    default:
      let p = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true); p.allowsMultipleSelection = true; p.delegate = self; present(p, animated: true)
    }
  }
  fileprivate func sendFile(_ url: URL, kind: String, name: String) {
    guard let d = try? Data(contentsOf: url) else { toast("Couldn’t read that file"); return }
    var w: Double? = nil, h: Double? = nil, data = d
    var kind = kind
    if kind == "photo", let img = UIImage(data: d) {
      // (a photo shrunk to 2048 across, as WhatsApp sends one)
      let s = min(1, 2048 / max(img.size.width, img.size.height))
      let sized = s < 1 ? UIGraphicsImageRenderer(size: CGSize(width: img.size.width * s, height: img.size.height * s)).image { _ in img.draw(in: CGRect(origin: .zero, size: CGSize(width: img.size.width * s, height: img.size.height * s))) } : img
      data = sized.jpegData(compressionQuality: 0.8) ?? d
      w = Double(sized.size.width); h = Double(sized.size.height)
    } else if kind == "photo" { kind = "file" }
    let tmpId = "local-" + UUID().uuidString
    let local = FileManager.default.temporaryDirectory.appendingPathComponent(tmpId)
    try? data.write(to: local)
    let fname = kind == "photo" ? (name as NSString).deletingPathExtension + ".jpg" : name
    Talk.shared.send(group, text: "", reply: replying, file: Msg.FileRef(id: tmpId, name: fname, size: data.count, kind: kind, w: w, h: h, secs: nil), localFile: local, upload: data)
    replying = nil
    toBottom(true)
  }

  // ---------- reading ----------
  private func open(_ m: Msg) {
    guard let f = m.file else { return }
    Net.shared.file(f.id) { [weak self] url in
      guard let self = self, let url = url else { toast("That file isn’t on the server any more"); return }
      // (QuickLook wants the name's extension)
      let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
      try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
      self.previewURL = named
      let q = QLPreviewController(); q.dataSource = self
      self.present(q, animated: true)
    }
  }
  func numberOfPreviewItems(in c: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
  func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { previewURL! as NSURL }

  // ---------- swipe right: reply ----------
  func tableView(_ tv: UITableView, leadingSwipeActionsConfigurationForRowAt ip: IndexPath) -> UISwipeActionsConfiguration? {
    guard case .msg(let id)? = data.itemIdentifier(for: ip), let m = msgs[id], m.kind != "sys", !m.deleted, !m.pending else { return nil }
    let a = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, done in self?.startReply(m); done(true) }
    a.image = UIImage(systemName: "arrowshape.turn.up.left.fill"); a.backgroundColor = Look.chatBg
    let c = UISwipeActionsConfiguration(actions: [a]); c.performsFirstActionWithFullSwipe = true
    return c
  }
  private func startReply(_ m: Msg) { editingMsg = nil; replying = m; UIImpactFeedbackGenerator(style: .light).impactOccurred(); bar.box.becomeFirstResponder() }

  // ---------- hold: reactions and the menu ----------
  func tableView(_ tv: UITableView, contextMenuConfigurationForRowAt ip: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    guard case .msg(let id)? = data.itemIdentifier(for: ip), let m = msgs[id], m.kind != "sys" else { return nil }
    return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in self?.menu(m) }
  }
  func tableView(_ tv: UITableView, previewForHighlightingContextMenuWithConfiguration c: UIContextMenuConfiguration) -> UITargetedPreview? {
    guard let id = c.identifier as? String, let ip = data.indexPath(for: .msg(id)), let cell = tv.cellForRow(at: ip) as? BubbleCell else { return nil }
    let p = UIPreviewParameters(); p.backgroundColor = .clear
    p.visiblePath = UIBezierPath(roundedRect: cell.bubble.bounds, cornerRadius: 16)
    return UITargetedPreview(view: cell.bubble, parameters: p)
  }
  private func menu(_ m: Msg) -> UIMenu {
    let T = Talk.shared, mine = m.by == T.me?.id
    let now = Date().timeIntervalSince1970 * 1000
    var items: [UIMenuElement] = []
    if !m.deleted && !m.pending {
      let quick = ["👍", "❤️", "😂", "😮", "😢", "🙏"].map { e -> UIAction in
        let on = m.reactions[T.me?.id ?? ""] == e
        return UIAction(title: e, image: ChatVC.emojiImage(e), state: on ? .on : .off) { [weak self] _ in self?.react(m, on ? nil : e) }
      }
      let more = UIAction(title: "More", image: UIImage(systemName: "plus")) { [weak self] _ in self?.anyEmoji(m) }
      let row = UIMenu(title: "", options: .displayInline, preferredElementSize: .small, children: quick + [more])
      items.append(row)
      items.append(UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in self?.startReply(m) })
      if !m.text.isEmpty { items.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = m.text; toast("Copied") }) }
      if mine && m.file == nil && now - m.at < 15 * 60000 {
        items.append(UIAction(title: "Edit", subtitle: "15 minutes after sending", image: UIImage(systemName: "pencil")) { [weak self] _ in
          self?.replying = nil; self?.editingMsg = m; self?.bar.setReply(("Editing", m.text), editing: true); self?.bar.box.text = m.text; self?.bar.textChanged(); self?.bar.box.becomeFirstResponder()
        })
      }
      if let f = m.file {
        items.append(UIAction(title: "Save / Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
          Net.shared.file(f.id) { url in
            guard let url = url else { toast("That file isn’t on the server any more"); return }
            let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
            try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
            self?.present(UIActivityViewController(activityItems: [named], applicationActivities: nil), animated: true)
          }
        })
      }
      if mine { items.append(UIAction(title: "Info", subtitle: "who has seen it", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.seenBy(m) }) }
    }
    var danger: [UIMenuElement] = []
    if mine && !m.deleted && !m.pending && now - m.at < 2 * 86400000 {
      danger.append(UIAction(title: "Delete for everyone", subtitle: "about 2 days after sending", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
        Net.shared.act(["act": "del", "msg": m.id]) { j in if (j?["ok"] as? Bool) == true { Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t delete it") } }
      })
    }
    danger.append(UIAction(title: "Delete for me", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in guard let self = self else { return }; Talk.shared.deleteForMe(self.group, m) })
    items.append(UIMenu(options: .displayInline, children: danger))
    return UIMenu(children: items)
  }
  static func emojiImage(_ e: String) -> UIImage {
    let s = NSAttributedString(string: e, attributes: [.font: UIFont.systemFont(ofSize: 26)])
    let size = s.size()
    return UIGraphicsImageRenderer(size: size).image { _ in s.draw(at: .zero) }.withRenderingMode(.alwaysOriginal)
  }
  private func react(_ m: Msg, _ e: String?) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    var b: [String: Any] = ["act": "react", "msg": m.id]; if let e = e { b["emoji"] = e }
    Net.shared.act(b) { _ in Talk.shared.sync() }
  }
  // + : any emoji, from iPhone's emoji keyboard
  private func anyEmoji(_ m: Msg) {
    let a = UIAlertController(title: "React", message: "Pick any emoji", preferredStyle: .alert)
    a.addTextField { t in t.placeholder = "😀"; t.textAlignment = .center; t.font = .systemFont(ofSize: 28) }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "React", style: .default) { [weak self] _ in
      guard let t = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), let first = t.first, first.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.value > 0x238C }) else { return }
      self?.react(m, String(first))
    })
    present(a, animated: true)
  }
  private func seenBy(_ m: Msg) {
    let T = Talk.shared, l = T.log(group)
    guard let g = T.groups[group], let idx = l.msgs.firstIndex(where: { $0.id == m.id }) else { return }
    let others = g.members.filter { $0 != T.me?.id }
    let seen = others.filter { p in l.readBy[p].flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 >= idx } ?? false }
    let not = others.filter { !seen.contains($0) }
    var s = seen.isEmpty ? "" : "Seen by: " + seen.map { T.name($0) }.joined(separator: ", ")
    if !not.isEmpty { s += (s.isEmpty ? "" : "\n\n") + "Not seen yet: " + not.map { T.name($0) }.joined(separator: ", ") }
    let a = UIAlertController(title: "Message info", message: s.isEmpty ? "Nobody else is in this group." : s, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true)
  }
}

extension ChatVC: PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
  func picker(_ p: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    p.dismiss(animated: true)
    for r in results {
      let ip = r.itemProvider
      let isMovie = ip.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      let type = isMovie ? UTType.movie.identifier : UTType.image.identifier
      ip.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
        guard let url = url else { return }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: copy)
        DispatchQueue.main.async { self?.sendFile(copy, kind: isMovie ? "video" : "photo", name: ip.suggestedName.map { $0 + "." + url.pathExtension } ?? url.lastPathComponent) }
      }
    }
  }
  func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    p.dismiss(animated: true)
    if let url = info[.mediaURL] as? URL { sendFile(url, kind: "video", name: "Video.mov") }
    else if let img = info[.originalImage] as? UIImage, let d = img.jpegData(compressionQuality: 0.9) {
      let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg"); try? d.write(to: u)
      sendFile(u, kind: "photo", name: "Photo.jpg")
    }
  }
  func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    for u in urls { sendFile(u, kind: "file", name: u.lastPathComponent) }
  }
}

// ---------- the day between messages ----------
final class DayCell: UITableViewCell {
  private let l = PaddedLabel()
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear; selectionStyle = .none
    l.font = .systemFont(ofSize: 12.5, weight: .medium); l.textColor = .secondaryLabel; l.backgroundColor = .tertiarySystemBackground
    l.layer.cornerRadius = 9; l.layer.masksToBounds = true; l.textAlignment = .center
    contentView.addSubview(l)
    l.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), l.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                                 l.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6), l.heightAnchor.constraint(equalToConstant: 24)])
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ s: String) { l.text = s }
}

// ---------- a message ----------
final class BubbleCell: UITableViewCell {
  let bubble = UIView()
  private let stack = UIStackView()
  private let nameL = UILabel(), textL = UILabel(), footL = UILabel()
  private let quote = UIView(), quoteBar = UIView(), quoteName = UILabel(), quoteText = UILabel()
  private let photo = UIImageView(), fileRow = UIStackView(), fileIcon = UIImageView(), fileName = UILabel(), fileSize = UILabel()
  private let reacts = PaddedLabel(), sysL = PaddedLabel(), retryB = UIButton(type: .system)
  private var lead: NSLayoutConstraint!, trail: NSLayoutConstraint!, photoH: NSLayoutConstraint!, photoW: NSLayoutConstraint!
  private var reactsLead: NSLayoutConstraint!, reactsTrail: NSLayoutConstraint!, bubbleBottom: NSLayoutConstraint!, reactsBottom: NSLayoutConstraint!
  private var msg: Msg?
  var onReplyTap: ((String) -> Void)?
  var onFileTap: ((Msg) -> Void)?
  var onRetry: ((Msg) -> Void)?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear; selectionStyle = .none
    bubble.layer.cornerRadius = 16; bubble.layer.cornerCurve = .continuous
    stack.axis = .vertical; stack.spacing = 4; stack.alignment = .fill
    nameL.font = .systemFont(ofSize: 13, weight: .semibold)
    textL.font = .systemFont(ofSize: 16.5); textL.numberOfLines = 0
    footL.font = .systemFont(ofSize: 11); footL.textAlignment = .right
    quote.layer.cornerRadius = 8; quote.clipsToBounds = true
    quoteBar.backgroundColor = Look.accent
    quoteName.font = .systemFont(ofSize: 12.5, weight: .semibold); quoteText.font = .systemFont(ofSize: 13); quoteText.numberOfLines = 2
    let qs = UIStackView(arrangedSubviews: [quoteName, quoteText]); qs.axis = .vertical; qs.spacing = 1
    [quoteBar, qs].forEach { quote.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([quoteBar.leadingAnchor.constraint(equalTo: quote.leadingAnchor), quoteBar.topAnchor.constraint(equalTo: quote.topAnchor), quoteBar.bottomAnchor.constraint(equalTo: quote.bottomAnchor), quoteBar.widthAnchor.constraint(equalToConstant: 3),
                                 qs.leadingAnchor.constraint(equalTo: quoteBar.trailingAnchor, constant: 8), qs.trailingAnchor.constraint(equalTo: quote.trailingAnchor, constant: -8), qs.topAnchor.constraint(equalTo: quote.topAnchor, constant: 5), qs.bottomAnchor.constraint(equalTo: quote.bottomAnchor, constant: -5)])
    quote.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(quoteTap)))
    photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; photo.layer.cornerRadius = 12; photo.backgroundColor = .tertiarySystemFill; photo.isUserInteractionEnabled = true
    photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fileTap)))
    fileIcon.image = UIImage(systemName: "doc.fill"); fileIcon.contentMode = .scaleAspectFit; fileIcon.widthAnchor.constraint(equalToConstant: 30).isActive = true
    fileName.font = .systemFont(ofSize: 15, weight: .semibold); fileName.numberOfLines = 2; fileSize.font = .systemFont(ofSize: 12)
    let fs = UIStackView(arrangedSubviews: [fileName, fileSize]); fs.axis = .vertical; fs.spacing = 2
    fileRow.addArrangedSubview(fileIcon); fileRow.addArrangedSubview(fs); fileRow.spacing = 10; fileRow.alignment = .center
    fileRow.isLayoutMarginsRelativeArrangement = true; fileRow.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8); fileRow.layer.cornerRadius = 10
    fileRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fileTap)))
    [nameL, quote, photo, fileRow, textL, footL].forEach { stack.addArrangedSubview($0) }
    bubble.addSubview(stack); contentView.addSubview(bubble)
    reacts.font = .systemFont(ofSize: 13); reacts.backgroundColor = .secondarySystemBackground; reacts.layer.cornerRadius = 11; reacts.layer.masksToBounds = true
    reacts.layer.borderWidth = 1.5; reacts.layer.borderColor = Look.chatBg.cgColor
    contentView.addSubview(reacts)
    sysL.font = .systemFont(ofSize: 12.5); sysL.textColor = .secondaryLabel; sysL.backgroundColor = .tertiarySystemBackground; sysL.numberOfLines = 0; sysL.textAlignment = .center
    sysL.layer.cornerRadius = 9; sysL.layer.masksToBounds = true
    contentView.addSubview(sysL)
    retryB.setImage(UIImage(systemName: "exclamationmark.circle.fill"), for: .normal); retryB.tintColor = .systemRed
    retryB.addAction(UIAction { [weak self] _ in if let m = self?.msg { self?.onRetry?(m) } }, for: .touchUpInside)
    contentView.addSubview(retryB)
    for v in [bubble, stack, reacts, sysL, retryB] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
    lead = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
    trail = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
    photoW = photo.widthAnchor.constraint(equalToConstant: 240); photoH = photo.heightAnchor.constraint(equalToConstant: 180)
    photoW.priority = .init(999); photoH.priority = .init(999)
    reactsLead = reacts.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10)
    reactsTrail = reacts.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10)
    bubbleBottom = bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)
    reactsBottom = reacts.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)
    NSLayoutConstraint.activate([
      bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
      bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),
      stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 7), stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
      stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
      photoW, photoH,
      reacts.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6), reacts.heightAnchor.constraint(equalToConstant: 22),
      sysL.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6), sysL.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
      sysL.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), sysL.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.85),
      retryB.centerYAnchor.constraint(equalTo: bubble.centerYAnchor), retryB.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -6),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }

  func set(_ m: Msg, group g: Group, log l: GroupLog) {
    msg = m
    let T = Talk.shared, mine = m.by == T.me?.id
    // a line about the group (made, added, left…): in the middle
    let sys = m.kind == "sys"
    sysL.isHidden = !sys; bubble.isHidden = sys; reacts.isHidden = true; retryB.isHidden = !(mine && m.failed)
    bubbleBottom.isActive = false; reactsBottom.isActive = false
    if sys { sysL.text = m.text; return }
    lead.isActive = !mine; trail.isActive = mine
    bubble.backgroundColor = mine ? Look.mine : Look.theirs
    let ink: UIColor = mine ? .white : .label, dim: UIColor = mine ? UIColor.white.withAlphaComponent(0.75) : .secondaryLabel
    // the name, coloured, with the role (others' only)
    nameL.isHidden = mine
    if !mine {
      let p = T.people[m.by]
      let a = NSMutableAttributedString(string: p?.name ?? "Someone", attributes: [.foregroundColor: Look.color(for: m.by)])
      if let r = p?.role, !r.isEmpty { a.append(NSAttributedString(string: " · " + r, attributes: [.foregroundColor: Look.color(for: m.by).withAlphaComponent(0.75), .font: UIFont.systemFont(ofSize: 12.5)])) }
      nameL.attributedText = a
    }
    // a reply's quote
    quote.isHidden = m.reply == nil || m.deleted
    if let r = m.reply {
      quote.backgroundColor = mine ? UIColor.white.withAlphaComponent(0.18) : UIColor.tertiarySystemFill
      quoteBar.backgroundColor = mine ? .white : Look.color(for: r.by)
      quoteName.text = T.name(r.by); quoteName.textColor = mine ? .white : Look.color(for: r.by)
      quoteText.text = r.text; quoteText.textColor = mine ? UIColor.white.withAlphaComponent(0.85) : .secondaryLabel
    }
    // a photo / a file
    let isPhoto = !m.deleted && m.file != nil && m.kind == "photo"
    photo.isHidden = !isPhoto; photoW.isActive = isPhoto; photoH.isActive = isPhoto
    if isPhoto, let f = m.file {
      let w: CGFloat = 240, ratio = CGFloat((f.h ?? 3) / max(1, f.w ?? 4))
      photoW.constant = w; photoH.constant = min(320, max(120, w * ratio))
      photo.image = nil
      Net.shared.file(f.id) { [weak self] url in guard let self = self, self.msg?.id == m.id, let url = url else { return }; self.photo.image = UIImage(contentsOfFile: url.path) }
    }
    fileRow.isHidden = m.deleted || m.file == nil || isPhoto
    if let f = m.file, !isPhoto {
      fileRow.backgroundColor = mine ? UIColor.white.withAlphaComponent(0.16) : .tertiarySystemFill
      fileIcon.image = UIImage(systemName: m.kind == "video" ? "play.rectangle.fill" : "doc.fill"); fileIcon.tintColor = ink
      fileName.text = f.name; fileName.textColor = ink
      fileSize.text = ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file) + " · " + (f.name as NSString).pathExtension.uppercased(); fileSize.textColor = dim
    }
    // the words
    if m.deleted {
      let a = NSMutableAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "nosign")!.withTintColor(dim)))
      a.append(NSAttributedString(string: " This message was deleted", attributes: [.font: UIFont.italicSystemFont(ofSize: 15), .foregroundColor: dim]))
      textL.attributedText = a; textL.isHidden = false
    } else {
      textL.attributedText = nil; textL.text = m.text; textL.textColor = ink; textL.font = .systemFont(ofSize: 16.5)
      textL.isHidden = m.text.isEmpty
    }
    // the time inside, "Edited", and ✓ / ✓✓ (blue once everyone has seen it) on mine
    let foot = NSMutableAttributedString(string: (m.edited && !m.deleted ? "Edited " : "") + Look.clock(m.at), attributes: [.foregroundColor: dim])
    if mine && !m.deleted {
      let others = g.members.filter { $0 != m.by }
      let idx = l.msgs.firstIndex { $0.id == m.id } ?? 0
      let allSeen = !others.isEmpty && others.allSatisfy { p in l.readBy[p].flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 >= idx } ?? false }
      let sym = m.pending ? (m.failed ? "exclamationmark.circle" : "clock") : allSeen ? "checkmark.circle.fill" : "checkmark"
      let tint: UIColor = allSeen ? UIColor(red: 0.62, green: 0.86, blue: 1, alpha: 1) : dim
      foot.append(NSAttributedString(string: " "))
      foot.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))!.withTintColor(tint))))
    }
    footL.attributedText = foot
    // reactions under the bubble: each emoji with its count
    let counts = Dictionary(grouping: m.reactions.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    reacts.isHidden = counts.isEmpty || m.deleted
    reacts.text = counts.map { $0.1 > 1 ? "\($0.0) \($0.1)" : $0.0 }.joined(separator: " ")
    reactsLead.isActive = !mine; reactsTrail.isActive = mine
    if reacts.isHidden { bubbleBottom.isActive = true } else { reactsBottom.isActive = true }
  }
  @objc private func quoteTap() { if let r = msg?.reply { onReplyTap?(r.id) } }
  @objc private func fileTap() { if let m = msg { onFileTap?(m) } }
  func flash() {
    let c = bubble.backgroundColor
    UIView.animate(withDuration: 0.2, animations: { self.bubble.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.5) }) { _ in UIView.animate(withDuration: 0.6) { self.bubble.backgroundColor = c } }
  }
}

// ---------- the message bar (Haris 2026-11-05 "like WhatsApp"): + · the box · camera · mic; typing → send ----------
final class MessageBar: UIView, UITextViewDelegate {
  let box = UITextView()
  private let plus = UIButton(type: .system), cam = UIButton(type: .system), mic = UIButton(type: .system), sendB = UIButton(type: .system)
  private let place = UILabel()
  private let replyV = UIView(), replyName = UILabel(), replyText = UILabel(), replyX = UIButton(type: .system), replyBar = UIView()
  private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  var onSend: ((String) -> Void)?
  var onPlus: ((String) -> Void)?
  var onCancelReply: (() -> Void)?
  var onMic: (() -> Void)?
  private var boxH: CGFloat = 36

  override init(frame: CGRect) {
    super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
    autoresizingMask = .flexibleHeight
    addSubview(blur)
    let sym = { (n: String) in UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)) }
    plus.setImage(sym("plus"), for: .normal); cam.setImage(sym("camera"), for: .normal); mic.setImage(sym("mic"), for: .normal)
    sendB.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)), for: .normal)
    [plus, cam, mic, sendB].forEach { $0.tintColor = Look.accent; addSubview($0) }
    plus.showsMenuAsPrimaryAction = true
    plus.menu = UIMenu(children: [
      UIAction(title: "Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in self?.onPlus?("photos") },
      UIAction(title: "Camera", image: UIImage(systemName: "camera")) { [weak self] _ in self?.onPlus?("camera") },
      UIAction(title: "Files", image: UIImage(systemName: "folder")) { [weak self] _ in self?.onPlus?("files") }])
    cam.addAction(UIAction { [weak self] _ in self?.onPlus?("camera") }, for: .touchUpInside)
    mic.addAction(UIAction { [weak self] _ in self?.onMic?() }, for: .touchUpInside)
    sendB.addAction(UIAction { [weak self] _ in self?.sendNow() }, for: .touchUpInside)
    box.font = .systemFont(ofSize: 16.5); box.backgroundColor = .secondarySystemBackground; box.layer.cornerRadius = 18; box.layer.cornerCurve = .continuous
    box.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10); box.delegate = self; box.isScrollEnabled = false
    box.layer.borderWidth = 0.5; box.layer.borderColor = UIColor.separator.cgColor
    addSubview(box)
    place.text = "Message"; place.font = .systemFont(ofSize: 16.5); place.textColor = .placeholderText; box.addSubview(place)
    replyV.backgroundColor = .clear
    replyBar.backgroundColor = Look.accent; replyName.font = .systemFont(ofSize: 13, weight: .semibold); replyName.textColor = Look.accent
    replyText.font = .systemFont(ofSize: 13); replyText.textColor = .secondaryLabel
    replyX.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal); replyX.tintColor = .tertiaryLabel
    replyX.addAction(UIAction { [weak self] _ in self?.onCancelReply?() }, for: .touchUpInside)
    [replyBar, replyName, replyText, replyX].forEach { replyV.addSubview($0) }
    replyV.isHidden = true; addSubview(replyV)
    textChanged()
  }
  required init?(coder: NSCoder) { fatalError() }
  // (the bar stays above the home indicator when the keyboard is down)
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: boxH + 16 + (replyV.isHidden ? 0 : 46) + safeAreaInsets.bottom) }
  override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); invalidateIntrinsicContentSize() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, top: CGFloat = replyV.isHidden ? 0 : 46
    blur.frame = CGRect(x: 0, y: 0, width: W, height: bounds.height + 200)
    replyV.frame = CGRect(x: 0, y: 0, width: W, height: 46)
    replyBar.frame = CGRect(x: 14, y: 8, width: 3, height: 32)
    replyName.frame = CGRect(x: 24, y: 7, width: W - 70, height: 17); replyText.frame = CGRect(x: 24, y: 24, width: W - 70, height: 17)
    replyX.frame = CGRect(x: W - 44, y: 6, width: 36, height: 36)
    let typing = !box.text.isEmpty
    let y = top + 8, by = y + boxH - 36
    plus.frame = CGRect(x: 6, y: by, width: 40, height: 36)
    let right: CGFloat = typing ? 50 : 88
    box.frame = CGRect(x: 48, y: y, width: W - 48 - right, height: boxH)
    place.frame = CGRect(x: 15, y: 8, width: box.bounds.width - 30, height: 20)
    sendB.frame = CGRect(x: W - 46, y: by, width: 40, height: 36)
    cam.frame = CGRect(x: W - 84, y: by, width: 38, height: 36); mic.frame = CGRect(x: W - 46, y: by, width: 40, height: 36)
    sendB.isHidden = !typing; cam.isHidden = typing; mic.isHidden = typing
  }
  func textViewDidChange(_ t: UITextView) { textChanged() }
  func textChanged() {
    place.isHidden = !box.text.isEmpty
    let h = min(130, max(36, ceil(box.sizeThatFits(CGSize(width: max(100, box.bounds.width), height: 400)).height)))
    box.isScrollEnabled = h >= 130
    if h != boxH { boxH = h; invalidateIntrinsicContentSize() }
    UIView.animate(withDuration: 0.15) { self.setNeedsLayout(); self.layoutIfNeeded() }
  }
  private func sendNow() {
    let t = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    box.text = ""; textChanged()
    onSend?(t)
  }
  func setReply(_ r: (String, String)?, editing: Bool) {
    replyV.isHidden = r == nil
    replyName.text = r?.0; replyText.text = r?.1
    replyBar.backgroundColor = editing ? .systemOrange : Look.accent; replyName.textColor = editing ? .systemOrange : Look.accent
    if r == nil && editing == false && box.text.isEmpty == false && replyName.text == "Editing" { box.text = ""; textChanged() }
    invalidateIntrinsicContentSize(); setNeedsLayout()
  }
}
