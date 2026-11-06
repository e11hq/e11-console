import UIKit

/* One way of finding, for every search on the phone (Haris, 2026-11-06: "give every search the same typo forgiveness and
   marked words, so they all behave alike") — as the website's task search: every word typed has to be there; exact
   first, and when nothing is found, small typos are forgiven ("frod" finds Ford: one letter off from 4 letters, two from
   8, two swapped letters count as one). What was found is marked: the words in the results get a light blue wash. */
enum Find {
  static func norm(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
  static func terms(_ q: String) -> [String] {
    norm(q).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "@" && $0 != "." }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }
  }
  private static func words(_ s: String) -> [String] { norm(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
  private static func limit(_ t: String) -> Int { t.count >= 8 ? 2 : t.count >= 4 ? 1 : 0 }
  // a word of the text close enough to the term (or starting close enough to it)
  private static func near(_ t: String, _ ws: [String]) -> String? {
    let lim = limit(t); guard lim > 0 else { return nil }
    return ws.first { w in AssetsCtl.typoDist(t, w, lim) <= lim || (w.count > t.count && AssetsCtl.typoDist(t, String(w.prefix(t.count)), lim) <= lim) }
  }
  struct Result<T> { var items: [T]; var loose: Bool; var marks: [String] }
  // the items whose text has every word: exact pieces first; none — the forgiving way
  static func filter<T>(_ items: [T], _ q: String, text: (T) -> String) -> Result<T> {
    let ts = terms(q)
    guard !ts.isEmpty else { return Result(items: items, loose: false, marks: []) }
    let exact = items.filter { x in let n = norm(text(x)); return ts.allSatisfy { n.contains($0) } }
    if !exact.isEmpty { return Result(items: exact, loose: false, marks: ts) }
    var marks = Set<String>()
    let loose = items.filter { x in
      let n = norm(text(x)), ws = words(text(x))
      var found: [String] = []
      for t in ts { if n.contains(t) { found.append(t) } else if let w = near(t, ws) { found.append(w) } else { return false } }
      found.forEach { marks.insert($0) }
      return true
    }
    return Result(items: loose, loose: !loose.isEmpty, marks: Array(marks))
  }
  // the words marked in every label inside these views (titles, names, lines under them)
  // (the last search's marks taken off first — rows kept from one search to the next kept them)
  private static let markKey = NSAttributedString.Key("e11FindMark")
  static func mark(_ views: [UIView], _ marks: [String], light: Bool) {
    let wash = UIColor.systemBlue.withAlphaComponent(light ? 0.16 : 0.3)
    func walk(_ v: UIView) {
      if let l = v as? UILabel, let t = l.attributedText, t.length > 0 {
        let s = NSMutableAttributedString(attributedString: t)
        let ns = t.string as NSString
        var any = false
        var old: [NSRange] = []
        t.enumerateAttribute(markKey, in: NSRange(location: 0, length: t.length)) { val, r, _ in if val != nil { old.append(r) } }
        for r in old { s.removeAttribute(.backgroundColor, range: r); s.removeAttribute(markKey, range: r); any = true }
        for w in marks where w.count >= 2 {
          var from = 0
          while from < ns.length {
            let r = ns.range(of: w, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound else { break }
            let starts = r.location == 0 || !(CharacterSet.alphanumerics.contains(UnicodeScalar(ns.character(at: r.location - 1)) ?? " "))
            if starts { s.addAttributes([.backgroundColor: wash, markKey: true], range: r); any = true }
            from = r.location + max(1, r.length)
          }
        }
        if any { l.attributedText = s }
      }
      v.subviews.forEach(walk)
    }
    views.forEach(walk)
  }
}
