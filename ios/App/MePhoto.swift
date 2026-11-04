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
  // (never from inside itself: a screen that's told and answers by offering a picture would tell it again — two screens
  //  with different photos of you, after View as…, sent it round and round until the app crashed: 1375, 2026-11-04)
  private var telling = false
  private func changed() { guard !telling else { return }; telling = true; watchers.forEach { $0() }; telling = false }

  // whose it is: another person (View as…, signed in as someone else) — the last one's photo goes, theirs is fetched (or
  // their initials) — Haris 2026-11-04: Amelia's tab kept Haris's photo
  private var who = UserDefaults.standard.string(forKey: "e11_me_photo_who")
  func person(_ id: String) {
    guard id != who else { return }
    who = id; UserDefaults.standard.set(id, forKey: "e11_me_photo_who")
    // (also the first time it's told — the kept photo can't be known to be this person's: fetched again for them)
    image = nil; url = nil; fetched = false; asking = false
    DiskPics.put("me-photo", Data())
    changed()
  }
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
      guard s == self.url else { self.ask(4); return }   // (a newer one was asked for while this one was on its way: that one now)
      if let img = img, img.size.width > 0 { self.fetched = true; self.set(img) }
      else if left > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.ask(left - 1) } }
    }
  }
  // the photo a screen fetched for you already (Home's people): taken while ours hasn't come
  // (only while there's none at all — never swapped for another screen's offer)
  func offer(_ img: UIImage, for id: String) { if !fetched, image == nil, who == nil || id == who { set(img) } }
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
