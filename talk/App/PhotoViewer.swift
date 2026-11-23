import UIKit
import AVKit
import ImageIO

/* A photo or video opened (the approved boards "A photo opened" and "Opening a photo" of the E11 Talk design): out of its
   bubble onto black; the sender and the date at the top with ‹ and •••; pinch or double-tap to zoom; swipe sideways
   through the chat's photos and videos (the strip under it too); the caption, the reactions with ☺︎, and Reply; Share ·
   Forward · Save · Delete at the foot; a tap hides and shows all that. Swiped down anywhere, the photo follows the finger
   and goes back into its bubble (Haris 2026-11-12: Quick Look's swipe moved the picture instead). Apple's parts: Apple's
   paging and zooming scroll views, glass buttons, menus, share sheet and player. */
final class PhotoViewerVC: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
  private var items: [Msg]
  private var at: Int
  // where a photo shows in the chat: the view and the part of it that is this photo (the whole bubble picture, or its
  // square in an album's grid)
  var source: ((Msg) -> (UIView, CGRect)?)?
  // (what sits beside the photo in the chat — its reactions, the forward button: away while the picture flies out and back,
  //  faded in once it has landed; the flying picture went over the reaction and cut it, Haris 2026-11-13)
  var beside: ((Msg, Bool) -> Void)?
  var onReply: ((Msg) -> Void)?, onForward: ((Msg) -> Void)?, onDelete: ((Msg) -> Void)?, onReact: ((Msg) -> Void)?, onShow: ((Msg) -> Void)?

  private let back = UIView(), pager = UIScrollView()
  private var pages: [ZoomPage] = []
  private let top = UIView(), foot = UIView(), topShade = Shade(), footShade = Shade()
  private let who = UILabel(), when = UILabel(), backB = UIButton(type: .system), moreB = UIButton(type: .system)
  private let cap = UILabel(), reacts = UIButton(type: .system), smile = UIButton(type: .system), replyB = UIButton(type: .system)
  private let strip = UIScrollView(), stripRow = UIStackView(), tools = UIStackView()
  private var chrome = true
  // a video's time played · seek bar · its length (Haris 2026-11-22 18:21, WhatsApp's); photos: not there (no height)
  private let seek = UIView(), played = UILabel(), length = UILabel(), bar = UISlider()
  private var seekH: NSLayoutConstraint!, ticks: Any?, ticking: AVPlayer?, dragging = false

  init(items: [Msg], at: Int) { self.items = items; self.at = at; super.init(nibName: nil, bundle: nil); modalPresentationStyle = .overFullScreen; modalPresentationCapturesStatusBarAppearance = true }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
  override var prefersStatusBarHidden: Bool { !chrome }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    back.backgroundColor = .black; back.frame = view.bounds; back.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(back)
    pager.isPagingEnabled = true; pager.showsHorizontalScrollIndicator = false; pager.delegate = self; pager.contentInsetAdjustmentBehavior = .never
    // (Apple's shade under the status bar came in by itself a moment after the photo — popping, Haris 2026-11-12; it's off,
    //  and the top carries its own soft shade instead, fading in and out with the buttons)
    if #available(iOS 26.0, *) { pager.topEdgeEffect.isHidden = true; pager.bottomEdgeEffect.isHidden = true }
    view.addSubview(pager)
    pages = items.map { ZoomPage(msg: $0) }
    pages.forEach { $0.onPlaying = { [weak self] in if self?.chrome == true { self?.toggleChrome() } } }
    pages.forEach { pager.addSubview($0) }
    // (the one opened and its neighbours: their pictures there from the first frame — read now if the chat hadn't)
    for i in max(0, at - 1)...min(items.count - 1, at + 1) where pages[i].image.image == nil {
      if let f = items[i].file { pages[i].image.image = ZoomPage.quick(items[i], f) }
    }
    // (the one opened, already on the phone: the full photo from the first frame — it showed the chat's small picture and
    //  turned sharp a moment later, every time: Haris 2026-11-19 11:15)
    if at < items.count, let f = items[at].file, let full = ZoomPage.full(items[at], f) { pages[at].image.image = full }

    // the top: ‹ · who and when · •••
    // (Apple's own glass, as Photos — Haris 2026-11-14; before iOS 26 the grey capsule as before)
    func glass(_ b: UIButton, _ sym: String, _ label: String) {
      var c: UIButton.Configuration
      if #available(iOS 26.0, *) { c = .glass() } else { c = .gray(); c.cornerStyle = .capsule; c.baseForegroundColor = .white; c.background.backgroundColor = UIColor(white: 0.16, alpha: 0.8) }
      // (Apple's own icon size and weight, as Photos — 15 regular; was 17 semibold: Haris 2026-11-21 19:38)
      c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)); c.contentInsets = .zero
      b.configuration = c; b.accessibilityLabel = label; b.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 42), b.heightAnchor.constraint(equalToConstant: 42)])
    }
    glass(backB, "chevron.left", "Back"); glass(moreB, "ellipsis", "More")
    backB.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
    moreB.showsMenuAsPrimaryAction = true
    moreB.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
      guard let self = self, let m = self.items[safe: self.at] else { done([]); return }
      done([UIAction(title: "Show in Chat", image: UIImage(systemName: "bubble.left")) { [weak self] _ in self?.dismiss(animated: true) { self?.onShow?(m) } },
            UIAction(title: "Forward", image: UIImage(systemName: "arrowshape.turn.up.right")) { [weak self] _ in self?.forwardCurrent() },
            UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share() },
            UIAction(title: "Save", image: UIImage(systemName: "arrow.down.to.line")) { [weak self] _ in self?.save() }])
    }])
    who.font = .systemFont(ofSize: 17, weight: .semibold); who.textColor = .white; who.textAlignment = .center
    when.font = .systemFont(ofSize: 13); when.textColor = UIColor(white: 0.62, alpha: 1); when.textAlignment = .center
    let names = UIStackView(arrangedSubviews: [who, when]); names.axis = .vertical; names.alignment = .center
    [backB, names, moreB].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; top.addSubview($0) }

    // the foot: the caption · reactions, ☺︎, Reply · the strip · Share · Forward · Save · Delete
    cap.textColor = .white; cap.font = .systemFont(ofSize: 17); cap.numberOfLines = 3
    var rc: UIButton.Configuration
    if #available(iOS 26.0, *) { rc = .glass() } else { rc = .gray(); rc.cornerStyle = .capsule; rc.background.backgroundColor = UIColor(white: 0.16, alpha: 0.9); rc.baseForegroundColor = UIColor(white: 0.8, alpha: 1) }
    reacts.configuration = rc; reacts.isUserInteractionEnabled = false
    glass(smile, "face.smiling", "React")
    smile.addAction(UIAction { [weak self] _ in guard let self = self, let m = self.items[safe: self.at] else { return }; self.onReact?(m) }, for: .touchUpInside)
    var pc: UIButton.Configuration
    if #available(iOS 26.0, *) { pc = .glass() } else { pc = .gray(); pc.cornerStyle = .capsule; pc.background.backgroundColor = UIColor(white: 0.16, alpha: 0.9); pc.baseForegroundColor = .white }
    pc.image = UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)); pc.imagePadding = 6
    pc.attributedTitle = AttributedString("Reply", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    replyB.configuration = pc
    replyB.addAction(UIAction { [weak self] _ in guard let self = self, let m = self.items[safe: self.at] else { return }; self.dismiss(animated: true) { self.onReply?(m) } }, for: .touchUpInside)
    strip.showsHorizontalScrollIndicator = false
    stripRow.axis = .horizontal; stripRow.spacing = 3; stripRow.alignment = .center
    for (i, m) in items.enumerated() {
      let b = UIButton(type: .custom); b.tag = i; b.imageView?.contentMode = .scaleAspectFill; b.clipsToBounds = true; b.layer.cornerRadius = 4
      b.widthAnchor.constraint(equalToConstant: 26).isActive = true; b.heightAnchor.constraint(equalToConstant: 36).isActive = true
      b.addAction(UIAction { [weak self] a in guard let t = (a.sender as? UIView)?.tag else { return }; self?.go(t, animated: false) }, for: .touchUpInside)
      // (the chat's own small picture when it has one — there at once; else a small one made off the main thread, not the
      //  whole photo: the strip came in late, Haris 2026-11-12)
      if let f = m.file {
        if let i = BubbleCell.cached(f.id) ?? ZoomPage.small(m, f) { b.setImage(i, for: .normal) } else { ZoomPage.thumb(m, f) { img in b.setImage(img, for: .normal) } }
      }
      stripRow.addArrangedSubview(b)
    }
    stripRow.translatesAutoresizingMaskIntoConstraints = false; strip.addSubview(stripRow)
    func tool(_ sym: String, _ label: String, _ red: Bool = false, _ act: @escaping () -> Void) -> UIButton {
      let b = UIButton(type: .system)
      // (the same size as the top's ‹ and ••• — Haris 2026-11-15)
      b.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)), for: .normal)
      b.tintColor = red ? .systemRed : .white; b.accessibilityLabel = label
      b.addAction(UIAction { _ in act() }, for: .touchUpInside); return b
    }
    tools.axis = .horizontal; tools.distribution = .equalSpacing; tools.alignment = .center
    let shareT = tool("square.and.arrow.up", "Share") { [weak self] in self?.share() }
    let fwdT = tool("arrowshape.turn.up.right", "Forward") { [weak self] in self?.forwardCurrent() }
    let saveT = tool("arrow.down.to.line", "Save") { [weak self] in self?.save() }
    let delT = tool("trash", "Delete", true) { [weak self] in guard let self = self, let m = self.items[safe: self.at] else { return }; self.dismiss(animated: true) { self.onDelete?(m) } }
    if #available(iOS 26.0, *) {
      // (as Photos — Haris 2026-11-14: Share on its own on the left, Forward · Save together in one glass in the middle,
      //  Delete on its own on the right; each Apple's own glass, the same taps as before)
      for (b, sym) in [(shareT, "square.and.arrow.up"), (delT, "trash")] {
        var c = UIButton.Configuration.glass(); c.image = b.image(for: .normal); c.contentInsets = .zero
        if sym == "trash" { c.baseForegroundColor = .systemRed }
        b.setImage(nil, for: .normal); b.configuration = c; b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 42), b.heightAnchor.constraint(equalToConstant: 42)])
      }
      let pair = UIVisualEffectView(effect: UIGlassEffect()); pair.cornerConfiguration = .capsule()
      let both = UIStackView(arrangedSubviews: [fwdT, saveT]); both.axis = .horizontal; both.distribution = .fillEqually
      [fwdT, saveT].forEach { $0.tintColor = .label }
      both.translatesAutoresizingMaskIntoConstraints = false; pair.contentView.addSubview(both); pair.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([pair.widthAnchor.constraint(equalToConstant: 100), pair.heightAnchor.constraint(equalToConstant: 42),
        both.leadingAnchor.constraint(equalTo: pair.contentView.leadingAnchor, constant: 6), both.trailingAnchor.constraint(equalTo: pair.contentView.trailingAnchor, constant: -6),
        both.topAnchor.constraint(equalTo: pair.contentView.topAnchor), both.bottomAnchor.constraint(equalTo: pair.contentView.bottomAnchor)])
      [shareT, pair, delT].forEach { tools.addArrangedSubview($0) }
    } else {
      [shareT, fwdT, saveT, delT].forEach { tools.addArrangedSubview($0) }
    }
    let row = UIStackView(arrangedSubviews: [reacts, smile, UIView(), replyB]); row.axis = .horizontal; row.spacing = 10; row.alignment = .center
    for l in [played, length] { l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium); l.textColor = .white; l.translatesAutoresizingMaskIntoConstraints = false; seek.addSubview(l) }
    played.text = "0:00"; length.textAlignment = .right
    bar.minimumTrackTintColor = .white; bar.maximumTrackTintColor = UIColor(white: 1, alpha: 0.3)
    let knob = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14)).image { _ in UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 14, height: 14)).fill() }
    bar.setThumbImage(knob, for: .normal); bar.setThumbImage(knob, for: .highlighted)
    bar.translatesAutoresizingMaskIntoConstraints = false; seek.addSubview(bar); seek.clipsToBounds = true
    bar.addAction(UIAction { [weak self] _ in guard let self = self else { return }; self.dragging = true; self.pages[safe: self.at]?.scrubBegin() }, for: .touchDown)
    bar.addAction(UIAction { [weak self] _ in guard let self = self else { return }; self.played.text = PhotoViewerVC.clock(Double(self.bar.value)); self.pages[safe: self.at]?.scrub(to: Double(self.bar.value)) }, for: .valueChanged)
    bar.addAction(UIAction { [weak self] _ in guard let self = self else { return }; self.dragging = false; self.pages[safe: self.at]?.scrubEnd() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    NSLayoutConstraint.activate([
      played.leadingAnchor.constraint(equalTo: seek.leadingAnchor, constant: 18), played.centerYAnchor.constraint(equalTo: seek.centerYAnchor), played.widthAnchor.constraint(equalToConstant: 44),
      length.trailingAnchor.constraint(equalTo: seek.trailingAnchor, constant: -18), length.centerYAnchor.constraint(equalTo: seek.centerYAnchor), length.widthAnchor.constraint(equalToConstant: 44),
      bar.leadingAnchor.constraint(equalTo: played.trailingAnchor, constant: 8), bar.trailingAnchor.constraint(equalTo: length.leadingAnchor, constant: -8), bar.centerYAnchor.constraint(equalTo: seek.centerYAnchor),
    ])
    pages.forEach { pg in pg.onPlayer = { [weak self, weak pg] in guard let self = self, let pg = pg, self.pages[safe: self.at] === pg else { return }; self.follow(pg) } }
    [cap, row, seek, strip, tools].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; foot.addSubview($0) }
    [top, foot].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    let g0 = topShade.layer as! CAGradientLayer
    g0.colors = [UIColor(white: 0, alpha: 0.5).cgColor, UIColor(white: 0, alpha: 0.18).cgColor, UIColor.clear.cgColor]; g0.locations = [0, 0.55, 1]
    topShade.isUserInteractionEnabled = false; top.clipsToBounds = false; top.insertSubview(topShade, at: 0)
    // (the same soft shade under the buttons at the foot, the top's turned upside down — Haris 2026-11-14; it comes and
    //  goes with them)
    let g1 = footShade.layer as! CAGradientLayer
    g1.colors = g0.colors?.reversed(); g1.locations = [0, 0.45, 1]
    footShade.isUserInteractionEnabled = false; foot.clipsToBounds = false; foot.insertSubview(footShade, at: 0)

    let g = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      top.topAnchor.constraint(equalTo: g.topAnchor), top.leadingAnchor.constraint(equalTo: view.leadingAnchor), top.trailingAnchor.constraint(equalTo: view.trailingAnchor), top.heightAnchor.constraint(equalToConstant: 58),
      backB.leadingAnchor.constraint(equalTo: top.leadingAnchor, constant: 16), backB.centerYAnchor.constraint(equalTo: top.centerYAnchor),
      moreB.trailingAnchor.constraint(equalTo: top.trailingAnchor, constant: -16), moreB.centerYAnchor.constraint(equalTo: top.centerYAnchor),
      names.centerXAnchor.constraint(equalTo: top.centerXAnchor), names.centerYAnchor.constraint(equalTo: top.centerYAnchor),
      names.leadingAnchor.constraint(greaterThanOrEqualTo: backB.trailingAnchor, constant: 8),
      foot.leadingAnchor.constraint(equalTo: view.leadingAnchor), foot.trailingAnchor.constraint(equalTo: view.trailingAnchor), foot.bottomAnchor.constraint(equalTo: g.bottomAnchor),
      cap.topAnchor.constraint(equalTo: foot.topAnchor), cap.leadingAnchor.constraint(equalTo: foot.leadingAnchor, constant: 18), cap.trailingAnchor.constraint(equalTo: foot.trailingAnchor, constant: -18),
      row.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: 12), row.leadingAnchor.constraint(equalTo: foot.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: foot.trailingAnchor, constant: -14),
      replyB.heightAnchor.constraint(equalToConstant: 34), reacts.heightAnchor.constraint(equalToConstant: 42),
      seek.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 0), seek.leadingAnchor.constraint(equalTo: foot.leadingAnchor), seek.trailingAnchor.constraint(equalTo: foot.trailingAnchor),
      strip.topAnchor.constraint(equalTo: seek.bottomAnchor, constant: 12), strip.leadingAnchor.constraint(equalTo: foot.leadingAnchor), strip.trailingAnchor.constraint(equalTo: foot.trailingAnchor), strip.heightAnchor.constraint(equalToConstant: 40),
      stripRow.centerYAnchor.constraint(equalTo: strip.centerYAnchor), stripRow.leadingAnchor.constraint(equalTo: strip.contentLayoutGuide.leadingAnchor, constant: 14),
      stripRow.trailingAnchor.constraint(equalTo: strip.contentLayoutGuide.trailingAnchor, constant: -14), stripRow.topAnchor.constraint(equalTo: strip.contentLayoutGuide.topAnchor, constant: 2),
      tools.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 10), tools.leadingAnchor.constraint(equalTo: foot.leadingAnchor, constant: 34), tools.trailingAnchor.constraint(equalTo: foot.trailingAnchor, constant: -34),
      tools.heightAnchor.constraint(equalToConstant: { if #available(iOS 26.0, *) { return 42 } else { return 40 } }()), tools.bottomAnchor.constraint(equalTo: foot.bottomAnchor, constant: -4),
    ])
    strip.isHidden = items.count < 2
    seekH = seek.heightAnchor.constraint(equalToConstant: 0); seekH.isActive = true
    let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
    pages.forEach { tap.require(toFail: $0.doubleTap) }
    pager.addGestureRecognizer(tap)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:))); pan.delegate = self
    view.addGestureRecognizer(pan)
  }
  // (the one on show always in the strip's middle, as Photos — Haris 2026-11-15: room at both ends, so the first and the
  //  last can come to the middle too)
  private func centreStrip() {
    let pad = max(0, strip.bounds.width / 2 - 27)
    guard abs(strip.contentInset.left - pad) > 0.5 else { return }
    strip.contentInset = UIEdgeInsets(top: 0, left: pad, bottom: 0, right: pad)
    if stripPlaced { placeStrip(animated: false) }
  }
  private func placeStrip(animated: Bool) {
    guard let b = stripRow.arrangedSubviews[safe: at] else { return }
    strip.setContentOffset(CGPoint(x: stripRow.frame.minX + b.frame.midX - strip.bounds.width / 2, y: 0), animated: animated)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    centreStrip()
    topShade.frame = CGRect(x: 0, y: -top.frame.minY, width: view.bounds.width, height: top.frame.maxY + 30)
    footShade.frame = CGRect(x: 0, y: -30, width: view.bounds.width, height: view.bounds.height - foot.frame.minY + 30)
    pager.frame = view.bounds
    for (i, p) in pages.enumerated() { p.frame = CGRect(x: CGFloat(i) * view.bounds.width, y: 0, width: view.bounds.width, height: view.bounds.height) }
    pager.contentSize = CGSize(width: view.bounds.width * CGFloat(pages.count), height: view.bounds.height)
    if !placed { placed = true; pager.contentOffset.x = CGFloat(at) * view.bounds.width; showCurrent() }
  }
  private var placed = false
  // (a video plays the moment it's on show — opened, or swiped to: no ▶ to tap first, Haris 2026-11-14; the buttons step
  //  aside once it plays, as Photos; a tap brings them back with ⏸)
  private var opened = false
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); opened = true; pages[safe: at]?.start() }
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); pages.forEach { $0.stop() }; follow(nil) }

  // opening: out of its bubble (the design's "Opening a photo") — the picture flies from the bubble to its place
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    pages[safe: at]?.prepare()
    // (the photo's own picture flies — out of an album, its square, not the whole grid: Haris 2026-11-12)
    guard let m = items[safe: at], let spot = source?(m), let w = spot.0.window else { return }
    let src = spot.0, r = spot.1
    let whole = r == src.bounds
    // (an album's photo: its own picture read now from the phone — an album keeps only its grid, so there was nothing to
    //  fly and the viewer stood black until the photo was read, Haris 2026-11-12)
    guard let img = m.file.flatMap({ ZoomPage.full(m, $0) ?? ZoomPage.quick(m, $0) }) ?? (whole ? (src as? UIImageView)?.image : nil) else { return }
    let from = src.convert(r, to: w)
    // (the flying picture starts as the bubble's photo looks — its corners and its shades — and the photo in the bubble
    //  is hidden meanwhile: nothing of it shows twice, nothing appears afterwards, Haris 2026-11-12)
    let fly = PhotoViewerVC.flier(img, like: whole ? src : nil); fly.frame = from
    beside?(m, false)
    // (under the buttons — it flew over ☺︎ and Reply and cut them, Haris 2026-11-12)
    view.insertSubview(fly, aboveSubview: pager); pager.alpha = 0; back.alpha = 0; top.alpha = 0; foot.alpha = 0
    if whole { src.alpha = 0 }
    pages[safe: at]?.landed = false
    let to = ZoomPage.fit(img.size, in: view.bounds)
    UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0) {
      fly.frame = to; fly.layer.cornerRadius = 0; fly.shades.forEach { $0.alpha = 0 }; self.back.alpha = 1; self.top.alpha = 1; self.foot.alpha = 1
    } completion: { _ in
      // (the page fades in over the landed picture — with it Apple's shade under the status bar, which popped in at once,
      //  Haris 2026-11-12)
      self.pages.forEach { $0.landed = true }
      UIView.animate(withDuration: 0.18, animations: { self.pager.alpha = 1 }) { _ in fly.removeFromSuperview(); src.alpha = 1 }
    }
  }

  private func go(_ i: Int, animated: Bool) {
    guard items.indices.contains(i) else { return }
    at = i; pager.setContentOffset(CGPoint(x: CGFloat(i) * view.bounds.width, y: 0), animated: animated); showCurrent()
  }
  func scrollViewDidEndDecelerating(_ s: UIScrollView) {
    guard s === pager, view.bounds.width > 0 else { return }
    let i = Int(round(s.contentOffset.x / view.bounds.width))
    if i != at { pages[safe: at]?.reset(); at = i; showCurrent() }
  }
  private func showCurrent() {
    guard let m = items[safe: at] else { return }
    for (i, p) in pages.enumerated() where i != at { p.stop() }
    if opened { pages[at].start() }
    let T = Talk.shared
    who.text = m.by == T.me?.id ? "You" : T.name(m.by)
    let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
    when.text = f.string(from: Date(timeIntervalSince1970: m.at / 1000))
    cap.text = m.text; cap.isHidden = m.text.isEmpty
    let video = m.kind == "video"
    seekH.constant = video ? 34 : 0; seek.isHidden = !video
    if video { follow(pages[at]) } else { follow(nil) }
    let counts = Dictionary(grouping: m.reactions.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    reacts.isHidden = counts.isEmpty
    reacts.configuration?.attributedTitle = AttributedString(counts.map { $0.0 }.joined() + (m.reactions.count > 1 ? "  \(m.reactions.count)" : ""),
                                                            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15)]))
    for (i, b) in stripRow.arrangedSubviews.enumerated() {
      let on = i == at
      b.layer.borderWidth = on ? 1.5 : 0; b.layer.borderColor = UIColor.white.cgColor
      (b.constraints.first { $0.firstAttribute == .width })?.constant = on ? 40 : 26
    }
    // (the strip centred on the one shown — already in place as the viewer opens, sliding only when you move between
    //  photos; it opened at its start and then slid across, Haris 2026-11-12)
    guard let b = stripRow.arrangedSubviews[safe: at] else { return }
    if !stripPlaced { view.layoutIfNeeded() } else { strip.layoutIfNeeded() }
    centreStrip()
    placeStrip(animated: stripPlaced)
    stripPlaced = true
  }
  private var stripPlaced = false
  // the seek row follows the video on show: its length, and where it is, ten times a second
  private func follow(_ pg: ZoomPage?) {
    if let o = ticks, let p = ticking { p.removeTimeObserver(o) }
    ticks = nil; ticking = nil
    guard let pg = pg else { return }
    let p = pg.player
    var len = pg.seconds ?? 0
    if let d = p?.currentItem?.duration, d.isNumeric, d.seconds > 0 { len = d.seconds }
    bar.minimumValue = 0; bar.maximumValue = Float(max(len, 0.1))
    length.text = PhotoViewerVC.clock(len)
    let now = p.map { $0.currentTime().seconds } ?? 0
    if !dragging { bar.value = Float(now.isFinite ? now : 0); played.text = PhotoViewerVC.clock(now.isFinite ? now : 0) }
    guard let pl = p else { return }
    ticking = pl
    ticks = pl.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
      guard let self = self, !self.dragging else { return }
      if let d = pl.currentItem?.duration, d.isNumeric, d.seconds > 0, abs(Double(self.bar.maximumValue) - d.seconds) > 0.05 {
        self.bar.maximumValue = Float(d.seconds); self.length.text = PhotoViewerVC.clock(d.seconds)
      }
      self.bar.value = Float(t.seconds); self.played.text = PhotoViewerVC.clock(t.seconds)
    }
  }
  static func clock(_ s: Double) -> String { let n = Int((s.isFinite ? s : 0).rounded(.down)); return String(format: "%d:%02d", n / 60, n % 60) }
  @objc private func toggleChrome() {
    chrome.toggle()
    pages[safe: at]?.chrome = chrome
    UIView.animate(withDuration: 0.2) { self.top.alpha = self.chrome ? 1 : 0; self.foot.alpha = self.chrome ? 1 : 0; self.setNeedsStatusBarAppearanceUpdate() }
  }

  // ---------- swiped down: the picture follows the finger, the black fades; far enough — back into its bubble ----------
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard let p = g as? UIPanGestureRecognizer, let page = pages[safe: at], page.zoomScale <= page.minimumZoomScale + 0.01 else { return false }
    let v = p.velocity(in: view)
    return v.y > abs(v.x) * 1.2
  }
  @objc private func drag(_ g: UIPanGestureRecognizer) {
    guard let page = pages[safe: at] else { return }
    let t = g.translation(in: view), k = max(0, min(1, t.y / 400))
    switch g.state {
    case .changed:
      page.image.transform = CGAffineTransform(translationX: t.x, y: t.y).scaledBy(x: 1 - k * 0.3, y: 1 - k * 0.3)
      back.alpha = 1 - k; top.alpha = chrome ? 1 - k * 3 : 0; foot.alpha = top.alpha
    case .ended, .cancelled:
      if t.y > 110 || g.velocity(in: view).y > 900 { close(from: page) }
      else {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
          page.image.transform = .identity; self.back.alpha = 1; self.top.alpha = self.chrome ? 1 : 0; self.foot.alpha = self.top.alpha
        }
      }
    default: break
    }
  }
  // the flying picture: the photo, and — flying from or to a bubble — that photo's corners and its two shades (the name's
  // diagonal, the time's at the bottom), as views that stretch with it
  final class Flier: UIImageView { var shades: [UIView] = [] }
  final class Shade: UIView { override class var layerClass: AnyClass { CAGradientLayer.self } }
  static func flier(_ img: UIImage, like src: UIView?) -> Flier {
    let f = Flier(image: img); f.contentMode = .scaleAspectFill; f.clipsToBounds = true
    guard let src = src else { return f }
    f.layer.cornerRadius = src.layer.cornerRadius; f.layer.cornerCurve = src.layer.cornerCurve; f.layer.maskedCorners = src.layer.maskedCorners
    for l in src.layer.sublayers ?? [] {
      guard let g = l as? CAGradientLayer, !g.isHidden, g.name == "diag" || g.name == "foot" else { continue }
      let v = Shade(); v.isUserInteractionEnabled = false
      let c = v.layer as! CAGradientLayer
      c.colors = g.colors; c.locations = g.locations; c.startPoint = g.startPoint; c.endPoint = g.endPoint
      if g.name == "diag" { v.frame = CGRect(origin: .zero, size: src.bounds.size); v.autoresizingMask = [.flexibleWidth, .flexibleHeight] }
      else { v.frame = CGRect(x: 0, y: src.bounds.height - 44, width: src.bounds.width, height: 44); v.autoresizingMask = [.flexibleWidth, .flexibleTopMargin] }
      f.frame = CGRect(origin: .zero, size: src.bounds.size)
      f.addSubview(v); f.shades.append(v)
    }
    return f
  }
  private func close(from page: ZoomPage? = nil) {
    pages.forEach { $0.stop() }
    let page = page ?? pages[safe: at]
    guard let page = page, let m = items[safe: at], let spot = source?(m), let w = spot.0.window else {
      UIView.animate(withDuration: 0.2, animations: { self.view.alpha = 0 }) { _ in self.dismiss(animated: false) }; return
    }
    let src = spot.0, r = spot.1, whole = r == src.bounds
    let to = src.convert(r, to: w), from = page.image.convert(page.image.bounds, to: view)
    guard let pic = page.image.image else { UIView.animate(withDuration: 0.2, animations: { self.view.alpha = 0 }) { _ in self.dismiss(animated: false) }; return }
    // (it lands looking exactly as the bubble's photo — its corners, its shades growing in on the way — and then the real
    //  one takes its place in the same frame: nothing reloads, Haris 2026-11-12. Back into an album: its own square.)
    let fly = PhotoViewerVC.flier(pic, like: whole ? src : nil); fly.frame = from
    let radius = fly.layer.cornerRadius; fly.layer.cornerRadius = 0; fly.shades.forEach { $0.alpha = 0 }
    view.insertSubview(fly, aboveSubview: pager); page.image.isHidden = true; if whole { src.alpha = 0 }
    beside?(m, false)
    let back = beside
    UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
      fly.frame = to; fly.layer.cornerRadius = radius; fly.shades.forEach { $0.alpha = 1 }; self.back.alpha = 0; self.top.alpha = 0; self.foot.alpha = 0
    } completion: { _ in
      if whole { src.alpha = 1; self.dismiss(animated: false); back?(m, true) }
      else { UIView.animate(withDuration: 0.12, animations: { fly.alpha = 0 }) { _ in self.dismiss(animated: false); back?(m, true) } }   // (an album's square: the grid's own picture under it)
    }
  }

  // ---------- the foot's actions ----------
  private func share() {
    guard let m = items[safe: at], let f = m.file else { return }
    Net.shared.file(f.id) { [weak self] url in DispatchQueue.main.async {
      guard let self = self, let url = url else { return }
      let named = ShareCopy.named(f, from: url)
      self.present(ShareOut.sheet([named]), animated: true)
    } }
  }
  private func save() {
    guard let m = items[safe: at], let f = m.file else { return }
    Net.shared.file(f.id) { url in DispatchQueue.main.async {
      guard let url = url else { return }
      if m.kind == "video" {
        let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
        try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
        UISaveVideoAtPathToSavedPhotosAlbum(named.path, nil, nil, nil)
      } else if let i = UIImage(contentsOfFile: url.path) { UIImageWriteToSavedPhotosAlbum(i, nil, nil, nil) }
      toast("Saved to Photos")
    } }
  }
  private func forwardCurrent() { guard let m = items[safe: at] else { return }; dismiss(animated: true) { self.onForward?(m) } }
}

// one photo or video, zoomable (Apple's scroll view zoom; double-tap in and out — videos too); a video: its first picture with ▶
final class ZoomPage: UIScrollView, UIScrollViewDelegate {
  let image = UIImageView(), doubleTap = UITapGestureRecognizer()
  private let msg: Msg
  // a video, playing in place (Apple's player layer over its first picture, fading in once its first frame is there)
  final class PlayerView: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; var pl: AVPlayerLayer { layer as! AVPlayerLayer } }
  private(set) var player: AVPlayer?
  private var playerView: PlayerView?, ready: NSKeyValueObservation?, rate: NSKeyValueObservation?, ended: NSObjectProtocol?
  private var want = false, atEnd = false, loading = false
  var onPlaying: (() -> Void)?
  var onPlayer: (() -> Void)?   // (its player made — the viewer's seek bar follows it)
  var seconds: Double? { msg.file?.secs }
  // (sound and picture together — Haris 2026-11-22 18:52: it played under the flying still, heard before it was seen. It
  //  plays only once the picture has landed and its first frame is ready; the still stays only until then)
  var landed = true { didSet { go() } }
  private func go() {
    guard want, landed, !held, let p = player, playerView?.pl.isReadyForDisplay == true, p.timeControlStatus == .paused else { return }
    p.play()
  }
  var chrome = true { didSet { button(animated: true) } }
  init(msg: Msg) {
    self.msg = msg; super.init(frame: .zero)
    delegate = self; minimumZoomScale = 1; maximumZoomScale = 4; showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never; bouncesZoom = true
    if #available(iOS 26.0, *) { topEdgeEffect.isHidden = true; bottomEdgeEffect.isHidden = true }
    image.contentMode = .scaleAspectFit; addSubview(image)
    doubleTap.numberOfTapsRequired = 2; doubleTap.addTarget(self, action: #selector(zoom(_:))); addGestureRecognizer(doubleTap)
    // (the chat's own picture at once, the full one taking its place when it's read — the page was empty a moment)
    if let f = msg.file {
      image.image = BubbleCell.cached(f.id)
      ZoomPage.picture(msg, f) { [weak self] img in if let img = img { self?.image.image = img; self?.setNeedsLayout() } }
    }
    if msg.kind == "video" {
      let play = UIButton(type: .system)
      var c = UIButton.Configuration.filled(); c.cornerStyle = .capsule; c.baseBackgroundColor = UIColor(white: 0, alpha: 0.45); c.baseForegroundColor = .white
      c.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)); play.configuration = c
      play.frame = CGRect(x: 0, y: 0, width: 70, height: 70); play.tag = 7
      play.addAction(UIAction { [weak self] _ in guard let self = self else { return }
        if (self.player?.timeControlStatus ?? .paused) != .paused { self.want = false; self.held = true; self.player?.pause(); self.button(animated: true) } else { self.held = false; self.start() } }, for: .touchUpInside)
      play.alpha = 0   // (it plays by itself: the ▶ only once it's paused or ended)
      addSubview(play)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    if zoomScale == 1 { image.frame = ZoomPage.fit(image.image?.size ?? bounds.size, in: bounds); contentSize = bounds.size }
    if let b = viewWithTag(7) { b.center = CGPoint(x: bounds.midX, y: bounds.midY); bringSubviewToFront(b) }   // (the middle of what shows, zoomed or not)
  }
  // (a video zooms as a photo does, playing or paused — its player is inside the picture; its ▶ / ⏸ stays in the middle at
  //  its own size: Haris 2026-11-18 19:38)
  func viewForZooming(in s: UIScrollView) -> UIView? { image }
  func scrollViewDidZoom(_ s: UIScrollView) {
    // (kept in the middle while it's smaller than the screen)
    let dx = max(0, (bounds.width - contentSize.width) / 2), dy = max(0, (bounds.height - contentSize.height) / 2)
    image.center = CGPoint(x: contentSize.width / 2 + dx, y: contentSize.height / 2 + dy)
  }
  @objc private func zoom(_ g: UITapGestureRecognizer) {
    if zoomScale > 1 { setZoomScale(1, animated: true) }
    else { let p = g.location(in: image); zoom(to: CGRect(x: p.x - 60, y: p.y - 60, width: 120, height: 120), animated: true) }
  }
  func reset() { setZoomScale(1, animated: false) }
  // on show: it plays (from the phone's copy — fetched first if it isn't there yet); off show: it pauses
  func start() {
    guard msg.kind == "video", let f = msg.file else { return }
    want = true
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    if let p = player { if atEnd { atEnd = false; p.seek(to: .zero) }; go(); return }
    load(f)
  }
  // (as the viewer starts opening: the player made and readied, not playing — it plays the moment the picture has landed,
  //  instead of only starting to get ready then: Haris 2026-11-22 18:21)
  func prepare() {
    guard msg.kind == "video", let f = msg.file, player == nil else { return }
    load(f)
  }
  private func load(_ f: Msg.FileRef) {
    guard !loading else { return }
    loading = true
    Net.shared.file(f.id) { [weak self] url in DispatchQueue.main.async {
      guard let self = self else { return }
      self.loading = false
      guard let url = url, self.player == nil else { return }
      // (under its own name, so the player knows its kind — the phone's copy has none)
      let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.id.replacingOccurrences(of: "/", with: "_") + "-" + f.name)
      if !FileManager.default.fileExists(atPath: named.path) { try? FileManager.default.copyItem(at: url, to: named) }
      let p = AVPlayer(url: named); p.actionAtItemEnd = .pause
      let v = PlayerView(); v.pl.player = p; v.pl.videoGravity = .resizeAspect; v.alpha = 0; v.isUserInteractionEnabled = false
      v.frame = self.image.bounds; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      self.image.addSubview(v)   // (inside the picture: it follows the finger when swiped down, and flies back with it)
      self.player = p; self.playerView = v
      self.ready = v.pl.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
        guard l.isReadyForDisplay else { return }
        DispatchQueue.main.async { v.alpha = 1; self?.go() }   // (its first frame in place of the still at once, then it plays)
      }
      self.rate = p.observe(\.timeControlStatus, options: [.new]) { [weak self] pl, _ in
        DispatchQueue.main.async { guard let self = self else { return }; if pl.timeControlStatus == .playing { self.onPlaying?() }; self.button(animated: true) }
      }
      self.ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in self?.atEnd = true; self?.button(animated: true) }
      self.onPlayer?()
      self.go()
    } }
  }
  // the seek bar: dragged — paused while the finger is on it, on from there when it's let go (if it was playing)
  // (one exact jump on its way at a time — when it lands, the next goes to where the finger is now: Apple's smooth scrubbing.
  //  Let go: it plays once the last jump has landed, whether iPhone says it finished or not, and after half a second anyway.
  //  It played at once while jumps were still on their way, and the last one took it back: the first frames twice after
  //  dragging to the start — Haris 2026-11-23 12:04)
  private var wasPlaying = false, chasing = false, chaseTo: Double?, letGo = false, scrubN = 0
  func scrubBegin() { wasPlaying = player?.timeControlStatus != .paused; player?.pause(); letGo = false; scrubN += 1 }
  func scrub(to t: Double) {
    atEnd = false; chaseTo = t
    if !chasing { chase() }
    button(animated: true)
  }
  private func chase() {
    guard let p = player, let t = chaseTo else { chasing = false; if letGo { playLetGo() }; return }
    chasing = true; chaseTo = nil
    p.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      DispatchQueue.main.async { self?.chase() }
    }
  }
  func scrubEnd() {
    guard wasPlaying, want, !held else { return }
    letGo = true
    guard chasing else { return playLetGo() }
    let n = scrubN
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self = self, self.scrubN == n, self.letGo else { return }
      self.playLetGo()
    }
  }
  private func playLetGo() { guard letGo else { return }; letGo = false; if want, !held { player?.play() } }
  func stop() { want = false; held = false; player?.pause(); button(animated: false) }
  private var held = false   // (paused with ⏸ — its ▶ stays until tapped)
  // ▶ once paused with ⏸ or ended; ⏸ while it plays and the buttons are shown; nothing while it plays on its own or loads
  private func button(animated: Bool) {
    guard let b = viewWithTag(7) as? UIButton else { return }
    let playing = player?.timeControlStatus == .playing
    let name = playing ? "pause.fill" : "play.fill"
    let alpha: CGFloat = playing ? (chrome ? 1 : 0) : (held || atEnd ? 1 : 0)
    guard b.alpha != alpha || b.configuration?.image?.accessibilityIdentifier != name else { return }
    let set = {
      let img = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)); img?.accessibilityIdentifier = name
      b.configuration?.image = img; b.alpha = alpha
    }
    if animated { UIView.transition(with: b, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction], animations: set) } else { set() }
  }
  deinit { if let e = ended { NotificationCenter.default.removeObserver(e) } }
  static func fit(_ size: CGSize, in b: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0 else { return b }
    let k = min(b.width / size.width, b.height / size.height), w = size.width * k, h = size.height * k
    return CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
  }
  // a small picture for the strip, made off the main thread
  // the chat's picture of it, or — a photo already on the phone — read now at the chat's size (kept for next time)
  static func quick(_ m: Msg, _ f: Msg.FileRef) -> UIImage? {
    if let i = BubbleCell.cached(f.id) { return i }
    let u = Net.local(f.id)
    guard m.kind == "photo", FileManager.default.fileExists(atPath: u.path) else { return nil }
    return BubbleCell.picture(u, f.id)
  }
  // the strip's picture of a photo already on the phone, read now — small, so the whole strip is there as it opens
  private static let smalls = NSCache<NSString, UIImage>()
  static func small(_ m: Msg, _ f: Msg.FileRef) -> UIImage? {
    if let i = smalls.object(forKey: f.id as NSString) { return i }
    let u = Net.local(f.id)
    guard m.kind == "photo", FileManager.default.fileExists(atPath: u.path),
          let src = CGImageSourceCreateWithURL(u as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 120] as CFDictionary) else { return nil }
    let i = UIImage(cgImage: cg); smalls.setObject(i, forKey: f.id as NSString); return i
  }
  static func thumb(_ m: Msg, _ f: Msg.FileRef, _ done: @escaping (UIImage?) -> Void) {
    // (Auto-download off for it: its little blurred picture — the grid never downloads by itself)
    if !Auto.here(f) && !Auto.now(m.kind) { done(Thumb.image(f)); return }
    Net.shared.file(f.id) { url in
      guard let url = url else { DispatchQueue.main.async { done(nil) }; return }
      if m.kind == "video" { BubbleCell.frame(url, f.id) { i in DispatchQueue.main.async { done(i) } }; return }
      DispatchQueue.global(qos: .userInitiated).async {
        let i = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 120] as CFDictionary) }.map { UIImage(cgImage: $0) }
        DispatchQueue.main.async { done(i) }
      }
    }
  }
  static func picture(_ m: Msg, _ f: Msg.FileRef, _ done: @escaping (UIImage?) -> Void) {
    if m.kind == "photo", let i = fulls.object(forKey: f.id as NSString) { return done(i) }
    Net.shared.file(f.id) { url in DispatchQueue.main.async {
      guard let url = url else { done(nil); return }
      if m.kind == "video" { BubbleCell.frame(url, f.id) { i in DispatchQueue.main.async { done(i) } } }
      else {
        let i = UIImage(contentsOfFile: url.path).map { $0.preparingForDisplay() ?? $0 }
        if let i = i { fulls.setObject(i, forKey: f.id as NSString) }
        done(i)
      }
    } }
  }
  // (full photos ready to draw — the last few opened; and one already on the phone, read now: Haris 2026-11-19 11:15)
  private static let fulls: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 16; return c }()
  static func full(_ m: Msg, _ f: Msg.FileRef) -> UIImage? {
    guard m.kind == "photo" else { return nil }
    if let i = fulls.object(forKey: f.id as NSString) { return i }
    let u = Net.local(f.id)
    guard FileManager.default.fileExists(atPath: u.path), let raw = UIImage(contentsOfFile: u.path) else { return nil }
    let i = raw.preparingForDisplay() ?? raw
    fulls.setObject(i, forKey: f.id as NSString); return i
  }
}
