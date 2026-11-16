import UIKit

// ---------- the one ✕ every sheet uses (Haris, 2026-10-31 / 2026-11-01: "keep these things consistent") ----------
// A 44 pt Liquid Glass circle, xmark 15 pt semibold in the label colour, 16 from the sheet's right edge, level with its
// heading. Every sheet takes its ✕ from here — never its own.
enum SheetClose {
  static func make() -> UIButton {
    var c: UIButton.Configuration
    if #available(iOS 26.0, *) { c = .glass() } else { c = .gray() }
    c.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    c.cornerStyle = .capsule; c.baseForegroundColor = .label
    let b = UIButton(configuration: c)
    b.accessibilityLabel = "Close"
    return b
  }
  static let size: CGFloat = 44
}
