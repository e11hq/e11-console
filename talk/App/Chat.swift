import UIKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox
import ImageIO

/* A group's chat (the mockups — WhatsApp's way, in E11's colours with SF Symbols): bubbles with the time inside and
   ✓✓ (blue once everyone has seen it), names coloured with their role, a reply's quote (tap: up to the original), photos
   and files, "Edited", "This message was deleted", reactions under the bubble. Swipe a message right to reply (the
   keyboard opens); swipe your own left for Message info; hold it: Apple's lift, the reactions as Apple's palette (seven
   and + for any emoji), then Reply · Copy · Star · (yours: Edit for 15 minutes, Info) · Delete (for everyone about 2 days,
   for me). The message bar: + (Photos, Camera, Files), the box, camera and mic; while typing, the send button. */
enum ChatItem: Hashable { case day(String), msg(String) }

final class ChatVC: UIViewController, UITableViewDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate, UIGestureRecognizerDelegate {
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
        c.onFileTap = { [weak self, weak c] m in self?.openFrom = (m.kind == "photo" || m.kind == "video") ? c?.photo : nil; self?.open(m) }
        c.onRetry = { [weak self] m in guard let self = self else { return }; Talk.shared.retry(self.group, m) }
        return c
      }
    }
    data.defaultRowAnimation = .fade
    // the swipes on a message (WhatsApp's, the design's boards 26 / 27): right — reply; your own left — Message info
    swipe.delegate = self; swipe.maximumNumberOfTouches = 1
    table.addGestureRecognizer(swipe)
    table.panGestureRecognizer.require(toFail: swipe)
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
    bar.onLayout = { [weak self] in self?.fitBottom() }
    fitBottom()
    Talk.shared.markRead(group)
    ChatVC.open = group
  }
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); if ChatVC.open == group { ChatVC.open = nil } }
  static var open: String?
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    fitBottom()
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
    // (how far everyone else has read: your message is read once it's at or before that — only its ✓✓ hangs on it)
    let meId = Talk.shared.me?.id, others = (Talk.shared.groups[group]?.members ?? []).filter { $0 != meId }
    let pos = Dictionary(all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    let readTo = others.isEmpty ? -1 : others.map { l.readBy[$0].flatMap { pos[$0] } ?? -1 }.min() ?? -1
    for (i, m) in all.enumerated() {
      let d = Look.day(m.at)
      let prev = i > 0 ? all[i - 1] : nil, next = i + 1 < all.count ? all[i + 1] : nil
      let same = { (o: Msg?) -> Bool in guard let o = o else { return false }; return o.by == m.by && o.kind != "sys" && m.kind != "sys" && Look.day(o.at) == d }
      newRuns[m.id] = Run(first: !same(prev), last: !same(next))
      if d != lastDay { items.append(.day(d)); lastDay = d }
      msgs[m.id] = m
      var h = Hasher(); h.combine(m.text); h.combine(m.edited); h.combine(m.deleted); h.combine(m.pending); h.combine(m.failed); h.combine(m.reactions); h.combine(m.file?.id)
      h.combine(newRuns[m.id]); h.combine(Talk.shared.people[m.by]?.color); h.combine(Talk.shared.people[m.by]?.role)
      if m.by == meId { h.combine(i <= readTo) }
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
    if !animated { table.scrollToRow(at: IndexPath(row: n - 1, section: 0), at: .bottom, animated: false) }
    table.layoutIfNeeded()
    let end = CGPoint(x: 0, y: max(-table.adjustedContentInset.top, table.contentSize.height + table.adjustedContentInset.bottom - table.bounds.height))
    table.setContentOffset(end, animated: animated)
  }
  /* The room under the last message = how much the message bar (with the keyboard under it, or the reply / @ list above
     it) covers, measured from where the bar really is — the keyboard's notice alone missed the bar's first showing (the
     chat scrolled to its end before the bar came) and its height changes, so the latest messages sat behind it and
     couldn't be scrolled out. Called on every keyboard move and whenever the bar is laid out. */
  @objc private func kbMoved(_ n: Notification) { view.layoutIfNeeded(); fitBottom() }
  private func fitBottom() {
    guard isViewLoaded, bar.window != nil, let screen = view.window?.screen else { return }
    let r = view.convert(bar.convert(bar.bounds, to: screen.coordinateSpace), from: screen.coordinateSpace)
    let cover = max(0, view.bounds.maxY - r.minY)
    guard abs(cover - kb) > 0.5 else { return }
    let wasAtEnd = table.contentOffset.y + table.bounds.height >= table.contentSize.height + table.adjustedContentInset.bottom - 40
    let grew = cover > kb
    kb = cover
    table.contentInset.bottom = max(0, cover - view.safeAreaInsets.bottom) + 8
    table.verticalScrollIndicatorInsets.bottom = table.contentInset.bottom
    downBottom.constant = -(cover + 25)
    if grew && (wasAtEnd || !scrolledAway) { toBottom(false) }
  }
  // (you scrolled up to read: the keyboard or the bar growing doesn't pull you back down)
  private var scrolledAway: Bool { table.contentOffset.y + table.bounds.height < table.contentSize.height - 160 }
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
      let q = QLPreviewController(); q.dataSource = self; q.delegate = self
      self.present(q, animated: true)
    }
  }
  // a photo or video opens out of its bubble and, swiped down, shrinks back into it — Apple's own zoom (Quick Look's)
  private weak var openFrom: UIView?
  func previewController(_ c: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? { openFrom }
  func numberOfPreviewItems(in c: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
  func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { previewURL! as NSURL }

  // ---------- the swipes: right — reply; your own left — Message info ----------
  // (Apple has no part for a bubble that follows the finger and springs back, so it's a pan of ours; the reply's keyboard
  // and the info page's push are Apple's own)
  private lazy var swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
  private weak var swipeCell: BubbleCell?
  private var swipeMsg: Msg?, swipeArmed = false, swipeDx: CGFloat = 0
  private func canReply(_ m: Msg) -> Bool { m.kind != "sys" && !m.deleted && !m.pending }
  private func canInfo(_ m: Msg) -> Bool { m.kind != "sys" && !m.deleted && !m.pending && m.by == Talk.shared.me?.id }
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g === swipe else { return true }
    let v = swipe.velocity(in: table)
    guard abs(v.x) > abs(v.y) * 1.3, bar.recording == false,
          let ip = table.indexPathForRow(at: swipe.location(in: table)), case .msg(let id)? = data.itemIdentifier(for: ip), let m = msgs[id] else { return false }
    return v.x > 0 ? canReply(m) : canInfo(m)
  }
  @objc private func swiped(_ g: UIPanGestureRecognizer) {
    switch g.state {
    case .began:
      guard let ip = table.indexPathForRow(at: g.location(in: table)), let c = table.cellForRow(at: ip) as? BubbleCell,
            case .msg(let id)? = data.itemIdentifier(for: ip), let m = msgs[id] else { return }
      swipeCell = c; swipeMsg = m; swipeArmed = false; swipeDx = 0
    case .changed:
      guard let c = swipeCell, let m = swipeMsg else { return }
      let raw = g.translation(in: table).x
      var dx = raw > 0 ? (canReply(m) ? raw : 0) : (canInfo(m) ? raw : 0)
      // (as far as 64 with the finger, then it gives less and less)
      let reach: CGFloat = dx > 0 ? 74 : 64
      if abs(dx) > reach { dx = (dx > 0 ? 1 : -1) * (reach + (abs(dx) - reach) * 0.25) }
      swipeDx = dx
      c.slide(dx)
      if dx < 0 { dimOthers(min(1, -dx / 64), but: c) } else if dx >= 0 { dimOthers(0, but: c) }
      let armed = abs(dx) >= 60
      if armed != swipeArmed {
        swipeArmed = armed
        if armed { UIImpactFeedbackGenerator(style: .light).impactOccurred(); if dx > 0 { c.pop() } }
      }
    case .ended, .cancelled, .failed:
      guard let c = swipeCell, let m = swipeMsg else { return }
      let go = swipeArmed && g.state == .ended, right = swipeDx > 0
      swipeCell = nil; swipeMsg = nil; swipeArmed = false
      if go && !right {
        // Message info: the chat stays dimmed with the bubble moved while Apple's push slides the page in
        openInfo(m) { [weak self] in c.settle(animated: false); self?.dimOthers(0, but: c) }
      } else {
        c.settle(animated: true)
        UIView.animate(withDuration: 0.3) { self.dimOthers(0, but: c) }
        if go { startReply(m) }
      }
    default: break
    }
  }
  private func dimOthers(_ p: CGFloat, but c: UITableViewCell) {
    for v in table.visibleCells where v !== c { v.contentView.alpha = 1 - 0.68 * p }
  }
  private func openInfo(_ m: Msg, after: (() -> Void)? = nil) {
    let vc = MessageInfoVC(group: group, id: m.id)
    navigationController?.pushViewController(vc, animated: true)
    if let tc = navigationController?.transitionCoordinator { tc.animate(alongsideTransition: nil) { _ in after?() } } else { after?() }
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
  // the design (board 33): the reactions on top, then Reply · Forward · Copy · Star · (line) · Delete — Forward comes with
  // the forward sheet (stage 5); yours also keep Edit (15 minutes) and Info, files Save / Share, as the app has them today
  private func menu(_ m: Msg) -> UIMenu {
    let T = Talk.shared, mine = m.by == T.me?.id
    let now = Date().timeIntervalSince1970 * 1000
    var items: [UIMenuElement] = []
    if !m.deleted && !m.pending {
      let quick = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🔥"].map { e -> UIAction in
        let on = m.reactions[T.me?.id ?? ""] == e
        return UIAction(title: e, image: ChatVC.emojiImage(e), state: on ? .on : .off) { [weak self] _ in self?.react(m, on ? nil : e) }
      }
      let more = UIAction(title: "More Reactions", image: UIImage(systemName: "plus")) { [weak self] _ in self?.anyEmoji(m) }
      if #available(iOS 17.0, *) {
        items.append(UIMenu(title: "", options: [.displayInline, .displayAsPalette], children: quick + [more]))
      } else {
        items.append(UIMenu(title: "", options: .displayInline, preferredElementSize: .small, children: quick + [more]))
      }
      var acts: [UIMenuElement] = []
      acts.append(UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in self?.startReply(m) })
      if !m.text.isEmpty { acts.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = m.text; toast("Copied") }) }
      let starred = T.isStarred(group, m.id)
      acts.append(UIAction(title: starred ? "Unstar" : "Star", image: UIImage(systemName: starred ? "star.slash" : "star")) { [weak self] _ in
        guard let self = self else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(); Talk.shared.toggleStar(self.group, m)
      })
      if mine && m.file == nil && now - m.at < 15 * 60000 {
        acts.append(UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] _ in
          self?.replying = nil; self?.editingMsg = m; self?.bar.setReply(("Editing", m.text), editing: true); self?.bar.box.text = m.text; self?.bar.textChanged(); self?.bar.box.becomeFirstResponder()
        })
      }
      if let f = m.file {
        acts.append(UIAction(title: "Save / Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
          Net.shared.file(f.id) { url in
            guard let url = url else { toast("That file isn’t on the server any more"); return }
            let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
            try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
            self?.present(UIActivityViewController(activityItems: [named], applicationActivities: nil), animated: true)
          }
        })
      }
      if mine { acts.append(UIAction(title: "Info", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.openInfo(m) }) }
      items.append(UIMenu(options: .displayInline, children: acts))
    }
    items.append(UIMenu(options: .displayInline, children: [
      UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.askDelete(m) }
    ]))
    return UIMenu(children: items)
  }
  // Delete: Apple's sheet — for everyone (yours, about 2 days after sending) or for me
  private func askDelete(_ m: Msg) {
    let mine = m.by == Talk.shared.me?.id, now = Date().timeIntervalSince1970 * 1000
    let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    if mine && !m.deleted && !m.pending && now - m.at < 2 * 86400000 {
      a.addAction(UIAlertAction(title: "Delete for Everyone", style: .destructive) { _ in
        Net.shared.act(["act": "del", "msg": m.id]) { j in if (j?["ok"] as? Bool) == true { Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t delete it") } }
      })
    }
    a.addAction(UIAlertAction(title: "Delete for Me", style: .destructive) { [weak self] _ in guard let self = self else { return }; Talk.shared.deleteForMe(self.group, m) })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(a, animated: true)
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
  // the voice note's own (Haris 2026-11-11): recording starts, a recording dropped into the bin
  static func voiceStart() { play("voice-start") }
  static func voiceCancel() { play("voice-cancel") }
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
  var fillTop: CGFloat = 0 { didSet { if fillTop != oldValue { setNeedsLayout() } } }
  override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; layer.insertSublayer(shape, at: 0) }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    shape.frame = bounds
    shape.path = BubbleShape.path(bounds.size, mine: tail.mine, tail: tail.on, top: fillTop).cgPath
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) {
    super.traitCollectionDidChange(p)
    if traitCollection.hasDifferentColorAppearance(comparedTo: p) { shape.fillColor = fill.resolvedColor(with: traitCollection).cgColor }
  }
  // a rectangle with its own radius at each corner (tl, tr, br, bl)
  static func rounded(_ r: CGRect, _ tl: CGFloat, _ tr: CGFloat, _ br: CGFloat, _ bl: CGFloat) -> UIBezierPath {
    let p = UIBezierPath(), x = r.minX, y = r.minY, W = r.maxX, H = r.maxY
    p.move(to: CGPoint(x: x + tl, y: y))
    p.addLine(to: CGPoint(x: W - tr, y: y)); if tr > 0 { p.addArc(withCenter: CGPoint(x: W - tr, y: y + tr), radius: tr, startAngle: -.pi / 2, endAngle: 0, clockwise: true) }
    p.addLine(to: CGPoint(x: W, y: H - br)); if br > 0 { p.addArc(withCenter: CGPoint(x: W - br, y: H - br), radius: br, startAngle: 0, endAngle: .pi / 2, clockwise: true) }
    p.addLine(to: CGPoint(x: x + bl, y: H)); if bl > 0 { p.addArc(withCenter: CGPoint(x: x + bl, y: H - bl), radius: bl, startAngle: .pi / 2, endAngle: .pi, clockwise: true) }
    p.addLine(to: CGPoint(x: x, y: y + tl)); if tl > 0 { p.addArc(withCenter: CGPoint(x: x + tl, y: y + tl), radius: tl, startAngle: .pi, endAngle: -.pi / 2, clockwise: true) }
    p.close(); return p
  }
  static func path(_ s: CGSize, mine: Bool, tail: Bool, r: CGFloat = 19, top: CGFloat = 0) -> UIBezierPath {
    let W = s.width, H = s.height, R = min(r, H / 2, W / 2)
    let small: CGFloat = 4
    let br = mine && tail ? small : R, bl = !mine && tail ? small : R
    guard top < H - 1 else { return UIBezierPath() }   // (a photo alone: no colour round it)
    let p = rounded(CGRect(x: 0, y: top, width: W, height: max(0, H - top)), top > 0 ? 0 : R, top > 0 ? 0 : R, br, bl)
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

// the photo in a bubble: its two shades (the name's diagonal, the time's at the bottom) follow its own size
final class PhotoView: UIImageView {
  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for l in layer.sublayers ?? [] {
      if l.name == "diag" { l.frame = bounds } else if l.name == "foot" { l.frame = CGRect(x: 0, y: bounds.height - 44, width: bounds.width, height: 44) }
    }
    CATransaction.commit()
  }
}
// words with room round them that Auto Layout knows about (the reactions pill, a group's note) — the old label drew its
// words inset inside a size that had no room for them, so they were cut away and the pill showed blank
final class InsetLabel: UILabel {
  private let dx: CGFloat, dy: CGFloat
  init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy; super.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError() }
  override func drawText(in r: CGRect) { super.drawText(in: r.insetBy(dx: dx, dy: dy)) }
  override func textRect(forBounds b: CGRect, limitedToNumberOfLines n: Int) -> CGRect {
    let r = super.textRect(forBounds: b.insetBy(dx: dx, dy: dy), limitedToNumberOfLines: n)
    return r.insetBy(dx: -dx, dy: -dy)
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

final class Bleed: UIView {
  let inner: UIView
  private var l: NSLayoutConstraint!, r: NSLayoutConstraint!, t: NSLayoutConstraint!, b: NSLayoutConstraint!
  init(_ v: UIView) {
    inner = v; super.init(frame: .zero)
    addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false
    l = v.leadingAnchor.constraint(equalTo: leadingAnchor); r = v.trailingAnchor.constraint(equalTo: trailingAnchor)
    t = v.topAnchor.constraint(equalTo: topAnchor); b = v.bottomAnchor.constraint(equalTo: bottomAnchor)
    b.priority = .init(999)   // (hidden in the bubble's stack it folds to 0 — its inside's own height gives way, no clash)
    NSLayoutConstraint.activate([l, r, t, b])
  }
  required init?(coder: NSCoder) { fatalError() }
  // how far past each edge it reaches
  func reach(_ top: CGFloat, _ left: CGFloat, _ bottom: CGFloat, _ right: CGFloat) { t.constant = -top; l.constant = -left; b.constant = bottom; r.constant = right }
}

final class BubbleCell: UITableViewCell {
  let bubble = BubbleShape()
  private let stack = UIStackView()
  private let nameL = UILabel(), roleL = UILabel(), textL = UILabel(), footL = UILabel(), stamp = UILabel()
  // a reply's quote (the design: a tinted box 4 from the bubble's edge, a bar in their colour, a photo's picture at the right)
  private let quote = UIView(), quoteBar = UIView(), quoteName = UILabel(), quoteText = UILabel(), quoteThumb = UIImageView()
  private lazy var quoteWrap = Bleed(quote)
  // a photo / video: to the bubble's edges; someone else's name over it on a diagonal shadow; the time over a bottom one
  let photo = PhotoView()
  private lazy var photoWrap = Bleed(photo)
  private let photoName = UILabel(), photoRole = UILabel(), diag = CAGradientLayer(), foot = CAGradientLayer()
  private let playDisc = UIView(), vlen = UILabel()
  // a document (any file): one card — its kind, name, size · kind; a download circle on one not on this phone yet
  private let card = UIView(), cardIcon = UIImageView(), cardName = UILabel(), cardSize = UILabel(), cardDown = UIImageView()
  private lazy var cardWrap = Bleed(card)
  // a link: its preview box — the site, the address, a line, 🔗 the site
  private let linkBox = UIView(), linkSite = UILabel(), linkURL = UILabel(), linkLine = UIView(), linkFoot = UILabel()
  private lazy var linkWrap = Bleed(linkBox)
  private var link: URL?
  private let voice = VoiceView()
  private let reacts = InsetLabel(dx: 8, dy: 0), sysL = InsetLabel(dx: 14, dy: 6), retryB = UIButton(type: .system)
  private let face = Avatar(frame: CGRect(x: 0, y: 0, width: 27, height: 27))
  private var lead: NSLayoutConstraint!, trail: NSLayoutConstraint!, photoH: NSLayoutConstraint!, mediaW: NSLayoutConstraint!
  private var wMine: NSLayoutConstraint!, wTheirs: NSLayoutConstraint!, top: NSLayoutConstraint!, stackTrail: NSLayoutConstraint!
  private var reactsLead: NSLayoutConstraint!, reactsTrail: NSLayoutConstraint!, bubbleBottom: NSLayoutConstraint!, reactsBottom: NSLayoutConstraint!
  private var msg: Msg?
  private var media = false, caption = false, tailOn = false, isMine = false
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
    textL.isUserInteractionEnabled = true; textL.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(linkTap)))
    footL.font = .systemFont(ofSize: 12); footL.textAlignment = .right
    stamp.font = .systemFont(ofSize: 12); stamp.textAlignment = .right
    // the quote
    quote.backgroundColor = UIColor.black.withAlphaComponent(0.22); quote.layer.cornerRadius = 12; quote.layer.cornerCurve = .continuous; quote.clipsToBounds = true
    quoteName.font = .systemFont(ofSize: 15, weight: .semibold); quoteText.font = .systemFont(ofSize: 14); quoteText.numberOfLines = 2
    quoteThumb.contentMode = .scaleAspectFill; quoteThumb.clipsToBounds = true
    let qs = UIStackView(arrangedSubviews: [quoteName, quoteText]); qs.axis = .vertical; qs.spacing = 0
    [quoteBar, qs, quoteThumb].forEach { quote.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([quoteBar.leadingAnchor.constraint(equalTo: quote.leadingAnchor), quoteBar.topAnchor.constraint(equalTo: quote.topAnchor), quoteBar.bottomAnchor.constraint(equalTo: quote.bottomAnchor), quoteBar.widthAnchor.constraint(equalToConstant: 4),
                                 qs.leadingAnchor.constraint(equalTo: quoteBar.trailingAnchor, constant: 10), qs.trailingAnchor.constraint(equalTo: quoteThumb.leadingAnchor, constant: -10), qs.topAnchor.constraint(equalTo: quote.topAnchor, constant: 6), qs.bottomAnchor.constraint(equalTo: quote.bottomAnchor, constant: -8),
                                 quoteThumb.trailingAnchor.constraint(equalTo: quote.trailingAnchor), quoteThumb.topAnchor.constraint(equalTo: quote.topAnchor), quoteThumb.bottomAnchor.constraint(equalTo: quote.bottomAnchor)])
    quoteThumbW = quoteThumb.widthAnchor.constraint(equalToConstant: 0); quoteThumbW.isActive = true
    quote.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(quoteTap)))
    // the photo
    photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; photo.backgroundColor = .tertiarySystemFill; photo.isUserInteractionEnabled = true
    photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fileTap)))
    diag.colors = [UIColor.black.withAlphaComponent(0.62).cgColor, UIColor.black.withAlphaComponent(0.28).cgColor, UIColor.clear.cgColor]
    diag.locations = [0, 0.26, 0.46]; diag.startPoint = CGPoint(x: 0, y: 0); diag.endPoint = CGPoint(x: 0.75, y: 1)
    foot.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.45).cgColor]
    diag.name = "diag"; foot.name = "foot"
    photo.layer.addSublayer(diag); photo.layer.addSublayer(foot)
    photoName.font = .systemFont(ofSize: 15, weight: .semibold); photoRole.font = .systemFont(ofSize: 12); photoRole.textColor = UIColor(white: 0.9, alpha: 1)
    for l in [photoName, photoRole] { l.layer.shadowColor = UIColor.black.cgColor; l.layer.shadowOpacity = 0.5; l.layer.shadowRadius = 2; l.layer.shadowOffset = CGSize(width: 0, height: 1) }
    let ps = UIStackView(arrangedSubviews: [photoName, photoRole]); ps.axis = .vertical; ps.alignment = .leading
    playDisc.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.92, alpha: 0.85); playDisc.layer.cornerRadius = 25; playDisc.isUserInteractionEnabled = false
    let tri = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))); tri.tintColor = UIColor(white: 0.23, alpha: 1)
    playDisc.addSubview(tri); tri.translatesAutoresizingMaskIntoConstraints = false
    vlen.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); vlen.textColor = .white
    vlen.layer.shadowColor = UIColor.black.cgColor; vlen.layer.shadowOpacity = 0.6; vlen.layer.shadowRadius = 2; vlen.layer.shadowOffset = CGSize(width: 0, height: 1)
    [ps, playDisc, vlen].forEach { photo.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([ps.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: 12), ps.topAnchor.constraint(equalTo: photo.topAnchor, constant: 8),
                                 playDisc.widthAnchor.constraint(equalToConstant: 50), playDisc.heightAnchor.constraint(equalToConstant: 50),
                                 playDisc.centerXAnchor.constraint(equalTo: photo.centerXAnchor), playDisc.centerYAnchor.constraint(equalTo: photo.centerYAnchor),
                                 tri.centerXAnchor.constraint(equalTo: playDisc.centerXAnchor, constant: 2), tri.centerYAnchor.constraint(equalTo: playDisc.centerYAnchor),
                                 vlen.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: 10), vlen.bottomAnchor.constraint(equalTo: photo.bottomAnchor, constant: -7)])
    photoH = photo.heightAnchor.constraint(equalToConstant: 180); photoH.priority = .init(999); photoH.isActive = true
    // the card
    card.backgroundColor = UIColor.black.withAlphaComponent(0.22); card.layer.cornerRadius = 14; card.layer.cornerCurve = .continuous
    cardName.font = .systemFont(ofSize: 16); cardName.lineBreakMode = .byTruncatingMiddle; cardSize.font = .systemFont(ofSize: 13)
    cardDown.image = UIImage(systemName: "arrow.down.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .light))
    let cs = UIStackView(arrangedSubviews: [cardName, cardSize]); cs.axis = .vertical
    [cardIcon, cs, cardDown].forEach { card.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    let ch = card.heightAnchor.constraint(equalToConstant: 58); ch.priority = .init(999)
    NSLayoutConstraint.activate([ch,
                                 cardIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11), cardIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                                 cardIcon.widthAnchor.constraint(equalToConstant: 22), cardIcon.heightAnchor.constraint(equalToConstant: 29),
                                 cs.leadingAnchor.constraint(equalTo: cardIcon.trailingAnchor, constant: 10), cs.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                                 cs.trailingAnchor.constraint(lessThanOrEqualTo: cardDown.leadingAnchor, constant: -10),
                                 cardDown.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12), cardDown.centerYAnchor.constraint(equalTo: card.centerYAnchor)])
    card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fileTap)))
    // the link's box
    linkBox.backgroundColor = UIColor.black.withAlphaComponent(0.22); linkBox.layer.cornerRadius = 12; linkBox.layer.cornerCurve = .continuous
    linkSite.font = .systemFont(ofSize: 15, weight: .semibold); linkURL.font = .systemFont(ofSize: 14); linkURL.numberOfLines = 2; linkURL.lineBreakMode = .byCharWrapping
    linkFoot.font = .systemFont(ofSize: 14)
    [linkSite, linkURL, linkLine, linkFoot].forEach { linkBox.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([linkSite.topAnchor.constraint(equalTo: linkBox.topAnchor, constant: 9), linkSite.leadingAnchor.constraint(equalTo: linkBox.leadingAnchor, constant: 12), linkSite.trailingAnchor.constraint(equalTo: linkBox.trailingAnchor, constant: -12),
                                 linkURL.topAnchor.constraint(equalTo: linkSite.bottomAnchor), linkURL.leadingAnchor.constraint(equalTo: linkSite.leadingAnchor), linkURL.trailingAnchor.constraint(equalTo: linkSite.trailingAnchor),
                                 linkLine.topAnchor.constraint(equalTo: linkURL.bottomAnchor, constant: 9), linkLine.leadingAnchor.constraint(equalTo: linkSite.leadingAnchor), linkLine.trailingAnchor.constraint(equalTo: linkSite.trailingAnchor), linkLine.heightAnchor.constraint(equalToConstant: 0.5),
                                 linkFoot.topAnchor.constraint(equalTo: linkLine.bottomAnchor, constant: 8), linkFoot.leadingAnchor.constraint(equalTo: linkSite.leadingAnchor), linkFoot.trailingAnchor.constraint(equalTo: linkSite.trailingAnchor),
                                 linkFoot.bottomAnchor.constraint(equalTo: linkBox.bottomAnchor, constant: -9)])
    linkBox.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(linkTap)))
    [nameL, roleL, photoWrap, quoteWrap, cardWrap, voice, linkWrap, textL, footL].forEach { stack.addArrangedSubview($0) }
    stack.setCustomSpacing(2, after: roleL); stack.setCustomSpacing(6, after: photoWrap); stack.setCustomSpacing(7, after: quoteWrap)
    stack.setCustomSpacing(7, after: cardWrap); stack.setCustomSpacing(7, after: linkWrap); stack.setCustomSpacing(2, after: nameL)
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
    lead = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44)
    trail = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -17)
    wMine = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 281 / 393)
    wTheirs = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 250 / 393)
    mediaW = bubble.widthAnchor.constraint(equalToConstant: 262); mediaW.priority = .init(999)
    top = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
    stackTrail = stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -11)
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
      reacts.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -5), reacts.heightAnchor.constraint(equalToConstant: 26),
      sysL.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13), sysL.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
      sysL.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), sysL.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.85),
      retryB.centerYAnchor.constraint(equalTo: bubble.centerYAnchor), retryB.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -6),
    ])
  }
  private var quoteThumbW: NSLayoutConstraint!
  static let clear = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
  required init?(coder: NSCoder) { fatalError() }
  // ---------- the swipe (the design, board 26): the bubble follows the finger; to the right the grey circle with the
  // white arrow comes in beside it and pops once it's far enough; let go — it all springs back ----------
  private lazy var replyIcon: UIView = {
    let v = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
    v.backgroundColor = UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 0.55); v.layer.cornerRadius = 16; v.alpha = 0
    v.isUserInteractionEnabled = false
    let a = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
    a.tintColor = .white; a.center = CGPoint(x: 16, y: 16); v.addSubview(a)
    self.contentView.addSubview(v)
    return v
  }()
  private var moving: [UIView] { [bubble, face, reacts, retryB] }
  func slide(_ dx: CGFloat) {
    let t = CGAffineTransform(translationX: dx, y: 0)
    for v in moving { v.transform = t }
    guard dx > 0 else { replyIcon.alpha = 0; return }
    let p = min(1, dx / 64)
    replyIcon.center = CGPoint(x: bubble.center.x - bubble.bounds.width / 2 - 22, y: bubble.center.y)
    if !popping { replyIcon.transform = CGAffineTransform(translationX: 26 * p - 26 + dx, y: 0).scaledBy(x: 0.5 + 0.5 * p, y: 0.5 + 0.5 * p) }
    replyIcon.alpha = p
    iconDx = dx
  }
  private var popping = false, iconDx: CGFloat = 0
  func pop() {
    popping = true
    let base = CGAffineTransform(translationX: iconDx, y: 0)
    UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.replyIcon.transform = base.scaledBy(x: 1.18, y: 1.18) } completion: { _ in
      UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.replyIcon.transform = CGAffineTransform(translationX: self.iconDx, y: 0) } completion: { _ in self.popping = false }
    }
  }
  func settle(animated: Bool) {
    let go = { for v in self.moving { v.transform = .identity }; self.replyIcon.alpha = 0 }
    popping = false
    if animated { UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: go) } else { go() }
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    for v in moving { v.transform = .identity }
    replyIcon.alpha = 0
    contentView.alpha = 1
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) {
    super.traitCollectionDidChange(p)
    if traitCollection.hasDifferentColorAppearance(comparedTo: p) { reacts.layer.borderColor = Look.chatBg.resolvedColor(with: traitCollection).cgColor; if let m = msg { foot(m) } }
  }
  // a photo: its corners follow the bubble's (top 19; at the bottom 19, the tail's 4 — or square above words)
  // a photo: rounded 19 at the top, and at the bottom too when no words follow (Apple's corner mask, so it follows the
  // photo's own size); the bubble's colour only under the words — none at all round a photo alone (it sat out from
  // under a photo as a coloured edge and a second tail: the old way read the sizes before they were laid out)
  private func shapePhoto() {
    photo.layer.cornerRadius = media ? 19 : 0; photo.layer.cornerCurve = .continuous
    photo.layer.maskedCorners = caption ? [.layerMinXMinYCorner, .layerMaxXMinYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    photo.layer.mask = nil
    bubble.fillTop = media ? (caption ? photoH.constant - 1 : .greatestFiniteMagnitude) : 0
  }
  private var group: Group?, log: GroupLog?

  func set(_ m: Msg, group g: Group, log l: GroupLog, run: Run) {
    msg = m; group = g; log = l
    let T = Talk.shared, mine = m.by == T.me?.id
    isMine = mine
    let sys = m.kind == "sys"
    sysL.isHidden = !sys; bubble.isHidden = sys; reacts.isHidden = true; retryB.isHidden = !(mine && m.failed); face.isHidden = true
    bubbleBottom.isActive = false; reactsBottom.isActive = false
    if sys { sysL.text = m.text; media = false; return }
    top.constant = run.first ? 10 : 2
    let isVideo = !m.deleted && m.file != nil && m.kind == "video"
    let isPhoto = !m.deleted && m.file != nil && (m.kind == "photo" || isVideo)
    let isVoice = !m.deleted && m.file != nil && m.kind == "voice"
    let isDoc = !m.deleted && m.file != nil && !isPhoto && !isVoice
    media = isPhoto; caption = isPhoto && !m.text.isEmpty
    lead.isActive = !mine; trail.isActive = mine
    mediaW.constant = isVoice ? 292 : mine ? 236 : 262; mediaW.isActive = isPhoto || isVoice
    wMine.isActive = mine && !isPhoto && !isVoice; wTheirs.isActive = !mine && !isPhoto && !isVoice
    stackTrail.constant = mine ? -11 : -12
    bubble.fill = mine ? Look.mine : Look.theirs
    tailOn = run.last && (!isPhoto || caption)
    bubble.tail = (mine, tailOn)
    let ink: UIColor = mine ? .white : .label, dim: UIColor = mine ? Look.mineTime : Look.roleInk
    // the name: over a photo for one, else at the top (others', first of a run)
    let showName = !mine && run.first
    let p = T.people[m.by]
    let client = p?.contact == true && !T.isContact
    let role = client ? "Client" : (p?.role ?? "")
    nameL.isHidden = !showName || isPhoto; roleL.isHidden = nameL.isHidden || role.isEmpty
    photoName.isHidden = !(showName && isPhoto); photoRole.isHidden = photoName.isHidden || role.isEmpty; diag.isHidden = photoName.isHidden
    for (n, r) in [(nameL, roleL), (photoName, photoRole)] {
      n.text = p?.name ?? "Someone"; n.textColor = Look.person(m.by)
      r.text = role; r.font = .systemFont(ofSize: 12, weight: client ? .semibold : .regular)
    }
    roleL.textColor = client ? Look.clientInk : Look.roleInk; photoRole.textColor = client ? Look.clientInk : UIColor(white: 0.9, alpha: 1)
    if !mine && run.last { face.isHidden = false; face.set(person: p) }
    // a reply's quote — the original's picture at the right when it was a photo
    quoteWrap.isHidden = m.reply == nil || m.deleted
    quoteWrap.reach(0, 8, 0, mine ? 7 : 8)
    if let r = m.reply {
      quoteBar.backgroundColor = Look.person(r.by)
      quoteName.text = r.by == T.me?.id ? "You" : T.name(r.by); quoteName.textColor = mine ? .white : Look.person(r.by)
      let cam = r.kind == "photo" || r.kind == "video"
      let qt = NSMutableAttributedString()
      if cam || r.kind == "voice" || r.kind == "file" {
        let sym = r.kind == "voice" ? "mic.fill" : r.kind == "file" ? "doc.fill" : r.kind == "video" ? "video.fill" : "camera.fill"
        qt.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))!.withTintColor(.secondaryLabel))))
        qt.append(NSAttributedString(string: " "))
      }
      let words = r.text.isEmpty ? (r.kind == "photo" ? "Photo" : r.kind == "video" ? "Video" : r.kind == "voice" ? "Voice message" : r.kind == "file" ? "File" : "") : r.text
      qt.append(NSAttributedString(string: words))
      qt.addAttribute(.foregroundColor, value: mine ? UIColor.white.withAlphaComponent(0.8) : UIColor.secondaryLabel, range: NSRange(location: 0, length: qt.length))
      quoteText.attributedText = qt
      quoteThumb.image = nil; quoteThumbW.constant = 0
      if cam, let o = l.msgs.first(where: { $0.id == r.id }), let f = o.file {
        quoteThumbW.constant = 54
        Net.shared.file(f.id) { [weak self] url in
          guard let self = self, self.msg?.id == m.id, let url = url else { return }
          if o.kind == "video" { BubbleCell.frame(url, f.id) { [weak self] i in if self?.msg?.id == m.id { self?.quoteThumb.image = i } } }
          else { self.quoteThumb.image = UIImage(contentsOfFile: url.path) }
        }
      }
    }
    // a photo / a video — to the bubble's edges (reaching past the stack's padding)
    photoWrap.isHidden = !isPhoto
    playDisc.isHidden = !isVideo; vlen.isHidden = !isVideo || m.file?.secs == nil
    if isPhoto, let f = m.file {
      let w: CGFloat = mine ? 236 : 262, ratio = CGFloat((f.h ?? 3) / max(1, f.w ?? 4))
      photoH.constant = min(330, max(120, w * ratio))
      photoWrap.reach(8, 12, caption ? 0 : 7, mine ? 11 : 12)
      photo.image = nil
      if let s = f.secs { vlen.text = String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
      if !isVideo || f.size <= 60 * 1024 * 1024 || FileManager.default.fileExists(atPath: Net.local(f.id).path) {
        Net.shared.file(f.id) { [weak self] url in
          guard let self = self, self.msg?.id == m.id, let url = url else { return }
          if isVideo { BubbleCell.frame(url, f.id) { [weak self] img in if self?.msg?.id == m.id { self?.photo.image = img } } }
          else { self.photo.image = BubbleCell.picture(url, f.id) }
        }
      }
    }
    shapePhoto()
    foot.isHidden = !(isPhoto && !caption)
    voice.isHidden = !isVoice
    if isVoice, let f = m.file { voice.set(id: m.id, file: f, by: m.by, mine: mine) }
    // a document: the card, 4 from the bubble's edge
    cardWrap.isHidden = !isDoc
    cardWrap.reach(nameL.isHidden ? 4 : 0, 8, 0, mine ? 7 : 8)
    if isDoc, let f = m.file {
      let ext = (f.name as NSString).pathExtension.lowercased()
      cardIcon.image = BubbleCell.docIcon(ext.isEmpty ? "file" : ext)
      cardName.text = f.name; cardName.textColor = ink
      cardSize.text = ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file) + " · " + (ext.isEmpty ? "file" : ext); cardSize.textColor = dim
      cardDown.isHidden = mine || FileManager.default.fileExists(atPath: Net.local(f.id).path); cardDown.tintColor = ink
    }
    // the words — the time sits on their last line when it fits (room kept for it at the end, as WhatsApp); a link: its box, and blue
    let a = NSMutableAttributedString()
    link = nil
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
      if let d = BubbleCell.links, !m.text.isEmpty {
        let ns = m.text as NSString
        for hit in d.matches(in: m.text, range: NSRange(location: 0, length: ns.length)) {
          guard let u = hit.url, u.scheme?.hasPrefix("http") == true else { continue }
          if link == nil { link = u }
          a.addAttributes([.foregroundColor: mine ? UIColor.white : Look.linkInk, .underlineStyle: NSUnderlineStyle.single.rawValue], range: hit.range)
        }
      }
    }
    linkWrap.isHidden = link == nil || isPhoto || isDoc
    linkWrap.reach(nameL.isHidden ? 4 : 0, 8, 0, mine ? 7 : 8)
    if let u = link {
      let site = (u.host ?? "").replacingOccurrences(of: "www.", with: "")
      let sub: UIColor = mine ? UIColor.white.withAlphaComponent(0.8) : .secondaryLabel
      linkSite.text = site; linkSite.textColor = ink
      linkURL.text = u.absoluteString; linkURL.textColor = sub
      linkLine.backgroundColor = sub.withAlphaComponent(0.3)
      let lf = NSMutableAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "link", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))!.withTintColor(sub)))
      lf.append(NSAttributedString(string: "  " + site, attributes: [.foregroundColor: sub])); linkFoot.attributedText = lf
    }
    let words = a.length > 0
    textL.isHidden = !words
    footL.isHidden = true
    stamp.isHidden = false
    foot(m)
    if words {
      let room = NSTextAttachment(image: BubbleCell.clear); room.bounds = CGRect(x: 0, y: 0, width: ceil(stamp.intrinsicContentSize.width) + 10, height: 1)
      a.append(NSAttributedString(attachment: room))
      textL.attributedText = a
    } else if !isPhoto && !isVoice {
      // (a card with no words: the time on its own line under it; a voice message keeps it at its bottom right)
      footL.isHidden = false; stamp.isHidden = true
    }
    // reactions under the bubble: the emojis and how many
    let counts = Dictionary(grouping: m.reactions.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    reacts.isHidden = counts.isEmpty || m.deleted
    reacts.text = counts.map { $0.0 }.joined() + (m.reactions.count > 1 ? " \(m.reactions.count)" : "")
    reactsLead.isActive = !mine; reactsTrail.isActive = mine
    if reacts.isHidden { bubbleBottom.isActive = true } else { reactsBottom.isActive = true }
    setNeedsLayout()
  }
  // the time inside — "Edited" before it, ✓✓ after it on yours; over a photo with no words: white, on its shadow
  private func foot(_ m: Msg) {
    guard let g = group, let l = log else { return }
    let T = Talk.shared, mine = m.by == T.me?.id
    let over = media && !caption
    let dim: UIColor = over ? .white : mine ? Look.mineTime : Look.roleInk
    let f = NSMutableAttributedString(string: (m.edited && !m.deleted ? "Edited " : "") + Look.clock(m.at), attributes: [.foregroundColor: dim, .font: UIFont.systemFont(ofSize: 12)])
    if mine && !m.deleted {
      let others = g.members.filter { $0 != m.by }
      let idx = l.msgs.firstIndex { $0.id == m.id } ?? 0
      let allSeen = !T.isContact && !others.isEmpty && others.allSatisfy { p in l.readBy[p].flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 >= idx } ?? false }
      f.append(NSAttributedString(string: " "))
      if m.pending {
        f.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: m.failed ? "exclamationmark.circle" : "clock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))!.withTintColor(dim.resolvedColor(with: traitCollection)))))
      } else {
        let c: UIColor = over ? .white : allSeen ? Look.readTick : Look.mineTime
        let t = NSTextAttachment(image: Ticks.image(c.resolvedColor(with: traitCollection)))
        t.bounds = CGRect(x: 0, y: -1, width: 16, height: 10)
        f.append(NSAttributedString(attachment: t))
      }
    }
    footL.attributedText = f; stamp.attributedText = f
    stamp.layer.shadowColor = UIColor.black.cgColor; stamp.layer.shadowOpacity = over ? 0.6 : 0; stamp.layer.shadowRadius = 2; stamp.layer.shadowOffset = CGSize(width: 0, height: 1)
  }
  static let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
  // a document's kind as the design draws it: a grey page with its corner turned, the kind in white on it
  private static var icons: [String: UIImage] = [:]
  static func docIcon(_ ext: String) -> UIImage {
    let label = String(ext.prefix(4)).uppercased()
    if let i = icons[label] { return i }
    let i = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 29)).image { _ in
      let page = UIBezierPath(); page.move(to: CGPoint(x: 3, y: 0)); page.addLine(to: CGPoint(x: 14, y: 0)); page.addLine(to: CGPoint(x: 22, y: 8)); page.addLine(to: CGPoint(x: 22, y: 26))
      page.addQuadCurve(to: CGPoint(x: 19, y: 29), controlPoint: CGPoint(x: 22, y: 29)); page.addLine(to: CGPoint(x: 3, y: 29)); page.addQuadCurve(to: CGPoint(x: 0, y: 26), controlPoint: CGPoint(x: 0, y: 29))
      page.addLine(to: CGPoint(x: 0, y: 3)); page.addQuadCurve(to: CGPoint(x: 3, y: 0), controlPoint: CGPoint(x: 0, y: 0)); page.close()
      UIColor.systemGray.setFill(); page.fill()
      let fold = UIBezierPath(); fold.move(to: CGPoint(x: 14, y: 0)); fold.addLine(to: CGPoint(x: 14, y: 5)); fold.addQuadCurve(to: CGPoint(x: 17, y: 8), controlPoint: CGPoint(x: 14, y: 8)); fold.addLine(to: CGPoint(x: 22, y: 8)); fold.close()
      UIColor.systemGray3.setFill(); fold.fill()
      let s = NSAttributedString(string: label, attributes: [.font: UIFont.systemFont(ofSize: label.count > 3 ? 5.5 : 7, weight: .heavy), .foregroundColor: UIColor.white])
      let sz = s.size(); s.draw(at: CGPoint(x: (22 - sz.width) / 2, y: 29 - 5 - sz.height))
    }
    icons[label] = i; return i
  }
  // a photo, shrunk once to the bubble's size and kept
  private static let pictures = NSCache<NSString, UIImage>()
  static func picture(_ url: URL, _ id: String) -> UIImage? {
    if let i = pictures.object(forKey: id as NSString) { return i }
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 800] as CFDictionary) else { return UIImage(contentsOfFile: url.path) }
    let i = UIImage(cgImage: cg); pictures.setObject(i, forKey: id as NSString); return i
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
  @objc private func linkTap() { if let u = link { UIApplication.shared.open(u) } }
  func flash() {
    UIView.animate(withDuration: 0.2, animations: { self.bubble.alpha = 0.55 }) { _ in UIView.animate(withDuration: 0.6) { self.bubble.alpha = 1 } }
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
  var onLayout: (() -> Void)?
  var recording: Bool { rec.isRecording || rec.isPaused || locked }
  // @: the group's people (id, name); the ones picked while typing
  var people: [(String, String)] = []
  private var picked: [String: String] = [:]   // id → name
  private let mentionV = UIStackView()
  private var mentionQ: (NSRange, String)?
  // the voice message being recorded: red dot, time, "‹ Slide to cancel"
  private let rec = VoiceRecorder()
  // recording (the approved design, boards 21 / 29–31): holding — the red mic, the time, "Slide to cancel ‹", the lock pill
  // above the mic; slid left — the mic flips into the bin; pulled up — locked: the time and the live waveform, then
  // delete · pause · send
  private let recV = UIView(), recMic = UIImageView(), recTime = UILabel(), recHint = UILabel()
  private let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial)), pillLock = UIImageView(), pillUp = UIImageView()
  private let binBody = UIImageView(), binLid = UIImageView()
  private let lockedV = UIView(), lockedTime = UILabel(), live = LiveWave(), trashB = UIButton(type: .system), pauseB = UIButton(type: .system), lockedSend = UIButton(type: .system)
  private var recCancelled = false, recStart: CGPoint = .zero, locked = false, holding = false
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
    recMic.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)); recMic.tintColor = .systemRed
    recMic.contentMode = .center; recMic.alpha = 0
    for l in [recTime, lockedTime] { l.font = .monospacedDigitSystemFont(ofSize: 20, weight: .regular); l.textColor = .label }
    recHint.text = "Slide to cancel ‹"; recHint.font = .systemFont(ofSize: 17); recHint.textColor = .secondaryLabel; recHint.textAlignment = .center
    [recTime, recHint].forEach { recV.addSubview($0) }
    addSubview(recV); addSubview(recMic)
    pill.layer.cornerRadius = 20; pill.clipsToBounds = true; pill.alpha = 0; pill.isUserInteractionEnabled = false
    pillLock.image = UIImage(systemName: "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)); pillLock.tintColor = .label; pillLock.contentMode = .center
    pillUp.image = UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)); pillUp.tintColor = .secondaryLabel; pillUp.contentMode = .center
    pill.contentView.addSubview(pillLock); pill.contentView.addSubview(pillUp)
    binBody.image = MessageBar.bin(lid: false); binLid.image = MessageBar.bin(lid: true)
    [binBody, binLid].forEach { $0.tintColor = .secondaryLabel; $0.alpha = 0; addSubview($0) }
    binLid.layer.anchorPoint = CGPoint(x: 0.08, y: 0.9)
    lockedV.isHidden = true; lockedV.backgroundColor = .clear
    trashB.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)), for: .normal); trashB.tintColor = .label
    trashB.accessibilityLabel = "Delete the recording"
    pauseB.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal); pauseB.tintColor = .systemRed
    pauseB.layer.borderWidth = 2; pauseB.layer.cornerRadius = 17; pauseB.accessibilityLabel = "Pause the recording"
    var ls = UIButton.Configuration.filled()
    ls.image = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
    ls.baseBackgroundColor = Look.rgb(0x2F7BFF); ls.baseForegroundColor = .white; ls.cornerStyle = .capsule; ls.contentInsets = .zero
    lockedSend.configuration = ls; lockedSend.accessibilityLabel = "Send"
    [lockedTime, live, trashB, pauseB, lockedSend].forEach { lockedV.addSubview($0) }
    addSubview(lockedV); addSubview(pill)
    trashB.addAction(UIAction { [weak self] _ in self?.cancelRecording() }, for: .touchUpInside)
    pauseB.addAction(UIAction { [weak self] _ in self?.togglePause() }, for: .touchUpInside)
    lockedSend.addAction(UIAction { [weak self] _ in self?.endRecording(send: true) }, for: .touchUpInside)
    rec.onTick = { [weak self] t in
      guard let self = self else { return }
      let s = String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
      self.recTime.text = s; self.lockedTime.text = s
      if self.locked { self.live.levels = self.rec.levels }
    }
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
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: (locked ? 83 : boxH + 14) + (replyV.isHidden ? 0 : 46) + mentionH + safeAreaInsets.bottom) }
  override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); invalidateIntrinsicContentSize() }
  override func layoutSubviews() {
    super.layoutSubviews()
    defer { onLayout?() }
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
    recV.frame = CGRect(x: 0, y: y, width: W - 60, height: 32)
    recTime.frame = CGRect(x: 42, y: 0, width: 70, height: 32)
    recHint.frame = CGRect(x: 0, y: 0, width: W, height: 32)
    if recMic.transform == .identity { recMic.frame = CGRect(x: 10, y: y, width: 26, height: 32) }
    pill.frame = CGRect(x: W - 44, y: y - 101, width: 40, height: 132)
    pillLock.frame = CGRect(x: 0, y: 10, width: 40, height: 22); pillUp.frame = CGRect(x: 0, y: 34, width: 40, height: 14)
    binBody.bounds = CGRect(x: 0, y: 0, width: 22, height: 18); binLid.bounds = CGRect(x: 0, y: 0, width: 22, height: 8)
    if binBody.alpha == 0 { binBody.center = CGPoint(x: 23, y: y + 25); binLid.center = CGPoint(x: 23 - 9.24, y: y + 13.2) }
    lockedV.frame = CGRect(x: 0, y: top, width: W, height: 83)
    lockedTime.frame = CGRect(x: 16, y: 10, width: 64, height: 24)
    live.frame = CGRect(x: 80, y: 11, width: W - 96, height: 22)
    trashB.frame = CGRect(x: 10, y: 44, width: 40, height: 40)
    pauseB.frame = CGRect(x: W / 2 - 17, y: 47, width: 34, height: 34)
    lockedSend.frame = CGRect(x: W - 56, y: 42, width: 44, height: 44)
    pauseB.layer.borderColor = UIColor.systemRed.resolvedColor(with: traitCollection).cgColor
  }
  @objc private func micHold(_ g: UILongPressGestureRecognizer) {
    switch g.state {
    case .began:
      recCancelled = false; locked = false; holding = true; recStart = g.location(in: self)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      rec.start { [weak self] ok in
        guard let self = self else { return }
        guard ok else { toast("Allow the microphone for E11 Talk in Settings to record"); return }
        guard self.holding else { _ = self.rec.stop(keep: false); return }
        ChatSound.voiceStart()
        self.recTime.text = "0:00"; self.lockedTime.text = "0:00"
        self.recV.isHidden = false; self.recV.alpha = 0; self.recMic.alpha = 0
        self.recHint.transform = CGAffineTransform(translationX: 60, y: 0)
        self.pill.transform = CGAffineTransform(translationX: 0, y: 40).scaledBy(x: 1, y: 0.4)
        self.pillLock.image = UIImage(systemName: "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        // (the box, + and camera slide away left; the time, the hint and the pill come in; the mic grows under the finger)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
          for v in [self.box, self.smiley, self.plus, self.cam] as [UIView] { v.alpha = 0; v.transform = CGAffineTransform(translationX: -60, y: 0) }
          self.recV.alpha = 1; self.recMic.alpha = 1; self.recHint.transform = .identity
          self.pill.alpha = 1; self.pill.transform = .identity
          self.mic.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        }
        UIView.animate(withDuration: 0.6, delay: 0.3, options: [.repeat, .autoreverse, .allowUserInteraction]) { self.recMic.alpha = 0.35 }
      }
    case .changed:
      guard rec.isRecording, !recCancelled, !locked else { return }
      let p = g.location(in: self), dx = p.x - recStart.x, dy = p.y - recStart.y
      if dy < -12 && dy < dx {
        // pulling up: the mic rises into the pill, the pill shortens; far enough — locked
        mic.transform = CGAffineTransform(translationX: 0, y: max(dy, -82)).scaledBy(x: 1.15, y: 1.15)
        pill.transform = CGAffineTransform(translationX: 0, y: max(dy, -82) * 0.08).scaledBy(x: 1, y: max(0.62, 1 + dy / 220))
        if dy < -82 { lock() }
      } else {
        recHint.transform = CGAffineTransform(translationX: min(0, dx), y: 0); recHint.alpha = max(0, 1 + dx / 140)
        if dx < -120 { cancelRecording() }
      }
    case .ended: holding = false; if !recCancelled && !locked { endRecording(send: true) }
    case .cancelled, .failed: holding = false; if !recCancelled && !locked { endRecording(send: false) }
    default: break
    }
  }
  // pulled up into the lock: it shuts, the pill goes, the bar opens to the locked recording
  private func lock() {
    locked = true
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    pillLock.image = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    live.levels = rec.levels
    lockedV.isHidden = false; lockedV.alpha = 0; lockedV.transform = CGAffineTransform(translationX: 0, y: 40)
    invalidateIntrinsicContentSize()
    UIView.animate(withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
      self.pill.alpha = 0; self.mic.alpha = 0; self.recV.alpha = 0; self.recMic.alpha = 0
      self.lockedV.alpha = 1; self.lockedV.transform = .identity
      self.superview?.layoutIfNeeded(); self.layoutIfNeeded()
    }
  }
  private func togglePause() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let paused = rec.togglePause()
    pauseB.setImage(UIImage(systemName: paused ? "mic.fill" : "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal)
  }
  // slid left (or the bin while locked): the recording goes — the red mic flips up and drops into the bin, the bin sinks
  private func cancelRecording() {
    guard !recCancelled else { return }
    recCancelled = true
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    _ = rec.stop(keep: false)
    let wasLocked = locked
    recMic.layer.removeAllAnimations(); recMic.alpha = 1
    let start = recMic.center
    binBody.alpha = 0; binLid.alpha = 0
    binBody.transform = CGAffineTransform(translationX: 0, y: 46); binLid.transform = CGAffineTransform(translationX: 0, y: 46)
    UIView.animate(withDuration: 0.2) {
      self.recV.alpha = 0; self.pill.alpha = 0; self.mic.transform = .identity; self.lockedV.alpha = 0
    }
    UIView.animateKeyframes(withDuration: 1.25, delay: wasLocked ? 0.1 : 0, options: [.calculationModeCubic]) {
      UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.35) {
        self.recMic.center = CGPoint(x: start.x, y: start.y - 70); self.recMic.transform = CGAffineTransform(rotationAngle: -.pi)
        self.binBody.alpha = 1; self.binLid.alpha = 1; self.binBody.transform = .identity; self.binLid.transform = .identity
      }
      UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.1) { self.binLid.transform = CGAffineTransform(rotationAngle: -0.95) }
      UIView.addKeyframe(withRelativeStartTime: 0.35, relativeDuration: 0.2) {
        self.recMic.center = CGPoint(x: self.binBody.center.x, y: self.binBody.center.y); self.recMic.transform = CGAffineTransform(rotationAngle: -2 * .pi).scaledBy(x: 0.5, y: 0.5)
      }
      UIView.addKeyframe(withRelativeStartTime: 0.55, relativeDuration: 0.02) { self.recMic.alpha = 0 }
      UIView.addKeyframe(withRelativeStartTime: 0.55, relativeDuration: 0.1) { self.binLid.transform = .identity }
      UIView.addKeyframe(withRelativeStartTime: 0.7, relativeDuration: 0.3) {
        self.binBody.transform = CGAffineTransform(translationX: 0, y: 60); self.binLid.transform = CGAffineTransform(translationX: 0, y: 60)
        self.binBody.alpha = 0; self.binLid.alpha = 0
      }
    } completion: { _ in
      self.recMic.transform = .identity; self.recMic.center = start
      self.backToBox()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ChatSound.voiceCancel() }
  }
  private func endRecording(send: Bool) {
    recMic.layer.removeAllAnimations()
    let r = rec.isRecording || rec.isPaused ? rec.stop(keep: send) : nil
    UIView.animate(withDuration: 0.2) { self.recV.alpha = 0; self.recMic.alpha = 0; self.pill.alpha = 0; self.lockedV.alpha = 0; self.mic.transform = .identity }
    backToBox()
    if let r = r { UIImpactFeedbackGenerator(style: .light).impactOccurred(); ChatSound.send(); onVoice?(r.0, r.1, r.2) }
    else if send { toast("Hold longer to record") }
  }
  // the box, + and camera slide back
  private func backToBox() {
    locked = false
    recV.isHidden = true; lockedV.isHidden = true
    recHint.alpha = 1; recHint.transform = .identity
    pauseB.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal)
    invalidateIntrinsicContentSize()
    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
      for v in [self.box, self.smiley, self.plus, self.cam, self.mic] as [UIView] { v.alpha = 1; v.transform = .identity }
      self.superview?.layoutIfNeeded(); self.layoutIfNeeded()
    }
  }
  // the bin as the design draws it — its body, and its lid apart so it can open
  static func bin(lid: Bool) -> UIImage {
    let size = lid ? CGSize(width: 22, height: 8) : CGSize(width: 22, height: 18)
    return UIGraphicsImageRenderer(size: size).image { _ in
      let p = UIBezierPath()
      if lid { p.move(to: CGPoint(x: 1, y: 7)); p.addLine(to: CGPoint(x: 21, y: 7)); p.move(to: CGPoint(x: 8, y: 7)); p.addLine(to: CGPoint(x: 8, y: 4)); p.addLine(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 14, y: 7)) }
      else { p.move(to: CGPoint(x: 3, y: 1)); p.addLine(to: CGPoint(x: 4.3, y: 16.2)); p.addLine(to: CGPoint(x: 17.7, y: 16.2)); p.addLine(to: CGPoint(x: 19, y: 1)); p.move(to: CGPoint(x: 8.5, y: 5)); p.addLine(to: CGPoint(x: 8.5, y: 13)); p.move(to: CGPoint(x: 13.5, y: 5)); p.addLine(to: CGPoint(x: 13.5, y: 13)) }
      p.lineWidth = 1.8; p.lineCapStyle = .round; p.lineJoinStyle = .round
      UIColor.black.setStroke(); p.stroke()
    }.withRenderingMode(.alwaysTemplate)
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
