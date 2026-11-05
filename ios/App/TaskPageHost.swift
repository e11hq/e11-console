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
    ProfileAskCard.current?.go()   // (a task opened: the birthday / city card slips away)
    FeedLoader.shared.cookies = serverHome.cookies   // (before anything is drawn: its pictures are fetched with it)
    let p = TaskPage(id: id, frame: view.bounds)
    // (typing a comment, a tap anywhere else only puts the keyboard away — it never taps what's under it: Haris 2026-11-04,
    //  a standard; the description locks the page itself and ends with Done)
    KeyboardShield.attach(p)
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
    // (the screen under it laid out as it will be first — the buttons aimed at a place it then changed, and jumped)
    if last { tabBar.isHidden = tabsHidden; edgePanOn(); view.setNeedsLayout(); view.layoutIfNeeded() }   // (the swipe back for what's under it — a review request, a Me page, Client Assets: it was off until the app came back from the background, Haris 2026-11-04)
    back.forEach { $0.layoutIfNeeded() }
    updateCornerNow()
    let finish = {
      p.removeFromSuperview()
      back.forEach { $0.transform = .identity }
      // (the last page gone: whatever was moved aside when it came in is back in place — a screen hidden or shown
      //  meanwhile too; one left aside showed a blank page, Haris 2026-11-01)
      if last { self.view.subviews.forEach { v in if v !== self.tabBar && !(v is TaskPage) && v.transform.tx != 0 { v.transform = .identity } } }
      // (and the screen under it drawn again as it is now: the page says what's showing — Home, My Tasks, the Inbox)
      if last { self.pageJS("window.__e11HomeResend && __e11HomeResend(); window.__e11MyTasksResend && __e11MyTasksResend(); window.__e11InboxResend && __e11InboxResend(); window.__e11ClientsResend && __e11ClientsResend()"); self.updateCorner() }
      if last { self.pageJS("window.__e11Task && window.__e11Task({ev:'closed'})") }
      else if let top = self.taskPages.last, top.tab == "comments" { self.taskShowComments(top, focus: "") }
    }
    let barTo: CGFloat = tabsHidden || formTucked ? 0 : 1
    if !animated { finish(); if last { tabBar.alpha = barTo }; return }
    UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
      p.transform = CGAffineTransform(translationX: W, y: 0)
      back.forEach { $0.transform = .identity }
      if last { self.tabBar.alpha = barTo }
    } completion: { _ in finish() }
  }

  // leaving a task (‹ or the swipe back) with a comment or reply written and not sent: iPhone's own alert — Send / Keep
  // as Draft / Go Back (Haris, 2026-11-02, as the website's). Keep as Draft isn't asked again until it changes.
  // ‹ (the glass button) as the swipe back: a step at a time — a thread to the comments, the comments to Details, Details
  // to the page before (Haris 2026-11-04)
  func taskBackStep(_ p: TaskPage) {
    if p.threadFeed != nil || p.tab == "comments" { UIImpactFeedbackGenerator(style: .light).impactOccurred(); toDetailsFromComments(p); return }
    leaveTaskPage(p)
  }
  func leaveTaskPage(_ p: TaskPage) {
    if let u = composeIfMade?.unsent(task: p.taskId) { askUnsent(p, u) } else { closeTaskPage(p) }
  }
  func askUnsent(_ p: TaskPage, _ u: ComposeBox.Unsent) {
    guard let c = composeIfMade else { return }
    let what = u.reply ? "reply" : "comment"
    var lines: [String] = []
    if !u.words.isEmpty { lines.append(u.words.count > 140 ? String(u.words.prefix(140)) + "…" : u.words) }
    if let f = u.files.first { lines.append("📎 " + f + (u.files.count > 1 ? " +\(u.files.count - 1) more" : "")) }
    if u.uploading > 0 { lines.append("Uploading \(u.uploading) file\(u.uploading == 1 ? "" : "s")… it sends by itself once they're up.") }
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    let a = UIAlertController(title: "Your \(what) hasn’t been sent", message: lines.joined(separator: "\n\n"), preferredStyle: .alert)
    if u.current {
      let send = UIAlertAction(title: "Send \(what.capitalized)", style: .default) { [weak self, weak p] _ in
        guard let self = self, let p = p else { return }
        c.sendDraft(u); self.closeTaskPage(p)
      }
      a.addAction(send); a.preferredAction = send
    }
    a.addAction(UIAlertAction(title: "Keep as Draft", style: .default) { [weak self, weak p] _ in
      guard let self = self, let p = p else { return }
      c.keepDraft(u); self.closeTaskPage(p)
    })
    a.addAction(UIAlertAction(title: "Go Back", style: .cancel) { [weak p] _ in
      // (back to it: Comments, the box ready)
      guard let p = p else { return }
      if p.tab != "comments" { p.setTab("comments", tell: true, slide: true) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { c.text.becomeFirstResponder() }
    })
    var top: UIViewController = self; while let n = top.presentedViewController { top = n }
    top.present(a, animated: true)
  }

  // iPhone's swipe back from the left edge: the page follows the finger; let go, it goes the way it was going
  @objc func taskEdgePan(_ g: UIScreenEdgePanGestureRecognizer) {
    // (no task page: a client's page goes back to the list the same way — Haris 2026-11-02)
    guard let p = taskPages.last else { if assetsCtl.isOpen { if assetsCtl.top?.backable == true { assetsCtl.edgePan(g) } } else if meCtl.isOpen { if meCtl.depth > 1 { meCtl.edgePan(g) } } else { clientEdgePan(g) }; return }
    let W = view.bounds.width
    let x = max(0, g.translation(in: view).x)
    let under: UIView? = taskPages.count > 1 ? taskPages[taskPages.count - 2] : nil
    let back = underViews(below: p, under: under)
    // on Comments the swipe from the edge goes back a step — a thread to the comments, the comments to Details — not back
    // to the list — and the
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
      if taskPages.count == 1 && !tabsHidden { tabBar.isHidden = false; tabBar.alpha = x / W }
      corner.between(cornerTarget(), cornerTarget(skipTop: true), x / W)
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: view).x
      let go = g.state == .ended && (v > 300 || (x > W * 0.4 && v > -200))
      // (a comment written here and not sent: the page comes back and asks first)
      let ask = go ? composeIfMade?.unsent(task: p.taskId) : nil
      if go && ask == nil {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        closeTaskPage(p)
      } else {
        if let u = ask { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.askUnsent(p, u) } }
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

  // the edge swipe on a client's page: it follows the finger, the list coming back under it, the top buttons between
  // the two (‹ fading as it goes); let go far or fast enough and it's back on the list, else it slides back
  func edgePanOn() {
    if taskPan == nil {
      let g = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(taskEdgePan(_:)))
      g.edges = .left
      view.addGestureRecognizer(g)
      taskPan = g
    }
    taskPan?.isEnabled = !taskPages.isEmpty || clientPageIfMade?.isHidden == false || (assetsCtl.isOpen && assetsCtl.top?.backable == true) || (meCtl.isOpen && meCtl.depth > 1)
  }
  func clientEdgePan(_ g: UIScreenEdgePanGestureRecognizer) {
    guard let p = clientPageIfMade, !p.isHidden, let l = clientUnder(), clientsWanted else { return }
    let W = view.bounds.width
    let x = max(0, g.translation(in: view).x)
    switch g.state {
    case .began:
      p.endEditing(true)
      if clientFrom != nil { view.insertSubview(l, belowSubview: p) }   // (opened from another tab: that tab's screen under it)
      l.isHidden = false; l.transform = .identity   // (shown, in place, to see where its buttons are)
      clientPanFrom = (cornerTargetFor(p), cornerTargetFor(l))
      l.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    case .changed:
      p.transform = CGAffineTransform(translationX: x, y: 0)
      l.transform = CGAffineTransform(translationX: -W * 0.3 * (1 - x / W), y: 0)
      if let f = clientPanFrom { corner.between(f.0, f.1, x / W) }
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: view).x
      let go = g.state == .ended && (v > 300 || (x > W * 0.4 && v > -200))
      clientPanFrom = nil
      if go {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        clientsOn = "list"
        fromTabSelected()
        clientLeavingBySwipe(p, l)
        pageJS("window.__e11Clients && window.__e11Clients({ev:'back'})")
      } else {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          p.transform = .identity; l.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
        } completion: { _ in if !p.isHidden && p.transform == .identity { l.isHidden = true; l.transform = .identity } }
        updateCorner()
      }
    default: break
    }
  }

  private func wire(_ p: TaskPage) {
    p.onBack = { [weak self, weak p] in guard let self = self, let p = p else { return }; if p.editingDesc { p.finishDesc() }; self.taskBackStep(p) }
    p.onCornerChange = { [weak self] in self?.updateCornerNow() }
    // (in a reply thread, only the swipe from the edge goes back — not a swipe across the page: Haris 2026-11-04)
    p.onSwipeToDetails = { [weak self, weak p] in guard let self = self, let p = p, p.threadFeed == nil else { return }; self.toDetailsFromComments(p) }
    p.onOpenFiles = { [weak self] list, i in self?.openFiles(list, at: i) }
    p.onFilesShown = { [weak self] paths in self?.loadLinkStates(paths) }
    p.onFileAction = { [weak self, weak p] f, what in
      guard let self = self, let p = p else { return }
      let toast: (String) -> Void = { [weak p] t in p?.toast(t) }
      if what == "copy" { self.copyFile(f, toast) } else if what == "download" { self.downloadFile(f, from: self.topMost(), toast) } else if what == "linkOff" { self.fileLinkToggle(f, toast) }
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
    p.onDescAttach = { [weak self, weak p] src in
      guard let self = self, let p = p else { return }
      Picker.shared.pick(from: self.topMost(), single: false, source: src) { [weak self, weak p] r in
        guard let self = self, let p = p else { return }
        let picked = ((r["files"] as? [[String: Any]]) ?? []).compactMap { f -> (URL, String)? in
          guard let tok = f["token"] as? String, let u = Picker.shared.url(tok) else { return nil }
          return (u, f["name"] as? String ?? "File")
        }
        self.uploadToTask(p, picked, toDesc: true)
      }
    }
    p.onDescUpload = { [weak self, weak p] picked in guard let self = self, let p = p else { return }; self.uploadToTask(p, picked, toDesc: true) }
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
    p.waiting += 1   // (the page shows the change already; the copy isn't drawn over it until the answer is in)
    serverTask.act(b) { [weak self, weak p] ok, m, err, need, messages in
      guard let self = self, let p = p else { return }
      p.waiting = max(0, p.waiting - 1)
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
        // (sent: down to the latest, where it is — Haris, 2026-11-02)
        if ok { p.feed?.wantEnd = true; p.threadFeed?.wantEnd = true }
        p.feed?.load(); p.threadFeed?.load()
      }
    }
    // a voice message on its way: in the feed it's for (the thread page's, or the task's) at once
    c.onPending = { [weak self] id, thread, dur in
      guard let p = self?.taskPages.last else { return }
      if let t = p.threadFeed, thread != nil { t.addPending(id: id, parent: thread, dur: dur) } else { p.feed?.addPending(id: id, parent: thread, dur: dur) }
    }
    c.onPendingFiles = { [weak self] id, thread, words, cards in
      guard let self = self, let p = self.taskPages.last else { return }
      if let t = p.threadFeed, thread != nil { t.addPending(id: id, parent: thread, text: words, files: cards) } else { p.feed?.addPending(id: id, parent: thread, text: words, files: cards) }
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
    f.onLoaded = { [weak self, weak p] m in
      if let ml = m["mentionable"] as? [[String: Any]] { self?.composeIfMade?.mentionable = ml }
      self?.composeIfMade?.filesFor = { [weak p] in p?.taskFilesForPick ?? [] }
    }
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
      guard let d = d else { return toast("Couldn’t open — try again") }
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
    // (a small picture for the strip and while the big one loads: a photo's own, at 240 wide — the server's sized copy —
    //  else the file's picture — a video's frame, a PDF's first page)
    // (the same 480-wide copy the file cards ask for: the server makes it once — two sizes meant twice the work)
    let small = (p["url"] as? String).map { serverURL() + $0.replacingOccurrences(of: "?view=1", with: "?w=480") } ?? ""
    let thumb = (p["thumbUrl"] as? String).map { serverURL() + $0 } ?? (CommentCell.isPic(n) ? small : "")
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
  // Copy link (Haris 2026-11-03): the file's short link on the clipboard (files.e11hq.com/f/…) — pasted in a comment or
  // the description here it's still the file (FileClip, as before); anywhere else, the link: staff open it in the app,
  // anyone else gets the E11 page with the file and Download. The same link every time (asked of the server once).
  static var fileLinks: [String: String] = [:]
  static var isAdmin = false   // (from the page: only Admins turn file and folder links off and on — Haris 2026-11-03)
  // (the links turned off, as the server has them — asked for the files on screen, so a file's sheet says Turn on link)
  static var linksOff = Set<String>()
  func loadLinkStates(_ paths: [String]) {
    let ps = Array(Set(paths.filter { !$0.isEmpty })).prefix(400)
    guard !ps.isEmpty else { return }
    serverTask.request("/api/flink", body: ["paths": Array(ps)]) { j in
      guard (j?["ok"] as? Bool) == true, let off = j?["off"] as? [String] else { return }
      for p in ps { if off.contains(p) { Main.linksOff.insert(p) } else { Main.linksOff.remove(p) } }
    }
  }
  func copyFile(_ f: [String: Any], _ toast: @escaping (String) -> Void) {
    guard let path = f["file"] as? String else { return toast("This file isn’t available") }
    let name = f["name"] as? String ?? "File"
    let put = { (link: String?) in
      UIPasteboard.general.string = link ?? "📎 " + name
      FileClip.file = f; FileClip.name = name; FileClip.change = UIPasteboard.general.changeCount
    }
    if let u = Main.fileLinks[path] { put(u); return toast("Link copied") }
    serverTask.request("/api/flink", body: ["path": path]) { j in
      if (j?["ok"] as? Bool) == true, let u = j?["url"] as? String { Main.fileLinks[path] = u; put(u); toast("Link copied") }
      else { put(nil); toast((j?["error"] as? String).map { _ in "No link — copied as text" } ?? "Copied") }
    }
  }
  // a Client Assets folder's link (not "Files" itself): the folder as it is now, for anyone (Haris 2026-11-03)
  static var folderLinks: [String: String] = [:]
  func copyFolderLink(client: String, folder: String, _ toast: @escaping (String) -> Void) {
    let key = client + "/" + folder
    let said = "Folder link copied"
    if let u = Main.folderLinks[key] { UIPasteboard.general.string = u; return toast(said) }
    serverTask.request("/api/flink", body: ["client": client, "folder": folder]) { j in
      if (j?["ok"] as? Bool) == true, let u = j?["url"] as? String { Main.folderLinks[key] = u; UIPasteboard.general.string = u; toast(said) }
      else { toast(j?["error"] as? String ?? "No connection — try again") }
    }
  }
  func folderLinkToggle(client: String, folder: String, _ toast: @escaping (String) -> Void) {
    serverTask.request("/api/flink", body: ["client": client, "folder": folder, "state": true]) { [weak self] j in
      guard let self = self else { return }
      guard (j?["ok"] as? Bool) == true else { return toast(j?["error"] as? String ?? "No connection — try again") }
      let off = (j?["off"] as? Bool) != true
      let ac = UIAlertController(title: off ? "Turn off this folder’s link?" : "This folder’s link is off", message: off ? "Anyone who has the link won’t be able to open the folder or its files. The files’ own links stay as they are. You can turn it on again — the link stays the same." : "Turn it on again? The same link shows the folder again.", preferredStyle: .alert)
      ac.overrideUserInterfaceStyle = self.statusStyle == .darkContent ? .light : .dark
      ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      let ok = UIAlertAction(title: off ? "Turn off" : "Turn on", style: off ? .destructive : .default) { _ in
        self.serverTask.request("/api/flink", body: ["client": client, "folder": folder, "off": off]) { r in
          let k = "d:" + client + "/" + folder
          if (r?["ok"] as? Bool) == true { if off { Main.linksOff.insert(k) } else { Main.linksOff.remove(k) } }
          toast((r?["ok"] as? Bool) == true ? (off ? "Folder link turned off" : "The folder link works again") : r?["error"] as? String ?? "That didn’t work — try again")
        }
      }
      ac.addAction(ok); ac.preferredAction = ok
      self.topMost().present(ac, animated: true)
    }
  }
  // Turn off link / Turn on link: asked first, as iPhone's own question
  func fileLinkToggle(_ f: [String: Any], _ toast: @escaping (String) -> Void) {
    guard let path = f["file"] as? String, let q = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return toast("This file can’t have a link") }
    serverTask.request("/api/flink?path=\(q)", body: nil) { [weak self] j in
      guard let self = self else { return }
      guard (j?["ok"] as? Bool) == true else { return toast(j?["error"] as? String ?? "No connection — try again") }
      let off = (j?["off"] as? Bool) != true
      let ac = UIAlertController(title: off ? "Turn off this file’s link?" : "This link is off", message: off ? "Anyone who has the link won’t be able to open or download the file. You can turn it on again — the link stays the same." : "Turn it on again? The same link opens the file again.", preferredStyle: .alert)
      ac.overrideUserInterfaceStyle = self.statusStyle == .darkContent ? .light : .dark
      ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      let ok = UIAlertAction(title: off ? "Turn off" : "Turn on", style: off ? .destructive : .default) { _ in
        self.serverTask.request("/api/flink", body: ["path": path, "off": off]) { r in
          if (r?["ok"] as? Bool) == true { if off { Main.linksOff.insert(path) } else { Main.linksOff.remove(path) } }
          toast((r?["ok"] as? Bool) == true ? (off ? "Link turned off" : "The link works again") : r?["error"] as? String ?? "That didn’t work — try again")
        }
      }
      ac.addAction(ok); ac.preferredAction = ok
      self.topMost().present(ac, animated: true)
    }
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
  // files from the phone onto the task: each one's card in the Files row at once, pulsing with its upload ring; all are
  // added together once they're up, and the real cards take their places (Haris, 2026-11-02)
  // toDesc: from the description's Attach (or pasted there) — a chip where the cursor was, made real as each is up
  func uploadToTask(_ p: TaskPage, _ picked: [(URL, String)], toDesc: Bool = false) {
    guard !picked.isEmpty else { return }
    let ids = picked.map { _ in "up-" + UUID().uuidString }
    if toDesc { p.descUploadsStarted(zip(ids, picked.map { $0.1 }).map { ($0, $1) }) }
    p.addUploads(scroll: !toDesc, zip(ids, picked).map { id, f in
      var c: [String: Any] = ["id": id, "name": f.1, "pending": true]
      if let t = CommentCell.localThumb(f.0, f.1) { FeedLoader.shared.setLocal("local:" + id, t); c["thumbUrl"] = "local:" + id }
      return c
    })
    var done: [[String: Any]] = [], sent = Set<String>(), left = picked.count
    for (i, (url, name)) in picked.enumerated() {
      let id = ids[i]
      let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
      Uploader.send(url, name: name, task: p.taskId, cookies: serverHome.cookies, progress: { f in UploadRing.post(id, f) }) { [weak self, weak p] path in
        guard let self = self, let p = p else { return }
        if let path = path { done.append(["name": name, "size": size, "path": path]); sent.insert(id); UploadRing.post(id, 1) }
        else { p.dropUploads([id]) }
        if toDesc { p.descUploaded(id, path: path, size: Int(size)) }
        left -= 1
        if left == 0 {
          if done.isEmpty { p.toast("Upload failed — try again"); return }
          UINotificationFeedbackGenerator().notificationOccurred(.success)
          Main.playUploaded()
          p.uploadsSent(sent)
          self.taskAct(p, ["act": "attach", "id": p.taskId, "files": done])
          // (never came: they go after a while)
          DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak p] in p?.dropUploads(sent) }
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
  // — back a step at a time (Haris 2026-11-04, again): from a reply thread, first back to the comments; from the comments,
  // to Details; from Details, the page before
  func toDetailsFromComments(_ p: TaskPage) {
    composeIfMade?.text.resignFirstResponder()
    if p.threadFeed != nil { closeThread(p); return }
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
        if p.waiting == 0 { self.refreshTaskPage(p) }
        p.feed?.load(); p.threadFeed?.load()
      }
      // (the tab bar: its counts from the copy — Part B step 1)
      self.refreshOwnTabs()
      // (the app icon's count: unread updates, from the copy — Part B step 7; the page's no longer needed)
      self.ownBadge()
      // (Home, My Tasks and the Inbox too — step 2: from the copy, no request)
      self.serverHome.refresh(); self.serverMyTasksIfMade?.refresh(); self.serverInboxIfMade?.refresh(); if self.clientsWanted { self.serverClientsIfMade?.refresh() }
      // (live, everywhere — Haris 2026-11-03: a client's page whose client was deleted, or made inactive, elsewhere goes back to
      //  the list with a toast)
      if self.clientsWanted, self.clientsOn == "client", let p = self.clientPageIfMade, !p.isHidden, !self.clientLeaving, let s = self.serverClientsIfMade,
         AppData.shared.ready, ServerHome.param(s.query, "view") == "client" {
        let c = AppData.shared.screen("clients", ServerHome.clientsJSON(s.query))
        if c.ready && c.model == nil {
          self.clientFrom = nil; self.clientsOn = "list"
          self.clientPageOut()
          self.pageJS("window.__e11Clients && window.__e11Clients({ev:'list'})")
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.clientsListIfMade?.toast(["t": "That client has been removed"]) }
        }
      }
    }
  }
}

/* ---------- Part B step 6: New task, Home search and My Tasks' filters — the app's own (web/appme-tasks.js on the app's
   copy; a new task straight to the server, /api/app/act tkNew). The copy not ready / not this person's: the page's way,
   as before ---------- */
final class NewTaskState { var s: [String: Any]; init(_ s: [String: Any]) { self.s = s } }
extension Main {
  private static var photoData: [String: String] = [:]   // (a picture's path → it as a data address, for the sheets)
  // people's pictures for a native sheet: the copy gives their paths; the sheets want the pictures themselves
  func withPhotos(_ obj: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    var paths = Set<String>()
    func walk(_ v: Any) {
      if let d = v as? [String: Any] {
        if let p = d["person"] as? [String: Any], let ph = p["photo"] as? String, !ph.hasPrefix("data:"), Main.photoData[ph] == nil { paths.insert(ph) }
        d.values.forEach(walk)
      } else if let a = v as? [Any] { a.forEach(walk) }
    }
    walk(obj)
    func swap(_ v: Any) -> Any {
      if var d = v as? [String: Any] {
        for (k, x) in d { d[k] = swap(x) }
        if var p = d["person"] as? [String: Any], let ph = p["photo"] as? String, !ph.hasPrefix("data:") { if let u = Main.photoData[ph] { p["photo"] = u } else { p["photo"] = nil }; d["person"] = p }
        return d
      }
      if let a = v as? [Any] { return a.map(swap) }
      return v
    }
    if paths.isEmpty { done(swap(obj) as? [String: Any] ?? obj); return }
    var left = paths.count, sent = false
    let finish = { if !sent { sent = true; done(swap(obj) as? [String: Any] ?? obj) } }
    for p in paths {
      let enc = p.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
      guard let url = URL(string: serverURL() + (p.hasPrefix("/") ? p : "/__file/" + enc)) else { left -= 1; continue }
      fetchPhoto(url) { img in
        if let img = img, let d = img.jpegData(compressionQuality: 0.8) { Main.photoData[p] = "data:image/jpeg;base64," + d.base64EncodedString() }
        left -= 1; if left <= 0 { finish() }
      }
    }
    if left <= 0 { finish() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { finish() }   // (a slow picture: its initials meanwhile)
  }
  private var ownCopy: Bool { AppData.shared.tabsOn && AppData.shared.ready && AppData.shared.isStarted }
  // a sheet from the brain ({ sheet, acts }); a row picked → its act
  func brainSheet(_ m: [String: Any], multi: Bool = false, _ run: @escaping ([String: Any]) -> Void) {
    guard let sheet = m["sheet"] as? [String: Any], let acts = m["acts"] as? [[String: Any]] else { return }
    withPhotos(sheet) { [weak self] a0 in
      guard let self = self else { return }
      var a = a0; if multi { a["multi"] = true }
      let one: (Int) -> Void = { i in guard i >= 0, i < acts.count else { return }; run(acts[i]) }
      // (in a sheet with ticks, a tick is told at once; a plain row in it — "Nobody yet" — when it's tapped)
      let ticks = Set(((a["sections"] as? [[String: Any]]) ?? []).flatMap { ($0["rows"] as? [[String: Any]]) ?? [] }.filter { ($0["multi"] as? Bool) == true }.compactMap { ($0["i"] as? NSNumber)?.intValue })
      let vc = NativeSheetVC(a, dark: self.statusStyle != .darkContent, pick: multi ? one : nil) { i, _ in if !multi || !ticks.contains(i) { one(i) } }
      self.topMost().present(vc, animated: true)
    }
  }

  // ---- New task ----
  func newTaskNative(view: String, project: String?) -> Bool {
    guard ownCopy else { return false }
    let ctx: [String: Any] = ["view": view, "projectId": project ?? NSNull()]
    guard let r = AppData.shared.meModel("tasks", "newTaskForm", [ctx]), let args = r["args"] as? [String: Any], let st = r["state"] as? [String: Any] else { return false }
    let key = args["key"] as? String ?? "new-task"
    if let open = FormSheetVC.current, open.isOpen {
      if open.key == key { open.expand(); return true }
      open.finish("replaced") { [weak self] in _ = self?.newTaskNative(view: view, project: project) }
      return true
    }
    let state = NewTaskState(st)
    withPhotos(args) { [weak self] a in
      guard let self = self, let host = self.sheetHost() else { return }
      let vc = FormSheetVC(a, dark: self.statusStyle != .darkContent, event: { [weak self] ev in self?.newTaskEvent(ev, key, state) }) { [weak self] r in
        if (r["closed"] as? String) == "discard" { self?.shownScreen?.toast(["t": "New task discarded"]) }
      }
      vc.onTuck = { [weak self] t in
        guard let self, self.formTucked != t else { return }
        self.formTucked = t
        self.tabBar.isUserInteractionEnabled = !t
        UIView.animate(withDuration: 0.2) { self.tabBar.alpha = t || self.tabsHidden ? 0 : 1 }
      }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      host.present(vc, animated: true)
    }
    return true
  }
  private func newTaskEvent(_ ev: [String: Any], _ key: String, _ state: NewTaskState) {
    let set = { (v: [String: Any]) in var x = v; x["key"] = key; if let f = FormSheetVC.current, f.isOpen, f.key == key { f.set(x) } }
    switch ev["ev"] as? String ?? "" {
    case "pick" where (ev["field"] as? String) == "client":
      guard let m = AppData.shared.meModel("tasks", "newTaskClients", [state.s]) else { return }
      brainSheet(m) { act in
        state.s["client"] = act["client"] ?? ""
        if let f = act["form"] as? [String: Any] { set(f) }
      }
    case "pick":
      guard let m = AppData.shared.meModel("tasks", "newTaskPeople", [state.s]) else { return }
      brainSheet(m, multi: true) { [weak self] act in
        var who = (state.s["who"] as? [String]) ?? []
        if (act["none"] as? Bool) == true { who = [] }
        else if let u = act["toggle"] as? String { who = who.contains(u) ? who.filter { $0 != u } : who + [u] }
        state.s["who"] = who
        guard let w = AppData.shared.meModel("tasks", "newTaskWho", [state.s]) else { return }
        self?.withPhotos(["assign": ["label": w["label"] ?? "", "person": w["person"] ?? NSNull()]]) { a in set(a) }
      }
    case "submit":
      let title = (ev["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      var b: [String: Any] = ["ev": "tkNew", "title": title, "projectId": state.s["client"] ?? "", "due": ev["due"] ?? "", "desc": ev["desc"] ?? "",
                              "who": state.s["who"] ?? [], "cd": (ev["cd"] as? Bool) == true, "ctxProjectId": state.s["project"] ?? NSNull(), "op": UUID().uuidString]
      if let v = state.s["view"] { b["view"] = v }
      serverTask.request("/api/app/act", body: b) { [weak self] j in
        guard let self = self else { return }
        guard let j = j, (j["off"] as? Bool) != true else { set(["alert": j == nil ? "No connection — try again" : "That didn’t work — try again"]); return }
        guard (j["ok"] as? Bool) == true, let id = (j["id"] as? String) ?? ((j["answer"] as? [String: Any])?["id"] as? String) else { set(["alert": j["error"] as? String ?? "That didn’t work — try again"]); return }
        if let ch = j["changes"] as? [[String: Any]], !ch.isEmpty { AppData.shared.applyLocal(ch) }
        if let f = FormSheetVC.current, f.isOpen, f.key == key { f.finish("submit") }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.homeToastRun = { [weak self] in self?.openTaskPage(id, tab: "details", focus: "") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.shownScreen?.toast(["t": "Created “\(title)”", "a": "Open", "ms": 6000]) }
      }
    default: break
    }
  }

  // ---- Home search (and My Tasks', the Inbox's): found on the phone ----
  func searchNative(_ q: String) -> Bool {
    guard ownCopy, let m = AppData.shared.meModel("tasks", "search", [q]) else { return false }
    (shownScreen ?? homeIfMade)?.searchResults(m)
    return true
  }
}
extension Main {
  // (the client whose page shows on the Clients tab — New task there starts in it)
  var clientsShownId: String? { clientsOn == "client" ? ServerHome.param(serverClients.query, "id") : nil }
}
// My Tasks' filters, the app's own (Part B step 6): the page's Work.f() kept here for each person; their buttons, chips and
// the server's query from the copy (myTasksSignal); the filter sheets too (myTasksFilterMenu)
extension Main {
  private var mtKey: String { "e11_mytasks_" + (myTasksPageMe ?? AppData.shared.me ?? "") }
  var myTasksF: [String: Any] {
    get {
      if let d = defaults.data(forKey: mtKey), let f = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let x = f["f"] as? [String: Any] { return x }
      return (AppData.shared.meModel("tasks", "myTasksDefault")?["filters"] as? [String: Any]) ?? [:]
    }
    set { if let d = try? JSONSerialization.data(withJSONObject: ["f": newValue, "tab": myTasksTab]) { defaults.set(d, forKey: mtKey) } }
  }
  var myTasksTab: String {
    get { ((defaults.data(forKey: mtKey).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["tab"] as? String) ?? "all" }
    set { if let d = try? JSONSerialization.data(withJSONObject: ["f": myTasksF, "tab": newValue]) { defaults.set(d, forKey: mtKey) } }
  }
  func myTasksOwnSignal(me: String?) -> [String: Any]? {
    guard AppData.shared.tabsOn, AppData.shared.ready, AppData.shared.isStarted, let me = me, AppData.shared.me == me else { return nil }
    return AppData.shared.meModel("tasks", "myTasksSignal", [myTasksF, myTasksTab])
  }
  // a change made here: My Tasks drawn again with it (as if the page had said so)
  private func myTasksAgain() { if var a = myTasksPageSignal { a["show"] = true; myTasksCommand(a) } }
  func myTasksFilterEvent(_ ev: [String: Any]) -> Bool {
    guard let a = myTasksPageSignal, myTasksOwnSignal(me: a["me"] as? String) != nil else { return false }
    switch ev["ev"] as? String ?? "" {
    case "tab": myTasksTab = (ev["tab"] as? String) == "done" ? "done" : "all"; myTasksAgain(); return true
    case "reset", "chip":
      let op: [String: Any] = (ev["ev"] as? String) == "reset" ? ["reset": true] : ["chip": ["act": ev["act"] ?? "", "id": ev["id"] ?? NSNull()]]
      if let f = AppData.shared.meModel("tasks", "myTasksFilters", [myTasksF, op])?["filters"] as? [String: Any] { myTasksF = f; myTasksAgain() }
      return true
    case "filter":
      let k = ev["k"] as? String ?? ""
      if k == "assigned" {
        if let f = AppData.shared.meModel("tasks", "myTasksFilters", [myTasksF, ["assigned": true]])?["filters"] as? [String: Any] { myTasksF = f; myTasksAgain() }
        return true
      }
      guard ["due", "people", "ams"].contains(k), let m = AppData.shared.meModel("tasks", "myTasksFilterMenu", [k, myTasksF]) else { return false }
      let base = myTasksF
      let multi = (((m["sheet"] as? [String: Any])?["sections"] as? [[String: Any]]) ?? []).contains { (($0["rows"] as? [[String: Any]]) ?? []).contains { ($0["multi"] as? Bool) == true } }
      brainSheet(m, multi: multi) { [weak self] act in
        guard let self = self, let to = act["set"] as? [String: Any] else { return }
        // (several ticks in one sheet: each tick's own change, on the filters as they are now)
        var now = self.myTasksF
        for (key, v) in to {
          let was = base[key]
          if let arr = v as? [String], let old = was as? [String] {
            let flip = Set(arr).symmetricDifference(Set(old))
            var cur = (now[key] as? [String]) ?? []
            for x in flip { cur = cur.contains(x) ? cur.filter { $0 != x } : cur + [x] }
            now[key] = cur
          } else if jsonString(["v": v]) != jsonString(["v": was ?? NSNull()]) { now[key] = v }
        }
        self.myTasksF = now; self.myTasksAgain()
      }
      return true
    default: return false
    }
  }
}

// Part B step 7: the app icon's count and this phone's notification address — the app's own (the page's way while the
// copy isn't ready)
extension Main {
  func ownBadge() {
    guard AppData.shared.tabsOn, AppData.shared.ready, AppData.shared.isStarted, let n = AppData.shared.screen("inbox", "all").model?["unread"] as? Int else { return }
    if n == lastOwnBadge { return }
    lastOwnBadge = n
    UNUserNotificationCenter.current().setBadgeCount(max(0, n)) { _ in }
  }
  var ownsBadge: Bool { AppData.shared.tabsOn && AppData.shared.ready && AppData.shared.isStarted }
}
// Part B step 7: a file link (files.e11hq.com/f/…, "Open in E11 Console") opened by the app itself — where the file is
// (a client's folder, a task, a comment), then its preview — as the page's FileLinks.open does
extension Main {
  func fileLinkNative(_ tok: String) -> Bool {
    guard AppData.shared.tabsOn, AppData.shared.ready, AppData.shared.isStarted else { return false }
    serverTask.request("/api/flink?token=" + (tok.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? tok), body: nil) { [weak self] j in
      guard let self = self else { return }
      let say = { (t: String) in self.shownScreen?.toast(["t": t]) }
      guard let j = j, (j["ok"] as? Bool) == true, let w = j["where"] as? [String: Any] else { say(j?["error"] as? String ?? "That file isn’t available"); return }
      let kind = w["kind"] as? String ?? "", file = w["file"] as? String
      switch kind {
      case "folder", "asset":
        guard let c = w["client"] as? String, AppData.shared.meModel("assets", "assets", [c]) != nil else { say("File not shared with you"); return }
        self.assetsCtl.openFromClients(client: c, folder: w["folder"] as? String)
        guard kind == "asset", let fid = file else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          guard let m = AppData.shared.meModel("assets", "assets", [c]), let all = m["files"] as? [[String: Any]] else { return }
          let list = all.filter { ($0["folder"] as? String) == (w["folder"] as? String) }
          if let i = list.firstIndex(where: { ($0["id"] as? String) == fid }) { self?.openFiles(list, at: i) }
        }
      case "task", "comment":
        guard let t = w["task"] as? String, AppData.shared.screen("task", t).model != nil else { say("File not shared with you"); return }
        self.openTaskPage(t, tab: kind == "comment" ? "comments" : "details", focus: "")
        guard let fid = file else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
          guard let files = AppData.shared.screen("task", t).model?["files"] as? [[String: Any]], let i = files.firstIndex(where: { ($0["id"] as? String) == fid }) else { return }
          self?.openFiles(files, at: i)
        }
      default: say("File not shared with you")
      }
    }
    return true
  }
}
// Part B step 7: a notification tapped (a banner, an Inbox row, a task link) — where it goes and what's marked read, from
// the shared brain (web/appme-tasks.js notifOpen / taskLinkOpen), opened with the app's own screens. The few the page still
// does itself (a content plan, a claim, the morning round-up, a scheduled comment that wasn't sent, the Trash): the page's
// way, as before
extension Main {
  func openNotifNative(_ nid: String?, hint: [String: Any], tries: Int = 0, peeked: Bool = false) -> Bool {
    guard AppData.shared.tabsOn, AppData.shared.ready, AppData.shared.isStarted else { return false }
    let r: [String: Any]?
    if nid == nil || nid?.isEmpty == true, let t = hint["taskId"] as? String, !t.isEmpty { r = AppData.shared.meModel("tasks", "taskLinkOpen", [t, peeked]) }
    else { r = AppData.shared.meModel("tasks", "notifOpen", [nid ?? NSNull(), hint]) }
    guard let res = r, let go = res["go"] as? [String: Any] else { return r != nil }
    let to = go["to"] as? String ?? ""
    if ["plan", "claim", "schedCancel", "trash"].contains(to) { return false }
    let read = (res["read"] as? [String]) ?? []
    if !read.isEmpty { serverTask.request("/api/home/act", body: ["act": "readList", "ids": read, "op": UUID().uuidString]) { _ in } }
    if let t = go["toast"] as? String, to.isEmpty {
      if (go["home"] as? Bool) == true, let first = tabKeys.first { selectTab(first) }
      if (go["peek"] as? Bool) == true, let id = go["id"] as? String, !peeked {
        // (Production / a freelancer: the server may show them this task — asked, then tried again)
        serverTask.request("/api/peek", body: ["taskId": id]) { [weak self] _ in
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            if !self.openNotifNative(nid, hint: hint, peeked: true) { self.shownScreen?.toast(["t": t]) }
          }
        }
        return true
      }
      shownScreen?.toast(["t": t]); return true
    }
    switch to {
    case "task":
      guard let id = go["id"] as? String else { return false }
      // (the brain names the comment alone; the comments screen takes "task~comment", as the website's Inbox gave it —
      //  with the comment's id alone nothing pulsed: Haris 2026-11-05)
      let fc = go["focus"] as? String ?? ""
      openTaskPage(id, tab: go["tab"] as? String ?? "details", focus: fc.isEmpty || fc.contains("~") ? fc : "\(id)~\(fc)")
    case "review":
      if let rid = go["id"] as? String { meCtl.command(["open": ["kind": "review", "id": rid]]) }
      selectTab("reviews")
    case "assets":
      guard let c = go["client"] as? String else { return false }
      assetsCtl.openFromClients(client: c, folder: go["folder"] as? String)
    case "birthday": break
    case "daily": if !dailyNative() { return false }
    default: return false
    }
    // (tapped before the update itself reached the app: marked read once it's there)
    if (res["wait"] as? Bool) == true, let n = nid { waitReadNotif(n, hint, 0) }
    return true
  }
  private func waitReadNotif(_ n: String, _ hint: [String: Any], _ tries: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self = self, let again = AppData.shared.meModel("tasks", "notifOpen", [n, hint]) else { return }
      if (again["wait"] as? Bool) == true { if tries < 8 { self.waitReadNotif(n, hint, tries + 1) }; return }
      let ids = (again["read"] as? [String]) ?? []
      if !ids.isEmpty { self.serverTask.request("/api/home/act", body: ["act": "readList", "ids": ids, "op": UUID().uuidString]) { _ in } }
    }
  }
}

// Part B step 8: the morning round-up — worked out by the shared brain (web/appme-tasks.js daily, as daily.js) and shown
// as the app's own sheet; a task opens the app's own task page, "See … in My Tasks" opens My Tasks with that filter
extension Main {
  @discardableResult func dailyNative() -> Bool {
    guard AppData.shared.tabsOn, AppData.shared.ready, AppData.shared.isStarted, var m = AppData.shared.meModel("tasks", "daily"), let host = sheetHost() else { return false }
    m["light"] = statusStyle == .darkContent
    host.present(DailySheetVC(m) { [weak self] ev in self?.dailyTap(ev) }, animated: true)
    return true
  }
  private func dailyTap(_ ev: [String: Any]) {
    switch ev["ev"] as? String ?? "" {
    case "open":
      guard let id = ev["id"] as? String, !id.isEmpty else { return }
      if AppData.shared.screen("task", id).model != nil { openTaskPage(id, tab: "details", focus: "") }
      else { shownScreen?.toast(["t": "That task isn’t there anymore"]) }
    case "all":
      // (the page's way: My Tasks' filters cleared, then the section's, the whole team's for a Super Admin; All)
      guard let m = AppData.shared.meModel("tasks", "daily"), let s = (m["sections"] as? [[String: Any]])?.first(where: { ($0["k"] as? String) == (ev["k"] as? String) }),
            let f = s["filter"] as? [String: Any] else { return }
      var to = (AppData.shared.meModel("tasks", "myTasksDefault")?["filters"] as? [String: Any]) ?? [:]
      if (m["team"] as? Bool) == true { to["team"] = true }
      f.forEach { to[$0.key] = $0.value }
      myTasksF = to; myTasksTab = "all"
      // (from a task page: back to the tabs first)
      for p in taskPages { closeTaskPage(p, animated: false) }
      if selectedTabKey == "mytasks" { myTasksAgain() } else { selectTab("mytasks") }
    default: break
    }
  }
}
