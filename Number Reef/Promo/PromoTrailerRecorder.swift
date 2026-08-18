import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Writes an App Store preview: H.264 video, then muxes the production music
/// bed + scripted SFX in a second pass (Simulator cannot tap AVAudioEngine).
@MainActor
final class PromoTrailerRecorder {
    private let size: CGSize
    private let fps: Int32
    private let outputURL: URL

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var frameIndex: Int64 = 0

    /// Populated by the host just before `finish()` from the director's cue log.
    var audioCues: [(time: TimeInterval, file: String, volume: Float)] = []

    init(size: CGSize, fps: Int = 30, outputURL: URL? = nil) {
        self.size = size
        self.fps = Int32(fps)
        let tag = "\(Int(size.width))x\(Int(size.height))"
        let name = "app-store-teaser-\(tag).mp4"
        self.outputURL = outputURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    func start() throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(size.width * size.height * 6),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        // Offline encode — never block the main thread waiting on realtime.
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw NSError(domain: "PromoTrailer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add video input"
            ])
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "PromoTrailer", code: 2)
        }

        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.sessionStarted = false
        self.frameIndex = 0
    }

    func capture(image: UIImage, at elapsed: TimeInterval) {
        _ = elapsed
        guard let writer, let videoInput, let adaptor else { return }
        guard let buffer = makePixelBuffer(from: image) else { return }

        let pts = CMTime(value: frameIndex, timescale: fps)
        if !sessionStarted {
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }

        var spun = 0
        while !videoInput.isReadyForMoreMediaData && spun < 500 {
            Thread.sleep(forTimeInterval: 0.001)
            spun += 1
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        _ = adaptor.append(buffer, withPresentationTime: pts)
        frameIndex += 1
    }

    func finish() async -> URL? {
        guard let writer, let videoInput else { return nil }
        videoInput.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            print("PROMO_TRAILER_ERROR \(writer.error?.localizedDescription ?? "video finish failed")")
            return nil
        }
        let videoDuration = CMTime(value: max(frameIndex, 1), timescale: fps)
        let mixed = await mixAudioBed(to: videoDuration, of: outputURL, cues: audioCues)
        return copyToDocuments(mixed ?? outputURL)
    }

    /// Lays the production music bed + scripted game SFX under the silent video.
    private func mixAudioBed(to duration: CMTime,
                             of url: URL,
                             cues: [(time: TimeInterval, file: String, volume: Float)]) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        do {
            try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        } catch {
            print("PROMO_TRAILER_ERROR mix video \(error)")
            return nil
        }

        var mixParams: [AVMutableAudioMixInputParameters] = []

        // Production gameplay music volume (~0.30 in AppAudio).
        if let musicURL = Bundle.main.url(forResource: "music_background", withExtension: "m4a"),
           let compMusic = composition.addMutableTrack(withMediaType: .audio,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) {
            let musicAsset = AVURLAsset(url: musicURL)
            if let musicTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first {
                let musicDur = (try? await musicTrack.load(.timeRange).duration) ?? duration
                var cursor = CMTime.zero
                while cursor < duration {
                    let remaining = CMTimeSubtract(duration, cursor)
                    let slice = CMTimeMinimum(remaining, musicDur)
                    try? compMusic.insertTimeRange(CMTimeRange(start: .zero, duration: slice),
                                                   of: musicTrack, at: cursor)
                    cursor = CMTimeAdd(cursor, slice)
                    if slice.seconds <= 0.001 { break }
                }
                let musicMix = AVMutableAudioMixInputParameters(track: compMusic)
                musicMix.setVolume(0.30, at: .zero)
                mixParams.append(musicMix)
            }
        }

        print("PROMO_TRAILER_AUDIO mix cues=\(cues.count) \(cues.map { "\($0.file)@\(String(format: "%.2f", $0.time))" }.joined(separator: ", "))")
        // Scripted SFX — same CAF files the game plays via AppAudio.
        for cue in cues {
            let at = CMTime(seconds: max(0, cue.time), preferredTimescale: 600)
            guard at < duration else { continue }
            guard let sfxURL = Bundle.main.url(forResource: cue.file, withExtension: "caf")
                    ?? Bundle.main.url(forResource: cue.file, withExtension: "m4a") else {
                print("PROMO_TRAILER_AUDIO missing \(cue.file)")
                continue
            }
            let sfxAsset = AVURLAsset(url: sfxURL)
            guard let sfxTrack = try? await sfxAsset.loadTracks(withMediaType: .audio).first,
                  let compSFX = composition.addMutableTrack(withMediaType: .audio,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let sfxDur = (try? await sfxTrack.load(.timeRange).duration) ?? .zero
            let remaining = CMTimeSubtract(duration, at)
            let slice = CMTimeMinimum(sfxDur, remaining)
            guard slice.seconds > 0.01 else { continue }
            try? compSFX.insertTimeRange(CMTimeRange(start: .zero, duration: slice),
                                         of: sfxTrack, at: at)
            let sfxMix = AVMutableAudioMixInputParameters(track: compSFX)
            sfxMix.setVolume(max(0.05, min(1, cue.volume * 2.2)), at: .zero)
            mixParams.append(sfxMix)
        }

        let tag = "\(Int(size.width))x\(Int(size.height))"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-store-teaser-\(tag)-mixed.mp4")
        try? FileManager.default.removeItem(at: dest)

        guard let export = AVAssetExportSession(asset: composition,
                                                presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        export.outputURL = dest
        export.outputFileType = .mp4
        export.timeRange = timeRange
        export.shouldOptimizeForNetworkUse = true
        if !mixParams.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = mixParams
            export.audioMix = audioMix
        }
        await export.export()
        guard export.status == .completed else {
            print("PROMO_TRAILER_ERROR export \(export.error?.localizedDescription ?? "mix failed")")
            return nil
        }
        print("PROMO_TRAILER_AUDIO cues=\(cues.count) music=on")
        return dest
    }

    private func copyToDocuments(_ url: URL) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Always publish the App Store filename (mixed temp may end in -mixed.mp4).
        let tag = "\(Int(size.width))x\(Int(size.height))"
        let dest = docs.appendingPathComponent("app-store-teaser-\(tag).mp4")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        let marker = docs.appendingPathComponent("promo-trailer-ready.txt")
        try? "\(dest.path)\n".write(to: marker, atomically: true, encoding: .utf8)
        return dest
    }

    private func makePixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ), let cgImage = image.cgImage else { return nil }

        // Snapshot bitmaps are already upright (UIKit top-left). A second
        // Y-flip here inverted the whole teaser (coral at the top, HUD at the
        // bottom). Draw the CGImage as-is into the pixel buffer.
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}
