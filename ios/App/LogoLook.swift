import UIKit

/* A client's logo in its tile, everywhere (Haris 2026-11-08: "their logo's fit the thumbnail … not cut, with little
   spacing on the sides"): the whole logo, as large as the tile lets it be, with a small margin — never cropped. Its tile:
   · a logo with its own background (its edges solid): that colour, so the logo reads edge to edge;
   · a transparent logo: by its ink — a light logo on a dark tile, a dark one on a white tile.
   Worked out once per logo (a 32 × 32 look at it) and kept. */
enum LogoLook {
  private final class Look { let image: UIImage; let bg: UIColor; init(_ i: UIImage, _ b: UIColor) { image = i; bg = b } }
  private static let cache = NSCache<NSString, Look>()
  static let darkTile = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)

  // the logo into its tile: the margin drawn round it, the tile's colour set, fitted whole
  static func put(_ img: UIImage, key: String?, in v: UIImageView) {
    let l = look(img, key: key)
    v.contentMode = .scaleAspectFit
    v.backgroundColor = l.bg
    v.image = l.image
  }

  // the logo drawn into its tile as one picture (an Apple cell's image — the Clients list, Haris 2026-11-10)
  static func tile(_ img: UIImage, key: String?, side: CGFloat, radius: CGFloat) -> UIImage {
    let l = look(img, key: key)
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
      let r = CGRect(x: 0, y: 0, width: side, height: side)
      UIBezierPath(roundedRect: r, cornerRadius: radius).addClip()
      l.bg.setFill(); UIRectFill(r)
      let s = l.image.size, k = min(side / max(1, s.width), side / max(1, s.height))
      let w = s.width * k, h = s.height * k
      l.image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    }.withRenderingMode(.alwaysOriginal)
  }
  private static func look(_ img: UIImage, key: String?) -> Look {
    if let k = key, let l = cache.object(forKey: k as NSString) { return l }
    let l = Look(padded(img), background(img))
    if let k = key { cache.setObject(l, forKey: k as NSString) }
    return l
  }
  // (a margin of a tenth of its longer side all round — transparent, so the tile's colour shows there)
  private static func padded(_ img: UIImage) -> UIImage {
    let s = img.size
    guard s.width > 0, s.height > 0 else { return img }
    let p = max(s.width, s.height) * 0.1
    let f = UIGraphicsImageRendererFormat(); f.scale = img.scale; f.opaque = false
    return UIGraphicsImageRenderer(size: CGSize(width: s.width + p * 2, height: s.height + p * 2), format: f).image { _ in
      img.draw(in: CGRect(x: p, y: p, width: s.width, height: s.height))
    }
  }
  private static func background(_ img: UIImage) -> UIColor {
    let n = 32
    guard let cg = img.cgImage else { return .white }
    var px = [UInt8](repeating: 0, count: n * n * 4)
    let ok: Bool = px.withUnsafeMutableBytes { buf in
      guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      ctx.interpolationQuality = .medium
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
      return true
    }
    guard ok else { return .white }
    // its edges: solid all round — the logo's own background, its colour
    var er = 0.0, eg = 0.0, eb = 0.0, ea = 0.0, en = 0.0
    for y in 0..<n { for x in 0..<n where x == 0 || y == 0 || x == n - 1 || y == n - 1 {
      let i = (y * n + x) * 4
      let a = Double(px[i + 3]) / 255
      ea += a; en += 1
      if a > 0 { er += Double(px[i]) / 255 / a; eg += Double(px[i + 1]) / 255 / a; eb += Double(px[i + 2]) / 255 / a }
    } }
    if en > 0, ea / en > 0.92 {
      let k = max(ea, 1)
      return UIColor(red: CGFloat(min(1, er / k)), green: CGFloat(min(1, eg / k)), blue: CGFloat(min(1, eb / k)), alpha: 1)
    }
    // transparent: by its ink — light on dark, dark on white
    var lum = 0.0, w = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
      let a = Double(px[i + 3]) / 255
      guard a > 0.5 else { continue }
      let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
      lum += (0.2126 * r + 0.7152 * g + 0.0722 * b) * a; w += a
    }
    guard w > 0 else { return .white }
    return lum / w > 0.62 ? darkTile : .white
  }
}
