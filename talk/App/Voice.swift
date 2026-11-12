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
  private(set) var isPaused = false
  // locked: the red pause stops the recording for a moment, the mic picks it up again
  @discardableResult func togglePause() -> Bool {
    guard let r = rec else { return false }
    if isPaused { r.record(); isPaused = false } else { r.pause(); isPaused = true }
    return isPaused
  }

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
          guard !self.isPaused else { return }
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
    rec?.stop(); rec = nil; isPaused = false
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
  private var link: CADisplayLink?
  var progress: Double { guard let p = player, p.duration > 0 else { return 0 }; return p.currentTime / p.duration }

  func toggle(_ id: String, url: URL) {
    if playing == id, let p = player {
      if p.isPlaying { p.pause(); link?.invalidate(); link = nil } else { p.play(); tick() }
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
    link?.invalidate()
    link = CADisplayLink(target: self, selector: #selector(frame)); link?.add(to: .main, forMode: .common)
  }
  @objc private func frame() { NotificationCenter.default.post(name: VoicePlayer.changed, object: nil) }
  func stop() {
    link?.invalidate(); link = nil
    player?.stop(); player = nil; playing = nil
    NotificationCenter.default.post(name: VoicePlayer.changed, object: nil)
  }
  func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { stop() }
}

// the locked recording's live waveform: the last bars, newest on the right
final class LiveWave: UIView {
  var levels: [Float] = [] { didSet { setNeedsDisplay() } }
  override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false; contentMode = .redraw }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ r: CGRect) {
    guard let c = UIGraphicsGetCurrentContext() else { return }
    let n = Int(bounds.width / 4), shown = Array(levels.suffix(n))
    c.setFillColor(UIColor.secondaryLabel.cgColor)
    for (i, l) in shown.enumerated() {
      let h = max(3, CGFloat(l) * bounds.height), x = bounds.width - CGFloat(shown.count - i) * 4
      c.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: (bounds.height - h) / 2, width: 2, height: h), cornerRadius: 1).cgPath)
    }
    c.fillPath()
  }
}

// voice messages heard on this phone (the mic badge turns blue, as WhatsApp)
enum VoiceHeard {
  private static let key = "talk.voiceHeard"
  private static var set = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
  static func has(_ id: String) -> Bool { set.contains(id) }
  static func clear() { set = []; UserDefaults.standard.removeObject(forKey: key) }
  static func add(_ id: String) {
    guard !set.contains(id) else { return }
    set.insert(id); UserDefaults.standard.set(Array(set.suffix(2000)), forKey: key)
  }
}

/* In the bubble (the approved design, board 21 — WhatsApp's voice bubble in our blue): the sender's picture with the mic
   badge (grey, blue once heard), ▶︎ / ❚❚, the bars with the dot moving along as it plays, the length under the bars.
   No width of its own: the bubble's width (292) gives it. */
final class VoiceView: UIView {
  private let btn = UIButton(type: .system), len = UILabel(), pic = Avatar(), badge = UIImageView(), dot = UIView()
  private var bars: [CGFloat] = []
  private var id = "", fileId = "", secs: Double = 0, mine = false
  private var played: UIColor = .label, rest: UIColor = .secondaryLabel
  private var loading = false, shownOn = false
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear; isOpaque = false; contentMode = .redraw
    btn.addAction(UIAction { [weak self] _ in self?.tap() }, for: .touchUpInside)
    len.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    pic.isUserInteractionEnabled = false
    badge.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)); badge.contentMode = .center
    badge.layer.shadowColor = UIColor.black.cgColor; badge.layer.shadowOpacity = 0.25; badge.layer.shadowRadius = 1; badge.layer.shadowOffset = .zero
    dot.layer.cornerRadius = 6; dot.isUserInteractionEnabled = false
    [pic, badge, btn, len, dot].forEach { addSubview($0) }
    NotificationCenter.default.addObserver(self, selector: #selector(update), name: VoicePlayer.changed, object: nil)
    let h = heightAnchor.constraint(equalToConstant: 56); h.priority = .init(999); h.isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(id: String, file: Msg.FileRef, by: String, mine: Bool) {
    self.id = id; fileId = file.id; secs = file.secs ?? 0; self.mine = mine
    played = mine ? .white : Look.dyn(0x5AA9FF, 0x007AFF)
    rest = mine ? UIColor.white.withAlphaComponent(0.42) : Look.dyn(0x8E8E93, 0xB4B4B9)
    bars = VoiceRecorder.bars(file.wave)
    let T = Talk.shared, p = T.people[by]
    pic.set(name: p?.name ?? "", color: Look.person(by), picture: p?.photo)
    btn.tintColor = mine ? .white : .label
    len.textColor = mine ? Look.mineTime : Look.roleInk
    dot.backgroundColor = played
    shownOn = true; update()
  }
  private func tap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    if !mine { VoiceHeard.add(id) }
    if VoicePlayer.shared.playing == id { VoicePlayer.shared.toggle(id, url: Net.local(fileId)); return }
    loading = true; update()
    Net.shared.file(fileId) { [weak self] url in
      guard let self = self else { return }
      self.loading = false
      guard let url = url else { toast("That voice message isn’t on the server any more"); self.update(); return }
      VoicePlayer.shared.toggle(self.id, url: url)
    }
  }
  private var progress: CGFloat { VoicePlayer.shared.playing == id ? CGFloat(VoicePlayer.shared.progress) : 0 }
  @objc private func update() {
    let on = VoicePlayer.shared.playing == id
    guard on || shownOn || loading else { return }   // (another bubble's playing: nothing here changes)
    shownOn = on
    let sym = loading ? "arrow.down.circle" : (on && VoicePlayer.shared.isPlaying ? "pause.fill" : "play.fill")
    btn.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)), for: .normal)
    let shown = on ? secs * Double(progress) : secs
    len.text = String(format: "%d:%02d", Int(shown) / 60, Int(shown) % 60)
    badge.tintColor = mine || VoiceHeard.has(id) ? Look.dyn(0x5AA9FF, 0x2F7BFF) : Look.dyn(0x8E8E93, 0x8E8E93)
    if mine { badge.tintColor = .white }
    placeDot()
    setNeedsDisplay()
  }
  private var x0: CGFloat { 96 }
  private var x1: CGFloat { bounds.width - 4 }
  private func placeDot() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    dot.frame = CGRect(x: x0 + (x1 - x0) * progress - 6, y: 20 - 6, width: 12, height: 12)
    CATransaction.commit()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    pic.frame = CGRect(x: 0, y: 2, width: 44, height: 44)
    badge.frame = CGRect(x: 28, y: 30, width: 18, height: 18)
    btn.frame = CGRect(x: 50, y: 4, width: 36, height: 36)
    len.frame = CGRect(x: x0, y: 36, width: 60, height: 16)
    placeDot()
  }
  override func draw(_ r: CGRect) {
    guard let c = UIGraphicsGetCurrentContext(), !bars.isEmpty else { return }
    let n = max(1, Int((x1 - x0 + 2) / 4)), p = progress
    for i in 0..<n {
      let b = bars[min(bars.count - 1, i * bars.count / n)]
      let h = max(3, b * 24), x = x0 + CGFloat(i) * 4
      c.setFillColor((CGFloat(i) / CGFloat(n) < p ? played : rest).cgColor)
      c.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: 20 - h / 2, width: 2, height: h), cornerRadius: 1).cgPath)
      c.fillPath()
    }
  }
}
