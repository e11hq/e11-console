import UIKit
import AVFoundation

/* Link a Mac — WhatsApp's way (Haris 2026-11-05/06). In E11 Talk: Settings → Linked devices → Link a Mac: the camera
   reads the code the E11 Console Mac app shows under E11 Talk. The server links only when that Mac is signed in to
   E11 Console as the same person. Then this phone hands the Mac its chats (the last 90 days: every group's messages and
   their photos, files and voice messages — videos stay on the phone), and from then on the Mac gets every new message
   itself, even with the phone off. The link stays until it's unlinked here, E11 Console is signed out on that Mac, the
   person leaves the team, or this phone hasn't opened E11 Talk for 30 days. */
final class LinkedDevicesVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var macs: [LinkedMac] { Talk.shared.macs }
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Linked Devices"
    navigationItem.largeTitleDisplayMode = .never
    NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .talkChanged, object: nil)
    Talk.shared.refresh()
  }
  override func numberOfSections(in tv: UITableView) -> Int { 2 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? 1 : macs.count }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { s == 1 && !macs.isEmpty ? "Linked Macs" : nil }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == 0 ? "On the Mac: E11 Console › E11 Talk at the bottom of the sidebar, then scan the code it shows. The Mac must be signed in as you."
      : macs.isEmpty ? nil : "A linked Mac gets your chats straight from your iPhone and keeps up by itself. It unlinks after 30 days if this iPhone doesn’t open E11 Talk. Tap one to unlink it."
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    var cfg = c.defaultContentConfiguration()
    if ip.section == 0 {
      cfg.text = "Link a Mac"; cfg.textProperties.color = Look.accent
      cfg.image = UIImage(systemName: "qrcode.viewfinder"); cfg.imageProperties.tintColor = Look.accent
    } else {
      let m = macs[ip.row], f = RelativeDateTimeFormatter(); f.unitsStyle = .full
      cfg.text = m.name
      cfg.secondaryText = "Last active " + f.localizedString(for: Date(timeIntervalSince1970: m.seenAt / 1000), relativeTo: Date())
      cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = UIImage(systemName: "laptopcomputer"); cfg.imageProperties.tintColor = .secondaryLabel
    }
    c.contentConfiguration = cfg
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    if ip.section == 0 { scan(); return }
    let m = macs[ip.row]
    let a = UIAlertController(title: m.name, message: "Unlink this Mac? Its E11 Talk chats are removed from it.", preferredStyle: .actionSheet)
    a.addAction(UIAlertAction(title: "Unlink", style: .destructive) { _ in
      Net.shared.act(["act": "unlinkMac", "id": m.id]) { j in
        if (j?["ok"] as? Bool) == true { toast("Unlinked"); Talk.shared.refresh() } else { toast(j?["error"] as? String ?? "Couldn’t unlink — try again") }
      }
    })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let cell = tv.cellForRow(at: ip) { a.popoverPresentationController?.sourceView = cell }
    present(a, animated: true)
  }
  private func scan() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: openScanner()
    case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { if ok { self.openScanner() } } }
    default:
      let a = UIAlertController(title: "Camera is off for E11 Talk", message: "To scan the Mac’s code, allow the camera in Settings.", preferredStyle: .alert)
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      a.addAction(UIAlertAction(title: "Settings", style: .default) { _ in if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } })
      present(a, animated: true)
    }
  }
  private func openScanner() {
    let s = ScanVC()
    s.onCode = { [weak self, weak s] code in
      Net.shared.act(["act": "linkMac", "code": code]) { j in
        guard (j?["ok"] as? Bool) == true, let m = j?["mac"] as? [String: Any], let id = m["id"] as? String else {
          s?.failed(j?["error"] as? String ?? "Couldn’t link — try again"); return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        s?.linked(m["name"] as? String ?? "Mac")
        Talk.shared.refresh()
        self?.handOver(to: id, progress: { p in s?.progress(p) }) { ok in
          s?.dismiss(animated: true) { toast(ok ? "Linked — your chats are on the Mac" : "Linked — some chats didn’t reach the Mac") }
        }
      }
    }
    let n = UINavigationController(rootViewController: s); n.modalPresentationStyle = .fullScreen
    present(n, animated: true)
  }
  // the chats to the Mac: first any file the server no longer has (sent again), then the chats themselves
  private func handOver(to mac: String, progress: @escaping (Double) -> Void, done: @escaping (Bool) -> Void) {
    let h = Talk.shared.handOver()
    Net.shared.post("/api/talk/link/has", ["ids": h.files.map { $0.id }]) { j in
      let have = Set((j?["have"] as? [String]) ?? [])
      let missing = h.files.filter { !have.contains($0.id) }
      var i = 0, ok = true
      func next() {
        progress(missing.isEmpty ? 0.9 : 0.9 * Double(i) / Double(missing.count))
        guard i < missing.count else {
          Net.shared.post("/api/talk/link/history", ["mac": mac, "groups": h.groups, "files": h.files.map { $0.id }]) { r in progress(1); done(ok && (r?["ok"] as? Bool) == true) }
          return
        }
        let f = missing[i]; i += 1
        Net.shared.resend(f.id, name: f.name) { sent in if !sent { ok = false }; next() }
      }
      next()
    }
  }
}

// ---------- the camera, reading the Mac's code ----------
final class ScanVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onCode: ((String) -> Void)?
  private let session = AVCaptureSession()
  private var preview: AVCaptureVideoPreviewLayer?
  private let frameV = UIView(), hint = UILabel(), panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
  private let bar = UIProgressView(progressViewStyle: .default)
  private var busy = false
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    title = "Link a Mac"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    navigationController?.navigationBar.barStyle = .black; navigationController?.navigationBar.tintColor = .white
    if let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) {
      session.addInput(input)
      let out = AVCaptureMetadataOutput()
      if session.canAddOutput(out) { session.addOutput(out); out.setMetadataObjectsDelegate(self, queue: .main); out.metadataObjectTypes = [.qr] }
      let p = AVCaptureVideoPreviewLayer(session: session); p.videoGravity = .resizeAspectFill; view.layer.addSublayer(p); preview = p
    }
    frameV.layer.borderColor = UIColor.white.cgColor; frameV.layer.borderWidth = 3; frameV.layer.cornerRadius = 22; frameV.layer.cornerCurve = .continuous
    view.addSubview(frameV)
    hint.text = "Point at the code on your Mac"; hint.textColor = .white; hint.font = .systemFont(ofSize: 17, weight: .semibold); hint.textAlignment = .center; hint.numberOfLines = 0
    panel.layer.cornerRadius = 18; panel.clipsToBounds = true
    panel.contentView.addSubview(hint); bar.isHidden = true; bar.progressTintColor = Look.accent; panel.contentView.addSubview(bar)
    view.addSubview(panel)
    DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
    let s = min(view.bounds.width - 80, 280)
    frameV.frame = CGRect(x: (view.bounds.width - s) / 2, y: view.bounds.midY - s / 2 - 30, width: s, height: s)
    panel.frame = CGRect(x: 24, y: frameV.frame.maxY + 36, width: view.bounds.width - 48, height: bar.isHidden ? 64 : 84)
    hint.frame = CGRect(x: 16, y: 10, width: panel.bounds.width - 32, height: 44)
    bar.frame = CGRect(x: 20, y: 62, width: panel.bounds.width - 40, height: 4)
  }
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); let s = session; DispatchQueue.global().async { s.stopRunning() } }
  func metadataOutput(_ o: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject], from c: AVCaptureConnection) {
    guard !busy, let v = (objs.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
    guard v.hasPrefix("e11talk-link:") else { hint.text = "That isn’t an E11 Console code"; return }
    busy = true
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    frameV.layer.borderColor = Look.accent.cgColor
    hint.text = "Linking…"
    onCode?(String(v.dropFirst("e11talk-link:".count)))
  }
  func failed(_ why: String) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    hint.text = why; frameV.layer.borderColor = UIColor.systemRed.cgColor
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.busy = false; self?.frameV.layer.borderColor = UIColor.white.cgColor; self?.hint.text = "Point at the code on your Mac" }
  }
  func linked(_ name: String) {
    let s = session; DispatchQueue.global().async { s.stopRunning() }
    hint.text = "Linked to \(name) — sending your chats…"
    bar.isHidden = false; bar.progress = 0.05; view.setNeedsLayout()
  }
  func progress(_ p: Double) { bar.setProgress(Float(max(0.05, p)), animated: true) }
}
