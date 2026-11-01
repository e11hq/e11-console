import UIKit

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
    p.onBack = { [weak self, weak p] in guard let self = self, let p = p else { return }; self.closeTaskPage(p) }
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
  func taskShowComments(_ p: TaskPage, focus: String) {
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
    cbox.isHidden = true; jumpHit.isHidden = true
    FeedLoader.shared.cookies = serverHome.cookies
    let f: CommentsFeed
    if let old = p.feed { f = old } else {
      f = makeFeed(p, thread: nil)
      p.feed = f
      p.commentsHost.addSubview(f)
    }
    f.frame = p.commentsHost.bounds
    f.isHidden = false
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
      guard let self = self, let b = self.cbarIfMade, !b.isHidden, let w = self.view.window else { return nil }
      let fr = b.layer.presentation()?.frame ?? b.frame
      return self.view.convert(fr, to: w).minY
    }
    f.onAct = { [weak self, weak p, weak f] body in
      guard let self = self, let p = p else { return }
      self.serverTask.act(body.merging(["page": p.taskId]) { a, _ in a }) { ok, m, err, _, messages in
        if !ok { p.toast(err ?? "That didn’t work — try again") }
        else if let first = messages.first { p.toast(first) }
        if let m = m { p.draw(m) }
        f?.load(); p.feed?.load()
      }
    }
    f.onToast = { [weak p] t in p?.toast(t) }
    f.onSheet = { [weak self] args, answer in
      guard let self = self, let host = self.sheetHost() else { return }
      host.present(NativeSheetVC(args, dark: self.statusStyle != .darkContent, pick: nil, answer: answer), animated: true)
    }
    // Reply: the comments screen behind sets the reply (its box line says "Replying to …"); the keyboard comes up
    f.onReply = { [weak self] cid in
      guard let self = self else { return }
      let js = "(function(){var b=document.querySelector('#detail .cm[data-comment=\"" + cid.replacingOccurrences(of: "\"", with: "") + "\"] [data-action=\"reply\"]');if(b){b.click();return 'ok'}return 'no'})()"
      self.cweb?.evaluateJavaScript(js) { _, _ in self.cbar.text.becomeFirstResponder() }
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
    t.load { [weak t] in if let id = pulse { t?.pulse(id) } }
    UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) { t.transform = .identity }
    let js = "(function(){var b=document.querySelector('#detail [data-action=\"open-thread\"][data-id=\"" + cid.replacingOccurrences(of: "\"", with: "") + "\"]');if(b)b.click();})()"
    cweb?.evaluateJavaScript(js, completionHandler: nil)
  }
  func closeThread(_ p: TaskPage) {
    guard let t = p.threadFeed else { return }
    let back = t.thread
    p.threadFeed = nil
    UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { t.transform = CGAffineTransform(translationX: p.bounds.width, y: 0) } completion: { _ in t.removeFromSuperview() }
    cweb?.evaluateJavaScript("window.__e11CmBack && window.__e11CmBack()", completionHandler: nil)
    // back on the comment the thread is for: it pulses
    if let id = back, let f = p.feed { f.load { f.pulse(id) } }
  }
  func taskHideComments() {
    guard taskComments != nil else { return }
    taskComments = nil
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
