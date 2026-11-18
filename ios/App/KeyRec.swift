import UIKit
import ObjectiveC

/* TEMPORARY — the keyboard recorder (Haris 2026-11-18 14:08: "Yes"). With the keyboard up in comments, Control Center pulled
   down and closed makes the keyboard drop halfway and come back (every time; 1850 too; never in E11 Talk). Reading the code
   didn't find what does it, and Control Center can't be opened in the simulator — so, on the owner's phone only, this notes
   from the moment the app goes inactive until 3 s after it's active again: who becomes / stops being first responder (with
   UIKit's own call stack), every keyboard notice, the app's look and tab bar redraws, the copy changing. Then a panel shows
   the notes (Copy · Close). Nothing else changes. Taken out again once the cause is found. */
enum KeyRec {
  private static var lines: [String] = []
  private static var t0 = CACurrentMediaTime()
  private static var recording = false
  private static var swizzled = false
  private static var watching = false
  private static var showItem: DispatchWorkItem?
  private static var panel: UIView?
  private static var cycle = 0

  static var allowed: Bool { (Main.shared.startInfo["owner"] as? Bool) == true }

  // the two test switches (the panel): the hidden web page out while signed in · the comment box keeping the keyboard
  // from Control Center until half a second after the app is active again
  static var webOut: Bool { get { allowed && UserDefaults.standard.bool(forKey: "kr_webOut") } set { UserDefaults.standard.set(newValue, forKey: "kr_webOut"); placeWeb() } }
  static var hold: Bool { get { allowed && UserDefaults.standard.bool(forKey: "kr_hold") } set { UserDefaults.standard.set(newValue, forKey: "kr_hold") } }
  static var holding = false
  static func placeWeb() {
    let m = Main.shared
    guard m.isViewLoaded, let w = m.web else { return }
    let out = webOut && Main.boot.state == .signedIn
    if out, w.superview != nil { w.removeFromSuperview(); note("web page taken out") }
    if !out, w.superview == nil { m.view.insertSubview(w, at: 0); note("web page put back") }
  }

  static func watch() {
    guard !watching else { return }
    watching = true
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in if hold { holding = true }; begin() }
    nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
      note("APP didBecomeActive")
      placeWeb()
      if holding { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { holding = false; note("hold over") } }
      guard recording else { return }
      showItem?.cancel()
      let w = DispatchWorkItem { finish() }
      showItem = w
      DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }
    nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in note("APP willEnterForeground") }
    nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in note("APP didEnterBackground"); recording = false; holding = false; showItem?.cancel() }
    for (n, name) in [(UIResponder.keyboardWillShowNotification, "willShow"), (UIResponder.keyboardDidShowNotification, "didShow"),
                      (UIResponder.keyboardWillHideNotification, "willHide"), (UIResponder.keyboardDidHideNotification, "didHide"),
                      (UIResponder.keyboardWillChangeFrameNotification, "willChangeFrame"), (UIResponder.keyboardDidChangeFrameNotification, "didChangeFrame")] {
      nc.addObserver(forName: n, object: nil, queue: .main) { x in
        guard recording else { return }
        let u = x.userInfo ?? [:]
        let b = (u[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let e = (u[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let d = (u[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? -1
        let local = (u[UIResponder.keyboardIsLocalUserInfoKey] as? Bool).map { $0 ? "local" : "NOT local" } ?? "?"
        note("KB \(name) y \(Int(b.minY))→\(Int(e.minY)) h \(Int(e.height)) dur \(String(format: "%.2f", d)) \(local) · fr: \(responderName())", stack: name.hasPrefix("will"))
      }
    }
    for (n, name) in [(UITextView.textDidBeginEditingNotification, "TV beginEditing"), (UITextView.textDidEndEditingNotification, "TV endEditing"),
                      (UITextField.textDidBeginEditingNotification, "TF beginEditing"), (UITextField.textDidEndEditingNotification, "TF endEditing")] {
      nc.addObserver(forName: n, object: nil, queue: .main) { x in note("\(name) \(describe(x.object as AnyObject?))") }
    }
    nc.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { x in note("WIN becameKey \(describe(x.object as AnyObject?))") }
    nc.addObserver(forName: UIWindow.didResignKeyNotification, object: nil, queue: .main) { x in note("WIN resignedKey \(describe(x.object as AnyObject?))") }
  }

  private static func begin() {
    guard allowed else { return }
    if !swizzled { swizzle(); swizzled = true }
    showItem?.cancel()
    panel?.removeFromSuperview(); panel = nil
    cycle += 1
    lines = ["E11 Console \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "")) · \(UIDevice.current.systemVersion) · round \(cycle)",
             "switches: web page out \(webOut ? "ON" : "off") (in the window: \(Main.shared.web?.superview != nil)) · keyboard held \(hold ? "ON" : "off")",
             "compose box: \(Main.shared.composeIfMade.map { "made, first responder: \($0.text.isFirstResponder), window: \($0.window != nil)" } ?? "not made")"]
    t0 = CACurrentMediaTime()
    recording = true
    note("APP willResignActive · fr: \(responderName())")
  }

  static func note(_ s: String, stack: Bool = false) {
    guard recording else { return }
    let ms = Int((CACurrentMediaTime() - t0) * 1000)
    var line = "\(ms)ms \(s)"
    if stack { line += "\n" + frames().map { "      " + $0 }.joined(separator: "\n") }
    lines.append(line)
  }

  private static func finish() {
    note("— end (3 s after active) · fr: \(responderName())")
    recording = false
    let text = lines.joined(separator: "\n")
    guard let win = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else { return }
    let p = UIView(frame: win.bounds.insetBy(dx: 12, dy: 0))
    p.frame.origin.y = win.safeAreaInsets.top + 50; p.frame.size.height = min(win.bounds.height * 0.45, 420)
    p.backgroundColor = UIColor.black.withAlphaComponent(0.88); p.layer.cornerRadius = 14
    let tv = UITextView(frame: p.bounds.inset(by: UIEdgeInsets(top: 40, left: 8, bottom: 8, right: 8)))
    tv.isEditable = false; tv.isSelectable = false; tv.backgroundColor = .clear; tv.textColor = .white
    tv.font = .monospacedSystemFont(ofSize: 9, weight: .regular); tv.text = text
    p.addSubview(tv)
    let title = UILabel(frame: CGRect(x: 12, y: 10, width: 160, height: 20)); title.text = "Keyboard recorder"; title.textColor = .white; title.font = .boldSystemFont(ofSize: 13)
    p.addSubview(title)
    let copy = UIButton(type: .system); copy.setTitle("Copy", for: .normal); copy.frame = CGRect(x: p.bounds.width - 140, y: 6, width: 60, height: 28)
    copy.addAction(UIAction { _ in UIPasteboard.general.string = text; copy.setTitle("Copied", for: .normal) }, for: .touchUpInside)
    let close = UIButton(type: .system); close.setTitle("Close", for: .normal); close.frame = CGRect(x: p.bounds.width - 72, y: 6, width: 60, height: 28)
    close.addAction(UIAction { [weak p] _ in p?.removeFromSuperview(); panel = nil }, for: .touchUpInside)
    p.addSubview(copy); p.addSubview(close)
    // the two switches, under the notes
    tv.frame.size.height -= 76
    for (i, (label, on)) in [("Web page out", webOut), ("Keyboard held", hold)].enumerated() {
      let y = p.bounds.height - 74 + CGFloat(i) * 36
      let l = UILabel(frame: CGRect(x: 14, y: y, width: 200, height: 31)); l.text = label; l.textColor = .white; l.font = .systemFont(ofSize: 14)
      let s = UISwitch(); s.isOn = on; s.frame.origin = CGPoint(x: p.bounds.width - s.frame.width - 14, y: y)
      s.addAction(UIAction { [weak s] _ in guard let s = s else { return }; if i == 0 { webOut = s.isOn } else { hold = s.isOn } }, for: .valueChanged)
      p.addSubview(l); p.addSubview(s)
    }
    UIView.performWithoutAnimation { win.addSubview(p) }
    panel = p
  }

  // who holds the keyboard now
  private static func responderName() -> String {
    KeyRecFound.last = nil
    UIApplication.shared.sendAction(#selector(UIResponder.krFind), to: nil, from: nil, for: nil)
    let r = KeyRecFound.last
    KeyRecFound.last = nil
    return describe(r)
  }

  static func describe(_ o: AnyObject?) -> String {
    guard let o = o else { return "nobody" }
    var s = String(describing: type(of: o))
    if let c = Main.shared.composeIfMade, o === c.text { s += " [COMPOSE BOX]" }
    if let v = o as? UIView { s += v.window == nil ? " (no window)" : "" }
    return s
  }

  // UIKit's own frames (the app's own are named too when iPhone knows them) — the ones that say why
  private static func frames() -> [String] {
    Thread.callStackSymbols.dropFirst(3).prefix(22).compactMap { l in
      let parts = l.split(separator: " ", omittingEmptySubsequences: true)
      guard parts.count >= 4 else { return nil }
      let lib = String(parts[1])
      let sym = parts.dropFirst(3).joined(separator: " ").replacingOccurrences(of: #" \+ \d+$"#, with: "", options: .regularExpression)
      if sym.contains("KeyRec") || sym.contains("kr_") { return nil }
      return "\(lib): \(sym.prefix(110))"
    }
  }

  // first responder taken / given up — UIResponder's own (the text views and the web view's content call it as super)
  private static func swizzle() {
    if let a = class_getInstanceMethod(UIResponder.self, #selector(UIResponder.becomeFirstResponder)), let b = class_getInstanceMethod(UIResponder.self, #selector(UIResponder.kr_become)) { method_exchangeImplementations(a, b) }
    if let a = class_getInstanceMethod(UIResponder.self, #selector(UIResponder.resignFirstResponder)), let b = class_getInstanceMethod(UIResponder.self, #selector(UIResponder.kr_resign)) { method_exchangeImplementations(a, b) }
  }
}

enum KeyRecFound { static weak var last: UIResponder? }

