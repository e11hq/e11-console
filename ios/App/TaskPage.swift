import UIKit
import UniformTypeIdentifiers

/* The task page, the app's own (shell 30, Haris 2026-11-01): it slides in from the right like any iPhone page and goes
   back with ‹ or iPhone's swipe from the left edge, following the finger. The Details tab is drawn here from the
   server's model (GET /api/task — the website's own rules, web/rules.js) and its changes go to the server
   (/api/home/act, from: task). Nothing on it is drawn or moved by the page behind; the page only says which task to
   open and when the task changed. The Comments tab, until it's the app's own too, shows the comments screen (the
   second web view) inside this page, under its bar. */

// the server side: the task as it is now, and its changes
final class ServerTask {
  var cookies: (@escaping (String) -> Void) -> Void = { $0("") }
  private var lastRev = 0
  var lastUndo: String?
  var cache: [String: [String: Any]] = [:]   // each task as last fetched (opened again: shown at once)
  func request(_ path: String, body: [String: Any]?, timeout: Double = 20, _ done: @escaping ([String: Any]?) -> Void) {
    cookies { cookie in
      guard let url = URL(string: serverURL() + path) else { return done(nil) }
      var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
      r.setValue("application/json", forHTTPHeaderField: "Accept")
      if !cookie.isEmpty { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
      if let b = body { r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: b) }
      URLSession.shared.dataTask(with: r) { d, resp, _ in
        let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200
        let j = ok ? d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
        DispatchQueue.main.async { done(j) }
      }.resume()
    }
  }
  // → the model, nil (not there / not for this person), or "off" (the server switched it off)
  func fetch(_ id: String, _ done: @escaping ([String: Any]?, Bool) -> Void) {
    let q = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
    request("/api/task?id=" + q, body: nil) { [weak self] j in
      guard let j = j else { return done(nil, false) }
      if (j["off"] as? Bool) == true { return done(nil, true) }
      let rev = j["rev"] as? Int ?? 0
      if let self = self, rev < self.lastRev { return }
      self?.lastRev = rev
      if let m = j["task"] as? [String: Any] { self?.cache[id] = m } else { self?.cache[id] = nil }
      done(j["task"] as? [String: Any], false)
    }
  }
  // a change → (ok, the task as it is now, error, need)
  func act(_ body: [String: Any], _ done: @escaping (Bool, [String: Any]?, String?, String?, [String]) -> Void) {
    var b = body; b["from"] = "task"; b["op"] = UUID().uuidString
    // (with the app's own copy: just what changed comes back, into the copy — the page is drawn from it: step 3)
    let copy = AppData.shared.ready
    if copy { b["copy"] = true }
    // (done on the phone's copy at once — the same code as the server's; put back if the server says no — Haris 2026-11-07)
    let undo = copy ? AppData.shared.localAct(b) : nil
    request("/api/home/act", body: b) { [weak self] j in
      guard let j = j else { AppData.shared.putBack(undo); return done(false, nil, "No connection — try again", nil, []) }
      if (j["off"] as? Bool) == true { AppData.shared.putBack(undo); return done(false, nil, "Try again in a moment", nil, []) }
      if (j["ok"] as? Bool) != true { AppData.shared.putBack(undo) }
      if copy, let ch = j["changes"] as? [[String: Any]] { AppData.shared.applyLocal(ch) }
      else if let rev = j["rev"] as? Int { self?.lastRev = max(self?.lastRev ?? 0, rev) }
      self?.lastUndo = j["undo"] as? String
      done((j["ok"] as? Bool) == true, j["task"] as? [String: Any], j["error"] as? String, j["need"] as? String, j["messages"] as? [String] ?? [])
    }
  }
}

final class TaskPage: UIView, UICollectionViewDelegate, UIGestureRecognizerDelegate, UITextViewDelegate {
  let taskId: String
  var model: [String: Any]?
  var people: [String: [String: Any]] = [:]
  var onTab: ((String) -> Void)?                      // "details" | "comments"
  var onAct: (([String: Any]) -> Void)?               // a change for the server
  var onEvent: (([String: Any]) -> Void)?             // for the page behind: copy, attach, from…
  var onOpen: ((String) -> Void)?                      // another task (a subtask, "New task from")
  var onDate: ((String, String, @escaping (String?) -> Void) -> Void)?   // which (start / due), its value → the new one
  var onComplete: (() -> Void)?
  // iPhone's own sheet (NativeSheetVC): its args, a tick (several), the answer (a row, or -2 with what was typed)
  var onSheet: (([String: Any], @escaping (Int) -> Void, @escaping (Int, String?) -> Void) -> Void)?
  var light = LAST_LIGHT { didSet { if light != oldValue { applyLook() } } }   // (only a real change of look draws the page again)
  private(set) var tab = "details"

  // Details: Apple's list (step 2, Haris 2026-11-08) — Apple places its cells and animates what comes, goes and changes
  let scroll: UICollectionView = {
    let cv = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    cv.backgroundColor = .clear
    return cv
  }()
  // (Haris 2026-11-09, "Task page Details — fully Apple": Apple's inset-grouped list — each row Apple's own list cell set
  //  by Apple's configuration in Apple's boxes, Apple's headers, the creator as Apple's footer; ours, held in Apple's
  //  cells, only what Apple has no part for — the client line, the title, the notes, the description, the files)
  private var listDS: UICollectionViewDiffableDataSource<String, String>?
  private var dSecs: [DSec] = []
  private var dItems: [String: DItem] = [:]
  // the frost under the bar follows whichever list is showing (Details, the comments, a thread)
  // (Details · Comments is in Apple's own bar now — Haris 2026-11-08: the bar's frost and its line follow the list that's
  //  showing, Apple's firm frost as every Apple page)
  var onEdgeScroll: ((UIScrollView) -> Void)?
  func edgeScroll(_ sv: UIScrollView) {
    onEdgeScroll?(sv)   // (Apple's own frost, untouched — as Home: Haris 2026-11-09)
  }
  // the page's ••• menu, for Apple's bar (TaskVC)
  private(set) var cornerMenu: UIMenu?
  var feed: CommentsFeed?
  var threadFeed: CommentsFeed? { didSet { updatePager() } }
  // the description's editor (DescEditor.swift)
  let descView = PasteTextView()   // (a file copied in the app pastes in as its 📎, its card under the description)
  // (the description as it's read — view only — links tappable)
  private lazy var descRead: UITextView = {
    let t = UITextView(); t.isEditable = false; t.isScrollEnabled = false; t.backgroundColor = .clear
    t.textContainerInset = .zero; t.textContainer.lineFragmentPadding = 0; t.dataDetectorTypes = [.link]
    return t
  }()
  // (while the description is being written, nothing else on the page answers a tap — only Done ends it: Haris,
  //  2026-11-02)
  var editingDesc = false { didSet { if oldValue != editingDesc { holdForDesc(); onDescEditing?(editingDesc) } } }
  var onDescEditing: ((Bool) -> Void)?   // (iPhone's own bar: Done in place of ••• while it's written — AppleNav)
  var descEmpty = true
  private func holdForDesc() {
    for c in scroll.visibleCells { c.isUserInteractionEnabled = !editingDesc || descBox.isDescendant(of: c) }
    seg.isEnabled = !editingDesc
    updatePager()
  }
  let mentionBox = UIStackView()
  var onSubmitFiles: ((String) -> Void)?
  var onOpenFiles: (([[String: Any]], Int) -> Void)?
  var onAttachFiles: (() -> Void)?
  var onAttachFrom: ((String) -> Void)?
  var onFileAction: (([String: Any], String) -> Void)?   // a file's "open" / "copy" / "download" (its touch-and-hold menu)   // (••• → Attach Files → Camera / Photos / Files)
  // files uploading from the phone (Haris, 2026-11-02): cards in the Files row straight away, pulsing with their rings
  // ({ id, name, pending, thumbUrl: "local:…", sent }); each gives its place to the real one once the server has it
  private(set) var uploads: [[String: Any]] = []
  private var knownFiles = Set<String>()
  func addUploads(scroll: Bool = true, _ u: [[String: Any]]) {
    let started = uploads.isEmpty
    if started { knownFiles = Set(((model?["files"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }) }
    uploads += u
    built = ""; if let m = model { draw(m) }
    // (attaching: down to Files, where they are)
    // (from the description's 📎: the page stays where the cursor is — Haris 2026-11-02)
    if started && scroll && !editingDesc { DispatchQueue.main.async { self.showFiles() } }
    // (then sideways to the last one you're attaching, once the page is down at Files — only on your own phone, only
    //  for these attaches; not the description's 📎)
    if scroll && !editingDesc, let last = u.last?["id"] as? String {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.filesStrip.reveal(last) }
    }
  }
  // sent to the task (waiting for the real ones), or gone (didn't upload / never came)
  func uploadsSent(_ ids: Set<String>) { for i in uploads.indices where ids.contains(uploads[i]["id"] as? String ?? "") { uploads[i]["sent"] = true } }
  func dropUploads(_ ids: Set<String>) {
    let n = uploads.count
    uploads.removeAll { ids.contains($0["id"] as? String ?? "") }
    if uploads.count != n { built = ""; if let m = model { draw(m) } }
  }
  private let filesStrip = FileStrip(side: 100), descStrip = FileStrip(side: 100)
  var descPending: [[String: Any]] = []
  var drawnOnce = false
  let openedAt = Date()
  // files uploaded from the description's 📎 Attach (or pasted from outside the app): to the task's files, a chip
  // where the cursor was, greyed with an arrow until it's up
  var onDescAttach: ((String) -> Void)?
  var onDescUpload: (([(URL, String)]) -> Void)?
  var descAutoFinish = false
  private var descInsertAt: NSRange?
  var pulses: [String: UIView] = [:]   // (drawn before: a later drawing animates what changed)
  private var descTouch: (CGPoint, Date)?
  var waiting = 0   // (changes sent, not answered yet)
  // a change shown at once, before the server's answer (Haris, 2026-11-02: changes came with a delay); the answer
  // redraws it as it is — a refused one goes back
  private func local(_ change: (inout [String: Any]) -> Void) {
    guard var m = model else { return }
    change(&m)
    built = ""; draw(m)
  }
  private lazy var descBox: DescBox = {
    let b = DescBox(); b.onExpand = { [weak self] in self?.relayAnimated() }
    // (a tap on it, for whoever may write it: the cursor where the finger was — tapping a description with words in it
    //  sometimes did nothing, Haris 2026-11-02)
    let tap = UITapGestureRecognizer(target: self, action: #selector(tappedDesc(_:))); tap.cancelsTouchesInView = false; tap.delegate = self
    b.addGestureRecognizer(tap)
    return b
  }()
  // the description's file cards, straight under it: the server's, and any pasted in while writing (until saved)
  var descShown: [[String: Any]] {
    let saved = (model?["descFiles"] as? [[String: Any]]) ?? []
    let have = Set(saved.compactMap { $0["file"] as? String })
    return saved + descPending.filter { !have.contains($0["file"] as? String ?? "") }
  }
  private func descStripAfter(_ m: [String: Any]) {
    let saved = Set(((m["descFiles"] as? [[String: Any]]) ?? []).compactMap { $0["file"] as? String })
    descPending.removeAll { saved.contains($0["file"] as? String ?? "") }
    // (no cards under the description: its chips are where its files are — Haris 2026-11-02)
  }
  // a file copied in the app (a preview's Copy), pasted while writing the description: its 📎 where the cursor is, its
  // card under the description at once — saved with Done, as the website keeps it (Haris 2026-11-02)
  func pasteIntoDesc() -> Bool {
    guard descView.isFirstResponder else { return false }
    guard let f = FileClip.current, let path = f["file"] as? String else { return pasteUpload() }
    let name = f["name"] as? String ?? "File"
    let tv = descView, r = tv.selectedRange
    let plain: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.label]
    DescEditor.dark = !light
    let add = NSMutableAttributedString(attributedString: DescEditor.chip(["path": path, "name": name, "size": f["size"] as? Int ?? 0], size: TaskPage.T))
    add.append(NSAttributedString(string: " ", attributes: plain))
    let m = NSMutableAttributedString(attributedString: tv.attributedText); m.replaceCharacters(in: r, with: add)
    tv.attributedText = m
    tv.selectedRange = NSRange(location: r.location + add.length, length: 0)
    tv.typingAttributes = plain
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    // (kept, so tapping its chip opens it before it's saved)
    if !descShown.contains(where: { ($0["file"] as? String) == path }) { descPending.append(f) }
    setNeedsLayout(); relayAnimated()
    return true
  }
  // a tap on a pasted file's 📎 in the description: its preview (with the description's other files)
  private func fileRef(in tv: UITextView, at p: CGPoint) -> [String: Any]? {
    guard tv.attributedText.length > 0, let pos = tv.closestPosition(to: p) else { return nil }
    let i = tv.offset(from: tv.beginningOfDocument, to: pos)
    for k in [i, i - 1] where k >= 0 && k < tv.attributedText.length {
      // (only on the chip itself, not anywhere on its line)
      guard let f = tv.attributedText.attribute(FILEREF_KEY, at: k, effectiveRange: nil) as? [String: Any] else { continue }
      if let r = tv.textRange(from: tv.position(from: tv.beginningOfDocument, offset: k) ?? pos, to: tv.position(from: tv.beginningOfDocument, offset: k + 1) ?? pos), tv.firstRect(for: r).insetBy(dx: -8, dy: -6).contains(p) { return f }
    }
    return nil
  }
  private func openRef(_ f: [String: Any]) {
    let files = descShown
    if let i = files.firstIndex(where: { ($0["file"] as? String) == (f["path"] as? String) }) { onOpenFiles?(files, i) }
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
    if g.view === descBox { descTouch = (t.location(in: descView), Date()) }
    return true
  }
  func textViewShouldBeginEditing(_ tv: UITextView) -> Bool {
    // (a tap on a 📎 opens it, it doesn't start writing)
    if tv === descView, let dt = descTouch, Date().timeIntervalSince(dt.1) < 0.6, let f = fileRef(in: tv, at: dt.0) { descTouch = nil; openRef(f); return false }
    return true
  }
  @objc private func tappedDesc(_ g: UITapGestureRecognizer) {
    if descRead.superview === descBox, let f = fileRef(in: descRead, at: g.location(in: descRead)) { openRef(f); return }
    let tv = descView
    if !tv.isFirstResponder, fileRef(in: tv, at: g.location(in: tv)) != nil { return }
    guard tv.superview === descBox, tv.isEditable, !tv.isFirstResponder else { return }
    let p = g.location(in: tv)
    tv.becomeFirstResponder()
    if let pos = tv.closestPosition(to: p), !descEmpty { tv.selectedTextRange = tv.textRange(from: pos, to: pos) }
  }
  private func relayAnimated() { UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.fitHosts(); self.scroll.layoutIfNeeded() } }
  func showFiles() {
    guard tab == "details", let ip = listDS?.indexPath(for: "files") ?? listDS?.indexPath(for: "attach") else { return }
    // (the Files box's bottom just above the bottom edge — Apple's list scrolls it there)
    scroll.scrollToItem(at: ip, at: .bottom, animated: true)
  }
  let seg = UISegmentedControl(items: ["Details", "Comments"])
  // (a task in the Trash, opened view only: its Details — Haris 2026-11-06)
  var trashId: String? { didSet { seg.setEnabled(trashId == nil, forSegmentAt: 1); updatePager(); setNeedsLayout() } }
  let commentsHost = UIView()                          // the comments screen goes in here
  private let fab = UIButton(type: .system)
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var toastView: UIView?
  private var titleView = UITextView()
  var built = ""

  init(id: String, frame: CGRect) {
    taskId = id
    super.init(frame: frame)
    scroll.alwaysBounceVertical = true
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.keyboardDismissMode = .interactive
    scroll.delegate = self
    scroll.automaticallyAdjustsScrollIndicatorInsets = false   // (the scroll bar starts under the bar from the start — the standard)
    do {
      // iPhone's own paging scroller (Haris 2026-11-07): Details and Comments side by side — Apple's movement
      pager.isPagingEnabled = true
      pager.showsHorizontalScrollIndicator = false; pager.showsVerticalScrollIndicator = false
      pager.contentInsetAdjustmentBehavior = .never
      pager.isDirectionalLockEnabled = true
      pager.scrollsToTop = false
      pager.delegate = self
      addSubview(pager)
      pager.addSubview(scroll)
    }
    scroll.setCollectionViewLayout(makeListLayout(), animated: false)
    let rowReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
      guard let self = self, let it = self.dItems[key] else { return }
      if let c = it.content { cell.contentConfiguration = c }
      cell.accessories = it.accessories
      cell.isUserInteractionEnabled = !self.editingDesc
    }
    let hostReg = UICollectionView.CellRegistration<HostCell, String> { [weak self] cell, _, key in
      guard let self = self, let it = self.dItems[key] else { return }
      cell.host(it.host, pad: it.pad, plain: it.plain)
      cell.isUserInteractionEnabled = !self.editingDesc || it.host === self.descBox
    }
    listDS = UICollectionViewDiffableDataSource<String, String>(collectionView: scroll) { [weak self] cv, ip, key -> UICollectionViewCell? in
      if self?.dItems[key]?.host != nil { return cv.dequeueConfiguredReusableCell(using: hostReg, for: ip, item: key) }
      return cv.dequeueConfiguredReusableCell(using: rowReg, for: ip, item: key)
    }
    let head = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] v, _, ip in
      var c = UIListContentConfiguration.groupedHeader(); c.text = self?.dSec(ip.section)?.head; v.contentConfiguration = c
    }
    let foot = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] v, _, ip in
      var c = UIListContentConfiguration.groupedFooter(); c.text = self?.dSec(ip.section)?.foot; v.contentConfiguration = c
    }
    listDS?.supplementaryViewProvider = { cv, kind, ip in
      kind == UICollectionView.elementKindSectionHeader ? cv.dequeueConfiguredReusableSupplementary(using: head, for: ip) : cv.dequeueConfiguredReusableSupplementary(using: foot, for: ip)
    }
    // (the keyboard: the page scrolls up past it, so where you're writing in the description stays in sight — Haris
    //  2026-11-02)
    // (where the keyboard is: Apple's keyboard guide — a mark held to its top, so the page is laid out again, inside Apple's
    //  own keyboard animation, as the keyboard comes, goes or is dragged down; no keyboard: nothing — Haris 2026-11-08)
    if #available(iOS 17.0, *) { keyboardLayoutGuide.usesBottomSafeArea = false }
    kbMark.isUserInteractionEnabled = false; kbMark.isHidden = true
    kbMark.translatesAutoresizingMaskIntoConstraints = false
    addSubview(kbMark)
    NSLayoutConstraint.activate([kbMark.leadingAnchor.constraint(equalTo: leadingAnchor), kbMark.widthAnchor.constraint(equalToConstant: 1), kbMark.heightAnchor.constraint(equalToConstant: 0), kbMark.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)])
    NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in self?.caretIntoView() }
    commentsHost.isHidden = true
    commentsHost.clipsToBounds = true
    pager.addSubview(commentsHost)
    // (Details · Comments: in the middle of Apple's bar, put there by the page's view controller — TaskVC — with Apple's
    //  glass look, Haris 2026-11-08; no strip of ours under the bar)
    seg.selectedSegmentIndex = 0
    seg.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.setTab(self.seg.selectedSegmentIndex == 1 ? "comments" : "details", tell: true, slide: true)
    }, for: .valueChanged)
    var fc: UIButton.Configuration
    if #available(iOS 26.0, *) { fc = .glass() } else { fc = .gray(); fc.cornerStyle = .capsule }
    fc.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    fc.imagePadding = 7
    fc.attributedTitle = AttributedString("Mark complete", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    fc.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 18)
    fc.baseForegroundColor = .label
    fab.configuration = fc
    fab.isHidden = true
    fab.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .medium).impactOccurred(); self?.onComplete?() }, for: .touchUpInside)
    addSubview(fab)
    spinner.hidesWhenStopped = true
    addSubview(spinner)
    titleView.delegate = self
    titleView.isScrollEnabled = false
    titleView.backgroundColor = .clear
    titleView.font = .systemFont(ofSize: 22, weight: .semibold)   // (less heavy, as ClickUp's — Haris 2026-11-02)
    titleView.textContainerInset = .zero
    titleView.textContainer.lineFragmentPadding = 0
    titleView.returnKeyType = .done
    setUpDesc()
    applyLook()
  }
  required init?(coder: NSCoder) { fatalError() }

  private func applyLook() {
    // (the window already takes the app's own light / dark: everything here follows it)
    backgroundColor = .systemGroupedBackground   // (Details in Apple's boxes: Apple's grouped background — Haris 2026-11-09)
    commentsHost.backgroundColor = .systemGroupedBackground
    // (the description's file chips are pictures: drawn again in the new look)
    if drawnOnce, !editingDesc, let m = model { Main.lookRedraws += 1; built = ""; draw(m) }
  }

  // ---------- layout ----------
  var safeTop: CGFloat { max(safeAreaInsets.top, window?.safeAreaInsets.top ?? 0, 20) }
  // iPhone's own navigation (AppleNav.swift, Haris 2026-11-07): Apple's bar is the top row — its ‹, the client and •••;
  // this page's own row is hidden and Details · Comments sit just under Apple's bar
  var appleRow: CGFloat? { didSet { if appleRow != oldValue { setNeedsLayout() } } }
  var onBarTitle: ((String, UIColor?) -> Void)?
  var onMenuMade: (() -> Void)?
  private var rowBottom: CGFloat { appleRow ?? safeTop + 54 }
  var barBottom: CGFloat { rowBottom }   // (Apple's bar's bottom: nothing of ours under it now)
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    do {
      let H = bounds.height
      if pager.frame != bounds { pager.frame = bounds }
      for (v, x) in [(scroll as UIView, CGFloat(0)), (commentsHost, W)] {
        if v.bounds.size != bounds.size { v.bounds = CGRect(origin: .zero, size: bounds.size) }
        v.center = CGPoint(x: x + W / 2, y: H / 2)
      }
      let size = CGSize(width: trashId == nil ? W * 2 : W, height: H)
      if pager.contentSize != size { pager.contentSize = size }
      if !pager.isDragging && !pager.isDecelerating && !pagerAuto {
        let x = tab == "comments" ? W : 0
        if pager.contentOffset != CGPoint(x: x, y: 0) { pager.contentOffset = CGPoint(x: x, y: 0) }
      }
    }
    let fs = fab.sizeThatFits(CGSize(width: 300, height: 48))
    let bottom = max(safeAreaInsets.bottom, window?.safeAreaInsets.bottom ?? 0)
    fab.frame = CGRect(x: W - 16 - fs.width, y: bounds.height - bottom - 8 - 48, width: fs.width, height: 48)
    spinner.center = CGPoint(x: W / 2, y: barBottom + 60)
    if scroll.contentInset.top != barBottom { scroll.contentInset.top = barBottom; scroll.verticalScrollIndicatorInsets.top = barBottom; scroll.contentOffset.y = -barBottom }
    if scroll.verticalScrollIndicatorInsets.top != barBottom { scroll.verticalScrollIndicatorInsets.top = barBottom }
    scroll.verticalScrollIndicatorInsets.bottom = bottom + 8   // (down to just above the bottom edge)
    // (room under the list for Mark complete, and the keyboard or the description's format bar)
    let inset = max(max(safeAreaInsets.bottom, 20) + (fab.isHidden ? 16 : 72), coverNow() + 16)
    if scroll.contentInset.bottom != inset { scroll.contentInset.bottom = inset }
    fitHosts()
  }

  // ---------- the tabs ----------
  func setTab(_ t: String, tell: Bool, slide: Bool = false) {
    if trashId != nil && t == "comments" { return }
    let was = tab
    if slide && was == t { return }   // (a second swipe for the same change — the edge and the middle at once: nothing more)
    tab = t
    seg.selectedSegmentIndex = t == "comments" ? 1 : 0
    let c = t == "comments"
    if c { endEditing(true) } else { edgeScroll(scroll) }
    do {
      let x = c ? bounds.width : 0
      if pager.isDragging || pager.isDecelerating { }   // (the swipe itself is taking it there)
      else if abs(pager.contentOffset.x - x) > 0.5 && slide && window != nil && bounds.width > 0 {
        // (a tap on Details · Comments, or the app moving it: Apple's own scroll there)
        pagerAuto = true
        scroll.isHidden = false; commentsHost.isHidden = false
        pager.setContentOffset(CGPoint(x: x, y: 0), animated: true)
      } else {
        if abs(pager.contentOffset.x - x) > 0.5 { pager.contentOffset = CGPoint(x: x, y: 0) }
        settlePages()
      }
      if tell { onTab?(t) }
      onPageMove?(pagerFraction)
    }
  }
  // ---------- Details ↔ Comments in iPhone's own paging scroller ----------
  // Apple moves the pages (the swipe, its speed, the bounce, a tap's scroll); Details · Comments follows. On Comments a
  // swipe right — from the edge too — goes to Details; on Details the edge swipe goes back (Haris 2026-11-07)
  let pager = UIScrollView()
  private var pagerAuto = false        // (moving after a tap / by the app)
  private var dragFrom: String?
  var onPeek: ((String) -> Void)?      // a swipe starting on this tab: the comments made ready, the keyboard put away
  var onPageMove: ((CGFloat) -> Void)? // 0 Details … 1 Comments, as it moves: the comment box goes with the comments
  private var pagerFraction: CGFloat { bounds.width > 0 ? max(0, min(1, pager.contentOffset.x / bounds.width)) : (tab == "comments" ? 1 : 0) }
  func pagerWaits(for g: UIGestureRecognizer) { pager.panGestureRecognizer.require(toFail: g) }
  private func updatePager() { pager.isScrollEnabled = trashId == nil && threadFeed == nil && !editingDesc }
  private func commentsList() -> UIScrollView { feed?.scroll ?? scroll }   // (a reply is its own Apple page now: ReplyVC)
  // at rest only the page showing is there (as before: hidden behind, out of taps and VoiceOver)
  private func settlePages() {
    let c = tab == "comments"
    scroll.isHidden = c; commentsHost.isHidden = !c
    fab.alpha = c ? 0 : 1
    seg.selectedSegmentIndex = c ? 1 : 0
    edgeScroll(c ? commentsList() : scroll)
  }
  func scrollViewDidScroll(_ sv: UIScrollView) {
    guard sv === pager else { return }
    let f = pagerFraction
    fab.alpha = 1 - f
    onPageMove?(f)
    if !pagerAuto {
      let i = f > 0.5 ? 1 : 0
      if seg.selectedSegmentIndex != i { seg.selectedSegmentIndex = i; edgeScroll(i == 1 ? commentsList() : scroll) }
    }
  }
  func scrollViewWillBeginDragging(_ sv: UIScrollView) {
    guard sv === pager else { return }
    pagerAuto = false
    dragFrom = tab
    endEditing(true)
    scroll.isHidden = false; commentsHost.isHidden = false
    onPeek?(tab)
    edgeScroll(tab == "comments" ? commentsList() : scroll)
    onPageMove?(pagerFraction)
  }
  func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate d: Bool) { if sv === pager, !d { pagerSettled() } }
  func scrollViewDidEndDecelerating(_ sv: UIScrollView) { if sv === pager { pagerSettled() } }
  func scrollViewDidEndScrollingAnimation(_ sv: UIScrollView) {
    guard sv === pager else { return }
    pagerAuto = false
    settlePages()
  }
  private func pagerSettled() {
    let t = pager.contentOffset.x > bounds.width / 2 ? "comments" : "details"
    let from = dragFrom; dragFrom = nil
    if t != tab { UISelectionFeedbackGenerator().selectionChanged(); setTab(t, tell: true) }
    else {
      settlePages()
      if from == "details" { onTab?("details") }   // (looked at Comments, came back: the comment box put away again)
    }
  }
  func setComments(_ n: Int) { let t = n > 0 ? "Comments \(n)" : "Comments"; if seg.titleForSegment(at: 1) != t { seg.setTitle(t, forSegmentAt: 1) } }   // (only when it changes)

  // ---------- drawing the model ----------
  func loading() { if model == nil { spinner.startAnimating() } }
  // (its files' paths, new ones: the host asks the server which links are off — the hold menu says Turn on link)
  var onFilesShown: (([String]) -> Void)?
  private var askedLinks = Set<String>()
  func draw(_ m: [String: Any]) {
    spinner.stopAnimating()
    model = m
    let paths = (((m["files"] as? [[String: Any]]) ?? []) + ((m["commentFiles"] as? [[String: Any]]) ?? [])).compactMap { $0["file"] as? String }
    let fresh = paths.filter { !askedLinks.contains($0) }
    if !fresh.isEmpty { askedLinks.formUnion(fresh); onFilesShown?(fresh) }
    // (each person's details joined, not one kept whole: what was known already — Home's, which has only initials, colour
    //  and photo — kept the name out, so a Guardian just picked read "Someone" until the server's answer: Haris 2026-11-07.
    //  A photo already fetched stays when the new one has none.)
    if let pp = m["people"] as? [String: [String: Any]] {
      people.merge(pp) { a, b in var x = a.merging(b) { _, n in n }; if b["photo"] == nil, let ph = a["photo"] { x["photo"] = ph }; return x }
    }
    if let c = m["client"] as? [String: Any] {
      onBarTitle?(c["name"] as? String ?? "", TaskPage.rgb(c["rgb"]))
    } else { onBarTitle?((m["sub"] as? Bool) == true ? "Subtask" : "My Tasks", nil) }
    setComments(m["comments"] as? Int ?? 0)
    makeMenu()
    // (unchanged: nothing redrawn — a tick or a title being typed stays as it is)
    let sig = (try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? UUID().uuidString
    if sig == built { return }
    // (while the description is being written nothing is redrawn under the finger: done, it catches up)
    if editingDesc || titleView.isFirstResponder { return }
    built = sig
    // (built and laid out with no animation at all — drawn while something else animates (a sheet going, the app coming
    //  back), every new row was carried along and grew from nothing: the rows sliding. Haris's reading, 2026-11-03.
    //  Then only the page's own change animation, from where things were.)
    // (then Apple's list told what came, went or changed — with its own animation once the page is on screen: applyList)
    UIView.performWithoutAnimation {
      CATransaction.begin(); CATransaction.setDisableActions(true)
      rebuild()
      CATransaction.commit()
    }
  }
  // (only drawn again when someone's picture or name really changed — photos arriving again and again redrew the whole
  //  page each time, the Files row and the lock note jumping by themselves; Haris 2026-11-02)
  func peopleChanged(_ p: [String: [String: Any]]) {
    let was = people
    people.merge(p) { _, b in b }
    let sig = { (d: [String: [String: Any]]) -> String? in JSONSerialization.isValidJSONObject(d) ? (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } : nil }
    if let a = sig(was), a == sig(people) { return }
    built = ""; if let m = model { draw(m) }
  }

  private var menuKey = ""
  private func makeMenu() {
    guard let m = model else { return }
    // (made again only when what's in it changes — only what changed changes, Haris 2026-11-08)
    let key = "\((m["readOnly"] as? Bool) == true)|\((m["canDelete"] as? Bool) == true && !TaskPage.viewOnly)"
    if key == menuKey, cornerMenu != nil { return }
    menuKey = key
    var items: [UIMenuElement] = []
    items.append(UIAction(title: "Copy link", image: UIImage(systemName: "link")) { [weak self] _ in guard let self = self else { return }; self.onEvent?(["ev": "copy", "id": self.taskId]) })
    if (m["readOnly"] as? Bool) != true {   // (attaching stays on the phone — Haris, 2026-11-01)
      items.append(UIMenu(title: "Attach Files", image: UIImage(systemName: "paperclip"), children: [
        UIAction(title: "Camera", image: UIImage(systemName: "camera")) { [weak self] _ in guard let self = self else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); self.onAttachFrom?("camera") },
        UIAction(title: "Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in guard let self = self else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); self.onAttachFrom?("photos") },
        UIAction(title: "Files", image: UIImage(systemName: "folder")) { [weak self] _ in guard let self = self else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); self.onAttachFrom?("files") },
      ]))
    }
    if (m["canDelete"] as? Bool) == true && !TaskPage.viewOnly {
      items.append(UIMenu(options: .displayInline, children: [UIAction(title: "Trash task", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete() }]))
    }
    cornerMenu = UIMenu(children: items)
    onMenuMade?()
  }
  private var ownFileIds = Set<String>()
  private func confirmRemove(_ f: [String: Any]) {
    guard let fid = f["id"] as? String else { return }
    let a = UIAlertController(title: "Move “\(f["name"] as? String ?? "this file")” to the Trash?", message: "It can be restored within 30 days.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Trash", style: .destructive) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "removeFile", "id": self.taskId, "value": fid]) })
    present(a)
  }
  private func confirmDelete() {
    let a = UIAlertController(title: "Move this task to the Trash?", message: "It can be restored within 30 days.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Trash", style: .destructive) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "delete", "id": self.taskId]) })
    present(a)
  }
  func present(_ vc: UIViewController) {
    var top = window?.rootViewController
    while let p = top?.presentedViewController { top = p }
    top?.present(vc, animated: true)
  }

  /* View only for everyone, the basics (Haris, 2026-11-01: "no one uses an iOS app to do the full process" — the
     Comments stay complete): title, notes, status / CD status, assignees with their ticks, dates, priority, client,
     description, checklist, subtasks, files (open to look at). Nothing on Details is changed from the phone. */
  static let viewOnly = true
  // the text: 16, as ClickUp's (rows, values, the description, section headings) — Haris 2026-11-02, side by side
  static let T: CGFloat = 16
  static func basic(_ m0: [String: Any]) -> [String: Any] {
    guard viewOnly else { return m0 }
    var m = m0
    for k in ["parts", "tags", "channels", "clientApproval", "activity", "complete", "review2", "kids"] { m[k] = nil }   // (Guardian and Task Update show — Haris; and Needs CD review, switched by whoever's role allows it — Haris 2026-11-06)
    // (Haris, 2026-11-02: these can be changed from the phone again, each by whoever's role allows it — the server's
    //  own can… say who: the title, Status, Task Update, Assignees, Priority, Client and the description; the rest stays
    //  view only)
    // (ticking the checklist and subtasks: by permission again, the server's own canCheck / canTick — Haris 2026-11-07)
    for k in ["canTags", "canRemoveTag", "canChannels", "canAddSub", "canAddCheck", "canDelete"] { m[k] = false }   // (Guardian and Finance: by role — Haris 2026-11-02)
    if var st = m["status"] as? [String: Any] { st["next"] = nil; m["status"] = st }
    if var c = m["completed"] as? [String: Any] { c["canFrom"] = false; c["canReopen"] = false; m["completed"] = c }
    if var l = m["lock"] as? [String: Any] { l["from"] = false; m["lock"] = l }
    return m
  }
  private func rebuild() {
    guard let m = model.map({ TaskPage.basic($0) }) else { return }
    DescEditor.dark = !light   // (the description's file chips drawn in the page's look)
    // (on screen already: what changes comes in, goes out and moves smoothly — Haris 2026-11-02)
    // (not while it's still coming in: its first drawings — from what was kept, then the copy — are put in as they are;
    //  animating them slid the rows down as the page opened, Haris 2026-11-02)
    listLive = window != nil && drawnOnce && !isHidden && Date().timeIntervalSince(openedAt) > 0.8
    defer { drawnOnce = true }
    let typing = titleView.isFirstResponder
    // Details, fully Apple (Haris 2026-11-09, mock-up "Task page Details — fully Apple"): Apple's boxes with Apple's
    // headers, each row Apple's own cell; the sections as they are now — only the ones whose drawing changed are set again
    var secs: [DSec] = [], items: [String: DItem] = [:]
    func add(_ key: String, head: String? = nil, _ list: [DItem]) {
      guard !list.isEmpty else { return }
      for it in list { items[it.key] = it }
      secs.append(DSec(key: key, head: head, foot: nil, plain: list.allSatisfy { $0.plain }, items: list.map { $0.key }))
    }
    // ---- the head, ours on the page (no box): the client's dot and name, subtask of…, the title, the notes ----
    var head: [DItem] = []
    // (the client's dot and name, at the top of Details — the middle of Apple's bar has Details · Comments: Haris
    //  2026-11-08)
    if let c = m["client"] as? [String: Any], let cn = c["name"] as? String, !cn.isEmpty {
      let d = UIView(); d.backgroundColor = TaskPage.rgb(c["rgb"]); d.layer.cornerRadius = 4
      d.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([d.widthAnchor.constraint(equalToConstant: 8), d.heightAnchor.constraint(equalToConstant: 8)])
      let l = label(cn, size: 15, color: .secondaryLabel, weight: .medium)
      let line = UIStackView(arrangedSubviews: [d, l, UIView()]); line.axis = .horizontal; line.alignment = .center; line.spacing = 7
      head.append(hosted("client", line, pad: UIEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)))
    }
    if let p = m["parent"] as? [String: Any], let pid = p["id"] as? String {
      head.append(hosted("parent", linkLine("Subtask of " + (p["title"] as? String ?? ""), sym: "arrow.turn.left.up") { [weak self] in self?.onOpen?(pid) }, pad: UIEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)))
    }
    if !typing { titleView.text = m["title"] as? String ?? "" }
    titleView.isEditable = (m["canTitle"] as? Bool) == true
    titleView.textColor = (m["done"] as? Bool) == true ? .secondaryLabel : .label
    head.append(hosted("title", titleView, pad: UIEdgeInsets(top: 0, left: 0, bottom: 4, right: 0), sig: "\(titleView.text ?? "")|\(titleView.isEditable)|\((m["done"] as? Bool) == true)"))
    if let c = m["completed"] as? [String: Any] {
      var t = "Completed" + ((c["label"] as? String).map { $0.isEmpty ? "" : " on " + $0 } ?? "") + " — read only."
      if let left = c["left"] as? Int { t += " Goes to the Trash in \(left) day\(left == 1 ? "" : "s")." }
      var btns: [(String, () -> Void)] = []
      if (c["canFrom"] as? Bool) == true { btns.append(("New task from this", { [weak self] in guard let self = self else { return }; self.onEvent?(["ev": "from", "id": self.taskId]) })) }
      if (c["canReopen"] as? Bool) == true { btns.append(("Reopen", { [weak self] in guard let self = self else { return }; self.onAct?(["act": "reopen", "id": self.taskId]) })) }
      head.append(hosted("done", note(sym: "checkmark.circle.fill", tint: .systemGreen, text: t, buttons: btns), pad: UIEdgeInsets(top: 8, left: 0, bottom: 2, right: 0)))
    }
    if let tn = m["trashNote"] as? String { head.append(hosted("trash", note(sym: "trash", tint: .systemRed, text: tn, buttons: []), pad: UIEdgeInsets(top: 8, left: 0, bottom: 2, right: 0))) }
    if let l = m["lock"] as? [String: Any] {
      var btns: [(String, () -> Void)] = []
      if (l["from"] as? Bool) == true { btns.append(("New task from this", { [weak self] in guard let self = self else { return }; self.onEvent?(["ev": "from", "id": self.taskId]) })) }
      head.append(hosted("lock", note(sym: "lock.fill", tint: .systemOrange, text: l["text"] as? String ?? "", buttons: btns), pad: UIEdgeInsets(top: 8, left: 0, bottom: 2, right: 0)))
    }
    if let b = m["basedOn"] as? [String: Any], let bid = b["id"] as? String {
      head.append(hosted("based", linkLine("New task from " + (b["title"] as? String ?? ""), sym: "link") { [weak self] in self?.onOpen?(bid) }, pad: UIEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)))
    }
    add("head", head)
    // ---- three boxes, in today's order (Haris 2026-11-09): Status · Task Update · CD status / Assignees · Dates ·
    //      Priority / Guardian · Finance · Client ----
    var state: [DItem] = []
    if let s = m["status"] as? [String: Any] { state.append(statusRow(s)) }
    let canUp = (m["canFields"] as? Bool) == true
    if (m["sub"] as? Bool) != true, m["update"] is [String: Any] || canUp { state.append(updateRow(m["update"] as? [String: Any], all: (m["updates"] as? [String]) ?? [], can: canUp)) }
    if let cd = m["cd"] as? [String: Any] {
      let chip = pill((cd["check"] as? Bool) == true ? "✓ " + (cd["label"] as? String ?? "") : cd["label"] as? String ?? "", fg: .white, bg: TaskPage.rgb(cd["rgb"]))
      state.append(row("cd", sym: "checkmark.shield", key: "CD status", value: chip))
    }
    add("state", state)
    var who3: [DItem] = []
    let asg = (m["assignees"] as? [[String: Any]]) ?? []
    let canAsg = (m["canAssign"] as? Bool) == true
    who3.append(row("assignees", sym: "person", key: "Assignees", text: asg.isEmpty ? (canAsg ? "Add" : "Nobody yet") : nil, value: asg.isEmpty ? nil : avatars(asg), chevron: canAsg, tap: canAsg ? { [weak self] in self?.pickPeople() } : nil))
    if let d = m["dates"] as? [String: Any] { who3.append(datesRow(d)) }
    if let pr = m["prio"] as? [[String: Any]] { who3.append(contentsOf: prioRows(pr, can: (m["canPrio"] as? Bool) == true)) }
    add("people", who3)
    var owner: [DItem] = []
    // Guardian and Finance, above Client (Haris 2026-11-02): each changed by whoever's role allows it
    let canGd = (m["canGuardian"] as? Bool) == true
    if let gd = m["guardian"] as? String {
      let who = gd == (m["me"] as? String) ? "You" : ((people[gd]?["name"] as? String) ?? name(gd))
      owner.append(row("guardian", sym: "star", key: "Guardian", text: who, chevron: canGd, tap: canGd ? { [weak self] in self?.pickGuardian() } : nil))
    } else if canGd { owner.append(row("guardian", sym: "star", key: "Guardian", text: "None", chevron: true, tap: { [weak self] in self?.pickGuardian() })) }
    if let fin = m["finance"] as? [String: Any] {
      let cur = fin["v"] as? String ?? ""
      let canFin = (m["canFinance"] as? Bool) == true
      owner.append(row("finance", sym: "dollarsign.circle", key: "Finance", text: cur.isEmpty ? (canFin ? "None" : "–") : nil, value: cur.isEmpty ? nil : pill(cur, fg: TaskPage.rgb(fin["rgb"]), bg: TaskPage.rgb(fin["rgb"]).withAlphaComponent(0.16)), chevron: canFin, tap: canFin ? { [weak self] in self?.pickFinance(cur) } : nil))
    }
    if (m["sub"] as? Bool) != true {
      let cl = m["client"] as? [String: Any]
      let v = UIStackView(); v.axis = .horizontal; v.spacing = 6; v.alignment = .center
      if let cl = cl { let d = UIView(); d.backgroundColor = TaskPage.rgb(cl["rgb"]); d.layer.cornerRadius = 4; d.widthAnchor.constraint(equalToConstant: 8).isActive = true; d.heightAnchor.constraint(equalToConstant: 8).isActive = true; v.addArrangedSubview(d) }
      v.addArrangedSubview(label(cl?["name"] as? String ?? "No client", size: 17, color: .secondaryLabel))
      if m["lock"] is [String: Any] { v.addArrangedSubview(symbol("lock.fill", 12, .secondaryLabel)) }
      let canCl = (m["canClient"] as? Bool) == true
      owner.append(row("client", sym: "square.grid.2x2", key: "Client", value: v, chevron: canCl, tap: canCl ? { [weak self] in self?.pickClient() } : nil))
    }
    add("owner", owner)
    // ---- Review ----
    if let rv = m["review"] as? [String: Any] {
      let sw = UISwitch(); sw.isOn = (rv["on"] as? Bool) == true; sw.isEnabled = (rv["canSet"] as? Bool) == true
      let noCD = (rv["noCD"] as? Bool) == true
      sw.addAction(UIAction { [weak self, weak sw] _ in
        guard let self = self, let sw = sw else { return }
        // (no CD set: it can't be turned on — it springs back, a double tap of haptics and a short message: Haris 2026-11-06)
        if noCD && sw.isOn {
          sw.setOn(false, animated: true)
          let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { g.impactOccurred() }
          self.toast("No CD set")
          return
        }
        self.tintCDName(sw.isOn)
        self.onAct?(["act": "needsCD", "id": self.taskId, "value": sw.isOn])
      }, for: .valueChanged)
      // (the CD's name — or the Acting CD's — as the cell's second line: blue while the switch is on, grey when it's off,
      //  turning as it's flicked — Haris 2026-11-06 / 11-08)
      let who = rv["who"] as? String ?? ""
      add("review", head: "REVIEW", [row("needsCD", sym: "checkmark.shield", key: "Needs CD review", sub: who.isEmpty ? nil : who, subColor: sw.isOn ? .systemBlue : .secondaryLabel, value: sw, extra: "\(noCD)")])
    }
    // ---- Description: Apple's box with its header; the words in it ours (written right in it — DescEditor.swift) ----
    let desc = m["desc"] as? String ?? ""
    let canDesc = (m["canDesc"] as? Bool) == true
    // (no description: "Add description…" for whoever may write one — tapped, written right there — and "No description"
    //  in grey for everyone else; a long one shows its first lines with Show More, once — Haris 2026-11-02)
    let noDesc = desc.isEmpty && ((m["descFiles"] as? [[String: Any]]) ?? []).isEmpty
    let rich: NSAttributedString = {
      let r = DescEditor.attributed((m["descRuns"] as? [[String: Any]]) ?? [], done: (m["done"] as? Bool) == true, size: TaskPage.T, creator: ((model?["creator"] as? [String: Any])?["id"] as? String))
      return r.length > 0 || !noDesc && desc.isEmpty ? r : NSAttributedString(string: desc, attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.label])
    }()
    var descSig: String?
    if canDesc || editingDesc {
      let tv = descView
      if !editingDesc { tv.attributedText = desc.isEmpty ? NSAttributedString(string: "Add description…", attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.tertiaryLabel]) : rich }
      descEmpty = desc.isEmpty
      tv.isEditable = true
      descBox.hold(tv); descSig = "write|" + tv.attributedText.string
    } else if noDesc {
      descRead.attributedText = NSAttributedString(string: "No description", attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.tertiaryLabel])
      descBox.hold(descRead); descSig = "none"
    } else if !rich.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      descRead.attributedText = rich
      descBox.hold(descRead); descSig = "read|" + rich.string
    }
    if let s = descSig {
      descStripAfter(m)
      add("desc", head: "DESCRIPTION", [hosted("desc", descBox, pad: UIEdgeInsets(top: 2, left: -1, bottom: 0, right: -1), sig: s)])   // (no box: the words on the page under the header — Haris 2026-11-09)
    }
    // ---- Subtasks ----
    let subs = (m["subtasks"] as? [[String: Any]]) ?? []
    let canAddSub = (m["canAddSub"] as? Bool) == true
    if !subs.isEmpty || canAddSub {
      var rows = subs.map { subRow($0) }
      if canAddSub { rows.append(addRow("addSub", "Add Subtask") { [weak self] in self?.askText("Add subtask", placeholder: "Subtask name") { v in guard let self = self else { return }; self.onAct?(["act": "addSub", "id": self.taskId, "value": v]) } }) }
      add("subs", head: subs.isEmpty ? "SUBTASKS" : "SUBTASKS · \(subs.filter { ($0["done"] as? Bool) == true }.count)/\(subs.count)", rows)
    }
    // ---- Checklist ----
    let cl = (m["checklist"] as? [[String: Any]]) ?? []
    let canAddCheck = (m["canAddCheck"] as? Bool) == true
    if !cl.isEmpty || canAddCheck {
      var rows = cl.map { checkRow($0, can: (m["canCheck"] as? Bool) == true) }
      if canAddCheck { rows.append(addRow("addCheck", "Add Item") { [weak self] in self?.askText("Add checklist item", placeholder: "Item") { v in guard let self = self else { return }; self.onAct?(["act": "addCheck", "id": self.taskId, "value": v]) } }) }
      add("checks", head: cl.isEmpty ? "CHECKLIST" : "CHECKLIST · \(cl.filter { ($0["done"] as? Bool) == true }.count)/\(cl.count)", rows)
    }
    // ---- Files ---- the task's and the comments' together, one row of cards that scrolls sideways (Haris, 2026-11-02),
    //      in Apple's box; Attach Files as Apple's cell under them
    //      Yours uploading: in the row at once (after the task's own), then the real one in its place, no jump.
    let own = (m["files"] as? [[String: Any]]) ?? [], fromComments = (m["commentFiles"] as? [[String: Any]]) ?? []
    var settle = Set<String>()
    uploads.removeAll { u in
      // (as soon as the real one is in — also before the upload's own answer: the live copy often brings it first, and
      //  both showed for a moment, Haris 2026-11-06)
      guard let r = own.first(where: { f in let id = f["id"] as? String ?? ""
        return (f["name"] as? String) == (u["name"] as? String) && !knownFiles.contains(id) && !settle.contains(id) }), let rid = r["id"] as? String else { return false }
      settle.insert(rid); CommentCell.handOver(from: [u], to: [r])
      return true
    }
    let files = own + fromComments
    let shown = own + uploads + fromComments
    let canAttach = (m["readOnly"] as? Bool) != true
    if !files.isEmpty || canAttach || !uploads.isEmpty {
      var fr: [DItem] = []
      let real = shown.filter { ($0["pending"] as? Bool) != true }
      let at: (Int) -> Int = { i in real.firstIndex { ($0["id"] as? String) == (shown[i]["id"] as? String) } ?? 0 }
      ownFileIds = canAttach ? Set(own.compactMap { $0["id"] as? String }) : []
      filesStrip.set(shown, settle: settle, open: { [weak self] i in self?.onOpenFiles?(real, at(i)) }, menu: { [weak self] i in self?.fileMenu(real, at(i)) })
      // (the strip keeps itself up to date; its cell is set again only when it comes or goes)
      if !shown.isEmpty { fr.append(hosted("files", filesStrip, pad: UIEdgeInsets(top: 12, left: -1, bottom: 12, right: 0), plain: false, sig: "strip")) }
      if canAttach { fr.append(addRow("attach", "Attach Files", sym: "paperclip") { [weak self] in self?.attachSheet() }) }
      add("files", head: files.isEmpty ? "FILES" : "FILES · \(files.count)", fr)
    }
    // ---- who made the task: Apple's grey footer at the very end, small and out of the way (Haris 2026-11-09: "Bottom") ----
    if let cr = m["creator"] as? [String: Any], let cid = cr["id"] as? String, !secs.isEmpty {
      let who = cid == (m["me"] as? String) ? "you" : ((people[cid]?["name"] as? String) ?? name(cid))
      let when = cr["when"] as? String ?? ""
      secs[secs.count - 1].foot = "Created by " + who + (when.isEmpty ? "" : " · " + when)
    }
    // Mark complete: only when this person may complete it
    if let c = m["complete"] as? [String: Any], (c["show"] as? Bool) == true { fab.isHidden = false } else { fab.isHidden = true }
    applyList(secs, items)
  }
  // Turn off link, or Turn on link (blue, open lock) when it's off
  private func linkAction(_ f: [String: Any]) -> UIAction {
    let off = Main.linksOff.contains(f["file"] as? String ?? "")
    let img = off ? UIImage(systemName: "lock.open")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal) : UIImage(systemName: "lock")
    return UIAction(title: off ? "Turn on link" : "Turn off link", image: img, attributes: off ? [] : .destructive) { [weak self] _ in self?.onFileAction?(f, "linkOff") }   // (Turn off link: red)
  }
  private func fileMenu(_ files: [[String: Any]], _ i: Int) -> UIMenu? {
    guard i < files.count else { return nil }
    let f = files[i]
    var items: [UIMenuElement] = [
      UIAction(title: "Open", image: UIImage(systemName: "eye")) { [weak self] _ in self?.onOpenFiles?(files, i) },
      UIAction(title: "Copy link", image: UIImage(systemName: "link")) { [weak self] _ in self?.onFileAction?(f, "copy") },
      UIAction(title: "Download", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in self?.onFileAction?(f, "download") },
    ]
    if Main.isAdmin { items.append(linkAction(f)) }   // (Admins turn links off and on)
    // (the task's own files: Remove — to the Trash, with Undo; a comment's files go with their comment — Haris 2026-11-06)
    if let fid = f["id"] as? String, ownFileIds.contains(fid) {
      items.append(UIMenu(options: .displayInline, children: [UIAction(title: "Trash", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmRemove(f) }]))
    }
    return UIMenu(title: f["name"] as? String ?? "", children: items)
  }
  // Details in Apple's list: the sections and their items as they are now; Apple told only what changed — new items
  // and gone ones (Apple's own animation once the page is on screen), and the items whose drawing changed set again
  private var listLive = false
  private func dSec(_ i: Int) -> DSec? { i >= 0 && i < dSecs.count ? dSecs[i] : nil }
  private func applyList(_ secs: [DSec], _ items: [String: DItem]) {
    var changed: [String] = []
    for (k, it) in items {
      guard let old = dItems[k] else { continue }
      // (a piece of ours showing just the same: the one already in its cell stays)
      if old.sig == it.sig { if it.host != nil, let h = old.host { it.host = h } } else { changed.append(k) }
    }
    let shape = { (s: [DSec]) in s.map { "\($0.key)|\($0.head != nil)|\($0.foot != nil)|\($0.plain)" } }
    let reshaped = shape(secs) != shape(dSecs)
    dItems = items; dSecs = secs
    guard let ds = listDS else { return }
    if reshaped { scroll.collectionViewLayout.invalidateLayout() }   // (a header or footer come or gone)
    var snap = NSDiffableDataSourceSnapshot<String, String>()
    for s in secs { snap.appendSections([s.key]); snap.appendItems(s.items, toSection: s.key) }
    let had = Set(ds.snapshot().itemIdentifiers)
    let again = changed.filter { had.contains($0) }
    if !again.isEmpty { snap.reconfigureItems(again) }
    ds.apply(snap, animatingDifferences: listLive && window != nil)
    refreshSupp()
  }
  // a header's or the footer's words changed (Subtasks · 1/3 → 2/3): set again where they show
  private func refreshSupp() {
    for kind in [UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter] {
      for ip in scroll.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
        guard let v = scroll.supplementaryView(forElementKind: kind, at: ip) as? UICollectionViewListCell, var c = v.contentConfiguration as? UIListContentConfiguration else { continue }
        let want = kind == UICollectionView.elementKindSectionHeader ? dSec(ip.section)?.head : dSec(ip.section)?.foot
        if c.text != want { c.text = want; v.contentConfiguration = c }
      }
    }
  }
  // Apple's inset-grouped list: Apple's boxes, headers and footer; the head (the title and its line) without a box
  private func makeListLayout() -> UICollectionViewLayout {
    UICollectionViewCompositionalLayout { [weak self] i, env in
      let s = self?.dSec(i)
      var c = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
      c.backgroundColor = .clear
      c.headerMode = s?.head != nil ? .supplementary : .none
      c.footerMode = s?.foot != nil ? .supplementary : .none
      c.showsSeparators = !(s?.plain ?? false)
      let sec = NSCollectionLayoutSection.list(using: c, layoutEnvironment: env)
      // (the gaps between the boxes half of Apple's own — set on Apple's section, Haris 2026-11-09: "Half")
      sec.contentInsets.top = (sec.contentInsets.top / 2).rounded()
      sec.contentInsets.bottom = (sec.contentInsets.bottom / 2).rounded()
      return sec
    }
  }
  // a piece of ours that changed height in its Apple cell (the title being typed, the description opened or written):
  // Apple's own self-sizing told, and the list follows
  private func fitHosts() {
    for case let c as HostCell in scroll.visibleCells where c.needsFit { c.invalidateIntrinsicContentSize() }
  }
  // the self-test: Details as Apple's list — its headers, Apple's cells, the creator's footer
  func detailsGeo() -> [String: Any] {
    ["sections": dSecs.count, "heads": dSecs.compactMap { $0.head }, "appleRows": dItems.values.filter { $0.host == nil }.count,
     "hosted": dItems.values.filter { $0.host != nil }.count, "foot": dSecs.last?.foot ?? "", "hasCreator": model?["creator"] is [String: Any],
     "cells": scroll.visibleCells.count, "listCells": scroll.visibleCells.filter { !($0 is HostCell) }.count]
  }
  func collectionView(_ cv: UICollectionView, shouldHighlightItemAt ip: IndexPath) -> Bool {
    guard cv === scroll, !editingDesc, let k = listDS?.itemIdentifier(for: ip) else { return false }
    return dItems[k]?.tap != nil
  }
  func collectionView(_ cv: UICollectionView, shouldSelectItemAt ip: IndexPath) -> Bool {
    guard cv === scroll, !editingDesc, let k = listDS?.itemIdentifier(for: ip) else { return false }
    return dItems[k]?.tap != nil
  }
  func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
    guard cv === scroll, let k = listDS?.itemIdentifier(for: ip) else { return }
    cv.deselectItem(at: ip, animated: true)
    dItems[k]?.tap?()
  }
  // how much of the page the keyboard covers (Apple's keyboard guide)
  private let kbMark = UIView()
  var kbCover: CGFloat {
    guard kbMark.frame.minY > 0 else { return 0 }
    var c = bounds.height - kbMark.frame.minY
    if #unavailable(iOS 17.0) { c -= safeAreaInsets.bottom }   // (before iOS 17 the guide also holds the bottom safe area)
    return max(0, c)
  }
  // the description's cursor in sight, above the keyboard and its format bar
  func caretIntoView() {
    guard descView.isFirstResponder, let r = descView.selectedTextRange else { return }
    layoutIfNeeded()
    // (above the format bar's own top — on iOS 26 the keyboard's height doesn't hold it, and the line tapped went behind
    //  it: Haris 2026-11-06)
    let limit = bounds.height - coverNow()
    let caret = descView.convert(descView.caretRect(for: r.end), to: self)
    let gap: CGFloat = 28
    if caret.maxY + gap > limit {
      let end = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
      scroll.setContentOffset(CGPoint(x: 0, y: min(end, scroll.contentOffset.y + caret.maxY + gap - limit)), animated: true)
    } else {
      let c = descView.convert(descView.caretRect(for: r.end), to: scroll).insetBy(dx: 0, dy: -gap)
      scroll.scrollRectToVisible(c, animated: true)
    }
  }
  // what covers the page's bottom now: the keyboard, or the description's format bar where it reaches higher
  private func coverNow() -> CGFloat {
    var c = kbCover
    if kbCover > 0, descView.isFirstResponder, let bar = descView.inputAccessoryView, bar.window != nil, !bar.isHidden {
      c = max(c, bounds.height - bar.convert(bar.bounds, to: self).minY)
    }
    return c
  }

  // ---------- row pieces ----------
  private func label(_ t: String, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular) -> UILabel {
    let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; return l
  }
  private func greyText(_ t: String) -> UILabel { label(t, size: TaskPage.T, color: .secondaryLabel) }
  private func symbol(_ s: String, _ size: CGFloat, _ c: UIColor, weight: UIImage.SymbolWeight = .regular) -> UIImageView {
    let i = UIImageView(image: UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight)))
    i.tintColor = c; i.contentMode = .center; i.setContentHuggingPriority(.required, for: .horizontal); return i
  }
  // ---------- Details' rows: Apple's own list cells, set by Apple's configuration ----------
  // icon · name (· a small line under it) · value · › — the value Apple's text, or ours where Apple has no part (a chip,
  // the faces, the dates' two buttons, a switch), shown by Apple's cell as its accessory
  private func row(_ id: String, sym: String, key: String, keyText: NSAttributedString? = nil, sub: String? = nil, subColor: UIColor = .secondaryLabel, text: String? = nil, value: UIView? = nil, chevron: Bool = false, extra: String = "", tap: (() -> Void)? = nil) -> DItem {
    var c: UIListContentConfiguration = sub != nil ? .subtitleCell() : (text != nil && value == nil ? .valueCell() : .cell())
    c.image = UIImage(systemName: sym)
    c.imageProperties.tintColor = .secondaryLabel
    if let k = keyText { c.attributedText = k } else { c.text = key }
    var v = value
    if let s = sub {
      c.secondaryText = s; c.secondaryTextProperties.color = subColor; c.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
      if v == nil, let t = text { v = label(t, size: 17, color: .secondaryLabel) }   // (a line under the name and a value: the value on the right)
    } else if v == nil, let t = text { c.secondaryText = t }
    let it = DItem(id)
    it.content = c
    if let v = v { it.accessories.append(.customView(configuration: .init(customView: v, placement: .trailing(), reservedLayoutWidth: .actual))) }
    if chevron { it.accessories.append(.disclosureIndicator()) }
    it.tap = tap
    it.sig = [sym, key, keyText?.string ?? "", sub ?? "", TaskPage.cs(subColor, traitCollection), text ?? "", "\(chevron)", "\(tap != nil)", extra, v.map { TaskPage.sig($0) } ?? ""].joined(separator: "|")
    return it
  }
  // a row in the tint, as Apple's own "Add…" rows: Add Subtask, Add Item, Attach Files
  private func addRow(_ id: String, _ t: String, sym: String = "plus", tap: @escaping () -> Void) -> DItem {
    var c = UIListContentConfiguration.cell()
    c.text = t; c.textProperties.color = .tintColor
    c.image = UIImage(systemName: sym); c.imageProperties.tintColor = .tintColor
    let it = DItem(id); it.content = c; it.tap = tap; it.sig = sym + "|" + t
    return it
  }
  // a piece of ours, held in Apple's cell (pad: top / bottom as given; left / right -1 = Apple's cell margin)
  private func hosted(_ id: String, _ v: UIView, pad: UIEdgeInsets, plain: Bool = true, sig: String? = nil) -> DItem {
    let it = DItem(id); it.host = v; it.pad = pad; it.plain = plain
    it.sig = sig ?? TaskPage.sig(v)
    return it
  }
  private func pill(_ t: String, fg: UIColor, bg: UIColor) -> UIView {
    let l = PaddedLabel(); l.text = t; l.font = .systemFont(ofSize: 14, weight: .semibold); l.textColor = fg; l.backgroundColor = bg
    l.layer.cornerRadius = 9; l.layer.cornerCurve = .continuous; l.clipsToBounds = true; l.insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    return l
  }
  func name(_ id: String) -> String { (people[id]?["first"] as? String) ?? "Someone" }
  private func avatar(_ id: String, _ side: CGFloat, ring: Bool = false, done: Bool = false) -> UIView {
    let p = people[id] ?? [:]
    let v = UIView(); v.layer.cornerRadius = side / 2; v.clipsToBounds = true
    v.backgroundColor = TaskPage.rgb(p["color"])
    v.translatesAutoresizingMaskIntoConstraints = false
    v.widthAnchor.constraint(equalToConstant: side).isActive = true; v.heightAnchor.constraint(equalToConstant: side).isActive = true
    if let s = p["photo"] as? String, s.hasPrefix("data:"), let d = Data(base64Encoded: String(s.split(separator: ",").last ?? "")), let img = UIImage(data: d) {
      let i = UIImageView(image: img); i.contentMode = .scaleAspectFill; i.frame = CGRect(x: 0, y: 0, width: side, height: side); v.addSubview(i)
    } else {
      let l = UILabel(); l.text = p["initials"] as? String ?? "?"; l.font = .systemFont(ofSize: side * 0.4, weight: .semibold); l.textColor = .white; l.textAlignment = .center
      l.frame = CGRect(x: 0, y: 0, width: side, height: side); v.addSubview(l)
    }
    // (their part done: a green ring, as on Home — Haris 2026-11-09)
    if ring { v.layer.borderWidth = 2; let rc: UIColor = done ? .systemGreen : .secondarySystemGroupedBackground; v.followLook("ring") { [weak v] tc in v?.layer.setBorder(rc, tc) } }
    return v
  }
  // (someone added: their picture springs in; someone taken off: it shrinks away and the others close up — Haris,
  //  2026-11-02)
  private var shownAvatars: [String]?
  private func avatars(_ list: [[String: Any]]) -> UIView {
    let s = UIStackView(); s.spacing = -6; s.alignment = .center
    let ids = list.prefix(5).compactMap { $0["id"] as? String }
    let before = shownAvatars; shownAvatars = ids
    let live = window != nil && before != nil
    var rows = Array(list.prefix(5))
    var going: [String] = []
    if live, let b = before { for (k, id) in b.enumerated() where !ids.contains(id) { going.append(id); rows.insert(["id": id], at: min(k, rows.count)) } }
    for a in rows {
      guard let id = a["id"] as? String else { continue }
      let v = avatar(id, 30, ring: true, done: (a["done"] as? Bool) == true)
      let isNew = live && !(before ?? []).contains(id), isGoing = going.contains(id)
      if isNew || isGoing {
        let cell = v
        // (coming in the way one goes out, in reverse and as long: room made first, then it grows in — Haris 2026-11-02)
        if isNew { cell.alpha = 0; cell.transform = CGAffineTransform(scaleX: 0.4, y: 0.4); cell.isHidden = true }
        DispatchQueue.main.async {
          if isNew {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: { cell.isHidden = false; s.layoutIfNeeded() }) { _ in
              UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { cell.alpha = 1; cell.transform = .identity }
            }
          }
          else { UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn, .allowUserInteraction], animations: { cell.alpha = 0; cell.transform = CGAffineTransform(scaleX: 0.4, y: 0.4) }) { _ in UIView.animate(withDuration: 0.25) { cell.isHidden = true; s.layoutIfNeeded() } } }
        }
      }
      s.addArrangedSubview(v)
    }
    if list.count > 5 { s.setCustomSpacing(6, after: s.arrangedSubviews.last ?? s); s.addArrangedSubview(greyText("+\(list.count - 5)")) }
    return s
  }
  private func note(sym: String, tint: UIColor, text: String, buttons: [(String, () -> Void)]) -> UIView {
    let box = UIView(); box.backgroundColor = tint.withAlphaComponent(light ? 0.12 : 0.18); box.layer.cornerRadius = 18; box.layer.cornerCurve = .continuous
    box.layer.name = "k:note:" + sym
    let ic = symbol(sym, 15, tint, weight: .semibold)
    let l = label(text, size: 15, color: .label); l.numberOfLines = 0
    let v = UIStackView(arrangedSubviews: [l]); v.axis = .vertical; v.spacing = 10; v.alignment = .leading
    if !buttons.isEmpty {
      let bs = UIStackView(); bs.spacing = 8
      for (t, run) in buttons {
        var c: UIButton.Configuration
        if #available(iOS 26.0, *) { c = .glass() } else { c = .gray(); c.cornerStyle = .capsule }
        c.attributedTitle = AttributedString(t, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]))
        c.baseForegroundColor = .label
        c.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
        let b = UIButton(configuration: c); b.addAction(UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); run() }, for: .touchUpInside)
        bs.addArrangedSubview(b)
      }
      v.addArrangedSubview(bs)
    }
    let h = UIStackView(arrangedSubviews: [ic, v]); h.spacing = 10; h.alignment = .top
    h.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14), h.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14), h.topAnchor.constraint(equalTo: box.topAnchor, constant: 12), h.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)])
    return box
  }
  private func linkLine(_ t: String, sym: String, tap: @escaping () -> Void) -> UIView {
    let r = TaskRow()
    let s = UIStackView(arrangedSubviews: [symbol(sym, 13, .systemBlue), label(t, size: 15, color: .systemBlue, weight: .medium)])
    s.spacing = 6; s.alignment = .center
    (s.arrangedSubviews[1] as? UILabel)?.lineBreakMode = .byTruncatingTail
    s.translatesAutoresizingMaskIntoConstraints = false; r.addSubview(s)
    NSLayoutConstraint.activate([s.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 2), s.trailingAnchor.constraint(lessThanOrEqualTo: r.trailingAnchor), s.topAnchor.constraint(equalTo: r.topAnchor, constant: 2), s.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -2)])
    r.onTap = tap; r.pressBg = false
    r.tag = 7
    return r
  }

  // ---------- the rows that change things ----------
  // the sheets are iPhone's own, the same as the phone website's (Haris, 2026-11-02): a tap on the row opens it
  private func statusRow(_ s: [String: Any]) -> DItem {
    let can = (s["canSet"] as? Bool) == true
    let v = pill(s["name"] as? String ?? "", fg: .white, bg: TaskPage.rgb(s["rgb"]))
    let why = s["why"] as? String ?? ""
    return row("status", sym: "circle.lefthalf.filled", key: "Status", sub: why.isEmpty ? nil : why, value: v, chevron: can, tap: can ? { [weak self] in self?.pickStatus(s) } : nil)
  }
  private func pickStatus(_ s: [String: Any]) {
    let opts = (s["options"] as? [[String: Any]]) ?? []
    let rows: [[String: Any]] = opts.enumerated().map { i, o in
      let locked = (o["locked"] as? Bool) == true
      return ["i": locked ? -1 : i, "label": o["name"] as? String ?? "", "dot": o["rgb"] ?? [135, 144, 158], "checked": (o["on"] as? Bool) == true, "locked": locked, "disabled": locked, "sub": locked ? "Waiting for CD approval" : ""]
    }
    onSheet?(["sections": [["header": "Status", "rows": rows]], "instant": true], { [weak self] i in
      guard let self = self, i >= 0, i < opts.count, (opts[i]["on"] as? Bool) != true, let id = opts[i]["id"] as? String else { return }
      self.local { m in
        guard var st = m["status"] as? [String: Any] else { return }
        st["name"] = opts[i]["name"]; st["rgb"] = opts[i]["rgb"]
        st["options"] = opts.map { var o = $0; o["on"] = ($0["id"] as? String) == id; return o }
        m["status"] = st
      }
      self.setStatus(id)
    }, { _, _ in })
  }
  func setStatus(_ id: String, cdAgain: String? = nil) {
    var b: [String: Any] = ["act": "status", "id": taskId, "value": id]
    if let c = cdAgain { b["cdAgain"] = c }
    onAct?(b)
  }
  // the server asks: going back from the client — does it need CD review again?
  func askCdAgain(_ status: String) {
    let a = UIAlertController(title: "Does this need CD review again?", message: "The task is going back for changes.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Yes, needs CD review", style: .default) { [weak self] _ in self?.setStatus(status, cdAgain: "yes") })
    a.addAction(UIAlertAction(title: "No, skip CD review", style: .default) { [weak self] _ in self?.setStatus(status, cdAgain: "no") })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(a)
  }
  private func datesRow(_ d: [String: Any]) -> DItem {
    let can = (d["canEdit"] as? Bool) == true
    let start = d["startLabel"] as? String ?? "", due = d["dueLabel"] as? String ?? ""
    func btn(_ t: String, empty: String, color: UIColor, which: String, value: String) -> UIView {
      if !can { return label(t.isEmpty ? empty : t, size: TaskPage.T, color: t.isEmpty ? .tertiaryLabel : color) }
      var c: UIButton.Configuration = .plain()
      c.attributedTitle = AttributedString(t.isEmpty ? empty : t, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: TaskPage.T)]))
      c.baseForegroundColor = t.isEmpty ? .tertiaryLabel : color
      c.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
      let b = UIButton(configuration: c)
      b.addAction(UIAction { [weak self] _ in
        guard let self = self else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.onDate?(which, value) { v in
          guard let v = v else { return }
          var b: [String: Any] = ["act": which, "id": self.taskId]
          if which == "due" { b["due"] = v } else { b["value"] = v }
          // (shown at once: the day as the page writes it — "Nov 2")
          self.local { m in
            guard var d = m["dates"] as? [String: Any] else { return }
            let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            let day = f.date(from: v); let o = DateFormatter(); o.locale = Locale(identifier: "en_US"); o.dateFormat = "MMM d"
            let label = v.isEmpty ? "" : day.map { o.string(from: $0) } ?? v
            if which == "due" { d["due"] = v; d["dueLabel"] = label; let t = f.string(from: Date()); d["today"] = v == t; d["late"] = !v.isEmpty && v < t } else { d["start"] = v; d["startLabel"] = label }
            m["dates"] = d
          }
          self.onAct?(b)
        }
      }, for: .touchUpInside)
      return b
    }
    let dueColor: UIColor = (d["late"] as? Bool) == true ? .systemRed : (d["today"] as? Bool) == true ? .systemBlue : .secondaryLabel
    let s = UIStackView(arrangedSubviews: [btn(start, empty: "Start", color: .secondaryLabel, which: "start", value: d["start"] as? String ?? ""), symbol("arrow.right", 12, .tertiaryLabel), btn(due, empty: "Due", color: dueColor, which: "due", value: d["due"] as? String ?? "")])
    s.spacing = 6; s.alignment = .center
    return row("dates", sym: "calendar", key: "Dates", value: s, extra: "\(can)|\(d["start"] as? String ?? "")|\(d["due"] as? String ?? "")")
  }
  private func prioRows(_ list: [[String: Any]], can: Bool) -> [DItem] {
    list.map { p in
      let key = p["key"] as? String ?? "_", lab = p["label"] as? String ?? ""
      let v: UIView? = lab.isEmpty ? nil : lab == "Urgent" ? pill("Urgent", fg: .systemRed, bg: UIColor.systemRed.withAlphaComponent(0.15)) : pill(lab, fg: .label, bg: .tertiarySystemFill)
      let who = p["name"] as? String ?? ""
      let plain = who.isEmpty || list.count == 1 && key == (model?["me"] as? String)
      // (whose priority it is in blue, as the date — Haris, 2026-11-02)
      var kt: NSAttributedString?
      if !plain {
        let f = UIFont.preferredFont(forTextStyle: .body)
        let a = NSMutableAttributedString(string: "Priority · ", attributes: [.font: f, .foregroundColor: UIColor.label])
        a.append(NSAttributedString(string: who, attributes: [.font: f, .foregroundColor: UIColor.systemBlue]))
        kt = a
      }
      return row("prio:" + key, sym: "flag", key: "Priority", keyText: kt, text: lab.isEmpty ? (can ? "None" : "–") : nil, value: v, chevron: can, tap: can ? { [weak self] in self?.pickPrio(p) } : nil)
    }
  }
  // Priority, as the website's sheet: whose it is, Urgent (always on top), the numbers for that day (one each per
  // person per day — the ones used on other tasks greyed), No priority
  private func pickPrio(_ p: [String: Any]) {
    let key = p["key"] as? String ?? "_", cur = p["v"] as? String ?? "", who = p["name"] as? String ?? ""
    let taken = Set(((p["taken"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue })
    let me = key == (model?["me"] as? String)
    let day = ((model?["dates"] as? [String: Any])?["dueLabel"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    var secs: [[String: Any]] = []
    var top: [String: Any] = ["rows": [["i": 1, "label": "Urgent", "sub": "always on top", "icon": "flag", "tint": [255, 69, 58], "checked": cur == "urgent"]]]
    if !who.isEmpty || me { top["header"] = me ? "Your priority" : who + "’s priority"; if let pp = people[key] { top["person"] = personArg(pp.merging(["id": key]) { a, _ in a }) } }
    secs.append(top)
    secs.append(["header": "Priority for " + (day ?? "tasks with no due date"), "rows": [["i": -1, "label": "", "kind": "num", "chips": (1...10).map { n in ["i": 100 + n, "label": String(n), "on": cur == String(n), "disabled": taken.contains(n)] }]]])
    secs.append(["rows": [["i": 2, "label": "No priority", "icon": "flag", "checked": cur.isEmpty]]])
    onSheet?(["sections": secs, "instant": true], { [weak self] i in
      guard let self = self else { return }
      if i == 1 { self.setPrio(key, "urgent") } else if i == 2 { self.setPrio(key, "none") } else if i > 100 && i <= 110 { self.setPrio(key, String(i - 100)) }
    }, { _, _ in })
  }
  private func prioItems(_ key: String, cur: String) -> [UIMenuElement] {
    var out: [UIMenuElement] = []
    out.append(UIAction(title: "Urgent", subtitle: "Always on top", image: UIImage(systemName: "flag.fill")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal), state: cur == "urgent" ? .on : .off) { [weak self] _ in self?.setPrio(key, "urgent") })
    var nums: [UIMenuElement] = []
    for n in 1...10 { nums.append(UIAction(title: "\(n)", state: cur == "\(n)" ? .on : .off) { [weak self] _ in self?.setPrio(key, "\(n)") }) }
    out.append(UIMenu(title: "Number (one per day)", options: .displayInline, children: nums))
    out.append(UIMenu(options: .displayInline, children: [UIAction(title: "No priority", state: cur.isEmpty ? .on : .off) { [weak self] _ in self?.setPrio(key, "none") }]))
    return out
  }
  private func setPrio(_ key: String, _ v: String) {
    local { m in
      m["prio"] = ((m["prio"] as? [[String: Any]]) ?? []).map { p in
        guard (p["key"] as? String) == key else { return p }
        var x = p; x["v"] = v == "none" ? "" : v; x["label"] = v == "urgent" ? "Urgent" : v == "none" ? "" : v; return x
      }
    }
    let value: Any = Int(v).map { $0 as Any } ?? v
    onAct?(["act": "prio", "id": taskId, "key": key, "value": value])
  }
  private func updateRow(_ u: [String: Any]?, all: [String], can: Bool) -> DItem {
    let cur = u?["t"] as? String ?? ""
    let v: UIView? = cur.isEmpty ? nil : pill(cur, fg: TaskPage.rgb(u?["rgb"]), bg: TaskPage.rgb(u?["rgb"]).withAlphaComponent(0.16))
    return row("update", sym: "arrow.triangle.2.circlepath", key: "Task Update", text: cur.isEmpty ? (can ? "None" : "–") : nil, value: v, chevron: can, extra: all.joined(separator: ","), tap: can ? { [weak self] in self?.pickUpdate(all, cur: cur) } : nil)
  }
  // Task Update: the website's list, the one on it ticked; Clear at the end when there is one
  private func pickUpdate(_ all: [String], cur: String) {
    var rows: [[String: Any]] = all.enumerated().map { i, x in ["i": i, "label": x, "checked": x == cur] }
    var secs: [[String: Any]] = [["header": "Task Update", "rows": rows]]
    if !cur.isEmpty { rows = [["i": 999, "label": "Clear", "icon": "x"]]; secs.append(["rows": rows]) }
    onSheet?(["sections": secs, "instant": true], { [weak self] i in
      guard let self = self, i >= 0 else { return }
      if i == 999 { self.local { $0["update"] = NSNull() }; self.onAct?(["act": "update", "id": self.taskId, "value": NSNull()]); return }
      guard i < all.count, all[i] != cur else { return }
      self.local { m in
        var u = (m["update"] as? [String: Any]) ?? [:]; u["t"] = all[i]
        if let c = (m["updateRgbs"] as? [Any]), i < c.count { u["rgb"] = c[i] }   // (its colour too, from the server's list)
        m["update"] = u
      }
      self.onAct?(["act": "update", "id": self.taskId, "value": all[i]])
    }, { _, _ in })
  }
  // a subtask: Apple's cell — its tick (ours, a button: ticked by permission), its name, who and when, › opens it
  private func subRow(_ s: [String: Any]) -> DItem {
    let id = s["id"] as? String ?? "", done = (s["done"] as? Bool) == true
    let tick = UIButton(type: .custom)
    tick.setImage(UIImage(systemName: done ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)), for: .normal)
    tick.tintColor = done ? .tintColor : .tertiaryLabel
    tick.isEnabled = (s["canTick"] as? Bool) == true
    tick.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      if !done { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      self.onAct?(["act": done ? "reopen" : "done", "id": id, "page": self.taskId])
    }, for: .touchUpInside)
    let title = s["title"] as? String ?? ""
    var c = UIListContentConfiguration.cell()
    c.attributedText = TaskPage.itemText(title, done: done)
    c.textProperties.numberOfLines = 1
    let it = DItem("sub:" + id)
    it.content = c
    it.accessories.append(.customView(configuration: .init(customView: tick, placement: .leading(), reservedLayoutWidth: .actual)))
    let side = UIStackView(); side.spacing = 8; side.alignment = .center
    if let av = s["av"] as? String { side.addArrangedSubview(avatar(av, 22)) }
    if let due = s["due"] as? String, !due.isEmpty { side.addArrangedSubview(label(due, size: 15, color: (s["late"] as? Bool) == true ? .systemRed : .secondaryLabel)) }
    if !side.arrangedSubviews.isEmpty { it.accessories.append(.customView(configuration: .init(customView: side, placement: .trailing(), reservedLayoutWidth: .actual))) }
    it.accessories.append(.disclosureIndicator())
    it.tap = { [weak self] in self?.onOpen?(id) }
    it.sig = "\(title)|\(done)|\(tick.isEnabled)|" + TaskPage.sig(side)
    return it
  }
  // a checklist item: Apple's cell with Apple's circle / filled tick (as Reminders) — tapped, ticked at once, by permission
  private func checkRow(_ ck: [String: Any], can: Bool) -> DItem {
    let id = ck["id"] as? String ?? "", done = (ck["done"] as? Bool) == true
    let text = ck["text"] as? String ?? ""
    var c = UIListContentConfiguration.cell()
    c.image = UIImage(systemName: done ? "checkmark.circle.fill" : "circle")
    c.imageProperties.tintColor = done ? .tintColor : .tertiaryLabel
    c.attributedText = TaskPage.itemText(text, done: done)
    let it = DItem("chk:" + id)
    it.content = c
    it.sig = "\(text)|\(done)|\(can)"
    if can {
      it.tap = { [weak self] in
        guard let self = self else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        // (ticked at once; the server's answer draws it as it is)
        self.local { m in m["checklist"] = ((m["checklist"] as? [[String: Any]]) ?? []).map { x in var x = x; if (x["id"] as? String) == id { x["done"] = !done }; return x } }
        self.onAct?(["act": "check", "id": self.taskId, "value": id])
      }
    }
    return it
  }
  static func itemText(_ t: String, done: Bool) -> NSAttributedString {
    var a: [NSAttributedString.Key: Any] = [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: done ? UIColor.secondaryLabel : UIColor.label]
    if done { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    return NSAttributedString(string: t, attributes: a)
  }
  // the CD's name under Needs CD review: blue while on, grey when off — turning as the switch is flicked
  private func tintCDName(_ on: Bool) {
    guard let ip = listDS?.indexPath(for: "needsCD"), let cell = scroll.cellForItem(at: ip) as? UICollectionViewListCell, var c = cell.contentConfiguration as? UIListContentConfiguration, c.secondaryText != nil else { return }
    c.secondaryTextProperties.color = on ? .systemBlue : .secondaryLabel
    UIView.transition(with: cell.contentView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) { cell.contentConfiguration = c }
  }

  // ---------- the sheets: people, tags, channels; a line of text ----------
  // the one Attach Files sheet (Camera · Photos · Files); the app uploads them itself, with their bars
  func attachSheet() { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onAttachFiles?() }   // (a tap felt, as every button — Haris, 2026-11-01)
  func askText(_ title: String, placeholder: String, value: String = "", _ done: @escaping (String) -> Void) {
    let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    a.addTextField { f in f.placeholder = placeholder; f.text = value; f.autocapitalizationType = .sentences; f.returnKeyType = .done }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Add", style: .default) { [weak a] _ in let v = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines); if !v.isEmpty { done(v) } })
    present(a)
  }
  private func personArg(_ p: [String: Any]) -> [String: Any] {
    let id = p["id"] as? String ?? ""
    var o: [String: Any] = ["initials": p["initials"] as? String ?? "?"]
    if let c = p["color"] { o["color"] = c }
    if let ph = people[id]?["photo"] as? String, ph.hasPrefix("data:") { o["photo"] = ph }
    return o
  }
  // Assignees: everyone who may be assigned, those on it ticked; each tick saves at once (as the website's sheet)
  func pickPeople() {
    guard let pool = model?["pool"] as? [[String: Any]], !pool.isEmpty else { return }
    var on = pool.map { ($0["on"] as? Bool) == true }
    let rows: [[String: Any]] = pool.enumerated().map { i, p in ["i": i, "label": (p["id"] as? String) == (model?["me"] as? String) ? "Me" : (p["name"] as? String ?? ""), "sub": p["role"] as? String ?? "", "person": personArg(p), "checked": on[i], "multi": true, "find": (p["name"] as? String ?? "") + " " + (p["role"] as? String ?? "")] }
    // (in their groups, as the website's sheet: Production, Social, Freelancers, Creative Director — whoever is on it ticked)
    let order: [(String, String)] = [("Production", "Production"), ("Social", "Social"), ("Freelancer", "Freelancers"), ("Creative Director", "Creative Director"), ("", "Others")]
    let sections: [[String: Any]] = order.compactMap { key, head in
      let known = Set(order.dropLast().map { $0.0 })
      let rs = rows.enumerated().filter { e in let r = pool[e.offset]["role"] as? String ?? ""; return r == key || (key == "" && !known.contains(r)) }
        .map { $0.element }.sorted { ($0["label"] as? String ?? "") == "Me" ? true : ($1["label"] as? String ?? "") == "Me" ? false : ($0["label"] as? String ?? "").localizedCompare($1["label"] as? String ?? "") == .orderedAscending }
      return rs.isEmpty ? nil : ["header": head, "rows": rs]
    }
    onSheet?(["sections": sections, "multi": true, "search": "Search people"], { [weak self] i in
      guard let self = self, i >= 0, i < pool.count, let id = pool[i]["id"] as? String else { return }
      on[i].toggle()
      UISelectionFeedbackGenerator().selectionChanged()
      let now = on[i]
      self.local { m in
        var a = (m["assignees"] as? [[String: Any]]) ?? []
        if now { if !a.contains(where: { ($0["id"] as? String) == id }) { a.append(["id": id, "done": false]) } } else { a.removeAll { ($0["id"] as? String) == id } }
        m["assignees"] = a
        let ticks = on
        m["pool"] = pool.enumerated().map { k, p in var x = p; x["on"] = k < ticks.count ? ticks[k] : false; return x }
      }
      self.onAct?(["act": "assign", "id": self.taskId, "key": id, "value": on[i]])
    }, { _, _ in })
  }
  func pickGuardian() {
    guard let pool = model?["pool"] as? [[String: Any]] else { return }
    let cur = model?["guardian"] as? String
    var rows: [[String: Any]] = pool.enumerated().map { i, p in ["i": i, "label": p["name"] as? String ?? "", "sub": p["role"] as? String ?? "", "person": personArg(p), "checked": (p["id"] as? String) == cur, "find": p["name"] as? String ?? ""] }
    if cur != nil { rows.append(["i": 999, "label": "No Guardian", "icon": "x"]) }
    // (as the other sheets: felt and shown at the tap — Haris 2026-11-02)
    onSheet?(["sections": [["header": "Guardian", "rows": rows]], "search": "Search people", "instant": true], { [weak self] i in
      guard let self = self, i >= 0 else { return }
      var v: Any = NSNull()
      if i != 999, i < pool.count, let id = pool[i]["id"] as? String {
        if id == cur { return }
        v = id
        let p = pool[i]
        self.local { m in
          m["guardian"] = id
          var pp = (m["people"] as? [String: [String: Any]]) ?? [:]
          if pp[id] == nil { let n = p["name"] as? String ?? ""; pp[id] = ["name": n, "first": n.split(separator: " ").first.map(String.init) ?? n, "initials": p["initials"] ?? "?", "color": p["color"] ?? [128, 128, 128]] }
          m["people"] = pp
        }
      } else { self.local { $0["guardian"] = NSNull() } }
      self.onAct?(["act": "guardian", "id": self.taskId, "value": v])
    }, { _, _ in })
  }
  // Finance: the website's five, the one on it ticked; Clear at the end when there is one
  private func pickFinance(_ cur: String) {
    let opts = (model?["financeOpts"] as? [[String: Any]]) ?? []
    guard !opts.isEmpty else { return }
    var secs: [[String: Any]] = [["header": "Finance", "rows": opts.enumerated().map { i, o in ["i": i, "label": o["t"] as? String ?? "", "dot": o["rgb"] ?? [128, 128, 128], "checked": (o["t"] as? String) == cur] }]]
    if !cur.isEmpty { secs.append(["rows": [["i": 999, "label": "Clear", "icon": "x"]]]) }
    onSheet?(["sections": secs, "instant": true], { [weak self] i in
      guard let self = self, i >= 0 else { return }
      if i == 999 { self.local { m in var f = (m["finance"] as? [String: Any]) ?? [:]; f["v"] = ""; f["rgb"] = NSNull(); m["finance"] = f }; self.onAct?(["act": "finance", "id": self.taskId, "value": NSNull()]); return }
      guard i < opts.count, let t = opts[i]["t"] as? String, t != cur else { return }
      self.local { m in var f = (m["finance"] as? [String: Any]) ?? [:]; f["v"] = t; f["rgb"] = opts[i]["rgb"]; m["finance"] = f }
      self.onAct?(["act": "finance", "id": self.taskId, "value": t])
    }, { _, _ in })
  }
  // Tags: this task's (ticked — untick to remove), then the ones used most; type to add a new one
  func pickTags() {
    guard let m = model else { return }
    let mine = ((m["tags"] as? [[String: Any]]) ?? []).compactMap { $0["t"] as? String }
    let others = ((m["allTags"] as? [String]) ?? []).filter { t in !mine.contains { $0.lowercased() == t.lowercased() } }
    let list = mine + others
    var on = list.map { mine.contains($0) }
    let canRemove = (m["canRemoveTag"] as? Bool) == true
    let row = { (i: Int, t: String) -> [String: Any] in ["i": i, "label": t, "checked": on[i], "multi": true, "icon": "tag", "disabled": on[i] && !canRemove] }
    var secs: [[String: Any]] = []
    if !mine.isEmpty { secs.append(["header": "On this task", "rows": mine.enumerated().map { row($0.offset, $0.element) }]) }
    if !others.isEmpty { secs.append(["header": "Used most", "rows": others.enumerated().map { row(mine.count + $0.offset, $0.element) }]) }
    onSheet?(["sections": secs, "multi": true, "search": "Search or add a tag", "custom": "Add “%@”"], { [weak self] i in
      guard let self = self, i >= 0, i < list.count else { return }
      on[i].toggle()
      UISelectionFeedbackGenerator().selectionChanged()
      self.onAct?(["act": on[i] ? "addTag" : "removeTag", "id": self.taskId, "value": list[i]])
    }, { [weak self] i, typed in
      guard let self = self, i == -2, let v = typed?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
      self.onAct?(["act": "addTag", "id": self.taskId, "value": v])
    })
  }
  func pickClient() {
    guard let list = model?["clients"] as? [[String: Any]], !list.isEmpty else { return }
    let rows: [[String: Any]] = list.enumerated().map { i, c in ["i": i, "label": c["name"] as? String ?? "", "dot": c["rgb"] ?? [128, 128, 128], "checked": (c["on"] as? Bool) == true, "find": c["name"] as? String ?? ""] }
    onSheet?(["sections": [["header": "Move to client", "rows": rows]], "search": "Search clients", "instant": true], { [weak self] i in
      guard let self = self, i >= 0, i < list.count, (list[i]["on"] as? Bool) != true, let id = list[i]["id"] as? String else { return }
      self.local { m in
        m["client"] = ["id": id, "name": list[i]["name"] ?? "", "rgb": list[i]["rgb"] ?? [128, 128, 128]]
        m["clients"] = list.map { var c = $0; c["on"] = ($0["id"] as? String) == id; return c }
      }
      self.onAct?(["act": "client", "id": self.taskId, "value": id])
    }, { _, _ in })
  }
  func pickChannels() {
    guard let m = model, let all = m["allChannels"] as? [[String: Any]] else { return }
    var keys = (m["channelKeys"] as? [String]) ?? []
    let rows: [[String: Any]] = all.enumerated().map { i, c in ["i": i, "label": c["n"] as? String ?? "", "checked": keys.contains(c["k"] as? String ?? ""), "multi": true, "icon": "send"] }
    onSheet?(["sections": [["header": "Channels", "rows": rows]], "multi": true], { [weak self] i in
      guard let self = self, i >= 0, i < all.count, let k = all[i]["k"] as? String else { return }
      if let j = keys.firstIndex(of: k) { keys.remove(at: j) } else { keys.append(k) }
      UISelectionFeedbackGenerator().selectionChanged()
      self.onAct?(["act": "channels", "id": self.taskId, "value": keys])
    }, { _, _ in })
  }

  // ---------- the title, edited in place ----------
  func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    if tv === descView {
      // (typing after a mention, or where one was deleted: plain words again, not the mention's blue — Haris 2026-11-02)
      if !text.isEmpty, tv.typingAttributes[MENTION_KEY] != nil {
        var a = tv.typingAttributes; a[MENTION_KEY] = nil; a[.foregroundColor] = UIColor.label; a[.link] = nil; tv.typingAttributes = a
      }
      // (a pasted file's 📎 is one piece: words typed next to it are plain, and deleting into it takes it all)
      if !text.isEmpty, tv.typingAttributes[FILEREF_KEY] != nil {
        var a = tv.typingAttributes; a[FILEREF_KEY] = nil; a[.foregroundColor] = UIColor.label; tv.typingAttributes = a
      }
      if text.isEmpty, range.length > 0, range.location < tv.attributedText.length {
        var whole = range
        for k in [range.location, NSMaxRange(range) - 1] where k >= 0 && k < tv.attributedText.length {
          var er = NSRange(location: 0, length: 0)
          if tv.attributedText.attribute(FILEREF_KEY, at: k, effectiveRange: &er) != nil { whole = NSUnionRange(whole, er) }
        }
        if whole != range {
          let m = NSMutableAttributedString(attributedString: tv.attributedText); m.deleteCharacters(in: whole)
          tv.attributedText = m; tv.selectedRange = NSRange(location: whole.location, length: 0)
          textViewDidChange(tv)
          return false
        }
      }
      return true
    }
    if text == "\n" { tv.resignFirstResponder(); return false }
    return true
  }
  // (writing in the description opens it all, as Expand does)
  func textViewDidBeginEditing(_ tv: UITextView) { if tv === descView { descBox.expand(); beginDesc() } }
  func textViewDidChangeSelection(_ tv: UITextView) { if tv === descView, tv.isFirstResponder, kbCover > 0 { DispatchQueue.main.async { self.caretIntoView() } } }
  func textViewDidChange(_ tv: UITextView) { setNeedsLayout(); if tv === descView { descChanged(); DispatchQueue.main.async { self.caretIntoView(); if !self.pulses.isEmpty || self.descUploading { self.placePulses() } } } }
  func textViewDidEndEditing(_ tv: UITextView) {
    if tv === descView { return }
    let v = tv.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let was = model?["title"] as? String ?? ""
    if v.isEmpty { tv.text = was; return }
    if v != was { onAct?(["act": "title", "id": taskId, "value": v]) }
  }

  // ---------- a short message, low on the screen ----------
  func toast(_ text: String, action: (String, () -> Void)? = nil) {
    toastView?.removeFromSuperview()
    let v = UIView(); v.backgroundColor = .secondarySystemGroupedBackground; v.layer.cornerRadius = 14; v.layer.cornerCurve = .continuous
    v.layer.shadowColor = UIColor.black.cgColor; v.layer.shadowOpacity = 0.18; v.layer.shadowRadius = 12; v.layer.shadowOffset = CGSize(width: 0, height: 4)
    let l = label(text, size: 15, color: .label, weight: .medium); l.numberOfLines = 2; l.textAlignment = .center
    v.addSubview(l)
    var bw: CGFloat = 0
    let btn = UIButton(type: .system)
    if let act = action {
      let (t, run) = act
      btn.setTitle(t, for: .normal); btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
      btn.addAction(UIAction { [weak v] _ in v?.removeFromSuperview(); run() }, for: .touchUpInside)
      v.addSubview(btn); bw = btn.sizeThatFits(CGSize(width: 200, height: 40)).width + 16
    }
    let W = bounds.width, ls = l.sizeThatFits(CGSize(width: W - 64 - bw, height: 60))
    let w = ls.width + 32 + bw, h = max(44, ls.height + 20)
    let bottom = tab == "comments" ? barBottom + 60 : (fab.isHidden ? bounds.height - max(safeAreaInsets.bottom, 20) - 8 : fab.frame.minY - 10)
    v.frame = CGRect(x: (W - w) / 2, y: bottom - h, width: w, height: h)
    l.frame = CGRect(x: 16, y: (h - ls.height) / 2, width: ls.width, height: ls.height)
    btn.frame = CGRect(x: w - bw - 4, y: 0, width: bw, height: h)
    v.alpha = 0; v.transform = CGAffineTransform(translationX: 0, y: 8)
    addSubview(v); toastView = v
    UIView.animate(withDuration: 0.16) { v.alpha = 1; v.transform = .identity }
    DispatchQueue.main.asyncAfter(deadline: .now() + (action == nil ? 2.6 : 8)) { [weak self, weak v] in
      UIView.animate(withDuration: 0.2, animations: { v?.alpha = 0 }) { _ in v?.removeFromSuperview(); if self?.toastView === v { self?.toastView = nil } }
    }
  }

  // ---------- helpers ----------
  static func rgb(_ a: Any?) -> UIColor {
    guard let a = a as? [NSNumber], a.count >= 3 else { return .systemGray }
    return UIColor(red: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: 1)
  }
  static func size(_ n: Int) -> String { n <= 0 ? "" : n < 1024 * 1024 ? "\(max(1, n / 1024)) KB" : String(format: "%.1f MB", Double(n) / 1048576) }
  static func fileSym(_ name: String) -> String {
    let e = (name as NSString).pathExtension.lowercased()
    if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(e) { return "photo" }
    if ["mp4", "mov", "m4v"].contains(e) { return "film" }
    if e == "pdf" { return "doc.richtext" }
    return "doc"
  }
  static func when(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let s = Date().timeIntervalSince(d)
    if s < 60 { return "now" }
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
    let o = DateFormatter(); o.dateFormat = "MMM d"; o.locale = Locale(identifier: "en_US")
    return o.string(from: d)
  }
}

// a row that can be tapped (greys while pressed, as iPhone's lists) or hold iPhone's own menu
final class TaskRow: UIView, UIContextMenuInteractionDelegate {
  var onTap: (() -> Void)? { didSet { if onTap != nil && tapG == nil { let g = UITapGestureRecognizer(target: self, action: #selector(tapped)); addGestureRecognizer(g); tapG = g } } }
  // touch and hold: iPhone's own menu (a file's Open, Copy, Download)
  var holdMenu: (() -> UIMenu?)? { didSet { if holdMenu != nil && !interactions.contains(where: { $0 is UIContextMenuInteraction }) { addInteraction(UIContextMenuInteraction(delegate: self)) } } }
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
    guard let m = holdMenu?() else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in m }
  }
  // (at its own size while its menu shows, as the files' — Haris 2026-11-06)
  func contextMenuInteraction(_ i: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration c: UIContextMenuConfiguration) -> UITargetedPreview? { PressPreview.make(self) }
  var pressBg = true
  private var tapG: UITapGestureRecognizer?
  private var menuBtn: UIButton?
  @objc private func tapped() { onTap?() }
  // with a menu: a switch or button inside the row keeps its own taps; anywhere else opens the menu
  override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? {
    guard let mb = menuBtn else { return super.hitTest(p, with: e) }
    mb.isHidden = true
    let v = super.hitTest(p, with: e)
    mb.isHidden = false
    if let c = v as? UIControl, c !== mb { return c }
    return point(inside: p, with: e) ? mb : nil
  }
  // the menu opens from a tap anywhere on the row (an invisible button over it)
  func attachMenu(_ m: UIMenu) {
    let b = UIButton(type: .custom)
    b.menu = m; b.showsMenuAsPrimaryAction = true
    b.translatesAutoresizingMaskIntoConstraints = false
    addSubview(b)
    NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: leadingAnchor), b.trailingAnchor.constraint(equalTo: trailingAnchor), b.topAnchor.constraint(equalTo: topAnchor), b.bottomAnchor.constraint(equalTo: bottomAnchor)])
    menuBtn = b
  }
  override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { super.touchesBegan(t, with: e); if onTap != nil && pressBg { backgroundColor = .systemFill } }
  override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { super.touchesEnded(t, with: e); unpress() }
  override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { super.touchesCancelled(t, with: e); unpress() }
  private func unpress() { if backgroundColor != nil { UIView.animate(withDuration: 0.25) { self.backgroundColor = nil } } }
}

final class PaddedLabel: UILabel {
  var insets = UIEdgeInsets.zero
  override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
  override var intrinsicContentSize: CGSize { let s = super.intrinsicContentSize; return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom) }
  override func sizeThatFits(_ size: CGSize) -> CGSize { let s = super.sizeThatFits(size); return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom) }
}

// Details in Apple's list (Haris 2026-11-09, "Task page Details — fully Apple"): a section — Apple's box with its header
// (the creator as Apple's footer on the last), or the head without a box — and its items
struct DSec {
  var key: String
  var head: String?
  var foot: String?
  var plain: Bool
  var items: [String]
}
// one item: Apple's own list cell, set by Apple's configuration — or a piece of ours Apple has no part for, held in Apple's
// cell (the client line, the title, a note, the description, the files); sig: what it shows, so only a change sets it again
final class DItem {
  let key: String
  var sig = ""
  var content: UIListContentConfiguration?
  var accessories: [UICellAccessory] = []
  var tap: (() -> Void)?
  var host: UIView?
  var pad = UIEdgeInsets.zero
  var plain = false
  init(_ key: String) { self.key = key }
}
// a piece of ours in Apple's list cell: placed inside the cell's margins, its height measured for Apple's own self-sizing
final class HostCell: UICollectionViewListCell {
  private weak var hosted: UIView?
  private var pad = UIEdgeInsets.zero
  func host(_ v: UIView?, pad p: UIEdgeInsets, plain: Bool) {
    pad = p
    backgroundConfiguration = plain ? .clear() : .listGroupedCell()
    if hosted !== v, let old = hosted, old.superview === contentView { old.removeFromSuperview() }
    hosted = v
    // (put in place at once, with no animation: drawn inside the list's own animation it grew from nothing)
    if let v = v, v.superview !== contentView {
      UIView.performWithoutAnimation { v.transform = .identity; v.translatesAutoresizingMaskIntoConstraints = true; contentView.addSubview(v) }
    }
    setNeedsLayout()
  }
  private var box: UIEdgeInsets {
    let m = contentView.layoutMargins
    return UIEdgeInsets(top: pad.top, left: pad.left < 0 ? m.left : pad.left, bottom: pad.bottom, right: pad.right < 0 ? m.right : pad.right)
  }
  func measure(_ W: CGFloat) -> CGFloat {
    guard let v = hosted else { return 1 }
    let b = box, w = max(1, W - b.left - b.right)
    var h: CGFloat
    if let tv = v as? UITextView { h = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height }
    else {
      if v.bounds.width != w { v.bounds.size.width = w }
      v.setNeedsLayout(); v.layoutIfNeeded()
      h = v.systemLayoutSizeFitting(CGSize(width: w, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }
    return ceil(h) + b.top + b.bottom
  }
  var needsFit: Bool { hosted != nil && abs(bounds.height - measure(bounds.width)) > 0.5 }
  override func preferredLayoutAttributesFitting(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    let r = super.preferredLayoutAttributesFitting(a)
    r.size.height = measure(a.size.width)
    return r
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let v = hosted, v.superview === contentView else { return }
    let f = contentView.bounds.inset(by: box)
    if v.frame != f { v.frame = f }
  }
}

// the description on the page: all of it, or — a long one, until Expand is tapped (once) — its first lines fading out
// with an Expand button on them, as ClickUp's. Writing in it opens it all.
final class DescBox: UIView {
  private(set) var expanded = false
  var onExpand: (() -> Void)?
  private weak var text: UITextView?
  private let fade = CAGradientLayer(), button = UIButton(type: .system)
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    // (under its header on the page itself — no box, Haris 2026-11-09: it fades into the page's colour, and Apple's
    //  "Show More" in the tint under it — mock-up "Task page Details — fully Apple")
    var c = UIButton.Configuration.plain()
    c.attributedTitle = AttributedString("Show More", attributes: AttributeContainer([.font: UIFont.preferredFont(forTextStyle: .body)]))
    c.baseForegroundColor = .tintColor
    c.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 8)
    button.configuration = c
    button.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.expand() }, for: .touchUpInside)
    followLook("fade") { [weak self] _ in self?.setNeedsLayout() }   // (a layer's colour: set again on the look's change)
  }
  required init?(coder: NSCoder) { fatalError() }
  func hold(_ tv: UITextView) {
    if text !== tv {
      text?.removeFromSuperview()
      tv.removeFromSuperview(); tv.translatesAutoresizingMaskIntoConstraints = false; addSubview(tv)
      // (its own full height; the box shows as much of it as it's given)
      NSLayoutConstraint.activate([tv.topAnchor.constraint(equalTo: topAnchor), tv.leadingAnchor.constraint(equalTo: leadingAnchor), tv.trailingAnchor.constraint(equalTo: trailingAnchor)])
      text = tv
    }
    layer.addSublayer(fade); addSubview(button)
  }
  func expand() { guard !expanded else { return }; expanded = true; onExpand?() }
  // (a long one, not opened yet: the cap, the fade and the button; the box is measured after this)
  override func layoutSubviews() {
    let w = bounds.width
    let full = text.map { $0.sizeThatFits(CGSize(width: w > 0 ? w : 300, height: .greatestFiniteMagnitude)).height } ?? 0
    if text?.isFirstResponder == true { expanded = true }
    let short = !expanded && full > 168 + 40
    super.layoutSubviews()
    fade.isHidden = !short; button.isHidden = !short
    // (the words fade out above 168, the rest covered in the page's colour; Show More under them)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    let bg = UIColor.systemGroupedBackground.resolvedColor(with: traitCollection)
    fade.frame = CGRect(x: 0, y: 108, width: w, height: max(60, bounds.height - 108))
    fade.colors = [bg.withAlphaComponent(0).cgColor, bg.cgColor, bg.cgColor]
    fade.locations = [0, NSNumber(value: Double(60 / max(60, bounds.height - 108))), 1]
    CATransaction.commit()
    let s = button.sizeThatFits(CGSize(width: 200, height: 40))
    button.frame = CGRect(x: 0, y: 170, width: s.width, height: s.height)
    bringSubviewToFront(button)
  }
  // (the size the page gives it: capped while it's a long one not opened)
  override func systemLayoutSizeFitting(_ t: CGSize, withHorizontalFittingPriority h: UILayoutPriority, verticalFittingPriority v: UILayoutPriority) -> CGSize {
    let full = text.map { $0.sizeThatFits(CGSize(width: t.width, height: .greatestFiniteMagnitude)).height } ?? 0
    if text?.isFirstResponder == true { expanded = true }
    let short = !expanded && full > 168 + 40
    return CGSize(width: t.width, height: ceil(short ? 168 + 36 : full))
  }
}


// ---------- changes on the page, smooth (Haris, 2026-11-02 — now Apple's own: Details is Apple's list, 2026-11-08) ----
extension TaskPage {
  static func firstText(_ v: UIView) -> String? {
    if let l = v as? UILabel, let t = l.text, !t.isEmpty { return t }
    for s in v.subviews { if let t = firstText(s) { return t } }
    return nil
  }
  // what a view shows, in words: its texts, pictures and colours (changed → cross-faded)
  // (a colour by its values and a picture by what it is — their descriptions carry a memory address, new at every drawing,
  //  so an unchanged card looked changed and flashed: the CD lock card, the Files block — Haris 2026-11-02)
  private static func cs(_ c: UIColor?, _ tc: UITraitCollection) -> String {
    guard let c = c else { return "-" }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.resolvedColor(with: tc).getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
  }
  private static func ims(_ i: UIImage?) -> String {
    guard let i = i else { return "-" }
    return String(i.description.replacingOccurrences(of: "0x[0-9a-fA-F]+", with: "", options: .regularExpression).prefix(200)) + "\(i.size.width)x\(i.size.height)"
  }
  static func sig(_ v: UIView) -> String {
    var out = ""
    let tc = v.traitCollection
    func walk(_ v: UIView) {
      if v.isHidden { return }
      if let l = v as? UILabel { out += "L" + (l.attributedText?.string ?? l.text ?? "") + cs(l.textColor, tc) }
      if let t = v as? UITextView { out += "T" + (t.text ?? "") }
      if let i = v as? UIImageView { out += "I" + ims(i.image) + cs(i.tintColor, tc) }
      if let b = v as? UIButton { out += "B" + ims(b.currentImage) + (b.currentTitle ?? b.configuration?.title ?? "") + cs(b.tintColor, tc) }
      if let c = v.backgroundColor { out += "C" + cs(c, tc) }
      // (what a control is set to, and how see-through things are: a kept section must show just the same)
      if let sw = v as? UISwitch { out += "S\(sw.isOn)" }
      if let c = v as? UIControl { out += "E\(c.isEnabled)" }
      if v.alpha < 1 { out += "A" + String(format: "%.2f", v.alpha) }
      if let l = v as? UILabel, let a = l.attributedText, a.length > 0 {
        a.enumerateAttributes(in: NSRange(location: 0, length: a.length)) { at, r, _ in
          if at[.strikethroughStyle] != nil { out += "~\(r.location)" }
          if let c = at[.foregroundColor] as? UIColor { out += "f" + cs(c, tc) }
          if let f = at[.font] as? UIFont { out += "w\(f.fontDescriptor.symbolicTraits.rawValue)\(f.pointSize)" }
        }
      }
      v.subviews.forEach(walk)
    }
    walk(v)
    return out
  }
}


// ---------- files from the phone into the description ----------
extension TaskPage {
  func descAttach(_ src: String) {
    descInsertAt = descView.selectedRange
    onDescAttach?(src)
  }
  // a picture or file pasted from outside the app (Photos, Files…): uploaded, its chip where the cursor is
  func pasteUpload() -> Bool {
    let pb = UIPasteboard.general
    var picked: [(URL, String)] = []
    for item in pb.items {
      guard let type = item.keys.first(where: { t in guard let u = UTType(t) else { return false }; return !u.conforms(to: .text) }) else { continue }
      var data: Data? = item[type] as? Data
      if data == nil, let img = item[type] as? UIImage { data = img.jpegData(compressionQuality: 0.9) }
      guard let d = data else { continue }
      let ext = (item[type] is UIImage) ? "jpg" : (UTType(type)?.preferredFilenameExtension ?? "dat")
      let name = (UTType(type)?.conforms(to: .image) == true || item[type] is UIImage ? "Pasted image." : "Pasted file.") + ext
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paste-\(UUID().uuidString)", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let u = dir.appendingPathComponent(name)
      guard (try? d.write(to: u)) != nil else { continue }
      picked.append((u, name))
    }
    if picked.isEmpty { return false }
    descInsertAt = descView.selectedRange
    onDescUpload?(picked)
    return true
  }
  var descUploading: Bool {
    var any = false
    let a = descView.attributedText ?? NSAttributedString()
    a.enumerateAttribute(FILEREF_KEY, in: NSRange(location: 0, length: a.length)) { v, _, stop in if (v as? [String: Any])?["pending"] != nil { any = true; stop.pointee = true } }
    return any
  }
  // the uploads have started: a greyed chip for each where the cursor was
  func descUploadsStarted(_ items: [(String, String)]) {
    guard editingDesc else { return }
    DescEditor.dark = !light
    let tv = descView
    let at = descInsertAt ?? tv.selectedRange; descInsertAt = nil
    let plain: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.label]
    let add = NSMutableAttributedString()
    for (id, name) in items {
      add.append(DescEditor.chip(["pending": id, "name": name], size: TaskPage.T))
      add.append(NSAttributedString(string: " ", attributes: plain))
    }
    let m = NSMutableAttributedString(attributedString: tv.attributedText)
    let r = NSRange(location: min(at.location, m.length), length: min(at.length, max(0, m.length - at.location)))
    m.replaceCharacters(in: r, with: add)
    tv.attributedText = m
    tv.selectedRange = NSRange(location: r.location + add.length, length: 0)
    tv.typingAttributes = plain
    if !tv.isFirstResponder { tv.becomeFirstResponder() }
    setNeedsLayout(); relayAnimated()
    DispatchQueue.main.async { self.placePulses() }
  }
  // a chip still uploading pulses, as the upload cards in Files do: a soft veil over it fading in and out, kept on the
  // chip as the words around it change (Haris 2026-11-02)
  func placePulses() {
    let tv = descView
    let a = tv.attributedText ?? NSAttributedString()
    var want: [String: CGRect] = [:]
    a.enumerateAttribute(FILEREF_KEY, in: NSRange(location: 0, length: a.length)) { v, r, _ in
      guard let id = (v as? [String: Any])?["pending"] as? String,
            let s = tv.position(from: tv.beginningOfDocument, offset: r.location), let e = tv.position(from: s, offset: r.length),
            let tr = tv.textRange(from: s, to: e) else { return }
      want[id] = tv.firstRect(for: tr)
    }
    for (id, v) in pulses where want[id] == nil { v.removeFromSuperview(); pulses[id] = nil }
    for (id, f) in want where !f.isNull && !f.isInfinite {
      let v: UIView
      if let x = pulses[id] { v = x } else {
        v = UIView(); v.isUserInteractionEnabled = false; v.backgroundColor = .systemBackground; v.alpha = 0
        tv.addSubview(v); pulses[id] = v
        UIView.animate(withDuration: 0.8, delay: 0, options: [.autoreverse, .repeat, .curveEaseInOut, .allowUserInteraction]) { v.alpha = 0.55 }
      }
      v.frame = f; v.layer.cornerRadius = f.height / 2
    }
  }
  // one is up (path) or failed (nil): its real chip in place of the greyed one, its card under the description
  func descUploaded(_ id: String, path: String?, size: Int) {
    let tv = descView
    let a = NSMutableAttributedString(attributedString: tv.attributedText)
    var found: (NSRange, [String: Any])?
    a.enumerateAttribute(FILEREF_KEY, in: NSRange(location: 0, length: a.length)) { v, r, stop in
      if let f = v as? [String: Any], (f["pending"] as? String) == id { found = (r, f); stop.pointee = true }
    }
    guard let hit = found else { return }
    let r = hit.0, f = hit.1
    let sel = tv.selectedRange
    let name = f["name"] as? String ?? "File"
    DescEditor.dark = !light
    if let path = path {
      a.replaceCharacters(in: r, with: DescEditor.chip(["path": path, "name": name, "size": size], size: TaskPage.T))
      // (no card under the description for it: it's in the task's Files already — Haris 2026-11-02; kept for its chip)
      let url = "/__file/" + path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/") + "?view=1"
      descPending.append(["id": "desc-" + id, "file": path, "name": name, "size": size, "url": url])
    } else {
      a.deleteCharacters(in: r)
      toast("Upload failed — try again")
    }
    tv.attributedText = a
    tv.selectedRange = NSRange(location: min(sel.location, a.length), length: 0)
    placePulses()
    setNeedsLayout(); relayAnimated()
    if descAutoFinish && !descUploading { finishDesc() }
  }
}
