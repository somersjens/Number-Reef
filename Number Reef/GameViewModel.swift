//
//  GameViewModel.swift
//  Elephant Challenge: Math Memory
//
//  The bridge between the pure `MemoryGame` engine and SwiftUI. It owns the
//  timing of a round (flip → answers → feedback → next round), the audio and
//  haptics, and the persistence of a finished session.
//
//  It never re-implements a rule: every tap is forwarded to the engine, and the
//  engine's answer decides what happens. That is what keeps rapid tapping from
//  scoring twice or costing two lives.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class GameViewModel: ObservableObject {
    private let request: GameSessionRequest
    private var engine: MemoryGame

    // Published mirrors of the engine, so SwiftUI observes value changes.
    @Published private(set) var state: GameState = .intro
    @Published private(set) var round: GameRound?
    @Published private(set) var roundNumber = 0
    @Published private(set) var cards = 0
    @Published private(set) var livesRemaining = GameConfig.startingLives
    @Published private(set) var selectedOptionID: UUID?
    @Published private(set) var burnedOptionIDs: Set<UUID> = []
    @Published private(set) var canUseFlamethrower = false
    @Published private(set) var isGameOver = false
    @Published private(set) var result = SessionResult()
    /// Brief highlight while the fire animation plays.
    @Published private(set) var isFiring = false

    /// Invalidates pending timed work when a round is superseded (restart, or
    /// leaving the screen), so a late callback can never touch a newer round.
    private var generation = 0
    private var hasRecordedResult = false

    var maximumRounds: Int { GameConfig.maximumRounds }
    var acceptsInput: Bool { state == .answering }
    /// The answer cards are on the table for the whole round — they are only
    /// ever face up or face down, never absent.
    var showsAnswers: Bool { state != .intro }
    /// Whether the answers are readable: during the memorising beat, and again
    /// while the round resolves so the player sees where the right card was.
    var showsAnswerValues: Bool { engine.showsAnswerValues }
    /// Whether the question is readable. It replaces the answers rather than
    /// sitting alongside them, which is what makes this a memory game.
    var showsQuestion: Bool { engine.showsQuestion }
    /// The correct card is highlighted after a wrong answer, and after the
    /// flamethrower has burned everything else away.
    var revealsCorrectAnswer: Bool {
        if case .wrong = engine.lastOutcome { return true }
        if case .correct = engine.lastOutcome { return true }
        return !burnedOptionIDs.isEmpty
    }

    init(request: GameSessionRequest) {
        self.request = request
        self.engine = MemoryGame(level: request.level,
                            cardCount: request.cardCount,
                            mixedVariant: request.mixedVariant)
    }

    // MARK: - Lifecycle

    /// Starts the level, resuming a paused session when one is waiting.
    func begin() {
        guard engine.state == .intro else { return }
        PlaytimeTracker.shared.challengeStarted()
        AppAudio.shared.setGameplayActive(true, questionText: nil)
        AppAudio.shared.playSessionStart()
        if let paused = PausedSessionStore.shared.session(request.board) {
            engine.resume(from: paused)
        } else {
            engine.start()
        }
        announceRound()
        sync()
    }

    /// The double card gets its own arrival sound, so the thicker card is
    /// noticed while the answers are still readable.
    private func announceRound() {
        if engine.round?.isDoubleCard == true {
            AppAudio.shared.playDoubleCardAppear()
        } else {
            AppAudio.shared.playCardReveal()
        }
    }

    func end() {
        // Leaving without finishing pauses the level rather than discarding it.
        savePausedSessionIfNeeded()
        recordResultIfNeeded()
        PlaytimeTracker.shared.challengeEnded()
        AppAudio.shared.setGameplayActive(false, questionText: nil)
        generation &+= 1
    }

    /// The close button: the level is put on pause with its cards intact, and
    /// those cards are banked to the player's total straight away.
    func quit() {
        savePausedSessionIfNeeded()
        engine.quit()
        recordResultIfNeeded()
        sync()
    }

    /// Freezes the session for this level, so re-entering it continues from
    /// here. A finished session has nothing to store and clears the record.
    ///
    /// A run that has not banked a single card is not worth coming back to:
    /// storing it would only put a pause marker on the menu for a level the
    /// player would restart from zero anyway.
    private func savePausedSessionIfNeeded() {
        guard !hasRecordedResult, let paused = engine.pausedSession() else { return }
        guard paused.cards > 0 else {
            PausedSessionStore.shared.clear(request.board)
            return
        }
        PausedSessionStore.shared.save(paused)
    }

    /// Play again always starts a clean run, so any paused record for this
    /// level is spent.
    func restart() {
        generation &+= 1
        hasRecordedResult = false
        PausedSessionStore.shared.clear(request.board)
        engine = MemoryGame(level: request.level,
                            cardCount: request.cardCount,
                            mixedVariant: request.mixedVariant)
        engine.start()
        AppAudio.shared.playSessionStart()
        announceRound()
        sync()
    }

    // MARK: - Round flow

    /// The tap that ends the memorising beat: the answer cards turn face down
    /// and the question comes up in their place.
    func turnCardsOver() {
        guard engine.turnCardsOver() else { return }
        // Every real interaction advances the playtime clock. Without these the
        // tracker only ever sees one gap from the first tap to the last, which
        // its idle limit then discards — a whole session counting as no time.
        PlaytimeTracker.shared.registerInteraction()
        AppAudio.shared.playCardFlip()
        haptic(.light)
        sync()

        let token = generation
        // Input opens as soon as the cards have finished turning; the question
        // is readable from that moment on.
        schedule(after: GameConfig.cardFlipDuration, token: token) { [weak self] in
            guard let self, self.engine.beginAnswering() else { return }
            self.sync()
        }
    }

    /// Forwards a card tap. The engine decides whether it counts; a repeat tap
    /// comes back as `.ignored` and changes nothing at all.
    func select(optionID: UUID) {
        let outcome = engine.select(optionID: optionID)
        guard outcome != .ignored else { return }
        PlaytimeTracker.shared.registerInteraction()
        sync()

        let token = generation
        let delay: Double
        switch outcome {
        case .correct(_, let wasDouble):
            AppAudio.shared.playCorrect()
            if wasDouble { AppAudio.shared.playDoubleScore() }
            haptic(.success)
            delay = GameConfig.nextRoundDelay.correct
        case .wrong:
            AppAudio.shared.playWrong()
            AppAudio.shared.playLifeLost()
            haptic(.error)
            delay = GameConfig.nextRoundDelay.wrong
        case .ignored:
            return
        }

        schedule(after: delay, token: token) { [weak self] in
            guard let self else { return }
            guard self.engine.finishResolving() else { return }
            self.engine.advance()
            if self.engine.state == .gameOver {
                self.finishSession()
            } else {
                self.announceRound()
            }
            self.sync()
        }
    }

    /// Burns the wrong cards for half a life. The engine's guard makes a second
    /// tap free, so hammering the button can never charge twice.
    func useFlamethrower() {
        guard engine.useFlamethrower() != nil else { return }
        PlaytimeTracker.shared.registerInteraction()
        AppAudio.shared.playFlamethrower()
        AppAudio.shared.playHalfLife()
        haptic(.rigid)
        withAnimation(.easeOut(duration: GameConfig.flamethrowerDuration)) { isFiring = true }
        sync()

        let token = generation
        // The flame flourish never blocks input: the single remaining card is
        // tappable throughout.
        schedule(after: GameConfig.flamethrowerDuration, token: token) { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) { self?.isFiring = false }
        }
    }

    // MARK: - Finishing

    private func finishSession() {
        recordResultIfNeeded()
    }

    /// Writes the session to disk exactly once, whichever way the screen is
    /// left: game over, the close button, or a swipe away.
    private func recordResultIfNeeded() {
        guard engine.state == .gameOver, !hasRecordedResult else { return }
        hasRecordedResult = true
        // A level that reached its end is finished, not paused.
        if engine.gameOverReason != .quit {
            PausedSessionStore.shared.clear(request.board)
        }

        let store = Progress.store
        let previousTotal = store.totalCards
        let newTotal = store.addCards(engine.cards)
        // The score belongs to the board this session was played on: the card
        // count, and on Supermix the combination, keep separate bests.
        let board = request.board
        let best = store.recordScore(engine.cards, board: board)
        let unlocked = CharacterUnlocks.newlyUnlocked(from: previousTotal, to: newTotal)

        // Reaching this board's maximum is tallied every time, which is what
        // the ×N badge on a completed card counts.
        let maximum = board.maximum
        if engine.cards >= maximum {
            store.recordMaxCompletion(board)
        }

        engine.applyProgressOutcome(previousBest: best.previousBest,
                                    isNewPersonalBest: best.isNewBest,
                                    unlockedCharacterIDs: unlocked)

        ReviewRequestCoordinator.shared.recordCompletedGame(
            isNewHighScore: best.isNewBest,
            score: engine.cards,
            maximumScore: maximum
        )

        // Leaving a level part-way through is not an achievement: the pause
        // button banks the cards quietly, with no end-of-session fanfare.
        if engine.gameOverReason != .quit {
            if best.isNewBest && engine.cards > 0 { AppAudio.shared.playHighScore() }
            else { AppAudio.shared.playSessionComplete() }
        }
        result = engine.result
    }

    // MARK: - Plumbing

    /// Copies the engine's state onto the published properties in one pass, so
    /// a single tap causes exactly one SwiftUI update rather than eight.
    private func sync() {
        state = engine.state
        round = engine.round
        roundNumber = engine.roundNumber
        cards = engine.cards
        livesRemaining = engine.livesRemaining
        selectedOptionID = engine.selectedOptionID
        burnedOptionIDs = engine.burnedOptionIDs
        canUseFlamethrower = engine.canUseFlamethrower
        isGameOver = engine.state == .gameOver
        if isGameOver { result = engine.result }
    }

    /// Runs `work` after a delay, unless the session moved on in the meantime.
    private func schedule(after delay: Double, token: Int, work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token else { return }
            work()
        }
    }

    private enum Haptic { case light, rigid, success, error }

    private func haptic(_ kind: Haptic) {
#if canImport(UIKit)
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .rigid: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
#endif
    }
}
