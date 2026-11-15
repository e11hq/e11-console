// Draws SF Symbols as Talk's message box shows them, for choosing one (Haris 2026-11-15: the smiley) — run on a Mac.
import AppKit
let names: [(String, NSFont.Weight, String)] = [("face.smiling", .regular, "now · face.smiling regular"), ("face.smiling", .light, "1 · face.smiling light"),
                                                 ("face.smiling", .ultraLight, "1b · face.smiling ultralight"), ("face.dashed", .light, "2 · face.dashed light"), ("face.dashed", .regular, "2b · face.dashed regular")]
let s: CGFloat = 3, W: CGFloat = 360, rowH: CGFloat = 60
for (look, bg, field, ink) in [("dark", NSColor.black, NSColor(white: 0.16, alpha: 1), NSColor.white), ("light", NSColor.white, NSColor(white: 0.94, alpha: 1), NSColor.black)] {
  let H = rowH * CGFloat(names.count) + 20
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * s), pixelsHigh: Int(H * s), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: W, height: H)
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  bg.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
  for (i, (n, w, label)) in names.enumerated() {
    let y = H - 10 - rowH * CGFloat(i + 1) + 14
    field.setFill(); NSBezierPath(roundedRect: NSRect(x: 12, y: y, width: 150, height: 32), xRadius: 15, yRadius: 15).fill()
    let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: w).applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
    if let img = NSImage(systemSymbolName: n, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
      let r = NSRect(x: 12 + 150 - 34 + (32 - img.size.width) / 2, y: y + (32 - img.size.height) / 2, width: img.size.width, height: img.size.height)
      img.draw(in: r)
    }
    (label as NSString).draw(at: NSPoint(x: 176, y: y + 8), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: ink.withAlphaComponent(0.7)])
  }
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/smiley-\(look).png"))
}

// Apple's outline smiley as the Mac draws it (face.smiling, regular, 15 pt), kept as Talk's own template picture (@2x, @3x)
// for the box — the iPhone's newer system draws the same symbol as a solid face (Haris 2026-11-15: "a regular in your
// picture is good")
for k in [2, 3] {
  let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular).applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
  let img = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
  let sz = img.size
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((sz.width * CGFloat(k)).rounded(.up)), pixelsHigh: Int((sz.height * CGFloat(k)).rounded(.up)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = sz
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSColor.clear.setFill(); NSRect(origin: .zero, size: sz).fill()
  img.draw(in: NSRect(origin: .zero, size: sz))
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/smile-line@\(k)x.png"))
  print("smile-line @\(k)x", sz)
}
