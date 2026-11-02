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
    var icon: Double = 1       // (what's on the glass: 🔍 fades as it melts into •••, and in again once it's out)
    var fade = false           // (coming from nothing or going to nothing: iPhone's own "materialize" — not a morph)
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
    ZStack {
      Group {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 6) { spots } } else { spots }
      }
      // (your photo: a layer of its own above the glass container — inside it, even as an overlay, iPhone drew the glass
      //  over the picture: tinted and blurred, Haris 2026-11-02 22:53)
      if m.corner.kind != "none" {
        photoOver(m.corner)
          .frame(width: m.corner.frame.width, height: m.corner.frame.height)
          .opacity(m.corner.opacity)
          .position(x: m.corner.frame.midX, y: m.corner.frame.midY)
      }
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
      // (the middle one: each kind its own glass shape — 🔍 and Mark all read — so iPhone morphs one glass into the other,
      //  the liquid drop way. The corner — your photo, ••• and ✕ — is one glass that stays: what's on it cross-fades.)
      .modifier(GlassLook(id: id == "mid" ? id + "-" + b.kind : id, ns: ns, fade: b.fade, blue: b.kind == "done"))
      .opacity(b.opacity)
      .position(x: b.frame.midX, y: b.frame.midY)
      .id(id == "mid" ? id + "-" + b.kind : id)
      .accessibilityLabel(["back": "Back", "search": "Search", "more": "More", "close": "Close search", "photo": "Me"][b.kind] ?? b.text)
    }
  }
  // your photo: laid over the glass rather than inside it — inside, iPhone's glass treats it as glass content and it
  // was often drawn black until the app was opened again (Haris 2026-11-02); it cross-fades with ••• / ✕ as before
  @ViewBuilder private func photoOver(_ b: CornerModel.B) -> some View {
    ZStack {
      if b.kind == "photo" {
        Group {
          if let img = b.image { Image(uiImage: img).resizable().scaledToFill() } else { Circle().fill(Color.gray.opacity(0.3)) }
        }
        .frame(width: b.frame.width, height: b.frame.height).clipShape(Circle())
        .opacity(b.icon).transition(.opacity)
      }
    }
    .allowsHitTesting(false)
  }
  private func face(_ b: CornerModel.B) -> some View {
    ZStack { faceOf(b).id(b.kind).transition(.opacity) }.opacity(b.icon)
  }
  @ViewBuilder private func faceOf(_ b: CornerModel.B) -> some View {
    switch b.kind {
    case "photo":
      // (the picture itself is on top of the glass, not in it — see photoOver)
      Color.clear.frame(width: b.frame.width, height: b.frame.height).contentShape(Circle())
    case "read", "unread", "done":
      Text(b.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(b.kind == "done" ? Color.white : Color.primary)
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
  let id: String; let ns: Namespace.ID; var fade = false
  var blue = false   // (Done while writing the description: blue glass with white words, so it's seen — Haris 2026-11-02)
  func body(content: Content) -> some View {
    // (a button that comes or goes on its own — ‹ into a task, 🔍 or Mark all read appearing, ✕ in search — forms out of
    //  a blur and settles, iPhone's own Liquid Glass "materialize"; one that turns into another still morphs into it)
    if #available(iOS 26.0, *) { content.glassEffect(blue ? .regular.tint(.blue).interactive() : .regular.interactive(), in: Capsule()).glassEffectID(id, in: ns).glassEffectTransition(fade ? .materialize : .matchedGeometry) }
    else if blue { content.background(Color.blue, in: Capsule()) }
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
  var searchBack = false   // (set just before a change: Home's search bar has just shrunk back into 🔍's circle)
  // Mail's spring; inside it iPhone's glass morphs by itself
  // (a little longer and livelier than Mail's 0.42 / 0.22 — Haris, 2026-11-02: going into a task it was too quick to see)
  static let duration: TimeInterval = 0.6, bounce: CGFloat = 0.3

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
    // (the very same three again — asked once more as a screen settles: nothing touched; setting them again without
    //  animation cut a spring still running short, a jump at its end — Haris's film, 2026-11-02 18:42)
    func same(_ a: Spot, _ b: Spot) -> Bool { a.kind == b.kind && a.text == b.text && a.frame == b.frame && a.image === b.image }
    if !scrubbed && same(was.0, l) && same(was.1, m) && same(was.2, c) { return }   // (after a swipe the drawing is part way: always set)
    left = l; mid = m; corner = c
    // (your photo, the same button, only its picture new: put in without any animation — inside the spring iPhone
    //  cross-faded the two pictures, a blink)
    if c.kind == "photo", was.2.kind == "photo", c.image !== was.2.image { now { model.corner.image = c.image } }
    // (after a swipe back the buttons are already part way, where the finger left them: they just carry on from there
    //  — the pull out of ••• below would start them all over again, Haris 2026-11-02)
    let fromSwipe = scrubbed; scrubbed = false
    // (the same buttons, put a point or two off — worked out again once a screen had settled: in at once, not as a
    //  creep after they'd settled; Haris 2026-11-02)
    func near(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) <= 2.5 && abs(a.minY - b.minY) <= 2.5 && abs(a.width - b.width) <= 2.5 }
    let tiny = !fromSwipe && was.0.kind == l.kind && was.1.kind == m.kind && was.2.kind == c.kind && near(was.0.frame, l.frame) && near(was.1.frame, m.frame) && near(was.2.frame, c.frame)
    let iconWas = model.mid.icon
    // Search opening: Home's own bar starts exactly where 🔍 is and stretches out — 🔍 hands over to it at once; closing,
    // the bar shrinks back into that circle and 🔍 takes over there, in place
    let handOver = !fromSwipe && was.1.kind == "search" && m.kind == "none" && c.kind == "close"
    let takeOver = !fromSwipe && m.kind == "search" && was.1.kind == "none" && (was.2.kind == "close" || searchBack)
    if handOver || takeOver { now { model.mid = b(m) } }
    // coming back from a task: 🔍 starts inside the ••• drop (unseen there), is pulled out of it, and its icon only
    // fades in once it's out — so it never sits on top of ••• (Haris, 2026-11-02)
    let outOfCorner = !fromSwipe && m.kind == "search" && was.1.kind == "none" && was.2.kind == "more" && animated
    if outOfCorner { now { var s = b(m); s.frame = was.2.frame; s.icon = 0; model.mid = s } }
    // (a button going to nothing — not melting into another: marked first, so it leaves the native way; one coming from
    //  nothing is marked as it comes)
    let midMelt = m.kind == "none" && was.1.kind == "search" && c.kind != "none"
    let goes = (left: was.0.kind != "none" && l.kind == "none", mid: was.1.kind != "none" && m.kind == "none" && !midMelt && !handOver && !fromSwipe, corner: was.2.kind != "none" && c.kind == "none")
    let comes = (left: was.0.kind == "none" && l.kind != "none", mid: was.1.kind == "none" && m.kind != "none" && !outOfCorner && !takeOver && !fromSwipe, corner: was.2.kind == "none" && c.kind != "none")
    let marked = animated && (goes.left || goes.mid || goes.corner)
    if marked { now { if goes.left { model.left.fade = true }; if goes.mid { model.mid.fade = true }; if goes.corner { model.corner.fade = true } } }
    let apply = {
      var nl = self.b(l); nl.fade = comes.left; self.model.left = nl
      var nc = self.b(c); nc.fade = comes.corner; self.model.corner = nc
      if !handOver && !takeOver {
        // into a task: 🔍 slides into your photo's glass and stays glass until the two have melted into one drop (then it
        // goes, out of sight inside it); its icon fades on the way; your photo fades into ••• on the same glass
        if !fromSwipe && m.kind == "none" && was.1.kind == "search" && c.kind != "none" { var s = self.b(was.1); s.frame = c.frame; s.icon = 0; self.model.mid = s }
        else if outOfCorner { var s = self.b(m); s.icon = 0; self.model.mid = s }
        else { var s = self.b(m); if fromSwipe && m.kind == "search" { s.icon = iconWas }; s.fade = comes.mid; self.model.mid = s }
      }
    }
    // (a point or two off while the last spring still runs: it carries on to the new place, no jump; once it has
    //  settled: put in at once, no creep)
    if tiny && animated && CACurrentMediaTime() - lastSpring < CornerButton.duration {
      if #available(iOS 17.0, *) { withAnimation(.spring(duration: CornerButton.duration * 0.6, bounce: 0)) { apply() } } else { withAnimation(.easeOut(duration: 0.3)) { apply() } }
      return
    }
    if !animated || tiny { now(apply); if m.kind == "none" { now { model.mid = b(m) } }; return }
    lastSpring = CACurrentMediaTime()
    // (a button marked to leave the native way is drawn so once before it goes: the change waits for the next frame)
    // (coming back — out of the task page's •••, or finishing a swipe back — no bounce: with it 🔍 went a point past its
    //  place and crept back after it seemed to have settled; Haris's film, 2026-11-02 16:46)
    let bounce: CGFloat = (outOfCorner || fromSwipe) ? 0 : CornerButton.bounce
    let spring = {
      if #available(iOS 17.0, *) { withAnimation(.spring(duration: CornerButton.duration, bounce: bounce)) { apply() } }
      else { withAnimation(.spring(response: CornerButton.duration, dampingFraction: 0.78)) { apply() } }
      // (the icon's own fade starts after the change itself — started before a change that waits a frame, it was undone
      //  by it, and 🔍 stayed empty until something else drew it: very late, Haris 2026-11-02)
      if outOfCorner { withAnimation(.easeOut(duration: 0.22).delay(0.16)) { self.model.mid.icon = 1 } }
      // (after a swipe: the icon finishes fading in on its own, after the glass — not at once with the spring)
      if fromSwipe && m.kind == "search" && iconWas < 1 { withAnimation(.easeOut(duration: 0.25).delay(0.08)) { self.model.mid.icon = 1 } }
    }
    if marked { DispatchQueue.main.async(execute: spring) } else { spring() }
    if m.kind == "none" && was.1.kind == "search" && c.kind != "none" {
      DispatchQueue.main.asyncAfter(deadline: .now() + CornerButton.duration) { [weak self] in guard let self = self, self.mid.kind == "none" else { return }; self.now { self.model.mid = self.b(self.mid) } }
    }
  }
  // part way between two sets (the swipe back): t = 0 at `a`, 1 at `b` — straight from the finger, no animation
  private var scrubbed = false
  private var lastSpring: CFTimeInterval = 0
  func between(_ a: (Spot, Spot, Spot), _ z: (Spot, Spot, Spot), _ t: CGFloat) {
    let t = max(0, min(1, t))
    scrubbed = true
    func lerp(_ x: CGRect, _ y: CGRect) -> CGRect { CGRect(x: x.minX + (y.minX - x.minX) * t, y: x.minY + (y.minY - x.minY) * t, width: x.width + (y.width - x.width) * t, height: x.height + (y.height - x.height) * t) }
    func mix(_ x: Spot, _ y: Spot, into: Spot?) -> CornerModel.B {
      if x.kind == "none" && y.kind == "none" { return CornerModel.B() }
      // (its icon only shows once it's well out of the drop, and fades with the finger — no snap, Haris 2026-11-02)
      if x.kind == "none" { var r = b(y, opacity: Double(t)); r.icon = Double(max(0, (t - 0.45) / 0.55)); if let i = into { r.frame = lerp(i.frame, y.frame) }; return r }
      if y.kind == "none" { var r = b(x, opacity: Double(1 - t)); r.icon = Double(max(0, 1 - t / 0.55)); if let i = into { r.frame = lerp(x.frame, i.frame) }; return r }
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
  // (whole points: worked out mid-slide and again once settled, the same place came out a fraction apart, and the
  //  buttons crept by it after they had settled — Haris, 2026-11-02)
  func cornerTarget(skipTop: Bool = false) -> (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot) {
    let t = cornerTargetRaw(skipTop: skipTop)
    func r(_ s: CornerButton.Spot) -> CornerButton.Spot { var x = s; x.frame = CGRect(x: x.frame.minX.rounded(), y: x.frame.minY.rounded(), width: x.frame.width.rounded(), height: x.frame.height.rounded()); return x }
    return (r(t.0), r(t.1), r(t.2))
  }
  private func cornerTargetRaw(skipTop: Bool) -> (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot) {
    let pages = skipTop ? Array(taskPages.dropLast()) : taskPages
    if let p = pages.last {
      if p.cornerFrame.width == 0 { p.setNeedsLayout(); p.layoutIfNeeded() }   // (never aim at a page not laid out yet)
      let f = p.convert(p.cornerFrame, to: view).offsetBy(dx: -p.transform.tx, dy: 0)
      let bf = p.convert(p.backFrame, to: view).offsetBy(dx: -p.transform.tx, dy: 0)
      let mid = p.editingDesc ? CornerButton.Spot(kind: "done", text: "Done", frame: corner.place("done", "Done", circle: f.offsetBy(dx: -56, dy: 0))) : CornerButton.Spot()
      return (CornerButton.Spot(kind: "back", frame: bf), mid, CornerButton.Spot(kind: "more", frame: f))
    }
    if let h = shownScreen { return screenSpots(h) }
    return (CornerButton.Spot(), CornerButton.Spot(), CornerButton.Spot())
  }
  // (one screen's three, wherever it is now — a client's page's and the list's under it, for the edge swipe between them)
  func cornerTargetFor(_ h: HomeView) -> (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot) {
    let t = screenSpots(h)
    func r(_ s: CornerButton.Spot) -> CornerButton.Spot { var x = s; x.frame = CGRect(x: x.frame.minX.rounded(), y: x.frame.minY.rounded(), width: x.frame.width.rounded(), height: x.frame.height.rounded()); return x }
    return (r(t.0), r(t.1), r(t.2))
  }
  private func screenSpots(_ h: HomeView) -> (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot) {
    do {
      let dx = -h.transform.tx
      let c = h.corner()
      let mf = corner.place(c.kind, c.text, circle: h.convert(c.frame, to: view).offsetBy(dx: dx, dy: 0))
      let meF = h.convert(h.meFrame, to: view).offsetBy(dx: dx, dy: 0)
      let cornerSpot = h.searching ? CornerButton.Spot(kind: "close", frame: meF) : CornerButton.Spot(kind: "photo", frame: meF, image: h.meImage)
      // (a client's page: the task page's — ‹ on the left, ••• where your photo is, no 🔍)
      if h.pageBar { return (CornerButton.Spot(kind: "back", frame: h.convert(h.backFrame, to: view).offsetBy(dx: dx, dy: 0)), CornerButton.Spot(), CornerButton.Spot(kind: "more", frame: meF)) }
      // (All Client Assets opened over another screen: ‹ too, with 🔍 and your photo)
      let left = h.backable && !h.searching ? CornerButton.Spot(kind: "back", frame: h.convert(h.backFrame, to: view).offsetBy(dx: dx, dy: 0)) : CornerButton.Spot()
      return (left, CornerButton.Spot(kind: c.kind, text: c.text, frame: mf), cornerSpot)
    }
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
    guard homeIfMade != nil || myTasksIfMade != nil || inboxIfMade != nil || clientsListIfMade != nil || clientPageIfMade != nil || !taskPages.isEmpty || assetsCtl.isOpen else { return }
    for h in [homeIfMade, myTasksIfMade, inboxIfMade, clientsListIfMade, clientPageIfMade].compactMap({ $0 }) where !h.cornerShared { h.cornerShared = true; h.onCorner = { [weak self] in self?.updateCorner() } }
    // (the page's ••• menu ready or changed: only the menu — moving the buttons again here, without the spring, cut
    //  the melt into ••• short as a task opened: build 1275's film)
    for p in taskPages where !p.cornerShared { p.cornerShared = true; p.onMenu = { [weak self, weak p] in if let p = p, p === self?.taskPages.last { self?.corner.items = p.cornerItems } } }
    if corner.superview == nil {
      corner.onLeft = { [weak self] in
        guard let self = self else { return }
        guard let p = self.taskPages.last else { if let h = self.shownScreen, h.backable { UIImpactFeedbackGenerator(style: .light).impactOccurred(); h.backTap() }; return }
        if p.editingDesc { p.finishDesc() }; self.closeTaskPage(p)
      }
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
    let searchBusy = (shownScreen?.searching ?? false) || (shownScreen?.closingSearch ?? false)
    let between = (t.0.kind == "none" && t.1.kind == "none" && t.2.kind == "none") || (t.1.kind == "none" && corner.kind != "none" && !searchBusy)
    // (the search bar just shrank back into its circle: 🔍 takes over right there)
    corner.searchBack = Date().timeIntervalSince(shownScreen?.searchClosedAt ?? .distantPast) < 0.4
    if between && taskPages.isEmpty && corner.kind != "none" && !cornerWaited {
      cornerWaited = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.cornerWaited = false; self?.updateCornerNow(animated: animated) }
      return
    }
    corner.items = taskPages.last?.cornerItems ?? shownScreen?.menuItems ?? []
    corner.go(left: t.0, mid: t.1, corner: t.2, menu: taskPages.last?.cornerMenu, animated: animated && corner.window != nil)
  }
}
