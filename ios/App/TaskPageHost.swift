import UIKit
import UniformTypeIdentifiers
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
    // (Home / My Tasks hid itself as the task was tapped — for the website's page, which slid over the page's own
    //  Home; the app's page slides over the screen itself, so it stays: no black under it, none on the way back)
    if let h = hiddenForOpen, Date().timeIntervalSince(h.1) < 3, let v = h.0 { v.isHidden = false }
    hiddenForOpen = nil
    if taskPages.isEmpty { taskTabHidden = tabBar.isHidden }
    // (under the shared top buttons, which stay where they are)
    if corner.superview === view { view.insertSubview(p, belowSubview: corner) } else { view.insertSubview(p, belowSubview: tabBar) }
    // (the comment box and its jump spot stay above the page)
    if let b = cbarIfMade { view.insertSubview(b, aboveSubview: p) }
    if jumpHitMade { view.insertSubview(jumpHit, aboveSubview: cbarIfMade ?? p) }
    taskPages.append(p)
    wire(p)
    p.people = serverHome.shown.flatMap { $0["people"] as? [String: [String: Any]] } ?? [:]
    p.setTab(tab == "comments" ? "comments" : "details", tell: false)
    p.loading()
    // (opened before: drawn at once as it was, then brought up to date; its comments fetched now, so the Comments tab is ready)
    if let m = serverTask.cache[id] { drawTask(p, m) }
    refreshTaskPage(p)
    // (pictures and files are fetched with the app's sign-in — given here, not only by the comments' fetch, which the
    //  app's own copy makes unnecessary: without it the file cards stayed grey)
    FeedLoader.shared.cookies = serverHome.cookies
    if !AppData.shared.ready { CommentsFeed.prefetch(id, cookies: serverHome.cookies) }
    // (the corner button: Search / Mark all read slides over into ••• as the page comes in — the page laid out
    //  first: before that its ‹ and ••• places are nothing, at the top-left corner, and the buttons flew off there)
    p.setNeedsLayout(); p.layoutIfNeeded()
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
      // (the app's comment box belongs to the page above, not to the screen under it: it never moves aside)
      // (nor do the shared top buttons: they change in place — 🔍 melting into your photo, ••• — not slide off with the screen)
      if v === p || v === tabBar || v === cbarIfMade || v === cbox || (composeIfMade != nil && v === composeIfMade) || v is CornerButton || v.isHidden || v.frame.width < W - 1 { return false }
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
      // (the last page gone: whatever was moved aside when it came in is back in place — a screen hidden or shown
      //  meanwhile too; one left aside showed a blank page, Haris 2026-11-01)
      if last { self.view.subviews.forEach { v in if v !== self.tabBar && !(v is TaskPage) && v.transform.tx != 0 { v.transform = .identity } } }
      // (and the screen under it drawn again as it is now: the page says what's showing — Home, My Tasks, the Inbox)
      if last { self.pageJS("window.__e11HomeResend && __e11HomeResend(); window.__e11MyTasksResend && __e11MyTasksResend(); window.__e11InboxResend && __e11InboxResend()"); self.updateCorner() }
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
    // on Comments the swipe from the edge goes to Details (out of a thread first), not back to the list — and the
    // rest of that swipe is used up: its "cancelled" (the page now on Details) mustn't run the slide back below,
    // which moved the comment box aside and left it cut off (Haris, 2026-11-01)
    if g.state == .began { taskPanSpent = false }
    if taskPanSpent { return }
    if p.tab == "comments" {
      if g.state == .began {
        taskPanSpent = true
        composeIfMade?.text.resignFirstResponder()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toDetailsFromComments(p)
        g.isEnabled = false; g.isEnabled = true   // (this swipe is used up)
      }
      return
    }
    switch g.state {
    case .began:
      p.endEditing(true)
    case .changed:
      p.transform = CGAffineTransform(translationX: x, y: 0)
      back.forEach { $0.transform = CGAffineTransform(translationX: -W * 0.3 * (1 - x / W), y: 0) }
      if taskPages.count == 1 && !taskTabHidden { tabBar.isHidden = false; tabBar.alpha = x / W }
      corner.between(cornerTarget(), cornerTarget(skipTop: true), x / W)
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: view).x
      let go = g.state == .ended && (v > 300 || (x > W * 0.4 && v > -200))
      if go {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        closeTaskPage(p)
      } else {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          p.transform = .identity
          back.forEach { $0.transform = CGAffineTransform(translationX: -W * 0.3, y: 0) }
          if self.taskPages.count == 1 { self.tabBar.alpha = 0 }
        } completion: { _ in if !self.taskPages.isEmpty { self.tabBar.isHidden = true } }
        updateCorner()
      }
    default: break
    }
  }

  private func wire(_ p: TaskPage) {
    p.onBack = { [weak self, weak p] in guard let self = self, let p = p else { return }; if p.editingDesc { p.finishDesc() }; self.closeTaskPage(p) }
    p.onCornerChange = { [weak self] in self?.updateCornerNow() }
    p.onSwipeToDetails = { [weak self, weak p] in guard let self = self, let p = p else { return }; self.toDetailsFromComments(p) }
    p.onOpenFiles = { [weak self] list, i in self?.openFiles(list, at: i) }
    p.onFileAction = { [weak self, weak p] f, what in
      guard let self = self, let p = p else { return }
      let toast: (String) -> Void = { [weak p] t in p?.toast(t) }
      if what == "copy" { self.copyFile(f, toast) } else if what == "download" { self.downloadFile(f, from: self.topMost(), toast) }
    }
    p.onAttachFrom = { [weak self, weak p] src in
      guard let self = self, let p = p else { return }
      Picker.shared.pick(from: self.topMost(), single: false, source: src) { [weak self, weak p] r in
        guard let self = self, let p = p else { return }
        let picked = ((r["files"] as? [[String: Any]]) ?? []).compactMap { f -> (URL, String)? in
          guard let tok = f["token"] as? String, let u = Picker.shared.url(tok) else { return nil }
          return (u, f["name"] as? String ?? "File")
        }
        self.uploadToTask(p, picked)
      }
    }
    p.onAttachFiles = { [weak self, weak p] in
      guard let self = self, let p = p, let host = self.sheetHost() else { return }
      host.present(AttachSheetVC(light: self.statusStyle == .darkContent) { [weak self, weak p] src in
        guard let self = self, let p = p else { return }
        Picker.shared.pick(from: self.topMost(), single: false, source: src) { [weak self, weak p] r in
          guard let self = self, let p = p else { return }
          let picked = ((r["files"] as? [[String: Any]]) ?? []).compactMap { f -> (URL, String)? in
            guard let tok = f["token"] as? String, let u = Picker.shared.url(tok) else { return nil }
            return (u, f["name"] as? String ?? "File")
          }
          self.uploadToTask(p, picked)
        }
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
    // the app's own copy first: no request at all (iOS app data plan)
    let c = AppData.shared.screen("task", p.taskId)
    if c.ready {
      if let m = c.model { drawTask(p, m) }
      else if p.model == nil { p.toast("This task is no longer here"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak p] in if let p = p { self?.closeTaskPage(p) } } }
      return
    }
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
    // a voice message on its way: in the feed it's for (the thread page's, or the task's) at once
    c.onPending = { [weak self] id, thread, dur in
      guard let p = self?.taskPages.last else { return }
      if let t = p.threadFeed, thread != nil { t.addPending(id: id, parent: thread, dur: dur) } else { p.feed?.addPending(id: id, parent: thread, dur: dur) }
    }
    c.onPendingEnd = { [weak self] id, ok in
      guard let p = self?.taskPages.last else { return }
      p.feed?.endPending(id: id, ok: ok); p.threadFeed?.endPending(id: id, ok: ok)
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
      c.transform = .identity   // (never left moved aside by a swipe back)
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
    f.onReply = { [weak self] cid, name, person in
      guard let self = self else { return }
      let c = self.compose
      if thread == nil { c.replyPerson = person; c.replyTo = (cid, name) }
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
    }
    // (the app's own comments: nothing of the old website comments screen to put away — going on into it slid the
    //  page's comments in over Details for a moment, Haris 2026-11-01, seen in the self-test film)
    if defaults.bool(forKey: "e11_feed_off") == false { return }
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
  static let officeExt = ["doc", "docx", "ppt", "pptx", "xls", "xlsx", "odt", "odp", "ods", "rtf"]
  // a file as the preview shows it: a picture, a video / sound (Apple's player), a PDF's / Office file's pages, text, or its card
  static func previewItem(_ p: [String: Any]) -> [String: Any] {
    let n = p["name"] as? String ?? ""
    let ext = (n as NSString).pathExtension.lowercased()
    let src = serverURL() + (p["url"] as? String ?? "")
    let thumb = (p["thumbUrl"] as? String).map { serverURL() + $0 } ?? ""
    let meta = [TaskPage.size(p["size"] as? Int ?? 0)].joined()
    var it: [String: Any] = ["id": p["id"] ?? "", "name": n, "ext": String(ext.prefix(5)), "meta": meta, "src": src, "thumb": thumb, "cover": thumb]
    if CommentCell.isPic(n) { it["kind"] = "image" }
    else if CommentCell.isVideo(n) { it["kind"] = "video" }
    else if ["m4a", "mp3", "wav", "aac", "caf"].contains(ext) { it["kind"] = "audio"; it["src"] = src.replacingOccurrences(of: "?view=1", with: "") }
    else if ext == "pdf" || officeExt.contains(ext) { it["kind"] = "pages" }
    else if ["txt", "csv", "md", "json"].contains(ext) { it["kind"] = "text" }
    else { it["kind"] = "other"; it["note"] = "Download it to see the whole file." }
    return it
  }
  // a file tapped: the app's preview, with all the files beside it (a comment's, the task's) to swipe through
  func openFiles(_ files: [[String: Any]], at i: Int) {
    guard i < files.count else { return }
    PreviewLoad.refreshCookies(web.configuration.websiteDataStore.httpCookieStore) { [weak self] in
      guard let self = self, let host = self.sheetHost() else { return }
      self.composeIfMade?.text.resignFirstResponder()
      let vc = PreviewVC(["files": files.map { Main.previewItem($0) }, "at": i], dark: self.statusStyle != .darkContent) { [weak self] ev in self?.previewEvent(ev, files) }
      self.previewVC = vc
      host.present(vc, animated: true)
    }
  }
  // Copy, as the website's: the file itself isn't copied — the app remembers which file it is, and pasting it into a
  // comment adds that same file (no upload, no second copy on the server; Haris, 2026-11-01)
  func copyFile(_ f: [String: Any], _ toast: @escaping (String) -> Void) {
    guard f["file"] is String else { return toast("This file isn’t available") }
    let name = f["name"] as? String ?? "File"
    UIPasteboard.general.string = "📎 " + name
    FileClip.file = f; FileClip.name = name; FileClip.change = UIPasteboard.general.changeCount
    toast("Copied — paste it into a comment")
  }
  // Download: fetched with its progress shown, then iPhone's own Save / Share sheet (Save Image, Save to Files…)
  func downloadFile(_ f: [String: Any], from vc: UIViewController, _ toast: @escaping (String) -> Void) {
    guard let path = f["url"] as? String, let url = URL(string: serverURL() + path.replacingOccurrences(of: "?view=1", with: "")) else { return toast("This file isn’t available") }
    PreviewLoad.refreshCookies(web.configuration.websiteDataStore.httpCookieStore) {
      var r = URLRequest(url: url); r.allHTTPHeaderFields = PreviewLoad.headers(url)
      let name = (f["name"] as? String ?? "File").replacingOccurrences(of: "/", with: "-")
      var watch: NSKeyValueObservation?
      let task = URLSession.shared.downloadTask(with: r) { [weak vc] tmp, resp, _ in
        watch?.invalidate()
        let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        let moved = ok && tmp.map { (try? FileManager.default.moveItem(at: $0, to: dest)) != nil } == true
        DispatchQueue.main.async {
          guard moved, let vc = vc else { return toast("Couldn’t download — try again") }
          let item: Any = CommentCell.isPic(name) ? (UIImage(contentsOfFile: dest.path).map { $0 as Any } ?? dest) : dest
          let share = UIActivityViewController(activityItems: [item], applicationActivities: nil)
          share.popoverPresentationController?.sourceView = vc.view
          vc.present(share, animated: true)
        }
      }
      var last = -1
      watch = task.progress.observe(\.fractionCompleted) { pr, _ in
        let n = Int(pr.fractionCompleted * 100)
        if n / 10 != last / 10 { last = n; DispatchQueue.main.async { toast(n >= 100 ? "Downloaded" : "Downloading… \(n)%") } }
      }
      toast("Downloading…")
      task.resume()
    }
  }
}

extension Main {
  // files from the phone onto the task: each uploads with its bar under Files, then all are added at once
  func uploadToTask(_ p: TaskPage, _ picked: [(URL, String)]) {
    guard !picked.isEmpty else { return }
    p.uploads = picked.map { ($0.1, 0) }
    var done: [[String: Any]] = [], left = picked.count
    for (i, (url, name)) in picked.enumerated() {
      let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
      Uploader.send(url, name: name, task: p.taskId, cookies: serverHome.cookies, progress: { [weak p] f in
        guard let p = p, i < p.uploads.count else { return }
        p.uploads[i].1 = f
      }) { [weak self, weak p] path in
        guard let self = self, let p = p else { return }
        if let path = path { done.append(["name": name, "size": size, "path": path]) }
        left -= 1
        if left == 0 {
          p.uploads = []
          if done.isEmpty { p.toast("Upload failed — try again"); return }
          UINotificationFeedbackGenerator().notificationOccurred(.success)
          Main.playUploaded()
          self.taskAct(p, ["act": "attach", "id": p.taskId, "files": done])
        }
      }
    }
  }
  // the preview's own buttons for a file opened here (not the page's): Copy, Download (with its progress), Info; and
  // a PDF's / Office file's page pictures (made on the server)
  func previewEvent(_ ev: [String: Any], _ files: [[String: Any]]) {
    guard let id = ev["id"] as? String, let f = files.first(where: { ($0["id"] as? String) == id }) else { return }
    let vc = previewVC
    let toast: (String) -> Void = { [weak vc] t in vc?.set(["toast": t]) }
    switch ev["ev"] as? String ?? "" {
    case "copy": copyFile(f, toast)
    case "dl": if let vc = vc { downloadFile(f, from: vc, toast) }
    case "more":
      vc?.set(["info": [["Name", f["name"] as? String ?? ""], ["Size", TaskPage.size(f["size"] as? Int ?? 0)]]])
    case "pages":
      guard let fp = f["file"] as? String else { vc?.set(["id": id, "pages": [String](), "note": "This file couldn’t be previewed — download it to see it."]); return }
      serverTask.request("/api/host/pdfPages", body: ["id": id, "path": fp], timeout: 150) { [weak vc] j in
        let pages = (j?["pages"] as? [String]) ?? []
        let total = j?["total"] as? Int ?? 0
        let note: String? = pages.isEmpty ? ((j?["unavailable"] as? Bool) == true ? "This file can’t be previewed yet — download it to see it." : "This file couldn’t be previewed — download it to see it.")
          : total > pages.count ? "Showing the first \(pages.count) of \(total) pages — download it for the rest." : nil
        var out: [String: Any] = ["id": id, "pages": pages.map { pg in serverURL() + "/__file/" + pg.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/") }]
        if let note { out["note"] = note }
        vc?.set(out)
      }
    default: break
    }
  }
}

extension Main {
  // a swipe right on Comments — or on a reply thread — goes to Details (Haris, 2026-11-01); from Details the edge
  // swipe then goes back to the page before
  func toDetailsFromComments(_ p: TaskPage) {
    composeIfMade?.text.resignFirstResponder()
    if let t = p.threadFeed {
      p.threadFeed = nil
      composeIfMade?.switchTo(task: p.taskId, parent: nil)
      t.removeFromSuperview()
      if let f = p.feed { p.edgeScroll(f.scroll) }
    }
    p.setTab("details", tell: true, slide: true)
  }
}

extension Main {
  // the tasks on Home / My Tasks fetched ahead, a few at a time, so a tapped task opens drawn (Haris, 2026-11-01):
  // the first 15 shown, each again at most every 5 minutes
  func prefetchTasks(_ m: [String: Any]) {
    let ids = ((m["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["cards"] as? [[String: Any]]) ?? [] }.compactMap { $0["id"] as? String }
    let now = Date()
    let want = Array(ids.filter { id in prefetchedAt[id].map { now.timeIntervalSince($0) > 300 } ?? true }.prefix(15))
    guard !want.isEmpty else { return }
    want.forEach { prefetchedAt[$0] = now }
    func next(_ i: Int) {
      guard i < want.count else { return }
      let id = want[i]
      serverTask.request("/api/task?id=" + (id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id), body: nil) { [weak self] j in
        if (j?["off"] as? Bool) == true { return }   // (the app's task page switched off: nothing to fetch for)
        if let t = j?["task"] as? [String: Any] { self?.serverTask.cache[id] = t }
        next(i + 1)
      }
    }
    next(0)
  }
}

extension Main {
  // the app's own copy changed (the live stream): the open task pages and their comments drawn again from it
  func watchCopy() {
    if copyWatch != nil { return }
    copyWatch = AppData.shared.listen { [weak self] in
      guard let self = self else { return }
      for p in self.taskPages {
        self.refreshTaskPage(p)
        p.feed?.load(); p.threadFeed?.load()
      }
      // (Home, My Tasks and the Inbox too — step 2: from the copy, no request)
      self.serverHome.refresh(); self.serverMyTasksIfMade?.refresh(); self.serverInboxIfMade?.refresh()
    }
  }
}
