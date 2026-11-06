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
  private var tabs: UITabBarController?
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
    Net.shared.onNews = { Talk.shared.sync() }
    if let r = options.notificationResponse, let g = (r.notification.request.content.userInfo["e11"] as? [String: Any])?["groupId"] as? String { wantGroup = g }
    start()
  }
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
    Talk.shared.refresh { [weak sp] in
      sp?.setName(Talk.shared.me?.name); sp?.progress(0.85)
      Talk.shared.sync { sp?.finish() }
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
    let settings = UINavigationController(rootViewController: SettingsVC())
    settings.navigationBar.prefersLargeTitles = true
    settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))
    t.viewControllers = [groups, settings]
    tabs = t
    NotificationCenter.default.addObserver(self, selector: #selector(badge), name: .talkChanged, object: nil)
    return t
  }
  @objc private func badge() {
    let n = Talk.shared.totalUnread
    tabs?.viewControllers?.first?.tabBarItem.badgeValue = n > 0 ? "\(n)" : nil
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
  func sceneDidEnterBackground(_ s: UIScene) { Net.shared.stopListening(); Talk.shared.flush(); Talk.shared.badge() }
}

// ---------- Settings ----------
final class SettingsVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Settings"
    NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .talkChanged, object: nil)
  }
  override func numberOfSections(in tv: UITableView) -> Int { 3 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { [1, 2, 1][s] }
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
      cfg.secondaryText = me?.role; cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 56, height: 56)
      let a = Avatar(frame: CGRect(x: 16, y: 10, width: 56, height: 56)); a.set(person: me); c.contentView.addSubview(a)
      c.selectionStyle = .none
    case (1, 0): cfg.text = "Notifications"; cfg.image = UIImage(systemName: "bell.badge"); c.accessoryType = .disclosureIndicator
    case (1, 1):
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
    if ip == IndexPath(row: 0, section: 1), let u = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(u) }
    if ip.section == 2 {
      let a = UIAlertController(title: "Sign out of E11 Talk?", message: "The chats on this phone are removed.", preferredStyle: .actionSheet)
      a.addAction(UIAlertAction(title: "Sign out", style: .destructive) { _ in SceneDelegate.current?.signOutNow() })
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(a, animated: true)
    }
  }
}
