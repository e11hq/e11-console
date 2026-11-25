import UIKit

/* Talk's chat bubble, its words and its time, laid out exactly as Talk's BubbleCell lays them (Chat.swift: the words 17 on a
   22 line, the room at their end as wide as the time + 10, the words measured at the screen's width × 281/393 − 23 on
   yours, 12 in / 11 out, the time 11 from the right and 6 from the bottom) — for every minute of an hour and two texts,
   at the iPhone sizes, and says where the time sits on the words. Measuring only (Haris 2026-11-25 20:57). */
enum Ticks {
  static let size = CGSize(width: 17, height: 11)
  static func image(_ c: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { _ in
      let p = UIBezierPath()
      p.move(to: CGPoint(x: 1.6, y: 6.1)); p.addLine(to: CGPoint(x: 4.6, y: 9.1)); p.addLine(to: CGPoint(x: 11.2, y: 1.7))
      p.move(to: CGPoint(x: 7.4, y: 8.3)); p.addLine(to: CGPoint(x: 8.2, y: 9.1)); p.addLine(to: CGPoint(x: 15.4, y: 1.7))
      p.lineWidth = 1.35; c.setStroke(); p.stroke()
    }
  }
}
let clear = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }

final class Bubble: UIView {
  let textL = UILabel(), stamp = UILabel(), stack = UIStackView()
  init(screenW: CGFloat, text: String, time: String) {
    super.init(frame: .zero)
    backgroundColor = UIColor(red: 0.2, green: 0.36, blue: 0.65, alpha: 1); layer.cornerRadius = 18
    textL.font = .systemFont(ofSize: 17); textL.numberOfLines = 0; textL.textColor = .white
    stamp.font = .systemFont(ofSize: 12); stamp.textAlignment = .right
    let f = NSMutableAttributedString(string: time, attributes: [.foregroundColor: UIColor(white: 1, alpha: 0.7), .font: UIFont.systemFont(ofSize: 12)])
    f.append(NSAttributedString(string: " "))
    let t = NSTextAttachment(image: Ticks.image(.white)); t.bounds = CGRect(x: 0, y: -1, width: Ticks.size.width, height: Ticks.size.height)
    f.append(NSAttributedString(attachment: t))
    stamp.attributedText = f
    textL.preferredMaxLayoutWidth = screenW * 281 / 393 - 23
    let a = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.white])
    let room = NSTextAttachment(image: clear); room.bounds = CGRect(x: 0, y: 0, width: ceil(stamp.intrinsicContentSize.width) + 10, height: 1)
    a.append(NSAttributedString(attachment: room))
    let ps = NSMutableParagraphStyle(); ps.minimumLineHeight = 22; ps.maximumLineHeight = 22
    a.addAttributes([.paragraphStyle: ps, .baselineOffset: (22 - UIFont.systemFont(ofSize: 17).lineHeight) / 4], range: NSRange(location: 0, length: a.length))
    textL.attributedText = a
    stack.axis = .vertical; stack.addArrangedSubview(textL)
    addSubview(stack); addSubview(stamp)
    for v in [stack, stamp] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
      stamp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11), stamp.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  // the words as UILabel itself draws them (the time hidden): how many of their pixels fall where the time sits
  func wordsUnderTime() -> Int {
    stamp.isHidden = true; backgroundColor = .black
    let f = UIGraphicsImageRendererFormat(); f.scale = 3
    let img = UIGraphicsImageRenderer(bounds: bounds, format: f).image { c in layer.render(in: c.cgContext) }
    stamp.isHidden = false; backgroundColor = UIColor(red: 0.2, green: 0.36, blue: 0.65, alpha: 1)
    guard let cg = img.cgImage, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return -1 }
    let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
    let r = stamp.frame.insetBy(dx: 1, dy: 1)
    var n = 0
    for y in Int(r.minY * 3)..<Int(r.maxY * 3) { for x in Int(r.minX * 3)..<Int(r.maxX * 3) {
      let i = y * bpr + x * bpp; if p[i] > 128 || p[i + 1] > 128 || p[i + 2] > 128 { n += 1 }
    } }
    return n
  }
  // where the words' last letter ends, in the bubble (TextKit, at the label's own width)
  func wordsEnd(_ text: String) -> (end: CGFloat, lines: Int, roomLine: Int) {
    let s = NSTextStorage(attributedString: textL.attributedText!), lm = NSLayoutManager(), tc = NSTextContainer(size: CGSize(width: textL.bounds.width, height: .greatestFiniteMagnitude))
    tc.lineFragmentPadding = 0; lm.addTextContainer(tc); s.addLayoutManager(lm); lm.ensureLayout(for: tc)
    let n = (text as NSString).length
    let last = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: n - 1, length: 1), actualCharacterRange: nil), in: tc)
    let room = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: n, length: 1), actualCharacterRange: nil), in: tc)
    var lines = 0, i = 0
    while i < lm.numberOfGlyphs { var r = NSRange(); lm.lineFragmentRect(forGlyphAt: i, effectiveRange: &r); lines += 1; i = NSMaxRange(r) }
    return (textL.frame.minX + stack.frame.minX + last.maxX, lines, room.minY > last.minY + 5 ? 2 : 1)
  }
}

final class VC: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    var out = "screen bubble-max text time | bubbleW textW labelLines(drawn) roomOnLine wordsEndX stampMinX overlap\n"
    var shots: [(String, Bubble)] = []
    for screenW in [393.0, 402.0, 390.0] as [CGFloat] {
      for text in ["Blue or red? Check again", "Red or blue? Check again"] {
        for h in [8] { for mi in 0..<60 {
          let time = String(format: "%d:%02d PM", h, mi)
          let b = Bubble(screenW: screenW, text: text, time: time)
          // (the bubble as wide as its words want, at most the widest — Talk's bubble hugs its words)
          let widest = screenW * 281 / 393
          b.translatesAutoresizingMaskIntoConstraints = false
          view.addSubview(b)
          let w = b.widthAnchor.constraint(lessThanOrEqualToConstant: widest); w.isActive = true
          b.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10).isActive = true
          b.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
          view.layoutIfNeeded()
          let e = b.wordsEnd(text)
          let ink = b.wordsUnderTime()
          let overlap = ink > 0
          out += "\(screenW) \(widest) \(text) \(time) | \(b.frame.width) \(b.textL.frame.width) \(e.lines) \(e.roomLine) \(String(format: "%.1f", e.end)) \(String(format: "%.1f", b.stamp.frame.minX)) \(overlap ? "OVERLAP" : "ok") (\(ink) word pixels under the time; label h \(b.textL.frame.height))\n"
          if (time == "8:41 PM" || time == "8:53 PM") && screenW == 393 { shots.append(("\(text)-\(time)", b)) } else { b.removeFromSuperview() }
        } }
      }
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? out.write(to: docs.appendingPathComponent("bubbles.txt"), atomically: true, encoding: .utf8)
    // the four at 393 drawn one under the other, for the picture
    for (i, s) in shots.enumerated() { s.1.frame.origin.y += CGFloat(i) * 70; s.1.transform = CGAffineTransform(translationX: 0, y: CGFloat(i) * 70) }
    let label = UILabel(frame: CGRect(x: 10, y: 400, width: 380, height: 100)); label.numberOfLines = 0; label.font = .systemFont(ofSize: 11)
    label.text = shots.map { $0.0 }.joined(separator: "\n"); view.addSubview(label)
    try? "done".write(to: docs.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
  }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds); let v = VC(); v.view.backgroundColor = .black; window?.rootViewController = v; window?.makeKeyAndVisible(); return true
  }
}
