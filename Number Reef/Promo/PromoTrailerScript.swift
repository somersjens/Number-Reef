//
//  PromoTrailerScript.swift
//  Number Reef
//
//  Fixed math beats and timeline waypoints for the App Store teaser.
//

import Foundation
import CoreGraphics

enum PromoTrailerScript {
    // MARK: Math

    /// Opening beat: four bubbles, correct last (= lowest once all are up).
    static func openingRound(number: Int = 1) -> GameRound {
        makeRound(number: number,
                  prompt: "6 + 7 = ?",
                  correct: "13",
                  wrongs: ["11", "12", "14"])
    }

    /// Rising set shown as prompt during unlock / helper beats.
    static func midRound(number: Int = 2) -> GameRound {
        makeRound(number: number,
                  prompt: "9 − 4 = ?",
                  correct: "5",
                  wrongs: ["3", "4", "6", "7"])
    }

    /// Final beat after the life fish — collecting this triggers the finale.
    static func finalRound(number: Int = 3) -> GameRound {
        makeRound(number: number,
                  prompt: "4 × 5 = ?",
                  correct: "20",
                  wrongs: ["16", "18", "22", "24"])
    }

    private static func makeRound(number: Int,
                                  prompt: String,
                                  correct: String,
                                  wrongs: [String]) -> GameRound {
        let question = MathQuestion(prompt: prompt,
                                    correctAnswer: correct,
                                    distractors: wrongs,
                                    sourceLevel: 1,
                                    kind: .addition)
        var options = [AnswerOption(text: correct, isCorrect: true)]
        options += wrongs.map { AnswerOption(text: $0, isCorrect: false) }
        return GameRound(number: number, question: question, options: options)
    }

    /// 11/12/14 first; 13 last on the far-left so it is still rising when the
    /// fish arrives — production collision pops it like a real catch.
    static func openingQueue(from round: GameRound) -> [AnswerOption] {
        let wrongs = round.options.filter { !$0.isCorrect }
        guard let correct = round.options.first(where: \.isCorrect) else {
            return round.options
        }
        if usesPad {
            return [wrongs[0], wrongs[1], correct, wrongs[2]]
        }
        // iPhone: 12 first so it is already high when the fish glides under it.
        return [wrongs[1], wrongs[0], correct, wrongs[2]]
    }

    // Pad: 11 left-center, 12 center, 13 far left, 14 right.
    // Phone: 12 first (center), then 11, 13, 14.
    static var openingVentFractions: [CGFloat] {
        usesPad ? [0.22, 0.50, 0.08, 0.92] : [0.54, 0.22, 0.08, 0.92]
    }

    static var openingGaps: [Double] {
        usesPad ? [0.10, 0.50, 0.55, 2.20] : [0.04, 0.22, 0.75, 2.20]
    }

    private static var usesPad: Bool { PromoTrailerRuntime.usesPadMetrics }

    static func midShowcaseQueue(from round: GameRound) -> [AnswerOption] {
        let wrongs = round.options.filter { !$0.isCorrect }
        guard let correct = round.options.first(where: \.isCorrect) else {
            return Array(wrongs.prefix(3))
        }
        if usesPad {
            // Three wrongs during unlock; 5 early enough to collect before the 2×.
            return Array(wrongs.prefix(3)) + [correct]
        }
        // iPhone: 3 and 6 during unlock; 5 for the collect; 4 last and low
        // so it is not sitting in the last character-switch arc.
        let three = wrongs.first { $0.text == "3" }
        let four = wrongs.first { $0.text == "4" }
        let six = wrongs.first { $0.text == "6" }
        return [three, six, correct, four].compactMap { $0 }
    }

    static var midShowcaseVentFractions: [CGFloat] {
        // iPhone: 6 a half-bubble left of the far-right crater so the lion
        // still has a lane between 3 and 6.
        usesPad ? [0.00, 1.00, 0.28, 0.50] : [0.00, 0.61, 0.48, 1.00]
    }

    static var midShowcaseGaps: [Double] {
        // iPhone: same 3/6/5 timing as before; 4 delayed so it is still
        // rising from the bottom-right during the glide into 5.
        usesPad ? [0.18, 0.70, 0.70, 2.55] : [0.18, 0.85, 3.60, 2.35]
    }

    static func finalQueue(from round: GameRound) -> [AnswerOption] {
        let wrongs = round.options.filter { !$0.isCorrect }
        guard let correct = round.options.first(where: \.isCorrect) else {
            return round.options
        }
        // 16/18 right after the 5; 22/24 fill the left-center while the fish
        // arcs right; 20 last on the far left so it is still low.
        return Array(wrongs.prefix(4)) + [correct]
    }

    /// 16 left-center, 18 center, 22 under 16, 24 a bit right of 22, 20 far left.
    static let finalVentFractions: [CGFloat] = [0.28, 0.52, 0.20, 0.38, 0.08]
    static let finalGaps: [Double] = [0.20, 0.62, 1.70, 1.35, 2.15]

    // MARK: Timeline

    struct Caption {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    static let captions: [Caption] = [
        Caption(text: "Avoid the wrong bubbles", start: 0.10, end: 4.8),
        Caption(text: "Unlock new characters", start: 5.2, end: 10.85),
        Caption(text: "Catch helper fish in time", start: 11.30, end: 16.25),
        Caption(text: "And learn math", start: 16.70, end: 20.8)
    ]

    static func captions(openingHitAt: TimeInterval?) -> [Caption] {
        let unlock = openingHitAt ?? zoomUnlockStart
        let catchStart: TimeInterval = 11.30
        let learnStart: TimeInterval = 16.70
        let gap: TimeInterval = 0.40
        let avoidEnd = min(4.8, unlock - gap)
        let unlockEnd = min(unlock + unlockCaptionDuration, catchStart - gap)
        return [
            Caption(text: "Avoid the wrong bubbles", start: 0.10, end: max(0.10, avoidEnd)),
            Caption(text: "Unlock new characters", start: unlock, end: max(unlock + 0.20, unlockEnd)),
            Caption(text: "Catch helper fish in time", start: catchStart, end: learnStart - gap),
            Caption(text: "And learn math", start: learnStart, end: 20.8)
        ]
    }

    /// Character showcase, offsets from the opening (13) collect.
    static var characterBeatOffsets: [(offset: TimeInterval, id: String)] {
        if usesPad {
            return [
                (0.08, "octopus"),
                (1.18, "crab"),
                (2.38, "bear"),
                (3.68, "lion"),
                (5.68, "octopus")
            ]
        }
        // iPhone: crab earlier so the climb after 13 never waits on the swap.
        return [
            (0.08, "octopus"),
            (0.58, "crab"),
            (2.38, "bear"),
            (3.68, "lion"),
            (5.68, "octopus")
        ]
    }

    static let zoomUnlockDuration: TimeInterval = 5.70
    static let unlockCaptionDuration: TimeInterval = 5.80

    /// iPad keeps the signed-off path. iPhone uses a rounder, slightly earlier
    /// collect so the same unit waypoints do not read as corners on a taller field.
    static var openingHitGate: TimeInterval { usesPad ? 4.05 : 3.16 }
    static var openingAssistAt: TimeInterval { usesPad ? 4.10 : 3.18 }
    static var midHitGate: TimeInterval { usesPad ? 10.95 : 11.28 }
    static var midAssistAt: TimeInterval { usesPad ? 10.95 : 11.32 }
    static var finalHitGate: TimeInterval { usesPad ? 18.48 : 18.20 }
    static var finalAssistAt: TimeInterval { usesPad ? 18.48 : 18.22 }
    static var finalBlendAt: TimeInterval { usesPad ? 18.30 : 18.05 }

    static var steerLookAhead: TimeInterval { usesPad ? 0.40 : 0.24 }
    static var unlockLookAhead: TimeInterval { usesPad ? 0.32 : 0.18 }
    static var underPassLookAheadStart: TimeInterval { usesPad ? 2.35 : 2.35 }
    static var underPassLookAheadEnd: TimeInterval { usesPad ? 3.28 : 3.28 }

    static var bonusAssistStart: TimeInterval { usesPad ? 11.85 : 11.85 }
    static var bonusAssistEnd: TimeInterval { usesPad ? 14.6 : 14.6 }
    static var bonusBlendStart: TimeInterval { usesPad ? 11.8 : 11.8 }
    static var bonusBlendEnd: TimeInterval { usesPad ? 13.45 : 13.45 }
    static var lifeAssistStart: TimeInterval { usesPad ? 13.7 : 13.7 }
    static var lifeAssistEnd: TimeInterval { usesPad ? 15.5 : 15.5 }
    static var lifeBlendStart: TimeInterval { usesPad ? 13.6 : 13.6 }
    static var lifeBlendEnd: TimeInterval { usesPad ? 15.3 : 15.3 }

    static var finaleFallbackAt: TimeInterval { usesPad ? 21.8 : 21.8 }
    static var finaleForceAt: TimeInterval { usesPad ? 22.6 : 22.6 }

    struct Waypoint {
        let time: TimeInterval
        let x: CGFloat
        let y: CGFloat
    }

    static var swimPath: [Waypoint] {
        usesPad ? padSwimPath : phoneSwimPath
    }

    /// One continuous swim. Opening dives the empty right lane (14 is held back
    /// until the fish is already under), then left and up into 13.
    static let padSwimPath: [Waypoint] = [
        Waypoint(time: 0.00, x: 0.50, y: 0.22),
        Waypoint(time: 0.50, x: 0.70, y: 0.30),
        Waypoint(time: 1.00, x: 0.84, y: 0.48),
        Waypoint(time: 1.50, x: 0.86, y: 0.70),
        Waypoint(time: 2.10, x: 0.76, y: 0.90),
        Waypoint(time: 2.70, x: 0.52, y: 0.92),
        Waypoint(time: 3.20, x: 0.36, y: 0.90),
        // Under 12, then through 13 in one climb — no hover on the bubble.
        Waypoint(time: 3.70, x: 0.20, y: 0.88),
        Waypoint(time: 4.15, x: 0.11, y: 0.80),
        Waypoint(time: 4.40, x: 0.10, y: 0.70),
        Waypoint(time: 4.65, x: 0.16, y: 0.56),
        Waypoint(time: 5.05, x: 0.36, y: 0.40),
        Waypoint(time: 5.50, x: 0.56, y: 0.28),
        // Wide unlock loops — round crests, no corners at the top.
        Waypoint(time: 5.90, x: 0.70, y: 0.16),
        Waypoint(time: 6.35, x: 0.86, y: 0.26),
        Waypoint(time: 6.85, x: 0.84, y: 0.46),
        Waypoint(time: 7.40, x: 0.70, y: 0.62),
        Waypoint(time: 8.00, x: 0.42, y: 0.70),
        Waypoint(time: 8.55, x: 0.20, y: 0.52),
        Waypoint(time: 9.05, x: 0.28, y: 0.28),
        Waypoint(time: 9.50, x: 0.48, y: 0.14),
        Waypoint(time: 10.00, x: 0.72, y: 0.20),
        Waypoint(time: 10.50, x: 0.80, y: 0.38),
        Waypoint(time: 10.95, x: 0.64, y: 0.50),
        // Into the 5, then a wide right curve to the 2× — no kink.
        Waypoint(time: 11.35, x: 0.52, y: 0.58),
        Waypoint(time: 11.80, x: 0.54, y: 0.66),
        Waypoint(time: 12.25, x: 0.64, y: 0.74),
        Waypoint(time: 12.70, x: 0.76, y: 0.80),
        Waypoint(time: 13.10, x: 0.84, y: 0.80),
        Waypoint(time: 13.50, x: 0.72, y: 0.68),
        Waypoint(time: 13.90, x: 0.50, y: 0.50),
        Waypoint(time: 14.25, x: 0.28, y: 0.40),
        Waypoint(time: 14.75, x: 0.20, y: 0.30),
        Waypoint(time: 15.35, x: 0.40, y: 0.16),
        Waypoint(time: 16.00, x: 0.70, y: 0.22),
        Waypoint(time: 16.60, x: 0.88, y: 0.42),
        Waypoint(time: 17.20, x: 0.78, y: 0.64),
        Waypoint(time: 17.75, x: 0.50, y: 0.80),
        Waypoint(time: 18.20, x: 0.26, y: 0.90),
        Waypoint(time: 18.50, x: 0.12, y: 0.92),
        Waypoint(time: 18.75, x: 0.10, y: 0.86)
    ]

    /// iPhone-only path: denser curves, grab 13 right after the weave, rounder
    /// character loops, and a smoother glide into 20. Not a copy of iPad.
    /// Lion climbs between 3 and 6; 6 sits farther right so they do not overlap.
    static let phoneSwimPath: [Waypoint] = [
        Waypoint(time: 0.00, x: 0.50, y: 0.22),
        Waypoint(time: 0.40, x: 0.66, y: 0.28),
        Waypoint(time: 0.80, x: 0.80, y: 0.38),
        Waypoint(time: 1.20, x: 0.86, y: 0.52),
        Waypoint(time: 1.60, x: 0.86, y: 0.66),
        Waypoint(time: 2.00, x: 0.82, y: 0.80),
        Waypoint(time: 2.35, x: 0.72, y: 0.92),
        // Stay low under 12, then pop 13 and keep climbing at the same speed.
        Waypoint(time: 2.62, x: 0.58, y: 0.96),
        Waypoint(time: 2.88, x: 0.46, y: 0.96),
        Waypoint(time: 3.10, x: 0.30, y: 0.95),
        Waypoint(time: 3.28, x: 0.14, y: 0.82),
        Waypoint(time: 3.48, x: 0.16, y: 0.66),
        Waypoint(time: 3.72, x: 0.28, y: 0.50),
        Waypoint(time: 4.00, x: 0.42, y: 0.36),
        Waypoint(time: 4.28, x: 0.56, y: 0.26),
        Waypoint(time: 4.56, x: 0.68, y: 0.18),
        Waypoint(time: 4.88, x: 0.80, y: 0.14),
        Waypoint(time: 5.20, x: 0.88, y: 0.16),
        // Character loops: extra points at the crests so they stay circular.
        Waypoint(time: 5.52, x: 0.90, y: 0.24),
        Waypoint(time: 5.88, x: 0.92, y: 0.32),
        Waypoint(time: 6.24, x: 0.90, y: 0.38),
        Waypoint(time: 6.60, x: 0.86, y: 0.52),
        Waypoint(time: 6.96, x: 0.78, y: 0.68),
        Waypoint(time: 7.32, x: 0.64, y: 0.80),
        Waypoint(time: 7.70, x: 0.50, y: 0.88),
        // Same climb as before, lane a bit right so it runs between 3 and 6.
        Waypoint(time: 8.08, x: 0.38, y: 0.88),
        Waypoint(time: 8.44, x: 0.26, y: 0.70),
        Waypoint(time: 8.80, x: 0.24, y: 0.42),
        Waypoint(time: 9.16, x: 0.32, y: 0.16),
        Waypoint(time: 9.52, x: 0.48, y: 0.12),
        // Last switch: wide right arc through where 4 used to sit, then into 5.
        Waypoint(time: 9.88, x: 0.66, y: 0.14),
        Waypoint(time: 10.22, x: 0.82, y: 0.22),
        Waypoint(time: 10.52, x: 0.92, y: 0.38),
        Waypoint(time: 10.82, x: 0.86, y: 0.52),
        Waypoint(time: 11.12, x: 0.70, y: 0.60),
        Waypoint(time: 11.40, x: 0.54, y: 0.64),
        Waypoint(time: 11.65, x: 0.50, y: 0.68),
        Waypoint(time: 11.95, x: 0.60, y: 0.72),
        Waypoint(time: 12.35, x: 0.74, y: 0.78),
        Waypoint(time: 12.75, x: 0.84, y: 0.80),
        Waypoint(time: 13.15, x: 0.86, y: 0.74),
        Waypoint(time: 13.50, x: 0.76, y: 0.64),
        Waypoint(time: 13.85, x: 0.58, y: 0.50),
        Waypoint(time: 14.20, x: 0.38, y: 0.40),
        Waypoint(time: 14.55, x: 0.24, y: 0.32),
        Waypoint(time: 14.95, x: 0.22, y: 0.22),
        Waypoint(time: 15.40, x: 0.36, y: 0.16),
        Waypoint(time: 15.90, x: 0.56, y: 0.18),
        Waypoint(time: 16.40, x: 0.74, y: 0.26),
        Waypoint(time: 16.90, x: 0.86, y: 0.40),
        Waypoint(time: 17.35, x: 0.84, y: 0.56),
        Waypoint(time: 17.75, x: 0.68, y: 0.72),
        Waypoint(time: 18.10, x: 0.48, y: 0.84),
        // Glide through 20 — no V into the bottom-left corner.
        Waypoint(time: 18.40, x: 0.28, y: 0.90),
        Waypoint(time: 18.62, x: 0.16, y: 0.88),
        Waypoint(time: 18.85, x: 0.10, y: 0.80)
    ]

    static let openingFishUnit = (x: CGFloat(0.50), y: CGFloat(0.22))
    static let openingFishHeading: Double = .pi * 0.28

    static let zoomUnlockStart: TimeInterval = 5.2
    static let zoomUnlockEnd: TimeInterval = 10.9
    static let unlockZoom: CGFloat = 1.0

    static let spawnBonusFishAt: TimeInterval = 11.70
    static let seedStreakAt: TimeInterval = 10.55
    static let spawnLifeFishAt: TimeInterval = 13.55
    static let installFinalRoundAt: TimeInterval = 11.72
    static let forceCompletionAfterFinal: TimeInterval = 0.12
    /// Fallback only — icon normally waits for the swim-out callback.
    static let showIconAt: TimeInterval = 27.00
    static let iconHold: TimeInterval = 2.15
    static let endAt: TimeInterval = 29.00

    /// Smooth unit-space point on `swimPath` (Catmull-Rom through waypoints).
    static func pathPoint(at time: TimeInterval) -> (x: CGFloat, y: CGFloat) {
        let path = swimPath
        guard let first = path.first else { return (0.5, 0.5) }
        if time <= first.time { return (first.x, first.y) }
        if let last = path.last, time >= last.time { return (last.x, last.y) }

        for index in 0..<(path.count - 1) {
            let a = path[index]
            let b = path[index + 1]
            guard time >= a.time && time <= b.time else { continue }
            let span = max(0.0001, b.time - a.time)
            let t = CGFloat((time - a.time) / span)
            let p0 = path[max(0, index - 1)]
            let p1 = a
            let p2 = b
            let p3 = path[min(path.count - 1, index + 2)]
            return catmull(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
        }
        return (first.x, first.y)
    }

    private static func catmull(p0: Waypoint, p1: Waypoint, p2: Waypoint, p3: Waypoint,
                               t: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let t2 = t * t
        let t3 = t2 * t
        func sample(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2
                   + (-a + 3 * b - 3 * c + d) * t3)
        }
        return (sample(p0.x, p1.x, p2.x, p3.x), sample(p0.y, p1.y, p2.y, p3.y))
    }
}
