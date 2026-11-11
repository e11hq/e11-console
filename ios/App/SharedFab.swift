import UIKit

/* The shared + (Haris 2026-11-05: "build the shared + button the way you said"). Every screen keeps its own floating
   button (+ New task, Add client, Add subscription…) where it is, but going from one screen to another the button is
   one: from a screen with one to a screen with another, it squashes and stretches into the new one's width and place
   with the words crossfading; to a screen with none (or a task opening over it) it shrinks away; to one with a button
   from none, it grows in. Done with a stand-in drawn over both screens for the moment of the change — each screen's own
   button is veiled meanwhile (still there for taps) and shows again once the stand-in has arrived. */
final class FabMorph {
  static let shared = FabMorph()
  weak var screen: HomeView?
  var known = false
  var ghost: UIButton?
  weak var veilA: HomeView?, veilB: HomeView?
  // (the screen it left stays veiled while it's no longer the one on top — it was still sliding out when the stand-in had
  //  gone, and its Upload came back for a moment: Haris 2026-11-06; it's unveiled when it's the one on top again)
  func unveil() { if veilA === screen { veilA?.fabVeiled = false }; veilB?.fabVeiled = false; veilA = nil; veilB = nil }
}

extension Main {
  // the screen on top now (nil: a task page over everything, the lock, or nothing yet) — called with the top buttons
  func fabFollow() {
    let m = FabMorph.shared
    // (Home is its own Apple screen: its + New task is its own, moving with it as Apple slides pages over it — never
    //  veiled for a stand-in drawn on the app's old shared screen, which isn't on show with Home's tab on: it was veiled
    //  as a task opened and only came back, in a snap, once the task page had gone — Haris 2026-11-07)
    // (My Tasks and the Inbox too, now their own Apple screens — the Inbox's + New task was veiled and gone when a Client
    //  Assets notification opened the app's old shared screen: Haris 2026-11-08)
    // (the Clients tab's pages and Client Assets' in Apple's navigation too — their buttons move with them: AppleClients.swift)
    let own: [HomeView] = [APPLE_HOME ? homeIfMade : nil, APPLE_MYTASKS ? myTasksIfMade : nil, APPLE_INBOX ? inboxIfMade : nil].compactMap { $0 }
      + [clientsListIfMade, clientPageIfMade].compactMap { $0 }.filter { $0.appleTop } + assetsCtl.screens.filter { $0.appleTop } + meCtl.screens.filter { $0.appleTop }   // (Me's, in its own Apple navigation — AppleMe.swift)
    for h in own { if h.fabVeiled { h.fabVeiled = false }; if m.veilA === h { m.veilA = nil }; if m.veilB === h { m.veilB = nil } }
    var to: HomeView? = taskPages.isEmpty && lockView == nil ? shownScreen : nil
    if let t = to, own.contains(where: { $0 === t }) { to = nil }
    guard m.known else { m.known = true; m.screen = to; return }
    guard to !== m.screen else { return }
    let from = m.screen.flatMap { s in own.contains(where: { $0 === s }) ? nil : s }
    m.screen = to
    to?.layoutIfNeeded()
    let place = { (h: HomeView, f: CGRect) -> CGRect in h.convert(f, to: self.view).offsetBy(dx: -h.transform.tx, dy: 0) }
    // (the screen left already gone — slid out with its button by the edge swipe or ‹, or taken away: nothing starts from
    //  where its button was; it came back there for a moment and faded, Haris 2026-11-06)
    let fromGone = from.map { $0.superview == nil || abs($0.transform.tx) > 1 } ?? true
    let a = fromGone ? nil : from.map { ($0, $0.fabNow) }.flatMap { $0.1.shown ? $0 : nil }
    let b = to.map { ($0, $0.fabNow) }.flatMap { $0.1.shown ? $0 : nil }
    // (one change at a time: a stand-in still moving is replaced from where it is)
    var start: CGRect? = nil, startCfg: UIButton.Configuration? = nil
    if let g = m.ghost { start = g.layer.presentation()?.frame ?? g.frame; startCfg = g.configuration; g.removeFromSuperview(); m.ghost = nil; m.unveil() }
    if start == nil, case let (h, f)? = a { start = place(h, f.frame); startCfg = f.config }
    if start == nil && b == nil { from?.fabVeiled = false; return }
    // (the same button in the same place: nothing to show)
    if case let (ha, fa)? = a, case let (hb, fb)? = b, fa.label == fb.label, place(ha, fa.frame) == place(hb, fb.frame) { hb.fabVeiled = false; return }

    let g = UIButton(type: .system)
    g.isUserInteractionEnabled = false
    g.accessibilityElementsHidden = true
    view.insertSubview(g, belowSubview: tabsMark)
    m.ghost = g
    from?.fabVeiled = true; to?.fabVeiled = true; m.veilA = from; m.veilB = to
    let done = { [weak g] in
      guard let g = g, FabMorph.shared.ghost === g else { return }
      g.removeFromSuperview(); FabMorph.shared.ghost = nil; FabMorph.shared.unveil()
    }
    UIView.performWithoutAnimation {
      if let s = start { g.configuration = startCfg; g.frame = s }
      else if case let (h, f)? = b { g.configuration = f.config; g.frame = place(h, f.frame); g.transform = CGAffineTransform(scaleX: 0.4, y: 0.4); g.alpha = 0 }
      g.layoutIfNeeded()
    }
    if case let (h, f)? = b {
      let target = place(h, f.frame)
      if start != nil {
        // another button: squash and stretch into its width and place, the words crossfading
        if startCfg?.attributedTitle != f.config?.attributedTitle || startCfg?.image != f.config?.image { let t = CATransition(); t.type = .fade; t.duration = 0.22; g.layer.add(t, forKey: "label") }
        g.configuration = f.config
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.4, options: [.allowUserInteraction, .beginFromCurrentState]) { g.frame = target; g.layoutIfNeeded() } completion: { _ in done() }
        let k = CAKeyframeAnimation(keyPath: "transform.scale.y")
        k.values = [1, 0.9, 1.05, 0.98, 1]; k.keyTimes = [0, 0.25, 0.55, 0.8, 1]; k.duration = 0.45
        k.timingFunction = CAMediaTimingFunction(name: .easeOut)
        g.layer.add(k, forKey: "squash")
      } else {
        // from nothing: it grows in
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3, options: [.allowUserInteraction]) { g.transform = .identity; g.alpha = 1 } completion: { _ in done() }
      }
    } else {
      // to nothing: it shrinks away
      UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) { g.transform = CGAffineTransform(scaleX: 0.4, y: 0.4); g.alpha = 0 } completion: { _ in done() }
    }
  }
}
