import UIKit

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
  private let blur = UIVisualEffectView(effect: nil), hairline = UIView()
  private let sub = UILabel(), title = UILabel(), smallTitle = UILabel(), smallSub = UILabel()
  private let searchCircle = HomeGlass(), me = UIButton(type: .custom), closeCircle = HomeGlass()
  private let searchBar = HomeGlass(), field = UITextField(), lens = UIImageView()
  private let results = UIScrollView(), hint = UILabel()
  private var resultViews: [UIView] = [], resultCards: [String: HomeCard] = [:]
  private(set) var searching = false
  private var findTimer: Timer?, keyboardH: CGFloat = 0
  private let scroll = UIScrollView()
  private let fab = UIButton(type: .custom)
  private var stats: [UIView] = []
  private var content: [UIView] = []
  private var cards: [String: HomeCard] = [:]
  private var m: [String: Any] = [:]
  private var L = HomeLook(nil)
  var people: [String: [String: Any]] = [:] { didSet { if oldValue.count != people.count { cards.values.forEach { $0.people = people }; meChanged() } } }
  private var meId = ""
  var bottomRoom: CGFloat = 120 { didSet { if oldValue != bottomRoom { setNeedsLayout() } } }
  // the top of the app's tab bar: the + sits 14 above it, 18 from the right (phone.css .ph-fab), so it's in place from
  // the first frame — not where the page had it a moment before the tab bar came (it jumped up, Haris 2026-10-31)
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
    hint.font = .systemFont(ofSize: 14); hint.numberOfLines = 0; results.addSubview(hint)
    addSubview(results)
    blur.isUserInteractionEnabled = false
    // (the bar once scrolled: frosted glass with a soft line under it, as Mail's)
    blur.contentView.addSubview(hairline)
    blur.alpha = 0
    addSubview(blur)
    sub.font = .systemFont(ofSize: 13, weight: .medium)
    title.font = .systemFont(ofSize: 32, weight: .heavy)
    title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.6
    smallTitle.font = .systemFont(ofSize: 17, weight: .bold); smallSub.font = .systemFont(ofSize: 12)
    smallTitle.alpha = 0; smallSub.alpha = 0
    // (the big title scrolls with the list and goes under the frosted bar; the small title is on the bar)
    insertSubview(sub, belowSubview: blur); insertSubview(title, belowSubview: blur)
    [smallTitle, smallSub].forEach { addSubview($0) }
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
    fab.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)), for: .normal)
    fab.tintColor = .white
    fab.accessibilityLabel = "New task"
    fab.layer.shadowColor = UIColor(red: 106 / 255, green: 86 / 255, blue: 230 / 255, alpha: 1).cgColor
    fab.layer.shadowOpacity = 0.5; fab.layer.shadowRadius = 14; fab.layer.shadowOffset = CGSize(width: 0, height: 10)
    fab.layer.borderWidth = 1
    fab.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "add"]) }, for: .touchUpInside)
    addSubview(fab)
    for _ in 0..<3 { let v = UIView(); v.layer.cornerRadius = 18; v.layer.borderWidth = 1; let n = UILabel(), l = UILabel(); n.tag = 1; l.tag = 2; v.addSubview(n); v.addSubview(l); scroll.addSubview(v); stats.append(v) }
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
    sub.text = model["date"] as? String; sub.textColor = L.sub
    title.attributedText = NSAttributedString(string: model["title"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 32, weight: .heavy), .kern: -0.64, .foregroundColor: L.h1])
    smallTitle.text = model["title"] as? String; smallTitle.textColor = L.h1
    smallSub.text = model["date"] as? String; smallSub.textColor = L.sub
    blur.effect = UIBlurEffect(style: L.light ? .systemMaterialLight : .systemMaterialDark)
    hairline.backgroundColor = L.light ? UIColor.black.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.12)
    [searchCircle, closeCircle, searchBar].forEach { $0.setLook(light: L.light, tint: L.roundIc) }
    lens.tintColor = L.sub; field.textColor = L.h1; field.tintColor = L.tag
    field.attributedPlaceholder = NSAttributedString(string: "Search tasks, clients, people", attributes: [.foregroundColor: L.sub.withAlphaComponent(0.8)])
    field.keyboardAppearance = L.light ? .light : .dark
    hint.textColor = L.empty
    meId = model["me"] as? String ?? ""; meChanged()
    let st = model["stats"] as? [Int] ?? [0, 0, 0]
    let names = ["Due today", "Overdue", "In review"], cols = [L.statG, L.statR, L.statA]
    for (i, v) in stats.enumerated() {
      v.backgroundColor = L.statBg; v.layer.borderColor = L.statLine.cgColor
      v.layer.shadowOpacity = 0   // (no drop shadows on boxes or cards — Haris, 2026-10-31)
      let n = v.viewWithTag(1) as? UILabel, l = v.viewWithTag(2) as? UILabel
      n?.text = "\(st.indices.contains(i) ? st[i] : 0)"; n?.font = .systemFont(ofSize: 24, weight: .heavy); n?.textColor = cols[i]
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
      h.attributedText = s; h.tag = 7
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
    fab.backgroundColor = L.fabBg; fab.layer.borderColor = L.fabLine.cgColor
    setNeedsLayout(); layoutIfNeeded()
  }
  private func meChanged() {
    let p = people[meId]
    let img = roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 40)
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
    results.contentInset.top = 18   // (clear of the blur under the search bar)
    layoutResults()
    // the three boxes (.ph-stats: 4 above, 6 below, 8 apart)
    var y: CGFloat = 4
    let bw = (W - 40 - 16) / 3, bh: CGFloat = 1 + 12 + 29 + 14 + 12 + 1
    for (i, v) in stats.enumerated() {
      v.frame = CGRect(x: 20 + CGFloat(i) * (bw + 8), y: y, width: bw, height: bh)
      v.viewWithTag(1)?.frame = CGRect(x: 13, y: 13, width: bw - 26, height: 29)
      v.viewWithTag(2)?.frame = CGRect(x: 13, y: 13 + 29, width: bw - 26, height: 15)
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
        if c === openCard, let a = actions { a.frame = CGRect(x: 16 + lw - a.frame.width, y: y, width: a.frame.width, height: h) }
        y += h
      }
    }
    scroll.contentSize = CGSize(width: W, height: y + bottomRoom)
    // the + button where the page has it
    let fs = L.fabRect?.width ?? 60
    if let tt = tabTop { fab.frame = CGRect(x: W - 18 - fs, y: tt - 14 - fs, width: fs, height: fs); fab.layer.cornerRadius = fs / 2 }
    else if let r = L.fabRect { fab.frame = r; fab.layer.cornerRadius = r.height / 2 } else { fab.frame = CGRect(x: W - 18 - 60, y: H - 170, width: 60, height: 60); fab.layer.cornerRadius = 30 }
  }
  func scrollToTop() { scroll.setContentOffset(CGPoint(x: 0, y: -scroll.contentInset.top), animated: true) }
  func scrollViewDidScroll(_ scrollView: UIScrollView) { if scrollView === scroll { layoutHeader() } }

  // ---------- the header (as Mail): the big title scrolls with the list, under a frosted bar that comes as it goes ----------
  private var bigHead: CGFloat { L.headH ?? (safeAreaInsets.top + 18 + 55 + 12) }
  private var smallHead: CGFloat { safeAreaInsets.top + 52 }
  private func ease(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { let x = min(1, max(0, (t - a) / (b - a))); return x * x * (3 - 2 * x) }
  // (how far the list has scrolled)
  private var scrolled: CGFloat { scroll.contentOffset.y + scroll.contentInset.top }
  // (0 big … 1 small: once the big title has gone under the bar)
  private var shrink: CGFloat {
    let subH = ceil(sub.font.lineHeight), by = bigHead - 12 - (subH + 2 + 37)
    return ease(by + subH - smallHead + 4, by + subH + 30 - smallHead, scrolled)
  }
  private func layoutHeader() {
    let W = bounds.width
    let bigH = bigHead, smallH = smallHead, top = safeAreaInsets.top
    let s = scrolled
    let subH = ceil(sub.font.lineHeight), tH: CGFloat = 37
    let blockH = subH + 2 + tH
    let by = bigH - 12 - blockH
    // the bar: frosted, with its soft line, there once the list reaches it
    blur.frame = CGRect(x: 0, y: 0, width: W, height: smallH)
    hairline.frame = CGRect(x: 0, y: smallH - 0.5, width: W, height: 0.5)
    blur.alpha = searching ? 1 : ease(by - smallH - 6, by - smallH + 10, s)
    scroll.verticalScrollIndicatorInsets = UIEdgeInsets(top: smallH - bigH, left: 0, bottom: bottomRoom - 20, right: 0)
    // the big date and title: moving with the list (finger for finger), going under the bar
    let tw = W - 20 - 40 - 10 - 46 - 10 - 20
    sub.frame = CGRect(x: 20, y: by - s, width: tw, height: subH)
    title.frame = CGRect(x: 20, y: by + subH + 2 - s, width: tw, height: tH)
    let bigA: CGFloat = searching ? 0 : 1
    sub.alpha = bigA; title.alpha = bigA
    // the small title and date on the bar, fading in as the big ones go under it
    let smallCY = top + 26
    let k = searching ? 0 : shrink
    smallTitle.frame = CGRect(x: 20, y: smallCY - 19, width: tw, height: 21); smallSub.frame = CGRect(x: 20, y: smallCY + 2, width: tw, height: 15)
    smallTitle.alpha = k; smallSub.alpha = k
    // Search and your photo: with the title until they reach the bar, then they stay on it
    let bigCY = by + blockH / 2
    let cy = max(smallCY, bigCY - max(0, s))
    if !searching {
      me.bounds = CGRect(x: 0, y: 0, width: 40, height: 40); me.center = CGPoint(x: W - 20 - 20, y: cy); me.layer.cornerRadius = 20
      searchCircle.frame = CGRect(x: W - 20 - 40 - 10 - 46, y: cy - 23, width: 46, height: 46)
    } else {
      // (the bar in the row the buttons are in; the ✕ where your photo was)
      searchBar.frame = CGRect(x: 20, y: cy - 23, width: W - 20 - 46 - 10 - 20, height: 46)
      closeCircle.frame = CGRect(x: W - 20 - 46, y: cy - 23, width: 46, height: 46)
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
    searchBar.frame = start; searchBar.isHidden = false; searchBar.alpha = 1
    searchBar.layer.cornerRadius = start.height / 2
    closeCircle.frame = meF; closeCircle.isHidden = false; closeCircle.alpha = 0
    closeCircle.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
    searchCircle.alpha = 0
    results.isHidden = false
    field.text = ""; showResults(nil)
    UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
      self.layoutHeader()
      self.searchBar.layer.cornerRadius = 23
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
    if let t = hint.text, !t.isEmpty { let h = hint.sizeThatFits(CGSize(width: lw - 8, height: 400)).height; hint.frame = CGRect(x: 20, y: 14, width: lw - 8, height: h); y = 14 + h + 14 } else { hint.frame = .zero }
    for (i, v) in resultViews.enumerated() {
      if i > 0 { y += 10 }
      if v.tag == 7 { y += i > 0 ? 12 : 4; v.frame = CGRect(x: 20, y: y, width: lw - 8, height: 15); y += 15 }
      else if let c = v as? HomeCard { let h = c.height(for: lw); c.bounds = CGRect(x: 0, y: 0, width: lw, height: h); c.center = CGPoint(x: 16 + lw / 2, y: y + h / 2); y += h }
      else { v.frame = CGRect(x: 16, y: y, width: lw, height: 70); y += 70 }
    }
    results.contentSize = CGSize(width: W, height: y + 20)
  }
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { if let o = openCard { setOpen(o, false) } }

  // ---------- swipe left on a card: Copy link · Delete (as in Mail: round buttons with their names under them) ----------
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard let p = g as? UIPanGestureRecognizer, let card = p.view as? HomeCard else { return true }
    let v = p.velocity(in: self)
    return abs(v.x) > abs(v.y) * 1.2 && (v.x < 0 || card.swipeX < 0)
  }
  private var reveal: CGFloat { canDelete ? 148 : 84 }
  private func actionsFor(_ card: HomeCard) -> HomeActions {
    if let a = actions, openCard === card { return a }
    actions?.removeFromSuperview()
    let a = HomeActions(delete: canDelete, light: L.light)
    a.frame = CGRect(x: card.center.x + card.bounds.width / 2 - reveal, y: card.center.y - card.bounds.height / 2, width: reveal, height: card.bounds.height)
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
    scroll.insertSubview(a, belowSubview: card)
    actions = a; openCard = card
    return a
  }
  @objc private func swipe(_ g: UIPanGestureRecognizer) {
    guard let card = g.view as? HomeCard else { return }
    switch g.state {
    case .began:
      if let o = openCard, o !== card { setOpen(o, false) }
      card.swipeStart = card.swipeX
      _ = actionsFor(card)
    case .changed:
      var x = card.swipeStart + g.translation(in: self).x
      if x > 0 { x = 0 }
      if x < -reveal { x = -reveal + (x + reveal) / 3 }   // (past the buttons: held back)
      card.swipeX = x
      actions?.progress = min(1, -x / reveal)
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: self).x
      setOpen(card, v < -350 || (card.swipeX < -reveal / 2 && v < 300))
    default: break
    }
  }
  func setOpen(_ card: HomeCard, _ open: Bool) {
    if open { _ = actionsFor(card) }
    let a = actions
    UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
      card.swipeX = open ? -self.reveal : 0
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
      btn.addAction(UIAction { [weak self, weak v] _ in v?.removeFromSuperview(); self?.onEvent?(["ev": "toast"]) }, for: .touchUpInside)
      v.addSubview(btn); b = btn; bw = btn.sizeThatFits(CGSize(width: 200, height: 40)).width + 14
    }
    let W = bounds.width
    let maxL = W - 32 - 28 - bw
    let ls = l.sizeThatFits(CGSize(width: maxL, height: 60))
    let w = min(W - 32, ls.width + 28 + bw), h = max(40, ls.height + 18)
    let bottom = (tabTop ?? bounds.height - 40) - 14 - (fab.isHidden ? 0 : fab.frame.height + 12)
    v.frame = CGRect(x: (W - w) / 2, y: bottom - h, width: w, height: h)
    l.frame = CGRect(x: 14, y: (h - ls.height) / 2, width: ls.width, height: ls.height)
    b?.frame = CGRect(x: w - bw, y: 0, width: bw - 4, height: h)
    v.alpha = 0; v.transform = CGAffineTransform(translationX: 0, y: 8)
    addSubview(v); toastView = v
    UIView.animate(withDuration: 0.16) { v.alpha = 1; v.transform = .identity }
    let ms = (t["ms"] as? Double) ?? 3000
    DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000) { [weak v] in
      guard let v = v else { return }
      UIView.animate(withDuration: 0.2, animations: { v.alpha = 0 }) { _ in v.removeFromSuperview() }
    }
  }
  // (for the self-test: the first card swiped open, held, closed)
  private var firstCard: HomeCard? { content.compactMap { $0 as? HomeCard }.first }
  func selfSwipe() { if let c = firstCard { setOpen(c, true) } }
  func selfPress() { if let c = firstCard { attach(c) } }
  func selfClose() { if let o = openCard { setOpen(o, false) } }
  func selfScroll(_ y: CGFloat) { scroll.setContentOffset(CGPoint(x: 0, y: y - scroll.contentInset.top), animated: false); layoutHeader() }
  func selfFind(_ q: String) { openSearch(); field.text = q; typed() }
  func selfFindDone() { closeSearch() }
  func geo() -> [String: Any] {
    ["open": openCard != nil, "openShift": openCard?.swipeX ?? 0, "actions": actions?.subviews.count ?? 0,
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
    sub = c("sub", SplashView.hex(0xb4b7c0), SplashView.hex(0x5d6068)); h1 = c("h1", SplashView.hex(0xe9eaee), SplashView.hex(0x17181b))
    round = c("round", w.withAlphaComponent(0.08), k.withAlphaComponent(0.05)); roundIc = c("roundIc", h1, h1)
    statBg = c("statBg", w.withAlphaComponent(0.06), w.withAlphaComponent(0.7)); statLine = c("statLine", w.withAlphaComponent(0.12), w)
    statLabel = c("statLabel", SplashView.hex(0xb4b7c0), SplashView.hex(0x5d6068))
    statG = c("statG", SplashView.hex(0x3ddc97), SplashView.hex(0x1a9e63)); statR = c("statR", SplashView.hex(0xff7a7a), SplashView.hex(0xd9363e)); statA = c("statA", SplashView.hex(0xf9be33), SplashView.hex(0xb57d00))
    gh = c("gh", SplashView.hex(0x7d808a), SplashView.hex(0x8a8d96)); empty = c("empty", gh, gh)
    card = c("card", SplashView.hex(0x121317), w); cardLine = c("cardLine", SplashView.hex(0x1d1f24), .clear)
    lateLine = c("lateLine", UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.45), UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.45))
    title = c("title", SplashView.hex(0xe9eaee), SplashView.hex(0x17181b)); meta = c("meta", SplashView.hex(0xb4b7c0), SplashView.hex(0x5d6068))
    sep = c("sep", gh, gh); late = c("late", SplashView.hex(0xff8a8a), SplashView.hex(0xd9363e)); today = c("today", SplashView.hex(0x8fbcff), SplashView.hex(0x2f6fd6))
    doneTitle = c("doneTitle", gh, gh)
    tag = c("tag", SplashView.hex(0xc9c0ff), SplashView.hex(0x5b4bd6)); tagBg = c("tagBg", UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.18), UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.14))
    urgent = c("urgent", SplashView.hex(0xff9494), SplashView.hex(0xd9363e)); urgentBg = c("urgentBg", UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.16), UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.12))
    more = c("more", meta, meta); moreBg = c("moreBg", w.withAlphaComponent(0.08), k.withAlphaComponent(0.06))
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
  var swipeStart: CGFloat = 0
  // (sideways when swiped open; pressed in a little while touched — both at once)
  var swipeX: CGFloat = 0 { didSet { applyTransform() } }
  private func applyTransform() {
    let s: CGFloat = isHighlighted ? 0.985 : 1
    transform = CGAffineTransform(translationX: swipeX, y: 0).scaledBy(x: s, y: s)
  }
  var people: [String: [String: Any]] = [:] { didSet { if oldValue.count != people.count { drawPeople() } } }
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
      if ml.length > 0 { ml.append(NSAttributedString(string: " ", attributes: [.font: f, .kern: 4.9])) }
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
  // the line under the title: client (with its colour), status, due date, comments — 6 apart, "·" between
  private func meta(_ items: [[String: Any]]) -> NSAttributedString {
    let f = UIFont.systemFont(ofSize: 12.5)
    let s = NSMutableAttributedString()
    // (as the page wraps it: whole pieces only — "3 comments" never split — and a "·" stays at the end of its line)
    let gap = { (breaks: Bool) in NSAttributedString(string: breaks ? " " : "\u{00A0}", attributes: [.font: f, .kern: 2.9]) }
    for (i, it) in items.enumerated() {
      if i > 0 { s.append(gap(false)); s.append(NSAttributedString(string: "·", attributes: [.font: f, .foregroundColor: L.sep])); s.append(gap(true)) }
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
      if check {
        let p = UIBezierPath(); let o = CGPoint(x: 6, y: 3)
        p.move(to: CGPoint(x: o.x + 1.6, y: o.y + 5.2)); p.addLine(to: CGPoint(x: o.x + 4, y: o.y + 7.6)); p.addLine(to: CGPoint(x: o.x + 8.6, y: o.y + 2.6))
        color.setStroke(); p.lineWidth = 1.9; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
      }
      (text as NSString).draw(at: CGPoint(x: 6 + tick, y: (16 - ts.height) / 2), withAttributes: [.font: f, .foregroundColor: color])
    }
  }
  // the status icon (app.js statusIconSVG, 16 units → 22 pt): done (filled, ticked), to do (dashed ring), or a ring with a slice for how far along
  static func statusIcon(_ d: [String: Any]?) -> UIImage {
    let col = NativeSheetVC.color(d?["rgb"]) ?? .systemGray
    let kind = d?["kind"] as? String ?? "todo"
    let frac = CGFloat((d?["frac"] as? NSNumber)?.doubleValue ?? 0.5)
    let k: CGFloat = 22 / 16
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { ctx in
      let g = ctx.cgContext
      g.scaleBy(x: k, y: k)
      if kind == "done" {
        col.setFill(); UIBezierPath(arcCenter: CGPoint(x: 8, y: 8), radius: 7, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        let p = UIBezierPath(); p.move(to: CGPoint(x: 4.9, y: 8.2)); p.addLine(to: CGPoint(x: 7, y: 10.3)); p.addLine(to: CGPoint(x: 11, y: 6))
        UIColor.white.setStroke(); p.lineWidth = 1.7; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        return
      }
      let ring = UIBezierPath(arcCenter: CGPoint(x: 8, y: 8), radius: 6.2, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      ring.lineWidth = 1.7; col.setStroke()
      if kind == "todo" { ring.setLineDash([2.4, 1.9], count: 2, phase: 0); ring.stroke(); return }
      ring.stroke()
      let a = min(0.999, max(0.08, frac)) * .pi * 2
      let s = UIBezierPath(); s.move(to: CGPoint(x: 8, y: 8)); s.addLine(to: CGPoint(x: 8, y: 8 - 3.6))
      s.addArc(withCenter: CGPoint(x: 8, y: 8), radius: 3.6, startAngle: -.pi / 2, endAngle: -.pi / 2 + a, clockwise: true); s.close()
      col.setFill(); s.fill()
    }
  }
}

// the buttons a swiped card shows: Copy link (grey) and Delete (red, for those who may), round with their names under
final class HomeActions: UIView {
  var onCopy: (() -> Void)?, onDelete: (() -> Void)?
  private var items: [UIView] = []
  var progress: CGFloat = 0 { didSet { items.forEach { $0.alpha = progress; $0.transform = CGAffineTransform(scaleX: 0.6 + 0.4 * progress, y: 0.6 + 0.4 * progress) } } }
  init(delete: Bool, light: Bool) {
    super.init(frame: .zero)
    func item(_ sym: String, _ name: String, _ col: UIColor, _ act: @escaping () -> Void) -> UIView {
      let v = UIView()
      let b = UIButton(type: .custom)
      b.backgroundColor = col; b.layer.cornerRadius = 26; b.tintColor = .white
      b.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal)
      b.frame = CGRect(x: 0, y: 0, width: 52, height: 52)
      b.addAction(UIAction { _ in act() }, for: .touchUpInside)
      b.accessibilityLabel = name
      let l = UILabel(); l.text = name; l.font = .systemFont(ofSize: 12); l.textColor = light ? SplashView.hex(0x5d6068) : SplashView.hex(0xb4b7c0); l.textAlignment = .center
      l.frame = CGRect(x: -14, y: 58, width: 80, height: 15)
      v.addSubview(b); v.addSubview(l)
      v.bounds = CGRect(x: 0, y: 0, width: 52, height: 73)
      return v
    }
    items.append(item("link", "Copy link", SplashView.hex(0x8a8d96), { [weak self] in self?.onCopy?() }))
    if delete { items.append(item("trash", "Delete", SplashView.hex(0xe5484d), { [weak self] in self?.onDelete?() })) }
    items.forEach { addSubview($0) }
    progress = 0
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    // (from the right: 16 in, 12 between)
    var x = bounds.width - 16
    for v in items.reversed() { v.center = CGPoint(x: x - 26, y: bounds.height / 2); x -= 52 + 12 }
  }
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
