import UIKit

/* Your photo — one, for everywhere it shows (Haris 2026-11-03): the top corner on every screen and the Me tab both draw
   this one. The app fetches it itself (signed in as you), keeps it on the phone, and shows the kept one at once; the
   page's own drawing of it is never used (drawn before the picture had loaded it came out black). No photo yet: your
   initials in your colour — never black, never an empty icon. A fetch that fails is tried again; the kept one stays. */
final class MePhoto {
  static let shared = MePhoto()
  private(set) var image: UIImage? = DiskPics.get("me-photo").flatMap { UIImage(data: $0) }
  private(set) var initials: String?, color: UIColor?
  private var url: String?, fetched = false, asking = false
  private var watchers: [() -> Void] = []
  var fetch: ((URL, @escaping (UIImage?) -> Void) -> Void)?

  func watch(_ f: @escaping () -> Void) { watchers.append(f) }
  private func changed() { watchers.forEach { $0() } }

  // where it is on the server (as the page says; nothing said: the kept one stays)
  func source(_ s: String?) {
    guard let s = s, !s.isEmpty else { return }
    if s == url { if !fetched { ask(4) }; return }
    url = s; fetched = false
    ask(4)
  }
  private func ask(_ left: Int) {
    guard !asking, let s = url, let u = URL(string: s), let f = fetch else { return }
    asking = true
    f(u) { [weak self] img in
      guard let self = self else { return }
      self.asking = false
      guard s == self.url else { return }
      if let img = img, img.size.width > 0 { self.fetched = true; self.set(img) }
      else if left > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.ask(left - 1) } }
    }
  }
  // the photo a screen fetched for you already (Home's people): taken while ours hasn't come
  func offer(_ img: UIImage) { if !fetched, image == nil || image?.size != img.size { set(img) } }
  private func set(_ img: UIImage) {
    image = img
    if let d = img.jpegData(compressionQuality: 0.9) { DiskPics.put("me-photo", d) }
    changed()
  }
  // who you are, for the initials when there's no photo
  func who(_ ini: String?, _ col: UIColor?) {
    guard let i = ini, !i.isEmpty, i != initials || col != color else { return }
    initials = i; color = col
    if image == nil { changed() }
  }
  // a round picture of you at this size: the photo, else your initials in your colour (nil only before anything's known)
  func picture(_ size: CGFloat) -> UIImage? {
    if image == nil && initials == nil { return nil }
    return roundPic(image, initials: initials, color: color, size: size)
  }
}
