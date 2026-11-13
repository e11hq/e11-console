import UIKit
import UserNotifications

/* Settings (the design's boards "Settings", "Settings — light" and, for a client contact, "Settings — a client" — Haris
   2026-11-13: checked against the boards, with every change from the done pages): Apple's grouped list —
   your card (picture, name, your role in your colour, "From E11 Console"; a client: "Client · their client" and the email);
   Starred Messages · Client Contacts (Super / Office Admins, how many); Notifications · Chat Backup (when it last backed up)
   · Storage and Data (how much) · Linked Devices (staff); Help · About E11 Talk (the version); Sign Out and what it does.
   Each row's icon in its own coloured tile, as iPhone's Settings. A value that changes is set again in its own row only,
   crossfading (a fingerprint per row) — nothing else drawn again, nothing moving. */
final class SettingsVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  enum Row: Hashable { case me, starred, contacts, notif, backup, storage, linked, help, about, signOut }
  private var data: UITableViewDiffableDataSource<Int, Row>!
  private var sigs: [Row: String] = [:]
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Settings"
    tableView.register(MeCardCell.self, forCellReuseIdentifier: "me")
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    data = Source(tableView: tableView) { [weak self] tv, ip, row in
      let c = tv.dequeueReusableCell(withIdentifier: row == .me ? "me" : "c", for: ip); self?.fill(c, row); return c
    }
    data.defaultRowAnimation = .fade
    for n in [Notification.Name.talkChanged, .talkBackup] { NotificationCenter.default.addObserver(self, selector: #selector(changed), name: n, object: nil) }
    reload(animated: false)
  }
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); reload(animated: view.window != nil) }
  @objc private func changed() { reload(animated: view.window != nil) }
  private var isContact: Bool { Talk.shared.isContact }
  private func reload(animated: Bool) {
    var snap = NSDiffableDataSourceSnapshot<Int, Row>()
    snap.appendSections([0, 1, 2, 3, 4])
    snap.appendItems([.me], toSection: 0)
    snap.appendItems([.starred] + (Talk.shared.boss && !isContact ? [.contacts] : []), toSection: 1)
    snap.appendItems([.notif, .backup, .storage] + (isContact ? [] : [.linked]), toSection: 2)
    snap.appendItems([.help, .about], toSection: 3)
    snap.appendItems([.signOut], toSection: 4)
    var new: [Row: String] = [:]
    for r in snap.itemIdentifiers { new[r] = value(r) }
    let old = data.snapshot()
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != new[$0] })
    sigs = new
    (data as? Source)?.footer = isContact ? "Signs you out of E11 Talk on this iPhone." : "Signs you out of E11 Talk on this iPhone. E11 Console stays signed in."
    data.applySteady(snap, in: tableView, animated: animated)
  }
  // what a row shows on its right (the card: who you are) — its fingerprint too
  private func value(_ r: Row) -> String {
    let T = Talk.shared
    switch r {
    case .me: return [T.me?.id, T.me?.name, T.me?.role, T.me?.picture, T.me?.client, T.myEmail].map { $0 ?? "" }.joined(separator: "|") + (isContact ? "c" : "")
    case .starred: let n = T.starred.count; return n == 0 ? "" : "\(n)"
    case .contacts: return "\(T.contacts.count)"
    case .backup:
      let B = Backup.shared
      guard let at = B.lastAt else { return B.every == .off ? "Off" : "" }
      let f = DateFormatter(); f.doesRelativeDateFormatting = true; f.dateStyle = .medium; f.timeStyle = .short
      return f.string(from: at)
    case .storage: return ByteCountFormatter.string(fromByteCount: Int64(Storage.total()), countStyle: .file)
    case .linked: let n = T.macs.count; return n == 0 ? "" : "\(n)"
    case .about: return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    default: return ""
    }
  }
  private func fill(_ c: UITableViewCell, _ r: Row) {
    if let m = c as? MeCardCell { m.set(); return }
    c.accessoryType = .disclosureIndicator; c.selectionStyle = .default
    var cfg = UIListContentConfiguration.valueCell()
    let row = { (t: String, tile: UIImage) in cfg.text = t; cfg.image = tile; cfg.secondaryText = self.value(r) }
    switch r {
    case .starred: row("Starred Messages", Tile.make(0xFFCC00, "star.fill"))
    case .contacts: row("Client Contacts", Tile.make(0xFF9F0A, "person.crop.circle.badge.plus"))
    case .notif: row("Notifications", Tile.make(0xFF3B30, "bell.fill"))
    case .backup: row("Chat Backup", Tile.make(0x34C759, "icloud.and.arrow.up.fill"))
    case .storage: row("Storage and Data", Tile.make(0x5E5CE6, "archivebox.fill"))
    case .linked: row("Linked Devices", Tile.make(0x0A84FF, "laptopcomputer.and.iphone"))
    case .help: row("Help", Tile.make(0x8E8E93, "questionmark"))
    case .about: row("About E11 Talk", Tile.e11())
    case .signOut:
      cfg = UIListContentConfiguration.cell(); cfg.text = "Sign Out"; cfg.textProperties.color = .systemRed
      c.accessoryType = .none
    case .me: break
    }
    cfg.imageToTextPadding = 14
    c.contentConfiguration = cfg
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard let r = data.itemIdentifier(for: ip) else { return }
    let push = { (v: UIViewController) in self.navigationController?.pushViewController(v, animated: true) }
    switch r {
    case .starred: push(StarredVC())
    case .contacts: push(ContactsVC())
    case .notif: push(NotificationsVC())
    case .backup: push(BackupVC())
    case .storage: push(StorageVC())
    case .linked: push(LinkedDevicesVC())
    case .help: push(HelpVC())
    case .about: push(AboutVC())
    case .signOut:
      let a = UIAlertController(title: "Sign out of E11 Talk?", message: "The chats on this phone are removed.", preferredStyle: .actionSheet)
      a.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { _ in SceneDelegate.current?.signOutNow() })
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(a, animated: true)
    case .me: break
    }
  }
  // (Sign Out's line under it — the board's words)
  private final class Source: UITableViewDiffableDataSource<Int, Row> {
    var footer = ""
    override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? { s == 4 ? footer : nil }
  }
}

/* your card on Settings (the board): your picture (60), your name, your role in your colour (a client: "Client · the
   client" in the client colour), and under it "From E11 Console" (a client: the email) — Apple's subtitle cell; the
   picture is ours, set in the room Apple's cell keeps for it. */
final class MeCardCell: UITableViewCell {
  private let pic = Avatar(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    contentConfiguration = UIListContentConfiguration.subtitleCell()   // (Apple's content view first, then the picture on it)
    pic.isUserInteractionEnabled = false; contentView.addSubview(pic)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set() {
    let T = Talk.shared, me = T.me
    var cfg = UIListContentConfiguration.subtitleCell()
    cfg.text = me?.name ?? "—"; cfg.textProperties.font = .systemFont(ofSize: 20, weight: .semibold)
    let client = me?.client.flatMap { T.clients[$0]?.name }
    let role = T.isContact ? "Client" + (client.map { " · \($0)" } ?? "") : (me?.role ?? "")
    let under = T.isContact ? (T.myEmail ?? "") : "From E11 Console"
    let s = NSMutableAttributedString(string: role, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold),
      .foregroundColor: T.isContact ? Look.clientInk : (me.map { Look.person($0.id) } ?? Look.accent)])
    if !under.isEmpty { s.append(NSAttributedString(string: "\n" + under, attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel])) }
    cfg.secondaryAttributedText = s; cfg.secondaryTextProperties.numberOfLines = 2; cfg.textToSecondaryTextVerticalPadding = 1
    cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 60, height: 60); cfg.imageToTextPadding = 14
    cfg.directionalLayoutMargins.top = 14; cfg.directionalLayoutMargins.bottom = 14
    contentConfiguration = cfg
    pic.set(person: me)
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    contentView.bringSubviewToFront(pic)
    // (in the room Apple's cell keeps for the picture)
    let room = (contentView as? UIListContentView)?.imageLayoutGuide?.layoutFrame
    pic.frame = room.map { CGRect(x: $0.midX - 30, y: $0.midY - 30, width: 60, height: 60).integral } ?? CGRect(x: 16, y: ((contentView.bounds.height - 60) / 2).rounded(), width: 60, height: 60)
  }
}

// a row's icon in its coloured tile, as iPhone's Settings (the board's: 30, its corners 7, the symbol white)
enum Tile {
  private static var made: [String: UIImage] = [:]
  static func make(_ color: UInt32, _ symbol: String) -> UIImage {
    let key = "\(color)\(symbol)"; if let i = made[key] { return i }
    let s = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))?.withTintColor(.white, renderingMode: .alwaysOriginal)
    let i = draw(color) { r in
      guard let s = s else { return }
      s.draw(in: CGRect(x: (r.width - s.size.width) / 2, y: (r.height - s.size.height) / 2, width: s.size.width, height: s.size.height))
    }
    made[key] = i; return i
  }
  // About's: E11's own, the word on its blue
  static func e11() -> UIImage {
    if let i = made["e11"] { return i }
    let i = draw(0x2B5FA3) { r in
      let t = NSAttributedString(string: "E11", attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .heavy), .foregroundColor: UIColor.white])
      let z = t.size(); t.draw(at: CGPoint(x: (r.width - z.width) / 2, y: (r.height - z.height) / 2))
    }
    made["e11"] = i; return i
  }
  private static func draw(_ color: UInt32, _ inside: (CGRect) -> Void) -> UIImage {
    let r = CGRect(x: 0, y: 0, width: 30, height: 30)
    return UIGraphicsImageRenderer(bounds: r).image { _ in
      Look.rgb(color).setFill(); UIBezierPath(roundedRect: r, cornerRadius: 7).fill(); inside(r)
    }
  }
}

/* E11 Talk's own choices kept on the phone (Notifications' "While E11 Talk is open") */
enum TalkPrefs {
  private static func get(_ k: String) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? true }
  static var inAppSounds: Bool { get { get("talk_inapp_sounds") } set { UserDefaults.standard.set(newValue, forKey: "talk_inapp_sounds") } }
  static var inAppBanners: Bool { get { get("talk_inapp_banners") } set { UserDefaults.standard.set(newValue, forKey: "talk_inapp_banners") } }
}

/* Notifications (the board "Notifications"): MESSAGES — Show Notifications, Sound, Show Message Preview: iPhone's own for
   E11 Talk, shown as they are; a switch changed opens iPhone's Settings for E11 Talk (only iPhone can change them) and the
   page shows what was set when you come back; Mentions Only in Muted Groups — kept on the server (it sends the
   notifications), on until turned off. WHILE E11 TALK IS OPEN — In-App Sounds (the send and arrive sounds), In-App
   Banners (a message from another group while you're in the app). */
final class NotificationsVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var sys: (on: Bool, sound: Bool, preview: Bool, asked: Bool) = (false, false, false, true)
  private var switches: [IndexPath: UISwitch] = [:]
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Notifications"; navigationItem.largeTitleDisplayMode = .never
    NotificationCenter.default.addObserver(self, selector: #selector(readSystem), name: UIApplication.didBecomeActiveNotification, object: nil)
    readSystem()
  }
  @objc private func readSystem() {
    UNUserNotificationCenter.current().getNotificationSettings { s in
      let on = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional || s.authorizationStatus == .ephemeral
      let v: (on: Bool, sound: Bool, preview: Bool, asked: Bool) = (on, on && s.soundSetting == .enabled, on && s.showPreviewsSetting != .never, s.authorizationStatus != .notDetermined)
      DispatchQueue.main.async {
        guard v != self.sys else { return }
        self.sys = v
        // (only the switches moved — Apple's own switch animation; the rows stay as they are)
        for (ip, sw) in self.switches where ip.section == 0 && ip.row < 3 { sw.setOn([v.0, v.1, v.2][ip.row], animated: self.view.window != nil) }
      }
    }
  }
  override func numberOfSections(in tv: UITableView) -> Int { 2 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { [4, 2][s] }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { ["Messages", "While E11 Talk Is Open"][s] }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == 0 ? "A muted group still tells you when someone @mentions you." : "The sounds are E11 Console’s: a soft swoop when you send, a soft pop when one arrives."
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .default, reuseIdentifier: nil); c.selectionStyle = .none
    var cfg = UIListContentConfiguration.cell()
    let sw = switches[ip] ?? UISwitch(); switches[ip] = sw
    if ip == IndexPath(row: 3, section: 0) {
      cfg.text = "Mentions Only in Muted Groups"
      sw.isOn = Talk.shared.mutedMentions
      sw.addAction(UIAction(identifier: .init("e11.notif")) { [weak sw] _ in
        guard let on = sw?.isOn else { return }
        // (shown at once; the server's answer puts it back if it couldn't be kept)
        Talk.shared.mutedMentions = on
        Net.shared.act(["act": "setOpt", "key": "mutedMentions", "on": on]) { j in
          guard (j?["ok"] as? Bool) != true else { return }
          Talk.shared.mutedMentions = !on; sw?.setOn(!on, animated: true); toast("Couldn’t change that — try again")
        }
      }, for: .valueChanged)
    } else if ip.section == 0 {
      cfg.text = ["Show Notifications", "Sound", "Show Message Preview"][ip.row]
      sw.isOn = [sys.on, sys.sound, sys.preview][ip.row]
      sw.addAction(UIAction(identifier: .init("e11.notif")) { [weak self, weak sw] _ in if let sw = sw { self?.toSystem(ip.row, sw) } }, for: .valueChanged)
    } else {
      cfg.text = ["In-App Sounds", "In-App Banners"][ip.row]
      sw.isOn = ip.row == 0 ? TalkPrefs.inAppSounds : TalkPrefs.inAppBanners
      sw.addAction(UIAction(identifier: .init("e11.notif")) { [weak sw] _ in guard let on = sw?.isOn else { return }; if ip.row == 0 { TalkPrefs.inAppSounds = on } else { TalkPrefs.inAppBanners = on } }, for: .valueChanged)
    }
    c.contentConfiguration = cfg; c.accessoryView = sw
    return c
  }
  // iPhone's own: asked the first time, else iPhone's Settings for E11 Talk
  private func toSystem(_ row: Int, _ sw: UISwitch) {
    if row == 0 && !sys.asked && sw.isOn {
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
        DispatchQueue.main.async { if ok { UIApplication.shared.registerForRemoteNotifications() }; self.readSystem() }
      }
      return
    }
    if let u = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(u) }
    // (put back as iPhone has it — it shows the real setting again on coming back)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sw.setOn([self.sys.on, self.sys.sound, self.sys.preview][row], animated: false) }
  }
}

/* What E11 Talk keeps on this phone: the photos, videos, files and voice notes of its chats (and their pictures) */
enum Storage {
  static func total() -> Int {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey]
    guard let e = FileManager.default.enumerator(at: Net.filesDir, includingPropertiesForKeys: Array(keys)) else { return 0 }
    var n = 0
    for case let u as URL in e { let v = try? u.resourceValues(forKeys: keys); n += v?.totalFileAllocatedSize ?? v?.fileSize ?? 0 }
    return n
  }
  static func size(_ id: String) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: Net.local(id).path)[.size] as? Int) ?? 0
  }
  struct Report { var total = 0; var kinds: [String: Int] = [:]; var groups: [(String, Int)] = [] }
  // each chat's files on the phone, by kind and by group (the board's bar and BY GROUP)
  static func report() -> Report {
    let T = Talk.shared
    var r = Report(); r.total = total()
    var seen = Set<String>()
    for g in T.groups.keys {
      var n = 0
      for m in T.log(g).msgs { guard let f = m.file, seen.insert(f.id).inserted else { continue }
        let s = size(f.id); guard s > 0 else { continue }
        n += s; r.kinds[m.kind == "photo" || m.kind == "video" || m.kind == "voice" ? m.kind : "file", default: 0] += s
      }
      if n > 0 { r.groups.append((g, n)) }
    }
    r.groups.sort { $0.1 > $1.1 }
    return r
  }
}

/* Storage and Data (the board "Storage and Data"): E11 Talk and how much it keeps, a bar by kind (Videos · Photos · Files
   · Voice) — ours inside Apple's cell; BY GROUP — Apple's value cells, the most first, each opening that group's media;
   under it what's deleted by itself. */
final class StorageVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var rep = Storage.Report()
  private var sig = ""
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Storage and Data"; navigationItem.largeTitleDisplayMode = .never
    tableView.register(StorageBarCell.self, forCellReuseIdentifier: "bar")
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    rep = Storage.report(); sig = Self.sign(rep)
  }
  private static func sign(_ r: Storage.Report) -> String { "\(r.total)|\(r.kinds.sorted { $0.key < $1.key })|\(r.groups.map { "\($0.0):\($0.1)" })" }
  // (set again only when what it shows changed — crossfading in place)
  // (worked out only while the page shows — again when it comes back)
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); if dirty { dirty = false; update(fade: false) } }
  private var dirty = false
  @objc private func changed() { if view.window == nil { dirty = true } else { update(fade: true) } }
  private func update(fade: Bool) {
    let r = Storage.report(), s = Self.sign(r)
    guard s != sig else { return }
    rep = r; sig = s
    guard fade else { tableView.reloadData(); return }
    UIView.transition(with: tableView, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction]) {
      UIView.performWithoutAnimation { self.tableView.reloadData() }
    }
  }
  override func numberOfSections(in tv: UITableView) -> Int { rep.groups.isEmpty ? 1 : 2 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? 1 : rep.groups.count }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { s == 1 ? "By Group" : nil }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == numberOfSections(in: tv) - 1 ? "A group with no new messages for 90 days deletes itself, with its files, on every device." : nil
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    if ip.section == 0 { let c = tv.dequeueReusableCell(withIdentifier: "bar", for: ip) as! StorageBarCell; c.set(rep); return c }
    let (g, n) = rep.groups[ip.row], T = Talk.shared
    let c = UITableViewCell(style: .value1, reuseIdentifier: nil); c.accessoryType = .disclosureIndicator
    var cfg = UIListContentConfiguration.valueCell()
    let grp = T.groups[g]
    cfg.text = [grp.flatMap { T.clients[$0.client]?.name }, grp?.name].compactMap { $0 }.joined(separator: " · ")
    cfg.textProperties.numberOfLines = 1
    cfg.secondaryText = ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    c.contentConfiguration = cfg
    return c
  }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { ip.section == 0 ? 100 : UITableView.automaticDimension }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard ip.section == 1 else { return }
    navigationController?.pushViewController(MediaVC(group: rep.groups[ip.row].0), animated: true)
  }
}

// the board's top box: "E11 Talk" and its size (Apple's value cell), then the bar by kind and its key (ours)
final class StorageBarCell: UITableViewCell {
  static let kinds: [(String, String, UInt32)] = [("video", "Videos", 0x5E5CE6), ("photo", "Photos", 0xFF9F0A), ("file", "Files", 0x34C759), ("voice", "Voice", 0x5AA9FF)]
  private let head = UIListContentView(configuration: .valueCell())
  private let track = UIView(), key = UILabel()
  private var parts: [UIView] = []
  private var share: [CGFloat] = []
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    track.backgroundColor = .tertiarySystemFill; track.layer.cornerRadius = 5; track.clipsToBounds = true
    parts = Self.kinds.map { k in let v = UIView(); v.backgroundColor = Look.rgb(k.2); track.addSubview(v); return v }
    let s = NSMutableAttributedString()
    for (i, k) in Self.kinds.enumerated() {
      s.append(NSAttributedString(string: (i == 0 ? "" : "    ") + "● ", attributes: [.foregroundColor: Look.rgb(k.2)]))
      s.append(NSAttributedString(string: k.1, attributes: [.foregroundColor: UIColor.secondaryLabel]))
    }
    key.attributedText = s; key.font = .systemFont(ofSize: 12)
    for v in [head, track, key] { contentView.addSubview(v) }
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ r: Storage.Report) {
    var cfg = UIListContentConfiguration.valueCell()
    cfg.text = "E11 Talk"; cfg.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
    cfg.secondaryText = ByteCountFormatter.string(fromByteCount: Int64(r.total), countStyle: .file)
    cfg.directionalLayoutMargins = .zero
    head.configuration = cfg
    share = Self.kinds.map { r.total > 0 ? CGFloat(r.kinds[$0.0] ?? 0) / CGFloat(r.total) : 0 }
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let m = contentView.directionalLayoutMargins, w = contentView.bounds.width - m.leading - m.trailing
    head.frame = CGRect(x: m.leading, y: 14, width: w, height: 24)
    track.frame = CGRect(x: m.leading, y: 48, width: w, height: 10)
    var x: CGFloat = 0
    for (v, s) in zip(parts, share) { let pw = (w * s).rounded(); v.frame = CGRect(x: x, y: 0, width: pw, height: 10); x += pw }
    key.frame = CGRect(x: m.leading, y: 68, width: w, height: 18)
  }
}

/* Help (no board of its own yet): Apple's grouped list, each part in a line or two */
final class HelpVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var items: [(String, String)] {
    var a: [(String, String)] = [
      ("Starred Messages", "Hold a message and tap Star. Find them in Settings › Starred Messages, or in a group’s info."),
      ("Muting a Group", "Hold a group in the list and tap Mute. A muted group still tells you when someone @mentions you."),
      ("Chat Backup", "Your chats back up to your own iCloud. Restore them any time from Settings › Chat Backup."),
    ]
    if !Talk.shared.isContact { a.append(("Linked Devices", "Link the E11 Console Mac app to see your chats on your Mac.")) }
    if Talk.shared.boss { a.append(("Client Contacts", "Add the people from each client who can be in groups. They only see the groups they’re added to.")) }
    return a
  }
  override func viewDidLoad() { super.viewDidLoad(); title = "Help"; navigationItem.largeTitleDisplayMode = .never }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { items.count }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil); c.selectionStyle = .none
    var cfg = UIListContentConfiguration.subtitleCell()
    cfg.text = items[ip.row].0; cfg.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
    cfg.secondaryText = items[ip.row].1; cfg.secondaryTextProperties.color = .secondaryLabel; cfg.secondaryTextProperties.font = .systemFont(ofSize: 15)
    cfg.textToSecondaryTextVerticalPadding = 3; cfg.directionalLayoutMargins.top = 11; cfg.directionalLayoutMargins.bottom = 11
    c.contentConfiguration = cfg
    return c
  }
}

/* About E11 Talk (no board of its own yet): the version, the server, and how chats are kept */
final class AboutVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() { super.viewDidLoad(); title = "About E11 Talk"; navigationItem.largeTitleDisplayMode = .never }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { 2 }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    "Chats live on this phone. The server only passes each message on and lets it go once everyone has it."
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .value1, reuseIdentifier: nil); c.selectionStyle = .none
    var cfg = UIListContentConfiguration.valueCell()
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    if ip.row == 0 { cfg.text = "Version"; cfg.secondaryText = "\(v) (\(b))" } else { cfg.text = "Server"; cfg.secondaryText = Server.host }
    c.contentConfiguration = cfg
    return c
  }
}
