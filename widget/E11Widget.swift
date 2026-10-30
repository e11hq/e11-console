// The E11 Console widget (iPhone home and lock screen, Mac desktop / Notification Center).
// One widget for everyone: it shows the signed-in person's own category — Production (My day), Social (Content
// plans) or Finance — from the server's /api/widget, asked with the app's own sign-in (WidgetShare). People with
// more than one category (Admins, Account Managers…) pick in Edit Widget, offered only what they may see.
// Finance money is marked private: hidden on the lock screen until the phone is unlocked.
// Not on CarPlay (the car's widget screen): taps there can't open anything.
import WidgetKit
import SwiftUI
import AppIntents

/* ---------- what the server sends (/api/widget) ---------- */
struct WSummary: Codable {
  var day: String?; var name: String?; var categories: [String]?; var main: String?
  var production: WProd?; var social: WSoc?; var finance: WFin?
}
struct WProd: Codable { var title: String?; var scope: String?; var dueToday: Int?; var doneToday: Int?; var overdue: Int?; var waitingCD: Int?; var open: Int?; var next: [WTask]?; var week: [WDay]? }
struct WTask: Codable { var id: String; var title: String?; var client: String?; var color: String?; var due: String? }
struct WDay: Codable { var day: String; var due: Int?; var done: Int? }
struct WSoc: Codable {
  var month: String?; var clients: Int?; var approved: Int?; var review: Int?; var changes: Int?; var draft: Int?; var missing: Int?
  var today: [WPost]?; var todayCount: Int?; var todayClients: Int?; var sentBack: [WBack]?; var nextOccasion: WOcc?
}
struct WPost: Codable { var planId: String; var title: String?; var client: String?; var color: String?; var channels: [String]?; var format: String? }
struct WBack: Codable { var planId: String; var client: String?; var note: String?; var by: String? }
struct WOcc: Codable { var name: String?; var date: String?; var days: Int? }
struct WFin: Codable { var month: String?; var statuses: [WStat]?; var spent: Double?; var subsSoon: [WSub]?; var subsSoonCount: Int? }
struct WStat: Codable { var status: String; var color: String?; var count: Int? }
struct WSub: Codable { var name: String?; var date: String?; var amount: Double? }

/* ---------- which category (Edit Widget) ---------- */
struct WCategory: AppEntity {
  let id: String
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
  static var defaultQuery = WCategoryQuery()
  static let names = ["auto": "Mine (automatic)", "production": "Production · My day", "social": "Social · Content plans", "finance": "Finance"]
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(WCategory.names[id] ?? id)") }
}
struct WCategoryQuery: EntityQuery {
  // only the categories this person may see (from the last summary)
  func allowed() -> [String] { ["auto"] + (WStore.cached()?.categories ?? []) }
  func entities(for identifiers: [String]) async throws -> [WCategory] { identifiers.filter { allowed().contains($0) }.map { WCategory(id: $0) } }
  func suggestedEntities() async throws -> [WCategory] { allowed().map { WCategory(id: $0) } }
  func defaultResult() async -> WCategory? { WCategory(id: "auto") }
}
struct WConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "E11 Console"
  static var description = IntentDescription("Your day at E11 at a glance.")
  @Parameter(title: "Show") var category: WCategory?
}

/* ---------- getting the numbers ---------- */
enum WStore {
  static func cached() -> WSummary? { WidgetShare.read("cache").flatMap { try? JSONDecoder().decode(WSummary.self, from: $0) } }
  // nil = couldn't ask (signed out, offline): use the last one
  static func fetch() async -> (WSummary?, signedOut: Bool) {
    guard let s = WidgetShare.signIn(), let url = URL(string: s.server + "/api/widget") else { return (nil, true) }
    var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    if !s.cookie.isEmpty { r.setValue(s.cookie, forHTTPHeaderField: "Cookie") }
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    let data: Data, h: HTTPURLResponse
    do {
      let (d, resp) = try await URLSession.shared.data(for: r)
      guard let hr = resp as? HTTPURLResponse else { return (nil, false) }
      data = d; h = hr
    } catch { return (nil, false) }
    // Cloudflare's sign-in page (a redirect elsewhere) or a refusal: the app's sign-in has run out
    if h.url?.host != url.host || h.statusCode == 401 || h.statusCode == 403 { return (nil, true) }
    guard h.statusCode == 200, let sum = try? JSONDecoder().decode(WSummary.self, from: data) else { return (nil, false) }
    WidgetShare.write("cache", data)
    return (sum, false)
  }
}

struct WEntry: TimelineEntry {
  let date: Date
  let summary: WSummary?
  let cat: String?        // production / social / finance (nil: nothing to show)
  let stale: Bool         // the last numbers (signed out or offline)
  let signedOut: Bool
}
func resolve(_ s: WSummary?, _ want: String?) -> String? {
  guard let s = s else { return nil }
  let cats = s.categories ?? []
  if let w = want, w != "auto" { return cats.contains(w) ? w : nil }
  return s.main ?? cats.first
}

struct WProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> WEntry { WEntry(date: Date(), summary: Sample.summary, cat: "production", stale: false, signedOut: false) }
  func snapshot(for configuration: WConfig, in context: Context) async -> WEntry {
    if context.isPreview { let c = resolve(WStore.cached(), configuration.category?.id) ?? "production"; return WEntry(date: Date(), summary: Sample.summary, cat: c, stale: false, signedOut: false) }
    let s = WStore.cached()
    return WEntry(date: Date(), summary: s ?? Sample.summary, cat: resolve(s ?? Sample.summary, configuration.category?.id), stale: s == nil, signedOut: false)
  }
  func timeline(for configuration: WConfig, in context: Context) async -> Timeline<WEntry> {
    let (fresh, signedOut) = await WStore.fetch()
    let s = fresh ?? WStore.cached()
    let e = WEntry(date: Date(), summary: s, cat: resolve(s, configuration.category?.id), stale: fresh == nil && s != nil, signedOut: signedOut)
    // about every 20 minutes (iOS may space it out more); right away when the app is opened
    return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(fresh == nil ? 3600 : 1200)))
  }
}

/* ---------- looks ---------- */
extension Color {
  init(hex: String?, fallback: Color = Color(red: 0.49, green: 0.42, blue: 1)) {
    var h = (hex ?? "").trimmingCharacters(in: .whitespaces); if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { self = fallback; return }
    self = Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
  }
}
enum W {
  static let bg = Color(red: 0.086, green: 0.086, blue: 0.11)
  static let accent = Color(red: 0.725, green: 0.698, blue: 1)
  static let dim = Color(white: 0.6)
  static let red = Color(red: 1, green: 0.42, blue: 0.42)
  static let amber = Color(red: 0.976, green: 0.745, blue: 0.2)
  static let green = Color(red: 0.239, green: 0.863, blue: 0.592)
  static let orange = Color(red: 1, green: 0.541, blue: 0.298)
  static func link(_ q: String) -> URL { URL(string: "e11console://open?" + q)! }
  static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  static func month(_ m: String?) -> String { guard let m = m, m.count >= 7, let i = Int(m.suffix(2)), i >= 1, i <= 12 else { return "" }; return months[i - 1] }
  static func date(_ s: String) -> Date? { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC"); return f.date(from: s) }
  // "Today", "Tomorrow", "Yest.", "Mon", "2 Dec"
  static func when(_ d: String?, today: String?) -> String {
    guard let d = d, let t = today, let a = date(d), let b = date(t) else { return "" }
    let n = Int((a.timeIntervalSince(b) / 86400).rounded())
    if n == 0 { return "Today" }; if n == 1 { return "Tomorrow" }; if n == -1 { return "Yest." }
    let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_GB")
    f.dateFormat = (n > 1 && n < 7) ? "EEE" : "d MMM"
    return f.string(from: a)
  }
  static func aed(_ v: Double?) -> String { let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f.string(from: NSNumber(value: v ?? 0)) ?? "0" }
}

struct Head: View {
  let title: String; var right: String = ""
  var body: some View {
    HStack(spacing: 5) {
      Image("WidgetMark").resizable().frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3.5))
      Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(W.accent).lineLimit(1)
      Spacer(minLength: 4)
      if !right.isEmpty { Text(right).font(.system(size: 11)).foregroundStyle(W.dim).lineLimit(1) }
    }
  }
}
struct Big: View {
  let n: Int; var color: Color = .white; var size: CGFloat = 30
  var body: some View { Text("\(n)").font(.system(size: size, weight: .bold, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1) }
}
struct Lbl: View {
  let t: String; var color: Color = W.dim
  var body: some View { Text(t).font(.system(size: 11)).foregroundStyle(color).lineLimit(1) }
}
struct Row: View {
  let color: Color; let text: String; var right: String = ""; var rightColor: Color = W.dim
  var body: some View {
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
      Text(text).font(.system(size: 12)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
      Spacer(minLength: 4)
      if !right.isEmpty { Text(right).font(.system(size: 11)).foregroundStyle(rightColor).lineLimit(1).layoutPriority(1) }
    }
  }
}
struct Note: View {
  let text: String
  var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(W.dim).multilineTextAlignment(.leading).lineLimit(3) }
}

/* ---------- the widget's face ---------- */
struct WView: View {
  @Environment(\.widgetFamily) var family
  let e: WEntry
  var body: some View {
    content
      .widgetURL(W.link(e.cat == "social" ? "view=plans" : e.cat == "finance" ? "view=fin-dash" : "view=home"))
      .containerBackground(for: .widget) { W.bg }
  }
  @ViewBuilder var content: some View {
    if e.summary == nil || e.cat == nil {
      empty
    } else if e.cat == "social", let s = e.summary?.social {
      SocialView(s: s, day: e.summary?.day, family: family, stale: e.stale)
    } else if e.cat == "finance", let f = e.summary?.finance {
      FinanceView(f: f, day: e.summary?.day, family: family, stale: e.stale)
    } else if let p = e.summary?.production {
      ProdView(p: p, day: e.summary?.day, family: family, stale: e.stale)
    } else { empty }
  }
  @ViewBuilder var empty: some View {
    let msg = e.summary == nil ? "Open E11 Console and sign in to see your day here." : "Not available for your role."
    switch family {
    #if os(iOS)
    case .accessoryInline: Text("E11 Console")
    case .accessoryCircular: Image(systemName: "checklist").font(.title2)
    case .accessoryRectangular: VStack(alignment: .leading) { Text("E11 Console").font(.headline); Text("Open the app to sign in").font(.caption) }
    #endif
    default: VStack(alignment: .leading, spacing: 6) { Head(title: "E11 Console"); Note(text: msg); Spacer(minLength: 0) }
    }
  }
}
struct Stale: View {
  let on: Bool
  var body: some View { if on { Text("Open E11 Console to refresh").font(.system(size: 9.5)).foregroundStyle(W.dim).lineLimit(1) } }
}

// Production · My day
struct ProdView: View {
  let p: WProd; let day: String?; let family: WidgetFamily; let stale: Bool
  var due: Int { p.dueToday ?? 0 }
  var over: Int { p.overdue ?? 0 }
  var rows: [WTask] { p.next ?? [] }
  func row(_ t: WTask) -> some View {
    let w = W.when(t.due, today: day)
    let late = (t.due ?? "9") < (day ?? "")
    return Link(destination: W.link("task=\(t.id)")) { Row(color: Color(hex: t.color), text: t.title ?? "", right: w, rightColor: late ? W.red : W.dim) }
  }
  var body: some View {
    switch family {
    #if os(iOS)
    case .accessoryInline:
      Label(rows.first.map { "\(due) due today · next \(W.when($0.due, today: day).lowercased())" } ?? "\(due) due today", systemImage: "checklist")
    case .accessoryCircular:
      Gauge(value: Double(p.doneToday ?? 0), in: 0...Double(max(1, due + (p.doneToday ?? 0)))) {
        Text("DUE")
      } currentValueLabel: { Text("\(due)") }
        .gaugeStyle(.accessoryCircular)
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text(p.title ?? "My day").font(.headline).widgetAccentable()
        Text(rows.first?.title ?? "Nothing open").font(.caption).lineLimit(1)
        Text(over > 0 ? "\(due) due today · \(over) overdue" : "\(due) due today").font(.caption).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
    #endif
    case .systemSmall:
      VStack(alignment: .leading, spacing: 2) {
        Head(title: p.title ?? "My day")
        Big(n: due)
        HStack(spacing: 3) { Lbl(t: "due today"); if over > 0 { Lbl(t: "· \(over) overdue", color: W.red) } }
        Spacer(minLength: 4)
        if let n = rows.first {
          Lbl(t: "Next · \(W.when(n.due, today: day))")
          Text(n.title ?? "").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
        } else { Lbl(t: "Nothing open — a clear day") }
        Stale(on: stale)
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    default:   // medium, large (Mac)
      VStack(alignment: .leading, spacing: 6) {
        Head(title: p.title ?? "My day", right: dayTitle)
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) { Big(n: due); Lbl(t: "Due today") }
            VStack(alignment: .leading, spacing: 0) { Big(n: over, color: over > 0 ? W.red : .white); Lbl(t: "Overdue") }
          }.frame(width: family == .systemLarge ? 110 : 82, alignment: .leading)
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.prefix(family == .systemLarge ? 5 : 4).enumerated()), id: \.offset) { _, t in row(t) }
            if rows.isEmpty { Note(text: p.scope == "team" || p.scope == "clients" ? "Nothing open." : "Nothing open on your list.") }
            if (p.waitingCD ?? 0) > 0 { Lbl(t: "+\(p.waitingCD ?? 0) waiting for CD review") }
          }
        }
        if family == .systemLarge { Spacer(minLength: 4); WeekChart(week: p.week ?? [], today: day) }
        Spacer(minLength: 0)
        Stale(on: stale)
      }
    }
  }
  var dayTitle: String { guard let d = day, let a = W.date(d) else { return "" }; let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM"; return f.string(from: a) }
}
struct WeekChart: View {
  let week: [WDay]; let today: String?
  var body: some View {
    let top = max(1, week.map { $0.due ?? 0 }.max() ?? 1)
    VStack(alignment: .leading, spacing: 4) {
      Lbl(t: "THIS WEEK")
      HStack(alignment: .bottom, spacing: 8) {
        ForEach(Array(week.enumerated()), id: \.offset) { i, d in
          VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(height: 54)
              RoundedRectangle(cornerRadius: 4).fill(d.day == today ? W.accent : W.accent.opacity(0.55)).frame(height: max(4, 54 * CGFloat(d.due ?? 0) / CGFloat(top)))
            }
            Text(["M", "T", "W", "T", "F"][min(i, 4)]).font(.system(size: 10)).foregroundStyle(d.day == today ? .white : W.dim)
          }
        }
      }
      Lbl(t: "\(week.reduce(0) { $0 + ($1.due ?? 0) }) due this week · \(week.reduce(0) { $0 + ($1.done ?? 0) }) done")
    }
  }
}

// Social · Content plans
struct SocialView: View {
  let s: WSoc; let day: String?; let family: WidgetFamily; let stale: Bool
  var total: Int { max(s.clients ?? 0, (s.approved ?? 0) + (s.review ?? 0) + (s.changes ?? 0) + (s.draft ?? 0)) }
  var posts: [WPost] { s.today ?? [] }
  func post(_ x: WPost) -> some View {
    Link(destination: W.link("plan=\(x.planId)")) { Row(color: Color(hex: x.color), text: [x.client, x.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), right: (x.channels ?? []).joined(separator: " · ")) }
  }
  var occ: String? {
    guard let o = s.nextOccasion, let name = o.name else { return nil }
    guard let d = o.days else { return "Next occasion: \(name)" }
    return "Next occasion: \(name) · in \(d) day\(d == 1 ? "" : "s")"
  }
  var bar: some View {
    GeometryReader { g in
      let t = CGFloat(max(1, total))
      HStack(spacing: 0) {
        Rectangle().fill(W.green).frame(width: g.size.width * CGFloat(s.approved ?? 0) / t)
        Rectangle().fill(W.amber).frame(width: g.size.width * CGFloat(s.review ?? 0) / t)
        Rectangle().fill(W.red).frame(width: g.size.width * CGFloat(s.changes ?? 0) / t)
        Spacer(minLength: 0)
      }.background(Color.white.opacity(0.1)).clipShape(Capsule())
    }.frame(height: 6)
  }
  var states: some View {
    HStack(spacing: 4) {
      if (s.review ?? 0) > 0 { Lbl(t: "\(s.review ?? 0) in review", color: W.amber) }
      if (s.changes ?? 0) > 0 { Lbl(t: "\(s.changes ?? 0) changes", color: W.red) }
      if (s.draft ?? 0) > 0 { Lbl(t: "\(s.draft ?? 0) draft") }
      if (s.missing ?? 0) > 0 { Lbl(t: "\(s.missing ?? 0) not started") }
    }
  }
  var body: some View {
    switch family {
    #if os(iOS)
    case .accessoryInline: Label("\(s.todayCount ?? 0) post\((s.todayCount ?? 0) == 1 ? "" : "s") today", systemImage: "calendar")
    case .accessoryCircular:
      ZStack { AccessoryWidgetBackground(); VStack(spacing: 0) { Text("\(s.todayCount ?? 0)").font(.system(size: 22, weight: .bold, design: .rounded)); Text("POSTS").font(.system(size: 8, weight: .semibold)) } }
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text("Content plans").font(.headline).widgetAccentable()
        Text("\(s.approved ?? 0) of \(total) approved").font(.caption).lineLimit(1)
        Text(s.sentBack?.first.map { "\($0.client ?? ""): changes" } ?? occ ?? "\(W.month(s.month)) plans").font(.caption).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
    #endif
    case .systemSmall:
      VStack(alignment: .leading, spacing: 2) {
        Head(title: "Posting today")
        Big(n: s.todayCount ?? 0)
        Lbl(t: (s.todayCount ?? 0) == 0 ? "nothing goes out today" : "posts · \(s.todayClients ?? 0) client\((s.todayClients ?? 0) == 1 ? "" : "s")")
        Spacer(minLength: 4)
        ForEach(Array(posts.prefix(2).enumerated()), id: \.offset) { _, x in Row(color: Color(hex: x.color), text: [x.client, x.title].compactMap { $0 }.joined(separator: " · ")) }
        if posts.isEmpty { Lbl(t: "\(s.approved ?? 0) of \(total) \(W.month(s.month)) plans approved") }
        Stale(on: stale)
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    default:
      VStack(alignment: .leading, spacing: 6) {
        Head(title: "Content plans", right: W.month(s.month))
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) { Big(n: s.approved ?? 0); Text("/ \(total)").font(.system(size: 14, weight: .semibold)).foregroundStyle(W.dim) }
            Lbl(t: "plans approved")
            bar
            states
          }.frame(width: family == .systemLarge ? 150 : 120, alignment: .leading)
          VStack(alignment: .leading, spacing: 4) {
            Lbl(t: "Posting today")
            ForEach(Array(posts.prefix(3).enumerated()), id: \.offset) { _, x in post(x) }
            if posts.isEmpty { Note(text: "Nothing goes out today.") }
            if family != .systemLarge, let o = occ { Lbl(t: o) }
          }
        }
        if family == .systemLarge {
          Spacer(minLength: 2)
          Lbl(t: "NEEDS YOU")
          ForEach(Array((s.sentBack ?? []).enumerated()), id: \.offset) { _, b in
            Link(destination: W.link("plan=\(b.planId)")) { Row(color: W.red, text: "\(b.client ?? ""): changes\(b.by.map { $0.isEmpty ? "" : " from \($0)" } ?? "")", right: "") }
          }
          if (s.sentBack ?? []).isEmpty { Note(text: "No plans sent back.") }
          if let o = occ { Lbl(t: o) }
        }
        Spacer(minLength: 0)
        Stale(on: stale)
      }
    }
  }
}

// Finance
struct FinanceView: View {
  let f: WFin; let day: String?; let family: WidgetFamily; let stale: Bool
  func count(_ k: String) -> Int { (f.statuses ?? []).first { $0.status == k }?.count ?? 0 }
  var body: some View {
    let inv = count("To be invoiced")
    switch family {
    #if os(iOS)
    case .accessoryInline: Label("\(inv) to invoice", systemImage: "doc.text")
    case .accessoryCircular:
      ZStack { AccessoryWidgetBackground(); VStack(spacing: 0) { Text("\(inv)").font(.system(size: 22, weight: .bold, design: .rounded)); Text("INVOICE").font(.system(size: 7, weight: .semibold)) } }
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text("To be invoiced · \(inv)").font(.headline).widgetAccentable().lineLimit(1)
        Text("Spent AED \(W.aed(f.spent))").font(.caption).privacySensitive().lineLimit(1)
        Text("\(count("LPO Pending")) LPO · \(count("Quote to be sent")) quotes").font(.caption).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
    #endif
    case .systemSmall:
      VStack(alignment: .leading, spacing: 2) {
        Head(title: "To invoice")
        Big(n: inv, color: W.orange)
        Lbl(t: "task\(inv == 1 ? "" : "s") to be invoiced")
        Spacer(minLength: 4)
        Row(color: W.amber, text: "\(count("LPO Pending")) LPO pending")
        Row(color: Color(hex: "#9aa4b2"), text: "\(count("Quote to be sent")) quotes to send")
        Stale(on: stale)
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    default:
      VStack(alignment: .leading, spacing: 6) {
        Head(title: "Finance", right: W.month(f.month))
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Lbl(t: "To be invoiced")
            Big(n: inv, color: W.orange, size: 28)
            Lbl(t: "task\(inv == 1 ? "" : "s")")
            Spacer(minLength: 6)
            Lbl(t: "Spent this month")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
              Text(W.aed(f.spent)).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).privacySensitive()
              Text("AED").font(.system(size: 10, weight: .semibold)).foregroundStyle(W.dim)
            }
          }.frame(width: family == .systemLarge ? 150 : 112, alignment: .leading)
          VStack(alignment: .leading, spacing: 4) {
            ForEach(f.statuses ?? [], id: \.status) { x in
              Row(color: Color(hex: x.color), text: x.status == "LPO Pending" ? "LPO pending" : x.status, right: "\(x.count ?? 0)", rightColor: .white)
            }
          }
        }
        if family == .systemLarge {
          Spacer(minLength: 2)
          Lbl(t: "SUBSCRIPTIONS · NEXT 7 DAYS")
          ForEach(Array((f.subsSoon ?? []).enumerated()), id: \.offset) { _, x in
            HStack { Text(x.name ?? "").font(.system(size: 12)).foregroundStyle(.white).lineLimit(1); Spacer(); Text("\(W.when(x.date, today: day)) · \(W.aed(x.amount)) AED").font(.system(size: 11)).foregroundStyle(W.dim).privacySensitive() }
          }
          if (f.subsSoon ?? []).isEmpty { Note(text: "None due this week.") }
        }
        Spacer(minLength: 0)
        Stale(on: stale)
      }
    }
  }
}

/* ---------- the widget ---------- */
struct E11Widget: Widget {
  var base: some WidgetConfiguration {
    AppIntentConfiguration(kind: "E11ConsoleWidget", intent: WConfig.self, provider: WProvider()) { e in WView(e: e) }
      .configurationDisplayName("E11 Console")
      .description("Your day at E11: tasks, content plans or Finance — whichever is yours.")
      .supportedFamilies(families)
  }
  var body: some WidgetConfiguration {
    #if os(iOS)
    // the car's widget screen (iOS 26): kept off — a tap there can't open the app
    base.disfavoredLocations(hidden, for: [.systemSmall])
    #else
    base
    #endif
  }
  #if os(iOS)
  var hidden: [WidgetLocation] { var l: [WidgetLocation] = []; if #available(iOS 26.0, *) { l.append(.carPlay) }; return l }
  #endif
  var families: [WidgetFamily] {
    #if os(iOS)
    return [.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular]
    #else
    return [.systemSmall, .systemMedium, .systemLarge]
    #endif
  }
}

@main
struct E11Widgets: WidgetBundle {
  var body: some Widget { E11Widget() }
}

/* ---------- made-up numbers for the widget gallery ---------- */
enum Sample {
  static let summary = WSummary(day: "2026-10-29", name: "", categories: ["production", "social", "finance"], main: "production",
    production: WProd(dueToday: 4, doneToday: 2, overdue: 1, waitingCD: 2, open: 9,
      next: [WTask(id: "a", title: "Kestrel | Safety Week", client: "Kestrel", color: "#ff6b6b", due: "2026-10-28"),
             WTask(id: "b", title: "Northline | Offer Pack", client: "Northline", color: "#3a7bd5", due: "2026-10-29"),
             WTask(id: "c", title: "Granite | Mini Stand", client: "Granite", color: "#3ecf8e", due: "2026-10-29"),
             WTask(id: "d", title: "Fortis | Campaign", client: "Fortis", color: "#f2a03e", due: "2026-10-30")],
      week: [WDay(day: "2026-10-26", due: 3, done: 3), WDay(day: "2026-10-27", due: 5, done: 4), WDay(day: "2026-10-28", due: 2, done: 1), WDay(day: "2026-10-29", due: 6, done: 2), WDay(day: "2026-10-30", due: 1, done: 0)]),
    social: WSoc(month: "2026-11", clients: 9, approved: 6, review: 1, changes: 1, draft: 1, missing: 0,
      today: [WPost(planId: "p", title: "Reel", client: "Northline", color: "#3a7bd5", channels: ["IG"], format: "Reel"),
              WPost(planId: "q", title: "Carousel", client: "Fortis", color: "#f2a03e", channels: ["IG", "LI"], format: "Carousel")],
      todayCount: 3, todayClients: 3, sentBack: [WBack(planId: "r", client: "Kestrel", note: "", by: "CD")], nextOccasion: WOcc(name: "National Day", date: "2026-12-02", days: 34)),
    finance: WFin(month: "2026-10", statuses: [WStat(status: "To be invoiced", color: "#ff8a4c", count: 7), WStat(status: "LPO Pending", color: "#f9be33", count: 4), WStat(status: "Quote to be sent", color: "#9aa4b2", count: 3), WStat(status: "Invoiced", color: "#3ddc97", count: 21), WStat(status: "Retainer", color: "#a875ff", count: 9)],
      spent: 12340, subsSoon: [WSub(name: "Adobe CC", date: "2026-10-31", amount: 1240), WSub(name: "Figma", date: "2026-11-02", amount: 410)], subsSoonCount: 2))
}
