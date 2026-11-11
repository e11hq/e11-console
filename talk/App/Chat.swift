import UIKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox

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
  private var runs: [String: Run] = [:]
  private let bar = MessageBar()
  private var kb: CGFloat = 0
  private var replying: Msg? { didSet { bar.setReply(replying.map { (Talk.shared.name($0.by), Talk.preview($0)) }, editing: false) } }
  private var editingMsg: Msg?
  private var previewURL: URL?
  private let titleV = UIStackView(), titleL = UILabel(), subL = UILabel(), titlePic = Avatar(frame: CGRect(x: 0, y: 0, width: 39, height: 39))
  private let clientLine = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
  private let downB = UIButton(type: .custom)
  private var downBottom: NSLayoutConstraint!

  private var focus: String?   // (opened from a search result: that message, highlighted)
  init(group: String, focus: String? = nil) { self.group = group; self.focus = focus; super.init(nibName: nil, bundle: nil); hidesBottomBarWhenPushed = true }
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
        if let m = self.msgs[id], let g = Talk.shared.groups[self.group] { c.set(m, group: g, log: Talk.shared.log(self.group), run: self.runs[id] ?? Run()) }
        c.onReplyTap = { [weak self] rid in self?.jump(to: rid) }
        c.onFileTap = { [weak self] m in self?.open(m) }
        c.onRetry = { [weak self] m in guard let self = self else { return }; Talk.shared.retry(self.group, m) }
        return c
      }
    }
    data.defaultRowAnimation = .fade
    // the title (the design): the group's picture, its name, its people — at the left after ‹; a tap: group info
    titleL.font = .systemFont(ofSize: 17, weight: .bold); subL.font = .systemFont(ofSize: 13); subL.textColor = .secondaryLabel
    titleL.lineBreakMode = .byTruncatingTail; subL.lineBreakMode = .byTruncatingTail
    let words = UIStackView(arrangedSubviews: [titleL, subL]); words.axis = .vertical; words.alignment = .leading; words.spacing = 0
    titlePic.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([titlePic.widthAnchor.constraint(equalToConstant: 39), titlePic.heightAnchor.constraint(equalToConstant: 39)])
    titleV.axis = .horizontal; titleV.alignment = .center; titleV.spacing = 10
    titleV.addArrangedSubview(titlePic); titleV.addArrangedSubview(words)
    titleV.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(info)))
    titleV.widthAnchor.constraint(lessThanOrEqualToConstant: max(140, UIScreen.main.bounds.width - 150)).isActive = true
    setBarButtons()
    bar.onSend = { [weak self] t, ms in self?.send(t, mentions: ms) }
    bar.onPlus = { [weak self] k in self?.attach(k) }
    bar.onCancelReply = { [weak self] in self?.editingMsg = nil; self?.replying = nil; self?.bar.setReply(nil, editing: false) }
    bar.onVoice = { [weak self] url, secs, wave in self?.sendVoice(url, secs: secs, wave: wave) }
    NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .talkGroup, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(head), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(gone(_:)), name: .talkGone, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(kbMoved(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    // ("Client can see this group" — the design: a thin orange band right under the bar, always there in a client group)
    let cl = UILabel(); cl.font = .systemFont(ofSize: 13, weight: .semibold); cl.textColor = Look.clientInk; cl.textAlignment = .center
    let eyeImg = UIImage(systemName: "eye", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))!.withRenderingMode(.alwaysTemplate)
    let eye = NSMutableAttributedString(attachment: NSTextAttachment(image: eyeImg))
    eye.append(NSAttributedString(string: "  Client can see this group"))
    eye.addAttribute(.foregroundColor, value: Look.clientInk, range: NSRange(location: 0, length: eye.length)); cl.attributedText = eye
    let tint = UIView(); tint.backgroundColor = Look.clientInk.withAlphaComponent(0.14); tint.isUserInteractionEnabled = false
    clientLine.isHidden = true
    [tint, cl].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; clientLine.contentView.addSubview($0) }
    clientLine.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(clientLine)
    NSLayoutConstraint.activate([
      tint.leadingAnchor.constraint(equalTo: clientLine.contentView.leadingAnchor), tint.trailingAnchor.constraint(equalTo: clientLine.contentView.trailingAnchor),
      tint.topAnchor.constraint(equalTo: clientLine.contentView.topAnchor), tint.bottomAnchor.constraint(equalTo: clientLine.contentView.bottomAnchor),
      cl.centerXAnchor.constraint(equalTo: clientLine.contentView.centerXAnchor), cl.centerYAnchor.constraint(equalTo: clientLine.contentView.centerYAnchor),
      clientLine.leadingAnchor.constraint(equalTo: view.leadingAnchor), clientLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      clientLine.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), clientLine.heightAnchor.constraint(equalToConstant: 30)])
    // the scroll-down button (the design: 31 round, at the right above the message bar) — shown once you've scrolled up
    var dc = UIButton.Configuration.plain()
    dc.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)); dc.baseForegroundColor = .label
    downB.configuration = dc
    downB.backgroundColor = Look.downBtn; downB.layer.cornerRadius = 15.5
    downB.layer.shadowColor = UIColor.black.cgColor; downB.layer.shadowOpacity = 0.3; downB.layer.shadowRadius = 6; downB.layer.shadowOffset = CGSize(width: 0, height: 3)
    downB.accessibilityLabel = "Scroll to the latest"
    downB.alpha = 0; downB.translatesAutoresizingMaskIntoConstraints = false
    downB.addAction(UIAction { [weak self] _ in self?.toBottom(true) }, for: .touchUpInside)
    view.addSubview(downB)
    downBottom = downB.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100)
    NSLayoutConstraint.activate([downB.widthAnchor.constraint(equalToConstant: 31), downB.heightAnchor.constraint(equalToConstant: 31),
                                 downB.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -9), downBottom])
    head()
    reload(animated: false)
    lastSeenId = Talk.shared.log(group).msgs.last?.id
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
    if !scrolledOnce, data.snapshot().numberOfItems > 0 {
      scrolledOnce = true; toBottom(false)
      if let f = focus { focus = nil; DispatchQueue.main.async { self.jump(to: f) } }
    }
  }
  private var scrolledOnce = false
  private var lastSeenId: String?
  // the scroll-down button: shown once the end of the chat is out of view
  func scrollViewDidScroll(_ s: UIScrollView) {
    let away = s.contentOffset.y + s.bounds.height < s.contentSize.height - 160
    if (downB.alpha > 0) != away { UIView.animate(withDuration: 0.2) { self.downB.alpha = away ? 1 : 0 } }
  }

  @objc private func head() {
    guard let g = Talk.shared.groups[group] else { return }
    let T = Talk.shared
    titleL.text = g.name
    titlePic.set(group: g)
    // (the people: a client first, as "Rania (Oasis Coffee)"; the team by full name; You last — cut short by the bar)
    let others = g.members.filter { $0 != T.me?.id }.compactMap { T.people[$0] }
    let clients = others.filter { $0.contact }.map { p in p.client.flatMap { T.clients[$0]?.name }.map { "\(p.name) (\($0))" } ?? p.name }
    let team = others.filter { !$0.contact }.map { $0.name }
    subL.text = (clients + team + ["You"]).joined(separator: ", ")
    // a client group, to staff: the band under the bar and the box's hint — the client can see what's written here
    let shared = g.withClient && !T.isContact
    bar.placeholder = shared ? "Message — client can see this" : ""
    if clientLine.isHidden == shared { clientLine.isHidden = !shared; table.contentInset.top = shared ? 30 : 0; table.verticalScrollIndicatorInsets.top = table.contentInset.top }
    // (@: the group's people)
    bar.people = g.members.filter { $0 != T.me?.id }.compactMap { id in T.people[id].map { (id, $0.name) } }
  }
  // ---------- search inside the chat: 🔍 — the words, ⌃ ⌄ through the matches (newest first), each brought into view ----------
  private let findBar = UISearchBar()
  private var finds: [String] = [], findAt = 0
  private func setBarButtons() {
    let find = UIBarButtonItem(title: nil, image: UIImage(systemName: "magnifyingglass"), primaryAction: UIAction { [weak self] _ in self?.startFind() }, menu: nil)
    navigationItem.rightBarButtonItems = [find]
    let t = UIBarButtonItem(customView: titleV)
    if #available(iOS 26.0, *) { t.hidesSharedBackground = true }
    navigationItem.leftItemsSupplementBackButton = true
    navigationItem.leftBarButtonItems = [t]
    navigationItem.titleView = nil
    navigationItem.hidesBackButton = false
  }
  private func startFind() {
    findBar.placeholder = "Search this chat"; findBar.delegate = self; findBar.searchBarStyle = .minimal; findBar.text = ""
    navigationItem.leftBarButtonItems = nil
    navigationItem.titleView = findBar
    navigationItem.hidesBackButton = true
    let up = UIBarButtonItem(title: nil, image: UIImage(systemName: "chevron.up"), primaryAction: UIAction { [weak self] _ in self?.step(1) }, menu: nil)
    let down = UIBarButtonItem(title: nil, image: UIImage(systemName: "chevron.down"), primaryAction: UIAction { [weak self] _ in self?.step(-1) }, menu: nil)
    let done = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.endFind() })
    navigationItem.rightBarButtonItems = [done, down, up]
    findBar.becomeFirstResponder()
  }
  private func endFind() { finds = []; findBar.resignFirstResponder(); setBarButtons(); becomeFirstResponder() }
  private func runFind() {
    finds = Talk.shared.search(findBar.text ?? "", in: group).map { $0.1.id }
    findAt = 0
    if let f = finds.first { jump(to: f) }
  }
  private func step(_ d: Int) {
    guard !finds.isEmpty else { toast(findBar.text?.isEmpty == false ? "Not found in this chat" : "Type something to find"); return }
    findAt = (findAt + d + finds.count) % finds.count
    jump(to: finds[findAt])
    toast("\(findAt + 1) of \(finds.count)")
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
    // (someone else's new message while the chat is open: E11 Console's soft arrive sound)
    if let last = Talk.shared.log(group).msgs.last, last.id != lastSeenId, last.by != Talk.shared.me?.id, last.kind != "sys", lastSeenId != nil, view.window != nil { ChatSound.arrive() }
    lastSeenId = Talk.shared.log(group).msgs.last?.id
    if near { toBottom(true) }
    if view.window != nil, UIApplication.shared.applicationState == .active { Talk.shared.markRead(group) }
  }
  // each message kept by its id; only one that shows something new is drawn again
  private func reload(animated: Bool) {
    let l = Talk.shared.log(group)
    var snap = NSDiffableDataSourceSnapshot<Int, ChatItem>(); snap.appendSections([0])
    var lastDay = "", newSigs: [String: Int] = [:], items: [ChatItem] = []
    msgs = [:]
    // (a run: one person's messages one after another on the same day — the name on its first, the tail on its last)
    var newRuns: [String: Run] = [:]
    let all = l.msgs
    for (i, m) in all.enumerated() {
      let d = Look.day(m.at)
      let prev = i > 0 ? all[i - 1] : nil, next = i + 1 < all.count ? all[i + 1] : nil
      let same = { (o: Msg?) -> Bool in guard let o = o else { return false }; return o.by == m.by && o.kind != "sys" && m.kind != "sys" && Look.day(o.at) == d }
      newRuns[m.id] = Run(first: !same(prev), last: !same(next))
      if d != lastDay { items.append(.day(d)); lastDay = d }
      msgs[m.id] = m
      var h = Hasher(); h.combine(m.text); h.combine(m.edited); h.combine(m.deleted); h.combine(m.pending); h.combine(m.failed); h.combine(m.reactions); h.combine(m.file?.id)
      h.combine(newRuns[m.id]); h.combine(Talk.shared.people[m.by]?.color); h.combine(Talk.shared.people[m.by]?.role)
      h.combine(l.readBy.count); h.combine(Talk.shared.groups[group]?.members.count ?? 0)
      for (k, v) in l.readBy.sorted(by: { $0.key < $1.key }) { h.combine(k); h.combine(v) }
      newSigs[m.id] = h.finalize()
      items.append(.msg(m.id))
    }
    runs = newRuns
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
    downBottom.constant = -(max(cover, bar.bounds.height) + 25)
    if grew && (atEnd || table.isTracking == false) && bar.box.isFirstResponder { toBottom(false) }
  }
  private func jump(to id: String) {
    guard let ip = data.indexPath(for: .msg(id)) else { toast("That message isn’t on this phone any more"); return }
    table.scrollToRow(at: ip, at: .middle, animated: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { (self.table.cellForRow(at: ip) as? BubbleCell)?.flash() }
  }

  // ---------- sending ----------
  private func send(_ text: String, mentions: [String] = []) {
    if let e = editingMsg {
      editingMsg = nil; bar.setReply(nil, editing: false)
      Net.shared.act(["act": "edit", "msg": e.id, "text": text]) { j in if (j?["ok"] as? Bool) == true { Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t edit it") } }
      return
    }
    Talk.shared.send(group, text: text, reply: replying, mentions: mentions)
    replying = nil
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    ChatSound.send()
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
  // a voice message: sent as it was recorded, with its length and waveform
  private func sendVoice(_ url: URL, secs: Double, wave: String) {
    guard let d = try? Data(contentsOf: url) else { return }
    let tmpId = "local-" + UUID().uuidString
    Talk.shared.send(group, text: "", reply: replying, file: Msg.FileRef(id: tmpId, name: "Voice message.m4a", size: d.count, kind: "voice", w: nil, h: nil, secs: secs, wave: wave), localFile: url, upload: d)
    replying = nil
    toBottom(true)
  }
  // a video from the camera or Photos: shrunk to 720p first (Haris 2026-11-05); one from Files goes as it is
  fileprivate func sendVideo(_ url: URL, name: String) {
    let asset = AVURLAsset(url: url)
    guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { sendFile(url, kind: "file", name: name); return }
    let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    ex.outputURL = out; ex.outputFileType = .mp4; ex.shouldOptimizeForNetworkUse = true
    toast("Getting the video ready…")
    ex.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let ok = ex.status == .completed
        let src = ok ? out : url
        let a2 = AVURLAsset(url: src)
        var w: Double? = nil, h: Double? = nil
        if let t = a2.tracks(withMediaType: .video).first { let sz = t.naturalSize.applying(t.preferredTransform); w = Double(abs(sz.width)); h = Double(abs(sz.height)) }
        let secs = CMTimeGetSeconds(a2.duration)
        guard let d = try? Data(contentsOf: src) else { toast("Couldn’t read that video"); return }
        let tmpId = "local-" + UUID().uuidString
        let fname = (name as NSString).deletingPathExtension + ".mp4"
        Talk.shared.send(self.group, text: "", reply: self.replying, file: Msg.FileRef(id: tmpId, name: fname, size: d.count, kind: "video", w: w, h: h, secs: secs.isFinite ? secs : nil), localFile: src, upload: d)
        self.replying = nil
        self.toBottom(true)
      }
    }
  }
  fileprivate func sendFile(_ url: URL, kind: String, name: String) {
    if kind == "video" { sendVideo(url, name: name); return }
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
    p.visiblePath = UIBezierPath(roundedRect: cell.bubble.bounds, cornerRadius: 19)
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
      if mine && !Talk.shared.isContact { items.append(UIAction(title: "Info", subtitle: "who has seen it", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.seenBy(m) }) }
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

extension ChatVC: UISearchBarDelegate {
  func searchBar(_ b: UISearchBar, textDidChange t: String) { runFind() }
  func searchBarSearchButtonClicked(_ b: UISearchBar) { b.resignFirstResponder(); runFind(); if finds.isEmpty { toast("Not found in this chat") } }
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

// ---------- the day between messages (the design: a small chip, 20 high, 13 semibold) ----------
final class DayCell: UITableViewCell {
  private let chip = UIView(), l = UILabel()
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear; selectionStyle = .none
    chip.backgroundColor = Look.dayChip; chip.layer.cornerRadius = 8; chip.layer.cornerCurve = .continuous
    l.font = .systemFont(ofSize: 13, weight: .semibold); l.textColor = .label; l.textAlignment = .center
    chip.addSubview(l); contentView.addSubview(chip)
    [chip, l].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([
      chip.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), chip.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
      chip.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4), chip.heightAnchor.constraint(equalToConstant: 20),
      l.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10), l.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
      l.centerYAnchor.constraint(equalTo: chip.centerYAnchor)])
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ s: String) { l.text = s }
}

/* A message sent and one arriving (Haris 2026-11-11): E11 Console's own comment sounds — iPhone's system sound service,
   silent with the ring switch off, never stopping music or a video; several arriving together: one sound. */
enum ChatSound {
  private static var ids: [String: SystemSoundID] = [:]
  private static var lastArrive = Date.distantPast
  private static func play(_ name: String) {
    if ids[name] == nil, let url = Bundle.main.url(forResource: name, withExtension: "wav") {
      var id: SystemSoundID = 0
      AudioServicesCreateSystemSoundID(url as CFURL, &id); ids[name] = id
    }
    if let id = ids[name], id != 0 { AudioServicesPlaySystemSound(id) }
  }
  static func send() { play("chat-send") }
  static func arrive() {
    guard Date().timeIntervalSince(lastArrive) > 1.2 else { return }
    lastArrive = Date(); play("chat-arrive")
  }
}

// ---------- a message (the approved design, canvas "E11 Talk — design", board 3) ----------
// Bubbles of 19 with the tail only on the last of a run from one person (that corner 4), 5 apart inside a run and 13
// between runs; others' first of a run carries the name in their E11 Console colour and the role under it in grey ("Client"
// in orange); their last carries their picture beside the tail; the time (and ✓✓ on yours) sits inside, on the last
// line when it fits, as WhatsApp.
struct Run: Hashable { var first = true, last = true }

/* The bubble's own shape — rounded 19, the tail's corner 4 and the tail itself — drawn by a shape layer, so the bubble's
   colour follows light / dark (set again on the look's change: a layer's colour is the one thing Apple can't switch). */
final class BubbleShape: UIView {
  private let shape = CAShapeLayer()
  var fill: UIColor = .clear { didSet { shape.fillColor = fill.resolvedColor(with: traitCollection).cgColor } }
  var tail: (mine: Bool, on: Bool) = (false, false) { didSet { setNeedsLayout() } }
  override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; layer.insertSublayer(shape, at: 0) }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    shape.frame = bounds
    shape.path = BubbleShape.path(bounds.size, mine: tail.mine, tail: tail.on).cgPath
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) {
    super.traitCollectionDidChange(p)
    if traitCollection.hasDifferentColorAppearance(comparedTo: p) { shape.fillColor = fill.resolvedColor(with: traitCollection).cgColor }
  }
  static func path(_ s: CGSize, mine: Bool, tail: Bool, r: CGFloat = 19) -> UIBezierPath {
    let W = s.width, H = s.height, R = min(r, H / 2, W / 2)
    let small: CGFloat = 4
    let tl = R, tr = R, br = mine && tail ? small : R, bl = !mine && tail ? small : R
    let p = UIBezierPath()
    p.move(to: CGPoint(x: tl, y: 0))
    p.addLine(to: CGPoint(x: W - tr, y: 0)); p.addArc(withCenter: CGPoint(x: W - tr, y: tr), radius: tr, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
    p.addLine(to: CGPoint(x: W, y: H - br)); p.addArc(withCenter: CGPoint(x: W - br, y: H - br), radius: br, startAngle: 0, endAngle: .pi / 2, clockwise: true)
    p.addLine(to: CGPoint(x: bl, y: H)); p.addArc(withCenter: CGPoint(x: bl, y: H - bl), radius: bl, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
    p.addLine(to: CGPoint(x: 0, y: tl)); p.addArc(withCenter: CGPoint(x: tl, y: tl), radius: tl, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
    p.close()
    guard tail, H >= 17 else { return p }
    // (the tail: the design's curve "M0 0 C0 9 3 14 10 17 H0 z", 10 × 17, 8 outside the bubble's edge)
    let t = UIBezierPath()
    if mine {
      t.move(to: CGPoint(x: W - 2, y: H - 17))
      t.addCurve(to: CGPoint(x: W + 8, y: H), controlPoint1: CGPoint(x: W - 2, y: H - 8), controlPoint2: CGPoint(x: W + 1, y: H - 3))
      t.addLine(to: CGPoint(x: W - 2, y: H))
    } else {
      t.move(to: CGPoint(x: 2, y: H - 17))
      t.addCurve(to: CGPoint(x: -8, y: H), controlPoint1: CGPoint(x: 2, y: H - 8), controlPoint2: CGPoint(x: -1, y: H - 3))
      t.addLine(to: CGPoint(x: 2, y: H))
    }
    t.close(); p.append(t)
    return p
  }
}

enum Ticks {
  // ✓✓ as the design draws it (16 × 10): blue-white once everyone has read it, else the time's colour
  static func image(_ c: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 16, height: 10)).image { _ in
      let p = UIBezierPath()
      p.move(to: CGPoint(x: 1, y: 5)); p.addLine(to: CGPoint(x: 4, y: 8)); p.addLine(to: CGPoint(x: 10, y: 2))
      p.move(to: CGPoint(x: 6, y: 8)); p.addLine(to: CGPoint(x: 7, y: 9)); p.addLine(to: CGPoint(x: 13, y: 2))
      p.lineWidth = 1.6; p.lineCapStyle = .round; p.lineJoinStyle = .round
      c.setStroke(); p.stroke()
    }
  }
}

final class BubbleCell: UITableViewCell {
  let bubble = BubbleShape()
  private let stack = UIStackView()
  private let nameL = UILabel(), roleL = UILabel(), textL = UILabel(), footL = UILabel(), stamp = UILabel()
  private let quote = UIView(), quoteBar = UIView(), quoteName = UILabel(), quoteText = UILabel()
  private let photo = UIImageView(), fileRow = UIStackView(), fileIcon = UIImageView(), fileName = UILabel(), fileSize = UILabel()
  private let voice = VoiceView()
  private let play = UIImageView(image: UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44)))
  private let vlen = PaddedLabel()
  private let reacts = PaddedLabel(), sysL = PaddedLabel(), retryB = UIButton(type: .system)
  private let face = Avatar(frame: CGRect(x: 0, y: 0, width: 27, height: 27))
  private var lead: NSLayoutConstraint!, trail: NSLayoutConstraint!, photoH: NSLayoutConstraint!, photoW: NSLayoutConstraint!
  private var wMine: NSLayoutConstraint!, wTheirs: NSLayoutConstraint!, top: NSLayoutConstraint!, stackTrail: NSLayoutConstraint!
  private var reactsLead: NSLayoutConstraint!, reactsTrail: NSLayoutConstraint!, bubbleBottom: NSLayoutConstraint!, reactsBottom: NSLayoutConstraint!
  private var msg: Msg?
  var onReplyTap: ((String) -> Void)?
  var onFileTap: ((Msg) -> Void)?
  var onRetry: ((Msg) -> Void)?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear; selectionStyle = .none
    stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill
    nameL.font = .systemFont(ofSize: 15, weight: .semibold)
    roleL.font = .systemFont(ofSize: 12); roleL.textColor = Look.roleInk
    textL.font = .systemFont(ofSize: 17); textL.numberOfLines = 0
    footL.font = .systemFont(ofSize: 12); footL.textAlignment = .right
    stamp.font = .systemFont(ofSize: 12); stamp.textAlignment = .right
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
    play.tintColor = .white; play.layer.shadowOpacity = 0.35; play.layer.shadowRadius = 6; play.layer.shadowOffset = .zero
    vlen.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold); vlen.textColor = .white; vlen.backgroundColor = UIColor.black.withAlphaComponent(0.45); vlen.layer.cornerRadius = 8; vlen.layer.masksToBounds = true
    [play, vlen].forEach { photo.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([play.centerXAnchor.constraint(equalTo: photo.centerXAnchor), play.centerYAnchor.constraint(equalTo: photo.centerYAnchor),
                                 vlen.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: 8), vlen.bottomAnchor.constraint(equalTo: photo.bottomAnchor, constant: -8), vlen.heightAnchor.constraint(equalToConstant: 20)])
    [nameL, roleL, quote, photo, fileRow, voice, textL, footL].forEach { stack.addArrangedSubview($0) }
    stack.setCustomSpacing(2, after: roleL); stack.setCustomSpacing(4, after: quote); stack.setCustomSpacing(4, after: photo); stack.setCustomSpacing(4, after: fileRow)
    bubble.addSubview(stack); bubble.addSubview(stamp); contentView.addSubview(bubble)
    face.isUserInteractionEnabled = false; contentView.addSubview(face)
    reacts.font = .systemFont(ofSize: 14); reacts.backgroundColor = Look.theirs; reacts.layer.cornerRadius = 13; reacts.layer.masksToBounds = true
    reacts.layer.borderWidth = 2; reacts.layer.borderColor = Look.chatBg.resolvedColor(with: traitCollection).cgColor
    contentView.addSubview(reacts)
    sysL.font = .systemFont(ofSize: 15); sysL.textColor = .label; sysL.backgroundColor = Look.dayChip; sysL.numberOfLines = 0; sysL.textAlignment = .center
    sysL.layer.cornerRadius = 10; sysL.layer.masksToBounds = true
    contentView.addSubview(sysL)
    retryB.setImage(UIImage(systemName: "exclamationmark.circle.fill"), for: .normal); retryB.tintColor = .systemRed
    retryB.addAction(UIAction { [weak self] _ in if let m = self?.msg { self?.onRetry?(m) } }, for: .touchUpInside)
    contentView.addSubview(retryB)
    for v in [bubble, stack, stamp, face, reacts, sysL, retryB] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
    // (yours: 17 from the right edge, at most 281 wide on a 393 phone; others': 44 from the left — their picture in it —
    // at most 250)
    lead = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44)
    trail = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -17)
    wMine = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 281 / 393)
    wTheirs = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 250 / 393)
    top = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
    stackTrail = stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -11)
    photoW = photo.widthAnchor.constraint(equalToConstant: 240); photoH = photo.heightAnchor.constraint(equalToConstant: 180)
    photoW.priority = .init(999); photoH.priority = .init(999)
    reactsLead = reacts.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12)
    reactsTrail = reacts.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12)
    bubbleBottom = bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)
    reactsBottom = reacts.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)
    NSLayoutConstraint.activate([
      top,
      stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -7),
      stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), stackTrail,
      stamp.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -11), stamp.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
      face.widthAnchor.constraint(equalToConstant: 27), face.heightAnchor.constraint(equalToConstant: 27),
      face.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -10), face.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
      photoW, photoH,
      reacts.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -5), reacts.heightAnchor.constraint(equalToConstant: 26),
      sysL.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13), sysL.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
      sysL.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), sysL.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.85),
      retryB.centerYAnchor.constraint(equalTo: bubble.centerYAnchor), retryB.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -6),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  override func traitCollectionDidChange(_ p: UITraitCollection?) {
    super.traitCollectionDidChange(p)
    if traitCollection.hasDifferentColorAppearance(comparedTo: p) { reacts.layer.borderColor = Look.chatBg.resolvedColor(with: traitCollection).cgColor; if let m = msg { foot(m) } }
  }
  private var group: Group?, log: GroupLog?

  func set(_ m: Msg, group g: Group, log l: GroupLog, run: Run) {
    msg = m; group = g; log = l
    let T = Talk.shared, mine = m.by == T.me?.id
    // a line about the group (made, added, left…): in the middle
    let sys = m.kind == "sys"
    sysL.isHidden = !sys; bubble.isHidden = sys; reacts.isHidden = true; retryB.isHidden = !(mine && m.failed); face.isHidden = true
    bubbleBottom.isActive = false; reactsBottom.isActive = false
    if sys { sysL.text = m.text; return }
    top.constant = run.first ? 10 : 2
    lead.isActive = !mine; trail.isActive = mine; wMine.isActive = mine; wTheirs.isActive = !mine
    stackTrail.constant = mine ? -11 : -12
    bubble.fill = mine ? Look.mine : Look.theirs
    bubble.tail = (mine, run.last)
    let ink: UIColor = mine ? .white : .label, dim: UIColor = mine ? Look.mineTime : Look.roleInk
    // others' first of a run: the name in their Console colour, the role under it ("Client" in orange); their picture by the last
    let showName = !mine && run.first
    nameL.isHidden = !showName; roleL.isHidden = !showName
    if showName {
      let p = T.people[m.by]
      nameL.text = p?.name ?? "Someone"; nameL.textColor = Look.person(m.by)
      let client = p?.contact == true && !T.isContact
      roleL.text = client ? "Client" : (p?.role ?? ""); roleL.isHidden = roleL.text?.isEmpty != false
      roleL.textColor = client ? Look.clientInk : Look.roleInk; roleL.font = .systemFont(ofSize: 12, weight: client ? .semibold : .regular)
    }
    if !mine && run.last { face.isHidden = false; face.set(person: T.people[m.by]) }
    // a reply's quote
    quote.isHidden = m.reply == nil || m.deleted
    if let r = m.reply {
      quote.backgroundColor = UIColor.black.withAlphaComponent(0.22)
      quoteBar.backgroundColor = Look.person(r.by)
      quoteName.text = T.name(r.by); quoteName.textColor = mine ? .white : Look.person(r.by)
      quoteText.text = r.text; quoteText.textColor = mine ? UIColor.white.withAlphaComponent(0.85) : .secondaryLabel
    }
    // a photo / a file (their own design comes with stage 2; here as before, in the new colours)
    let isVideo = !m.deleted && m.file != nil && m.kind == "video"
    let isPhoto = !m.deleted && m.file != nil && (m.kind == "photo" || isVideo)
    let isVoice = !m.deleted && m.file != nil && m.kind == "voice"
    photo.isHidden = !isPhoto; photoW.isActive = isPhoto; photoH.isActive = isPhoto
    play.isHidden = !isVideo; vlen.isHidden = !isVideo || m.file?.secs == nil
    if isPhoto, let f = m.file {
      let w: CGFloat = 240, ratio = CGFloat((f.h ?? 3) / max(1, f.w ?? 4))
      photoW.constant = w; photoH.constant = min(320, max(120, w * ratio))
      photo.image = nil
      if let s = f.secs { vlen.text = String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
      if !isVideo || f.size <= 60 * 1024 * 1024 || FileManager.default.fileExists(atPath: Net.local(f.id).path) {
        Net.shared.file(f.id) { [weak self] url in
          guard let self = self, self.msg?.id == m.id, let url = url else { return }
          if isVideo { BubbleCell.frame(url, f.id) { [weak self] img in if self?.msg?.id == m.id { self?.photo.image = img } } }
          else { self.photo.image = UIImage(contentsOfFile: url.path) }
        }
      }
    }
    voice.isHidden = !isVoice
    if isVoice, let f = m.file { voice.set(id: m.id, file: f, ink: ink, dim: dim) }
    fileRow.isHidden = m.deleted || m.file == nil || isPhoto || isVoice
    if let f = m.file, !isPhoto {
      fileRow.backgroundColor = UIColor.black.withAlphaComponent(0.22)
      fileIcon.image = UIImage(systemName: m.kind == "video" ? "play.rectangle.fill" : "doc.fill"); fileIcon.tintColor = ink
      fileName.text = f.name; fileName.textColor = ink
      fileSize.text = ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file) + " · " + (f.name as NSString).pathExtension.uppercased(); fileSize.textColor = dim
    }
    // the words — the time sits on their last line when it fits (room kept for it at the end, as WhatsApp)
    let a = NSMutableAttributedString()
    if m.deleted {
      a.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "nosign")!.withTintColor(dim))))
      a.append(NSAttributedString(string: " " + (mine ? "You deleted this message" : "This message was deleted"), attributes: [.font: UIFont.italicSystemFont(ofSize: 17), .foregroundColor: dim]))
    } else {
      a.append(NSAttributedString(string: m.text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: ink]))
      for id in m.mentions {
        guard let n = T.people[id]?.name, !n.isEmpty else { continue }
        var from = m.text.startIndex
        while let r = m.text.range(of: "@" + n, range: from..<m.text.endIndex) {
          a.addAttributes([.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: mine ? UIColor.white : Look.person(id)], range: NSRange(r, in: m.text))
          from = r.upperBound
        }
      }
    }
    let words = a.length > 0
    textL.isHidden = !words
    footL.isHidden = words; stamp.isHidden = !words
    foot(m)
    if words {
      // (an invisible space as wide as the time at the end of the words: the time goes there, or onto its own line)
      let room = NSTextAttachment(); room.bounds = CGRect(x: 0, y: 0, width: ceil(stamp.intrinsicContentSize.width) + 10, height: 1)
      a.append(NSAttributedString(attachment: room))
      textL.attributedText = a
    }
    // reactions under the bubble: each emoji with its count
    let counts = Dictionary(grouping: m.reactions.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    reacts.isHidden = counts.isEmpty || m.deleted
    reacts.text = counts.map { $0.0 }.joined() + (m.reactions.count > 1 ? " \(m.reactions.count)" : "")
    reactsLead.isActive = !mine; reactsTrail.isActive = mine
    if reacts.isHidden { bubbleBottom.isActive = true } else { reactsBottom.isActive = true }
  }
  // the time inside — "Edited" before it, ✓✓ after it on yours (blue-white once everyone has read it; never for a client)
  private func foot(_ m: Msg) {
    guard let g = group, let l = log else { return }
    let T = Talk.shared, mine = m.by == T.me?.id
    let dim: UIColor = mine ? Look.mineTime : Look.roleInk
    let f = NSMutableAttributedString(string: (m.edited && !m.deleted ? "Edited " : "") + Look.clock(m.at), attributes: [.foregroundColor: dim, .font: UIFont.systemFont(ofSize: 12)])
    if mine && !m.deleted {
      let others = g.members.filter { $0 != m.by }
      let idx = l.msgs.firstIndex { $0.id == m.id } ?? 0
      let allSeen = !T.isContact && !others.isEmpty && others.allSatisfy { p in l.readBy[p].flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 >= idx } ?? false }
      f.append(NSAttributedString(string: " "))
      if m.pending {
        f.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: m.failed ? "exclamationmark.circle" : "clock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))!.withTintColor(dim.resolvedColor(with: traitCollection)))))
      } else {
        let t = NSTextAttachment(image: Ticks.image((allSeen ? Look.readTick : Look.mineTime).resolvedColor(with: traitCollection)))
        t.bounds = CGRect(x: 0, y: -1, width: 16, height: 10)
        f.append(NSAttributedString(attachment: t))
      }
    }
    footL.attributedText = f; stamp.attributedText = f
  }
  // a video's first frame (kept)
  private static let frames = NSCache<NSString, UIImage>()
  static func frame(_ url: URL, _ id: String, _ done: @escaping (UIImage?) -> Void) {
    if let i = frames.object(forKey: id as NSString) { done(i); return }
    DispatchQueue.global(qos: .userInitiated).async {
      let named = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(Net.stableKey(id)).mp4")
      if !FileManager.default.fileExists(atPath: named.path) { try? FileManager.default.copyItem(at: url, to: named) }
      let g = AVAssetImageGenerator(asset: AVURLAsset(url: named)); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 720, height: 720)
      let img = (try? g.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)).map { UIImage(cgImage: $0) }
      if let i = img { frames.setObject(i, forKey: id as NSString) }
      DispatchQueue.main.async { done(img) }
    }
  }
  @objc private func quoteTap() { if let r = msg?.reply { onReplyTap?(r.id) } }
  @objc private func fileTap() { if let m = msg { onFileTap?(m) } }
  func flash() {
    let c = bubble.fill
    UIView.animate(withDuration: 0.2, animations: { self.bubble.alpha = 0.55 }) { _ in UIView.animate(withDuration: 0.6) { self.bubble.alpha = 1; self.bubble.fill = c } }
  }
}

// ---------- the message bar (Haris 2026-11-05 "like WhatsApp"): + · the box · camera · mic; typing → send ----------
/* The message box (the design): it can switch to iPhone's emoji keyboard from its smiley — Apple's own keyboard,
   asked for through the text view's input mode. */
final class EmojiBox: UITextView {
  var emoji = false
  override var textInputMode: UITextInputMode? {
    if emoji, let m = UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage == "emoji" }) { return m }
    return super.textInputMode
  }
}

final class MessageBar: UIView, UITextViewDelegate {
  let box = EmojiBox()
  private let smiley = UIButton(type: .system)
  private let plus = UIButton(type: .system), cam = UIButton(type: .system), mic = UIButton(type: .system), sendB = UIButton(type: .system)
  private let place = UILabel()
  var placeholder = "Message" { didSet { place.text = placeholder } }
  private let replyV = UIView(), replyName = UILabel(), replyText = UILabel(), replyX = UIButton(type: .system), replyBar = UIView()
  private let blur = UIView()
  var onSend: ((String, [String]) -> Void)?
  var onPlus: ((String) -> Void)?
  var onCancelReply: (() -> Void)?
  var onVoice: ((URL, Double, String) -> Void)?
  // @: the group's people (id, name); the ones picked while typing
  var people: [(String, String)] = []
  private var picked: [String: String] = [:]   // id → name
  private let mentionV = UIStackView()
  private var mentionQ: (NSRange, String)?
  // the voice message being recorded: red dot, time, "‹ Slide to cancel"
  private let rec = VoiceRecorder()
  private let recV = UIView(), recDot = UIView(), recTime = UILabel(), recHint = UILabel()
  private var recCancelled = false, recStartX: CGFloat = 0
  private var boxH: CGFloat = 32

  override init(frame: CGRect) {
    super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
    autoresizingMask = .flexibleHeight
    blur.backgroundColor = Look.barBg
    addSubview(blur)
    // (the design: + · the box with its smiley · camera · the mic in a round button — while typing, send in our blue)
    let sym = { (n: String, size: CGFloat) in UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)) }
    plus.setImage(sym("plus", 21), for: .normal); cam.setImage(sym("camera", 21), for: .normal)
    [plus, cam].forEach { $0.tintColor = .label; addSubview($0) }
    var mc = UIButton.Configuration.filled()
    mc.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
    mc.baseBackgroundColor = .label; mc.baseForegroundColor = .systemBackground; mc.cornerStyle = .capsule; mc.contentInsets = .zero
    mic.configuration = mc
    var sc = UIButton.Configuration.filled()
    sc.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
    sc.baseBackgroundColor = Look.rgb(0x2F7BFF); sc.baseForegroundColor = .white; sc.cornerStyle = .capsule; sc.contentInsets = .zero
    sendB.configuration = sc
    mic.accessibilityLabel = "Hold to record a voice message"; sendB.accessibilityLabel = "Send"
    [mic, sendB].forEach { addSubview($0) }
    smiley.setImage(sym("face.smiling", 18), for: .normal); smiley.tintColor = .label; smiley.accessibilityLabel = "Emoji"
    smiley.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      self.box.emoji.toggle()
      if self.box.isFirstResponder { self.box.reloadInputViews() } else { self.box.becomeFirstResponder() }
    }, for: .touchUpInside)
    plus.showsMenuAsPrimaryAction = true
    plus.menu = UIMenu(children: [
      UIAction(title: "Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in self?.onPlus?("photos") },
      UIAction(title: "Camera", image: UIImage(systemName: "camera")) { [weak self] _ in self?.onPlus?("camera") },
      UIAction(title: "Files", image: UIImage(systemName: "folder")) { [weak self] _ in self?.onPlus?("files") }])
    cam.addAction(UIAction { [weak self] _ in self?.onPlus?("camera") }, for: .touchUpInside)
    // (hold the mic to record — let go to send, slide left to drop it; a tap says how)
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(micHold(_:))); hold.minimumPressDuration = 0.18
    mic.addGestureRecognizer(hold)
    mic.addAction(UIAction { _ in toast("Hold to record, let go to send") }, for: .touchUpInside)
    recV.backgroundColor = .clear; recV.isHidden = true
    recDot.backgroundColor = .systemRed; recDot.layer.cornerRadius = 5
    recTime.font = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
    recHint.text = "‹ Slide to cancel"; recHint.font = .systemFont(ofSize: 15); recHint.textColor = .secondaryLabel; recHint.textAlignment = .center
    [recDot, recTime, recHint].forEach { recV.addSubview($0) }
    addSubview(recV)
    rec.onTick = { [weak self] t in self?.recTime.text = String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
    mentionV.axis = .vertical; mentionV.isHidden = true
    addSubview(mentionV)
    sendB.addAction(UIAction { [weak self] _ in self?.sendNow() }, for: .touchUpInside)
    box.font = .systemFont(ofSize: 17); box.backgroundColor = Look.field; box.layer.cornerRadius = 16; box.layer.cornerCurve = .continuous
    box.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 34); box.delegate = self; box.isScrollEnabled = false
    addSubview(box); addSubview(smiley)
    place.text = ""; place.font = .systemFont(ofSize: 16); place.textColor = .systemGray; box.addSubview(place)
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
  private var mentionH: CGFloat { mentionV.isHidden ? 0 : CGFloat(mentionV.arrangedSubviews.count) * 44 }
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: boxH + 14 + (replyV.isHidden ? 0 : 46) + mentionH + safeAreaInsets.bottom) }
  override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); invalidateIntrinsicContentSize() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, mh = mentionH, top: CGFloat = mh + (replyV.isHidden ? 0 : 46)
    blur.frame = CGRect(x: 0, y: 0, width: W, height: bounds.height + 200)
    mentionV.frame = CGRect(x: 0, y: 0, width: W, height: mh)
    replyV.frame = CGRect(x: 0, y: mh, width: W, height: 46)
    replyBar.frame = CGRect(x: 14, y: 8, width: 3, height: 32)
    replyName.frame = CGRect(x: 24, y: 7, width: W - 70, height: 17); replyText.frame = CGRect(x: 24, y: 24, width: W - 70, height: 17)
    replyX.frame = CGRect(x: W - 44, y: 6, width: 36, height: 36)
    let typing = !box.text.isEmpty
    // (the design's places: + at 10, the box from 46, camera and mic at the right; the buttons stay level with the box's last line)
    let y = top + 8, by = y + boxH - 32
    plus.frame = CGRect(x: 10, y: by, width: 32, height: 32)
    let right: CGFloat = typing ? 49 : 87
    box.frame = CGRect(x: 46, y: y, width: W - 46 - right, height: boxH)
    smiley.frame = CGRect(x: box.frame.maxX - 34, y: y + boxH - 32, width: 32, height: 32)
    place.frame = CGRect(x: 13, y: 6, width: box.bounds.width - 46, height: 20)
    sendB.frame = CGRect(x: W - 41, y: by, width: 32, height: 32)
    cam.frame = CGRect(x: W - 79, y: by, width: 32, height: 32); mic.frame = CGRect(x: W - 41, y: by, width: 32, height: 32)
    sendB.isHidden = !typing; cam.isHidden = typing; mic.isHidden = typing
    recV.frame = CGRect(x: 8, y: y, width: W - 60, height: 36)
    recDot.frame = CGRect(x: 10, y: 13, width: 10, height: 10)
    recTime.frame = CGRect(x: 28, y: 0, width: 60, height: 36)
    recHint.frame = CGRect(x: 90, y: 0, width: recV.bounds.width - 100, height: 36)
  }
  @objc private func micHold(_ g: UILongPressGestureRecognizer) {
    switch g.state {
    case .began:
      recCancelled = false; recStartX = g.location(in: self).x
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      rec.start { [weak self] ok in
        guard let self = self else { return }
        guard ok else { toast("Allow the microphone for E11 Talk in Settings to record"); return }
        self.recTime.text = "0:00"
        self.recV.isHidden = false; self.box.isHidden = true; self.smiley.isHidden = true; self.plus.isHidden = true; self.cam.isHidden = true
        self.recDot.alpha = 1
        UIView.animate(withDuration: 0.6, delay: 0, options: [.repeat, .autoreverse]) { self.recDot.alpha = 0.2 }
      }
    case .changed:
      let x = g.location(in: self).x - recStartX
      recHint.alpha = max(0.2, 1 + x / 120)
      if x < -110, !recCancelled { recCancelled = true; UINotificationFeedbackGenerator().notificationOccurred(.warning); endRecording(send: false) }
    case .ended: if !recCancelled { endRecording(send: true) }
    case .cancelled, .failed: if !recCancelled { endRecording(send: false) }
    default: break
    }
  }
  private func endRecording(send: Bool) {
    recDot.layer.removeAllAnimations()
    recV.isHidden = true; box.isHidden = false; smiley.isHidden = false; plus.isHidden = false; recHint.alpha = 1
    setNeedsLayout()
    guard rec.isRecording else { return }
    if let r = rec.stop(keep: send) { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onVoice?(r.0, r.1, r.2) }
    else if send { toast("Hold longer to record") }
  }
  func textViewDidChange(_ t: UITextView) { textChanged(); findMention() }
  func textViewDidChangeSelection(_ t: UITextView) { findMention() }
  // "@ki" just before the cursor: the people whose name starts so — tap one to put "@Kiran Rao " in
  private func findMention() {
    let ns = box.text as NSString, caret = box.selectedRange.location
    guard caret <= ns.length, !people.isEmpty else { showMentions([]); return }
    let before = ns.substring(to: caret)
    guard let at = before.range(of: "@", options: .backwards) else { showMentions([]); return }
    let word = String(before[at.upperBound...])
    let startOK = at.lowerBound == before.startIndex || before[before.index(before: at.lowerBound)].isWhitespace
    guard startOK, !word.contains("\n"), word.count <= 20 else { showMentions([]); return }
    mentionQ = (NSRange(at.lowerBound..<before.endIndex, in: before), word)
    let q = word.lowercased()
    showMentions(people.filter { q.isEmpty || $0.1.lowercased().hasPrefix(q) || $0.1.lowercased().contains(" " + q) }.prefix(4).map { $0 })
  }
  private func showMentions(_ list: [(String, String)]) {
    mentionV.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (id, name) in list {
      var c = UIButton.Configuration.plain()
      c.title = name; c.baseForegroundColor = .label; c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 56, bottom: 0, trailing: 16)
      let b = UIButton(configuration: c); b.contentHorizontalAlignment = .leading
      b.heightAnchor.constraint(equalToConstant: 44).isActive = true
      let a = Avatar(frame: CGRect(x: 14, y: 6, width: 32, height: 32)); a.set(person: Talk.shared.people[id]); a.isUserInteractionEnabled = false; b.addSubview(a)
      b.addAction(UIAction { [weak self] _ in self?.pick(id, name) }, for: .touchUpInside)
      mentionV.addArrangedSubview(b)
    }
    let was = mentionV.isHidden
    mentionV.isHidden = list.isEmpty
    if was != mentionV.isHidden || !list.isEmpty { invalidateIntrinsicContentSize(); setNeedsLayout() }
  }
  private func pick(_ id: String, _ name: String) {
    guard let r = mentionQ?.0 else { return }
    let ns = box.text as NSString
    box.text = ns.replacingCharacters(in: r, with: "@" + name + " ")
    box.selectedRange = NSRange(location: r.location + name.utf16.count + 2, length: 0)
    picked[id] = name
    UISelectionFeedbackGenerator().selectionChanged()
    showMentions([]); textChanged()
  }
  func textChanged() {
    place.isHidden = !box.text.isEmpty
    let h = min(130, max(32, ceil(box.sizeThatFits(CGSize(width: max(100, box.bounds.width), height: 400)).height)))
    box.isScrollEnabled = h >= 130
    if h != boxH { boxH = h; invalidateIntrinsicContentSize() }
    UIView.animate(withDuration: 0.15) { self.setNeedsLayout(); self.layoutIfNeeded() }
  }
  private func sendNow() {
    let t = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    // (the people picked with @ whose name is still in the words)
    let ms = picked.filter { t.contains("@" + $0.value) }.map { $0.key }
    box.text = ""; picked = [:]; showMentions([]); textChanged()
    onSend?(t, ms)
  }
  func setReply(_ r: (String, String)?, editing: Bool) {
    replyV.isHidden = r == nil
    replyName.text = r?.0; replyText.text = r?.1
    replyBar.backgroundColor = editing ? .systemOrange : Look.accent; replyName.textColor = editing ? .systemOrange : Look.accent
    if r == nil && editing == false && box.text.isEmpty == false && replyName.text == "Editing" { box.text = ""; textChanged() }
    invalidateIntrinsicContentSize(); setNeedsLayout()
  }
}
