// Renders how macOS shows an app's icon (the system's own drawing, glass included) into PNG files.
//   swift preview.swift <App.app> <out-prefix>
import Cocoa
let args = CommandLine.arguments
let app = args[1], out = args[2]
func save(_ img: NSImage, _ path: String, _ size: CGFloat) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
  NSAppearance(named: look)!.performAsCurrentDrawingAppearance {
    let img = NSWorkspace.shared.icon(forFile: app)
    img.size = NSSize(width: 512, height: 512)
    save(img, "\(out)-\(name).png", 512)
  }
}
print("ok")
