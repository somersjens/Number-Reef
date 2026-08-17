
import Foundation
import AVFoundation
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 4 else { exit(1) }
let url = URL(fileURLWithPath: args[1])
let t = Double(args[2])!
let dest = URL(fileURLWithPath: args[3])
let asset = AVURLAsset(url: url)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
let time = CMTime(seconds: t, preferredTimescale: 600)
do {
  let cg = try gen.copyCGImage(at: time, actualTime: nil)
  let rep = NSBitmapImageRep(cgImage: cg)
  guard let data = rep.representation(using: .png, properties: [:]) else { exit(2) }
  try data.write(to: dest)
  print("ok \(dest.lastPathComponent)")
} catch {
  fputs("err \(error)\n", stderr)
  exit(3)
}
