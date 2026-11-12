import UIKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox
import ImageIO

/* A group's chat (the mockups — WhatsApp's way, in E11's colours with SF Symbols): bubbles with the time inside and
   ✓✓ (blue once everyone has seen it), names coloured with their role, a reply's quote (tap: up to the original), photos
   and files, "Edited", "This message was deleted", reactions under the bubble. Swipe a message right to reply (the
   keyboard opens); swipe your own left for Message info; hold it: Apple's lift, the reactions as Apple's palette (seven
   and + for any emoji), then Reply · Copy · Star · (yours: Edit for 15 minutes, Info) · Delete (for everyone about 2 days,
   for me). The message bar: + (Photos, Camera, Files), the box, camera and mic; while typing, the send button. */
enum ChatItem: Hashable { case msg(String) }

final class ChatVC: UIViewController, UITableViewDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate, UIGestureRecognizerDelegate {
  let group: String
  private let table = UITableView(frame: .zero, style: .plain)
  // (one section per day: its chip is the section's header — Apple's own floating header, stuck under the bar until the
  //  next day's pushes it away, as E11 Console's comments)
  private var data: UITableViewDiffableDataSource<String, ChatItem>!
  private var dayOf: [String: String] = [:]   // section → the words on its chip
  private var msgs: [String: Msg] = [:]
  private var sigs: [String: Int] = [:]
  private var runs: [String: Run] = [:]
  private let bar = MessageBar()
  private var kb: CGFloat = 0
  private var replying: Msg? { didSet {
    let mine = replying?.by == Talk.shared.me?.id
    bar.setReply(replying.map { (mine ? "You" : Talk.shared.name($0.by), Talk.preview($0)) }, editing: false, ink: replying.map { mine ? Look.accent : Look.person($0.by) } ?? Look.accent)
  } }
  private var editingMsg: Msg?
  private var previewURL: URL?
  private let titleV = UIStackView(), titleL = UILabel(), subL = UILabel(), titlePic = Avatar(frame: CGRect(x: 0, y: 0, width: 39, height: 39))
  private let clientLine = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
  private let downB = UIButton(type: .custom)
  private var downBottom: NSLayoutConstraint!

  private var focus: String?   // (opened from a search result: that message, highlighted)
  init(group: String, focus: String? = nil) { self.group = group; self.focus = focus; super.init(nibName: nil, bundle: nil)
    // (Apple's own: the tab bar slides away with the list as the chat comes in, and back with the finger on the back swipe —
    //  Haris 2026-11-12, option A; it was hidden with Apple's call after arriving and faded, iOS 26 leaving it drawn)
    hidesBottomBarWhenPushed = true
  }
  required init?(coder: NSCoder) { fatalError() }
  /* The message bar is part of the page, held on Apple's keyboard guide (Haris 2026-11-12): above the keyboard while it's
     up, above the home line while it's down — the lower of the two, so it moves with the keyboard (and a drag down)
     smoothly, never jumping as the home line's room came and went; its frost reaches down behind the keyboard, so no
     page shows at the keyboard's rounded corners. (It was the keyboard's own accessory before.) While searching, the
     bar of matches takes its place (the design's board "Search in a chat"). */
  private var homeLimits: [NSLayoutConstraint] = []
  private let topFrost = ChatVC.frost()
  private let titleSpot = UIView()
  private var spotW: NSLayoutConstraint!
  private static let titleLead: CGFloat = { if #available(iOS 26.0, *) { return 68 } else { return 44 } }()
  private static let rowMid: CGFloat = { if #available(iOS 26.0, *) { return 27 } else { return 22 } }()
  // (the picture's middle level with the back button's, as WhatsApp's — measured from Haris's screenshots: it sat about 5
  //  lower, 2026-11-12)
  private static let titleMid: CGFloat = { if #available(iOS 26.0, *) { return 32 } else { return 22 } }()
  // the picture and the name in the page, on its frost (they slide with it)
  private func pinTitle() {
    titleV.removeFromSuperview(); titleV.translatesAutoresizingMaskIntoConstraints = false
    view.insertSubview(titleV, aboveSubview: topFrost)
    NSLayoutConstraint.activate([titleV.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: ChatVC.titleLead),
                                 titleV.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -ChatVC.titleMid)])
  }
  // the chat's top frost (Haris 2026-11-12, b): Apple's blur, tinted thick with the chat's colour — nothing shows through
  static func frost() -> UIVisualEffectView {
    let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial)); v.isUserInteractionEnabled = false
    v.contentView.backgroundColor = UIColor { Look.chatBg.resolvedColor(with: $0).withAlphaComponent(0.8) }
    return v
  }
  private var home: CGFloat { UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0 }
  private func placeBars() {
    if #available(iOS 17.0, *) { view.keyboardLayoutGuide.usesBottomSafeArea = false }   // (iOS 16: the guide stops at the home line itself)
    for a in [bar, findAcc] as [UIView] {
      a.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(a)
      let onKeys = a.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor); onKeys.priority = .init(999)
      let aboveHome = a.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -home)
      homeLimits.append(aboveHome)
      NSLayoutConstraint.activate([a.leadingAnchor.constraint(equalTo: view.leadingAnchor), a.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                   a.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor), onKeys, aboveHome])
    }
    findAcc.isHidden = true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Look.chatBg
    navigationItem.largeTitleDisplayMode = .never
    table.backgroundColor = .clear; table.separatorStyle = .none; table.keyboardDismissMode = .interactive
    table.delegate = self; table.estimatedRowHeight = 60; table.rowHeight = UITableView.automaticDimension
    table.register(BubbleCell.self, forCellReuseIdentifier: "b"); table.register(DayHeader.self, forHeaderFooterViewReuseIdentifier: "d")
    table.sectionHeaderTopPadding = 0
    table.frame = view.bounds; table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // (the room above and below the messages is ours to set: the bar at the top, the message bar at the bottom — fitBottom)
    table.contentInsetAdjustmentBehavior = .never
    // (the day chips are floating headers: on automatic Apple draws its firm frost with a line down past them — the chat
    //  gets Apple's soft frost instead, as E11 Console's comments, Haris 2026-11-10 / 2026-11-12)
    // (WhatsApp's, Haris 2026-11-12: one steady frost the bar's own height, always there — no edge effect growing down
    //  past the day chips; the stuck chip sits just under it)
    if #available(iOS 26.0, *) { table.topEdgeEffect.isHidden = true }
    // (the frost is the page's own, under Apple's bar, which is clear here — so it slides with the page on the back swipe;
    //  as the bar's own background it went the moment the swipe began, the bar taking the list's look — Haris 2026-11-12)
    let barLook = UINavigationBarAppearance(); barLook.configureWithTransparentBackground()
    navigationItem.standardAppearance = barLook; navigationItem.scrollEdgeAppearance = barLook; navigationItem.compactScrollEdgeAppearance = barLook
    // the chat's background (approved mock-up "E11 Talk — chat background", Haris 2026-11-12): our own soft line drawings
    // with the E11. wordmark in outline, faint, standing still behind the messages — the list's own background view
    let pattern = UIView(); pattern.backgroundColor = ChatVC.pattern; table.backgroundView = pattern
    view.addSubview(table)
    placeBars()
    data = UITableViewDiffableDataSource<String, ChatItem>(tableView: table) { [weak self] tv, ip, item in
      guard let self = self else { return UITableViewCell() }
      switch item {
      case .msg(let id):
        let c = tv.dequeueReusableCell(withIdentifier: "b", for: ip) as! BubbleCell
        c.contentView.isUserInteractionEnabled = !self.keyUp
        c.find = self.findSet.contains(id) ? (self.findQ, id == self.findCur) : nil
        if let m = self.msgs[id], let g = Talk.shared.groups[self.group] { c.set(m, group: g, log: Talk.shared.log(self.group), run: self.runs[id] ?? Run()) }
        c.onReplyTap = { [weak self] rid in self?.jump(to: rid) }
        c.onFileTap = { [weak self, weak c] m in self?.openFrom = (m.kind == "photo" || m.kind == "video") ? c?.photo : nil; self?.open(m) }
        c.onRetry = { [weak self] m in guard let self = self else { return }; Talk.shared.retry(self.group, m) }
        c.onForward = { [weak self] m in self?.forward(m) }
        return c
      }
    }
    data.defaultRowAnimation = .fade
    // the swipes on a message (WhatsApp's, the design's boards 26 / 27): right — reply; your own left — Message info
    swipe.delegate = self; swipe.maximumNumberOfTouches = 1
    table.addGestureRecognizer(swipe)
    table.panGestureRecognizer.require(toFail: swipe)
    // the keyboard rule (every page): while typing, a tap on the chat only puts the keyboard down — never opens a photo, a
    // link or plays a voice note under the finger; the chat still scrolls, and dragging down takes the keyboard with it
    keyTap.delegate = self; keyTap.cancelsTouchesInView = true
    table.addGestureRecognizer(keyTap)
    // the title (the design): the group's picture, its name, its people — at the left after ‹; a tap: group info
    titleL.font = .systemFont(ofSize: 17, weight: .bold); subL.font = .systemFont(ofSize: 13); subL.textColor = .secondaryLabel
    titleL.lineBreakMode = .byTruncatingTail; subL.lineBreakMode = .byTruncatingTail
    let words = UIStackView(arrangedSubviews: [titleL, subL]); words.axis = .vertical; words.alignment = .leading; words.spacing = 0
    titlePic.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([titlePic.widthAnchor.constraint(equalToConstant: 39), titlePic.heightAnchor.constraint(equalToConstant: 39)])
    titleV.axis = .horizontal; titleV.alignment = .center; titleV.spacing = 10
    titleV.addArrangedSubview(titlePic); titleV.addArrangedSubview(words)
    titleV.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(info)))
    titleV.widthAnchor.constraint(lessThanOrEqualToConstant: max(140, UIScreen.main.bounds.width - 150)).isActive = true
    // (the picture and the name are the page's own, on its top frost where the bar had them — so they slide with the chat
    //  and follow the finger on a back swipe, WhatsApp's way, instead of Apple's fade of a bar item; Haris 2026-11-12. An
    //  empty spot of the same size stays in Apple's bar for the tap, as the bar takes the touches there.)
    titleSpot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(info)))
    titleSpot.translatesAutoresizingMaskIntoConstraints = false
    spotW = titleSpot.widthAnchor.constraint(equalToConstant: 200)
    NSLayoutConstraint.activate([spotW, titleSpot.heightAnchor.constraint(equalToConstant: 39)])
    setBarButtons()
    bar.onSend = { [weak self] t, ms in self?.send(t, mentions: ms) }
    bar.onPlus = { [weak self] k in self?.attach(k) }
    bar.onCancelReply = { [weak self] in self?.editingMsg = nil; self?.replying = nil; self?.bar.setReply(nil, editing: false) }
    bar.onVoice = { [weak self] url, secs, wave in self?.sendVoice(url, secs: secs, wave: wave) }
    NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .talkGroup, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(head), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(gone(_:)), name: .talkGone, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(kbMoved(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    // (once the keyboard has settled, and back from another app: what it covers measured from where the bar really is —
    //  the notices around leaving the app left the latest message under the bar, unable to scroll out — Haris 2026-11-12)
    NotificationCenter.default.addObserver(self, selector: #selector(kbSettled), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(backInApp), name: UIApplication.didBecomeActiveNotification, object: nil)
    // ("Client can see this group" — the design: a thin orange band right under the bar, always there in a client group)
    let cl = UILabel(); cl.font = .systemFont(ofSize: 13, weight: .semibold); cl.textColor = Look.clientInk; cl.textAlignment = .center
    let eyeImg = UIImage(systemName: "eye", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))!.withRenderingMode(.alwaysTemplate)
    let eye = NSMutableAttributedString(attachment: NSTextAttachment(image: eyeImg))
    eye.append(NSAttributedString(string: "  Client can see this group"))
    eye.addAttribute(.foregroundColor, value: Look.clientInk, range: NSRange(location: 0, length: eye.length)); cl.attributedText = eye
    let tint = UIView(); tint.backgroundColor = Look.clientInk.withAlphaComponent(0.14); tint.isUserInteractionEnabled = false
    clientLine.isHidden = true
    let edge = UIView(); edge.backgroundColor = Look.clientInk.withAlphaComponent(0.22); edge.isUserInteractionEnabled = false
    edge.translatesAutoresizingMaskIntoConstraints = false; clientLine.contentView.addSubview(edge)
    NSLayoutConstraint.activate([edge.leadingAnchor.constraint(equalTo: clientLine.contentView.leadingAnchor), edge.trailingAnchor.constraint(equalTo: clientLine.contentView.trailingAnchor),
                                 edge.bottomAnchor.constraint(equalTo: clientLine.contentView.bottomAnchor), edge.heightAnchor.constraint(equalToConstant: 0.5)])
    [tint, cl].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; clientLine.contentView.addSubview($0) }
    topFrost.isUserInteractionEnabled = false; topFrost.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(topFrost)
    NSLayoutConstraint.activate([topFrost.topAnchor.constraint(equalTo: view.topAnchor), topFrost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                                 topFrost.trailingAnchor.constraint(equalTo: view.trailingAnchor), topFrost.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)])
    pinTitle()   // (the name on the frost)
    clientLine.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(clientLine)
    NSLayoutConstraint.activate([
      tint.leadingAnchor.constraint(equalTo: clientLine.contentView.leadingAnchor), tint.trailingAnchor.constraint(equalTo: clientLine.contentView.trailingAnchor),
      tint.topAnchor.constraint(equalTo: clientLine.contentView.topAnchor), tint.bottomAnchor.constraint(equalTo: clientLine.contentView.bottomAnchor),
      cl.centerXAnchor.constraint(equalTo: clientLine.contentView.centerXAnchor), cl.centerYAnchor.constraint(equalTo: clientLine.contentView.centerYAnchor),
      clientLine.leadingAnchor.constraint(equalTo: view.leadingAnchor), clientLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      clientLine.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), clientLine.heightAnchor.constraint(equalToConstant: 30)])
    // the scroll-down button (the design: 31 round, at the right above the message bar) — shown once you've scrolled up
    var dc = UIButton.Configuration.plain()
    dc.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)); dc.baseForegroundColor = .label
    downB.configuration = dc
    downB.backgroundColor = Look.downBtn; downB.layer.cornerRadius = 15.5
    downB.layer.shadowColor = UIColor.black.cgColor; downB.layer.shadowOpacity = 0.3; downB.layer.shadowRadius = 6; downB.layer.shadowOffset = CGSize(width: 0, height: 3)
    downB.accessibilityLabel = "Scroll to the latest"
    downB.alpha = 0; downB.translatesAutoresizingMaskIntoConstraints = false
    downB.addAction(UIAction { [weak self] _ in self?.toBottom(true) }, for: .touchUpInside)
    view.addSubview(downB)
    downBottom = downB.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100)
    NSLayoutConstraint.activate([downB.widthAnchor.constraint(equalToConstant: 31), downB.heightAnchor.constraint(equalToConstant: 31),
                                 downB.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -9), downBottom])
    head()
    reload(animated: false)
    lastSeenId = Talk.shared.log(group).msgs.last?.id
  }
  override func viewDidAppear(_ a: Bool) {
    super.viewDidAppear(a)
    // (the back swipe from the edge goes first; a reply swipe starts away from the edge)
    if let pop = navigationController?.interactivePopGestureRecognizer, !swipeWaits { swipeWaits = true; swipe.require(toFail: pop) }
    homeLimits.forEach { $0.constant = -home }
    bar.onLayout = { [weak self] in self?.fitBottom() }
    fitBottom()
    Talk.shared.markRead(group)
    ChatVC.open = group
  }
  override func viewWillDisappear(_ a: Bool) {
    super.viewWillDisappear(a); endFind(leaving: true); if ChatVC.open == group { ChatVC.open = nil }
    // (going back, Apple puts the tab bar back at the first touch of the swipe — its icons fade in with the slide instead,
    //  following the finger, Haris 2026-11-12)
    if isMovingFromParent, let bar = tabBarController?.tabBar, let tc = transitionCoordinator {
      bar.alpha = 0
      tc.animate(alongsideTransition: { _ in bar.alpha = 1 }, completion: { _ in bar.alpha = 1 })
    }
  }
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    if isMovingToParent { coverTitle() }
  }
  /* The list's big title folding into its bar as the chat comes in (Apple's, with the tab bar hidden as it's pushed —
     kept, Haris 2026-11-12): WhatsApp's way of not seeing it — for the slide, the chat's frost reaches down over the big
     title's room, under the chat's own bar row, and shrinks to the chat's bar as the slide goes (and grows back 
     way out nothing: the title doesn't move then). Only for the slide, then gone. */
  private func coverTitle() {
    guard let n = navigationController, let tc = transitionCoordinator else { return }
    let rowBottom = (n.view.window?.safeAreaInsets.top ?? n.view.safeAreaInsets.top) + ChatVC.rowMid * 2
    let full = n.navigationBar.frame.maxY, W = n.view.bounds.width
    // (WhatsApp's: the chat's picture and name are there at once, in their place, as the chat opens — held still above the
    //  slide and given back to the page as it arrives, in the same spot; going back they slide away with the page)
    titleV.removeFromSuperview(); titleV.translatesAutoresizingMaskIntoConstraints = false
    n.view.insertSubview(titleV, belowSubview: n.navigationBar)
    NSLayoutConstraint.activate([titleV.leadingAnchor.constraint(equalTo: n.view.leadingAnchor, constant: ChatVC.titleLead),
                                 titleV.centerYAnchor.constraint(equalTo: n.view.topAnchor, constant: rowBottom - ChatVC.titleMid)])
    guard full - rowBottom > 1 else { tc.animate(alongsideTransition: nil) { [weak self] _ in self?.pinTitle() }; return }
    // (WhatsApp's, frame by frame: at the first moment one frost from the very top down past the list's search bar, thick
    //  enough that the big title and the search don't show through; then it settles to the chat's bar. Two pieces of the
    //  one frost: the top behind Apple's bar (the chat's name and buttons on it), the rest over the folding title.)
    // (the same frost as the chat's own top — ChatVC.frost — so the hand-off at the end can't be seen; it only shrinks)
    let piece = { (y: CGFloat, h: CGFloat) -> UIVisualEffectView in
      let v = ChatVC.frost(); v.frame = CGRect(x: 0, y: y, width: W, height: h); return v
    }
    // (the list's search bar goes the moment the cover comes, so it can't show again as the cover settles; back as it
    //  always is once the chat has arrived — the way back is Apple's, as usual)
    let fromItem = tc.viewController(forKey: .from)?.navigationItem
    let searchBar = fromItem?.searchController?.searchBar
    searchBar?.alpha = 0
    // (and the list's small title: as its big title folds, Apple shows the small one ("E11") in the bar's middle and slides
    //  it away — right over the chat's name; an empty title view in its place for the slide, Haris 2026-11-12)
    let hadTitleView = fromItem?.titleView
    if hadTitleView == nil { fromItem?.titleView = UIView() }
    // (the shrinking piece is the frost's colour without a blur — a blur whose size changes frame by frame flickered a dark
    //  line at its edge on the phone's screen, Haris 2026-11-12; the still piece above keeps the frost)
    let upper = piece(0, rowBottom), lower = UIView(frame: CGRect(x: 0, y: rowBottom, width: W, height: full - rowBottom))
    lower.isUserInteractionEnabled = false
    lower.backgroundColor = UIColor { Look.chatBg.resolvedColor(with: $0) }
    // (and the list's bar line under its bar for the slide — it showed at the bar's foot as the title folded)
    let looks = [fromItem?.standardAppearance, fromItem?.scrollEdgeAppearance, fromItem?.compactAppearance]
    for (i, a) in looks.enumerated() {
      let b = (a ?? n.navigationBar.standardAppearance).copy(); b.shadowColor = .clear
      if i == 0 { fromItem?.standardAppearance = b } else if i == 1 { fromItem?.scrollEdgeAppearance = b } else { fromItem?.compactAppearance = b }
    }
    n.view.insertSubview(upper, belowSubview: titleV); n.view.insertSubview(lower, aboveSubview: n.navigationBar)
    tc.animate(alongsideTransition: { _ in lower.frame.size.height = 0 },
               completion: { [weak self] _ in upper.removeFromSuperview(); lower.removeFromSuperview(); searchBar?.alpha = 1; if hadTitleView == nil { fromItem?.titleView = nil }
                 fromItem?.standardAppearance = looks[0]; fromItem?.scrollEdgeAppearance = looks[1]; fromItem?.compactAppearance = looks[2]
                 self?.pinTitle() })
  }
  static var open: String?
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    fitBottom()
    if !scrolledOnce, data.snapshot().numberOfItems > 0 {
      scrolledOnce = true; toBottom(false)
      if let f = focus { focus = nil; DispatchQueue.main.async { self.jump(to: f) } }
    }
  }
  private var scrolledOnce = false
  private var lastSeenId: String?
  // the scroll-down button: shown once the end of the chat is out of view
  // ---------- sections of a long chat ----------
  // (each row's height kept once it's been seen, so lining up and scrolling back over it never guesses again — no jumps)
  private var rowH: [String: CGFloat] = [:]
  func tableView(_ tv: UITableView, willDisplay cell: UITableViewCell, forRowAt ip: IndexPath) {
    if case .msg(let id)? = data.itemIdentifier(for: ip) { rowH[id] = cell.bounds.height }
  }
  func tableView(_ tv: UITableView, estimatedHeightForRowAt ip: IndexPath) -> CGFloat {
    if case .msg(let id)? = data.itemIdentifier(for: ip), let h = rowH[id] { return h }
    return 60
  }
  static let page = 100
  private var shownFrom: String?, hasOlder = false, addingOlder = false
  // the next 100 older ones above — the place on screen kept where it is
  private func older() {
    guard hasOlder, !addingOlder else { return }
    let all = Talk.shared.log(group).msgs
    guard let from = shownFrom, let i = all.firstIndex(where: { $0.id == from }), i > 0 else { return }
    addingOlder = true
    let h = table.contentSize.height, y = table.contentOffset.y
    shownFrom = all[max(0, i - ChatVC.page)].id
    UIView.performWithoutAnimation {
      reload(animated: false)
      table.layoutIfNeeded()
      table.contentOffset.y = y + (table.contentSize.height - h)
    }
    addingOlder = false
  }
  // an older message asked for (a quote, a search): lined up down from a little above it first
  private func reach(_ id: String) {
    guard data.indexPath(for: .msg(id)) == nil else { return }
    let all = Talk.shared.log(group).msgs
    guard let i = all.firstIndex(where: { $0.id == id }) else { return }
    shownFrom = all[max(0, i - 20)].id
    reload(animated: false); table.layoutIfNeeded()
  }
  func scrollViewDidScroll(_ s: UIScrollView) {
    if hasOlder && s.contentOffset.y < -s.adjustedContentInset.top + 700 && (s.isDragging || s.isDecelerating) { older() }
    let away = s.contentOffset.y + s.bounds.height < s.contentSize.height - 160
    if (downB.alpha > 0) != away { UIView.animate(withDuration: 0.2) { self.downB.alpha = away ? 1 : 0 } }
    chipsAwake()
  }
  /* The day chip stuck under the bar (WhatsApp's way, Haris 2026-11-12): there while the chat moves, it fades away a
     moment after the chat stops, and comes back as soon as it moves again. Only the stuck one — a chip in its own place
     between the messages always stays. (Apple's list keeps the chip stuck; the fade is Apple's view animation.) */
  private var chipNap: DispatchWorkItem?
  private func chipsAwake() {
    for s in 0..<table.numberOfSections { (table.headerView(forSection: s) as? DayHeader)?.showChip(true) }
    chipNap?.cancel()
    let w = DispatchWorkItem { [weak self] in self?.chipsNap() }
    chipNap = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
  }
  private func chipsNap() {
    guard !table.isTracking, !table.isDecelerating else { chipsAwake(); return }
    let top = table.contentOffset.y + table.adjustedContentInset.top
    for s in 0..<table.numberOfSections {
      // (stuck: the chip's own place has gone above the bar)
      guard let h = table.headerView(forSection: s) as? DayHeader, table.rect(forSection: s).minY < top - 1, table.rect(forSection: s).maxY > top + 38 else { continue }
      h.showChip(false)
    }
  }

  @objc private func head() {
    guard let g = Talk.shared.groups[group] else { return }
    let T = Talk.shared
    titleL.text = g.name
    titlePic.set(group: g)
    // (the people: a client first, as "Rania (Oasis Coffee)"; the team by full name; You last — cut short by the bar)
    let others = g.members.filter { $0 != T.me?.id }.compactMap { T.people[$0] }
    let clients = others.filter { $0.contact }.map { p in p.client.flatMap { T.clients[$0]?.name }.map { "\(p.name) (\($0))" } ?? p.name }
    let team = others.filter { !$0.contact }.map { $0.name }
    subL.text = (clients + team + ["You"]).joined(separator: ", ")
    spotW?.constant = min(titleV.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width, max(140, UIScreen.main.bounds.width - 150))
    // a client group, to staff: the band under the bar and the box's hint — the client can see what's written here
    let shared = g.withClient && !T.isContact
    bar.placeholder = shared ? "Message — client can see this" : ""
    if clientLine.isHidden == shared { clientLine.isHidden = !shared; fitBottom() }
    // (@: the group's people)
    bar.people = g.members.filter { $0 != T.me?.id }.compactMap { id in T.people[id].map { (id, $0.name) } }
  }
  // ---------- search inside the chat (the design's board "Search in a chat"): the field and its own ✕ in Apple's bar;
  // above the keyboard ˄ ˅ in a glass capsule and "2 of 3 matches"; every match marked in the messages, the one shown
  // brighter. Earlier = up, later = down; it starts on the newest. ----------
  private let findBar = UISearchBar()
  // (the field level with the round ✕ beside it: the search bar 44 high, centred in the bar's middle — on its own as the
  //  title it sat about 8 lower than the ✕, Haris 2026-11-12)
  private lazy var findBox: UIView = {
    final class Box: UIView { override var intrinsicContentSize: CGSize { CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44) } }
    let b = Box()
    b.addSubview(findBar); findBar.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([findBar.leadingAnchor.constraint(equalTo: b.leadingAnchor), findBar.trailingAnchor.constraint(equalTo: b.trailingAnchor),
                                 findBar.centerYAnchor.constraint(equalTo: b.centerYAnchor), findBar.heightAnchor.constraint(equalToConstant: 44)])
    return b
  }()
  private lazy var findAcc: FindBar = {
    let f = FindBar()
    f.up.addAction(UIAction { [weak self] _ in self?.step(-1) }, for: .touchUpInside)
    f.down.addAction(UIAction { [weak self] _ in self?.step(1) }, for: .touchUpInside)
    return f
  }()
  private var finding = false
  private var finds: [String] = [], findAt = 0, findQ = "", findCur: String?
  private var findSet = Set<String>()
  private func setBarButtons() {
    let find = UIBarButtonItem(title: nil, image: UIImage(systemName: "magnifyingglass"), primaryAction: UIAction { [weak self] _ in self?.startFind() }, menu: nil)
    navigationItem.rightBarButtonItems = [find]
    let t = UIBarButtonItem(customView: titleSpot)
    titleV.isHidden = false
    if #available(iOS 26.0, *) { t.hidesSharedBackground = true }
    navigationItem.leftItemsSupplementBackButton = true
    navigationItem.leftBarButtonItems = [t]
    navigationItem.titleView = nil
    navigationItem.hidesBackButton = false
  }
  private func startFind() {
    guard !finding else { return }
    findBar.placeholder = "Search in this chat"; findBar.delegate = self; findBar.text = ""
    bar.box.resignFirstResponder(); bar.isHidden = true; findAcc.isHidden = false
    finding = true; finds = []; findQ = ""; findCur = nil; findSet = []
    findAcc.show(0, 0, typed: false)
    navigationItem.leftBarButtonItems = nil; titleV.isHidden = true
    navigationItem.hidesBackButton = true
    navigationItem.titleView = findBox
    let close = UIBarButtonItem(title: nil, image: UIImage(systemName: "xmark"), primaryAction: UIAction { [weak self] _ in self?.endFind() }, menu: nil)
    close.accessibilityLabel = "Close the search"
    navigationItem.rightBarButtonItems = [close]
    findBar.searchTextField.becomeFirstResponder()
  }
  private func endFind(leaving: Bool = false) {
    guard finding else { return }
    finding = false
    findAcc.isHidden = true; bar.isHidden = false
    findBar.searchTextField.resignFirstResponder()
    let was = findSet
    finds = []; findSet = []; findQ = ""; findCur = nil
    remark(was)
    setBarButtons()
    if !leaving { fitBottom() }
  }
  private func runFind() {
    let q = (findBar.text ?? "").trimmingCharacters(in: .whitespaces)
    let was = findSet
    // (oldest first, as they stand in the chat — starting on the newest)
    finds = Talk.shared.search(q, in: group).map { $0.1.id }.reversed()
    findQ = q; findSet = Set(finds)
    findAt = max(0, finds.count - 1); findCur = finds.last
    remark(was.union(findSet))
    findAcc.show(finds.isEmpty ? 0 : findAt + 1, finds.count, typed: q.count >= 2)
    if let f = findCur { bring(f) }
  }
  private func step(_ d: Int) {
    guard !finds.isEmpty else { return }
    let to = min(max(findAt + d, 0), finds.count - 1)
    guard to != findAt else { return }
    let was = findCur
    findAt = to; findCur = finds[to]
    remark(Set([was, findCur].compactMap { $0 }))
    findAcc.show(findAt + 1, finds.count, typed: true)
    UISelectionFeedbackGenerator().selectionChanged()
    bring(finds[to])
  }
  // (only the messages whose marks changed are set again — the same rows, the same heights)
  private func remark(_ ids: Set<String>) {
    var snap = data.snapshot()
    let items = ids.map { ChatItem.msg($0) }.filter { snap.indexOfItem($0) != nil }
    guard !items.isEmpty else { return }
    snap.reconfigureItems(items)
    data.apply(snap, animatingDifferences: false)
  }
  private func bring(_ id: String) {
    reach(id)
    guard let ip = data.indexPath(for: .msg(id)) else { return }
    table.scrollToRow(at: ip, at: .middle, animated: true)
    // (the match found: its bubble pulses once it's in view — Haris 2026-11-12)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self = self, self.findCur == id, let ip = self.data.indexPath(for: .msg(id)) else { return }
      (self.table.cellForRow(at: ip) as? BubbleCell)?.pulse()
    }
  }
  @objc private func info() { navigationController?.pushViewController(GroupInfoVC(group: group), animated: true) }
  @objc private func gone(_ n: Notification) {
    guard (n.object as? String) == group else { return }
    toast("This group was deleted")
    navigationController?.popToRootViewController(animated: true)
  }
  @objc private func changed(_ n: Notification) {
    guard (n.object as? String) == group else { return }
    let near = table.contentOffset.y + table.bounds.height >= table.contentSize.height - 120
    reload(animated: true)
    // (someone else's new message while the chat is open: E11 Console's soft arrive sound)
    if let last = Talk.shared.log(group).msgs.last, last.id != lastSeenId, last.by != Talk.shared.me?.id, last.kind != "sys", lastSeenId != nil, view.window != nil { ChatSound.arrive() }
    // (one of yours just sent: always to the end — Haris 2026-11-12: it stopped short, the new row measured only after)
    let mineNew = Talk.shared.log(group).msgs.last.map { $0.id != lastSeenId && $0.by == Talk.shared.me?.id } ?? false
    lastSeenId = Talk.shared.log(group).msgs.last?.id
    if near || mineNew {
      toBottom(true)
      // (once the new row has its real height, the rest of the way if it fell short)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
        guard let self = self, !self.table.isTracking else { return }
        let end = self.table.contentSize.height + self.table.adjustedContentInset.bottom - self.table.bounds.height
        if end - self.table.contentOffset.y > 2 { self.toBottom(true) }
      }
    }
    if view.window != nil, UIApplication.shared.applicationState == .active { Talk.shared.markRead(group) }
  }
  // each message kept by its id; only one that shows something new is drawn again
  private func reload(animated: Bool) {
    let l = Talk.shared.log(group)
    var snap = NSDiffableDataSourceSnapshot<String, ChatItem>()
    var lastDay = "", newSigs: [String: Int] = [:], items: [ChatItem] = [], section = "", newDayOf: [String: String] = [:]
    msgs = [:]
    // (a run: one person's messages one after another on the same day — the name on its first, the tail on its last)
    var newRuns: [String: Run] = [:]
    let all = l.msgs
    // (how far everyone else has read: your message is read once it's at or before that — only its ✓✓ hangs on it)
    let meId = Talk.shared.me?.id, others = (Talk.shared.groups[group]?.members ?? []).filter { $0 != meId }
    let pos = Dictionary(all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    let readTo = others.isEmpty ? -1 : others.map { l.readBy[$0].flatMap { pos[$0] } ?? -1 }.min() ?? -1
    // (and how far everyone else's phone has them — ✓✓)
    let gotTo = others.isEmpty ? -1 : others.map { p in max(l.readBy[p].flatMap { pos[$0] } ?? -1, (l.gotAt?[p] ?? []).compactMap { pos[$0.upto] }.max() ?? -1) }.min() ?? -1
    // (a long chat in sections, WhatsApp's way — Haris 2026-11-12: the newest 100 lined up at first, 100 more above as
    //  you near the top; from the first one lined up, everything newer)
    let start = shownFrom.flatMap { pos[$0] } ?? max(0, all.count - ChatVC.page)
    shownFrom = all.indices.contains(start) ? all[start].id : nil
    hasOlder = start > 0
    for i in start..<all.count {
      let m = all[i]
      let d = Look.day(m.at)
      let prev = i > 0 ? all[i - 1] : nil, next = i + 1 < all.count ? all[i + 1] : nil
      let same = { (o: Msg?) -> Bool in guard let o = o else { return false }; return o.by == m.by && o.kind != "sys" && m.kind != "sys" && Look.day(o.at) == d }
      newRuns[m.id] = Run(first: !same(prev), last: !same(next))
      if d != lastDay {
        lastDay = d
        section = newDayOf[d] == nil ? d : d + "#\(i)"   // (the same words twice — a section each)
        newDayOf[section] = d; snap.appendSections([section])
      }
      msgs[m.id] = m
      var h = Hasher(); h.combine(m.text); h.combine(m.edited); h.combine(m.deleted); h.combine(m.pending); h.combine(m.failed); h.combine(m.reactions); h.combine(m.file?.id); h.combine(m.link)
      h.combine(newRuns[m.id]); h.combine(Talk.shared.people[m.by]?.color); h.combine(Talk.shared.people[m.by]?.role)
      if m.by == meId { h.combine(i <= readTo); h.combine(i <= gotTo) }
      newSigs[m.id] = h.finalize()
      items.append(.msg(m.id)); snap.appendItems([.msg(m.id)], toSection: section)
    }
    runs = newRuns; dayOf = newDayOf
    let old = data.snapshot()
    snap.reconfigureItems(items.filter { if case .msg(let id) = $0 { return old.indexOfItem($0) != nil && sigs[id] != newSigs[id] }; return false })
    sigs = newSigs
    data.apply(snap, animatingDifferences: animated && old.numberOfItems > 0)
  }
  private func toBottom(_ animated: Bool) {
    let s = data.snapshot()
    guard let last = s.sectionIdentifiers.last, s.numberOfItems(inSection: last) > 0 else { return }
    if !animated { table.scrollToRow(at: IndexPath(row: s.numberOfItems(inSection: last) - 1, section: s.numberOfSections - 1), at: .bottom, animated: false) }
    let end = { () -> CGPoint in self.table.layoutIfNeeded(); return CGPoint(x: 0, y: max(-self.table.adjustedContentInset.top, self.table.contentSize.height + self.table.adjustedContentInset.bottom - self.table.bounds.height)) }
    guard !animated else { table.setContentOffset(end(), animated: true); return }
    // (the rows near the end take their real heights once they're in view — placed again until the end stays put, so
    //  the chat doesn't open a little short and then jump to its end)
    for _ in 0..<4 { let e = end(); if abs(table.contentOffset.y - e.y) < 0.5 { break }; table.contentOffset = e }
  }
  /* The room under the last message = how much the message bar (with the keyboard under it, or the reply / @ list above
     it) covers, measured from where the bar really is — the keyboard's notice alone missed the bar's first showing (the
     chat scrolled to its end before the bar came) and its height changes, so the latest messages sat behind it and
     couldn't be scrolled out. Called on every keyboard move and whenever the bar is laid out. */
  // how much of the page the keyboard covers (with the message bar on it); 0 while it's down
  private var kbOverlap: CGFloat = 0
  @objc private func kbSettled() {
    let acc: UIView = finding ? findAcc : bar
    guard isViewLoaded, view.window != nil, acc.window != nil else { return }
    kbOverlap = view.keyboardLayoutGuide.layoutFrame.height
    keyUp = kbOverlap > home + 20   // (the keyboard guide counts the home line when the keyboard is down)
    fitBottom()
  }
  @objc private func backInApp() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.kbSettled() } }
  @objc private func kbMoved(_ n: Notification) {
    if let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
      kbOverlap = max(0, view.bounds.maxY - view.convert(f, from: nil).minY)
      keyUp = kbOverlap > home + 20   // (the keyboard guide counts the home line when the keyboard is down)
    }
    view.layoutIfNeeded(); fitBottom()
  }
  override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); fitBottom() }
  private func fitBottom() {
    guard isViewLoaded else { return }
    // the top: under Apple's bar (and the client band); the bottom: the message bar, or the keyboard with it on top —
    // the bar's own height counts even before the keyboard says anything (it sits at the very bottom, home line included)
    let top = view.safeAreaInsets.top + (clientLine.isHidden ? 0 : 30)
    if table.contentInset.top != top { table.contentInset.top = top; table.verticalScrollIndicatorInsets.top = top }
    // (the message bar's real height from the start — before it's on the screen it has no home-line room yet, and the
    //  chat opened that much short and then jumped when the bar came — Haris 2026-11-12)
    let acc: UIView = finding ? findAcc : bar
    let accTop = acc.frame.height > 0 ? acc.frame.minY : view.bounds.maxY - home - acc.intrinsicContentSize.height
    // (the @ list comes over the chat, as a menu would — it isn't counted, so the messages don't move for it — Haris 2026-11-12)
    let cover = view.bounds.maxY - accTop - (finding ? 0 : bar.listH)
    guard abs(cover - kb) > 0.5 else { return }
    let wasAtEnd = table.contentOffset.y + table.bounds.height >= table.contentSize.height + table.adjustedContentInset.bottom - 40
    let grew = cover > kb
    kb = cover
    table.contentInset.bottom = cover + 8
    table.verticalScrollIndicatorInsets.bottom = cover
    downBottom.constant = -(cover + 25)
    if grew && (wasAtEnd || !scrolledAway) { toBottom(false) }
  }
  // (you scrolled up to read: the keyboard or the bar growing doesn't pull you back down)
  private var scrolledAway: Bool { table.contentOffset.y + table.bounds.height < table.contentSize.height - 160 }
  private func jump(to id: String) {
    reach(id)
    guard let ip = data.indexPath(for: .msg(id)) else { toast("That message isn’t on this phone any more"); return }
    table.scrollToRow(at: ip, at: .middle, animated: true)
    // (a quote tapped, or opened from a search: the message pulses once in view, as the chat's search does — Haris 2026-11-12)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      guard let self = self, let ip = self.data.indexPath(for: .msg(id)) else { return }
      (self.table.cellForRow(at: ip) as? BubbleCell)?.pulse()
    }
  }

  // ---------- sending ----------
  private func send(_ text: String, mentions: [String] = []) {
    if let e = editingMsg {
      editingMsg = nil; bar.setReply(nil, editing: false)
      Net.shared.act(["act": "edit", "msg": e.id, "text": text]) { j in if (j?["ok"] as? Bool) == true { Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t edit it") } }
      return
    }
    Talk.shared.send(group, text: text, reply: replying, mentions: mentions)
    replying = nil
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    toBottom(true)
  }
  private func attach(_ kind: String) {
    switch kind {
    case "photos":
      var c = PHPickerConfiguration(); c.selectionLimit = 10; c.filter = .any(of: [.images, .videos])
      let p = PHPickerViewController(configuration: c); p.delegate = self; present(p, animated: true)
    case "camera":
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else { toast("No camera here"); return }
      let p = UIImagePickerController(); p.sourceType = .camera; p.mediaTypes = ["public.image", "public.movie"]; p.delegate = self; present(p, animated: true)
    default:
      let p = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true); p.allowsMultipleSelection = true; p.delegate = self; present(p, animated: true)
    }
  }
  // a voice message: sent as it was recorded, with its length and waveform
  private func sendVoice(_ url: URL, secs: Double, wave: String) {
    guard let d = try? Data(contentsOf: url) else { return }
    let tmpId = "local-" + UUID().uuidString
    Talk.shared.send(group, text: "", reply: replying, file: Msg.FileRef(id: tmpId, name: "Voice message.m4a", size: d.count, kind: "voice", w: nil, h: nil, secs: secs, wave: wave), localFile: url, upload: d)
    replying = nil
    toBottom(true)
  }
  // a video from the camera or Photos: shrunk to 720p first (Haris 2026-11-05); one from Files goes as it is
  fileprivate func sendVideo(_ url: URL, name: String) {
    let asset = AVURLAsset(url: url)
    guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { sendFile(url, kind: "file", name: name); return }
    let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    ex.outputURL = out; ex.outputFileType = .mp4; ex.shouldOptimizeForNetworkUse = true
    toast("Getting the video ready…")
    ex.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let ok = ex.status == .completed
        let src = ok ? out : url
        let a2 = AVURLAsset(url: src)
        var w: Double? = nil, h: Double? = nil
        if let t = a2.tracks(withMediaType: .video).first { let sz = t.naturalSize.applying(t.preferredTransform); w = Double(abs(sz.width)); h = Double(abs(sz.height)) }
        let secs = CMTimeGetSeconds(a2.duration)
        guard let d = try? Data(contentsOf: src) else { toast("Couldn’t read that video"); return }
        let tmpId = "local-" + UUID().uuidString
        let fname = (name as NSString).deletingPathExtension + ".mp4"
        Talk.shared.send(self.group, text: "", reply: self.replying, file: Msg.FileRef(id: tmpId, name: fname, size: d.count, kind: "video", w: w, h: h, secs: secs.isFinite ? secs : nil), localFile: src, upload: d)
        self.replying = nil
        self.toBottom(true)
      }
    }
  }
  fileprivate func sendFile(_ url: URL, kind: String, name: String) {
    if kind == "video" { sendVideo(url, name: name); return }
    guard let d = try? Data(contentsOf: url) else { toast("Couldn’t read that file"); return }
    var w: Double? = nil, h: Double? = nil, data = d
    var kind = kind
    if kind == "photo", let img = UIImage(data: d) {
      // (a photo shrunk to 2048 across, as WhatsApp sends one)
      let s = min(1, 2048 / max(img.size.width, img.size.height))
      let sized = s < 1 ? UIGraphicsImageRenderer(size: CGSize(width: img.size.width * s, height: img.size.height * s)).image { _ in img.draw(in: CGRect(origin: .zero, size: CGSize(width: img.size.width * s, height: img.size.height * s))) } : img
      data = sized.jpegData(compressionQuality: 0.8) ?? d
      w = Double(sized.size.width); h = Double(sized.size.height)
    } else if kind == "photo" { kind = "file" }
    let tmpId = "local-" + UUID().uuidString
    let local = FileManager.default.temporaryDirectory.appendingPathComponent(tmpId)
    try? data.write(to: local)
    let fname = kind == "photo" ? (name as NSString).deletingPathExtension + ".jpg" : name
    Talk.shared.send(group, text: "", reply: replying, file: Msg.FileRef(id: tmpId, name: fname, size: data.count, kind: kind, w: w, h: h, secs: nil), localFile: local, upload: data)
    replying = nil
    toBottom(true)
  }

  // ---------- reading ----------
  private func open(_ m: Msg) {
    guard let f = m.file else { return }
    Net.shared.file(f.id) { [weak self] url in
      guard let self = self, let url = url else { toast("That file isn’t on the server any more"); return }
      // (QuickLook wants the name's extension)
      let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
      try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
      self.previewURL = named
      let q = QLPreviewController(); q.dataSource = self; q.delegate = self
      self.present(q, animated: true)
    }
  }
  // a photo or video opens out of its bubble and, swiped down, shrinks back into it — Apple's own zoom (Quick Look's)
  private weak var openFrom: UIView?
  func previewController(_ c: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? { openFrom }
  func numberOfPreviewItems(in c: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
  func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { previewURL! as NSURL }

  // ---------- the day's chip: the section's header ----------
  func tableView(_ tv: UITableView, viewForHeaderInSection i: Int) -> UIView? {
    guard let id = data.snapshot().sectionIdentifiers[safe: i], let h = tv.dequeueReusableHeaderFooterView(withIdentifier: "d") as? DayHeader else { return nil }
    h.set(dayOf[id] ?? id); h.showChip(true, animated: false); return h
  }
  func tableView(_ tv: UITableView, heightForHeaderInSection i: Int) -> CGFloat { 38 }

  // ---------- the swipes: right — reply; your own left — Message info ----------
  // (Apple has no part for a bubble that follows the finger and springs back, so it's a pan of ours; the reply's keyboard
  // and the info page's push are Apple's own)
  private lazy var swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
  private weak var swipeCell: BubbleCell?
  private var swipeMsg: Msg?, swipeArmed = false, swipeDx: CGFloat = 0
  private func canReply(_ m: Msg) -> Bool { m.kind != "sys" && !m.deleted && !m.pending }
  private func canInfo(_ m: Msg) -> Bool { m.kind != "sys" && !m.deleted && !m.pending && m.by == Talk.shared.me?.id }
  private lazy var keyTap = UITapGestureRecognizer(target: self, action: #selector(keyDown))
  // (searching: a tap on the chat puts the keyboard down and closes the search too — Haris 2026-11-12)
  @objc private func keyDown() { if findBar.searchTextField.isFirstResponder { endFind() } else { bar.box.resignFirstResponder() } }
  // (while the keyboard is up, what's in the messages doesn't take touches — the tap above has them; scrolling and the
  // swipes are the list's own and go on)
  private var keyUp = false { didSet { if keyUp != oldValue { table.visibleCells.forEach { $0.contentView.isUserInteractionEnabled = !keyUp } } } }
  private var swipeWaits = false
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    if g === keyTap { return bar.box.isFirstResponder || findBar.searchTextField.isFirstResponder }
    guard g === swipe else { return true }
    guard swipe.location(in: view).x > 28 else { return false }   // (the screen's edge: going back)
    let v = swipe.velocity(in: table)
    guard abs(v.x) > abs(v.y) * 1.3, bar.recording == false,
          let ip = table.indexPathForRow(at: swipe.location(in: table)), case .msg(let id)? = data.itemIdentifier(for: ip), let m = msgs[id],
          let c = table.cellForRow(at: ip) as? BubbleCell,
          // (only from the bubble itself — elsewhere on the page the finger is the page's: Apple's back swipe)
          c.bubble.bounds.insetBy(dx: -6, dy: -4).contains(swipe.location(in: c.bubble)) else { return false }
    return v.x > 0 ? canReply(m) : canInfo(m)
  }
  /* Your own message swiped left (the design, board 27 — WhatsApp's): the bubble travels a little (64) as the chat dims,
     then the finger hooks Message info itself — the page comes in with the finger and goes where the finger leaves it
     (far enough or flicked: it arrives; else it slides back, the bubble and the chat as they were). Apple has no push
     a finger can drive, so this one slide is ours (SlideIn), the way Apple's own push looks. */
  private(set) var hook: UIPercentDrivenInteractiveTransition?
  private let hookDelegate = HookSlide()
  @objc private func swiped(_ g: UIPanGestureRecognizer) {
    let raw = g.translation(in: table).x, W = max(1, view.bounds.width)
    switch g.state {
    case .began:
      guard let ip = table.indexPathForRow(at: g.location(in: table)), let c = table.cellForRow(at: ip) as? BubbleCell,
            case .msg(let id)? = data.itemIdentifier(for: ip), let m = msgs[id] else { return }
      swipeCell = c; swipeMsg = m; swipeArmed = false; swipeDx = 0
    case .changed:
      guard let c = swipeCell, let m = swipeMsg else { return }
      if raw > 0 || hook == nil && !canInfo(m) {
        // reply: the bubble with the finger as far as 64, and there it stops (as Message info's)
        let dx = raw > 0 && canReply(m) ? min(raw, 64) : 0
        swipeDx = dx; c.slide(dx); dimOthers(0, but: c)
        let armed = dx >= 60
        if armed != swipeArmed { swipeArmed = armed; if armed { UIImpactFeedbackGenerator(style: .light).impactOccurred(); c.pop() } }
        return
      }
      // Message info: the bubble to 64 at most, then the page follows the finger
      let dx = max(raw, -64)
      swipeDx = dx; c.slide(dx); dimOthers(min(1, -dx / 64), but: c)
      let beyond = -raw - 64
      if beyond > 0 {
        if hook == nil { startHook(m, c) }
        hook?.update(min(0.99, beyond / W))
      } else { hook?.update(0) }
    case .ended, .cancelled, .failed:
      guard let c = swipeCell, let m = swipeMsg else { return }
      swipeCell = nil; swipeMsg = nil
      if let h = hook {
        swipeArmed = false
        let v = g.velocity(in: table).x, p = max(0, min(1, (-raw - 64) / W))
        let go = g.state == .ended && (v < -300 || (p > 0.25 && v < 300))
        // (the rest of the way as quickly as the finger was going — never a slow crawl to the end)
        let left = Double(go ? 1 - p : p), dur = 0.35 * left
        let want = max(0.12, min(0.3, abs(v) > 50 ? left * Double(W) / Double(abs(v)) : 0.25))
        h.completionSpeed = CGFloat(max(1, dur / want))
        if go { h.finish() } else { h.cancel() }
        return
      }
      let go = swipeArmed && g.state == .ended && swipeDx > 0
      swipeArmed = false
      c.settle(animated: true)
      UIView.animate(withDuration: 0.3) { self.dimOthers(0, but: c) }
      if go { startReply(m) }
    default: break
    }
  }
  private func startHook(_ m: Msg, _ c: BubbleCell) {
    guard let n = navigationController else { return }
    let h = UIPercentDrivenInteractiveTransition(); h.completionCurve = .easeOut; h.wantsInteractiveStart = true
    hook = h
    // (the navigation's delegate only for this one slide — with one there all the time, Apple's back swipe stopped)
    n.delegate = hookDelegate
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    n.pushViewController(MessageInfoVC(group: group, id: m.id), animated: true)
    n.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] ctx in
      guard let self = self else { return }
      self.hook = nil; n.delegate = nil
      if ctx.isCancelled {
        UIView.animate(withDuration: 0.3) { self.dimOthers(0, but: c) }
        c.settle(animated: true)
      } else { c.settle(animated: false); self.dimOthers(0, but: c) }
    }
  }
  private func dimOthers(_ p: CGFloat, but c: UITableViewCell) {
    for v in table.visibleCells where v !== c { v.contentView.alpha = 1 - 0.68 * p }
  }
  // Forward (the button beside a photo, video, file or link, or hold › Forward): the sheet of groups to send it to
  private func forward(_ m: Msg) {
    bar.box.resignFirstResponder()
    let n = UINavigationController(rootViewController: ForwardVC(msg: m, from: group))
    if let s = n.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
    present(n, animated: true)
  }
  // the pattern's tile in the chat's colours: dark lines at a tenth in light, white at a fifteenth in dark
  static let pattern: UIColor = {
    // (drawn once per look at the phone's own scale, its line colour solid and the strength given as the drawing's
    //  opacity — the tint's own alpha didn't come through, the pattern far stronger than the mock-up)
    func tile(_ ink: UIColor, _ alpha: CGFloat) -> UIColor {
      guard let t = UIImage(named: "TalkPattern")?.withTintColor(ink, renderingMode: .alwaysOriginal) else { return .clear }
      let f = UIGraphicsImageRendererFormat(); f.scale = UIScreen.main.scale; f.opaque = false
      let img = UIGraphicsImageRenderer(size: CGSize(width: 288, height: 288), format: f).image { _ in t.draw(in: CGRect(x: 0, y: 0, width: 288, height: 288), blendMode: .normal, alpha: alpha) }
      return UIColor(patternImage: img)
    }
    let light = tile(UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 1), 0.07), dark = tile(.white, 0.045)
    return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
  }()
  private func openInfo(_ m: Msg) { navigationController?.pushViewController(MessageInfoVC(group: group, id: m.id), animated: true) }
  private func startReply(_ m: Msg) { editingMsg = nil; replying = m; UIImpactFeedbackGenerator(style: .light).impactOccurred(); bar.box.becomeFirstResponder() }

  // ---------- hold: reactions and the menu ----------
  func tableView(_ tv: UITableView, contextMenuConfigurationForRowAt ip: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    guard case .msg(let id)? = data.itemIdentifier(for: ip), let m = msgs[id], m.kind != "sys" else { return nil }
    // (the trial of Haris 2026-11-12: a preview of the bubble — iPhone places it where it fits with the menu, shrinking a
    //  tall one — iMessage's way; build 39 kept the bubble itself, slid up WhatsApp's way)
    let shot = (tv.cellForRow(at: ip) as? BubbleCell)?.bubble.snapshotView(afterScreenUpdates: false)
    return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: shot.map { v in { BubblePreview(v) } }) { [weak self] _ in self?.menu(m) }
  }
  // opening and closing: from and back to the message's own place in the chat
  func tableView(_ tv: UITableView, previewForDismissingContextMenuWithConfiguration c: UIContextMenuConfiguration) -> UITargetedPreview? { holdPreview(tv, c) }
  func tableView(_ tv: UITableView, previewForHighlightingContextMenuWithConfiguration c: UIContextMenuConfiguration) -> UITargetedPreview? { holdPreview(tv, c) }
  private func holdPreview(_ tv: UITableView, _ c: UIContextMenuConfiguration) -> UITargetedPreview? {
    guard let id = c.identifier as? String, let ip = data.indexPath(for: .msg(id)), let cell = tv.cellForRow(at: ip) as? BubbleCell else { return nil }
    let p = UIPreviewParameters(); p.backgroundColor = .clear
    p.visiblePath = UIBezierPath(roundedRect: cell.bubble.bounds, cornerRadius: 19)
    return UITargetedPreview(view: cell.bubble, parameters: p)
  }
  // the design (board 33): the reactions on top, then Reply · Forward · Copy · Star · (line) · Delete — Forward comes with
  // the forward sheet (stage 5); yours also keep Edit (15 minutes) and Info, files Save / Share, as the app has them today
  private func menu(_ m: Msg) -> UIMenu {
    let T = Talk.shared, mine = m.by == T.me?.id
    let now = Date().timeIntervalSince1970 * 1000
    var items: [UIMenuElement] = []
    if !m.deleted && !m.pending {
      var acts: [UIMenuElement] = []
      acts.append(UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in self?.startReply(m) })
      acts.append(UIAction(title: "Forward", image: UIImage(systemName: "arrowshape.turn.up.right")) { [weak self] _ in self?.forward(m) })
      if !m.text.isEmpty { acts.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = m.text; toast("Copied") }) }
      let starred = T.isStarred(group, m.id)
      acts.append(UIAction(title: starred ? "Unstar" : "Star", image: UIImage(systemName: starred ? "star.slash" : "star")) { [weak self] _ in
        guard let self = self else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(); Talk.shared.toggleStar(self.group, m)
      })
      if mine && m.file == nil && now - m.at < 15 * 60000 {
        acts.append(UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] _ in
          self?.replying = nil; self?.editingMsg = m; self?.bar.setReply(("Editing", m.text), editing: true); self?.bar.box.text = m.text; self?.bar.textChanged(); self?.bar.box.becomeFirstResponder()
        })
      }
      if let f = m.file {
        acts.append(UIAction(title: "Save / Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
          Net.shared.file(f.id) { url in
            guard let url = url else { toast("That file isn’t on the server any more"); return }
            let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
            try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
            self?.present(UIActivityViewController(activityItems: [named], applicationActivities: nil), animated: true)
          }
        })
      }
      if mine { acts.append(UIAction(title: "Info", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.openInfo(m) }) }
      items.append(UIMenu(options: .displayInline, children: acts))
    }
    // (a deleted message's line: only Delete for Me — it goes from this phone's chat, Haris 2026-11-12)
    if m.deleted {
      return UIMenu(children: [UIAction(title: "Delete for Me", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
        guard let self = self else { return }; Talk.shared.deleteForMe(self.group, m)
      }])
    }
    items.append(UIMenu(options: .displayInline, children: [
      UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.askDelete(m) }
    ]))
    return UIMenu(children: items)
  }
  // Delete: Apple's sheet — for everyone (yours, about 2 days after sending) or for me
  private func askDelete(_ m: Msg) {
    let mine = m.by == Talk.shared.me?.id, now = Date().timeIntervalSince1970 * 1000
    let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    if mine && !m.deleted && !m.pending && now - m.at < 2 * 86400000 {
      a.addAction(UIAlertAction(title: "Delete for Everyone", style: .destructive) { [weak self] _ in
        guard let g = self?.group else { return }
        let was = Talk.shared.local(g, m.id) { $0.deleted = true; $0.text = ""; $0.reply = nil }   // (shows at once; the file goes with the server's answer)
        Net.shared.act(["act": "del", "msg": m.id]) { j in if (j?["ok"] as? Bool) == true { Talk.shared.sync() } else { if let w = was { Talk.shared.putBack(g, w) }; toast(j?["error"] as? String ?? "Couldn’t delete it") } }
      })
    }
    a.addAction(UIAlertAction(title: "Delete for Me", style: .destructive) { [weak self] _ in guard let self = self else { return }; Talk.shared.deleteForMe(self.group, m) })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(a, animated: true)
  }

  private func react(_ m: Msg, _ e: String?) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    guard let me = Talk.shared.me?.id else { return }
    let g = group
    let was = Talk.shared.local(g, m.id) { $0.reactions[me] = e }   // (shows at once)
    var b: [String: Any] = ["act": "react", "msg": m.id]; if let e = e { b["emoji"] = e }
    Net.shared.act(b) { j in
      if (j?["ok"] as? Bool) == true { Talk.shared.sync() } else { if let w = was { Talk.shared.putBack(g, w) }; toast(j?["error"] as? String ?? "Couldn’t react — try again") }
    }
  }
  // + : any emoji, from iPhone's emoji keyboard
  private func anyEmoji(_ m: Msg) {
    let v = EmojiSheet(mine: m.reactions[Talk.shared.me?.id ?? ""]) { [weak self] e in self?.react(m, e) }
    let n = UINavigationController(rootViewController: v)
    if let sh = n.sheetPresentationController { sh.detents = [.medium(), .large()]; sh.prefersGrabberVisible = true }
    present(n, animated: true)
  }

  // ---------- the reactions bar beside Apple's hold menu (approved mock-up "E11 Talk — hold a message", Haris
  // 2026-11-12): ours — a glass capsule above the held message: the seven quick ones, then the ones you used lately (no
  // twice), scrolling sideways; + pinned at its end opens the emoji sheet. Apple's lift and menu below it. ----------
  private var reactBar: ReactBar?
  func tableView(_ tv: UITableView, willDisplayContextMenu c: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
    guard let id = c.identifier as? String, let m = msgs[id], !m.deleted, !m.pending, m.kind != "sys",
          let ip = data.indexPath(for: .msg(id)), let cell = tv.cellForRow(at: ip) as? BubbleCell, let w = view.window else { return }
    let me = Talk.shared.me?.id ?? ""
    let bar = ReactBar(mine: m.reactions[me]) { [weak self, weak tv] e in
      guard let self = self else { return }
      if let e = e { self.react(m, m.reactions[me] == e ? nil : e) } else { self.pendingMore = m }
      tv?.contextMenuInteraction?.dismissMenu()
    }
    reactBar = bar
    let mine = m.by == Talk.shared.me?.id
    // (the strip just above where iPhone put the preview — known once its lift has finished; grows out of its top corner,
    //  the emojis popping in one after another)
    let show = { (b: CGRect) in
      guard self.reactBar === bar else { return }
      bar.frame = CGRect(x: 14, y: max(w.safeAreaInsets.top + 8, b.minY - 62), width: w.bounds.width - 28, height: 54)
      let from = CGPoint(x: mine ? b.maxX - 34 : b.minX + 34, y: b.minY), k: CGFloat = 0.2
      bar.alpha = 0
      bar.transform = CGAffineTransform(translationX: (from.x - bar.center.x) * (1 - k), y: (from.y - bar.center.y) * (1 - k)).scaledBy(x: k, y: k)
      bar.prepareToPop(); w.addSubview(bar)
      UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.74, initialSpringVelocity: 0) { bar.alpha = 1; bar.transform = .identity }
      bar.pop()
    }
    // (where iPhone puts the preview is known as its lift begins — its view is given its final place then — so the strip
    //  comes with the lift, not after it; checked again as the lift ends, and moved there if iPhone placed it otherwise.
    //  The place read with the preview's own size and scale, as iPhone may shrink it — Haris 2026-11-12)
    // (the preview's place read inside iPhone's own lift — where its final place is already set — and the strip shown
    //  there; read again as the lift ends and moved if iPhone placed it otherwise. Before, it was read a moment too early,
    //  from where the message started, and could land under the preview or over the menu — Haris 2026-11-12)
    guard let a = animator, let pv = (a.previewViewController as? BubblePreview)?.shot else { show(cell.bubble.convert(cell.bubble.bounds, to: w)); return }
    var shown = false
    a.addAnimations { let b = pv.convert(pv.bounds, to: w); DispatchQueue.main.async { if !shown { shown = true; show(b) } } }
    a.addCompletion {
      guard self.reactBar === bar, pv.window != nil else { return }
      let b = pv.convert(pv.bounds, to: w)
      if !shown { shown = true; show(b); return }
      let y = max(w.safeAreaInsets.top + 8, b.minY - 62)
      if abs(bar.frame.minY - y) > 1 { UIView.animate(withDuration: 0.2) { bar.frame.origin.y = y } }
    }
    // (the chat behind a little blurred while the message is held — Haris 2026-11-12)
    if let host = navigationController?.view {
      let veil = UIVisualEffectView(effect: nil); veil.frame = host.bounds; veil.isUserInteractionEnabled = false
      veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]; host.addSubview(veil); holdVeil = veil
      UIView.animate(withDuration: 0.3) { veil.effect = UIBlurEffect(style: .systemUltraThinMaterial) }
    }
  }
  private var holdVeil: UIVisualEffectView?
  func tableView(_ tv: UITableView, willEndContextMenuInteraction c: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
    if let veil = holdVeil { holdVeil = nil; UIView.animate(withDuration: 0.25, animations: { veil.effect = nil }) { _ in veil.removeFromSuperview() } }
    if let bar = reactBar {
      reactBar = nil
      UIView.animate(withDuration: 0.2, animations: { bar.alpha = 0; bar.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }) { _ in bar.removeFromSuperview() }
    }
    if let m = pendingMore {
      pendingMore = nil
      animator?.addCompletion { [weak self] in self?.anyEmoji(m) }
      if animator == nil { anyEmoji(m) }
    }
  }
  private var pendingMore: Msg?

}

extension ChatVC: UISearchBarDelegate {
  func searchBar(_ b: UISearchBar, textDidChange t: String) { runFind() }
  func searchBarSearchButtonClicked(_ b: UISearchBar) { b.searchTextField.resignFirstResponder() }
  // (the keyboard put down — Search, a tap on the chat or dragged away: the matches' bar stays at the bottom)
  func searchBarTextDidEndEditing(_ b: UISearchBar) {
    fitBottom()
  }
}

extension ChatVC: PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
  func picker(_ p: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    p.dismiss(animated: true)
    for r in results {
      let ip = r.itemProvider
      let isMovie = ip.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      let type = isMovie ? UTType.movie.identifier : UTType.image.identifier
      ip.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
        guard let url = url else { return }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: copy)
        DispatchQueue.main.async { self?.sendFile(copy, kind: isMovie ? "video" : "photo", name: ip.suggestedName.map { $0 + "." + url.pathExtension } ?? url.lastPathComponent) }
      }
    }
  }
  func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    p.dismiss(animated: true)
    if let url = info[.mediaURL] as? URL { sendFile(url, kind: "video", name: "Video.mov") }
    else if let img = info[.originalImage] as? UIImage, let d = img.jpegData(compressionQuality: 0.9) {
      let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg"); try? d.write(to: u)
      sendFile(u, kind: "photo", name: "Photo.jpg")
    }
  }
  func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    for u in urls { sendFile(u, kind: "file", name: u.lastPathComponent) }
  }
}

// ---------- the day over its messages (the design: a small chip, 20 high, 13 semibold) — the section's header, so it
// stays under the bar while its day scrolls by (Apple's floating header) ----------
final class DayHeader: UITableViewHeaderFooterView {
  private let chip = UIView(), l = UILabel()
  override init(reuseIdentifier: String?) {
    super.init(reuseIdentifier: reuseIdentifier)
    backgroundConfiguration = .clear()
    insetsLayoutMarginsFromSafeArea = false; contentView.insetsLayoutMarginsFromSafeArea = false
    chip.backgroundColor = Look.dayChip; chip.layer.cornerRadius = 8; chip.layer.cornerCurve = .continuous
    l.font = .systemFont(ofSize: 13, weight: .semibold); l.textColor = .label; l.textAlignment = .center
    chip.addSubview(l); contentView.addSubview(chip)
    [chip, l].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([
      chip.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), chip.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
      chip.heightAnchor.constraint(equalToConstant: 20),
      l.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10), l.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
      l.centerYAnchor.constraint(equalTo: chip.centerYAnchor)])
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ s: String) { l.text = s }
  // (only the chip fades — the header itself stays, so Apple's frost under the bar, which follows the stuck header,
  //  keeps its place: fading the whole header moved the frost up and down — Haris 2026-11-12)
  func showChip(_ on: Bool, animated: Bool = true) {
    let a: CGFloat = on ? 1 : 0
    guard chip.alpha != a else { return }
    if animated { UIView.animate(withDuration: on ? 0.15 : 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.chip.alpha = a } } else { chip.alpha = a }
  }
}

/* A message sent and one arriving (Haris 2026-11-11): E11 Console's own comment sounds — iPhone's system sound service,
   silent with the ring switch off, never stopping music or a video; several arriving together: one sound. */
enum ChatSound {
  private static var ids: [String: SystemSoundID] = [:]
  private static var lastArrive = Date.distantPast
  private static func play(_ name: String) {
    if ids[name] == nil, let url = Bundle.main.url(forResource: name, withExtension: "wav") {
      var id: SystemSoundID = 0
      AudioServicesCreateSystemSoundID(url as CFURL, &id); ids[name] = id
    }
    if let id = ids[name], id != 0 { AudioServicesPlaySystemSound(id) }
  }
  // (several sent together — a forward to many groups, a few photos — one sound)
  private static var lastSend = Date.distantPast
  static func send() { guard Date().timeIntervalSince(lastSend) > 0.4 else { return }; lastSend = Date(); play("chat-send") }
  // the voice note's own (Haris 2026-11-11): recording starts, a recording dropped into the bin
  static func voiceStart() { play("voice-start") }
  static func voiceCancel() { play("voice-cancel") }
  static func arrive() {
    guard Date().timeIntervalSince(lastArrive) > 1.2 else { return }
    lastArrive = Date(); play("chat-arrive")
  }
}

// ---------- a message (the approved design, canvas "E11 Talk — design", board 3) ----------
// Bubbles of 19 with the tail only on the last of a run from one person (that corner 4), 5 apart inside a run and 13
// between runs; others' first of a run carries the name in their E11 Console colour and the role under it in grey ("Client"
// in orange); their last carries their picture beside the tail; the time (and ✓✓ on yours) sits inside, on the last
// line when it fits, as WhatsApp.
struct Run: Hashable { var first = true, last = true }

/* The bubble's own shape — rounded 19, the tail's corner 4 and the tail itself — drawn by a shape layer, so the bubble's
   colour follows light / dark (set again on the look's change: a layer's colour is the one thing Apple can't switch). */
final class BubbleShape: UIView {
  private let shape = CAShapeLayer()
  var fill: UIColor = .clear { didSet { shape.fillColor = fill.resolvedColor(with: traitCollection).cgColor } }
  var tail: (mine: Bool, on: Bool) = (false, false) { didSet { setNeedsLayout() } }
  var fillTop: CGFloat = 0 { didSet { if fillTop != oldValue { setNeedsLayout() } } }
  override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; layer.insertSublayer(shape, at: 0) }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    shape.frame = bounds
    shape.path = BubbleShape.path(bounds.size, mine: tail.mine, tail: tail.on, top: fillTop).cgPath
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) {
    super.traitCollectionDidChange(p)
    if traitCollection.hasDifferentColorAppearance(comparedTo: p) { shape.fillColor = fill.resolvedColor(with: traitCollection).cgColor }
  }
  // a rectangle with its own radius at each corner (tl, tr, br, bl)
  static func rounded(_ r: CGRect, _ tl: CGFloat, _ tr: CGFloat, _ br: CGFloat, _ bl: CGFloat) -> UIBezierPath {
    let p = UIBezierPath(), x = r.minX, y = r.minY, W = r.maxX, H = r.maxY
    p.move(to: CGPoint(x: x + tl, y: y))
    p.addLine(to: CGPoint(x: W - tr, y: y)); if tr > 0 { p.addArc(withCenter: CGPoint(x: W - tr, y: y + tr), radius: tr, startAngle: -.pi / 2, endAngle: 0, clockwise: true) }
    p.addLine(to: CGPoint(x: W, y: H - br)); if br > 0 { p.addArc(withCenter: CGPoint(x: W - br, y: H - br), radius: br, startAngle: 0, endAngle: .pi / 2, clockwise: true) }
    p.addLine(to: CGPoint(x: x + bl, y: H)); if bl > 0 { p.addArc(withCenter: CGPoint(x: x + bl, y: H - bl), radius: bl, startAngle: .pi / 2, endAngle: .pi, clockwise: true) }
    p.addLine(to: CGPoint(x: x, y: y + tl)); if tl > 0 { p.addArc(withCenter: CGPoint(x: x + tl, y: y + tl), radius: tl, startAngle: .pi, endAngle: -.pi / 2, clockwise: true) }
    p.close(); return p
  }
  static func path(_ s: CGSize, mine: Bool, tail: Bool, r: CGFloat = 19, top: CGFloat = 0) -> UIBezierPath {
    let W = s.width, H = s.height, R = min(r, H / 2, W / 2)
    let small: CGFloat = 4
    let br = mine && tail ? small : R, bl = !mine && tail ? small : R
    guard top < H - 1 else { return UIBezierPath() }   // (a photo alone: no colour round it)
    let p = rounded(CGRect(x: 0, y: top, width: W, height: max(0, H - top)), top > 0 ? 0 : R, top > 0 ? 0 : R, br, bl)
    guard tail, H >= 17 else { return p }
    // (the tail: the design's curve "M0 0 C0 9 3 14 10 17 H0 z", 10 × 17, 8 outside the bubble's edge)
    let t = UIBezierPath()
    if mine {
      t.move(to: CGPoint(x: W - 2, y: H - 17))
      t.addCurve(to: CGPoint(x: W + 8, y: H), controlPoint1: CGPoint(x: W - 2, y: H - 8), controlPoint2: CGPoint(x: W + 1, y: H - 3))
      t.addLine(to: CGPoint(x: W - 2, y: H))
    } else {
      t.move(to: CGPoint(x: 2, y: H - 17))
      t.addCurve(to: CGPoint(x: -8, y: H), controlPoint1: CGPoint(x: 2, y: H - 8), controlPoint2: CGPoint(x: -1, y: H - 3))
      t.addLine(to: CGPoint(x: 2, y: H))
    }
    t.close(); p.append(t)
    return p
  }
}

// the photo in a bubble: its two shades (the name's diagonal, the time's at the bottom) follow its own size
final class PhotoView: UIImageView {
  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for l in layer.sublayers ?? [] {
      if l.name == "diag" { l.frame = bounds } else if l.name == "foot" { l.frame = CGRect(x: 0, y: bounds.height - 44, width: bounds.width, height: 44) }
    }
    CATransaction.commit()
  }
}
// words with room round them that Auto Layout knows about (the reactions pill, a group's note) — the old label drew its
// words inset inside a size that had no room for them, so they were cut away and the pill showed blank
final class InsetLabel: UILabel {
  private let dx: CGFloat, dy: CGFloat
  init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy; super.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError() }
  override func drawText(in r: CGRect) { super.drawText(in: r.insetBy(dx: dx, dy: dy)) }
  override func textRect(forBounds b: CGRect, limitedToNumberOfLines n: Int) -> CGRect {
    let r = super.textRect(forBounds: b.insetBy(dx: dx, dy: dy), limitedToNumberOfLines: n)
    return r.insetBy(dx: -dx, dy: -dy)
  }
}

enum Ticks {
  // ✓ sent · ✓✓ delivered to everyone · ✓✓ in aqua read by everyone (16 × 10, as the design draws it)
  static func image(_ c: UIColor, double: Bool = true) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 16, height: 10)).image { _ in
      let p = UIBezierPath()
      if double {
        p.move(to: CGPoint(x: 1, y: 5)); p.addLine(to: CGPoint(x: 4, y: 8)); p.addLine(to: CGPoint(x: 10, y: 2))
        p.move(to: CGPoint(x: 6, y: 8)); p.addLine(to: CGPoint(x: 7, y: 9)); p.addLine(to: CGPoint(x: 13, y: 2))
      } else { p.move(to: CGPoint(x: 4, y: 5)); p.addLine(to: CGPoint(x: 7, y: 8)); p.addLine(to: CGPoint(x: 13, y: 2)) }
      p.lineWidth = 1.6; p.lineCapStyle = .round; p.lineJoinStyle = .round
      c.setStroke(); p.stroke()
    }
  }
}

final class Bleed: UIView {
  let inner: UIView
  private var l: NSLayoutConstraint!, r: NSLayoutConstraint!, t: NSLayoutConstraint!, b: NSLayoutConstraint!
  init(_ v: UIView) {
    inner = v; super.init(frame: .zero)
    addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false
    l = v.leadingAnchor.constraint(equalTo: leadingAnchor); r = v.trailingAnchor.constraint(equalTo: trailingAnchor)
    t = v.topAnchor.constraint(equalTo: topAnchor); b = v.bottomAnchor.constraint(equalTo: bottomAnchor)
    b.priority = .init(999)   // (hidden in the bubble's stack it folds to 0 — its inside's own height gives way, no clash)
    NSLayoutConstraint.activate([l, r, t, b])
  }
  required init?(coder: NSCoder) { fatalError() }
  // how far past each edge it reaches
  func reach(_ top: CGFloat, _ left: CGFloat, _ bottom: CGFloat, _ right: CGFloat) { t.constant = -top; l.constant = -left; b.constant = bottom; r.constant = right }
}

final class BubbleCell: UITableViewCell {
  var find: (String, Bool)?   // (searching: the words, and whether this is the match shown)
  static let findAll = Look.rgb(0x7A5626), findNow = Look.rgb(0xD9952F)
  let bubble = BubbleShape()
  private let stack = UIStackView()
  private let nameL = UILabel(), roleL = UILabel(), textL = UILabel(), footL = UILabel(), stamp = UILabel()
  // a reply's quote (the design: a tinted box 4 from the bubble's edge, a bar in their colour, a photo's picture at the right)
  private let quote = UIView(), quoteBar = UIView(), quoteName = UILabel(), quoteText = UILabel(), quoteThumb = UIImageView()
  private lazy var quoteWrap = Bleed(quote)
  // a photo / video: to the bubble's edges; someone else's name over it on a diagonal shadow; the time over a bottom one
  let photo = PhotoView()
  private lazy var photoWrap = Bleed(photo)
  private let photoName = UILabel(), photoRole = UILabel(), diag = CAGradientLayer(), foot = CAGradientLayer()
  private let playDisc = UIView(), vlen = UILabel()
  // a document (any file): one card — its kind, name, size · kind; a download circle on one not on this phone yet
  private let card = UIView(), cardIcon = UIImageView(), cardName = UILabel(), cardSize = UILabel(), cardDown = UIImageView()
  private lazy var cardWrap = Bleed(card)
  // a link: its preview box — the site, the address, a line, 🔗 the site
  private let linkBox = UIView(), linkSite = UILabel(), linkURL = UILabel(), linkLine = UIView(), linkFoot = UILabel()
  // a link's preview (option B, Haris 2026-11-12): its picture on top of the card, ▶ on it for a video
  private let linkImg = UIImageView(), linkPlay = UIView()
  private var linkImgH: NSLayoutConstraint!, linkImgOff: NSLayoutConstraint!, wideCard = false
  private lazy var linkWrap = Bleed(linkBox)
  private var link: URL?
  private let voice = VoiceView()
  private let reacts = InsetLabel(dx: 8, dy: 0), sysL = InsetLabel(dx: 12, dy: 3), retryB = UIButton(type: .system)
  private let face = Avatar(frame: CGRect(x: 0, y: 0, width: 27, height: 27))
  private var lead: NSLayoutConstraint!, trail: NSLayoutConstraint!, photoH: NSLayoutConstraint!, mediaW: NSLayoutConstraint!
  private var wMine: NSLayoutConstraint!, wTheirs: NSLayoutConstraint!, top: NSLayoutConstraint!, stackTrail: NSLayoutConstraint!
  private var reactsLead: NSLayoutConstraint!, reactsTrail: NSLayoutConstraint!, bubbleBottom: NSLayoutConstraint!, reactsBottom: NSLayoutConstraint!
  private var msg: Msg?
  private var media = false, caption = false, tailOn = false, isMine = false, framed = false, overPhoto = false, shownFile: String?
  // "Forwarded" over a forwarded message (the design, board 32: italic, its arrow, in the time's colour)
  private let fwdL = UILabel()
  // the round forward button beside a photo, video, file or link (anyone's) — on the other side from the bubble
  let fwdB = UIButton(type: .custom)
  var onForward: ((Msg) -> Void)?
  private var fwdMine: NSLayoutConstraint!, fwdTheirs: NSLayoutConstraint!
  var onReplyTap: ((String) -> Void)?
  var onFileTap: ((Msg) -> Void)?
  var onRetry: ((Msg) -> Void)?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear; selectionStyle = .none
    insetsLayoutMarginsFromSafeArea = false; contentView.insetsLayoutMarginsFromSafeArea = false   // (steady heights — the rule)
    stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill
    nameL.font = .systemFont(ofSize: 15, weight: .semibold)
    roleL.font = .systemFont(ofSize: 12); roleL.textColor = Look.roleInk
    textL.font = .systemFont(ofSize: 17); textL.numberOfLines = 0
    textL.isUserInteractionEnabled = true; textL.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(linkTap)))
    footL.font = .systemFont(ofSize: 12); footL.textAlignment = .right
    stamp.font = .systemFont(ofSize: 12); stamp.textAlignment = .right
    // the quote
    quote.backgroundColor = UIColor.black.withAlphaComponent(0.22); quote.layer.cornerRadius = 15; quote.layer.cornerCurve = .continuous; quote.clipsToBounds = true
    quoteName.font = .systemFont(ofSize: 15, weight: .semibold); quoteText.font = .systemFont(ofSize: 14); quoteText.numberOfLines = 2
    quoteThumb.contentMode = .scaleAspectFill; quoteThumb.clipsToBounds = true
    // (the picture fills the quote's height, never sets it — a photo's own size made the quote as tall as the photo)
    quoteThumb.setContentCompressionResistancePriority(.init(1), for: .vertical); quoteThumb.setContentHuggingPriority(.init(1), for: .vertical)
    quoteThumb.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    let qs = UIStackView(arrangedSubviews: [quoteName, quoteText]); qs.axis = .vertical; qs.spacing = 0
    [quoteBar, qs, quoteThumb].forEach { quote.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([quoteBar.leadingAnchor.constraint(equalTo: quote.leadingAnchor), quoteBar.topAnchor.constraint(equalTo: quote.topAnchor), quoteBar.bottomAnchor.constraint(equalTo: quote.bottomAnchor), quoteBar.widthAnchor.constraint(equalToConstant: 4),
                                 qs.leadingAnchor.constraint(equalTo: quoteBar.trailingAnchor, constant: 10), qs.trailingAnchor.constraint(equalTo: quoteThumb.leadingAnchor, constant: -10), qs.topAnchor.constraint(equalTo: quote.topAnchor, constant: 6), qs.bottomAnchor.constraint(equalTo: quote.bottomAnchor, constant: -8),
                                 quoteThumb.trailingAnchor.constraint(equalTo: quote.trailingAnchor), quoteThumb.topAnchor.constraint(equalTo: quote.topAnchor), quoteThumb.bottomAnchor.constraint(equalTo: quote.bottomAnchor)])
    quoteThumbW = quoteThumb.widthAnchor.constraint(equalToConstant: 0); quoteThumbW.isActive = true
    quote.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(quoteTap)))
    // the photo
    photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; photo.backgroundColor = .tertiarySystemFill; photo.isUserInteractionEnabled = true
    photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fileTap)))
    diag.colors = [UIColor.black.withAlphaComponent(0.62).cgColor, UIColor.black.withAlphaComponent(0.28).cgColor, UIColor.clear.cgColor]
    diag.locations = [0, 0.26, 0.46]; diag.startPoint = CGPoint(x: 0, y: 0); diag.endPoint = CGPoint(x: 0.75, y: 1)
    foot.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.45).cgColor]
    diag.name = "diag"; foot.name = "foot"
    photo.layer.addSublayer(diag); photo.layer.addSublayer(foot)
    photoName.font = .systemFont(ofSize: 15, weight: .semibold); photoRole.font = .systemFont(ofSize: 12); photoRole.textColor = UIColor(white: 0.9, alpha: 1)
    for l in [photoName, photoRole] { l.layer.shadowColor = UIColor.black.cgColor; l.layer.shadowOpacity = 0.5; l.layer.shadowRadius = 2; l.layer.shadowOffset = CGSize(width: 0, height: 1) }
    let ps = UIStackView(arrangedSubviews: [photoName, photoRole]); ps.axis = .vertical; ps.alignment = .leading
    playDisc.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.92, alpha: 0.85); playDisc.layer.cornerRadius = 25; playDisc.isUserInteractionEnabled = false
    let tri = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))); tri.tintColor = UIColor(white: 0.23, alpha: 1)
    playDisc.addSubview(tri); tri.translatesAutoresizingMaskIntoConstraints = false
    vlen.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); vlen.textColor = .white
    vlen.layer.shadowColor = UIColor.black.cgColor; vlen.layer.shadowOpacity = 0.6; vlen.layer.shadowRadius = 2; vlen.layer.shadowOffset = CGSize(width: 0, height: 1)
    [ps, playDisc, vlen].forEach { photo.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([ps.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: 12), ps.topAnchor.constraint(equalTo: photo.topAnchor, constant: 8),
                                 playDisc.widthAnchor.constraint(equalToConstant: 50), playDisc.heightAnchor.constraint(equalToConstant: 50),
                                 playDisc.centerXAnchor.constraint(equalTo: photo.centerXAnchor), playDisc.centerYAnchor.constraint(equalTo: photo.centerYAnchor),
                                 tri.centerXAnchor.constraint(equalTo: playDisc.centerXAnchor, constant: 2), tri.centerYAnchor.constraint(equalTo: playDisc.centerYAnchor),
                                 vlen.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: 10), vlen.bottomAnchor.constraint(equalTo: photo.bottomAnchor, constant: -7)])
    photoH = photo.heightAnchor.constraint(equalToConstant: 180); photoH.priority = .init(999); photoH.isActive = true
    // the card
    card.backgroundColor = UIColor.black.withAlphaComponent(0.22); card.layer.cornerRadius = 14; card.layer.cornerCurve = .continuous
    cardName.font = .systemFont(ofSize: 16); cardName.lineBreakMode = .byTruncatingMiddle; cardSize.font = .systemFont(ofSize: 13)
    cardDown.image = UIImage(systemName: "arrow.down.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .light))
    let cs = UIStackView(arrangedSubviews: [cardName, cardSize]); cs.axis = .vertical
    [cardIcon, cs, cardDown].forEach { card.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    let ch = card.heightAnchor.constraint(equalToConstant: 58); ch.priority = .init(999)
    NSLayoutConstraint.activate([ch,
                                 cardIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11), cardIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                                 cardIcon.widthAnchor.constraint(equalToConstant: 22), cardIcon.heightAnchor.constraint(equalToConstant: 29),
                                 cs.leadingAnchor.constraint(equalTo: cardIcon.trailingAnchor, constant: 10), cs.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                                 cs.trailingAnchor.constraint(lessThanOrEqualTo: cardDown.leadingAnchor, constant: -10),
                                 cardDown.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12), cardDown.centerYAnchor.constraint(equalTo: card.centerYAnchor)])
    card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fileTap)))
    // the link's box
    linkBox.backgroundColor = UIColor.black.withAlphaComponent(0.22); linkBox.layer.cornerRadius = 15; linkBox.layer.cornerCurve = .continuous
    linkSite.font = .systemFont(ofSize: 15, weight: .semibold); linkURL.font = .systemFont(ofSize: 14); linkURL.numberOfLines = 2; linkURL.lineBreakMode = .byCharWrapping
    linkFoot.font = .systemFont(ofSize: 14)
    linkBox.clipsToBounds = true
    linkImg.contentMode = .scaleAspectFill; linkImg.clipsToBounds = true; linkImg.backgroundColor = UIColor.black.withAlphaComponent(0.12)
    linkImg.setContentCompressionResistancePriority(.init(1), for: .vertical); linkImg.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    linkPlay.backgroundColor = UIColor.black.withAlphaComponent(0.45); linkPlay.layer.cornerRadius = 23; linkPlay.isUserInteractionEnabled = false
    let playTri = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))); playTri.tintColor = .white
    playTri.translatesAutoresizingMaskIntoConstraints = false; linkPlay.addSubview(playTri)
    [linkImg, linkSite, linkURL, linkLine, linkFoot].forEach { linkBox.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    linkPlay.translatesAutoresizingMaskIntoConstraints = false; linkImg.addSubview(linkPlay)
    linkImgH = linkImg.heightAnchor.constraint(equalTo: linkImg.widthAnchor, multiplier: 1 / 1.91); linkImgH.priority = .init(999)
    linkImgOff = linkImg.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([linkImg.topAnchor.constraint(equalTo: linkBox.topAnchor), linkImg.leadingAnchor.constraint(equalTo: linkBox.leadingAnchor), linkImg.trailingAnchor.constraint(equalTo: linkBox.trailingAnchor), linkImgOff,
                                 linkPlay.widthAnchor.constraint(equalToConstant: 46), linkPlay.heightAnchor.constraint(equalToConstant: 46),
                                 linkPlay.centerXAnchor.constraint(equalTo: linkImg.centerXAnchor), linkPlay.centerYAnchor.constraint(equalTo: linkImg.centerYAnchor),
                                 playTri.centerXAnchor.constraint(equalTo: linkPlay.centerXAnchor, constant: 2), playTri.centerYAnchor.constraint(equalTo: linkPlay.centerYAnchor)])
    NSLayoutConstraint.activate([linkSite.topAnchor.constraint(equalTo: linkImg.bottomAnchor, constant: 9), linkSite.leadingAnchor.constraint(equalTo: linkBox.leadingAnchor, constant: 12), linkSite.trailingAnchor.constraint(equalTo: linkBox.trailingAnchor, constant: -12),
                                 linkURL.topAnchor.constraint(equalTo: linkSite.bottomAnchor), linkURL.leadingAnchor.constraint(equalTo: linkSite.leadingAnchor), linkURL.trailingAnchor.constraint(equalTo: linkSite.trailingAnchor),
                                 linkLine.topAnchor.constraint(equalTo: linkURL.bottomAnchor, constant: 9), linkLine.leadingAnchor.constraint(equalTo: linkSite.leadingAnchor), linkLine.trailingAnchor.constraint(equalTo: linkSite.trailingAnchor), linkLine.heightAnchor.constraint(equalToConstant: 0.5),
                                 linkFoot.topAnchor.constraint(equalTo: linkLine.bottomAnchor, constant: 8), linkFoot.leadingAnchor.constraint(equalTo: linkSite.leadingAnchor), linkFoot.trailingAnchor.constraint(equalTo: linkSite.trailingAnchor),
                                 linkFoot.bottomAnchor.constraint(equalTo: linkBox.bottomAnchor, constant: -9)])
    linkBox.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(linkTap)))
    [nameL, roleL, fwdL, photoWrap, quoteWrap, cardWrap, voice, linkWrap, textL, footL].forEach { stack.addArrangedSubview($0) }
    stack.setCustomSpacing(4, after: fwdL)
    stack.setCustomSpacing(2, after: roleL); stack.setCustomSpacing(6, after: photoWrap); stack.setCustomSpacing(7, after: quoteWrap)
    stack.setCustomSpacing(7, after: cardWrap); stack.setCustomSpacing(7, after: linkWrap); stack.setCustomSpacing(2, after: nameL)
    bubble.addSubview(stack); bubble.addSubview(stamp); contentView.addSubview(bubble)
    face.isUserInteractionEnabled = false; contentView.addSubview(face)
    reacts.font = .systemFont(ofSize: 14); reacts.backgroundColor = Look.theirs; reacts.layer.cornerRadius = 13; reacts.layer.masksToBounds = true
    reacts.layer.borderWidth = 2; reacts.layer.borderColor = Look.chatBg.resolvedColor(with: traitCollection).cgColor
    contentView.addSubview(reacts)
    sysL.font = .systemFont(ofSize: 12); sysL.textColor = Look.dyn(0xE5E5EA, 0x000000); sysL.backgroundColor = Look.dyn(0x181818, 0xFFFFFF); sysL.numberOfLines = 0; sysL.textAlignment = .center
    sysL.layer.cornerRadius = 8; sysL.layer.cornerCurve = .continuous; sysL.layer.masksToBounds = true
    contentView.addSubview(sysL)
    retryB.setImage(UIImage(systemName: "exclamationmark.circle.fill"), for: .normal); retryB.tintColor = .systemRed
    retryB.addAction(UIAction { [weak self] _ in if let m = self?.msg { self?.onRetry?(m) } }, for: .touchUpInside)
    contentView.addSubview(retryB)
    fwdL.font = .italicSystemFont(ofSize: 14)
    fwdB.backgroundColor = Look.downBtn; fwdB.layer.cornerRadius = 15
    fwdB.setImage(UIImage(systemName: "arrowshape.turn.up.right.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
    fwdB.tintColor = .secondaryLabel; fwdB.accessibilityLabel = "Forward"
    fwdB.addAction(UIAction { [weak self] _ in if let m = self?.msg { UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onForward?(m) } }, for: .touchUpInside)
    contentView.addSubview(fwdB)
    for v in [bubble, stack, stamp, face, reacts, sysL, retryB, fwdB] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
    fwdMine = fwdB.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -10)
    fwdTheirs = fwdB.leadingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: 18)
    lead = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44)
    trail = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -17)
    wMine = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 281 / 393)
    wTheirs = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 250 / 393)
    mediaW = bubble.widthAnchor.constraint(equalToConstant: 262); mediaW.priority = .init(999)
    top = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
    stackTrail = stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -11)
    reactsLead = reacts.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12)
    reactsTrail = reacts.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12)
    bubbleBottom = bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)
    reactsBottom = reacts.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)
    NSLayoutConstraint.activate([
      top,
      stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -7),
      stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), stackTrail,
      stamp.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -11), stamp.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
      face.widthAnchor.constraint(equalToConstant: 27), face.heightAnchor.constraint(equalToConstant: 27),
      face.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -10), face.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
      reacts.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -5), reacts.heightAnchor.constraint(equalToConstant: 26),
      sysL.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13), sysL.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
      sysL.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), sysL.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.85),
      retryB.centerYAnchor.constraint(equalTo: bubble.centerYAnchor), retryB.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -6),
      fwdB.widthAnchor.constraint(equalToConstant: 30), fwdB.heightAnchor.constraint(equalToConstant: 30), fwdB.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
    ])
  }
  private var quoteThumbW: NSLayoutConstraint!
  // (a short message: the bubble as narrow as its words — a weak pull to nothing that the words hold out against;
  //  the widest stays the design's — Haris 2026-11-12)
  private lazy var tight: NSLayoutConstraint = { let c = bubble.widthAnchor.constraint(equalToConstant: 0); c.priority = .init(999); return c }()
  // emojis alone (WhatsApp's sizes, measured from Haris's screenshot, 2026-11-12): larger in the bubble — one at 46, two at
  // 28, three at 22 — the time on its own line under them; more — as words. (One in a bubble too, Haris 16:27.)
  private var emojis = 0
  // the group's notes say people by their first name (Haris 2026-11-12): each full name the phone knows, longest first,
  // becomes its first word — "Muhammad Haris Sharif added Haris Client" → "Muhammad added Haris"
  static func firstNames(_ text: String) -> String {
    var t = text
    let names = Set(Talk.shared.people.values.map { $0.name }).filter { $0.contains(" ") }.sorted { $0.count > $1.count }
    for n in names where t.contains(n) { t = t.replacingOccurrences(of: n, with: String(n.split(separator: " ").first ?? Substring(n))) }
    return t
  }
  static func emojiCount(_ s: String) -> Int {
    let cs = s.filter { !$0.isWhitespace }
    guard !cs.isEmpty, cs.count <= 3 else { return 0 }
    for c in cs {
      guard let f = c.unicodeScalars.first, f.properties.isEmojiPresentation || (f.properties.isEmoji && c.unicodeScalars.count > 1) else { return 0 }
    }
    return cs.count
  }
  static let clear = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
  required init?(coder: NSCoder) { fatalError() }
  // ---------- the swipe (the design, board 26): the bubble follows the finger; to the right the grey circle with the
  // white arrow comes in beside it and pops once it's far enough; let go — it all springs back ----------
  private lazy var replyIcon: UIView = {
    let v = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
    v.backgroundColor = UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 0.55); v.layer.cornerRadius = 16; v.alpha = 0
    v.isUserInteractionEnabled = false
    let a = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
    a.tintColor = .white; a.center = CGPoint(x: 16, y: 16); v.addSubview(a)
    self.contentView.addSubview(v)
    return v
  }()
  private var moving: [UIView] { [bubble, face, reacts, retryB, fwdB] }
  func slide(_ dx: CGFloat) {
    let t = CGAffineTransform(translationX: dx, y: 0)
    for v in moving { v.transform = t }
    guard dx > 0 else { replyIcon.alpha = 0; return }
    // (the reply: the arrow comes in at the screen's left edge, the forward button goes)
    let p = min(1, dx / 64)
    replyIcon.center = CGPoint(x: 28, y: bubble.center.y)
    if !popping { replyIcon.transform = CGAffineTransform(scaleX: 0.5 + 0.5 * p, y: 0.5 + 0.5 * p) }
    replyIcon.alpha = p
    fwdB.alpha = 1 - p
    iconDx = 0
  }
  private var popping = false, iconDx: CGFloat = 0
  func pop() {
    popping = true
    let base = CGAffineTransform(translationX: iconDx, y: 0)
    UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.replyIcon.transform = base.scaledBy(x: 1.18, y: 1.18) } completion: { _ in
      UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.replyIcon.transform = CGAffineTransform(translationX: self.iconDx, y: 0) } completion: { _ in self.popping = false }
    }
  }
  func settle(animated: Bool) {
    let go = { for v in self.moving { v.transform = .identity }; self.replyIcon.alpha = 0; self.fwdB.alpha = 1 }
    popping = false
    if animated { UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: go) } else { go() }
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    for v in moving { v.transform = .identity }
    replyIcon.alpha = 0
    contentView.alpha = 1
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) {
    super.traitCollectionDidChange(p)
    if traitCollection.hasDifferentColorAppearance(comparedTo: p) { reacts.layer.borderColor = Look.chatBg.resolvedColor(with: traitCollection).cgColor; if let m = msg { foot(m) } }
  }
  // a photo: its corners follow the bubble's (top 19; at the bottom 19, the tail's 4 — or square above words)
  // a photo: rounded 19 at the top, and at the bottom too when no words follow (Apple's corner mask, so it follows the
  // photo's own size); the bubble's colour only under the words — none at all round a photo alone (it sat out from
  // under a photo as a coloured edge and a second tail: the old way read the sizes before they were laid out)
  private func shapePhoto() {
    photo.layer.cornerRadius = framed ? 14 : media ? 19 : 0; photo.layer.cornerCurve = .continuous
    photo.layer.maskedCorners = caption && !framed ? [.layerMinXMinYCorner, .layerMaxXMinYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    photo.layer.mask = nil
    bubble.fillTop = media ? (caption ? photoH.constant - 1 : .greatestFiniteMagnitude) : 0
  }
  private var group: Group?, log: GroupLog?

  func set(_ m: Msg, group g: Group, log l: GroupLog, run: Run) {
    msg = m; group = g; log = l
    let T = Talk.shared, mine = m.by == T.me?.id
    isMine = mine
    let sys = m.kind == "sys"
    sysL.isHidden = !sys; bubble.isHidden = sys; reacts.isHidden = true; retryB.isHidden = !(mine && m.failed); face.isHidden = true; fwdB.isHidden = true
    bubbleBottom.isActive = false; reactsBottom.isActive = false
    if sys {
      // (the group's notes as WhatsApp's, measured from Haris's screenshot: 12 on an 18 line, a small white pill — 2026-11-12)
      let ps = NSMutableParagraphStyle(); ps.minimumLineHeight = 18; ps.maximumLineHeight = 18; ps.alignment = .center
      sysL.attributedText = NSAttributedString(string: BubbleCell.firstNames(m.text), attributes: [.font: UIFont.systemFont(ofSize: 12), .paragraphStyle: ps, .baselineOffset: (18 - UIFont.systemFont(ofSize: 12).lineHeight) / 4])
      media = false; return
    }
    top.constant = run.first ? 10 : 2
    let isVideo = !m.deleted && m.file != nil && m.kind == "video"
    let isPhoto = !m.deleted && m.file != nil && (m.kind == "photo" || isVideo)
    let isVoice = !m.deleted && m.file != nil && m.kind == "voice"
    let isDoc = !m.deleted && m.file != nil && !isPhoto && !isVoice
    emojis = !m.deleted && m.file == nil && m.reply == nil && m.fwd != true ? BubbleCell.emojiCount(m.text) : 0
    // (only a photo has the photo's height — a text bubble on a cell that last showed a photo grew to it, Haris 2026-11-12)
    photoH.isActive = isPhoto
    textL.preferredMaxLayoutWidth = UIScreen.main.bounds.width * (mine ? 281 : 250) / 393 - 24
    // (a forwarded photo sits inside the bubble under "Forwarded", rounded 14, the bubble's colour round it)
    framed = isPhoto && m.fwd == true
    media = isPhoto && !framed; caption = isPhoto && !m.text.isEmpty; overPhoto = isPhoto && !caption
    fwdL.isHidden = m.fwd != true || m.deleted
    if !fwdL.isHidden {
      let c: UIColor = mine ? Look.mineTime : Look.roleInk
      let a = NSMutableAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "arrowshape.turn.up.right.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))!.withTintColor(c.resolvedColor(with: traitCollection), renderingMode: .alwaysOriginal)))
      a.append(NSAttributedString(string: " Forwarded", attributes: [.foregroundColor: c, .font: UIFont.italicSystemFont(ofSize: 14)]))
      fwdL.attributedText = a
    }
    fwdB.isHidden = m.deleted || m.pending || !(isPhoto || isDoc)   // (a link: below, once it's found)
    fwdB.alpha = 1
    fwdMine.isActive = mine; fwdTheirs.isActive = !mine
    lead.isActive = !mine; trail.isActive = mine
    mediaW.constant = isVoice ? 292 : mine ? 236 : 262; mediaW.isActive = isPhoto || isVoice
    wMine.isActive = mine && !isPhoto && !isVoice; wTheirs.isActive = !mine && !isPhoto && !isVoice
    stackTrail.constant = mine ? -11 : -12
    bubble.fill = mine ? Look.mine : Look.theirs
    tailOn = run.last && (!isPhoto || caption || framed)
    bubble.tail = (mine, tailOn)
    let ink: UIColor = mine ? .white : .label, dim: UIColor = mine ? Look.mineTime : Look.roleInk
    // the name: over a photo for one, else at the top (others', first of a run)
    let showName = !mine && run.first
    let p = T.people[m.by]
    let client = p?.contact == true && !T.isContact
    let role = client ? "Client" : (p?.role ?? "")
    nameL.isHidden = !showName || (isPhoto && !framed); roleL.isHidden = nameL.isHidden || role.isEmpty
    photoName.isHidden = !(showName && isPhoto && !framed); photoRole.isHidden = photoName.isHidden || role.isEmpty; diag.isHidden = photoName.isHidden
    for (n, r) in [(nameL, roleL), (photoName, photoRole)] {
      n.text = p?.name ?? "Someone"; n.textColor = Look.person(m.by)
      r.text = role; r.font = .systemFont(ofSize: 12, weight: client ? .semibold : .regular)
    }
    roleL.textColor = client ? Look.clientInk : Look.roleInk; photoRole.textColor = client ? Look.clientInk : UIColor(white: 0.9, alpha: 1)
    if !mine && run.last { face.isHidden = false; face.set(person: p) }
    // a reply's quote — the original's picture at the right when it was a photo
    quoteWrap.isHidden = m.reply == nil || m.deleted
    // (4 from the bubble's edge all round when it's at the top — the same as at its sides — its corners the bubble's own,
    //  4 in: 15 inside 19; Haris 2026-11-12)
    quoteWrap.reach(nameL.isHidden && fwdL.isHidden ? 4 : 0, 8, 0, mine ? 7 : 8)
    if let r = m.reply {
      quoteBar.backgroundColor = Look.person(r.by)
      quoteName.text = r.by == T.me?.id ? "You" : T.name(r.by); quoteName.textColor = mine ? .white : Look.person(r.by)
      let cam = r.kind == "photo" || r.kind == "video"
      let qt = NSMutableAttributedString()
      // (the kind's symbol in the quote's own words' colour — it was a faint grey, hard to see on the blue — and the emoji
      //  the quote's words came with taken off, so it isn't shown twice)
      let ink: UIColor = (mine ? UIColor.white.withAlphaComponent(0.8) : UIColor.secondaryLabel).resolvedColor(with: traitCollection)
      if cam || r.kind == "voice" || r.kind == "file" {
        let sym = r.kind == "voice" ? "mic.fill" : r.kind == "file" ? "doc.fill" : r.kind == "video" ? "video.fill" : "camera.fill"
        qt.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))!.withTintColor(ink, renderingMode: .alwaysOriginal))))
        qt.append(NSAttributedString(string: " "))
      }
      var said = r.text
      for e in ["📷 ", "🎥 ", "🎤 ", "📄 "] where said.hasPrefix(e) { said = String(said.dropFirst(e.count)) }
      let words = said.isEmpty ? (r.kind == "photo" ? "Photo" : r.kind == "video" ? "Video" : r.kind == "voice" ? "Voice message" : r.kind == "file" ? "File" : "") : said
      qt.append(NSAttributedString(string: words))
      qt.addAttribute(.foregroundColor, value: mine ? UIColor.white.withAlphaComponent(0.8) : UIColor.secondaryLabel, range: NSRange(location: 0, length: qt.length))
      quoteText.attributedText = qt
      quoteThumb.image = nil; quoteThumbW.constant = 0
      if cam, let o = l.msgs.first(where: { $0.id == r.id }), let f = o.file {
        quoteThumbW.constant = 54
        Net.shared.file(f.id) { [weak self] url in
          guard let self = self, self.msg?.id == m.id, let url = url else { return }
          if o.kind == "video" { BubbleCell.frame(url, f.id) { [weak self] i in if self?.msg?.id == m.id { self?.quoteThumb.image = i } } }
          else { self.quoteThumb.image = UIImage(contentsOfFile: url.path) }
        }
      }
    }
    // a photo / a video — to the bubble's edges (reaching past the stack's padding)
    photoWrap.isHidden = !isPhoto
    playDisc.isHidden = !isVideo; vlen.isHidden = !isVideo || m.file?.secs == nil
    if isPhoto, let f = m.file {
      let w: CGFloat = mine ? 236 : 262, ratio = CGFloat((f.h ?? 3) / max(1, f.w ?? 4))
      photoH.constant = min(330, max(120, w * ratio))
      if framed { photoWrap.reach(0, 8, caption ? 0 : 3, mine ? 7 : 8) } else { photoWrap.reach(8, 12, caption ? 0 : 7, mine ? 11 : 12) }
      if let s = f.secs { vlen.text = String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
      // (the same photo drawn again keeps its picture — it blanked for a moment on every redraw, all photos flashing)
      let known = isVideo ? BubbleCell.frames.object(forKey: f.id as NSString) : BubbleCell.pictures.object(forKey: f.id as NSString)
      if shownFile == f.id && photo.image != nil { } else if let k = known { photo.image = k; shownFile = f.id } else { photo.image = nil; shownFile = f.id }
      if photo.image == nil, !isVideo || f.size <= 60 * 1024 * 1024 || FileManager.default.fileExists(atPath: Net.local(f.id).path) {
        Net.shared.file(f.id) { [weak self] url in
          guard let self = self, self.msg?.id == m.id, let url = url else { return }
          if isVideo { BubbleCell.frame(url, f.id) { [weak self] img in if self?.msg?.id == m.id { self?.photo.image = img } } }
          else { self.photo.image = BubbleCell.picture(url, f.id) }
        }
      }
    }
    shapePhoto()
    foot.isHidden = !(isPhoto && !caption)
    voice.isHidden = !isVoice
    if isVoice, let f = m.file { voice.set(id: m.id, file: f, by: m.by, mine: mine) }
    // a document: the card, 4 from the bubble's edge
    cardWrap.isHidden = !isDoc
    cardWrap.reach(nameL.isHidden ? 4 : 0, 8, 0, mine ? 7 : 8)
    if isDoc, let f = m.file {
      let ext = (f.name as NSString).pathExtension.lowercased()
      cardIcon.image = BubbleCell.docIcon(ext.isEmpty ? "file" : ext)
      cardName.text = f.name; cardName.textColor = ink
      cardSize.text = ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file) + " · " + (ext.isEmpty ? "file" : ext); cardSize.textColor = dim
      cardDown.isHidden = mine || FileManager.default.fileExists(atPath: Net.local(f.id).path); cardDown.tintColor = ink
    }
    // the words — the time sits on their last line when it fits (room kept for it at the end, as WhatsApp); a link: its box, and blue
    let a = NSMutableAttributedString()
    link = nil
    if m.deleted {
      a.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "nosign")!.withTintColor(dim))))
      a.append(NSAttributedString(string: " " + (mine || m.goneForMe == true ? "You deleted this message" : "This message was deleted"), attributes: [.font: UIFont.italicSystemFont(ofSize: 17), .foregroundColor: dim]))
    } else {
      a.append(NSAttributedString(string: m.text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: ink]))
      for id in m.mentions {
        guard let n = T.people[id]?.name, !n.isEmpty else { continue }
        var from = m.text.startIndex
        while let r = m.text.range(of: "@" + n, range: from..<m.text.endIndex) {
          a.addAttributes([.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: mine ? UIColor.white : Look.person(id)], range: NSRange(r, in: m.text))
          from = r.upperBound
        }
      }
      if let d = BubbleCell.links, !m.text.isEmpty {
        let ns = m.text as NSString
        for hit in d.matches(in: m.text, range: NSRange(location: 0, length: ns.length)) {
          guard let u = hit.url, u.scheme?.hasPrefix("http") == true else { continue }
          if link == nil { link = u }
          a.addAttributes([.foregroundColor: mine ? UIColor.white : Look.linkInk, .underlineStyle: NSUnderlineStyle.single.rawValue], range: hit.range)
        }
      }
      // (searching: every match marked in amber, the one shown brighter — the design's board "Search in a chat")
      if let f = find, !f.0.isEmpty {
        let q = f.0, cur = f.1
        var from = m.text.startIndex
        while let r = m.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: from..<m.text.endIndex) {
          a.addAttributes([.backgroundColor: cur ? BubbleCell.findNow : BubbleCell.findAll, .foregroundColor: UIColor.white], range: NSRange(r, in: m.text))
          from = r.upperBound
        }
      }
    }
    linkWrap.isHidden = link == nil || isPhoto || isDoc
    tight.isActive = !isPhoto && !isVoice && !isDoc && (link == nil || m.link?.img != nil)
    if link != nil && !m.deleted && !m.pending { fwdB.isHidden = false }
    linkWrap.reach(nameL.isHidden ? 4 : 0, 8, 0, mine ? 7 : 8)
    wideCard = false
    if let u = link {
      let pv = m.link
      let site = pv?.site ?? (u.host ?? "").replacingOccurrences(of: "www.", with: "")
      let sub: UIColor = mine ? UIColor.white.withAlphaComponent(0.8) : .secondaryLabel
      // (with a preview: its picture, its title over two lines, the site with its icon; without: as before)
      let title = pv?.title.flatMap { $0.isEmpty ? nil : $0 }
      linkSite.text = title ?? site; linkSite.textColor = ink; linkSite.numberOfLines = title == nil ? 1 : 2
      linkURL.text = title == nil ? u.absoluteString : nil; linkURL.textColor = sub
      linkLine.backgroundColor = sub.withAlphaComponent(0.3)
      let mark = NSTextAttachment(image: UIImage(systemName: "link", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))!.withTintColor(sub))
      if let ic = pv?.icon, let i = UIImage(contentsOfFile: Net.local(ic).path) { mark.image = i; mark.bounds = CGRect(x: 0, y: -2, width: 14, height: 14) }
      let lf = NSMutableAttributedString(attachment: mark)
      lf.append(NSAttributedString(string: "  " + site, attributes: [.foregroundColor: sub])); linkFoot.attributedText = lf
      let hasImg = pv?.img != nil
      linkImgOff.isActive = !hasImg; linkImgH.isActive = hasImg; linkPlay.isHidden = !(hasImg && pv?.video == true)
      wideCard = hasImg
      if let id = pv?.img {
        if let i = UIImage(contentsOfFile: Net.local(id).path) { linkImg.image = i }
        else { linkImg.image = nil; Net.shared.file(id) { [weak self] url in guard let self = self, self.msg?.id == m.id, let url = url else { return }; self.linkImg.image = UIImage(contentsOfFile: url.path) } }
      } else { linkImg.image = nil }
    } else { linkImgOff.isActive = true; linkImgH.isActive = false }
    let words = a.length > 0
    textL.isHidden = !words
    footL.isHidden = true
    stamp.isHidden = false
    foot(m)
    if words && emojis > 0 {
      // (one at 46, two at 28, three at 22 — the time on its own line under them)
      let e = NSMutableAttributedString(string: m.text.trimmingCharacters(in: .whitespacesAndNewlines), attributes: [.font: UIFont.systemFont(ofSize: [46, 28, 22][emojis - 1])])
      // (the time's own line as wide as the time, so the bubble holds it — a lone emoji is narrower than its time)
      let room = NSTextAttachment(image: BubbleCell.clear); room.bounds = CGRect(x: 0, y: 0, width: ceil(stamp.intrinsicContentSize.width), height: 16)
      e.append(NSAttributedString(string: "\n")); e.append(NSAttributedString(attachment: room))
      textL.attributedText = e
    } else if words {
      let room = NSTextAttachment(image: BubbleCell.clear); room.bounds = CGRect(x: 0, y: 0, width: ceil(stamp.intrinsicContentSize.width) + 10, height: 1)
      a.append(NSAttributedString(attachment: room))
      // (the design: 17 on a 22 line)
      let ps = NSMutableParagraphStyle(); ps.minimumLineHeight = 22; ps.maximumLineHeight = 22
      a.addAttributes([.paragraphStyle: ps, .baselineOffset: (22 - UIFont.systemFont(ofSize: 17).lineHeight) / 4], range: NSRange(location: 0, length: a.length))
      textL.attributedText = a
    } else if !isPhoto && !isVoice {
      // (a card with no words: the time on its own line under it; a voice message keeps it at its bottom right)
      footL.isHidden = false; stamp.isHidden = true
    }
    // reactions under the bubble: the emojis and how many
    let counts = Dictionary(grouping: m.reactions.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    reacts.isHidden = counts.isEmpty || m.deleted
    reacts.text = counts.map { $0.0 }.joined() + (m.reactions.count > 1 ? " \(m.reactions.count)" : "")
    reactsLead.isActive = !mine; reactsTrail.isActive = mine
    // (a message of words: the bubble as wide as what's in it, worked out here — the words' own widest line with the time's
    //  room, the name, "Forwarded", a quote — never wider than the design's widest; the label's own size grew to that widest)
    if tight.isActive && wideCard { tight.constant = UIScreen.main.bounds.width * (mine ? 281 : 250) / 393 }   // (a preview's picture: the widest)
    else if tight.isActive {
      let widest = UIScreen.main.bounds.width * (mine ? 281 : 250) / 393, inner = widest - 24
      var w: CGFloat = 0
      if !textL.isHidden, let t = textL.attributedText {
        w = ceil(t.boundingRect(with: CGSize(width: inner, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).width) + 1
      }
      for l in [nameL, roleL, fwdL] where !l.isHidden { w = max(w, ceil(l.intrinsicContentSize.width)) }
      if !quoteWrap.isHidden { w = max(w, max(quoteName.intrinsicContentSize.width, quoteText.intrinsicContentSize.width) + 26 + quoteThumbW.constant) }
      if !footL.isHidden { w = max(w, ceil(footL.intrinsicContentSize.width)) }
      tight.constant = min(widest, w + 24)
    }
    if reacts.isHidden { bubbleBottom.isActive = true } else { reactsBottom.isActive = true }
    setNeedsLayout()
  }
  // the time inside — "Edited" before it, ✓✓ after it on yours; over a photo with no words: white, on its shadow
  private func foot(_ m: Msg) {
    guard let g = group, let l = log else { return }
    let T = Talk.shared, mine = m.by == T.me?.id
    let over = overPhoto
    let dim: UIColor = over ? .white : mine ? Look.mineTime : Look.roleInk
    let f = NSMutableAttributedString(string: (m.edited && !m.deleted ? "Edited " : "") + Look.clock(m.at), attributes: [.foregroundColor: dim, .font: UIFont.systemFont(ofSize: 12)])
    if mine && !m.deleted {
      let others = g.members.filter { $0 != m.by }
      let idx = l.msgs.firstIndex { $0.id == m.id } ?? 0
      let allSeen = !T.isContact && !others.isEmpty && others.allSatisfy { p in l.readBy[p].flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 >= idx } ?? false }
      // (delivered: every other phone has it — read counts as had; a client sees only this, never read)
      let allGot = !others.isEmpty && others.allSatisfy { p in l.read(p, m.id) || l.time(l.gotAt, p, m.id) != nil }
      f.append(NSAttributedString(string: " "))
      if m.pending {
        f.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: m.failed ? "exclamationmark.circle" : "clock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))!.withTintColor(dim.resolvedColor(with: traitCollection)))))
      } else {
        let c: UIColor = allSeen ? Look.readTick : over ? .white : Look.mineTime
        let t = NSTextAttachment(image: Ticks.image(c.resolvedColor(with: traitCollection), double: allSeen || allGot))
        t.bounds = CGRect(x: 0, y: -1, width: 16, height: 10)
        f.append(NSAttributedString(attachment: t))
      }
    }
    footL.attributedText = f; stamp.attributedText = f
    stamp.layer.shadowColor = UIColor.black.cgColor; stamp.layer.shadowOpacity = over ? 0.6 : 0; stamp.layer.shadowRadius = 2; stamp.layer.shadowOffset = CGSize(width: 0, height: 1)
  }
  static let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
  // a document's kind as the design draws it: a grey page with its corner turned, the kind in white on it
  private static var icons: [String: UIImage] = [:]
  static func docIcon(_ ext: String) -> UIImage {
    let label = String(ext.prefix(4)).uppercased()
    if let i = icons[label] { return i }
    let i = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 29)).image { _ in
      let page = UIBezierPath(); page.move(to: CGPoint(x: 3, y: 0)); page.addLine(to: CGPoint(x: 14, y: 0)); page.addLine(to: CGPoint(x: 22, y: 8)); page.addLine(to: CGPoint(x: 22, y: 26))
      page.addQuadCurve(to: CGPoint(x: 19, y: 29), controlPoint: CGPoint(x: 22, y: 29)); page.addLine(to: CGPoint(x: 3, y: 29)); page.addQuadCurve(to: CGPoint(x: 0, y: 26), controlPoint: CGPoint(x: 0, y: 29))
      page.addLine(to: CGPoint(x: 0, y: 3)); page.addQuadCurve(to: CGPoint(x: 3, y: 0), controlPoint: CGPoint(x: 0, y: 0)); page.close()
      UIColor.systemGray.setFill(); page.fill()
      let fold = UIBezierPath(); fold.move(to: CGPoint(x: 14, y: 0)); fold.addLine(to: CGPoint(x: 14, y: 5)); fold.addQuadCurve(to: CGPoint(x: 17, y: 8), controlPoint: CGPoint(x: 14, y: 8)); fold.addLine(to: CGPoint(x: 22, y: 8)); fold.close()
      UIColor.systemGray3.setFill(); fold.fill()
      let s = NSAttributedString(string: label, attributes: [.font: UIFont.systemFont(ofSize: label.count > 3 ? 5.5 : 7, weight: .heavy), .foregroundColor: UIColor.white])
      let sz = s.size(); s.draw(at: CGPoint(x: (22 - sz.width) / 2, y: 29 - 5 - sz.height))
    }
    icons[label] = i; return i
  }
  // a photo, shrunk once to the bubble's size and kept
  private static let pictures = NSCache<NSString, UIImage>()
  static func picture(_ url: URL, _ id: String) -> UIImage? {
    if let i = pictures.object(forKey: id as NSString) { return i }
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 800] as CFDictionary) else { return UIImage(contentsOfFile: url.path) }
    let i = UIImage(cgImage: cg); pictures.setObject(i, forKey: id as NSString); return i
  }
  // a video's first frame (kept)
  static let frames = NSCache<NSString, UIImage>()
  static func frame(_ url: URL, _ id: String, _ done: @escaping (UIImage?) -> Void) {
    if let i = frames.object(forKey: id as NSString) { done(i); return }
    DispatchQueue.global(qos: .userInitiated).async {
      let named = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(Net.stableKey(id)).mp4")
      if !FileManager.default.fileExists(atPath: named.path) { try? FileManager.default.copyItem(at: url, to: named) }
      let g = AVAssetImageGenerator(asset: AVURLAsset(url: named)); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 720, height: 720)
      let img = (try? g.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)).map { UIImage(cgImage: $0) }
      if let i = img { frames.setObject(i, forKey: id as NSString) }
      DispatchQueue.main.async { done(img) }
    }
  }
  @objc private func quoteTap() { if let r = msg?.reply { onReplyTap?(r.id) } }
  @objc private func fileTap() { if let m = msg { onFileTap?(m) } }
  @objc private func linkTap() { if let u = link { UIApplication.shared.open(u) } }
  // a found message: the bubble swells a little and settles (on its layer, so a swipe's own move is never disturbed)
  func pulse() {
    let a = CAKeyframeAnimation(keyPath: "transform.scale")
    a.values = [1, 1.07, 0.98, 1]; a.keyTimes = [0, 0.35, 0.7, 1]; a.duration = 0.45
    a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeOut)]
    bubble.layer.add(a, forKey: "pulse")
  }

}

// ---------- the message bar (Haris 2026-11-05 "like WhatsApp"): + · the box · camera · mic; typing → send ----------
/* The message box (the design): it can switch to iPhone's emoji keyboard from its smiley — Apple's own keyboard,
   asked for through the text view's input mode. */
final class EmojiBox: UITextView {
  var emoji = false
  override var textInputMode: UITextInputMode? {
    if emoji, let m = UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage == "emoji" }) { return m }
    return super.textInputMode
  }
}

final class MessageBar: UIView, UITextViewDelegate {
  let box = EmojiBox()
  private let smiley = UIButton(type: .system)
  private let plus = UIButton(type: .system), cam = UIButton(type: .system), mic = UIButton(type: .system), sendB = UIButton(type: .system)
  private let place = UILabel()
  var placeholder = "Message" { didSet { place.text = placeholder } }
  private let replyV = UIView(), replyName = UILabel(), replyText = UILabel(), replyX = UIButton(type: .system), replyBar = UIView()
  private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  var onSend: ((String, [String]) -> Void)?
  var onPlus: ((String) -> Void)?
  var onCancelReply: (() -> Void)?
  var onVoice: ((URL, Double, String) -> Void)?
  var onLayout: (() -> Void)?
  var recording: Bool { rec.isRecording || rec.isPaused || locked }
  // @: the group's people (id, name); the ones picked while typing
  var people: [(String, String)] = []
  private var picked: [String: String] = [:]   // id → name
  private let mentionV = UIStackView()
  private var mentionQ: (NSRange, String)?
  // the voice message being recorded: red dot, time, "‹ Slide to cancel"
  private let rec = VoiceRecorder()
  // recording (the approved design, boards 21 / 29–31): holding — the red mic, the time, "Slide to cancel ‹", the lock pill
  // above the mic; slid left — the mic flips into the bin; pulled up — locked: the time and the live waveform, then
  // delete · pause · send
  private let recV = UIView(), recMic = UIImageView(), recTime = UILabel(), recHint = UILabel()
  private let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial)), pillLock = UIImageView(), pillUp = UIImageView()
  private let binBody = UIImageView(), binLid = UIImageView()
  private let lockedV = UIView(), lockedTime = UILabel(), live = LiveWave(), trashB = UIButton(type: .system), pauseB = UIButton(type: .system), lockedSend = UIButton(type: .system)
  private var recCancelled = false, recStart: CGPoint = .zero, locked = false, holding = false
  private var boxH: CGFloat = 30

  override init(frame: CGRect) {
    super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
    autoresizingMask = .flexibleHeight
    // (WhatsApp's: a frost in the chat's own colour — what scrolls behind shows through softly; the box white with its
    //  hairline — Haris 2026-11-12. Apple's blur, tinted with the page's colour.)
    blur.contentView.backgroundColor = UIColor { Look.chatBg.resolvedColor(with: $0).withAlphaComponent(0.62) }
    addSubview(blur)
    // (the design: + · the box with its smiley · camera · the mic in a round button — while typing, send in our blue)
    // (WhatsApp's weights and sizes, Haris 2026-11-12: + thin, the camera and smiley lighter and smaller — they looked
    //  heavy and squeezed)
    let sym = { (n: String, size: CGFloat, w: UIImage.SymbolWeight) in UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: w)) }
    plus.setImage(sym("plus", 18, .light), for: .normal); cam.setImage(sym("camera", 16, .regular), for: .normal)
    [plus, cam].forEach { $0.tintColor = .label; addSubview($0) }
    var mc = UIButton.Configuration.filled()
    // (WhatsApp's, measured from Haris's screenshot: a filled mic about 11 × 16 in a 31 circle, level with the box)
    mc.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
    mc.baseBackgroundColor = .label; mc.baseForegroundColor = .systemBackground; mc.cornerStyle = .capsule; mc.contentInsets = .zero
    mic.configuration = mc
    var sc = UIButton.Configuration.filled()
    sc.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
    sc.baseBackgroundColor = Look.rgb(0x2F7BFF); sc.baseForegroundColor = .white; sc.cornerStyle = .capsule; sc.contentInsets = .zero
    sendB.configuration = sc
    mic.accessibilityLabel = "Hold to record a voice message"; sendB.accessibilityLabel = "Send"
    [mic, sendB].forEach { addSubview($0) }
    smiley.setImage(sym("face.smiling", 15, .regular), for: .normal); smiley.tintColor = .label; smiley.accessibilityLabel = "Emoji"
    smiley.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      self.box.emoji.toggle()
      if self.box.isFirstResponder { self.box.reloadInputViews() } else { self.box.becomeFirstResponder() }
    }, for: .touchUpInside)
    plus.showsMenuAsPrimaryAction = true
    plus.menu = UIMenu(children: [
      UIAction(title: "Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in self?.onPlus?("photos") },
      UIAction(title: "Camera", image: UIImage(systemName: "camera")) { [weak self] _ in self?.onPlus?("camera") },
      UIAction(title: "Files", image: UIImage(systemName: "folder")) { [weak self] _ in self?.onPlus?("files") }])
    cam.addAction(UIAction { [weak self] _ in self?.onPlus?("camera") }, for: .touchUpInside)
    // (hold the mic to record — let go to send, slide left to drop it; a tap says how)
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(micHold(_:))); hold.minimumPressDuration = 0.18
    mic.addGestureRecognizer(hold)
    mic.addAction(UIAction { _ in toast("Hold to record, let go to send") }, for: .touchUpInside)
    recV.backgroundColor = .clear; recV.isHidden = true
    recMic.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)); recMic.tintColor = .systemRed
    recMic.contentMode = .center; recMic.alpha = 0
    for l in [recTime, lockedTime] { l.font = .monospacedDigitSystemFont(ofSize: 20, weight: .regular); l.textColor = .label }
    recHint.text = "Slide to cancel ‹"; recHint.font = .systemFont(ofSize: 17); recHint.textColor = .secondaryLabel; recHint.textAlignment = .center
    [recTime, recHint].forEach { recV.addSubview($0) }
    addSubview(recV); addSubview(recMic)
    pill.layer.cornerRadius = 20; pill.clipsToBounds = true; pill.alpha = 0; pill.isUserInteractionEnabled = false
    pillLock.image = UIImage(systemName: "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)); pillLock.tintColor = .label; pillLock.contentMode = .center
    pillUp.image = UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)); pillUp.tintColor = .secondaryLabel; pillUp.contentMode = .center
    pill.contentView.addSubview(pillLock); pill.contentView.addSubview(pillUp)
    binBody.image = MessageBar.bin(lid: false); binLid.image = MessageBar.bin(lid: true)
    [binBody, binLid].forEach { $0.tintColor = .secondaryLabel; $0.alpha = 0; addSubview($0) }
    binLid.layer.anchorPoint = CGPoint(x: 0.08, y: 0.9)
    lockedV.isHidden = true; lockedV.backgroundColor = .clear
    trashB.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)), for: .normal); trashB.tintColor = .label
    trashB.accessibilityLabel = "Delete the recording"
    pauseB.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal); pauseB.tintColor = .systemRed
    pauseB.layer.borderWidth = 2; pauseB.layer.cornerRadius = 17; pauseB.accessibilityLabel = "Pause the recording"
    var ls = UIButton.Configuration.filled()
    ls.image = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    ls.baseBackgroundColor = Look.rgb(0x2F7BFF); ls.baseForegroundColor = .white; ls.cornerStyle = .capsule; ls.contentInsets = .zero
    lockedSend.configuration = ls; lockedSend.accessibilityLabel = "Send"
    [lockedTime, live, trashB, pauseB, lockedSend].forEach { lockedV.addSubview($0) }
    addSubview(lockedV); addSubview(pill)
    trashB.addAction(UIAction { [weak self] _ in self?.cancelRecording() }, for: .touchUpInside)
    pauseB.addAction(UIAction { [weak self] _ in self?.togglePause() }, for: .touchUpInside)
    lockedSend.addAction(UIAction { [weak self] _ in self?.endRecording(send: true) }, for: .touchUpInside)
    rec.onTick = { [weak self] t in
      guard let self = self else { return }
      let s = String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
      self.recTime.text = s; self.lockedTime.text = s
      if self.locked { self.live.levels = self.rec.levels }
    }
    mentionV.axis = .vertical; mentionV.isHidden = true
    addSubview(mentionV)
    sendB.addAction(UIAction { [weak self] _ in self?.sendNow() }, for: .touchUpInside)
    box.font = .systemFont(ofSize: 17); box.backgroundColor = Look.field; box.layer.cornerRadius = 15; box.layer.cornerCurve = .continuous; box.layer.borderWidth = 0.5
    box.textContainerInset = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 34); box.delegate = self; box.isScrollEnabled = false
    addSubview(box); addSubview(smiley)
    place.text = ""; place.font = .systemFont(ofSize: 16); place.textColor = .systemGray; box.addSubview(place)
    // the message being answered (WhatsApp's): edge to edge over the box, its person's colour as the bar on the very
    // left and their name, the words under it, ⓧ drawn thin at the right
    replyV.backgroundColor = .tertiarySystemFill
    replyBar.backgroundColor = Look.accent; replyName.font = .systemFont(ofSize: 15, weight: .semibold); replyName.textColor = Look.accent
    replyText.font = .systemFont(ofSize: 15); replyText.textColor = .label
    replyX.setImage(UIImage(systemName: "xmark.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .light)), for: .normal); replyX.tintColor = .label
    replyX.accessibilityLabel = "Cancel the reply"
    replyX.addAction(UIAction { [weak self] _ in self?.onCancelReply?() }, for: .touchUpInside)
    [replyBar, replyName, replyText, replyX].forEach { replyV.addSubview($0) }
    replyV.isHidden = true; addSubview(replyV)
    textChanged()
  }
  required init?(coder: NSCoder) { fatalError() }
  // (the bar stays above the home indicator when the keyboard is down)
  private var mentionH: CGFloat { mentionV.isHidden ? 0 : CGFloat(mentionV.arrangedSubviews.count) * 44 }
  var listH: CGFloat { mentionH }   // (the @ list sits over the chat — the chat makes no room for it)
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: (locked ? 83 : boxH + 13) + (replyV.isHidden ? 0 : 52) + mentionH) }
  override func layoutSubviews() {
    super.layoutSubviews()
    defer { onLayout?() }
    let W = bounds.width, mh = mentionH, top: CGFloat = mh + (replyV.isHidden ? 0 : 52)
    blur.frame = CGRect(x: 0, y: 0, width: W, height: bounds.height + 420)   // (down behind the home line and the keyboard)
    mentionV.frame = CGRect(x: 0, y: 0, width: W, height: mh)
    replyV.frame = CGRect(x: 0, y: mh, width: W, height: 52)
    replyBar.frame = CGRect(x: 0, y: 0, width: 4, height: 52)
    replyName.frame = CGRect(x: 12, y: 7, width: W - 64, height: 19); replyText.frame = CGRect(x: 12, y: 27, width: W - 64, height: 19)
    replyX.frame = CGRect(x: W - 46, y: 6, width: 40, height: 40)
    let typing = !box.text.isEmpty
    // (the design's places: + at 10, the box from 46, camera and mic at the right; the buttons stay level with the box's last line)
    let y = top + 9, by = y + boxH - 31   // (the design: the box 9 from the bar's top, the buttons 1 above it)
    plus.frame = CGRect(x: 10, y: by, width: 32, height: 32)
    let right: CGFloat = typing ? 49 : 93
    box.frame = CGRect(x: 46, y: y, width: W - 46 - right, height: boxH)
    smiley.frame = CGRect(x: box.frame.maxX - 34, y: y + boxH - 31, width: 32, height: 32)
    place.frame = CGRect(x: 13, y: 5, width: box.bounds.width - 46, height: 20)
    sendB.frame = CGRect(x: W - 41, y: y + boxH - 15 - 15.5, width: 31, height: 31)   // (the mic's own size and place)
    cam.frame = CGRect(x: W - 79, y: by, width: 32, height: 32); mic.frame = CGRect(x: W - 41, y: y + boxH - 15 - 15.5, width: 31, height: 31)
    sendB.isHidden = !typing; cam.isHidden = typing; mic.isHidden = typing
    recV.frame = CGRect(x: 0, y: y, width: W - 60, height: 32)
    recTime.frame = CGRect(x: 42, y: 0, width: 70, height: 32)
    recHint.frame = CGRect(x: 0, y: 0, width: W, height: 32)
    if recMic.transform == .identity { recMic.frame = CGRect(x: 10, y: y, width: 26, height: 32) }
    pill.frame = CGRect(x: W - 44, y: y - 101, width: 40, height: 132)
    pillLock.frame = CGRect(x: 0, y: 10, width: 40, height: 22); pillUp.frame = CGRect(x: 0, y: 34, width: 40, height: 14)
    binBody.bounds = CGRect(x: 0, y: 0, width: 22, height: 18); binLid.bounds = CGRect(x: 0, y: 0, width: 22, height: 8)
    if binBody.alpha == 0 { binBody.center = CGPoint(x: 23, y: y + 25); binLid.center = CGPoint(x: 23 - 9.24, y: y + 13.2) }
    lockedV.frame = CGRect(x: 0, y: top, width: W, height: 83)
    lockedTime.frame = CGRect(x: 16, y: 10, width: 64, height: 24)
    live.frame = CGRect(x: 80, y: 11, width: W - 96, height: 22)
    trashB.frame = CGRect(x: 10, y: 44, width: 40, height: 40)
    pauseB.frame = CGRect(x: W / 2 - 17, y: 47, width: 34, height: 34)
    lockedSend.frame = CGRect(x: W - 41, y: 48.5, width: 31, height: 31)   // (the send's own size, 10 from the edge — Haris 2026-11-12)
    pauseB.layer.borderColor = UIColor.systemRed.resolvedColor(with: traitCollection).cgColor
    box.layer.borderColor = MessageBar.boxEdge.resolvedColor(with: traitCollection).cgColor
  }
  @objc private func micHold(_ g: UILongPressGestureRecognizer) {
    switch g.state {
    case .began:
      recCancelled = false; locked = false; holding = true; recStart = g.location(in: self)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      rec.start { [weak self] ok in
        guard let self = self else { return }
        guard ok else { toast("Allow the microphone for E11 Talk in Settings to record"); return }
        guard self.holding else { _ = self.rec.stop(keep: false); return }
        ChatSound.voiceStart()
        self.recTime.text = "0:00"; self.lockedTime.text = "0:00"
        self.recV.isHidden = false; self.recV.alpha = 0; self.recMic.alpha = 0
        self.recHint.transform = CGAffineTransform(translationX: 60, y: 0)
        self.pill.transform = CGAffineTransform(translationX: 0, y: 40).scaledBy(x: 1, y: 0.4)
        self.pillLock.image = UIImage(systemName: "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        // (the box, + and camera slide away left; the time, the hint and the pill come in; the mic grows under the finger)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
          for v in [self.box, self.smiley, self.plus, self.cam] as [UIView] { v.alpha = 0; v.transform = CGAffineTransform(translationX: -60, y: 0) }
          self.recV.alpha = 1; self.recMic.alpha = 1; self.recHint.transform = .identity
          self.pill.alpha = 1; self.pill.transform = .identity
          self.mic.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        }
        UIView.animate(withDuration: 0.6, delay: 0.3, options: [.repeat, .autoreverse, .allowUserInteraction]) { self.recMic.alpha = 0.35 }
      }
    case .changed:
      guard rec.isRecording, !recCancelled, !locked else { return }
      let p = g.location(in: self), dx = p.x - recStart.x, dy = p.y - recStart.y
      if dy < -12 && dy < dx {
        // pulling up: the mic rises into the pill, the pill shortens; far enough — locked
        mic.transform = CGAffineTransform(translationX: 0, y: max(dy, -82)).scaledBy(x: 1.15, y: 1.15)
        pill.transform = CGAffineTransform(translationX: 0, y: max(dy, -82) * 0.08).scaledBy(x: 1, y: max(0.62, 1 + dy / 220))
        if dy < -82 { lock() }
      } else {
        recHint.transform = CGAffineTransform(translationX: min(0, dx), y: 0); recHint.alpha = max(0, 1 + dx / 140)
        if dx < -120 { cancelRecording() }
      }
    case .ended: holding = false; if !recCancelled && !locked { endRecording(send: true) }
    case .cancelled, .failed: holding = false; if !recCancelled && !locked { endRecording(send: false) }
    default: break
    }
  }
  // pulled up into the lock: it shuts, the pill goes, the bar opens to the locked recording
  private func lock() {
    locked = true
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    pillLock.image = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    live.levels = rec.levels
    lockedV.isHidden = false; lockedV.alpha = 0; lockedV.transform = CGAffineTransform(translationX: 0, y: 40)
    invalidateIntrinsicContentSize()
    UIView.animate(withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
      self.pill.alpha = 0; self.mic.alpha = 0; self.recV.alpha = 0; self.recMic.alpha = 0
      self.lockedV.alpha = 1; self.lockedV.transform = .identity
      self.superview?.layoutIfNeeded(); self.layoutIfNeeded()
    }
  }
  private func togglePause() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let paused = rec.togglePause()
    pauseB.setImage(UIImage(systemName: paused ? "mic.fill" : "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal)
  }
  // slid left (or the bin while locked): the recording goes — the red mic flips up and drops into the bin, the bin sinks
  private func cancelRecording() {
    guard !recCancelled else { return }
    recCancelled = true
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    _ = rec.stop(keep: false)
    let wasLocked = locked
    recMic.layer.removeAllAnimations(); recMic.alpha = 1
    let start = recMic.center
    binBody.alpha = 0; binLid.alpha = 0
    binBody.transform = CGAffineTransform(translationX: 0, y: 46); binLid.transform = CGAffineTransform(translationX: 0, y: 46)
    UIView.animate(withDuration: 0.2) {
      self.recV.alpha = 0; self.pill.alpha = 0; self.mic.transform = .identity; self.lockedV.alpha = 0
    }
    UIView.animateKeyframes(withDuration: 1.25, delay: wasLocked ? 0.1 : 0, options: [.calculationModeCubic]) {
      UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.35) {
        self.recMic.center = CGPoint(x: start.x, y: start.y - 70); self.recMic.transform = CGAffineTransform(rotationAngle: -.pi)
        self.binBody.alpha = 1; self.binLid.alpha = 1; self.binBody.transform = .identity; self.binLid.transform = .identity
      }
      UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.1) { self.binLid.transform = CGAffineTransform(rotationAngle: -0.95) }
      UIView.addKeyframe(withRelativeStartTime: 0.35, relativeDuration: 0.2) {
        self.recMic.center = CGPoint(x: self.binBody.center.x, y: self.binBody.center.y); self.recMic.transform = CGAffineTransform(rotationAngle: -2 * .pi).scaledBy(x: 0.5, y: 0.5)
      }
      UIView.addKeyframe(withRelativeStartTime: 0.55, relativeDuration: 0.02) { self.recMic.alpha = 0 }
      UIView.addKeyframe(withRelativeStartTime: 0.55, relativeDuration: 0.1) { self.binLid.transform = .identity }
      UIView.addKeyframe(withRelativeStartTime: 0.7, relativeDuration: 0.3) {
        self.binBody.transform = CGAffineTransform(translationX: 0, y: 60); self.binLid.transform = CGAffineTransform(translationX: 0, y: 60)
        self.binBody.alpha = 0; self.binLid.alpha = 0
      }
    } completion: { _ in
      self.recMic.transform = .identity; self.recMic.center = start
      self.backToBox()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ChatSound.voiceCancel() }
  }
  private func endRecording(send: Bool) {
    recMic.layer.removeAllAnimations()
    let r = rec.isRecording || rec.isPaused ? rec.stop(keep: send) : nil
    UIView.animate(withDuration: 0.2) { self.recV.alpha = 0; self.recMic.alpha = 0; self.pill.alpha = 0; self.lockedV.alpha = 0; self.mic.transform = .identity }
    backToBox()
    if let r = r { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onVoice?(r.0, r.1, r.2) }
    else if send { toast("Hold longer to record") }
  }
  // the box, + and camera slide back
  private func backToBox() {
    locked = false
    recV.isHidden = true; lockedV.isHidden = true
    recHint.alpha = 1; recHint.transform = .identity
    pauseB.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal)
    invalidateIntrinsicContentSize()
    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
      for v in [self.box, self.smiley, self.plus, self.cam, self.mic] as [UIView] { v.alpha = 1; v.transform = .identity }
      self.superview?.layoutIfNeeded(); self.layoutIfNeeded()
    }
  }
  static let boxEdge = Look.dyn(0x3A3A3C, 0xC6C6C8)
  override func traitCollectionDidChange(_ p: UITraitCollection?) { super.traitCollectionDidChange(p); if traitCollection.hasDifferentColorAppearance(comparedTo: p) { setNeedsLayout() } }
  // the bin as the design draws it — its body, and its lid apart so it can open
  static func bin(lid: Bool) -> UIImage {
    let size = lid ? CGSize(width: 22, height: 8) : CGSize(width: 22, height: 18)
    return UIGraphicsImageRenderer(size: size).image { _ in
      let p = UIBezierPath()
      if lid { p.move(to: CGPoint(x: 1, y: 7)); p.addLine(to: CGPoint(x: 21, y: 7)); p.move(to: CGPoint(x: 8, y: 7)); p.addLine(to: CGPoint(x: 8, y: 4)); p.addLine(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 14, y: 7)) }
      else { p.move(to: CGPoint(x: 3, y: 1)); p.addLine(to: CGPoint(x: 4.3, y: 16.2)); p.addLine(to: CGPoint(x: 17.7, y: 16.2)); p.addLine(to: CGPoint(x: 19, y: 1)); p.move(to: CGPoint(x: 8.5, y: 5)); p.addLine(to: CGPoint(x: 8.5, y: 13)); p.move(to: CGPoint(x: 13.5, y: 5)); p.addLine(to: CGPoint(x: 13.5, y: 13)) }
      p.lineWidth = 1.8; p.lineCapStyle = .round; p.lineJoinStyle = .round
      UIColor.black.setStroke(); p.stroke()
    }.withRenderingMode(.alwaysTemplate)
  }
  func textViewDidChange(_ t: UITextView) { textChanged(); findMention() }
  func textViewDidChangeSelection(_ t: UITextView) { findMention() }
  // "@ki" just before the cursor: the people whose name starts so — tap one to put "@Kiran Rao " in
  private func findMention() {
    let ns = box.text as NSString, caret = box.selectedRange.location
    guard caret <= ns.length, !people.isEmpty else { showMentions([]); return }
    let before = ns.substring(to: caret)
    guard let at = before.range(of: "@", options: .backwards) else { showMentions([]); return }
    let word = String(before[at.upperBound...])
    let startOK = at.lowerBound == before.startIndex || before[before.index(before: at.lowerBound)].isWhitespace
    guard startOK, !word.contains("\n"), word.count <= 20 else { showMentions([]); return }
    mentionQ = (NSRange(at.lowerBound..<before.endIndex, in: before), word)
    let q = word.lowercased()
    showMentions(people.filter { q.isEmpty || $0.1.lowercased().hasPrefix(q) || $0.1.lowercased().contains(" " + q) }.prefix(4).map { $0 })
  }
  private func showMentions(_ list: [(String, String)]) {
    mentionV.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (id, name) in list {
      var c = UIButton.Configuration.plain()
      c.title = name; c.baseForegroundColor = .label; c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 56, bottom: 0, trailing: 16)
      let b = UIButton(configuration: c); b.contentHorizontalAlignment = .leading
      b.heightAnchor.constraint(equalToConstant: 44).isActive = true
      let a = Avatar(frame: CGRect(x: 14, y: 6, width: 32, height: 32)); a.set(person: Talk.shared.people[id]); a.isUserInteractionEnabled = false; b.addSubview(a)
      b.addAction(UIAction { [weak self] _ in self?.pick(id, name) }, for: .touchUpInside)
      mentionV.addArrangedSubview(b)
    }
    let was = mentionV.isHidden
    mentionV.isHidden = list.isEmpty
    if was != mentionV.isHidden || !list.isEmpty { invalidateIntrinsicContentSize(); setNeedsLayout() }
  }
  private func pick(_ id: String, _ name: String) {
    guard let r = mentionQ?.0 else { return }
    let ns = box.text as NSString
    box.text = ns.replacingCharacters(in: r, with: "@" + name + " ")
    box.selectedRange = NSRange(location: r.location + name.utf16.count + 2, length: 0)
    picked[id] = name
    UISelectionFeedbackGenerator().selectionChanged()
    showMentions([]); textChanged()
  }
  func textChanged() {
    place.isHidden = !box.text.isEmpty
    let h = min(130, max(30, ceil(box.sizeThatFits(CGSize(width: max(100, box.bounds.width), height: 400)).height)))
    box.isScrollEnabled = h >= 130
    if h != boxH { boxH = h; invalidateIntrinsicContentSize() }
    UIView.animate(withDuration: 0.15) { self.setNeedsLayout(); self.layoutIfNeeded() }
  }
  private func sendNow() {
    let t = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    // (the people picked with @ whose name is still in the words)
    let ms = picked.filter { t.contains("@" + $0.value) }.map { $0.key }
    box.text = ""; picked = [:]; showMentions([]); textChanged()
    onSend?(t, ms)
  }
  func setReply(_ r: (String, String)?, editing: Bool, ink: UIColor = Look.accent) {
    replyV.isHidden = r == nil
    replyName.text = r?.0; replyText.text = r?.1
    replyBar.backgroundColor = editing ? .systemOrange : ink; replyName.textColor = editing ? .systemOrange : ink
    if r == nil && editing == false && box.text.isEmpty == false && replyName.text == "Editing" { box.text = ""; textChanged() }
    invalidateIntrinsicContentSize(); setNeedsLayout()
  }
}

// the reactions you used lately on this phone (newest first) — for the bar after the seven quick ones
enum RecentReactions {
  private static let key = "talk.recentReactions"
  static let quick = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🔥"]
  static var list: [String] { (UserDefaults.standard.stringArray(forKey: key) ?? []) }
  static func used(_ e: String) {
    var l = list.filter { $0 != e }; l.insert(e, at: 0)
    UserDefaults.standard.set(Array(l.prefix(24)), forKey: key)
  }
  // the bar's emojis: the seven, then the lately used that aren't among them — never one twice
  static var bar: [String] { quick + list.filter { !quick.contains($0) } }
}

// the glass capsule: Apple's glass (iOS 26; a thick material before), the emojis scrolling sideways, + at its end
final class ReactBar: UIView {
  private let glass: UIVisualEffectView
  private let scroll = UIScrollView(), row = UIStackView(), plus = UIButton(type: .system)
  private let pick: (String?) -> Void
  init(mine: String?, pick: @escaping (String?) -> Void) {
    self.pick = pick
    if #available(iOS 26.0, *) { glass = UIVisualEffectView(effect: UIGlassEffect()) } else { glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial)) }
    super.init(frame: .zero)
    glass.layer.cornerRadius = 27; glass.layer.cornerCurve = .continuous; glass.clipsToBounds = true
    layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.14; layer.shadowRadius = 14; layer.shadowOffset = CGSize(width: 0, height: 6)
    addSubview(glass)
    scroll.showsHorizontalScrollIndicator = false; scroll.alwaysBounceHorizontal = true
    row.axis = .horizontal; row.spacing = 2; row.alignment = .center
    for e in RecentReactions.bar {
      let b = UIButton(type: .custom)
      b.setTitle(e, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 27)
      b.widthAnchor.constraint(equalToConstant: 42).isActive = true; b.heightAnchor.constraint(equalToConstant: 42).isActive = true
      b.layer.cornerRadius = 21
      if e == mine { b.backgroundColor = UIColor.label.withAlphaComponent(0.1) }
      b.accessibilityLabel = "React " + e
      b.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); RecentReactions.used(e); self?.pick(e) }, for: .touchUpInside)
      row.addArrangedSubview(b)
    }
    scroll.addSubview(row); glass.contentView.addSubview(scroll)
    var pc = UIButton.Configuration.gray()
    pc.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)); pc.cornerStyle = .capsule; pc.contentInsets = .zero
    pc.baseForegroundColor = .label
    plus.configuration = pc; plus.accessibilityLabel = "More reactions"
    plus.addAction(UIAction { [weak self] _ in self?.pick(nil) }, for: .touchUpInside)
    glass.contentView.addSubview(plus)
  }
  required init?(coder: NSCoder) { fatalError() }
  // the emojis (and +) pop in one after another as the strip grows
  private var pops: [UIView] { row.arrangedSubviews + [plus] }
  func prepareToPop() { for v in pops { v.alpha = 0; v.transform = CGAffineTransform(scaleX: 0.3, y: 0.3) } }
  func pop() {
    for (i, v) in pops.enumerated() {
      UIView.animate(withDuration: 0.38, delay: 0.06 + 0.025 * Double(min(i, 10)), usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction]) { v.alpha = 1; v.transform = .identity }
    }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    glass.frame = bounds
    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 27).cgPath
    plus.frame = CGRect(x: bounds.width - 48, y: 7, width: 40, height: 40)
    scroll.frame = CGRect(x: 6, y: 0, width: bounds.width - 58, height: bounds.height)
    let w = row.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
    row.frame = CGRect(x: 0, y: 6, width: w, height: 42); scroll.contentSize = CGSize(width: w, height: bounds.height)
  }
}

// + : Apple's sheet — the seven quick reactions on top, iPhone's own emoji keyboard under them (search, Frequently Used,
// every category); any emoji: it reacts and the sheet goes
final class EmojiSheet: UIViewController, UITextViewDelegate {
  private let mine: String?, done: (String) -> Void
  private let box = EmojiBox()
  init(mine: String?, done: @escaping (String) -> Void) { self.mine = mine; self.done = done; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    title = "React"
    navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let row = UIStackView(); row.axis = .horizontal; row.distribution = .equalSpacing; row.alignment = .center
    for e in RecentReactions.quick {
      let b = UIButton(type: .custom); b.setTitle(e, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 32)
      b.layer.cornerRadius = 22; if e == mine { b.backgroundColor = UIColor.label.withAlphaComponent(0.1) }
      b.widthAnchor.constraint(equalToConstant: 44).isActive = true; b.heightAnchor.constraint(equalToConstant: 44).isActive = true
      b.addAction(UIAction { [weak self] _ in self?.chose(e) }, for: .touchUpInside)
      row.addArrangedSubview(b)
    }
    row.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(row)
    // (the box only brings iPhone's emoji keyboard up; what's typed into it is the reaction)
    box.emoji = true; box.delegate = self; box.alpha = 0.02; box.autocorrectionType = .no
    box.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(box)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      box.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 4), box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      box.widthAnchor.constraint(equalToConstant: 2), box.heightAnchor.constraint(equalToConstant: 2)])
  }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); box.becomeFirstResponder() }
  func textViewDidChange(_ t: UITextView) {
    guard let c = t.text.first(where: { $0.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x238C } }) else { t.text = ""; return }
    chose(String(c))
  }
  private func chose(_ e: String) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    RecentReactions.used(e)
    done(e); dismiss(animated: true)
  }
}

// ---------- searching: the bar above the keyboard (the design's board "Search in a chat") — ˄ ˅ in a glass capsule
// and how many matches; it stays at the bottom when the keyboard goes down ----------
final class FindBar: UIView {
  let up = UIButton(type: .system), down = UIButton(type: .system)
  private let countL = UILabel(), line = UIView()
  private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  private let capsule: UIVisualEffectView = {
    if #available(iOS 26.0, *) { return UIVisualEffectView(effect: UIGlassEffect()) }
    return UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
  }()
  override init(frame: CGRect) {
    super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 56))
    autoresizingMask = .flexibleHeight
    blur.contentView.backgroundColor = UIColor { Look.chatBg.resolvedColor(with: $0).withAlphaComponent(0.62) }
    addSubview(blur)
    line.backgroundColor = .separator; addSubview(line)
    capsule.layer.cornerRadius = 20; capsule.layer.cornerCurve = .continuous; capsule.clipsToBounds = true
    addSubview(capsule)
    let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    up.setImage(UIImage(systemName: "chevron.up", withConfiguration: cfg), for: .normal); up.accessibilityLabel = "Earlier match"
    down.setImage(UIImage(systemName: "chevron.down", withConfiguration: cfg), for: .normal); down.accessibilityLabel = "Later match"
    [up, down].forEach { $0.tintColor = .label; capsule.contentView.addSubview($0) }
    countL.font = .systemFont(ofSize: 16); countL.textColor = .secondaryLabel
    addSubview(countL)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 56) }
  override func layoutSubviews() {
    super.layoutSubviews()
    blur.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + 420)
    line.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / max(1, traitCollection.displayScale))
    capsule.frame = CGRect(x: 16, y: 8, width: 100, height: 40)
    up.frame = CGRect(x: 0, y: 0, width: 50, height: 40); down.frame = CGRect(x: 50, y: 0, width: 50, height: 40)
    countL.frame = CGRect(x: 132, y: 8, width: bounds.width - 148, height: 40)
  }
  // (n of total; nothing typed yet: no words; typed and none: "No matches")
  func show(_ n: Int, _ total: Int, typed: Bool) {
    let t = !typed ? "" : total == 0 ? "No matches" : "\(n) of \(total) \(total == 1 ? "match" : "matches")"
    if countL.text != t { UIView.transition(with: countL, duration: 0.15, options: .transitionCrossDissolve) { self.countL.text = t } }
    up.isEnabled = total > 0 && n > 1
    down.isEnabled = total > 0 && n < total
  }
}


// the hold's preview (trial, Haris 2026-11-12): the bubble's picture at its own size — iPhone shrinks it if it won't fit
// (the bubble itself as it looks — iPhone's own snapshot of it, at its own size, in the middle of a clear margin: a
//  picture of it was shown enlarged and cut on a reply, Haris 2026-11-12; iPhone's rounding falls on the margin)
final class BubblePreview: UIViewController {
  static let pad: CGFloat = 12
  let shot: UIView
  init(_ shot: UIView) {
    self.shot = shot; super.init(nibName: nil, bundle: nil)
    preferredContentSize = CGSize(width: shot.bounds.width + 2 * BubblePreview.pad, height: shot.bounds.height + 2 * BubblePreview.pad)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() { let v = UIView(); v.backgroundColor = .clear; v.addSubview(shot); view = v }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); shot.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY) }
}
