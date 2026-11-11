import UIKit

/* The Inbox as its own screen in Apple's tab container (Haris 2026-11-08 — it follows Home, as My Tasks): its tab is its
   own navigation with this screen at its root. Apple's bar from the start: the big title "Inbox" with its line under it
   (how many unread), "Mark all read" (or "Mark all unread", asked first) and your photo as Apple's own bar buttons. No
   search (Haris). All / Unread / Mentions stay as Mail's buttons, at the top of Apple's list, scrolling away with it as
   Mail's do (Haris: "Same as mail"); the rows Apple's own list cells (InboxCell, Home.swift), edge to edge as Mail's, with
   Apple's own swipe (Read / Unread) and Apple's peek on a hold (InboxPeekVC, below). "+ New task" as before. */
let APPLE_INBOX = APPLE_NAV

// a tab's first screen with its own Apple navigation (Home, My Tasks, the Inbox)
protocol TabRoot: UIViewController {}
extension HomeVC: TabRoot {}
extension MyTasksVC: TabRoot {}

final class InboxVC: UIViewController, TabRoot {
  static weak var shared: InboxVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); InboxVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = HomeLook.bg; view = v }   // (Home's own background, as every page — Haris 2026-11-11)
  private var meItem: UIBarButtonItem?
  private var markItem: UIBarButtonItem?
  private var mePhoto: UIImage?
  private var markKind = "", markText = ""

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = "Inbox"
    let me = UIBarButtonItem(image: BarImage.me(nil, traitCollection), primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.inboxIfMade?.meTap() })
    me.accessibilityLabel = "Me"
    BarImage.bare(me)
    meItem = me
    // "Mark all read" / "Mark all unread": Apple's own bar button with its words
    let mark = UIBarButtonItem(title: "Mark all read", primaryAction: UIAction { [weak self] _ in
      guard let self = self, !self.markKind.isEmpty else { return }
      Main.shared.inboxIfMade?.cornerTap(self.markKind)
    })
    mark.tintColor = .label
    mark.accessibilityIdentifier = "mark-all-read"
    markItem = mark
    navigationItem.rightBarButtonItems = [me]
    if #available(iOS 17.0, *) { registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: InboxVC, _: UITraitCollection) in vc.paintMe() } }
    // (its screen in it from the start — made now if it wasn't: the tab never comes up empty, and Apple's bar has its list
    //  before the first look — Haris 2026-11-08: a black flash, the big title cut, on each tab's first open)
    BigLine.prime(self, "inbox")   // (its line there before it first shows, as Home's date)
    if APPLE_INBOX { adopt(Main.shared.inboxView) } else if let h = Main.shared.inboxIfMade { adopt(h) }
  }
  // (where the tab bar starts, for "+ New task" and the list's end — as Home's screen does)
  // (its list drawn from what the phone kept before it first shows — never an empty tab: Haris 2026-11-08)
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    Main.shared.drawBeforeShow("inbox")
  }
  override func viewDidAppear(_ a: Bool) {
    super.viewDidAppear(a)
    // (Apple's bar told this page's list again each time it shows — on the phone the bar was left following another, empty
    //  list in the page and the big title stuck; the cause not found: Haris's exception, 2026-11-09 19:15)
    if let h = Main.shared.inboxIfMade { setContentScrollView(h.appleScroll, for: .top) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let m = Main.shared
    if let h = m.inboxIfMade, h.superview === view { h.tabTop = m.homeTabTop }
  }
  func adopt(_ h: HomeView) {
    loadViewIfNeeded()
    if h.superview !== view {
      h.removeFromSuperview()
      h.frame = view.bounds; h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(h, at: 0)
    }
    view.backgroundColor = h.backgroundColor ?? view.backgroundColor
    h.onAppleTitle = { [weak self] _, d in self?.setLine(d) }
    h.onAppleMe = { [weak self] img in if let img = img { self?.mePhoto = img; self?.paintMe() } }
    h.onAppleCorner = { [weak self, weak h] in self?.showMark(h?.corner()) }
    h.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    h.useAppleTop()
    setContentScrollView(h.appleScroll, for: .top)
    showMark(h.corner())
  }
  func paintMe() { meItem?.image = BarImage.me(mePhoto, traitCollection) }
  var markShown: String { markKind }   // (for the self-test: "read", "unread" or "" — the bar button showing)
  // Mark all read (unread ones in the list) or Mark all unread (none unread, rows in the list) — or neither
  private func showMark(_ c: (kind: String, text: String, frame: CGRect)?) {
    let kind = c.map { $0.kind == "read" || $0.kind == "unread" ? $0.kind : "" } ?? ""
    let text = c?.text ?? ""
    guard kind != markKind || text != markText else { return }
    markKind = kind; markText = text
    guard let me = meItem, let mark = markItem else { return }
    if kind.isEmpty { navigationItem.rightBarButtonItems = [me]; return }
    mark.title = c?.text
    navigationItem.rightBarButtonItems = [me, .fixedSpace(0), mark]
  }
  private var shownLine: String?
  private func setLine(_ d: String) {
    guard d != shownLine else { return }
    shownLine = d
    BigLine.set(self, d, "inbox")
  }
}

/* Hold a row in the Inbox: Apple's own peek (Haris 2026-11-09 23:42 "I like this"; mock-up "Inbox — with the rules", Peek).
   Apple lifts it, blurs the list and puts its menu under it; the preview inside is ours, drawn from the phone's copy — at
   once, offline too. Peeking neither opens the task nor marks it read; tapping the preview opens it, as the row's tap.
   - A comment (or a reply, a mention, amendments): the task's client, name and status at the top, the comment in full
     (pictures too) as the comments page draws it, the one before it faded for its context.
   - Anything else about a task (assigned, status, due…): the task's key facts as Apple's rows and the start of its
     description.
   Not about a task (a birthday, the round-up, Client Assets…): no peek — Apple's own lift of the row. */
final class InboxPeekVC: UIViewController {
  let taskId: String
  private(set) var commentText: String?
  private let task: [String: Any]
  private let shown: [[String: Any]]   // (the comment and the one before it — empty for a change)
  private let people: [String: [String: Any]]
  private let me: String
  // what the notification is about, from the phone's copy (nil: not a task, or not in the copy)
  static func make(_ nid: String) -> InboxPeekVC? {
    guard let res = AppData.shared.meModel("tasks", "notifOpen", [nid, [String: Any]()]), let go = res["go"] as? [String: Any],
          (go["to"] as? String) == "task", let id = go["id"] as? String, !id.isEmpty,
          let t = AppData.shared.screen("task", id).model else { return nil }
    var focus = go["focus"] as? String ?? ""
    if let r = focus.range(of: "~") { focus = String(focus[r.upperBound...]) }
    var shown: [[String: Any]] = [], people: [String: [String: Any]] = [:], me = t["me"] as? String ?? ""
    if !focus.isEmpty {
      // the comment where it is — among the task's comments, or in its thread
      let thread = go["thread"] as? String
      for th in [thread, nil] as [String?] where shown.isEmpty {
        guard let f = AppData.shared.screen("comments", id, th).model else { continue }
        let items = (f["items"] as? [[String: Any]]) ?? []
        if let i = items.firstIndex(where: { ($0["id"] as? String) == focus }) {
          shown = (i > 0 ? [items[i - 1]] : []) + [items[i]]
          people = (f["people"] as? [String: [String: Any]]) ?? [:]; me = f["me"] as? String ?? me
        }
      }
    }
    return InboxPeekVC(task: t, id: id, shown: shown, people: people, me: me)
  }
  private init(task: [String: Any], id: String, shown: [[String: Any]], people: [String: [String: Any]], me: String) {
    self.task = task; self.taskId = id; self.shown = shown; self.people = people; self.me = me
    commentText = shown.last?["text"] as? String
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  private let stack = UIStackView()
  private var fitH: CGFloat = 0
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = HomeLook(Main.shared.lookBoth).bg
    view.clipsToBounds = true
    stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill
    view.addSubview(stack)
    let W = UIScreen.main.bounds.width - 32
    let maxH = UIScreen.main.bounds.height * 0.62   // (Apple's menu needs its room under it)
    let head = headBlock()
    stack.addArrangedSubview(head)
    stack.addArrangedSubview(line())
    if shown.isEmpty { stack.addArrangedSubview(factsBlock()) }
    else {
      // the notified comment always whole; the one before it only as much as fits (its start, faded) — none if there's no
      // room (Haris 2026-11-10: a long one before it squeezed the notified one and the task's name away)
      let headH = fitted(head, W) + 1
      let focusH = CommentCell(shown[shown.count - 1], people: people, me: me, thread: false, root: false).height(for: W)
      let room = maxH - headH - 16 - focusH
      stack.addArrangedSubview(gap(8))
      if shown.count > 1, room >= 70 {
        // (cut short: its card keeps its rounded bottom and its words fade into the card — no sharp edge: Haris 2026-11-10)
        let prev = CommentCell(shown[0], people: people, me: me, thread: false, root: true)
        prev.isUserInteractionEnabled = false
        let full = prev.height(for: W), h = min(full, room, 130)
        let wrap = UIView(); wrap.alpha = 0.6
        let shape = UIView(frame: CGRect(x: 16, y: 6, width: W - 32, height: h - 12))
        shape.layer.cornerRadius = 18; shape.layer.cornerCurve = .continuous; shape.clipsToBounds = true
        wrap.addSubview(shape)
        shape.addSubview(prev); prev.frame = CGRect(x: -16, y: -6, width: W, height: full)
        if full > h {
          let fade = CAGradientLayer()
          // (a layer's colours: set again when the phone's look changes — the light / dark rule's followLook)
          let paint: (UITraitCollection) -> Void = { tc in let card = HomeLook(Main.shared.lookBoth).card.resolvedColor(with: tc); fade.colors = [card.withAlphaComponent(0).cgColor, card.cgColor] }
          paint(traitCollection)
          shape.followLook("fade", paint)
          fade.frame = CGRect(x: 0, y: max(0, shape.bounds.height - 44), width: shape.bounds.width, height: min(44, shape.bounds.height))
          shape.layer.addSublayer(fade)
        }
        wrap.heightAnchor.constraint(equalToConstant: h).isActive = true
        stack.addArrangedSubview(wrap)
      }
      let c = CommentCell(shown[shown.count - 1], people: people, me: me, thread: false, root: false)
      c.isUserInteractionEnabled = false
      c.heightAnchor.constraint(equalToConstant: focusH).isActive = true
      stack.addArrangedSubview(c)
      stack.addArrangedSubview(gap(8))
    }
    fitH = fitted(stack, W)
    preferredContentSize = CGSize(width: W, height: min(fitH, maxH))
  }
  private func fitted(_ v: UIView, _ W: CGFloat) -> CGFloat {
    ceil(v.systemLayoutSizeFitting(CGSize(width: W, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
  }
  private func gap(_ h: CGFloat) -> UIView { let p = UIView(); p.heightAnchor.constraint(equalToConstant: h).isActive = true; return p }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // (its own height, never squeezed into the preview's: the task's name and the comment keep their room)
    stack.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: max(fitH, view.bounds.height))
  }
  // the client, the task's name, its status (and due, priority) as chips
  private func headBlock() -> UIView {
    let v = UIStackView(); v.axis = .vertical; v.spacing = 4; v.isLayoutMarginsRelativeArrangement = true
    v.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16)
    if let c = task["client"] as? [String: Any] {
      let dot = UIView(); dot.backgroundColor = TaskPage.rgb(c["rgb"]); dot.layer.cornerRadius = 4.5
      dot.widthAnchor.constraint(equalToConstant: 9).isActive = true; dot.heightAnchor.constraint(equalToConstant: 9).isActive = true
      let n = UILabel(); n.text = c["name"] as? String; n.font = .systemFont(ofSize: 13); n.textColor = .secondaryLabel
      let r = UIStackView(arrangedSubviews: [dot, n, UIView()]); r.spacing = 8; r.alignment = .center
      v.addArrangedSubview(r)
    }
    let t = UILabel(); t.text = (task["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled task"
    t.font = .systemFont(ofSize: 19, weight: .bold); t.numberOfLines = 2
    t.setContentCompressionResistancePriority(.required, for: .vertical)
    v.addArrangedSubview(t)
    var chips: [UIView] = []
    if let s = task["status"] as? [String: Any], let name = s["name"] as? String, !name.isEmpty {
      let col = TaskPage.rgb(s["rgb"]); chips.append(chip((task["done"] as? Bool) == true ? "Done" : name, col.withAlphaComponent(0.18), col))
    }
    if let d = task["dates"] as? [String: Any], let due = d["dueLabel"] as? String, !due.isEmpty, (task["done"] as? Bool) != true {
      let late = (d["late"] as? Bool) == true, today = (d["today"] as? Bool) == true
      let col: UIColor = late ? .systemRed : today ? .systemOrange : .secondaryLabel
      chips.append(chip("Due " + due, (late || today ? col : UIColor.systemGray).withAlphaComponent(0.16), col))
    }
    if !chips.isEmpty {
      let r = UIStackView(arrangedSubviews: chips + [UIView()]); r.spacing = 6; r.alignment = .center
      v.setCustomSpacing(6, after: t)
      v.addArrangedSubview(r)
    }
    return v
  }
  private func chip(_ s: String, _ bg: UIColor, _ fg: UIColor) -> UIView {
    let c = PaddedLabel(); c.text = s; c.font = .systemFont(ofSize: 13, weight: .semibold); c.textColor = fg
    c.backgroundColor = bg; c.layer.cornerRadius = 10; c.layer.cornerCurve = .continuous; c.clipsToBounds = true
    c.insets = UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)
    return c
  }
  private func line() -> UIView {
    let l = UIView(); l.backgroundColor = .separator
    l.heightAnchor.constraint(equalToConstant: 1 / max(1, UIScreen.main.scale)).isActive = true
    return l
  }
  // a change: the task's key facts as Apple's rows, then the start of its description
  private func factsBlock() -> UIView {
    let v = UIStackView(); v.axis = .vertical; v.spacing = 0
    let name = { (id: String) -> String in id == (self.task["me"] as? String) ? "You" : (self.people[id]?["name"] as? String) ?? (self.taskPeople[id]?["name"] as? String) ?? "Someone" }
    var facts: [(String, String, UIColor)] = []
    if let c = task["creator"] as? [String: Any], let id = c["id"] as? String { facts.append(("Created by", name(id), .label)) }
    let who = ((task["assignees"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.map(name)
    if !who.isEmpty { facts.append((who.count == 1 ? "Assignee" : "Assignees", ListFormatter.localizedString(byJoining: who), .label)) }
    if let d = task["dates"] as? [String: Any], let due = d["dueLabel"] as? String, !due.isEmpty {
      facts.append(("Due", due, (d["late"] as? Bool) == true ? .systemRed : (d["today"] as? Bool) == true ? .systemOrange : .label))
    }
    // (the priority: yours if you're on it, else the task's first)
    let prios = (task["prio"] as? [[String: Any]]) ?? []
    let mine = prios.first { ($0["key"] as? String) == (task["me"] as? String) } ?? prios.first { !(($0["label"] as? String) ?? "").isEmpty }
    if let p = mine?["label"] as? String, !p.isEmpty {
      facts.append(("Priority", p == "Urgent" ? "Urgent" : "Priority \(p)", p == "Urgent" || p == "1" ? .systemRed : .label))
    }
    for (i, f) in facts.enumerated() {
      var c = UIListContentConfiguration.valueCell()
      c.text = f.0; c.textProperties.color = .secondaryLabel
      c.secondaryText = f.1; c.secondaryTextProperties.color = f.2; c.secondaryTextProperties.font = .systemFont(ofSize: 17, weight: .medium)
      c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
      let row = UIListContentView(configuration: c)
      v.addArrangedSubview(row)
      if i < facts.count - 1 { let l = line(); let w = UIView(); w.addSubview(l); l.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: w.leadingAnchor, constant: 16), l.trailingAnchor.constraint(equalTo: w.trailingAnchor), l.topAnchor.constraint(equalTo: w.topAnchor), l.bottomAnchor.constraint(equalTo: w.bottomAnchor)])
        v.addArrangedSubview(w) }
    }
    if let d = task["desc"] as? String, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let l = UILabel(); l.text = d; l.numberOfLines = 4; l.font = .systemFont(ofSize: 15); l.textColor = .secondaryLabel
      let w = UIStackView(arrangedSubviews: [l]); w.isLayoutMarginsRelativeArrangement = true
      w.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16)
      v.addArrangedSubview(w)
    } else {
      let p = UIView(); p.heightAnchor.constraint(equalToConstant: 6).isActive = true; v.addArrangedSubview(p)
    }
    return v
  }
  private var taskPeople: [String: [String: Any]] { (task["people"] as? [String: [String: Any]]) ?? [:] }
}
