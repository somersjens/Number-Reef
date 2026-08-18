//
//  PromoTrailerHostView.swift
//  Number Reef
//
//  Hosts the real ReefPlayfield at production layout scale, with HUD, captions,
//  and the final app-icon beat. Capture scales up to App Store export pixels.
//

import SwiftUI
import Combine
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

struct PromoTrailerHostView: View {
    let layoutSize: CGSize
    let exportSize: CGSize
    let usesPadMetrics: Bool
    let captureProvider: () -> UIView?
    let onFinished: (URL?) -> Void

    @StateObject private var director = PromoTrailerDirector()
    @StateObject private var model: GameViewModel
    @State private var engine: ReefEngine?
    /// Class-backed encode state so CADisplayLink doesn't read a stale View copy.
    @State private var encode = PromoEncodeState()
    @State private var displayLink: CADisplayLink?
    @State private var linkTarget: PromoDisplayLinkProxy?

    init(layoutSize: CGSize,
         exportSize: CGSize,
         usesPadMetrics: Bool,
         captureProvider: @escaping () -> UIView? = { nil },
         onFinished: @escaping (URL?) -> Void) {
        self.layoutSize = layoutSize
        self.exportSize = exportSize
        self.usesPadMetrics = usesPadMetrics
        self.captureProvider = captureProvider
        self.onFinished = onFinished
        let level = MathLevel(topic: .addition, index: 1)
        let request = GameSessionRequest(level: level, mode: .mixed)
        _model = StateObject(wrappedValue: GameViewModel(request: request))
    }

    private var character: AnimalCharacter {
        CharacterCatalog.character(id: director.characterID)
    }

    private var hudControlSize: CGFloat { usesPadMetrics ? 44 : 34 }
    private var hudSymbolSize: CGFloat { usesPadMetrics ? 34 : 26 }
    private var hudNumberSize: CGFloat { usesPadMetrics ? 32 : 24 }
    private var topInset: CGFloat { usesPadMetrics ? 28 : 18 }

    var body: some View {
        ZStack(alignment: .top) {
            playfield
                .blur(radius: director.backgroundBlur)

            hud
                .padding(.leading, usesPadMetrics ? 28 : 16)
                .padding(.trailing, usesPadMetrics ? 28 : 16)
                .padding(.top, topInset + (usesPadMetrics ? 12 : 6))
                .opacity(director.playsLevelCompletion || director.iconOpacity > 0.5 ? 0 : 1)
                .animation(.easeOut(duration: 0.22), value: director.playsLevelCompletion)
                .allowsHitTesting(false)

            captionOverlay

            appIconOverlay

            #if DEBUG
            // Debug overlay removed after verifying place vs capture.
            #endif
        }
        .frame(width: layoutSize.width, height: layoutSize.height)
        .clipped()
        .background(Color(red: 0.05, green: 0.25, blue: 0.40))
        .preferredColorScheme(.light)
        .ignoresSafeArea()
        .onAppear {
            UserDefaults.standard.set(true, forKey: GameSettings.onboardingCompleteKey)
            UserDefaults.standard.set(false, forKey: GameSettings.onboardingReplayRequestedKey)
            GameSettings.characterID = "octopus"
            LanguageManager.shared.override = AppLanguage.named("en")
            if !GameSettings.musicEnabled { AppAudio.shared.toggleMusic() }
            if !GameSettings.gameSoundsEnabled { AppAudio.shared.toggleGameSounds() }
            if GameSettings.spokenSumsEnabled { AppAudio.shared.toggleSpokenSums() }
            // Trailer: avoid touching AVAudioEngine at boot (Simulator can hang /
            // abort on AURemoteIO). Music is muxed into the MP4 after capture.
            model.prepare()
            Task { await boot() }
        }
        .onDisappear {
            tearDown()
        }
    }

    private var playfield: some View {
        ReefPlayfield(
            round: model.round,
            maximumRounds: model.maximumRounds,
            character: character,
            isPad: usesPadMetrics,
            isLive: model.acceptsInput || model.state == .answering,
            isRunning: true,
            playsFishEntrance: false,
            hasBonusFishPower: model.hasBonusFishPower,
            isHeartFishAvailable: model.isHeartFishAvailable,
            heartFishRestoresWholeLife: model.heartFishGivesWholeLife,
            isStreakBoostActive: model.isStreakBoostActive,
            playsLevelCompletion: director.playsLevelCompletion,
            reduceMotion: false,
            tutorialPlan: ReefTutorialPlan(),
            topReserve: topInset + (usesPadMetrics ? 54 : 42),
            bottomReserve: usesPadMetrics ? 12 : 8,
            scoreTarget: nil,
            onHit: { id in
                if director.blocksAnswerHits { return false }
                guard let correctID = model.round?.correctOption?.id, id == correctID else {
                    return false
                }
                return model.select(optionID: id)
            },
            onScoreBubbleArrived: model.scoreBubbleArrived,
            onBonusFishCaught: model.catchBonusFish,
            onHeartFishCaught: model.catchHeartFish,
            onHeartFishMissed: model.missHeartFish,
            onFishEntranceComplete: {},
            onLevelCompletionFinished: {
                director.handleLevelCompletionFinished()
            },
            onTutorialEvent: { _ in },
            onEngineReady: { engine in
                let changed = self.engine !== engine
                self.engine = engine
                director.attach(engine: engine, model: model)
                if changed {
                    director.enableExternalClock()
                    if encode.recordingStarted {
                        director.resyncForRecordingStart()
                    } else {
                        director.bootstrap()
                    }
                }
            },
            suppressesPlayerSteering: true,
            promptInForeground: true
        )
        .id("promo-trailer-reef")
    }

    private var hud: some View {
        ZStack {
            HStack(alignment: .center, spacing: usesPadMetrics ? 7 : 5) {
                Text(verbatim: LN(model.cards))
                    .font(.system(size: hudNumberSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                CurrencyIcon(size: hudSymbolSize)
            }
            .frame(height: hudControlSize)
            .foregroundStyle(character.deepColor)

            HStack(spacing: 10) {
                Circle()
                    .fill(character.deepColor)
                    .frame(width: hudControlSize, height: hudControlSize)
                    .overlay {
                        Image(systemName: "pause.fill")
                            .font(.system(size: usesPadMetrics ? 22 : 16, weight: .bold))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                Spacer(minLength: 0)
                LivesView(lives: model.livesRemaining,
                          character: character,
                          isPad: usesPadMetrics,
                          glyphSize: hudSymbolSize,
                          rowHeight: hudControlSize)
            }
        }
    }

    private var captionOverlay: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                PromoTrailerCaptionCard(text: director.captionText,
                                        theme: character,
                                        isPad: usesPadMetrics)
                    .id(director.captionText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, usesPadMetrics ? 24 : 16)
            .padding(.top, topInset + (usesPadMetrics ? 84 : 66))
            .opacity(director.captionOpacity)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var appIconOverlay: some View {
        VStack {
            Spacer()
            Image("app_icon_clean")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: usesPadMetrics ? 280 : 210,
                       height: usesPadMetrics ? 280 : 210)
                .clipShape(RoundedRectangle(cornerRadius: usesPadMetrics ? 64 : 48,
                                            style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                .rotationEffect(.degrees(director.iconRotation))
                .scaleEffect(director.iconScale)
                .opacity(director.iconOpacity)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func boot() async {
        print("PROMO_TRAILER_BOOT")
        await model.begin()
        print("PROMO_TRAILER_BEGAN")
        // Wait for ReefPlayfield layout so placeFish isn't a no-op.
        for _ in 0..<20 {
            if let engine, engine.trailerPlayfieldSize.width > 0 { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        director.bootstrap()
        print("PROMO_TRAILER_BOOTSTRAPPED")
        director.enableExternalClock()
        startClock()
        try? await Task.sleep(nanoseconds: 150_000_000)
        startRecording()
    }

    private func startRecording() {
        guard !encode.recordingStarted else { return }
        encode.recordingStarted = true
        encode.isFinishing = false
        let recorder = PromoTrailerRecorder(size: exportSize,
                                            fps: PromoTrailerRuntime.framesPerSecond)
        encode.recorder = recorder
        do {
            try recorder.start()
            director.enableExternalClock()
            director.resyncForRecordingStart()
            if let engine {
                let p = engine.trailerFishPosition
                print("PROMO_TRAILER_PLACE fish=(\(Int(p.x)),\(Int(p.y))) size=\(Int(engine.trailerPlayfieldSize.width))x\(Int(engine.trailerPlayfieldSize.height))")
            }
            encode.lastCaptureIndex = -1
            encode.warmupFramesRemaining = 8
            encode.pendingCaptureElapsed = nil
            encode.pendingFinish = false
            encode.recordStartDate = Date()
            print("PROMO_TRAILER_RECORDING")
        } catch {
            print("PROMO_TRAILER_ERROR \(error)")
            onFinished(nil)
        }
    }

    private func startClock() {
#if canImport(UIKit)
        guard displayLink == nil else { return }
        let encode = self.encode
        let director = self.director
        let layoutSize = self.layoutSize
        let exportSize = self.exportSize
        let captureProvider = self.captureProvider
        let onFinished = self.onFinished
        let proxy = PromoDisplayLinkProxy {
            Self.advanceEncode(encode: encode,
                               director: director,
                               layoutSize: layoutSize,
                               exportSize: exportSize,
                               captureProvider: captureProvider,
                               onFinished: onFinished,
                               stopClock: { [self] in
                                   self.displayLink?.invalidate()
                                   self.displayLink = nil
                               })
        }
        linkTarget = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(PromoDisplayLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
#endif
    }

    private static func advanceEncode(encode: PromoEncodeState,
                                      director: PromoTrailerDirector,
                                      layoutSize: CGSize,
                                      exportSize: CGSize,
                                      captureProvider: () -> UIView?,
                                      onFinished: @escaping (URL?) -> Void,
                                      stopClock: @escaping () -> Void) {
        guard encode.recordingStarted, !encode.isFinishing else { return }

        // Offline encode: advance content as fast as capture allows. Wall-clock
        // pacing made Simulator exports time out (~3–5 fps capture vs 30 fps).
        let fps = Double(PromoTrailerRuntime.framesPerSecond)

        // Capture the previous sim step on the next display beat so SwiftUI has
        // committed FishView.position (same-turn drawHierarchy stays stale).
        if let pending = encode.pendingCaptureElapsed {
            // Opening frames: re-place then wait one display beat before snapshot.
            if encode.lastCaptureIndex <= 2, !encode.openPoseHold {
                director.resyncForRecordingStart()
                encode.openPoseHold = true
                return
            }
            encode.openPoseHold = false
            encode.pendingCaptureElapsed = nil
            CATransaction.flush()
            if encode.lastCaptureIndex <= 2 {
                let p = director.engineFishPosition
                print("PROMO_TRAILER_SNAP fish=(\(Int(p.x)),\(Int(p.y))) frame=\(encode.lastCaptureIndex)")
            }
            if let image = snapshot(layoutSize: layoutSize, exportSize: exportSize,
                                    captureProvider: captureProvider,
                                    forceFresh: encode.lastCaptureIndex < 15) {
                encode.recorder?.capture(image: image, at: pending)
            }
            if encode.lastCaptureIndex % 30 == 0 {
                print("PROMO_TRAILER_FRAME \(encode.lastCaptureIndex)")
            }
            if encode.pendingFinish {
                encode.pendingFinish = false
                encode.isFinishing = true
                encode.recorder?.audioCues = director.trailerAudioCues
                finishEncode(encode: encode, onFinished: onFinished, stopClock: stopClock)
                return
            }
        }

        // Warm-up: place + let SwiftUI commit before encoding frame 0.
        if encode.warmupFramesRemaining > 0 {
            encode.warmupFramesRemaining -= 1
            director.resyncForRecordingStart()
            return
        }

        let next = encode.lastCaptureIndex + 1
        let elapsed = Double(next) / fps
        if next == 0 {
            director.resyncForRecordingStart()
            director.tick(elapsed: 0)
        } else {
            director.stepSimulation(dt: 1.0 / fps)
            director.tick(elapsed: elapsed)
        }
        encode.lastCaptureIndex = next
        encode.pendingCaptureElapsed = elapsed
        if director.isFinished || elapsed >= PromoTrailerRuntime.maximumDuration {
            encode.pendingFinish = true
        }
    }

    private static func snapshot(layoutSize: CGSize,
                                 exportSize: CGSize,
                                 captureProvider: () -> UIView?,
                                 forceFresh: Bool) -> UIImage? {
        guard let view = captureProvider() else { return nil }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let layoutImage = UIGraphicsImageRenderer(size: layoutSize, format: format).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: layoutSize),
                               afterScreenUpdates: forceFresh)
        }
        if layoutSize == exportSize { return layoutImage }
        return UIGraphicsImageRenderer(size: exportSize, format: format).image { _ in
            layoutImage.draw(in: CGRect(origin: .zero, size: exportSize))
        }
    }

    private static func finishEncode(encode: PromoEncodeState,
                                     onFinished: @escaping (URL?) -> Void,
                                     stopClock: @escaping () -> Void) {
        guard encode.recordingStarted else { return }
        encode.recordingStarted = false
        stopClock()
        Task {
            let url = await encode.recorder?.finish()
            print("PROMO_TRAILER_DONE \(url?.path ?? "nil")")
            onFinished(url)
        }
    }

    private func finishRecording() {
        encode.isFinishing = true
        encode.recorder?.audioCues = director.trailerAudioCues
        Self.finishEncode(encode: encode, onFinished: onFinished) { [self] in
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func tearDown() {
        displayLink?.invalidate()
        displayLink = nil
        encode.recordingStarted = false
        AppAudio.shared.setGameplayActive(false, questionText: nil)
        model.end()
    }
}

final class PromoEncodeState {
    var recordingStarted = false
    var isFinishing = false
    var recorder: PromoTrailerRecorder?
    var recordStartDate: Date?
    var lastCaptureIndex: Int64 = -1
    var warmupFramesRemaining = 0
    var pendingCaptureElapsed: TimeInterval?
    var pendingFinish = false
    var openPoseHold = false
}

#if canImport(UIKit)
final class PromoDisplayLinkProxy: NSObject {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func tick() { handler() }
}
#endif

struct PromoTrailerCaptionCard: View {
    let text: String
    let theme: AnimalCharacter
    var isPad: Bool

    private var portraitSize: CGFloat { isPad ? 56 : 40 }
    private var fontSize: CGFloat { isPad ? 30 : 22 }

    var body: some View {
        HStack(alignment: .center, spacing: isPad ? 14 : 10) {
            theme.artwork
                .resizable()
                .scaledToFit()
                .frame(width: portraitSize, height: portraitSize)

            Text(verbatim: text)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.deepColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, isPad ? 12 : 8)
        .padding(.trailing, isPad ? 18 : 14)
        .padding(.vertical, isPad ? 10 : 6)
        .background {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.95))
                .shadow(color: theme.deepColor.opacity(0.18), radius: 8, y: 4)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(theme.skyColor.opacity(0.85), lineWidth: 1.5)
        }
    }
}
