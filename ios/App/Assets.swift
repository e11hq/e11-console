import UIKit

/* Client Assets, the app's own (shell 32 — Haris 2026-11-02, from the approved mockup; "everything at once"):
   1. All Client Assets — Home's big title ("Client Assets", "6 clients · 287 files" under it), the shared 🔍 (every
      client's files) and your photo; the clients as a 2-column grid of cards (logo or colour with initials, name,
      "6 folders · 48 files"); "+ Add client" for those who may.
   2. A client's assets — the task page's bar (‹ · logo and name, "6 folders · 48 files" under it · •••): a search bar
      for its files, Folders as a 2-column grid, Recently added in one inset group (thumbnail, name, type · size, •••).
   3. A folder — the bar with its name and the client under it: its folders, "N files" with Select, the files as a
      3-column grid (tapped: the app's preview; held: Copy, Download, Info, Delete); "↑ Upload" at the bottom right.
   What's in them, and who may do what, comes from the page (phone.js NativeAssets — the website's own rules); each
   change is done there too, the website's way. Screens slide in from the right over the one before; ‹ or the swipe
   from the left edge goes back. */

// ---------- pieces ----------

// a line of words in the list (nothing here yet, a folder's note)
final class AssetsNote: UIView, HomeBlock {
  let label = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    label.font = .systemFont(ofSize: 15); label.textColor = .secondaryLabel; label.numberOfLines = 0; label.textAlignment = .center
    addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }
  func blockHeight(_ W: CGFloat) -> CGFloat { ceil(label.sizeThatFits(CGSize(width: W - 64, height: 400)).height) + 36 }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = bounds.insetBy(dx: 32, dy: 18) }
}

// the search bar for a client's files (as iPhone's own: a grey capsule with the lens)
final class AssetsFind: UIView, HomeBlock, UITextFieldDelegate {
  let field = UISearchTextField()
  var onChange: ((String) -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    field.font = .systemFont(ofSize: 17); field.returnKeyType = .search; field.autocorrectionType = .no
    field.delegate = self
    field.addAction(UIAction { [weak self] _ in self?.onChange?(self?.field.text ?? "") }, for: .editingChanged)
    addSubview(field)
  }
  required init?(coder: NSCoder) { fatalError() }
  func textFieldShouldReturn(_ t: UITextField) -> Bool { t.resignFirstResponder(); return true }
  func blockHeight(_ W: CGFloat) -> CGFloat { 52 }
  override func layoutSubviews() { super.layoutSubviews(); field.frame = CGRect(x: 16, y: 4, width: bounds.width - 32, height: 40) }
}

// a tile that's tapped, or touched and held as the comment cards are (Haris 2026-11-03): the whole card shrinks as one
// from the moment the finger is down (the shared PressShrink); held long enough — the haptic, its sheet slides up, and
// it springs back
class AssetTile: UIControl {
  var onTap: (() -> Void)?
  var onHold: (() -> Void)?
  private var shrink: PressShrink?
  // (a tile that does nothing when tapped — a row of words: no shrink under the finger, no tap)
  var pressable = true { didSet { shrink?.isEnabled = pressable } }
  override init(frame: CGRect) {
    super.init(frame: frame)
    addAction(UIAction { [weak self] _ in guard let self = self, self.pressable, let t = self.onTap else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); t() }, for: .touchUpInside)
    shrink = PressShrink.add(to: self)
    let lp = UILongPressGestureRecognizer(target: self, action: #selector(held(_:))); lp.minimumPressDuration = 0.45
    addGestureRecognizer(lp)
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func held(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began, let h = onHold else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    cancelTracking(with: nil)   // (no tap after the hold)
    h()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.shrink?.release() }
  }
  // (Client Assets' files and folders: touch and hold as Home's task cards — Apple's own lift and its popup menu beside
  //  it, no shrink of ours, no sheet: Haris 2026-11-08 "instead of having slide sheet, make it a popup … same like on
  //  task cards". Set once; other tiles — Me's rows — keep theirs)
  var contextMenu: (() -> UIMenu?)? {
    didSet {
      guard contextMenu != nil, menuHost == nil else { return }
      shrink?.isEnabled = false; shrink.map { removeGestureRecognizer($0) }; shrink = nil
      gestureRecognizers?.filter { $0 is UILongPressGestureRecognizer }.forEach { removeGestureRecognizer($0) }
      // (iPhone's own menu interaction on the tile, as on Home's cards — its delegate apart from the tile: UIControl's own
      //  built-in menu opens as a button's menu, with no shrink and no lift — Haris 2026-11-08)
      let m = TileMenu(); m.tile = self; menuHost = m
      addInteraction(UIContextMenuInteraction(delegate: m))
    }
  }
  private var menuHost: TileMenu?
  // (its size and place set without touching its shrink — setting the frame of a card shrunk while held re-laid its
  //  insides: they moved, as the comment cards' once did)
  func place(_ r: CGRect) { bounds = CGRect(origin: .zero, size: r.size); center = CGPoint(x: r.midX, y: r.midY) }
}

// a Client Assets tile's touch and hold: iPhone's own shrink, lift and menu beside it, as Home's task cards
final class TileMenu: NSObject, UIContextMenuInteractionDelegate {
  weak var tile: AssetTile?
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation p: CGPoint) -> UIContextMenuConfiguration? {
    guard let m = tile?.contextMenu?() else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in m }
  }
  // (the tile itself lifts, with its own rounded corners)
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configuration c: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier id: NSCopying) -> UITargetedPreview? {
    guard let v = tile else { return nil }
    let pp = UIPreviewParameters()
    pp.visiblePath = UIBezierPath(roundedRect: v.bounds, cornerRadius: v.layer.cornerRadius > 0 ? v.layer.cornerRadius : 18)
    pp.backgroundColor = v.backgroundColor ?? .clear
    return UITargetedPreview(view: v, parameters: pp)
  }
}

// Info: iPhone's own grouped list of what it is
final class AssetsInfoVC: UITableViewController {
  private let rows: [(String, String)]
  var openTask: (() -> Void)?   // (a final file whose task is still there: Open task, as the website's)
  init(title: String, rows: [(String, String)]) { self.rows = rows; super.init(style: .insetGrouped); self.title = title }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
  }
  override func numberOfSections(in tv: UITableView) -> Int { openTask == nil ? 1 : 2 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? rows.count : 1 }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    if ip.section == 1 {
      let c = UITableViewCell(style: .default, reuseIdentifier: nil)
      c.textLabel?.text = "Open task"; c.textLabel?.textColor = .systemBlue
      c.imageView?.image = UIImage(systemName: "arrow.up.forward.square"); c.imageView?.tintColor = .systemBlue
      return c
    }
    let c = UITableViewCell(style: .value1, reuseIdentifier: nil)
    c.textLabel?.text = rows[ip.row].0; c.detailTextLabel?.text = rows[ip.row].1
    c.detailTextLabel?.numberOfLines = 2; c.selectionStyle = .none
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard ip.section == 1, let run = openTask else { return }
    dismiss(animated: true) { run() }
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); (navigationController as? FitNav)?.fitTo(tableView) }
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); (navigationController as? FitNav)?.fitTo(tableView) }
}

// ---------- the screens: which are open, what's in them, and what's done there ----------
final class AssetsCtl {
  private unowned let main: Main
  init(_ m: Main) { main = m }
  private struct Screen { let h: HomeView; let kind: String; let client: String?; let folder: String?; var q = ""; var picked: Set<String>? = nil }   // (picked: Select on — the files ticked)
  private var stack: [Screen] = []
  private var models: [String: [String: Any]] = [:]   // (a client's, by its id; "" — all of them)
  private var fromPage = false, rootTab = false
  // (opened on the Clients tab in Apple's navigation — AppleClients.swift: each screen a page pushed there, Apple's push,
  //  bar, swipe back; elsewhere — Me, Client Assets as a tab — as before)
  private(set) var appleNav: UINavigationController?
  private func pickHost() {
    guard APPLE_CLIENTS, let t = AppleTabs.shared else { appleNav = nil; return }
    // (the Clients tab; Client Assets as the Office Admin's tab; anywhere else — Me's — the app's own navigation, Apple's
    //  push over Me: Haris 2026-11-08, mock-up assets-main-mockup.png)
    if t.ownNav === t.clientsNav { appleNav = main.clientsApple ? t.clientsNav : nil }
    else if t.ownNav === t.assetsNav { appleNav = t.assetsNav }
    else if t.ownNav === t.meNav { appleNav = t.meNav }   // (Me in its own Apple navigation — AppleMe.swift: pushed on Me)
    else if t.ownNav == nil { appleNav = main.navigationController }
    else { appleNav = nil }
  }
  // (All Client Assets as the Office Admin's tab: its tab's first screen, not pushed)
  private var tabRoot: HomeView? { appleNav != nil && appleNav === AppleTabs.shared?.assetsNav ? AssetsTabVC.shared?.h : nil }
  private weak var pushingVC: AssetsVC?
  private func appleVC(_ h: HomeView) -> AssetsVC? {
    if let p = pushingVC, p.h === h { return p }
    return appleNav?.viewControllers.first { ($0 as? AssetsVC)?.h === h } as? AssetsVC
  }
  // (Apple's navigation changed — the tab tapped again pops them all at once, and only the top one hears it: the ones no
  //  longer there taken off too)
  func reconcile(_ vcs: [UIViewController]) {
    guard appleNav != nil else { return }
    for s in stack where s.h !== tabRoot && !vcs.contains(where: { ($0 as? AssetsVC)?.h === s.h }) { navGone(s.h) }
  }
  private weak var base: UIView?   // (what the first one was opened over — a client's page, the list; hidden under it meanwhile)
  // (who's signed in: as the page or Me said, else the app's own copy's — opened from a client's page without the
  //  website, it wasn't known, so a new folder or an upload went to a page that isn't there and never showed: Haris
  //  2026-11-06)
  private var meSaid: String?
  private var me: String? {
    get { (meSaid?.isEmpty == false ? meSaid : nil) ?? AppData.shared.me }
    set { meSaid = newValue }
  }
  private var pending: [String: ([String: Any]) -> Void] = [:]
  private(set) var leaving = false
  private var upBusy = false

  var top: HomeView? { stack.last.map { $0.h } }
  // the one the top buttons belong to: going back, already the one under it (it was nil then — for a moment the buttons
  // were the Clients tab's under all of them, then this one's again: they faded out and in, Haris 2026-11-03 08:20)
  var shown: HomeView? {
    guard let s = stack.last, !s.h.isHidden else { return nil }
    if leaving { return stack.count >= 2 ? stack[stack.count - 2].h : nil }
    return s.h
  }
  var isOpen: Bool { !stack.isEmpty }
  var screens: [HomeView] { stack.map { $0.h } }

  // ---------- talking to the page ----------
  // (Part B step 5: the changes go straight to the server — /api/app/act, done there as the website would; the changed
  //  records into the app's copy at once, and the screen's contents worked out from it. Switched off on the server
  //  (kv app-act-assets), the copy not this person's yet, or no answer: the page, as before)
  private static let serverActs: [String: String] = ["addClient": "caAddClient", "uploaded": "caUploaded", "newFolder": "caNewFolder",
    "renameFolder": "caRenameFolder", "deleteFolder": "caDeleteFolder", "deleteFile": "caDeleteFile", "deleteFiles": "caDeleteFiles",
    "renameClient": "caRenameClient", "deleteClient": "caDeleteClient"]
  static var logosAsked = false
  func ask(_ ev: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    if let name = ev["ev"] as? String, let act = AssetsCtl.serverActs[name], AppData.shared.tabsOn, AppData.shared.ready, AppData.shared.me == me, me != nil,
       JSONSerialization.isValidJSONObject(ev) {
      var b = ev; b["ev"] = act; b["op"] = UUID().uuidString
      main.serverTask.request("/api/app/act", body: b) { [weak self] j in
        guard let self = self else { return }
        guard let j = j, (j["off"] as? Bool) != true else { self.askPage(ev, done); return }
        if let ch = j["changes"] as? [[String: Any]], !ch.isEmpty { AppData.shared.applyLocal(ch) }
        var r = j
        // (the screen's contents as the page answered them: all of them after adding / deleting a client, else that client's)
        let whose: Any = name == "addClient" || name == "deleteClient" ? NSNull() : (ev["client"] ?? NSNull())
        if let m = AppData.shared.meModel("assets", "assets", [whose]) { r["model"] = m; self.take(m) }
        done(r)
      }
      return
    }
    askPage(ev, done)
  }
  private func askPage(_ ev: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    // (Part B step 2: what's in it from the app's own copy at once — the page's answer still follows and wins)
    if (ev["ev"] as? String) == "want", AppData.shared.ready, let m = AppData.shared.meModel("assets", "assets", [ev["client"] ?? NSNull()]) {
      take(m)
      // (no website — step 9, offline: the copy's is the answer; and the logo catch-up asked of the server, once a run,
      //  as the page's autoLogosAll did when Client Assets opened)
      if !main.pageReady {
        if !AssetsCtl.logosAsked { AssetsCtl.logosAsked = true; main.serverTask.request("/api/app/act", body: ["ev": "caLogosAll", "op": UUID().uuidString]) { _ in } }
        done(["ok": true]); return
      }
    }
    // (no website and nothing in the copy for it — a client whose Client Assets aren't there for this person: said, and
    //  its empty screen taken away, not left on Loading… — the walk-through, 2026-11-05)
    if !main.pageReady, (ev["ev"] as? String) == "want" {
      done(["ok": false, "error": "These files aren’t here"])
      if let c = ev["client"] as? String, models[c] == nil, top != nil, stack.last?.client == c { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.pop() } }
      return
    }
    // (no website, and the server didn't take it: said at once — not 20 s of nothing)
    if !main.pageReady { done(["ok": false, "error": "Couldn’t reach the server — try again"]); return }
    let rid = UUID().uuidString
    var e = ev; e["rid"] = rid
    pending[rid] = done
    main.pageJS("window.__e11Assets && window.__e11Assets(\(jsonString(e)))")
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
      guard let self = self, let d = self.pending.removeValue(forKey: rid) else { return }
      d(["ok": false, "error": "No answer — try again"])
    }
  }
  // from the page: an answer, or show / hide (opened on the page itself)
  func command(_ a: [String: Any]) {
    if let rid = a["rid"] as? String {
      if let m = a["model"] as? [String: Any] { take(m) }
      pending.removeValue(forKey: rid)?(a)
      return
    }
    // (live: what's shown changed on the page — someone else's change, another device's)
    if (a["push"] as? Bool) == true {
      if let m = a["model"] as? [String: Any] { take(m); return }
      if (a["gone"] as? Bool) == true, let id = a["key"] as? String, !id.isEmpty {
        models[id] = nil
        if appleNav != nil, stack.contains(where: { $0.client == id }) {
          close(animated: true)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.main.shownScreen?.assetsToast("That client has been removed") }
          return
        }
        if let i = stack.firstIndex(where: { $0.client == id }) {
          let h = i > 0 ? stack[i - 1].h : nil
          while stack.count > i + 1 { stack.removeLast().h.removeFromSuperview() }
          pop()
          if let h = h { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { h.assetsToast("That client has been removed") } }
        }
      }
      return
    }
    guard let show = a["show"] as? Bool else { return }
    if !show { if fromPage { close(animated: false) }; return }
    if let m = a["me"] as? String { me = m }
    let st = (a["start"] as? [String: Any]) ?? [:]
    let client = st["client"] as? String, folder = st["folder"] as? String
    // (already showing it — the page saying so again)
    if fromPage, let s = stack.last, s.client == client, s.folder == folder, s.kind == (client == nil ? "all" : folder == nil ? "client" : "folder") { return }
    close(animated: false)
    pickHost()
    fromPage = true; rootTab = (a["root"] as? Bool) == true
    // (from Me › Client Assets: it slides in over Me, as Me's other pages — Haris 2026-11-04)
    let slide = main.selectedTabKey == "me"
    // (opened from somewhere — an Inbox update, a link, a client's page: just that screen, so ‹ goes back where you came
    //  from, not up through the client's folders — Haris 2026-11-04)
    if let c = client { open(client: c, folder: folder, animated: slide, direct: !rootTab) } else { openAll(animated: slide) }
  }
  private func take(_ m: [String: Any]) {
    let kind = m["kind"] as? String
    if kind == "client", let cid = m["id"] as? String {
      // (which links are off: the client's files, and its folders as "d:<client>/<folder>")
      main.loadLinkStates(((m["files"] as? [[String: Any]]) ?? []).compactMap { $0["file"] as? String } + ((m["folders"] as? [[String: Any]]) ?? []).compactMap { ($0["id"] as? String).map { "d:\(cid)/\($0)" } })
    }
    if kind == "all" { models[""] = m } else if kind == "client", let id = m["id"] as? String { models[id] = m }
    for s in stack where (kind == "all" && s.kind == "all") || (kind == "client" && s.client == (m["id"] as? String)) { draw(s) }
    main.updateCorner()   // (its ••• as it is now)
  }

  // ---------- opening ----------
  // from the Clients tab: a client's folder (or its assets) over its page
  func openFromClients(client: String, folder: String?) {
    if !stack.isEmpty, fromPage { close(animated: false) }
    fromPage = false; rootTab = false
    if stack.isEmpty { pickHost() }
    open(client: client, folder: folder, animated: true, direct: true)   // (‹ back to the client's page, the way you came)
  }
  // (the self-test: the first client opened from All Client Assets, as tapping its card)
  func selfOpenClient() -> String {
    let list = (models[""]?["clients"] as? [[String: Any]]) ?? []
    guard let id = list.first?["id"] as? String else { return "no clients (\(models[""] == nil ? "no model" : "empty"))" }
    guard stack.last?.kind == "all" else { return "top is \(stack.last?.kind ?? "nothing") of \(stack.count)" }
    push(screen("client", id, nil), animated: true); ask(["ev": "want", "client": id]) { _ in }
    return "opened"
  }
  func openAll(animated: Bool) {
    if stack.isEmpty { pickHost() }
    push(screen("all", nil, nil), animated: animated)
    ask(["ev": "want"]) { [weak self] r in if (r["ok"] as? Bool) != true { self?.top?.assetsToast(r["error"] as? String ?? "Not available") } }
  }
  private func open(client: String, folder: String?, animated: Bool, direct: Bool = false) {
    // (the client's screen, then the folders down to the one asked for — only the last slides in)
    var chain: [String] = []
    if let f = folder, let m = models[client] {
      var cur: String? = f
      while let id = cur, chain.count < 8 { chain.insert(id, at: 0); cur = folderInfo(m, id)?["parent"] as? String }
    } else if let f = folder { chain = [f] }
    if direct, let f = folder {
      push(screen("folder", client, f), animated: animated)
      ask(["ev": "want", "client": client]) { [weak self] r in if (r["ok"] as? Bool) != true { self?.top?.assetsToast(r["error"] as? String ?? "Not available") } }
      return
    }
    let first = screen("client", client, nil)
    push(first, animated: animated && chain.isEmpty)
    for (i, f) in chain.enumerated() { push(screen("folder", client, f), animated: animated && i == chain.count - 1) }
    ask(["ev": "want", "client": client]) { [weak self] r in
      guard let self = self else { return }
      if (r["ok"] as? Bool) != true { self.top?.assetsToast(r["error"] as? String ?? "Not available"); return }
      // (a folder asked for straight away: its folders above it, now that they're known)
      if self.appleNav == nil, let f = folder, chain.count == 1, let m = self.models[client], let p = self.folderInfo(m, f)?["parent"] as? String, let i = self.stack.firstIndex(where: { $0.folder == f }) {
        var ups: [String] = []; var cur: String? = p
        while let id = cur, ups.count < 8 { ups.insert(id, at: 0); cur = self.folderInfo(m, id)?["parent"] as? String }
        for (k, id) in ups.enumerated() { let s = self.screen("folder", client, id); s.h.isHidden = true; self.stack.insert(s, at: i + k); self.draw(s) }
        self.stack.forEach { self.main.view.bringSubviewToFront($0.h) }
        self.main.view.bringSubviewToFront(self.main.tabsMark)
      }
    }
  }
  private func screen(_ kind: String, _ client: String?, _ folder: String?) -> Screen {
    let h = HomeView(frame: main.view.bounds)
    h.assets = kind
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.assetsBack = !(stack.isEmpty && fromPage && rootTab)
    h.present = { [weak self] vc in self?.main.topMost().present(vc, animated: true) }
    h.onEvent = { [weak self, weak h] ev in guard let self = self, let h = h else { return }; self.event(h, ev) }
    h.onAssetsDraw = { [weak self] h, _ in self?.blocks(h) }
    h.assetsMenu = { [weak self, weak h] in guard let self = self, let h = h else { return [] }; return self.menuItems(h) }
    h.cornerShared = true
    h.onCorner = { [weak self] in self?.main.updateCorner() }
    if appleNav == nil { main.view.insertSubview(h, belowSubview: main.tabsMark) }
    let s = Screen(h: h, kind: kind, client: client, folder: folder)
    draw(s)
    return s
  }
  private func under(_ i: Int) -> UIView? {
    if i > 0 { return stack[i - 1].h }
    // (opened from the app's own Me — Me › Client Assets: Me comes back under it, as it was)
    if fromPage { return main.meCtl.borrow() }
    // (kept from when it opened: it's hidden under the screens since — asking whether it's shown found nothing, and
    //  going back left a black page, Haris 2026-11-02 23:00)
    if let b = base { return b }
    if let p = main.clientPageIfMade, !p.isHidden { base = p; return p }
    if let l = main.clientsListIfMade, !l.isHidden { base = l; return l }
    return nil
  }
  // live without the website (the page used to send changes again): when the copy changes — another phone, the Mac,
  // the website — the open screens are worked out again from it (Haris 2026-11-06)
  private var copyWatch: UUID?
  private func watchCopyLive() {
    guard copyWatch == nil else { return }
    copyWatch = AppData.shared.listen { [weak self] in
      guard let self = self, !self.stack.isEmpty, !self.main.pageReady else { return }
      var whose: [Any] = []
      if self.stack.contains(where: { $0.kind == "all" }) { whose.append(NSNull()) }
      for c in Set(self.stack.compactMap { $0.client }) { whose.append(c) }
      for w in whose { if let m = AppData.shared.meModel("assets", "assets", [w]) { self.take(m) } }
    }
  }
  private func push(_ s: Screen, animated: Bool) {
    if let n = appleNav {
      watchCopyLive()
      stack.append(s)
      draw(s)
      // (the Office Admin's tab: All Client Assets is its first screen)
      if s.kind == "all", stack.count == 1, n === AppleTabs.shared?.assetsNav, let vc = AssetsTabVC.shared {
        vc.adopt(s.h); blocks(s.h); main.updateCorner(); return
      }
      let vc = AssetsVC(s.h)
      vc.onGone = { [weak self, weak h = s.h] in if let h = h { self?.navGone(h) } }
      vc.onSearch = { [weak self, weak h = s.h] q in
        guard let self = self, let h = h, let i = self.stack.firstIndex(where: { $0.h === h }), self.stack[i].q != q else { return }
        self.stack[i].q = q; self.blocks(h)
      }
      pushingVC = vc
      vc.loadViewIfNeeded()
      blocks(s.h)   // (in Apple's list now — Apple's search instead of the box)
      pushingVC = nil
      n.pushViewController(vc, animated: animated && n.view.window != nil)
      main.updateCorner()
      return
    }
    let W = main.view.bounds.width
    let u = under(stack.count)
    watchCopyLive()
    stack.append(s)
    draw(s)
    s.h.isHidden = false
    if animated && main.view.window != nil {
      s.h.transform = CGAffineTransform(translationX: W, y: 0)
      UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        s.h.transform = .identity; u?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
      } completion: { _ in if !s.h.isHidden, s.h.transform == .identity { u?.isHidden = true; u?.transform = .identity }; self.main.updateCorner() }
    } else {
      s.h.transform = .identity
      if let u = u { u.isHidden = true }
    }
    main.edgePanOn()
    main.updateCorner()
  }
  // ‹ / the swipe: the top one goes, the one under it comes back
  func pop(animated: Bool = true) {
    guard let s = stack.last, !leaving else { return }
    if let n = appleNav {
      // (Apple's pop — what follows is done as the page goes: navGone)
      if let vc = appleVC(s.h) { if n.topViewController === vc { n.popViewController(animated: animated && n.view.window != nil) } else { navGone(s.h) } } else { navGone(s.h) }
      return
    }
    let W = main.view.bounds.width
    let u = under(stack.count - 1)
    if let u = u { u.isHidden = false; u.transform = CGAffineTransform(translationX: -W * 0.3, y: 0) }
    leaving = true
    main.updateCorner()
    let finish = {
      s.h.removeFromSuperview()
      // (closed meanwhile — another tab, the page moved on: nothing left to take off)
      if let i = self.stack.firstIndex(where: { $0.h === s.h }) { self.stack.remove(at: i) } else { self.leaving = false; return }
      self.leaving = false
      if self.stack.isEmpty { self.base = nil }
      if self.stack.isEmpty && self.fromPage {
        self.fromPage = false; self.main.pageJS("window.__e11Assets && window.__e11Assets({ev:'back'})")
      }
      else if let t = self.stack.last { self.refreshScreen(t) }
      // (without the website — step 9: emptied on the Me tab, Me again — however it was opened; the walk-through found a
      //  black screen after Client Assets opened from Me went back to nothing, 2026-11-05)
      if self.stack.isEmpty, !self.main.pageReady, self.main.selectedTabKey == "me" { self.main.meCtl.reveal() }
      self.main.edgePanOn(); self.main.updateCorner()
    }
    if animated {
      UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        s.h.transform = CGAffineTransform(translationX: W, y: 0); u?.transform = .identity
      } completion: { _ in finish() }
    } else { u?.transform = .identity; finish() }
  }
  // a page pushed in Apple's navigation gone (‹, the swipe back, popped): off the stack, the one under it brought up to date
  private func navGone(_ h: HomeView) {
    guard let i = stack.firstIndex(where: { $0.h === h }) else { return }
    stack.remove(at: i)
    if stack.isEmpty {
      base = nil; appleNav = nil
      if fromPage { fromPage = false; main.pageJS("window.__e11Assets && window.__e11Assets({ev:'back'})") }
    } else if let t = stack.last { refreshScreen(t) }
    main.updateCorner()
  }
  // (the Clients tab going away: the ones opened from it go with it)
  func closeIfFromClients() { if !fromPage && !stack.isEmpty { close(animated: false) } }
  // all of them gone (another tab, the page moved on)
  func close(animated: Bool) {
    // (in Apple's navigation: back to the page they were opened over)
    if let n = appleNav {
      let hs = Set(stack.map { ObjectIdentifier($0.h) })
      stack = []; leaving = false; fromPage = false; base = nil; appleNav = nil
      if let i = n.viewControllers.firstIndex(where: { ($0 as? AssetsVC).map { hs.contains(ObjectIdentifier($0.h)) } ?? false }), i > 0 {
        n.viewControllers.forEach { ($0 as? AssetsVC)?.onGone = nil }
        n.popToViewController(n.viewControllers[i - 1], animated: animated && n.view.window != nil)
      }
      main.updateCorner()
      return
    }
    stack.forEach { $0.h.removeFromSuperview() }
    stack = []; leaving = false; fromPage = false; base = nil
    main.edgePanOn(); main.updateCorner()
  }
  // the edge swipe on the top one: it follows the finger, the one under it coming back, the top buttons between them
  private var panFrom: ((CornerButton.Spot, CornerButton.Spot, CornerButton.Spot), (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot))?
  func edgePan(_ g: UIScreenEdgePanGestureRecognizer) {
    guard let s = stack.last, !leaving, appleNav == nil else { return }
    let W = main.view.bounds.width
    let x = max(0, g.translation(in: main.view).x)
    let u = under(stack.count - 1)
    switch g.state {
    case .began:
      s.h.endEditing(true)
      if let u = u as? HomeView { u.isHidden = false; u.transform = .identity; panFrom = (main.cornerTargetFor(s.h), main.cornerTargetFor(u)) } else { u?.isHidden = false; panFrom = nil }
      u?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    case .changed:
      s.h.transform = CGAffineTransform(translationX: x, y: 0)
      u?.transform = CGAffineTransform(translationX: -W * 0.3 * (1 - x / W), y: 0)
      if let f = panFrom { main.corner.between(f.0, f.1, x / W) }
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: main.view).x
      let go = g.state == .ended && (v > 300 || (x > W * 0.4 && v > -200))
      panFrom = nil
      if go {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        leaving = true; main.updateCorner()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          s.h.transform = CGAffineTransform(translationX: W, y: 0); u?.transform = .identity
        } completion: { _ in self.leaving = false; self.pop(animated: false) }
      } else {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          s.h.transform = .identity; u?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
        } completion: { _ in if s.h.transform == .identity { u?.isHidden = true; u?.transform = .identity } }
        main.updateCorner()
      }
    default: break
    }
  }
  // (back on screen: what's there now)
  func refresh() { if let s = stack.last { refreshScreen(s) } }
  private func refreshScreen(_ s: Screen) {
    ask(s.client == nil ? ["ev": "want"] : ["ev": "want", "client": s.client!]) { _ in }
  }

  // ---------- what's on each ----------
  private func folderInfo(_ m: [String: Any], _ id: String) -> [String: Any]? { ((m["folders"] as? [[String: Any]]) ?? []).first { ($0["id"] as? String) == id } }
  private func filesIn(_ m: [String: Any], _ fid: String) -> [[String: Any]] { ((m["files"] as? [[String: Any]]) ?? []).filter { ($0["folder"] as? String) == fid } }
  private func screenOf(_ h: HomeView) -> Screen? { stack.first { $0.h === h } }
  private func draw(_ s: Screen) {
    var mm: [String: Any] = ["show": true, "me": me ?? main.clientsPageMe ?? "", "look": main.lookBoth]
    if s.kind == "all" {
      let m = models[""]
      mm["title"] = "Client Assets"; mm["date"] = m?["sub"] as? String ?? ""
    }
    s.h.bottomRoom = (main.tabBar.isHidden ? 40 : main.view.bounds.height - main.tabBar.frame.minY) + 96
    if !s.h.appleTop { s.h.tabTop = main.tabBar.isHidden ? nil : main.tabPillTop }   // (in Apple's navigation: its page's own — ClientsPushedVC)
    s.h.people = main.homePagePeople
    s.h.update(mm)
  }
  private func part<T: UIView>(_ h: HomeView, _ k: String, _ make: () -> T) -> T {
    if let v = h.assetsParts[k] as? T { return v }
    let v = make(); h.assetsParts[k] = v; return v
  }
  // a row or tile kept by what it shows (its key) while it's there — the ones no longer drawn let go by sweep
  private var keptNow = Set<String>()
  private func kept<T: UIView>(_ h: HomeView, _ k: String, _ make: () -> T) -> T { keptNow.insert(k); return part(h, "@" + k, make) }
  private func sweep(_ h: HomeView) {
    for k in h.assetsParts.keys where k.hasPrefix("@") && !keptNow.contains(String(k.dropFirst())) { h.assetsParts[k] = nil }
    keptNow = []
  }
  // Apple's own empty state in the list (AppleEmpty)
  private func empty(_ h: HomeView, _ id: String) -> AppleEmpty { part(h, "empty:" + id) { () -> AppleEmpty in let e = AppleEmpty(); e.accessibilityIdentifier = id; return e } }
  // a group's heading — Apple's header over it (our words, Apple's header)
  private func head(_ h: HomeView, _ id: String, _ t: String) -> UILabel {
    let l = part(h, "head:" + id) { () -> UILabel in let x = UILabel(); x.accessibilityIdentifier = id; return x }
    let a = NSAttributedString(string: t, attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.secondaryLabel])
    if l.attributedText?.isEqual(to: a) != true { l.attributedText = a }
    return l
  }
  // folders as the Files app's tiles: tapped, opened; held, Apple's menu with its lift (Open · Info · Copy link …)
  private func folderTiles(_ h: HomeView, _ list: [[String: Any]], client cid: String) -> [UIView] {
    list.map { x in
      let id = x["id"] as? String ?? ""
      let t = kept(h, "fd:" + id) { FileTile() }
      t.folder(x, lines: 2)
      t.onTap = { [weak self] in guard let self = self else { return }; self.push(self.screen("folder", cid, id), animated: true) }
      t.menu = { [weak self, weak h] in h.flatMap { self?.folderMenu($0, x, client: cid) } }
      return t
    }
  }
  // files as Apple's rows (Recently added, what search found): tapped, Quick Look; held, Apple's menu with its lift
  private func fileRows(_ h: HomeView, _ list: [[String: Any]], client cid: String, found: Bool, marks: [String], whereFrom cname: String?) -> [UIView] {
    list.map { x in
      let id = x["id"] as? String ?? ""
      let r = kept(h, (found ? "fs:" : "fr:") + id) { () -> FileListRow in let v = FileListRow(); v.found = found; return v }
      var at = x["where"] as? String ?? ""
      if let c = cname, at.hasPrefix(c + " › ") { at = String(at.dropFirst(c.count + 3)) }
      r.set(x, line: FileListRow.line(x, at: at), marks: marks, look: h.look)
      r.onTap = { [weak self] in self?.preview(x, among: list) }
      r.menu = { [weak self, weak h] in h.flatMap { self?.fileMenu($0, x, client: cid) } }
      r.onLook = { [weak h] in h?.listAgain() }
      return r
    }
  }
  private func blocks(_ h: HomeView) {
    guard let s = screenOf(h) else { return }
    let L = h.look
    var out: [UIView] = []
    switch s.kind {
    case "all":
      // (Haris 2026-11-10, approved: each client Apple's own row in Apple's inset group — its logo or colour, its name,
      //  "3 folders · 41 files", ›)
      let m = models[""] ?? [:]
      let list = (m["clients"] as? [[String: Any]]) ?? []
      for c in list {
        let id = c["id"] as? String ?? ""
        let r = kept(h, "k:" + id) { () -> ClientListRow in let x = ClientListRow(); x.held = false; return x }
        r.id = id
        r.set(c, inactive: false, look: L, people: [:])
        r.onTap = { [weak self] in guard let self = self else { return }; self.push(self.screen("client", id, nil), animated: true); self.ask(["ev": "want", "client": id]) { _ in } }
        r.onLook = { [weak h] in h?.listAgain() }
        out.append(r)
      }
      sweep(h)
      if m.isEmpty { let n = empty(h, "wait"); n.setLoading(); out.append(n) }
      else if list.isEmpty { let n = empty(h, "none"); n.set("person.2", "No Clients", (m["canAdd"] as? Bool) == true ? "Add your first client to start collecting their brand assets." : "An Admin or Account Manager will add them here."); out.append(n) }
      h.setFab("Add client", "plus", (m["canAdd"] as? Bool) == true ? { [weak self, weak h] in if let h = h { self?.addClient(h) } } : nil)
    case "client":
      guard let cid = s.client else { break }
      let m = models[cid] ?? [:]
      h.drawAssetsBar(name: m["name"] as? String ?? main.clientPageIfMade?.model["title"] as? String ?? "Client Assets", sub: m["sub"] as? String ?? "", logo: m["logo"] as? String, rgb: m["rgb"], ini: m["ini"] as? String, showLogo: false)   // (just the name — no colour box or logo: Haris 2026-11-04)
      appleVC(h)?.placeholder("Search \(m["name"] as? String ?? "this client")’s files")
      let all = (m["files"] as? [[String: Any]]) ?? []
      let q = s.q.trimmingCharacters(in: .whitespaces)
      if !q.isEmpty {
        // (what search found: Apple's rows, the words washed — each its own row, so no wash stays after search)
        // (the approved mock-up "Searching Client Assets": its folders found, then its files — Apple's rows, the words washed)
        let found = AssetsCtl.find(all, q)
        let loose = AssetsCtl.lastLoose
        let fr = Find.filter((m["folders"] as? [[String: Any]]) ?? [], q) { "\($0["name"] ?? "")" }
        let dirs = fr.loose ? [] : fr.items
        if !dirs.isEmpty {
          out.append(head(h, "foundDirs", "Folders"))
          for x in dirs {
            let id = x["id"] as? String ?? ""
            let r = kept(h, "fsd:" + id) { () -> FileListRow in let v = FileListRow(); v.found = true; return v }
            let n = x["total"] as? Int ?? x["files"] as? Int ?? 0
            r.setFolder(x, line: [x["path"] as? String ?? "", "\(n) file\(n == 1 ? "" : "s")"].filter { !$0.isEmpty }.joined(separator: " · "), marks: fr.marks, look: L)
            r.onTap = { [weak self] in guard let self = self else { return }; self.push(self.screen("folder", cid, id), animated: true) }
            r.menu = { [weak self, weak h] in h.flatMap { self?.folderMenu($0, x, client: cid) } }
            out.append(r)
          }
        }
        if !found.isEmpty { out.append(head(h, "found", "Files · \(found.count)" + (loose ? " — close matches" : ""))) }
        if found.isEmpty && dirs.isEmpty { let n = empty(h, "foundNone"); n.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); out.append(n) }
        let marks = Find.filter(found, q) { "\($0["name"] ?? "") \($0["where"] ?? "")" }.marks
        out += fileRows(h, found, client: cid, found: true, marks: marks, whereFrom: m["name"] as? String)
      } else {
        // (its folders: the Files app's grid, three across — Haris 2026-11-10, approved)
        let tops = ((m["folders"] as? [[String: Any]]) ?? []).filter { $0["parent"] == nil || $0["parent"] is NSNull }
        if !tops.isEmpty { out.append(head(h, "folders", "Folders")) }
        out += folderTiles(h, tops, client: cid)
        if m.isEmpty { let n = empty(h, "wait"); n.setLoading(); out.append(n) }
        else if tops.isEmpty { let n = empty(h, "noFolders"); n.set("folder", "No Folders"); out.append(n) }
        // (Recently added: Apple's rows)
        let recent = ((m["recent"] as? [String]) ?? []).compactMap { id in all.first { ($0["id"] as? String) == id } }
        if !recent.isEmpty {
          out.append(head(h, "recent", "Recently added"))
          out += fileRows(h, recent, client: cid, found: false, marks: [], whereFrom: m["name"] as? String)
        }
      }
      sweep(h)
      h.setFab("", "plus", nil)
    case "folder":
      guard let cid = s.client, let fid = s.folder else { break }
      let m = models[cid] ?? [:]
      let f = folderInfo(m, fid)
      h.drawAssetsBar(name: f?["name"] as? String ?? "Folder", sub: m["name"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      let subs = ((m["folders"] as? [[String: Any]]) ?? []).filter { ($0["parent"] as? String) == fid }
      if !subs.isEmpty { out.append(head(h, "folders", "Folders")) }
      out += folderTiles(h, subs, client: cid)
      let files = filesIn(m, fid)
      // (Select: Apple's ticks on the tiles; the words at the header's right — Select ↔ Cancel)
      let i = stack.firstIndex { $0.h === h }
      let picking = i.flatMap { stack[$0].picked }
      let fh = head(h, "files", files.isEmpty ? "Files" : "\(files.count) file\(files.count == 1 ? "" : "s")")
      h.tileSeeAll["h:files"] = files.isEmpty ? nil : (picking == nil ? "Select" : "Cancel", { [weak self, weak h] in
        guard let self = self, let h = h, let j = self.stack.firstIndex(where: { $0.h === h }) else { return }
        self.stack[j].picked = self.stack[j].picked == nil ? [] : nil; self.blocks(h)
      })
      if !files.isEmpty || f == nil || subs.isEmpty { out.append(fh) }
      var tiles: [FileTile] = []
      for x in files {
        let id = x["id"] as? String ?? ""
        let t = kept(h, "ff:" + id) { FileTile() }
        t.file(x, lines: 2, sizeText: TaskPage.size(x["size"] as? Int ?? 0))
        t.selecting = picking != nil
        t.picked = picking?.contains(id) == true
        t.onTap = { [weak self, weak h] in
          guard let self = self, let h = h, let j = self.stack.firstIndex(where: { $0.h === h }) else { return }
          if var p = self.stack[j].picked { UISelectionFeedbackGenerator().selectionChanged(); if p.contains(id) { p.remove(id) } else { p.insert(id) }; self.stack[j].picked = p; self.blocks(h) }
          else { self.preview(x, among: files) }
        }
        t.menu = picking != nil ? nil : { [weak self, weak h] in h.flatMap { self?.fileMenu($0, x, client: cid) } }
        tiles.append(t)
      }
      out += tiles
      if files.isEmpty {
        // (Apple's empty state: "No Files", and the folder's own note — or Upload — under it)
        let n = empty(h, "empty")
        if m.isEmpty { n.setLoading() }
        else { n.set("doc", "No Files", (f?["note"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ((f?["canUpload"] as? Bool) == true ? "Tap Upload to add some." : nil)) }
        out.append(n)
      }
      sweep(h)
      if let pk = picking {
        let list = files.filter { pk.contains($0["id"] as? String ?? "") }
        let n = list.count
        h.setFab(n == 0 ? "Select files" : "Download \(n)", "arrow.down.circle", n == 0 ? nil : { [weak self, weak h] in
          guard let self = self, let h = h else { return }
          self.downloadMany(h, list, name: f?["name"] as? String ?? "Files")
          if let j = self.stack.firstIndex(where: { $0.h === h }) { self.stack[j].picked = nil }; self.blocks(h)
        })
        // (and Trash, when you may delete every file picked — Haris 2026-11-04)
        let canDel = !list.isEmpty && list.allSatisfy { ($0["canDel"] as? Bool) == true }
        h.setFab2("Trash \(n)", canDel ? { [weak self, weak h] in
          guard let self = self, let h = h else { return }
          let ids = list.compactMap { $0["id"] as? String }
          let one = list.count == 1 ? "“\(list[0]["name"] as? String ?? "this file")”" : "\(list.count) files"
          self.confirm(h, "Move \(one) to the Trash?", "\(list.count == 1 ? "It moves" : "They move") to the Trash, where \(list.count == 1 ? "it" : "they") can be restored within 30 days. Copies already pasted into tasks stay.", "Delete") { [weak self, weak h] in
            guard let self = self, let h = h else { return }
            self.change(h, ["ev": "deleteFiles", "client": cid, "folder": fid, "files": ids], done: list.count == 1 ? "Moved to the Trash" : "\(list.count) files moved to the Trash") { [weak self, weak h] _ in
              guard let self = self, let h = h else { return }
              if let j = self.stack.firstIndex(where: { $0.h === h }) { self.stack[j].picked = nil }; self.blocks(h)
            }
          }
        } : nil)
      } else {
        h.setFab2("", nil)
        h.setFab("Upload", "arrow.up", (f?["canUpload"] as? Bool) == true ? { [weak self, weak h] in if let h = h { self?.upload(h, client: cid, folder: fid) } } : nil)
      }
    default: break
    }
    h.setContent(out)
  }
  // a client's files whose names have every word typed (accents and case aside)
  // (exact pieces first; nothing found — small typos allowed, as the website's caSearch: "frod" finds Ford, "gudelines"
  //  guidelines; Haris 2026-11-06. lastLoose: the last search was the forgiving one — "close matches")
  static var lastLoose = false
  static func find(_ files: [[String: Any]], _ q: String) -> [[String: Any]] {
    let norm = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let terms = norm(q).split(whereSeparator: { $0 == " " || $0 == "," }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }
    let hay = { (f: [String: Any]) in norm((f["name"] as? String ?? "") + " " + (f["where"] as? String ?? "")) }
    let exact = files.filter { f in let n = hay(f); return terms.allSatisfy { n.contains($0) } }
    lastLoose = false
    if !exact.isEmpty || terms.isEmpty { return Array(exact.prefix(80)) }
    let limit = { (t: String) -> Int in t.count >= 8 ? 2 : t.count >= 4 ? 1 : 0 }
    let near = { (t: String, n: String) -> Bool in
      if n.contains(t) { return true }
      let lim = limit(t); guard lim > 0 else { return false }
      let words = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
      return words.contains { w in typoDist(t, w, lim) <= lim || (w.count > t.count && typoDist(t, String(w.prefix(t.count)), lim) <= lim) }
    }
    let loose = files.filter { f in let n = hay(f); return terms.allSatisfy { near($0, n) } }
    lastLoose = !loose.isEmpty
    return Array(loose.prefix(80))
  }
  // (the website's editDist: letters added, dropped, changed — two swapped count as one)
  static func typoDist(_ a0: String, _ b0: String, _ maxD: Int) -> Int {
    let a = Array(a0), b = Array(b0)
    if abs(a.count - b.count) > maxD { return maxD + 1 }
    if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
    var prev2 = [Int](repeating: 0, count: b.count + 1), prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
      cur[0] = i; var best = cur[0]
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] { v = min(v, prev2[j - 2] + 1) }
        cur[j] = v; if v < best { best = v }
      }
      if best > maxD { return maxD + 1 }
      prev2 = prev; prev = cur
    }
    return prev[b.count]
  }

  // ---------- taps ----------
  private func event(_ h: HomeView, _ ev: [String: Any]) {
    switch ev["ev"] as? String ?? "" {
    case "back": if h === top { pop() }
    case "me": close(animated: false); main.pageJS("window.__e11Assets && window.__e11Assets({ev:'me'})"); if !main.pageReady { main.selectTab("me") }
    case "find":
      // 🔍 on All Client Assets: every client's files, found here
      let q = (ev["q"] as? String ?? "").trimmingCharacters(in: .whitespaces)
      guard !q.isEmpty else { h.showFound([], hint: "Search the files of every client — logos, guidelines, fonts…"); return }
      let all = (models[""]?["files"] as? [[String: Any]]) ?? []
      let found = AssetsCtl.find(all, q)
      let loose = AssetsCtl.lastLoose
      // (Apple's rows, each with where it is — "Client › Folder · 2 MB" — the words washed; one per file, made each search)
      let marks = Find.filter(found, q) { "\($0["name"] ?? "") \($0["where"] ?? "")" }.marks
      let rows: [UIView] = found.map { x in
        let r = FileListRow(); r.found = true
        r.set(x, line: FileListRow.line(x, at: x["where"] as? String ?? ""), marks: marks, look: h.look)
        r.onTap = { [weak self] in self?.preview(x, among: found) }
        r.menu = { [weak self, weak h] in h.flatMap { self?.fileMenu($0, x, client: x["client"] as? String ?? "") } }
        r.onLook = { [weak h] in h?.listAgain() }
        return r
      }
      // (nothing found: Apple's own "No Results" — Haris 2026-11-10)
      if found.isEmpty { let e = empty(h, "allNone"); e.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); h.showFound([e], hint: nil) }
      else { h.showFound(rows, hint: loose ? "Nothing matched exactly — close matches:" : nil) }
    default: break
    }
  }
  private func preview(_ f: [String: Any], among list: [[String: Any]]) {
    let at = list.firstIndex { ($0["id"] as? String) == (f["id"] as? String) } ?? 0
    main.quickLook(list, at: at)   // (Apple's Quick Look — Haris 2026-11-10, approved)
  }
  private func toast(_ h: HomeView?, _ t: String) { (h ?? top)?.assetsToast(t) }

  // ---------- a file's and a folder's menu (held, or •••): Apple's popup menu, as Home's task cards (Haris 2026-11-08) ----------
  private static let symbols = ["link": "link", "download": "arrow.down.circle", "info": "info.circle", "unlock": "lock.open",
                                "lock": "lock", "trash": "trash", "folder": "folder", "edit": "pencil"]
  private func popup(_ title: String, _ items: [(String, String, Bool, () -> Void)]) -> UIMenu {
    let act = { (it: (String, String, Bool, () -> Void)) -> UIAction in
      let run = it.3
      // (Turn off link: red, as the sheet had it — Haris 2026-11-03)
      return UIAction(title: it.0, image: AssetsCtl.symbols[it.1].flatMap { UIImage(systemName: $0) }, attributes: it.2 || it.0 == "Turn off link" ? .destructive : []) { _ in run() }
    }
    let main = items.filter { !$0.2 }.map(act), danger = items.filter { $0.2 }.map(act)
    return UIMenu(title: title, children: [UIMenu(options: .displayInline, children: main)] + (danger.isEmpty ? [] : [UIMenu(options: .displayInline, children: danger)]))
  }
  func fileMenu(_ h: HomeView, _ f: [String: Any], client: String) -> UIMenu {
    var items: [(String, String, Bool, () -> Void)] = [
      ("Copy link", "link", false, { [weak self, weak h] in self?.main.copyFile(f) { t in h?.assetsToast(t) } }),
      ("Download", "download", false, { [weak self, weak h] in guard let self = self else { return }; self.main.downloadFile(f, from: self.main.topMost()) { t in h?.assetsToast(t) } }),
      ("Info", "info", false, { [weak self] in self?.fileInfo(f) }),
    ]
    let flipFile: () -> Void = { [weak self, weak h] in self?.main.fileLinkToggle(f) { t in h?.assetsToast(t) } }
    if Main.isAdmin { if Main.linksOff.contains(f["file"] as? String ?? "") { items.append(("Turn on link", "unlock", false, flipFile)) } else { items.append(("Turn off link", "lock", false, flipFile)) } }
    if (f["canDel"] as? Bool) == true, let fid = f["folder"] as? String {
      items.append(("Trash", "trash", true, { [weak self, weak h] in
        guard let self = self, let h = h else { return }
        self.confirm(h, "Move “\(f["name"] as? String ?? "this file")” to the Trash?", "It can be restored within 30 days. Copies already pasted into tasks stay.", "Trash") {
          self.change(h, ["ev": "deleteFile", "client": client, "folder": fid, "file": f["id"] as? String ?? ""], done: "Moved to the Trash")
        }
      }))
    }
    return popup(f["name"] as? String ?? "File", items)
  }
  func folderMenu(_ h: HomeView, _ f: [String: Any], client: String) -> UIMenu {
    let id = f["id"] as? String ?? ""
    var items: [(String, String, Bool, () -> Void)] = [
      ("Open", "folder", false, { [weak self] in guard let self = self else { return }; self.push(self.screen("folder", client, id), animated: true) }),
      ("Info", "info", false, { [weak self] in self?.folderInfoSheet(f, client: client) }),
    ]
    if (f["canLink"] as? Bool) == true {
      items.append(("Copy link", "link", false, { [weak self, weak h] in self?.main.copyFolderLink(client: client, folder: id) { t in h?.assetsToast(t) } }))
      let flip: () -> Void = { [weak self, weak h] in self?.main.folderLinkToggle(client: client, folder: id) { t in h?.assetsToast(t) } }
      if Main.isAdmin { if Main.linksOff.contains("d:\(client)/\(id)") { items.append(("Turn on link", "unlock", false, flip)) } else { items.append(("Turn off link", "lock", false, flip)) } }
    }
    if (f["canRename"] as? Bool) == true { items.append(("Rename folder", "edit", false, { [weak self, weak h] in if let h = h { self?.renameFolder(h, f, client: client) } })) }
    if (f["canDel"] as? Bool) == true { items.append(("Trash folder", "trash", true, { [weak self, weak h] in if let h = h { self?.deleteFolder(h, f, client: client) } })) }
    return popup(f["name"] as? String ?? "Folder", items)
  }
  // the ••• at the top
  private func menuItems(_ h: HomeView) -> [CornerMenuItem] {
    guard let s = screenOf(h), let cid = s.client else { return [] }
    let m = models[cid] ?? [:]
    var out: [CornerMenuItem] = []
    if s.kind == "client" {
      if (m["canNewTop"] as? Bool) == true { out.append(CornerMenuItem(title: "New folder", symbol: "folder.badge.plus", run: { [weak self, weak h] in if let h = h { self?.newFolder(h, client: cid, parent: nil) } })) }
      // (no Download all for a whole client — every folder at once is too much for the server; a folder's own files only:
      //  Haris 2026-11-08)
      out.append(CornerMenuItem(title: "Info", symbol: "info.circle", run: { [weak self] in self?.clientInfo(m) }))
      var edit: [CornerMenuItem] = []
      if (m["canRename"] as? Bool) == true { edit.append(CornerMenuItem(title: "Rename client", symbol: "pencil", run: { [weak self, weak h] in if let h = h { self?.renameClient(h, m) } })) }
      if (m["canDelete"] as? Bool) == true { edit.append(CornerMenuItem(title: "Delete client", symbol: "trash", destructive: true, run: { [weak self, weak h] in if let h = h { self?.deleteClient(h, m) } })) }
      if !edit.isEmpty { out.append(CornerMenuItem(title: "", inline: true, children: edit)) }
    } else if s.kind == "folder", let fid = s.folder, let f = folderInfo(m, fid) {
      if (f["canUpload"] as? Bool) == true { out.append(CornerMenuItem(title: "Upload", symbol: "arrow.up", run: { [weak self, weak h] in if let h = h { self?.upload(h, client: cid, folder: fid) } })) }
      if (f["canSub"] as? Bool) == true { out.append(CornerMenuItem(title: "New folder", symbol: "folder.badge.plus", run: { [weak self, weak h] in if let h = h { self?.newFolder(h, client: cid, parent: fid) } })) }
      let files = filesIn(m, fid)
      if !files.isEmpty {
        out.append(CornerMenuItem(title: "Select", symbol: "checkmark.circle", run: { [weak self, weak h] in guard let self = self, let h = h, let j = self.stack.firstIndex(where: { $0.h === h }) else { return }; self.stack[j].picked = []; self.blocks(h) }))
        out.append(CornerMenuItem(title: "Download all", symbol: "arrow.down.circle", run: { [weak self, weak h] in if let h = h { self?.downloadMany(h, files, name: f["name"] as? String ?? "Files") } }))
      }
      if (f["canLink"] as? Bool) == true {
        out.append(CornerMenuItem(title: "Copy link", symbol: "link", run: { [weak self, weak h] in self?.main.copyFolderLink(client: cid, folder: fid) { t in h?.assetsToast(t) } }))
        let off = Main.linksOff.contains("d:\(cid)/\(fid)")
        if Main.isAdmin { out.append(CornerMenuItem(title: off ? "Turn on link" : "Turn off link", symbol: off ? "lock.open" : "lock", destructive: !off, run: { [weak self, weak h] in self?.main.folderLinkToggle(client: cid, folder: fid) { t in h?.assetsToast(t) } })) }
      }
      out.append(CornerMenuItem(title: "Info", symbol: "info.circle", run: { [weak self] in self?.folderInfoSheet(f, client: cid) }))
      var edit: [CornerMenuItem] = []
      if (f["canRename"] as? Bool) == true { edit.append(CornerMenuItem(title: "Rename folder", symbol: "pencil", run: { [weak self, weak h] in if let h = h { self?.renameFolder(h, f, client: cid) } })) }
      if (f["canDel"] as? Bool) == true { edit.append(CornerMenuItem(title: "Trash folder", symbol: "trash", destructive: true, run: { [weak self, weak h] in if let h = h { self?.deleteFolder(h, f, client: cid) } })) }
      if !edit.isEmpty { out.append(CornerMenuItem(title: "", inline: true, children: edit)) }
    }
    return out
  }

  // ---------- changes (done on the page, the website's way) ----------
  private func change(_ h: HomeView, _ ev: [String: Any], done: String?, then: (([String: Any]) -> Void)? = nil) {
    ask(ev) { [weak self, weak h] r in
      if (r["ok"] as? Bool) != true { UINotificationFeedbackGenerator().notificationOccurred(.error); h?.assetsToast(r["error"] as? String ?? "That didn’t work — try again"); return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      if let d = done { h?.assetsToast(d) }
      then?(r)
      _ = self
    }
  }
  private func prompt(_ h: HomeView, _ title: String, _ message: String?, value: String = "", placeholder: String, ok: String, _ run: @escaping (String) -> Void) {
    let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
    a.addTextField { t in t.text = value; t.placeholder = placeholder; t.autocapitalizationType = .sentences; t.clearButtonMode = .whileEditing }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    let go = UIAlertAction(title: ok, style: .default) { [weak a] _ in let v = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces); if !v.isEmpty { run(v) } }
    a.addAction(go); a.preferredAction = go
    main.topMost().present(a, animated: true)
  }
  private func confirm(_ h: HomeView, _ title: String, _ message: String, _ ok: String, _ run: @escaping () -> Void) {
    let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: ok, style: .destructive) { _ in run() })
    main.topMost().present(a, animated: true)
  }
  private func addClient(_ h: HomeView) {
    prompt(h, "Add client", "New clients start with Logos, Brand Guidelines, Fonts and Files folders.", placeholder: "e.g. Ford", ok: "Add client") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "addClient", "name": name], done: "Added \(name)") { [weak self] r in
        guard let self = self, let id = r["id"] as? String else { return }
        self.push(self.screen("client", id, nil), animated: true); self.ask(["ev": "want", "client": id]) { _ in }
      }
    }
  }
  private func newFolder(_ h: HomeView, client: String, parent: String?) {
    let m = models[client] ?? [:]
    let pname = parent.flatMap { folderInfo(m, $0)?["path"] as? String }
    prompt(h, "New folder", "In \(m["name"] as? String ?? "this client")\(pname.map { " › " + $0 } ?? "")", placeholder: parent == nil ? "e.g. Social templates" : "e.g. Summer campaign shoot", ok: "Create") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      var ev: [String: Any] = ["ev": "newFolder", "client": client, "name": name]; if let p = parent { ev["parent"] = p }
      self.change(h, ev, done: "Made “\(name)”")
    }
  }
  private func renameFolder(_ h: HomeView, _ f: [String: Any], client: String) {
    prompt(h, "Rename folder", nil, value: f["name"] as? String ?? "", placeholder: "Folder name", ok: "Save") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "renameFolder", "client": client, "folder": f["id"] as? String ?? "", "name": name], done: nil)
    }
  }
  private func deleteFolder(_ h: HomeView, _ f: [String: Any], client: String) {
    let subs = f["subs"] as? Int ?? 0, n = f["total"] as? Int ?? 0
    let what = [subs > 0 ? "\(subs) folder\(subs == 1 ? "" : "s")" : "", n > 0 ? "\(n) file\(n == 1 ? "" : "s")" : ""].filter { !$0.isEmpty }.joined(separator: " and ")
    confirm(h, "Move “\(f["name"] as? String ?? "this folder")” to the Trash?", "The folder\(what.isEmpty ? "" : " and everything in it (\(what))") moves to the Trash, where it can be restored within 30 days. Copies already pasted into tasks stay.", "Delete folder") { [weak self, weak h] in
      guard let self = self, let h = h else { return }
      let id = f["id"] as? String ?? ""
      self.change(h, ["ev": "deleteFolder", "client": client, "folder": id], done: "Moved to the Trash") { [weak self] _ in
        // (that folder's own screen, if it's open: gone)
        guard let self = self else { return }
        if let i = self.stack.firstIndex(where: { $0.folder == id }) { while self.stack.count > i + 1 { self.stack.removeLast().h.removeFromSuperview() }; self.pop() }
      }
    }
  }
  private func renameClient(_ h: HomeView, _ m: [String: Any]) {
    let id = m["id"] as? String ?? ""
    prompt(h, "Rename client", nil, value: m["name"] as? String ?? "", placeholder: "Client name", ok: "Save") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "renameClient", "client": id, "name": name], done: nil)
    }
  }
  private func deleteClient(_ h: HomeView, _ m: [String: Any]) {
    let id = m["id"] as? String ?? "", n = ((m["files"] as? [[String: Any]]) ?? []).count, nf = ((m["folders"] as? [[String: Any]]) ?? []).count
    confirm(h, "Delete \(m["name"] as? String ?? "this client")?", "This removes the client and its \(nf) folders\(n > 0 ? " and \(n) file\(n == 1 ? "" : "s") (moved to the Trash)" : ""). Files already pasted into tasks stay in those tasks.", "Delete client") { [weak self, weak h] in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "deleteClient", "client": id], done: "Deleted \(m["name"] as? String ?? "")") { [weak self] _ in
        guard let self = self else { return }
        self.models[id] = nil
        if let i = self.stack.firstIndex(where: { $0.client == id }) { while self.stack.count > i + 1 { self.stack.removeLast().h.removeFromSuperview() }; self.pop() }
      }
    }
  }
  // Upload: iPhone's own Photos / Camera / Files, each file sent in pieces into the folder, then filed by the page
  private func upload(_ h: HomeView, client: String, folder: String) {
    guard !upBusy, let f = models[client].flatMap({ folderInfo($0, folder) }), let dir = f["dir"] as? String else { if upBusy { toast(h, "Still uploading — one moment") }; return }
    main.topMost().present(AttachSheetVC(title: "Upload to \(f["name"] as? String ?? "folder")") { [weak self, weak h] src in
      guard let self = self else { return }
      Picker.shared.pick(from: self.main.topMost(), single: false, source: src) { [weak self, weak h] r in
        guard let self = self else { return }
        let picked = ((r["files"] as? [[String: Any]]) ?? []).compactMap { x -> (URL, String)? in
          guard let tok = x["token"] as? String, let u = Picker.shared.url(tok) else { return nil }
          return (u, x["name"] as? String ?? "File")
        }
        guard !picked.isEmpty else { return }
        self.upBusy = true
        var sent: [[String: Any]] = []
        let total = picked.count
        let cancels = UploadCenter.shared.cancels
        func next(_ i: Int) {
          // (Cancel on the uploads' bar: nothing more goes up and nothing is filed)
          if UploadCenter.shared.cancels != cancels { self.upBusy = false; h?.assetsToast("Upload cancelled"); return }
          guard i < total else {
            self.upBusy = false
            guard !sent.isEmpty else { h?.assetsToast("Couldn’t upload — try again"); return }
            self.ask(["ev": "uploaded", "client": client, "folder": folder, "files": sent]) { [weak h] r in
              if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); Main.playUploaded(); h?.assetsToast("Added \(sent.count) file\(sent.count == 1 ? "" : "s") to \(f["name"] as? String ?? "the folder")" + (sent.count < total ? " — \(total - sent.count) didn’t upload" : "")) }
              else { h?.assetsToast(r["error"] as? String ?? "That didn’t work — try again") }
            }
            return
          }
          let (url, name) = picked[i]
          let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
          // (its progress on the uploads' bar at the bottom, with Cancel — as a download's)
          Uploader.send(url, name: name, task: "", dest: dir, cookies: self.main.serverHome.cookies, progress: { _ in }) { path in
            if let p = path { sent.append(["name": name, "path": p, "size": size]) }
            next(i + 1)
          }
        }
        next(0)
      }
    }, animated: true)
  }
  // several files at once: one .zip from the server, then iPhone's own Save / Share sheet
  private func downloadMany(_ h: HomeView, _ files: [[String: Any]], name: String) {
    let paths = files.compactMap { $0["file"] as? String }
    guard !paths.isEmpty else { return }
    // (an ✕ on its progress: stuck or too long, it's stopped — Haris 2026-11-08; nothing said after that but "cancelled")
    var cancelled = false
    var task: URLSessionDownloadTask?
    let stop: () -> Void = { [weak h] in cancelled = true; task?.cancel(); UIImpactFeedbackGenerator(style: .light).impactOccurred(); h?.assetsToast("Download cancelled", cancel: nil) }
    let say = { [weak h] (t: String) in
      guard !cancelled else { return }
      let going = t.hasPrefix("Downloading") || t.hasPrefix("Getting")
      h?.assetsToast(t, cancel: going ? stop : nil)
    }
    if files.count == 1 { main.downloadFile(files[0], from: main.topMost(), started: { task = $0 }, say); return }
    say("Getting \(paths.count) files ready…")
    main.serverTask.request("/api/host/exportFiles", body: ["folder": name, "paths": paths], timeout: 120) { [weak self] j in
      guard let self = self, !cancelled else { return }
      guard let url = j?["url"] as? String else { say("Couldn’t download — try again"); return }
      self.main.downloadFile(["url": url, "name": name + ".zip"], from: self.main.topMost(), started: { task = $0 }, say)
    }
  }

  // ---------- Info ----------
  private static func when(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let o = DateFormatter(); o.dateStyle = .medium; o.timeStyle = .short
    return o.string(from: d)
  }
  private func info(_ title: String, _ rows: [(String, String)], task: String? = nil) {
    let vc = AssetsInfoVC(title: title, rows: rows.filter { !$0.1.isEmpty })
    if let t = task { vc.openTask = { [weak self] in self?.main.openTaskPage(t, tab: "details", focus: "") } }
    let nav = FitNav(rootViewController: vc)
    nav.sheetPresentationController?.prefersGrabberVisible = true
    nav.prepare(width: main.view.bounds.width, bottom: main.bottomSafe)
    main.topMost().present(nav, animated: true)
  }
  // (the website's own rows — the same titles and values as its Info, Haris 2026-11-03)
  private func pageRows(_ x: [String: Any]) -> [(String, String)]? {
    guard let r = (x["info"] as? [String: Any])?["rows"] as? [[Any]], !r.isEmpty else { return nil }
    return r.compactMap { p in p.count >= 2 ? ("\(p[0])", "\(p[1])") : nil }
  }
  private func fileInfo(_ f: [String: Any]) {
    if let rows = pageRows(f) { info(f["name"] as? String ?? "File", rows, task: (f["info"] as? [String: Any])?["task"] as? String); return }
    info(f["name"] as? String ?? "File", [("Kind", f["label"] as? String ?? ""), ("Size", TaskPage.size(f["size"] as? Int ?? 0)), ("Where", f["where"] as? String ?? ""),
                                         ("Added by", f["by"] as? String ?? ""), ("Added", AssetsCtl.when(f["at"] as? String ?? ""))])
  }
  private func folderInfoSheet(_ f: [String: Any], client: String) {
    if let rows = pageRows(f) { info(f["name"] as? String ?? "Folder", rows); return }
    let m = models[client] ?? [:]
    let subs = f["subs"] as? Int ?? 0
    info(f["name"] as? String ?? "Folder", [("Kind", (f["final"] as? Bool) == true ? "Final files of a completed task" : "Folder"), ("Where", "\(m["name"] as? String ?? "") › \(f["path"] as? String ?? "")"),
                                           ("Folders", subs > 0 ? "\(subs)" : ""), ("Files", "\(f["total"] as? Int ?? 0)"), ("Size", TaskPage.size(f["size"] as? Int ?? 0)),
                                           ("Created by", f["by"] as? String ?? ""), ("Created", AssetsCtl.when(f["at"] as? String ?? ""))])
  }
  private func clientInfo(_ m: [String: Any]) {
    let files = (m["files"] as? [[String: Any]]) ?? []
    info(m["name"] as? String ?? "Client", [("Contents", m["sub"] as? String ?? ""), ("Size", TaskPage.size(files.reduce(0) { $0 + ($1["size"] as? Int ?? 0) })),
                                           ("Added by", m["by"] as? String ?? ""), ("Added", AssetsCtl.when(m["at"] as? String ?? ""))])
  }
}
