import UIKit

/* Client Assets, the app's own (shell 32 — Haris 2026-11-02, from the approved mockup; "everything at once"):
   1. All Client Assets — Home's big title ("Client Assets", "6 clients · 287 files" under it), the shared 🔍 (every
      client's files) and your photo; the clients as a 2-column grid of cards (logo or colour with initials, name,
      "6 folders · 48 files"); "+ Add client" for those who may.
   2. A client's assets — the task page's bar (‹ · logo and name, "6 folders · 48 files" under it · •••): a search bar
      for its files, Folders as a 2-column grid, Recently added in one inset group (thumbnail, name, type · size, •••).
   3. A folder — the bar with its name and the client under it: its folders, "N files" with Select, the files as a
      3-column grid (tapped: the app's preview; held: Copy, Download, Info, Delete); "↑ Upload" at the bottom right.
   What's in them, and who may do what, comes from the page (phone.js NativeAssets — the website's own rules); each
   change is done there too, the website's way. Screens slide in from the right over the one before; ‹ or the swipe
   from the left edge goes back. */

// ---------- pieces ----------

// "Folders" · "Recently added" · "14 files" with Select on the right
final class AssetsHead: UIView, HomeBlock {
  let label = UILabel(), button = UIButton(type: .system)
  var onButton: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    label.font = .systemFont(ofSize: 16); label.textColor = .secondaryLabel
    button.titleLabel?.font = .systemFont(ofSize: 15)
    button.addAction(UIAction { [weak self] _ in UISelectionFeedbackGenerator().selectionChanged(); self?.onButton?() }, for: .touchUpInside)
    addSubview(label); addSubview(button)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ t: String, button b: String? = nil) {
    label.text = t
    UIView.performWithoutAnimation { button.setTitle(b, for: .normal); button.layoutIfNeeded() }
    button.isHidden = b == nil
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { 40 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    let bw = button.isHidden ? 0 : ceil(button.sizeThatFits(CGSize(width: 200, height: 30)).width)
    button.frame = CGRect(x: W - 20 - bw, y: 8, width: bw, height: 30)
    label.frame = CGRect(x: 20, y: 8, width: W - 40 - bw - 8, height: 30)
  }
}

// a line of words in the list (nothing here yet, a folder's note)
final class AssetsNote: UIView, HomeBlock {
  let label = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    label.font = .systemFont(ofSize: 15); label.textColor = .secondaryLabel; label.numberOfLines = 0; label.textAlignment = .center
    addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }
  func blockHeight(_ W: CGFloat) -> CGFloat { ceil(label.sizeThatFits(CGSize(width: W - 64, height: 400)).height) + 36 }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = bounds.insetBy(dx: 32, dy: 18) }
}

// the search bar for a client's files (as iPhone's own: a grey capsule with the lens)
final class AssetsFind: UIView, HomeBlock, UITextFieldDelegate {
  let field = UISearchTextField()
  var onChange: ((String) -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    field.font = .systemFont(ofSize: 17); field.returnKeyType = .search; field.autocorrectionType = .no
    field.delegate = self
    field.addAction(UIAction { [weak self] _ in self?.onChange?(self?.field.text ?? "") }, for: .editingChanged)
    addSubview(field)
  }
  required init?(coder: NSCoder) { fatalError() }
  func textFieldShouldReturn(_ t: UITextField) -> Bool { t.resignFirstResponder(); return true }
  func blockHeight(_ W: CGFloat) -> CGFloat { 52 }
  override func layoutSubviews() { super.layoutSubviews(); field.frame = CGRect(x: 16, y: 4, width: bounds.width - 32, height: 40) }
}

// a picture of a file: its thumbnail when it has one, else its kind's colour with its extension
final class AssetThumb: UIView {
  private let img = UIImageView(), ext = UILabel()
  private var src: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true; layer.cornerCurve = .continuous
    img.contentMode = .scaleAspectFill; img.clipsToBounds = true
    ext.textColor = .white; ext.textAlignment = .center; ext.adjustsFontSizeToFitWidth = true; ext.minimumScaleFactor = 0.5
    addSubview(img); addSubview(ext)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ f: [String: Any]) {
    let name = f["name"] as? String ?? ""
    backgroundColor = DescEditor.kind(name).1
    ext.text = (f["ext"] as? String ?? "file").uppercased()
    let t = f["thumbUrl"] as? String
    if t != src {
      src = t; img.image = nil; ext.isHidden = false
      if let p = t { FeedLoader.shared.image(p) { [weak self] i in guard let self = self, self.src == p, let i = i else { return }; self.img.image = i; self.ext.isHidden = true; self.backgroundColor = .tertiarySystemFill } }
    }
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    img.frame = bounds
    ext.font = .systemFont(ofSize: max(10, bounds.width * 0.2), weight: .heavy)
    ext.frame = bounds.insetBy(dx: 6, dy: 0)
  }
}

// a tile that's tapped, or touched and held as the comment cards are (Haris 2026-11-03): the whole card shrinks as one
// from the moment the finger is down (the shared PressShrink); held long enough — the haptic, its sheet slides up, and
// it springs back
class AssetTile: UIControl {
  var onTap: (() -> Void)?
  var onHold: (() -> Void)?
  private var shrink: PressShrink?
  // (a tile that does nothing when tapped — a row of words: no shrink under the finger, no tap)
  var pressable = true { didSet { shrink?.isEnabled = pressable } }
  override init(frame: CGRect) {
    super.init(frame: frame)
    addAction(UIAction { [weak self] _ in guard let self = self, self.pressable, let t = self.onTap else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); t() }, for: .touchUpInside)
    shrink = PressShrink.add(to: self)
    let lp = UILongPressGestureRecognizer(target: self, action: #selector(held(_:))); lp.minimumPressDuration = 0.45
    addGestureRecognizer(lp)
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func held(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began, let h = onHold else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    cancelTracking(with: nil)   // (no tap after the hold)
    h()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.shrink?.release() }
  }
  // (its size and place set without touching its shrink — setting the frame of a card shrunk while held re-laid its
  //  insides: they moved, as the comment cards' once did)
  func place(_ r: CGRect) { bounds = CGRect(origin: .zero, size: r.size); center = CGPoint(x: r.midX, y: r.midY) }
}

// the clients: two columns of cards — a big logo area (its logo, or its colour with initials), name, "6 folders · 48 files"
final class ClientCards: UIView, HomeBlock {
  var onOpen: ((String) -> Void)?
  private var tiles: [AssetTile] = [], made: [String: (AssetTile, String)] = [:]
  // (each card kept while it shows the same — only a changed one is made again: the rule for every screen of the app's)
  func set(_ list: [[String: Any]], look L: HomeLook) {
    var keep = made; made = [:]
    tiles = list.map { c in
      let id = c["id"] as? String ?? ""
      let sig = "\(c["name"] ?? "")|\(c["sub"] ?? "")|\(c["logo"] ?? "")|\(c["rgb"] ?? "")|\(L.light)"
      if let k = keep.removeValue(forKey: id) {
        if k.1 == sig { made[id] = k; return k.0 }
        k.0.removeFromSuperview()
      }
      let t = AssetTile(); t.backgroundColor = L.card; t.layer.cornerRadius = 24; t.layer.cornerCurve = .continuous
      let logo = UIImageView(); logo.layer.cornerRadius = 16; logo.layer.cornerCurve = .continuous; logo.clipsToBounds = true; logo.contentMode = .scaleAspectFill   // (the logo filling its whole tile, edge to edge — Haris 2026-11-04)
      logo.backgroundColor = NativeSheetVC.color(c["rgb"]) ?? .systemBlue; logo.tag = 1
      let ini = UILabel(); ini.text = c["ini"] as? String; ini.font = .systemFont(ofSize: 34, weight: .heavy); ini.textColor = .white; ini.textAlignment = .center; ini.tag = 2
      logo.addSubview(ini)
      let n = UILabel(); n.text = c["name"] as? String; n.font = .systemFont(ofSize: 16, weight: .semibold); n.textColor = L.title; n.lineBreakMode = .byTruncatingTail; n.tag = 3
      let s = UILabel(); s.text = c["sub"] as? String; s.font = .systemFont(ofSize: 13); s.textColor = .secondaryLabel; s.tag = 4
      [logo, n, s].forEach { $0.isUserInteractionEnabled = false; t.addSubview($0) }
      if let p = c["logo"] as? String { FeedLoader.shared.image(p) { [weak logo, weak ini] i in guard let i = i else { return }; logo?.image = i; logo?.backgroundColor = .white; ini?.isHidden = true } }
      t.onTap = { [weak self] in self?.onOpen?(id) }
      t.accessibilityLabel = "\(c["name"] as? String ?? ""), \(c["sub"] as? String ?? "")"
      addSubview(t)
      made[id] = (t, sig)
      return t
    }
    keep.values.forEach { $0.0.removeFromSuperview() }
    setNeedsLayout()
  }
  private func side(_ W: CGFloat) -> CGFloat { (W - 32 - 12) / 2 }
  private func tileH(_ W: CGFloat) -> CGFloat { 12 + (side(W) - 24) * 0.62 + 10 + 22 + 18 + 12 }
  func blockHeight(_ W: CGFloat) -> CGFloat { let rows = CGFloat((tiles.count + 1) / 2); return rows == 0 ? 0 : rows * tileH(W) + (rows - 1) * 12 + 8 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, s = side(W), h = tileH(W)
    for (i, t) in tiles.enumerated() {
      t.place(CGRect(x: 16 + CGFloat(i % 2) * (s + 12), y: CGFloat(i / 2) * (h + 12), width: s, height: h))
      let lh = (s - 24) * 0.62
      t.viewWithTag(1)?.frame = CGRect(x: 12, y: 12, width: s - 24, height: lh)
      if let lv = t.viewWithTag(1) { lv.viewWithTag(2)?.frame = lv.bounds }
      t.viewWithTag(3)?.frame = CGRect(x: 14, y: 12 + lh + 10, width: s - 28, height: 22)
      t.viewWithTag(4)?.frame = CGRect(x: 14, y: 12 + lh + 10 + 22, width: s - 28, height: 18)
    }
  }
}

// folders: two columns of tiles — the folder in its colour, its name, "14 files" (held: its menu)
final class FolderTiles: UIView, HomeBlock {
  var onOpen: ((String) -> Void)?
  var menu: (([String: Any]) -> Void)?   // (held: its sheet)
  private var tiles: [AssetTile] = [], made: [String: (AssetTile, String)] = [:]
  static func meta(_ f: [String: Any]) -> String {
    let s = f["subs"] as? Int ?? 0, n = f["files"] as? Int ?? 0
    let bits = [s > 0 ? "\(s) folder\(s == 1 ? "" : "s")" : "", n > 0 ? "\(n) file\(n == 1 ? "" : "s")" : ""].filter { !$0.isEmpty }
    return bits.isEmpty ? "Empty" : bits.joined(separator: " · ")
  }
  // (each folder kept while it shows the same — only a changed one is made again)
  func set(_ list: [[String: Any]], look L: HomeLook) {
    var keep = made; made = [:]
    tiles = list.map { f in
      let id = f["id"] as? String ?? ""
      let sig = "\(f["name"] ?? "")|\(FolderTiles.meta(f))|\(f["final"] ?? "")|\(f["rgb"] ?? "")|\(L.light)"
      if let k = keep.removeValue(forKey: id) {
        if k.1 == sig { made[id] = k; k.0.onHold = { [weak self] in self?.menu?(f) }; return k.0 }
        k.0.removeFromSuperview()
      }
      let t = AssetTile(); t.backgroundColor = L.card; t.layer.cornerRadius = 20; t.layer.cornerCurve = .continuous
      let fin = (f["final"] as? Bool) == true
      let ic = UIImageView(image: UIImage(systemName: fin ? "checkmark.seal" : "folder", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)))
      ic.tintColor = fin ? .systemGreen : (NativeSheetVC.color(f["rgb"]) ?? .systemBlue); ic.contentMode = .left; ic.tag = 1
      let n = UILabel(); n.text = f["name"] as? String; n.font = .systemFont(ofSize: 15, weight: .semibold); n.textColor = L.title; n.lineBreakMode = .byTruncatingTail; n.tag = 2
      let s = UILabel(); s.text = (fin ? "Final · " : "") + FolderTiles.meta(f); s.font = .systemFont(ofSize: 13); s.textColor = .secondaryLabel; s.tag = 3
      [ic, n, s].forEach { $0.isUserInteractionEnabled = false; t.addSubview($0) }
      t.onTap = { [weak self] in self?.onOpen?(id) }
      t.onHold = { [weak self] in self?.menu?(f) }
      t.accessibilityLabel = "\(f["name"] as? String ?? "Folder"), \(s.text ?? "")"
      addSubview(t)
      made[id] = (t, sig)
      return t
    }
    keep.values.forEach { $0.0.removeFromSuperview() }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { let r = CGFloat((tiles.count + 1) / 2); return r == 0 ? 0 : r * 96 + (r - 1) * 10 + 6 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, s = (W - 32 - 10) / 2
    for (i, t) in tiles.enumerated() {
      t.place(CGRect(x: 16 + CGFloat(i % 2) * (s + 10), y: CGFloat(i / 2) * 106, width: s, height: 96))
      t.viewWithTag(1)?.frame = CGRect(x: 14, y: 14, width: 40, height: 28)
      t.viewWithTag(2)?.frame = CGRect(x: 14, y: 50, width: s - 28, height: 20)
      t.viewWithTag(3)?.frame = CGRect(x: 14, y: 70, width: s - 28, height: 17)
    }
  }
}

// files in one inset group, a row each: thumbnail, name, "PNG · 48 KB" (or where it is, when found), •••
final class FileRows: UIView, HomeBlock {
  var onOpen: (([String: Any]) -> Void)?
  var menu: (([String: Any]) -> Void)?   // (held: its sheet)
  private let box = UIView()
  private var rows: [AssetTile] = [], lines: [UIView] = [], made: [String: (AssetTile, String)] = [:]
  static let H: CGFloat = 64
  override init(frame: CGRect) { super.init(frame: frame); box.layer.cornerRadius = 22; box.layer.cornerCurve = .continuous; box.clipsToBounds = true; addSubview(box) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ list: [[String: Any]], look L: HomeLook, showWhere: Bool = false) {
    box.backgroundColor = L.card
    // (each row kept while it shows the same — only a changed one is made again)
    var keep = made; made = [:]
    rows = list.map { f in
      let id = f["id"] as? String ?? ""
      let sig = "\(f["name"] ?? "")|\(f["size"] ?? "")|\(f["thumbUrl"] ?? "")|\(f["where"] ?? "")|\(f["canDel"] ?? "")|\(showWhere)|\(L.light)"
      if let k = keep.removeValue(forKey: id) {
        if k.1 == sig { made[id] = k; k.0.onTap = { [weak self] in self?.onOpen?(f) }; k.0.onHold = { [weak self] in self?.menu?(f) }; return k.0 }
        k.0.removeFromSuperview()
      }
      let r = AssetTile()
      let th = AssetThumb(); th.layer.cornerRadius = 10; th.set(f); th.tag = 1
      let n = UILabel(); n.text = f["name"] as? String; n.font = .systemFont(ofSize: 16); n.textColor = L.title; n.lineBreakMode = .byTruncatingMiddle; n.tag = 2
      let s = UILabel(); s.font = .systemFont(ofSize: 13); s.textColor = .secondaryLabel; s.tag = 3; s.lineBreakMode = .byTruncatingTail
      s.text = showWhere ? (f["where"] as? String ?? "") : "\((f["ext"] as? String ?? "").uppercased()) · \(TaskPage.size(f["size"] as? Int ?? 0))"
      // (its own fixed look in every state — a system button redrew its ••• as the menu came and went and it moved a
      //  few points, Haris 2026-11-03 07:59)
      var mc = UIButton.Configuration.plain()
      mc.image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
      mc.baseForegroundColor = .tertiaryLabel; mc.contentInsets = .zero
      let more = UIButton(configuration: mc); more.tag = 4
      more.automaticallyUpdatesConfiguration = false
      // (its sheet, as holding the row — the same as the comments' •••)
      more.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.menu?(f) }, for: .touchUpInside)
      more.accessibilityLabel = "More"
      [th, n, s].forEach { $0.isUserInteractionEnabled = false; r.addSubview($0) }
      r.addSubview(more)
      r.onTap = { [weak self] in self?.onOpen?(f) }
      r.onHold = { [weak self] in self?.menu?(f) }
      r.accessibilityLabel = "\(f["name"] as? String ?? "File"), \(s.text ?? "")"
      box.addSubview(r)
      made[id] = (r, sig)
      return r
    }
    keep.values.forEach { $0.0.removeFromSuperview() }
    lines.forEach { $0.removeFromSuperview() }
    lines = rows.dropFirst().map { _ in let l = UIView(); l.backgroundColor = .separator; box.addSubview(l); return l }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { rows.isEmpty ? 0 : CGFloat(rows.count) * FileRows.H + 6 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    box.frame = CGRect(x: 16, y: 0, width: W - 32, height: CGFloat(rows.count) * FileRows.H)
    let bw = box.bounds.width, H = FileRows.H
    for (i, r) in rows.enumerated() {
      r.place(CGRect(x: 0, y: CGFloat(i) * H, width: bw, height: H))
      r.viewWithTag(1)?.frame = CGRect(x: 14, y: (H - 44) / 2, width: 44, height: 44)
      r.viewWithTag(4)?.frame = CGRect(x: bw - 50, y: 0, width: 44, height: H)
      r.viewWithTag(2)?.frame = CGRect(x: 70, y: H / 2 - 21, width: bw - 70 - 54, height: 22)
      r.viewWithTag(3)?.frame = CGRect(x: 70, y: H / 2 + 2, width: bw - 70 - 54, height: 18)
    }
    let px = 1 / max(1, traitCollection.displayScale)
    for (i, l) in lines.enumerated() { l.frame = CGRect(x: 70, y: CGFloat(i + 1) * H - px / 2, width: bw - 70, height: px) }
  }
}

// a folder's files: three columns of square thumbnails, the name and size under each; Select ticks several
final class FileTiles: UIView, HomeBlock {
  var onOpen: (([String: Any]) -> Void)?
  var menu: (([String: Any]) -> Void)?   // (held: its sheet)
  var onPick: (() -> Void)?
  var selecting = false { didSet { if oldValue != selecting { if !selecting { picked = [] }; paintPicks() } } }
  private(set) var picked = Set<String>()
  private var tiles: [AssetTile] = [], files: [[String: Any]] = [], made: [String: (AssetTile, String)] = [:]
  // (each file kept while it shows the same — only a changed one is made again)
  func set(_ list: [[String: Any]], look L: HomeLook) {
    files = list
    picked = picked.filter { id in list.contains { ($0["id"] as? String) == id } }
    var keep = made; made = [:]
    tiles = list.map { f in
      let id = f["id"] as? String ?? ""
      let sig = "\(f["name"] ?? "")|\(f["size"] ?? "")|\(f["thumbUrl"] ?? "")|\(f["canDel"] ?? "")|\(L.light)"
      if let k = keep.removeValue(forKey: id) {
        if k.1 == sig { made[id] = k; return k.0 }
        k.0.removeFromSuperview()
      }
      let t = AssetTile()
      let th = AssetThumb(); th.layer.cornerRadius = 18; th.set(f); th.tag = 1
      let n = UILabel(); n.text = f["name"] as? String; n.font = .systemFont(ofSize: 13, weight: .medium); n.textColor = L.title; n.lineBreakMode = .byTruncatingMiddle; n.tag = 2
      let s = UILabel(); s.text = TaskPage.size(f["size"] as? Int ?? 0); s.font = .systemFont(ofSize: 12); s.textColor = .secondaryLabel; s.tag = 3
      let tick = UIImageView(); tick.tag = 5; tick.isHidden = true
      [th, n, s, tick].forEach { $0.isUserInteractionEnabled = false; t.addSubview($0) }
      t.onTap = { [weak self] in
        guard let self = self else { return }
        if self.selecting { if self.picked.contains(id) { self.picked.remove(id) } else { self.picked.insert(id) }; self.paintPicks(); self.onPick?() }
        else { self.onOpen?(f) }
      }
      t.onHold = { [weak self] in if self?.selecting != true { self?.menu?(f) } }
      t.accessibilityLabel = "\(f["name"] as? String ?? "File"), \(s.text ?? "")"
      addSubview(t)
      made[id] = (t, sig)
      return t
    }
    keep.values.forEach { $0.0.removeFromSuperview() }
    paintPicks()
    setNeedsLayout()
  }
  var pickedFiles: [[String: Any]] { files.filter { picked.contains($0["id"] as? String ?? "") } }
  private func paintPicks() {
    for (i, t) in tiles.enumerated() {
      guard let tick = t.viewWithTag(5) as? UIImageView, i < files.count else { continue }
      let on = picked.contains(files[i]["id"] as? String ?? "")
      tick.isHidden = !selecting
      tick.image = UIImage(systemName: on ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
      tick.tintColor = on ? .systemBlue : .white
      tick.layer.shadowColor = UIColor.black.cgColor; tick.layer.shadowOpacity = on ? 0 : 0.35; tick.layer.shadowRadius = 2; tick.layer.shadowOffset = .zero
      t.viewWithTag(1)?.alpha = selecting && !on ? 0.75 : 1
    }
  }
  private func side(_ W: CGFloat) -> CGFloat { floor((W - 32 - 2 * 10) / 3) }
  func blockHeight(_ W: CGFloat) -> CGFloat { let r = CGFloat((tiles.count + 2) / 3); return r == 0 ? 0 : r * (side(W) + 42) + (r - 1) * 12 + 6 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, s = side(W)
    for (i, t) in tiles.enumerated() {
      t.place(CGRect(x: 16 + CGFloat(i % 3) * (s + 10), y: CGFloat(i / 3) * (s + 42 + 12), width: s, height: s + 42))
      t.viewWithTag(1)?.frame = CGRect(x: 0, y: 0, width: s, height: s)
      t.viewWithTag(2)?.frame = CGRect(x: 2, y: s + 6, width: s - 4, height: 17)
      t.viewWithTag(3)?.frame = CGRect(x: 2, y: s + 23, width: s - 4, height: 15)
      t.viewWithTag(5)?.frame = CGRect(x: s - 32, y: 6, width: 26, height: 26)
    }
  }
}

// Info: iPhone's own grouped list of what it is
final class AssetsInfoVC: UITableViewController {
  private let rows: [(String, String)]
  var openTask: (() -> Void)?   // (a final file whose task is still there: Open task, as the website's)
  init(title: String, rows: [(String, String)]) { self.rows = rows; super.init(style: .insetGrouped); self.title = title }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
  }
  override func numberOfSections(in tv: UITableView) -> Int { openTask == nil ? 1 : 2 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? rows.count : 1 }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    if ip.section == 1 {
      let c = UITableViewCell(style: .default, reuseIdentifier: nil)
      c.textLabel?.text = "Open task"; c.textLabel?.textColor = .systemBlue
      c.imageView?.image = UIImage(systemName: "arrow.up.forward.square"); c.imageView?.tintColor = .systemBlue
      return c
    }
    let c = UITableViewCell(style: .value1, reuseIdentifier: nil)
    c.textLabel?.text = rows[ip.row].0; c.detailTextLabel?.text = rows[ip.row].1
    c.detailTextLabel?.numberOfLines = 2; c.selectionStyle = .none
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard ip.section == 1, let run = openTask else { return }
    dismiss(animated: true) { run() }
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); (navigationController as? FitNav)?.fitTo(tableView) }
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); (navigationController as? FitNav)?.fitTo(tableView) }
}

// ---------- the screens: which are open, what's in them, and what's done there ----------
final class AssetsCtl {
  private unowned let main: Main
  init(_ m: Main) { main = m }
  private struct Screen { let h: HomeView; let kind: String; let client: String?; let folder: String?; var q = "" }
  private var stack: [Screen] = []
  private var models: [String: [String: Any]] = [:]   // (a client's, by its id; "" — all of them)
  private var fromPage = false, rootTab = false
  private weak var base: UIView?   // (what the first one was opened over — a client's page, the list; hidden under it meanwhile)
  var light = true
  // (who's signed in: as the page or Me said, else the app's own copy's — opened from a client's page without the
  //  website, it wasn't known, so a new folder or an upload went to a page that isn't there and never showed: Haris
  //  2026-11-06)
  private var meSaid: String?
  private var me: String? {
    get { (meSaid?.isEmpty == false ? meSaid : nil) ?? AppData.shared.me }
    set { meSaid = newValue }
  }
  private var pending: [String: ([String: Any]) -> Void] = [:]
  private(set) var leaving = false
  private var upBusy = false

  var top: HomeView? { stack.last.map { $0.h } }
  // the one the top buttons belong to: going back, already the one under it (it was nil then — for a moment the buttons
  // were the Clients tab's under all of them, then this one's again: they faded out and in, Haris 2026-11-03 08:20)
  var shown: HomeView? {
    guard let s = stack.last, !s.h.isHidden else { return nil }
    if leaving { return stack.count >= 2 ? stack[stack.count - 2].h : nil }
    return s.h
  }
  var isOpen: Bool { !stack.isEmpty }
  var screens: [HomeView] { stack.map { $0.h } }

  // ---------- talking to the page ----------
  // (Part B step 5: the changes go straight to the server — /api/app/act, done there as the website would; the changed
  //  records into the app's copy at once, and the screen's contents worked out from it. Switched off on the server
  //  (kv app-act-assets), the copy not this person's yet, or no answer: the page, as before)
  private static let serverActs: [String: String] = ["addClient": "caAddClient", "uploaded": "caUploaded", "newFolder": "caNewFolder",
    "renameFolder": "caRenameFolder", "deleteFolder": "caDeleteFolder", "deleteFile": "caDeleteFile", "deleteFiles": "caDeleteFiles",
    "renameClient": "caRenameClient", "deleteClient": "caDeleteClient"]
  static var logosAsked = false
  func ask(_ ev: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    if let name = ev["ev"] as? String, let act = AssetsCtl.serverActs[name], AppData.shared.tabsOn, AppData.shared.ready, AppData.shared.me == me, me != nil,
       JSONSerialization.isValidJSONObject(ev) {
      var b = ev; b["ev"] = act; b["op"] = UUID().uuidString
      main.serverTask.request("/api/app/act", body: b) { [weak self] j in
        guard let self = self else { return }
        guard let j = j, (j["off"] as? Bool) != true else { self.askPage(ev, done); return }
        if let ch = j["changes"] as? [[String: Any]], !ch.isEmpty { AppData.shared.applyLocal(ch) }
        var r = j
        // (the screen's contents as the page answered them: all of them after adding / deleting a client, else that client's)
        let whose: Any = name == "addClient" || name == "deleteClient" ? NSNull() : (ev["client"] ?? NSNull())
        if let m = AppData.shared.meModel("assets", "assets", [whose]) { r["model"] = m; self.take(m) }
        done(r)
      }
      return
    }
    askPage(ev, done)
  }
  private func askPage(_ ev: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    // (Part B step 2: what's in it from the app's own copy at once — the page's answer still follows and wins)
    if (ev["ev"] as? String) == "want", AppData.shared.ready, let m = AppData.shared.meModel("assets", "assets", [ev["client"] ?? NSNull()]) {
      take(m)
      // (no website — step 9, offline: the copy's is the answer; and the logo catch-up asked of the server, once a run,
      //  as the page's autoLogosAll did when Client Assets opened)
      if !main.pageReady {
        if !AssetsCtl.logosAsked { AssetsCtl.logosAsked = true; main.serverTask.request("/api/app/act", body: ["ev": "caLogosAll", "op": UUID().uuidString]) { _ in } }
        done(["ok": true]); return
      }
    }
    // (no website and nothing in the copy for it — a client whose Client Assets aren't there for this person: said, and
    //  its empty screen taken away, not left on Loading… — the walk-through, 2026-11-05)
    if !main.pageReady, (ev["ev"] as? String) == "want" {
      done(["ok": false, "error": "These files aren’t here"])
      if let c = ev["client"] as? String, models[c] == nil, top != nil, stack.last?.client == c { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.pop() } }
      return
    }
    // (no website, and the server didn't take it: said at once — not 20 s of nothing)
    if !main.pageReady { done(["ok": false, "error": "Couldn’t reach the server — try again"]); return }
    let rid = UUID().uuidString
    var e = ev; e["rid"] = rid
    pending[rid] = done
    main.pageJS("window.__e11Assets && window.__e11Assets(\(jsonString(e)))")
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
      guard let self = self, let d = self.pending.removeValue(forKey: rid) else { return }
      d(["ok": false, "error": "No answer — try again"])
    }
  }
  // from the page: an answer, or show / hide (opened on the page itself)
  func command(_ a: [String: Any]) {
    if let rid = a["rid"] as? String {
      if let m = a["model"] as? [String: Any] { take(m) }
      pending.removeValue(forKey: rid)?(a)
      return
    }
    // (live: what's shown changed on the page — someone else's change, another device's)
    if (a["push"] as? Bool) == true {
      if let m = a["model"] as? [String: Any] { take(m); return }
      if (a["gone"] as? Bool) == true, let id = a["key"] as? String, !id.isEmpty {
        models[id] = nil
        if let i = stack.firstIndex(where: { $0.client == id }) {
          let h = i > 0 ? stack[i - 1].h : nil
          while stack.count > i + 1 { stack.removeLast().h.removeFromSuperview() }
          pop()
          if let h = h { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { h.assetsToast("That client has been removed") } }
        }
      }
      return
    }
    guard let show = a["show"] as? Bool else { return }
    if !show { if fromPage { close(animated: false) }; return }
    light = (a["light"] as? Bool) ?? light
    if let m = a["me"] as? String { me = m }
    let st = (a["start"] as? [String: Any]) ?? [:]
    let client = st["client"] as? String, folder = st["folder"] as? String
    // (already showing it — the page saying so again)
    if fromPage, let s = stack.last, s.client == client, s.folder == folder, s.kind == (client == nil ? "all" : folder == nil ? "client" : "folder") { return }
    close(animated: false)
    fromPage = true; rootTab = (a["root"] as? Bool) == true
    // (from Me › Client Assets: it slides in over Me, as Me's other pages — Haris 2026-11-04)
    let slide = main.selectedTabKey == "me"
    // (opened from somewhere — an Inbox update, a link, a client's page: just that screen, so ‹ goes back where you came
    //  from, not up through the client's folders — Haris 2026-11-04)
    if let c = client { open(client: c, folder: folder, animated: slide, direct: !rootTab) } else { openAll(animated: slide) }
  }
  private func take(_ m: [String: Any]) {
    let kind = m["kind"] as? String
    if kind == "client", let cid = m["id"] as? String {
      // (which links are off: the client's files, and its folders as "d:<client>/<folder>")
      main.loadLinkStates(((m["files"] as? [[String: Any]]) ?? []).compactMap { $0["file"] as? String } + ((m["folders"] as? [[String: Any]]) ?? []).compactMap { ($0["id"] as? String).map { "d:\(cid)/\($0)" } })
    }
    if kind == "all" { models[""] = m } else if kind == "client", let id = m["id"] as? String { models[id] = m }
    for s in stack where (kind == "all" && s.kind == "all") || (kind == "client" && s.client == (m["id"] as? String)) { draw(s) }
    main.updateCorner()   // (its ••• as it is now)
  }

  // ---------- opening ----------
  // from the Clients tab: a client's folder (or its assets) over its page
  func openFromClients(client: String, folder: String?) {
    if !stack.isEmpty, fromPage { close(animated: false) }
    fromPage = false; rootTab = false
    light = main.clientsLight
    open(client: client, folder: folder, animated: true, direct: true)   // (‹ back to the client's page, the way you came)
  }
  func openAll(animated: Bool) {
    push(screen("all", nil, nil), animated: animated)
    ask(["ev": "want"]) { [weak self] r in if (r["ok"] as? Bool) != true { self?.top?.assetsToast(r["error"] as? String ?? "Not available") } }
  }
  private func open(client: String, folder: String?, animated: Bool, direct: Bool = false) {
    // (the client's screen, then the folders down to the one asked for — only the last slides in)
    var chain: [String] = []
    if let f = folder, let m = models[client] {
      var cur: String? = f
      while let id = cur, chain.count < 8 { chain.insert(id, at: 0); cur = folderInfo(m, id)?["parent"] as? String }
    } else if let f = folder { chain = [f] }
    if direct, let f = folder {
      push(screen("folder", client, f), animated: animated)
      ask(["ev": "want", "client": client]) { [weak self] r in if (r["ok"] as? Bool) != true { self?.top?.assetsToast(r["error"] as? String ?? "Not available") } }
      return
    }
    let first = screen("client", client, nil)
    push(first, animated: animated && chain.isEmpty)
    for (i, f) in chain.enumerated() { push(screen("folder", client, f), animated: animated && i == chain.count - 1) }
    ask(["ev": "want", "client": client]) { [weak self] r in
      guard let self = self else { return }
      if (r["ok"] as? Bool) != true { self.top?.assetsToast(r["error"] as? String ?? "Not available"); return }
      // (a folder asked for straight away: its folders above it, now that they're known)
      if let f = folder, chain.count == 1, let m = self.models[client], let p = self.folderInfo(m, f)?["parent"] as? String, let i = self.stack.firstIndex(where: { $0.folder == f }) {
        var ups: [String] = []; var cur: String? = p
        while let id = cur, ups.count < 8 { ups.insert(id, at: 0); cur = self.folderInfo(m, id)?["parent"] as? String }
        for (k, id) in ups.enumerated() { let s = self.screen("folder", client, id); s.h.isHidden = true; self.stack.insert(s, at: i + k); self.draw(s) }
        self.stack.forEach { self.main.view.bringSubviewToFront($0.h) }
        self.main.view.bringSubviewToFront(self.main.tabBar)
      }
    }
  }
  private func screen(_ kind: String, _ client: String?, _ folder: String?) -> Screen {
    let h = HomeView(frame: main.view.bounds)
    h.assets = kind
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.assetsBack = !(stack.isEmpty && fromPage && rootTab)
    h.present = { [weak self] vc in self?.main.topMost().present(vc, animated: true) }
    h.onEvent = { [weak self, weak h] ev in guard let self = self, let h = h else { return }; self.event(h, ev) }
    h.onAssetsDraw = { [weak self] h, _ in self?.blocks(h) }
    h.assetsMenu = { [weak self, weak h] in guard let self = self, let h = h else { return [] }; return self.menuItems(h) }
    h.cornerShared = true
    h.onCorner = { [weak self] in self?.main.updateCorner() }
    main.view.insertSubview(h, belowSubview: main.tabBar)
    let s = Screen(h: h, kind: kind, client: client, folder: folder)
    draw(s)
    return s
  }
  private func under(_ i: Int) -> UIView? {
    if i > 0 { return stack[i - 1].h }
    // (opened from the app's own Me — Me › Client Assets: Me comes back under it, as it was)
    if fromPage { return main.meCtl.borrow() }
    // (kept from when it opened: it's hidden under the screens since — asking whether it's shown found nothing, and
    //  going back left a black page, Haris 2026-11-02 23:00)
    if let b = base { return b }
    if let p = main.clientPageIfMade, !p.isHidden { base = p; return p }
    if let l = main.clientsListIfMade, !l.isHidden { base = l; return l }
    return nil
  }
  // live without the website (the page used to send changes again): when the copy changes — another phone, the Mac,
  // the website — the open screens are worked out again from it (Haris 2026-11-06)
  private var copyWatch: UUID?
  private func watchCopyLive() {
    guard copyWatch == nil else { return }
    copyWatch = AppData.shared.listen { [weak self] in
      guard let self = self, !self.stack.isEmpty, !self.main.pageReady else { return }
      var whose: [Any] = []
      if self.stack.contains(where: { $0.kind == "all" }) { whose.append(NSNull()) }
      for c in Set(self.stack.compactMap { $0.client }) { whose.append(c) }
      for w in whose { if let m = AppData.shared.meModel("assets", "assets", [w]) { self.take(m) } }
    }
  }
  private func push(_ s: Screen, animated: Bool) {
    let W = main.view.bounds.width
    let u = under(stack.count)
    watchCopyLive()
    stack.append(s)
    draw(s)
    s.h.isHidden = false
    if animated && main.view.window != nil {
      s.h.transform = CGAffineTransform(translationX: W, y: 0)
      UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        s.h.transform = .identity; u?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
      } completion: { _ in if !s.h.isHidden, s.h.transform == .identity { u?.isHidden = true; u?.transform = .identity }; self.main.updateCorner() }
    } else {
      s.h.transform = .identity
      if let u = u { u.isHidden = true }
    }
    main.edgePanOn()
    main.updateCorner()
  }
  // ‹ / the swipe: the top one goes, the one under it comes back
  func pop(animated: Bool = true) {
    guard let s = stack.last, !leaving else { return }
    let W = main.view.bounds.width
    let u = under(stack.count - 1)
    if let u = u { u.isHidden = false; u.transform = CGAffineTransform(translationX: -W * 0.3, y: 0) }
    leaving = true
    main.updateCorner()
    let finish = {
      s.h.removeFromSuperview()
      // (closed meanwhile — another tab, the page moved on: nothing left to take off)
      if let i = self.stack.firstIndex(where: { $0.h === s.h }) { self.stack.remove(at: i) } else { self.leaving = false; return }
      self.leaving = false
      if self.stack.isEmpty { self.base = nil }
      if self.stack.isEmpty && self.fromPage {
        self.fromPage = false; self.main.pageJS("window.__e11Assets && window.__e11Assets({ev:'back'})")
      }
      else if let t = self.stack.last { self.refreshScreen(t) }
      // (without the website — step 9: emptied on the Me tab, Me again — however it was opened; the walk-through found a
      //  black screen after Client Assets opened from Me went back to nothing, 2026-11-05)
      if self.stack.isEmpty, !self.main.pageReady, self.main.selectedTabKey == "me" { self.main.meCtl.reveal() }
      self.main.edgePanOn(); self.main.updateCorner()
    }
    if animated {
      UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        s.h.transform = CGAffineTransform(translationX: W, y: 0); u?.transform = .identity
      } completion: { _ in finish() }
    } else { u?.transform = .identity; finish() }
  }
  // (the Clients tab going away: the ones opened from it go with it)
  func closeIfFromClients() { if !fromPage && !stack.isEmpty { close(animated: false) } }
  // all of them gone (another tab, the page moved on)
  func close(animated: Bool) {
    stack.forEach { $0.h.removeFromSuperview() }
    stack = []; leaving = false; fromPage = false; base = nil
    main.edgePanOn(); main.updateCorner()
  }
  // the edge swipe on the top one: it follows the finger, the one under it coming back, the top buttons between them
  private var panFrom: ((CornerButton.Spot, CornerButton.Spot, CornerButton.Spot), (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot))?
  func edgePan(_ g: UIScreenEdgePanGestureRecognizer) {
    guard let s = stack.last, !leaving else { return }
    let W = main.view.bounds.width
    let x = max(0, g.translation(in: main.view).x)
    let u = under(stack.count - 1)
    switch g.state {
    case .began:
      s.h.endEditing(true)
      if let u = u as? HomeView { u.isHidden = false; u.transform = .identity; panFrom = (main.cornerTargetFor(s.h), main.cornerTargetFor(u)) } else { u?.isHidden = false; panFrom = nil }
      u?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    case .changed:
      s.h.transform = CGAffineTransform(translationX: x, y: 0)
      u?.transform = CGAffineTransform(translationX: -W * 0.3 * (1 - x / W), y: 0)
      if let f = panFrom { main.corner.between(f.0, f.1, x / W) }
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: main.view).x
      let go = g.state == .ended && (v > 300 || (x > W * 0.4 && v > -200))
      panFrom = nil
      if go {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        leaving = true; main.updateCorner()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          s.h.transform = CGAffineTransform(translationX: W, y: 0); u?.transform = .identity
        } completion: { _ in self.leaving = false; self.pop(animated: false) }
      } else {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          s.h.transform = .identity; u?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
        } completion: { _ in if s.h.transform == .identity { u?.isHidden = true; u?.transform = .identity } }
        main.updateCorner()
      }
    default: break
    }
  }
  // (back on screen: what's there now)
  func refresh() { if let s = stack.last { refreshScreen(s) } }
  private func refreshScreen(_ s: Screen) {
    ask(s.client == nil ? ["ev": "want"] : ["ev": "want", "client": s.client!]) { _ in }
  }

  // ---------- what's on each ----------
  private func folderInfo(_ m: [String: Any], _ id: String) -> [String: Any]? { ((m["folders"] as? [[String: Any]]) ?? []).first { ($0["id"] as? String) == id } }
  private func filesIn(_ m: [String: Any], _ fid: String) -> [[String: Any]] { ((m["files"] as? [[String: Any]]) ?? []).filter { ($0["folder"] as? String) == fid } }
  private func screenOf(_ h: HomeView) -> Screen? { stack.first { $0.h === h } }
  func relight(_ l: Bool) { guard l != light else { return }; light = l; stack.forEach { draw($0) } }
  private func draw(_ s: Screen) {
    var mm: [String: Any] = ["show": true, "me": me ?? main.clientsPageMe ?? "", "look": ["light": light]]
    if let l = main.homeLook as? [String: Any], (l["light"] as? Bool) == light { mm["look"] = l }
    if s.kind == "all" {
      let m = models[""]
      mm["title"] = "Client Assets"; mm["date"] = m?["sub"] as? String ?? ""
    }
    s.h.bottomRoom = (main.tabBar.isHidden ? 40 : main.view.bounds.height - main.tabBar.frame.minY) + 96
    s.h.tabTop = main.tabBar.isHidden ? nil : main.tabPillTop
    s.h.people = main.homePagePeople
    s.h.update(mm)
  }
  private func part<T: UIView>(_ h: HomeView, _ k: String, _ make: () -> T) -> T {
    if let v = h.assetsParts[k] as? T { return v }
    let v = make(); h.assetsParts[k] = v; return v
  }
  private func blocks(_ h: HomeView) {
    guard let s = screenOf(h) else { return }
    let L = h.look
    var out: [UIView] = []
    switch s.kind {
    case "all":
      let m = models[""] ?? [:]
      let cards = part(h, "cards") { ClientCards() }
      cards.onOpen = { [weak self] id in self?.push(self!.screen("client", id, nil), animated: true); self?.ask(["ev": "want", "client": id]) { _ in } }
      cards.set((m["clients"] as? [[String: Any]]) ?? [], look: L)
      out.append(cards)
      if m.isEmpty { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n) }
      else if ((m["clients"] as? [[String: Any]]) ?? []).isEmpty { let n = part(h, "none") { AssetsNote() }; n.label.text = (m["canAdd"] as? Bool) == true ? "No clients yet — add your first client to start collecting their brand assets." : "No clients yet — an Admin or Account Manager will add them here."; out.append(n) }
      h.setFab("Add client", "plus", (m["canAdd"] as? Bool) == true ? { [weak self, weak h] in if let h = h { self?.addClient(h) } } : nil)
    case "client":
      guard let cid = s.client else { break }
      let m = models[cid] ?? [:]
      h.drawAssetsBar(name: m["name"] as? String ?? main.clientPageIfMade?.model["title"] as? String ?? "Client Assets", sub: m["sub"] as? String ?? "", logo: m["logo"] as? String, rgb: m["rgb"], ini: m["ini"] as? String, showLogo: false)   // (just the name — no colour box or logo: Haris 2026-11-04)
      let find = part(h, "find") { AssetsFind() }
      find.field.placeholder = "Search \(m["name"] as? String ?? "this client")’s files"
      find.onChange = { [weak self, weak h] q in guard let self = self, let h = h, let i = self.stack.firstIndex(where: { $0.h === h }) else { return }; self.stack[i].q = q; self.blocks(h); h.setNeedsLayout() }
      out.append(find)
      let all = (m["files"] as? [[String: Any]]) ?? []
      let q = s.q.trimmingCharacters(in: .whitespaces)
      if !q.isEmpty {
        let found = AssetsCtl.find(all, q)
        let head = part(h, "foundHead") { AssetsHead() }; head.set(found.isEmpty ? "No files found" : "\(found.count) file\(found.count == 1 ? "" : "s") found"); out.append(head)
        let rows = part(h, "found") { FileRows() }
        rows.onOpen = { [weak self] f in self?.preview(f, among: found) }
        rows.menu = { [weak self, weak h] f in if let h = h { self?.fileMenu(h, f, client: cid) } }
        rows.set(found, look: L, showWhere: true); out.append(rows)
      } else {
        let tops = ((m["folders"] as? [[String: Any]]) ?? []).filter { $0["parent"] == nil || $0["parent"] is NSNull }
        let head = part(h, "foldersHead") { AssetsHead() }; head.set("Folders"); out.append(head)
        let tiles = part(h, "folders") { FolderTiles() }
        tiles.onOpen = { [weak self] id in guard let self = self else { return }; self.push(self.screen("folder", cid, id), animated: true) }
        tiles.menu = { [weak self, weak h] f in if let h = h { self?.folderMenu(h, f, client: cid) } }
        tiles.set(tops, look: L); out.append(tiles)
        if m.isEmpty { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n) }
        let recent = ((m["recent"] as? [String]) ?? []).compactMap { id in all.first { ($0["id"] as? String) == id } }
        if !recent.isEmpty {
          let rh = part(h, "recentHead") { AssetsHead() }; rh.set("Recently added"); out.append(rh)
          let rows = part(h, "recent") { FileRows() }
          rows.onOpen = { [weak self] f in self?.preview(f, among: recent) }
          rows.menu = { [weak self, weak h] f in if let h = h { self?.fileMenu(h, f, client: cid) } }
          rows.set(recent, look: L); out.append(rows)
        }
      }
      h.setFab("", "plus", nil)
    case "folder":
      guard let cid = s.client, let fid = s.folder else { break }
      let m = models[cid] ?? [:]
      let f = folderInfo(m, fid)
      h.drawAssetsBar(name: f?["name"] as? String ?? "Folder", sub: m["name"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      let subs = ((m["folders"] as? [[String: Any]]) ?? []).filter { ($0["parent"] as? String) == fid }
      if !subs.isEmpty {
        let head = part(h, "foldersHead") { AssetsHead() }; head.set("Folders"); out.append(head)
        let tiles = part(h, "folders") { FolderTiles() }
        tiles.onOpen = { [weak self] id in guard let self = self else { return }; self.push(self.screen("folder", cid, id), animated: true) }
        tiles.menu = { [weak self, weak h] x in if let h = h { self?.folderMenu(h, x, client: cid) } }
        tiles.set(subs, look: L); out.append(tiles)
      }
      let files = filesIn(m, fid)
      let grid = part(h, "files") { FileTiles() }
      let head = part(h, "filesHead") { AssetsHead() }
      head.set(files.isEmpty ? "Files" : "\(files.count) file\(files.count == 1 ? "" : "s")", button: files.isEmpty ? nil : grid.selecting ? "Cancel" : "Select")
      head.onButton = { [weak self, weak h, weak grid] in guard let h = h, let g = grid else { return }; g.selecting.toggle(); self?.blocks(h); h.setNeedsLayout() }
      if !files.isEmpty || f == nil || subs.isEmpty { out.append(head) }
      grid.onOpen = { [weak self] x in self?.preview(x, among: files) }
      grid.menu = { [weak self, weak h] x in if let h = h { self?.fileMenu(h, x, client: cid) } }
      grid.onPick = { [weak self, weak h] in if let h = h { self?.blocks(h) } }
      grid.set(files, look: L)
      if !files.isEmpty { out.append(grid) }
      if files.isEmpty {
        let n = part(h, "empty") { AssetsNote() }
        n.label.text = m.isEmpty ? "Loading…" : (f?["note"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ((f?["canUpload"] as? Bool) == true ? "No files yet — tap Upload to add some." : "No files here yet.")
        out.append(n)
      }
      if grid.selecting {
        let n = grid.picked.count
        h.setFab(n == 0 ? "Select files" : "Download \(n)", "arrow.down.circle", n == 0 ? nil : { [weak self, weak h, weak grid] in
          guard let self = self, let h = h, let g = grid else { return }
          self.downloadMany(h, g.pickedFiles, name: f?["name"] as? String ?? "Files"); g.selecting = false; self.blocks(h)
        })
        // (and Delete, when you may delete every file picked — Haris 2026-11-04)
        let pk = grid.pickedFiles
        let canDel = !pk.isEmpty && pk.allSatisfy { ($0["canDel"] as? Bool) == true }
        h.setFab2("Delete \(n)", canDel ? { [weak self, weak h, weak grid] in
          guard let self = self, let h = h, let g = grid else { return }
          let list = g.pickedFiles; let ids = list.compactMap { $0["id"] as? String }
          let one = list.count == 1 ? "“\(list[0]["name"] as? String ?? "this file")”" : "\(list.count) files"
          self.confirm(h, "Delete \(one)?", "\(list.count == 1 ? "It moves" : "They move") to the Trash, where \(list.count == 1 ? "it" : "they") can be restored within 30 days. Copies already pasted into tasks stay.", "Delete") { [weak self, weak h, weak g] in
            guard let self = self, let h = h else { return }
            self.change(h, ["ev": "deleteFiles", "client": cid, "folder": fid, "files": ids], done: list.count == 1 ? "Deleted" : "\(list.count) files deleted") { [weak self, weak h] _ in
              g?.selecting = false; if let h = h { self?.blocks(h) }
            }
          }
        } : nil)
      } else {
        h.setFab2("", nil)
        h.setFab("Upload", "arrow.up", (f?["canUpload"] as? Bool) == true ? { [weak self, weak h] in if let h = h { self?.upload(h, client: cid, folder: fid) } } : nil)
      }
    default: break
    }
    h.setContent(out)
  }
  // a client's files whose names have every word typed (accents and case aside)
  static func find(_ files: [[String: Any]], _ q: String) -> [[String: Any]] {
    let norm = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let terms = norm(q).split(whereSeparator: { $0 == " " || $0 == "," }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }
    return files.filter { f in let n = norm((f["name"] as? String ?? "") + " " + (f["where"] as? String ?? "")); return terms.allSatisfy { n.contains($0) } }.prefix(80).map { $0 }
  }

  // ---------- taps ----------
  private func event(_ h: HomeView, _ ev: [String: Any]) {
    switch ev["ev"] as? String ?? "" {
    case "back": if h === top { pop() }
    case "me": close(animated: false); main.pageJS("window.__e11Assets && window.__e11Assets({ev:'me'})"); if !main.pageReady { main.selectTab("me") }
    case "find":
      // 🔍 on All Client Assets: every client's files, found here
      let q = (ev["q"] as? String ?? "").trimmingCharacters(in: .whitespaces)
      guard !q.isEmpty else { h.showFound([], hint: "Search the files of every client — logos, guidelines, fonts…"); return }
      let all = (models[""]?["files"] as? [[String: Any]]) ?? []
      let found = AssetsCtl.find(all, q)
      let rows = FileRows()
      rows.onOpen = { [weak self] f in self?.preview(f, among: found) }
      rows.menu = { [weak self, weak h] f in if let h = h { self?.fileMenu(h, f, client: f["client"] as? String ?? "") } }
      rows.set(found, look: h.look, showWhere: true)
      h.showFound(found.isEmpty ? [] : [rows], hint: found.isEmpty ? "No files found." : nil)
    default: break
    }
  }
  private func preview(_ f: [String: Any], among list: [[String: Any]]) {
    let at = list.firstIndex { ($0["id"] as? String) == (f["id"] as? String) } ?? 0
    main.openFiles(list, at: at)
  }
  private func toast(_ h: HomeView?, _ t: String) { (h ?? top)?.assetsToast(t) }

  // ---------- a file's and a folder's sheet (held, or •••): iPhone's own sheet, as the comments' ----------
  private func sheet(_ title: String, _ items: [(String, String, Bool, () -> Void)]) {
    var main: [[String: Any]] = [], danger: [[String: Any]] = []
    for (i, it) in items.enumerated() {
      var row: [String: Any] = ["i": i, "label": it.0, "icon": it.1, "danger": it.2]
      if it.1 == "unlock" { row["accent"] = true }   // (Turn on link: blue)
      if it.0 == "Turn off link" { row["red"] = true }   // (Turn off link: red — Haris 2026-11-03)
      if it.2 { danger.append(row) } else { main.append(row) }
    }
    var secs: [[String: Any]] = [["header": title, "rows": main]]
    if !danger.isEmpty { secs.append(["rows": danger]) }
    let vc = NativeSheetVC(["sections": secs], dark: !light, pick: nil) { i, _ in
      guard i >= 0, i < items.count else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { items[i].3() }   // (once the sheet has gone)
    }
    self.main.topMost().present(vc, animated: true)
  }
  func fileMenu(_ h: HomeView, _ f: [String: Any], client: String) {
    var items: [(String, String, Bool, () -> Void)] = [
      ("Copy link", "link", false, { [weak self, weak h] in self?.main.copyFile(f) { t in h?.assetsToast(t) } }),
      ("Download", "download", false, { [weak self, weak h] in guard let self = self else { return }; self.main.downloadFile(f, from: self.main.topMost()) { t in h?.assetsToast(t) } }),
      ("Info", "info", false, { [weak self] in self?.fileInfo(f) }),
    ]
    let flipFile: () -> Void = { [weak self, weak h] in self?.main.fileLinkToggle(f) { t in h?.assetsToast(t) } }
    if Main.isAdmin { if Main.linksOff.contains(f["file"] as? String ?? "") { items.append(("Turn on link", "unlock", false, flipFile)) } else { items.append(("Turn off link", "lock", false, flipFile)) } }
    if (f["canDel"] as? Bool) == true, let fid = f["folder"] as? String {
      items.append(("Delete", "trash", true, { [weak self, weak h] in
        guard let self = self, let h = h else { return }
        self.confirm(h, "Delete “\(f["name"] as? String ?? "this file")”?", "It moves to the Trash, where it can be restored within 30 days. Copies already pasted into tasks stay.", "Delete") {
          self.change(h, ["ev": "deleteFile", "client": client, "folder": fid, "file": f["id"] as? String ?? ""], done: "Deleted")
        }
      }))
    }
    sheet(f["name"] as? String ?? "File", items)
  }
  func folderMenu(_ h: HomeView, _ f: [String: Any], client: String) {
    let id = f["id"] as? String ?? ""
    var items: [(String, String, Bool, () -> Void)] = [
      ("Open", "folder", false, { [weak self] in guard let self = self else { return }; self.push(self.screen("folder", client, id), animated: true) }),
      ("Info", "info", false, { [weak self] in self?.folderInfoSheet(f, client: client) }),
    ]
    if (f["canLink"] as? Bool) == true {
      items.append(("Copy link", "link", false, { [weak self, weak h] in self?.main.copyFolderLink(client: client, folder: id) { t in h?.assetsToast(t) } }))
      let flip: () -> Void = { [weak self, weak h] in self?.main.folderLinkToggle(client: client, folder: id) { t in h?.assetsToast(t) } }
      if Main.isAdmin { if Main.linksOff.contains("d:\(client)/\(id)") { items.append(("Turn on link", "unlock", false, flip)) } else { items.append(("Turn off link", "lock", false, flip)) } }
    }
    if (f["canRename"] as? Bool) == true { items.append(("Rename folder", "edit", false, { [weak self, weak h] in if let h = h { self?.renameFolder(h, f, client: client) } })) }
    if (f["canDel"] as? Bool) == true { items.append(("Delete folder", "trash", true, { [weak self, weak h] in if let h = h { self?.deleteFolder(h, f, client: client) } })) }
    sheet(f["name"] as? String ?? "Folder", items)
  }
  // the ••• at the top
  private func menuItems(_ h: HomeView) -> [CornerMenuItem] {
    guard let s = screenOf(h), let cid = s.client else { return [] }
    let m = models[cid] ?? [:]
    var out: [CornerMenuItem] = []
    if s.kind == "client" {
      if (m["canNewTop"] as? Bool) == true { out.append(CornerMenuItem(title: "New folder", symbol: "folder.badge.plus", run: { [weak self, weak h] in if let h = h { self?.newFolder(h, client: cid, parent: nil) } })) }
      let all = (m["files"] as? [[String: Any]]) ?? []
      if !all.isEmpty { out.append(CornerMenuItem(title: "Download all", symbol: "arrow.down.circle", run: { [weak self, weak h] in if let h = h { self?.downloadMany(h, all, name: m["name"] as? String ?? "Client Assets") } })) }
      out.append(CornerMenuItem(title: "Info", symbol: "info.circle", run: { [weak self] in self?.clientInfo(m) }))
      var edit: [CornerMenuItem] = []
      if (m["canRename"] as? Bool) == true { edit.append(CornerMenuItem(title: "Rename client", symbol: "pencil", run: { [weak self, weak h] in if let h = h { self?.renameClient(h, m) } })) }
      if (m["canDelete"] as? Bool) == true { edit.append(CornerMenuItem(title: "Delete client", symbol: "trash", destructive: true, run: { [weak self, weak h] in if let h = h { self?.deleteClient(h, m) } })) }
      if !edit.isEmpty { out.append(CornerMenuItem(title: "", inline: true, children: edit)) }
    } else if s.kind == "folder", let fid = s.folder, let f = folderInfo(m, fid) {
      if (f["canUpload"] as? Bool) == true { out.append(CornerMenuItem(title: "Upload", symbol: "arrow.up", run: { [weak self, weak h] in if let h = h { self?.upload(h, client: cid, folder: fid) } })) }
      if (f["canSub"] as? Bool) == true { out.append(CornerMenuItem(title: "New folder", symbol: "folder.badge.plus", run: { [weak self, weak h] in if let h = h { self?.newFolder(h, client: cid, parent: fid) } })) }
      let files = filesIn(m, fid)
      if !files.isEmpty {
        out.append(CornerMenuItem(title: "Select", symbol: "checkmark.circle", run: { [weak self, weak h] in guard let self = self, let h = h, let g = h.assetsParts["files"] as? FileTiles else { return }; g.selecting = true; self.blocks(h); h.setNeedsLayout() }))
        out.append(CornerMenuItem(title: "Download all", symbol: "arrow.down.circle", run: { [weak self, weak h] in if let h = h { self?.downloadMany(h, files, name: f["name"] as? String ?? "Files") } }))
      }
      if (f["canLink"] as? Bool) == true {
        out.append(CornerMenuItem(title: "Copy link", symbol: "link", run: { [weak self, weak h] in self?.main.copyFolderLink(client: cid, folder: fid) { t in h?.assetsToast(t) } }))
        let off = Main.linksOff.contains("d:\(cid)/\(fid)")
        if Main.isAdmin { out.append(CornerMenuItem(title: off ? "Turn on link" : "Turn off link", symbol: off ? "lock.open" : "lock", destructive: !off, run: { [weak self, weak h] in self?.main.folderLinkToggle(client: cid, folder: fid) { t in h?.assetsToast(t) } })) }
      }
      out.append(CornerMenuItem(title: "Info", symbol: "info.circle", run: { [weak self] in self?.folderInfoSheet(f, client: cid) }))
      var edit: [CornerMenuItem] = []
      if (f["canRename"] as? Bool) == true { edit.append(CornerMenuItem(title: "Rename folder", symbol: "pencil", run: { [weak self, weak h] in if let h = h { self?.renameFolder(h, f, client: cid) } })) }
      if (f["canDel"] as? Bool) == true { edit.append(CornerMenuItem(title: "Delete folder", symbol: "trash", destructive: true, run: { [weak self, weak h] in if let h = h { self?.deleteFolder(h, f, client: cid) } })) }
      if !edit.isEmpty { out.append(CornerMenuItem(title: "", inline: true, children: edit)) }
    }
    return out
  }

  // ---------- changes (done on the page, the website's way) ----------
  private func change(_ h: HomeView, _ ev: [String: Any], done: String?, then: (([String: Any]) -> Void)? = nil) {
    ask(ev) { [weak self, weak h] r in
      if (r["ok"] as? Bool) != true { UINotificationFeedbackGenerator().notificationOccurred(.error); h?.assetsToast(r["error"] as? String ?? "That didn’t work — try again"); return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      if let d = done { h?.assetsToast(d) }
      then?(r)
      _ = self
    }
  }
  private func prompt(_ h: HomeView, _ title: String, _ message: String?, value: String = "", placeholder: String, ok: String, _ run: @escaping (String) -> Void) {
    let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
    a.addTextField { t in t.text = value; t.placeholder = placeholder; t.autocapitalizationType = .sentences; t.clearButtonMode = .whileEditing }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    let go = UIAlertAction(title: ok, style: .default) { [weak a] _ in let v = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces); if !v.isEmpty { run(v) } }
    a.addAction(go); a.preferredAction = go
    main.topMost().present(a, animated: true)
  }
  private func confirm(_ h: HomeView, _ title: String, _ message: String, _ ok: String, _ run: @escaping () -> Void) {
    let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: ok, style: .destructive) { _ in run() })
    main.topMost().present(a, animated: true)
  }
  private func addClient(_ h: HomeView) {
    prompt(h, "Add client", "New clients start with Logos, Brand Guidelines, Fonts and Files folders.", placeholder: "e.g. Ford", ok: "Add client") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "addClient", "name": name], done: "Added \(name)") { [weak self] r in
        guard let self = self, let id = r["id"] as? String else { return }
        self.push(self.screen("client", id, nil), animated: true); self.ask(["ev": "want", "client": id]) { _ in }
      }
    }
  }
  private func newFolder(_ h: HomeView, client: String, parent: String?) {
    let m = models[client] ?? [:]
    let pname = parent.flatMap { folderInfo(m, $0)?["path"] as? String }
    prompt(h, "New folder", "In \(m["name"] as? String ?? "this client")\(pname.map { " › " + $0 } ?? "")", placeholder: parent == nil ? "e.g. Social templates" : "e.g. Summer campaign shoot", ok: "Create") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      var ev: [String: Any] = ["ev": "newFolder", "client": client, "name": name]; if let p = parent { ev["parent"] = p }
      self.change(h, ev, done: "Made “\(name)”")
    }
  }
  private func renameFolder(_ h: HomeView, _ f: [String: Any], client: String) {
    prompt(h, "Rename folder", nil, value: f["name"] as? String ?? "", placeholder: "Folder name", ok: "Save") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "renameFolder", "client": client, "folder": f["id"] as? String ?? "", "name": name], done: nil)
    }
  }
  private func deleteFolder(_ h: HomeView, _ f: [String: Any], client: String) {
    let subs = f["subs"] as? Int ?? 0, n = f["total"] as? Int ?? 0
    let what = [subs > 0 ? "\(subs) folder\(subs == 1 ? "" : "s")" : "", n > 0 ? "\(n) file\(n == 1 ? "" : "s")" : ""].filter { !$0.isEmpty }.joined(separator: " and ")
    confirm(h, "Delete “\(f["name"] as? String ?? "this folder")”?", "The folder\(what.isEmpty ? "" : " and everything in it (\(what))") moves to the Trash, where it can be restored within 30 days. Copies already pasted into tasks stay.", "Delete folder") { [weak self, weak h] in
      guard let self = self, let h = h else { return }
      let id = f["id"] as? String ?? ""
      self.change(h, ["ev": "deleteFolder", "client": client, "folder": id], done: "Deleted") { [weak self] _ in
        // (that folder's own screen, if it's open: gone)
        guard let self = self else { return }
        if let i = self.stack.firstIndex(where: { $0.folder == id }) { while self.stack.count > i + 1 { self.stack.removeLast().h.removeFromSuperview() }; self.pop() }
      }
    }
  }
  private func renameClient(_ h: HomeView, _ m: [String: Any]) {
    let id = m["id"] as? String ?? ""
    prompt(h, "Rename client", nil, value: m["name"] as? String ?? "", placeholder: "Client name", ok: "Save") { [weak self, weak h] name in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "renameClient", "client": id, "name": name], done: nil)
    }
  }
  private func deleteClient(_ h: HomeView, _ m: [String: Any]) {
    let id = m["id"] as? String ?? "", n = ((m["files"] as? [[String: Any]]) ?? []).count, nf = ((m["folders"] as? [[String: Any]]) ?? []).count
    confirm(h, "Delete \(m["name"] as? String ?? "this client")?", "This removes the client and its \(nf) folders\(n > 0 ? " and \(n) file\(n == 1 ? "" : "s") (moved to the Trash)" : ""). Files already pasted into tasks stay in those tasks.", "Delete client") { [weak self, weak h] in
      guard let self = self, let h = h else { return }
      self.change(h, ["ev": "deleteClient", "client": id], done: "Deleted \(m["name"] as? String ?? "")") { [weak self] _ in
        guard let self = self else { return }
        self.models[id] = nil
        if let i = self.stack.firstIndex(where: { $0.client == id }) { while self.stack.count > i + 1 { self.stack.removeLast().h.removeFromSuperview() }; self.pop() }
      }
    }
  }
  // Upload: iPhone's own Photos / Camera / Files, each file sent in pieces into the folder, then filed by the page
  private func upload(_ h: HomeView, client: String, folder: String) {
    guard !upBusy, let f = models[client].flatMap({ folderInfo($0, folder) }), let dir = f["dir"] as? String else { if upBusy { toast(h, "Still uploading — one moment") }; return }
    main.topMost().present(AttachSheetVC(light: light, title: "Upload to \(f["name"] as? String ?? "folder")") { [weak self, weak h] src in
      guard let self = self else { return }
      Picker.shared.pick(from: self.main.topMost(), single: false, source: src) { [weak self, weak h] r in
        guard let self = self else { return }
        let picked = ((r["files"] as? [[String: Any]]) ?? []).compactMap { x -> (URL, String)? in
          guard let tok = x["token"] as? String, let u = Picker.shared.url(tok) else { return nil }
          return (u, x["name"] as? String ?? "File")
        }
        guard !picked.isEmpty else { return }
        self.upBusy = true
        var sent: [[String: Any]] = []
        let total = picked.count
        func next(_ i: Int) {
          guard i < total else {
            self.upBusy = false
            guard !sent.isEmpty else { h?.assetsToast("Couldn’t upload — try again"); return }
            self.ask(["ev": "uploaded", "client": client, "folder": folder, "files": sent]) { [weak h] r in
              if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.assetsToast("Added \(sent.count) file\(sent.count == 1 ? "" : "s") to \(f["name"] as? String ?? "the folder")" + (sent.count < total ? " — \(total - sent.count) didn’t upload" : "")) }
              else { h?.assetsToast(r["error"] as? String ?? "That didn’t work — try again") }
            }
            return
          }
          let (url, name) = picked[i]
          let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
          Uploader.send(url, name: name, task: "", dest: dir, cookies: self.main.serverHome.cookies, progress: { p in
            h?.assetsToast("Uploading \(total > 1 ? "\(i + 1) of \(total)" : name)… \(Int(p * 100))%")
          }) { path in
            if let p = path { sent.append(["name": name, "path": p, "size": size]) }
            next(i + 1)
          }
        }
        h?.assetsToast("Uploading…")
        next(0)
      }
    }, animated: true)
  }
  // several files at once: one .zip from the server, then iPhone's own Save / Share sheet
  private func downloadMany(_ h: HomeView, _ files: [[String: Any]], name: String) {
    let paths = files.compactMap { $0["file"] as? String }
    guard !paths.isEmpty else { return }
    if files.count == 1 { main.downloadFile(files[0], from: main.topMost()) { [weak h] t in h?.assetsToast(t) }; return }
    h.assetsToast("Getting \(paths.count) files ready…")
    main.serverTask.request("/api/host/exportFiles", body: ["folder": name, "paths": paths], timeout: 120) { [weak self, weak h] j in
      guard let self = self, let url = j?["url"] as? String else { h?.assetsToast("Couldn’t download — try again"); return }
      self.main.downloadFile(["url": url, "name": name + ".zip"], from: self.main.topMost()) { t in h?.assetsToast(t) }
    }
  }

  // ---------- Info ----------
  private static func when(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let o = DateFormatter(); o.dateStyle = .medium; o.timeStyle = .short
    return o.string(from: d)
  }
  private func info(_ title: String, _ rows: [(String, String)], task: String? = nil) {
    let vc = AssetsInfoVC(title: title, rows: rows.filter { !$0.1.isEmpty })
    if let t = task { vc.openTask = { [weak self] in self?.main.openTaskPage(t, tab: "details", focus: "") } }
    let nav = FitNav(rootViewController: vc)
    nav.overrideUserInterfaceStyle = light ? .light : .dark
    nav.sheetPresentationController?.prefersGrabberVisible = true
    nav.prepare(width: main.view.bounds.width, bottom: main.view.safeAreaInsets.bottom)
    main.topMost().present(nav, animated: true)
  }
  // (the website's own rows — the same titles and values as its Info, Haris 2026-11-03)
  private func pageRows(_ x: [String: Any]) -> [(String, String)]? {
    guard let r = (x["info"] as? [String: Any])?["rows"] as? [[Any]], !r.isEmpty else { return nil }
    return r.compactMap { p in p.count >= 2 ? ("\(p[0])", "\(p[1])") : nil }
  }
  private func fileInfo(_ f: [String: Any]) {
    if let rows = pageRows(f) { info(f["name"] as? String ?? "File", rows, task: (f["info"] as? [String: Any])?["task"] as? String); return }
    info(f["name"] as? String ?? "File", [("Kind", f["label"] as? String ?? ""), ("Size", TaskPage.size(f["size"] as? Int ?? 0)), ("Where", f["where"] as? String ?? ""),
                                         ("Added by", f["by"] as? String ?? ""), ("Added", AssetsCtl.when(f["at"] as? String ?? ""))])
  }
  private func folderInfoSheet(_ f: [String: Any], client: String) {
    if let rows = pageRows(f) { info(f["name"] as? String ?? "Folder", rows); return }
    let m = models[client] ?? [:]
    let subs = f["subs"] as? Int ?? 0
    info(f["name"] as? String ?? "Folder", [("Kind", (f["final"] as? Bool) == true ? "Final files of a completed task" : "Folder"), ("Where", "\(m["name"] as? String ?? "") › \(f["path"] as? String ?? "")"),
                                           ("Folders", subs > 0 ? "\(subs)" : ""), ("Files", "\(f["total"] as? Int ?? 0)"), ("Size", TaskPage.size(f["size"] as? Int ?? 0)),
                                           ("Created by", f["by"] as? String ?? ""), ("Created", AssetsCtl.when(f["at"] as? String ?? ""))])
  }
  private func clientInfo(_ m: [String: Any]) {
    let files = (m["files"] as? [[String: Any]]) ?? []
    info(m["name"] as? String ?? "Client", [("Contents", m["sub"] as? String ?? ""), ("Size", TaskPage.size(files.reduce(0) { $0 + ($1["size"] as? Int ?? 0) })),
                                           ("Added by", m["by"] as? String ?? ""), ("Added", AssetsCtl.when(m["at"] as? String ?? ""))])
  }
}
