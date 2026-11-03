// A one-off mockup (Haris 2026-11-04): the comment reactions as emoji (now) and as SF Symbols — light and dark.
import AppKit

let W: CGFloat = 1440, H: CGFloat = 900
let img = NSImage(size: NSSize(width: W, height: H))
let emojis = ["👍", "✅", "🎉", "❤️", "👀", "🙏"]
let syms: [(String, NSColor)] = [("hand.thumbsup.fill", .systemBlue), ("checkmark.circle.fill", .systemGreen), ("party.popper.fill", .systemOrange),
                                 ("heart.fill", .systemRed), ("eyes", .systemPurple), ("hands.clap.fill", .systemYellow)]
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: NSColor, bold: Bool = false) {
  let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: c]
  (s as NSString).draw(at: NSPoint(x: x, y: H - y - size * 1.25), withAttributes: a)
}
func rr(_ r: NSRect, _ rad: CGFloat, _ c: NSColor) { c.setFill(); NSBezierPath(roundedRect: NSRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height), xRadius: rad, yRadius: rad).fill() }
func sym(_ name: String, _ c: NSColor, _ size: CGFloat, center: NSPoint) {
  guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { text("?", center.x - 6, center.y - 10, 18, .red); return }
  var cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
  cfg = cfg.applying(NSImage.SymbolConfiguration(paletteColors: [c]))
  let s = base.withSymbolConfiguration(cfg) ?? base
  let sz = s.size
  s.draw(in: NSRect(x: center.x - sz.width / 2, y: H - center.y - sz.height / 2, width: sz.width, height: sz.height))
}
func emoji(_ e: String, _ size: CGFloat, center: NSPoint) {
  let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size)]
  let sz = (e as NSString).size(withAttributes: a)
  (e as NSString).draw(at: NSPoint(x: center.x - sz.width / 2, y: H - center.y - sz.height / 2), withAttributes: a)
}
img.lockFocus()
NSColor(calibratedRed: 0.85, green: 0.86, blue: 0.88, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
text("Comment reactions — emoji (now) vs SF Symbols (mockup)", 40, 28, 26, .black, bold: true)
text("Touch and hold a comment: the row on top of its sheet; under a comment: the small counts. Real SF Symbols, iPhone's colours.", 40, 66, 15, .darkGray)
for (i, dark) in [false, true].enumerated() {
  let x0: CGFloat = 40 + CGFloat(i) * 700, y0: CGFloat = 110
  let bg = dark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.97, alpha: 1)
  let ink = dark ? NSColor.white : NSColor.black, sub = dark ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.45, alpha: 1)
  let chip = dark ? NSColor(white: 0.2, alpha: 1) : NSColor(white: 0.9, alpha: 1)
  rr(NSRect(x: x0, y: y0, width: 660, height: 760), 34, bg)
  text(dark ? "Dark" : "Light", x0 + 28, y0 + 22, 18, ink, bold: true)
  for (j, now) in [true, false].enumerated() {
    let y = y0 + 70 + CGFloat(j) * 340
    text(now ? "Now — emoji" : "SF Symbols", x0 + 28, y, 15, sub, bold: true)
    // the sheet's row
    rr(NSRect(x: x0 + 24, y: y + 30, width: 612, height: 96), 28, chip.withAlphaComponent(0.6))
    for k in 0..<6 {
      let cx = x0 + 24 + 52 + CGFloat(k) * 101, cy = y + 78
      rr(NSRect(x: cx - 34, y: cy - 34, width: 68, height: 68), 34, dark ? NSColor(white: 0.26, alpha: 1) : .white)
      if now { emoji(emojis[k], 32, center: NSPoint(x: cx, y: cy)) } else { sym(syms[k].0, syms[k].1, 28, center: NSPoint(x: cx, y: cy)) }
    }
    // a comment with its counts
    let cy0 = y + 150
    rr(NSRect(x: x0 + 24, y: cy0, width: 44, height: 44), 22, .systemIndigo)
    text("SA", x0 + 33, cy0 + 10, 16, .white, bold: true)
    text("Sara", x0 + 82, cy0, 16, ink, bold: true); text("· 9:14 AM", x0 + 124, cy0, 15, sub)
    text("First cut is up — can you check the music in reel 2?", x0 + 82, cy0 + 24, 17, ink)
    var cx = x0 + 82
    for (k, n) in [(0, 2), (3, 1), (4, 3)] {
      rr(NSRect(x: cx, y: cy0 + 62, width: 70, height: 34), 17, chip)
      if now { emoji(emojis[k], 18, center: NSPoint(x: cx + 22, y: cy0 + 79)) } else { sym(syms[k].0, syms[k].1, 15, center: NSPoint(x: cx + 22, y: cy0 + 79)) }
      text("\(n)", cx + 40, cy0 + 69, 16, ink, bold: true)
      cx += 80
    }
  }
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("ok")
