import UIKit
import SwiftUI

/* The top buttons, shared by every screen of the app's own (Haris, 2026-11-01): three Liquid Glass buttons in one
   glass container — so when two come close they melt together like drops of liquid, and part again:
     left    ‹ (a task page)                                  — grows in / shrinks away
     middle  🔍 · Mark all read · Mark all unread · Done      — stretches between a circle and a capsule
     corner  your photo · ••• (its menu opens out of it) · ✕
   Opening a task: 🔍 melts into your photo, the photo turns into •••, ‹ grows in; back: the other way; the swipe from
   the edge in between follows the finger. Each screen only says what its buttons are and where (HomeView.corner(),
   TaskPage.cornerFrame); its own buttons stay invisible. */
/* Built with SwiftUI's own Liquid Glass morphing (Haris, 2026-11-01: "only iOS native animations", "Apple's own
   effect"): the three are glass shapes with glass ids inside one GlassEffectContainer, changed inside a spring — iPhone
   then morphs them itself: they squash and stretch as they change shape and place, melt together when close and pull
   apart. (Glass views inside UIKit's glass container didn't animate their shape at all — the film of build 1265.)
   ••• is a SwiftUI Menu on the glass: its menu grows out of the glass and back. */
struct CornerMenuItem: Identifiable {
  let id = UUID()
  var title: String
  var symbol: String? = nil
  var destructive = false
  var inline = false                 // (its children shown in place, in their own section)
  var children: [CornerMenuItem] = []
  var run: (() -> Void)? = nil
}

final class CornerModel: ObservableObject {
  struct B {
    var kind = "none", text = "", frame = CGRect.zero
    var image: UIImage? = nil
    var opacity: Double = 1
  }
  @Published var left = B()
  @Published var mid = B()
  @Published var corner = B()
  @Published var items: [CornerMenuItem] = []
  var onLeft: (() -> Void)?, onMid: (() -> Void)?, onCorner: (() -> Void)?
}

struct CornerBar: View {
  @ObservedObject var m: CornerModel
  @Namespace private var ns
  var body: some View {
    Group {
      if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 6) { spots } } else { spots }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
  }
  private var spots: some View {
    ZStack {
      Color.clear
      spot(m.left, id: "left") { m.onLeft?() }
      spot(m.mid, id: "mid") { m.onMid?() }
      spot(m.corner, id: "corner") { m.onCorner?() }
    }
  }
  @ViewBuilder private func spot(_ b: CornerModel.B, id: String, tap: @escaping () -> Void) -> some View {
    if b.kind != "none" {
      Group {
        if b.kind == "more" {
          Menu { menu(m.items) } label: { face(b) }
            .buttonStyle(.plain)
        } else {
          Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); tap() } label: { face(b) }
            .buttonStyle(.plain)
        }
      }
      .frame(width: b.frame.width, height: b.frame.height)
      .modifier(GlassLook(id: id, ns: ns))
      .opacity(b.opacity)
      .position(x: b.frame.midX, y: b.frame.midY)
      .accessibilityLabel(["back": "Back", "search": "Search", "more": "More", "close": "Close search", "photo": "Me"][b.kind] ?? b.text)
    }
  }
  @ViewBuilder private func face(_ b: CornerModel.B) -> some View {
    switch b.kind {
    case "photo":
      if let img = b.image { Image(uiImage: img).resizable().scaledToFill().frame(width: b.frame.width, height: b.frame.height).clipShape(Circle()) }
      else { Circle().fill(Color.gray.opacity(0.3)) }
    case "read", "unread", "done":
      Text(b.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(b.kind == "done" ? Color.blue : Color.primary)
        .frame(width: b.frame.width, height: b.frame.height).contentShape(Capsule())
    default:
      let sym = ["back": "chevron.left", "search": "magnifyingglass", "more": "ellipsis", "close": "xmark"][b.kind] ?? "circle"
      Image(systemName: sym).font(.system(size: b.kind == "back" ? 19 : b.kind == "close" ? 17 : 18, weight: .medium)).foregroundStyle(Color.primary)
        .frame(width: b.frame.width, height: b.frame.height).contentShape(Circle())
    }
  }
  private func menu(_ items: [CornerMenuItem]) -> AnyView {
    AnyView(ForEach(items) { it in
      if it.inline { Section { menu(it.children) } }
      else if !it.children.isEmpty { Menu { menu(it.children) } label: { label(it) } }
      else { Button(role: it.destructive ? .destructive : nil) { it.run?() } label: { label(it) } }
    })
  }
  @ViewBuilder private func label(_ it: CornerMenuItem) -> some View {
    if let s = it.symbol { Label(it.title, systemImage: s) } else { Text(it.title) }
  }
}
// the glass, with its id, so iPhone morphs it (before iOS 26: a soft material)
private struct GlassLook: ViewModifier {
  let id: String; let ns: Namespace.ID
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) { content.glassEffect(.regular.interactive(), in: Capsule()).glassEffectID(id, in: ns) }
    else { content.background(.ultraThinMaterial, in: Capsule()) }
  }
}

final class CornerButton: UIView {
  struct Spot { var kind = "none", text = "", frame = CGRect.zero, image: UIImage? = nil }
  private let model = CornerModel()
  private lazy var host: UIHostingController<CornerBar> = {
    let h = UIHostingController(rootView: CornerBar(m: model))
    h.view.backgroundColor = .clear
    if #available(iOS 16.4, *) { h.safeAreaRegions = [] }
    return h
  }()
  private(set) var left = Spot(), mid = Spot(), corner = Spot()
  var onLeft: (() -> Void)?, onMid: ((String) -> Void)?, onCorner: ((String) -> Void)?
  var items: [CornerMenuItem] { get { model.items } set { model.items = newValue } }
  // (what the self-test reads: the corner's ••• on a task page, else the middle one's kind)
  var kind: String { corner.kind == "more" ? "more" : mid.kind }
  // Mail's spring; inside it iPhone's glass morphs by itself
  static let duration: TimeInterval = 0.42, bounce: CGFloat = 0.22

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(host.view)
    model.onLeft = { [weak self] in self?.onLeft?() }
    model.onMid = { [weak self] in guard let self = self else { return }; self.onMid?(self.mid.kind) }
    model.onCorner = { [weak self] in guard let self = self, self.corner.kind != "more" else { return }; self.onCorner?(self.corner.kind) }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); host.view.frame = bounds }
  // only the buttons take touches; the rest of the strip lets them through to the screen
  override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? {
    for s in [corner, mid, left] where s.kind != "none" && s.frame.insetBy(dx: -4, dy: -4).contains(p) { return super.hitTest(p, with: e) }
    return nil
  }

  // what a capsule with words needs; a place for the middle one (a capsule keeps the circle's right edge)
  func width(_ kind: String, _ text: String) -> CGFloat {
    if ["read", "unread", "done"].contains(kind) { return ceil((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width) + 32 }
    return 44
  }
  func place(_ kind: String, _ text: String, circle f: CGRect) -> CGRect { let w = width(kind, text); return CGRect(x: f.maxX - w, y: f.minY, width: w, height: f.height) }

  private func b(_ s: Spot, opacity: Double = 1) -> CornerModel.B { CornerModel.B(kind: s.kind, text: s.text, frame: s.frame, image: s.image, opacity: opacity) }
  private func now(_ change: () -> Void) { var t = Transaction(); t.disablesAnimations = true; withTransaction(t, change) }

  // to these three spots: changed inside Mail's spring — iPhone's glass morphs from one to the next by itself
  func go(left l: Spot, mid m: Spot, corner c: Spot, menu: UIMenu?, animated: Bool) {
    let was = (left, mid, corner)
    left = l; mid = m; corner = c
    // Search opening: Home's own bar starts exactly where 🔍 is and stretches out — 🔍 hands over to it at once; closing,
    // the bar shrinks back into that circle and 🔍 takes over there, in place
    if was.1.kind == "search" && m.kind == "none" && c.kind == "close" { now { model.mid = b(m) } }
    if m.kind == "search" && was.2.kind == "close" && was.1.kind == "none" { now { model.mid = b(m) } }
    let apply = {
      self.model.left = self.b(l); self.model.corner = self.b(c)
      if !(was.1.kind == "search" && m.kind == "none" && c.kind == "close") && !(m.kind == "search" && was.2.kind == "close" && was.1.kind == "none") {
        // 🔍 opening a task: onto your photo as it goes, so the two glasses melt into one (the •••)
        if m.kind == "none" && was.1.kind == "search" && c.kind != "none" { self.model.mid = CornerModel.B(kind: "search", frame: c.frame, opacity: 0) }
        else { self.model.mid = self.b(m) }
      }
    }
    if !animated { now(apply); if m.kind == "none" { now { model.mid = b(m) } }; return }
    if #available(iOS 17.0, *) { withAnimation(.spring(duration: CornerButton.duration, bounce: CornerButton.bounce)) { apply() } }
    else { withAnimation(.spring(response: CornerButton.duration, dampingFraction: 0.78)) { apply() } }
    if m.kind == "none" && was.1.kind == "search" && c.kind != "none" {
      DispatchQueue.main.asyncAfter(deadline: .now() + CornerButton.duration) { [weak self] in guard let self = self, self.mid.kind == "none" else { return }; self.now { self.model.mid = self.b(self.mid) } }
    }
  }
  // part way between two sets (the swipe back): t = 0 at `a`, 1 at `b` — straight from the finger, no animation
  func between(_ a: (Spot, Spot, Spot), _ z: (Spot, Spot, Spot), _ t: CGFloat) {
    let t = max(0, min(1, t))
    func lerp(_ x: CGRect, _ y: CGRect) -> CGRect { CGRect(x: x.minX + (y.minX - x.minX) * t, y: x.minY + (y.minY - x.minY) * t, width: x.width + (y.width - x.width) * t, height: x.height + (y.height - x.height) * t) }
    func mix(_ x: Spot, _ y: Spot, into: Spot?) -> CornerModel.B {
      if x.kind == "none" && y.kind == "none" { return CornerModel.B() }
      if x.kind == "none" { var r = b(y, opacity: Double(t)); if let i = into { r.frame = lerp(i.frame, y.frame) }; return r }
      if y.kind == "none" { var r = b(x, opacity: Double(1 - t)); if let i = into { r.frame = lerp(x.frame, i.frame) }; return r }
      var r = b(t < 0.5 ? x : y); r.frame = lerp(x.frame, y.frame); return r
    }
    now {
      model.left = mix(a.0, z.0, into: nil)
      model.mid = mix(a.1, z.1, into: a.1.kind == "none" ? (a.2.kind != "none" ? a.2 : nil) : (z.2.kind != "none" ? z.2 : nil))
      model.corner = mix(a.2, z.2, into: nil)
    }
  }
}

// ---------- on the app's screen ----------
extension Main {
  // the three spots now: the top task page's, else the shown screen's
  func cornerTarget(skipTop: Bool = false) -> (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot) {
    let pages = skipTop ? Array(taskPages.dropLast()) : taskPages
    if let p = pages.last {
      if p.cornerFrame.width == 0 { p.setNeedsLayout(); p.layoutIfNeeded() }   // (never aim at a page not laid out yet)
      let f = p.convert(p.cornerFrame, to: view).offsetBy(dx: -p.transform.tx, dy: 0)
      let bf = p.convert(p.backFrame, to: view).offsetBy(dx: -p.transform.tx, dy: 0)
      let mid = p.editingDesc ? CornerButton.Spot(kind: "done", text: "Done", frame: corner.place("done", "Done", circle: f.offsetBy(dx: -56, dy: 0))) : CornerButton.Spot()
      return (CornerButton.Spot(kind: "back", frame: bf), mid, CornerButton.Spot(kind: "more", frame: f))
    }
    if let h = shownScreen {
      let dx = -h.transform.tx
      let c = h.corner()
      let mf = corner.place(c.kind, c.text, circle: h.convert(c.frame, to: view).offsetBy(dx: dx, dy: 0))
      let meF = h.convert(h.meFrame, to: view).offsetBy(dx: dx, dy: 0)
      let cornerSpot = h.searching ? CornerButton.Spot(kind: "close", frame: meF) : CornerButton.Spot(kind: "photo", frame: meF, image: h.meImage)
      return (CornerButton.Spot(), CornerButton.Spot(kind: c.kind, text: c.text, frame: mf), cornerSpot)
    }
    return (CornerButton.Spot(), CornerButton.Spot(), CornerButton.Spot())
  }
  // (a tab change hides one screen and shows the next a moment apart: settled together, so it changes in place
  //  rather than going and coming back)
  func updateCorner(animated: Bool = true) {
    if cornerPending { return }
    cornerPending = true
    DispatchQueue.main.async { self.cornerPending = false; self.updateCornerNow(animated: animated) }
  }
  func updateCornerNow(animated: Bool = true) {
    // (only once there's a screen of the app's own to show it on)
    guard homeIfMade != nil || myTasksIfMade != nil || inboxIfMade != nil || !taskPages.isEmpty else { return }
    for h in [homeIfMade, myTasksIfMade, inboxIfMade].compactMap({ $0 }) where !h.cornerShared { h.cornerShared = true; h.onCorner = { [weak self] in self?.updateCorner() } }
    // (the page's ••• menu ready or changed: only the menu — moving the buttons again here, without the spring, cut
    //  the melt into ••• short as a task opened: build 1275's film)
    for p in taskPages where !p.cornerShared { p.cornerShared = true; p.onMenu = { [weak self, weak p] in if let p = p, p === self?.taskPages.last { self?.corner.items = p.cornerItems } } }
    if corner.superview == nil {
      corner.onLeft = { [weak self] in guard let self = self, let p = self.taskPages.last else { return }; if p.editingDesc { p.finishDesc() }; self.closeTaskPage(p) }
      corner.onMid = { [weak self] k in if k == "done" { self?.taskPages.last?.finishDesc(); return }; self?.shownScreen?.cornerTap(k) }
      corner.onCorner = { [weak self] k in guard let h = self?.shownScreen else { return }; if k == "close" { h.closeSearch() } else { h.meTap() } }
    }
    // (a strip across the top, above the screens and task pages, under sheets and the tab bar)
    let strip = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.safeAreaInsets.top + 60)
    if corner.frame != strip { corner.frame = strip }
    // (put in once, and never taken out again: re-inserting it took it off the screen and back, so iPhone drew the
    //  glass afresh — the buttons blurred out and in on every change (build 1273's film). Task pages go under it.)
    if corner.superview !== view { view.insertSubview(corner, belowSubview: tabBar) }
    else if let i = view.subviews.firstIndex(of: corner), view.subviews[(i + 1)...].contains(where: { $0 is HomeView || $0 is TaskPage }) {
      // (a screen made later went on top of it — My Tasks or the Inbox the first time: only then is it moved back up)
      view.bringSubviewToFront(corner); view.bringSubviewToFront(tabBar)
    }
    if lockView != nil { corner.alpha = 0; return }
    corner.alpha = 1
    let t = cornerTarget()
    // (between two screens — a tab change hides one a moment before the next shows — nothing is there for an instant:
    //  the buttons wait for the next screen instead of vanishing and coming back; seen in build 1271's film)
    let between = (t.0.kind == "none" && t.1.kind == "none" && t.2.kind == "none") || (t.1.kind == "none" && corner.kind != "none" && !(shownScreen?.searching ?? false))
    if between && taskPages.isEmpty && corner.kind != "none" && !cornerWaited {
      cornerWaited = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.cornerWaited = false; self?.updateCornerNow(animated: animated) }
      return
    }
    corner.items = taskPages.last?.cornerItems ?? []
    corner.go(left: t.0, mid: t.1, corner: t.2, menu: taskPages.last?.cornerMenu, animated: animated && corner.window != nil)
  }
}
