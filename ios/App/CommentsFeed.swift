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
  var onReply: ((String) -> Void)?                   // Reply: the box replies to this comment
  var onThread: ((String) -> Void)?                  // "N replies" → the thread's page
  var onBack: (() -> Void)?                          // (a thread page) back to the comments
  var onToast: ((String) -> Void)?
  var onSheet: (([String: Any], @escaping (Int, String?) -> Void) -> Void)?
  let scroll = UIScrollView()
  private let content = UIView()
  private var cells: [String: CommentCell] = [:]
  private var order: [String] = []
  private(set) var model: [String: Any]?
  private var people: [String: [String: Any]] = [:]
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
  func load(_ done: (() -> Void)? = nil) {
    var p = "/api/comments?id=" + (taskId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? taskId)
    if let t = thread { p += "&thread=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t) }
    FeedLoader.shared.get(p) { [weak self] j in
      guard let self = self, let f = j?["feed"] as? [String: Any] else { done?(); return }
      self.draw(f); done?()
    }
  }
  private func draw(_ m: [String: Any]) {
    model = m
    if let pp = m["people"] as? [String: [String: Any]] { people.merge(pp) { _, b in b } }
    let items = (m["items"] as? [[String: Any]]) ?? []
    let atEnd = isAtEnd()
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
      c.onReact = { [weak self] e in guard let self = self else { return }; self.onAct?(["act": "react", "id": self.taskId, "key": id, "value": e]) }
      content.addSubview(c); cells[id] = c
    }
    for (id, c) in cells where !seen.contains(id) { c.removeFromSuperview(); cells[id] = nil }
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
    content.frame = CGRect(x: 0, y: 0, width: W, height: y + 8)
    scroll.contentSize = content.frame.size
    scroll.contentInset.bottom = bottomRoom
    scroll.verticalScrollIndicatorInsets.bottom = bottomRoom
  }
  // the box grew or the keyboard came: at the latest it stays at the latest
  private func roomChanged(_ old: CGFloat) {
    let wasEnd = scroll.contentOffset.y + scroll.bounds.height >= scroll.contentSize.height + old - 60
    scroll.contentInset.bottom = bottomRoom; scroll.verticalScrollIndicatorInsets.bottom = bottomRoom
    if wasEnd { toEnd(animated: false) }
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
    if !ro { rows.append(["i": -1, "label": "", "kind": "emoji", "chips": emojis.enumerated().map { ["i": 100 + $0.offset, "swatch": $0.element] }]) }
    if (it["canReply"] as? Bool) == true && thread == nil { rows.append(["i": 1, "label": "Reply", "icon": "reply"]) }
    if thread != nil && !ro { rows.append(["i": 1, "label": "Reply", "icon": "reply"]) }
    rows.append(["i": 2, "label": "Copy text", "icon": "copy"])
    var secs: [[String: Any]] = [["rows": rows]]
    if (it["canDelete"] as? Bool) == true { secs.append(["rows": [["i": 3, "label": "Delete comment", "icon": "trash", "danger": true]]]) }
    onSheet?(["sections": secs]) { [weak self] i, swatch in
      guard let self = self else { return }
      if let e = swatch, emojis.contains(e) { self.onAct?(["act": "react", "id": self.taskId, "key": id, "value": e]); return }
      switch i {
      case 1: self.onReply?(id); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.keepInView(id) }
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
    let pics = files.filter { CommentCell.isPic($0["name"] as? String ?? "") }
    if !pics.isEmpty { stack.addArrangedSubview(CommentCell.tiles(pics)) }
    for f in files where !CommentCell.isPic(f["name"] as? String ?? "") { stack.addArrangedSubview(CommentCell.fileRow(f)) }
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
    if let sn = it["seen"] as? [String: Any] {
      let l = UILabel(); l.font = .systemFont(ofSize: 12.5); l.textColor = .secondaryLabel
      var t = sn["label"] as? String ?? ""
      if let at = sn["at"] as? String { t += " · " + TaskPage.when(at) }
      let eye = UIImageView(image: UIImage(systemName: (sn["on"] as? Bool) == true ? "eye" : "eye.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))); eye.tintColor = .secondaryLabel
      l.text = t
      let s = UIStackView(arrangedSubviews: [eye, l, UIView()]); s.spacing = 5; s.alignment = .center
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
    if (it["owner"] as? Bool) == true {
      let bar = UIView(); bar.backgroundColor = .systemOrange; bar.layer.cornerRadius = 1.5
      bar.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(bar)
      NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: hasReplies || root ? 3 : -8), bar.widthAnchor.constraint(equalToConstant: 3), bar.topAnchor.constraint(equalTo: card.topAnchor, constant: 10), bar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)])
    }
    let lp = UILongPressGestureRecognizer(target: self, action: #selector(held(_:))); lp.minimumPressDuration = 0.45
    addGestureRecognizer(lp)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func held(_ g: UILongPressGestureRecognizer) {
    if g.state == .began {
      UIView.animate(withDuration: 0.12, animations: { self.card.transform = CGAffineTransform(scaleX: 0.985, y: 0.985) }) { _ in UIView.animate(withDuration: 0.2) { self.card.transform = .identity } }
      onHold?()
    }
  }
  func height(for W: CGFloat) -> CGFloat {
    if let m = measured, m.0 == W { return m.1 }
    card.frame = CGRect(x: 16, y: 6, width: W - 32, height: 10)
    let h = card.systemLayoutSizeFitting(CGSize(width: W - 32, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    measured = (W, h + 12)
    return h + 12
  }
  override func layoutSubviews() { super.layoutSubviews(); card.frame = CGRect(x: 16, y: 6, width: bounds.width - 32, height: bounds.height - 12) }

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
  // up to 3 a row, 4:3 each (one alone: wider) — a grey shimmer until the picture arrives
  static func tiles(_ pics: [[String: Any]]) -> UIView {
    let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 6
    let perRow = pics.count == 1 ? 1 : min(3, pics.count)
    var i = 0
    while i < min(pics.count, 6) {
      let row = UIStackView(); row.spacing = 6; row.distribution = .fillEqually
      for f in pics[i..<min(i + perRow, min(pics.count, 6))] {
        let v = UIImageView(); v.contentMode = .scaleAspectFill; v.clipsToBounds = true; v.layer.cornerRadius = 12; v.layer.cornerCurve = .continuous
        v.backgroundColor = .tertiarySystemFill
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalTo: v.widthAnchor, multiplier: 0.75).isActive = true
        let shimmer = Shimmer(); shimmer.frame = .zero; shimmer.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(shimmer)
        NSLayoutConstraint.activate([shimmer.leadingAnchor.constraint(equalTo: v.leadingAnchor), shimmer.trailingAnchor.constraint(equalTo: v.trailingAnchor), shimmer.topAnchor.constraint(equalTo: v.topAnchor), shimmer.bottomAnchor.constraint(equalTo: v.bottomAnchor)])
        if let p = (f["thumbUrl"] as? String) ?? (f["url"] as? String) { FeedLoader.shared.image(p) { [weak v, weak shimmer] img in shimmer?.removeFromSuperview(); if let img = img { v?.image = img } } }
        row.addArrangedSubview(v)
      }
      if pics.count == 1 { row.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true }
      let wrap = UIStackView(arrangedSubviews: [row]); wrap.alignment = pics.count == 1 ? .leading : .fill
      grid.addArrangedSubview(wrap)
      i += perRow
    }
    return grid
  }
  static func fileRow(_ f: [String: Any]) -> UIView {
    let box = UIView(); box.backgroundColor = .tertiarySystemFill; box.layer.cornerRadius = 12; box.layer.cornerCurve = .continuous
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
