import UIKit

/* ================= Home (E11 Day / My Day), drawn by the app itself (23+, Haris 2026-10-31) =================
   The same page as the website's phone Home (phone.js myDay / card, phone.css .ph-head / .ph-stats / .ph-gh / .pc),
   only scrolled and tapped by iPhone itself. The page stays the engine: it sends what to show — the header, the three
   boxes, the groups and their task cards, and the colours of its own Home drawn under this one (light / dark) — with
   the "home" command whenever something changes (NativeHome in phone.js), and the taps go back to it
   (window.__e11Home: open a task, Search, Me, New task). */
final class HomeView: UIView, UIScrollViewDelegate {
  var onEvent: (([String: Any]) -> Void)?
  private let head = UIView(), sub = UILabel(), title = UILabel(), search = UIButton(type: .custom), me = UIButton(type: .custom)
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
    addSubview(head)
    sub.font = .systemFont(ofSize: 13, weight: .medium)
    title.font = .systemFont(ofSize: 32, weight: .heavy)
    title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.6
    head.addSubview(sub); head.addSubview(title)
    search.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
    search.layer.cornerRadius = 23
    search.accessibilityLabel = "Search"
    search.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "search"]) }, for: .touchUpInside)
    me.layer.cornerRadius = 20; me.clipsToBounds = true
    me.accessibilityLabel = "Me"
    me.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "me"]) }, for: .touchUpInside)
    head.addSubview(search); head.addSubview(me)
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
    var e = ev; e["y"] = Int(scroll.contentOffset.y.rounded())
    onEvent?(e)
  }

  // ---------- what the page sent ----------
  func update(_ model: [String: Any]) {
    m = model
    L = HomeLook(model["look"] as? [String: Any])
    backgroundColor = L.bg
    head.backgroundColor = L.headBg
    sub.text = model["date"] as? String; sub.textColor = L.sub
    title.attributedText = NSAttributedString(string: model["title"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 32, weight: .heavy), .kern: -0.64, .foregroundColor: L.h1])
    search.backgroundColor = L.round; search.tintColor = L.roundIc
    meId = model["me"] as? String ?? ""; meChanged()
    let st = model["stats"] as? [Int] ?? [0, 0, 0]
    let names = ["Due today", "Overdue", "In review"], cols = [L.statG, L.statR, L.statA]
    for (i, v) in stats.enumerated() {
      v.backgroundColor = L.statBg; v.layer.borderColor = L.statLine.cgColor
      if L.light { v.layer.shadowColor = UIColor(red: 30 / 255, green: 30 / 255, blue: 60 / 255, alpha: 1).cgColor; v.layer.shadowOpacity = 0.06; v.layer.shadowRadius = 7; v.layer.shadowOffset = CGSize(width: 0, height: 4) } else { v.layer.shadowOpacity = 0 }
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
          v = HomeCard(); v.onTap = { [weak self] in self?.send(["ev": "open", "id": id]) }
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
    for (id, v) in cards where !seen.contains(id) { v.removeFromSuperview(); cards[id] = nil }
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
    let safeTop = safeAreaInsets.top
    let headH = L.headH ?? (safeTop + 18 + 55 + 12)
    head.frame = CGRect(x: 0, y: 0, width: W, height: headH)
    // (.ph-head: the date over the title on the left, Search and your photo on the right, all centred on one line)
    let subH = ceil(sub.font.lineHeight), tH: CGFloat = 37
    let blockH = subH + 2 + tH
    let by = headH - 12 - blockH
    me.frame = CGRect(x: W - 20 - 40, y: by + (blockH - 40) / 2, width: 40, height: 40)
    search.frame = CGRect(x: me.frame.minX - 10 - 46, y: by + (blockH - 46) / 2, width: 46, height: 46)
    let tw = search.frame.minX - 10 - 20
    sub.frame = CGRect(x: 20, y: by, width: tw, height: subH)
    title.frame = CGRect(x: 20, y: by + subH + 2, width: tw, height: tH)
    scroll.frame = CGRect(x: 0, y: headH, width: W, height: H - headH)
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
        if c.frame.size != CGSize(width: lw, height: h) || c.frame.origin != CGPoint(x: 16, y: y) { c.frame = CGRect(x: 16, y: y, width: lw, height: h) }
        y += h
      }
    }
    scroll.contentSize = CGSize(width: W, height: y + bottomRoom)
    scroll.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomRoom - 20, right: 0)
    // the + button where the page has it
    let fs = L.fabRect?.width ?? 60
    if let tt = tabTop { fab.frame = CGRect(x: W - 18 - fs, y: tt - 14 - fs, width: fs, height: fs); fab.layer.cornerRadius = fs / 2 }
    else if let r = L.fabRect { fab.frame = r; fab.layer.cornerRadius = r.height / 2 } else { fab.frame = CGRect(x: W - 18 - 60, y: H - 170, width: 60, height: 60); fab.layer.cornerRadius = 30 }
  }
  func scrollToTop() { scroll.setContentOffset(.zero, animated: true) }
  func geo() -> [String: Any] {
    ["title": title.text ?? "", "date": sub.text ?? "", "stats": stats.map { ($0.viewWithTag(1) as? UILabel)?.text ?? "" },
     "groups": content.filter { $0.tag == 7 }.map { ($0 as? UILabel)?.text ?? "" }, "cards": cards.count, "fab": !fab.isHidden,
     "headH": head.frame.height, "light": L.light]
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
  override var isHighlighted: Bool { didSet { UIView.animate(withDuration: 0.08) { self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity } } }

  func set(_ d: [String: Any], look: HomeLook) {
    c = d; L = look
    let late = (d["late"] as? Bool) == true, done = (d["done"] as? Bool) == true
    backgroundColor = L.card
    layer.borderColor = (late ? L.lateLine : L.cardLine).cgColor
    if L.light { layer.shadowColor = UIColor(red: 30 / 255, green: 30 / 255, blue: 60 / 255, alpha: 1).cgColor; layer.shadowOpacity = 0.07; layer.shadowRadius = 8; layer.shadowOffset = CGSize(width: 0, height: 4) } else { layer.shadowOpacity = 0 }
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
    if L.light { layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 20).cgPath }
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
