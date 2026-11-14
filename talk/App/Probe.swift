import UIKit
import QuartzCore

/* TEMPORARY — the speed report (Haris 2026-11-14: "How can we make talk the fastest as much as possible?"): every moment
   timed on his phone instead of guessed — the app's start (from the moment iPhone started it), reading the phone's copy,
   the first list on screen, the server's answers, a chat's opening, each chat read from the phone, scrolling (frames that
   missed the screen) and memory. Settings › Speed Report shows it, with Copy. Taken out once the slow parts are fixed. */
enum Probe {
  // when iPhone started the app (not when our code first ran)
  static let launched: Double = {
    var kp = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0 else { return Date().timeIntervalSince1970 }
    let tv = kp.kp_proc.p_starttime
    return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
  }()
  private static var lines: [String] = []
  static func now() -> Double { Date().timeIntervalSince1970 }
  // a moment, in ms since the app was started
  static func mark(_ s: String) { add(String(format: "%6.0f ms  %@", (now() - launched) * 1000, s)) }
  // how long something took
  static func took(_ ms: Double, _ s: String) { add(String(format: "   took %5.0f ms  %@", ms, s)) }
  @discardableResult static func time<T>(_ s: String, _ f: () -> T) -> T { let a = now(); let r = f(); took((now() - a) * 1000, s); return r }
  static func add(_ s: String) {
    let go = { lines.append(s); if lines.count > 800 { lines.removeFirst(200) } }
    if Thread.isMainThread { go() } else { DispatchQueue.main.async(execute: go) }
  }
  static var memory: String {
    var info = task_vm_info_data_t()
    var c = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let k = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &c) } }
    return k == KERN_SUCCESS ? "\(info.phys_footprint / 1_048_576) MB" : "?"
  }
  static func kb(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0) / 1024 }
  static func report() -> String {
    let T = Talk.shared
    let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")"
    var h = "E11 Talk speed report · \(v) · \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)\n"
    h += "memory now \(memory) · \(T.groups.count) groups · \(T.loadedChats) chats read · \(T.loadedMessages) messages in memory\n"
    h += "on the phone: copy \(T.copyKB) KB · chats \(T.chatsKB) KB · files \(ByteCountFormatter.string(fromByteCount: Int64(Storage.total()), countStyle: .file))\n\n"
    return h + lines.joined(separator: "\n")
  }

  // scrolling: frames that missed the screen while a list moves
  final class Frames: NSObject {
    private var link: CADisplayLink?, last: CFTimeInterval = 0, n = 0, missed = 0, worst: CFTimeInterval = 0, name = ""
    func start(_ what: String) {
      stop(); name = what; n = 0; missed = 0; worst = 0; last = 0
      let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
      // (at the screen's own rate — 120 a second on ProMotion; counted at 60 every frame looked missed: report 1)
      l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
      l.add(to: .main, forMode: .common); link = l
    }
    @objc private func tick(_ l: CADisplayLink) {
      defer { last = l.timestamp }
      guard last > 0 else { return }
      let gap = l.timestamp - last, want = 1.0 / Double(max(60, UIScreen.main.maximumFramesPerSecond))
      n += 1; worst = max(worst, gap)
      if gap > want * 1.5 { missed += Int((gap / want).rounded()) - 1 }
    }
    func stop() {
      guard let l = link else { return }
      l.invalidate(); link = nil
      if n > 5 { Probe.add(String(format: "         scroll %@: %d frames, %d missed, worst %.0f ms", name, n, missed, worst * 1000)) }
    }
  }
}

// the report in Settings, with Copy
final class ProbeVC: UIViewController {
  private let text = UITextView()
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Speed Report"; view.backgroundColor = .systemBackground
    text.font = .monospacedSystemFont(ofSize: 11, weight: .regular); text.isEditable = false; text.text = Probe.report()
    text.frame = view.bounds; text.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(text)
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy", primaryAction: UIAction { [weak self] _ in
      UIPasteboard.general.string = Probe.report(); self?.navigationItem.rightBarButtonItem?.title = "Copied"
    })
  }
}
