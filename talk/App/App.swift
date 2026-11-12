import UIKit
import UserNotifications

/* E11 Talk — the chat app (project doc claude/client-groups-app-idea.md). Never part of E11 Console's iPhone app; the
   same server, its own sign-in for now. Opening: the startup screen (from the phone's own copy, so usually at once),
   then Groups. Notifications come from E11 Talk itself (its own app on Apple's push service). */
@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(_ app: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    // (reply straight from the banner, or mark it read — stage 2)
    let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Message")
    let read = UNNotificationAction(identifier: "read", title: "Mark as read", options: [])
    UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "talk-msg", actions: [reply, read], intentIdentifiers: [], options: [])])
    return true
  }
  func application(_ app: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    UISceneConfiguration(name: "Default", sessionRole: s.role)
  }
  func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken t: Data) {
    let token = t.map { String(format: "%02x", $0) }.joined()
    #if DEBUG
    let env = "sandbox"
    #else
    let env = "production"
    #endif
    Net.shared.post("/api/talk/push", ["token": token, "env": env])
    UserDefaults.standard.set(token, forKey: "talk_push_token")
  }
  // a notification while E11 Talk is open: shown, unless its group is open on the screen
  func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
    Talk.shared.sync()
    let g = (n.request.content.userInfo["e11"] as? [String: Any])?["groupId"] as? String
    done(g != nil && g == ChatVC.open ? [] : [.banner, .sound, .list])
  }
  // tapped: its group; replied from the banner: sent from there, without opening the app; Mark as read
  func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
    let g = (r.notification.request.content.userInfo["e11"] as? [String: Any])?["groupId"] as? String
    if r.actionIdentifier == "reply", let g = g, let t = (r as? UNTextInputNotificationResponse)?.userText.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
      var bg = UIBackgroundTaskIdentifier.invalid
      bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg) }
      Net.shared.act(["act": "send", "group": g, "text": t, "cid": UUID().uuidString]) { _ in
        Talk.shared.loadLocal()
        Talk.shared.sync { Talk.shared.markRead(g); Talk.shared.flush(); done(); UIApplication.shared.endBackgroundTask(bg) }
      }
      return
    }
    if r.actionIdentifier == "read", let g = g {
      var bg = UIBackgroundTaskIdentifier.invalid
      bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg) }
      Talk.shared.loadLocal()
      Talk.shared.sync { Talk.shared.markRead(g); Talk.shared.flush(); done(); UIApplication.shared.endBackgroundTask(bg) }
      return
    }
    if let g = g { SceneDelegate.openGroup(g) }
    done()
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  static weak var current: SceneDelegate?
  private(set) var tabs: UITabBarController?
  private var wantGroup: String?

  func scene(_ s: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let ws = s as? UIWindowScene else { return }
    SceneDelegate.current = self
    let w = UIWindow(windowScene: ws)
    w.tintColor = Look.accent
    window = w
    w.rootViewController = UIViewController()
    w.makeKeyAndVisible()
    Net.shared.onSignedOut = { [weak self] in self?.signedOut() }
    NotificationCenter.default.addObserver(self, selector: #selector(refused), name: .talkRefused, object: nil)
    Net.shared.onNews = { Talk.shared.sync() }
    if let r = options.notificationResponse, let g = (r.notification.request.content.userInfo["e11"] as? [String: Any])?["groupId"] as? String { wantGroup = g }
    #if DEBUG
    // (the build's own check in the simulator, no account needed: the tabs, a chat opened on them — is the tab bar gone?)
    if ProcessInfo.processInfo.arguments.contains("-chatcheck") { chatCheck(); return }
    #endif
    start()
  }
  #if DEBUG
  private func chatCheck() {
    let t = mainTabs(); window?.rootViewController = t
    func say(_ what: String) {
      if #available(iOS 18, *) { NSLog("chatcheck \(what): isTabBarHidden=\(t.isTabBarHidden) tabBar.isHidden=\(t.tabBar.isHidden) tabBar.alpha=\(t.tabBar.alpha) tabBar.frame=\(NSCoder.string(for: t.tabBar.frame)) window=\(NSCoder.string(for: t.view.bounds))") }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      say("list")
      (t.viewControllers?.first as? UINavigationController)?.pushViewController(ChatVC(group: "check"), animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { say("chat") }
    }
  }
  #endif
  private func start() {
    guard let w = window else { return }
    guard Net.shared.signedIn else { showSignIn(); return }
    Talk.shared.loadLocal()
    Talk.shared.prune()
    let main = mainTabs()
    w.rootViewController = main
    // the startup screen over it until the chats are ready
    let sp = SplashView(name: Talk.shared.me?.name)
    sp.frame = w.bounds; sp.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    w.addSubview(sp)
    sp.onDone = { [weak self] in self?.askNotifications(); if let g = self?.wantGroup { self?.wantGroup = nil; SceneDelegate.openGroup(g) } }
    if !Talk.shared.groups.isEmpty || Talk.shared.me != nil { sp.progress(0.7) }
    // a new phone (nothing of this account here yet): before anything comes in, look for an iCloud backup to restore
    let fresh = Talk.shared.isFresh
    if fresh { Talk.shared.holdSync = true }
    Talk.shared.refresh { [weak self, weak sp] in
      sp?.setName(Talk.shared.me?.name); sp?.progress(0.85)
      guard fresh, let uid = Talk.shared.me?.id else { Talk.shared.holdSync = false; Talk.shared.sync { sp?.finish() }; return }
      Backup.shared.find(uid) { meta in
        guard let m = meta else { Talk.shared.holdSync = false; Talk.shared.sync { sp?.finish() }; return }
        sp?.finish()
        let r = RestoreVC(uid: uid, meta: m)
        r.onDone = { Talk.shared.holdSync = false; Talk.shared.sync() }
        r.modalPresentationStyle = .fullScreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.window?.rootViewController?.present(r, animated: true) }
      }
    }
    // (slow or offline: the phone's own copy is enough to go on)
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak sp] in sp?.finish() }
    Net.shared.listen()
  }
  private func mainTabs() -> UITabBarController {
    let t = UITabBarController()
    let groups = UINavigationController(rootViewController: GroupsVC())
    groups.navigationBar.prefersLargeTitles = true
    groups.tabBarItem = UITabBarItem(title: "Groups", image: UIImage(systemName: "bubble.left.and.bubble.right"), selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill"))
    // (staff: Groups · Clients · Settings — the Clients tab is groups with a client contact in them)
    let clients = UINavigationController(rootViewController: GroupsVC(clientsTab: true))
    clients.navigationBar.prefersLargeTitles = true
    clients.tabBarItem = UITabBarItem(title: "Clients", image: UIImage(systemName: "person.2"), selectedImage: UIImage(systemName: "person.2.fill"))
    let settings = UINavigationController(rootViewController: SettingsVC())
    settings.navigationBar.prefersLargeTitles = true
    settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))
    t.viewControllers = [groups, clients, settings]
    tabs = t
    NotificationCenter.default.addObserver(self, selector: #selector(badge), name: .talkChanged, object: nil)
    shape()
    return t
  }
  // a client contact sees one list of their chats (no tab bar); staff see the three tabs. Checked on every count change, so
  // it acts only when the kind of account changes — it used to put the tab bar back whenever a message or a read came in,
  // there behind an open chat's message box
  private var contactMode = false, shaped = false
  @objc private func shape() {
    guard let t = tabs else { return }
    let c = Talk.shared.isContact
    if c != contactMode || !shaped {
      shaped = true
      contactMode = c
      // (iOS 18 on: Apple's own call — the tab bar's isHidden set by hand left Apple's call to hide it beside a chat
      //  doing nothing, the bar staying behind the chat and Message info)
      if #available(iOS 18, *) { t.setTabBarHidden(c, animated: false) } else { t.tabBar.isHidden = c }
      if c { t.selectedIndex = 0; (t.viewControllers?.first as? UINavigationController)?.popToRootViewController(animated: false) }
      t.viewControllers?.compactMap { ($0 as? UINavigationController)?.viewControllers.first }.forEach { $0.additionalSafeAreaInsets.bottom = 0 }
    }
  }
  @objc private func badge() {
    shape()
    let T = Talk.shared
    tabs?.viewControllers?.first?.tabBarItem.badgeValue = T.totalUnread > 0 ? "\(T.totalUnread)" : nil
    if (tabs?.viewControllers?.count ?? 0) > 1 { let n = T.groups.values.filter { $0.withClient }.reduce(0) { $0 + T.unread($1.id) }; tabs?.viewControllers?[1].tabBarItem.badgeValue = n > 0 && !T.isContact ? "\(n)" : nil }
  }
  private func showSignIn() {
    let s = SignInVC()
    s.onDone = { [weak self] in self?.start() }
    window?.rootViewController = s
  }
  private var signingOut = false
  private func signedOut() {
    guard !signingOut, Net.shared.signedIn else { return }
    signingOut = true
    Net.shared.stopListening(); Net.shared.cookie = nil
    let a = UIAlertController(title: "Please sign in again", message: "Your E11 Talk sign-in has run out (about once a month). Your chats stay on this phone.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Sign in", style: .default) { [weak self] _ in self?.signingOut = false; self?.showSignIn() })
    window?.rootViewController?.present(a, animated: true)
  }
  // the email signed in isn't on the Team or in Client Contacts: Apple's alert says so, once while the app is open
  private var toldRefused = false
  @objc private func refused() {
    guard !toldRefused, let top = window?.rootViewController else { return }
    toldRefused = true
    let a = UIAlertController(title: "This email isn’t set up for E11 Talk", message: "Ask E11 to add you, or sign out and sign in with the email they added for you.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in self?.toldRefused = false; self?.signOutNow() })
    a.addAction(UIAlertAction(title: "OK", style: .cancel))
    (top.presentedViewController ?? top).present(a, animated: true)
  }
  func signOutNow() {
    if let t = UserDefaults.standard.string(forKey: "talk_push_token") { Net.shared.post("/api/talk/push", ["token": t, "off": true]) }
    Talk.shared.signOut()
    showSignIn()
  }
  private func askNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { ok, _ in
      if ok { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
    }
  }
  static func openGroup(_ g: String) {
    guard let sd = current, let tabs = sd.tabs, let nav = tabs.viewControllers?.first as? UINavigationController else { return }
    tabs.selectedIndex = 0
    nav.popToRootViewController(animated: false)
    if Talk.shared.groups[g] != nil { nav.pushViewController(ChatVC(group: g), animated: true) }
    else { Talk.shared.refresh { if Talk.shared.groups[g] != nil { nav.pushViewController(ChatVC(group: g), animated: true) } } }
  }
  func sceneDidBecomeActive(_ s: UIScene) {
    guard Net.shared.signedIn, tabs != nil else { return }
    Net.shared.listen()
    Talk.shared.refresh { Talk.shared.prune() }; Talk.shared.sync()
  }
  func sceneDidEnterBackground(_ s: UIScene) { Net.shared.stopListening(); Talk.shared.flush(); Talk.shared.badge(); Backup.shared.backUpIfDue() }
}

// ---------- Settings ----------
final class SettingsVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Settings"
    NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .talkBackup, object: nil)
  }
  override func numberOfSections(in tv: UITableView) -> Int { 3 }
  // (Super Admins and Office Admins also get "Client contacts")
  private var boss: Bool { Talk.shared.boss }
  private enum R1 { case notif, backup, linked, storage, contacts }
  private var rows1: [R1] { [.notif, .backup] + (Talk.shared.isContact ? [] : [.linked]) + [.storage] + (boss ? [.contacts] : []) }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { [1, rows1.count, 1][s] }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { ip.section == 0 ? 76 : 48 }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == 1 ? "Chats live on this phone. The server only passes each message on and lets it go once everyone has it." : s == 2 ? "E11 Talk \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")) · \(Server.host)" : nil
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    var cfg = c.defaultContentConfiguration()
    switch (ip.section, ip.row) {
    case (0, _):
      let me = Talk.shared.me
      cfg.text = me?.name ?? "—"; cfg.textProperties.font = .systemFont(ofSize: 19, weight: .semibold)
      cfg.secondaryText = Talk.shared.isContact ? "\(me?.role ?? "") · client" : me?.role; cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 56, height: 56)
      let a = Avatar(frame: CGRect(x: 16, y: 10, width: 56, height: 56)); a.set(person: me); c.contentView.addSubview(a)
      c.selectionStyle = .none
    case (1, let r) where rows1[r] == .linked:
      let n = Talk.shared.macs.count
      cfg.text = "Linked devices"; cfg.secondaryText = n == 0 ? "Link a Mac" : "\(n) Mac\(n == 1 ? "" : "s")"
      cfg.secondaryTextProperties.color = .secondaryLabel; cfg.image = UIImage(systemName: "laptopcomputer.and.iphone"); c.accessoryType = .disclosureIndicator
    case (1, let r) where rows1[r] == .notif: cfg.text = "Notifications"; cfg.image = UIImage(systemName: "bell.badge"); c.accessoryType = .disclosureIndicator
    case (1, let r) where rows1[r] == .backup:
      let B = Backup.shared, f = RelativeDateTimeFormatter(); f.unitsStyle = .short
      cfg.text = "Chat backup"; cfg.secondaryText = B.every == .off && B.lastAt == nil ? "Off" : B.lastAt.map { "Last: " + f.localizedString(for: $0, relativeTo: Date()) } ?? "Not backed up yet"
      cfg.secondaryTextProperties.color = .secondaryLabel; cfg.image = UIImage(systemName: "icloud"); c.accessoryType = .disclosureIndicator
    case (1, let r) where rows1[r] == .contacts:
      cfg.text = "Client contacts"; cfg.secondaryText = "\(Talk.shared.contacts.count) · who from each client can be in groups"; cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = UIImage(systemName: "person.crop.rectangle.stack"); c.accessoryType = .disclosureIndicator
    case (1, let r) where rows1[r] == .storage:
      let n = (try? FileManager.default.contentsOfDirectory(at: Net.filesDir, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } ?? 0
      cfg.text = "Storage"; cfg.secondaryText = ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) + " of photos and files on this phone"; cfg.image = UIImage(systemName: "internaldrive")
      c.selectionStyle = .none
    default: cfg.text = "Sign out"; cfg.textProperties.color = .systemRed; cfg.image = UIImage(systemName: "rectangle.portrait.and.arrow.right"); cfg.imageProperties.tintColor = .systemRed
    }
    c.contentConfiguration = cfg
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    if ip.section == 1 {
      switch rows1[ip.row] {
      case .backup: navigationController?.pushViewController(BackupVC(), animated: true); return
      case .linked: navigationController?.pushViewController(LinkedDevicesVC(), animated: true); return
      case .contacts: navigationController?.pushViewController(ContactsVC(), animated: true); return
      default: break
      }
    }
    if ip.section == 1, rows1[ip.row] == .notif, let u = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(u) }
    if ip.section == 2 {
      let a = UIAlertController(title: "Sign out of E11 Talk?", message: "The chats on this phone are removed.", preferredStyle: .actionSheet)
      a.addAction(UIAlertAction(title: "Sign out", style: .destructive) { _ in SceneDelegate.current?.signOutNow() })
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(a, animated: true)
    }
  }
}

// the tab bar beside a pushed chat (Console's way, its lesson 2026-11-08): hidden with Apple's call once the page has
// arrived, back as the slide back to the tab's first screen begins (and hidden again if that slide is called off)
// the tab bar beside a chat and the pages under it (Console's way, its lesson 2026-11-08): hidden with Apple's call once
// the page has arrived, back as the slide back to the tab's first screen begins (and hidden again if that's called off) —
// never "hide when pushed", which snapped the big title into the bar; Settings' pages keep it
enum TabBarHide {
  static func arrived(_ vc: UIViewController) {
    guard #available(iOS 18, *), !Talk.shared.isContact, let t = vc.tabBarController ?? SceneDelegate.current?.tabs else { return }
    t.setTabBarHidden(true, animated: true)
  }
  static func leaving(_ vc: UIViewController) {
    guard #available(iOS 18, *), !Talk.shared.isContact, let t = vc.tabBarController ?? SceneDelegate.current?.tabs, let n = vc.navigationController,
          vc.isMovingFromParent, n.viewControllers.count == 1 else { return }
    t.setTabBarHidden(false, animated: true)
    vc.transitionCoordinator?.notifyWhenInteractionChanges { c in if c.isCancelled { t.setTabBarHidden(true, animated: true) } }
  }
}
// the navigation's delegate for one slide only: Message info hooked by the finger (SlideIn, driven by it)
final class HookSlide: NSObject, UINavigationControllerDelegate {
  func navigationController(_ n: UINavigationController, animationControllerFor op: UINavigationController.Operation, from: UIViewController, to: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    op == .push && (from as? ChatVC)?.hook != nil ? SlideIn() : nil
  }
  func navigationController(_ n: UINavigationController, interactionControllerFor a: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
    a is SlideIn ? n.viewControllers.compactMap { $0 as? ChatVC }.last?.hook : nil
  }
}

// the push a finger drives (Message info hooked from a chat — WhatsApp's way, the design's board 27): Message info lies
// under the chat, and the chat itself is slid away to the left with the finger, its shadow on the page it uncovers
final class SlideIn: NSObject, UIViewControllerAnimatedTransitioning {
  private var animator: UIViewPropertyAnimator?
  func transitionDuration(using c: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }
  func animateTransition(using c: UIViewControllerContextTransitioning) { interruptibleAnimator(using: c).startAnimation() }
  // (one animator the finger drives frame by frame — Apple's way for an interactive slide; the shadow with its path set,
  //  so it isn't worked out again on every frame: the slide was slow and stepped)
  func interruptibleAnimator(using c: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
    if let a = animator { return a }
    let a = UIViewPropertyAnimator(duration: transitionDuration(using: c), curve: .linear)
    guard let from = c.view(forKey: .from), let to = c.view(forKey: .to), let toVC = c.viewController(forKey: .to) else {
      a.addCompletion { _ in c.completeTransition(false) }; animator = a; return a
    }
    let box = c.containerView, W = box.bounds.width
    to.frame = c.finalFrame(for: toVC)
    box.insertSubview(to, belowSubview: from)
    to.transform = CGAffineTransform(translationX: W * 0.3, y: 0)
    from.layer.shadowColor = UIColor.black.cgColor; from.layer.shadowOpacity = 0.18; from.layer.shadowRadius = 10; from.layer.shadowOffset = .zero
    from.layer.shadowPath = UIBezierPath(rect: from.bounds).cgPath
    a.addAnimations { from.transform = CGAffineTransform(translationX: -W, y: 0); to.transform = .identity }
    a.addCompletion { _ in
      from.transform = .identity; to.transform = .identity; from.layer.shadowOpacity = 0; from.layer.shadowPath = nil
      if c.transitionWasCancelled { to.removeFromSuperview() }
      c.completeTransition(!c.transitionWasCancelled)
    }
    animator = a
    return a
  }
  func animationEnded(_ done: Bool) { animator = nil }
}
