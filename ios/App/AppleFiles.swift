import UIKit
import QuickLook

/* Folders and files as the Files app's grid (Haris 2026-11-10, mock-up "Clients — with the rules", approved 12:33): the
   folder in its colour, or the file's own picture in its own shape (a photo wide, a document tall), its name centred under
   it (one line in a client's sideways row, up to two in a grid), its count or size under that. No card behind it.
   Apple's parts carry it: Apple's grid (the list's sections — a sideways-scrolling row on a client's page, three across in
   Client Assets), Apple's selection and ticks, Apple's hold menu with its lift, Apple's Quick Look on a tap. Ours, said
   plainly: this tile itself — Apple has no ready-made tile. */
final class FileTile: UIView {
  var id = ""
  var onTap: (() -> Void)?
  var menu: (() -> UIMenu?)?
  private(set) var sig = ""
  private(set) var info: [String: Any] = [:]
  private let pic = UIImageView(), badge = UILabel(), name = UILabel(), sub = UILabel(), tick = UIImageView()
  private var lines = 1, picPath: String?, aspect: CGFloat = 1
  private(set) var isFolder = true, isClient = false
  var key: String { (isClient ? "fc:" : isFolder ? "fd:" : "ff:") + id }   // (its identity in the list)
  static let stripW: CGFloat = 92
  // (held: Apple's lift on the picture itself — the folder or the file — as the Files app and Photos, not the tile's box;
  //  Haris 2026-11-10 15:32)
  var liftView: UIView { pic }
  var liftRadius: CGFloat { isFolder ? 4 : max(6, pic.layer.cornerRadius) }
  // (held: the lift's outline — a folder in its own shape, its tab and its body, so Apple's lift shadow follows the folder,
  //  not a box around it: a grey box showed behind a lifted folder, Haris 2026-11-10 17:08; a file: its picture's rounded shape)
  // (a folder: its outline read off Apple's folder picture itself — its tab, the tab's slope and its rounded corners exactly,
  //  in light and dark: drawn by hand the tab's slope was cut off, Haris 2026-11-10 17:54; drawn as a box, the lift showed a
  //  pale box around the folder in light, 2026-11-11 07:43)
  var liftPath: UIBezierPath {
    let b = pic.bounds
    guard isFolder, FileTile.folderOutline.count > 2 else { return UIBezierPath(roundedRect: b, cornerRadius: liftRadius) }
    let path = UIBezierPath()
    for (i, q) in FileTile.folderOutline.enumerated() {
      let pt = CGPoint(x: q.x * b.width, y: q.y * b.height)
      if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.close()
    return path
  }
  // the folder picture's outline, 0…1 across and down: its top edge left to right, then its bottom edge back
  static let folderOutline: [CGPoint] = {
    // (drawn afresh at a known size, so its pixels are its own — a cropped picture's may still be the whole one's)
    let img = folderImage.withTintColor(.black, renderingMode: .alwaysOriginal)
    guard img.size.width > 0 else { return [] }
    let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
    let size = CGSize(width: 200, height: (200 * img.size.height / img.size.width).rounded())
    let drawn = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    guard let cg = drawn.cgImage, let data = cg.dataProvider?.data, let px = CFDataGetBytePtr(data) else { return [] }
    let w = cg.width, h = cg.height, bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
    guard w > 1, h > 1, bpp >= 1 else { return [] }
    let on = { (x: Int, y: Int) -> Bool in px[y * bpr + x * bpp + (bpp - 1)] > 8 }
    var top: [CGPoint] = [], bottom: [CGPoint] = []
    let n = 96
    for i in 0...n {
      let x = min(w - 1, Int((Double(i) / Double(n) * Double(w - 1)).rounded()))
      guard let y0 = (0..<h).first(where: { on(x, $0) }), let y1 = (0..<h).reversed().first(where: { on(x, $0) }) else { continue }
      let fx = CGFloat(x) / CGFloat(w - 1)
      top.append(CGPoint(x: fx, y: CGFloat(y0) / CGFloat(h)))
      bottom.append(CGPoint(x: fx, y: CGFloat(y1 + 1) / CGFloat(h)))
    }
    return top + bottom.reversed()
  }()
  // (Apple's folder symbol with the room Apple leaves around it taken off — so the folder itself fills its 84 × 70, as the
  //  mock-up; with that room it came out about a fifth smaller than its name called for: Haris 2026-11-10 15:21)
  static let folderImage: UIImage = {
    guard let sym = UIImage(systemName: "folder.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)) else { return UIImage() }
    let full = UIGraphicsImageRenderer(size: sym.size).image { _ in sym.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero) }
    guard let cg = full.cgImage, let data = cg.dataProvider?.data, let px = CFDataGetBytePtr(data) else { return sym.withRenderingMode(.alwaysTemplate) }
    let w = cg.width, h = cg.height, bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h { for x in 0..<w where px[y * bpr + x * bpp + (bpp - 1)] > 8 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
    guard maxX > minX, maxY > minY, let crop = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return sym.withRenderingMode(.alwaysTemplate) }
    return UIImage(cgImage: crop, scale: full.scale, orientation: .up).withRenderingMode(.alwaysTemplate)
  }()
  // (the folders' colour: a lighter blue, closer to the Files app's — light and dark, switching by itself)
  static let folderBlue = Look.c(UIColor(red: 0x5A / 255, green: 0xA9 / 255, blue: 0xE6 / 255, alpha: 1), UIColor(red: 0x6C / 255, green: 0xB7 / 255, blue: 0xF0 / 255, alpha: 1))
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    pic.contentMode = .scaleAspectFit; pic.layer.cornerCurve = .continuous
    badge.font = .systemFont(ofSize: 12, weight: .bold); badge.textAlignment = .center
    name.font = .systemFont(ofSize: 13, weight: .medium); name.textAlignment = .center; name.lineBreakMode = .byTruncatingMiddle
    sub.font = .systemFont(ofSize: 12); sub.textColor = .secondaryLabel; sub.textAlignment = .center
    tick.contentMode = .center; tick.isHidden = true
    [pic, name, sub, tick].forEach { addSubview($0) }
    pic.addSubview(badge)
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  // a folder: its colour, its name, "14 files"
  func folder(_ f: [String: Any], lines: Int) {
    // (Apple's own folder, every folder the same, in the lighter folder blue — Haris 2026-11-10 14:00, 15:19)
    let col = FileTile.folderBlue
    let n = f["files"] as? Int ?? 0, subs = f["subs"] as? Int ?? 0, fin = (f["final"] as? Bool) == true
    let s = "d|\(f["name"] ?? "")|\(n)|\(subs)|\(fin)|\(lines)"
    guard s != sig else { return }
    sig = s; info = f; isFolder = true; isClient = false; self.lines = lines; id = f["id"] as? String ?? ""
    // (its colour drawn into the picture, as a file's picture: a tint goes grey while a sheet is up over the page — Apple
    //  greys tinted controls then, and a folder is content, not a control: Haris 2026-11-10 15:25)
    pic.contentMode = .scaleToFill; pic.tintColor = nil
    // (a picture's colour is fixed when it's made — set again for the phone's look, as Apple can't switch it by itself)
    pic.followLook("folder") { [weak pic] tc in pic?.image = FileTile.folderImage.withTintColor(col.resolvedColor(with: tc), renderingMode: .alwaysOriginal) }; pic.backgroundColor = .clear; pic.layer.cornerRadius = 0; pic.layer.borderWidth = 0
    badge.isHidden = true; picPath = nil
    name.text = f["name"] as? String; name.numberOfLines = lines
    // ("Final · 2 folders · 14 files", "Empty" — as Client Assets had it; a client's page: its files, counted through)
    let bits = [subs > 0 ? "\(subs) folder\(subs == 1 ? "" : "s")" : "", n > 0 ? "\(n) file\(n == 1 ? "" : "s")" : ""].filter { !$0.isEmpty }
    sub.text = (fin ? "Final · " : "") + (bits.isEmpty ? "Empty" : bits.joined(separator: " · "))
    accessibilityLabel = "\(name.text ?? "Folder"), folder, \(sub.text ?? "")"
    setNeedsLayout()
  }
  // a file: its own picture (the server's small one) in its own shape — else its type's badge in its colour
  func file(_ f: [String: Any], lines: Int, sizeText: String) {
    let s = "f|\(f["id"] ?? "")|\(f["name"] ?? "")|\(sizeText)|\(CommentCell.picURL(f) ?? "")|\(lines)"
    guard s != sig else { return }
    sig = s; info = f; isFolder = false; isClient = false; self.lines = lines; id = f["id"] as? String ?? ""
    let nm = f["name"] as? String ?? "File"
    let ext = (nm as NSString).pathExtension.uppercased()
    name.text = nm; name.numberOfLines = lines
    sub.text = sizeText
    pic.image = nil; pic.layer.cornerRadius = 6; pic.clipsToBounds = true
    pic.layer.borderWidth = 1 / UIScreen.main.scale
    pic.followLook("line") { [weak self] tc in self?.pic.layer.setBorder(.separator, tc) }
    let (bg, fg) = FileTile.colours(ext)
    pic.backgroundColor = bg; badge.textColor = fg; badge.text = ext.isEmpty ? "FILE" : String(ext.prefix(4)); badge.isHidden = false
    aspect = ["PDF", "DOC", "DOCX", "AI", "PSD", "PAGES"].contains(ext) ? 0.75 : ["MP4", "MOV", "M4V"].contains(ext) ? 16 / 9 : 1
    let p = CommentCell.picURL(f)
    picPath = p
    if let p = p {
      FeedLoader.shared.image(p) { [weak self] img in
        guard let self = self, self.picPath == p, let img = img else { return }
        // (the picture's own shape — a photo wide, a document tall)
        self.aspect = max(0.5, min(2, img.size.width / max(1, img.size.height)))
        UIView.transition(with: self.pic, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
          self.pic.image = img; self.pic.contentMode = .scaleAspectFill; self.badge.isHidden = true
        }
        self.setNeedsLayout()
      }
    }
    accessibilityLabel = "\(nm), \(sizeText)"
    setNeedsLayout()
  }
  // a client in All Client Assets (Haris 2026-11-10, mock-up 0 B — the Files app's grid, two across, no card): its logo whole on
  // its own background (LogoLook), or its colour with its name; the name and "4 folders · 1 file" centred under it
  func client(_ c: [String: Any]) {
    let s = "c|\(c["name"] ?? "")|\(c["sub"] ?? "")|\(c["logo"] ?? "")|\(String(describing: c["rgb"]))"
    guard s != sig else { return }
    sig = s; info = c; isFolder = false; isClient = true; lines = 1; id = c["id"] as? String ?? ""
    pic.image = nil; pic.layer.cornerRadius = 16; pic.clipsToBounds = true; pic.layer.borderWidth = 0; pic.contentMode = .scaleAspectFit
    pic.backgroundColor = NativeSheetVC.color(c["rgb"]) ?? .systemGray
    badge.isHidden = false; badge.textColor = .white; badge.font = .systemFont(ofSize: 20, weight: .bold)
    badge.adjustsFontSizeToFitWidth = true; badge.minimumScaleFactor = 0.5
    badge.text = (c["name"] as? String ?? "").uppercased()
    name.text = c["name"] as? String; name.numberOfLines = 1; name.font = .systemFont(ofSize: 15, weight: .semibold); name.lineBreakMode = .byTruncatingTail
    sub.text = c["sub"] as? String; sub.font = .systemFont(ofSize: 13)
    let p = c["logo"] as? String
    picPath = p
    if let p = p {
      FeedLoader.shared.image(p) { [weak self] img in
        guard let self = self, self.picPath == p, let img = img else { return }
        UIView.transition(with: self.pic, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
          LogoLook.put(img, key: p, in: self.pic); self.badge.isHidden = true
        }
      }
    }
    accessibilityLabel = "\(name.text ?? "Client"), \(sub.text ?? "")"
    setNeedsLayout()
  }
  static func clientHeight(width w: CGFloat) -> CGFloat { w * 0.625 + 8 + 20 + 17 }
  var picked = false { didSet { if picked != oldValue { paintTick() } } }
  var selecting = false { didSet { if selecting != oldValue { paintTick() } } }
  private func paintTick() {
    tick.isHidden = !selecting
    tick.image = UIImage(systemName: picked ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
    tick.tintColor = picked ? .systemBlue : .white
  }
  // (each kind's colours, the same in the grid and the rows)
  static func colours(_ ext: String) -> (UIColor, UIColor) {
    switch ext {
    case "PDF": return (.systemRed, .white)
    case "AI", "EPS": return (.systemOrange, .white)
    case "PSD": return (.systemBlue, .white)
    case "MP4", "MOV", "M4V": return (.systemGray4, .label)
    case "SVG": return (Look.c(UIColor(red: 0.12, green: 0.23, blue: 0.18, alpha: 1), UIColor(red: 0.85, green: 0.95, blue: 0.89, alpha: 1)), .systemGreen)
    default: return (.tertiarySystemFill, .secondaryLabel)
    }
  }
  // the tile's height for its width: the picture as wide as the tile (a folder a little less), then its words
  // (the picture's square — in the grid, as wide as its column (Haris 2026-11-10 17:21: the folders sat apart, 84 wide in a
  //  116 column — now only the grid's 10 between them, the page's 16 at its edges, as the search bar and the lists); in a
  //  client's sideways row, as before: 84 at most)
  static func box(_ w: CGFloat) -> CGFloat { w > stripW ? w - 4 : min(w * 0.82, 84) }
  // (a folder's picture is the folder's own shape, 84 × 70 — its name 6 under it, as the mock-up; a file's the square)
  static func picH(_ w: CGFloat, folder: Bool) -> CGFloat {
    guard folder else { return box(w) }
    let sz = folderImage.size   // (the folder's own shape — about 84 × 67)
    return (box(w) * (sz.width > 0 ? sz.height / sz.width : 70.0 / 84)).rounded()
  }
  static func height(width w: CGFloat, lines: Int, folder: Bool = false) -> CGFloat { picH(w, folder: folder) + 6 + CGFloat(lines) * 16 + 15 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    if isClient {
      let h = W * 0.625
      pic.frame = CGRect(x: 0, y: 0, width: W, height: h)
      badge.frame = pic.bounds.insetBy(dx: 12, dy: 0)
      name.frame = CGRect(x: 0, y: h + 8, width: W, height: 20)
      sub.frame = CGRect(x: 0, y: name.frame.maxY, width: W, height: 17)
      return
    }
    let box = FileTile.box(W)
    let ph = FileTile.picH(W, folder: isFolder)
    if isFolder {
      pic.frame = CGRect(x: (W - box) / 2, y: 0, width: box, height: ph)
    } else {
      // (in its own shape, within the square — a photo wide, a document tall)
      let w = aspect >= 1 ? box : box * aspect, h = aspect >= 1 ? box / aspect : box
      pic.frame = CGRect(x: (W - w) / 2, y: (box - h), width: w, height: h)
    }
    badge.frame = pic.bounds
    // (the name as tall as its words, up to its lines — the line under it right below, as the client page's row; the tile
    //  keeps its room for two lines, so its height never changes: Haris 2026-11-10 16:48, a one-line name sat in the
    //  middle of a two-line box and left a gap above "1 file")
    let nh = min(CGFloat(lines) * 16, max(16, ceil(name.sizeThatFits(CGSize(width: W, height: .greatestFiniteMagnitude)).height)))
    name.frame = CGRect(x: 0, y: ph + 6, width: W, height: nh)
    sub.frame = CGRect(x: 0, y: name.frame.maxY, width: W, height: 15)
    tick.frame = CGRect(x: pic.frame.maxX - 26, y: pic.frame.maxY - 26, width: 24, height: 24)
  }
}

// a cell of Apple's grid holding one tile — Apple's highlight dims it while pressed, as the Files app
final class TileCell: UICollectionViewCell {
  private weak var tile: FileTile?
  func show(_ t: FileTile) {
    if tile !== t { if let old = tile, old.superview === contentView { old.removeFromSuperview() }; tile = t }
    if t.superview !== contentView { contentView.addSubview(t) }
    isAccessibilityElement = true; accessibilityLabel = t.accessibilityLabel; accessibilityTraits = .button
    setNeedsLayout()
  }
  override var isHighlighted: Bool { didSet { UIView.animate(withDuration: isHighlighted ? 0.05 : 0.2) { self.contentView.alpha = self.isHighlighted ? 0.55 : 1 } } }
  override func layoutSubviews() {
    super.layoutSubviews()
    if let t = tile, t.superview === contentView { t.frame = contentView.bounds }
  }
}

/* A file as a row of Apple's list (Haris 2026-11-10, approved mock-up): Recently added, and what search found — on a
   client's Client Assets, All Client Assets and a client's page. Apple's own subtitle cell: the file's picture (or its
   type's badge in its colour), its name, the line under it (where it is, or its type and size). The words searched for
   carry search's wash; a found row has its own identity (`found`) so a wash never stays on a row after search. */
final class FileListRow: UIView, AppleRow {
  var id = ""
  var found = false
  var onTap: (() -> Void)?
  var menu: (() -> UIMenu?)?
  var onLook: (() -> Void)?   // (its picture came after it was drawn: its cell set again)
  private(set) var info: [String: Any] = [:]
  private(set) var rowContent = UIListContentConfiguration.subtitleCell()
  private(set) var rowSig = ""
  var rowHasAccessory: Bool { false }
  var rowChevron: Bool { isFolder }   // (a folder found opens, Apple's ›; a file opens in Quick Look)
  private(set) var isFolder = false
  var key: String { (found ? "fs" : "fr") + (isFolder ? "d:" : ":") + id }
  var rowLeading: Bool { false }
  var rowLate: Bool { false }
  func rowTapped() { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap?() }
  private var picPath: String?, pic: UIImage?, line = "", marks: [String] = []
  override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
  required init?(coder: NSCoder) { fatalError() }
  // a folder search found: the folder in its colour, its name, where it is and how many files (mock-up "Searching Client Assets")
  func setFolder(_ f: [String: Any], line: String, marks: [String], look L: HomeLook) {
    isFolder = true; info = f; id = f["id"] as? String ?? ""; self.line = line; self.marks = marks
    picPath = nil; pic = nil
    paint(L)
  }
  // the line under a file's name, as everywhere: where it is · its type · its size
  static func line(_ f: [String: Any], at: String) -> String {
    let ext = ((f["name"] as? String ?? "") as NSString).pathExtension.uppercased()
    return [at, ext, TaskPage.size(f["size"] as? Int ?? 0)].filter { !$0.isEmpty }.joined(separator: " · ")
  }
  // line: what's under the name; marks: the words searched for (none — no wash)
  func set(_ f: [String: Any], line: String, marks: [String], look L: HomeLook) {
    isFolder = false; info = f; id = f["id"] as? String ?? ""; self.line = line; self.marks = marks
    let p = CommentCell.picURL(f)
    if p != picPath {
      picPath = p; pic = nil
      if let p = p {
        var now = true
        FeedLoader.shared.image(p) { [weak self] img in
          guard let self = self, self.picPath == p, let img = img else { return }
          self.pic = FileListRow.thumb(img)
          if !now { self.paint(L); self.onLook?() }
        }
        now = false
      }
    }
    paint(L)
  }
  private func paint(_ L: HomeLook) {
    let nm = info["name"] as? String ?? "File"
    let sig = "\(isFolder)|\(nm)|\(line)|\(marks.joined(separator: ","))|\(pic != nil)|\(picPath ?? "")|\(String(describing: info["rgb"]))|\(L.key)"
    guard sig != rowSig else { return }
    rowSig = sig
    var cfg = UIListContentConfiguration.subtitleCell()
    let ext = (nm as NSString).pathExtension.uppercased()
    if isFolder {
      cfg.image = FileTile.folderImage.withTintColor(FileTile.folderBlue.resolvedColor(with: traitCollection), renderingMode: .alwaysOriginal)
      cfg.imageProperties.maximumSize = CGSize(width: 40, height: 32)
    } else { cfg.image = pic ?? FileListRow.badge(ext) }
    cfg.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
    cfg.imageProperties.maximumSize = CGSize(width: 44, height: 44)
    cfg.imageToTextPadding = 13
    cfg.attributedText = FileListRow.marked(nm, marks, font: .systemFont(ofSize: 16), color: L.title)
    cfg.textProperties.numberOfLines = 1; cfg.textProperties.lineBreakMode = .byTruncatingMiddle
    cfg.secondaryAttributedText = FileListRow.marked(line, marks, font: .systemFont(ofSize: 13), color: .secondaryLabel)
    cfg.secondaryTextProperties.numberOfLines = 1
    cfg.textToSecondaryTextVerticalPadding = 2
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    rowContent = cfg
    accessibilityLabel = "\(nm), \(line)"
  }
  // the words searched for, washed as everywhere in search (Find's wash)
  static func marked(_ s: String, _ marks: [String], font: UIFont, color: UIColor) -> NSAttributedString {
    let a = NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let ns = s as NSString
    for w in marks { for r in Find.ranges(w, ns) { a.addAttribute(.backgroundColor, value: Find.wash, range: r) } }
    return a
  }
  // (its picture, square with Apple's rounded corners)
  static func thumb(_ img: UIImage) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44)).image { _ in
      UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 44, height: 44), cornerRadius: 10).addClip()
      let s = img.size, k = max(44 / max(1, s.width), 44 / max(1, s.height))
      img.draw(in: CGRect(x: (44 - s.width * k) / 2, y: (44 - s.height * k) / 2, width: s.width * k, height: s.height * k))
    }.withRenderingMode(.alwaysOriginal)
  }
  // (no picture: its type's badge in its colour — the same colours as the grid's tiles; dynamic, so light / dark switch)
  static func badge(_ ext: String) -> UIImage {
    let (bg, fg) = FileTile.colours(ext)
    let t = ext.isEmpty ? "FILE" : String(ext.prefix(4))
    let draw = { (tc: UITraitCollection) -> UIImage in
      UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44)).image { _ in
        bg.resolvedColor(with: tc).setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 44, height: 44), cornerRadius: 10).fill()
        let f = UIFont.systemFont(ofSize: t.count > 3 ? 10 : 12, weight: .bold), sz = (t as NSString).size(withAttributes: [.font: f])
        (t as NSString).draw(at: CGPoint(x: (44 - sz.width) / 2, y: (44 - sz.height) / 2), withAttributes: [.font: f, .foregroundColor: fg.resolvedColor(with: tc)])
      }
    }
    let light = draw(UITraitCollection(userInterfaceStyle: .light)), dark = draw(UITraitCollection(userInterfaceStyle: .dark))
    // (both looks in one picture — iPhone shows the right one by itself, as an asset catalogue's)
    let a = UIImageAsset()
    a.register(light, with: UITraitCollection(userInterfaceStyle: .light)); a.register(dark, with: UITraitCollection(userInterfaceStyle: .dark))
    return a.image(with: UITraitCollection.current)
  }
}

/* Client Assets' files opened in Apple's own Quick Look (Haris 2026-11-10, approved): swipe sideways for the next and the
   one before, swipe down to close (it grows out of the tile or row tapped, and goes back into it), Apple's Share — the file
   itself. Each file fetched with the app's sign-in when it's about to show (the one tapped first, then those beside it),
   kept in one folder of the phone's caches while Quick Look is open and cleared when it closes. */
final class FilesLook: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  static weak var source: UIView?   // (the tile or row tapped — set by the list just before it opens)
  private static var shown: FilesLook?
  final class Item: NSObject, QLPreviewItem {
    let f: [String: Any], src: String
    var url: URL?, loading = false
    init(_ f: [String: Any]) { self.f = f; src = Main.previewItem(f)["src"] as? String ?? "" }
    var previewItemURL: URL? { url }
    var previewItemTitle: String? { f["name"] as? String }
  }
  private var items: [Item] = [], first = 0
  private weak var from: UIView?, q: QLPreviewController?
  private let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("quicklook-\(UUID().uuidString)", isDirectory: true)
  static func show(_ files: [[String: Any]], at i: Int, host: UIViewController, toast: @escaping (String) -> Void) {
    guard i < files.count else { return }
    let me = FilesLook()
    me.items = files.map(Item.init); me.first = i; me.from = source; source = nil
    try? FileManager.default.createDirectory(at: me.dir, withIntermediateDirectories: true)
    // (Quick Look opens at once, out of what was tapped — a file not on the phone yet shows Apple's spinner in it until it's
    //  there; never a toast of ours first: Haris 2026-11-11 07:47)
    let q = QLPreviewController(); q.dataSource = me; q.delegate = me; q.currentPreviewItemIndex = i
    me.q = q; shown = me
    host.present(q, animated: true)
    me.waiting(true)
    me.load(i) { ok in
      me.waiting(false)
      guard ok else {
        toast("Couldn’t open — try again")
        q.dismiss(animated: true) { try? FileManager.default.removeItem(at: me.dir); if shown === me { shown = nil } }
        return
      }
      me.load(i - 1) { _ in }; me.load(i + 1) { _ in }
    }
  }
  // Apple's spinner in the middle of Quick Look while the file on show is on its way
  private var spin: UIActivityIndicatorView?
  private func waiting(_ on: Bool) {
    guard on else { spin?.removeFromSuperview(); spin = nil; return }
    guard let v = q?.view, spin == nil else { return }
    let s = UIActivityIndicatorView(style: .large); s.hidesWhenStopped = true
    s.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(s)
    NSLayoutConstraint.activate([s.centerXAnchor.constraint(equalTo: v.centerXAnchor), s.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
    s.startAnimating(); spin = s
  }
  private func load(_ i: Int, _ done: @escaping (Bool) -> Void) {
    guard i >= 0, i < items.count else { return done(false) }
    let it = items[i]
    if it.url != nil { return done(true) }
    if it.loading { return }
    it.loading = true
    PreviewLoad.data(it.src) { [weak self] d in
      it.loading = false
      guard let self = self, let d = d else { return done(false) }
      let name = (it.f["name"] as? String ?? "File").replacingOccurrences(of: "/", with: "-")
      let sub = self.dir.appendingPathComponent("\(i)", isDirectory: true)
      try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
      let u = sub.appendingPathComponent(name)
      guard (try? d.write(to: u)) != nil else { return done(false) }
      it.url = u
      // (the one on show was waiting for it: shown now, the spinner gone)
      if let q = self.q, q.currentPreviewItemIndex == i { self.waiting(false); q.refreshCurrentPreviewItem() }
      done(true)
    }
  }
  func numberOfPreviewItems(in c: QLPreviewController) -> Int { items.count }
  func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem {
    // (about to show: it, and the ones beside it, fetched — Apple's spinner while the one on show is on its way)
    if items[i].url == nil, c.currentPreviewItemIndex == i { waiting(true) }
    load(i) { _ in }; load(i - 1) { _ in }; load(i + 1) { _ in }
    return items[i]
  }
  func previewController(_ c: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {
    (item as? Item) === items[first] ? from : nil
  }
  func previewControllerDidDismiss(_ c: QLPreviewController) {
    try? FileManager.default.removeItem(at: dir)
    FilesLook.shown = nil
  }
}
extension Main {
  // Client Assets' files (a client's page's search too): Apple's Quick Look
  func quickLook(_ files: [[String: Any]], at i: Int) {
    PreviewLoad.refreshCookies(web.configuration.websiteDataStore.httpCookieStore) { [weak self] in
      guard let self = self, let host = self.sheetHost() else { return }
      FilesLook.show(files, at: i, host: host) { [weak self] t in self?.shownScreen?.assetsToast(t) }
    }
  }
}

/* Apple's own empty state in the list (Haris 2026-11-10: "Apple's own empty-state views — Yes"): Apple's
   UIContentUnavailableConfiguration in a cell of the list — its symbol, its bold title, the grey line under it, centred —
   under what's above it (a client's folders and Open · Done), not over the page. "Loading…" is Apple's own loading view.
   (iOS 16: the line alone, as before.) */
final class AppleEmpty: UIView {
  private(set) var symbol: String?, title = "", line: String?, loading = false
  private(set) var sig = ""
  func set(_ symbol: String?, _ title: String, _ line: String? = nil) {
    self.symbol = symbol; self.title = title; self.line = line; loading = false
    sig = "\(symbol ?? "")|\(title)|\(line ?? "")"
  }
  func setLoading() { symbol = nil; title = "Loading…"; line = nil; loading = true; sig = "loading" }
  // its cell's content, set by the list
  func paint(_ cell: UICollectionViewListCell) {
    if #available(iOS 17.0, *) {
      var c: UIContentUnavailableConfiguration = loading ? .loading() : .empty()
      if !loading {
        c.image = symbol.flatMap { UIImage(systemName: $0) }
        c.text = title
        c.secondaryText = line
      }
      c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 28, leading: 24, bottom: 28, trailing: 24)
      cell.contentConfiguration = c
    } else {
      var c = UIListContentConfiguration.cell()
      c.text = [title, line].compactMap { $0 }.joined(separator: " — ")
      c.textProperties.font = .systemFont(ofSize: 14); c.textProperties.color = .secondaryLabel; c.textProperties.alignment = .center
      cell.contentConfiguration = c
    }
    cell.accessories = []
    var bg = UIBackgroundConfiguration.clear(); bg.backgroundColor = .clear
    cell.backgroundConfiguration = bg
  }
}
