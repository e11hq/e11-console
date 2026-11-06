import UIKit

/* E11 Talk's iCloud backup — WhatsApp's way (Haris 2026-11-06, Stage 3). Chats live only on the phone (the server lets
   each message go once everyone has it), so this keeps a copy in the person's own private iCloud (E11 Talk's hidden
   iCloud folder — not in Files, nobody else's) and brings it back on a new phone after signing in.
   - Settings → Chat backup: last backup (when, how big), Back up now, Automatic (Daily · Weekly · Monthly · Off), Include
     videos.
   - What's kept: the chats (each group's messages, who's seen what) and their photos, files and voice messages (videos
     only when switched on), per account: Backups/<server>/<person>/. Each backup copies only what changed since the last.
   - A new phone (nothing of this account on it): after signing in, "Restore your chats?" — before any new message comes
     in, so nothing is lost; then it carries on from where the backup was. */
extension Notification.Name { static let talkBackup = Notification.Name("talk.backup") }

struct BackupMeta { let at: Date; let seq: Int; let size: Int; let groups: Int }

final class Backup {
  static let shared = Backup()
  static let container = "iCloud.ae.e11.talk"
  enum Every: String, CaseIterable {
    case daily, weekly, monthly, off
    var title: String { ["daily": "Daily", "weekly": "Weekly", "monthly": "Monthly", "off": "Off"][rawValue]! }
    var seconds: TimeInterval { ["daily": 86_400, "weekly": 7 * 86_400, "monthly": 30 * 86_400, "off": .infinity][rawValue]! }
  }
  private let ud = UserDefaults.standard
  var every: Every { get { Every(rawValue: ud.string(forKey: "talk_backup_every") ?? "") ?? .daily } set { ud.set(newValue.rawValue, forKey: "talk_backup_every"); changed() } }
  var videos: Bool { get { ud.bool(forKey: "talk_backup_videos") } set { ud.set(newValue, forKey: "talk_backup_videos"); changed() } }
  var lastAt: Date? { let t = ud.double(forKey: "talk_backup_at"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
  var lastSize: Int { ud.integer(forKey: "talk_backup_size") }
  private(set) var running = false
  private(set) var lastError: String?
  private let q = DispatchQueue(label: "talk.backup", qos: .utility)
  private let fm = FileManager.default
  private func changed() { DispatchQueue.main.async { NotificationCenter.default.post(name: .talkBackup, object: nil) } }

  // E11 Talk's iCloud folder for this account (nil: iCloud or iCloud Drive is off for E11 Talk). Off the main thread.
  private func root(_ uid: String) -> URL? {
    guard let c = fm.url(forUbiquityContainerIdentifier: Backup.container) else { return nil }
    let safe = { (s: String) in s.replacingOccurrences(of: "/", with: "_") }
    return c.appendingPathComponent("Backups", isDirectory: true).appendingPathComponent(safe(Server.host), isDirectory: true).appendingPathComponent(safe(uid), isDirectory: true)
  }
  static let noICloud = "iCloud isn’t on for E11 Talk. Turn on iCloud Drive in Settings → your name → iCloud, and let E11 Talk use it."

  // ---------- back up ----------
  func backUp(_ done: ((String?) -> Void)? = nil) {
    guard !running, let uid = Talk.shared.me?.id else { done?(running ? nil : "Not signed in"); return }
    running = true; lastError = nil; changed()
    let T = Talk.shared
    let ids = T.fileIds(videos: videos)
    let seq = T.syncedUpTo, src = T.localDir, files = Net.filesDir
    q.async { [self] in
      var err: String?
      var size = 0, groups = 0
      if let r = root(uid) {
        do {
          let fdir = r.appendingPathComponent("files", isDirectory: true)
          try fm.createDirectory(at: fdir, withIntermediateDirectories: true)
          // the chats: every group's log and the lists (small — always copied)
          let mine = (try fm.contentsOfDirectory(atPath: src.path)).filter { $0.hasSuffix(".json") }
          for f in mine {
            let to = r.appendingPathComponent(f)
            try? fm.removeItem(at: to)
            try fm.copyItem(at: src.appendingPathComponent(f), to: to)
            size += (try? fm.attributesOfItem(atPath: to.path)[.size] as? Int) ?? 0
            if f.hasPrefix("g-") { groups += 1 }
          }
          // groups no longer on the phone leave the backup too
          for f in (try fm.contentsOfDirectory(atPath: r.path)) where f.hasSuffix(".json") && f != "meta.json" && !mine.contains(f) { try? fm.removeItem(at: r.appendingPathComponent(f)) }
          // their files: only what's new or changed
          var keep = Set<String>()
          for id in ids {
            let from = Net.local(id), name = from.lastPathComponent
            guard let n = (try? fm.attributesOfItem(atPath: from.path))?[.size] as? Int else { continue }   // (never opened here: not on the phone)
            keep.insert(name)
            let to = fdir.appendingPathComponent(name)
            if ((try? fm.attributesOfItem(atPath: to.path))?[.size] as? Int) != n || fm.fileExists(atPath: fdir.appendingPathComponent("." + name + ".icloud").path) {
              try? fm.removeItem(at: to)
              try fm.copyItem(at: from, to: to)
            }
            size += n
          }
          for f in (try fm.contentsOfDirectory(atPath: fdir.path)) {
            let real = f.hasPrefix(".") && f.hasSuffix(".icloud") ? String(f.dropFirst().dropLast(7)) : f
            if !keep.contains(real) { try? fm.removeItem(at: fdir.appendingPathComponent(f)) }
          }
          _ = files
          // last: what this backup is
          let meta: [String: Any] = ["at": Date().timeIntervalSince1970, "seq": seq, "size": size, "groups": groups,
                                     "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""]
          try JSONSerialization.data(withJSONObject: meta).write(to: r.appendingPathComponent("meta.json"), options: .atomic)
        } catch { err = "Couldn’t back up — " + error.localizedDescription }
      } else { err = Backup.noICloud }
      DispatchQueue.main.async { [self] in
        running = false; lastError = err
        if err == nil { ud.set(Date().timeIntervalSince1970, forKey: "talk_backup_at"); ud.set(size, forKey: "talk_backup_size") }
        changed(); done?(err)
      }
    }
  }
  // automatic: when the app goes to the background and the last backup is older than the chosen interval
  func backUpIfDue() {
    guard every != .off, !running, Talk.shared.me != nil, !Talk.shared.isFresh else { return }
    if let t = lastAt, Date().timeIntervalSince(t) < every.seconds { return }
    var task: UIBackgroundTaskIdentifier = .invalid
    task = UIApplication.shared.beginBackgroundTask(withName: "E11 Talk backup") { UIApplication.shared.endBackgroundTask(task); task = .invalid }
    backUp { _ in if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid } }
  }

  // ---------- restore (a new phone) ----------
  // iCloud may not have the files on this phone yet: ask for them and wait
  private func fetch(_ url: URL, wait: TimeInterval) -> Bool {
    if fm.fileExists(atPath: url.path) { return true }
    try? fm.startDownloadingUbiquitousItem(at: url)
    let end = Date().addingTimeInterval(wait)
    while Date() < end { if fm.fileExists(atPath: url.path) { return true }; Thread.sleep(forTimeInterval: 0.3) }
    return fm.fileExists(atPath: url.path)
  }
  private func placeholder(_ url: URL) -> Bool { fm.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud").path) }
  // this account's backup, if there is one (done on the main thread; nil: none, or iCloud off)
  func find(_ uid: String, _ done: @escaping (BackupMeta?) -> Void) {
    q.async { [self] in
      var out: BackupMeta?
      if let r = root(uid) {
        let m = r.appendingPathComponent("meta.json")
        if fm.fileExists(atPath: m.path) || placeholder(m), fetch(m, wait: 15),
           let d = try? Data(contentsOf: m), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
          out = BackupMeta(at: Date(timeIntervalSince1970: j["at"] as? Double ?? 0), seq: j["seq"] as? Int ?? 0, size: j["size"] as? Int ?? 0, groups: j["groups"] as? Int ?? 0)
        }
      }
      DispatchQueue.main.async { done(out) }
    }
  }
  func restore(_ uid: String, meta: BackupMeta, progress: @escaping (Double) -> Void, _ done: @escaping (String?) -> Void) {
    let dst = Talk.shared.localDir, fdst = Net.filesDir
    q.async { [self] in
      var err: String?
      if let r = root(uid) {
        let fdir = r.appendingPathComponent("files", isDirectory: true)
        // everything in the backup, by its real name (a file iCloud hasn't brought down yet shows as .name.icloud)
        func items(_ d: URL) -> [URL] {
          ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).compactMap { f in
            if f.hasPrefix(".") && f.hasSuffix(".icloud") { return d.appendingPathComponent(String(f.dropFirst().dropLast(7))) }
            return f.hasPrefix(".") ? nil : d.appendingPathComponent(f)
          }
        }
        let chats = items(r).filter { $0.pathExtension == "json" && $0.lastPathComponent != "meta.json" }
        let files = items(fdir)
        let all = chats + files
        all.forEach { try? fm.startDownloadingUbiquitousItem(at: $0) }
        var done = 0
        for u in all {
          // (the chats must all come; a file that doesn't come in time is fetched from the server later, if it still has it)
          let ok = fetch(u, wait: chats.contains(u) ? 120 : 60)
          if ok {
            let into = (chats.contains(u) ? dst : fdst).appendingPathComponent(u.lastPathComponent)
            try? fm.removeItem(at: into)
            if (try? fm.copyItem(at: u, to: into)) == nil, chats.contains(u) { err = "Couldn’t restore \(u.lastPathComponent)" }
          } else if chats.contains(u) { err = "iCloud is taking too long — try again on Wi-Fi" }
          done += 1
          let p = Double(done) / Double(max(1, all.count))
          DispatchQueue.main.async { progress(p) }
          if err != nil { break }
        }
      } else { err = Backup.noICloud }
      DispatchQueue.main.async {
        if err == nil {
          Talk.shared.syncedUpTo = meta.seq
          Talk.shared.reloadFromDisk()
          UserDefaults.standard.set(meta.at.timeIntervalSince1970, forKey: "talk_backup_at"); UserDefaults.standard.set(meta.size, forKey: "talk_backup_size")
        }
        done(err)
      }
    }
  }
}

// ---------- "Restore your chats?" on a new phone ----------
final class RestoreVC: UIViewController {
  private let meta: BackupMeta, uid: String
  var onDone: (() -> Void)?
  private let bar = UIProgressView(progressViewStyle: .default), status = UILabel()
  private let restoreB = UIButton(configuration: .filled()), skipB = UIButton(configuration: .plain())
  init(uid: String, meta: BackupMeta) { self.uid = uid; self.meta = meta; super.init(nibName: nil, bundle: nil); isModalInPresentation = true }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let icon = UIImageView(image: UIImage(systemName: "icloud.and.arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 54, weight: .regular)))
    icon.tintColor = Look.accent; icon.contentMode = .scaleAspectFit
    let title = UILabel(); title.text = "Restore your chats"; title.font = .systemFont(ofSize: 26, weight: .bold); title.textAlignment = .center
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
    let sub = UILabel(); sub.numberOfLines = 0; sub.textAlignment = .center; sub.textColor = .secondaryLabel; sub.font = .systemFont(ofSize: 16)
    sub.text = "A backup was found in your iCloud.\n\(f.string(from: meta.at)) · \(ByteCountFormatter.string(fromByteCount: Int64(meta.size), countStyle: .file)) · \(meta.groups) chat\(meta.groups == 1 ? "" : "s")\n\nIf you skip, chats from before can’t be brought back later."
    restoreB.configuration?.title = "Restore"; restoreB.configuration?.cornerStyle = .large; restoreB.configuration?.buttonSize = .large
    skipB.configuration?.title = "Skip"
    restoreB.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
    skipB.addAction(UIAction { [weak self] _ in self?.skip() }, for: .touchUpInside)
    bar.isHidden = true; status.isHidden = true; status.textColor = .secondaryLabel; status.font = .systemFont(ofSize: 14); status.textAlignment = .center
    let st = UIStackView(arrangedSubviews: [icon, title, sub, bar, status, restoreB, skipB]); st.axis = .vertical; st.spacing = 14
    st.setCustomSpacing(28, after: sub); st.setCustomSpacing(6, after: restoreB)
    st.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(st)
    NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
                                 st.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12),
                                 st.centerYAnchor.constraint(equalTo: view.centerYAnchor), icon.heightAnchor.constraint(equalToConstant: 64)])
  }
  private func go() {
    restoreB.isEnabled = false; skipB.isHidden = true; bar.isHidden = false; status.isHidden = false
    status.text = "Restoring… keep E11 Talk open"
    UIApplication.shared.isIdleTimerDisabled = true
    Backup.shared.restore(uid, meta: meta, progress: { [weak self] p in self?.bar.setProgress(Float(p), animated: true) }) { [weak self] err in
      UIApplication.shared.isIdleTimerDisabled = false
      guard let self = self else { return }
      if let e = err {
        self.status.text = e; self.restoreB.isEnabled = true; self.restoreB.configuration?.title = "Try again"; self.skipB.isHidden = false
      } else {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.dismiss(animated: true) { toast("Chats restored"); self.onDone?() }
      }
    }
  }
  private func skip() {
    let a = UIAlertController(title: "Skip restoring?", message: "Chats from before won’t be on this phone. New messages still come in.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Skip", style: .destructive) { [weak self] _ in self?.dismiss(animated: true) { self?.onDone?() } })
    present(a, animated: true)
  }
}

// ---------- Settings → Chat backup ----------
final class BackupVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private let B = Backup.shared
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Chat backup"
    navigationItem.largeTitleDisplayMode = .never
    NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .talkBackup, object: nil)
  }
  override func numberOfSections(in tv: UITableView) -> Int { 3 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { [2, 1, 1][s] }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    switch s {
    case 0: return B.lastError ?? "Your chats, photos, files and voice messages are kept in your own iCloud — only you can see them. On a new phone, sign in to E11 Talk and you’ll be asked to restore them."
    case 1: return "Backs up when you leave E11 Talk, once the time has passed. Use Wi-Fi when you can."
    default: return "Videos can make the backup much bigger."
    }
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .value1, reuseIdentifier: nil)
    var cfg = UIListContentConfiguration.valueCell()
    switch (ip.section, ip.row) {
    case (0, 0):
      cfg = .subtitleCell()
      let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
      cfg.text = "Last backup"
      cfg.secondaryText = B.lastAt.map { f.localizedString(for: $0, relativeTo: Date()).capitalizingFirst + " · " + ByteCountFormatter.string(fromByteCount: Int64(B.lastSize), countStyle: .file) } ?? "Never"
      cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = UIImage(systemName: "icloud"); c.selectionStyle = .none
    case (0, 1):
      cfg = .cell()
      cfg.text = B.running ? "Backing up…" : "Back up now"; cfg.textProperties.color = B.running ? .secondaryLabel : Look.accent
      if B.running { let sp = UIActivityIndicatorView(style: .medium); sp.startAnimating(); c.accessoryView = sp }
    case (1, 0):
      cfg.text = "Automatic backup"; cfg.secondaryText = B.every.title
      let b = UIButton(configuration: .plain()); b.showsMenuAsPrimaryAction = true; b.changesSelectionAsPrimaryAction = true
      b.menu = UIMenu(children: Backup.Every.allCases.map { e in UIAction(title: e.title, state: e == B.every ? .on : .off) { [weak self] _ in self?.B.every = e } })
      b.configuration?.title = B.every.title; b.configuration?.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
      b.configuration?.imagePlacement = .trailing; b.configuration?.imagePadding = 4; b.configuration?.baseForegroundColor = .secondaryLabel
      b.sizeToFit(); c.accessoryView = b; cfg.secondaryText = nil; c.selectionStyle = .none
    default:
      cfg.text = "Include videos"
      let sw = UISwitch(); sw.isOn = B.videos; sw.addAction(UIAction { [weak self] a in self?.B.videos = (a.sender as? UISwitch)?.isOn ?? false }, for: .valueChanged)
      c.accessoryView = sw; c.selectionStyle = .none
    }
    c.contentConfiguration = cfg
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard ip == IndexPath(row: 1, section: 0), !B.running else { return }
    B.backUp { err in
      if let e = err { toast(e.count > 60 ? "Couldn’t back up — see below" : e) }
      else { UINotificationFeedbackGenerator().notificationOccurred(.success); toast("Backed up to iCloud") }
    }
  }
}
private extension String { var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() } }
