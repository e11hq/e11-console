// The seek bar's let-go, filmed (Haris 2026-11-23 12:50): only Apple's player (AVPlayer + its layer), driven as the apps'
// seek bar drives it, the simulator's screen recorded. Two passes: "bare" (the player alone on black) and "under" (a
// picture of the first frame under the player, as both apps have — here turned to its negative, so if it ever shows
// through it can be told from the video itself). A line at the top says what's happening, read from the film.
import UIKit
import AVFoundation
import CoreImage

final class PlayerView: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; var pl: AVPlayerLayer { layer as! AVPlayerLayer } }

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds); window?.rootViewController = VC(); window?.makeKeyAndVisible(); return true
  }
}

final class VC: UIViewController {
  let file = Bundle.main.url(forResource: "test", withExtension: "mp4")!
  let still = UIImageView(), pv = PlayerView(), line = UILabel()
  var p: AVPlayer!, t0 = Date(), phase = "", logText = ""
  func ms() -> Double { Date().timeIntervalSince(t0) * 1000 }
  func log(_ s: String) { let l = String(format: "%7.1f ms  t=%.3f  %@", ms(), p?.currentTime().seconds ?? -1, s); print(l); logText += l + "\n"
    try? logText.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("seek.txt"), atomically: true, encoding: .utf8) }
  func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }

  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .black
    still.contentMode = .scaleAspectFit; still.frame = view.bounds; view.addSubview(still)
    pv.frame = view.bounds; pv.pl.videoGravity = .resizeAspect; view.addSubview(pv)
    line.frame = CGRect(x: 0, y: 60, width: view.bounds.width, height: 40); line.textAlignment = .center
    line.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold); line.textColor = .yellow; line.backgroundColor = UIColor(white: 0, alpha: 0.7)
    view.addSubview(line)
    // (the first frame, as a negative)
    let g = AVAssetImageGenerator(asset: AVURLAsset(url: file)); g.appliesPreferredTrackTransform = true
    g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
    if let cg = try? g.copyCGImage(at: .zero, actualTime: nil) {
      let ci = CIImage(cgImage: cg).applyingFilter("CIColorInvert")
      if let out = CIContext().createCGImage(ci, from: ci.extent) { still.image = UIImage(cgImage: out) }
    }
    let tick = CADisplayLink(target: self, selector: #selector(show)); tick.add(to: .main, forMode: .common)
    after(1.5) { self.run(["bare 0", "bare 1", "under 0", "under 1", "bare 0", "under 0"]) }
  }
  @objc func show() { line.text = String(format: "%@  t=%.3f", phase, p?.currentTime().seconds ?? 0) }

  func run(_ list: [String]) {
    guard let s = list.first else { phase = "DONE"; log("DONE"); return }
    let parts = s.split(separator: " "), under = parts[0] == "under", to = Double(parts[1])!
    still.isHidden = !under
    p = AVPlayer(playerItem: AVPlayerItem(url: file)); p.actionAtItemEnd = .pause; pv.pl.player = p
    phase = s + " load"; log("=== " + s)
    waitReady {
      self.phase = s + " play"; self.log("PLAY"); self.p.play()
      self.after(1.2) {
        self.phase = s + " drag"; self.p.pause(); self.log("PAUSE (finger down)")
        let from = self.p.currentTime().seconds
        for i in 1...20 { self.after(Double(i) / 60) {
          let x = from + (to - from) * Double(i) / 20
          self.p.seek(to: CMTime(seconds: x, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { fin in
            DispatchQueue.main.async { self.log(String(format: "jump to %.3f landed %@", x, fin ? "yes" : "no")) } }
        } }
        self.after(20.0 / 60 + 0.2) {
          self.phase = s + " LETGO"; self.log("PLAY (let go)"); self.p.play()
          self.after(1.6) { self.p.pause(); self.after(0.5) { self.run(Array(list.dropFirst())) } }
        }
      }
    }
  }
  func waitReady(_ f: @escaping () -> Void) {
    if p.currentItem?.status == .readyToPlay, pv.pl.isReadyForDisplay { f() } else { after(0.05) { self.waitReady(f) } }
  }
}
