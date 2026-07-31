//
//  RoundFactory.swift
//  Elephant Challenge: Math Memory
//
//  Builds one complete round: the question, the answer cards in their final
//  shuffled positions, and whether this round carries the special double card.
//
//  Answer positions are decided here, once, before the cards become visible —
//  the UI never re-orders them afterwards.
//

import Foundation

// MARK: - Answer card

public struct AnswerOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let isCorrect: Bool

    public init(id: UUID = UUID(), text: String, isCorrect: Bool) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
    }
}

// MARK: - Round

public struct GameRound: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 1-based position in the session.
    public let number: Int
    public let question: MathQuestion
    /// Exactly one option has `isCorrect == true`.
    public let options: [AnswerOption]
    /// The thick special card: a harder sum worth double.
    public let isDoubleCard: Bool

    public init(id: UUID = UUID(),
                number: Int,
                question: MathQuestion,
                options: [AnswerOption],
                isDoubleCard: Bool) {
        self.id = id
        self.number = number
        self.question = question
        self.options = options
        self.isDoubleCard = isDoubleCard
    }

    /// Cards awarded when this round is answered correctly.
    public var reward: Int {
        isDoubleCard ? GameConfig.doubleCardReward : GameConfig.normalCardReward
    }

    public var correctOption: AnswerOption? {
        options.first { $0.isCorrect }
    }
}

// MARK: - Double-card balancing

/// Decides whether a round carries the special double card. A flat 20% coin
/// flip would happily produce five in a row or a forty-round drought, so this
/// keeps the long-run rate at ~20% while bounding both extremes.
public final class DoubleCardScheduler {
    private let random: RandomSource
    private var consecutive = 0
    private var sincePrevious = 0

    public init(random: RandomSource = RandomSource()) {
        self.random = random
    }

    public func reset() {
        consecutive = 0
        sincePrevious = 0
    }

    /// - Parameter roundNumber: 1-based round index in the session.
    public func shouldOfferDoubleCard(roundNumber: Int) -> Bool {
        guard roundNumber >= GameConfig.doubleCardEarliestRound else {
            register(false)
            return false
        }
        // Hard ceiling: never more than N double cards back to back.
        if consecutive >= GameConfig.doubleCardMaxConsecutive {
            register(false)
            return false
        }
        // Pity rule: after a long dry spell the next eligible round is a double.
        if sincePrevious >= GameConfig.doubleCardPityThreshold {
            register(true)
            return true
        }
        let hit = random.double(in: 0..<1) < GameConfig.doubleCardProbability
        register(hit)
        return hit
    }

    private func register(_ hit: Bool) {
        if hit {
            consecutive += 1
            sincePrevious = 0
        } else {
            consecutive = 0
            sincePrevious += 1
        }
    }
}

// MARK: - Factory

public final class RoundFactory {
    private let generator: QuestionGenerator
    private let scheduler: DoubleCardScheduler
    private let random: RandomSource
    private let cardCount: CardCount

    public init(level: MathLevel,
                cardCount: CardCount,
                mixedVariant: MixedVariant = .all,
                seed: UInt64? = nil) {
        let random = RandomSource(seed: seed)
        self.random = random
        self.cardCount = cardCount
        self.generator = QuestionGenerator(level: level,
                                           mixedVariant: mixedVariant,
                                           random: random)
        self.scheduler = DoubleCardScheduler(random: random)
    }

    public func reset() {
        generator.reset()
        scheduler.reset()
    }

    /// Builds the round for a given 1-based round number.
    public func makeRound(number: Int) -> GameRound {
        let isDouble = scheduler.shouldOfferDoubleCard(roundNumber: number)
        let question = isDouble
            ? generator.nextHarder(requiredDistractors: cardCount.distractorCount)
            : generator.next(requiredDistractors: cardCount.distractorCount)
        return GameRound(number: number,
                         question: question,
                         options: makeOptions(for: question),
                         isDoubleCard: isDouble)
    }

    /// One correct card plus the required number of unique wrong cards, laid
    /// out in ascending order. Ordered cards are far easier to hold in mind
    /// than scattered ones, which is the point of the memorising beat.
    ///
    /// The correct answer's position still varies from round to round, because
    /// where it lands depends on how the distractors compare to it — but it
    /// never moves once the round is built.
    private func makeOptions(for question: MathQuestion) -> [AnswerOption] {
        var options = [AnswerOption(text: question.correctAnswer, isCorrect: true)]
        var used: Set<AnswerValue> = [AnswerValue(question.correctAnswer)]
        for candidate in question.distractors {
            guard options.count <= cardCount.distractorCount else { break }
            let value = AnswerValue(candidate)
            guard !used.contains(value) else { continue }
            used.insert(value)
            options.append(AnswerOption(text: candidate, isCorrect: false))
        }
        return options.sorted { AnswerValue($0.text) < AnswerValue($1.text) }
    }
}
