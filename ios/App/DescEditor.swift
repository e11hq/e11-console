import UIKit

/* The task's description, edited on the phone (Haris, 2026-11-01 — mockup dm-mock 1): tap it and it's written right
   where it is, looking the same; above the keyboard B · I · U · bullets · numbers · @ · link; typing @ lists the people
   under it; Done (the corner button) saves it as the website keeps it (HTML with mentions) — /api/home/act desc. */
let MENTION_KEY = NSAttributedString.Key("e11User")
// a file pasted into the description: where it is in the words ("📎 name", blue; tapped, its preview) — its card under it
let FILEREF_KEY = NSAttributedString.Key("e11File")

enum DescEditor {
  // a pasted file in the description: a light grey chip — its icon in its kind's colour (pictures green, PDFs red,
  // videos purple, the rest blue, as the Files app), its name — one piece in the words (Haris 2026-11-02)
  static var dark = false   // (the page's look, set before drawing)
  static func kind(_ name: String) -> (String, UIColor) {
    let ext = (name as NSString).pathExtension.lowercased()
    if ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"].contains(ext) { return ("photo", .systemGreen) }
    if ext == "pdf" { return ("doc.richtext", .systemRed) }
    if ["mp4", "mov", "m4v", "webm", "avi", "mkv"].contains(ext) { return ("film", .systemPurple) }
    return ("doc", .systemBlue)
  }
  static func chip(_ f: [String: Any], size: CGFloat) -> NSAttributedString {
    let name = f["name"] as? String ?? ((f["path"] as? String).map { ($0 as NSString).lastPathComponent } ?? "File")
    let tc = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    let font = UIFont.systemFont(ofSize: size - 1, weight: .medium)
    // (still uploading: an upload arrow in grey, the name greyed — the real chip takes its place once it's up)
    let up = f["pending"] != nil
    let (sym, col) = up ? ("arrow.up.circle", UIColor.secondaryLabel) : kind(name)
    let icon = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: size - 3, weight: .semibold))?.withTintColor(col.resolvedColor(with: tc), renderingMode: .alwaysOriginal)
    let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingMiddle
    let ta: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: (up ? UIColor.secondaryLabel : UIColor.label).resolvedColor(with: tc), .paragraphStyle: para]
    let tw = min(ceil((name as NSString).size(withAttributes: ta).width), 210)
    let iw = icon?.size.width ?? 0, h = ceil(font.lineHeight) + 6
    let w = 8 + iw + 5 + tw + 10
    let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
      UIColor.tertiarySystemFill.resolvedColor(with: tc).setFill()
      UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: h / 2).fill()
      if let i = icon { i.draw(at: CGPoint(x: 8, y: (h - i.size.height) / 2)) }
      (name as NSString).draw(with: CGRect(x: 8 + iw + 5, y: (h - font.lineHeight) / 2, width: tw, height: font.lineHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: ta, context: nil)
    }
    let at = NSTextAttachment(); at.image = img
    let body = UIFont.systemFont(ofSize: size)
    at.bounds = CGRect(x: 0, y: (body.capHeight - h) / 2, width: w, height: h)
    let s = NSMutableAttributedString(attachment: at)
    s.addAttributes([FILEREF_KEY: f, .font: body], range: NSRange(location: 0, length: s.length))
    return s
  }
  // # files: the task's files whose names match what's typed after # (the website's and Files' list)
  static func fileHits(_ files: [[String: Any]], _ q: String) -> [[String: Any]] {
    var seen = Set<String>(), out: [[String: Any]] = []
    for f in files {
      guard let p = f["file"] as? String, !seen.contains(p) else { continue }
      seen.insert(p)
      let n = (f["name"] as? String ?? "").lowercased()
      if q.isEmpty || n.contains(q) { out.append(f) }
    }
    return Array(out.prefix(5))
  }
  // a row in the # list: its kind's coloured icon, its name, its size
  static func fileRow(_ f: [String: Any], tap: @escaping () -> Void) -> UIView {
    let row = TaskRow()
    let name = f["name"] as? String ?? "File"
    let (sym, col) = kind(name)
    let ic = UIImageView(image: UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))); ic.tintColor = col
    ic.contentMode = .center; ic.widthAnchor.constraint(equalToConstant: 28).isActive = true
    let l = UILabel(); l.text = name; l.font = .systemFont(ofSize: 16, weight: .medium); l.lineBreakMode = .byTruncatingMiddle
    let sz = UILabel(); sz.text = TaskPage.size(f["size"] as? Int ?? 0); sz.font = .systemFont(ofSize: 13); sz.textColor = .secondaryLabel
    sz.setContentCompressionResistancePriority(.required, for: .horizontal)
    let h = UIStackView(arrangedSubviews: [ic, l, sz]); h.spacing = 10; h.alignment = .center
    h.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), h.topAnchor.constraint(equalTo: row.topAnchor, constant: 8), h.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8), h.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14)])
    row.onTap = tap
    return row
  }
  // the words as plain text (each chip as "📎 name", as the website keeps it)
  static func plain(_ a: NSAttributedString) -> String {
    var out = ""
    a.enumerateAttributes(in: NSRange(location: 0, length: a.length), options: []) { at, r, _ in
      if let f = at[FILEREF_KEY] as? [String: Any] { out += "📎 " + (f["name"] as? String ?? "File"); return }
      out += (a.string as NSString).substring(with: r)
    }
    return out
  }
  static func attributed(_ runs: [[String: Any]], done: Bool, size: CGFloat = 17, creator: String? = nil) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for r in runs {
      var traits: UIFontDescriptor.SymbolicTraits = []
      if r["b"] != nil { traits.insert(.traitBold) }
      if r["i"] != nil { traits.insert(.traitItalic) }
      let base = UIFont.systemFont(ofSize: size)
      let font = traits.isEmpty ? base : (base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: size) } ?? base)
      var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: done ? UIColor.secondaryLabel : UIColor.label]
      if r["u"] != nil { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
      if r["s"] != nil { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      if let u = r["user"] as? String { a[MENTION_KEY] = u; a[.foregroundColor] = u == creator ? UIColor.systemOrange : UIColor.systemBlue }   // (the creator: orange)
      if let l = r["link"] as? String, let url = URL(string: l) { a[.link] = url }
      if let f = r["ref"] as? [String: Any] { out.append(chip(f, size: size)); continue }
      out.append(NSAttributedString(string: r["t"] as? String ?? "", attributes: a))
    }
    return out
  }
  private static func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
  // the words back as the website keeps them: lines starting "• " / "1. " become lists
  static func html(_ a: NSAttributedString) -> String {
    var out = "", list: String? = nil
    let ns = a.string as NSString
    var lineStart = 0
    while lineStart <= ns.length {
      var end = 0, contentsEnd = 0
      ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
      var r = NSRange(location: lineStart, length: contentsEnd - lineStart)
      let line = ns.substring(with: r)
      var kind: String? = nil
      if line.hasPrefix("• ") { kind = "ul"; r = NSRange(location: r.location + 2, length: r.length - 2) }
      else if let m = line.range(of: "^[0-9]+\\. ", options: .regularExpression) { kind = "ol"; let n = line.distance(from: line.startIndex, to: m.upperBound); r = NSRange(location: r.location + n, length: r.length - n) }
      if kind != list { if let l = list { out += "</\(l)>" }; if let k = kind { out += "<\(k)>" }; list = kind }
      var inner = ""
      a.enumerateAttributes(in: r, options: []) { at, rr, _ in
        var t = esc(ns.substring(with: rr))
        // (a pasted file, as the website writes it: its 📎 chip)
        if let f = at[FILEREF_KEY] as? [String: Any], let path = f["path"] as? String {
          let name = f["name"] as? String ?? (path as NSString).lastPathComponent
          let thumb = (f["thumb"] as? String).map { " data-fthumb=\"\(esc($0))\"" } ?? ""
          inner += "<span class=\"fileref\" contenteditable=\"false\" data-fpath=\"\(esc(path))\" data-fname=\"\(esc(name))\" data-fsize=\"\((f["size"] as? NSNumber)?.intValue ?? 0)\"\(thumb)>📎 \(esc(name))</span>"
          return
        }
        if let u = at[MENTION_KEY] as? String { t = "<span class=\"mention\" data-user=\"\(esc(u))\">\(t)</span>"; inner += t; return }
        if let f = at[.font] as? UIFont {
          if f.fontDescriptor.symbolicTraits.contains(.traitItalic) { t = "<i>\(t)</i>" }
          if f.fontDescriptor.symbolicTraits.contains(.traitBold) { t = "<b>\(t)</b>" }
        }
        if at[.underlineStyle] != nil { t = "<u>\(t)</u>" }
        if at[.strikethroughStyle] != nil { t = "<s>\(t)</s>" }
        if let l = at[.link] as? URL { t = "<a href=\"\(esc(l.absoluteString))\">\(t)</a>" } else if let l = at[.link] as? String { t = "<a href=\"\(esc(l))\">\(t)</a>" }
        inner += t
      }
      out += kind != nil ? "<li>\(inner)</li>" : inner + (end < ns.length || contentsEnd < end ? "<br>" : "")
      if end >= ns.length { break }
      lineStart = end
    }
    if let l = list { out += "</\(l)>" }
    return out
  }
}

extension TaskPage {
  func setUpDesc() {
    descView.isScrollEnabled = false; descView.backgroundColor = .clear
    descView.textContainerInset = .zero; descView.textContainer.lineFragmentPadding = 0
    descView.font = .systemFont(ofSize: TaskPage.T)
    descView.dataDetectorTypes = []
    descView.delegate = self
    descView.onPasteFiles = { [weak self] in self?.pasteIntoDesc() ?? false }
    // (copied words with mentions or chips: back as they were; a chip from another task goes into this task's Files
    //  when it's saved — the server's, as the website's — Haris 2026-11-02)
    descView.onPasteRich = { [weak self] runs in
      guard let self = self else { return false }
      let tv = self.descView
      let ins = DescEditor.attributed(runs, done: false, size: TaskPage.T, creator: ((self.model?["creator"] as? [String: Any])?["id"] as? String))
      let r = tv.selectedRange
      let m = NSMutableAttributedString(attributedString: tv.attributedText ?? NSAttributedString())
      guard NSMaxRange(r) <= m.length else { return false }
      m.replaceCharacters(in: r, with: ins)
      tv.attributedText = m
      tv.selectedRange = NSRange(location: r.location + ins.length, length: 0)
      var a = tv.typingAttributes; a[MENTION_KEY] = nil; a[FILEREF_KEY] = nil; a[.link] = nil; a[.foregroundColor] = UIColor.label; a[.font] = UIFont.systemFont(ofSize: TaskPage.T); tv.typingAttributes = a
      self.textViewDidChange(tv)
      return true
    }
    descView.inputAccessoryView = descBar()
    mentionBox.axis = .vertical
    mentionBox.backgroundColor = .secondarySystemGroupedBackground
    mentionBox.layer.cornerRadius = 16; mentionBox.layer.cornerCurve = .continuous; mentionBox.clipsToBounds = true
    mentionBox.isHidden = true
  }
  // the format buttons above the keyboard: iPhone's own toolbar, so iPhone draws it its own way over the keyboard
  // (on iOS 26, Liquid Glass floating above it) — a bar of our own was cut off by the keyboard's rounded corners
  // (Haris, 2026-11-02)
  private func descBar() -> UIView {
    let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 400, height: 44))
    // (three groups — text, lists, mention and link — each its own glass on iOS 26, so all seven fit with no ••• to
    //  open; and each has its name, so if iPhone ever does fold some into •••, the list there reads, not bare icons —
    //  Haris 2026-11-02)
    let groups: [[(String, String, String)]] = [
      [("bold", "b", "Bold"), ("italic", "i", "Italic"), ("underline", "u", "Underline")],
      [("list.bullet", "ul", "Bulleted List"), ("list.number", "ol", "Numbered List")],
      [("at", "@", "Mention"), ("link", "link", "Link")]]
    var out: [UIBarButtonItem] = []
    for (gi, g) in groups.enumerated() {
      if gi > 0 { out.append(UIBarButtonItem.flexibleSpace()) }
      if gi == groups.count - 1 {
        // (a file from the phone, into the task's files, its chip where the cursor is — Haris 2026-11-02)
        let menu = UIMenu(children: [("Camera", "camera", "camera"), ("Photos", "photo.on.rectangle", "photos"), ("Files", "folder", "files")].map { t, sym, src in
          UIAction(title: t, image: UIImage(systemName: sym)) { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.descAttach(src) }
        })
        let b = UIBarButtonItem(title: "Attach", image: UIImage(systemName: "paperclip", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), menu: menu)
        b.tintColor = .label; b.accessibilityLabel = "Attach"
        out.append(b)
      }
      for (sym, k, name) in g {
        let b = UIBarButtonItem(title: name, image: UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), primaryAction: UIAction(title: name, image: UIImage(systemName: sym)) { [weak self] _ in UISelectionFeedbackGenerator().selectionChanged(); self?.format(k) })
        b.tintColor = .label
        b.accessibilityLabel = name
        out.append(b)
      }
    }
    bar.items = out
    bar.sizeToFit()
    // (a small gap under it, so the glass doesn't sit on the keyboard — Haris 2026-11-02: "keep the iPhone look, with a
    //  small gap"; the gap is see-through)
    let gap: CGFloat = 8
    let box = UIView(frame: CGRect(x: 0, y: 0, width: bar.bounds.width, height: bar.bounds.height + gap))
    box.backgroundColor = .clear
    box.autoresizingMask = [.flexibleWidth]
    bar.frame = CGRect(x: 0, y: 0, width: box.bounds.width, height: bar.bounds.height)
    bar.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
    box.addSubview(bar)
    return box
  }
  func beginDesc() {
    guard !editingDesc, (model?["canDesc"] as? Bool) == true else { return }
    editingDesc = true
    if descEmpty { descView.attributedText = NSAttributedString(string: "", attributes: [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.label]) }
    descView.typingAttributes = [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.label]
    onCornerChange?()
  }
  // Done: saved (only if it changed)
  func finishDesc() {
    guard editingDesc else { return }
    // (a file still going up: saved as soon as it's there — until then it stays as it is)
    if descUploading { descAutoFinish = true; toast("Saves after the upload"); descView.resignFirstResponder(); return }
    descAutoFinish = false
    editingDesc = false
    hideMentions()
    descView.resignFirstResponder()
    let html = DescEditor.html(descView.attributedText)
    let text = DescEditor.plain(descView.attributedText)
    // (a pasted file whose 📎 was deleted again before Done: its card goes too)
    var kept = Set<String>()
    descView.attributedText.enumerateAttribute(FILEREF_KEY, in: NSRange(location: 0, length: descView.attributedText.length)) { v, _, _ in if let p = (v as? [String: Any])?["path"] as? String { kept.insert(p) } }
    descPending.removeAll { !kept.contains($0["file"] as? String ?? "") }
    // (a file from another task or Client Assets: into this task's Files too — Haris 2026-11-02)
    let own = Set(((model?["files"] as? [[String: Any]]) ?? []).compactMap { $0["file"] as? String })
    let extra = descPending.filter { f in guard let p = f["file"] as? String else { return false }; return !own.contains(p) && !p.hasPrefix("attachments/\(taskId)/") }
    if !extra.isEmpty { onAct?(["act": "attach", "id": taskId, "files": extra.map { ["name": $0["name"] as? String ?? "File", "size": $0["size"] as? Int ?? 0, "path": $0["file"] as? String ?? ""] }]) }
    let was = DescEditor.html(DescEditor.attributed((model?["descRuns"] as? [[String: Any]]) ?? [], done: false))
    if html != was && !(descEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onAct?(["act": "desc", "id": taskId, "html": html, "text": text, "chips": true]) }
    built = ""
    if let m = model { draw(m) }
    onCornerChange?()
  }
  private func format(_ k: String) {
    let tv = descView
    let r = tv.selectedRange
    switch k {
    case "b", "i":
      let trait: UIFontDescriptor.SymbolicTraits = k == "b" ? .traitBold : .traitItalic
      if r.length == 0 { var ta = tv.typingAttributes; ta[.font] = toggled(ta[.font] as? UIFont, trait); tv.typingAttributes = ta; return }
      let m = NSMutableAttributedString(attributedString: tv.attributedText)
      m.enumerateAttribute(.font, in: r) { v, rr, _ in m.addAttribute(.font, value: toggled(v as? UIFont, trait), range: rr) }
      tv.attributedText = m; tv.selectedRange = r
    case "u":
      let m = NSMutableAttributedString(attributedString: tv.attributedText)
      if r.length == 0 { var ta = tv.typingAttributes; ta[.underlineStyle] = ta[.underlineStyle] == nil ? NSUnderlineStyle.single.rawValue : nil; tv.typingAttributes = ta; return }
      let on = m.attribute(.underlineStyle, at: r.location, effectiveRange: nil) != nil
      if on { m.removeAttribute(.underlineStyle, range: r) } else { m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
      tv.attributedText = m; tv.selectedRange = r
    case "ul", "ol":
      // each line in the selection: the list mark added (or taken off when it's already that kind)
      let ns = tv.text as NSString
      var lines: [NSRange] = []
      var loc = ns.lineRange(for: NSRange(location: r.location, length: 0)).location
      while true {
        let one = ns.lineRange(for: NSRange(location: loc, length: 0))
        lines.append(one)
        let next = NSMaxRange(one)
        if next >= NSMaxRange(r) || next >= ns.length || next == loc { break }
        loc = next
      }
      let m = NSMutableAttributedString(attributedString: tv.attributedText)
      for (n, one) in lines.enumerated().reversed() {
        let line = ns.substring(with: one)
        if let h = line.range(of: "^(• |[0-9]+\\. )", options: .regularExpression) {
          let len = line.distance(from: line.startIndex, to: h.upperBound)
          let same = (k == "ul") == line.hasPrefix("• ")
          m.replaceCharacters(in: NSRange(location: one.location, length: len), with: "")
          if same { continue }
        }
        m.insert(NSAttributedString(string: k == "ul" ? "• " : "\(n + 1). ", attributes: tv.typingAttributes), at: one.location)
      }
      tv.attributedText = m
    case "@":
      tv.insertText("@")
    case "link":
      let a = UIAlertController(title: "Add a link", message: nil, preferredStyle: .alert)
      a.addTextField { f in f.placeholder = "https://"; f.keyboardType = .URL; f.autocapitalizationType = .none }
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      a.addAction(UIAlertAction(title: "Add", style: .default) { [weak a, weak tv] _ in
        guard let tv = tv, var u = a?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !u.isEmpty else { return }
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        guard let url = URL(string: u) else { return }
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        if r.length > 0 { m.addAttribute(.link, value: url, range: r) }
        else { var at = tv.typingAttributes; at[.link] = url; m.insert(NSAttributedString(string: u, attributes: at), at: r.location) }
        tv.attributedText = m
      })
      present(a)
    default: break
    }
  }
  private func toggled(_ f: UIFont?, _ t: UIFontDescriptor.SymbolicTraits) -> UIFont {
    let f = f ?? .systemFont(ofSize: TaskPage.T)
    var tr = f.fontDescriptor.symbolicTraits
    if tr.contains(t) { tr.remove(t) } else { tr.insert(t) }
    return f.fontDescriptor.withSymbolicTraits(tr).map { UIFont(descriptor: $0, size: f.pointSize) } ?? f
  }

  // ---------- @: the people under the words; tapped → a blue mention ----------
  func descChanged() {
    let tv = descView
    let r = tv.selectedRange
    let before = (tv.text as NSString).substring(to: r.location)
    // (# and some letters: the task's files — picked, its chip in place of what was typed; Haris 2026-11-02)
    if let m = before.range(of: "(^|\\s)#([^\\s#@]*)$", options: .regularExpression) {
      let typed = String(before[m]).trimmingCharacters(in: .whitespacesAndNewlines)
      let q = String(typed.dropFirst()).lowercased()
      let hits = DescEditor.fileHits(taskFilesForPick, q)
      if hits.isEmpty { hideMentions(); return }
      mentionBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
      let at = (before as NSString).length - (typed as NSString).length
      for f in hits { mentionBox.addArrangedSubview(DescEditor.fileRow(f) { [weak self] in self?.insertFileChip(f, from: at) }) }
      showMentionBox(hits.count)
      return
    }
    guard let m = before.range(of: "@([A-Za-z]*)$", options: .regularExpression) else { hideMentions(); return }
    let q = String(before[m].dropFirst()).lowercased()
    let all = (model?["mentionable"] as? [[String: Any]]) ?? []
    let hits = all.filter { q.isEmpty || ($0["name"] as? String ?? "").lowercased().split(separator: " ").contains { $0.hasPrefix(q) } }.prefix(4)
    if hits.isEmpty { hideMentions(); return }
    mentionBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let at = (before as NSString).length - q.count - 1
    for p in hits {
      let row = TaskRow()
      let h = UIStackView(arrangedSubviews: [CommentCell.avatar(p, 28), { let l = UILabel(); l.text = p["name"] as? String; l.font = .systemFont(ofSize: 16, weight: .medium); return l }()])
      h.spacing = 10; h.alignment = .center; h.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(h)
      NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), h.topAnchor.constraint(equalTo: row.topAnchor, constant: 8), h.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8), h.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor)])
      row.onTap = { [weak self] in self?.insertMention(p, from: at) }
      mentionBox.addArrangedSubview(row)
    }
    showMentionBox(hits.count)
  }
  private func showMentionBox(_ n: Int) {
    let tv = descView
    if mentionBox.superview == nil { addSubview(mentionBox) }
    // just under the line being written
    let caret = tv.convert(tv.caretRect(for: tv.selectedTextRange?.end ?? tv.endOfDocument), to: self)
    let h = CGFloat(n) * 46
    // (under the line being written — or above it when that would run under the keyboard's format bar: the @ and #
    //  lists sat over B · I · U, Haris 2026-11-02)
    let room = bounds.height - (kbCover > 0 ? kbCover + 8 : safeAreaInsets.bottom + 16)   // (the keyboard's frame holds its format bar)
    var y = caret.maxY + 10
    if y + h > room { y = caret.minY - 10 - h }
    mentionBox.frame = CGRect(x: 16, y: max(barBottom + 4, y), width: bounds.width - 32, height: h)
    mentionBox.isHidden = false
    bringSubviewToFront(mentionBox)
  }
  // the task's files for # (its own and its comments', as the Files row)
  // (the task's files and its comments' — each file once, as the website's taskFilesList)
  var taskFilesForPick: [[String: Any]] {
    var seen = Set<String>()
    return (((model?["files"] as? [[String: Any]]) ?? []) + ((model?["commentFiles"] as? [[String: Any]]) ?? [])).filter { f in
      guard let k = (f["file"] as? String) ?? (f["id"] as? String) else { return true }
      return seen.insert(k).inserted
    }
  }
  private func insertFileChip(_ f: [String: Any], from at: Int) {
    guard let path = f["file"] as? String else { return }
    let tv = descView
    let r = tv.selectedRange
    DescEditor.dark = !light
    let plain: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: TaskPage.T), .foregroundColor: UIColor.label]
    let add = NSMutableAttributedString(attributedString: DescEditor.chip(["path": path, "name": f["name"] as? String ?? "File", "size": f["size"] as? Int ?? 0], size: TaskPage.T))
    add.append(NSAttributedString(string: " ", attributes: plain))
    let m = NSMutableAttributedString(attributedString: tv.attributedText)
    m.replaceCharacters(in: NSRange(location: at, length: r.location - at), with: add)
    tv.attributedText = m
    tv.selectedRange = NSRange(location: at + add.length, length: 0)
    tv.typingAttributes = plain
    if !descPending.contains(where: { ($0["file"] as? String) == path }) { descPending.append(f) }
    UISelectionFeedbackGenerator().selectionChanged()
    hideMentions()
    setNeedsLayout()
  }
  private func insertMention(_ p: [String: Any], from at: Int) {
    let tv = descView
    let r = tv.selectedRange
    let m = NSMutableAttributedString(attributedString: tv.attributedText)
    let name = "@" + (p["name"] as? String ?? "")
    var a = tv.typingAttributes; a[MENTION_KEY] = p["id"] as? String ?? ""; a[.foregroundColor] = UIColor.systemBlue
    m.replaceCharacters(in: NSRange(location: at, length: r.location - at), with: NSAttributedString(string: name, attributes: a))
    var plain = tv.typingAttributes; plain[MENTION_KEY] = nil; plain[.foregroundColor] = UIColor.label
    m.insert(NSAttributedString(string: " ", attributes: plain), at: at + (name as NSString).length)
    tv.attributedText = m
    tv.selectedRange = NSRange(location: at + (name as NSString).length + 1, length: 0)
    tv.typingAttributes = plain
    UISelectionFeedbackGenerator().selectionChanged()
    hideMentions()
  }
  func hideMentions() { mentionBox.isHidden = true }
}

// Copied words with mentions or file chips paste back as they were — in a comment or the description, on the phone, the
// Mac app or the website (Haris 2026-11-02). The clipboard carries the words (for other apps: "@Name", "📎 name") and the
// same words as the website's HTML in a <div data-e11-clip>, which only E11 reads back.
enum RichClip {
  static let MARK = "data-e11-clip"
  static func has(_ a: NSAttributedString) -> Bool {
    var any = false
    a.enumerateAttributes(in: NSRange(location: 0, length: a.length), options: []) { at, _, stop in
      if at[MENTION_KEY] != nil || at[FILEREF_KEY] != nil { any = true; stop.pointee = true }
    }
    return any
  }
  // (on the clipboard; nothing to do when the words have no mention or chip — iPhone's own copy stays)
  static func put(_ a: NSAttributedString) {
    guard a.length > 0, has(a) else { return }
    let html = "<div \(MARK)=\"1\">" + DescEditor.html(a) + "</div>"
    UIPasteboard.general.items = [["public.html": html, "public.utf8-plain-text": DescEditor.plain(a)]]
  }
  // the copied words as runs (as the server sends them), when they're E11's
  static func runs() -> [[String: Any]]? {
    let pb = UIPasteboard.general
    guard pb.contains(pasteboardTypes: ["public.html"]) else { return nil }
    var html: String? = nil
    if let d = pb.data(forPasteboardType: "public.html") { html = String(data: d, encoding: .utf8) }
    if html == nil { html = pb.value(forPasteboardType: "public.html") as? String }
    guard let h = html, let m = h.range(of: MARK) else { return nil }
    // (from the marked div's end of tag on; what's after its close doesn't matter much — the web adds nothing there)
    guard let open = h[m.upperBound...].range(of: ">") else { return nil }
    var body = String(h[open.upperBound...])
    if let close = body.range(of: "</div>", options: .backwards) { body = String(body[..<close.lowerBound]) }
    let r = parse(body)
    return r.isEmpty ? nil : r
  }
  // the website's HTML (b, i, u, s, a, br, div/p, ul/ol/li, mention and file chip spans) → runs
  static func parse(_ html: String) -> [[String: Any]] {
    var out: [[String: Any]] = []
    var b = 0, i = 0, u = 0, s = 0
    var links: [String?] = [], spans: [String] = [], lists: [(String, Int)] = []
    var user: String? = nil, skip = 0
    func text(_ t: String) {
      guard !t.isEmpty else { return }
      var r: [String: Any] = ["t": t]
      if b > 0 { r["b"] = true }; if i > 0 { r["i"] = true }; if u > 0 { r["u"] = true }; if s > 0 { r["s"] = true }
      if let l = links.last ?? nil { r["link"] = l }
      if let us = user { r["user"] = us }
      out.append(r)
    }
    func endsWithNewline() -> Bool { (out.last?["t"] as? String)?.hasSuffix("\n") ?? true }
    func newline() { if !endsWithNewline() { text("\n") } }
    func attr(_ tag: String, _ name: String) -> String? {
      guard let r = tag.range(of: name + "=\"([^\"]*)\"", options: .regularExpression) else { return nil }
      let v = tag[r].dropFirst(name.count + 2).dropLast()
      return unescape(String(v))
    }
    var rest = Substring(html)
    while !rest.isEmpty {
      guard let lt = rest.firstIndex(of: "<") else {
        if skip == 0 { text(unescape(collapse(String(rest)))) }
        break
      }
      if lt > rest.startIndex, skip == 0 { text(unescape(collapse(String(rest[..<lt])))) }
      guard let gt = rest[lt...].firstIndex(of: ">") else { break }
      let tag = String(rest[rest.index(after: lt)..<gt])
      rest = rest[rest.index(after: gt)...]
      let closing = tag.hasPrefix("/")
      let name = (closing ? String(tag.dropFirst()) : tag).split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "\n" }).first.map { $0.lowercased() } ?? ""
      if skip > 0 { if name == "span" { skip += closing ? -1 : 1 }; continue }
      switch (name, closing) {
      case ("b", false), ("strong", false): b += 1
      case ("b", true), ("strong", true): b = max(0, b - 1)
      case ("i", false), ("em", false): i += 1
      case ("i", true), ("em", true): i = max(0, i - 1)
      case ("u", false): u += 1
      case ("u", true): u = max(0, u - 1)
      case ("s", false), ("strike", false), ("del", false): s += 1
      case ("s", true), ("strike", true), ("del", true): s = max(0, s - 1)
      case ("a", false): let h = attr(tag, "href"); links.append(h.flatMap { $0.hasPrefix("http") ? $0 : nil })
      case ("a", true): _ = links.popLast()
      case ("br", _): text("\n")
      case ("div", _), ("p", _), ("blockquote", _), ("pre", _): newline()
      case ("ul", false): newline(); lists.append(("ul", 0))
      case ("ol", false): newline(); lists.append(("ol", 0))
      case ("ul", true), ("ol", true): _ = lists.popLast(); newline()
      case ("li", false):
        newline()
        if var l = lists.popLast() { l.1 += 1; lists.append(l); text(l.0 == "ol" ? "\(l.1). " : "• ") } else { text("• ") }
      case ("li", true): newline()
      case ("span", false):
        if tag.contains("fileref"), let path = attr(tag, "data-fpath") {
          var f: [String: Any] = ["path": path, "name": attr(tag, "data-fname") ?? (path as NSString).lastPathComponent, "size": Int(attr(tag, "data-fsize") ?? "") ?? 0]
          if let th = attr(tag, "data-fthumb") { f["thumb"] = th }
          out.append(["t": "", "ref": f]); skip = 1   // (its inner words: its name, drawn by the chip)
        } else if tag.contains("mention"), let id = attr(tag, "data-user") { user = id; spans.append("m") }
        else { spans.append("") }
      case ("span", true): if spans.popLast() == "m" { user = nil }
      default: break
      }
    }
    // (no newline left at the very end)
    while let l = out.last, let t = l["t"] as? String, l["ref"] == nil, t.hasSuffix("\n") {
      let k = String(t.dropLast()); if k.isEmpty { out.removeLast() } else { out[out.count - 1]["t"] = k }
    }
    return out
  }
  private static func collapse(_ s: String) -> String { s.replacingOccurrences(of: "[\\r\\n\\t ]+", with: " ", options: .regularExpression) }
  static func unescape(_ s: String) -> String {
    guard s.contains("&") else { return s }
    var t = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&apos;", with: "'")
    while let r = t.range(of: "&#(x?[0-9a-fA-F]+);", options: .regularExpression) {
      let code = t[r].dropFirst(2).dropLast()
      let n = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
      t.replaceSubrange(r, with: n.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? "")
    }
    return t.replacingOccurrences(of: "&amp;", with: "&")
  }
}
