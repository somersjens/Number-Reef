//
//  PromoTrailerDirector.swift
//  Number Reef
//
//  Drives the real ReefEngine + GameViewModel along a fixed teaser timeline.
//

import SwiftUI
import Combine

@MainActor
final class PromoTrailerDirector: ObservableObject {
    @Published private(set) var characterID = "octopus"
    @Published private(set) var captionText = ""
    @Published private(set) var captionOpacity: Double = 0
    @Published private(set) var cameraZoom: CGFloat = 1
    @Published private(set) var cameraAnchor: UnitPoint = .center
    @Published private(set) var iconOpacity: Double = 0
    @Published private(set) var iconScale: CGFloat = 0.78
    @Published private(set) var iconRotation: Double = -26
    @Published private(set) var playsLevelCompletion = false
    @Published private(set) var backgroundBlur: CGFloat = 0
    @Published private(set) var isFinished = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// When true, answer collisions are ignored so the scripted swim can pass
    /// through distractors without spending a life or clearing the wave.
    @Published private(set) var blocksAnswerHits = false

    private weak var engine: ReefEngine?
    private weak var model: GameViewModel?

    private var openingRound = PromoTrailerScript.openingRound()
    private var midRound = PromoTrailerScript.midRound()
    private var finalRound = PromoTrailerScript.finalRound()

    private var didStartOpening = false
    private var didInstallMid = false
    private var didSpawnBonus = false
    private var didSeedStreak = false
    private var didSpawnLife = false
    private var didInstallFinal = false
    private var didTriggerCompletion = false
    private var didShowIcon = false
    private var openingCollected = false
    private var penultimateCollected = false
    private var finalCollected = false
    private var openingHitAt: TimeInterval?
    private var awaitingFinalInstall = false
    private var didCatchBonus = false
    private var didCatchLife = false
    private var smoothSteerTarget: CGPoint?
    private var audioCues: [(time: TimeInterval, file: String, volume: Float)] = []
    private var finaleAt: TimeInterval?
    private var finishAt: TimeInterval?
    private var iconRevealAt: TimeInterval?

    func attach(engine: ReefEngine, model: GameViewModel) {
        if self.engine !== engine {
            // ReefPlayfield can rebuild a fresh @StateObject; never keep steering
            // an orphaned engine while the on-screen reef is a new instance.
            didStartOpening = false
            didInstallMid = false
            didInstallFinal = false
        }
        self.engine = engine
        self.model = model
        engine.trailerPrepareDeterministicSession()
        model.onAnswerResolved = { [weak self] isCorrect, startedStreak in
            self?.handleAnswer(isCorrect: isCorrect, startedStreak: startedStreak)
        }
        model.setHeartFishRestoresWholeLife(true)
        // Whole trailer starts at 2 lives; the life-fish beat restores to 3.
        model.trailerSetLifeHalves(4)
        engine.trailerCompletionSpeedScale = 1.2
        engine.trailerKeepCompletionStream = true
        GameSettings.characterID = "octopus"
        characterID = "octopus"
        audioCues.removeAll()
        finaleAt = nil
        finishAt = nil
    }

    /// SFX cues collected during the scripted run — muxed into the MP4 after
    /// video capture (Simulator cannot reliably tap AVAudioEngine).
    var trailerAudioCues: [(time: TimeInterval, file: String, volume: Float)] {
        audioCues
    }

    var engineFishPosition: CGPoint {
        engine?.trailerFishPosition ?? .zero
    }

    private func cueSFX(_ file: String, volume: Float, at time: TimeInterval? = nil) {
        let at = time ?? elapsed
        audioCues.append((at, file, volume))
        print("PROMO_TRAILER_SFX \(file) t=\(String(format: "%.2f", at))")
    }

    func enableExternalClock() {
        engine?.trailerEnableExternalClock()
    }

    func stepSimulation(dt: Double) {
        engine?.trailerStep(dt: dt)
    }

    /// Resets path steering to t=0 when recording begins (avoids the warm-up
    /// swim reversing back to the opening waypoint).
    func resyncForRecordingStart() {
        guard let engine else { return }
        let start = point(x: PromoTrailerScript.openingFishUnit.x,
                          y: PromoTrailerScript.openingFishUnit.y, in: engine)
        engine.trailerPlaceFish(at: start, heading: PromoTrailerScript.openingFishHeading)
        let ahead = PromoTrailerScript.pathPoint(at: PromoTrailerScript.steerLookAhead)
        let startTarget = point(x: ahead.x, y: ahead.y, in: engine)
        smoothSteerTarget = startTarget
        engine.steer(toward: startTarget)
        // Keep rounds/lives; only reset motion to the scripted t=0 pose.
        if audioCues.isEmpty {
            cueSFX("sfx_session_start", volume: 0.16, at: 0.05)
        }
        engine.objectWillChange.send()
    }

    /// Called once the playfield has laid out and the session is answering.
    func bootstrap() {
        guard let engine, let model, !didStartOpening else { return }

        let size = engine.trailerPlayfieldSize
        guard size.width > 0 else { return }
        didStartOpening = true

        model.trailerSetLifeHalves(4)

        // Start near the sea-floor spawn and climb the right corridor.
        let start = point(x: PromoTrailerScript.openingFishUnit.x,
                          y: PromoTrailerScript.openingFishUnit.y, in: engine)
        engine.trailerPlaceFish(at: start, heading: PromoTrailerScript.openingFishHeading)

        openingRound = PromoTrailerScript.openingRound(number: 1)
        model.trailerInstall(round: openingRound)
        engine.load(round: openingRound)
        engine.setLive(true)
        engine.trailerInstallAnswerQueue(
            PromoTrailerScript.openingQueue(from: openingRound),
            gapsBeforeEachRelease: PromoTrailerScript.openingGaps,
            ventFractions: PromoTrailerScript.openingVentFractions
        )

        let ahead = PromoTrailerScript.pathPoint(at: PromoTrailerScript.steerLookAhead)
        let startTarget = point(x: ahead.x, y: ahead.y, in: engine)
        smoothSteerTarget = startTarget
        engine.steer(toward: startTarget)
    }

    /// Advances scripted steering / spawns. `elapsed` is recording time.
    func tick(elapsed: TimeInterval) {
        self.elapsed = elapsed
        guard let engine, let model, !isFinished else { return }

        updateCaption(at: elapsed)
        updateCharacter(at: elapsed)
        updateCamera(at: elapsed, engine: engine)
        updateAnswerGate(at: elapsed)
        steer(at: elapsed, engine: engine)
        assistCollectIfNeeded(at: elapsed, engine: engine, model: model)
        assistHelpersIfNeeded(at: elapsed, engine: engine, model: model)

        if !didInstallMid, openingCollected {
            installMid(engine: engine, model: model)
        }

        if !didSpawnBonus, penultimateCollected,
           elapsed >= PromoTrailerScript.spawnBonusFishAt {
            didSpawnBonus = true
            engine.trailerSpawnBonusFishFromRight(yFraction: 0.80)
        }

        if !didSeedStreak, elapsed >= PromoTrailerScript.seedStreakAt {
            didSeedStreak = true
            model.trailerSeedCorrectStreak(4)
        }

        // Life fish after the streak hit — lives stay at 2 until catch → 3.
        if !didSpawnLife, penultimateCollected, elapsed >= PromoTrailerScript.spawnLifeFishAt {
            didSpawnLife = true
            model.setHeartFishRestoresWholeLife(true)
            model.makeHeartFishAvailable()
            engine.trailerSpawnHeartFishFromLeft(yFraction: 0.38)
        }

        if awaitingFinalInstall, !didInstallFinal,
           elapsed >= PromoTrailerScript.installFinalRoundAt {
            installFinal(engine: engine, model: model)
        }

        if let due = finaleAt, elapsed >= due {
            finaleAt = nil
            beginFinale()
        }

        if !didTriggerCompletion, didInstallFinal, elapsed >= PromoTrailerScript.finaleFallbackAt {
            if !finalCollected {
                _ = engine.trailerTryCollectCorrect(within: engine.trailerAnswerHitRadius)
            }
            if finalCollected || elapsed >= PromoTrailerScript.finaleForceAt {
                beginFinale()
            }
        }

        // Production collision can catch helpers before assist — still mux SFX.
        if !didCatchBonus, engine.trailerHasBonusAura {
            markBonusCaught()
        }
        if !didCatchLife, didSpawnLife, model.livesRemaining >= 2.95 {
            markLifeCaught()
        }

        // Fallback icon if the completion callback never fires.
        if !didShowIcon, elapsed >= PromoTrailerScript.showIconAt {
            revealIcon()
        }

        if let started = iconRevealAt {
            let t = max(0, elapsed - started)
            let fade = min(1, t / 0.24)
            let turn = min(1, t / 0.52)
            iconOpacity = fade
            iconRotation = -26 * (1 - turn)
            iconScale = 0.82 + 0.18 * CGFloat(turn)
        }

        if let due = finishAt, elapsed >= due {
            isFinished = true
            engine.releaseTouch()
        }

        if !isFinished, elapsed >= PromoTrailerScript.endAt {
            isFinished = true
            engine.releaseTouch()
        }
    }

    /// Called when the production level-completion swim-out finishes.
    func handleLevelCompletionFinished() {
        revealIcon()
        finishAt = elapsed + PromoTrailerScript.iconHold
    }

    // MARK: - Private

    private func revealIcon() {
        guard !didShowIcon else { return }
        didShowIcon = true
        iconRevealAt = elapsed
        iconOpacity = 0
        iconScale = 0.80
        iconRotation = -26
        backgroundBlur = 5
    }

    private func assistHelpersIfNeeded(at time: TimeInterval, engine: ReefEngine, model: GameViewModel) {
        if !didCatchBonus, penultimateCollected,
           time >= PromoTrailerScript.bonusAssistStart, time < PromoTrailerScript.bonusAssistEnd,
           let bonus = engine.trailerBonusFish,
           bonus.isCarryingReward {
            if engine.trailerTryCatchBonusFish(within: engine.trailerHelperHitRadius(length: bonus.length)) {
                markBonusCaught()
            }
            return
        }
        if !didCatchLife, time >= PromoTrailerScript.lifeAssistStart, time < PromoTrailerScript.lifeAssistEnd,
           let heart = engine.trailerHeartFish,
           heart.isCarryingReward {
            if engine.trailerTryCatchHeartFish(within: engine.trailerHelperHitRadius(length: heart.length)) {
                markLifeCaught()
            }
        }
        _ = model
    }

    private func markBonusCaught() {
        guard !didCatchBonus else { return }
        didCatchBonus = true
        cueSFX("sfx_double_card", volume: 0.22)
    }

    private func markLifeCaught() {
        guard !didCatchLife else { return }
        didCatchLife = true
        cueSFX("sfx_character_unlock", volume: 0.18)
    }

    private func assistCollectIfNeeded(at time: TimeInterval, engine: ReefEngine, model: GameViewModel) {
        guard !blocksAnswerHits else { return }
        let target: ReefBubble?
        let radiusScale: CGFloat
        if !openingCollected, time >= PromoTrailerScript.openingAssistAt {
            target = engine.trailerBubbles.first { $0.isCorrect && !$0.isPopping }
            radiusScale = engine.trailerIsPad ? 1.85 : 1.42
        } else if !penultimateCollected, time >= PromoTrailerScript.midAssistAt {
            target = engine.trailerBubbles.first { $0.isCorrect && !$0.isPopping }
            radiusScale = 1.15
        } else if !finalCollected, time >= PromoTrailerScript.finalAssistAt {
            target = engine.trailerBubbles.first { $0.isCorrect && !$0.isPopping }
            radiusScale = engine.trailerIsPad ? 1.12 : 1.05
        } else {
            target = nil
            radiusScale = 1
        }
        guard target != nil else { return }
        engine.setLive(true)
        _ = engine.trailerTryCollectCorrect(within: engine.trailerAnswerHitRadius * radiusScale)
        _ = model
    }

    private func updateAnswerGate(at time: TimeInterval) {
        if !openingCollected {
            blocksAnswerHits = time < PromoTrailerScript.openingHitGate
            return
        }
        if !penultimateCollected {
            blocksAnswerHits = time < PromoTrailerScript.midHitGate
            return
        }
        if !finalCollected {
            blocksAnswerHits = time < PromoTrailerScript.finalHitGate
            return
        }
        blocksAnswerHits = true
    }

    private func handleAnswer(isCorrect: Bool, startedStreak: Bool) {
        guard isCorrect else { return }
        cueSFX("sfx_correct", volume: 0.14)
        if !openingCollected {
            openingCollected = true
            openingHitAt = elapsed
            return
        }
        if !penultimateCollected {
            penultimateCollected = true
            awaitingFinalInstall = true
            if startedStreak {
                cueSFX("sfx_double_score", volume: 0.15)
            }
            return
        }
        if !finalCollected {
            finalCollected = true
            finaleAt = elapsed + PromoTrailerScript.forceCompletionAfterFinal
        }
    }

    private func installMid(engine: ReefEngine, model: GameViewModel) {
        didInstallMid = true
        midRound = PromoTrailerScript.midRound(number: 2)
        // Wrongs only — the 5 waits for the streak beat. Queue first so a
        // SwiftUI `onChange(round)` load echo keeps the rising next sum.
        engine.trailerInstallAnswerQueue(
            PromoTrailerScript.midShowcaseQueue(from: midRound),
            gapsBeforeEachRelease: PromoTrailerScript.midShowcaseGaps,
            ventFractions: PromoTrailerScript.midShowcaseVentFractions,
            exactVents: !engine.trailerIsPad
        )
        model.trailerInstall(round: midRound)
        engine.setLive(true)
    }

    private func installFinal(engine: ReefEngine, model: GameViewModel) {
        didInstallFinal = true
        awaitingFinalInstall = false
        finalRound = PromoTrailerScript.finalRound(number: 3)
        engine.trailerClearAnswers(keepRound: true)
        engine.trailerInstallAnswerQueue(
            PromoTrailerScript.finalQueue(from: finalRound),
            gapsBeforeEachRelease: PromoTrailerScript.finalGaps,
            ventFractions: PromoTrailerScript.finalVentFractions
        )
        model.trailerInstall(round: finalRound)
        engine.setLive(true)
    }

    private func beginFinale() {
        guard !didTriggerCompletion, let model else { return }
        didTriggerCompletion = true
        cueSFX("sfx_level_complete", volume: 0.10)
        model.trailerForceLevelComplete()
        playsLevelCompletion = true
    }

    private func updateCaption(at time: TimeInterval) {
        if playsLevelCompletion || iconOpacity > 0.2 {
            if captionOpacity != 0 { captionOpacity = 0 }
            return
        }
        guard let active = PromoTrailerScript.captions(openingHitAt: openingHitAt).first(where: {
            time >= $0.start && time < $0.end
        }) else {
            if captionOpacity != 0 { captionOpacity = 0 }
            return
        }
        captionText = active.text
        // Fade on the simulation clock only — SwiftUI animations use wall time
        // and smear two captions together during offline encode.
        let fade: TimeInterval = 0.14
        let into = max(0, time - active.start)
        let out = max(0, active.end - time)
        var opacity = 1.0
        if into < fade {
            let t = into / fade
            opacity = t * t * (3 - 2 * t)
        }
        if out < fade {
            let t = out / fade
            opacity = min(opacity, t * t * (3 - 2 * t))
        }
        captionOpacity = opacity
    }

    private func updateCharacter(at time: TimeInterval) {
        let origin = openingHitAt ?? PromoTrailerScript.zoomUnlockStart
        var next = "octopus"
        for beat in PromoTrailerScript.characterBeatOffsets where time >= origin + beat.offset {
            next = beat.id
        }
        guard next != characterID else { return }
        characterID = next
        GameSettings.characterID = next
    }

    private func updateCamera(at time: TimeInterval, engine: ReefEngine) {
        let start = openingHitAt ?? PromoTrailerScript.zoomUnlockStart
        let end = start + PromoTrailerScript.zoomUnlockDuration
        let peak = PromoTrailerScript.unlockZoom
        let zoom: CGFloat
        let zoomOut: TimeInterval = 0.70
        if time < start || time > end {
            zoom = 1
        } else if time < start + 0.55 {
            let t = CGFloat((time - start) / 0.55)
            zoom = 1 + (peak - 1) * (t * t * (3 - 2 * t))
        } else if time > end - zoomOut {
            let t = CGFloat((end - time) / zoomOut)
            zoom = 1 + (peak - 1) * (t * t * (3 - 2 * t))
        } else {
            zoom = peak
        }
        cameraZoom = zoom

        // Never leave the anchor off-center once zoom is gone — that read as a
        // frame shift after the life-fish beat.
        if zoom <= 1.02 || playsLevelCompletion {
            cameraAnchor = .center
            return
        }
        let size = engine.trailerPlayfieldSize
        guard size.width > 1, size.height > 1 else {
            cameraAnchor = .center
            return
        }
        let fish = engine.trailerFishPosition
        // During zoom-out, pull the anchor back to center so the settle is calm.
        let raw = UnitPoint(x: min(0.78, max(0.22, fish.x / size.width)),
                            y: min(0.68, max(0.28, fish.y / size.height)))
        if time > end - zoomOut {
            let t = CGFloat((end - time) / zoomOut)
            cameraAnchor = UnitPoint(x: 0.5 + (raw.x - 0.5) * t,
                                     y: 0.5 + (raw.y - 0.5) * t)
        } else {
            cameraAnchor = raw
        }
    }

    private func steer(at time: TimeInterval, engine: ReefEngine) {
        guard !playsLevelCompletion else { return }

        let pad = engine.trailerIsPad
        let lookAhead: TimeInterval
        if !pad, !openingCollected,
           time >= PromoTrailerScript.underPassLookAheadStart && time < PromoTrailerScript.underPassLookAheadEnd {
            lookAhead = 0.10
        } else if time >= 5.5 && time < 11.1 {
            lookAhead = PromoTrailerScript.unlockLookAhead
        } else {
            lookAhead = PromoTrailerScript.steerLookAhead
        }
        let look = time + lookAhead
        let unit = PromoTrailerScript.pathPoint(at: look)
        var desired = point(x: unit.x, y: unit.y, in: engine)
        let weave: CGFloat
        if !pad, !openingCollected, time >= 2.35 && time < 3.50 {
            weave = 0
        } else if !pad, time >= 6.70 && time < 8.50 {
            // Keep the climb between 3 and 6 on the scripted lane.
            weave = 0
        } else if !pad, time >= 10.15 && time < 11.55 {
            weave = 0.18
        } else if time >= (openingHitAt ?? PromoTrailerScript.zoomUnlockStart) && time < 11.0 {
            weave = pad ? 1.12 : 0.78
        } else if time >= 11.7 && time < 13.4 {
            weave = pad ? 0.65 : 0.50
        } else if time >= 13.4 && time < 18.2 {
            weave = pad ? 1.12 : 0.82
        } else {
            weave = pad ? 1 : 0.72
        }
        let allowCorrect = (!openingCollected && time >= PromoTrailerScript.openingHitGate)
            || (!penultimateCollected && time >= PromoTrailerScript.midHitGate)
            || (!finalCollected && time >= PromoTrailerScript.finalHitGate)
        desired = avoidWrongBubbles(desired: desired, engine: engine,
                                    allowingCorrectApproach: allowCorrect,
                                    strength: weave)

        if !openingCollected, time >= PromoTrailerScript.openingHitGate - (pad ? 0 : 0.06),
           let thirteen = engine.trailerBubbles.first(where: { $0.isCorrect && !$0.isPopping }) {
            desired = blendToward(desired, thirteen.position, engine: engine,
                                  enter: pad ? 260 : 120,
                                  full: engine.trailerAnswerHitRadius * (pad ? 0.55 : 0.42))
        } else if !penultimateCollected, time >= PromoTrailerScript.midHitGate - 0.05,
                  let five = engine.trailerBubbles.first(where: { $0.isCorrect && !$0.isPopping }) {
            desired = blendToward(desired, five.position, engine: engine,
                                  enter: pad ? 240 : 170,
                                  full: engine.trailerAnswerHitRadius)
        } else if penultimateCollected, !didCatchBonus,
                  time >= PromoTrailerScript.bonusBlendStart, time < PromoTrailerScript.bonusBlendEnd,
                  let bonus = engine.trailerBonusFish, bonus.isCarryingReward {
            desired = blendToward(desired, bonus.carriedCoinPosition, engine: engine,
                                  enter: pad ? 300 : 250,
                                  full: pad ? 90 : 70)
        } else if !didCatchLife,
                  time >= PromoTrailerScript.lifeBlendStart, time < PromoTrailerScript.lifeBlendEnd,
                  let heart = engine.trailerHeartFish, heart.isCarryingReward {
            desired = blendToward(desired, heart.position, engine: engine,
                                  enter: pad ? 300 : 250,
                                  full: pad ? 90 : 70)
        } else if !finalCollected, time >= PromoTrailerScript.finalBlendAt,
                  let twenty = engine.trailerBubbles.first(where: { $0.isCorrect && !$0.isPopping }) {
            desired = blendToward(desired, twenty.position, engine: engine,
                                  enter: pad ? 220 : 150,
                                  full: engine.trailerAnswerHitRadius * (pad ? 0.7 : 0.55))
        }

        let blend: CGFloat
        if time < 3.45 {
            blend = pad ? 0.32 : 0.26
        } else if time >= PromoTrailerScript.openingHitGate && time < PromoTrailerScript.openingHitGate + 0.85 {
            blend = pad ? 0.30 : 0.26
        } else if time >= 11.2 && time < 14.0 {
            blend = pad ? 0.24 : 0.18
        } else if time >= PromoTrailerScript.finalBlendAt && time < PromoTrailerScript.finalBlendAt + 0.80 {
            blend = pad ? 0.30 : 0.18
        } else {
            blend = pad ? 0.22 : 0.16
        }
        applySteer(toward: desired, engine: engine, blend: blend)
    }

    private func blendToward(_ desired: CGPoint, _ target: CGPoint, engine: ReefEngine,
                             enter: CGFloat, full: CGFloat) -> CGPoint {
        let fish = engine.trailerFishPosition
        let dx = target.x - fish.x
        let dy = target.y - fish.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance < enter else { return desired }
        let t = min(1, max(0, (enter - distance) / max(enter - full, 1)))
        let ease = t * t * (3 - 2 * t)
        return CGPoint(x: desired.x + (target.x - desired.x) * ease,
                       y: desired.y + (target.y - desired.y) * ease)
    }

    private func applySteer(toward raw: CGPoint, engine: ReefEngine, blend: CGFloat) {
        let next: CGPoint
        if let previous = smoothSteerTarget {
            let t = min(max(blend, 0.08), 1)
            next = CGPoint(x: previous.x + (raw.x - previous.x) * t,
                           y: previous.y + (raw.y - previous.y) * t)
        } else {
            next = raw
        }
        smoothSteerTarget = next
        engine.steer(toward: next)
    }

    private func avoidWrongBubbles(desired: CGPoint, engine: ReefEngine,
                                   allowingCorrectApproach: Bool,
                                   strength: CGFloat = 1) -> CGPoint {
        _ = allowingCorrectApproach
        guard strength > 0.01 else { return desired }
        let fish = engine.trailerFishPosition
        let fishRadius = engine.trailerFishLength * 0.42
        let bubbleRadius = engine.trailerBubbleRadius
        let clearance = fishRadius + bubbleRadius + (engine.trailerIsPad ? 52 : 22)
        var result = desired
        for bubble in engine.trailerBubbles where !bubble.isPopping {
            if bubble.isCorrect && allowingCorrectApproach { continue }
            for probe in [fish, desired] {
                let dx = probe.x - bubble.position.x
                let dy = probe.y - bubble.position.y
                let distance = sqrt(dx * dx + dy * dy)
                guard distance < clearance, distance > 0.5 else { continue }
                let push = (clearance - distance) / clearance
                let scale = clearance * push * 1.15 * strength
                result.x += dx / distance * scale
                result.y += dy / distance * scale
            }
        }
        return result
    }

    private func point(x: CGFloat, y: CGFloat, in engine: ReefEngine) -> CGPoint {
        let size = engine.trailerPlayfieldSize
        let top = engine.trailerTopReserve
        let bottom = max(top + 40, engine.trailerSpawnLine - 30)
        return CGPoint(x: size.width * x,
                       y: top + (bottom - top) * y)
    }
}
