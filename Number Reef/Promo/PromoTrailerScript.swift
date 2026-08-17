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
                  wrongs: ["16", "18", "24", "25"])
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
        return [wrongs[0], wrongs[1], correct, wrongs[2]]
    }

    // 11 left-center, 12 center, 13 far left (early enough to meet the climb),
    // 14 right after the under-pass.
    static let openingVentFractions: [CGFloat] = [0.22, 0.50, 0.08, 0.92]
    static let openingGaps: [Double] = [0.10, 0.50, 1.20, 2.20]

    static func midShowcaseQueue(from round: GameRound) -> [AnswerOption] {
        let wrongs = round.options.filter { !$0.isCorrect }
        guard let correct = round.options.first(where: \.isCorrect) else {
            return Array(wrongs.prefix(3))
        }
        // Three wrongs during unlock; 5 early enough to collect before the 2×.
        return Array(wrongs.prefix(3)) + [correct]
    }

    static let midShowcaseVentFractions: [CGFloat] = [0.00, 1.00, 0.28, 0.50]
    static let midShowcaseGaps: [Double] = [0.18, 0.70, 0.70, 2.55]

    static func finalQueue(from round: GameRound) -> [AnswerOption] {
        let wrongs = round.options.filter { !$0.isCorrect }
        guard let correct = round.options.first(where: \.isCorrect) else {
            return round.options
        }
        // 16/18 right after the 5; 20 last on the far left so it is still low.
        return [wrongs[0], wrongs[1], correct]
    }

    /// 16 left-center, 18 center — right corridor stays free for the 2×.
    static let finalVentFractions: [CGFloat] = [0.28, 0.52, 0.08]
    static let finalGaps: [Double] = [0.20, 0.62, 4.70]

    // MARK: Timeline

    struct Caption {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    static let captions: [Caption] = [
        Caption(text: "Avoid the wrong bubbles", start: 0.10, end: 4.8),
        Caption(text: "Unlock new characters", start: 5.2, end: 11.0),
        Caption(text: "Catch helper fish in time", start: 11.3, end: 16.4),
        Caption(text: "And learn math", start: 16.7, end: 20.8)
    ]

    /// Character showcase. Lion is held longer so the yellow theme can settle
    /// before returning to octopus.
    static let characterBeats: [(time: TimeInterval, id: String)] = [
        (5.2, "octopus"),
        (6.3, "crab"),
        (7.5, "bear"),
        (8.8, "lion"),
        (10.8, "octopus")
    ]

    struct Waypoint {
        let time: TimeInterval
        let x: CGFloat
        let y: CGFloat
    }

    /// One continuous swim. Opening dives the empty right lane (14 is held back
    /// until the fish is already under), then left and up into 13.
    static let swimPath: [Waypoint] = [
        Waypoint(time: 0.00, x: 0.50, y: 0.22),
        Waypoint(time: 0.50, x: 0.70, y: 0.30),
        Waypoint(time: 1.00, x: 0.84, y: 0.48),
        Waypoint(time: 1.50, x: 0.86, y: 0.70),
        Waypoint(time: 2.10, x: 0.76, y: 0.90),
        Waypoint(time: 2.70, x: 0.52, y: 0.92),
        Waypoint(time: 3.20, x: 0.36, y: 0.90),
        // Under 12, then a long left glide into 13 as it rises from the vent.
        Waypoint(time: 3.70, x: 0.20, y: 0.88),
        Waypoint(time: 4.20, x: 0.12, y: 0.80),
        Waypoint(time: 4.70, x: 0.10, y: 0.70),
        Waypoint(time: 5.20, x: 0.10, y: 0.60),
        Waypoint(time: 5.55, x: 0.10, y: 0.54),
        // Soft exit after the pop.
        Waypoint(time: 5.70, x: 0.28, y: 0.48),
        Waypoint(time: 6.10, x: 0.48, y: 0.34),
        // Wide unlock loops — weave the rising mid-round wrongs.
        Waypoint(time: 6.20, x: 0.62, y: 0.26),
        Waypoint(time: 6.80, x: 0.84, y: 0.38),
        Waypoint(time: 7.40, x: 0.72, y: 0.62),
        Waypoint(time: 8.00, x: 0.38, y: 0.70),
        Waypoint(time: 8.60, x: 0.18, y: 0.46),
        Waypoint(time: 9.20, x: 0.36, y: 0.22),
        Waypoint(time: 9.80, x: 0.70, y: 0.24),
        Waypoint(time: 10.40, x: 0.78, y: 0.38),
        Waypoint(time: 10.90, x: 0.62, y: 0.50),
        // Glide into the risen 5, then keep moving — no pause.
        Waypoint(time: 11.30, x: 0.52, y: 0.58),
        Waypoint(time: 11.65, x: 0.50, y: 0.62),
        // Fluid line from the 5 into the 2× coin (from the right).
        Waypoint(time: 12.10, x: 0.58, y: 0.70),
        Waypoint(time: 12.55, x: 0.70, y: 0.78),
        Waypoint(time: 13.05, x: 0.82, y: 0.80),
        Waypoint(time: 13.40, x: 0.68, y: 0.62),
        // Life fish earlier — glide past it, then a wide arc to 20.
        Waypoint(time: 13.80, x: 0.46, y: 0.48),
        Waypoint(time: 14.25, x: 0.28, y: 0.40),
        Waypoint(time: 14.75, x: 0.20, y: 0.30),
        Waypoint(time: 15.35, x: 0.40, y: 0.16),
        Waypoint(time: 16.00, x: 0.70, y: 0.22),
        Waypoint(time: 16.60, x: 0.88, y: 0.42),
        Waypoint(time: 17.20, x: 0.78, y: 0.64),
        Waypoint(time: 17.75, x: 0.50, y: 0.80),
        Waypoint(time: 18.30, x: 0.26, y: 0.84),
        Waypoint(time: 18.80, x: 0.12, y: 0.82),
        Waypoint(time: 19.30, x: 0.12, y: 0.76)
    ]

    static let steerLookAhead: TimeInterval = 0.40
    static let openingFishUnit = (x: CGFloat(0.50), y: CGFloat(0.22))
    static let openingFishHeading: Double = .pi * 0.28

    static let zoomUnlockStart: TimeInterval = 5.2
    static let zoomUnlockEnd: TimeInterval = 10.9
    static let unlockZoom: CGFloat = 1.0

    static let spawnBonusFishAt: TimeInterval = 11.70
    static let seedStreakAt: TimeInterval = 10.55
    static let spawnLifeFishAt: TimeInterval = 13.55
    static let installFinalRoundAt: TimeInterval = 11.72
    static let forceCompletionAfterFinal: TimeInterval = 0.45
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
