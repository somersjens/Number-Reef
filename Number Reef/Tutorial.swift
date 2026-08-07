//
//  Tutorial.swift
//  Number Reef
//
//  The guided first game. A new player is walked through the reef one step at a
//  time: swimming, collecting the right answer, what a wrong one costs, the two
//  helper fish, and the streak bonus — after which the level simply carries on
//  as an ordinary session.
//
//  The tutorial never re-implements a rule. Each step only *shapes* what the
//  reef releases (`ReefTutorialPlan`) and listens for the one thing that step is
//  waiting for; scoring, lives and rounds keep running through `MemoryGame`
//  exactly as they do in a normal game. That is what makes the tutorial a real
//  session rather than a scripted demo: the bubbles the player collects here
//  count, and the level continues from where the last step leaves it.
//

import SwiftUI
import Combine

// MARK: - Steps

/// The nine in-game steps, in the order they are played. The tenth step of the
/// script is the score pointer on the home screen, which lives there rather than
/// in a session — see `HomeView`.
enum TutorialStep: Int, CaseIterable, Identifiable {
    /// Tap a point and the fish swims there. The marker sits below the fish.
    case tapToSwim = 1
    /// The same, held and dragged, with the marker at the top of the water.
    case dragToSwim
    /// Two bubbles, one of them right. A wrong touch costs nothing here.
    case collectCorrect
    /// Only wrong answers. Touching one costs a whole life and clears the water.
    case wrongCostsLife
    /// A heart fish, which hands a whole life back.
    case heartFish
    /// A 2x fish, which doubles the next answer.
    case bonusFish
    /// Five right answers in a row, one bubble at a time, to reach the streak.
    case buildStreak
    /// The streak is running: two bubbles at the boosted tempo.
    case superBonusRunning
    /// Normal play resumes; the last message clears itself after a few seconds.
    case freePlay

    var id: Int { rawValue }

    /// The message shown on screen for this step.
    var messageKey: String { "tutorial.step.\(rawValue)" }

    var next: TutorialStep? { TutorialStep(rawValue: rawValue + 1) }

    /// How long the closing message stays before the tutorial hands the level
    /// back to the player.
    static let freePlayMessageDuration = 5.0
}

// MARK: - What the reef should release

/// The shape the tutorial asks the reef to take for the current step. The reef
/// owns *how* it releases bubbles and fish; this only says what may be in the
/// water while a step is being taught.
struct ReefTutorialPlan: Equatable {
    /// One fixed wave: how many right and wrong answers the coral offers before
    /// starting the same set over again.
    struct Wave: Equatable {
        var correct: Int
        var wrong: Int
    }

    /// False for every ordinary session, which leaves the reef untouched.
    var isActive = false
    /// Where the player has to swim, in the open water's own unit coordinates
    /// (0 = just under the HUD, 1 = just above the coral). A marker is drawn
    /// there and reaching it reports `reachedSwimTarget`.
    var swimTarget: UnitPoint?
    /// Draws a finger tracing the way from the fish to the target. The second
    /// step asks for a different *gesture* rather than a different place, and
    /// its wording alone reads much like the first one's.
    var showsSwipeHint = false
    /// Fixes the composition of every wave. Nil leaves the normal set of five.
    var answers: Wave?
    /// No answer bubble may be in the water at all.
    var suppressesAnswers = false
    /// A wrong touch bursts the whole wave instead of only the bubble hit.
    var burstsWaveOnWrong = false
    /// Puts a 2x fish in the water, and puts it back whenever it is missed.
    var wantsBonusFish = false
    /// The same for the heart fish.
    var wantsHeartFish = false
}

/// The three things the reef itself notices, which the tutorial waits on.
enum ReefTutorialEvent {
    case reachedSwimTarget
    case caughtBonusFish
    case caughtHeartFish
}

// MARK: - Controller

/// Runs the script: holds the current step, hands the reef its plan, and moves
/// on the moment the step's own condition is met. Everything it needs to know
/// arrives as an event — nothing here polls the game.
@MainActor
final class TutorialController: ObservableObject {
    @Published private(set) var step: TutorialStep?
    @Published private(set) var plan = ReefTutorialPlan()

    /// The session being taught. Weak, so the controller can never keep a
    /// finished game alive.
    private weak var model: GameViewModel?
    /// Invalidates the pending close of the last message when the run is left,
    /// restarted or finished first.
    private var generation = 0

    var isActive: Bool { step != nil }

    /// The line currently on screen, in the player's own language.
    var message: String? {
        step.map { L(key: $0.messageKey) }
    }

    // MARK: Lifecycle

    /// Starts the walkthrough on a session that has just opened its first round.
    func begin(model: GameViewModel) {
        guard step == nil else { return }
        self.model = model
        model.onAnswerResolved = { [weak self] isCorrect, startedStreak in
            self?.answerResolved(isCorrect: isCorrect, startedStreak: startedStreak)
        }
        // Whatever happens to this session from here — finished, lost or left —
        // the player has seen the reef, so the home screen owes them the last
        // step of the script.
        GameSettings.tutorialHomeHintPending = true
        enter(.tapToSwim)
    }

    /// Ends the walkthrough and hands the level back unchanged: normal waves,
    /// normal penalties, normal helper fish.
    func finish() {
        guard step != nil else { return }
        generation &+= 1
        release()
        withAnimation(.easeOut(duration: 0.32)) {
            step = nil
            plan = ReefTutorialPlan()
        }
    }

    /// Leaving the game screen: the same tidy-up, without the animation of a
    /// view that is on its way out.
    func cancel() {
        guard step != nil else { return }
        generation &+= 1
        release()
        step = nil
        plan = ReefTutorialPlan()
    }

    private func release() {
        model?.setWrongAnswerPenalty(true)
        model?.setHeartFishRestoresWholeLife(false)
        model?.onAnswerResolved = nil
    }

    // MARK: Events

    /// Reported by the reef itself.
    func handle(_ event: ReefTutorialEvent) {
        guard let step else { return }
        switch event {
        case .reachedSwimTarget:
            if step == .tapToSwim || step == .dragToSwim { advance() }
        case .caughtHeartFish:
            if step == .heartFish { advance() }
        case .caughtBonusFish:
            if step == .bonusFish { advance() }
        }
    }

    /// Reported by the session for every answer it accepts.
    private func answerResolved(isCorrect: Bool, startedStreak: Bool) {
        guard let step else { return }
        switch step {
        case .collectCorrect:
            if isCorrect { advance() }
        case .wrongCostsLife:
            if !isCorrect { advance() }
        case .buildStreak:
            // True on the answer that starts the boost, which is the fifth in
            // a row — the whole point of this step.
            if startedStreak { advance() }
        case .superBonusRunning:
            if isCorrect { advance() }
        default:
            break
        }
    }

    // MARK: Steps

    private func advance() {
        guard let next = step?.next else {
            finish()
            return
        }
        enter(next)
    }

    private func enter(_ step: TutorialStep) {
        generation &+= 1
        let token = generation

        // Only the "try it once" step is free: everywhere else a wrong answer
        // costs exactly what it costs in a real game.
        model?.setWrongAnswerPenalty(step != .collectCorrect)
        if step == .heartFish {
            model?.setHeartFishRestoresWholeLife(true)
            model?.makeHeartFishAvailable()
        }

        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            self.step = step
            self.plan = Self.plan(for: step)
        }

        if step == .freePlay {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + TutorialStep.freePlayMessageDuration
            ) { [weak self] in
                guard let self, self.generation == token else { return }
                self.finish()
            }
        }
    }

    /// The reef's marching orders for each step.
    ///
    /// The two swim targets sit clear of the message card at the top and of the
    /// coral at the bottom, so the fish always has open water to cross.
    private static func plan(for step: TutorialStep) -> ReefTutorialPlan {
        var plan = ReefTutorialPlan()
        plan.isActive = true
        switch step {
        case .tapToSwim:
            plan.swimTarget = UnitPoint(x: 0.5, y: 0.88)
            plan.suppressesAnswers = true
        case .dragToSwim:
            plan.swimTarget = UnitPoint(x: 0.5, y: 0.26)
            plan.showsSwipeHint = true
            plan.suppressesAnswers = true
        case .collectCorrect:
            plan.answers = .init(correct: 1, wrong: 1)
        case .wrongCostsLife:
            // Every wrong answer this question has. A round carries one right
            // answer and `GameConfig.distractorCount` wrong ones, and the same
            // number may never be in the water twice.
            plan.answers = .init(correct: 0, wrong: GameConfig.distractorCount)
            plan.burstsWaveOnWrong = true
        case .heartFish:
            plan.suppressesAnswers = true
            plan.wantsHeartFish = true
        case .bonusFish:
            plan.suppressesAnswers = true
            plan.wantsBonusFish = true
        case .buildStreak:
            plan.answers = .init(correct: 1, wrong: 0)
        case .superBonusRunning:
            plan.answers = .init(correct: 1, wrong: 1)
        case .freePlay:
            // Nothing shaped any more: full waves, both helper fish back on
            // their own schedule. Only the message is still the tutorial's.
            break
        }
        return plan
    }
}

// MARK: - Message

/// The line the tutorial is currently teaching, shown under the HUD in the
/// game and at the top of the menu for the closing step. The character does the
/// talking, so it reads as the same voice as the level card.
struct TutorialMessageCard: View {
    let text: String
    let theme: AnimalCharacter
    var isPad: Bool = AppLayout.isPad

    private var portraitSize: CGFloat { isPad ? 56 : 42 }

    var body: some View {
        HStack(alignment: .center, spacing: isPad ? 14 : 10) {
            theme.artwork
                .resizable()
                .scaledToFit()
                .padding(isPad ? 4 : 3)
                .frame(width: portraitSize, height: portraitSize)
                .background(theme.skyColor,
                            in: RoundedRectangle(cornerRadius: isPad ? 15 : 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: isPad ? 15 : 12, style: .continuous)
                    .stroke(theme.deepColor.opacity(0.12), lineWidth: 1))

            Text(verbatim: text)
                .font(.system(size: isPad ? 19 : 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.deepColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isPad ? 16 : 12)
        .padding(.vertical, isPad ? 12 : 9)
        .background {
            RoundedRectangle(cornerRadius: isPad ? 24 : 20, style: .continuous)
                .fill(.white.opacity(0.95))
                .overlay {
                    RoundedRectangle(cornerRadius: isPad ? 24 : 20, style: .continuous)
                        .stroke(.white, lineWidth: 2)
                }
                .shadow(color: theme.deepColor.opacity(0.24), radius: 12, y: 6)
        }
        .frame(maxWidth: isPad ? 620 : 420)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Swim marker

/// The pulsing ring the first two steps ask the player to swim to.
struct TutorialTargetView: View {
    let theme: AnimalCharacter
    /// The reef's own clock, so the pulse freezes with everything else when the
    /// game is paused.
    let clock: Double
    let isPad: Bool

    private var diameter: CGFloat { isPad ? 96 : 72 }

    var body: some View {
        let beat = (sin(clock * 3.4) + 1) / 2
        ZStack {
            Circle()
                .fill(.white.opacity(0.18))
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: isPad ? 4 : 3)
                .scaleEffect(0.62 + 0.38 * beat)
                .opacity(1 - beat * 0.75)
            Circle()
                .stroke(theme.deepColor.opacity(0.9), style: StrokeStyle(
                    lineWidth: isPad ? 4 : 3, dash: [isPad ? 12 : 9, isPad ? 9 : 7]
                ))
                .rotationEffect(.radians(clock * 0.9))
            Image(systemName: "target")
                .font(.system(size: diameter * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: theme.deepColor.opacity(0.6), radius: 3)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(1 + 0.05 * beat)
        .shadow(color: .white.opacity(0.7), radius: 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Swipe hint

/// A finger sliding from the fish to the marker, over and over. It is what
/// makes the second swimming step visibly a *different* instruction from the
/// first: same water, same marker, but held and dragged rather than tapped.
struct TutorialSwipeHint: View {
    let start: CGPoint
    let end: CGPoint
    let theme: AnimalCharacter
    /// The reef's clock, so the hand stops with the rest of the scene.
    let clock: Double
    let isPad: Bool

    /// One full pass, plus a short beat before it starts over.
    private static let cycle = 2.0
    private static let travel = 1.45

    var body: some View {
        let phase = clock.truncatingRemainder(dividingBy: Self.cycle)
        let progress = min(1, phase / Self.travel)
        let eased = progress * progress * (3 - 2 * progress)
        let point = CGPoint(x: start.x + (end.x - start.x) * eased,
                            y: start.y + (end.y - start.y) * eased)
        // Fades in as it leaves the fish and out as it arrives, so the loop
        // never snaps back across the screen.
        let fade = min(1, progress / 0.18) * min(1, (1 - progress) / 0.22)

        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(.white.opacity(0.5), style: StrokeStyle(
                lineWidth: isPad ? 5 : 4, lineCap: .round, dash: [1, isPad ? 16 : 13]
            ))

            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: isPad ? 40 : 30, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: theme.deepColor.opacity(0.75), radius: 4)
                // The glyph points up and to the left from its own fingertip.
                .offset(x: isPad ? 13 : 10, y: isPad ? 19 : 14)
                .position(point)
                .opacity(fade)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - "Only at the start" notice

/// Shown when the tutorial is asked for on a game that is already under way.
/// Same card, same button as everything else the level screen puts up.
struct TutorialNoticeCard: View {
    let theme: AnimalCharacter
    let onDismiss: () -> Void

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14 * scale) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 30 * scale, weight: .bold))
                    .foregroundStyle(theme.deepColor)
                    .frame(width: 62 * scale, height: 62 * scale)
                    .background(theme.skyColor, in: Circle())

                Text("tutorial.notice.title")
                    .font(.system(size: 22 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
                    .multilineTextAlignment(.center)

                Text("tutorial.notice.message")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(theme.deepColor.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onDismiss) {
                    Text("common.ok")
                        .font(.system(size: 17 * scale, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14 * scale)
                        .foregroundStyle(.white)
                        .background(theme.deepColor,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tutorial-notice-ok")
            }
            .padding(26 * scale)
            .frame(maxWidth: 340 * scale)
            .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
            .shadow(color: theme.deepColor.opacity(0.3), radius: 20, y: 10)
            .padding(24)
        }
    }
}
