// Registers this Mac (the build Mac) as a development Mac of the Apple team, once, through the App Store Connect API
// with the key from GitHub's secrets. Xcode's automatic signing needs one registered Mac to make the Mac app's
// development profile (needed since the widget shares a Keychain group with the app). Prints only what it did.
// Usage: swift register-mac.swift <key.p8> <key id> <issuer id> <provisioning UDID>
import Foundation
import CryptoKit

let a = CommandLine.arguments
guard a.count == 5, let pem = try? String(contentsOfFile: a[1], encoding: .utf8), let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else { print("register-mac: missing key or arguments"); exit(1) }
let (kid, iss, udid) = (a[2], a[3], a[4])
func b64(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
let now = Int(Date().timeIntervalSince1970)
let head = b64(try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": kid, "typ": "JWT"]))
let body = b64(try! JSONSerialization.data(withJSONObject: ["iss": iss, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"] as [String: Any]))
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
let q = udid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) ?? udid
let (s1, found) = call("GET", "/v1/devices?filter[udid]=\(q)&limit=5")
if s1 == 200, let list = found["data"] as? [Any], !list.isEmpty { print("register-mac: this Mac is already registered"); exit(0) }
if s1 != 200 { print("register-mac: couldn't list devices (\(s1)) \((found["errors"] as? [[String: Any]])?.first?["detail"] ?? "")") }
let (s2, made) = call("POST", "/v1/devices", ["data": ["type": "devices", "attributes": ["name": "E11 build Mac", "platform": "MAC_OS", "udid": udid]]])
if s2 == 201 { print("register-mac: registered this Mac as \"E11 build Mac\""); exit(0) }
print("register-mac: couldn't register (\(s2)) \((made["errors"] as? [[String: Any]])?.first?["detail"] ?? "")")
exit(1)
