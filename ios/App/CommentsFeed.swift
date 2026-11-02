import UIKit

/* A task's Comments, the app's own (step 2, Haris 2026-11-01): drawn from the server (/api/comments), newest at the
   bottom. Pictures and link cards keep their size from the start (a loading shimmer inside), so nothing moves while
   they arrive. Touch and hold a comment for the reactions, Reply, Copy and Delete; "N replies" opens the thread on a
   page of its own (sliding in like the task page); coming back, that card pulses as WhatsApp's do. Away from the
   bottom a round glass ↓ shows; comments arriving meanwhile make it a "N new comments ↓" pill. Writing still goes
   through the comment box (CommentBar) and the comments screen behind it until step 3. */
final class FeedLoader {
  static let shared = FeedLoader()
  var cookies: (@escaping (String) -> Void) -> Void = { $0("") }
  private let cache = NSCache<NSString, UIImage>()
  private var links: [String: [String: Any]] = [:]
  func image(_ path: String, _ done: @escaping (UIImage?) -> Void) {
    if let i = cache.object(forKey: path as NSString) { return done(i) }
    cookies { c in
      guard let url = URL(string: path.hasPrefix("http") ? path : serverURL() + path) else { return done(nil) }
      var r = URLRequest(url: url); if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
      URLSession.shared.dataTask(with: r) { d, _, _ in
        let img = d.flatMap { UIImage(data: $0) }
        if let img = img { self.cache.setObject(img, forKey: path as NSString) }
        DispatchQueue.main.async { done(img) }
      }.resume()
    }
  }
  func data(_ path: String, _ done: @escaping (Data?) -> Void) {
    cookies { c in
      guard let url = URL(string: path.hasPrefix("http") ? path : serverURL() + path) else { return done(nil) }
      var r = URLRequest(url: url); if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
      URLSession.shared.dataTask(with: r) { d, _, _ in DispatchQueue.main.async { done(d) } }.resume()
    }
  }
  func link(_ u: String, _ done: @escaping ([String: Any]?) -> Void) {
    if let l = links[u] { return done(l) }
    cookies { c in
      guard let q = u.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: serverURL() + "/api/link?u=" + q) else { return done(nil) }
      var r = URLRequest(url: url); if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
      URLSession.shared.dataTask(with: r) { d, _, _ in
        let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        DispatchQueue.main.async { if let j = j { self.links[u] = j }; done(j) }
      }.resume()
    }
  }
  func get(_ path: String, _ done: @escaping ([String: Any]?) -> Void) {
    cookies { c in
      guard let url = URL(string: serverURL() + path) else { return done(nil) }
      var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData); if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
      r.setValue("application/json", forHTTPHeaderField: "Accept")
      URLSession.shared.dataTask(with: r) { d, resp, _ in
        let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200
        let j = ok ? d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
        DispatchQueue.main.async { done(j) }
      }.resume()
    }
  }
  func post(_ path: String, _ body: [String: Any]) {
    cookies { c in
      guard let url = URL(string: serverURL() + path) else { return }
      var r = URLRequest(url: url); r.httpMethod = "POST"; if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
      r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: body)
      URLSession.shared.dataTask(with: r).resume()
    }
  }
}

final class CommentsFeed: UIView, UIScrollViewDelegate {
  let taskId: String
  let thread: String?
  var onAct: (([String: Any]) -> Void)?             // react / deleteComment (the server's)
  var onReply: ((String, String, [String: Any]?) -> Void)?   // Reply: the box replies to this comment (its writer's name, and them — their picture)
  var onEdit: ((String, [[String: Any]]) -> Void)?   // Edit (its first 10 minutes): the words back in the box
  var onThread: ((String) -> Void)?                  // "N replies" → the thread's page
  var onBack: (() -> Void)?                          // (a thread page) back to the comments
  var onToast: ((String) -> Void)?
  var onLoaded: (([String: Any]) -> Void)?
  var onOpenFile: (([[String: Any]], Int) -> Void)?
  var onSheet: (([String: Any], @escaping (Int, String?) -> Void) -> Void)?
  let scroll = UIScrollView()
  private let content = UIView()
  private var cells: [String: CommentCell] = [:]
  private var order: [String] = []
  private(set) var model: [String: Any]?
  var people: [String: [String: Any]] = [:]
  private let jump = UIButton(type: .custom)
  private let jumpFx = UIVisualEffectView(effect: nil)
  private let jumpLabel = UILabel()
  private var seenIds = Set<String>()                 // (what was there when last at the bottom: anything else is new)
  private var first = true
  var topInset: CGFloat = 0 { didSet { setNeedsLayout() } }
  var bottomRoom: CGFloat = 100 { didSet { if oldValue != bottomRoom { roomChanged(oldValue) } } }
  private let threadBar = UIView()
  // where the comment box's top is (on screen, following the keyboard frame by frame): the room kept under the list
  var boxTop: (() -> CGFloat?)?
  private var link: CADisplayLink?
  override func didMoveToWindow() {
    super.didMoveToWindow()
    link?.invalidate(); link = nil
    if window != nil { let l = CADisplayLink(target: self, selector: #selector(tick)); l.add(to: .main, forMode: .common); link = l }
  }
  @objc private func tick() {
    guard let top = boxTop?(), let w = window else { return }
    let mine = convert(bounds, to: w)
    let room = max(0, mine.maxY - top) + 6
    if abs(room - bottomRoom) > 0.5 { bottomRoom = room }
  }

  init(task: String, thread: String?) {
    taskId = task; self.thread = thread
    super.init(frame: .zero)
    backgroundColor = .systemGroupedBackground
    scroll.alwaysBounceVertical = true
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.keyboardDismissMode = .interactive   // (dragging down takes the keyboard with the finger — rule 5)
    scroll.delegate = self
    addSubview(scroll); scroll.addSubview(content)
    if #available(iOS 26.0, *) { scroll.topEdgeEffect.style = .soft }
    // the ↓ button / "N new comments" pill: glass, just above the comment box
    jumpFx.isUserInteractionEnabled = false; jumpFx.clipsToBounds = true
    if #available(iOS 26.0, *) { jumpFx.effect = UIGlassEffect(style: .regular) } else { jumpFx.effect = UIBlurEffect(style: .systemThinMaterial) }
    jump.addSubview(jumpFx)
    jumpLabel.font = .systemFont(ofSize: 15, weight: .semibold); jumpLabel.textAlignment = .center; jumpLabel.textColor = .label
    jump.addSubview(jumpLabel)
    jump.layer.shadowColor = UIColor.black.cgColor; jump.layer.shadowOpacity = 0.12; jump.layer.shadowRadius = 10; jump.layer.shadowOffset = CGSize(width: 0, height: 4)
    jump.alpha = 0
    jump.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.toEnd(animated: true) }, for: .touchUpInside)
    addSubview(jump)
    if thread != nil {
      // a thread's page: its own bar line under the task's ("‹ Thread")
      threadBar.backgroundColor = .clear
      let b = UIButton(type: .system)
      var c = UIButton.Configuration.plain()
      c.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)); c.imagePadding = 6
      c.attributedTitle = AttributedString("Thread", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
      c.baseForegroundColor = .label
      b.configuration = c
      b.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
      b.frame = CGRect(x: 8, y: 0, width: 140, height: 40)
      threadBar.addSubview(b)
      addSubview(threadBar)
      // (iPhone's swipe from the left edge also goes back out of the thread)
      let g = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edge(_:))); g.edges = .left; addGestureRecognizer(g)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func edge(_ g: UIScreenEdgePanGestureRecognizer) {
    let x = max(0, g.translation(in: superview).x), W = bounds.width
    switch g.state {
    case .changed: transform = CGAffineTransform(translationX: x, y: 0)
    case .ended, .cancelled:
      if g.velocity(in: superview).x > 300 || x > W * 0.4 { onBack?() }
      else { UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) { self.transform = .identity } }
    default: break
    }
  }

  // ---------- data ----------
  // each task's comments (and threads) as last fetched: shown at once, then brought up to date — no empty wait
  static var cache: [String: [String: Any]] = [:]
  static func path(_ taskId: String, _ thread: String?) -> String {
    var p = "/api/comments?id=" + (taskId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? taskId)
    if let t = thread { p += "&thread=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t) }
    return p
  }
  // fetched ahead (a task page opening), so its Comments tab has them ready
  static func prefetch(_ taskId: String, cookies: @escaping (@escaping (String) -> Void) -> Void) {
    FeedLoader.shared.cookies = cookies
    let p = path(taskId, nil)
    FeedLoader.shared.get(p) { j in if let f = j?["feed"] as? [String: Any] { cache[p] = f } }
  }
  func load(_ done: (() -> Void)? = nil) {
    // the app's own copy first: no request at all (iOS app data plan)
    let c = AppData.shared.screen("comments", taskId, thread)
    if c.ready, let f = c.model { dropArrived(f); draw(f); done?(); return }
    let p = CommentsFeed.path(taskId, thread)
    if model == nil, let c = CommentsFeed.cache[p] { draw(c) }
    FeedLoader.shared.get(p) { [weak self] j in
      guard let self = self, let f = j?["feed"] as? [String: Any] else { done?(); return }
      CommentsFeed.cache[p] = f
      self.pending.removeAll { $0.done }   // (the real ones are in this one)
      self.draw(f); done?()
    }
  }
  // ---------- a voice message on its way (Haris, 2026-11-01): in the feed at once, its pill pulsing while it uploads,
  // then the real one (with its length) from the server takes its place ----------
  private var pending: [(id: String, item: [String: Any], done: Bool)] = []
  func addPending(id: String, parent: String?, dur: Double) {
    guard parent == thread, let m = model else { return }
    let at = ISO8601DateFormatter().string(from: Date())
    // (shaped as the server's one — "replies": null makes it a card like every comment — so nothing moves when it's swapped)
    let it: [String: Any] = ["id": id, "who": m["me"] as? String ?? "", "at": at, "runs": [[String: Any]](), "replies": NSNull(), "files": [["id": id, "name": "Voice message.m4a", "voice": true, "dur": Int(dur.rounded()), "pending": true]]]
    pending.append((id, it, false))
    draw(m, mine: true)
  }
  // (a sent one goes once the real one is in the comments: your own voice message, from about then)
  private func dropArrived(_ f: [String: Any]) {
    let items = (f["items"] as? [[String: Any]]) ?? []
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let when: (String) -> Date? = { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
    pending.removeAll { p in
      guard p.done, let pa = when(p.item["at"] as? String ?? "") else { return false }
      return items.contains { it in
        (it["who"] as? String) == (p.item["who"] as? String) && (when(it["at"] as? String ?? "") ?? .distantPast) >= pa.addingTimeInterval(-20)
          && ((it["files"] as? [[String: Any]]) ?? []).contains { ($0["voice"] as? Bool) == true }
      }
    }
  }
  // sent: it stays until the feed that has the real one arrives; not sent: it goes now
  func endPending(id: String, ok: Bool) {
    guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
    if ok { pending[i].done = true } else { pending.remove(at: i); if let m = model { draw(m) } }
  }
  private func draw(_ m: [String: Any], mine: Bool = false) {
    model = m
    onLoaded?(m)
    if let pp = m["people"] as? [String: [String: Any]] { people.merge(pp) { _, b in b } }
    let items = ((m["items"] as? [[String: Any]]) ?? []) + pending.map { $0.item }
    let atEnd = mine || isAtEnd()   // (your own voice message: down to it)
    let keepTopId = order.first { (cells[$0]?.frame.maxY ?? 0) > scroll.contentOffset.y + scroll.contentInset.top }
    let keepTopY = keepTopId.flatMap { cells[$0] }.map { $0.frame.minY - scroll.contentOffset.y }
    var next: [String] = [], seen = Set<String>()
    for (k, it) in items.enumerated() {
      guard let id = it["id"] as? String else { continue }
      seen.insert(id); next.append(id)
      let sig = (try? JSONSerialization.data(withJSONObject: it, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
      let isRoot = thread != nil && k == 0
      if let c = cells[id], c.sig == sig { continue }
      cells[id]?.removeFromSuperview()
      let c = CommentCell(it, people: people, me: m["me"] as? String ?? "", thread: thread != nil, root: isRoot)
      c.sig = sig
      c.onHold = { [weak self] in self?.hold(it) }
      c.onReplies = { [weak self] in self?.onThread?(id) }
      c.onOpen = { [weak self] list, i in self?.onOpenFile?(list, i) }
      c.onReact = { [weak self] e in guard let self = self else { return }; self.onAct?(["act": "react", "id": self.taskId, "key": id, "value": e]) }
      content.addSubview(c); cells[id] = c
    }
    for (id, c) in cells where !seen.contains(id) { c.removeFromSuperview(); cells[id] = nil }
    // your scheduled comments, last (dashed: "Scheduled · 4:00 PM")
    schedViews.forEach { $0.removeFromSuperview() }
    schedViews = ((m["scheduled"] as? [[String: Any]]) ?? []).map { ScheduledCard($0) }
    schedViews.forEach { content.addSubview($0) }
    let newOnes = next.filter { !seenIds.contains($0) }
    order = next
    layoutCells()
    if first { first = false; seenIds = Set(next); toEnd(animated: false); tellSeen(); return }
    // at the latest: new comments stay in view (rule 3); higher up nothing moves — the pill counts them
    if atEnd { seenIds = Set(next); toEnd(animated: true) }
    else if let id = keepTopId, let c = cells[id], let y = keepTopY { scroll.contentOffset.y = c.frame.minY - y }
    let mineNew = newOnes.filter { id in (items.first { ($0["id"] as? String) == id }?["mine"] as? Bool) != true }
    paintJump(newCount: atEnd ? 0 : mineNew.count + pendingNew)
    if !atEnd { pendingNew += mineNew.count; seenIds.formUnion(newOnes) }
    tellSeen()
  }
  private var pendingNew = 0
  private var schedViews: [ScheduledCard] = []

  // ---------- layout ----------
  override func layoutSubviews() {
    super.layoutSubviews()
    scroll.frame = bounds
    if thread != nil { threadBar.frame = CGRect(x: 0, y: topInset, width: bounds.width, height: 40) }
    let top = topInset + (thread != nil ? 44 : 6)
    if scroll.contentInset.top != top { scroll.contentInset.top = top; scroll.verticalScrollIndicatorInsets.top = top }
    layoutCells()
    placeJump()
  }
  private func layoutCells() {
    let W = bounds.width
    guard W > 0 else { return }
    var y: CGFloat = 4
    for id in order {
      guard let c = cells[id] else { continue }
      let h = c.height(for: W)
      c.frame = CGRect(x: 0, y: y, width: W, height: h)
      y += h
    }
    for v in schedViews { let h = v.height(for: W); v.frame = CGRect(x: 0, y: y, width: W, height: h); y += h }
    content.frame = CGRect(x: 0, y: 0, width: W, height: y + 8)
    scroll.contentSize = content.frame.size
    scroll.contentInset.bottom = bottomRoom
    scroll.verticalScrollIndicatorInsets.bottom = bottomRoom
  }
  // the box grew or the keyboard came: at the latest it stays at the latest
  private func roomChanged(_ old: CGFloat) {
    let wasEnd = scroll.contentOffset.y + scroll.bounds.height >= scroll.contentSize.height + old - 60
    scroll.contentInset.bottom = bottomRoom; scroll.verticalScrollIndicatorInsets.bottom = bottomRoom
    // (the keyboard dragged down with the list: the list follows the finger, nothing else moves it — keeping it at the
    //  latest at the same time made it jump about, Haris 2026-11-02)
    if wasEnd && !scroll.isTracking && !scroll.isDragging && !scroll.isDecelerating { toEnd(animated: false) }
    placeJump()
  }
  func isAtEnd() -> Bool { scroll.contentOffset.y + scroll.bounds.height >= scroll.contentSize.height + scroll.contentInset.bottom - 80 }
  func toEnd(animated: Bool) {
    layoutIfNeeded()
    let end = max(-scroll.contentInset.top, scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height)
    scroll.setContentOffset(CGPoint(x: 0, y: end), animated: animated)
  }
  func scrollViewDidScroll(_ s: UIScrollView) {
    if isAtEnd() { if pendingNew > 0 || jump.alpha > 0 { pendingNew = 0; seenIds = Set(order) }; paintJump(newCount: 0) }
    else if jump.alpha == 0 { paintJump(newCount: pendingNew) }
    seenSoon()
  }
  private func paintJump(newCount: Int) {
    let show = !isAtEnd()
    jumpLabel.text = newCount > 0 ? "\(newCount) new comment\(newCount == 1 ? "" : "s")  ↓" : "↓"
    placeJump()
    UIView.animate(withDuration: 0.18) { self.jump.alpha = show ? 1 : 0 }
  }
  private func placeJump() {
    let pill = (jumpLabel.text ?? "↓") != "↓"
    let w = pill ? ceil(jumpLabel.sizeThatFits(CGSize(width: 300, height: 44)).width) + 32 : 44
    jump.frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height - bottomRoom - 14 - 44, width: w, height: 44)
    jumpFx.frame = jump.bounds; jumpFx.layer.cornerRadius = 22
    jumpLabel.frame = jump.bounds
  }

  // ---------- the WhatsApp pulse: the whole row, a see-through grey, once ----------
  func pulse(_ id: String) {
    guard let c = cells[id] else { return }
    layoutIfNeeded()
    let y = max(-scroll.contentInset.top, min(c.frame.midY - scroll.bounds.height * 0.4, scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height))
    scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    let band = UIView(frame: c.bounds)
    band.backgroundColor = traitCollection.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.13) : UIColor.black.withAlphaComponent(0.08)
    band.alpha = 0; band.isUserInteractionEnabled = false
    c.insertSubview(band, at: 0)
    UIView.animate(withDuration: 0.2, delay: 0.15, options: [.curveEaseOut]) { band.alpha = 1 } completion: { _ in
      UIView.animate(withDuration: 0.6, delay: 0.5, options: [.curveEaseInOut]) { band.alpha = 0 } completion: { _ in band.removeFromSuperview() }
    }
  }
  func has(_ id: String) -> Bool { cells[id] != nil }
  // Reply (rule 7): the list stays where it is; the replied comment is kept in view above the box
  func keepInView(_ id: String) {
    guard let c = cells[id] else { return }
    let visibleBottom = scroll.contentOffset.y + scroll.bounds.height - bottomRoom
    if c.frame.maxY > visibleBottom { scroll.setContentOffset(CGPoint(x: 0, y: c.frame.maxY - scroll.bounds.height + bottomRoom + 8), animated: true) }
    else if c.frame.minY < scroll.contentOffset.y + scroll.contentInset.top { scroll.setContentOffset(CGPoint(x: 0, y: c.frame.minY - scroll.contentInset.top - 8), animated: true) }
  }

  // ---------- touch and hold: reactions, Reply, Copy, Delete (as today's sheet) ----------
  private func hold(_ it: [String: Any]) {
    guard let id = it["id"] as? String else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let ro = (model?["readOnly"] as? Bool) == true
    var rows: [[String: Any]] = []
    let emojis = ["👍", "✅", "🎉", "❤️", "👀", "🙏"]
    if !ro { rows.append(["i": -1, "label": "", "kind": "emoji", "chips": emojis.enumerated().map { ["i": 100 + $0.offset, "swatch": $0.element, "label": $0.element] }]) }
    if (it["canReply"] as? Bool) == true && thread == nil { rows.append(["i": 1, "label": "Reply", "icon": "reply"]) }
    if thread != nil && !ro { rows.append(["i": 1, "label": "Reply", "icon": "reply"]) }
    if (it["canEdit"] as? Bool) == true { rows.append(["i": 4, "label": "Edit comment", "icon": "edit"]) }
    rows.append(["i": 2, "label": "Copy text", "icon": "copy"])
    var secs: [[String: Any]] = [["rows": rows]]
    if (it["canDelete"] as? Bool) == true { secs.append(["rows": [["i": 3, "label": "Delete comment", "icon": "trash", "danger": true]]]) }
    onSheet?(["sections": secs]) { [weak self] i, swatch in
      guard let self = self else { return }
      if let e = swatch, emojis.contains(e) { self.onAct?(["act": "react", "id": self.taskId, "key": id, "value": e]); return }
      switch i {
      case 1:
        let who = it["who"] as? String ?? ""
        self.onReply?(self.thread ?? id, (self.people[who]?["first"] as? String) ?? "them", self.people[who])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.keepInView(id) }
      case 4: self.onEdit?(id, (it["runs"] as? [[String: Any]]) ?? [])
      case 2: UIPasteboard.general.string = it["text"] as? String ?? ""; self.onToast?("Copied")
      case 3: self.confirmDelete(id, replies: ((it["replies"] as? [String: Any])?["n"] as? Int) ?? 0)
      default: break
      }
    }
  }
  private func confirmDelete(_ id: String, replies: Int) {
    let a = UIAlertController(title: "Delete comment?", message: replies > 0 ? "This also removes its \(replies) repl\(replies == 1 ? "y" : "ies")." : nil, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in guard let self = self else { return }; self.onAct?(["act": "deleteComment", "id": self.taskId, "value": id]) })
    var top = window?.rootViewController; while let p = top?.presentedViewController { top = p }
    top?.present(a, animated: true)
  }

  // ---------- Seen: comments that mention you, once they're in view, told to the server (as the page did) ----------
  private var told = Set<String>(), seenT: Timer?
  private func seenSoon() { seenT?.invalidate(); seenT = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.tellSeen() } }
  private func tellSeen() {
    guard let items = model?["items"] as? [[String: Any]] else { return }
    let top = scroll.contentOffset.y, bottom = top + scroll.bounds.height - bottomRoom
    var ids: [String] = []
    for it in items where (it["mentionsMe"] as? Bool) == true && (it["mine"] as? Bool) != true {
      guard let id = it["id"] as? String, !told.contains(id), let c = cells[id], c.frame.maxY > top, c.frame.minY < bottom else { continue }
      ids.append(id); told.insert(id)
    }
    if !ids.isEmpty { FeedLoader.shared.post("/api/seen", ["taskId": taskId, "ids": ids]) }
  }
}

// one comment: avatar · name · time, the words, files, link cards, reactions, Seen by, "N replies"
final class CommentCell: UIView {
  var sig = ""
  var onHold: (() -> Void)?
  var onReplies: (() -> Void)?
  var onReact: ((String) -> Void)?
  var onOpen: (([[String: Any]], Int) -> Void)?
  private let card = UIView()
  private let stack = UIStackView()
  private var measured: (CGFloat, CGFloat)?
  init(_ it: [String: Any], people: [String: [String: Any]], me: String, thread: Bool, root: Bool) {
    super.init(frame: .zero)
    let who = it["who"] as? String ?? ""
    let p = people[who] ?? [:]
    let hasReplies = it["replies"] != nil && !thread
    // a comment with replies is a card of its own (as on the website); the task owner's comments have an orange bar
    card.backgroundColor = hasReplies || root ? .secondarySystemGroupedBackground : .clear
    card.layer.cornerRadius = 18; card.layer.cornerCurve = .continuous
    addSubview(card)
    let av = CommentCell.avatar(p, 32)
    let name = UILabel(); name.font = .systemFont(ofSize: 15, weight: .semibold); name.text = who == me ? "You" : (p["name"] as? String ?? "Someone")
    name.lineBreakMode = .byTruncatingTail
    let when = UILabel(); when.font = .systemFont(ofSize: 13); when.textColor = .secondaryLabel; when.text = TaskPage.when(it["at"] as? String ?? "") + ((it["edited"] as? Bool) == true ? " · edited" : "")
    let meta = UIStackView(arrangedSubviews: [name, when]); meta.spacing = 6; meta.alignment = .firstBaseline
    name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    stack.axis = .vertical; stack.spacing = 6; stack.alignment = .fill
    stack.addArrangedSubview(meta)
    let words = UILabel(); words.numberOfLines = 0
    words.attributedText = CommentCell.text((it["runs"] as? [[String: Any]]) ?? [], me: me)
    if (words.attributedText?.length ?? 0) > 0 { stack.addArrangedSubview(words) }
    // files: pictures as fixed-size tiles (their room kept from the start), others as file rows
    let files = (it["files"] as? [[String: Any]]) ?? []
    for f in files where (f["voice"] as? Bool) == true {
      let w = UIStackView(arrangedSubviews: [VoiceBubble(path: f["url"] as? String ?? "", dur: f["dur"] as? Int ?? 0, pending: (f["pending"] as? Bool) == true), UIView()]); w.alignment = .center
      stack.addArrangedSubview(w)
    }
    let rest = files.filter { ($0["voice"] as? Bool) != true }
    // (tapped: the preview, with all of this comment's files to swipe through)
    if !rest.isEmpty { stack.addArrangedSubview(CommentCell.tiles(rest, open: { [weak self] i in self?.onOpen?(rest, i) })) }
    for u in ((it["urls"] as? [String]) ?? []).prefix(3) { stack.addArrangedSubview(LinkCard(u)) }
    let rx = (it["reactions"] as? [[String: Any]]) ?? []
    if !rx.isEmpty {
      let r = UIStackView(); r.spacing = 6
      for x in rx {
        let e = x["e"] as? String ?? ""
        var c = UIButton.Configuration.filled(); c.cornerStyle = .capsule; c.baseBackgroundColor = .tertiarySystemFill; c.baseForegroundColor = .label
        c.attributedTitle = AttributedString("\(e) \(x["n"] as? Int ?? 1)", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14, weight: .medium)]))
        c.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        let b = UIButton(configuration: c); b.addAction(UIAction { [weak self] _ in UISelectionFeedbackGenerator().selectionChanged(); self?.onReact?(e) }, for: .touchUpInside)
        r.addArrangedSubview(b)
      }
      r.addArrangedSubview(UIView())
      stack.addArrangedSubview(r)
    }
    // the task's creator: an orange "Creator" chip by the Seen line (no bar down the side — Haris, 2026-11-01)
    let creator: UIView? = (it["owner"] as? Bool) == true ? {
      let c = PaddedLabel(); c.text = "Creator"; c.font = .systemFont(ofSize: 11.5, weight: .semibold); c.textColor = .systemOrange
      c.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.16); c.layer.cornerRadius = 7; c.clipsToBounds = true; c.insets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
      return c }() : nil
    if it["seen"] == nil, let c = creator { let s = UIStackView(arrangedSubviews: [c, UIView()]); stack.addArrangedSubview(s) }
    if let sn = it["seen"] as? [String: Any] {
      let l = UILabel(); l.font = .systemFont(ofSize: 12.5); l.textColor = .secondaryLabel
      var t = sn["label"] as? String ?? ""
      if let at = sn["at"] as? String { t += " · " + TaskPage.when(at) }
      let eye = UIImageView(image: UIImage(systemName: (sn["on"] as? Bool) == true ? "eye" : "eye.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))); eye.tintColor = .secondaryLabel
      l.text = t
      let s = UIStackView(arrangedSubviews: [eye, l]); s.spacing = 5; s.alignment = .center
      if let c = creator { s.setCustomSpacing(8, after: l); s.addArrangedSubview(c) }
      s.addArrangedSubview(UIView())
      stack.addArrangedSubview(s)
    }
    if hasReplies, let r = it["replies"] as? [String: Any] {
      let b = TaskRow(); b.pressBg = false
      let n = r["n"] as? Int ?? 0
      let avs = UIStackView(); avs.spacing = -5
      for id in ((r["people"] as? [String]) ?? []).prefix(3) { avs.addArrangedSubview(CommentCell.avatar(people[id] ?? [:], 20)) }
      let l = UILabel(); l.font = .systemFont(ofSize: 14.5, weight: .semibold); l.textColor = .systemBlue; l.text = "\(n) repl\(n == 1 ? "y" : "ies")"
      let last = UILabel(); last.font = .systemFont(ofSize: 13); last.textColor = .secondaryLabel; last.text = "Last reply " + TaskPage.when(r["last"] as? String ?? "")
      let chev = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))); chev.tintColor = .tertiaryLabel
      let h = UIStackView(arrangedSubviews: [avs, l, last, UIView(), chev]); h.spacing = 7; h.alignment = .center
      h.translatesAutoresizingMaskIntoConstraints = false; b.addSubview(h)
      NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: b.leadingAnchor), h.trailingAnchor.constraint(equalTo: b.trailingAnchor), h.topAnchor.constraint(equalTo: b.topAnchor, constant: 4), h.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: 2)])
      b.onTap = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onReplies?() }
      stack.addArrangedSubview(b)
    }
    let right = UIStackView(arrangedSubviews: [stack]); right.axis = .vertical
    let row = UIStackView(arrangedSubviews: [av, right]); row.spacing = 10; row.alignment = .top
    row.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(row)
    let pad: CGFloat = hasReplies || root ? 12 : 4
    NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad), row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -pad), row.topAnchor.constraint(equalTo: card.topAnchor, constant: pad), row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -pad)])
    let lp = UILongPressGestureRecognizer(target: self, action: #selector(held(_:))); lp.minimumPressDuration = 0.45
    addGestureRecognizer(lp)
    pressShrink = PressShrink.add(to: card)
  }
  required init?(coder: NSCoder) { fatalError() }
  // touch and hold: the shared PressShrink (shrinks from the moment the finger is down); held long enough — the
  // haptic, the menu, and it springs back
  private var pressShrink: PressShrink?
  @objc private func held(_ g: UILongPressGestureRecognizer) {
    if g.state == .began { onHold?(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.pressShrink?.release() } }
  }
  func height(for W: CGFloat) -> CGFloat {
    if let m = measured, m.0 == W { return m.1 }
    card.bounds = CGRect(x: 0, y: 0, width: W - 32, height: 10)
    let h = card.systemLayoutSizeFitting(CGSize(width: W - 32, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    measured = (W, h + 12)
    return h + 12
  }
  // (its size and place set without touching its shrink: setting the frame of a card that's shrunk while held re-laid
  //  its insides — the text moved; now the whole card shrinks as one picture, Haris 2026-11-01)
  override func layoutSubviews() {
    super.layoutSubviews()
    let size = CGSize(width: bounds.width - 32, height: bounds.height - 12)
    if card.bounds.size != size { card.bounds = CGRect(origin: .zero, size: size) }
    card.center = CGPoint(x: 16 + size.width / 2, y: 6 + size.height / 2)
  }

  // ---------- pieces ----------
  static func avatar(_ p: [String: Any], _ side: CGFloat) -> UIView {
    let v = UIView(); v.layer.cornerRadius = side / 2; v.clipsToBounds = true; v.backgroundColor = TaskPage.rgb(p["color"])
    v.translatesAutoresizingMaskIntoConstraints = false
    v.widthAnchor.constraint(equalToConstant: side).isActive = true; v.heightAnchor.constraint(equalToConstant: side).isActive = true
    let l = UILabel(); l.text = p["initials"] as? String ?? "?"; l.font = .systemFont(ofSize: side * 0.38, weight: .semibold); l.textColor = .white; l.textAlignment = .center
    l.frame = CGRect(x: 0, y: 0, width: side, height: side); v.addSubview(l)
    if let ph = p["photo"] as? String {
      if ph.hasPrefix("data:"), let d = Data(base64Encoded: String(ph.split(separator: ",").last ?? "")), let img = UIImage(data: d) { let i = UIImageView(image: img); i.contentMode = .scaleAspectFill; i.frame = l.frame; v.addSubview(i) }
      else if ph.hasPrefix("/") { let i = UIImageView(frame: l.frame); i.contentMode = .scaleAspectFill; v.addSubview(i); FeedLoader.shared.image(ph) { [weak i] img in i?.image = img } }
    }
    return v
  }
  static func text(_ runs: [[String: Any]], me: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for r in runs {
      var font = UIFont.systemFont(ofSize: 16, weight: r["b"] != nil ? .semibold : .regular)
      if r["i"] != nil, let d = font.fontDescriptor.withSymbolicTraits(.traitItalic) { font = UIFont(descriptor: d, size: 16) }
      var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
      if r["u"] != nil { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
      if r["s"] != nil { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      if let u = r["user"] as? String {
        a[.foregroundColor] = UIColor.systemBlue; a[.font] = UIFont.systemFont(ofSize: 16, weight: .medium)
        if u == me { a[.backgroundColor] = UIColor.systemBlue.withAlphaComponent(0.14) }
      } else if let l = r["link"] as? String, let url = URL(string: l) { a[.link] = url; a[.foregroundColor] = UIColor.systemBlue }
      out.append(NSAttributedString(string: r["t"] as? String ?? "", attributes: a))
    }
    let ps = NSMutableParagraphStyle(); ps.lineSpacing = 2
    out.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: out.length))
    return out
  }
  static func isPic(_ n: String) -> Bool { ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains((n as NSString).pathExtension.lowercased()) }
  static let videoExt = ["mp4", "mov", "m4v", "webm", "avi", "mkv"]
  static func isVideo(_ n: String) -> Bool { videoExt.contains((n as NSString).pathExtension.lowercased()) }
  // every file the same card (Haris, 2026-11-01): squares, three a row, a third of the width each — a picture shows
  // itself, a video its frame with ▶, a PDF / Office file its first page, anything else its type; the name under
  // all but pictures. A grey shimmer until the picture arrives (the room kept from the start, so nothing jumps).
  static func tiles(_ files: [[String: Any]], open: @escaping (Int) -> Void = { _ in }, menu: ((Int) -> UIMenu?)? = nil) -> UIView {
    let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 6
    var i = 0
    while i < files.count {
      let row = UIStackView(); row.spacing = 6; row.distribution = .fillEqually
      for k in i..<(i + 3) {
        guard k < files.count else { row.addArrangedSubview(UIView()); continue }   // (an empty place keeps the size)
        row.addArrangedSubview(tile(files[k], open: { open(k) }, menu: menu.map { m in { () -> UIMenu? in m(k) } }))
      }
      grid.addArrangedSubview(row)
      i += 3
    }
    return grid
  }
  static func tile(_ f: [String: Any], open: @escaping () -> Void, menu: (() -> UIMenu?)?) -> UIView {
    let n = f["name"] as? String ?? "File"
    let pic = isPic(n), video = isVideo(n)
    let v = TapImage(); v.contentMode = .scaleAspectFill; v.clipsToBounds = true; v.layer.cornerRadius = 12; v.layer.cornerCurve = .continuous
    v.onTap = open
    v.menu = menu
    v.backgroundColor = .tertiarySystemFill
    v.translatesAutoresizingMaskIntoConstraints = false
    v.heightAnchor.constraint(equalTo: v.widthAnchor).isActive = true
    func pin(_ x: UIView, _ l: CGFloat?, _ t: CGFloat?, _ r: CGFloat?, _ b: CGFloat?) {
      x.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(x)
      if let l { x.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: l).isActive = true }
      if let t { x.topAnchor.constraint(equalTo: v.topAnchor, constant: t).isActive = true }
      if let r { x.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -r).isActive = true }
      if let b { x.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -b).isActive = true }
    }
    let ext = (n as NSString).pathExtension.uppercased()
    // the type, in the middle until a picture covers it
    let typeL = UILabel(); typeL.text = ext.isEmpty ? "FILE" : String(ext.prefix(4)); typeL.font = .systemFont(ofSize: 15, weight: .bold); typeL.textColor = .secondaryLabel; typeL.textAlignment = .center
    if !pic { pin(typeL, 0, 0, 0, 28) }
    // (a photo: the server's smaller copy, quicker to come — the card is a third of the screen wide)
    let picURL = (f["thumbUrl"] as? String) ?? (pic ? (f["url"] as? String)?.replacingOccurrences(of: "?view=1", with: "?w=480") : nil)
    let shimmer = Shimmer()
    if picURL != nil { pin(shimmer, 0, 0, 0, 0) }
    // the name (not on pictures), on a soft shade when there's a picture under it
    let shade = CAGradientLayer(); shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.55).cgColor]
    let name = UILabel(); name.text = n; name.font = .systemFont(ofSize: 11.5, weight: .medium); name.textColor = .label; name.lineBreakMode = .byTruncatingMiddle; name.textAlignment = .center
    let shadeView = ShadeView(shade); shadeView.isHidden = true
    if !pic { pin(shadeView, 0, nil, 0, 0); shadeView.heightAnchor.constraint(equalToConstant: 34).isActive = true; pin(name, 6, nil, 6, 8) }
    let play = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
    play.tintColor = .white; play.contentMode = .center; play.backgroundColor = UIColor.black.withAlphaComponent(0.45); play.layer.cornerRadius = 15
    if video { pin(play, nil, nil, nil, nil); play.widthAnchor.constraint(equalToConstant: 30).isActive = true; play.heightAnchor.constraint(equalToConstant: 30).isActive = true; play.centerXAnchor.constraint(equalTo: v.centerXAnchor).isActive = true; play.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -6).isActive = true }
    if let p = picURL {
      FeedLoader.shared.image(p) { [weak v, weak shimmer, weak typeL, weak name, weak shadeView] img in
        shimmer?.removeFromSuperview()
        guard let img = img else { return }
        v?.image = img; typeL?.isHidden = true
        if !pic { shadeView?.isHidden = false; name?.textColor = .white }
      }
    }
    return v
  }
  static func fileRow(_ f: [String: Any], open: (() -> Void)? = nil) -> UIView {
    let box = TapView(); box.onTap = open; box.backgroundColor = .tertiarySystemFill; box.layer.cornerRadius = 12; box.layer.cornerCurve = .continuous
    let n = f["name"] as? String ?? "File"
    let ext = (n as NSString).pathExtension.uppercased()
    let tag = PaddedLabel(); tag.text = ext.isEmpty ? "FILE" : String(ext.prefix(4)); tag.font = .systemFont(ofSize: 10, weight: .bold); tag.textColor = .white
    tag.backgroundColor = ext == "PDF" ? .systemRed : ext == "AI" ? .systemOrange : .systemGray; tag.layer.cornerRadius = 6; tag.clipsToBounds = true; tag.insets = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6); tag.textAlignment = .center
    let name = UILabel(); name.font = .systemFont(ofSize: 14.5, weight: .medium); name.text = n; name.lineBreakMode = .byTruncatingMiddle
    let size = UILabel(); size.font = .systemFont(ofSize: 12.5); size.textColor = .secondaryLabel; size.text = TaskPage.size(f["size"] as? Int ?? 0)
    let v = UIStackView(arrangedSubviews: [name, size]); v.axis = .vertical; v.spacing = 1
    let h = UIStackView(arrangedSubviews: [tag, v]); h.spacing = 10; h.alignment = .center
    h.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8), h.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12), h.topAnchor.constraint(equalTo: box.topAnchor, constant: 8), h.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8)])
    return box
  }
}

// a link's card (WeTransfer with its expiry, or a page's title): its size kept from the start
final class LinkCard: UIView {
  private var url = ""
  @objc private func tapped() { if let u = URL(string: url) { UIApplication.shared.open(u) } }
  init(_ url: String) {
    super.init(frame: .zero)
    self.url = url
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    backgroundColor = .tertiarySystemFill; layer.cornerRadius = 12; layer.cornerCurve = .continuous
    heightAnchor.constraint(equalToConstant: 62).isActive = true
    let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    let site = UILabel(); site.font = .systemFont(ofSize: 12.5); site.textColor = .secondaryLabel; site.text = host
    let title = UILabel(); title.font = .systemFont(ofSize: 15, weight: .semibold); title.text = url; title.lineBreakMode = .byTruncatingTail
    let v = UIStackView(arrangedSubviews: [site, title]); v.axis = .vertical; v.spacing = 2
    v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v)
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), v.centerYAnchor.constraint(equalTo: centerYAnchor)])
    FeedLoader.shared.link(url) { [weak site, weak title] p in
      guard let p = p, (p["ok"] as? Bool) != false else { return }
      if let s = p["site"] as? String { site?.text = s }
      if let wt = p["wt"] as? [String: Any] {
        let n = wt["count"] as? Int ?? wt["files"] as? Int ?? 0
        title?.text = "WeTransfer" + (n > 0 ? " · \(n) file\(n == 1 ? "" : "s")" : "")
        if let exp = wt["expires"] as? String ?? wt["expiresAt"] as? String { site?.text = "Expires " + TaskPage.when(exp).replacingOccurrences(of: "now", with: "soon"); site?.textColor = .systemOrange }
      } else if let t = p["title"] as? String, !t.isEmpty { title?.text = t }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
}

final class Shimmer: UIView {
  private let g = CAGradientLayer()
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    g.colors = [UIColor.clear.cgColor, UIColor.white.withAlphaComponent(0.18).cgColor, UIColor.clear.cgColor]
    g.startPoint = CGPoint(x: 0, y: 0.5); g.endPoint = CGPoint(x: 1, y: 0.5); g.locations = [0, 0.5, 1]
    layer.addSublayer(g)
    let a = CABasicAnimation(keyPath: "transform.translation.x"); a.fromValue = -300; a.toValue = 300; a.duration = 1.2; a.repeatCount = .infinity
    g.add(a, forKey: "s")
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); g.frame = bounds.insetBy(dx: -bounds.width, dy: 0) }
}

// a picture / file box that can be tapped
final class TapImage: UIImageView, UIContextMenuInteractionDelegate {
  var onTap: (() -> Void)? { didSet { isUserInteractionEnabled = onTap != nil; if gestureRecognizers?.isEmpty ?? true { addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(t))) } } }
  // touch and hold: iPhone's own menu (Open, Copy, Download…), the tile lifted as its preview
  var menu: (() -> UIMenu?)? { didSet { if menu != nil && interactions.isEmpty { isUserInteractionEnabled = true; addInteraction(UIContextMenuInteraction(delegate: self)) } } }
  @objc private func t() { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap?() }
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
    guard let m = menu?() else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in m }
  }
}
final class TapView: UIView, UIContextMenuInteractionDelegate {
  var onTap: (() -> Void)? { didSet { if onTap != nil && (gestureRecognizers?.isEmpty ?? true) { addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(t))) } } }
  var menu: (() -> UIMenu?)? { didSet { if menu != nil && interactions.isEmpty { addInteraction(UIContextMenuInteraction(delegate: self)) } } }
  @objc private func t() { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap?() }
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
    guard let m = menu?() else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in m }
  }
}
/* Touch and hold, app-wide (Haris, 2026-11-02: "this long press behaviour will be app wide"): the view shrinks from the
   moment the finger is down — as iPhone's own press — all through the hold; let go early, move, or scroll and it springs
   back; the hold's own action (its haptic and menu) then calls release(). It never takes the touch from anything else.
   iPhone's own menus (UIContextMenuInteraction) already do this themselves. Shared: comments, Home / My Tasks cards. */
final class PressShrink: UIGestureRecognizer {
  private weak var target: UIView?
  private var start = CGPoint.zero
  private var pending: DispatchWorkItem?
  static func add(to v: UIView) -> PressShrink {
    let g = PressShrink(target: nil, action: nil)
    g.target = v; g.cancelsTouchesInView = false; g.delaysTouchesBegan = false; g.delaysTouchesEnded = false
    v.addGestureRecognizer(g)
    return g
  }
  override func canPrevent(_ g: UIGestureRecognizer) -> Bool { false }
  override func canBePrevented(by g: UIGestureRecognizer) -> Bool { false }
  override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent) {
    super.touchesBegan(t, with: e)
    guard let v = target, let touch = t.first else { return }
    start = touch.location(in: v)
    // (a moment's wait, as iPhone's: a quick flick to scroll doesn't shrink anything)
    let w = DispatchWorkItem { [weak self] in self?.shrink(true) }
    pending = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: w)
  }
  override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent) {
    super.touchesMoved(t, with: e)
    guard let v = target, let p = t.first?.location(in: v) else { return }
    if hypot(p.x - start.x, p.y - start.y) > 10 { release() }
  }
  override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent) { super.touchesEnded(t, with: e); release(); state = .failed }
  override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent) { super.touchesCancelled(t, with: e); release(); state = .failed }
  func release() { pending?.cancel(); pending = nil; shrink(false) }
  private var shrunk = false
  // (only its own scale: a card being swiped sideways keeps its shift)
  private func shrink(_ down: Bool) {
    guard let v = target else { return }
    if down {
      shrunk = true
      let t = v.transform
      UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) { v.transform = CGAffineTransform(translationX: t.tx, y: t.ty).scaledBy(x: 0.965, y: 0.965) }
    } else if shrunk {
      shrunk = false
      let t = v.transform
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { v.transform = CGAffineTransform(translationX: t.tx, y: t.ty) }
    }
  }
}
// a gradient that keeps to its view's size
final class ShadeView: UIView {
  private let g: CAGradientLayer
  init(_ g: CAGradientLayer) { self.g = g; super.init(frame: .zero); isUserInteractionEnabled = false; layer.addSublayer(g) }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); g.frame = bounds }
}

final class ScheduledCard: UIView {
  private let box = UIView(), label = UILabel()
  init(_ x: [String: Any]) {
    super.init(frame: .zero)
    box.layer.cornerRadius = 16; box.layer.cornerCurve = .continuous
    let dash = CAShapeLayer(); dash.strokeColor = UIColor.separator.cgColor; dash.fillColor = UIColor.clear.cgColor; dash.lineDashPattern = [5, 4]; dash.lineWidth = 1
    box.layer.addSublayer(dash); self.dash = dash
    addSubview(box)
    let when: String = {
      let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      guard let d = f.date(from: x["at"] as? String ?? "") ?? ISO8601DateFormatter().date(from: x["at"] as? String ?? "") else { return "" }
      let o = DateFormatter(); o.locale = Locale(identifier: "en_US"); o.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "MMM d, h:mm a"
      return o.string(from: d)
    }()
    let s = NSMutableAttributedString(string: "🕓 Scheduled · \(when)", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.label])
    let t = x["text"] as? String ?? "", n = x["files"] as? Int ?? 0
    s.append(NSAttributedString(string: "\n" + (t.isEmpty ? "\(n) file\(n == 1 ? "" : "s")" : t), attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel]))
    label.attributedText = s; label.numberOfLines = 4
    box.addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }
  private var dash: CAShapeLayer?
  func height(for W: CGFloat) -> CGFloat { ceil(label.sizeThatFits(CGSize(width: W - 32 - 28, height: 200)).height) + 24 + 12 }
  override func layoutSubviews() {
    super.layoutSubviews()
    box.frame = CGRect(x: 16, y: 6, width: bounds.width - 32, height: bounds.height - 12)
    label.frame = box.bounds.insetBy(dx: 14, dy: 12)
    dash?.frame = box.bounds; dash?.path = UIBezierPath(roundedRect: box.bounds, cornerRadius: 16).cgPath
  }
}
