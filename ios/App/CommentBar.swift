import UIKit

/* Attach Files: "Attach Files" over three big rounded tiles — Camera · Photos · Files — with a Liquid Glass ✕ at the top
   right. The one attach sheet of the app (the comment box's +, a Home card held, and any to come). */
final class AttachSheetVC: UIViewController, UISheetPresentationControllerDelegate {
  private let pick: (String) -> Void
  private let heading: String?
  var onCancel: (() -> Void)?
  // (every attach sheet is the same: "Attach Files", a glass ✕, Camera · Photos · Files — Haris, 2026-10-31)
  init(title: String? = "Attach Files", pick: @escaping (String) -> Void) {
    self.pick = pick
    self.heading = title
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController {
      let h: CGFloat = title == nil ? 150 : 194
      sh.detents = [.custom(identifier: .init("attach")) { _ in h }]
      sh.prefersGrabberVisible = true
      sh.delegate = self
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { onCancel?() }
  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26, *) { view.backgroundColor = .clear } else { view.backgroundColor = .systemGroupedBackground }
    let row = UIStackView(); row.axis = .horizontal; row.spacing = 10; row.distribution = .fillEqually
    for (src, sym, title) in [("camera", "camera", "Camera"), ("photos", "photo", "Photos"), ("files", "doc.badge.arrow.up", "Files")] {
      var c = UIButton.Configuration.filled()
      c.baseBackgroundColor = .tertiarySystemFill
      c.baseForegroundColor = .label
      c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
      c.imagePlacement = .top
      c.imagePadding = 10
      c.title = title
      c.background.cornerRadius = 22
      c.cornerStyle = .fixed
      let b = UIButton(configuration: c)
      b.addAction(UIAction { [weak self] _ in
        guard let self else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        let p = self.pick
        self.dismiss(animated: true) { p(src) }
      }, for: .touchUpInside)
      row.addArrangedSubview(b)
    }
    row.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(row)
    var top: CGFloat = 28
    if let h = heading {
      let l = UILabel(); l.text = h; l.font = .systemFont(ofSize: 17, weight: .semibold); l.textAlignment = .center; l.textColor = .label
      l.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(l)
      NSLayoutConstraint.activate([l.topAnchor.constraint(equalTo: view.topAnchor, constant: 24), l.centerXAnchor.constraint(equalTo: view.centerXAnchor)])
      top = 66
      // a Liquid Glass ✕ at the top right, level with the heading, that closes it (Haris, 2026-10-31)
      let x = SheetClose.make()
      x.addAction(UIAction { [weak self] _ in
        guard let self else { return }
        let cancel = self.onCancel
        self.dismiss(animated: true) { cancel?() }
      }, for: .touchUpInside)
      x.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(x)
      NSLayoutConstraint.activate([x.widthAnchor.constraint(equalToConstant: 44), x.heightAnchor.constraint(equalToConstant: 44),
        x.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), x.centerYAnchor.constraint(equalTo: l.centerYAnchor)])
    }
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: view.topAnchor, constant: top),
      row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      row.heightAnchor.constraint(equalToConstant: 100),
    ])
  }
}


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
