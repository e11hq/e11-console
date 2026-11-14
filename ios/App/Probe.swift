import UIKit
import QuartzCore

/* TEMPORARY — E11 Console's speed report (Haris 2026-11-14: "after the timing trial we will do for console as well"),
   as E11 Talk's: every moment timed on his phone instead of guessed — the app's start (from the moment iPhone started it),
   the engine and the copy on the phone, the server's answers with the server's own time (Server-Timing, server 1.9.53),
   each screen worked out from the copy, a task's opening, any moment the screen froze (and on which page), memory.
   Shake the iPhone to see it, with Copy. On its own branch (ios-speed-probe), never the App Store; taken out once fixed. */
enum Probe {
  static let launched: Double = {
    var kp = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0 else { return Date().timeIntervalSince1970 }
    let tv = kp.kp_proc.p_starttime
    return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
  }()
  private static var lines: [String] = []
  private static let lock = NSLock()
  static func now() -> Double { Date().timeIntervalSince1970 }
  static func mark(_ s: String) { add(String(format: "%6.0f ms  %@", (now() - launched) * 1000, s)) }
  static func took(_ ms: Double, _ s: String) { add(String(format: "   took %5.0f ms  %@", ms, s)) }
  static func add(_ s: String) { lock.lock(); lines.append(s); if lines.count > 900 { lines.removeFirst(200) }; lock.unlock() }
  static var memory: String {
    var info = task_vm_info_data_t()
    var c = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let k = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &c) } }
    return k == KERN_SUCCESS ? "\(info.phys_footprint / 1_048_576) MB" : "?"
  }
  static func report() -> String {
    let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")"
    lock.lock(); let body = lines.joined(separator: "\n"); lock.unlock()
    return "E11 Console speed report · \(v) · \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)\nmemory now \(memory) · screen \(UIScreen.main.maximumFramesPerSecond) fps\n\n" + body
  }

  // the screen freezing: any moment the next frame came late (more than two frames' time), and on which page
  final class Hitches: NSObject {
    static let shared = Hitches()
    private var link: CADisplayLink?, last: CFTimeInterval = 0, logged = 0
    func start() {
      guard link == nil else { return }
      let l = CADisplayLink(target: self, selector: #selector(tick(_:))); l.add(to: .main, forMode: .common); link = l
    }
    @objc private func tick(_ l: CADisplayLink) {
      defer { last = l.timestamp }
      guard last > 0, UIApplication.shared.applicationState == .active else { return }
      let gap = l.timestamp - last, frame = 1.0 / Double(max(60, UIScreen.main.maximumFramesPerSecond))
      guard gap > max(0.025, frame * 2.5), logged < 400 else { return }
      logged += 1
      Probe.mark(String(format: "screen froze %.0f ms (%d frames missed) on %@", gap * 1000, Int((gap / frame).rounded()) - 1, Hitches.page()))
    }
    static func page() -> String {
      guard let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first, var v = w.rootViewController else { return "?" }
      while true {
        if let p = v.presentedViewController { v = p; continue }
        if let t = v as? UITabBarController, let s = t.selectedViewController { v = s; continue }
        if let n = v as? UINavigationController, let top = n.topViewController { v = top; continue }
        break
      }
      return String(describing: type(of: v))
    }
  }
}

// shake the iPhone: the report, with Copy
final class ShakeWindow: UIWindow {
  override func motionEnded(_ m: UIEvent.EventSubtype, with e: UIEvent?) {
    super.motionEnded(m, with: e)
    guard m == .motionShake, var top = rootViewController else { return }
    while let p = top.presentedViewController { top = p }
    if top is ProbeNav { return }
    top.present(ProbeNav(rootViewController: ProbeVC()), animated: true)
  }
}
final class ProbeNav: UINavigationController {}
final class ProbeVC: UIViewController {
  private let text = UITextView()
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Speed Report"; view.backgroundColor = .systemBackground
    text.font = .monospacedSystemFont(ofSize: 11, weight: .regular); text.isEditable = false; text.text = Probe.report()
    text.frame = view.bounds; text.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(text)
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy", primaryAction: UIAction { [weak self] _ in
      UIPasteboard.general.string = Probe.report(); self?.navigationItem.rightBarButtonItem?.title = "Copied"
    })
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
  }
}

// (TEMPORARY speed report) a piece of the app timed: logged when it took 4 ms or more; `sum` adds up many small ones made
// in one go (rows, logos) and logs the total once the screen is free again
extension Probe {
  static func span(_ name: String, _ t0: Double) { let ms = (now() - t0) * 1000; if ms >= 4 { took(ms, name) } }
  private static var sums: [String: (n: Int, ms: Double)] = [:]
  static func sum(_ name: String, _ t0: Double) {
    let ms = (now() - t0) * 1000
    guard Thread.isMainThread else { if ms >= 4 { took(ms, name + " (in background)") }; return }
    if sums.isEmpty { DispatchQueue.main.async { for (k, v) in sums where v.ms >= 4 { took(v.ms, "\(v.n) × \(k)") }; sums = [:] } }
    let o = sums[name] ?? (0, 0); sums[name] = (o.n + 1, o.ms + ms)
  }
}
