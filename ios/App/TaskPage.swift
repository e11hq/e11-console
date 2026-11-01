import UIKit

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
  private func request(_ path: String, body: [String: Any]?, _ done: @escaping ([String: Any]?) -> Void) {
    cookies { cookie in
      guard let url = URL(string: serverURL() + path) else { return done(nil) }
      var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
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
      done(j["task"] as? [String: Any], false)
    }
  }
  // a change → (ok, the task as it is now, error, need)
  func act(_ body: [String: Any], _ done: @escaping (Bool, [String: Any]?, String?, String?, [String]) -> Void) {
    var b = body; b["from"] = "task"; b["op"] = UUID().uuidString
    request("/api/home/act", body: b) { [weak self] j in
      guard let j = j else { return done(false, nil, "No connection — try again", nil, []) }
      if (j["off"] as? Bool) == true { return done(false, nil, "Try again in a moment", nil, []) }
      if let rev = j["rev"] as? Int { self?.lastRev = max(self?.lastRev ?? 0, rev) }
      done((j["ok"] as? Bool) == true, j["task"] as? [String: Any], j["error"] as? String, j["need"] as? String, j["messages"] as? [String] ?? [])
    }
  }
}

final class TaskPage: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UITextViewDelegate {
  let taskId: String
  var model: [String: Any]?
  var people: [String: [String: Any]] = [:]
  var onBack: (() -> Void)?
  var onTab: ((String) -> Void)?                      // "details" | "comments"
  var onAct: (([String: Any]) -> Void)?               // a change for the server
  var onEvent: (([String: Any]) -> Void)?             // for the page behind: copy, attach, from…
  var onOpen: ((String) -> Void)?                      // another task (a subtask, "New task from")
  var onDate: ((String, String, @escaping (String?) -> Void) -> Void)?   // which (start / due), its value → the new one
  var onComplete: (() -> Void)?
  // iPhone's own sheet (NativeSheetVC): its args, a tick (several), the answer (a row, or -2 with what was typed)
  var onSheet: (([String: Any], @escaping (Int) -> Void, @escaping (Int, String?) -> Void) -> Void)?
  var light = LAST_LIGHT { didSet { applyLook() } }
  private(set) var tab = "details"

  let scroll = UIScrollView()
  private let content = UIView()
  private let barBox = UIView()                        // what the frost edge sits under (the buttons and the switch)
  var barBoxView: UIView { barBox }
  // the corner button (Main's CornerButton) stands in for ••• — this page's own stays invisible; its menu is lent
  var cornerShared = false { didSet { more.alpha = cornerShared ? 0 : 1; moreBtn.isHidden = cornerShared } }
  var cornerFrame: CGRect { more.frame }
  var cornerMenu: UIMenu? { moreBtn.menu }
  var onMenu: (() -> Void)?
  var feed: CommentsFeed?, threadFeed: CommentsFeed?
  // the description's editor (DescEditor.swift)
  let descView = UITextView()
  var editingDesc = false, descEmpty = true
  let mentionBox = UIStackView()
  var onCornerChange: (() -> Void)?
  var onSubmitFiles: ((String) -> Void)?
  private let back = HomeGlass(), more = HomeGlass()
  private let moreBtn = UIButton(type: .custom)        // (over the ••• circle: iPhone's own menu)
  private let dot = UIView(), client = UILabel()
  let seg = UISegmentedControl(items: ["Details", "Comments"])
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
    addSubview(scroll)
    scroll.addSubview(content)
    commentsHost.isHidden = true
    commentsHost.clipsToBounds = true
    addSubview(commentsHost)
    addSubview(barBox)
    if #available(iOS 26.0, *) {
      let i = UIScrollEdgeElementContainerInteraction()
      i.scrollView = scroll; i.edge = .top
      barBox.addInteraction(i)
      scroll.topEdgeEffect.style = .soft
    }
    back.setIcon("chevron.left", 19)
    back.accessibilityLabel = "Back"
    back.onTap = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onBack?() }
    more.setIcon("ellipsis", 18)
    more.accessibilityLabel = "More"
    moreBtn.showsMenuAsPrimaryAction = true
    moreBtn.accessibilityLabel = "More"
    dot.layer.cornerRadius = 3
    client.font = .systemFont(ofSize: 17, weight: .semibold)
    client.lineBreakMode = .byTruncatingTail
    [back, more, moreBtn, dot, client, seg].forEach { barBox.addSubview($0) }
    seg.selectedSegmentIndex = 0
    seg.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.setTab(self.seg.selectedSegmentIndex == 1 ? "comments" : "details", tell: true)
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
    titleView.font = .systemFont(ofSize: 26, weight: .bold)
    titleView.textContainerInset = .zero
    titleView.textContainer.lineFragmentPadding = 0
    titleView.returnKeyType = .done
    setUpDesc()
    applyLook()
  }
  required init?(coder: NSCoder) { fatalError() }

  private func applyLook() {
    // (the window already takes the app's own light / dark: everything here follows it)
    backgroundColor = .systemGroupedBackground
    commentsHost.backgroundColor = .clear
    back.setLook(light: light, tint: .label); more.setLook(light: light, tint: .label)
    client.textColor = .label
  }

  // ---------- layout ----------
  var safeTop: CGFloat { max(safeAreaInsets.top, window?.safeAreaInsets.top ?? 0, 20) }
  var barBottom: CGFloat { safeTop + 54 + 8 + 32 + 10 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, top = safeTop
    scroll.frame = bounds
    barBox.frame = CGRect(x: 0, y: 0, width: W, height: barBottom)
    back.frame = CGRect(x: 16, y: top, width: 44, height: 44)
    more.frame = CGRect(x: W - 60, y: top, width: 44, height: 44)
    moreBtn.frame = more.frame
    let cw = min(client.sizeThatFits(CGSize(width: 400, height: 30)).width, W - 76 - 76 - 18)
    dot.frame = CGRect(x: 76, y: top + 22 - 5, width: 10, height: 10)
    client.frame = CGRect(x: dot.isHidden ? 76 : 94, y: top, width: cw, height: 44)
    seg.frame = CGRect(x: 16, y: top + 54 + 8, width: W - 32, height: 32)
    commentsHost.frame = bounds
    let fs = fab.sizeThatFits(CGSize(width: 300, height: 48))
    let bottom = max(safeAreaInsets.bottom, window?.safeAreaInsets.bottom ?? 0)
    fab.frame = CGRect(x: W - 16 - fs.width, y: bounds.height - bottom - 8 - 48, width: fs.width, height: 48)
    spinner.center = CGPoint(x: W / 2, y: barBottom + 60)
    if scroll.contentInset.top != barBottom { scroll.contentInset.top = barBottom; scroll.verticalScrollIndicatorInsets.top = barBottom; scroll.contentOffset.y = -barBottom }
    layoutContent()
  }

  // ---------- the tabs ----------
  func setTab(_ t: String, tell: Bool) {
    tab = t
    seg.selectedSegmentIndex = t == "comments" ? 1 : 0
    let c = t == "comments"
    commentsHost.isHidden = !c
    scroll.isHidden = c
    fab.alpha = c ? 0 : 1
    if c { endEditing(true) }
    if tell { onTab?(t) }
  }
  func setComments(_ n: Int) { seg.setTitle(n > 0 ? "Comments \(n)" : "Comments", forSegmentAt: 1) }

  // ---------- drawing the model ----------
  func loading() { if model == nil { spinner.startAnimating() } }
  func draw(_ m: [String: Any]) {
    spinner.stopAnimating()
    model = m
    if let pp = m["people"] as? [String: [String: Any]] { people.merge(pp) { a, b in b["photo"] != nil ? b : a } }
    if let c = m["client"] as? [String: Any] {
      client.text = c["name"] as? String ?? ""; dot.backgroundColor = TaskPage.rgb(c["rgb"]); dot.isHidden = false
    } else { client.text = (m["sub"] as? Bool) == true ? "Subtask" : "My Tasks"; dot.isHidden = true }
    setComments(m["comments"] as? Int ?? 0)
    makeMenu()
    // (unchanged: nothing redrawn — a tick or a title being typed stays as it is)
    let sig = (try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? UUID().uuidString
    if sig == built { return }
    // (while the description is being written nothing is redrawn under the finger: done, it catches up)
    if editingDesc || titleView.isFirstResponder { return }
    built = sig
    rebuild()
    setNeedsLayout()
  }
  func peopleChanged(_ p: [String: [String: Any]]) { people.merge(p) { _, b in b }; built = ""; if let m = model { draw(m) } }

  private func makeMenu() {
    guard let m = model else { return }
    var items: [UIMenuElement] = []
    items.append(UIAction(title: "Copy link", image: UIImage(systemName: "link")) { [weak self] _ in guard let self = self else { return }; self.onEvent?(["ev": "copy", "id": self.taskId]) })
    if (m["readOnly"] as? Bool) != true {
      items.append(UIMenu(title: "Attach Files", image: UIImage(systemName: "paperclip"), children: [
        UIAction(title: "Camera", image: UIImage(systemName: "camera")) { [weak self] _ in guard let self = self else { return }; self.onEvent?(["ev": "attach", "id": self.taskId, "source": "camera"]) },
        UIAction(title: "Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in guard let self = self else { return }; self.onEvent?(["ev": "attach", "id": self.taskId, "source": "photos"]) },
        UIAction(title: "Files", image: UIImage(systemName: "folder")) { [weak self] _ in guard let self = self else { return }; self.onEvent?(["ev": "attach", "id": self.taskId, "source": "files"]) },
      ]))
    }
    if (m["canDelete"] as? Bool) == true {
      items.append(UIMenu(options: .displayInline, children: [UIAction(title: "Delete task", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete() }]))
    }
    moreBtn.menu = UIMenu(children: items)
    onMenu?()
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
  private func rebuild() {
    guard let m = model else { return }
    let keepY = scroll.contentOffset.y
    let typing = titleView.isFirstResponder
    blocks.forEach { if $0 !== titleView { $0.removeFromSuperview() } }
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
    if (m["sub"] as? Bool) != true {
      let c = m["client"] as? [String: Any]
      let v = UIStackView(); v.axis = .horizontal; v.spacing = 6; v.alignment = .center
      if let c = c { let d = UIView(); d.backgroundColor = TaskPage.rgb(c["rgb"]); d.layer.cornerRadius = 4; d.widthAnchor.constraint(equalToConstant: 9).isActive = true; d.heightAnchor.constraint(equalToConstant: 9).isActive = true; v.addArrangedSubview(d) }
      v.addArrangedSubview(label(c?["name"] as? String ?? "No client", size: 17, color: .secondaryLabel))
      if m["lock"] != nil { v.addArrangedSubview(symbol("lock.fill", 12, .secondaryLabel)) }
      let canCl = (m["canClient"] as? Bool) == true
      g.append(row(sym: "square.grid.2x2", key: "Client", value: v, chevron: canCl, tap: canCl ? { [weak self] in self?.pickClient() } : nil))
    }
    let tags = (m["tags"] as? [[String: Any]]) ?? []
    let canTags = (m["canTags"] as? Bool) == true
    if !tags.isEmpty || canTags { g.append(row(sym: "tag", key: "Tags", value: tags.isEmpty ? greyText("Add") as UIView : chips(tags.map { ($0["t"] as? String ?? "", TaskPage.rgb($0["rgb"])) }), chevron: canTags, tap: canTags ? { [weak self] in self?.pickTags() } : nil)) }
    let ch = (m["channels"] as? [String]) ?? []
    let canCh = (m["canChannels"] as? Bool) == true
    if !ch.isEmpty || canCh { g.append(row(sym: "paperplane", key: "Channels", value: label(ch.isEmpty ? "None" : ch.joined(separator: " · "), size: 17, color: .secondaryLabel), chevron: canCh, tap: canCh ? { [weak self] in self?.pickChannels() } : nil)) }
    let canGd = (m["canGuardian"] as? Bool) == true
    if let gd = m["guardian"] as? String { g.append(row(sym: "star", key: "Guardian", value: personLine(gd, extra: ""), chevron: canGd, tap: canGd ? { [weak self] in self?.pickGuardian() } : nil)) }
    else if canGd { g.append(row(sym: "star", key: "Guardian", value: greyText("None"), chevron: true, tap: { [weak self] in self?.pickGuardian() })) }
    blocks.append(group(g))
    // ---- Review ----
    var r: [UIView] = []
    if let rv = m["review"] as? [String: Any] {
      let sw = UISwitch(); sw.isOn = (rv["on"] as? Bool) == true; sw.isEnabled = (rv["canSet"] as? Bool) == true
      sw.addAction(UIAction { [weak self, weak sw] _ in guard let self = self, let sw = sw else { return }; self.onAct?(["act": "needsCD", "id": self.taskId, "value": sw.isOn]) }, for: .valueChanged)
      let who = (rv["on"] as? Bool) == true ? (rv["who"] as? String ?? "") : ""
      r.append(row(sym: "checkmark.shield", key: "Needs CD review", sub: who.isEmpty ? nil : who, value: sw))
    }
    if let ca = m["clientApproval"] as? [String: Any] { r.append(clientApprovalRow(ca)) }
    if (m["sub"] as? Bool) != true { r.append(updateRow(m["update"] as? [String: Any], all: (m["updates"] as? [String]) ?? [], can: (m["canFields"] as? Bool) == true)) }
    if !r.isEmpty { blocks.append(header("Review")); blocks.append(group(r)) }
    // ---- Description ----
    let desc = m["desc"] as? String ?? ""
    let canDesc = (m["canDesc"] as? Bool) == true
    if !desc.isEmpty || canDesc || editingDesc {
      blocks.append(header("Description", lock: m["lock"] != nil))
      // (edited right where it is, looking the same — DescEditor.swift)
      let tv = descView
      if !editingDesc { tv.attributedText = desc.isEmpty ? NSAttributedString(string: "Add a description… Type @ to mention someone", attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.tertiaryLabel]) : DescEditor.attributed((m["descRuns"] as? [[String: Any]]) ?? [], done: (m["done"] as? Bool) == true) }
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
    // ---- Files ----
    let files = (m["files"] as? [[String: Any]]) ?? []
    if !files.isEmpty {
      blocks.append(header("Files · \(files.count)"))
      blocks.append(group(files.prefix(12).map { f in row(sym: TaskPage.fileSym(f["name"] as? String ?? ""), key: f["name"] as? String ?? "File", value: greyText(TaskPage.size(f["size"] as? Int ?? 0)), keyLines: 1) }))
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
    blocks.forEach { if $0.superview !== content { content.addSubview($0) } }
    // Mark complete: only when this person may complete it
    if let c = m["complete"] as? [String: Any], (c["show"] as? Bool) == true { fab.isHidden = false } else { fab.isHidden = true }
    layoutContent()
    scroll.contentOffset.y = min(max(-scroll.contentInset.top, keepY), max(-scroll.contentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.contentInset.bottom))
  }
  private func layoutContent() {
    let W = bounds.width
    var y: CGFloat = 4
    for b in blocks {
      let x: CGFloat = 16, w = W - 32
      let h: CGFloat
      if b === titleView { h = ceil(titleView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height); y += 2 }
      else { b.frame.size.width = w; b.setNeedsLayout(); b.layoutIfNeeded(); h = b.systemLayoutSizeFitting(CGSize(width: w, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height }
      b.frame = CGRect(x: x, y: y, width: w, height: h)
      y += h + ((b.tag == 7) ? 7 : 16)
    }
    let bottom = max(safeAreaInsets.bottom, 20) + (fab.isHidden ? 16 : 72)
    content.frame = CGRect(x: 0, y: 0, width: W, height: y)
    scroll.contentSize = CGSize(width: W, height: y)
    scroll.contentInset.bottom = bottom
  }

  // ---------- row pieces ----------
  private func label(_ t: String, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular) -> UILabel {
    let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; return l
  }
  private func greyText(_ t: String) -> UILabel { label(t, size: 17, color: .secondaryLabel) }
  private func symbol(_ s: String, _ size: CGFloat, _ c: UIColor, weight: UIImage.SymbolWeight = .regular) -> UIImageView {
    let i = UIImageView(image: UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight)))
    i.tintColor = c; i.contentMode = .center; i.setContentHuggingPriority(.required, for: .horizontal); return i
  }
  private func header(_ t: String, lock: Bool = false) -> UIView {
    let l = label(t.uppercased(), size: 13, color: .secondaryLabel)
    let s = UIStackView(arrangedSubviews: [l]); s.spacing = 5; s.alignment = .center
    if lock { s.addArrangedSubview(symbol("lock.fill", 10, .secondaryLabel)) }
    s.addArrangedSubview(UIView())
    s.isLayoutMarginsRelativeArrangement = true
    s.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    s.tag = 7   // (closer to its group)
    return s
  }
  private func pad(_ v: UIView, v vv: CGFloat = 12) -> UIView {
    let b = UIView(); v.translatesAutoresizingMaskIntoConstraints = false; b.addSubview(v)
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 16), v.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -16), v.topAnchor.constraint(equalTo: b.topAnchor, constant: vv), v.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -vv)])
    return b
  }
  // a rounded group of rows with thin lines between them (as iPhone's Settings)
  private func group(_ rows: [UIView]) -> UIView {
    let g = UIStackView(); g.axis = .vertical
    g.backgroundColor = .secondarySystemGroupedBackground
    g.layer.cornerRadius = 22; g.layer.cornerCurve = .continuous; g.clipsToBounds = true
    for (i, r) in rows.enumerated() {
      if i > 0 {
        let line = UIView(); line.backgroundColor = .separator
        let wrap = UIView(); wrap.addSubview(line); line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 52), line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor), line.topAnchor.constraint(equalTo: wrap.topAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale), wrap.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)])
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
    let k = label(key, size: 17, color: .label); k.numberOfLines = keyLines
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
      ic.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 16), ic.widthAnchor.constraint(equalToConstant: 24), ic.centerYAnchor.constraint(equalTo: r.centerYAnchor),
      h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 52), h.trailingAnchor.constraint(equalTo: r.trailingAnchor, constant: -16),
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
  private func avatars(_ list: [[String: Any]]) -> UIView {
    let s = UIStackView(); s.spacing = -6; s.alignment = .center
    for a in list.prefix(5) {
      guard let id = a["id"] as? String else { continue }
      let v = avatar(id, 30, ring: true)
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
  private func statusRow(_ s: [String: Any]) -> UIView {
    let can = (s["canSet"] as? Bool) == true
    let v = UIStackView(); v.spacing = 8; v.alignment = .center
    v.addArrangedSubview(pill(s["name"] as? String ?? "", fg: .white, bg: TaskPage.rgb(s["rgb"])))
    var menu: UIMenu?
    if can {
      let opts = (s["options"] as? [[String: Any]]) ?? []
      menu = UIMenu(title: "Status", children: opts.map { o in
        let img = UIImage(systemName: "circle.fill")?.withTintColor(TaskPage.rgb(o["rgb"]), renderingMode: .alwaysOriginal)
        let locked = (o["locked"] as? Bool) == true
        return UIAction(title: o["name"] as? String ?? "", subtitle: locked ? "Waiting for CD approval" : nil, image: locked ? UIImage(systemName: "lock.fill") : img, attributes: locked ? .disabled : [], state: (o["on"] as? Bool) == true ? .on : .off) { [weak self] _ in
          guard let self = self, let id = o["id"] as? String else { return }
          self.setStatus(id)
        }
      })
      if let next = s["next"] as? String {
        var c: UIButton.Configuration = .gray(); c.cornerStyle = .capsule
        c.attributedTitle = AttributedString("Next", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]))
        c.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)); c.imagePlacement = .trailing; c.imagePadding = 4
        c.baseForegroundColor = .label
        c.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 10)
        let b = UIButton(configuration: c)
        b.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.setStatus(next) }, for: .touchUpInside)
        v.addArrangedSubview(b)
      }
    }
    let why = s["why"] as? String ?? ""
    return row(sym: "circle.lefthalf.filled", key: "Status", sub: why.isEmpty ? nil : why, value: v, chevron: false, menu: menu)
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
        } else if (rv["canSubmit"] as? Bool) != true { self.toast("Move the task to In Progress first") }
        else { self.onSubmitFiles?(rv["cd"] as? String ?? "") }
      }, for: .touchUpInside)
      let bw = UIView(); b.translatesAutoresizingMaskIntoConstraints = false; bw.addSubview(b)
      NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: bw.leadingAnchor, constant: 52), b.topAnchor.constraint(equalTo: bw.topAnchor), b.bottomAnchor.constraint(equalTo: bw.bottomAnchor, constant: -12), b.trailingAnchor.constraint(lessThanOrEqualTo: bw.trailingAnchor, constant: -16)])
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
    NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: bw.leadingAnchor, constant: 52), b.topAnchor.constraint(equalTo: bw.topAnchor), b.bottomAnchor.constraint(equalTo: bw.bottomAnchor, constant: -12), b.trailingAnchor.constraint(lessThanOrEqualTo: bw.trailingAnchor, constant: -16)])
    wrap.addArrangedSubview(bw)
    return wrap
  }
  private func datesRow(_ d: [String: Any]) -> UIView {
    let can = (d["canEdit"] as? Bool) == true
    let start = d["startLabel"] as? String ?? "", due = d["dueLabel"] as? String ?? ""
    func btn(_ t: String, empty: String, color: UIColor, which: String, value: String) -> UIView {
      if !can { return label(t.isEmpty ? empty : t, size: 17, color: t.isEmpty ? .tertiaryLabel : color) }
      var c: UIButton.Configuration = .plain()
      c.attributedTitle = AttributedString(t.isEmpty ? empty : t, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17)]))
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
      let menu: UIMenu? = can ? UIMenu(title: who.isEmpty ? "Priority" : (who == "You" ? "Your priority" : who + "’s priority"), children: prioItems(key, cur: p["v"] as? String ?? "")) : nil
      return row(sym: "flag", key: who.isEmpty || list.count == 1 && key == (model?["me"] as? String) ? "Priority" : "Priority · " + who, value: v, chevron: can, menu: menu)
    }
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
    UISelectionFeedbackGenerator().selectionChanged()
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
    var menu: UIMenu?
    if can {
      var items: [UIMenuElement] = all.map { x in UIAction(title: x, state: x == cur ? .on : .off) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "update", "id": self.taskId, "value": x]) } }
      if !cur.isEmpty { items.insert(UIMenu(options: .displayInline, children: [UIAction(title: "Clear", attributes: .destructive) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "update", "id": self.taskId, "value": NSNull()]) }]), at: 0) }
      menu = UIMenu(title: "Task Update", children: items)
    }
    return row(sym: "arrow.triangle.2.circlepath", key: "Task Update", value: v, chevron: can, menu: menu)
  }
  private func subRow(_ s: [String: Any], ro: Bool) -> UIView {
    let id = s["id"] as? String ?? "", done = (s["done"] as? Bool) == true
    let r = TaskRow()
    let tick = UIButton(type: .custom)
    tick.setImage(UIImage(systemName: done ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)), for: .normal)
    tick.tintColor = done ? .systemGreen : .tertiaryLabel
    tick.isEnabled = (s["canTick"] as? Bool) == true
    tick.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      if !done { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      self.onAct?(["act": done ? "reopen" : "done", "id": id, "page": self.taskId])
    }, for: .touchUpInside)
    let t = label(s["title"] as? String ?? "", size: 17, color: done ? .secondaryLabel : .label)
    if done { t.attributedText = NSAttributedString(string: t.text ?? "", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: 17)]) }
    t.lineBreakMode = .byTruncatingTail
    let h = UIStackView(arrangedSubviews: [tick, t]); h.spacing = 12; h.alignment = .center
    t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    if let av = s["av"] as? String { h.addArrangedSubview(avatar(av, 22)) }
    if let due = s["due"] as? String, !due.isEmpty { h.addArrangedSubview(label(due, size: 15, color: (s["late"] as? Bool) == true ? .systemRed : .secondaryLabel)) }
    h.addArrangedSubview(symbol("chevron.right", 13, .tertiaryLabel, weight: .semibold))
    h.translatesAutoresizingMaskIntoConstraints = false; r.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 14), h.trailingAnchor.constraint(equalTo: r.trailingAnchor, constant: -16), h.topAnchor.constraint(equalTo: r.topAnchor, constant: 9), h.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -9), r.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)])
    r.onTap = { [weak self] in self?.onOpen?(id) }
    return r
  }
  private func checkRow(_ c: [String: Any], can: Bool) -> UIView {
    let id = c["id"] as? String ?? "", done = (c["done"] as? Bool) == true
    let r = TaskRow()
    let box = symbol(done ? "checkmark.square.fill" : "square", 20, done ? .systemBlue : .tertiaryLabel)
    let t = label(c["text"] as? String ?? "", size: 17, color: done ? .secondaryLabel : .label); t.numberOfLines = 0
    if done { t.attributedText = NSAttributedString(string: t.text ?? "", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: 17)]) }
    let h = UIStackView(arrangedSubviews: [box, t]); h.spacing = 12; h.alignment = .center
    h.translatesAutoresizingMaskIntoConstraints = false; r.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 16), h.trailingAnchor.constraint(equalTo: r.trailingAnchor, constant: -16), h.topAnchor.constraint(equalTo: r.topAnchor, constant: 13), h.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -13)])
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
    let h = UIStackView(arrangedSubviews: [symbol("plus.circle.fill", 20, .systemBlue), label(t, size: 17, color: .systemBlue)]); h.spacing = 12; h.alignment = .center
    h.translatesAutoresizingMaskIntoConstraints = false; r.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 15), h.trailingAnchor.constraint(lessThanOrEqualTo: r.trailingAnchor, constant: -16), h.topAnchor.constraint(equalTo: r.topAnchor, constant: 13), h.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -13)])
    r.onTap = tap
    return r
  }
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
    onSheet?(["sections": [["header": "Assignees", "rows": rows]], "multi": true, "search": "Search people"], { [weak self] i in
      guard let self = self, i >= 0, i < pool.count, let id = pool[i]["id"] as? String else { return }
      on[i].toggle()
      UISelectionFeedbackGenerator().selectionChanged()
      self.onAct?(["act": "assign", "id": self.taskId, "key": id, "value": on[i]])
    }, { _, _ in })
  }
  func pickGuardian() {
    guard let pool = model?["pool"] as? [[String: Any]] else { return }
    let cur = model?["guardian"] as? String
    var rows: [[String: Any]] = pool.enumerated().map { i, p in ["i": i, "label": p["name"] as? String ?? "", "sub": p["role"] as? String ?? "", "person": personArg(p), "checked": (p["id"] as? String) == cur, "find": p["name"] as? String ?? ""] }
    if cur != nil { rows.append(["i": 999, "label": "No Guardian", "icon": "x"]) }
    onSheet?(["sections": [["header": "Guardian", "rows": rows]], "search": "Search people"], { _ in }, { [weak self] i, _ in
      guard let self = self, i >= 0 else { return }
      var v: Any = NSNull()
      if i != 999, i < pool.count, let id = pool[i]["id"] as? String { v = id }
      self.onAct?(["act": "guardian", "id": self.taskId, "value": v])
    })
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
    onSheet?(["sections": [["header": "Move to client", "rows": rows]], "search": "Search clients"], { _ in }, { [weak self] i, _ in
      guard let self = self, i >= 0, i < list.count, (list[i]["on"] as? Bool) != true, let id = list[i]["id"] as? String else { return }
      self.onAct?(["act": "client", "id": self.taskId, "value": id])
    })
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
    if tv === descView { return true }
    if text == "\n" { tv.resignFirstResponder(); return false }
    return true
  }
  func textViewDidBeginEditing(_ tv: UITextView) { if tv === descView { beginDesc() } }
  func textViewDidChange(_ tv: UITextView) { setNeedsLayout(); if tv === descView { descChanged() } }
  func textViewDidEndEditing(_ tv: UITextView) {
    if tv === descView { return }
    let v = tv.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let was = model?["title"] as? String ?? ""
    if v.isEmpty { tv.text = was; return }
    if v != was { onAct?(["act": "title", "id": taskId, "value": v]) }
  }

  // ---------- a short message, low on the screen ----------
  func toast(_ text: String) {
    toastView?.removeFromSuperview()
    let v = UIView(); v.backgroundColor = .secondarySystemGroupedBackground; v.layer.cornerRadius = 14; v.layer.cornerCurve = .continuous
    v.layer.shadowColor = UIColor.black.cgColor; v.layer.shadowOpacity = 0.18; v.layer.shadowRadius = 12; v.layer.shadowOffset = CGSize(width: 0, height: 4)
    let l = label(text, size: 15, color: .label, weight: .medium); l.numberOfLines = 2; l.textAlignment = .center
    v.addSubview(l)
    let W = bounds.width, ls = l.sizeThatFits(CGSize(width: W - 64, height: 60))
    let w = ls.width + 32, h = max(44, ls.height + 20)
    let bottom = (fab.isHidden || tab == "comments" ? bounds.height - max(safeAreaInsets.bottom, 20) - 8 : fab.frame.minY - 10)
    v.frame = CGRect(x: (W - w) / 2, y: bottom - h, width: w, height: h)
    l.frame = CGRect(x: 16, y: (h - ls.height) / 2, width: ls.width, height: ls.height)
    v.alpha = 0; v.transform = CGAffineTransform(translationX: 0, y: 8)
    addSubview(v); toastView = v
    UIView.animate(withDuration: 0.16) { v.alpha = 1; v.transform = .identity }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self, weak v] in
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
final class TaskRow: UIView {
  var onTap: (() -> Void)? { didSet { if onTap != nil && tapG == nil { let g = UITapGestureRecognizer(target: self, action: #selector(tapped)); addGestureRecognizer(g); tapG = g } } }
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
