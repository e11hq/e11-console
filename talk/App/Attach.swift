import UIKit
import Photos
import PhotosUI
import Contacts
import ContactsUI
import MapKit
import CoreLocation
import VisionKit
import UniformTypeIdentifiers
import AVFoundation

/* The + sheet and what it opens (canvas "Attach panel — Talk & Console": V9, Claude's style; W1–W6, T4, T6 — Haris
   2026-11-16). The same file in E11 Talk and E11 Console's iPhone app.
   - AttachSheet: iPhone's own sheet — ✕ · where it goes · All Photos / Next (3); your recent photos as a row of big tiles
     (tap to tick, the number on each); then Apple's grouped list (Camera · Files · Contact · Location, or Camera · Files).
   - FilesSheet: "Choose Files · Send original files up to 1 GB in size." — Choose from Files · Choose Photo or Video ·
     Scan Document.
   - ContactPreview: a picked contact's numbers and emails, each ticked; untick any, then Send.
   - PlacePicker: Apple's map with your dot, Send Current Location, and the places nearby.
   - MapsChooser: a place in a chat or comment tapped — the map apps on this iPhone.
   Everything here is Apple's own part (sheet, list, picker, camera, scanner, contact views, map), set to our look; ours
   only the row of photos, inside Apple's sheet. */

enum AttachChoice { case photos([PHAsset]), allPhotos, camera, files, contact, location }

struct AttachRow {
  let key: String, title: String, symbol: String
  static let camera = AttachRow(key: "camera", title: "Camera", symbol: "camera")
  static let files = AttachRow(key: "files", title: "Files", symbol: "doc")
  static let contact = AttachRow(key: "contact", title: "Contact", symbol: "person.crop.circle")
  static let location = AttachRow(key: "location", title: "Location", symbol: "location")
}

enum Attach {
  static let maxBytes = 1_000_000_000   // (files up to 1 GB, in the iPhone apps — Haris 2026-11-16)
  static func size(_ url: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0 }
  static func tooBig(_ url: URL) -> Bool { size(url) > maxBytes }
  // a sheet sized to what it holds (iPhone's own sheet, its own grabber)
  static func sheet(_ vc: UIViewController, height: CGFloat) {
    vc.modalPresentationStyle = .pageSheet
    if let s = vc.sheetPresentationController {
      s.detents = [.custom(identifier: .init("fit")) { _ in height }]
      s.prefersGrabberVisible = true
      s.preferredCornerRadius = 32
    }
  }
  // the round ✕ in a sheet's corner — Apple's glass where there is glass
  static func closeButton() -> UIButton {
    let b = UIButton(type: .system)
    var c: UIButton.Configuration
    if #available(iOS 26.0, *) { c = .glass() } else { c = .gray(); c.cornerStyle = .capsule }
    c.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    c.baseForegroundColor = .label
    b.configuration = c
    b.accessibilityLabel = "Close"
    b.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 44), b.heightAnchor.constraint(equalToConstant: 44)])
    return b
  }
  static var bottomInset: CGFloat {
    (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 34
  }
}

// ---------- the + sheet ----------
final class AttachSheet: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UITableViewDataSource, UITableViewDelegate,
                         PHPhotoLibraryChangeObserver, UIAdaptivePresentationControllerDelegate {
  static let tileW: CGFloat = 120, tileH: CGFloat = 128, rowH: CGFloat = 54
  private let titleText: String, rows: [AttachRow], nextWord: String, tint: UIColor
  var onChoice: ((AttachChoice?) -> Void)?   // (nil: closed with nothing chosen)
  private var assets: PHFetchResult<PHAsset>?
  private var picked: [String] = []   // (ticked, in the order they were ticked)
  private let images = PHCachingImageManager()
  private var strip: UICollectionView!
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private let closeB = Attach.closeButton(), titleL = UILabel(), rightB = UIButton(type: .system), allow = UIButton(type: .system)

  init(title: String, rows: [AttachRow], nextWord: String, tint: UIColor) {
    titleText = title; self.rows = rows; self.nextWord = nextWord; self.tint = tint
    super.init(nibName: nil, bundle: nil)
    let h = 20 + 44 + 16 + AttachSheet.tileH + 18 + CGFloat(rows.count) * AttachSheet.rowH + 16 + Attach.bottomInset
    Attach.sheet(self, height: h)
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    presentationController?.delegate = self
    closeB.addAction(UIAction { [weak self] _ in self?.finish(nil) }, for: .touchUpInside)
    titleL.text = titleText; titleL.font = .systemFont(ofSize: 17, weight: .semibold); titleL.textAlignment = .center; titleL.lineBreakMode = .byTruncatingTail
    titleL.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    rightB.addAction(UIAction { [weak self] _ in self?.right() }, for: .touchUpInside)
    rightB.setContentHuggingPriority(.required, for: .horizontal); rightB.setContentCompressionResistancePriority(.required, for: .horizontal)
    setRight(animated: false)
    let head = UIStackView(arrangedSubviews: [closeB, titleL, rightB]); head.alignment = .center; head.spacing = 10

    let lay = UICollectionViewFlowLayout(); lay.scrollDirection = .horizontal; lay.itemSize = CGSize(width: AttachSheet.tileW, height: AttachSheet.tileH)
    lay.minimumLineSpacing = 4
    strip = UICollectionView(frame: .zero, collectionViewLayout: lay)
    strip.register(PhotoTile.self, forCellWithReuseIdentifier: "t")
    strip.dataSource = self; strip.delegate = self; strip.backgroundColor = .clear; strip.showsHorizontalScrollIndicator = false
    strip.layer.cornerRadius = 22; strip.layer.cornerCurve = .continuous; strip.clipsToBounds = true
    // (no access to Photos: one tile asking for it — All Photos still works, Apple's picker needs none)
    var ac = UIButton.Configuration.filled()
    ac.baseBackgroundColor = .secondarySystemGroupedBackground; ac.baseForegroundColor = tint
    ac.image = UIImage(systemName: "photo.on.rectangle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26)); ac.imagePlacement = .top; ac.imagePadding = 8
    ac.title = "Allow Access to Photos"; ac.subtitle = "To see your recent photos here"
    ac.titleAlignment = .center; ac.background.cornerRadius = 22
    ac.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 16, weight: .semibold); return a }
    ac.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 13); a.foregroundColor = .secondaryLabel; return a }
    allow.configuration = ac; allow.isHidden = true
    allow.addAction(UIAction { _ in if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }, for: .touchUpInside)

    table.dataSource = self; table.delegate = self; table.isScrollEnabled = false; table.rowHeight = AttachSheet.rowH
    table.backgroundColor = .clear; table.sectionHeaderTopPadding = 0; table.contentInset = .zero
    table.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 0.01)); table.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 0.01))
    table.register(UITableViewCell.self, forCellReuseIdentifier: "r")

    for v in [head, strip!, allow, table] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
    NSLayoutConstraint.activate([
      head.topAnchor.constraint(equalTo: view.topAnchor, constant: 20), head.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      head.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), head.heightAnchor.constraint(equalToConstant: 44),
      strip.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 16), strip.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      strip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), strip.heightAnchor.constraint(equalToConstant: AttachSheet.tileH),
      allow.topAnchor.constraint(equalTo: strip.topAnchor), allow.bottomAnchor.constraint(equalTo: strip.bottomAnchor),
      allow.leadingAnchor.constraint(equalTo: strip.leadingAnchor), allow.trailingAnchor.constraint(equalTo: strip.trailingAnchor),
      table.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 18), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    photosAccess()
  }

  // ---------- Photos: asked once (Apple's own question), then the recents, newest first ----------
  private func photosAccess() {
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .authorized, .limited: load()
    case .notDetermined:
      strip.alpha = 0
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in DispatchQueue.main.async { self?.photosAccess() } }
    default: strip.isHidden = true; allow.isHidden = false
    }
  }
  private func load() {
    let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    o.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
    assets = PHAsset.fetchAssets(with: o)
    strip.reloadData()
    PHPhotoLibrary.shared().register(self)
    if strip.alpha == 0 { UIView.animate(withDuration: 0.2) { self.strip.alpha = 1 } }
  }
  func photoLibraryDidChange(_ change: PHChange) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let a = self.assets, let d = change.changeDetails(for: a) else { return }
      self.assets = d.fetchResultAfterChanges
      if d.hasIncrementalChanges {
        self.strip.performBatchUpdates {
          if let r = d.removedIndexes, !r.isEmpty { self.strip.deleteItems(at: r.map { IndexPath(item: $0, section: 0) }) }
          if let i = d.insertedIndexes, !i.isEmpty { self.strip.insertItems(at: i.map { IndexPath(item: $0, section: 0) }) }
          if let c = d.changedIndexes, !c.isEmpty { self.strip.reloadItems(at: c.map { IndexPath(item: $0, section: 0) }) }
        }
      } else { self.strip.reloadData() }
      let ids = Set((0..<(self.assets?.count ?? 0)).compactMap { self.assets?.object(at: $0).localIdentifier })
      let before = self.picked.count; self.picked.removeAll { !ids.contains($0) }
      if before != self.picked.count { self.badges(); self.setRight(animated: true) }
    }
  }
  func collectionView(_ c: UICollectionView, numberOfItemsInSection s: Int) -> Int { assets?.count ?? 0 }
  func collectionView(_ c: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
    let cell = c.dequeueReusableCell(withReuseIdentifier: "t", for: ip) as! PhotoTile
    guard let a = assets?.object(at: ip.item) else { return cell }
    cell.show(a, images: images, tint: tint, number: picked.firstIndex(of: a.localIdentifier).map { $0 + 1 })
    return cell
  }
  func collectionView(_ c: UICollectionView, didSelectItemAt ip: IndexPath) {
    guard let id = assets?.object(at: ip.item).localIdentifier else { return }
    if let i = picked.firstIndex(of: id) { picked.remove(at: i) } else { picked.append(id) }
    UISelectionFeedbackGenerator().selectionChanged()
    badges(); setRight(animated: true)
  }
  // (only the numbers change — the tiles stay as they are)
  private func badges() {
    for case let cell as PhotoTile in strip.visibleCells { if let id = cell.assetId { cell.setNumber(picked.firstIndex(of: id).map { $0 + 1 }, tint: tint) } }
  }
  private func setRight(animated: Bool) {
    var c: UIButton.Configuration
    if picked.isEmpty { c = .plain(); c.title = "All Photos"; c.baseForegroundColor = .label }
    else { c = .filled(); c.title = "\(nextWord) (\(picked.count))"; c.baseBackgroundColor = tint; c.baseForegroundColor = .white; c.cornerStyle = .capsule }
    let weight: UIFont.Weight = picked.isEmpty ? .regular : .semibold
    c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 16, weight: weight); return a }
    if animated { UIView.transition(with: rightB, duration: 0.2, options: .transitionCrossDissolve) { self.rightB.configuration = c } }
    else { rightB.configuration = c }
  }
  private func right() {
    if picked.isEmpty { finish(.allPhotos); return }
    let r = PHAsset.fetchAssets(withLocalIdentifiers: picked, options: nil)
    var by: [String: PHAsset] = [:]; r.enumerateObjects { a, _, _ in by[a.localIdentifier] = a }
    finish(.photos(picked.compactMap { by[$0] }))
  }

  // ---------- Apple's list ----------
  func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { rows.count }
  func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let cell = t.dequeueReusableCell(withIdentifier: "r", for: ip)
    var c = cell.defaultContentConfiguration()
    c.text = rows[ip.row].title; c.textProperties.font = .systemFont(ofSize: 17)
    c.image = UIImage(systemName: rows[ip.row].symbol); c.imageProperties.tintColor = .label
    c.imageToTextPadding = 16
    cell.contentConfiguration = c
    cell.backgroundColor = .secondarySystemGroupedBackground
    return cell
  }
  func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
    t.deselectRow(at: ip, animated: true)
    switch rows[ip.row].key {
    case "camera": finish(.camera)
    case "files": finish(.files)
    case "contact": finish(.contact)
    default: finish(.location)
    }
  }

  private func finish(_ c: AttachChoice?) {
    let done = onChoice; onChoice = nil
    dismiss(animated: true) { done?(c) }
  }
  // (pulled down: closed with nothing chosen)
  func presentationControllerDidDismiss(_ p: UIPresentationController) { let done = onChoice; onChoice = nil; done?(nil) }
}

final class PhotoTile: UICollectionViewCell {
  private let pic = UIImageView(), badge = UILabel(), dur = UILabel()
  private(set) var assetId: String?
  private var req: PHImageRequestID?
  private weak var mgr: PHImageManager?
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.contentMode = .scaleAspectFill; pic.clipsToBounds = true; pic.backgroundColor = .tertiarySystemFill
    badge.font = .systemFont(ofSize: 13, weight: .bold); badge.textAlignment = .center; badge.textColor = .white
    badge.layer.cornerRadius = 12; badge.layer.borderWidth = 2; badge.layer.borderColor = UIColor.white.cgColor; badge.clipsToBounds = true
    dur.font = .systemFont(ofSize: 12, weight: .semibold); dur.textColor = .white
    dur.layer.shadowColor = UIColor.black.cgColor; dur.layer.shadowOpacity = 0.5; dur.layer.shadowRadius = 2; dur.layer.shadowOffset = .zero
    for v in [pic, badge, dur] { v.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(v) }
    NSLayoutConstraint.activate([
      pic.topAnchor.constraint(equalTo: contentView.topAnchor), pic.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      pic.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), pic.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7), badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
      badge.widthAnchor.constraint(equalToConstant: 24), badge.heightAnchor.constraint(equalToConstant: 24),
      dur.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8), dur.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
    ])
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  override func prepareForReuse() { super.prepareForReuse(); if let r = req { mgr?.cancelImageRequest(r) }; req = nil; pic.image = nil }
  func show(_ a: PHAsset, images: PHCachingImageManager, tint: UIColor, number: Int?) {
    assetId = a.localIdentifier; mgr = images
    let o = PHImageRequestOptions(); o.deliveryMode = .opportunistic; o.isNetworkAccessAllowed = true; o.resizeMode = .fast
    let s = UIScreen.main.scale
    req = images.requestImage(for: a, targetSize: CGSize(width: AttachSheet.tileW * s, height: AttachSheet.tileH * s), contentMode: .aspectFill, options: o) { [weak self] i, _ in
      guard let self = self, self.assetId == a.localIdentifier else { return }
      self.pic.image = i
    }
    if a.mediaType == .video { let t = Int(a.duration.rounded()); dur.text = String(format: "%d:%02d", t / 60, t % 60); dur.isHidden = false } else { dur.isHidden = true }
    accessibilityLabel = a.mediaType == .video ? "Video" : "Photo"
    setNumber(number, tint: tint)
  }
  func setNumber(_ n: Int?, tint: UIColor) {
    UIView.transition(with: badge, duration: 0.15, options: .transitionCrossDissolve) {
      self.badge.text = n.map(String.init) ?? ""
      self.badge.backgroundColor = n == nil ? UIColor.black.withAlphaComponent(0.15) : tint
    }
    accessibilityValue = n.map { "Selected, \($0)" }
  }
}

// ---------- Files: originals up to 1 GB (WhatsApp's) ----------
final class FilesSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
  private let rows = [("files", "Choose from Files", "doc"), ("originals", "Choose Photo or Video", "photo.on.rectangle"), ("scan", "Scan Document", "doc.viewfinder")]
  var onPick: ((String?) -> Void)?
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  init() {
    super.init(nibName: nil, bundle: nil)
    Attach.sheet(self, height: 20 + 60 + 14 + CGFloat(rows.count) * AttachSheet.rowH + 16 + Attach.bottomInset)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    let t = UILabel(); t.text = "Choose Files"; t.font = .systemFont(ofSize: 17, weight: .semibold); t.textAlignment = .center
    let s = UILabel(); s.text = "Send original files up to 1 GB in size."; s.font = .systemFont(ofSize: 15); s.textColor = .secondaryLabel; s.textAlignment = .center; s.numberOfLines = 2
    let words = UIStackView(arrangedSubviews: [t, s]); words.axis = .vertical; words.spacing = 3
    let x = Attach.closeButton(); x.addAction(UIAction { [weak self] _ in self?.done(nil) }, for: .touchUpInside)
    table.dataSource = self; table.delegate = self; table.isScrollEnabled = false; table.rowHeight = AttachSheet.rowH
    table.backgroundColor = .clear; table.sectionHeaderTopPadding = 0
    table.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 0.01))
    table.register(UITableViewCell.self, forCellReuseIdentifier: "r")
    for v in [words, x, table] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
    NSLayoutConstraint.activate([
      words.topAnchor.constraint(equalTo: view.topAnchor, constant: 22), words.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      words.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 70),
      x.topAnchor.constraint(equalTo: view.topAnchor, constant: 18), x.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      table.topAnchor.constraint(equalTo: words.bottomAnchor, constant: 14), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }
  func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { rows.count }
  func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let cell = t.dequeueReusableCell(withIdentifier: "r", for: ip)
    var c = cell.defaultContentConfiguration(); c.text = rows[ip.row].1; c.image = UIImage(systemName: rows[ip.row].2); c.imageProperties.tintColor = .label; c.imageToTextPadding = 16
    cell.contentConfiguration = c; cell.backgroundColor = .secondarySystemGroupedBackground
    return cell
  }
  func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) { t.deselectRow(at: ip, animated: true); done(rows[ip.row].0) }
  private func done(_ k: String?) { let f = onPick; onPick = nil; dismiss(animated: true) { f?(k) } }
}

// ---------- picked photos and videos to files ----------
struct AttachFile { let url: URL; let kind: String; let name: String }   // (kind: photo, video or file)
enum AttachExport {
  // photos ticked in the row: as Photos picks them today (Compatible — JPEG, H.264), in the order ticked
  static func compatible(_ assets: [PHAsset], done: @escaping ([AttachFile]) -> Void) {
    var out = [AttachFile?](repeating: nil, count: assets.count)
    let g = DispatchGroup()
    for (i, a) in assets.enumerated() {
      g.enter()
      let base = ((PHAssetResource.assetResources(for: a).first?.originalFilename ?? (a.mediaType == .video ? "Video" : "Photo")) as NSString).deletingPathExtension
      if a.mediaType == .video {
        let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true; o.version = .current; o.deliveryMode = .highQualityFormat
        PHImageManager.default().requestExportSession(forVideo: a, options: o, exportPreset: AVAssetExportPresetHighestQuality) { s, _ in
          guard let s = s else { g.leave(); return }
          let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
          s.outputURL = u; s.outputFileType = .mp4
          s.exportAsynchronously {
            let ok = s.status == .completed
            DispatchQueue.main.async { if ok { out[i] = AttachFile(url: u, kind: "video", name: base + ".mp4") }; g.leave() }
          }
        }
      } else {
        let o = PHImageRequestOptions(); o.isNetworkAccessAllowed = true; o.version = .current; o.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: a, options: o) { d, uti, _, _ in
          guard let d = d else { DispatchQueue.main.async { g.leave() }; return }
          let type = uti.flatMap { UTType($0) }
          let keep = type.map { $0.conforms(to: .jpeg) || $0.conforms(to: .png) || $0.conforms(to: .gif) } ?? false
          let data = keep ? d : jpeg(d) ?? d
          let ext = keep ? (type?.preferredFilenameExtension ?? "jpg") : "jpg"
          let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
          let ok = (try? data.write(to: u)) != nil
          DispatchQueue.main.async { if ok { out[i] = AttachFile(url: u, kind: "photo", name: base + "." + ext) }; g.leave() }
        }
      }
    }
    g.notify(queue: .main) { done(out.compactMap { $0 }) }
  }
  // (an iPhone photo — HEIC — as JPEG, its details and turn kept)
  static func jpeg(_ d: Data) -> Data? {
    guard let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
    let out = NSMutableData()
    guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImageFromSource(dst, src, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    return CGImageDestinationFinalize(dst) ? out as Data : nil
  }
}

// ---------- Choose Photo or Video: the originals, exactly as in Photos (HEIC, HEVC…), sent as files ----------
final class OriginalsPicker: NSObject, PHPickerViewControllerDelegate {
  private var done: (([AttachFile]) -> Void)?
  private static var live: OriginalsPicker?
  static func present(from vc: UIViewController, done: @escaping ([AttachFile]) -> Void) {
    let me = OriginalsPicker(); me.done = done; live = me
    var c = PHPickerConfiguration(photoLibrary: .shared()); c.selectionLimit = 10; c.filter = .any(of: [.images, .videos])
    c.preferredAssetRepresentationMode = .current
    let p = PHPickerViewController(configuration: c); p.delegate = me
    vc.present(p, animated: true)
  }
  func picker(_ p: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    p.dismiss(animated: true)
    var out = [AttachFile?](repeating: nil, count: results.count)
    let g = DispatchGroup()
    for (i, r) in results.enumerated() {
      let ip = r.itemProvider
      guard let type = ip.registeredTypeIdentifiers.first(where: { UTType($0).map { $0.conforms(to: .image) || $0.conforms(to: .movie) } ?? false }) else { continue }
      g.enter()
      ip.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
        guard let url = url else { DispatchQueue.main.async { g.leave() }; return }
        let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : url.pathExtension
        let name = ip.suggestedName.map { $0.hasSuffix("." + ext) ? $0 : $0 + "." + ext } ?? url.lastPathComponent
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        let ok = (try? FileManager.default.copyItem(at: url, to: copy)) != nil
        DispatchQueue.main.async { if ok { out[i] = AttachFile(url: copy, kind: "file", name: name) }; g.leave() }
      }
    }
    g.notify(queue: .main) { [weak self] in self?.done?(out.compactMap { $0 }); self?.done = nil; OriginalsPicker.live = nil }
  }
}

// ---------- Scan Document: Apple's scanner, the pages as one PDF ----------
final class DocScanner: NSObject, VNDocumentCameraViewControllerDelegate {
  private var done: ((AttachFile?) -> Void)?
  private static var live: DocScanner?
  static func present(from vc: UIViewController, done: @escaping (AttachFile?) -> Void) {
    guard VNDocumentCameraViewController.isSupported else { done(nil); return }
    let me = DocScanner(); me.done = done; live = me
    let s = VNDocumentCameraViewController(); s.delegate = me
    vc.present(s, animated: true)
  }
  func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    let name = "Scan \(f.string(from: Date())).pdf"
    let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    let first = scan.imageOfPage(at: 0)
    let r = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size))
    try? r.writePDF(to: u) { ctx in
      for i in 0..<scan.pageCount {
        let img = scan.imageOfPage(at: i)
        ctx.beginPage(withBounds: CGRect(origin: .zero, size: img.size), pageInfo: [:])
        img.draw(in: CGRect(origin: .zero, size: img.size))
      }
    }
    c.dismiss(animated: true) { [weak self] in self?.end(FileManager.default.fileExists(atPath: u.path) ? AttachFile(url: u, kind: "file", name: name) : nil) }
  }
  func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { c.dismiss(animated: true) { [weak self] in self?.end(nil) } }
  func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError e: Error) { c.dismiss(animated: true) { [weak self] in self?.end(nil) } }
  private func end(_ f: AttachFile?) { done?(f); done = nil; DocScanner.live = nil }
}

// ---------- a contact: iPhone's own picker, then the preview — untick what's not to go ----------
struct SharedContact: Codable, Equatable, Hashable {
  struct Item: Codable, Equatable, Hashable { var label: String; var value: String }
  var name: String; var phones: [Item]; var emails: [Item]
  init(name: String, phones: [Item], emails: [Item]) { self.name = name; self.phones = phones; self.emails = emails }
  init?(_ j: [String: Any]?) {
    guard let j = j, let n = j["name"] as? String, !n.isEmpty else { return nil }
    let items = { (a: Any?) in ((a as? [[String: Any]]) ?? []).compactMap { x -> Item? in (x["value"] as? String).map { Item(label: x["label"] as? String ?? "", value: $0) } } }
    name = n; phones = items(j["phones"]); emails = items(j["emails"])
  }
  var json: [String: Any] { ["name": name, "phones": phones.map { ["label": $0.label, "value": $0.value] }, "emails": emails.map { ["label": $0.label, "value": $0.value] }] }
  var first: String { phones.first?.value ?? emails.first?.value ?? "" }
  // as iPhone's own contact (for its contact card and New Contact)
  var contact: CNMutableContact {
    let c = CNMutableContact()
    let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
    c.givenName = parts.first ?? name; c.familyName = parts.count > 1 ? parts[1] : ""
    c.phoneNumbers = phones.map { CNLabeledValue(label: SharedContact.label($0.label), value: CNPhoneNumber(stringValue: $0.value)) }
    c.emailAddresses = emails.map { CNLabeledValue(label: SharedContact.label($0.label), value: $0.value as NSString) }
    return c
  }
  private static func label(_ l: String) -> String {
    switch l.lowercased() { case "mobile": return CNLabelPhoneNumberMobile; case "iphone": return CNLabelPhoneNumberiPhone; case "home": return CNLabelHome
    case "work": return CNLabelWork; case "main": return CNLabelPhoneNumberMain; default: return l.isEmpty ? CNLabelOther : l }
  }
}

final class ContactFlow: NSObject, CNContactPickerDelegate {
  private static var live: ContactFlow?
  private weak var host: UIViewController?
  private var send: ((SharedContact) -> Void)?
  static func present(from vc: UIViewController, tint: UIColor, send: @escaping (SharedContact) -> Void) {
    let me = ContactFlow(); me.host = vc; me.send = send; live = me
    let p = CNContactPickerViewController(); p.delegate = me
    p.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0")
    vc.present(p, animated: true)
  }
  func contactPicker(_ p: CNContactPickerViewController, didSelect c: CNContact) {
    // (only what the picker gave — reading a detail it didn't fetch would stop the app)
    let has = { (k: String) in c.isKeyAvailable(k) }
    let full = [has(CNContactGivenNameKey) ? c.givenName : "", has(CNContactFamilyNameKey) ? c.familyName : ""].filter { !$0.isEmpty }.joined(separator: " ")
    let name = full.isEmpty ? (has(CNContactOrganizationNameKey) ? c.organizationName : "") : full
    let lab = { (l: String?) in l.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "" }
    let sc = SharedContact(name: name.isEmpty ? "Contact" : name,
                           phones: has(CNContactPhoneNumbersKey) ? c.phoneNumbers.map { .init(label: lab($0.label), value: $0.value.stringValue) } : [],
                           emails: has(CNContactEmailAddressesKey) ? c.emailAddresses.map { .init(label: lab($0.label), value: $0.value as String) } : [])
    let photo = has(CNContactThumbnailImageDataKey) ? c.thumbnailImageData.flatMap(UIImage.init(data:)) : nil
    // (Apple's picker closes itself; the preview comes up once it has)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
      guard let self = self, let h = self.host else { ContactFlow.live = nil; return }
      let v = ContactPreview(sc, photo: photo)
      v.onSend = { [weak self] picked in self?.send?(picked); ContactFlow.live = nil }
      v.onClose = { ContactFlow.live = nil }
      let nav = UINavigationController(rootViewController: v); nav.modalPresentationStyle = .pageSheet
      h.present(nav, animated: true)
    }
  }
  func contactPickerDidCancel(_ p: CNContactPickerViewController) { ContactFlow.live = nil }
}

final class ContactPreview: UITableViewController {
  private let c: SharedContact, photo: UIImage?
  private var on: Set<String> = []
  var onSend: ((SharedContact) -> Void)?
  var onClose: (() -> Void)?
  private var items: [(String, SharedContact.Item)] { c.phones.map { ("p", $0) } + c.emails.map { ("e", $0) } }
  init(_ c: SharedContact, photo: UIImage?) {
    self.c = c; self.photo = photo
    super.init(style: .insetGrouped)
    on = Set(items.map { $0.0 + $0.1.value })
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Send Contact"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) { self?.onClose?() } })
    let sendB = UIBarButtonItem(title: "Send", primaryAction: UIAction { [weak self] _ in self?.go() })
    if #available(iOS 26.0, *) { sendB.style = .prominent } else { sendB.style = .done }
    navigationItem.rightBarButtonItem = sendB
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "r")
    // the person: their picture (or initials) and name
    let head = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 150))
    let pic = UIImageView(), ini = UILabel(), name = UILabel()
    pic.layer.cornerRadius = 42; pic.clipsToBounds = true; pic.contentMode = .scaleAspectFill; pic.backgroundColor = .systemGray
    pic.image = photo
    ini.text = c.name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    ini.font = .systemFont(ofSize: 30, weight: .semibold); ini.textColor = .white; ini.textAlignment = .center; ini.isHidden = photo != nil
    name.text = c.name; name.font = .systemFont(ofSize: 22, weight: .semibold); name.textAlignment = .center
    for v in [pic, ini, name] { v.translatesAutoresizingMaskIntoConstraints = false; head.addSubview(v) }
    NSLayoutConstraint.activate([
      pic.topAnchor.constraint(equalTo: head.topAnchor, constant: 8), pic.centerXAnchor.constraint(equalTo: head.centerXAnchor),
      pic.widthAnchor.constraint(equalToConstant: 84), pic.heightAnchor.constraint(equalToConstant: 84),
      ini.centerXAnchor.constraint(equalTo: pic.centerXAnchor), ini.centerYAnchor.constraint(equalTo: pic.centerYAnchor),
      name.topAnchor.constraint(equalTo: pic.bottomAnchor, constant: 10), name.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 20),
      name.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -20),
    ])
    tableView.tableHeaderView = head
  }
  override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { items.count }
  override func tableView(_ t: UITableView, titleForFooterInSection s: Int) -> String? { "Untick anything you don't want to send." }
  override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let cell = t.dequeueReusableCell(withIdentifier: "r", for: ip)
    let it = items[ip.row]
    var c = UIListContentConfiguration.subtitleCell()
    c.text = it.1.label.isEmpty ? (it.0 == "p" ? "phone" : "email") : it.1.label
    c.textProperties.font = .systemFont(ofSize: 13); c.textProperties.color = .secondaryLabel
    c.secondaryText = it.1.value; c.secondaryTextProperties.font = .systemFont(ofSize: 17); c.secondaryTextProperties.color = view.tintColor
    c.textToSecondaryTextVerticalPadding = 3
    cell.contentConfiguration = c
    let ticked = on.contains(it.0 + it.1.value)
    let mark = UIImageView(image: UIImage(systemName: ticked ? "checkmark.circle.fill" : "circle"))
    mark.tintColor = ticked ? view.tintColor : .tertiaryLabel
    cell.accessoryView = mark
    return cell
  }
  override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
    t.deselectRow(at: ip, animated: true)
    let it = items[ip.row], k = it.0 + it.1.value
    if on.contains(k) { on.remove(k) } else { on.insert(k) }
    UISelectionFeedbackGenerator().selectionChanged()
    if let cell = t.cellForRow(at: ip), let mark = cell.accessoryView as? UIImageView {
      let ticked = on.contains(k)
      UIView.transition(with: mark, duration: 0.15, options: .transitionCrossDissolve) {
        mark.image = UIImage(systemName: ticked ? "checkmark.circle.fill" : "circle"); mark.tintColor = ticked ? self.view.tintColor : .tertiaryLabel
      }
    }
    navigationItem.rightBarButtonItem?.isEnabled = !on.isEmpty
  }
  private func go() {
    let out = SharedContact(name: c.name, phones: c.phones.filter { on.contains("p" + $0.value) }, emails: c.emails.filter { on.contains("e" + $0.value) })
    guard !out.phones.isEmpty || !out.emails.isEmpty else { return }
    let f = onSend; onSend = nil
    dismiss(animated: true) { f?(out) }
  }
}

// ---------- a place: your current location, or one nearby (Apple's map) ----------
struct SharedPlace: Codable, Equatable, Hashable {
  var lat: Double; var lng: Double; var name: String?; var addr: String?
  init(lat: Double, lng: Double, name: String?, addr: String?) { self.lat = lat; self.lng = lng; self.name = name; self.addr = addr }
  init?(_ j: [String: Any]?) {
    guard let j = j, let a = (j["lat"] as? NSNumber)?.doubleValue, let o = (j["lng"] as? NSNumber)?.doubleValue else { return nil }
    lat = a; lng = o; name = j["name"] as? String; addr = j["addr"] as? String
  }
  var json: [String: Any] { var j: [String: Any] = ["lat": lat, "lng": lng]; j["name"] = name; j["addr"] = addr; return j }
  var coord: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
  var title: String { name ?? "Location" }
  var line: String { addr ?? String(format: "%.5f, %.5f", lat, lng) }
}

final class PlacePicker: UIViewController, UITableViewDataSource, UITableViewDelegate, CLLocationManagerDelegate, MKMapViewDelegate {
  var onSend: ((SharedPlace) -> Void)?
  private let map = MKMapView(), table = UITableView(frame: .zero, style: .insetGrouped), lm = CLLocationManager()
  private var here: CLLocation?, hereAddr: String?, near: [MKMapItem] = [], centred = false, searched: CLLocation?
  private let tint: UIColor
  init(tint: UIColor) { self.tint = tint; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  static func present(from vc: UIViewController, tint: UIColor, send: @escaping (SharedPlace) -> Void) {
    let lm = CLLocationManager()
    if !CLLocationManager.locationServicesEnabled() || [.denied, .restricted].contains(lm.authorizationStatus) {
      let a = UIAlertController(title: "Location Is Off", message: "Turn on Location for this app in Settings to send where you are.", preferredStyle: .alert)
      a.addAction(UIAlertAction(title: "Settings", style: .default) { _ in if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } })
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      vc.present(a, animated: true); return
    }
    let p = PlacePicker(tint: tint); p.onSend = send
    let nav = UINavigationController(rootViewController: p); nav.modalPresentationStyle = .pageSheet
    if let s = nav.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
    vc.present(nav, animated: true)
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Send Location"; view.backgroundColor = .systemGroupedBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    map.showsUserLocation = true; map.delegate = self; map.pointOfInterestFilter = .includingAll
    table.dataSource = self; table.delegate = self; table.register(UITableViewCell.self, forCellReuseIdentifier: "r")
    for v in [map, table] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
    NSLayoutConstraint.activate([
      map.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), map.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      map.trailingAnchor.constraint(equalTo: view.trailingAnchor), map.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.38),
      table.topAnchor.constraint(equalTo: map.bottomAnchor), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    lm.delegate = self; lm.desiredAccuracy = kCLLocationAccuracyBest
    if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() } else { lm.startUpdatingLocation() }
  }
  override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); lm.stopUpdatingLocation() }
  func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
    switch m.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways: m.startUpdatingLocation()
    case .denied, .restricted: dismiss(animated: true)
    default: break
    }
  }
  func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
    guard let l = locs.last, l.horizontalAccuracy >= 0 else { return }
    let first = here == nil
    here = l
    if !centred { centred = true; map.setRegion(MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 400, longitudinalMeters: 400), animated: false) }
    // (only the first row's words change as the fix gets better — nothing else moves)
    if let cell = table.cellForRow(at: IndexPath(row: 0, section: 0)) { fill(cell, row: 0) } else if first { table.reloadData() }
    if searched == nil || l.distance(from: searched!) > 150 { searched = l; nearby(l); address(l) }
  }
  private func address(_ l: CLLocation) {
    CLGeocoder().reverseGeocodeLocation(l) { [weak self] p, _ in
      guard let p = p?.first else { return }
      self?.hereAddr = [p.thoroughfare.map { [p.subThoroughfare, $0].compactMap { $0 }.joined(separator: " ") }, p.locality].compactMap { $0 }.joined(separator: ", ")
    }
  }
  private func nearby(_ l: CLLocation) {
    let r = MKLocalPointsOfInterestRequest(center: l.coordinate, radius: 300)
    MKLocalSearch(request: r).start { [weak self] res, _ in
      guard let self = self, let items = res?.mapItems else { return }
      let sorted = Array(items.sorted { ($0.placemark.location?.distance(from: l) ?? 0) < ($1.placemark.location?.distance(from: l) ?? 0) }.prefix(25))
      let had = self.near.count
      self.near = sorted
      // (the places fade in under the first row; a new set crossfades)
      if had == 0 { self.table.performBatchUpdates { self.table.insertSections(IndexSet(integer: 1), with: .fade) } }
      else { UIView.transition(with: self.table, duration: 0.2, options: .transitionCrossDissolve) { self.table.reloadSections(IndexSet(integer: 1), with: .none) } }
    }
  }
  func numberOfSections(in t: UITableView) -> Int { near.isEmpty ? 1 : 2 }
  func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? 1 : near.count }
  func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { s == 1 ? "Nearby Places" : nil }
  func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let cell = t.dequeueReusableCell(withIdentifier: "r", for: ip); fill(cell, row: ip.section == 0 ? 0 : ip.row + 1); return cell
  }
  private func fill(_ cell: UITableViewCell, row: Int) {
    var c = UIListContentConfiguration.subtitleCell()
    if row == 0 {
      c.image = UIImage(systemName: "location.circle.fill"); c.imageProperties.tintColor = .systemGreen
      c.imageProperties.preferredSymbolConfiguration = .init(pointSize: 30)
      c.text = "Send Current Location"; c.textProperties.color = tint; c.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
      c.secondaryText = here.map { "Accurate to \(Int($0.horizontalAccuracy.rounded())) metres" } ?? "Finding where you are…"
      cell.isUserInteractionEnabled = here != nil
    } else {
      let m = near[row - 1]
      c.image = UIImage(systemName: "mappin.circle.fill"); c.imageProperties.tintColor = .systemRed
      c.imageProperties.preferredSymbolConfiguration = .init(pointSize: 30)
      c.text = m.name; c.secondaryText = PlacePicker.line(m.placemark)
      cell.isUserInteractionEnabled = true
    }
    c.secondaryTextProperties.color = .secondaryLabel; c.textToSecondaryTextVerticalPadding = 2
    cell.contentConfiguration = c; cell.backgroundColor = .secondarySystemGroupedBackground
  }
  static func line(_ p: MKPlacemark) -> String {
    [p.thoroughfare.map { [p.subThoroughfare, $0].compactMap { $0 }.joined(separator: " ") }, p.locality].compactMap { $0 }.joined(separator: ", ")
  }
  func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
    t.deselectRow(at: ip, animated: true)
    let p: SharedPlace
    if ip.section == 0 { guard let h = here else { return }; p = SharedPlace(lat: h.coordinate.latitude, lng: h.coordinate.longitude, name: nil, addr: hereAddr) }
    else { let m = near[ip.row]; p = SharedPlace(lat: m.placemark.coordinate.latitude, lng: m.placemark.coordinate.longitude, name: m.name, addr: PlacePicker.line(m.placemark)) }
    let f = onSend; onSend = nil
    dismiss(animated: true) { f?(p) }
  }
}

// ---------- a place tapped in a chat or comment: the map apps on this iPhone (Haris 2026-11-16, W6) ----------
enum MapsChooser {
  static func show(_ p: SharedPlace, from vc: UIViewController, source: UIView?) {
    let a = UIAlertController(title: p.title, message: p.line, preferredStyle: .actionSheet)
    let q = "\(p.lat),\(p.lng)"
    a.addAction(UIAlertAction(title: "Open in Apple Maps", style: .default) { _ in
      let item = MKMapItem(placemark: MKPlacemark(coordinate: p.coord)); item.name = p.name ?? p.addr
      item.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: p.coord)])
    })
    if let g = URL(string: "comgooglemaps://"), UIApplication.shared.canOpenURL(g), let u = URL(string: "comgooglemaps://?q=\(q)&center=\(q)") {
      a.addAction(UIAlertAction(title: "Open in Google Maps", style: .default) { _ in UIApplication.shared.open(u) })
    }
    if let w = URL(string: "waze://"), UIApplication.shared.canOpenURL(w), let u = URL(string: "waze://?ll=\(q)&navigate=yes") {
      a.addAction(UIAlertAction(title: "Open in Waze", style: .default) { _ in UIApplication.shared.open(u) })
    }
    a.addAction(UIAlertAction(title: "Copy Coordinates", style: .default) { _ in UIPasteboard.general.string = q })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let pop = a.popoverPresentationController { pop.sourceView = source ?? vc.view; pop.sourceRect = (source ?? vc.view).bounds }
    vc.present(a, animated: true)
  }
}

// ---------- a contact's card tapped: iPhone's own contact card (Message, Call… — its own choice of apps) or New Contact ----------
enum ContactOpen {
  static func card(_ c: SharedContact, from vc: UIViewController) {
    let v = CNContactViewController(forUnknownContact: c.contact)
    v.allowsActions = true; v.allowsEditing = false; v.contactStore = CNContactStore()
    v.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak v] _ in v?.dismiss(animated: true) })
    let nav = UINavigationController(rootViewController: v); nav.modalPresentationStyle = .pageSheet
    vc.present(nav, animated: true)
  }
  static func save(_ c: SharedContact, from vc: UIViewController) {
    let v = CNContactViewController(forNewContact: c.contact)
    v.contactStore = CNContactStore()
    let d = NewContactDone(); v.delegate = d; NewContactDone.live = d
    let nav = UINavigationController(rootViewController: v); nav.modalPresentationStyle = .pageSheet
    vc.present(nav, animated: true)
  }
}
private final class NewContactDone: NSObject, CNContactViewControllerDelegate {
  static var live: NewContactDone?
  func contactViewController(_ v: CNContactViewController, didCompleteWith c: CNContact?) { v.dismiss(animated: true); NewContactDone.live = nil }
}

// ---------- a place's picture: Apple's map around it with a pin, made once for each look and kept ----------
enum MapThumb {
  private static let cache = NSCache<NSString, UIImage>()
  static func key(_ p: SharedPlace, _ size: CGSize, dark: Bool) -> String { "\(p.lat),\(p.lng),\(Int(size.width))x\(Int(size.height)),\(dark ? "d" : "l")" }
  static func cached(_ p: SharedPlace, _ size: CGSize, dark: Bool) -> UIImage? { cache.object(forKey: key(p, size, dark: dark) as NSString) }
  static func make(_ p: SharedPlace, _ size: CGSize, dark: Bool, done: @escaping (UIImage?) -> Void) {
    let k = key(p, size, dark: dark) as NSString
    if let i = cache.object(forKey: k) { done(i); return }
    let o = MKMapSnapshotter.Options()
    o.region = MKCoordinateRegion(center: p.coord, latitudinalMeters: 500, longitudinalMeters: 500)
    let scale = UIScreen.main.scale
    o.size = size; o.scale = scale
    o.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    MKMapSnapshotter(options: o).start(with: .global(qos: .userInitiated)) { s, _ in
      guard let s = s else { DispatchQueue.main.async { done(nil) }; return }
      let f = UIGraphicsImageRendererFormat(); f.scale = scale
      let r = UIGraphicsImageRenderer(size: size, format: f)
      let img = r.image { _ in
        s.image.draw(at: .zero)
        let pt = s.point(for: p.coord)
        // (the pin: a red dot ringed in white — the place's own spot)
        let dot = CGRect(x: pt.x - 9, y: pt.y - 9, width: 18, height: 18)
        UIColor.white.setFill(); UIBezierPath(ovalIn: dot.insetBy(dx: -2.5, dy: -2.5)).fill()
        UIColor.systemRed.setFill(); UIBezierPath(ovalIn: dot).fill()
      }
      cache.setObject(img, forKey: k)
      DispatchQueue.main.async { done(img) }
    }
  }
}
