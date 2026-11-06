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
    let to: HomeView? = taskPages.isEmpty && lockView == nil ? shownScreen : nil
    guard m.known else { m.known = true; m.screen = to; return }
    guard to !== m.screen else { return }
    let from = m.screen
    m.screen = to
    to?.layoutIfNeeded()
    let place = { (h: HomeView, f: CGRect) -> CGRect in h.convert(f, to: self.view).offsetBy(dx: -h.transform.tx, dy: 0) }
    let a = from.map { ($0, $0.fabNow) }.flatMap { $0.1.shown ? $0 : nil }
    let b = to.map { ($0, $0.fabNow) }.flatMap { $0.1.shown ? $0 : nil }
    // (one change at a time: a stand-in still moving is replaced from where it is)
    var start: CGRect? = nil, startCfg: UIButton.Configuration? = nil, startLight = true
    if let g = m.ghost { start = g.layer.presentation()?.frame ?? g.frame; startCfg = g.configuration; startLight = g.overrideUserInterfaceStyle != .dark; g.removeFromSuperview(); m.ghost = nil; m.unveil() }
    if start == nil, case let (h, f)? = a { start = place(h, f.frame); startCfg = f.config; startLight = f.light }
    if start == nil && b == nil { from?.fabVeiled = false; return }
    // (the same button in the same place: nothing to show)
    if case let (ha, fa)? = a, case let (hb, fb)? = b, fa.label == fb.label, place(ha, fa.frame) == place(hb, fb.frame) { hb.fabVeiled = false; return }

    let g = UIButton(type: .system)
    g.isUserInteractionEnabled = false
    g.accessibilityElementsHidden = true
    if corner.superview === view { view.insertSubview(g, belowSubview: corner) } else { view.insertSubview(g, belowSubview: tabBar) }
    m.ghost = g
    from?.fabVeiled = true; to?.fabVeiled = true; m.veilA = from; m.veilB = to
    let done = { [weak g] in
      guard let g = g, FabMorph.shared.ghost === g else { return }
      g.removeFromSuperview(); FabMorph.shared.ghost = nil; FabMorph.shared.unveil()
    }
    UIView.performWithoutAnimation {
      if let s = start { g.configuration = startCfg; g.overrideUserInterfaceStyle = startLight ? .light : .dark; g.frame = s }
      else if case let (h, f)? = b { g.configuration = f.config; g.overrideUserInterfaceStyle = f.light ? .light : .dark; g.frame = place(h, f.frame); g.transform = CGAffineTransform(scaleX: 0.4, y: 0.4); g.alpha = 0 }
      g.layoutIfNeeded()
    }
    if case let (h, f)? = b {
      let target = place(h, f.frame)
      if start != nil {
        // another button: squash and stretch into its width and place, the words crossfading
        if startCfg?.attributedTitle != f.config?.attributedTitle || startCfg?.image != f.config?.image { let t = CATransition(); t.type = .fade; t.duration = 0.22; g.layer.add(t, forKey: "label") }
        g.configuration = f.config; g.overrideUserInterfaceStyle = f.light ? .light : .dark
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
