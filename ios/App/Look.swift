import UIKit
import ObjectiveC

/* ================= Light and dark, Apple's way (Haris 2026-11-09: "Yes, start") =================
   The app follows the phone's look and nothing of ours forces one: our colours are Apple's dynamic colours — each holds
   both looks, as the system colours do — so iPhone switches every screen itself, in its own fade, with nothing drawn
   again. Only what Apple can't switch by itself (a layer's border or shadow colour, a blur's style, a picture) is set
   again when the look changes (followLook). Before: the app repainted its screens with fixed colours after the website
   inside it said which look it was (setAppearance → relight), and screens it didn't reach stayed in the old look. */
enum Look {
  // one colour for both looks
  static func c(_ dark: UIColor, _ light: UIColor) -> UIColor { UIColor { $0.userInterfaceStyle == .light ? light : dark } }
  // white on dark, black on light (the ink of our buttons' words and icons)
  static let ink = c(.white, .black)
  static let inkInverse = c(.black, .white)
}

private var lookKey: UInt8 = 0
private final class LookFollowers { var list: [String: (UITraitCollection) -> Void] = [:]; var watching = false }
extension UIView {
  // what Apple can't switch by itself: set now and again whenever the look changes (Apple's trait change)
  func followLook(_ key: String, _ apply: @escaping (UITraitCollection) -> Void) {
    let f: LookFollowers
    if let x = objc_getAssociatedObject(self, &lookKey) as? LookFollowers { f = x } else { f = LookFollowers(); objc_setAssociatedObject(self, &lookKey, f, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    f.list[key] = apply
    if !f.watching {
      f.watching = true
      if #available(iOS 17.0, *) {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (v: UIView, _: UITraitCollection) in
          (objc_getAssociatedObject(v, &lookKey) as? LookFollowers)?.list.values.forEach { $0(v.traitCollection) }
        }
      }   // (iOS 16: set as it's drawn — the look then changes with the next drawing)
    }
    apply(traitCollection)
  }
}
extension CALayer {
  // a layer's colours (border, shadow) in the look of the view it's on — set again by followLook
  func setBorder(_ c: UIColor, _ tc: UITraitCollection) { borderColor = c.resolvedColor(with: tc).cgColor }
}
