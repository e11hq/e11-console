import UIKit
import CoreImage

// (who's in the pictures and who has a photo: redrawn when that changes — a photo arriving later too)
func picsKey(_ p: [String: [String: Any]]) -> String { p.keys.sorted().map { $0 + (p[$0]?["photo"] != nil ? "+" : "") }.joined(separator: ",") }

/* ================= Home (E11 Day / My Day), drawn by the app itself (23+, Haris 2026-10-31) =================
   The same page as the website's phone Home (phone.js myDay / card, phone.css .ph-head / .ph-stats / .ph-gh / .pc),
   only scrolled and tapped by iPhone itself. The page stays the engine: it sends what to show — the header, the three
   boxes, the groups and their task cards, and the colours of its own Home drawn under this one (light / dark) — with
   the "home" command whenever something changes (NativeHome in phone.js), and the taps go back to it
   (window.__e11Home: open a task, Search, Me, New task). */
final class HomeView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UITextFieldDelegate {
  var onEvent: (([String: Any]) -> Void)?
  var present: ((UIViewController) -> Void)?
  private var canDelete = false
  private weak var openCard: HomeCard?
  private var actions: HomeActions?
  private var toastView: UIView?
  /* The header (Haris, 2026-10-31, as Mail): at the top the big title with the date over it; as the list scrolls it
     shrinks as it rises into a small bar — the small title with the date under it — and the cards pass under it
     through a soft blur. Search is a Liquid Glass circle that stretches into a glass search bar; your photo then
     turns into a glass ✕ that closes it. */
  private let blur = UIVisualEffectView(effect: nil), hairline = UIView(), blurMask = CAGradientLayer()
  // the bar's own row (the small title on it): on iOS 26+ iPhone's own scroll edge effect frosts the list under it, as in Mail
  private let topBar = HomePassThrough(), topLine = UIView()
  private var edgeHook: AnyObject?
  /* Mail's own measures (Haris, 2026-10-31, from his Mail screenshots): the bar's buttons 44 pt, 16 from the right
     edge, 12 apart, their middle 22 under the status bar; the bar 54 under it; the small title 17 semibold with the
     line under it 12 regular; the big title 34 bold, 16 from the left, the line under it 15 regular; system colours */
  private let R: CGFloat = 16, BTN: CGFloat = 44
  private let sub = UILabel(), title = UILabel(), smallTitle = UILabel(), smallSub = UILabel()
  private let searchCircle = HomeGlass(), me = UIButton(type: .custom), closeCircle = HomeGlass()
  private let searchBar = HomeGlass(), field = UITextField(), lens = UIImageView()
  private let results = UIScrollView(), hint = UILabel()
  private var resultViews: [UIView] = [], resultCards: [String: HomeCard] = [:]
  private(set) var searching = false
  private var findTimer: Timer?, keyboardH: CGFloat = 0
  private let scroll = UIScrollView()
  private let fab = UIButton(type: .system)
  // at the end of the list, beside "+ New task": "YOUR OWN CREATIVE AGENCY" — it fades in (0.5 s) once
  // the list has reached its end, and out again on scrolling back (Haris, 2026-10-31)
  private let motto = UILabel()
  private var mottoOn = false
  private var stats: [UIView] = []
  private var content: [UIView] = []
  private var cards: [String: HomeCard] = [:]
  private var m: [String: Any] = [:]
  private var L = HomeLook(nil)
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { cards.values.forEach { $0.people = people }; meChanged() } } }
  private var meId = ""
  var bottomRoom: CGFloat = 120 { didSet { if oldValue != bottomRoom { setNeedsLayout() } } }
  // the top of the app's tab bar: the + sits 14 above it, 18 from the right (phone.css .ph-fab), so it's in place from
  // the first frame — not where the page had it a moment before the tab bar came (it jumped up, Haris 2026-10-31)
  // (the room under the list's last card: up to 12 above "+ New task", which sits 14 above the tab bar)
  private var endRoom: CGFloat { tabTop.map { bounds.height - ($0 - 14 - BTN) + 12 } ?? bottomRoom }
  var tabTop: CGFloat? { didSet { if oldValue != tabTop { setNeedsLayout() } } }

  override init(frame: CGRect) {
    super.init(frame: frame)
    scroll.alwaysBounceVertical = true
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.delegate = self
    addSubview(scroll)
    // the search results (in place of the list while searching)
    results.alwaysBounceVertical = true; results.contentInsetAdjustmentBehavior = .never; results.keyboardDismissMode = .onDrag
    results.alpha = 0; results.isHidden = true
    hint.font = .systemFont(ofSize: 15); hint.numberOfLines = 0; hint.textAlignment = .center; results.addSubview(hint)
    addSubview(results)
    blur.isUserInteractionEnabled = false
    // (the bar once scrolled: frosted glass with a soft line under it, as Mail's)
    blur.contentView.addSubview(hairline)
    blur.alpha = 0
    blurMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    blur.layer.mask = blurMask
    addSubview(blur)
    addSubview(topBar)
    topLine.alpha = 0; topBar.addSubview(topLine)   // (the soft line under the bar, as Mail's)
    if #available(iOS 26.0, *) {
      blur.isHidden = true
      let i = UIScrollEdgeElementContainerInteraction()
      i.scrollView = scroll; i.edge = .top
      topBar.addInteraction(i)
      edgeHook = i
      scroll.topEdgeEffect.style = .soft
      results.topEdgeEffect.style = .soft
    }
    sub.font = .systemFont(ofSize: 15)
    title.font = .systemFont(ofSize: 34, weight: .bold)
    title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.6
    smallTitle.font = .systemFont(ofSize: 17, weight: .semibold); smallSub.font = .systemFont(ofSize: 12)
    smallTitle.alpha = 0; smallSub.alpha = 0
    // (the big title scrolls with the list and goes under the frosted bar; the small title is on the bar)
    // (the big date and title are the list's own first lines: they scroll with it, under the frosted edge)
    scroll.addSubview(sub); scroll.addSubview(title)
    [smallTitle, smallSub].forEach { topBar.addSubview($0) }
    searchCircle.setIcon("magnifyingglass", 18)
    searchCircle.accessibilityLabel = "Search"
    searchCircle.onTap = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.openSearch() }
    me.clipsToBounds = true
    me.accessibilityLabel = "Me"
    me.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "me"]) }, for: .touchUpInside)
    closeCircle.setIcon("xmark", 17)
    closeCircle.accessibilityLabel = "Close search"
    closeCircle.onTap = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.closeSearch() }
    closeCircle.alpha = 0; closeCircle.isHidden = true
    // the search bar: a glass capsule with the lens and the text field
    lens.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
    lens.contentMode = .center
    field.font = .systemFont(ofSize: 17)
    field.delegate = self
    field.returnKeyType = .search; field.autocorrectionType = .no; field.clearButtonMode = .whileEditing
    field.addAction(UIAction { [weak self] _ in self?.typed() }, for: .editingChanged)
    field.addAction(UIAction { [weak self] _ in self?.field.resignFirstResponder() }, for: .editingDidEndOnExit)
    searchBar.content.addSubview(lens); searchBar.content.addSubview(field)
    searchBar.isHidden = true
    [searchCircle, me, searchBar, closeCircle].forEach { addSubview($0) }
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
      guard let self = self, let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
      let r = self.convert(end, from: nil)
      self.keyboardH = max(0, self.bounds.maxY - r.minY); self.setNeedsLayout()
    }
    nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in self?.keyboardH = 0; self?.setNeedsLayout() }
    // "+ New task": a Liquid Glass capsule the size of Mail's "Select" (iOS 26's own glass button; before: a grey capsule)
    var fc: UIButton.Configuration
    if #available(iOS 26.0, *) { fc = .glass() } else { fc = .gray(); fc.cornerStyle = .capsule }
    fc.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    fc.imagePadding = 6
    fc.attributedTitle = AttributedString("New task", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    fc.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 18)
    fc.baseForegroundColor = .label
    fab.configuration = fc
    fab.accessibilityLabel = "New task"
    fab.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "add"]) }, for: .touchUpInside)
    addSubview(fab)
    for i in 0..<3 {
      let v = UIView(); v.layer.cornerRadius = 18; v.layer.borderWidth = 1; let n = UILabel(), l = UILabel(); n.tag = 1; l.tag = 2; v.addSubview(n); v.addSubview(l); scroll.addSubview(v); stats.append(v)
      // (tapped: Due today / Overdue bring their group up to where the big title is; In review opens My Tasks waiting
      //  for the CD's review — Haris, 2026-10-31)
      let tap = UITapGestureRecognizer(target: self, action: #selector(statTap(_:))); v.tag = 100 + i; v.addGestureRecognizer(tap)
      v.isAccessibilityElement = true; v.accessibilityTraits = .button
    }
  }
  required init?(coder: NSCoder) { fatalError() }

  private func send(_ ev: [String: Any]) {
    var e = ev; e["y"] = Int((scroll.contentOffset.y + scroll.contentInset.top).rounded())
    onEvent?(e)
  }

  // ---------- what the page sent ----------
  func update(_ model: [String: Any]) {
    m = model
    L = HomeLook(model["look"] as? [String: Any])
    backgroundColor = L.bg
    // (the system's own text colours, as Mail: label for the titles, secondary label for the lines under them)
    overrideUserInterfaceStyle = L.light ? .light : .dark
    sub.text = model["date"] as? String; sub.textColor = .secondaryLabel
    title.attributedText = NSAttributedString(string: model["title"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.label])
    smallTitle.text = model["title"] as? String; smallTitle.textColor = .label
    smallSub.text = model["date"] as? String; smallSub.textColor = .secondaryLabel
    blur.effect = UIBlurEffect(style: L.light ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark)
    hairline.backgroundColor = L.light ? UIColor.black.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.08)
    topLine.backgroundColor = hairline.backgroundColor
    [searchCircle, closeCircle, searchBar].forEach { $0.setLook(light: L.light, tint: L.roundIc) }
    lens.tintColor = L.sub; field.textColor = L.h1; field.tintColor = L.tag
    field.attributedPlaceholder = NSAttributedString(string: "Search tasks, clients, people", attributes: [.foregroundColor: L.sub])
    field.keyboardAppearance = L.light ? .light : .dark
    hint.textColor = L.empty
    meId = model["me"] as? String ?? ""; meChanged()
    let st = model["stats"] as? [Int] ?? [0, 0, 0]
    let names = ["Due today", "Overdue", "In review"], cols = [L.statG, L.statR, L.statA]
    for (i, v) in stats.enumerated() {
      v.backgroundColor = L.statBg; v.layer.borderColor = L.statLine.cgColor
      v.layer.shadowOpacity = 0   // (no drop shadows on boxes or cards — Haris, 2026-10-31)
      let n = v.viewWithTag(1) as? UILabel, l = v.viewWithTag(2) as? UILabel
      n?.text = "\(st.indices.contains(i) ? st[i] : 0)"; n?.font = .systemFont(ofSize: 34, weight: .bold); n?.textColor = cols[i]   // (as Mail's big title)
      l?.text = names[i]; l?.font = .systemFont(ofSize: 12); l?.textColor = L.statLabel
    }
    // the groups: their headers, cards (kept by task, so a change doesn't redraw the rest) and "nothing due" lines
    content.forEach { if !($0 is HomeCard) { $0.removeFromSuperview() } }
    content = []
    var seen = Set<String>()
    for g in model["groups"] as? [[String: Any]] ?? [] {
      let h = UILabel()
      let name = (g["name"] as? String ?? "").uppercased()
      let s = NSMutableAttributedString(string: name, attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .kern: 0.72, .foregroundColor: L.gh])
      if let n = g["n"] as? Int, n > 0 {
        s.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 12), .kern: 3.6]))
        s.append(NSAttributedString(string: "\(n)", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: L.gh.withAlphaComponent(0.8)]))
      }
      h.attributedText = s; h.tag = 7; h.accessibilityIdentifier = g["name"] as? String
      scroll.addSubview(h); content.append(h)
      for c in g["cards"] as? [[String: Any]] ?? [] {
        guard let id = c["id"] as? String else { continue }
        seen.insert(id)
        let v: HomeCard
        if let old = cards[id] { v = old } else {
          v = HomeCard(); v.id = id
          v.onTap = { [weak self, weak v] in
            guard let self = self else { return }
            // (a card swiped open: a tap closes it, as in Mail)
            if let o = self.openCard { self.setOpen(o, false); if o === v { return } }
            self.send(["ev": "open", "id": id])
          }
          let pan = UIPanGestureRecognizer(target: self, action: #selector(self.swipe(_:))); pan.delegate = self; v.addGestureRecognizer(pan)
          let lp = UILongPressGestureRecognizer(target: self, action: #selector(self.press(_:))); lp.minimumPressDuration = 0.45; v.addGestureRecognizer(lp)
          self.scroll.addSubview(v); self.cards[id] = v
        }
        v.people = people
        v.set(c, look: L)
        content.append(v)
      }
      if let e = g["empty"] as? String, !e.isEmpty {
        let l = UILabel(); l.text = e; l.font = .systemFont(ofSize: 14); l.textColor = L.empty; l.tag = 8; l.numberOfLines = 0
        scroll.addSubview(l); content.append(l)
      }
    }
    for (id, v) in cards where !seen.contains(id) { if v === openCard { actions?.removeFromSuperview(); actions = nil; openCard = nil }; v.removeFromSuperview(); cards[id] = nil }
    canDelete = (model["canDelete"] as? Bool) == true
    if let t = model["toast"] as? [String: Any] { toast(t) }
    fab.isHidden = (model["add"] as? Bool) != true

    setNeedsLayout(); layoutIfNeeded()
  }
  private func meChanged() {
    let p = people[meId]
    let img = roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 44)
    me.setImage(img, for: .normal)
  }

  // ---------- where things go ----------
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    let bigH = bigHead
    // the list runs the full height, under the header; it starts below the big header
    if scroll.frame != bounds { scroll.frame = bounds }
    if scroll.contentInset.top != bigH { let s0 = scroll.contentOffset.y + scroll.contentInset.top; scroll.contentInset.top = bigH; scroll.contentOffset.y = s0 - bigH }
    layoutHeader()
    results.frame = CGRect(x: 0, y: searchBar.frame.maxY + 8, width: W, height: H - searchBar.frame.maxY - 8)
    results.contentInset.bottom = max(keyboardH, bottomRoom - 60)
    results.contentInset.top = 12   // (clear of the blur under the search bar)
    layoutResults()
    // the three boxes (.ph-stats: 4 above, 6 below, 8 apart)
    var y: CGFloat = 4
    let bw = (W - 32 - 16) / 3, bh: CGFloat = 1 + 10 + 41 + 15 + 12 + 1
    for (i, v) in stats.enumerated() {
      v.frame = CGRect(x: 16 + CGFloat(i) * (bw + 8), y: y, width: bw, height: bh)
      v.viewWithTag(1)?.frame = CGRect(x: 13, y: 11, width: bw - 26, height: 41)
      v.viewWithTag(2)?.frame = CGRect(x: 13, y: 11 + 41, width: bw - 26, height: 15)
    }
    y += bh + 6
    // the list (.ph-list: 16 from the sides, 10 between things; a group's title 12 lower than that)
    let lw = W - 32
    for (i, v) in content.enumerated() {
      if i > 0 { y += 10 }
      if v.tag == 7 {
        y += 12
        v.frame = CGRect(x: 20, y: y, width: lw - 8, height: 15)
        y += 15
      } else if v.tag == 8 {
        let h = (v as? UILabel)?.sizeThatFits(CGSize(width: lw - 8, height: 400)).height ?? 17
        v.frame = CGRect(x: 20, y: y + 14, width: lw - 8, height: h)
        y += 14 + h + 14
      } else if let c = v as? HomeCard {
        let h = c.height(for: lw)
        // (bounds and centre: a card swiped open keeps its sideways shift)
        c.bounds = CGRect(x: 0, y: 0, width: lw, height: h); c.center = CGPoint(x: 16 + lw / 2, y: y + h / 2)
        if c === openCard, let a = actions { a.frame = CGRect(x: a.leading ? 16 : 16 + lw - a.frame.width, y: y, width: a.frame.width, height: h) }
        y += h
      }
    }
    // (the list ends with its last card 12 above "+ New task", so nothing is hidden behind it and no empty third of the
    //  screen is left under it — Haris, 2026-10-31; while scrolling the cards still pass under the + and the tab bar)
    scroll.contentSize = CGSize(width: W, height: y + endRoom)
    // (a list that got shorter — a task deleted — never leaves the view scrolled past its end, showing nothing)
    let maxY = max(-scroll.contentInset.top, scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height)
    if !scroll.isDragging && !scroll.isDecelerating && scroll.contentOffset.y > maxY + 1 { scroll.setContentOffset(CGPoint(x: 0, y: maxY), animated: true) }
    // the + button where the page has it
    // "+ New task": 44 tall like Mail's buttons, 16 from the right, 14 above the tab bar
    let fw = ceil(fab.sizeThatFits(CGSize(width: 300, height: BTN)).width)
    fab.frame = CGRect(x: W - R - fw, y: (tabTop ?? H - 100) - 14 - BTN, width: fw, height: BTN)
    // (in the room left of the +, its middle level with the +'s)
    if motto.superview == nil {
      // (Haris, 2026-10-31: in capitals, 9 pt medium, letter spacing 2.4, the frost bar date's grey)
      motto.attributedText = NSAttributedString(string: "YOUR OWN CREATIVE AGENCY", attributes: [.font: UIFont.systemFont(ofSize: 9, weight: .medium), .kern: 2.4, .foregroundColor: UIColor.secondaryLabel])
      motto.textAlignment = .center
      motto.adjustsFontSizeToFitWidth = true; motto.minimumScaleFactor = 0.7
      motto.alpha = 0; motto.isUserInteractionEnabled = false
      insertSubview(motto, belowSubview: fab)
    }
    motto.frame = CGRect(x: 16, y: fab.frame.midY - 16, width: max(0, fab.frame.minX - 12 - 16), height: 32)
    showMotto()
  }
  func scrollToTop() { scroll.setContentOffset(CGPoint(x: 0, y: -scroll.contentInset.top), animated: true) }
  func scrollViewDidScroll(_ scrollView: UIScrollView) { if scrollView === scroll { layoutHeader(); showMotto() } }
  // the list at its end (or too short to scroll), Home not searching, no toast beside the + — the motto shows
  private func showMotto() {
    let end = max(-scroll.contentInset.top, scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height)
    let want = !searching && !fab.isHidden && toastView == nil && scroll.contentOffset.y >= end - 2
    guard want != mottoOn else { return }
    mottoOn = want
    UIView.animate(withDuration: 0.5, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.motto.alpha = want ? 1 : 0 }
  }

  // ---------- the header (as Mail): the big title scrolls with the list, under a frosted bar that comes as it goes ----------
  // (where the list's boxes start: under the big title and its line, 18 below them — as Mail's filters)
  private var bigHead: CGFloat { safeAreaInsets.top + 66 + 41 + 1 + 19 + 18 - 4 }
  // (the bar's row: its middle 28 under the status bar, 14 of room under the 46 pt buttons — Haris: they sat on its edge)
  private var smallHead: CGFloat { safeAreaInsets.top + 54 }
  private func ease(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { let x = min(1, max(0, (t - a) / (b - a))); return x * x * (3 - 2 * x) }
  // (how far the list has scrolled)
  private var scrolled: CGFloat { scroll.contentOffset.y + scroll.contentInset.top }
  // (0 big … 1 small: as Mail, once the big title has scrolled up under the bar's row — its baseline past the bar's
  // lower edge — the bar switches over in one quick move, not with the scroll — Haris, 2026-10-31)
  private var barIn = false
  private var shrink: CGFloat { barIn ? 1 : 0 }
  // (Mail switches once its big title is up in the bar's row, under the buttons: its top at the status bar)
  private var pastBig: Bool { scrolled > 62 }
  // Mail's blur fade, measured frame by frame (Haris, 2026-10-31): over 0.5 s (Haris chose 0.5; Mail ~0.3) the big title's blur builds up as it
  // fades; the small title comes in very blurred and see-through ~10 pt low, rises and sharpens, its line just after;
  // the frost comes in the first few frames. Driven frame by frame (0 big … 1 small), so a quick scroll back reverses it
  // from wherever it is.
  private var barK: CGFloat = 0
  private var barLink: CADisplayLink?, barT: CFTimeInterval = 0
  private let barDur: CGFloat = 0.5   // (Haris, 2026-10-31: 0.5 s)
  private var fades: [ObjectIdentifier: HomeBlurFade] = [:]
  private func fade(_ l: UILabel) -> HomeBlurFade {
    if let f = fades[ObjectIdentifier(l)] { return f }
    let f = HomeBlurFade(l); fades[ObjectIdentifier(l)] = f; return f
  }
  private func easeOut(_ x: CGFloat) -> CGFloat { let t = min(1, max(0, x)); return 1 - pow(1 - t, 3) }
  private func applyBar() {
    let tr = traitCollection
    if searching {
      fades.values.forEach { $0.clear() }
      smallTitle.alpha = 0; smallSub.alpha = 0; title.alpha = 1; sub.alpha = 1
      return
    }
    let k = barK, k2 = max(0, min(1, (k - 0.12) / 0.88))
    fade(smallTitle).set(blur: 8 * (1 - ease(0.1, 0.8, k)), alpha: ease(0.02, 0.55, k), dy: 10 * (1 - easeOut(k)), trait: tr)
    fade(smallSub).set(blur: 8 * (1 - ease(0.1, 0.8, k2)), alpha: ease(0.02, 0.55, k2), dy: 10 * (1 - easeOut(k2)), trait: tr)
    fade(title).set(blur: 8 * ease(0, 0.6, k), alpha: 1 - ease(0.15, 0.7, k), dy: 0, trait: tr)
    fade(sub).set(blur: 8 * ease(0, 0.6, k), alpha: 1 - ease(0.1, 0.6, k), dy: 0, trait: tr)
  }
  @objc private func barTick() {
    let now = CACurrentMediaTime(), dt = CGFloat(min(now - barT, 1.0 / 30)); barT = now
    let target: CGFloat = barIn ? 1 : 0, step = dt / barDur
    barK = target > barK ? min(target, barK + step) : max(target, barK - step)
    applyBar()
    if barK == target { barLink?.invalidate(); barLink = nil }
  }
  // the bar switching over (the frost and its line, the small title and date in; the big ones out) — or back
  private func setBar(_ on: Bool, now: Bool = false) {
    barIn = on
    if #available(iOS 26.0, *) {
      UIView.animate(withDuration: now ? 0 : 0.25) { self.scroll.topEdgeEffect.isHidden = !on; self.topLine.alpha = on ? 1 : 0 }
    } else {
      UIView.animate(withDuration: now ? 0 : 0.25) { self.blur.alpha = on ? 1 : 0 }
    }
    if now { barLink?.invalidate(); barLink = nil; barK = on ? 1 : 0; applyBar(); return }
    if barLink == nil {
      barT = CACurrentMediaTime()
      let l = CADisplayLink(target: self, selector: #selector(barTick))
      if #available(iOS 15.0, *) { l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120) }
      l.add(to: .main, forMode: .common); barLink = l
    }
  }
  private func layoutHeader() {
    let W = bounds.width
    let bigH = bigHead, smallH = smallHead, top = safeAreaInsets.top
    let titleY = top + 66   // (the big title's top, as Mail's)
    // the bar's frost: iPhone's own scroll edge effect under the bar's row (iOS 26+), there once the list moves under it;
    // before iOS 26 a thin see-through blur that softens out at its lower edge
    topBar.frame = CGRect(x: 0, y: 0, width: W, height: smallH)
    // (it comes the moment the big title has gone under the bar, as Mail's — Haris, 2026-10-31)
    if !searching && pastBig != barIn { setBar(pastBig) }
    if #available(iOS 26.0, *) {
      if let i = edgeHook as? UIScrollEdgeElementContainerInteraction { let want: UIScrollView = searching ? results : scroll; if i.scrollView !== want { i.scrollView = want } }
      let hide = !searching && !barIn
      if scroll.topEdgeEffect.isHidden != hide { UIView.animate(withDuration: 0.25) { self.scroll.topEdgeEffect.isHidden = hide } }
      topLine.frame = CGRect(x: 0, y: smallH - 0.5, width: W, height: 0.5)
      topLine.alpha = searching || !barIn ? 0 : 1
    } else {
      blur.frame = CGRect(x: 0, y: 0, width: W, height: smallH + 14)
      CATransaction.begin(); CATransaction.setDisableActions(true)
      blurMask.frame = blur.bounds; blurMask.locations = [0, NSNumber(value: Double(smallH / (smallH + 14))), 1]
      CATransaction.commit()
      hairline.frame = CGRect(x: 0, y: smallH - 0.5, width: W, height: 0.5)
      blur.alpha = searching || barIn ? 1 : 0
    }
    // (the scroll bar on the right runs from the bar's lower edge down, never up beside it — as Mail's; set here, not by iPhone)
    if scroll.automaticallyAdjustsScrollIndicatorInsets { scroll.automaticallyAdjustsScrollIndicatorInsets = false }
    // (… down to just above the tab bar, as Mail's)
    scroll.verticalScrollIndicatorInsets = UIEdgeInsets(top: smallH, left: 0, bottom: tabTop.map { bounds.height - $0 + 8 } ?? bottomRoom - 20, right: 0)
    // the big date and title: the list's own first lines (above its top, in the room it keeps for them)
    let tw = W - 16 - R
    // (bounds and centre, not frame: the blur fade moves them with a transform)
    func place(_ l: UILabel, _ r: CGRect) { l.bounds = CGRect(origin: .zero, size: r.size); l.center = CGPoint(x: r.midX, y: r.midY) }
    place(title, CGRect(x: 16, y: titleY - bigH, width: tw, height: 41))
    place(sub, CGRect(x: 16, y: titleY + 41 + 1 - bigH, width: tw, height: 19))
    // the small title and date on the bar: there once the big ones have gone under it (gone while searching, under its bar)
    let smallCY = top + 22
    let stw = W - 16 - R - BTN - 12 - BTN - 12
    place(smallTitle, CGRect(x: 16, y: top + 1, width: stw, height: 21)); place(smallSub, CGRect(x: 16, y: top + 25, width: stw, height: 15))
    applyBar()
    // Search and your photo: with the title until they reach the bar, then they stay on it
    // (Search and your photo stay on the bar's row from the start — they don't move with the list — Haris, 2026-10-31)
    let cy = smallCY
    if !searching {
      me.bounds = CGRect(x: 0, y: 0, width: BTN, height: BTN); me.center = CGPoint(x: W - R - BTN / 2, y: cy); me.layer.cornerRadius = BTN / 2
      searchCircle.frame = CGRect(x: W - R - BTN - 12 - BTN, y: cy - BTN / 2, width: BTN, height: BTN)
    } else {
      // (the bar in the row the buttons are in; the ✕ where your photo was)
      searchBar.frame = CGRect(x: 16, y: cy - BTN / 2, width: W - 16 - BTN - 12 - R, height: BTN)
      closeCircle.frame = CGRect(x: W - R - BTN, y: cy - BTN / 2, width: BTN, height: BTN)
    }
    lens.frame = CGRect(x: 12, y: 0, width: 22, height: searchBar.bounds.height)
    field.frame = CGRect(x: 40, y: 0, width: max(0, searchBar.bounds.width - 40 - 10), height: searchBar.bounds.height)
  }
  // the field's own ✕: clears what's typed (and the results)
  func textFieldShouldClear(_ textField: UITextField) -> Bool { DispatchQueue.main.async { self.typed() }; return true }

  // ---------- search: the glass circle stretches into a search bar, your photo becomes a glass ✕ ----------
  func openSearch() {
    if searching { field.becomeFirstResponder(); return }
    if let o = openCard { setOpen(o, false) }
    let start = searchCircle.frame, meF = me.frame
    searching = true
    showMotto()
    searchBar.frame = start; searchBar.isHidden = false; searchBar.alpha = 1
    searchBar.layer.cornerRadius = start.height / 2
    closeCircle.frame = meF; closeCircle.isHidden = false; closeCircle.alpha = 0
    closeCircle.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
    searchCircle.alpha = 0
    results.isHidden = false
    field.text = ""; showResults(nil)
    UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
      self.layoutHeader()
      self.searchBar.layer.cornerRadius = self.BTN / 2
      self.me.alpha = 0; self.me.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
      self.closeCircle.alpha = 1; self.closeCircle.transform = .identity
      self.scroll.alpha = 0; self.results.alpha = 1; self.fab.alpha = 0
      self.results.frame.origin.y = self.searchBar.frame.maxY + 8
    }
    field.becomeFirstResponder()
  }
  func closeSearch() {
    guard searching else { return }
    field.resignFirstResponder()
    findTimer?.invalidate()
    searching = false
    showMotto()
    setNeedsLayout(); layoutIfNeeded()
    let back = searchCircle.frame
    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3, options: [.allowUserInteraction]) {
      self.searchBar.frame = back; self.searchBar.layer.cornerRadius = back.height / 2
      self.lens.frame = CGRect(x: 12, y: 0, width: 22, height: back.height)
      self.field.alpha = 0
      self.closeCircle.alpha = 0; self.closeCircle.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
      self.me.alpha = 1; self.me.transform = .identity
      self.scroll.alpha = 1; self.results.alpha = 0; self.fab.alpha = 1
      self.layoutHeader()
    } completion: { _ in
      if self.searching { return }
      self.searchBar.isHidden = true; self.closeCircle.isHidden = true; self.field.alpha = 1
      self.searchCircle.alpha = 1; self.results.isHidden = true
      self.field.text = ""; self.showResults(nil)
    }
  }
  private func typed() {
    findTimer?.invalidate()
    let q = field.text ?? ""
    if q.trimmingCharacters(in: .whitespaces).isEmpty { showResults(nil); return }
    findTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in self?.onEvent?(["ev": "find", "q": q]) }
  }
  // what the page found for the bar (the search command): clients, then tasks — in the cards of Home
  func searchResults(_ r: [String: Any]) {
    guard searching, (r["q"] as? String) == field.text else { return }
    showResults(r)
  }
  private func showResults(_ r: [String: Any]?) {
    resultViews.forEach { $0.removeFromSuperview() }
    resultViews = []
    var seen = Set<String>()
    let q = (field.text ?? "").trimmingCharacters(in: .whitespaces)
    if let r = r {
      let clients = r["clients"] as? [[String: Any]] ?? [], tasks = r["tasks"] as? [[String: Any]] ?? []
      if !clients.isEmpty {
        resultViews.append(groupHead("Clients", clients.count))
        for c in clients {
          let row = HomeClientRow(); row.set(c, look: L)
          let id = c["id"] as? String ?? ""
          row.addAction(UIAction { [weak self] _ in self?.field.resignFirstResponder(); self?.send(["ev": "client", "id": id]) }, for: .touchUpInside)
          results.addSubview(row); resultViews.append(row)
        }
      }
      if !tasks.isEmpty {
        resultViews.append(groupHead("Tasks", (r["total"] as? Int) ?? tasks.count))
        for c in tasks {
          guard let id = c["id"] as? String else { continue }
          seen.insert(id)
          let v: HomeCard
          if let old = resultCards[id] { v = old } else {
            v = HomeCard(); v.id = id
            v.onTap = { [weak self] in self?.field.resignFirstResponder(); self?.send(["ev": "open", "id": id]) }
            resultCards[id] = v
          }
          v.people = people; v.set(c, look: L)
          results.addSubview(v); resultViews.append(v)
        }
      }
      hint.text = clients.isEmpty && tasks.isEmpty ? "No tasks found. Try a client or person’s name." : nil
    } else { hint.text = q.isEmpty ? "Search tasks, clients or people." : nil }
    for (id, v) in resultCards where !seen.contains(id) { v.removeFromSuperview(); resultCards[id] = nil }
    setNeedsLayout()
  }
  private func groupHead(_ name: String, _ n: Int) -> UILabel {
    let h = UILabel(); h.tag = 7
    let s = NSMutableAttributedString(string: name.uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .kern: 0.72, .foregroundColor: L.gh])
    s.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 12), .kern: 3.6]))
    s.append(NSAttributedString(string: "\(n)", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: L.gh.withAlphaComponent(0.8)]))
    h.attributedText = s
    results.addSubview(h)
    return h
  }
  private func layoutResults() {
    let W = bounds.width, lw = W - 32
    var y: CGFloat = 0
    // (the hint: just under the search bar, in the middle of the page)
    if let t = hint.text, !t.isEmpty { let h = hint.sizeThatFits(CGSize(width: lw, height: 400)).height; hint.frame = CGRect(x: 16, y: 0, width: lw, height: h); y = h + 14 } else { hint.frame = .zero }
    for (i, v) in resultViews.enumerated() {
      if i > 0 { y += 10 }
      if v.tag == 7 { y += i > 0 ? 12 : 4; v.frame = CGRect(x: 20, y: y, width: lw - 8, height: 15); y += 15 }
      else if let c = v as? HomeCard { let h = c.height(for: lw); c.bounds = CGRect(x: 0, y: 0, width: lw, height: h); c.center = CGPoint(x: 16 + lw / 2, y: y + h / 2); y += h }
      else { v.frame = CGRect(x: 16, y: y, width: lw, height: 70); y += 70 }
    }
    results.contentSize = CGSize(width: W, height: y + 20)
  }
  @objc private func statTap(_ g: UITapGestureRecognizer) {
    guard let v = g.view, !searching else { return }
    if let o = openCard { setOpen(o, false) }
    UIView.animate(withDuration: 0.08, animations: { v.transform = CGAffineTransform(scaleX: 0.96, y: 0.96) }) { _ in UIView.animate(withDuration: 0.15) { v.transform = .identity } }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let i = v.tag - 100
    if i == 2 { send(["ev": "review"]); return }
    showGroup(i == 0 ? "Today" : "Overdue")
  }
  // a group's heading brought up to where the big title is (as far as the list goes)
  func showGroup(_ name: String) {
    guard let h = content.first(where: { $0.tag == 7 && $0.accessibilityIdentifier == name }) else { return }
    let want = h.frame.minY - (safeAreaInsets.top + 66)
    let maxY = max(-scroll.contentInset.top, scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height)
    scroll.setContentOffset(CGPoint(x: 0, y: min(maxY, max(-scroll.contentInset.top, want))), animated: true)
  }
  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { if scrollView === scroll { layoutHeader() } }
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { if let o = openCard { setOpen(o, false) } }

  // ---------- swipe left on a card: Copy link · Delete; swipe right: Done · Due (as in Mail: round buttons with their names
  // under them) ----------
  private func leadOK(_ card: HomeCard) -> Bool { (card.info["canDone"] as? Bool) == true || (card.info["canDue"] as? Bool) == true }
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard let p = g as? UIPanGestureRecognizer, let card = p.view as? HomeCard else { return true }
    let v = p.velocity(in: self)
    return abs(v.x) > abs(v.y) * 1.2 && (v.x < 0 || card.swipeX != 0 || leadOK(card))
  }
  private func reveal(_ leading: Bool) -> CGFloat {
    let n = leading ? max(1, actions?.leading == true ? actions!.count : 2) : (canDelete ? 2 : 1)
    return 20 + CGFloat(n) * 64
  }
  // (+1: the card slid right, Done · Due on its left; -1: slid left, Copy link · Delete on its right)
  private var openSide: CGFloat { (openCard?.swipeX ?? 0) > 0 ? 1 : -1 }
  private func actionsFor(_ card: HomeCard, leading: Bool) -> HomeActions {
    if let a = actions, openCard === card, a.leading == leading { return a }
    actions?.removeFromSuperview()
    let a: HomeActions
    if leading {
      let d = card.info
      a = HomeActions(done: (d["done"] as? Bool) == true, showDone: (d["canDone"] as? Bool) == true, due: d["due"] as? String, showDue: (d["canDue"] as? Bool) == true, cdHold: (d["cdHold"] as? Bool) == true)
    } else { a = HomeActions(delete: canDelete, light: L.light) }
    let w = 20 + CGFloat(a.count) * 64
    a.frame = CGRect(x: leading ? card.center.x - card.bounds.width / 2 : card.center.x + card.bounds.width / 2 - w, y: card.center.y - card.bounds.height / 2, width: w, height: card.bounds.height)
    a.onCopy = { [weak self, weak card] in
      guard let self = self, let card = card else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      self.send(["ev": "copy", "id": card.id]); self.setOpen(card, false)
    }
    a.onDelete = { [weak self, weak card] in
      guard let self = self, let card = card else { return }
      // (asked first: the task goes to the Trash)
      let al = UIAlertController(title: "Delete this task?", message: card.taskTitle.isEmpty ? nil : card.taskTitle, preferredStyle: .actionSheet)
      al.addAction(UIAlertAction(title: "Delete Task", style: .destructive) { _ in self.send(["ev": "delete", "id": card.id]); self.setOpen(card, false) })
      al.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in self.setOpen(card, false) })
      al.overrideUserInterfaceStyle = self.L.light ? .light : .dark
      self.present?(al)
    }
    // Done: green at once (grey again when a done task is reopened), then the card closes and the page does the rest — as
    // its own tick: a task not ready to complete only shows why (the circle stays grey), Undo on the toast
    a.onDone = { [weak self, weak card, weak a] in
      guard let self = self, let card = card else { return }
      let wasDone = (card.info["done"] as? Bool) == true, ready = (card.info["doneReady"] as? Bool) == true
      if wasDone || ready {
        a?.markDone(!wasDone)
        if !wasDone { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + (wasDone || ready ? 0.35 : 0)) {
        self.send(["ev": "done", "id": card.id, "done": !wasDone]); self.setOpen(card, false)
      }
    }
    // Due: the card closes and the page opens the date sheet the task page uses
    a.onDue = { [weak self, weak card] in
      guard let self = self, let card = card else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      self.send(["ev": "due", "id": card.id]); self.setOpen(card, false)
    }
    scroll.insertSubview(a, belowSubview: card)
    actions = a; openCard = card
    return a
  }
  private var swipeLead = false
  @objc private func swipe(_ g: UIPanGestureRecognizer) {
    guard let card = g.view as? HomeCard else { return }
    switch g.state {
    case .began:
      if let o = openCard, o !== card { setOpen(o, false) }
      card.swipeStart = card.swipeX
      swipeLead = card.swipeX != 0 ? card.swipeX > 0 : g.velocity(in: self).x > 0
      if swipeLead && !leadOK(card) { swipeLead = false }
      _ = actionsFor(card, leading: swipeLead)
    case .changed:
      var x = card.swipeStart + g.translation(in: self).x
      let r = reveal(swipeLead)
      if swipeLead {
        if x < 0 { x = 0 }
        if x > r { x = r + (x - r) / 3 }   // (past the buttons: held back)
      } else {
        if x > 0 { x = 0 }
        if x < -r { x = -r + (x + r) / 3 }
      }
      card.swipeX = x
      actions?.progress = min(1, abs(x) / r)
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: self).x, r = reveal(swipeLead)
      if swipeLead { setOpen(card, v > 350 || (card.swipeX > r / 2 && v > -300), leading: true) }
      else { setOpen(card, v < -350 || (card.swipeX < -r / 2 && v < 300), leading: false) }
    default: break
    }
  }
  func setOpen(_ card: HomeCard, _ open: Bool, leading: Bool? = nil) {
    let lead = leading ?? (openCard === card ? openSide > 0 : false)
    if open { _ = actionsFor(card, leading: lead) }
    let a = actions, r = reveal(lead)
    UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
      card.swipeX = open ? (lead ? r : -r) : 0
      a?.progress = open ? 1 : 0
    } completion: { _ in
      if !open && card.swipeX == 0 && self.openCard === card { a?.removeFromSuperview(); if self.actions === a { self.actions = nil }; self.openCard = nil }
    }
  }

  // ---------- long press a card: Attach Files (Camera · Photos · Files), the card lifted over the dimmed screen ----------
  @objc private func press(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began, let card = g.view as? HomeCard else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    attach(card)
  }
  private func attach(_ card: HomeCard) {
    if let o = openCard { setOpen(o, false) }
    card.isHighlighted = false
    let id = card.id
    let sheet = AttachSheetVC(light: L.light, title: "Attach Files") { [weak self] src in self?.send(["ev": "attach", "id": id, "source": src]) }
    if let snap = card.snapshotView(afterScreenUpdates: true) {
      sheet.lifted = snap; sheet.liftedFrame = card.convert(card.bounds, to: nil)
    }
    present?(sheet)
  }

  // ---------- a toast over Home (the page's own would be under it): "Link copied", "2 files added to …", Undo ----------
  func toast(_ t: [String: Any]) {
    toastView?.removeFromSuperview()
    let text = t["t"] as? String ?? "", act = t["a"] as? String ?? ""
    let v = UIView(); v.backgroundColor = L.light ? .white : SplashView.hex(0x2b2c31); v.layer.cornerRadius = 10
    v.layer.borderWidth = 1; v.layer.borderColor = (L.light ? UIColor.black.withAlphaComponent(0.1) : UIColor.white.withAlphaComponent(0.12)).cgColor
    v.layer.shadowColor = UIColor.black.cgColor; v.layer.shadowOpacity = 0.3; v.layer.shadowRadius = 12; v.layer.shadowOffset = CGSize(width: 0, height: 6)
    let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: 14); l.textColor = L.title; l.numberOfLines = 2
    v.addSubview(l)
    var bw: CGFloat = 0
    var b: UIButton?
    if !act.isEmpty {
      let btn = UIButton(type: .system); btn.setTitle(act, for: .normal); btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold); btn.tintColor = L.tag
      btn.addAction(UIAction { [weak self, weak v] _ in v?.removeFromSuperview(); if self?.toastView === v { self?.toastView = nil }; self?.showMotto(); self?.onEvent?(["ev": "toast"]) }, for: .touchUpInside)
      v.addSubview(btn); b = btn; bw = btn.sizeThatFits(CGSize(width: 200, height: 40)).width + 14
    }
    // (low, just above the tab bar: beside the +, its bottom level with the +'s — Haris: it sat far too high)
    let W = bounds.width
    let room = fab.isHidden ? W - 32 : fab.frame.minX - 12 - 16
    let maxL = room - 28 - bw
    let ls = l.sizeThatFits(CGSize(width: maxL, height: 60))
    let w = min(room, ls.width + 28 + bw), h = max(44, ls.height + 18)
    let bottom = fab.isHidden ? (tabTop ?? bounds.height - 40) - 12 : fab.frame.maxY
    v.frame = CGRect(x: 16, y: bottom - h, width: w, height: h)
    l.frame = CGRect(x: 14, y: (h - ls.height) / 2, width: ls.width, height: ls.height)
    b?.frame = CGRect(x: w - bw, y: 0, width: bw - 4, height: h)
    v.alpha = 0; v.transform = CGAffineTransform(translationX: 0, y: 8)
    addSubview(v); toastView = v
    showMotto()
    UIView.animate(withDuration: 0.16) { v.alpha = 1; v.transform = .identity }
    let ms = (t["ms"] as? Double) ?? 3000
    DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000) { [weak v] in
      guard let v = v else { return }
      UIView.animate(withDuration: 0.2, animations: { v.alpha = 0 }) { [weak self] _ in v.removeFromSuperview(); if self?.toastView === v { self?.toastView = nil }; self?.showMotto() }
    }
  }
  // (for the self-test: the first card swiped open, held, closed)
  private var firstCard: HomeCard? { content.compactMap { $0 as? HomeCard }.first }
  func selfSwipe() { if let c = firstCard { setOpen(c, true) } }
  func selfPress() { if let c = firstCard { attach(c) } }
  func selfSwipeRight() { if let c = firstCard { setOpen(c, true, leading: true) } }
  func selfClose() { if let o = openCard { setOpen(o, false) } }
  func selfScroll(_ y: CGFloat) { scroll.setContentOffset(CGPoint(x: 0, y: y - scroll.contentInset.top), animated: false); layoutHeader(); setBar(barIn, now: true) }
  func selfFind(_ q: String) { openSearch(); field.text = q; typed() }
  func selfFindDone() { closeSearch() }
  func geo() -> [String: Any] {
    ["open": openCard != nil, "openShift": openCard?.swipeX ?? 0, "actions": actions?.subviews.count ?? 0, "lead": actions?.leading ?? false,
     "title": title.text ?? "", "date": sub.text ?? "", "stats": stats.map { ($0.viewWithTag(1) as? UILabel)?.text ?? "" },
     "groups": content.filter { $0.tag == 7 }.map { ($0 as? UILabel)?.text ?? "" }, "cards": cards.count, "fab": !fab.isHidden,
     "headH": blur.frame.height, "shrink": shrink, "bar": blur.alpha, "smallTitle": smallTitle.alpha, "searching": searching,
     "searchBarW": searchBar.isHidden ? 0 : searchBar.frame.width, "results": resultViews.count, "light": L.light]
  }
}

// the colours the page's own Home uses (phone.css), read from it; dark / light defaults when a piece isn't on it
struct HomeLook {
  let light: Bool
  let bg, headBg, sub, h1, round, roundIc, statBg, statLine, statLabel, statG, statR, statA, gh, empty: UIColor
  let card, cardLine, lateLine, title, meta, sep, late, today, doneTitle, tag, tagBg, urgent, urgentBg, more, moreBg, fabBg, fabLine: UIColor
  let headH: CGFloat?, fabRect: CGRect?
  init(_ d: [String: Any]?) {
    let lt = (d?["light"] as? Bool) ?? false
    light = lt
    func c(_ k: String, _ dark: UIColor, _ lightC: UIColor) -> UIColor {
      guard let a = d?[k] as? [NSNumber], a.count >= 3 else { return lt ? lightC : dark }
      return UIColor(red: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: a.count > 3 ? CGFloat(a[3].doubleValue) : 1)
    }
    let w = UIColor.white, k = UIColor.black
    bg = c("bg", SplashView.hex(0x0c0d0f), SplashView.hex(0xf4f4f7)); headBg = c("headBg", bg, bg)
    // (every grey on the app's own screens is the date's grey: iPhone's secondary label — Haris, 2026-10-31)
    let grey = UIColor.secondaryLabel
    sub = grey; h1 = c("h1", SplashView.hex(0xe9eaee), SplashView.hex(0x17181b))
    round = c("round", w.withAlphaComponent(0.08), k.withAlphaComponent(0.05)); roundIc = c("roundIc", h1, h1)
    statBg = c("statBg", w.withAlphaComponent(0.06), w.withAlphaComponent(0.7)); statLine = c("statLine", w.withAlphaComponent(0.12), w)
    statLabel = grey
    statG = c("statG", SplashView.hex(0x3ddc97), SplashView.hex(0x1a9e63)); statR = c("statR", SplashView.hex(0xff7a7a), SplashView.hex(0xd9363e)); statA = c("statA", SplashView.hex(0xf9be33), SplashView.hex(0xb57d00))
    gh = grey; empty = grey
    card = c("card", SplashView.hex(0x121317), w); cardLine = c("cardLine", SplashView.hex(0x1d1f24), .clear)
    lateLine = c("lateLine", UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.45), UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.45))
    title = c("title", SplashView.hex(0xe9eaee), SplashView.hex(0x17181b)); meta = grey
    sep = grey; late = c("late", SplashView.hex(0xff8a8a), SplashView.hex(0xd9363e)); today = c("today", SplashView.hex(0x8fbcff), SplashView.hex(0x2f6fd6))
    doneTitle = grey
    tag = c("tag", SplashView.hex(0xc9c0ff), SplashView.hex(0x5b4bd6)); tagBg = c("tagBg", UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.18), UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.14))
    urgent = c("urgent", SplashView.hex(0xff9494), SplashView.hex(0xd9363e)); urgentBg = c("urgentBg", UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.16), UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.12))
    more = grey; moreBg = c("moreBg", w.withAlphaComponent(0.08), k.withAlphaComponent(0.06))
    let f = d?["fab"] as? [String: Any]
    func fc(_ k: String, _ dflt: UIColor) -> UIColor {
      guard let a = f?[k] as? [NSNumber], a.count >= 3 else { return dflt }
      return UIColor(red: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: a.count > 3 ? CGFloat(a[3].doubleValue) : 1)
    }
    fabBg = fc("bg", SplashView.hex(0x5b4bd6)); fabLine = fc("line", .clear)
    if let r = f?["rect"] as? [NSNumber], r.count == 4, r[2].doubleValue > 0 { fabRect = CGRect(x: r[0].doubleValue, y: r[1].doubleValue, width: r[2].doubleValue, height: r[3].doubleValue) } else { fabRect = nil }
    headH = (d?["headH"] as? NSNumber).map { CGFloat($0.doubleValue) }
  }
}

// one task card (phone.js card(), phone.css .pc)
final class HomeCard: UIControl {
  var onTap: (() -> Void)?
  var id = ""
  var taskTitle: String { c["title"] as? String ?? "" }
  var info: [String: Any] { c }
  var swipeStart: CGFloat = 0
  // (sideways when swiped open; pressed in a little while touched — both at once)
  var swipeX: CGFloat = 0 { didSet { applyTransform() } }
  private func applyTransform() {
    let s: CGFloat = isHighlighted ? 0.985 : 1
    transform = CGAffineTransform(translationX: swipeX, y: 0).scaledBy(x: s, y: s)
  }
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { drawPeople() } } }
  private let icon = UIImageView(), titleL = UILabel(), metaL = UILabel(), chip = UIView(), chipL = UILabel(), badge = UILabel(), avs = UIView()
  private var c: [String: Any] = [:]
  private var L = HomeLook(nil)
  private var stackW: CGFloat = 0
  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 20; layer.borderWidth = 1
    titleL.numberOfLines = 0; metaL.numberOfLines = 0
    chip.layer.cornerRadius = 4; chip.addSubview(chipL)
    badge.layer.cornerRadius = 6; badge.clipsToBounds = true; badge.textAlignment = .center
    [icon, titleL, metaL, chip, badge, avs].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
    addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
  }
  required init?(coder: NSCoder) { fatalError() }
  // (.pc:active: pressed in a little)
  override var isHighlighted: Bool { didSet { if oldValue != isHighlighted { UIView.animate(withDuration: 0.08) { self.applyTransform() } } } }

  func set(_ d: [String: Any], look: HomeLook) {
    c = d; L = look
    let late = (d["late"] as? Bool) == true, done = (d["done"] as? Bool) == true
    backgroundColor = L.card
    layer.borderColor = (late ? L.lateLine : L.cardLine).cgColor
    layer.shadowOpacity = 0
    let t = d["title"] as? String ?? ""
    let ps = NSMutableParagraphStyle(); ps.minimumLineHeight = 20.15; ps.maximumLineHeight = 20.15
    var ta: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15.5, weight: t.isEmpty ? .medium : .semibold), .foregroundColor: done || t.isEmpty ? L.doneTitle : L.title, .paragraphStyle: ps, .baselineOffset: 1.5]
    if t.isEmpty { ta[.font] = UIFont.italicSystemFont(ofSize: 15.5) }
    if done { ta[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    titleL.attributedText = NSAttributedString(string: t.isEmpty ? "Untitled task" : t, attributes: ta)
    // the CD chip (CD Review / ✓ CD Approved) at the end of the line under the title, on its last line when it fits
    // (Haris, 2026-10-31: "1 comment" and the chip together)
    let ml = NSMutableAttributedString(attributedString: meta(d["meta"] as? [[String: Any]] ?? []))
    if let cd = d["cd"] as? [String: Any] {
      let img = HomeCard.cdChip(cd["t"] as? String ?? "", check: (cd["check"] as? Bool) == true, color: NativeSheetVC.color(cd["rgb"]) ?? .systemYellow)
      let a = NSTextAttachment(); a.image = img
      let f = UIFont.systemFont(ofSize: 12.5)
      a.bounds = CGRect(x: 0, y: ((f.capHeight - img.size.height) / 2).rounded(), width: img.size.width, height: img.size.height)
      // (after the comments on the second line; with no comments, the second line is the chip's own)
      let hasCm = (d["meta"] as? [[String: Any]] ?? []).contains(where: HomeCard.isComments)
      if ml.length > 0 { ml.append(NSAttributedString(string: hasCm ? " " : "\n", attributes: hasCm ? [.font: f, .kern: 4.9] : [.font: f])) }
      ml.append(NSAttributedString(attachment: a))
    }
    metaL.attributedText = ml
    icon.image = HomeCard.statusIcon(d["icon"] as? [String: Any])
    chip.isHidden = true
    // Urgent, or the priority number
    if let b = d["badge"] as? [String: Any] {
      let u = (b["urgent"] as? Bool) == true
      badge.isHidden = false
      badge.attributedText = NSAttributedString(string: b["t"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: u ? L.urgent : L.tag])
      badge.backgroundColor = u ? L.urgentBg : L.tagBg
    } else { badge.isHidden = true }
    drawPeople()
    setNeedsLayout()
  }
  static func isComments(_ it: [String: Any]) -> Bool {
    if (it["cm"] as? Bool) == true { return true }
    let t = (it["t"] as? String ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
    return t.hasSuffix(" comment") || t.hasSuffix(" comments")
  }
  // the line under the title: client (with its colour), status, due date, comments — 6 apart, "·" between
  private func meta(_ items: [[String: Any]]) -> NSAttributedString {
    let f = UIFont.systemFont(ofSize: 12.5)
    let s = NSMutableAttributedString()
    // (as the page wraps it: whole pieces only — "3 comments" never split — and a "·" stays at the end of its line)
    let gap = { (breaks: Bool) in NSAttributedString(string: breaks ? " " : "\u{00A0}", attributes: [.font: f, .kern: 2.9]) }
    // (the comments always start the second line, the CD chip after them — the same on every card, Haris 2026-10-31)
    for (i, it) in items.enumerated() {
      let cm = HomeCard.isComments(it)
      if i > 0 && cm { s.append(NSAttributedString(string: "\n", attributes: [.font: f])) }
      else if i > 0 { s.append(gap(false)); s.append(NSAttributedString(string: "·", attributes: [.font: f, .foregroundColor: L.sep])); s.append(gap(true)) }
      if let dot = NativeSheetVC.color(it["dot"]) {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in dot.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 8, height: 8), cornerRadius: 2).fill() }
        let a = NSTextAttachment(); a.image = img; a.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        s.append(NSAttributedString(attachment: a)); s.append(gap(false))
      }
      let b = it["b"] as? String
      let col = b == "late" ? L.late : b == "today" ? L.today : L.meta
      s.append(NSAttributedString(string: (it["t"] as? String ?? "").replacingOccurrences(of: " ", with: "\u{00A0}"), attributes: [.font: b != nil ? UIFont.systemFont(ofSize: 12.5, weight: .semibold) : f, .foregroundColor: col]))
    }
    let ps = NSMutableParagraphStyle(); ps.lineSpacing = 1
    s.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: s.length))
    return s
  }
  // the assignees' pictures (two, overlapping, ringed in the card's colour; a green tick when their part is done) and "+N"
  private func drawPeople() {
    avs.subviews.forEach { $0.removeFromSuperview() }
    let list = c["av"] as? [[String: Any]] ?? []
    var x: CGFloat = 0
    func ringed(_ img: UIImage) -> UIView {
      let r = UIView(frame: CGRect(x: x - 2, y: -2, width: 26, height: 26)); r.backgroundColor = L.card; r.layer.cornerRadius = 13
      let iv = UIImageView(image: img); iv.frame = CGRect(x: 2, y: 2, width: 22, height: 22); r.addSubview(iv)
      return r
    }
    for a in list {
      let id = a["id"] as? String ?? ""
      let p = people[id]
      let v = ringed(roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 22))
      if (a["done"] as? Bool) == true {
        let t = UIView(frame: CGRect(x: 13, y: 13, width: 16, height: 16))
        t.backgroundColor = L.card; t.layer.cornerRadius = 8
        let g = UIView(frame: CGRect(x: 2, y: 2, width: 12, height: 12)); g.backgroundColor = SplashView.green; g.layer.cornerRadius = 6
        let ck = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .black)))
        ck.tintColor = SplashView.hex(0x0b1d14); ck.frame = CGRect(x: 2, y: 2, width: 8, height: 8); ck.contentMode = .center
        g.addSubview(ck); t.addSubview(g); v.addSubview(t)
      }
      avs.addSubview(v)
      x += 16
    }
    if let n = c["more"] as? Int, n > 0 {
      let r = UIView(frame: CGRect(x: x - 2, y: -2, width: 26, height: 26)); r.backgroundColor = L.card; r.layer.cornerRadius = 13
      let l = UILabel(frame: CGRect(x: 2, y: 2, width: 22, height: 22)); l.text = "+\(n)"; l.font = .systemFont(ofSize: 9.5, weight: .semibold); l.textColor = L.more
      l.backgroundColor = L.moreBg; l.layer.cornerRadius = 11; l.clipsToBounds = true; l.textAlignment = .center
      r.addSubview(l); avs.addSubview(r); x += 16
    }
    // (22 for the first, 16 more for each next one: they overlap by 6)
    stackW = x > 0 ? x + 6 : 0
    avs.frame.size = CGSize(width: stackW, height: 22)
    setNeedsLayout()
  }
  // (.pc: 14 inside, the icon 22 on the left, 12 to the text, the badge and pictures on the right)
  private func sideSize() -> CGSize {
    var w: CGFloat = 0, h: CGFloat = 0
    if !badge.isHidden { let s = badge.attributedText?.size() ?? .zero; w = ceil(s.width) + 14; h = ceil(s.height) + 6 }
    if stackW > 0 { w = max(w, stackW); h += (h > 0 ? 6 : 0) + 22 }
    return CGSize(width: w, height: h)
  }
  private func bodyHeight(_ bw: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    let th = ceil(titleL.sizeThatFits(CGSize(width: bw, height: 1000)).height)
    let mh = ceil(metaL.sizeThatFits(CGSize(width: bw, height: 1000)).height)
    return (th, mh, 0)
  }
  func height(for w: CGFloat) -> CGFloat {
    let side = sideSize()
    let bw = w - 1 - 14 - 22 - 12 - (side.width > 0 ? side.width + 12 : 0) - 14 - 1
    let (th, mh, ch) = bodyHeight(bw)
    let body = th + 5 + mh + (ch > 0 ? 5 + ch : 0)
    return 1 + 14 + max(23, body, side.height) + 14 + 1
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width
    icon.frame = CGRect(x: 15, y: 16, width: 22, height: 22)
    let side = sideSize()
    let bx: CGFloat = 15 + 22 + 12
    let bw = w - bx - (side.width > 0 ? side.width + 12 : 0) - 15
    let (th, mh, ch) = bodyHeight(bw)
    titleL.frame = CGRect(x: bx, y: 15, width: bw, height: th)
    metaL.frame = CGRect(x: bx, y: 15 + th + 5, width: bw, height: mh)
    if ch > 0 {
      let cs = chipL.attributedText?.size() ?? .zero
      chip.frame = CGRect(x: bx + 8, y: metaL.frame.maxY + 5, width: ceil(cs.width) + 12, height: ch)
      chipL.frame = CGRect(x: 6, y: 0, width: ceil(cs.width) + 2, height: ch)
    }
    var y: CGFloat = 15
    if !badge.isHidden { let s = badge.attributedText?.size() ?? .zero; badge.frame = CGRect(x: w - 15 - ceil(s.width) - 14, y: y, width: ceil(s.width) + 14, height: ceil(s.height) + 6); y = badge.frame.maxY + 6 }
    if stackW > 0 { avs.frame = CGRect(x: w - 15 - stackW, y: y, width: stackW, height: 22) }
  }
  // the CD chip (app.css .cd-chip): 10.5 bold in the CD colour on a 16% wash, 4 round, a tick before "CD Approved" —
  // the tick and the words on one centre line
  static func cdChip(_ text: String, check: Bool, color: UIColor) -> UIImage {
    let f = UIFont.systemFont(ofSize: 10.5, weight: .bold)
    let ts = (text as NSString).size(withAttributes: [.font: f])
    let tick: CGFloat = check ? 10 + 3 : 0
    let size = CGSize(width: ceil(6 + tick + ts.width + 6), height: 16)
    return UIGraphicsImageRenderer(size: size).image { _ in
      color.withAlphaComponent(0.16).setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4).fill()
      if check, let ck = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))?.withTintColor(color, renderingMode: .alwaysOriginal) {
        ck.draw(in: CGRect(x: 6 + (10 - ck.size.width) / 2, y: (16 - ck.size.height) / 2, width: ck.size.width, height: ck.size.height))
      }
      (text as NSString).draw(at: CGPoint(x: 6 + tick, y: (16 - ts.height) / 2), withAttributes: [.font: f, .foregroundColor: color])
    }
  }
  // the status icon, in SF Symbols (Haris, 2026-10-31): to do — a dashed circle; under way — a half-filled circle; nearly
  // there (the later statuses) — a filled circle in a ring; done — a filled circle with a tick. In the status's colour.
  static func statusIcon(_ d: [String: Any]?) -> UIImage {
    let col = NativeSheetVC.color(d?["rgb"]) ?? .systemGray
    let kind = d?["kind"] as? String ?? "todo"
    let frac = CGFloat((d?["frac"] as? NSNumber)?.doubleValue ?? 0.5)
    let name = kind == "done" ? "checkmark.circle.fill" : kind == "todo" ? "circle.dashed" : frac < 0.6 ? "circle.lefthalf.filled" : "circle.inset.filled"
    let cfg = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
    let sym = UIImage(systemName: name, withConfiguration: cfg)?.withTintColor(col, renderingMode: .alwaysOriginal) ?? UIImage()
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
      sym.draw(in: CGRect(x: (22 - sym.size.width) / 2, y: (22 - sym.size.height) / 2, width: sym.size.width, height: sym.size.height))
    }
  }
}

// the buttons a swiped card shows: Copy link (grey) and Delete (red, for those who may), round with their names under
final class HomeActions: UIView {
  var onCopy: (() -> Void)?, onDelete: (() -> Void)?, onDone: (() -> Void)?, onDue: (() -> Void)?
  let leading: Bool
  private var items: [UIView] = []
  private(set) var doneBtn: UIButton?
  var progress: CGFloat = 0 { didSet { items.forEach { $0.alpha = progress; $0.transform = CGAffineTransform(scaleX: 0.6 + 0.4 * progress, y: 0.6 + 0.4 * progress) } } }
  static let grey = SplashView.hex(0x8a8d96), green = SplashView.hex(0x30d158), purple = SplashView.hex(0x7a6ff0), orange = SplashView.hex(0xff9f0a)
  private func item(_ name: String, _ col: UIColor, sym: String? = nil, inner: UIView? = nil, _ act: @escaping () -> Void) -> (UIView, UIButton) {
    let v = UIView()
    let b = UIButton(type: .custom)
    b.backgroundColor = col; b.layer.cornerRadius = 26; b.tintColor = .white
    if let sym = sym { b.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal) }
    b.frame = CGRect(x: 0, y: 0, width: 52, height: 52)
    if let inner = inner { inner.isUserInteractionEnabled = false; inner.frame = b.bounds; b.addSubview(inner) }
    b.addAction(UIAction { _ in act() }, for: .touchUpInside)
    b.accessibilityLabel = name
    let l = UILabel(); l.text = name; l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabel; l.textAlignment = .center
    l.frame = CGRect(x: -14, y: 58, width: 80, height: 15)
    v.addSubview(b); v.addSubview(l)
    v.bounds = CGRect(x: 0, y: 0, width: 52, height: 73)
    return (v, b)
  }
  // swiped left (trailing): Copy link · Delete
  init(delete: Bool, light: Bool) {
    leading = false
    super.init(frame: .zero)
    items.append(item("Copy link", HomeActions.grey, sym: "link", { [weak self] in self?.onCopy?() }).0)
    if delete { items.append(item("Delete", SplashView.hex(0xe5484d), sym: "trash", { [weak self] in self?.onDelete?() }).0) }
    items.forEach { addSubview($0) }
    progress = 0
  }
  // swiped right (leading), as Mail's Unread · Remind Me: Done (grey, green once done) · Due (the day big, the month under
  // it; SET with a calendar when there's none) — Haris, 2026-10-31
  init(done: Bool, showDone: Bool, due: String?, showDue: Bool, cdHold: Bool = false) {
    leading = true
    super.init(frame: .zero)
    if showDone && cdHold {
      // held by the CD's review: a faded orange "CD" · Review — a tap says why (Haris, 2026-10-31)
      let cd = UILabel(); cd.text = "CD"; cd.font = .systemFont(ofSize: 16, weight: .bold); cd.textColor = .white; cd.textAlignment = .center
      let (v, b) = item("Review", HomeActions.orange, inner: cd, { [weak self] in self?.onDone?() })
      b.alpha = 0.42
      (v.subviews.compactMap { $0 as? UILabel }.first)?.textColor = .tertiaryLabel
      items.append(v)
    } else if showDone {
      let (v, b) = item("Done", done ? HomeActions.green : HomeActions.grey, sym: "checkmark", { [weak self] in self?.onDone?() })
      doneBtn = b; items.append(v)
    }
    if showDue {
      let inner = UIView()
      let top = UILabel(), bot = UILabel()
      top.textColor = .white; bot.textColor = .white; top.textAlignment = .center; bot.textAlignment = .center
      if let d = due, d.count >= 10, let day = Int(d.dropFirst(8).prefix(2)), let mon = Int(d.dropFirst(5).prefix(2)), (1...12).contains(mon) {
        top.text = "\(day)"; top.font = .systemFont(ofSize: 21, weight: .bold)
        bot.text = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][mon - 1]; bot.font = .systemFont(ofSize: 10, weight: .semibold)
        top.frame = CGRect(x: 0, y: 8, width: 52, height: 24); bot.frame = CGRect(x: 0, y: 31, width: 52, height: 12)
        inner.addSubview(top)
      } else {
        let cal = UIImageView(image: UIImage(systemName: "calendar", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
        cal.tintColor = .white; cal.contentMode = .center; cal.frame = CGRect(x: 0, y: 9, width: 52, height: 22)
        bot.text = "SET"; bot.font = .systemFont(ofSize: 10, weight: .semibold); bot.frame = CGRect(x: 0, y: 31, width: 52, height: 12)
        inner.addSubview(cal)
      }
      inner.addSubview(bot)
      items.append(item("Due", HomeActions.purple, inner: inner, { [weak self] in self?.onDue?() }).0)
    }
    items.forEach { addSubview($0) }
    progress = 0
  }
  var count: Int { items.count }
  // (Done tapped: the circle turns green — or grey again, reopened — with a little pop)
  func markDone(_ on: Bool) {
    guard let b = doneBtn else { return }
    UIView.animate(withDuration: 0.12, animations: { b.transform = CGAffineTransform(scaleX: 1.12, y: 1.12); b.backgroundColor = on ? HomeActions.green : HomeActions.grey }) { _ in
      UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) { b.transform = .identity }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    // (16 in from the side they're on, 12 between)
    if leading { var x: CGFloat = 16; for v in items { v.center = CGPoint(x: x + 26, y: bounds.height / 2); x += 52 + 12 } }
    else { var x = bounds.width - 16; for v in items.reversed() { v.center = CGPoint(x: x - 26, y: bounds.height / 2); x -= 52 + 12 } }
  }
}

// a label going or coming through a blur that builds up / clears frame by frame (Mail's bar titles): its copies at a few
// blur strengths, the nearest two shown over each other; sharp (the label itself) when there's no blur
final class HomeBlurFade {
  static let radii: [CGFloat] = [0, 1.5, 3, 4.5, 6, 8]
  static let ci = CIContext()
  weak var label: UILabel?
  private let a = UIImageView(), b = UIImageView()
  private var imgs: [UIImage] = [], key = ""
  private let pad: CGFloat = 22
  init(_ l: UILabel) { label = l; [a, b].forEach { $0.isUserInteractionEnabled = false; $0.isHidden = true } }
  private func ready(_ trait: UITraitCollection) -> Bool {
    guard let l = label, let text = l.text, !text.isEmpty, let font = l.font, l.bounds.width > 0, l.bounds.height > 0 else { return false }
    let colour = (l.textColor ?? .label).resolvedColor(with: trait)
    let k = "\(text)|\(l.bounds.size)|\(colour)|\(font.pointSize)|\(font.fontName)"
    if k == key { return !imgs.isEmpty }
    key = k; imgs = []
    let fmt = UIGraphicsImageRendererFormat.preferred(); let sc = fmt.scale, bs = l.bounds.size, p = pad
    let size = CGSize(width: bs.width + p * 2, height: bs.height + p * 2)
    // (as the label draws it: shrunk to fit if it does, middle of its height)
    let fit = l.adjustsFontSizeToFitWidth ? min(1, max(l.minimumScaleFactor, bs.width / max(1, (text as NSString).size(withAttributes: [.font: font]).width))) : 1
    let f2 = fit < 1 ? font.withSize(font.pointSize * fit) : font
    let sharp = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
      NSAttributedString(string: text, attributes: [.font: f2, .foregroundColor: colour])
        .draw(with: CGRect(x: p, y: p + (bs.height - f2.lineHeight) / 2, width: bs.width, height: f2.lineHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
    guard let src = CIImage(image: sharp) else { return false }
    for r in HomeBlurFade.radii {
      if r == 0 { imgs.append(sharp); continue }
      guard let f = CIFilter(name: "CIGaussianBlur") else { imgs = []; return false }
      f.setValue(src, forKey: kCIInputImageKey); f.setValue(r * sc, forKey: kCIInputRadiusKey)
      guard let o = f.outputImage?.cropped(to: src.extent), let cg = Self.ci.createCGImage(o, from: src.extent) else { imgs = []; return false }
      imgs.append(UIImage(cgImage: cg, scale: sc, orientation: .up))
    }
    return true
  }
  // blur (points; 0 = sharp), how see-through, how far below its place
  func set(blur r: CGFloat, alpha: CGFloat, dy: CGFloat, trait: UITraitCollection) {
    guard let l = label else { return }
    let t = CGAffineTransform(translationX: 0, y: dy)
    if l.transform != t { l.transform = t }
    if alpha < 0.01 { l.alpha = 0; a.isHidden = true; b.isHidden = true; return }
    if r < 0.2 || !ready(trait) { l.alpha = alpha; a.isHidden = true; b.isHidden = true; return }
    if a.superview !== l.superview { l.superview?.insertSubview(a, aboveSubview: l); l.superview?.insertSubview(b, aboveSubview: a) }
    let R = HomeBlurFade.radii
    var i = 0; while i < R.count - 2 && r > R[i + 1] { i += 1 }
    let f = min(1, max(0, (r - R[i]) / (R[i + 1] - R[i])))
    l.alpha = 0
    for v in [a, b] { v.bounds = CGRect(origin: .zero, size: imgs[0].size); v.center = l.center; v.transform = t; v.isHidden = false }
    a.image = imgs[i]; b.image = imgs[i + 1]
    a.alpha = alpha; b.alpha = alpha * f
  }
  func clear() { a.isHidden = true; b.isHidden = true; label?.transform = .identity }
}

// a Liquid Glass circle or capsule (iOS 26+: iPhone's own glass; before: a thin blur with a light edge)
final class HomeGlass: UIView {
  var onTap: (() -> Void)?
  let content = UIView()
  private let fx = UIVisualEffectView(effect: nil), icon = UIImageView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    fx.isUserInteractionEnabled = true   // (the search bar's field, inside it, gets its taps — its ✕ too)
    addSubview(fx)
    content.isUserInteractionEnabled = true
    fx.contentView.addSubview(content)
    icon.contentMode = .center; addSubview(icon)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    isAccessibilityElement = true; accessibilityTraits = .button
    fx.clipsToBounds = true
    if #available(iOS 26.0, *) {
      let g = UIGlassEffect(style: .regular); g.isInteractive = true
      fx.effect = g
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func tap() { onTap?() }
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { g is UITapGestureRecognizer ? onTap != nil : true }
  func setIcon(_ sym: String, _ size: CGFloat) { icon.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium)) }
  func setLook(light: Bool, tint: UIColor) {
    icon.tintColor = tint
    overrideUserInterfaceStyle = light ? .light : .dark
    if #available(iOS 26.0, *) { return }
    fx.effect = UIBlurEffect(style: light ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark)
    fx.layer.borderWidth = 1; fx.layer.borderColor = UIColor.white.withAlphaComponent(light ? 0.6 : 0.18).cgColor
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    fx.frame = bounds; content.frame = fx.contentView.bounds; icon.frame = bounds
    fx.layer.cornerRadius = min(bounds.height, bounds.width) / 2
  }
  // (the search bar's field gets the taps inside it; the glass itself only when there's no field)
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let v = super.hitTest(point, with: event)
    if let v = v, v !== self, v.isDescendant(of: content), v !== content { return v }
    return v == nil ? nil : self
  }
}

// a client in the search results (phone.js search(): the coloured square with its initials, the name, its open tasks)
final class HomeClientRow: UIControl {
  private let sq = UILabel(), name = UILabel(), meta = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 20; layer.borderWidth = 1
    sq.layer.cornerRadius = 11; sq.clipsToBounds = true; sq.textAlignment = .center; sq.font = .systemFont(ofSize: 14, weight: .heavy); sq.textColor = .white
    name.font = .systemFont(ofSize: 15.5, weight: .semibold); meta.font = .systemFont(ofSize: 12.5)
    [sq, name, meta].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isHighlighted: Bool { didSet { UIView.animate(withDuration: 0.08) { self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity } } }
  func set(_ c: [String: Any], look L: HomeLook) {
    backgroundColor = L.card; layer.borderColor = L.cardLine.cgColor
    sq.text = c["ini"] as? String; sq.backgroundColor = NativeSheetVC.color(c["rgb"]) ?? .systemIndigo
    name.text = c["name"] as? String; name.textColor = L.title
    let n = c["open"] as? Int ?? 0
    meta.text = "Client · \(n) open task\(n == 1 ? "" : "s")"; meta.textColor = L.meta
    accessibilityLabel = name.text
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    sq.frame = CGRect(x: 15, y: (bounds.height - 40) / 2, width: 40, height: 40)
    name.frame = CGRect(x: 67, y: bounds.height / 2 - 20, width: bounds.width - 82, height: 21)
    meta.frame = CGRect(x: 67, y: bounds.height / 2 + 3, width: bounds.width - 82, height: 17)
  }
}

// a view that only takes touches on what's in it (the bar's row: the list under its empty parts still scrolls)
final class HomePassThrough: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { let v = super.hitTest(point, with: event); return v === self ? nil : v }
}
