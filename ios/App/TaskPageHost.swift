import UIKit
import QuickLook

/* The app's own task page (shell 30) on the app's screen: opened when the page behind asks (taskPage open — a card,
   a row in the Inbox, a search result…), pushed in from the right as iPhone's own pages are, and taken back with ‹
   or the swipe from the left edge, which follows the finger and lets go the way it was going. Its data and changes
   are the server's (ServerTask); the page behind only hears that it closed, and does what only it can do (Copy link,
   attaching files, New task from this). */
extension Main {
  func taskPageCommand(_ a: [String: Any]) {
    if let id = a["open"] as? String, !id.isEmpty {
      // (already the top page: just its tab)
      if let top = taskPages.last, top.taskId == id { if let t = a["tab"] as? String, t != top.tab { top.setTab(t, tell: true) }; return }
      openTaskPage(id, tab: a["tab"] as? String ?? "details", focus: a["focus"] as? String ?? "")
    } else if let id = a["changed"] as? String {
      for p in taskPages where p.taskId == id || ((p.model?["subtasks"] as? [[String: Any]]) ?? []).contains(where: { ($0["id"] as? String) == id }) { refreshTaskPage(p); p.feed?.load(); p.threadFeed?.load() }
    } else if (a["closeAll"] as? Bool) == true {
      while let p = taskPages.last { closeTaskPage(p, animated: false) }
    }
  }

  func openTaskPage(_ id: String, tab: String, focus: String) {
    endEditing()
    let p = TaskPage(id: id, frame: view.bounds)
    p.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    p.light = statusStyle == .darkContent
    let under: UIView? = taskPages.last
    if taskPages.isEmpty { taskTabHidden = tabBar.isHidden }
    view.insertSubview(p, belowSubview: tabBar)
    // (the comment box and its jump spot stay above the page)
    if let b = cbarIfMade { view.insertSubview(b, aboveSubview: p) }
    if jumpHitMade { view.insertSubview(jumpHit, aboveSubview: cbarIfMade ?? p) }
    taskPages.append(p)
    wire(p)
    p.people = serverHome.shown.flatMap { $0["people"] as? [String: [String: Any]] } ?? [:]
    p.setTab(tab == "comments" ? "comments" : "details", tell: false)
    p.loading()
    refreshTaskPage(p)
    // (the corner button: Search / Mark all read slides over into ••• as the page comes in)
    updateCornerNow()
    // the edge swipe: one, on the app's screen, for whichever page is on top
    if taskPan == nil {
      let g = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(taskEdgePan(_:)))
      g.edges = .left
      view.addGestureRecognizer(g)
      taskPan = g
    }
    taskPan?.isEnabled = true
    // in from the right, the screen under it moving a little to the left and darkening (as iPhone's own push)
    let W = view.bounds.width
    p.transform = CGAffineTransform(translationX: W, y: 0)
    shadow(p, on: true)
    UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      p.transform = .identity
      self.underViews(below: p, under: under).forEach { $0.transform = CGAffineTransform(translationX: -W * 0.3, y: 0) }
      self.tabBar.alpha = 0
    } completion: { _ in
      if self.taskPages.last === p {
        self.tabBar.isHidden = true
        if p.tab == "comments" { self.taskShowComments(p, focus: focus) }
      }
    }
  }
  // what's under a page: the page before it, or the app's screen (the page and its own screens)
  func underViews(below p: TaskPage, under: UIView?) -> [UIView] {
    if let u = under { return [u] }
    let W = view.bounds.width
    return view.subviews.filter { v in
      if v === p || v === tabBar || v === cbarIfMade || v === cbox || v.isHidden || v.frame.width < W - 1 { return false }
      if jumpHitMade && v === jumpHit { return false }
      return !taskPages.contains { $0 === v }
    }
  }
  private func shadow(_ p: UIView, on: Bool) {
    p.layer.shadowColor = UIColor.black.cgColor
    p.layer.shadowOpacity = on ? 0.18 : 0
    p.layer.shadowRadius = 12
    p.layer.shadowOffset = CGSize(width: -3, height: 0)
    p.layer.shadowPath = UIBezierPath(rect: p.bounds).cgPath
  }

  func closeTaskPage(_ p: TaskPage, animated: Bool = true) {
    guard let i = taskPages.firstIndex(where: { $0 === p }) else { return }
    p.endEditing(true)
    if p.tab == "comments" { taskHideComments() }
    taskPages.remove(at: i)
    let under: UIView? = taskPages.last
    let back = underViews(below: p, under: under)
    let W = view.bounds.width
    let last = taskPages.isEmpty
    updateCornerNow()
    if last { tabBar.isHidden = taskTabHidden; taskPan?.isEnabled = false }
    let finish = {
      p.removeFromSuperview()
      back.forEach { $0.transform = .identity }
      if last { self.pageJS("window.__e11Task && window.__e11Task({ev:'closed'})") }
      else if let top = self.taskPages.last, top.tab == "comments" { self.taskShowComments(top, focus: "") }
    }
    if !animated { finish(); if last { tabBar.alpha = 1 }; return }
    UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
      p.transform = CGAffineTransform(translationX: W, y: 0)
      back.forEach { $0.transform = .identity }
      if last { self.tabBar.alpha = 1 }
    } completion: { _ in finish() }
  }

  // iPhone's swipe back from the left edge: the page follows the finger; let go, it goes the way it was going
  @objc func taskEdgePan(_ g: UIScreenEdgePanGestureRecognizer) {
    guard let p = taskPages.last else { return }
    let W = view.bounds.width
    let x = max(0, g.translation(in: view).x)
    let under: UIView? = taskPages.count > 1 ? taskPages[taskPages.count - 2] : nil
    let back = underViews(below: p, under: under)
    switch g.state {
    case .began:
      p.endEditing(true)
      if p.tab == "comments" { cbarIfMade?.text.resignFirstResponder() }
    case .changed:
      p.transform = CGAffineTransform(translationX: x, y: 0)
      back.forEach { $0.transform = CGAffineTransform(translationX: -W * 0.3 * (1 - x / W), y: 0) }
      if taskPages.count == 1 && !taskTabHidden { tabBar.isHidden = false; tabBar.alpha = x / W }
      if p.tab == "comments" { cbarIfMade?.transform = CGAffineTransform(translationX: x, y: 0) }
      corner.between(cornerTarget(), cornerTarget(skipTop: true), x / W)
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: view).x
      let go = g.state == .ended && (v > 300 || (x > W * 0.4 && v > -200))
      if go {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        cbarIfMade?.transform = .identity
        closeTaskPage(p)
      } else {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          p.transform = .identity
          back.forEach { $0.transform = CGAffineTransform(translationX: -W * 0.3, y: 0) }
          if self.taskPages.count == 1 { self.tabBar.alpha = 0 }
          self.cbarIfMade?.transform = .identity
        } completion: { _ in if !self.taskPages.isEmpty { self.tabBar.isHidden = true } }
        updateCorner()
      }
    default: break
    }
  }

  private func wire(_ p: TaskPage) {
    p.onBack = { [weak self, weak p] in guard let self = self, let p = p else { return }; if p.editingDesc { p.finishDesc() }; self.closeTaskPage(p) }
    p.onCornerChange = { [weak self] in self?.updateCornerNow() }
    p.onOpenFiles = { [weak self] list, i in self?.openFiles(list, at: i) }
    p.onAttachFiles = { [weak self, weak p] in
      guard let self = self, let p = p, let host = self.sheetHost() else { return }
      host.present(AttachSheetVC(light: self.statusStyle == .darkContent) { [weak self] src in
        self?.pageJS("window.__e11Task && window.__e11Task(\(jsonString(["ev": "attach", "id": p.taskId, "source": src])))")
      }, animated: true)
    }
    p.onSubmitFiles = { [weak self, weak p] cd in
      guard let self = self, let p = p, let host = self.sheetHost() else { return }
      let vc = SubmitSheetVC(task: p.taskId, cd: cd, light: self.statusStyle == .darkContent) { [weak self, weak p] files in
        guard let self = self, let p = p else { return }
        self.taskAct(p, ["act": "submitReview", "id": p.taskId, "files": files])
      }
      vc.cookies = self.serverHome.cookies
      host.present(vc, animated: true)
    }
    p.onOpen = { [weak self] id in self?.openTaskPage(id, tab: "details", focus: "") }
    p.onTab = { [weak self, weak p] t in guard let self = self, let p = p else { return }; if t == "comments" { self.taskShowComments(p, focus: "") } else { self.taskHideComments() } }
    p.onEvent = { [weak self] ev in self?.pageJS("window.__e11Task && window.__e11Task(\(jsonString(ev)))") }
    p.onAct = { [weak self, weak p] body in guard let self = self, let p = p else { return }; self.taskAct(p, body) }
    p.onComplete = { [weak self, weak p] in
      guard let self = self, let p = p, let c = p.model?["complete"] as? [String: Any] else { return }
      if (c["ok"] as? Bool) != true { p.toast(c["why"] as? String ?? "Not ready yet"); return }
      self.taskAct(p, ["act": "done", "id": p.taskId])
    }
    p.onSheet = { [weak self] args, pick, answer in
      guard let self = self, let host = self.sheetHost() else { return }
      host.present(NativeSheetVC(args, dark: self.statusStyle != .darkContent, pick: pick, answer: answer), animated: true)
    }
    p.onDate = { [weak self] which, value, answer in
      guard let self = self, let host = self.sheetHost() else { return }
      host.present(DateSheetVC(["value": value, "min": "", "max": "", "clearable": !value.isEmpty, "md": false], dark: self.statusStyle != .darkContent) { r in
        if (r["cancel"] as? Bool) == true || (r["ok"] as? Bool) == false { return answer(nil) }
        let v = (r["clear"] as? Bool) == true ? "" : (r["date"] as? String ?? "")
        answer(v == value ? nil : v)
      }, animated: true)
    }
  }

  func refreshTaskPage(_ p: TaskPage) {
    serverTask.fetch(p.taskId) { [weak self, weak p] m, off in
      guard let self = self, let p = p, self.taskPages.contains(where: { $0 === p }) else { return }
      if off { self.taskPageToWeb(p); return }
      guard let m = m else {
        if p.model == nil { p.toast("This task is no longer here"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.closeTaskPage(p) } }
        return
      }
      self.drawTask(p, m)
    }
  }
  private func drawTask(_ p: TaskPage, _ m: [String: Any]) {
    p.draw(m)
    // (photos: fetched with the app's sign-in, kept with Home's)
    if let pp = m["people"] as? [String: [String: Any]] {
      serverHome.photos(pp) { [weak p] got in p?.peopleChanged(got.filter { ($0.value["photo"] as? String)?.hasPrefix("data:") == true }) }
    }
  }
  // the server switched the app's task page off: the website's own task page instead
  private func taskPageToWeb(_ p: TaskPage) {
    let id = p.taskId, tab = p.tab
    closeTaskPage(p, animated: false)
    pageJS("window.__e11Task && window.__e11Task(\(jsonString(["ev": "web", "id": id, "tab": tab])))")
  }

  func taskAct(_ p: TaskPage, _ body: [String: Any]) {
    var b = body
    if (b["id"] as? String) != p.taskId { b["page"] = p.taskId }
    serverTask.act(b) { [weak self, weak p] ok, m, err, need, messages in
      guard let self = self, let p = p else { return }
      if !ok {
        if need == "clientApproval" {
          let al = UIAlertController(title: "Did the client approve?", message: "Saved with the final files in Client Assets.", preferredStyle: .actionSheet)
          al.addAction(UIAlertAction(title: "Yes, today", style: .default) { _ in var x = b; x["clientApproval"] = "yes"; self.taskAct(p, x) })
          al.addAction(UIAlertAction(title: "Not needed", style: .default) { _ in var x = b; x["clientApproval"] = "none"; self.taskAct(p, x) })
          al.addAction(UIAlertAction(title: "Cancel", style: .cancel))
          self.topMost().present(al, animated: true)
        } else if need == "cdAgain", let st = b["value"] as? String { p.askCdAgain(st) }
        else { UINotificationFeedbackGenerator().notificationOccurred(.warning); p.toast(err ?? "That didn’t work — try again") }
        // (what was shown at once — a tick — goes back to how it is)
        self.refreshTaskPage(p)
        return
      }
      if (b["act"] as? String) == "delete", (b["page"] == nil) {
        self.closeTaskPage(p)
        self.serverHome.refresh()
        return
      }
      if (b["act"] as? String) == "done", b["page"] == nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
      if let first = messages.first, !first.isEmpty { p.toast(first) }
      if let m = m { self.drawTask(p, m) } else { self.refreshTaskPage(p) }
      // (Home, My Tasks and the Inbox under it: as they are now)
      self.serverHome.refresh()
    }
  }

  // ---------- its Comments tab: the comments screen inside the page, under its bar ----------
  // step 3: the app's own box (ComposeBox), on the keyboard, above the task page
  var compose: ComposeBox {
    if let c = composeIfMade { return c }
    let c = ComposeBox()
    c.translatesAutoresizingMaskIntoConstraints = false
    c.isHidden = true
    view.insertSubview(c, belowSubview: tabBar)
    NSLayoutConstraint.activate([c.leadingAnchor.constraint(equalTo: view.leadingAnchor), c.trailingAnchor.constraint(equalTo: view.trailingAnchor), c.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])
    c.cookies = serverHome.cookies
    c.onToast = { [weak self] t in self?.taskPages.last?.toast(t) }
    c.onAttach = { [weak self] pick in
      guard let self = self, let host = self.sheetHost() else { return }
      host.present(AttachSheetVC(light: self.statusStyle == .darkContent) { src in pick(src) }, animated: true)
    }
    c.onSend = { [weak self] body, done in
      guard let self = self, let p = self.taskPages.last else { return done(false) }
      self.serverTask.act(body.merging(["page": p.taskId]) { a, _ in a }) { ok, m, err, _, _ in
        if !ok { p.toast(err ?? "Not sent — try again") }
        done(ok)
        if let m = m { p.draw(m) }
        p.feed?.load(); p.threadFeed?.load()
      }
    }
    composeIfMade = c
    return c
  }
  func taskShowComments(_ p: TaskPage, focus: String) {
    if !defaults.bool(forKey: "e11_feed_off") {
      // the comments and the box, both the app's own: nothing of the website's behind them
      taskComments = focus.isEmpty ? p.taskId : focus
      p.bringSubviewToFront(p.commentsHost); p.bringSubviewToFront(p.barBoxView)
      let c = compose
      c.switchTo(task: p.taskId, parent: p.threadFeed?.thread)
      view.insertSubview(c, aboveSubview: p)
      if c.isHidden { c.alpha = 0; c.isHidden = false; UIView.animate(withDuration: 0.12) { c.alpha = 1 } }
      showFeed(p, focus: focus)
      return
    }
    makeCommentsWeb()
    taskComments = focus.isEmpty ? p.taskId : focus
    // (the comments screen goes inside the page, below its bar; the box and its jump spot above the page)
    if cbox.superview !== p.commentsHost { p.commentsHost.addSubview(cbox) }
    p.bringSubviewToFront(p.commentsHost); p.bringSubviewToFront(p.barBoxView)
    if let b = cbarIfMade { view.insertSubview(b, aboveSubview: p) }
    cbarTask = taskComments
    cbarShow = true; cbarOnComments = true
    cbarFeed = CGRect(x: 0, y: p.barBottom, width: view.bounds.width, height: view.bounds.height - p.barBottom)
    cwebUpdate()
    // (the box: shown, as the page's own sync would; its contents are the comments screen's to say)
    let b = cbar
    if b.isHidden { b.isHidden = false; UIView.animate(withDuration: 0.1) { b.alpha = 1 } }
    if let cp = cwebPanG, let tp = taskPan { cp.require(toFail: tp) }
    // step 2: the comments drawn by the app (the comments screen stays behind it, unseen, for writing until step 3)
    if !defaults.bool(forKey: "e11_feed_off") { showFeed(p, focus: focus) }
  }
  private func showFeed(_ p: TaskPage, focus: String) {
    if cwebShown { cbox.isHidden = true }; if jumpHitMade { jumpHit.isHidden = true }
    FeedLoader.shared.cookies = serverHome.cookies
    let f: CommentsFeed
    if let old = p.feed { f = old } else {
      f = makeFeed(p, thread: nil)
      p.feed = f
      p.commentsHost.addSubview(f)
    }
    f.frame = p.commentsHost.bounds
    f.isHidden = false
    p.edgeScroll(p.threadFeed?.scroll ?? f.scroll)
    p.commentsHost.bringSubviewToFront(f)
    if let t = p.threadFeed { p.commentsHost.bringSubviewToFront(t) }
    f.load { [weak self, weak p, weak f] in
      // from the Inbox: that comment pulses — in its thread for a reply
      let parts = focus.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
      guard let self = self, let p = p, let f = f, parts.count > 1, !parts[1].isEmpty else { return }
      let cid = parts[1]
      if f.has(cid) { f.pulse(cid) }
      else if let parent = (f.model?["parents"] as? [String: String])?[cid] { self.openThread(p, parent, pulse: cid) }
    }
  }
  private func makeFeed(_ p: TaskPage, thread: String?) -> CommentsFeed {
    let f = CommentsFeed(task: p.taskId, thread: thread)
    f.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    f.topInset = p.barBottom
    f.boxTop = { [weak self] in
      guard let self = self, let b = self.composeIfMade, !b.isHidden, let w = self.view.window else { return nil }
      let fr = b.layer.presentation()?.frame ?? b.frame
      return self.view.convert(fr, to: w).minY
    }
    f.onAct = { [weak self, weak p, weak f] body in
      guard let self = self, let p = p else { return }
      self.serverTask.act(body.merging(["page": p.taskId]) { a, _ in a }) { ok, m, err, _, messages in
        if !ok { p.toast(err ?? "That didn’t work — try again") }
        else if (body["act"] as? String) == "deleteComment", let u = self.serverTask.lastUndo {
          // Undo for 8 seconds: the comment and its replies back
          p.toast("Comment deleted", action: ("Undo", { [weak self, weak p, weak f] in
            guard let self = self, let p = p else { return }
            self.serverTask.act(["act": "undoDelete", "trashId": u, "id": p.taskId, "page": p.taskId]) { ok, _, err, _, _ in
              if !ok { p.toast(err ?? "Couldn’t bring it back") }
              f?.load(); p.feed?.load(); self.refreshTaskPage(p)
            }
          }))
        } else if let first = messages.first { p.toast(first) }
        if let m = m { p.draw(m) }
        f?.load(); p.feed?.load()
      }
    }
    f.onLoaded = { [weak self] m in if let ml = m["mentionable"] as? [[String: Any]] { self?.composeIfMade?.mentionable = ml } }
    f.onOpenFile = { [weak self] list, i in self?.openFiles(list, at: i) }
    f.onToast = { [weak p] t in p?.toast(t) }
    f.onSheet = { [weak self] args, answer in
      guard let self = self, let host = self.sheetHost() else { return }
      host.present(NativeSheetVC(args, dark: self.statusStyle != .darkContent, pick: nil, answer: answer), animated: true)
    }
    // Reply: the comments screen behind sets the reply (its box line says "Replying to …"); the keyboard comes up
    f.onReply = { [weak self] cid, name in
      guard let self = self else { return }
      let c = self.compose
      if thread == nil { c.replyTo = (cid, name) }
      c.text.becomeFirstResponder()
    }
    f.onEdit = { [weak self] cid, runs in
      guard let self = self else { return }
      let c = self.compose
      c.editing = cid
      c.setText(DescEditor.attributed(runs, done: false))
      c.text.becomeFirstResponder()
    }
    f.onThread = { [weak self, weak p] cid in guard let self = self, let p = p else { return }; self.openThread(p, cid, pulse: nil) }
    f.onBack = { [weak self, weak p] in guard let self = self, let p = p else { return }; self.closeThread(p) }
    return f
  }
  // a thread on a page of its own, sliding in from the right; the comments screen behind opens it too (for replying)
  func openThread(_ p: TaskPage, _ cid: String, pulse: String?) {
    p.threadFeed?.removeFromSuperview()
    let t = makeFeed(p, thread: cid)
    p.threadFeed = t
    t.frame = p.commentsHost.bounds
    p.commentsHost.addSubview(t)
    t.transform = CGAffineTransform(translationX: p.bounds.width, y: 0)
    composeIfMade?.replyTo = nil; composeIfMade?.switchTo(task: p.taskId, parent: cid)
    t.load { [weak t] in if let id = pulse { t?.pulse(id) } }
    p.edgeScroll(t.scroll)
    UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) { t.transform = .identity }
  }
  func closeThread(_ p: TaskPage) {
    guard let t = p.threadFeed else { return }
    let back = t.thread
    p.threadFeed = nil
    composeIfMade?.switchTo(task: p.taskId, parent: nil)
    if let f = p.feed { p.edgeScroll(f.scroll) }
    UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { t.transform = CGAffineTransform(translationX: p.bounds.width, y: 0) } completion: { _ in t.removeFromSuperview() }
    // back on the comment the thread is for: it pulses
    if let id = back, let f = p.feed { f.load { f.pulse(id) } }
  }
  func taskHideComments() {
    guard taskComments != nil else { return }
    taskComments = nil
    if let c = composeIfMade, !c.isHidden {
      c.text.resignFirstResponder()
      c.switchTo(task: c.taskId, parent: c.parentId)   // (keeps what's written)
      UIView.animate(withDuration: 0.12, animations: { c.alpha = 0 }) { _ in if c.alpha == 0 { c.isHidden = true } }
      if defaults.bool(forKey: "e11_feed_off") == false { return }
    }
    cbarOnComments = false; cbarShow = false; cbarTask = nil
    cwebUpdate()
    let b = cbar
    if b.text.isFirstResponder { b.text.resignFirstResponder() }
    UIView.animate(withDuration: 0.12, animations: { b.alpha = 0 }) { _ in if b.alpha == 0 { b.isHidden = true } }
    jumpHit.isHidden = true
    // (back on the app's screen once it's hidden, for the page's own task page)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self = self, self.taskComments == nil, self.cbox.isHidden else { return }
      if self.cbox.superview !== self.view, let w = self.web { self.view.insertSubview(self.cbox, aboveSubview: w) }
    }
  }
  func endEditing() { view.endEditing(true) }
}

/* A comment's or a task's file, opened (Haris: "finish off the whole task detail / comment"): pictures in the app's
   own preview (swipe through the others beside it); any other file fetched and shown by iPhone's own Quick Look —
   PDFs, videos, documents — with its Share button (Save to Files, AirDrop…). */
final class QuickFile: NSObject, QLPreviewControllerDataSource {
  static let shared = QuickFile()
  private var url: URL?
  func numberOfPreviewItems(in c: QLPreviewController) -> Int { url == nil ? 0 : 1 }
  func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { (url ?? URL(fileURLWithPath: "/")) as NSURL }
  func show(_ f: [String: Any], from host: UIViewController, toast: @escaping (String) -> Void) {
    guard let path = f["url"] as? String else { return toast("This file isn’t available") }
    toast("Opening…")
    PreviewLoad.data(serverURL() + path) { d in
      guard let d = d else { return toast("Couldn’t open the file — try again") }
      let name = (f["name"] as? String ?? "File").replacingOccurrences(of: "/", with: "-")
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent("open-\(UUID().uuidString)", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let u = dir.appendingPathComponent(name)
      guard (try? d.write(to: u)) != nil else { return toast("Couldn’t open the file") }
      self.url = u
      let q = QLPreviewController(); q.dataSource = self
      host.present(q, animated: true)
    }
  }
}
extension Main {
  func openFiles(_ files: [[String: Any]], at i: Int) {
    guard i < files.count else { return }
    let f = files[i]
    PreviewLoad.refreshCookies(web.configuration.websiteDataStore.httpCookieStore) { [weak self] in
      guard let self = self, let host = self.sheetHost() else { return }
      self.composeIfMade?.text.resignFirstResponder()
      if CommentCell.isPic(f["name"] as? String ?? "") {
        let pics = files.filter { CommentCell.isPic($0["name"] as? String ?? "") }
        let list: [[String: Any]] = pics.map { p in
          let ext = ((p["name"] as? String ?? "") as NSString).pathExtension.lowercased()
          return ["id": p["id"] ?? "", "name": p["name"] ?? "", "kind": "image", "ext": ext, "src": serverURL() + (p["url"] as? String ?? ""), "thumb": (p["thumbUrl"] as? String).map { serverURL() + $0 } ?? "", "meta": TaskPage.size(p["size"] as? Int ?? 0)]
        }
        let at = pics.firstIndex { ($0["id"] as? String) == (f["id"] as? String) } ?? 0
        let vc = PreviewVC(["files": list, "at": at], dark: self.statusStyle != .darkContent) { _ in }
        self.previewVC = vc
        host.present(vc, animated: true)
      } else {
        QuickFile.shared.show(f, from: host) { [weak self] t in self?.taskPages.last?.toast(t) }
      }
    }
  }
}
