import UIKit
import AVFoundation

/* Voice messages (stage 2, as WhatsApp): hold the mic to record — a red dot, the time, "‹ Slide to cancel"; let go to
   send it, slide left to drop it. Recorded small (AAC, mono) with its waveform measured while recording, so every phone
   draws the same bars without opening the sound. In the bubble: play / pause, the bars filling as it plays, the length. */
final class VoiceRecorder: NSObject {
  private var rec: AVAudioRecorder?
  private var timer: Timer?
  private(set) var levels: [Float] = []
  private(set) var url: URL?
  var onTick: ((TimeInterval) -> Void)?
  var isRecording: Bool { rec?.isRecording == true }

  func start(_ done: @escaping (Bool) -> Void) {
    AVAudioSession.sharedInstance().requestRecordPermission { ok in
      DispatchQueue.main.async {
        guard ok else { done(false); return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setActive(true)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let set: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000]
        guard let r = try? AVAudioRecorder(url: u, settings: set) else { done(false); return }
        r.isMeteringEnabled = true
        guard r.record() else { done(false); return }
        self.rec = r; self.url = u; self.levels = []
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
          guard let self = self, let r = self.rec else { return }
          r.updateMeters()
          self.levels.append(max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50)))
          self.onTick?(r.currentTime)
        }
        done(true)
      }
    }
  }
  // stops; with keep: the file, its length and its waveform (else it's thrown away)
  func stop(keep: Bool) -> (URL, Double, String)? {
    timer?.invalidate(); timer = nil
    let secs = rec?.currentTime ?? 0
    rec?.stop(); rec = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    guard keep, let u = url, secs >= 0.7 else { if let u = url { try? FileManager.default.removeItem(at: u) }; url = nil; return nil }
    url = nil
    return (u, secs, VoiceRecorder.wave(levels))
  }
  // 48 bars, each 0–255, as base64 (small enough to go with the message)
  static func wave(_ l: [Float]) -> String {
    let n = 48
    guard !l.isEmpty else { return Data(repeating: 40, count: n).base64EncodedString() }
    var out = [UInt8]()
    for i in 0..<n {
      let a = i * l.count / n, b = max(a + 1, (i + 1) * l.count / n)
      let slice = l[a..<min(b, l.count)]
      let v = slice.isEmpty ? 0 : slice.max() ?? 0
      out.append(UInt8(max(18, min(255, Int(v * 255)))))
    }
    return Data(out).base64EncodedString()
  }
  static func bars(_ wave: String?) -> [CGFloat] {
    guard let w = wave, let d = Data(base64Encoded: w), !d.isEmpty else { return Array(repeating: 0.3, count: 48) }
    return d.map { CGFloat($0) / 255 }
  }
}

// one voice message playing at a time, the bubbles following it
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
  static let shared = VoicePlayer()
  static let changed = Notification.Name("talk.voice")
  private(set) var playing: String?
  private var player: AVAudioPlayer?
  private var timer: Timer?
  var progress: Double { guard let p = player, p.duration > 0 else { return 0 }; return p.currentTime / p.duration }

  func toggle(_ id: String, url: URL) {
    if playing == id, let p = player {
      if p.isPlaying { p.pause(); timer?.invalidate() } else { p.play(); tick() }
      NotificationCenter.default.post(name: VoicePlayer.changed, object: nil); return
    }
    stop()
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    try? AVAudioSession.sharedInstance().setActive(true)
    guard let p = try? AVAudioPlayer(contentsOf: url) else { toast("Couldn’t play it"); return }
    p.delegate = self; p.play()
    player = p; playing = id
    tick()
    NotificationCenter.default.post(name: VoicePlayer.changed, object: nil)
  }
  var isPlaying: Bool { player?.isPlaying == true }
  private func tick() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in NotificationCenter.default.post(name: VoicePlayer.changed, object: nil) }
  }
  func stop() {
    timer?.invalidate(); timer = nil
    player?.stop(); player = nil; playing = nil
    NotificationCenter.default.post(name: VoicePlayer.changed, object: nil)
  }
  func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { stop() }
}

// in the bubble: ▶︎ / ❚❚, the bars (filled as far as it has played), the length
final class VoiceView: UIView {
  private let btn = UIButton(type: .system), len = UILabel()
  private var bars: [CGFloat] = []
  private var id = "", fileId = "", secs: Double = 0
  private var ink: UIColor = .label, dim: UIColor = .secondaryLabel
  private var loading = false
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    btn.addAction(UIAction { [weak self] _ in self?.tap() }, for: .touchUpInside)
    len.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    addSubview(btn); addSubview(len)
    NotificationCenter.default.addObserver(self, selector: #selector(update), name: VoicePlayer.changed, object: nil)
    heightAnchor.constraint(equalToConstant: 40).isActive = true
    widthAnchor.constraint(equalToConstant: 230).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(id: String, file: Msg.FileRef, ink: UIColor, dim: UIColor) {
    self.id = id; fileId = file.id; secs = file.secs ?? 0
    self.ink = ink; self.dim = dim
    bars = VoiceRecorder.bars(file.wave)
    btn.tintColor = ink
    len.textColor = dim
    update()
  }
  private func tap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    if VoicePlayer.shared.playing == id { VoicePlayer.shared.toggle(id, url: Net.local(fileId)); return }
    loading = true; update()
    Net.shared.file(fileId) { [weak self] url in
      guard let self = self else { return }
      self.loading = false
      guard let url = url else { toast("That voice message isn’t on the server any more"); self.update(); return }
      VoicePlayer.shared.toggle(self.id, url: url)
    }
  }
  @objc private func update() {
    let mine = VoicePlayer.shared.playing == id
    let sym = loading ? "arrow.down.circle" : (mine && VoicePlayer.shared.isPlaying ? "pause.fill" : "play.fill")
    btn.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal)
    let p = mine ? VoicePlayer.shared.progress : 0
    let shown = mine ? secs * p : secs
    len.text = String(format: "%d:%02d", Int(shown) / 60, Int(shown) % 60)
    setNeedsDisplay()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    btn.frame = CGRect(x: 0, y: 4, width: 32, height: 32)
    len.frame = CGRect(x: bounds.width - 38, y: 12, width: 38, height: 16)
  }
  override func draw(_ r: CGRect) {
    guard let c = UIGraphicsGetCurrentContext(), !bars.isEmpty else { return }
    let x0: CGFloat = 40, x1 = bounds.width - 44, w = (x1 - x0) / CGFloat(bars.count)
    let p = VoicePlayer.shared.playing == id ? CGFloat(VoicePlayer.shared.progress) : 0
    for (i, b) in bars.enumerated() {
      let h = max(3, b * 26), x = x0 + CGFloat(i) * w
      c.setFillColor((CGFloat(i) / CGFloat(bars.count) < p ? ink : dim.withAlphaComponent(0.55)).cgColor)
      c.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: (bounds.height - h) / 2, width: max(1.5, w - 1.5), height: h), cornerRadius: 1).cgPath)
      c.fillPath()
    }
  }
}
