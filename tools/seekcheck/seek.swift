// The seek bar's let-go, measured (Haris 2026-11-23 12:29): Apple's own player (AVPlayer), driven exactly as the apps'
// seek bar drives it — playing, the finger down (pause), a drag (an exact jump for each step, 60 a second), held, let go
// (play) — and the player's own time read every 1/60 s, with each jump's landing. Nothing of the apps is changed by this.
// Ways: as = the apps today; final = play when the last jump lands; chase = one jump at a time, play after the last;
// cancel = the jumps still on their way given up, then play.
import AVFoundation
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let file = URL(fileURLWithPath: CommandLine.arguments[1])
let way = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "as"
let target = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 0
let p = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: file)))
p.actionAtItemEnd = .pause
let t0 = Date()
func ms() -> Double { Date().timeIntervalSince(t0) * 1000 }
func now() -> Double { p.currentTime().seconds }
func log(_ s: String) { print(String(format: "%7.1f ms  t=%.3f  %@", ms(), now(), s)) }
func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }

var seekN = 0, chasing = false, chaseTo: Double? = nil, letGo = false
func jump(_ x: Double, _ done: ((Bool) -> Void)? = nil) {
  seekN += 1; let n = seekN
  p.seek(to: CMTime(seconds: x, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { fin in
    DispatchQueue.main.async { log(String(format: "jump #%d to %.3f landed finished=%@", n, x, fin ? "yes" : "no")); done?(fin) }
  }
}
func chase() {
  guard let x = chaseTo else { chasing = false; if letGo { letGo = false; log("PLAY (chase done)"); p.play() }; return }
  chasing = true; chaseTo = nil
  jump(x) { _ in chase() }
}

var watching = false, last = -1.0
func watch() {
  guard watching else { return }
  let t = now()
  if last >= 0, t < last - 0.02 { log(String(format: "BACK from %.3f", last)) }
  last = t
  after(1.0 / 60) { watch() }
}

func waitReady(_ then: @escaping () -> Void) {
  if p.currentItem?.status == .readyToPlay { then() } else { after(0.05) { waitReady(then) } }
}
waitReady {
  let len = p.currentItem!.duration.seconds
  log(String(format: "ready, %.3f s long — way=%@ to %.2f", len, way, target))
  p.play(); log("PLAY (playing before the drag)")
  after(1.2) {
    p.pause(); log("finger down: PAUSE")
    let from = now(), steps = 20
    watching = true; watch()
    for i in 1...steps {
      after(Double(i) / 60) {
        let x = from + (target - from) * Double(i) / Double(steps)
        if way == "chase" { chaseTo = x; if !chasing { chase() } } else { jump(x) }
      }
    }
    after(Double(steps) / 60 + 0.2) {
      log("LET GO")
      switch way {
      case "final": jump(target) { _ in log("PLAY (final landed)"); p.play() }
      case "chase": letGo = true; if !chasing { letGo = false; log("PLAY"); p.play() }
      case "cancel": p.currentItem?.cancelPendingSeeks(); log("PLAY (after cancelPendingSeeks)"); p.play()
      default: log("PLAY"); p.play()
      }
      after(1.2) { watching = false; log("end"); exit(0) }
    }
  }
}
after(15) { log("timeout"); exit(1) }
RunLoop.main.run()
