import UIKit
import AVFoundation

/* Link a Mac — WhatsApp's way (Haris 2026-11-05/06). In E11 Talk: Settings → Linked devices → Link a Mac: the camera
   reads the code E11 Talk for Mac shows (its own app, staff and client contacts alike — Haris 2026-11-14); the scan signs
   that Mac in as this phone's person. Then this phone hands the Mac its chats (the last 90 days: every group's messages and
   their photos, files and voice messages — videos stay on the phone), and from then on the Mac gets every new message
   itself, even with the phone off. The link stays until it's unlinked here, Talk is signed out on this phone, the
   person leaves the team, or this phone hasn't opened E11 Talk for 30 days. */
final class LinkedDevicesVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var macs: [LinkedMac] { Talk.shared.macs }
  /* (the board 45: LINKED MACS — each Mac in its tile, when it was last active, › to unlink; then Link a Mac as Apple's
     filled button with its line. Only a Mac that changed is set again, crossfading; one linked or unlinked fades.) */
  private enum Row: Hashable { case mac(String), link }
  private var data: UITableViewDiffableDataSource<Int, Row>!
  private var sigs: [String: String] = [:]
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Linked Devices"
    navigationItem.largeTitleDisplayMode = .never
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    data = Source(tableView: tableView) { [weak self] tv, ip, r in
      let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip); self?.fill(c, r); return c
    }
    (data as? Source)?.owner = self
    data.defaultRowAnimation = .fade
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    reload(animated: false)
    Talk.shared.refresh()
  }
  @objc private func changed() { reload(animated: view.window != nil) }
  private func sig(_ m: LinkedMac) -> String { m.name + "|" + when(m) }
  private func reload(animated: Bool) {
    var snap = NSDiffableDataSourceSnapshot<Int, Row>()
    if !macs.isEmpty { snap.appendSections([0]); snap.appendItems(macs.map { .mac($0.id) }, toSection: 0) }
    snap.appendSections([1]); snap.appendItems([.link], toSection: 1)
    var new: [String: String] = [:]
    for m in macs { new[m.id] = sig(m) }
    let old = data.snapshot()
    snap.reconfigureItems(macs.filter { old.indexOfItem(.mac($0.id)) != nil && sigs[$0.id] != new[$0.id] }.map { .mac($0.id) })
    sigs = new
    data.applySteady(snap, in: tableView, animated: animated)
  }
  // "Active today, 9:12 PM" · "Active yesterday" · "Active Nov 10" (the board's)
  private func when(_ m: LinkedMac) -> String {
    let d = Date(timeIntervalSince1970: m.seenAt / 1000), cal = Calendar.current
    if cal.isDateInToday(d) { let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return "Active today, " + f.string(from: d) }
    if cal.isDateInYesterday(d) { return "Active yesterday" }
    let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd"); return "Active " + f.string(from: d)
  }
  private func fill(_ c: UITableViewCell, _ r: Row) {
    c.contentView.subviews.filter { $0.tag == 78 }.forEach { $0.removeFromSuperview() }
    switch r {
    case .mac(let id):
      guard let m = macs.first(where: { $0.id == id }) else { return }
      var cfg = UIListContentConfiguration.subtitleCell()
      cfg.text = m.name; cfg.secondaryText = when(m); cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = Tile.make(0x5E5CE6, "desktopcomputer"); cfg.imageToTextPadding = 12
      c.contentConfiguration = cfg; c.accessoryType = .disclosureIndicator; c.selectionStyle = .default
      c.backgroundConfiguration = nil
    case .link:
      // (Apple's filled button on the page's own ground, as the board's)
      c.contentConfiguration = nil; c.accessoryType = .none; c.selectionStyle = .none
      var bg = UIBackgroundConfiguration.clear(); bg.backgroundColor = .clear; c.backgroundConfiguration = bg
      var bc = UIButton.Configuration.filled(); bc.title = "Link a Device"; bc.cornerStyle = .capsule; bc.baseBackgroundColor = Look.dyn(0x2F7BFF, 0x2F7BFF)
      bc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 17, weight: .semibold); return a }
      let b = UIButton(configuration: bc, primaryAction: UIAction { [weak self] _ in self?.scan() }); b.tag = 78
      b.frame = c.contentView.bounds; b.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      c.contentView.addSubview(b)
    }
  }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { data.itemIdentifier(for: ip) == .link ? 50 : UITableView.automaticDimension }
  private final class Source: UITableViewDiffableDataSource<Int, Row> {
    weak var owner: LinkedDevicesVC?
    override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { snapshot().sectionIdentifiers[s] == 0 ? "Linked Devices" : nil }
    override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
      snapshot().sectionIdentifiers[s] == 0
        ? "A linked device gets your chats straight from your iPhone and keeps up by itself. It unlinks after 30 days if this iPhone doesn’t open E11 Talk."
        : "On your computer: open E11 Talk, then scan the code it shows."
    }
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard case .mac(let id)? = data.itemIdentifier(for: ip), let m = macs.first(where: { $0.id == id }) else { return }
    let a = UIAlertController(title: m.name, message: "Unlink this device? Its E11 Talk chats are removed from it.", preferredStyle: .actionSheet)
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
      let a = UIAlertController(title: "Camera is off for E11 Talk", message: "To scan the device’s code, allow the camera in Settings.", preferredStyle: .alert)
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
        s?.linked(m["name"] as? String ?? "Computer")
        Talk.shared.refresh()
        self?.handOver(to: id, progress: { p in s?.progress(p) }) { ok in
          s?.dismiss(animated: true) { toast(ok ? "Linked — your chats are on it" : "Linked — some chats didn’t reach it") }
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
  // (the board 46: the camera dimmed round Apple's scanner frame — its four corners — the words under it, white and grey)
  private let dim = CAShapeLayer(), corners = CAShapeLayer(), hint = UILabel(), line = UILabel()
  private let bar = UIProgressView(progressViewStyle: .default)
  private var busy = false
  private var hole = CGRect.zero
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    title = "Link a Device"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    navigationController?.navigationBar.barStyle = .black; navigationController?.navigationBar.tintColor = .white
    if let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) {
      session.addInput(input)
      let out = AVCaptureMetadataOutput()
      if session.canAddOutput(out) { session.addOutput(out); out.setMetadataObjectsDelegate(self, queue: .main); out.metadataObjectTypes = [.qr] }
      let p = AVCaptureVideoPreviewLayer(session: session); p.videoGravity = .resizeAspectFill; view.layer.addSublayer(p); preview = p
    }
    dim.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor; dim.fillRule = .evenOdd; view.layer.addSublayer(dim)
    corners.strokeColor = UIColor.white.cgColor; corners.fillColor = UIColor.clear.cgColor; corners.lineWidth = 4; corners.lineCap = .round
    view.layer.addSublayer(corners)
    hint.text = "Point your iPhone at the code on your computer"; hint.textColor = .white; hint.font = .systemFont(ofSize: 17); hint.textAlignment = .center; hint.numberOfLines = 0
    line.text = "Open E11 Talk on your computer. The code works once, for 2 minutes."
    line.textColor = UIColor(white: 0.68, alpha: 1); line.font = .systemFont(ofSize: 14); line.textAlignment = .center; line.numberOfLines = 0
    bar.isHidden = true; bar.progressTintColor = Look.accent
    [hint, line, bar].forEach { view.addSubview($0) }
    DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
    let s = min(view.bounds.width - 132, 260)
    hole = CGRect(x: (view.bounds.width - s) / 2, y: view.bounds.midY - s / 2 - 70, width: s, height: s)
    let d = UIBezierPath(rect: view.bounds); d.append(UIBezierPath(roundedRect: hole, cornerRadius: 30)); dim.path = d.cgPath; dim.frame = view.bounds
    // (the frame's four corners, each 44 along with the frame's own rounding)
    let r: CGFloat = 30, k: CGFloat = 44, h = hole, c = UIBezierPath()
    c.move(to: CGPoint(x: h.minX, y: h.minY + k)); c.addLine(to: CGPoint(x: h.minX, y: h.minY + r)); c.addArc(withCenter: CGPoint(x: h.minX + r, y: h.minY + r), radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true); c.addLine(to: CGPoint(x: h.minX + k, y: h.minY))
    c.move(to: CGPoint(x: h.maxX - k, y: h.minY)); c.addLine(to: CGPoint(x: h.maxX - r, y: h.minY)); c.addArc(withCenter: CGPoint(x: h.maxX - r, y: h.minY + r), radius: r, startAngle: .pi * 1.5, endAngle: 0, clockwise: true); c.addLine(to: CGPoint(x: h.maxX, y: h.minY + k))
    c.move(to: CGPoint(x: h.maxX, y: h.maxY - k)); c.addLine(to: CGPoint(x: h.maxX, y: h.maxY - r)); c.addArc(withCenter: CGPoint(x: h.maxX - r, y: h.maxY - r), radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: true); c.addLine(to: CGPoint(x: h.maxX - k, y: h.maxY))
    c.move(to: CGPoint(x: h.minX + k, y: h.maxY)); c.addLine(to: CGPoint(x: h.minX + r, y: h.maxY)); c.addArc(withCenter: CGPoint(x: h.minX + r, y: h.maxY - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: true); c.addLine(to: CGPoint(x: h.minX, y: h.maxY - k))
    corners.path = c.cgPath; corners.frame = view.bounds
    let w = view.bounds.width - 80
    let hh = ceil(hint.sizeThatFits(CGSize(width: w, height: 200)).height)
    hint.frame = CGRect(x: 40, y: hole.maxY + 42, width: w, height: hh)
    let lh = ceil(line.sizeThatFits(CGSize(width: w, height: 200)).height)
    line.frame = CGRect(x: 40, y: hint.frame.maxY + 10, width: w, height: lh)
    bar.frame = CGRect(x: 60, y: line.frame.maxY + 20, width: view.bounds.width - 120, height: 4)
  }
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); let s = session; DispatchQueue.global().async { s.stopRunning() } }
  func metadataOutput(_ o: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject], from c: AVCaptureConnection) {
    guard !busy, let v = (objs.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
    guard v.hasPrefix("e11talk-link:") else { hint.text = "That isn’t an E11 Talk code"; return }
    busy = true
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    corners.strokeColor = Look.accent.cgColor
    hint.text = "Linking…"
    onCode?(String(v.dropFirst("e11talk-link:".count)))
  }
  func failed(_ why: String) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    hint.text = why; corners.strokeColor = UIColor.systemRed.cgColor
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.busy = false; self?.corners.strokeColor = UIColor.white.cgColor; self?.hint.text = "Point your iPhone at the code on your computer" }
  }
  func linked(_ name: String) {
    let s = session; DispatchQueue.global().async { s.stopRunning() }
    hint.text = "Linked to \(name) — sending your chats…"
    bar.isHidden = false; bar.progress = 0.05; view.setNeedsLayout()
  }
  func progress(_ p: Double) { bar.setProgress(Float(max(0.05, p)), animated: true) }
}
