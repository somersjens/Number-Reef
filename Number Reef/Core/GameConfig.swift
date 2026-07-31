//
//  GameConfig.swift
//  Elephant Challenge: Math Memory
//
//  The single source of truth for every tunable gameplay number. Nothing in the
//  game may hardcode a life count, a probability, a duration or an unlock
//  requirement — it is declared here and read from here.
//

import Foundation

// MARK: - Card count (difficulty)

/// How many answer cards are laid out per round. Fewer cards means fewer
/// possible answers, so this doubles as the difficulty setting. The first case
/// is the default everywhere: fewest cards, easiest game.
public enum CardCount: Int, CaseIterable, Identifiable, Codable, Sendable {
    case two = 2
    case three = 3
    case four = 4

    public var id: Int { rawValue }

    /// Number of answer cards shown.
    public var answerCards: Int { rawValue }

    /// Number of distractors needed (all cards but the correct one).
    public var distractorCount: Int { rawValue - 1 }

    /// Localization key for the difficulty label ("Easy" / "Medium" / "Hard").
    public var difficultyKey: String {
        switch self {
        case .two: return "difficulty.easy"
        case .three: return "difficulty.medium"
        case .four: return "difficulty.hard"
        }
    }

    /// Localization key for the one-line explanation under the label.
    public var difficultyDetailKey: String {
        switch self {
        case .two: return "difficulty.easy.detail"
        case .three: return "difficulty.medium.detail"
        case .four: return "difficulty.hard.detail"
        }
    }

    /// SF Symbol shown next to the option.
    public var symbolName: String {
        switch self {
        case .two: return "leaf.fill"
        case .three: return "shuffle"
        case .four: return "bolt.fill"
        }
    }

    public static func from(rawValue: Int) -> CardCount {
        CardCount(rawValue: rawValue) ?? allCases[0]
    }
}

// MARK: - Central configuration

public enum GameConfig {

    // MARK: Lives

    /// Lives a session starts with. Lives are tracked internally in half units
    /// so the flamethrower can cost exactly half a life.
    public static let startingLives = 3.0
    /// A wrong answer costs one whole life.
    public static let wrongAnswerCost = 1.0
    /// Using the flamethrower costs half a life.
    public static let flamethrowerCost = 0.5

    /// Internal granularity: everything is stored as an integer number of
    /// halves, so no floating point rounding can ever strand the player on
    /// 0.4999 lives.
    public static let lifeGranularity = 2
    public static var startingLifeHalves: Int { Int(startingLives * Double(lifeGranularity)) }
    public static var wrongAnswerCostHalves: Int { Int(wrongAnswerCost * Double(lifeGranularity)) }
    public static var flamethrowerCostHalves: Int { Int(flamethrowerCost * Double(lifeGranularity)) }

    // MARK: Session

    /// The session ends after this many rounds even if lives remain.
    public static let maximumRounds = 20

    // MARK: Special double card

    /// Chance that an eligible round carries the thick double card.
    public static let doubleCardProbability = 0.20
    /// A double card is never offered before this many rounds have been played,
    /// so the very first round always teaches the plain flow.
    public static let doubleCardEarliestRound = 2
    /// Hard ceiling on consecutive double cards, so a lucky streak cannot turn
    /// the whole session into double rounds.
    public static let doubleCardMaxConsecutive = 2
    /// After this many plain rounds in a row the next eligible round is forced
    /// to be a double card, so a player is never starved of them.
    public static let doubleCardPityThreshold = 8
    /// Cards awarded for a correct answer on a double card.
    public static let doubleCardReward = 2
    /// Cards awarded for a correct answer on a normal card.
    public static let normalCardReward = 1

    // MARK: Timing (seconds)
    //
    // The brief is explicit: the next round must be able to start within
    // roughly 300–600 ms. These are the only durations gameplay may use.

    /// Card flip animation.
    public static let cardFlipDuration = 0.28
    /// Answer cards fading/scaling in once the question is visible.
    public static let answerRevealDuration = 0.18
    /// How long correct/wrong feedback stays on screen before the next round.
    public static let correctFeedbackDuration = 0.32
    public static let wrongFeedbackDuration = 0.55
    /// Fire sweep across the wrong cards.
    public static let flamethrowerDuration = 0.42
    /// Gap between feedback ending and the next round's closed cards appearing.
    public static let roundTransitionDuration = 0.12

    /// Total time from answering to the next round being interactive.
    public static var nextRoundDelay: (correct: Double, wrong: Double) {
        (correctFeedbackDuration + roundTransitionDuration,
         wrongFeedbackDuration + roundTransitionDuration)
    }

    // MARK: Levels

    /// Levels available without Premium.
    public static let freeLevelCount = 12
    /// Highest level Premium unlocks.
    public static let maximumLevel = 99

    /// How strongly question selection leans toward the highest available
    /// sub-level. Weight of sub-level i (1-based) is `i ^ levelWeightExponent`,
    /// so lower levels stay in the mix but the top of the range dominates.
    public static let levelWeightExponent = 1.0
    /// The selected level itself is guaranteed at least this share of rounds,
    /// so "the highest available difficulty appears regularly" is not left to
    /// chance on a level-40 run.
    public static let topLevelMinimumShare = 0.35

    // MARK: Characters

    /// Total earned cards required to unlock each character, in catalog order.
    /// Index 0 is the starter character and is therefore always 0.
    ///
    /// The second half of the catalog is Premium-exclusive: `nil` means the
    /// character cannot be earned with cards at all, no matter the total.
    public static let characterUnlockRequirements: [Int?] = [
        0,          // fox — from the start
        500,        // frog
        1_500,      // penguin
        3_000,      // bunny
        5_000,      // dog
        nil, nil, nil, nil, nil   // lion, octopus, crab, elephant, bear — Premium
    ]

    // MARK: Level progress

    /// Every answer-card count is its own scoreboard, with its own target: ten
    /// cards per answer card on the table, so two cards aim at 20, three at 30
    /// and four at 40. A harder table is worth more, and the three scores never
    /// mix with one another.
    public static let levelMaximumPerAnswerCard = 10

    public static func levelMaximum(answerCards: Int) -> Int {
        levelMaximumPerAnswerCard * max(1, answerCards)
    }

    public static func levelMaximum(cardCount: CardCount) -> Int {
        levelMaximum(answerCards: cardCount.answerCards)
    }

    /// Supermix is the broadest exercise in the game and runs on its own scale:
    /// every combination reaches for the same 50, whatever the card count.
    public static let mixedLevelMaximum = 50

    /// Ceiling on the "reached the maximum ×N" tally, so a long-lived save
    /// cannot grow the badge without bound.
    public static let maximumCompletionCount = 100

    /// The three progress dots fill at these shares of `levelCompletionCards`,
    /// so the card art follows the economy instead of hardcoded scores.
    public static let levelTierShares = [0.01, 0.4, 0.75]

    // MARK: Storage

    /// Bumped whenever the persisted shape changes; drives migration.
    public static let storageVersion = 3
}
