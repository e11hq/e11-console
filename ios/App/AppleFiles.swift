import UIKit

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
  private var lines = 1, isFolder = true, picPath: String?, aspect: CGFloat = 1
  static let stripW: CGFloat = 92
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
    let col = NativeSheetVC.color(f["rgb"]) ?? .systemBlue
    let n = f["files"] as? Int ?? 0
    let s = "d|\(f["name"] ?? "")|\(n)|\(String(describing: f["rgb"]))|\(lines)"
    guard s != sig else { return }
    sig = s; info = f; isFolder = true; self.lines = lines; id = f["id"] as? String ?? ""
    pic.image = UIImage(systemName: "folder.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 52, weight: .regular))
    pic.tintColor = col; pic.backgroundColor = .clear; pic.layer.cornerRadius = 0; pic.layer.borderWidth = 0
    badge.isHidden = true; picPath = nil
    name.text = f["name"] as? String; name.numberOfLines = lines
    sub.text = "\(n) file\(n == 1 ? "" : "s")"
    accessibilityLabel = "\(name.text ?? "Folder"), folder, \(sub.text ?? "")"
    setNeedsLayout()
  }
  // a file: its own picture (the server's small one) in its own shape — else its type's badge in its colour
  func file(_ f: [String: Any], lines: Int, sizeText: String) {
    let s = "f|\(f["id"] ?? "")|\(f["name"] ?? "")|\(sizeText)|\(CommentCell.picURL(f) ?? "")|\(lines)"
    guard s != sig else { return }
    sig = s; info = f; isFolder = false; self.lines = lines; id = f["id"] as? String ?? ""
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
  static func height(width w: CGFloat, lines: Int) -> CGFloat { w * 0.82 + 6 + CGFloat(lines) * 16 + 15 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    let box = W * 0.82
    if isFolder {
      pic.frame = CGRect(x: (W - box) / 2, y: 0, width: box, height: box)
    } else {
      // (in its own shape, within the square — a photo wide, a document tall)
      let w = aspect >= 1 ? box : box * aspect, h = aspect >= 1 ? box / aspect : box
      pic.frame = CGRect(x: (W - w) / 2, y: (box - h), width: w, height: h)
    }
    badge.frame = pic.bounds
    name.frame = CGRect(x: 0, y: box + 6, width: W, height: CGFloat(lines) * 16)
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
