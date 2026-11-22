// A test run only (Haris 2026-11-22 16:40): Talk's video-frame code on a real HDR video, on the Mac — which frame is dark.
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

let src = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var report: [String] = []

func meanSRGB(_ cg: CGImage) -> Double {
  let w = 64, h = Int(Double(cg.height) / Double(cg.width) * 64)
  let cs = CGColorSpace(name: CGColorSpace.sRGB)!
  guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
  ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
  let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
  var s = 0.0; for i in 0..<(w * h) { s += 0.2126 * Double(p[i*4]) + 0.7152 * Double(p[i*4+1]) + 0.0722 * Double(p[i*4+2]) }
  return s / Double(w * h)
}
func save(_ cg: CGImage, _ name: String) {
  let u = out.appendingPathComponent(name + ".jpg")
  if let d = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil) { CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary); CGImageDestinationFinalize(d) }
  // read back as a phone would, and measured again
  var back = -1.0, backCS = "?"
  if let s = CGImageSourceCreateWithURL(u as CFURL, nil), let i = CGImageSourceCreateImageAtIndex(s, 0, nil) { back = meanSRGB(i); backCS = (i.colorSpace?.name as String?) ?? "nil" }
  report.append("\(name): frame colour space=\((cg.colorSpace?.name as String?) ?? "nil") bits=\(cg.bitsPerComponent) mean(sRGB)=\(String(format: "%.1f", meanSRGB(cg))) | saved JPEG colour space=\(backCS) mean=\(String(format: "%.1f", back))")
}
func frame(_ a: AVAsset, comp709: Bool) -> CGImage? {
  let g = AVAssetImageGenerator(asset: a); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 720, height: 720)
  g.requestedTimeToleranceBefore = .positiveInfinity; g.requestedTimeToleranceAfter = .positiveInfinity
  if comp709 {
    let c = AVMutableVideoComposition(propertiesOf: a)
    c.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2; c.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2; c.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
    g.videoComposition = c
  }
  return try? g.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
}
// the original
let orig = AVURLAsset(url: src)
report.append("original HDR: \(orig.tracks(withMediaType: .video).first?.hasMediaCharacteristic(.containsHDRVideo) == true)")
if let f = frame(orig, comp709: false) { save(f, "1-original-plain") }
if let f = frame(orig, comp709: true) { save(f, "2-original-709") }

// made smaller as Talk does since 236: 10-bit HEVC, HLG, BT.2020 (VideoShrink, without the watermark)
let hlg = out.appendingPathComponent("talk-copy.mp4"); try? FileManager.default.removeItem(at: hlg)
let vt = orig.tracks(withMediaType: .video).first!
let comp = AVMutableVideoComposition(propertiesOf: orig)
comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020; comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG; comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
let reader = try! AVAssetReader(asset: orig)
let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: [vt], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
vOut.videoComposition = comp; reader.add(vOut)
let writer = try! AVAssetWriter(outputURL: hlg, fileType: .mp4)
let sz = comp.renderSize, k = min(1, 854 / max(sz.width, sz.height))
let w = Int((sz.width * k / 2).rounded()) * 2, h = Int((sz.height * k / 2).rounded()) * 2
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000, AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String],
  AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]])
vIn.expectsMediaDataInRealTime = false; writer.add(vIn)
reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
let q = DispatchQueue(label: "w"), sem = DispatchSemaphore(value: 0)
vIn.requestMediaDataWhenReady(on: q) {
  while vIn.isReadyForMoreMediaData { if let b = vOut.copyNextSampleBuffer() { vIn.append(b) } else { vIn.markAsFinished(); writer.finishWriting { sem.signal() }; return } }
}
sem.wait()
report.append("Talk's copy written: \(writer.status == .completed) \(writer.error?.localizedDescription ?? "")")
let copy = AVURLAsset(url: hlg)
report.append("Talk's copy HDR: \(copy.tracks(withMediaType: .video).first?.hasMediaCharacteristic(.containsHDRVideo) == true)")
if let f = frame(copy, comp709: false) { save(f, "3-copy-plain") }
if let f = frame(copy, comp709: true) { save(f, "4-copy-709 (Talk 245)") }
// and the frame turned into standard colour by Core Image, tone-mapped (another way)
if let f = frame(copy, comp709: false) {
  var img = CIImage(cgImage: f)
  if #available(macOS 15.0, *), let t = CIFilter(name: "CIToneMapHeadroom") { t.setValue(img, forKey: kCIInputImageKey); t.setValue(1.0, forKey: "inputTargetHeadroom"); if let o = t.outputImage { img = o } }
  let ctx = CIContext()
  if let c = ctx.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) { save(c, "5-copy-tonemapped-sRGB") }
}
try! report.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
print(report.joined(separator: "\n"))
