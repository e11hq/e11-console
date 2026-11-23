// The apps' seek bar, as it is in both (PhotoViewer.swift / Preview.swift on 2026-11-23): the same three actions on a
// UISlider — finger down: pause; each move: an exact jump; finger up: play if it was playing — and the player's time
// following it ten times a second. Every event and every jump's landing logged. Launch argument "fix" changes one thing,
// told in the log. (Haris 2026-11-23 13:10 — measured, nothing of the apps changed)
import UIKit
import AVFoundation

final class BarVC: UIViewController {
  let file = Bundle.main.url(forResource: "test", withExtension: "mp4") ?? URL(fileURLWithPath: "/missing.mp4")
  let pv = PlayerView(), bar = UISlider(), line = UILabel(), state = UILabel()
  var p: AVPlayer!, t0 = Date(), logText = "", dragging = false, wasPlaying = false, ticks: Any?
  let fix = ProcessInfo.processInfo.arguments.contains("fix")
  func ms() -> Double { Date().timeIntervalSince(t0) * 1000 }
  func log(_ s: String) {
    let l = String(format: "%7.1f ms  t=%.3f  %@", ms(), p?.currentTime().seconds ?? -1, s); print(l)
    let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("seek.txt")
    if !FileManager.default.fileExists(atPath: u.path) { FileManager.default.createFile(atPath: u.path, contents: nil) }
    if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write((l + "\n").data(using: .utf8)!); try? h.close() }
  }
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .black
    pv.frame = view.bounds; pv.pl.videoGravity = .resizeAspect; view.addSubview(pv)
    line.frame = CGRect(x: 0, y: 60, width: view.bounds.width, height: 40); line.textAlignment = .center
    line.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold); line.textColor = .yellow; line.backgroundColor = UIColor(white: 0, alpha: 0.7); view.addSubview(line)
    state.frame = CGRect(x: 0, y: 110, width: view.bounds.width, height: 30); state.textAlignment = .center; state.textColor = .white
    state.accessibilityIdentifier = "state"; state.text = "loading"; view.addSubview(state)
    bar.frame = CGRect(x: 60, y: view.bounds.height - 140, width: view.bounds.width - 120, height: 34); bar.accessibilityIdentifier = "bar"
    bar.minimumTrackTintColor = .white; view.addSubview(bar)
    bar.addAction(UIAction { [weak self] _ in guard let self else { return }; self.log("event touchDown"); self.dragging = true
      self.wasPlaying = self.p.timeControlStatus != .paused; self.p.pause() }, for: .touchDown)
    bar.addAction(UIAction { [weak self] _ in guard let self else { return }
      self.log(String(format: "event valueChanged %.3f (dragging %@)", self.bar.value, self.dragging ? "yes" : "no"))
      if self.fix && !self.dragging { self.log("  (fix: not dragging — no jump)"); return }
      let x = Double(self.bar.value)
      self.p.seek(to: CMTime(seconds: x, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { fin in
        DispatchQueue.main.async { self.log(String(format: "  jump to %.3f landed %@", x, fin ? "yes" : "no")) } }
    }, for: .valueChanged)
    bar.addAction(UIAction { [weak self] _ in guard let self else { return }; self.log("event touchUp"); self.dragging = false
      if self.wasPlaying { self.log("PLAY (let go)"); self.p.play() } }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    let tick = CADisplayLink(target: self, selector: #selector(drawLine)); tick.add(to: .main, forMode: .common)
    log("start — fix: " + (fix ? "valueChanged ignored when the finger isn't on the bar" : "none (the apps as they are)"))
    p = AVPlayer(playerItem: AVPlayerItem(url: file)); p.actionAtItemEnd = .pause; pv.pl.player = p
    ticks = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
      guard let self, !self.dragging else { return }
      if let d = self.p.currentItem?.duration, d.isNumeric, d.seconds > 0, abs(Double(self.bar.maximumValue) - d.seconds) > 0.05 { self.bar.maximumValue = Float(d.seconds) }
      self.bar.value = Float(t.seconds)
    }
    var last = -1.0
    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      guard let self, let p = self.p else { return }
      let t = p.currentTime().seconds
      if last >= 0, t < last - 0.02, !self.dragging { self.log(String(format: "BACK from %.3f", last)) }
      last = t
    }
    waitReady()
  }
  func waitReady() {
    guard p.currentItem?.status == .readyToPlay, pv.pl.isReadyForDisplay else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitReady() }; return }
    log("PLAY (start)"); p.play()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.state.text = "playing"; self.log("ready for the finger") }
  }
  @objc func drawLine() { line.text = String(format: "t=%.3f %@", p?.currentTime().seconds ?? 0, dragging ? "DRAG" : "") }
}
