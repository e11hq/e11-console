import AVFoundation
import VideoToolbox

/* A video made smaller for sending, in HEVC (H.265) — Haris 2026-11-21 12:08: "Sharper at 720". HEVC needs about half the
   bitrate of H.264 for the same look, so at the size Apple's 720p H.264 preset gave, the picture is clearly sharper.
   720p (HD: 1080p) on the long side kept as the video's own shape, its own frame rate, the bitrate set here (never more
   than the original's), sound as AAC. Every iPhone since 2017 and every Mac plays it. Anything that can't be done this way
   (no video track, the encoder refuses) → nil, and the caller falls back to Apple's preset as before. */
enum VideoShrink {
  // (bits per second: 720p 4 Mbps, 1080p 8 Mbps — to be checked against real videos with Haris and tuned)
  static func bitrate(hd: Bool) -> Int { hd ? 8_000_000 : 4_000_000 }

  // (stop: the sending bubble's id — its ✕ stops this; progress: 0…1 as the frames go)
  // ProRes RAW (or RAW HQ): a camera's raw footage — sent as the original, never made smaller (Haris 2026-11-21 13:18)
  static func isRaw(_ asset: AVAsset) -> Bool {
    guard let t = asset.tracks(withMediaType: .video).first, let d = t.formatDescriptions.first else { return false }
    let c = CMFormatDescriptionGetMediaSubType(d as! CMFormatDescription)
    return c == 0x6170726E || c == 0x61707268   // 'aprn', 'aprh'
  }
  // which ProRes it is, for its bubble's label (Haris 2026-11-21 14:00: "Add labels to every prores type") — the kind, and
  // "Log" when filmed in Apple Log; nil for any other video
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
    let log = tf.localizedCaseInsensitiveContains("log") || all.contains("AppleLog") || all.contains("Apple Log")
    return log ? n + " · Log" : n
  }
  // (why the last one couldn't be made smaller — said when a video goes as its original instead)
  static var lastError: String?
  static func run(_ asset: AVAsset, hd: Bool, to out: URL, stop: String? = nil, progress: ((Double) -> Void)? = nil, done: @escaping (Bool) -> Void) {
    lastError = nil
    guard let vt = asset.tracks(withMediaType: .video).first,
          let reader = try? AVAssetReader(asset: asset),
          let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else { done(false); return }
    // the size: the long side at most 1280 (HD 1920), the video's own shape (turned the way it's watched), even numbers
    let turned = vt.naturalSize.applying(vt.preferredTransform)
    let nat = CGSize(width: abs(turned.width), height: abs(turned.height)), long = max(nat.width, nat.height), cap: CGFloat = hd ? 1920 : 1280
    let k = long > cap ? cap / long : 1
    let w = Int((nat.width * k / 2).rounded()) * 2, h = Int((nat.height * k / 2).rounded()) * 2
    guard w > 0, h > 0 else { done(false); return }
    let own = Int(vt.estimatedDataRate), rate = own > 0 ? min(bitrate(hd: hd), own) : bitrate(hd: hd)
    let fps = vt.nominalFrameRate > 0 ? Double(vt.nominalFrameRate) : 30

    // (read through Apple's video composition set to standard colour: a ProRes Log or HDR video is turned into the colours
    //  every phone shows, turned the right way up — tagging the written video alone left Log footage flat and grey,
    //  Haris 2026-11-21 14:32)
    let comp = AVMutableVideoComposition(propertiesOf: asset)
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
