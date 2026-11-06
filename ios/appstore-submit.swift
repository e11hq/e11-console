// Puts an iPhone build up for App Review through the App Store Connect API, with the key from GitHub's secrets
// (Haris 2026-11-06: "Submit it to apple"). It makes (or finds) the App Store version, sets it to release
// automatically once approved, picks the build, sets "What's New", checks the App Review sign-in details are there,
// and — only with "submit" — sends it for review. Prints what it did; never prints the key or any password.
// Usage: swift appstore-submit.swift <key.p8> <key id> <issuer id> <version> <build> <whats-new file> <check|submit>
import Foundation
import CryptoKit

let a = CommandLine.arguments
guard a.count == 8, let pem = try? String(contentsOfFile: a[1], encoding: .utf8), let key = try? P256.Signing.PrivateKey(pemRepresentation: pem),
      let whatsNew = try? String(contentsOfFile: a[6], encoding: .utf8) else { print("submit: missing key or arguments"); exit(1) }
let (kid, iss, version, build, mode) = (a[2], a[3], a[4], a[5], a[7])
let bundle = "ae.e11.console.ios"
func b64(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
let now = Int(Date().timeIntervalSince1970)
let head = b64(try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": kid, "typ": "JWT"]))
let body = b64(try! JSONSerialization.data(withJSONObject: ["iss": iss, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"] as [String: Any]))
let sig = b64(try! key.signature(for: Data("\(head).\(body)".utf8)).rawRepresentation)
let jwt = "\(head).\(body).\(sig)"

func call(_ method: String, _ path: String, _ json: [String: Any]? = nil) -> (Int, [String: Any]) {
  var r = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com" + path)!)
  r.httpMethod = method
  r.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
  if let j = json { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: j) }
  var out: (Int, [String: Any]) = (0, [:])
  let done = DispatchSemaphore(value: 0)
  URLSession.shared.dataTask(with: r) { d, resp, _ in
    out = ((resp as? HTTPURLResponse)?.statusCode ?? 0, (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:])
    done.signal()
  }.resume()
  done.wait()
  return out
}
func err(_ j: [String: Any]) -> String { ((j["errors"] as? [[String: Any]]) ?? []).map { "\($0["title"] ?? "") — \($0["detail"] ?? "")" }.joined(separator: "; ") }
func fail(_ s: String) -> Never { print("submit: STOPPED — \(s)"); exit(1) }
func list(_ j: [String: Any]) -> [[String: Any]] { (j["data"] as? [[String: Any]]) ?? [] }
func one(_ j: [String: Any]) -> [String: Any] { (j["data"] as? [String: Any]) ?? [:] }
func attrs(_ x: [String: Any]) -> [String: Any] { (x["attributes"] as? [String: Any]) ?? [:] }

// the app
let (s0, apps) = call("GET", "/v1/apps?filter[bundleId]=\(bundle)")
guard s0 == 200, let app = list(apps).first, let appId = app["id"] as? String else { fail("app not found (\(s0)) \(err(apps))") }
print("app: \(attrs(app)["name"] ?? bundle)")

// the build (processed by Apple)
let (s1, builds) = call("GET", "/v1/builds?filter[app]=\(appId)&filter[version]=\(build)&filter[preReleaseVersion.platform]=IOS&limit=5")
guard s1 == 200, let b = list(builds).first, let buildId = b["id"] as? String else { fail("build \(build) not found (\(s1)) \(err(builds))") }
let state = attrs(b)["processingState"] as? String ?? "?"
print("build \(build): \(state)")
guard state == "VALID" else { fail("build \(build) isn't ready at Apple yet (\(state))") }

// the version: found or made, released automatically once approved
let (s2, vers) = call("GET", "/v1/apps/\(appId)/appStoreVersions?filter[platform]=IOS&limit=20")
guard s2 == 200 else { fail("versions (\(s2)) \(err(vers))") }
for v in list(vers) { print("version \(attrs(v)["versionString"] ?? "?"): \(attrs(v)["appStoreState"] ?? attrs(v)["appVersionState"] ?? "?")") }
var verId = list(vers).first { (attrs($0)["versionString"] as? String) == version }?["id"] as? String
if verId == nil {
  let (s, made) = call("POST", "/v1/appStoreVersions", ["data": ["type": "appStoreVersions",
    "attributes": ["platform": "IOS", "versionString": version, "releaseType": "AFTER_APPROVAL"],
    "relationships": ["app": ["data": ["type": "apps", "id": appId]]]]])
  guard s == 201, let id = one(made)["id"] as? String else { fail("couldn't make version \(version) (\(s)) \(err(made))") }
  verId = id; print("version \(version): made")
} else {
  let (s, j) = call("PATCH", "/v1/appStoreVersions/\(verId!)", ["data": ["type": "appStoreVersions", "id": verId!, "attributes": ["releaseType": "AFTER_APPROVAL"]]])
  guard s == 200 else { fail("couldn't set automatic release (\(s)) \(err(j))") }
  print("version \(version): found")
}
let vid = verId!
print("release: automatically once approved")

// its build
let (s3, j3) = call("PATCH", "/v1/appStoreVersions/\(vid)/relationships/build", ["data": ["type": "builds", "id": buildId]])
guard s3 == 204 || s3 == 200 else { fail("couldn't pick build \(build) (\(s3)) \(err(j3))") }
print("build \(build): picked for \(version)")

// What's New, in every language the version has
let (s4, locs) = call("GET", "/v1/appStoreVersions/\(vid)/appStoreVersionLocalizations")
guard s4 == 200, !list(locs).isEmpty else { fail("no texts on the version (\(s4)) \(err(locs))") }
for l in list(locs) {
  guard let lid = l["id"] as? String else { continue }
  let (s, j) = call("PATCH", "/v1/appStoreVersionLocalizations/\(lid)", ["data": ["type": "appStoreVersionLocalizations", "id": lid, "attributes": ["whatsNew": whatsNew.trimmingCharacters(in: .whitespacesAndNewlines)]]])
  guard s == 200 else { fail("couldn't set What's New (\(attrs(l)["locale"] ?? "")) (\(s)) \(err(j))") }
  let shots = attrs(l)["description"] as? String
  print("What's New set (\(attrs(l)["locale"] ?? "?")); description \(shots?.isEmpty == false ? "there" : "MISSING")")
}

// App Review sign-in details (filled by Haris in App Store Connect; only checked here, never printed)
let (s5, rd) = call("GET", "/v1/appStoreVersions/\(vid)/appStoreReviewDetail")
let r = attrs(one(rd))
let signIn = (r["demoAccountName"] as? String ?? "").isEmpty == false && (r["demoAccountRequired"] as? Bool ?? false)
print("App Review details: \(s5 == 200 ? "there" : "MISSING (\(s5))"); sign-in account \(signIn ? "there" : "MISSING"); notes \((r["notes"] as? String ?? "").isEmpty ? "MISSING" : "there")")

if mode != "submit" { print("submit: checked only — nothing sent to Apple"); exit(0) }
guard s5 == 200, signIn else { fail("the App Review sign-in isn't on this version — it must be added in App Store Connect first") }

// sent for review
let (s6, sub) = call("POST", "/v1/reviewSubmissions", ["data": ["type": "reviewSubmissions", "attributes": ["platform": "IOS"],
  "relationships": ["app": ["data": ["type": "apps", "id": appId]]]]])
guard s6 == 201, let subId = one(sub)["id"] as? String else { fail("couldn't start the submission (\(s6)) \(err(sub))") }
let (s7, item) = call("POST", "/v1/reviewSubmissionItems", ["data": ["type": "reviewSubmissionItems",
  "relationships": ["reviewSubmission": ["data": ["type": "reviewSubmissions", "id": subId]], "appStoreVersion": ["data": ["type": "appStoreVersions", "id": vid]]]]])
guard s7 == 201 else { fail("couldn't add \(version) to the submission (\(s7)) \(err(item))") }
let (s8, done) = call("PATCH", "/v1/reviewSubmissions/\(subId)", ["data": ["type": "reviewSubmissions", "id": subId, "attributes": ["submitted": true]]])
guard s8 == 200 else { fail("couldn't send for review (\(s8)) \(err(done))") }
print("submit: \(version) (\(build)) SENT FOR REVIEW — \(attrs(one(done))["state"] ?? "")")
