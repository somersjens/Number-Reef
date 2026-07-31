//
//  MemoryGame.swift
//  Elephant Challenge: Math Memory
//
//  The session state machine. Every rule that decides what a tap does lives
//  here, and every transition is guarded by the current state — that is what
//  makes double taps, double scoring and double life loss impossible.
//
//  This type is deliberately free of SwiftUI and of timers: the view drives it
//  with explicit calls and asks it what to show. That keeps it fully testable.
//

import Foundation

// MARK: - State

public enum GameState: String, Equatable, Sendable {
    /// Session created, nothing shown yet.
    case intro
    /// The answer cards lie face up: this is the memorising beat. The question
    /// is still hidden, and a tap turns the cards over.
    case memorising
    /// The cards are mid-flip: they are turning face down while the question
    /// comes up. No input is accepted during the turn.
    case questionVisible
    /// The cards are face down and the question is readable. Exactly one tap
    /// is accepted — the player must remember where the answer was.
    case answering
    /// An answer was taken: feedback is showing, input is locked.
    case resolving
    /// Feedback finished; the next round can be installed.
    case roundComplete
    /// Out of lives, or the round limit was reached.
    case gameOver
}

public enum GameOverReason: String, Equatable, Sendable {
    case outOfLives
    case roundsCompleted
    case quit
}

/// What resolving a tap produced, so the view knows which feedback to play.
public enum AnswerOutcome: Equatable, Sendable {
    case correct(cardsEarned: Int, wasDoubleCard: Bool)
    case wrong(correctOptionID: UUID)
    /// The tap was ignored (wrong state, or the round was already answered).
    case ignored
}

// MARK: - Result

public struct SessionResult: Equatable, Sendable {
    public var correctAnswers = 0
    public var wrongAnswers = 0
    public var cardsEarned = 0
    /// Cards that came from double cards over and above the normal reward.
    public var bonusCards = 0
    public var doubleCardsAnswered = 0
    public var flamethrowersUsed = 0
    public var isNewPersonalBest = false
    public var previousPersonalBest = 0
    public var unlockedCharacterIDs: [String] = []
    public var reason: GameOverReason = .roundsCompleted

    public init() {}
}

// MARK: - Engine

public final class MemoryGame {
    // MARK: Configuration

    public let level: MathLevel
    public let cardCount: CardCount
    /// Which scoreboard this session plays on, so a paused run can only ever be
    /// resumed onto the exact board it came from.
    public let board: LevelBoard
    private let factory: RoundFactory

    // MARK: Observable state (read by the view)

    public private(set) var state: GameState = .intro
    public private(set) var round: GameRound?
    /// The round after this one, built ahead of time so a transition never
    /// waits on generation.
    private var preparedRound: GameRound?

    public private(set) var roundNumber = 0
    public private(set) var cards = 0
    /// Lives in half units. 6 == three lives.
    public private(set) var lifeHalves = GameConfig.startingLifeHalves
    /// Options burned away by the flamethrower this round.
    public private(set) var burnedOptionIDs: Set<UUID> = []
    /// The option the player tapped this round, if any.
    public private(set) var selectedOptionID: UUID?
    public private(set) var lastOutcome: AnswerOutcome?
    public private(set) var result = SessionResult()
    public private(set) var isFlamethrowerUsedThisRound = false

    /// Set once the session is over; nil while playing.
    public private(set) var gameOverReason: GameOverReason?

    // MARK: Derived

    public var livesRemaining: Double {
        Double(lifeHalves) / Double(GameConfig.lifeGranularity)
    }

    public var maximumRounds: Int { GameConfig.maximumRounds }

    /// Whether a tap on an answer card can be accepted right now.
    public var acceptsInput: Bool { state == .answering }

    /// Whether the answer values are readable. They are during the memorising
    /// beat, and again while the round resolves so the player can see what they
    /// picked and where the right card was.
    public var showsAnswerValues: Bool {
        state == .memorising || state == .resolving || state == .roundComplete
    }

    /// Whether the question is readable. It appears only once the cards are
    /// face down, which is what makes this a memory game.
    public var showsQuestion: Bool {
        state != .intro && state != .memorising
    }

    /// The flamethrower needs at least half a life left, may be used once per
    /// round, and only while the answer cards are live. There must also be
    /// something to burn — it does nothing on a single remaining card.
    public var canUseFlamethrower: Bool {
        state == .answering
            && !isFlamethrowerUsedThisRound
            && lifeHalves >= GameConfig.flamethrowerCostHalves
            && (round?.options.count ?? 0) > 1
    }

    // MARK: Init

    public init(level: MathLevel,
                cardCount: CardCount,
                mixedVariant: MixedVariant = .all,
                seed: UInt64? = nil) {
        self.level = level
        self.cardCount = cardCount
        self.board = LevelBoard(level: level, cardCount: cardCount, mixedVariant: mixedVariant)
        self.factory = RoundFactory(level: level,
                                    cardCount: cardCount,
                                    mixedVariant: mixedVariant,
                                    seed: seed)
    }

    // MARK: - Session lifecycle

    /// Starts the session and deals the first round's answer cards face up.
    @discardableResult
    public func start() -> Bool {
        guard state == .intro else { return false }
        roundNumber = 1
        round = factory.makeRound(number: 1)
        preparedRound = factory.makeRound(number: 2)
        state = .memorising
        return true
    }

    /// Resumes a level the player left part-way through, restoring the cards,
    /// lives and round they stopped on. Rejected if the record is not playable.
    @discardableResult
    public func resume(from session: PausedSession) -> Bool {
        guard state == .intro, session.isResumable else { return false }
        roundNumber = session.roundNumber
        cards = session.cards
        lifeHalves = session.lifeHalves
        result.correctAnswers = session.correctAnswers
        result.wrongAnswers = session.wrongAnswers
        result.doubleCardsAnswered = session.doubleCardsAnswered
        result.bonusCards = session.bonusCards
        result.flamethrowersUsed = session.flamethrowersUsed
        result.cardsEarned = session.cards
        round = factory.makeRound(number: roundNumber)
        preparedRound = factory.makeRound(number: roundNumber + 1)
        state = .memorising
        return true
    }

    /// A snapshot of the session as it stands, for storing when the player
    /// leaves. Nil once the session is over — there is nothing to come back to.
    public func pausedSession() -> PausedSession? {
        guard state != .intro, state != .gameOver else { return nil }
        return PausedSession(boardID: board.storageID,
                             cardCount: cardCount.rawValue,
                             roundNumber: roundNumber,
                             cards: cards,
                             lifeHalves: lifeHalves,
                             correctAnswers: result.correctAnswers,
                             wrongAnswers: result.wrongAnswers,
                             doubleCardsAnswered: result.doubleCardsAnswered,
                             bonusCards: result.bonusCards,
                             flamethrowersUsed: result.flamethrowersUsed)
    }

    /// The tap that turns the answer cards face down and brings the question
    /// up. From here on the player is working from memory.
    @discardableResult
    public func turnCardsOver() -> Bool {
        guard state == .memorising else { return false }
        state = .questionVisible
        return true
    }

    /// Called once the cards have finished turning. From here the round accepts
    /// exactly one answer.
    @discardableResult
    public func beginAnswering() -> Bool {
        guard state == .questionVisible else { return false }
        state = .answering
        return true
    }

    // MARK: - Answering

    /// Resolves a tap on an answer card. Any tap that arrives in the wrong
    /// state — a second tap on the same round, a tap during feedback, a tap on
    /// a burned card — is ignored without touching score or lives.
    @discardableResult
    public func select(optionID: UUID) -> AnswerOutcome {
        guard state == .answering,
              let round,
              selectedOptionID == nil,
              !burnedOptionIDs.contains(optionID),
              let option = round.options.first(where: { $0.id == optionID })
        else {
            // Deliberately leaves `lastOutcome` alone: an ignored tap must not
            // disturb the feedback the view is currently showing.
            return .ignored
        }

        // Lock input for the whole of the resolve phase, before any scoring.
        selectedOptionID = optionID
        state = .resolving

        let outcome: AnswerOutcome
        if option.isCorrect {
            let earned = round.reward
            cards += earned
            result.correctAnswers += 1
            result.cardsEarned += earned
            if round.isDoubleCard {
                result.doubleCardsAnswered += 1
                result.bonusCards += earned - GameConfig.normalCardReward
            }
            outcome = .correct(cardsEarned: earned, wasDoubleCard: round.isDoubleCard)
        } else {
            result.wrongAnswers += 1
            spendLifeHalves(GameConfig.wrongAnswerCostHalves)
            outcome = .wrong(correctOptionID: round.correctOption?.id ?? optionID)
        }
        lastOutcome = outcome
        return outcome
    }

    /// Burns every wrong card for half a life. Returns the burned card ids, or
    /// nil when the helper is not available — a rapid second tap therefore
    /// costs nothing and burns nothing.
    @discardableResult
    public func useFlamethrower() -> Set<UUID>? {
        guard canUseFlamethrower, let round else { return nil }
        // Mark it spent before deducting, so two taps in the same frame cannot
        // both pass the guard.
        isFlamethrowerUsedThisRound = true
        let burned = Set(round.options.filter { !$0.isCorrect }.map(\.id))
        burnedOptionIDs = burned
        result.flamethrowersUsed += 1
        spendLifeHalves(GameConfig.flamethrowerCostHalves)
        return burned
    }

    // MARK: - Round transitions

    /// Called by the view when the feedback animation has finished.
    @discardableResult
    public func finishResolving() -> Bool {
        guard state == .resolving else { return false }
        state = .roundComplete
        return true
    }

    /// Installs the next round, or ends the session. Returns the new state.
    @discardableResult
    public func advance() -> GameState {
        guard state == .roundComplete else { return state }

        if lifeHalves <= 0 {
            finish(reason: .outOfLives)
            return state
        }
        if roundNumber >= GameConfig.maximumRounds {
            finish(reason: .roundsCompleted)
            return state
        }

        roundNumber += 1
        round = preparedRound ?? factory.makeRound(number: roundNumber)
        // Build the round after next while the player is looking at this one.
        preparedRound = factory.makeRound(number: roundNumber + 1)
        selectedOptionID = nil
        burnedOptionIDs.removeAll()
        isFlamethrowerUsedThisRound = false
        lastOutcome = nil
        state = .memorising
        return state
    }

    /// Ends the session early (the player left the game screen).
    public func quit() {
        guard state != .gameOver else { return }
        finish(reason: .quit)
    }

    // MARK: - Private

    private func spendLifeHalves(_ halves: Int) {
        lifeHalves = max(0, lifeHalves - halves)
    }

    private func finish(reason: GameOverReason) {
        gameOverReason = reason
        result.reason = reason
        state = .gameOver
    }

    /// Fills in the persistence-derived parts of the result. Called by the view
    /// model once the score has been recorded, so the engine itself stays free
    /// of storage concerns.
    public func applyProgressOutcome(previousBest: Int,
                                     isNewPersonalBest: Bool,
                                     unlockedCharacterIDs: [String]) {
        result.previousPersonalBest = previousBest
        result.isNewPersonalBest = isNewPersonalBest
        result.unlockedCharacterIDs = unlockedCharacterIDs
    }
}
