import UIKit
import AVFoundation
import CoreImage

/* A test page for now (Haris 2026-11-22 16:49): the last video sent — how long each step took, and the previews Talk made for
   it with how bright they are — to find out why a video waits after it's up and why an HDR video's previews are dark.
   Reached by tapping Version five times in About. To be taken out once those are found. */
enum Diag {
  private(set) static var steps: [(String, Double)] = []
  private(set) static var pictures: [(String, UIImage, Double)] = []
  private static var t0: Double = 0
  static var videoId: String?   // (the last video sent, under its server id — its bubble's frame)
  // a new video being sent: everything starts again
  static func start() { DispatchQueue.main.async { steps = []; pictures = []; videoId = nil; t0 = CACurrentMediaTime(); steps.append(("Send tapped", 0)) } }
  static func mark(_ what: String) {
    let t = CACurrentMediaTime()
    DispatchQueue.main.async { guard t0 > 0 else { return }; steps.append((what, t - t0)) }
  }
  static func picture(_ what: String, _ cg: CGImage?) {
    guard let cg = cg else { return }
    let b = brightness(cg)
    DispatchQueue.main.async { if !pictures.contains(where: { $0.0 == what }) { pictures.append((what, UIImage(cgImage: cg), b)) } }
  }
  static func note(_ s: String) { DispatchQueue.main.async { guard t0 > 0 else { return }; steps.append(("· " + s, CACurrentMediaTime() - t0)) } }
  // the same frame of Talk's copy, four ways — to see which is right on the phone itself
  static func variants(_ url: URL) {
    guard t0 > 0, !pictures.contains(where: { $0.0.hasPrefix("A ") }) else { return }
    // (with its name ending in .mp4 — iPhone's video tools may need it)
    let named = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).mp4")
    try? FileManager.default.copyItem(at: url, to: named)
    let a = AVURLAsset(url: named)
    let at = CMTime(seconds: 0.1, preferredTimescale: 600)
    func gen(_ comp: Bool) -> CGImage? {
      let g = AVAssetImageGenerator(asset: a); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 320, height: 320)
      g.requestedTimeToleranceBefore = .positiveInfinity; g.requestedTimeToleranceAfter = .positiveInfinity
      if comp { let c = AVMutableVideoComposition(propertiesOf: a); c.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2; c.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2; c.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2; g.videoComposition = c }
      return try? g.copyCGImage(at: at, actualTime: nil)
    }
    picture("A plain frame", gen(false))
    picture("B standard colour as taken (Talk up to 247)", gen(true))
    if let p = gen(false) {
      var img = CIImage(cgImage: p)
      if #available(iOS 18.0, *), let t = CIFilter(name: "CIToneMapHeadroom") { t.setValue(img, forKey: kCIInputImageKey); t.setValue(1.0, forKey: "inputTargetHeadroom"); if let o = t.outputImage { img = o } }
      picture("C plain, toned down by Core Image", CIContext().createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
    }
    // D: the first frame read as the video itself is played, turned to standard colour by Core Image
    if let r = try? AVAssetReader(asset: a), let t = a.tracks(withMediaType: .video).first {
      let o = AVAssetReaderTrackOutput(track: t, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
      if r.canAdd(o) { r.add(o); r.startReading()
        if let sb = o.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) {
          var img = CIImage(cvPixelBuffer: pb)
          if #available(iOS 18.0, *), let f = CIFilter(name: "CIToneMapHeadroom") { f.setValue(img, forKey: kCIInputImageKey); f.setValue(1.0, forKey: "inputTargetHeadroom"); if let x = f.outputImage { img = x } }
          img = img.transformed(by: CGAffineTransform(scaleX: 320 / max(img.extent.width, img.extent.height), y: 320 / max(img.extent.width, img.extent.height)))
          picture("D as played, toned down by Core Image (Talk now)", CIContext().createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        }
        r.cancelReading()
      }
    }
    try? FileManager.default.removeItem(at: named)
  }
  static func picture(_ what: String, base64: String?) {
    guard let s = base64, let d = Data(base64Encoded: s), let i = UIImage(data: d), let cg = i.cgImage else { return }
    picture(what, cg)
  }
  // the mean brightness (0–255) as a standard screen shows it — the same measure as the Mac test (160 right, 92 dark)
  static func brightness(_ cg: CGImage) -> Double {
    let w = 64, h = max(1, Int(Double(cg.height) / Double(max(1, cg.width)) * 64))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var s = 0.0; for i in 0..<(w * h) { s += 0.2126 * Double(p[i * 4]) + 0.7152 * Double(p[i * 4 + 1]) + 0.0722 * Double(p[i * 4 + 2]) }
    return s / Double(w * h)
  }
}

final class DiagVC: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Test"; view.backgroundColor = .systemGroupedBackground
    let sv = UIScrollView(), st = UIStackView(); st.axis = .vertical; st.spacing = 12
    sv.translatesAutoresizingMaskIntoConstraints = false; st.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(sv); sv.addSubview(st)
    NSLayoutConstraint.activate([sv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                 sv.leadingAnchor.constraint(equalTo: view.leadingAnchor), sv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                 st.topAnchor.constraint(equalTo: sv.topAnchor, constant: 16), st.bottomAnchor.constraint(equalTo: sv.bottomAnchor, constant: -16),
                                 st.leadingAnchor.constraint(equalTo: sv.leadingAnchor, constant: 16), st.widthAnchor.constraint(equalTo: sv.widthAnchor, constant: -32)])
    let l = UILabel(); l.numberOfLines = 0; l.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    l.text = Diag.steps.isEmpty ? "Send a video, then come back here." : "The last video sent (seconds from Send):\n\n" + Diag.steps.map { String(format: "%6.2f  ", $0.1) + $0.0 }.joined(separator: "\n")
    st.addArrangedSubview(l)
    for (what, img, b) in Diag.pictures {
      let t = UILabel(); t.numberOfLines = 0; t.font = .systemFont(ofSize: 14, weight: .semibold)
      t.text = "\(what) — brightness \(Int(b)) of 255 (\(img.cgImage.map { "\($0.width)×\($0.height), " + (($0.colorSpace?.name as String?) ?? "no colour space") } ?? ""))"
      let iv = UIImageView(image: img); iv.contentMode = .scaleAspectFit; iv.heightAnchor.constraint(equalToConstant: 260).isActive = true
      st.addArrangedSubview(t); st.addArrangedSubview(iv)
    }
  }
}
