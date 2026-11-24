import WidgetKit
import SwiftUI

/* E11 Talk's unread widget (Haris 2026-11-24, the design canvas "E11 Talk Unread Widget"): small — the count, how many
   groups, their pictures; medium — the 3 groups with the newest unread; large — up to 5. Muted groups never show. Nothing
   unread: "All caught up". Tapping a group opens its chat (e11talk://group/<id>); anywhere else opens Talk.
   It reads only what the app and its notification helper keep for it (Shared/WidgetStore.swift) — it never asks the
   server. */

private let blue = Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xE4 / 255)
private let card = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1) : .white })

struct Row: Identifiable {
  let id: String, name: String, letters: String, color: Color, line: String, at: Double, count: Int   // (count -1: the dot alone)
  let pic: UIImage?, e11: Bool
}
struct Entry: TimelineEntry {
  let date: Date
  let signedIn: Bool
  let rows: [Row]
  let total: Int
}

struct Provider: TimelineProvider {
  func placeholder(in c: Context) -> Entry { Entry(date: Date(), signedIn: true, rows: [], total: 0) }
  func getSnapshot(in c: Context, completion: @escaping (Entry) -> Void) { completion(make()) }
  func getTimeline(in c: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let e = make()
    // (again at midnight — "Yesterday" and the days move on — or when a mute ends, whichever comes first)
    let cal = Calendar.current
    var next = cal.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(5)
    let now = Date().timeIntervalSince1970 * 1000
    if let ends = WidgetStore.summary?.groups.compactMap({ $0.mutedUntil }).filter({ $0 > now }).min() {
      next = min(next, Date(timeIntervalSince1970: ends / 1000 + 5))
    }
    completion(Timeline(entries: [e], policy: .after(next)))
  }

  // the app's summary, and the messages that came while Talk was closed on top of it
  private func make() -> Entry {
    guard let s = WidgetStore.summary else { return Entry(date: Date(), signedIn: false, rows: [], total: 0) }
    let now = Date().timeIntervalSince1970 * 1000
    var byId: [String: WidgetStore.G] = [:]
    for g in s.groups { byId[g.id] = g }
    var count: [String: Int] = [:], line: [String: String] = [:], at: [String: Double] = [:], extra: [String: WidgetStore.New] = [:]
    for g in s.groups where !g.muted(now) && g.unread != 0 { count[g.id] = g.unread; line[g.id] = g.line; at[g.id] = g.lastAt }
    for n in WidgetStore.news.sorted(by: { $0.at < $1.at }) {
      if let g = byId[n.g], g.muted(now) { continue }
      count[n.g] = max(count[n.g] ?? 0, 0) + 1
      if n.at >= (at[n.g] ?? 0) { at[n.g] = n.at; line[n.g] = n.line }
      if byId[n.g] == nil { extra[n.g] = n }
    }
    var rows: [Row] = []
    for (id, c) in count where c != 0 {
      if let g = byId[id] {
        rows.append(Row(id: id, name: g.name, letters: g.letters, color: Color(hex: g.color), line: line[id] ?? "", at: at[id] ?? g.lastAt, count: c,
                        pic: g.pic && !s.contact ? WidgetStore.get(WidgetStore.picService, id).flatMap { UIImage(data: $0) } : nil, e11: s.contact))
      } else if let n = extra[id] {   // (a group the app hasn't seen yet: its name from the notification)
        rows.append(Row(id: id, name: n.title, letters: initials(n.title), color: blue, line: line[id] ?? n.line, at: at[id] ?? n.at, count: c, pic: nil, e11: s.contact))
      }
    }
    rows.sort { $0.at > $1.at }
    return Entry(date: Date(), signedIn: true, rows: rows, total: rows.reduce(0) { $0 + max($1.count, 1) })
  }
}

// the same letters as the app's (a middle "Al" skipped — Haris 2026-11-08)
func initials(_ s: String) -> String {
  let all = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
  guard let first = all.first else { return "" }
  let next = all.dropFirst().first { $0.lowercased() != "al" } ?? all.dropFirst().first
  return (String(first.prefix(1)) + (next.map { String($0.prefix(1)) } ?? "")).uppercased()
}
// the app's time words: today the time, "Yesterday", the weekday this week, else the date
func when(_ ms: Double) -> String {
  let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current, f = DateFormatter()
  if cal.isDateInToday(d) { f.timeStyle = .short; f.dateStyle = .none; return f.string(from: d) }
  if cal.isDateInYesterday(d) { return "Yesterday" }
  if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 { f.dateFormat = "EEE"; return f.string(from: d) }
  f.dateFormat = "MMM d"; return f.string(from: d)
}
extension Color {
  init(hex: String) {
    var h = hex.trimmingCharacters(in: .whitespaces)
    if h.hasPrefix("#") { h.removeFirst() }
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    let v = UInt32(h, radix: 16) ?? 0x2F6FE4
    self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
  }
}
private func link(_ id: String?) -> URL { URL(string: id.map { "e11talk://group/" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0) } ?? "e11talk://")! }
private func summaryLine(_ e: Entry) -> String { "\(e.total) in \(e.rows.count) group\(e.rows.count == 1 ? "" : "s")" }

// ---------- the pieces ----------
struct Pic: View {
  let row: Row, size: CGFloat
  var body: some View {
    ZStack {
      if row.e11 {
        Circle().fill(Color.black)
        Text("E11.").font(.system(size: size * 0.3, weight: .bold)).foregroundColor(.white)
      } else if let i = row.pic {
        Image(uiImage: i).resizable().scaledToFill()
      } else {
        Circle().fill(row.color)
        Text(row.letters).font(.system(size: size * 0.36, weight: .semibold)).foregroundColor(.white).minimumScaleFactor(0.5)
      }
    }
    .frame(width: size, height: size).clipShape(Circle())
  }
}
struct Badge: View {
  let count: Int, size: CGFloat
  var body: some View {
    Group {
      if count < 0 { Circle().fill(blue).frame(width: size * 0.6, height: size * 0.6) }
      else {
        Text(count > 99 ? "99+" : "\(count)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
          .padding(.horizontal, 6).frame(minWidth: size, minHeight: size).background(Capsule().fill(blue))
      }
    }
  }
}
struct Mark: View {
  let size: CGFloat
  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(blue).frame(width: size, height: size)
      .overlay(Image(systemName: "bubble.left.fill").font(.system(size: size * 0.5, weight: .semibold)).foregroundColor(.white))
  }
}
struct GroupLine: View {
  let row: Row, pic: CGFloat, big: Bool
  var body: some View {
    Link(destination: link(row.id)) {
      HStack(spacing: 10) {
        Pic(row: row, size: pic)
        VStack(alignment: .leading, spacing: 1) {
          Text(row.name).font(.system(size: big ? 14 : 13, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
          Text(row.line).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
        }
        Spacer(minLength: 4)
        VStack(alignment: .trailing, spacing: 4) {
          Text(when(row.at)).font(.system(size: 11)).foregroundColor(blue)
          Badge(count: row.count, size: big ? 20 : 18)
        }
      }
    }
  }
}
struct CaughtUp: View {
  let signedIn: Bool, big: Bool, wide: Bool
  var body: some View {
    let tick = Image(systemName: "checkmark.circle").font(.system(size: big ? 46 : 30, weight: .regular)).foregroundColor(blue)
    let title = Text(signedIn ? "All caught up" : "E11 Talk").font(.system(size: big ? 17 : 15, weight: .bold)).foregroundColor(.primary)
    let sub = Text(signedIn ? (wide ? "New messages will show here" : "No unread messages") : "Open E11 Talk to sign in").font(.system(size: big ? 13 : 12)).foregroundColor(.secondary)
    if wide && !big {
      HStack(spacing: 12) { tick; VStack(alignment: .leading, spacing: 2) { title; sub } }.frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if big {
      VStack(spacing: 10) { tick; title; sub }.frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 4) { tick; title; sub }
    }
  }
}

// ---------- the three sizes ----------
struct Small: View {
  let e: Entry
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack { Mark(size: 28); Spacer(); Text("E11 Talk").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary) }
      Spacer(minLength: 0)
      if e.rows.isEmpty { CaughtUp(signedIn: e.signedIn, big: false, wide: false) }
      else {
        Text("\(e.total)").font(.system(size: 44, weight: .bold)).foregroundColor(blue).minimumScaleFactor(0.5).lineLimit(1)
        Text("unread").font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
        Text("in \(e.rows.count) group\(e.rows.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundColor(.secondary)
        Spacer(minLength: 6)
        HStack(spacing: -6) {
          ForEach(e.rows.prefix(4)) { r in Pic(row: r, size: 24).overlay(Circle().stroke(card, lineWidth: 2)) }
        }
      }
    }
    .widgetURL(link(nil))
  }
}
struct Medium: View {
  let e: Entry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Unread").font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
        Spacer()
        Text(e.rows.isEmpty ? "E11 Talk" : summaryLine(e)).font(.system(size: 12, weight: .semibold)).foregroundColor(e.rows.isEmpty ? .secondary : blue)
      }
      if e.rows.isEmpty { CaughtUp(signedIn: e.signedIn, big: false, wide: true) }
      else {
        ForEach(e.rows.prefix(3)) { r in GroupLine(row: r, pic: 32, big: false) }
        Spacer(minLength: 0)
      }
    }
    .widgetURL(link(nil))
  }
}
struct Large: View {
  let e: Entry
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Mark(size: 24)
        Text("Unread").font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
        Spacer()
        if !e.rows.isEmpty { Text(summaryLine(e)).font(.system(size: 12, weight: .semibold)).foregroundColor(blue) }
      }
      if e.rows.isEmpty { CaughtUp(signedIn: e.signedIn, big: true, wide: true) }
      else {
        ForEach(Array(e.rows.prefix(5).enumerated()), id: \.element.id) { i, r in
          GroupLine(row: r, pic: 38, big: true)
          if i < min(e.rows.count, 5) - 1 { Divider() }
        }
        Spacer(minLength: 0)
      }
    }
    .widgetURL(link(nil))
  }
}
struct UnreadView: View {
  @Environment(\.widgetFamily) var family
  let e: Entry
  var body: some View {
    Group {
      switch family {
      case .systemMedium: Medium(e: e)
      case .systemLarge: Large(e: e)
      default: Small(e: e)
      }
    }
    .containerBackground(for: .widget) { card }
  }
}

@main
struct TalkUnreadWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetStore.kind, provider: Provider()) { e in UnreadView(e: e) }
      .configurationDisplayName("Unread")
      .description("Your groups with unread messages. Muted groups don't show.")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
