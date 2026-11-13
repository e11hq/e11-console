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
    // (Settings › Notifications: In-App Banners and In-App Sounds)
    var opts: UNNotificationPresentationOptions = [.list]
    if TalkPrefs.inAppBanners { opts.insert(.banner) }
    if TalkPrefs.inAppSounds { opts.insert(.sound) }
    done(g != nil && g == ChatVC.open ? [] : opts)
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

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {
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
    Server.follow()
    if !Net.shared.signedIn, let c = SignInKeys.consoleReviewCookie { Net.shared.cookie = c }   // (App Review: Console's sign-in carried over)
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
    if fresh { Talk.shared.holdSync = true; sp.setup() }
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
  // a tab tapped again: on its first page, the list back to its start (deeper, Apple's own goes back to the first page)
  func tabBarController(_ c: UITabBarController, shouldSelect vc: UIViewController) -> Bool {
    if vc === c.selectedViewController, let n = vc as? UINavigationController, n.viewControllers.count == 1, let l = n.topViewController as? ListVC { l.toStart() }
    return true
  }
  private func mainTabs() -> UITabBarController {
    let t = UITabBarController()
    let groups = UINavigationController(rootViewController: GroupsVC())
    groups.navigationBar.prefersLargeTitles = true
    groups.tabBarItem = UITabBarItem(title: "E11 Agency", image: UIImage(systemName: "bubble.left.and.bubble.right"), selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill"))
    // (staff: E11 Agency · Clients · Settings (board 1) — the Clients tab is groups with a client contact in them)
    let clients = UINavigationController(rootViewController: GroupsVC(clientsTab: true))
    clients.navigationBar.prefersLargeTitles = true
    clients.tabBarItem = UITabBarItem(title: "Clients", image: UIImage(systemName: "briefcase"), selectedImage: UIImage(systemName: "briefcase.fill"))   // (board 1: the briefcase)
    let settings = UINavigationController(rootViewController: SettingsVC())
    settings.navigationBar.prefersLargeTitles = true
    settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))
    t.viewControllers = [groups, clients, settings]
    t.delegate = self
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
    Server.follow()
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
    SignInKeys.dropOwn()   // (a client contact's own key for Face ID let go)
    UserDefaults.standard.removeObject(forKey: "talk_via_console")
    Talk.shared.signOut()
    UserDefaults.standard.removeObject(forKey: "talk_review")   // (off the App Review copy — after its own copy is gone)
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
    // (signed in through E11 Console, and Console signed out since — its key gone: Talk signs out too, the plan)
    if UserDefaults.standard.bool(forKey: "talk_via_console"), SignInKeys.consoleKey == nil, !Talk.shared.isContact { signOutNow(); return }
    Talk.shared.refresh { Talk.shared.prune(); SignInKeys.refreshOwn() }; Talk.shared.sync()
    // (Auto-download: the network watched; what waited for Wi-Fi comes if it's here now)
    Auto.startOnce(); Talk.shared.catchUp()
  }
  func sceneDidEnterBackground(_ s: UIScene) { Net.shared.stopListening(); Talk.shared.flush(); Talk.shared.badge(); Backup.shared.backUpIfDue() }
}

// ---------- Settings ----------
// the tab bar beside a pushed chat (Console's way, its lesson 2026-11-08): hidden with Apple's call once the page has
// arrived, back as the slide back to the tab's first screen begins (and hidden again if that slide is called off)
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
