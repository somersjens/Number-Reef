//
//  MathTopic.swift
//  Elephant Challenge: Math Memory
//
//  The topic catalog and the difficulty curve behind it. Both the level cards
//  the player sees and the sums the generator produces read from here, so the
//  number on a card and the maths behind it can never drift apart.
//
//  Ported from Jumping Fox's ChallengeScaling/LevelCatalog, reduced to the one
//  practice form Math Memory needs.
//

import Foundation

// MARK: - Topics

public enum MathTopic: String, CaseIterable, Identifiable, Codable, Sendable {
    case addition
    case subtraction
    case tables
    case fractions
    case percentages
    case mixed

    public var id: String { rawValue }

    /// Localization key for the topic name.
    public var titleKey: String { "topic.\(rawValue)" }
    /// Localization key for the one-line "what this practises" summary.
    public var detailKey: String { "topic.\(rawValue).detail" }

    /// SF Symbol for the topic selector.
    public var symbolName: String {
        switch self {
        case .addition: return "plus"
        case .subtraction: return "minus"
        case .tables: return "multiply"
        case .fractions: return "divide"
        case .percentages: return "percent"
        case .mixed: return "star.fill"
        }
    }

    /// Small secondary glyph shown on a level card.
    public var operatorSymbol: String {
        switch self {
        case .addition: return "+"
        case .subtraction: return "−"
        case .tables: return "×"
        case .fractions: return "½"
        case .percentages: return "%"
        case .mixed: return "+ − × %"
        }
    }
}

// MARK: - Difficulty scaling

/// The Supermix sub-choices: how many operations the mix draws from. Each one
/// adds the next operation to the one before it, so the ladder is strictly
/// widening rather than four unrelated sets.
public enum MixedVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case basic      // + −
    case times      // + − ×
    case fraction   // + − × ÷
    case all        // + − × ÷ %

    public var id: String { rawValue }

    /// The operator glyphs this variant practises, in their fixed order.
    public var operators: [String] {
        Array(["+", "−", "×", "÷", "%"].prefix(operationCount))
    }

    public var operationCount: Int {
        switch self {
        case .basic:    return 2
        case .times:    return 3
        case .fraction: return 4
        case .all:      return 5
        }
    }

    /// The topics a round of this variant can draw from.
    public var topics: [MathTopic] {
        let ladder: [MathTopic] = [.addition, .subtraction, .tables, .fractions, .percentages]
        return Array(ladder.prefix(operationCount))
    }

    /// Localization key for the one-line explanation.
    public var detailKey: String { "info.super.\(rawValue)" }
}

public enum MathScaling {
    /// Fraction denominators for all 99 levels, in the intended learning order.
    public static let fractionDenominators = [
        2, 4, 8, 3, 6, 12, 5, 10, 20, 7, 14, 28, 16, 32, 64, 128, 256, 512,
        24, 48, 96, 192, 384, 768, 40, 80, 160, 320, 640, 56, 112, 224, 448, 896,
        9, 18, 36, 72, 144, 288, 576, 11, 22, 44, 88, 176, 352, 704, 13, 26, 52,
        104, 208, 416, 832, 15, 30, 60, 120, 240, 480, 960, 17, 34, 68, 136, 272,
        544, 19, 38, 76, 152, 304, 608, 21, 42, 84, 168, 336, 672, 23, 46, 92,
        184, 368, 736, 25, 50, 100, 200, 400, 800, 27, 54, 108, 216, 432, 864, 1000]

    /// Percentages for all 99 levels, in the intended learning order.
    public static let percentageLevels = [
        25, 50, 75, 5, 10, 15, 20, 40, 80, 30, 60, 90, 35, 45, 55, 65, 70, 85, 95,
        2, 4, 6, 8, 12, 14, 16, 18, 22, 24, 26, 28, 32, 34, 36, 38, 42, 44, 46, 48,
        52, 54, 56, 58, 62, 64, 66, 68, 72, 74, 76, 78, 82, 84, 86, 88, 92, 94, 96,
        98, 1, 3, 7, 9, 11, 13, 17, 19, 21, 23, 27, 29, 31, 33, 37, 39, 41, 43, 47,
        49, 51, 53, 57, 59, 61, 63, 67, 69, 71, 73, 77, 79, 81, 83, 87, 89, 91, 93,
        97, 99]

    /// The denominator practised at a given level.
    public static func fractionDenominator(_ level: Int) -> Int {
        fractionDenominators[clampIndex(level, count: fractionDenominators.count)]
    }

    /// The percentage practised at a given level.
    public static func percentage(_ level: Int) -> Int {
        percentageLevels[clampIndex(level, count: percentageLevels.count)]
    }

    private static func clampIndex(_ level: Int, count: Int) -> Int {
        min(max(0, level - 1), count - 1)
    }

    /// Highest number added at a given addition level. The other operand grows
    /// with it, so level 3 gives sums like 14 + 3 but never 14 + 9.
    public static func additionCeiling(_ level: Int) -> Int {
        max(10, level * 5 + 3)
    }

    /// Highest starting number at a given subtraction level.
    public static func subtractionCeiling(_ level: Int) -> Int {
        max(10, level * 6 + 3)
    }

    /// The tables available at a given level: this level's table and every
    /// table below it (capped at 99).
    public static func tablePool(_ level: Int) -> [Int] {
        Array(1...min(GameConfig.maximumLevel, max(1, level)))
    }

    /// The big round "whole" a high-level fraction/percentage question works
    /// with. Climbs in tens from 110 (level 13) toward ~970 (level 99).
    public static func premiumCeiling(_ level: Int) -> Int {
        100 + max(1, level - 12) * 10
    }

    /// The friendly denominators reviewed by high-level fraction questions.
    public static let premiumFractionDenominators = [2, 4, 5, 8, 10, 20, 25]
    /// The friendly percentages reviewed by high-level percentage questions.
    public static let premiumPercentages = [50, 25, 10, 20, 75, 5]
}

// MARK: - Level

/// One selectable level within a topic.
public struct MathLevel: Identifiable, Hashable, Codable, Sendable {
    public let topic: MathTopic
    /// 1-based level number.
    public let index: Int

    public var id: String { "\(topic.rawValue).\(index)" }

    /// Levels beyond the free tier need Premium.
    public var requiresPremium: Bool { index > GameConfig.freeLevelCount }

    /// The big central number on the level card. Meaningful per topic: the
    /// number added/taken away, the table, the denominator, the percentage.
    public var cardNumber: String {
        switch topic {
        case .addition, .subtraction, .tables, .mixed:
            return "\(index)"
        case .fractions:
            return "\(MathScaling.fractionDenominator(index))"
        case .percentages:
            return "\(MathScaling.percentage(index))"
        }
    }

    public init(topic: MathTopic, index: Int) {
        self.topic = topic
        self.index = max(1, min(GameConfig.maximumLevel, index))
    }
}

public enum LevelCatalog {
    /// Every level of a topic, free tier first.
    public static func levels(for topic: MathTopic) -> [MathLevel] {
        (1...GameConfig.maximumLevel).map { MathLevel(topic: topic, index: $0) }
    }

    public static func level(id: String) -> MathLevel? {
        let parts = id.split(separator: ".")
        guard parts.count == 2,
              let topic = MathTopic(rawValue: String(parts[0])),
              let index = Int(parts[1]),
              (1...GameConfig.maximumLevel).contains(index) else { return nil }
        return MathLevel(topic: topic, index: index)
    }
}
