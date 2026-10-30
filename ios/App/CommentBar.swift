// The comment box on a task's Comments (iPhone app 17+, Haris 2026-10-30): iPhone's own text box on the keyboard,
// like Messages — it rides with the keyboard (pinned to the keyboard layout guide), so the page never moves for it.
// + attach (the page's own attach: Photos / Camera / Files), the waiting files as tiles with ×, an upload ring,
// @mentions (people with photos above the box), "Replying to …" with ×, Bold / Italic / Underline from iOS's own
// text menu (Format). The page keeps the comments list, the draft and the sending (phone.js NativeComment):
// what's typed goes to it as runs — [{ t, b, i, u }] for text, { m: userId, t: "@Name" } for a mention.
import UIKit

final class CommentBar: UIView, UITextViewDelegate, UITableViewDataSource, UITableViewDelegate {
  static let MENTION = NSAttributedString.Key("e11Mention")   // (value: "<userId>\u{1}<label>")
  var onEvent: (([String: Any]) -> Void)?
  var onHeight: ((CGFloat) -> Void)?
  private(set) var key = ""
  private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  private let line = UIView()
  private let stack = UIStackView()
  private let replyRow = UIView()
  private let replyLabel = UILabel()
  private let replyX = UIButton(type: .system)
  private let tilesScroll = UIScrollView()
  private let tilesStack = UIStackView()
  private let row = UIStackView()
  private let plus = UIButton(type: .system)
  private let box = UIView()
  let text = UITextView()
  private let hint = UILabel()
  private let send = UIButton(type: .system)
  private var textH: NSLayoutConstraint?
  private var people: [[String: Any]] = []
  private var pics: [String: UIImage] = [:]
  private let mentionCard = UIView()
  private let mentionTable = UITableView(frame: .zero, style: .plain)
  private var matches: [[String: Any]] = []
  private var mentionRange: NSRange?
  private var mentionH: NSLayoutConstraint?
  var accent = UIColor(red: 0.36, green: 0.29, blue: 0.94, alpha: 1)
  private var uploading = false
  private var hasFiles = false
  private var draftTimer: Timer?
  private var lastH: CGFloat = -1
  private static let FONT: CGFloat = 16
  private static let MAX_TEXT: CGFloat = 124   // (about five lines, then it scrolls inside)
  private var base: [NSAttributedString.Key: Any] { [.font: UIFont.systemFont(ofSize: CommentBar.FONT), .foregroundColor: UIColor.label] }

  override init(frame: CGRect) {
    super.init(frame: frame)
    build()
  }
  required init?(coder: NSCoder) { fatalError() }

  private func build() {
    clipsToBounds = false
    blur.translatesAutoresizingMaskIntoConstraints = false
    addSubview(blur)
    line.backgroundColor = .separator
    line.translatesAutoresizingMaskIntoConstraints = false
    addSubview(line)
    // (the background runs on under the bar — over the home-bar strip, and behind the keyboard)
    NSLayoutConstraint.activate([
      blur.topAnchor.constraint(equalTo: topAnchor), blur.leadingAnchor.constraint(equalTo: leadingAnchor),
      blur.trailingAnchor.constraint(equalTo: trailingAnchor), blur.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 120),
      line.topAnchor.constraint(equalTo: topAnchor), line.leadingAnchor.constraint(equalTo: leadingAnchor),
      line.trailingAnchor.constraint(equalTo: trailingAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
    ])
    stack.axis = .vertical; stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
    ])
    // Replying to …  ×
    replyRow.backgroundColor = .tertiarySystemFill
    replyRow.layer.cornerRadius = 12; replyRow.layer.cornerCurve = .continuous
    replyLabel.font = .systemFont(ofSize: 13); replyLabel.textColor = .secondaryLabel; replyLabel.lineBreakMode = .byTruncatingTail
    replyX.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
    replyX.tintColor = .secondaryLabel
    replyX.addAction(UIAction { [weak self] _ in self?.onEvent?(["ev": "cancelReply"]) }, for: .touchUpInside)
    [replyLabel, replyX].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; replyRow.addSubview($0) }
    NSLayoutConstraint.activate([
      replyRow.heightAnchor.constraint(equalToConstant: 32),
      replyLabel.leadingAnchor.constraint(equalTo: replyRow.leadingAnchor, constant: 12), replyLabel.centerYAnchor.constraint(equalTo: replyRow.centerYAnchor),
      replyX.leadingAnchor.constraint(greaterThanOrEqualTo: replyLabel.trailingAnchor, constant: 8),
      replyX.trailingAnchor.constraint(equalTo: replyRow.trailingAnchor, constant: -6), replyX.centerYAnchor.constraint(equalTo: replyRow.centerYAnchor),
      replyX.widthAnchor.constraint(equalToConstant: 30), replyX.heightAnchor.constraint(equalToConstant: 30),
    ])
    replyRow.isHidden = true
    stack.addArrangedSubview(replyRow)
    // the waiting files
    tilesScroll.showsHorizontalScrollIndicator = false
    tilesScroll.clipsToBounds = false
    tilesStack.axis = .horizontal; tilesStack.spacing = 8; tilesStack.alignment = .center
    tilesStack.translatesAutoresizingMaskIntoConstraints = false
    tilesScroll.addSubview(tilesStack)
    NSLayoutConstraint.activate([
      tilesScroll.heightAnchor.constraint(equalToConstant: 62),
      tilesStack.leadingAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.leadingAnchor, constant: 46),
      tilesStack.trailingAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.trailingAnchor),
      tilesStack.topAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.topAnchor),
      tilesStack.bottomAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.bottomAnchor),
      tilesStack.heightAnchor.constraint(equalTo: tilesScroll.frameLayoutGuide.heightAnchor),
    ])
    tilesScroll.isHidden = true
    stack.addArrangedSubview(tilesScroll)
    // + · the text box · send
    row.axis = .horizontal; row.spacing = 8; row.alignment = .bottom
    plus.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
    plus.tintColor = .label
    plus.backgroundColor = .tertiarySystemFill
    plus.layer.cornerRadius = 18
    plus.addAction(UIAction { [weak self] _ in guard let self else { return }; self.onEvent?(["ev": "attach", "key": self.key]) }, for: .touchUpInside)
    box.backgroundColor = .systemBackground
    box.layer.cornerRadius = 18; box.layer.cornerCurve = .continuous
    box.layer.borderWidth = 1; box.layer.borderColor = UIColor.separator.cgColor
    text.font = .systemFont(ofSize: CommentBar.FONT)
    text.backgroundColor = .clear
    text.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    text.isScrollEnabled = false
    text.allowsEditingTextAttributes = true   // (select text → Format: Bold, Italic, Underline)
    text.delegate = self
    text.typingAttributes = base
    hint.font = .systemFont(ofSize: CommentBar.FONT); hint.textColor = .placeholderText
    hint.text = "Write a comment"
    send.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
    send.tintColor = .white
    send.layer.cornerRadius = 17
    send.addAction(UIAction { [weak self] _ in self?.sendNow() }, for: .touchUpInside)
    [text, hint].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; box.addSubview($0) }
    [plus, box, send].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addArrangedSubview($0) }
    let th = text.heightAnchor.constraint(equalToConstant: 36)
    textH = th
    NSLayoutConstraint.activate([
      plus.widthAnchor.constraint(equalToConstant: 36), plus.heightAnchor.constraint(equalToConstant: 36),
      send.widthAnchor.constraint(equalToConstant: 34), send.heightAnchor.constraint(equalToConstant: 34),
      text.topAnchor.constraint(equalTo: box.topAnchor), text.bottomAnchor.constraint(equalTo: box.bottomAnchor),
      text.leadingAnchor.constraint(equalTo: box.leadingAnchor), text.trailingAnchor.constraint(equalTo: box.trailingAnchor), th,
      hint.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 15), hint.centerYAnchor.constraint(equalTo: box.topAnchor, constant: 18),
      hint.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -10),
    ])
    stack.addArrangedSubview(row)
    // @mentions: people above the box
    mentionCard.backgroundColor = .secondarySystemGroupedBackground
    mentionCard.layer.cornerRadius = 14; mentionCard.layer.cornerCurve = .continuous
    mentionCard.layer.shadowColor = UIColor.black.cgColor; mentionCard.layer.shadowOpacity = 0.18
    mentionCard.layer.shadowRadius = 14; mentionCard.layer.shadowOffset = CGSize(width: 0, height: 4)
    mentionTable.dataSource = self; mentionTable.delegate = self
    mentionTable.backgroundColor = .clear
    mentionTable.layer.cornerRadius = 14; mentionTable.clipsToBounds = true
    mentionTable.rowHeight = 48
    mentionTable.translatesAutoresizingMaskIntoConstraints = false
    mentionCard.addSubview(mentionTable)
    mentionCard.translatesAutoresizingMaskIntoConstraints = false
    mentionCard.isHidden = true
    addSubview(mentionCard)
    let mh = mentionCard.heightAnchor.constraint(equalToConstant: 0)
    mentionH = mh
    NSLayoutConstraint.activate([
      mentionCard.bottomAnchor.constraint(equalTo: topAnchor, constant: -6),
      mentionCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), mentionCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), mh,
      mentionTable.topAnchor.constraint(equalTo: mentionCard.topAnchor), mentionTable.bottomAnchor.constraint(equalTo: mentionCard.bottomAnchor),
      mentionTable.leadingAnchor.constraint(equalTo: mentionCard.leadingAnchor), mentionTable.trailingAnchor.constraint(equalTo: mentionCard.trailingAnchor),
    ])
    refresh()
  }

  // (the people list sits above the bar, outside it: taps there still belong to it)
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    if !mentionCard.isHidden && mentionCard.frame.contains(point) { return true }
    return super.point(inside: point, with: event)
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    fitText()
    if abs(bounds.height - lastH) > 0.5 { lastH = bounds.height; onHeight?(bounds.height) }
  }

  /* ---------- from the page ---------- */
  func apply(_ a: [String: Any]) {
    if let c = NativeSheetVC.color(a["accent"]) { accent = c }
    if let ppl = a["people"] as? [[String: Any]] {
      people = ppl
      pics = [:]
      for p in ppl {
        guard let id = p["id"] as? String else { continue }
        let per = p["person"] as? [String: Any]
        pics[id] = roundPic(NativeSheetVC.photo(per), initials: per?["initials"] as? String, color: NativeSheetVC.color(per?["color"]), size: 30)
      }
    }
    if let k = a["key"] as? String {
      if k != key || a["runs"] != nil {
        key = k
        setRuns(a["runs"] as? [[String: Any]] ?? [])
        hideMentions()
      }
      hint.text = a["placeholder"] as? String ?? "Write a comment"
      if let r = a["replying"] as? [String: Any] {
        let s = NSMutableAttributedString(string: "Replying to ", attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.secondaryLabel])
        s.append(NSAttributedString(string: r["name"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.label]))
        replyLabel.attributedText = s
        replyRow.isHidden = false
      } else { replyRow.isHidden = true }
      setTiles(a["files"] as? [[String: Any]] ?? [], uploading: a["uploading"] as? [String: Any])
    }
    if (a["focus"] as? Bool) == true { text.becomeFirstResponder() }
    if (a["blur"] as? Bool) == true { text.resignFirstResponder() }
    refresh()
  }

  /* ---------- what's typed ---------- */
  private func mentionString(id: String, label: String) -> NSAttributedString {
    NSAttributedString(string: label, attributes: [.font: UIFont.systemFont(ofSize: CommentBar.FONT, weight: .medium), .foregroundColor: accent,
                                                   .backgroundColor: accent.withAlphaComponent(0.12), CommentBar.MENTION: id + "\u{1}" + label])
  }
  private func setRuns(_ runs: [[String: Any]]) {
    let s = NSMutableAttributedString()
    for r in runs {
      let t = r["t"] as? String ?? ""
      if let m = r["m"] as? String { s.append(mentionString(id: m, label: t)); continue }
      var f = UIFont.systemFont(ofSize: CommentBar.FONT)
      var traits: UIFontDescriptor.SymbolicTraits = []
      if r["b"] != nil { traits.insert(.traitBold) }
      if r["i"] != nil { traits.insert(.traitItalic) }
      if !traits.isEmpty, let d = f.fontDescriptor.withSymbolicTraits(traits) { f = UIFont(descriptor: d, size: CommentBar.FONT) }
      var at: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: UIColor.label]
      if r["u"] != nil { at[.underlineStyle] = NSUnderlineStyle.single.rawValue }
      s.append(NSAttributedString(string: t, attributes: at))
    }
    text.attributedText = s
    text.typingAttributes = base
    refresh()
  }
  func runs() -> [[String: Any]] {
    var out: [[String: Any]] = []
    let s: NSAttributedString = text.attributedText ?? NSAttributedString()
    let all = s.string as NSString
    s.enumerateAttributes(in: NSRange(location: 0, length: s.length), options: []) { at, range, _ in
      let t = all.substring(with: range)
      if let m = at[CommentBar.MENTION] as? String {
        let id = String(m.split(separator: "\u{1}", maxSplits: 1).first ?? "")
        out.append(["m": id, "t": t]); return
      }
      var r: [String: Any] = ["t": t]
      if let f = at[.font] as? UIFont {
        let tr = f.fontDescriptor.symbolicTraits
        if tr.contains(.traitBold) { r["b"] = 1 }
        if tr.contains(.traitItalic) { r["i"] = 1 }
      }
      if let u = at[.underlineStyle] as? Int, u != 0 { r["u"] = 1 }
      out.append(r)
    }
    return out
  }
  private var isEmpty: Bool { (text.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private func refresh() {
    hint.isHidden = !(text.text ?? "").isEmpty
    let ready = !uploading && (!isEmpty || hasFiles)
    send.isHidden = isEmpty && !hasFiles && !uploading
    send.isEnabled = ready
    send.backgroundColor = ready ? accent : accent.withAlphaComponent(0.4)
    box.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
  }
  private func fitText() {
    let w = text.bounds.width > 0 ? text.bounds.width : max(200, bounds.width - 110)
    let need = ceil(text.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
    let h = min(max(36, need), CommentBar.MAX_TEXT)
    let scroll = need > CommentBar.MAX_TEXT
    if text.isScrollEnabled != scroll { text.isScrollEnabled = scroll }
    if let c = textH, abs(c.constant - h) > 0.5 { c.constant = h }
  }
  // (a mention that's been typed into isn't one any more; typing after a mention isn't part of it)
  private func tidyMentions() {
    guard let s = text.attributedText, s.length > 0 else { return }
    let m = NSMutableAttributedString(attributedString: s)
    var changed = false
    let all = s.string as NSString
    s.enumerateAttribute(CommentBar.MENTION, in: NSRange(location: 0, length: s.length), options: []) { v, range, _ in
      guard let v = v as? String else { return }
      let label = String(v.split(separator: "\u{1}", maxSplits: 1).dropFirst().first ?? "")
      if all.substring(with: range) != label {
        m.removeAttribute(CommentBar.MENTION, range: range); m.removeAttribute(.backgroundColor, range: range)
        m.addAttributes([.foregroundColor: UIColor.label, .font: UIFont.systemFont(ofSize: CommentBar.FONT)], range: range)
        changed = true
      }
    }
    if changed { let sel = text.selectedRange; text.attributedText = m; text.selectedRange = sel }
    plainTyping()
  }
  private func plainTyping() {
    if text.typingAttributes[CommentBar.MENTION] != nil {
      var t = text.typingAttributes
      t[CommentBar.MENTION] = nil; t[.backgroundColor] = nil; t[.foregroundColor] = UIColor.label; t[.font] = UIFont.systemFont(ofSize: CommentBar.FONT)
      text.typingAttributes = t
    }
  }
  func textViewDidChange(_ textView: UITextView) {
    tidyMentions()
    refresh()
    fitText()
    checkMention()
    draftTimer?.invalidate()
    draftTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
      guard let self else { return }
      self.onEvent?(["ev": "draft", "key": self.key, "runs": self.runs()])
    }
  }
  func textViewDidChangeSelection(_ textView: UITextView) { plainTyping(); checkMention() }
  private func sendNow() {
    guard !uploading, !isEmpty || hasFiles else { return }
    draftTimer?.invalidate()
    hideMentions()
    onEvent?(["ev": "send", "key": key, "runs": runs()])
  }
  // (self-test: type this, as if typed)
  func selfType(_ s: String) {
    text.attributedText = NSAttributedString(string: s, attributes: base)
    text.selectedRange = NSRange(location: (s as NSString).length, length: 0)
    textViewDidChange(text)
  }
  static func selfArgs() -> [String: Any] {
    let p1: [String: Any] = ["initials": "SA", "color": [124, 92, 255]]
    let p2: [String: Any] = ["initials": "OK", "color": [0, 160, 140]]
    var sara: [String: Any] = ["id": "u1", "name": "Sara Ahmed", "email": "sara@example.com", "role": "Production"]
    sara["person"] = p1
    var omar: [String: Any] = ["id": "u2", "name": "Omar Khan", "email": "omar@example.com", "role": "Account Manager"]
    omar["person"] = p2
    let file: [String: Any] = ["id": "f1", "name": "brief.pdf", "ext": "pdf"]
    var a: [String: Any] = ["show": true, "key": "selftest", "placeholder": "Write a reply", "p": 1]
    a["people"] = [sara, omar]
    a["replying"] = ["name": "Sara"] as [String: Any]
    a["files"] = [file]
    a["uploading"] = ["n": 1, "frac": 0.4] as [String: Any]
    a["runs"] = [[String: Any]]()
    return a
  }
  func geo() -> [String: Any] {
    guard let win = window else { return ["error": "not shown"] }
    let f = { (v: UIView) -> [CGFloat] in let r = v.convert(v.bounds, to: win); return [r.minX, r.minY, r.width, r.height] }
    return ["bar": f(self), "text": f(text), "mentions": mentionCard.isHidden ? [] : f(mentionCard), "matches": matches.count, "hidden": isHidden, "alpha": alpha]
  }
  // (the page has sent it: empty again, ready for the next one)
  func clear() { setRuns([]); hideMentions(); fitText() }

  /* ---------- @mentions ---------- */
  private func checkMention() {
    let sel = text.selectedRange
    guard sel.length == 0, !people.isEmpty, let all = text.text as NSString? else { return hideMentions() }
    let upto = all.substring(to: min(sel.location, all.length)) as NSString
    guard let re = try? NSRegularExpression(pattern: "(?:^|[\\s(])@([^\\s@]{0,30})$"),
          let m = re.firstMatch(in: upto as String, range: NSRange(location: 0, length: upto.length)) else { return hideMentions() }
    let qr = m.range(at: 1)
    let q = upto.substring(with: qr).lowercased()
    // (not inside a mention already made)
    if qr.location > 0, let s = text.attributedText, qr.location - 1 < s.length, s.attribute(CommentBar.MENTION, at: qr.location - 1, effectiveRange: nil) != nil { return hideMentions() }
    matches = Array(people.filter { p in
      q.isEmpty || ((p["name"] as? String) ?? "").lowercased().contains(q) || ((p["email"] as? String) ?? "").lowercased().contains(q)
    }.prefix(5))
    mentionRange = NSRange(location: qr.location - 1, length: qr.length + 1)
    if matches.isEmpty { return hideMentions() }
    mentionTable.reloadData()
    mentionH?.constant = CGFloat(matches.count) * 48
    mentionCard.isHidden = false
  }
  private func hideMentions() { mentionCard.isHidden = true; mentionRange = nil }
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { matches.count }
  func tableView(_ tableView: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let p = matches[ip.row]
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    var c = UIListContentConfiguration.valueCell()
    c.text = p["name"] as? String
    c.secondaryText = p["role"] as? String
    if let id = p["id"] as? String, let img = pics[id] {
      c.image = img
      c.imageProperties.maximumSize = CGSize(width: 30, height: 30)
      c.imageProperties.reservedLayoutSize = CGSize(width: 30, height: 30)
    }
    cell.contentConfiguration = c
    cell.backgroundColor = .clear
    return cell
  }
  func tableView(_ tableView: UITableView, didSelectRowAt ip: IndexPath) {
    tableView.deselectRow(at: ip, animated: false)
    guard let r = mentionRange, ip.row < matches.count, let id = matches[ip.row]["id"] as? String, let s = text.attributedText, NSMaxRange(r) <= s.length else { return hideMentions() }
    let label = "@" + ((matches[ip.row]["name"] as? String) ?? "")
    let ins = NSMutableAttributedString(attributedString: mentionString(id: id, label: label))
    ins.append(NSAttributedString(string: " ", attributes: base))
    let m = NSMutableAttributedString(attributedString: s)
    m.replaceCharacters(in: r, with: ins)
    text.attributedText = m
    text.selectedRange = NSRange(location: r.location + ins.length, length: 0)
    text.typingAttributes = base
    UISelectionFeedbackGenerator().selectionChanged()
    hideMentions()
    textViewDidChange(text)
  }

  /* ---------- the waiting files ---------- */
  private func setTiles(_ files: [[String: Any]], uploading up: [String: Any]?) {
    tilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for f in files { tilesStack.addArrangedSubview(tile(f)) }
    if let up {
      let n = max(1, (up["n"] as? NSNumber)?.intValue ?? 1)
      let frac = CGFloat((up["frac"] as? NSNumber)?.doubleValue ?? 0)
      for _ in 0..<n { tilesStack.addArrangedSubview(ringTile(frac)) }
    }
    uploading = up != nil
    hasFiles = !files.isEmpty
    tilesScroll.isHidden = files.isEmpty && up == nil
  }
  private func square() -> (UIView, UIView) {
    let wrap = UIView()
    wrap.translatesAutoresizingMaskIntoConstraints = false
    wrap.widthAnchor.constraint(equalToConstant: 62).isActive = true
    wrap.heightAnchor.constraint(equalToConstant: 62).isActive = true
    let sq = UIView(frame: CGRect(x: 0, y: 8, width: 54, height: 54))
    sq.layer.cornerRadius = 10; sq.layer.cornerCurve = .continuous; sq.clipsToBounds = true
    sq.backgroundColor = .tertiarySystemFill
    wrap.addSubview(sq)
    return (wrap, sq)
  }
  private func tile(_ f: [String: Any]) -> UIView {
    let (wrap, sq) = square()
    if let img = NativeSheetVC.photo(f["thumb"].map { ["photo": $0] }) {
      let iv = UIImageView(image: img); iv.contentMode = .scaleAspectFill; iv.frame = sq.bounds; sq.addSubview(iv)
      if (f["video"] as? Bool) == true {
        let play = UIImageView(image: UIImage(systemName: "play.fill")); play.tintColor = .white
        play.frame = CGRect(x: 19, y: 19, width: 16, height: 16); sq.addSubview(play)
      }
    } else {
      let l = UILabel(frame: sq.bounds.insetBy(dx: 4, dy: 4))
      l.text = ((f["ext"] as? String) ?? "file").uppercased(); l.font = .systemFont(ofSize: 12, weight: .bold)
      l.textColor = .secondaryLabel; l.textAlignment = .center; l.adjustsFontSizeToFitWidth = true
      sq.addSubview(l)
    }
    let x = UIButton(type: .custom)
    x.frame = CGRect(x: 42, y: 0, width: 20, height: 20)
    x.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)), for: .normal)
    x.tintColor = .white; x.backgroundColor = UIColor.black.withAlphaComponent(0.75); x.layer.cornerRadius = 10
    let id = f["id"] as? String ?? ""
    x.addAction(UIAction { [weak self] _ in guard let self else { return }; self.onEvent?(["ev": "removeFile", "key": self.key, "id": id]) }, for: .touchUpInside)
    wrap.addSubview(x)
    return wrap
  }
  private func ringTile(_ frac: CGFloat) -> UIView {
    let (wrap, sq) = square()
    let path = UIBezierPath(arcCenter: CGPoint(x: 27, y: 27), radius: 13, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true)
    let track = CAShapeLayer(); track.path = path.cgPath; track.fillColor = UIColor.clear.cgColor
    track.strokeColor = UIColor.quaternaryLabel.cgColor; track.lineWidth = 3
    let ring = CAShapeLayer(); ring.path = path.cgPath; ring.fillColor = UIColor.clear.cgColor
    ring.strokeColor = accent.cgColor; ring.lineWidth = 3; ring.lineCap = .round
    ring.strokeEnd = max(0.04, min(1, frac))
    sq.layer.addSublayer(track); sq.layer.addSublayer(ring)
    return wrap
  }
}
