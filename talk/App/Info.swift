import UIKit

/* Message info (the approved design, boards 28 / 29 / 30) — your own message swiped left (or hold › Info).
   Apple's pushed page: ‹ and "Message info" in Apple's bar; the day chip and the message itself as it shows in the chat;
   then Apple's inset groups — READ BY (blue ✓✓) and DELIVERED TO (grey ✓✓): each person's picture, name, the date and the
   time. A client contact sees only DELIVERED TO, with each person's role, and the line that who has read it isn't shown.
   Drawn from the phone's copy (works offline); live — a read or a delivery arriving changes only that row. */
final class MessageInfoVC: UIViewController {
  private let group: String, id: String
  private var cv: UICollectionView!
  private var data: UICollectionViewDiffableDataSource<String, String>!
  private var sigs: [String: Int] = [:]
  private let bubbleCell = BubbleCell(style: .default, reuseIdentifier: nil)
  private lazy var bubbleH = bubbleCell.heightAnchor.constraint(equalToConstant: 60)

  init(group: String, id: String) { self.group = group; self.id = id; super.init(nibName: nil, bundle: nil); if #unavailable(iOS 18) { hidesBottomBarWhenPushed = true } }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); TabBarHide.arrived(self) }
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); TabBarHide.leaving(self) }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Message info"
    navigationItem.largeTitleDisplayMode = .never
    view.backgroundColor = Look.chatBg
    let layout = UICollectionViewCompositionalLayout { [weak self] i, env in
      let top = self?.data?.snapshot().sectionIdentifiers[safe: i] == "top"
      var c = UICollectionLayoutListConfiguration(appearance: top ? .plain : .insetGrouped)
      c.backgroundColor = .clear; c.showsSeparators = !top
      c.headerMode = top ? .none : .supplementary
      c.footerMode = (!top && self?.data?.snapshot().sectionIdentifiers[safe: i] == "got" && Talk.shared.isContact) ? .supplementary : .none
      c.separatorConfiguration.color = UIColor.separator.withAlphaComponent(0.6)
      c.separatorConfiguration.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: 42, bottom: 0, trailing: 0)
      let s = NSCollectionLayoutSection.list(using: c, layoutEnvironment: env)
      if top { s.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0) }
      return s
    }
    cv = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
    cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cv.backgroundColor = .clear
    view.addSubview(cv)

    // the message, as the chat shows it (its day chip over it, a line under it)
    let msgReg = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, _ in
      guard let self = self else { return }
      cell.backgroundConfiguration = .clear()
      if self.bubbleCell.superview !== cell.contentView {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let chip = ChipLabel(); chip.tag = 1
        chip.font = .systemFont(ofSize: 13, weight: .semibold); chip.textColor = .label; chip.backgroundColor = Look.dayChip
        chip.layer.cornerRadius = 8; chip.layer.masksToBounds = true; chip.textAlignment = .center
        let line = UIView(); line.tag = 2; line.backgroundColor = UIColor.separator
        [chip, self.bubbleCell, line].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview($0) }
        NSLayoutConstraint.activate([
          chip.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 34), chip.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
          chip.heightAnchor.constraint(equalToConstant: 20),
          self.bubbleCell.topAnchor.constraint(equalTo: chip.bottomAnchor, constant: 4), self.bubbleH,
          self.bubbleCell.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor), self.bubbleCell.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
          line.topAnchor.constraint(equalTo: self.bubbleCell.bottomAnchor, constant: 11), line.heightAnchor.constraint(equalToConstant: 0.5),
          line.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor), line.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
          line.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)])
      }
      (cell.contentView.viewWithTag(1) as? UILabel)?.text = self.msg.map { Look.day($0.at) }
      self.fillBubble()
    }
    // a person: picture, name (a client's view: the role under it), the date and the time
    let rowReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
      guard let self = self else { return }
      let pid = String(key.dropFirst(2)), T = Talk.shared, p = T.people[pid]
      var c = UIListContentConfiguration.cell()
      c.text = p?.name ?? "Someone"; c.textProperties.font = .systemFont(ofSize: 17)
      if T.isContact, let r = p?.role, !r.isEmpty { c.secondaryText = r; c.secondaryTextProperties.font = .systemFont(ofSize: 13); c.secondaryTextProperties.color = .secondaryLabel }
      c.image = MessageInfoVC.face(pid) { [weak self] in self?.redraw(key) }
      c.imageProperties.maximumSize = CGSize(width: 35, height: 35); c.imageProperties.reservedLayoutSize = CGSize(width: 35, height: 35)
      c.imageProperties.cornerRadius = 17.5
      c.imageToTextPadding = 7
      c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6.5, leading: 17, bottom: 6.5, trailing: 20)
      cell.contentConfiguration = c
      var b = UIBackgroundConfiguration.listGroupedCell(); b.backgroundColor = Look.dyn(0x1A1A1A, 0xFFFFFF); cell.backgroundConfiguration = b
      let at = key.hasPrefix("r:") ? self.log.time(self.log.readAt, pid, self.id) : self.log.time(self.log.gotAt, pid, self.id)
      let when = UILabel(); when.attributedText = MessageInfoVC.when(at); when.sizeToFit()
      cell.accessories = [.customView(configuration: .init(customView: when, placement: .trailing(), reservedLayoutWidth: .actual))]
    }
    let headReg = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, ip in
      guard let s = self?.data.snapshot().sectionIdentifiers[safe: ip.section] else { return }
      var c = UIListContentConfiguration.groupedHeader()
      c.text = s == "read" ? "READ BY" : "DELIVERED TO"
      c.textProperties.font = .systemFont(ofSize: 15); c.textProperties.color = .secondaryLabel
      c.image = Ticks.image(s == "read" ? Look.dyn(0x5AA9FF, 0x007AFF) : .systemGray).withRenderingMode(.alwaysOriginal)
      c.imageToTextPadding = 8
      c.directionalLayoutMargins.leading = 16
      cell.contentConfiguration = c
    }
    let footReg = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { cell, _, _ in
      var c = UIListContentConfiguration.groupedFooter()
      c.text = "You see when it reached each person. Who has read it isn’t shown."
      cell.contentConfiguration = c
    }
    data = UICollectionViewDiffableDataSource<String, String>(collectionView: cv) { cv, ip, key in
      key == "msg" ? cv.dequeueConfiguredReusableCell(using: msgReg, for: ip, item: key) : cv.dequeueConfiguredReusableCell(using: rowReg, for: ip, item: key)
    }
    data.supplementaryViewProvider = { cv, kind, ip in
      kind == UICollectionView.elementKindSectionHeader ? cv.dequeueConfiguredReusableSupplementary(using: headReg, for: ip) : cv.dequeueConfiguredReusableSupplementary(using: footReg, for: ip)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .talkGroup, object: nil)
    reload(animated: false)
  }

  private var log: GroupLog { Talk.shared.log(group) }
  private var msg: Msg? { log.msgs.first { $0.id == id } }
  private func fillBubble() {
    guard let m = msg, let g = Talk.shared.groups[group] else { return }
    bubbleCell.set(m, group: g, log: log, run: Run(first: true, last: true))
    // (its exact height for the page's width, as the chat's list works it out)
    let w = view.bounds.width
    bubbleCell.frame.size.width = w
    bubbleH.constant = ceil(bubbleCell.systemLayoutSizeFitting(CGSize(width: w, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
  }
  @objc private func changed(_ n: Notification) {
    guard (n.object as? String) == group else { return }
    guard let m = msg, !m.deleted else {
      if navigationController?.topViewController === self { toast("That message was deleted"); navigationController?.popViewController(animated: true) }
      return
    }
    fillBubble()
    reload(animated: true)
  }
  private func redraw(_ key: String) {
    var s = data.snapshot(); guard s.indexOfItem(key) != nil else { return }
    s.reconfigureItems([key]); data.apply(s, animatingDifferences: false)
  }
  // who has read it (staff only) — then whose phone has it; each person once, the earliest first
  private func reload(animated: Bool) {
    let T = Talk.shared, l = log
    let others = (T.groups[group]?.members ?? []).filter { $0 != T.me?.id }
    var read: [(String, Double)] = [], got: [(String, Double)] = []
    for p in others {
      if !T.isContact, l.read(p, id) { read.append((p, l.time(l.readAt, p, id) ?? 0)); continue }
      if let t = l.time(l.gotAt, p, id) { got.append((p, t)) } else if T.isContact, let t = l.time(l.readAt, p, id) { got.append((p, t)) }
    }
    read.sort { $0.1 < $1.1 }; got.sort { $0.1 < $1.1 }
    var s = NSDiffableDataSourceSnapshot<String, String>()
    s.appendSections(["top"]); s.appendItems(["msg"], toSection: "top")
    if !read.isEmpty { s.appendSections(["read"]); s.appendItems(read.map { "r:" + $0.0 }, toSection: "read") }
    if !got.isEmpty || T.isContact { s.appendSections(["got"]); s.appendItems(got.map { "d:" + $0.0 }, toSection: "got") }
    // (only a row that shows something new is drawn again)
    var newSigs: [String: Int] = [:]
    for k in s.itemIdentifiers where k != "msg" {
      let pid = String(k.dropFirst(2))
      var h = Hasher(); h.combine(k.hasPrefix("r:") ? l.time(l.readAt, pid, id) : l.time(l.gotAt, pid, id)); h.combine(T.people[pid]?.name); h.combine(T.people[pid]?.picture)
      newSigs[k] = h.finalize()
    }
    let old = data.snapshot()
    s.reconfigureItems(s.itemIdentifiers.filter { k in k != "msg" && old.indexOfItem(k) != nil && sigs[k] != newSigs[k] })
    sigs = newSigs
    data.apply(s, animatingDifferences: animated && old.numberOfItems > 0)
  }

  // "11/11/2026  9:45 PM" — the date grey, the time as the name
  static func when(_ at: Double?) -> NSAttributedString {
    guard let at = at, at > 0 else { return NSAttributedString(string: "—", attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel]) }
    let d = DateFormatter(); d.dateStyle = .short; d.timeStyle = .none
    let a = NSMutableAttributedString(string: d.string(from: Date(timeIntervalSince1970: at / 1000)), attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel])
    let p = NSMutableParagraphStyle(); p.alignment = .right
    a.append(NSAttributedString(string: "  "))
    a.append(NSAttributedString(string: Look.clock(at), attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.label]))
    a.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: a.length))
    return a
  }
  // a person's picture as an image for Apple's cell: their photo, else their initials on their E11 Console colour
  private static var faces: [String: UIImage] = [:]
  static func face(_ pid: String, loaded: @escaping () -> Void) -> UIImage {
    let p = Talk.shared.people[pid]
    if let ph = p?.picture, let i = faces[ph] { return i }
    let size = CGSize(width: 70, height: 70)
    let initials = UIGraphicsImageRenderer(size: size).image { _ in
      Look.person(pid).setFill(); UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
      let t = NSAttributedString(string: Look.initials(p?.name ?? ""), attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: UIColor.white])
      let ts = t.size(); t.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2))
    }
    if let ph = p?.picture {
      Net.shared.picture(ph) { i in
        guard let i = i else { return }
        let round = UIGraphicsImageRenderer(size: size).image { _ in UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip(); i.draw(in: CGRect(origin: .zero, size: size)) }
        let first = faces[ph] == nil
        faces[ph] = round
        if first { DispatchQueue.main.async { loaded() } }
      }
      if let i = faces[ph] { return i }
    }
    return initials
  }
}

// the day chip's words with room either side
final class ChipLabel: UILabel {
  override var intrinsicContentSize: CGSize { let s = super.intrinsicContentSize; return CGSize(width: s.width + 24, height: s.height) }
}

extension Array {
  subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
