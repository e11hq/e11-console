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

  static func run(_ asset: AVAsset, hd: Bool, to out: URL, done: @escaping (Bool) -> Void) {
    guard let vt = asset.tracks(withMediaType: .video).first,
          let reader = try? AVAssetReader(asset: asset),
          let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else { done(false); return }
    // the size: the long side at most 1280 (HD 1920), the video's own shape, even numbers
    let nat = vt.naturalSize, long = max(nat.width, nat.height), cap: CGFloat = hd ? 1920 : 1280
    let k = long > cap ? cap / long : 1
    let w = Int((nat.width * k / 2).rounded()) * 2, h = Int((nat.height * k / 2).rounded()) * 2
    guard w > 0, h > 0 else { done(false); return }
    let own = Int(vt.estimatedDataRate), rate = own > 0 ? min(bitrate(hd: hd), own) : bitrate(hd: hd)
    let fps = vt.nominalFrameRate > 0 ? Double(vt.nominalFrameRate) : 30

    let vOut = AVAssetReaderTrackOutput(track: vt, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    vOut.alwaysCopiesSampleData = false
    guard reader.canAdd(vOut) else { done(false); return }
    reader.add(vOut)
    let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h,
      AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: rate, AVVideoExpectedSourceFrameRateKey: fps,
                                        AVVideoMaxKeyFrameIntervalDurationKey: 2,
                                        AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String]])
    vIn.transform = vt.preferredTransform; vIn.expectsMediaDataInRealTime = false
    guard writer.canAdd(vIn) else { done(false); return }
    writer.add(vIn)

    var aOut: AVAssetReaderTrackOutput?, aIn: AVAssetWriterInput?
    if let at = asset.tracks(withMediaType: .audio).first {
      let o = AVAssetReaderTrackOutput(track: at, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
      let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2,
                                                                      AVSampleRateKey: 44100, AVEncoderBitRateKey: 128_000])
      i.expectsMediaDataInRealTime = false
      if reader.canAdd(o), writer.canAdd(i) { reader.add(o); writer.add(i); aOut = o; aIn = i }
    }
    writer.shouldOptimizeForNetworkUse = true
    guard reader.startReading(), writer.startWriting() else { done(false); return }
    writer.startSession(atSourceTime: .zero)

    let g = DispatchGroup(), q = DispatchQueue(label: "talk.shrink.v"), qa = DispatchQueue(label: "talk.shrink.a")
    func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderTrackOutput, _ queue: DispatchQueue) {
      g.enter()
      let state = Done()
      input.requestMediaDataWhenReady(on: queue) {
        while input.isReadyForMoreMediaData && !state.yes {
          if reader.status == .reading, let b = output.copyNextSampleBuffer() {
            if !input.append(b) { state.yes = true; input.markAsFinished(); g.leave() }
          } else { state.yes = true; input.markAsFinished(); g.leave() }
        }
      }
    }
    pump(vIn, vOut, q)
    if let o = aOut, let i = aIn { pump(i, o, qa) }
    g.notify(queue: .global(qos: .userInitiated)) {
      if reader.status == .failed || writer.status == .failed { reader.cancelReading(); writer.cancelWriting(); done(false); return }
      writer.finishWriting { done(writer.status == .completed) }
    }
  }
}
// (one track finished — kept on its own queue only)
private final class Done: @unchecked Sendable { var yes = false }
