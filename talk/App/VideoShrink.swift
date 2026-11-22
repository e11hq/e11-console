import AVFoundation
import VideoToolbox
import CoreImage
import UIKit

/* A video made smaller for sending, in HEVC (H.265) — Haris 2026-11-21 12:08: "Sharper at 720". HEVC needs about half the
   bitrate of H.264 for the same look, so at the size Apple's 720p H.264 preset gave, the picture is clearly sharper.
   720p (HD: 1080p) on the long side kept as the video's own shape, its own frame rate, the bitrate set here (never more
   than the original's), sound as AAC. Every iPhone since 2017 and every Mac plays it. Anything that can't be done this way
   (no video track, the encoder refuses) → nil, and the caller falls back to Apple's preset as before. */
enum VideoShrink {
  // (as WhatsApp — Haris 2026-11-22 13:22: standard 480p, HD 720p; HEVC at 1.2 / 2.5 Mbps. Was 720p 4 Mbps / 1080p 8 Mbps)
  static func bitrate(hd: Bool) -> Int { hd ? 2_500_000 : 1_200_000 }
  static func longSide(hd: Bool) -> CGFloat { hd ? 1280 : 854 }

  // (stop: the sending bubble's id — its ✕ stops this; progress: 0…1 as the frames go)
  // ProRes RAW (or RAW HQ): a camera's raw footage — sent as the original, never made smaller (Haris 2026-11-21 13:18)
  static func isRaw(_ asset: AVAsset) -> Bool {
    guard let t = asset.tracks(withMediaType: .video).first, let d = t.formatDescriptions.first else { return false }
    let c = CMFormatDescriptionGetMediaSubType(d as! CMFormatDescription)
    return c == 0x6170726E || c == 0x61707268   // 'aprn', 'aprh'
  }
  // which ProRes it is, for its bubble's label (Haris 2026-11-21 14:00: "Add labels to every prores type") — the kind, and
  // "Log" when filmed in Apple Log; nil for any other video
  // Apple Log: iPhone marks it only as "com.apple.rec2020.apple-log" (the file's 'logs' box, read 2026-11-21 from Haris's
  // iPhone 17 Pro clip IMG_4844 — its colour box says Rec. 2020 with no transfer, so Apple's own conversion leaves it flat)
  static func isAppleLog(_ asset: AVAsset) -> Bool {
    guard let t = asset.tracks(withMediaType: .video).first, let d0 = t.formatDescriptions.first else { return false }
    let all = (CMFormatDescriptionGetExtensions(d0 as! CMFormatDescription) as NSDictionary?)?.description ?? ""
    return all.contains("apple-log") || all.contains("AppleLog")
  }
  /* Apple Log → normal colours, as a 33-point colour cube on the code values: Apple's published Apple Log curve undone
     (R0 −0.05641088, Rt 0.01, c 47.28711236, b 0.00964052, γ 0.08550479, β 0.69336945), Rec. 2020 → Rec. 709 colours, a soft
     shoulder for the highlights, then Rec. 709's own curve — tried on a frame of IMG_4844 first: it looks like a normal video */
  private static let logCube: Data = {
    let n = 33
    let R0 = -0.05641088, Rt = 0.01, c = 47.28711236, b = 0.00964052, g = 0.08550479, B = 0.69336945
    let Pt = c * (Rt - R0) * (Rt - R0)
    func lin(_ p: Double) -> Double { p >= Pt ? pow(2, (p - B) / g) - b : (max(p, 0) / c).squareRoot() + R0 }
    func tone(_ x: Double) -> Double { let x = max(x, 0); return x / (1 + x / 4) * 1.25 }
    func oetf(_ l: Double) -> Double { let l = min(max(l, 0), 1); return l < 0.018 ? 4.5 * l : 1.099 * pow(l, 0.45) - 0.099 }
    var out = [Float](); out.reserveCapacity(n * n * n * 4)
    for bi in 0..<n { for gi in 0..<n { for ri in 0..<n {
      let r = lin(Double(ri) / Double(n - 1)), gg = lin(Double(gi) / Double(n - 1)), bb = lin(Double(bi) / Double(n - 1))
      let r7 = 1.6605 * r - 0.5876 * gg - 0.0728 * bb, g7 = -0.1246 * r + 1.1329 * gg - 0.0083 * bb, b7 = -0.0182 * r - 0.1006 * gg + 1.1187 * bb
      out += [Float(oetf(tone(r7))), Float(oetf(tone(g7))), Float(oetf(tone(b7))), 1]
    } } }
    return out.withUnsafeBufferPointer { Data(buffer: $0) }
  }()
  private static let rawCtx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
  static func proRes(_ asset: AVAsset) -> String? {
    guard let t = asset.tracks(withMediaType: .video).first, let d0 = t.formatDescriptions.first else { return nil }
    let d = d0 as! CMFormatDescription
    let names: [FourCharCode: String] = [0x6170636F: "ProRes 422 Proxy", 0x61706373: "ProRes 422 LT", 0x6170636E: "ProRes 422",
                                         0x61706368: "ProRes 422 HQ", 0x61703468: "ProRes 4444", 0x61703478: "ProRes 4444 XQ",
                                         0x6170726E: "ProRes RAW", 0x61707268: "ProRes RAW HQ"]
    guard let n = names[CMFormatDescriptionGetMediaSubType(d)] else { return nil }
    // (Log: the colour tag, wherever iPhone put it — its transfer function, or anywhere in the track's description; an iPhone
    //  17 Pro Log clip wasn't found by the tag alone, Haris 2026-11-21 14:36)
    let tf = CMFormatDescriptionGetExtension(d, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String ?? ""
    let all = (CMFormatDescriptionGetExtensions(d) as NSDictionary?)?.description ?? ""
    let log = tf.localizedCaseInsensitiveContains("log") || all.contains("apple-log") || all.contains("AppleLog") || all.contains("Apple Log")
    return log ? n + " · Log" : n
  }
  // (why the last one couldn't be made smaller — said when a video goes as its original instead)
  static var lastError: String?
  static func run(_ asset: AVAsset, hd: Bool, to out: URL, stop: String? = nil, progress: ((Double) -> Void)? = nil, done: @escaping (Bool) -> Void) {
    lastError = nil
    guard let vt = asset.tracks(withMediaType: .video).first,
          let reader = try? AVAssetReader(asset: asset),
          let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else { done(false); return }
    // the size: the long side at most 854 — 480p (HD 1280 — 720p), the video's own shape (turned the way it's watched), even numbers
    let turned = vt.naturalSize.applying(vt.preferredTransform)
    let nat = CGSize(width: abs(turned.width), height: abs(turned.height)), long = max(nat.width, nat.height), cap = longSide(hd: hd)
    let k = long > cap ? cap / long : 1
    let w = Int((nat.width * k / 2).rounded()) * 2, h = Int((nat.height * k / 2).rounded()) * 2
    guard w > 0, h > 0 else { done(false); return }
    let own = Int(vt.estimatedDataRate), rate = own > 0 ? min(bitrate(hd: hd), own) : bitrate(hd: hd)
    let fps = vt.nominalFrameRate > 0 ? Double(vt.nominalFrameRate) : 30

    // (read through Apple's video composition set to standard colour: a ProRes Log or HDR video is turned into the colours
    //  every phone shows, turned the right way up — tagging the written video alone left Log footage flat and grey,
    //  Haris 2026-11-21 14:32)
    let comp: AVMutableVideoComposition
    if isAppleLog(asset) {
      // (Apple Log: the cube above on each frame, on the raw code values — no colour management of Core Image's own)
      let tr = vt.preferredTransform
      comp = AVMutableVideoComposition(asset: asset) { req in
        var img = req.sourceImage
        // (turned the way it's watched, if Apple hasn't already)
        if abs(img.extent.width - req.renderSize.width) > 1 {
          img = img.transformed(by: tr)
          img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        }
        let f = CIFilter(name: "CIColorCube", parameters: [kCIInputImageKey: img, "inputCubeDimension": 33, "inputCubeData": VideoShrink.logCube])
        req.finish(with: Watermark.onto(f?.outputImage ?? img, size: req.renderSize), context: VideoShrink.rawCtx)
      }
      comp.renderSize = nat
    } else {
      // (every other video: Apple's own colour handling, the watermark laid on each frame)
      let tr = vt.preferredTransform
      comp = AVMutableVideoComposition(asset: asset) { req in
        var img = req.sourceImage
        if abs(img.extent.width - req.renderSize.width) > 1 {
          img = img.transformed(by: tr)
          img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        }
        req.finish(with: Watermark.onto(img, size: req.renderSize), context: nil)
      }
      comp.renderSize = nat
    }
    comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
    let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: [vt], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    vOut.videoComposition = comp
    vOut.alwaysCopiesSampleData = false
    guard reader.canAdd(vOut) else { done(false); return }
    reader.add(vOut)
    let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h,
      AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: rate, AVVideoExpectedSourceFrameRateKey: fps,
                                        AVVideoMaxKeyFrameIntervalDurationKey: 2,
                                        AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String],
      // (standard colour, as every phone shows it — a ProRes Log or HDR video turned into it, not tagged with its own)
      AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                  AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
    vIn.expectsMediaDataInRealTime = false   // (already turned the right way up by the composition)
    guard writer.canAdd(vIn) else { done(false); return }
    writer.add(vIn)

    var aOut: AVAssetReaderTrackOutput?, aIn: AVAssetWriterInput?
    if let at = asset.tracks(withMediaType: .audio).first {
      // (read as plain stereo — an iPhone 17's camera records spatial audio, 4 channels and more, which the stereo AAC
      //  couldn't take: every camera ProRes clip failed and went at its full size, Haris 2026-11-21 14:05)
      let o = AVAssetReaderTrackOutput(track: at, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44100,
                                                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                                                                   AVLinearPCMIsNonInterleaved: false])
      let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2,
                                                                      AVSampleRateKey: 44100, AVEncoderBitRateKey: 128_000])
      i.expectsMediaDataInRealTime = false
      if reader.canAdd(o), writer.canAdd(i) { reader.add(o); writer.add(i); aOut = o; aIn = i }
    }
    writer.shouldOptimizeForNetworkUse = true
    guard reader.startReading(), writer.startWriting() else { done(false); return }
    writer.startSession(atSourceTime: .zero)

    let g = DispatchGroup(), q = DispatchQueue(label: "talk.shrink.v"), qa = DispatchQueue(label: "talk.shrink.a")
    let length = max(0.1, CMTimeGetSeconds(asset.duration))
    func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, _ queue: DispatchQueue, video: Bool) {
      g.enter()
      let state = Done()
      input.requestMediaDataWhenReady(on: queue) {
        while input.isReadyForMoreMediaData && !state.yes {
          if Uploads.isStopped(stop) { state.yes = true; reader.cancelReading(); input.markAsFinished(); g.leave(); return }
          if reader.status == .reading, let b = output.copyNextSampleBuffer() {
            if video, let p = progress { let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(b)); if t.isFinite { p(min(1, t / length)) } }
            if !input.append(b) { state.yes = true; input.markAsFinished(); g.leave() }
          } else { state.yes = true; input.markAsFinished(); g.leave() }
        }
      }
    }
    pump(vIn, vOut, q, video: true)
    if let o = aOut, let i = aIn { pump(i, o, qa, video: false) }
    g.notify(queue: .global(qos: .userInitiated)) {
      if Uploads.isStopped(stop) || reader.status == .failed || writer.status == .failed {
        lastError = (writer.error ?? reader.error).map { ($0 as NSError).localizedDescription + " (\(($0 as NSError).code))" }
        reader.cancelReading(); writer.cancelWriting(); done(false); return
      }
      writer.finishWriting { if writer.status != .completed { lastError = writer.error.map { ($0 as NSError).localizedDescription + " (\(($0 as NSError).code))" } }; done(writer.status == .completed) }
    }
  }
}
// (one track finished — kept on its own queue only)
private final class Done: @unchecked Sendable { var yes = false }

/* E11 Talk's mark on every photo and video sent from Photos or the camera (not files): the white speech bubble with E11,
   at 60% with a light shadow, bottom right, its bubble 11% of the picture's shorter side, 3.5% from the edges — the
   approved mock-up "A, medium, 60%" (Haris 2026-11-21 14:53–14:54). The image (TalkWatermark) is the bubble 512 px in a
   600 px square with its shadow. */
enum Watermark {
  private static let mark: CGImage? = UIImage(named: "TalkWatermark")?.cgImage
  private static let ciMark: CIImage? = mark.map { CIImage(cgImage: $0) }
  // (where it goes, in a picture of this size: the whole 600 px square, so its bubble is 11% of the shorter side)
  private static func spot(_ w: CGFloat, _ h: CGFloat) -> CGRect {
    let short = min(w, h), bubble = short * 0.11, box = bubble * 600 / 512, pad = short * 0.035 - (box - bubble) / 2
    return CGRect(x: w - pad - box, y: pad, width: box, height: box)   // (from the bottom left, as Core Image counts)
  }
  // a photo
  static func onto(_ cg: CGImage) -> CGImage {
    guard let m = mark else { return cg }
    let w = CGFloat(cg.width), h = CGFloat(cg.height), r = spot(w, h)
    let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
    let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { ctx in
      let c = ctx.cgContext
      c.translateBy(x: 0, y: h); c.scaleBy(x: 1, y: -1)   // (drawn the way Core Graphics counts: from the bottom left)
      c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
      c.draw(m, in: r)
    }
    return img.cgImage ?? cg
  }
  // a video's frame
  static func onto(_ frame: CIImage, size: CGSize) -> CIImage {
    guard let m = ciMark else { return frame }
    let r = spot(size.width, size.height)
    let placed = m.transformed(by: CGAffineTransform(scaleX: r.width / m.extent.width, y: r.height / m.extent.height)).transformed(by: CGAffineTransform(translationX: r.minX, y: r.minY))
    return placed.composited(over: frame).cropped(to: CGRect(origin: .zero, size: size))
  }
}
