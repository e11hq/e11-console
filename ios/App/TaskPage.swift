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

  // Details: Apple's list (step 2, Haris 2026-11-08) — each section, row group, note and heading a cell of iPhone's own
  // collection list; Apple places them and animates what comes, goes and moves (our own placing and change animation
  // taken out)
  let scroll: UICollectionView = {
    let cv = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    cv.backgroundColor = .clear
    cv.allowsSelection = false
    return cv
  }()
  private var listDS: UICollectionViewDiffableDataSource<Int, String>?
  private var listKeys: [String] = []
  private var listViews: [String: UIView] = [:]
  private var listGeo: [String: PageCell.Geo] = [:]
  private let barBox = UIView()                        // what the frost edge sits under (the buttons and the switch)
  var barBoxView: UIView { barBox }
  private var edgeHook: AnyObject?
  // the frost under the bar follows whichever list is showing (Details, the comments, a thread)
  func edgeScroll(_ sv: UIScrollView) { if #available(iOS 26.0, *) { (edgeHook as? UIScrollEdgeElementContainerInteraction)?.scrollView = sv } }
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
    for b in blocks { b.isUserInteractionEnabled = !editingDesc || b === descBox }
    seg.isEnabled = !editingDesc
    updatePager()
  }
  let mentionBox = UIStackView()
  var onSubmitFiles: ((String) -> Void)?
  var onOpenFiles: (([[String: Any]], Int) -> Void)?
  var onAttachFiles: (() -> Void)?
  var onAttachFrom: ((String) -> Void)?
  var onFileAction: (([String: Any], String) -> Void)?   // a file's "open" / "copy" / "download" (its touch-and-hold menu)   // (••• → Attach Files → Camera / Photos / Files)
  private var filesBlock: UIView?
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
  private func relayAnimated() { UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.layoutContent() } }
  func showFiles() {
    guard let b = filesBlock, tab == "details", let k = listViews.first(where: { $0.value === b })?.key, let ip = listDS?.indexPath(for: k) else { return }
    // (the Files block's bottom just above the bottom edge — Apple's list scrolls it there)
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
    let reg = UICollectionView.CellRegistration<PageCell, String> { [weak self] cell, _, key in
      cell.host(self?.listViews[key], self?.listGeo[key] ?? PageCell.Geo(x: 0, w: 0, h: 1, gap: 0))
    }
    listDS = UICollectionViewDiffableDataSource<Int, String>(collectionView: scroll) { cv, ip, key in cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: key) }
    // (the keyboard: the page scrolls up past it, so where you're writing in the description stays in sight — Haris
    //  2026-11-02)
    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in self?.keyboardMoved(n) }
    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in self?.kbCover = 0; self?.setNeedsLayout() }
    NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in self?.caretIntoView() }
    commentsHost.isHidden = true
    commentsHost.clipsToBounds = true
    pager.addSubview(commentsHost)
    addSubview(barBox)
    if #available(iOS 26.0, *) {
      let i = UIScrollEdgeElementContainerInteraction()
      i.scrollView = scroll; i.edge = .top
      barBox.addInteraction(i)
      edgeHook = i
      // (Apple's own frost behind Details · Comments and the bar, from the list under them — Apple's scroll edge, as it
      //  comes: our firmer frost and the code watching the list for it removed, Haris 2026-11-07)
    }
    barBox.addSubview(seg)
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
    backgroundColor = .systemBackground
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
  var barBottom: CGFloat { rowBottom + 8 + 32 + 10 }
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
    barBox.frame = CGRect(x: 0, y: 0, width: W, height: barBottom)
    seg.frame = CGRect(x: 16, y: rowBottom + 8, width: W - 32, height: 32)
    let fs = fab.sizeThatFits(CGSize(width: 300, height: 48))
    let bottom = max(safeAreaInsets.bottom, window?.safeAreaInsets.bottom ?? 0)
    fab.frame = CGRect(x: W - 16 - fs.width, y: bounds.height - bottom - 8 - 48, width: fs.width, height: 48)
    spinner.center = CGPoint(x: W / 2, y: barBottom + 60)
    if scroll.contentInset.top != barBottom { scroll.contentInset.top = barBottom; scroll.verticalScrollIndicatorInsets.top = barBottom; scroll.contentOffset.y = -barBottom }
    if scroll.verticalScrollIndicatorInsets.top != barBottom { scroll.verticalScrollIndicatorInsets.top = barBottom }
    scroll.verticalScrollIndicatorInsets.bottom = bottom + 8   // (down to just above the bottom edge)
    layoutContent()
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
  func setComments(_ n: Int) { seg.setTitle(n > 0 ? "Comments \(n)" : "Comments", forSegmentAt: 1) }

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
    listHold = true
    UIView.performWithoutAnimation {
      CATransaction.begin(); CATransaction.setDisableActions(true)
      rebuild()
      setNeedsLayout(); layoutIfNeeded()
      CATransaction.commit()
    }
    // (then Apple's list told what came, went, moved or changed — with its own animation once the page is on screen)
    listHold = false
    layoutContent()
  }
  // Only the sections that changed are new (Haris 2026-11-03): each new section is matched with the one before it by
  // what it is (its key) — when it shows just the same, the one already on the page stays and the new one is dropped.
  // The ones holding the page's own pieces (the title, the description, the file rows) are always the new ones: those
  // pieces move into them as they're built.
  private func blockKey(_ b: UIView) -> String {
    if let n = b.layer.name, n.hasPrefix("k:") { return n }
    return String(describing: type(of: b)) + ":" + (TaskPage.firstText(b) ?? "")
  }
  private func holdsOwnPieces(_ b: UIView) -> Bool {
    let own: [UIView] = [titleView, descBox, descView, descRead, filesStrip, descStrip, mentionBox]
    return own.contains { $0 === b || $0.isDescendant(of: b) }
  }
  private func keepUnchanged(_ old: [UIView]) {
    var pool: [String: [UIView]] = [:]
    for b in old where !holdsOwnPieces(b) && !(b is PageBand) { pool[blockKey(b), default: []].append(b) }
    var kept = Set<ObjectIdentifier>()
    for (i, b) in blocks.enumerated() where !holdsOwnPieces(b) {
      let k = blockKey(b)
      guard var list = pool[k], let j = list.firstIndex(where: { type(of: $0) == type(of: b) && TaskPage.sig($0) == TaskPage.sig(b) && $0.tag == b.tag }) else { continue }
      let o = list.remove(at: j); pool[k] = list
      blocks[i] = o; kept.insert(ObjectIdentifier(o))
    }
    // (the bands aren't sections of their own: placed again after this — placeBands)
    for b in old where b !== titleView && !(b is PageBand) && !kept.contains(ObjectIdentifier(b)) && !blocks.contains(where: { $0 === b }) { b.removeFromSuperview() }
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

  private func makeMenu() {
    guard let m = model else { return }
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
      items.append(UIMenu(options: .displayInline, children: [UIAction(title: "Delete task", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete() }]))
    }
    cornerMenu = UIMenu(children: items)
    onMenuMade?()
  }
  private var ownFileIds = Set<String>()
  private func confirmRemove(_ f: [String: Any]) {
    guard let fid = f["id"] as? String else { return }
    let a = UIAlertController(title: "Remove “\(f["name"] as? String ?? "this file")”?", message: "It goes to the Trash.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "removeFile", "id": self.taskId, "value": fid]) })
    present(a)
  }
  private func confirmDelete() {
    let a = UIAlertController(title: "Delete this task?", message: "It goes to the Trash.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "delete", "id": self.taskId]) })
    present(a)
  }
  func present(_ vc: UIViewController) {
    var top = window?.rootViewController
    while let p = top?.presentedViewController { top = p }
    top?.present(vc, animated: true)
  }

  // the rows: built as views, laid out top to bottom
  private var blocks: [UIView] = []
  private var heights: [CGFloat] = []
  /* View only for everyone, the basics (Haris, 2026-11-01: "no one uses an iOS app to do the full process" — the
     Comments stay complete): title, notes, status / CD status, assignees with their ticks, dates, priority, client,
     description, checklist, subtasks, files (open to look at). Nothing on Details is changed from the phone. */
  static let viewOnly = true
  // Full screen, no cards (Haris, 2026-11-02, from ClickUp's page): everything on one line 20 from the screen's edge —
  // the title, the rows' icons, the section headings, the description, the files; sections split by a thin grey band
  static let M: CGFloat = 20
  // the text: 16, as ClickUp's (rows, values, the description, section headings) — Haris 2026-11-02, side by side
  static let T: CGFloat = 16
  static func basic(_ m0: [String: Any]) -> [String: Any] {
    guard viewOnly else { return m0 }
    var m = m0
    for k in ["creator", "parts", "tags", "channels", "clientApproval", "activity", "complete", "review2", "kids"] { m[k] = nil }   // (Guardian and Task Update show — Haris; and Needs CD review, switched by whoever's role allows it — Haris 2026-11-06)
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
    // (the sections as they are now — the ones that come out the same are kept as they are, Haris 2026-11-03)
    let oldBlocks = blocks
    blocks = []
    let ro = (m["readOnly"] as? Bool) == true
    // the head: subtask of… / the title (edited in place, looks the same)
    if let p = m["parent"] as? [String: Any], let pid = p["id"] as? String {
      blocks.append(linkLine("Subtask of " + (p["title"] as? String ?? ""), sym: "arrow.turn.left.up") { [weak self] in self?.onOpen?(pid) })
    }
    if !typing { titleView.text = m["title"] as? String ?? "" }
    titleView.isEditable = (m["canTitle"] as? Bool) == true
    titleView.textColor = (m["done"] as? Bool) == true ? .secondaryLabel : .label
    blocks.append(titleView)
    if let c = m["completed"] as? [String: Any] {
      var t = "Completed" + ((c["label"] as? String).map { $0.isEmpty ? "" : " on " + $0 } ?? "") + " — read only."
      if let left = c["left"] as? Int { t += " Goes to the Trash in \(left) day\(left == 1 ? "" : "s")." }
      var btns: [(String, () -> Void)] = []
      if (c["canFrom"] as? Bool) == true { btns.append(("New task from this", { [weak self] in guard let self = self else { return }; self.onEvent?(["ev": "from", "id": self.taskId]) })) }
      if (c["canReopen"] as? Bool) == true { btns.append(("Reopen", { [weak self] in guard let self = self else { return }; self.onAct?(["act": "reopen", "id": self.taskId]) })) }
      blocks.append(note(sym: "checkmark.circle.fill", tint: .systemGreen, text: t, buttons: btns))
    }
    if let tn = m["trashNote"] as? String { blocks.append(note(sym: "trash", tint: .systemRed, text: tn, buttons: [])) }
    if let l = m["lock"] as? [String: Any] {
      var btns: [(String, () -> Void)] = []
      if (l["from"] as? Bool) == true { btns.append(("New task from this", { [weak self] in guard let self = self else { return }; self.onEvent?(["ev": "from", "id": self.taskId]) })) }
      blocks.append(note(sym: "lock.fill", tint: .systemOrange, text: l["text"] as? String ?? "", buttons: btns))
    }
    if let b = m["basedOn"] as? [String: Any], let bid = b["id"] as? String {
      blocks.append(linkLine("New task from " + (b["title"] as? String ?? ""), sym: "link") { [weak self] in self?.onOpen?(bid) })
    }
    for k in (m["kids"] as? [[String: Any]]) ?? [] { if let kid = k["id"] as? String { blocks.append(linkLine("New task from this: " + (k["title"] as? String ?? ""), sym: "arrow.turn.down.right") { [weak self] in self?.onOpen?(kid) }) } }
    // ---- the main group ----
    var g: [UIView] = []
    if let s = m["status"] as? [String: Any] { g.append(statusRow(s)) }
    if let cd = m["cd"] as? [String: Any] {
      let chip = pill((cd["check"] as? Bool) == true ? "✓ " + (cd["label"] as? String ?? "") : cd["label"] as? String ?? "", fg: .white, bg: TaskPage.rgb(cd["rgb"]))
      g.append(row(sym: "checkmark.shield", key: "CD status", value: chip))
    }
    if let c = m["creator"] as? [String: Any], let cid = c["id"] as? String {
      g.append(row(sym: "pencil", key: "Created by", value: personLine(cid, extra: (c["when"] as? String).map { " · " + $0 } ?? "")))
    }
    let asg = (m["assignees"] as? [[String: Any]]) ?? []
    let canAsg = (m["canAssign"] as? Bool) == true
    g.append(row(sym: "person", key: "Assignees", value: asg.isEmpty ? greyText(canAsg ? "Add" : "Nobody yet") as UIView : avatars(asg), chevron: canAsg, tap: canAsg ? { [weak self] in self?.pickPeople() } : nil))
    if let p = m["parts"] as? [String: Any] { g.append(partsRow(p)) }
    if let d = m["dates"] as? [String: Any] { g.append(datesRow(d)) }
    if let pr = m["prio"] as? [[String: Any]] { g.append(contentsOf: prioRows(pr, can: (m["canPrio"] as? Bool) == true)) }
    // Guardian and Finance, above Client (Haris 2026-11-02): each changed by whoever's role allows it
    let canGd = (m["canGuardian"] as? Bool) == true
    if let gd = m["guardian"] as? String { g.append(row(sym: "star", key: "Guardian", value: personLine(gd, extra: ""), chevron: canGd, tap: canGd ? { [weak self] in self?.pickGuardian() } : nil)) }
    else if canGd { g.append(row(sym: "star", key: "Guardian", value: greyText("None"), chevron: true, tap: { [weak self] in self?.pickGuardian() })) }
    if let fin = m["finance"] as? [String: Any] {
      let cur = fin["v"] as? String ?? ""
      let canFin = (m["canFinance"] as? Bool) == true
      let v: UIView = cur.isEmpty ? greyText(canFin ? "None" : "–") : pill(cur, fg: TaskPage.rgb(fin["rgb"]), bg: TaskPage.rgb(fin["rgb"]).withAlphaComponent(0.16))
      g.append(row(sym: "dollarsign.circle", key: "Finance", value: v, chevron: canFin, tap: canFin ? { [weak self] in self?.pickFinance(cur) } : nil))
    }
    if (m["sub"] as? Bool) != true {
      let c = m["client"] as? [String: Any]
      let v = UIStackView(); v.axis = .horizontal; v.spacing = 6; v.alignment = .center
      if let c = c { let d = UIView(); d.backgroundColor = TaskPage.rgb(c["rgb"]); d.layer.cornerRadius = 4; d.widthAnchor.constraint(equalToConstant: 9).isActive = true; d.heightAnchor.constraint(equalToConstant: 9).isActive = true; v.addArrangedSubview(d) }
      v.addArrangedSubview(label(c?["name"] as? String ?? "No client", size: TaskPage.T, color: .secondaryLabel))
      if m["lock"] is [String: Any] { v.addArrangedSubview(symbol("lock.fill", 12, .secondaryLabel)) }
      let canCl = (m["canClient"] as? Bool) == true
      g.append(row(sym: "square.grid.2x2", key: "Client", value: v, chevron: canCl, tap: canCl ? { [weak self] in self?.pickClient() } : nil))
    }
    let tags = (m["tags"] as? [[String: Any]]) ?? []
    let canTags = (m["canTags"] as? Bool) == true
    if !tags.isEmpty || canTags { g.append(row(sym: "tag", key: "Tags", value: tags.isEmpty ? greyText("Add") as UIView : chips(tags.map { ($0["t"] as? String ?? "", TaskPage.rgb($0["rgb"])) }), chevron: canTags, tap: canTags ? { [weak self] in self?.pickTags() } : nil)) }
    let ch = (m["channels"] as? [String]) ?? []
    let canCh = (m["canChannels"] as? Bool) == true
    if !ch.isEmpty || canCh { g.append(row(sym: "paperplane", key: "Channels", value: label(ch.isEmpty ? "None" : ch.joined(separator: " · "), size: TaskPage.T, color: .secondaryLabel), chevron: canCh, tap: canCh ? { [weak self] in self?.pickChannels() } : nil)) }
    // (view only: the Task Update under Status)
    let canUp = (m["canFields"] as? Bool) == true
    if TaskPage.viewOnly, (m["sub"] as? Bool) != true, m["update"] is [String: Any] || canUp { g.insert(updateRow(m["update"] as? [String: Any], all: (m["updates"] as? [String]) ?? [], can: canUp), at: min(g.count, 1)) }
    blocks.append(group(g))
    // ---- Review ----
    var r: [UIView] = []
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
        self.onAct?(["act": "needsCD", "id": self.taskId, "value": sw.isOn])
      }, for: .valueChanged)
      let who = rv["who"] as? String ?? ""   // (the CD's name — or the Acting CD's — on and off: Haris 2026-11-06)
      r.append(row(sym: "checkmark.shield", key: "Needs CD review", sub: who.isEmpty ? nil : who, value: sw))
    }
    if let ca = m["clientApproval"] as? [String: Any] { r.append(clientApprovalRow(ca)) }
    if (m["sub"] as? Bool) != true && !TaskPage.viewOnly { r.append(updateRow(m["update"] as? [String: Any], all: (m["updates"] as? [String]) ?? [], can: (m["canFields"] as? Bool) == true)) }
    if !r.isEmpty { blocks.append(header("Review")); blocks.append(group(r)) }
    // ---- Description ----
    let desc = m["desc"] as? String ?? ""
    let canDesc = (m["canDesc"] as? Bool) == true
    // (no description, view only: "Add description…" for whoever may write one — tapped, written right there — and
    //  "No description" in grey for everyone else; Haris 2026-11-02)
    // (and whoever may change it writes right in it — tapped, the keyboard; a long one shows its first lines with an
    //  Expand button, once: expanded, it stays so — Haris 2026-11-02)
    let noDesc = desc.isEmpty && ((m["descFiles"] as? [[String: Any]]) ?? []).isEmpty
    let rich: NSAttributedString = {
      let r = DescEditor.attributed((m["descRuns"] as? [[String: Any]]) ?? [], done: (m["done"] as? Bool) == true, size: TaskPage.T, creator: ((model?["creator"] as? [String: Any])?["id"] as? String))
      return r.length > 0 || !noDesc && desc.isEmpty ? r : NSAttributedString(string: desc, attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.label])
    }()
    if TaskPage.viewOnly && (canDesc || editingDesc) {
      let tv = descView
      if !editingDesc { tv.attributedText = desc.isEmpty ? NSAttributedString(string: "Add description…", attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.tertiaryLabel]) : rich }
      descEmpty = desc.isEmpty
      tv.isEditable = true
      descBox.hold(tv); blocks.append(descBox); descStripAfter(m)
    } else if TaskPage.viewOnly && noDesc {
      descRead.attributedText = NSAttributedString(string: "No description", attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.tertiaryLabel])
      descBox.hold(descRead); blocks.append(descBox)
    } else if TaskPage.viewOnly && rich.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
      descRead.attributedText = rich
      descBox.hold(descRead); blocks.append(descBox); descStripAfter(m)
    }
    if !TaskPage.viewOnly && (!desc.isEmpty || canDesc || editingDesc) {
      blocks.append(header("Description", lock: m["lock"] is [String: Any]))
      // (edited right where it is, looking the same — DescEditor.swift)
      let tv = descView
      if !editingDesc { tv.attributedText = desc.isEmpty ? NSAttributedString(string: "Add a description… Type @ to mention someone", attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.tertiaryLabel]) : DescEditor.attributed((m["descRuns"] as? [[String: Any]]) ?? [], done: (m["done"] as? Bool) == true, size: TaskPage.T, creator: ((model?["creator"] as? [String: Any])?["id"] as? String)) }
      descEmpty = desc.isEmpty
      tv.isEditable = canDesc
      blocks.append(group([pad(tv)]))
    }
    // ---- Subtasks ----
    let subs = (m["subtasks"] as? [[String: Any]]) ?? []
    let canAddSub = (m["canAddSub"] as? Bool) == true
    if !subs.isEmpty || canAddSub {
      blocks.append(header(subs.isEmpty ? "Subtasks" : "Subtasks · \(subs.filter { ($0["done"] as? Bool) == true }.count)/\(subs.count)"))
      var rows = subs.map { subRow($0, ro: ro) }
      if canAddSub { rows.append(addRow("Add subtask") { [weak self] in self?.askText("Add subtask", placeholder: "Subtask name") { v in guard let self = self else { return }; self.onAct?(["act": "addSub", "id": self.taskId, "value": v]) } }) }
      blocks.append(group(rows))
    }
    // ---- Checklist ----
    let cl = (m["checklist"] as? [[String: Any]]) ?? []
    let canAddCheck = (m["canAddCheck"] as? Bool) == true
    if !cl.isEmpty || canAddCheck {
      blocks.append(header(cl.isEmpty ? "Checklist" : "Checklist · \(cl.filter { ($0["done"] as? Bool) == true }.count)/\(cl.count)"))
      var rows = cl.map { checkRow($0, can: (m["canCheck"] as? Bool) == true) }
      if canAddCheck { rows.append(addRow("Add checklist item") { [weak self] in self?.askText("Add checklist item", placeholder: "Item") { v in guard let self = self else { return }; self.onAct?(["act": "addCheck", "id": self.taskId, "value": v]) } }) }
      blocks.append(group(rows))
    }
    // ---- the description, view only: straight on the page like the title, in the body size, above Files — no box,
    //      no heading (Haris, 2026-11-01) ----
    // (shown above, in its box)
    // (files pasted into the description: the same cards as comments' — tapped, the preview with them)
    // (now straight under the description — Haris 2026-11-02 — set up there)
    // ---- Files ---- the task's and the comments' together, one row of cards that scrolls sideways (Haris, 2026-11-02)
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
      blocks.append(header(files.isEmpty ? "Files" : "Files · \(files.count)", sym: UIImage(systemName: "photo.stack") != nil ? "photo.stack" : "photo.on.rectangle"))   // (Haris chose photo.stack, 2026-11-02)
      var fr: [UIView] = []
      let real = shown.filter { ($0["pending"] as? Bool) != true }
      let at: (Int) -> Int = { i in real.firstIndex { ($0["id"] as? String) == (shown[i]["id"] as? String) } ?? 0 }
      ownFileIds = canAttach ? Set(own.compactMap { $0["id"] as? String }) : []
      filesStrip.set(shown, settle: settle, open: { [weak self] i in self?.onOpenFiles?(real, at(i)) }, menu: { [weak self] i in self?.fileMenu(real, at(i)) })
      if !shown.isEmpty { fr.append(pad(filesStrip, right: 0)) }
      if canAttach { fr.append(addRow("Attach Files") { [weak self] in self?.attachSheet() }) }
      let fg = group(fr); filesBlock = fg
      blocks.append(fg)
    }
    // ---- Activity ----
    let act = (m["activity"] as? [[String: Any]]) ?? []
    if !act.isEmpty {
      blocks.append(header("Activity"))
      let lines = act.prefix(12).map { a -> UIView in
        let who = (a["who"] as? String).map { name($0) } ?? "Someone"
        let s = NSMutableAttributedString(string: who, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.label])
        s.append(NSAttributedString(string: " " + (a["text"] as? String ?? ""), attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel]))
        s.append(NSAttributedString(string: " · " + TaskPage.when(a["at"] as? String ?? ""), attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.tertiaryLabel]))
        let l = UILabel(); l.attributedText = s; l.numberOfLines = 0
        return pad(l, v: 9)
      }
      blocks.append(group(lines))
    }
    keepUnchanged(oldBlocks)
    // Mark complete: only when this person may complete it
    if let c = m["complete"] as? [String: Any], (c["show"] as? Bool) == true { fab.isHidden = false } else { fab.isHidden = true }
    layoutContent()
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
      items.append(UIMenu(options: .displayInline, children: [UIAction(title: "Remove", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmRemove(f) }]))
    }
    return UIMenu(title: f["name"] as? String ?? "", children: items)
  }
  // each section's place in the list: across the page or on its edge, its height and the room after it (as the page had
  // them); the list told only when something really changed
  private var listLive = false, listHold = false
  private func layoutContent() {
    let W = bounds.width, M = TaskPage.M
    guard W > 0, !listHold else { return }
    placeBands()
    holdForDesc()
    var keys: [String] = [], views: [String: UIView] = [:], geo: [String: PageCell.Geo] = [:], seen: [String: Int] = [:]
    for (k, b) in blocks.enumerated() {
      // (rows and bands go right across; the files row from the page edge to the screen's; the rest on the page edge)
      let full = b is PageGroup || b is PageBand
      let x: CGFloat = full ? 0 : M, w = full ? W : (b === descStrip ? W - M : W - 2 * M)
      var h: CGFloat
      if b === titleView { h = ceil(titleView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height) }
      else if b is PageBand { h = 8 }
      else {
        if b.bounds.width != w { b.bounds.size.width = w }
        b.setNeedsLayout(); b.layoutIfNeeded()
        h = b.systemLayoutSizeFitting(CGSize(width: w, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
      }
      h = ceil(h)
      let next = k + 1 < blocks.count ? blocks[k + 1] : nil
      let gap: CGFloat = (b is PageBand || next is PageBand ? (b is PageBand ? 10 : 6) : b.tag == 7 ? 4 : b is PageGroup ? 4 : 10)
      let base = listKey(b, next: next)
      let n = seen[base, default: 0]; seen[base] = n + 1
      let key = n == 0 ? base : base + "#\(n)"
      keys.append(key); views[key] = b
      geo[key] = PageCell.Geo(x: x, w: w, h: h, gap: gap, top: b === titleView ? 2 : 0)
    }
    let bottom = max(safeAreaInsets.bottom, 20) + (fab.isHidden ? 16 : 72)
    let inset = max(bottom, coverNow() + 16)
    if scroll.contentInset.bottom != inset { scroll.contentInset.bottom = inset }
    // (what changed: the order, a section put in place of another under the same key, or a height)
    let changed = keys.filter { k in listViews[k] !== views[k] || listGeo[k] != geo[k] }
    let same = keys == listKeys && changed.isEmpty
    listViews = views; listGeo = geo
    if same { return }
    let order = keys != listKeys
    listKeys = keys
    guard let ds = listDS else { return }
    scroll.collectionViewLayout.invalidateLayout()   // (the places as they are now)
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    snap.appendSections([0]); snap.appendItems(keys, toSection: 0)
    let had = Set(ds.snapshot().itemIdentifiers)
    snap.reconfigureItems(changed.filter { had.contains($0) })
    // (inside an animation of its own — the description growing — Apple's list goes along with it)
    let animated = order ? listLive : (listLive || UIView.inheritedAnimationDuration > 0)
    ds.apply(snap, animatingDifferences: animated && window != nil)
  }
  // Apple's list laid out with each section's exact place — its height known, nothing guessed and corrected as it comes
  // into sight (Haris 2026-11-08: a section reaching the bottom edge came in squeezed and then grew, as the long sheets'
  // last row once did)
  private func makeListLayout() -> UICollectionViewLayout {
    UICollectionViewCompositionalLayout { [weak self] _, env in
      let W = env.container.contentSize.width
      var frames: [NSCollectionLayoutGroupCustomItem] = [], y: CGFloat = 0
      for k in self?.listKeys ?? [] {
        let h = self?.listGeo[k].map { $0.top + $0.h + $0.gap } ?? 1
        frames.append(NSCollectionLayoutGroupCustomItem(frame: CGRect(x: 0, y: y, width: W, height: h)))
        y += h
      }
      let group = NSCollectionLayoutGroup.custom(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(max(y, 1)))) { _ in frames }
      return NSCollectionLayoutSection(group: group)
    }
  }
  // a section's key: what it is (the title, the description, a heading's words, a row group by its first row…); a band by
  // what comes after it, so it goes with it
  private func listKey(_ b: UIView, next: UIView?) -> String {
    if b === titleView { return "title" }
    if b is DescBox { return "desc" }
    if b === descStrip { return "dstrip" }
    if b is PageBand { return "band>" + (next.map { listKey($0, next: nil) } ?? "end") }
    return blockKey(b)
  }
  var kbCover: CGFloat = 0
  private func keyboardMoved(_ n: Notification) {
    guard let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue, window != nil else { return }
    let mine = convert(bounds, to: nil)
    kbCover = max(0, mine.maxY - f.minY)
    setNeedsLayout()
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

  // a thin grey band before each section (a heading), and before the description — none at the top, never two together
  // (each band kept by what comes after it — the same band stays with its section; Haris 2026-11-08: bands handed round by
  //  position were taken off the page on a redraw, coming back from another app, and didn't come back)
  private var bands: [String: PageBand] = [:]
  var bandsShown: Int { bands.values.filter { $0.window != nil }.count }   // (the self-test: the bands still on the page)
  private func placeBands() {
    blocks.removeAll { $0 is PageBand }
    var out: [UIView] = [], used = Set<String>()
    for b in blocks {
      let isDesc = b is DescBox
      let heading = b is PageHeading
      if heading || isDesc, let prev = out.last, !(prev is PageBand), prev !== titleView {
        var k = listKey(b, next: nil), n = 1
        while used.contains(k) { k = listKey(b, next: nil) + "#\(n)"; n += 1 }
        used.insert(k)
        let band = bands[k] ?? PageBand(); bands[k] = band
        out.append(band)
      }
      out.append(b)
    }
    for (k, b) in bands where !used.contains(k) { b.removeFromSuperview(); bands[k] = nil }
    blocks = out
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
  private func header(_ t: String, lock: Bool = false, sym: String? = nil) -> UIView {
    let l = label(t, size: TaskPage.T, color: .secondaryLabel)
    let s = PageHeading(arrangedSubviews: sym.map { [symbol($0, 14, .secondaryLabel), l] } ?? [l]); s.spacing = 5; s.alignment = .center
    if lock { s.addArrangedSubview(symbol("lock.fill", 10, .secondaryLabel)) }
    s.addArrangedSubview(UIView())
    s.isLayoutMarginsRelativeArrangement = true
    s.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
    s.tag = 7   // (closer to its group)
    return s
  }
  private func pad(_ v: UIView, v vv: CGFloat = 12, right: CGFloat = TaskPage.M) -> UIView {
    let b = UIView(); v.translatesAutoresizingMaskIntoConstraints = false; b.addSubview(v)
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: TaskPage.M), v.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -right), v.topAnchor.constraint(equalTo: b.topAnchor, constant: vv), v.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -vv)])
    return b
  }
  // a rounded group of rows with thin lines between them (as iPhone's Settings)
  private func group(_ rows: [UIView]) -> UIView {
    let g = PageGroup(); g.axis = .vertical   // (full width, on the page itself — no card)
    for (i, r) in rows.enumerated() {
      if i > 0 {
        let line = UIView(); line.backgroundColor = .separator
        let wrap = UIView(); wrap.addSubview(line); line.translatesAutoresizingMaskIntoConstraints = false; wrap.layer.name = "k:sep"
        NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: TaskPage.M + 36), line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor), line.topAnchor.constraint(equalTo: wrap.topAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale), wrap.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)])
        g.addArrangedSubview(wrap)
      }
      g.addArrangedSubview(r)
    }
    return g
  }
  // icon · name (· a small line under it) · value · › (only when it can be changed)
  private func row(sym: String, key: String, sub: String? = nil, value: UIView?, chevron: Bool = false, keyLines: Int = 1, tap: (() -> Void)? = nil, menu: UIMenu? = nil) -> UIView {
    let r = TaskRow()
    let ic = symbol(sym, 16, .secondaryLabel)
    ic.translatesAutoresizingMaskIntoConstraints = false
    let k = label(key, size: TaskPage.T, color: .secondaryLabel); k.numberOfLines = keyLines   // (the names in their icons' grey — Haris, 2026-11-02)
    k.setContentCompressionResistancePriority(.defaultHigh + 1, for: .horizontal)
    let left = UIStackView(arrangedSubviews: [k]); left.axis = .vertical; left.spacing = 2
    if let sub = sub { let s = label(sub, size: 13, color: .secondaryLabel); s.numberOfLines = 2; left.addArrangedSubview(s) }
    let h = UIStackView(); h.axis = .horizontal; h.alignment = .center; h.spacing = 10
    h.addArrangedSubview(left)
    let spacer = UIView(); spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal); h.addArrangedSubview(spacer)
    if let v = value { v.setContentHuggingPriority(.required, for: .horizontal); h.addArrangedSubview(v) }
    if chevron { h.addArrangedSubview(symbol("chevron.right", 13, .tertiaryLabel, weight: .semibold)) }
    h.translatesAutoresizingMaskIntoConstraints = false
    r.addSubview(ic); r.addSubview(h)
    NSLayoutConstraint.activate([
      ic.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: TaskPage.M), ic.widthAnchor.constraint(equalToConstant: 24), ic.centerYAnchor.constraint(equalTo: r.centerYAnchor),
      h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: TaskPage.M + 36), h.trailingAnchor.constraint(equalTo: r.trailingAnchor, constant: -TaskPage.M),
      h.topAnchor.constraint(equalTo: r.topAnchor, constant: 11), h.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -11),
      r.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
    ])
    r.onTap = tap
    if let menu = menu { r.attachMenu(menu) }
    return r
  }
  private func pill(_ t: String, fg: UIColor, bg: UIColor) -> UIView {
    let l = PaddedLabel(); l.text = t; l.font = .systemFont(ofSize: 14, weight: .semibold); l.textColor = fg; l.backgroundColor = bg
    l.layer.cornerRadius = 9; l.layer.cornerCurve = .continuous; l.clipsToBounds = true; l.insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    return l
  }
  private func chips(_ list: [(String, UIColor)]) -> UIView {
    let s = UIStackView(); s.spacing = 6; s.alignment = .center
    for (t, c) in list.prefix(3) { s.addArrangedSubview(pill(t, fg: c, bg: c.withAlphaComponent(0.16))) }
    if list.count > 3 { s.addArrangedSubview(greyText("+\(list.count - 3)")) }
    return s
  }
  func name(_ id: String) -> String { (people[id]?["first"] as? String) ?? "Someone" }
  private func avatar(_ id: String, _ side: CGFloat, ring: Bool = false) -> UIView {
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
    if ring { v.layer.borderWidth = 2; v.layer.borderColor = UIColor.secondarySystemGroupedBackground.cgColor }
    return v
  }
  private func personLine(_ id: String, extra: String) -> UIView {
    let s = UIStackView(arrangedSubviews: [avatar(id, 24), greyText(((people[id]?["name"] as? String).map { id == (model?["me"] as? String) ? "You" : $0 } ?? name(id)) + extra)])
    s.spacing = 7; s.alignment = .center
    return s
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
      let v = avatar(id, 30, ring: true)
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
      if (a["done"] as? Bool) == true {
        let tick = symbol("checkmark.circle.fill", 13, .systemGreen, weight: .bold)
        tick.backgroundColor = .secondarySystemGroupedBackground; tick.layer.cornerRadius = 7; tick.clipsToBounds = true
        let w = UIView(); w.translatesAutoresizingMaskIntoConstraints = false
        w.widthAnchor.constraint(equalToConstant: 30).isActive = true; w.heightAnchor.constraint(equalToConstant: 30).isActive = true
        w.addSubview(v); v.leadingAnchor.constraint(equalTo: w.leadingAnchor).isActive = true; v.topAnchor.constraint(equalTo: w.topAnchor).isActive = true
        tick.frame = CGRect(x: 18, y: 18, width: 14, height: 14); w.addSubview(tick)
        s.addArrangedSubview(w)
      } else { s.addArrangedSubview(v) }
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
  private func statusRow(_ s: [String: Any]) -> UIView {
    let can = (s["canSet"] as? Bool) == true
    let v = pill(s["name"] as? String ?? "", fg: .white, bg: TaskPage.rgb(s["rgb"]))
    let why = s["why"] as? String ?? ""
    return row(sym: "circle.lefthalf.filled", key: "Status", sub: why.isEmpty ? nil : why, value: v, chevron: can, tap: can ? { [weak self] in self?.pickStatus(s) } : nil)
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
  private func partsRow(_ p: [String: Any]) -> UIView {
    let chipsV = UIStackView(); chipsV.spacing = 6; chipsV.alignment = .center
    for c in ((p["chips"] as? [[String: Any]]) ?? []).prefix(3) {
      let done = (c["done"] as? Bool) == true, pend = (c["pending"] as? Bool) == true
      let col: UIColor = done ? .systemGreen : pend ? .systemOrange : .secondaryLabel
      chipsV.addArrangedSubview(pill((c["name"] as? String ?? "") + (done ? " ✓" : pend ? " · review" : ""), fg: col, bg: col.withAlphaComponent(0.14)))
    }
    let n = p["n"] as? Int ?? 0, of = p["of"] as? Int ?? 0
    let r = row(sym: "circle.dotted.circle", key: "Parts", sub: "\(n)/\(of) done", value: chipsV)
    // files for the CD (an assignee on a task that needs CD review): Submit / Withdraw (dm-mock 2, 3)
    if let rv = model?["review2"] as? [String: Any], let st = rv["state"] as? String, st != "approved" {
      let wrap = UIStackView(arrangedSubviews: [r]); wrap.axis = .vertical
      let pending = st == "pending"
      var c: UIButton.Configuration = pending ? .tinted() : .filled()
      c.cornerStyle = .capsule; c.baseBackgroundColor = pending ? .systemRed : .systemBlue; c.baseForegroundColor = pending ? .systemRed : .white
      if !pending { c.image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)); c.imagePadding = 6 }
      c.attributedTitle = AttributedString(pending ? "Withdraw" : "Submit files for CD review", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16, weight: .semibold)]))
      c.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
      let b = UIButton(configuration: c)
      b.addAction(UIAction { [weak self] _ in
        guard let self = self else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if pending {
          let a = UIAlertController(title: "Withdraw your submission?", message: "The files you sent will be removed so you can upload the right ones.", preferredStyle: .alert)
          a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
          a.addAction(UIAlertAction(title: "Withdraw", style: .destructive) { _ in self.onAct?(["act": "withdrawReview", "id": self.taskId]) })
          self.present(a)
        } else if (rv["canSubmit"] as? Bool) != true { self.toast("Set it to In Progress first") }
        else { self.onSubmitFiles?(rv["cd"] as? String ?? "") }
      }, for: .touchUpInside)
      let bw = UIView(); b.translatesAutoresizingMaskIntoConstraints = false; bw.addSubview(b)
      NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: bw.leadingAnchor, constant: TaskPage.M + 36), b.topAnchor.constraint(equalTo: bw.topAnchor), b.bottomAnchor.constraint(equalTo: bw.bottomAnchor, constant: -12), b.trailingAnchor.constraint(lessThanOrEqualTo: bw.trailingAnchor, constant: -TaskPage.M)])
      wrap.addArrangedSubview(bw)
      return wrap
    }
    guard let mine = p["mine"] as? String, mine == "open" || mine == "done" else { return r }
    // Mark my part done / Undo
    let wrap = UIStackView(arrangedSubviews: [r]); wrap.axis = .vertical
    var c: UIButton.Configuration = mine == "done" ? .tinted() : .filled()
    c.cornerStyle = .capsule
    c.baseBackgroundColor = .systemGreen
    c.baseForegroundColor = mine == "done" ? .systemGreen : .white
    c.image = UIImage(systemName: mine == "done" ? "checkmark.circle.fill" : "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)); c.imagePadding = 6
    c.attributedTitle = AttributedString(mine == "done" ? "My part is done · Undo" : "Mark my part done", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16, weight: .semibold)]))
    c.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    let b = UIButton(configuration: c)
    b.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      if mine == "open" { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      self.onAct?(["act": "myPart", "id": self.taskId, "value": mine == "open"])
    }, for: .touchUpInside)
    let bw = UIView(); b.translatesAutoresizingMaskIntoConstraints = false; bw.addSubview(b)
    NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: bw.leadingAnchor, constant: TaskPage.M + 36), b.topAnchor.constraint(equalTo: bw.topAnchor), b.bottomAnchor.constraint(equalTo: bw.bottomAnchor, constant: -12), b.trailingAnchor.constraint(lessThanOrEqualTo: bw.trailingAnchor, constant: -TaskPage.M)])
    wrap.addArrangedSubview(bw)
    return wrap
  }
  private func datesRow(_ d: [String: Any]) -> UIView {
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
    return row(sym: "calendar", key: "Dates", value: s)
  }
  private func prioRows(_ list: [[String: Any]], can: Bool) -> [UIView] {
    list.map { p in
      let key = p["key"] as? String ?? "_", lab = p["label"] as? String ?? ""
      let v: UIView = lab.isEmpty ? greyText(can ? "None" : "–") : lab == "Urgent" ? pill("Urgent", fg: .systemRed, bg: UIColor.systemRed.withAlphaComponent(0.15)) : pill(lab, fg: .label, bg: .tertiarySystemFill)
      let who = p["name"] as? String ?? ""
      let plain = who.isEmpty || list.count == 1 && key == (model?["me"] as? String)
      let r = row(sym: "flag", key: plain ? "Priority" : "Priority · " + who, value: v, chevron: can, tap: can ? { [weak self] in self?.pickPrio(p) } : nil)
      // (whose priority it is in blue, as the date — Haris, 2026-11-02)
      if !plain, let k = findKey(r, "Priority · " + who) {
        let a = NSMutableAttributedString(string: "Priority · ", attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.secondaryLabel])
        a.append(NSAttributedString(string: who, attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.systemBlue]))
        k.attributedText = a
      }
      return r
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
  private func findKey(_ v: UIView, _ t: String) -> UILabel? {
    if let l = v as? UILabel, l.text == t { return l }
    for s in v.subviews { if let l = findKey(s, t) { return l } }
    return nil
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
  private func clientApprovalRow(_ ca: [String: Any]) -> UIView {
    let state = ca["state"] as? String ?? "missing", text = ca["text"] as? String ?? ""
    let col: UIColor = state == "yes" ? .systemGreen : state == "none" ? .secondaryLabel : .systemOrange
    let v: UIView = state == "none" ? greyText(text) : pill(text, fg: col, bg: col.withAlphaComponent(0.15))
    var menu: UIMenu?
    if (ca["canSet"] as? Bool) == true {
      var items: [UIMenuElement] = [
        UIAction(title: "Client approved", image: UIImage(systemName: "checkmark.circle"), state: state == "yes" ? .on : .off) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "clientApproval", "id": self.taskId, "value": "yes"]) },
        UIAction(title: "Not needed", state: state == "none" ? .on : .off) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "clientApproval", "id": self.taskId, "value": "none"]) },
      ]
      if state == "yes" || state == "none" { items.append(UIMenu(options: .displayInline, children: [UIAction(title: "Clear", attributes: .destructive) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "clientApproval", "id": self.taskId, "value": "clear"]) }])) }
      menu = UIMenu(title: "Client approval", children: items)
    }
    return row(sym: "person.2", key: "Client approval", sub: "After the CD’s approval, before Done", value: v, chevron: menu != nil, menu: menu)
  }
  private func updateRow(_ u: [String: Any]?, all: [String], can: Bool) -> UIView {
    let cur = u?["t"] as? String ?? ""
    let v: UIView = cur.isEmpty ? greyText(can ? "None" : "–") : pill(cur, fg: TaskPage.rgb(u?["rgb"]), bg: TaskPage.rgb(u?["rgb"]).withAlphaComponent(0.16))
    return row(sym: "arrow.triangle.2.circlepath", key: "Task Update", value: v, chevron: can, tap: can ? { [weak self] in self?.pickUpdate(all, cur: cur) } : nil)
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
  private func subRow(_ s: [String: Any], ro: Bool) -> UIView {
    let id = s["id"] as? String ?? "", done = (s["done"] as? Bool) == true
    let r = TaskRow(); r.layer.name = "k:sub:" + id
    let tick = UIButton(type: .custom)
    tick.setImage(UIImage(systemName: done ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)), for: .normal)
    tick.tintColor = done ? .systemGreen : .tertiaryLabel
    tick.isEnabled = (s["canTick"] as? Bool) == true
    tick.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      if !done { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      self.onAct?(["act": done ? "reopen" : "done", "id": id, "page": self.taskId])
    }, for: .touchUpInside)
    let t = label(s["title"] as? String ?? "", size: TaskPage.T, color: done ? .secondaryLabel : .label)
    if done { t.attributedText = NSAttributedString(string: t.text ?? "", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: TaskPage.T)]) }
    t.lineBreakMode = .byTruncatingTail
    let h = UIStackView(arrangedSubviews: [tick, t]); h.spacing = 12; h.alignment = .center
    // (the name starts right after the circle and takes the room; the circle, picture, date and › keep their size)
    tick.setContentHuggingPriority(.required, for: .horizontal); tick.widthAnchor.constraint(equalToConstant: 26).isActive = true
    t.textAlignment = .natural
    t.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
    t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    if let av = s["av"] as? String { h.addArrangedSubview(avatar(av, 22)) }
    if let due = s["due"] as? String, !due.isEmpty { h.addArrangedSubview(label(due, size: 15, color: (s["late"] as? Bool) == true ? .systemRed : .secondaryLabel)) }
    h.addArrangedSubview(symbol("chevron.right", 13, .tertiaryLabel, weight: .semibold))
    h.translatesAutoresizingMaskIntoConstraints = false; r.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: TaskPage.M - 2), h.trailingAnchor.constraint(equalTo: r.trailingAnchor, constant: -TaskPage.M), h.topAnchor.constraint(equalTo: r.topAnchor, constant: 9), h.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -9), r.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)])
    r.onTap = { [weak self] in self?.onOpen?(id) }
    return r
  }
  private func checkRow(_ c: [String: Any], can: Bool) -> UIView {
    let id = c["id"] as? String ?? "", done = (c["done"] as? Bool) == true
    let r = TaskRow(); r.layer.name = "k:chk:" + id
    let box = symbol(done ? "checkmark.square.fill" : "square", 20, done ? .systemBlue : .tertiaryLabel)
    let t = label(c["text"] as? String ?? "", size: TaskPage.T, color: done ? .secondaryLabel : .label); t.numberOfLines = 0
    if done { t.attributedText = NSAttributedString(string: t.text ?? "", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: TaskPage.T)]) }
    let h = UIStackView(arrangedSubviews: [box, t]); h.spacing = 12; h.alignment = .center
    h.translatesAutoresizingMaskIntoConstraints = false; r.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: TaskPage.M), h.trailingAnchor.constraint(equalTo: r.trailingAnchor, constant: -TaskPage.M), h.topAnchor.constraint(equalTo: r.topAnchor, constant: 13), h.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -13)])
    if can {
      r.onTap = { [weak self, weak box] in
        guard let self = self else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        // (ticked at once; the server's answer redraws it)
        box?.image = UIImage(systemName: done ? "square" : "checkmark.square.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)); box?.tintColor = done ? .tertiaryLabel : .systemBlue
        self.onAct?(["act": "check", "id": self.taskId, "value": id])
      }
    }
    return r
  }

  // ---------- the sheets: people, tags, channels; a line of text ----------
  private func addRow(_ t: String, tap: @escaping () -> Void) -> UIView {
    let r = TaskRow()
    let h = UIStackView(arrangedSubviews: [symbol("plus.circle.fill", 20, .systemBlue), label(t, size: TaskPage.T, color: .systemBlue)]); h.spacing = 12; h.alignment = .center
    h.translatesAutoresizingMaskIntoConstraints = false; r.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: TaskPage.M - 1), h.trailingAnchor.constraint(lessThanOrEqualTo: r.trailingAnchor, constant: -TaskPage.M), h.topAnchor.constraint(equalTo: r.topAnchor, constant: 13), h.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -13)])
    r.onTap = tap
    return r
  }
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

// the task page's pieces: a set of rows right across the page, and the grey band between sections
// one section of a task's Details in Apple's list: the section, placed across the page or on its edge, with the room
// after it as the page had it
final class PageCell: UICollectionViewCell {
  struct Geo: Equatable { var x: CGFloat, w: CGFloat, h: CGFloat, gap: CGFloat, top: CGFloat = 0 }
  private weak var hosted: UIView?
  private var geo = Geo(x: 0, w: 0, h: 1, gap: 0)
  func host(_ v: UIView?, _ g: Geo) {
    geo = g
    backgroundConfiguration = .clear()
    if hosted !== v, let old = hosted, old.superview === contentView { old.removeFromSuperview() }
    hosted = v
    // (put in place at once, with no animation: drawn inside the list's own animation it grew from nothing)
    if let v = v, v.superview !== contentView {
      UIView.performWithoutAnimation { v.transform = .identity; contentView.addSubview(v); v.frame = CGRect(x: g.x, y: g.top, width: g.w, height: g.h) }
    }
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let v = hosted, v.superview === contentView else { return }
    let f = CGRect(x: geo.x, y: geo.top, width: geo.w, height: geo.h)
    if v.frame != f { v.frame = f }
  }
}
final class PageGroup: UIStackView {}
final class PageHeading: UIStackView {}
final class PageBand: UIView {
  override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .secondarySystemBackground; isUserInteractionEnabled = false }
  required init?(coder: NSCoder) { fatalError() }
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
    fade.colors = [UIColor.systemBackground.withAlphaComponent(0).cgColor, UIColor.systemBackground.cgColor]
    var c = UIButton.Configuration.plain(); c.cornerStyle = .capsule
    c.attributedTitle = AttributedString("Expand", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
    c.baseForegroundColor = .label; c.background.backgroundColor = .systemBackground
    c.background.strokeColor = .separator; c.background.strokeWidth = 1
    c.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)
    button.configuration = c
    button.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.expand() }, for: .touchUpInside)
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
    CATransaction.begin(); CATransaction.setDisableActions(true)
    fade.frame = CGRect(x: 0, y: bounds.height - 72, width: w, height: 72)
    fade.colors = [UIColor.systemBackground.withAlphaComponent(0).cgColor, UIColor.systemBackground.cgColor]
    CATransaction.commit()
    let s = button.sizeThatFits(CGSize(width: 200, height: 40))
    button.frame = CGRect(x: (w - s.width) / 2, y: bounds.height - s.height - 6, width: s.width, height: s.height)
    bringSubviewToFront(button)
  }
  // (the size the page gives it: capped while it's a long one not opened)
  override func systemLayoutSizeFitting(_ t: CGSize, withHorizontalFittingPriority h: UILayoutPriority, verticalFittingPriority v: UILayoutPriority) -> CGSize {
    let full = text.map { $0.sizeThatFits(CGSize(width: t.width, height: .greatestFiniteMagnitude)).height } ?? 0
    if text?.isFirstResponder == true { expanded = true }
    let short = !expanded && full > 168 + 40
    return CGSize(width: t.width, height: ceil(short ? 168 : full))
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
