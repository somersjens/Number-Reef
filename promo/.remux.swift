import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }
let src = URL(fileURLWithPath: args[1])
let dest = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: dest)

let asset = AVURLAsset(url: src)
let sem = DispatchSemaphore(value: 0)
var ok = false
Task {
    guard let export = AVAssetExportSession(asset: asset,
                                            presetName: AVAssetExportPresetPassthrough)
            ?? AVAssetExportSession(asset: asset,
                                    presetName: AVAssetExportPresetHighestQuality) else {
        fputs("no export session\n", stderr)
        sem.signal()
        return
    }
    export.outputURL = dest
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    await export.export()
    if export.status == .completed {
        ok = true
        print("ok \(dest.lastPathComponent)")
    } else {
        fputs("export \(export.error?.localizedDescription ?? "failed")\n", stderr)
    }
    sem.signal()
}
sem.wait()
exit(ok ? 0 : 2)
