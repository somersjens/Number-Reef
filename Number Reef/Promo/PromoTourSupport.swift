#if TRAILER_EXPORT
import Combine
import SwiftUI

// MARK: - Capture handshake

/// Writes the files the capture script waits on, and a timed event trace the
/// master uses to place menu taps. Production builds never compile this type.
@MainActor
final class AppStoreTourRecorder: ObservableObject {
    static let shared = AppStoreTourRecorder()

    private var startedAt: TimeInterval?
    private var events: [(String, TimeInterval)] = []

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppStoreTeaser", isDirectory: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func prepare() {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        try? Data("ready\n".utf8).write(to: url("playback-ready"), options: .atomic)
    }

    func waitForStart(_ action: @escaping @MainActor () -> Void) {
        if FileManager.default.fileExists(atPath: url("start").path) {
            start(action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForStart(action)
        }
    }

    private func start(_ action: @escaping @MainActor () -> Void) {
        guard startedAt == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        events.removeAll()
        event("start")
        action()
    }

    func event(_ name: String) {
        guard let startedAt else { return }
        let time = ProcessInfo.processInfo.systemUptime - startedAt
        events.append((name, time))
        persistEvents()
    }

    func finish(eventName: String) {
        event(eventName)
        persistEvents()
        try? Data("complete\n".utf8).write(to: url("playback-complete"), options: .atomic)
    }

    private func persistEvents() {
        let text = events.map { String(format: "%.3f\t%@", $0.1, $0.0) }
            .joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: url("events.tsv"), options: .atomic)
    }
}

// MARK: - In-memory menu progress

struct PromoBoardRecord {
    var best: Int
    var maxCompletions: Int
}

/// Deterministic scores for the menu tour. Nothing here is written to
/// UserDefaults, iCloud, or the player's real progress.
struct PromoMenuProgress {
    var boards: [String: PromoBoardRecord] = [:]
    var total: Int = 0

    func best(_ board: LevelBoard) -> Int { boards[board.storageID]?.best ?? 0 }

    func maxCompletions(_ board: LevelBoard) -> Int {
        boards[board.storageID]?.maxCompletions ?? 0
    }

    func topicTotal(_ topic: MathTopic) -> Int {
        LevelCatalog.levels(for: topic).reduce(0) { partial, level in
            partial + LevelBoard.all(for: level).reduce(0) { $0 + best($1) }
        }
    }

    /// The Premium tour starts before a player has earned anything.
    static func premiumTour() -> PromoMenuProgress { PromoMenuProgress() }

    /// A deliberately varied curve, weighted toward completed lower levels.
    /// Every topic and mode moves its maximum scores onto different cards, so
    /// switching the menu visibly changes which levels are finished. The values
    /// themselves stay fixed, which keeps the header on the same total.
    static func menuTour() -> PromoMenuProgress {
        func scaled(_ base: [Int], from reference: Int, to target: Int) -> [Int] {
            base.map { value in
                min(target, Int((Double(value) * Double(target) / Double(reference)).rounded()))
            }
        }
        // Same curve as Rabbit Hole, scaled onto this game's own board maxima
        // so crowned cards still read as finished.
        let baseScoresByMode: [PracticeMode: [Int]] = [
            .order: scaled([20, 20, 20, 20, 18, 16, 14, 12, 10, 8, 5, 2],
                           from: 20, to: GameConfig.orderLevelMaximum),
            .random: scaled([30, 30, 30, 27, 24, 21, 18, 15, 12, 9, 6, 3],
                            from: 30, to: GameConfig.randomLevelMaximum),
            .mixed: scaled([40, 40, 36, 32, 28, 24, 20, 16, 12, 8, 4, 0],
                           from: 40, to: GameConfig.mixedLevelMaximum),
        ]
        let maximumPairs = [
            [4, 9], [5, 10], [6, 11], [7, 8], [4, 10],
            [5, 11], [6, 8], [7, 9], [4, 11], [5, 8],
            [6, 9], [7, 10], [4, 8], [5, 9], [6, 10],
            [7, 11], [4, 7], [5, 6], [8, 11],
        ]

        func variedScores(_ base: [Int], seed: Int) -> [Int] {
            guard let maximum = base.max(), !base.isEmpty else { return base }
            let maximumCount = base.filter { $0 == maximum }.count
            var maximumSlots = maximumPairs[seed % maximumPairs.count]
            let higherSlots = Array(4..<min(12, base.count))
            for offset in 0..<higherSlots.count where maximumSlots.count < maximumCount {
                let candidate = higherSlots[(offset + seed) % higherSlots.count]
                if !maximumSlots.contains(candidate) { maximumSlots.append(candidate) }
            }

            let remaining = base.filter { $0 != maximum }
            let rotation = remaining.isEmpty ? 0 : seed % remaining.count
            let rotated = Array(remaining.dropFirst(rotation) + remaining.prefix(rotation))
            var result = Array(repeating: 0, count: base.count)
            var remainingIndex = 0
            for index in result.indices {
                if maximumSlots.prefix(maximumCount).contains(index) {
                    result[index] = maximum
                } else if remainingIndex < rotated.count {
                    result[index] = rotated[remainingIndex]
                    remainingIndex += 1
                }
            }
            return result
        }

        var progress = PromoMenuProgress()
        let regularTopics: [MathTopic] = [
            .addition, .subtraction, .tables, .fractions, .percentages,
        ]
        for (topicIndex, topic) in regularTopics.enumerated() {
            let levels = LevelCatalog.levels(for: topic).filter { !$0.requiresPremium }
            for (modeIndex, mode) in PracticeMode.allCases.enumerated() {
                let seed = topicIndex * PracticeMode.allCases.count + modeIndex
                let scores = variedScores(baseScoresByMode[mode] ?? [], seed: seed)
                for (offset, level) in levels.enumerated() {
                    let board = LevelBoard(level: level, mode: mode)
                    let score = offset < scores.count ? scores[offset] : 0
                    progress.boards[board.storageID] = PromoBoardRecord(
                        best: score,
                        maxCompletions: score >= board.maximum ? 1 + ((seed + offset) % 3) : 0
                    )
                }
            }
        }

        let superBaseScores = scaled([50, 50, 40, 35, 30, 25, 20, 15, 5, 5, 0, 0],
                                     from: 50, to: GameConfig.supermixLevelMaximum)
        for (variantIndex, variant) in MixedVariant.allCases.enumerated() {
            let levels = LevelCatalog.levels(for: .mixed).filter { !$0.requiresPremium }
            let seed = 15 + variantIndex
            let scores = variedScores(superBaseScores, seed: seed)
            for (offset, level) in levels.enumerated() {
                let board = LevelBoard(level: level, mixedVariant: variant)
                let score = offset < scores.count ? scores[offset] : 0
                progress.boards[board.storageID] = PromoBoardRecord(
                    best: score,
                    maxCompletions: score >= board.maximum ? 1 + ((seed + offset) % 3) : 0
                )
            }
        }
        progress.total = progress.boards.values.reduce(0) { $0 + $1.best }
        return progress
    }
}
#endif
