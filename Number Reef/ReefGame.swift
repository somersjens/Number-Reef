//
//  ReefGame.swift
//  Number Reef
//
//  The reef playing surface: the sum sits on a piece of coral on the sea floor,
//  the coral releases answer bubbles at irregular intervals, and the player
//  steers a fish into the bubble carrying the right answer.
//
//  This file holds the whole of the new gameplay and nothing else. Every rule
//  about scoring, lives, rounds and progress still lives in `MemoryGame`; this
//  scene only decides *when* an answer is touched and hands that answer over.
//  Wrong bubbles are free to drift off the top of the screen — reaching them is
//  never required.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Screen edges

/// The window's own safe area. The reef is laid out edge to edge, so it needs
/// the real insets to keep the sum clear of the home indicator and the fish
/// clear of the HUD — and a `GeometryReader` nested inside the playing field
/// reports zero for them, because its container has already been inset.
///
/// Sample this in `onAppear` and keep the value in state. Reading it from
/// inside a `body` wedges SwiftUI's update pass: the view renders once and then
/// stops receiving updates entirely, which shows up as a frozen playing field
/// with no sum on the coral.
struct ScreenSafeArea: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    @MainActor
    static var current: ScreenSafeArea {
#if canImport(UIKit)
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let insets = window?.safeAreaInsets else { return ScreenSafeArea() }
        return ScreenSafeArea(top: insets.top,
                              bottom: insets.bottom,
                              leading: insets.left,
                              trailing: insets.right)
#else
        return ScreenSafeArea()
#endif
    }
}

// MARK: - Tuning

/// A conservative decoration budget for older hardware and Low Power Mode.
/// Gameplay, steering and collision detection always retain their 60 Hz step;
/// only effects that do not carry information become a little sparser.
private enum ReefPerformanceBudget {
    static let isConstrained: Bool = {
        ProcessInfo.processInfo.physicalMemory < 4_000_000_000
            || ProcessInfo.processInfo.isLowPowerModeEnabled
    }()

    static let moteCount = isConstrained ? 10 : 16
    static let maximumAmbientBubbles = isConstrained ? 10 : 18
    static let wakeInterval = isConstrained ? 0.105 : 0.075
    static let completionStreamInterval = isConstrained ? 0.055 : 0.035
    static let completionTrailInterval = isConstrained ? 0.070 : 0.045
    /// Scenery sway: 20 Hz normally, 12 Hz where the frame budget is tightest.
    static let swayInterval = isConstrained ? 1.0 / 12.0 : 1.0 / 20.0
    static let driftInterval = isConstrained ? 1.0 / 4.0 : 1.0 / 6.0
}

#if canImport(UIKit)
/// Decode the two occasional power-up sprites before gameplay starts. Their
/// first appearance should never have to pay PNG decompression on the frame in
/// which they enter the water.
private enum ReefArtworkCache {
    static let bonusFish: UIImage = preparedImage(named: "2x_coin_fish")
    static let lifeFish: UIImage = preparedImage(named: "life_fish")

    static func prewarm() {
        _ = bonusFish
        _ = lifeFish
    }

    private static func preparedImage(named name: String) -> UIImage {
        let image = UIImage(named: name) ?? UIImage()
        return image.preparingForDisplay() ?? image
    }
}
#endif

/// Every tunable number of the reef scene, kept together the way `GameConfig`
/// keeps the session's.
enum ReefConfig {
    /// Simulation step. The scene is driven at display cadence at this rate.
    ///
    /// The interactive scene runs at display cadence so fish steering and
    /// answer collisions stay smooth.
    static let tick = 1.0 / 60.0

    // MARK: Bubbles

    static func bubbleDiameter(isPad: Bool) -> CGFloat { isPad ? 118 : 88 }

    /// Cruise speed after a bubble has cleared its crater. Answers stay in the
    /// open water long enough to read and intercept.
    static let riseSpeed: ClosedRange<CGFloat> = 72...88
    /// A new bubble first shoots clear of the coral, then eases into its cruise.
    /// Expressing this relative to its diameter keeps the launch equally lively
    /// on iPhone and iPad.
    static let launchSpeedFactor: ClosedRange<CGFloat> = 1.75...2.05
    static let launchHoldDuration = 0.42
    static let launchSlowdownDuration = 0.28
    /// Sideways sway, so no two bubbles share a path.
    static let driftAmplitude: ClosedRange<CGFloat> = 6...22
    static let driftPeriod: ClosedRange<Double> = 2.4...4.4

    /// Gap between two releases. Irregular, but short enough that a quick
    /// player does not spend most of a round waiting for the next answer.
    static let spawnGap: ClosedRange<Double> = 0.95...1.45
    /// Now and then two bubbles follow each other closely, which is what breaks
    /// the rhythm; `closeGapChance` decides how often.
    static let closeGap: ClosedRange<Double> = 0.45...0.70
    static let closeGapChance = 0.40
    /// A breather before the coral starts over with the same set of answers.
    static let waveGap: ClosedRange<Double> = 1.5...2.1
    /// The first bubble starts emerging as the new sum settles into view.
    static let firstGap: ClosedRange<Double> = 0.10...0.25
    /// Retry delay when there is no room to release a bubble yet.
    static let blockedGap = 0.25
    /// Once the correct answer has drifted beyond the fish's reachable water,
    /// replace it from below after one short beat instead of waiting for the
    /// whole old wave to disappear.
    static let missedCorrectRetryGap: ClosedRange<Double> = 0.35...0.60
    /// The fish and bubble hit radii overlap up to roughly this far above the
    /// HUD reserve. Crossing it means the answer can no longer be collected.
    static let missedCorrectTopFactor: CGFloat = 0.46

    /// Chance that the correct answer occupies each successive place in a
    /// fresh five-bubble wave. This favours an early answer without making its
    /// arrival predictable: first 35%, then 30%, 20%, 10% and 5%.
    static let correctAnswerPositionWeights = [35, 30, 20, 10, 5]

    /// Most bubbles allowed in the water at once — a whole set of answers, so
    /// every one of them can be up there together. Crowding is not left to this
    /// number alone: a release still needs a crater with room above it, so the
    /// water thins itself out when the bubbles bunch up.
    static let maximumLiveBubbles = GameConfig.answerBubbleCount
    /// Least horizontal distance between a new bubble and one still near the
    /// coral, as a share of the bubble diameter.
    static let separationFactor: CGFloat = 1.06
    /// A new bubble also leaves this much of a gap from the previous vent, so
    /// they do not stream out of one spot.
    static let ventSpreadFactor: CGFloat = 0.55
    /// How far above the coral a bubble still counts as "in the way" when the
    /// next release looks for a free spot.
    static let crowdBandFactor: CGFloat = 1.7

    /// How long a burst stays on screen after a bubble is touched or burned.
    static let popDuration = 0.26
    /// A caught answer leaves the back of the character as a small score
    /// bubble. It reaches the HUD just after the next sum begins to appear.
    static let collectedBubbleDuration = 0.92
    /// A bubble starts as a speck in its crater and swells to full size as it
    /// leaves, the way a real one does.
    static let emergeDuration = 0.62
    /// Size it starts at, as a share of full.
    static let emergeStartScale = 0.10
    /// A launch must carry the whole bubble clearly above the coral before the
    /// fish can collect it. This moves play into the water instead of letting a
    /// player camp along the sea floor.
    static let minimumCatchRiseFactor: CGFloat = 1.12

    // MARK: Fish

    /// The character's nominal size. Everything that has to agree with the
    /// player's body — the hit radius, the wake, the entrance spiral, the walls
    /// — is measured from this one number, so it stays the same for all ten.
    static func fishLength(isPad: Bool) -> CGFloat { isPad ? 96 : 72 }
    /// How large the artwork is drawn against that nominal size. Applied to the
    /// geometric mean of the asset's own width and height, so every character
    /// covers the same amount of water at its own proportions.
    static let fishArtworkSpan: CGFloat = 0.85
    /// Body radius used for touches, a little inside the artwork so a near miss
    /// reads as a miss.
    static let fishHitFactor: CGFloat = 0.30
    /// Bubbles are forgiving by the same margin, so contact matches what is on
    /// screen.
    static let bubbleHitFactor: CGFloat = 0.46

    /// Ceiling on the fish's speed, in points per second.
    static let fishMaximumSpeed: CGFloat = 620
    /// How eagerly the fish closes the remaining distance. Higher is snappier;
    /// this is the balance between "responds at once" and "glides".
    static let fishApproach: CGFloat = 7.0
    /// Below this distance the fish holds still, so a resting finger does not
    /// make it jitter.
    static let fishDeadzone: CGFloat = 7
    /// How quickly the fish swings round to face where it is going.
    static let fishTurnRate: Double = 9.0

    /// The opening swim curls inward from beyond the right edge before the
    /// first answer is released. Long enough to read as an entrance, without
    /// making a child wait to play.
    static let fishEntranceDuration = 1.85
    /// Opens the first round just before the fish settles, so the crown of its
    /// first bubble can already peek out as the entrance finishes.
    static let fishEntranceAnswerLead = 0.90

    // MARK: Level completion

    /// A compact finale: gather, draw the heart, then let the bubbles fill the
    /// water while the fish follows its last heading out of view. The exit
    /// occupies the old post-heart pause, so the result card follows motion
    /// instead of a frozen final frame.
    static let completionDuration = 3.45
    static let completionGatherDuration = 0.55
    static let completionHeartDuration = 2.45

    /// The tail sheds short underwater eddies rather than surface-like rings.
    /// Tiny air pockets live a little longer so they can peel away and rise.
    static let wakeLifetime = 0.78
    static let miniBubbleLifetime = 1.05
    static let wakeInterval = ReefPerformanceBudget.wakeInterval
    /// How long a resting character waits between two breath bubbles. Random
    /// within the range, so the rhythm never becomes a metronome.
    static let idleBreathGap: ClosedRange<Double> = 0.9...1.8

    /// After a touch, no second answer can be taken for this long — one bump
    /// can never select two bubbles.
    static let collisionCooldown = 0.22

    // MARK: Decorative air bubbles

    static let ambientBubbleGap: ClosedRange<Double> = 0.32...0.72
    static let ambientBubbleSpeed: ClosedRange<CGFloat> = 28...54
    static let ambientBubbleRadius: ClosedRange<CGFloat> = 3.5...9
    static let maximumAmbientBubbles = ReefPerformanceBudget.maximumAmbientBubbles
    static let ambientBubblePopDuration = 0.24

    // MARK: Tutorial

    /// How long the walkthrough's helper fish takes to come round, both the
    /// first time and after a miss. Short enough not to be a wait, long enough
    /// that a fish never appears on top of the message announcing it.
    static let tutorialFishArrival = 0.8

    /// Water the walkthrough keeps free below the HUD: its message card hangs
    /// there, and a helper fish crossing behind that card is a helper fish the
    /// player never sees. Generous enough for the longest translation, which
    /// runs to three lines.
    static func tutorialMessageReserve(isPad: Bool) -> CGFloat { isPad ? 150 : 116 }

    // MARK: 2x fish

    static func bonusFishLength(isPad: Bool) -> CGFloat { isPad ? 82 : 62 }
    /// Slow enough to notice and intercept, while still clearly being a
    /// passing power-up rather than another answer bubble.
    static let bonusFishSpeed: ClosedRange<CGFloat> = 155...190
    /// After one of the preselected questions appears, this little extra delay
    /// keeps the exact arrival surprising and independent of answer releases.
    static let bonusFishQuestionDelay: ClosedRange<Double> = 2.0...5.0
    static let bonusFishPopDuration = 0.32

    // MARK: Heart fish

    static func heartFishLength(isPad: Bool) -> CGFloat { isPad ? 88 : 66 }
    /// Slightly slower than the 2x fish: this reward follows eight correct
    /// answers and should be an attainable comeback opportunity.
    static let heartFishSpeed: ClosedRange<CGFloat> = 125...155
    static let heartFishDelay: ClosedRange<Double> = 1.5...3.5
    static let heartFishPopDuration = 0.36

    // MARK: Sea floor

    /// How far the reef block sits above the bottom edge, on top of whatever
    /// the home indicator already reserves.
    static func floorInset(isPad: Bool) -> CGFloat { isPad ? 26 : 18 }
    /// The doorway the sum is written in.
    static func doorHeight(isPad: Bool) -> CGFloat { isPad ? 86 : 68 }
    /// The coral rim on top of the doorway, which the craters are set into.
    static func craterRimHeight(isPad: Bool) -> CGFloat { isPad ? 24 : 18 }
    /// How much of the reef block the coral sides take, so the sum never runs
    /// edge to edge and the mound stays visible beside it.
    static func blockInset(isPad: Bool) -> CGFloat { isPad ? 72 : 28 }
    /// How far inside the block the outermost crater sits.
    static func craterInset(isPad: Bool) -> CGFloat { isPad ? 44 : 32 }

    /// Everything from the crest down: rim, sum and sea floor.
    static func bandHeight(isPad: Bool, bottomReserve: CGFloat) -> CGFloat {
        floorInset(isPad: isPad) + bottomReserve
            + doorHeight(isPad: isPad) + craterRimHeight(isPad: isPad)
    }
    /// The sand runs off the bottom of the screen, so the floor never ends in
    /// a visible edge, and its crown rises either side of the reef block.
    static func sandHeight(isPad: Bool, bottomReserve: CGFloat) -> CGFloat {
        floorInset(isPad: isPad) + bottomReserve + (isPad ? 118 : 92)
    }
    /// Margin between a bubble and the side of the screen.
    static func sideInset(isPad: Bool) -> CGFloat { isPad ? 12 : 8 }

    /// The coral has a fixed set of craters, and every bubble comes out of one
    /// of them. Fixing the positions is what lets the craters actually be drawn
    /// where the bubbles appear.
    static let craterCount = 5

    static func craterPositions(width: CGFloat, isPad: Bool) -> [CGFloat] {
        let inset = blockInset(isPad: isPad) + craterInset(isPad: isPad)
        let minX = inset
        let maxX = max(minX, width - inset)
        guard craterCount > 1, maxX > minX else { return [(minX + maxX) / 2] }
        return (0..<craterCount).map {
            minX + (maxX - minX) * CGFloat($0) / CGFloat(craterCount - 1)
        }
    }

    // MARK: Ambience

    /// How often the swaying scenery is re-sampled. Coral, plants and vents all
    /// breathe at well under 1.2 Hz, so a fresh position 20 times a second is
    /// already smoother than the eye can follow — while a full 60 Hz rebuild of
    /// that whole sea floor is by far the most expensive thing in the frame.
    /// Everything the player actually steers and touches keeps the 60 Hz step.
    static let swayInterval = ReefPerformanceBudget.swayInterval
    /// The sun shafts drift on a 35-second cycle and are the one full-screen
    /// blur in the scene, so they are re-sampled far more sparingly still.
    static let driftInterval = ReefPerformanceBudget.driftInterval

    /// Specks of drifting plankton, purely decorative. They freeze with the
    /// rest of the scene when the game is paused.
    static let moteCount = ReefPerformanceBudget.moteCount
    static let moteSpeed: ClosedRange<CGFloat> = 8...22
    static let moteRadius: ClosedRange<CGFloat> = 1.5...4.5
}

// MARK: - Palette

/// The reef's colours. Each one starts from the player's own character colours
/// and is pulled toward the sea, so a fox reef and a penguin reef are still
/// recognisably theirs while both read as water.
struct ReefPalette {
    let character: AnimalCharacter

    private static let surface = (0.60, 0.87, 0.95)
    private static let depth = (0.10, 0.45, 0.66)
    private static let sandTone = (0.96, 0.90, 0.74)
    private static let sandShadow = (0.80, 0.68, 0.46)

    var waterTop: Color { Self.mix(character.skyRGB, Self.surface, 0.72) }
    var waterDeep: Color { Self.mix(character.primaryRGB, Self.depth, 0.85) }
    var sand: Color { Self.mix(character.tintRGB, Self.sandTone, 0.72) }
    var sandDeep: Color { Self.mix(character.deepRGB, Self.sandShadow, 0.62) }

    /// The coral keeps the character's own colour: it is the one warm thing on
    /// the reef, and it is what the sum stands on.
    var coral: Color { character.color }
    var coralDeep: Color { character.deepColor }
    var plant: Color { Color(red: 0.18, green: 0.56, blue: 0.34) }
    var plantLight: Color { Color(red: 0.43, green: 0.72, blue: 0.30) }

    private static func mix(_ base: (Double, Double, Double),
                            _ target: (Double, Double, Double),
                            _ amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        return Color(red: base.0 + (target.0 - base.0) * t,
                     green: base.1 + (target.1 - base.1) * t,
                     blue: base.2 + (target.2 - base.2) * t)
    }
}

// MARK: - Model

/// One answer bubble on its way up.
struct ReefBubble: Identifiable {
    let id = UUID()
    /// The engine's option, which is what a touch reports back.
    let optionID: UUID
    let text: String
    let isCorrect: Bool
    let diameter: CGFloat

    /// Centre of the sway, and the current position around it.
    let baseX: CGFloat
    var position: CGPoint
    let launchSpeed: CGFloat
    let speed: CGFloat
    let driftAmplitude: CGFloat
    let driftPeriod: Double
    let phase: Double

    var age: Double = 0
    /// Set the moment the bubble bursts; it is removed once the burst ends.
    var popAge: Double?

    var isPopping: Bool { popAge != nil }

    /// 0 → just released, 1 → full size.
    var emergence: Double {
        min(1, age / ReefConfig.emergeDuration)
    }
}

/// The right answer after it has been collected. It is deliberately separate
/// from the live answer bubbles: those burst, while this one slips out behind
/// the swimmer and carries its value to the score at the top of the reef.
struct ReefCollectedBubble: Identifiable {
    let id = UUID()
    let diameter: CGFloat
    let start: CGPoint
    let firstControl: CGPoint
    let secondControl: CGPoint
    let target: CGPoint
    var position: CGPoint
    var age: Double = 0
}

/// A speck of drifting plankton. Decoration only — it is never touched and
/// never carries an answer.
struct ReefMote: Identifiable {
    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let sway: CGFloat
    let period: Double
    let phase: Double
    let baseX: CGFloat
    var age: Double = 0
}

/// Where the fish is, which way it is pointing, and whether a finger is
/// currently steering it.
struct ReefFish {
    var position: CGPoint = .zero
    /// Radians, 0 pointing right.
    var heading: Double = 0
    var isSwimming = false
}

/// One sideways wisp or tiny rising air pocket shed by the fish's tail.
struct ReefWake: Identifiable {
    enum Kind {
        case wisp
        case bubble
    }

    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let kind: Kind
    /// Direction of travel when the wake was released. Wisps retain this
    /// orientation while the fish turns away from them.
    let heading: Double
    /// Alternates across the tail to keep the disturbance organic.
    let side: CGFloat
    var velocity: CGPoint
    var age: Double = 0

    var lifetime: Double {
        kind == .bubble ? ReefConfig.miniBubbleLifetime : ReefConfig.wakeLifetime
    }
}

/// A fast 2x power-up fish crossing the open water from either side.
struct ReefBonusFish: Identifiable {
    let id = UUID()
    var position: CGPoint
    let direction: CGFloat
    let speed: CGFloat
    let length: CGFloat
    var isCarryingReward = true
}

/// A passing recovery fish earned by a run of correct answers after damage.
struct ReefHeartFish: Identifiable {
    let id = UUID()
    var position: CGPoint
    let direction: CGFloat
    let speed: CGFloat
    let length: CGFloat
    var isCarryingReward = true
}

/// One decorative bubble in the completed-level finale. Answer bubbles keep
/// their separate model because these carry no text and can never be touched.
struct ReefCelebrationBubble: Identifiable {
    enum Kind { case stream, trail }

    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let phase: Double
    let kind: Kind
    var age: Double = 0
}

/// A small, purely decorative air pocket. It never carries an answer or
/// changes score; touching the player's fish only starts its visual pop.
struct ReefAmbientBubble: Identifiable {
    let id = UUID()
    let baseX: CGFloat
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let phase: Double
    var age: Double = 0
    var popAge: Double?
}

// MARK: - Engine

/// Drives the bubbles and the fish. It owns exactly one timer, holds no rules
/// about scoring, and reports a touched answer through `onHit`.
@MainActor
final class ReefEngine: ObservableObject {
    // These values all advance together in `tick()`. Publishing each array
    // element mutation caused many redundant SwiftUI invalidations per frame
    // (especially while bubbles, wakes and motes were all moving). `clock` is
    // the single render signal for the completed simulation frame instead.
    private(set) var bubbles: [ReefBubble] = []
    private(set) var collectedBubbles: [ReefCollectedBubble] = []
    private(set) var fish = ReefFish()
    private(set) var motes: [ReefMote] = []
    private(set) var wakes: [ReefWake] = []
    private(set) var bonusFish: ReefBonusFish?
    private(set) var heartFish: ReefHeartFish?
    private(set) var celebrationBubbles: [ReefCelebrationBubble] = []
    private(set) var ambientBubbles: [ReefAmbientBubble] = []
    private(set) var hasBonusAura = false
    /// Seconds of running time. It stops when the game does, so nothing moves
    /// behind a pause. Everything the player steers, touches or reads timing
    /// from follows this at the display's full cadence (60 or 120 Hz).
    @Published private(set) var clock: Double = 0
    /// The same clock, held still between sway steps. The sea floor is ~185
    /// gradient, stroke and shadow nodes; rebuilding all of them 60 times a
    /// second left no frame budget for the moments that actually matter — an
    /// answer being taken. Because the scenery views are `Equatable` on their
    /// clock, an unchanged value here skips that entire rebuild.
    private(set) var swayClock: Double = 0
    /// Coarser still, for the drifting sun shafts and their full-screen blur.
    private(set) var driftClock: Double = 0

    /// Called when the fish touches an answer bubble. Returns whether the
    /// session accepted it, so a touch the engine ignores leaves the water
    /// exactly as it was.
    var onHit: ((UUID) -> Bool)?
    var onCollectedBubbleArrived: (() -> Void)?
    var onBonusFishCaught: (() -> Void)?
    var onHeartFishCaught: (() -> Bool)?
    var onHeartFishMissed: (() -> Void)?

    // Geometry, set from the view's layout.
    private var size: CGSize = .zero
    private var spawnLine: CGFloat = 0
    /// Kept clear at the top so the fish never swims under the HUD.
    private var topReserve: CGFloat = 0
    private var isPad = false
    private var diameter: CGFloat = 88
    private var fishLength: CGFloat = 72
    /// Width of this character's actual side artwork, rather than the nominal
    /// collision size. It puts the collected bubble behind long and short
    /// swimmers equally convincingly.
    private var fishArtworkWidth: CGFloat = 72
    private var scoreTarget: CGPoint?

    // Round state.
    private var round: GameRound?
    private var queue: [AnswerOption] = []
    private var timeToNextSpawn: Double = 0
    private var lastVentX: CGFloat?

    /// Whether answers may be released and touched. False while feedback plays,
    /// on the intro card and once the session is over.
    private var isLive = false
    private var collisionCooldown: Double = 0
    private var speedMultiplier = 1.0

    // At the start, one to three hidden question numbers are picked across the
    // whole board. This makes a passage possible near the beginning or near
    // the end without tying it to how many seconds the player needs.
    private var maximumRounds = 1
    private var bonusFishTriggerRounds: [Int] = []
    private var nextBonusFishTrigger = 0
    private var pendingBonusFishDelays: [Double] = []

    // A heart fish is scheduled by the rules engine once its earned meter is
    // full. This scene only owns the short randomized arrival delay.
    private var isHeartFishAvailable = false
    private var heartFishDelay: Double?

    // The walkthrough. While a plan is active it decides what may be in the
    // water; the reef keeps releasing, steering and colliding exactly as it
    // otherwise would. See `Tutorial.swift`.
    private var tutorialPlan = ReefTutorialPlan()
    /// Where the current step asks the player to swim, in reef coordinates.
    @Published private(set) var tutorialTarget: CGPoint?
    /// Time until the taught helper fish comes back around after being missed.
    private var tutorialFishDelay: Double?
    var onTutorialEvent: ((ReefTutorialEvent) -> Void)?

    // Steering.
    private var target: CGPoint?
    /// Residual velocity after the scripted entrance. It gently decays until a
    /// finger takes over, which avoids the fish stopping dead at the endpoint.
    private var coastVelocity: CGPoint = .zero

    // Opening swim. A non-nil elapsed time temporarily owns the fish, so touch
    // steering cannot pull it out of the entrance before it reaches centre.
    private var entranceElapsed: Double?
    private var entranceCompletion: (() -> Void)?
    private var entranceDidOpenRound = false
    private var wakeCountdown: Double = 0
    private var wakeSide: CGFloat = -1
    private var wakeEmissionIndex = 0
    private var idleBreathCountdown = Double.random(in: ReefConfig.idleBreathGap)

    // Completed-level swim. It deliberately lives in this engine so the real
    // fish continues from its final gameplay position without a visual jump.
    private var completionElapsed: Double?
    private var completionStart = CGPoint.zero
    private var completionCallback: (() -> Void)?
    private var completionBubbleCountdown = 0.0
    private var completionTrailCountdown = 0.0
    private var reducesCompletionMotion = false
    private var ambientBubbleCountdown = Double.random(in: ReefConfig.ambientBubbleGap)

#if canImport(UIKit)
    /// A display-linked driver avoids timer firings landing halfway through a
    /// screen refresh, which was visible as uneven motion on slower devices.
    private final class DisplayLinkTarget: NSObject {
        weak var owner: ReefEngine?

        init(owner: ReefEngine) {
            self.owner = owner
        }

        @objc func advance(_ displayLink: CADisplayLink) {
            guard let owner else {
                displayLink.invalidate()
                return
            }
            owner.advance(displayLink)
        }
    }

    private lazy var displayLinkTarget = DisplayLinkTarget(owner: self)
    private var displayLink: CADisplayLink?
    private var lastFrameTargetTimestamp: CFTimeInterval?
#else
    private var timer: Timer?
#endif

    deinit {
#if canImport(UIKit)
        displayLink?.invalidate()
#else
        timer?.invalidate()
#endif
    }

    // MARK: Layout

    /// Called from the view's geometry. Re-running it on a size change keeps
    /// the fish and the bubbles inside the new bounds.
    func layout(size: CGSize, spawnLine: CGFloat, topReserve: CGFloat, isPad: Bool,
                fishArtworkWidth: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        let isFirst = self.size == .zero
        self.size = size
        self.spawnLine = spawnLine
        self.topReserve = topReserve
        self.isPad = isPad
        self.diameter = ReefConfig.bubbleDiameter(isPad: isPad)
        self.fishLength = ReefConfig.fishLength(isPad: isPad)
        self.fishArtworkWidth = fishArtworkWidth
        if isFirst {
            // Avoid storage growth while gameplay is already animating. These
            // are small upper bounds and reserve capacity only; they do not
            // create or draw additional objects.
            bubbles.reserveCapacity(ReefConfig.maximumLiveBubbles + 4)
            queue.reserveCapacity(GameConfig.answerBubbleCount)
            wakes.reserveCapacity(ReefPerformanceBudget.isConstrained ? 24 : 48)
            ambientBubbles.reserveCapacity(ReefConfig.maximumAmbientBubbles)
            celebrationBubbles.reserveCapacity(ReefPerformanceBudget.isConstrained ? 72 : 120)
            fish.position = CGPoint(x: size.width / 2, y: spawnLine - fishLength)
        } else {
            fish.position = clampedFishPosition(fish.position)
        }
        updateTutorialTarget()
        seedMotes()
    }

    /// Scatters the drifting specks over the water, once per size.
    private func seedMotes() {
        motes = (0..<ReefConfig.moteCount).map { _ in
            let x = CGFloat.random(in: 0...size.width)
            return ReefMote(position: CGPoint(x: x, y: CGFloat.random(in: 0...size.height)),
                            radius: CGFloat.random(in: ReefConfig.moteRadius),
                            speed: CGFloat.random(in: ReefConfig.moteSpeed),
                            sway: CGFloat.random(in: 4...14),
                            period: Double.random(in: 3...7),
                            phase: Double.random(in: 0..<(2 * .pi)),
                            baseX: x)
        }
    }

    // MARK: Session control

    /// Supplies the board length before its first question is loaded. The
    /// actual hidden trigger questions are chosen when that question arrives,
    /// which also makes a resumed board plan only over its remaining rounds.
    func configureBonusFish(maximumRounds: Int) {
        self.maximumRounds = max(1, maximumRounds)
    }

    /// Installs a round. Called only when the sum actually changes, so a wrong
    /// answer leaves the water — and the sum — as it was.
    func load(round: GameRound?) {
        let previousRoundNumber = self.round?.number
        self.round = round
        bubbles.removeAll()
        queue.removeAll()
        lastVentX = nil
        collisionCooldown = 0
        timeToNextSpawn = Double.random(in: ReefConfig.firstGap)
        guard let round else { return }

        // Playing again reuses this SwiftUI playfield and therefore this
        // engine. A fresh round one starts a genuinely fresh hidden plan.
        if round.number == 1, previousRoundNumber != nil {
            collectedBubbles.removeAll()
            bonusFish = nil
            bonusFishTriggerRounds.removeAll()
            nextBonusFishTrigger = 0
            pendingBonusFishDelays.removeAll()
            heartFish = nil
            isHeartFishAvailable = false
            heartFishDelay = nil
        }
        if bonusFishTriggerRounds.isEmpty {
            makeBonusFishPlan(startingAt: round.number)
        }
        while nextBonusFishTrigger < bonusFishTriggerRounds.count,
              round.number >= bonusFishTriggerRounds[nextBonusFishTrigger] {
            pendingBonusFishDelays.append(
                Double.random(in: ReefConfig.bonusFishQuestionDelay)
            )
            nextBonusFishTrigger += 1
        }
    }

    private func makeBonusFishPlan(startingAt firstRound: Int) {
        let requestedCount = Int.random(in: GameConfig.bonusFishCount)

        // `maximumRounds` is only the one-card-per-answer ceiling. A perfect
        // streak pays two cards, and every caught 2x fish can make one of those
        // answers worth four. Plan against that shortest possible run; a fish
        // may then be late, but never on a question the level cannot reach.
        let streakStart = min(GameConfig.streakThreshold, maximumRounds)
        let cardsAfterStreakStart = max(0,
            maximumRounds - streakStart - requestedCount * GameConfig.bonusFishMultiplier
        )
        let shortestPossibleRun = streakStart
            + Int(ceil(Double(cardsAfterStreakStart) / Double(GameConfig.streakMultiplier)))
        let lastRound = max(firstRound, min(maximumRounds, shortestPossibleRun))
        let availableRounds = Array(firstRound...lastRound)
        let count = min(requestedCount, availableRounds.count)
        bonusFishTriggerRounds = Array(availableRounds.shuffled().prefix(count)).sorted()
        nextBonusFishTrigger = 0
    }

    /// Play is live only while the session is accepting an answer.
    func setLive(_ live: Bool) {
        guard isLive != live else { return }
        isLive = live
        // Coming back from feedback, the fish may still be sitting where the
        // last bubble was. A moment's grace keeps one collision from turning
        // into two lives.
        if live { collisionCooldown = ReefConfig.collisionCooldown }
    }

    func setBonusAura(_ active: Bool) {
        guard hasBonusAura != active else { return }
        hasBonusAura = active
        // This can change while the simulation is paused, so it cannot wait
        // for the next clock update to be drawn.
        objectWillChange.send()
    }

    func setHeartFishAvailable(_ available: Bool) {
        if available && !isHeartFishAvailable && heartFish == nil {
            heartFishDelay = Double.random(in: ReefConfig.heartFishDelay)
        } else if !available {
            heartFishDelay = nil
        }
        isHeartFishAvailable = available
    }

    func setSpeedMultiplier(_ multiplier: Double) {
        speedMultiplier = max(1, multiplier)
    }

    /// Takes the walkthrough's marching orders for the step now being taught.
    /// A step that changes what the water holds clears it first, so the player
    /// always reads the new message against the bubbles that message describes.
    func applyTutorial(_ plan: ReefTutorialPlan) {
        let previous = tutorialPlan
        tutorialPlan = plan
        guard plan != previous else { return }
        updateTutorialTarget()

        guard plan.isActive else {
            tutorialFishDelay = nil
            return
        }

        if plan.suppressesAnswers {
            popAllAnswerBubbles()
            queue.removeAll()
        } else if plan.answers != previous.answers || previous.suppressesAnswers {
            popAllAnswerBubbles()
            queue.removeAll()
            timeToNextSpawn = Double.random(in: ReefConfig.firstGap)
        }

        // A helper fish that has already given up its reward is on its way out
        // and may finish crossing; one still carrying a reward belongs to the
        // step that asked for it and leaves with it.
        if !plan.wantsHeartFish, heartFish?.isCarryingReward == true { heartFish = nil }
        if !plan.wantsBonusFish, bonusFish?.isCarryingReward == true { bonusFish = nil }
        if plan.wantsHeartFish != previous.wantsHeartFish
            || plan.wantsBonusFish != previous.wantsBonusFish {
            tutorialFishDelay = (plan.wantsHeartFish || plan.wantsBonusFish)
                ? ReefConfig.tutorialFishArrival
                : nil
        }
    }

    /// Turns the step's unit target into a point in the open water: never under
    /// the HUD, never inside the coral, and always somewhere the fish can
    /// actually reach.
    private func updateTutorialTarget() {
        guard tutorialPlan.isActive,
              let unit = tutorialPlan.swimTarget,
              size.width > 0, spawnLine > topReserve else {
            if tutorialTarget != nil { tutorialTarget = nil }
            return
        }
        let top = topReserve + fishLength * 0.6
        let bottom = max(top, spawnLine - fishLength * 0.6)
        let point = CGPoint(x: size.width * CGFloat(unit.x),
                            y: top + (bottom - top) * CGFloat(unit.y))
        if tutorialTarget != point { tutorialTarget = point }
    }

    /// Reports the moment the fish arrives, which is what ends the step.
    private func checkTutorialTarget() {
        guard let target = tutorialTarget, entranceElapsed == nil else { return }
        let dx = target.x - fish.position.x
        let dy = target.y - fish.position.y
        let reach = fishLength * 0.55
        guard dx * dx + dy * dy <= reach * reach else { return }
        tutorialTarget = nil
        onTutorialEvent?(.reachedSwimTarget)
    }

    /// Puts the taught helper fish in the water, and puts it back whenever it
    /// crosses without being caught: a step ends because the player managed it,
    /// never because they were unlucky. It enters from the side the player is
    /// furthest from, so there is always a swim to make.
    private func spawnTutorialFishIfDue(_ dt: Double) {
        guard tutorialPlan.isActive,
              tutorialPlan.wantsHeartFish || tutorialPlan.wantsBonusFish,
              size.width > 0 else { return }
        // Only ever one of them, and never a second while the first is still
        // carrying its reward.
        guard heartFish?.isCarryingReward != true,
              bonusFish?.isCarryingReward != true else { return }

        guard var delay = tutorialFishDelay else {
            tutorialFishDelay = ReefConfig.tutorialFishArrival
            return
        }
        delay -= dt
        tutorialFishDelay = delay
        guard delay <= 0 else { return }
        tutorialFishDelay = nil

        let length = tutorialPlan.wantsHeartFish
            ? ReefConfig.heartFishLength(isPad: isPad)
            : ReefConfig.bonusFishLength(isPad: isPad)
        // Enter from the far side, so there is always a swim to make.
        let direction: CGFloat = fish.position.x > size.width / 2 ? 1 : -1
        let startX = direction > 0 ? -length : size.width + length
        let speed = CGFloat.random(in: tutorialPlan.wantsHeartFish
                                   ? ReefConfig.heartFishSpeed
                                   : ReefConfig.bonusFishSpeed)
        let y = tutorialFishLane(length: length)

        if tutorialPlan.wantsHeartFish {
            heartFish = ReefHeartFish(position: CGPoint(x: startX, y: y),
                                      direction: direction,
                                      speed: speed,
                                      length: length)
        } else {
            bonusFish = ReefBonusFish(position: CGPoint(x: startX, y: y),
                                      direction: direction,
                                      speed: speed,
                                      length: length)
        }
    }

    /// The height a taught helper fish crosses at. It clears the message card
    /// completely — a fish swimming behind it is one the player never sees —
    /// and stays well away from where the player is floating, so catching it is
    /// something they have to actually swim for.
    private func tutorialFishLane(length: CGFloat) -> CGFloat {
        // Half the drawn sprite, which is taller than the collision length.
        let halfSprite = length * 0.67
        let top = topReserve + ReefConfig.tutorialMessageReserve(isPad: isPad) + halfSprite
        let bottom = max(top, spawnLine - halfSprite - length * 0.2)
        guard bottom > top else { return top }

        let clearance = length * 1.15
        let lanes = [top...max(top, fish.position.y - clearance),
                     min(bottom, fish.position.y + clearance)...bottom]
            .filter { $0.upperBound - $0.lowerBound > length * 0.4 }
        // The roomiest side of the player, or — if there is no room either side
        // — simply the middle of the band.
        guard let lane = lanes.max(by: {
            ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound)
        }) else { return (top + bottom) / 2 }
        return CGFloat.random(in: lane)
    }

    func setScoreTarget(_ target: CGPoint?) {
        scoreTarget = target
    }

    /// Starts and stops the simulation itself. Everything freezes when the game
    /// is paused, covered or left.
    func setRunning(_ running: Bool) {
        if running {
#if canImport(UIKit)
            guard displayLink == nil else { return }
            lastFrameTargetTimestamp = nil
            let link = CADisplayLink(target: displayLinkTarget,
                                     selector: #selector(DisplayLinkTarget.advance(_:)))
            let maximumFPS = ReefPerformanceBudget.isConstrained
                ? 60
                : max(60, UIScreen.main.maximumFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: Float(maximumFPS),
                preferred: Float(maximumFPS)
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
#else
            guard timer == nil else { return }
            let timer = Timer(timeInterval: ReefConfig.tick, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(dt: ReefConfig.tick) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
#endif
        } else {
#if canImport(UIKit)
            displayLink?.invalidate()
            displayLink = nil
            lastFrameTargetTimestamp = nil
#else
            timer?.invalidate()
            timer = nil
#endif
            // A paused game is not being steered; the fish must not carry on
            // toward a target chosen before the pause.
            releaseTouch()
        }
    }

    /// Tears the scene down for good: no timer, no bubbles, nothing pending.
    func stop() {
        setRunning(false)
        bubbles.removeAll()
        collectedBubbles.removeAll()
        queue.removeAll()
        round = nil
        entranceElapsed = nil
        entranceCompletion = nil
        wakes.removeAll()
        bonusFish = nil
        heartFish = nil
        celebrationBubbles.removeAll()
        ambientBubbles.removeAll()
        completionElapsed = nil
        completionCallback = nil
        tutorialPlan = ReefTutorialPlan()
        tutorialTarget = nil
        tutorialFishDelay = nil
        onHit = nil
        onCollectedBubbleArrived = nil
        onBonusFishCaught = nil
        onHeartFishCaught = nil
        onHeartFishMissed = nil
        onTutorialEvent = nil
    }

    /// Sends the fish in from beyond the right edge along a tightening loop.
    /// Gameplay is deliberately started by the completion, not alongside it.
    func beginFishEntrance(completion: @escaping () -> Void) {
        guard size.width > 0, size.height > 0 else {
            completion()
            return
        }
        releaseTouch()
        entranceElapsed = 0
        entranceCompletion = completion
        entranceDidOpenRound = false
        wakeCountdown = 0
        fish.position = fishEntrancePosition(progress: 0)
        let firstStep = fishEntrancePosition(progress: 0.002)
        fish.heading = atan2(Double(firstStep.y - fish.position.y),
                             Double(firstStep.x - fish.position.x))
        fish.isSwimming = true
    }

    /// Takes control after the final answer. Normal answer bubbles disappear,
    /// the current fish gathers toward the heart's lower point and then traces
    /// the curve while air streams up from the same coral vents used in play.
    func beginLevelCompletion(reduceMotion: Bool, completion: @escaping () -> Void) {
        guard completionElapsed == nil else { return }
        releaseTouch()
        isLive = false
        bubbles.removeAll()
        bonusFish = nil
        heartFish = nil
        celebrationBubbles.removeAll()
        ambientBubbles.removeAll()
        completionStart = fish.position
        completionElapsed = 0
        completionCallback = completion
        completionBubbleCountdown = 0
        completionTrailCountdown = 0
        reducesCompletionMotion = reduceMotion
        fish.isSwimming = !reduceMotion
    }

    func endLevelCompletion() {
        completionElapsed = nil
        completionCallback = nil
        celebrationBubbles.removeAll()
        fish.isSwimming = false
    }

    // MARK: Steering

    /// The finger moved, or landed. The fish swims toward this point for as
    /// long as the touch lasts.
    func steer(toward point: CGPoint) {
        guard entranceElapsed == nil else { return }
        target = point
        coastVelocity = .zero
        fish.isSwimming = true
    }

    /// The finger left the glass. The fish coasts to a stop where it is: no new
    /// movement is started, and the last direction is not carried on.
    func releaseTouch() {
        target = nil
        coastVelocity = .zero
        fish.isSwimming = false
    }

    // MARK: Simulation

    #if canImport(UIKit)
    /// Uses the display's real presentation interval. This keeps motion at the
    /// same speed when a frame is late and lets ProMotion devices render the
    /// simulation at their native cadence instead of repeating every frame.
    private func advance(_ displayLink: CADisplayLink) {
        let target = displayLink.targetTimestamp
        let measured = lastFrameTargetTimestamp.map { target - $0 }
            ?? (target - displayLink.timestamp)
        lastFrameTargetTimestamp = target
        // Do not let a debugger stop or a transient system stall teleport an
        // answer through the fish. Normal 60/120 Hz intervals pass unchanged.
        tick(dt: min(max(measured, 1.0 / 120.0), 1.0 / 30.0))
    }
    #endif

    private func tick(dt: Double) {
        if completionElapsed != nil {
            moveMotes(dt)
            moveWakes(dt)
            moveCollectedBubbles(dt)
            moveLevelCompletion(dt)
            advanceClocks(dt)
            return
        }
        moveWakes(dt)
        let previousFishPosition = fish.position
        if entranceElapsed != nil {
            moveFishEntrance(dt)
        } else {
            moveFish(dt)
        }
        leaveWakeIfMoving(from: previousFishPosition, dt: dt)
        moveMotes(dt)
        moveAmbientBubbles(dt)
        spawnAmbientBubbleIfDue(dt)
        popAmbientBubblesTouchedByFish()
        moveBubbles(dt * speedMultiplier)
        moveCollectedBubbles(dt)
        retireMissedCorrectIfNeeded()
        moveBonusFish(dt)
        moveHeartFish(dt)
        if collisionCooldown > 0 { collisionCooldown = max(0, collisionCooldown - dt) }
        spawnBonusFishIfDue(dt)
        spawnHeartFishIfDue(dt)
        spawnTutorialFishIfDue(dt)
        checkTutorialTarget()
        if isLive, !tutorialPlan.suppressesAnswers {
            spawnIfDue(dt * speedMultiplier)
        }
        // The 2x fish remains catchable during answer feedback. Answer bubbles
        // still consult `isLive` below, so they retain their existing timing.
        // Nothing can be collected during the scripted entrance.
        if entranceElapsed == nil { checkCollisions() }
        // Publish only after every part of this frame has been simulated, so
        // SwiftUI observes one coherent scene rather than intermediate state.
        advanceClocks(dt)
    }

    /// Advances the frame clock and samples the two slower scenery clocks
    /// before publishing the completed frame.
    private func advanceClocks(_ dt: Double) {
        let nextClock = clock + dt
        swayClock = (nextClock / ReefConfig.swayInterval).rounded(.down)
            * ReefConfig.swayInterval
        driftClock = (nextClock / ReefConfig.driftInterval).rounded(.down)
            * ReefConfig.driftInterval
        // This is the one published write for the completed frame. The
        // scenery clocks above are sampled by the same render pass without
        // triggering two extra full playfield invalidations.
        clock = nextClock
    }

    // MARK: Level completion

    private func moveLevelCompletion(_ dt: Double) {
        guard let elapsed = completionElapsed else { return }
        let next = elapsed + dt
        let previous = fish.position

        // The completion path owns the fish. Do not consult the normal
        // steering flag here: setRunning(false) may clear it during the same
        // SwiftUI update in which the finale begins.
        if !reducesCompletionMotion {
            fish.isSwimming = true
            let gatherEnd = ReefConfig.completionGatherDuration
            if next < gatherEnd {
                let p = smoothstep(next / gatherEnd)
                fish.position = interpolate(completionStart, completionPathPoint(progress: 0), p)
            } else {
                let raw = (next - gatherEnd) / ReefConfig.completionHeartDuration
                let p = min(max(raw, 0), 1)
                if raw <= 1 {
                    fish.position = completionPathPoint(progress: p)
                } else {
                    let exitDuration = max(
                        0.001,
                        ReefConfig.completionDuration
                            - ReefConfig.completionGatherDuration
                            - ReefConfig.completionHeartDuration
                    )
                    let exitProgress = min((next - gatherEnd
                                            - ReefConfig.completionHeartDuration)
                                           / exitDuration, 1)
                    fish.position = completionExitPoint(progress: exitProgress)
                }
                completionTrailCountdown -= dt
                if completionTrailCountdown <= 0, raw < 1 {
                    completionTrailCountdown = ReefPerformanceBudget.completionTrailInterval
                    celebrationBubbles.append(ReefCelebrationBubble(
                        position: fish.position,
                        radius: CGFloat.random(in: isPad ? 4...8 : 3...6),
                        speed: CGFloat.random(in: 5...14),
                        phase: Double.random(in: 0..<(2 * .pi)),
                        kind: .trail
                    ))
                }
            }
            let dx = fish.position.x - previous.x
            let dy = fish.position.y - previous.y
            if abs(dx) + abs(dy) > 0.01 {
                fish.heading = atan2(Double(dy), Double(dx))
            }
        }

        if !reducesCompletionMotion {
            completionBubbleCountdown -= dt
            if completionBubbleCountdown <= 0 {
                completionBubbleCountdown = ReefPerformanceBudget.completionStreamInterval
                spawnCompletionStreamBubble()
            }
        }

        moveCelebrationBubbles(dt)
        completionElapsed = next
        let duration = reducesCompletionMotion ? 0.9 : ReefConfig.completionDuration
        if next >= duration {
            completionElapsed = nil
            fish.isSwimming = false
            let callback = completionCallback
            completionCallback = nil
            callback?()
        }
    }

    /// The user's loose single-stroke ribbon: up from the lower-left, around a
    /// broad top loop, across its own trail, and out through a curled lower
    /// tail. Six joined Bézier arcs preserve the hand-drawn character while
    /// matching tangents at every join keeps the fish's steering fluid.
    private func completionPathPoint(progress: Double) -> CGPoint {
        let openHeight = max(1, spawnLine - topReserve)
        let scale = min(size.width * 0.84 / 0.81, openHeight * 0.84 / 1.10)
        let centre = CGPoint(x: size.width / 2,
                             y: topReserve + openHeight * 0.51)

        let lowerLeft = CGPoint(x: -0.38, y: 0.43)
        let upperRight = CGPoint(x: 0.22, y: -0.43)
        let upperLeft = CGPoint(x: -0.12, y: -0.48)
        let loopExit = CGPoint(x: -0.32, y: 0.02)
        let lowerRight = CGPoint(x: 0.20, y: 0.16)
        let lowerBend = CGPoint(x: 0.24, y: 0.44)
        let tail = CGPoint(x: 0.43, y: 0.39)
        let segments: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
            (lowerLeft, CGPoint(x: -0.28, y: 0.25),
             CGPoint(x: 0.15, y: -0.27), upperRight),
            (upperRight, CGPoint(x: 0.30, y: -0.58),
             CGPoint(x: -0.02, y: -0.56), upperLeft),
            (upperLeft, CGPoint(x: -0.22, y: -0.40),
             CGPoint(x: -0.39, y: -0.09), loopExit),
            (loopExit, CGPoint(x: -0.25, y: 0.13),
             CGPoint(x: 0.10, y: 0.08), lowerRight),
            (lowerRight, CGPoint(x: 0.30, y: 0.24),
             CGPoint(x: 0.23, y: 0.36), lowerBend),
            (lowerBend, CGPoint(x: 0.25, y: 0.52),
             CGPoint(x: 0.36, y: 0.42), tail)
        ]

        let point = pointAlongBezierPath(segments, progress: progress)
        return CGPoint(x: centre.x + point.x * scale,
                       y: centre.y + point.y * scale)
    }

    /// Carries the fish beyond the right edge along the final Bézier tangent.
    /// A linear continuation preserves its swimming speed and heading, avoiding
    /// the pause that previously followed the completed heart stroke.
    private func completionExitPoint(progress: Double) -> CGPoint {
        let start = completionPathPoint(progress: 1)
        let direction = CGVector(dx: 0.07, dy: -0.03)
        let length = max(0.001, hypot(direction.dx, direction.dy))
        let unit = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let requiredX = size.width + fishArtworkWidth * 0.65
        let distance = max(fishArtworkWidth, (requiredX - start.x) / max(0.001, unit.dx))
        let p = CGFloat(min(max(progress, 0), 1))
        return CGPoint(x: start.x + unit.dx * distance * p,
                       y: start.y + unit.dy * distance * p)
    }

    /// Maps time to approximate distance rather than assigning every segment
    /// equal time. Short curls and long diagonals are therefore swum at the
    /// same apparent speed.
    private func pointAlongBezierPath(
        _ segments: [(CGPoint, CGPoint, CGPoint, CGPoint)],
        progress: Double
    ) -> CGPoint {
        let samplesPerSegment = 10
        let lengths = segments.map { segment in
            var length: CGFloat = 0
            var previous = segment.0
            for sample in 1...samplesPerSegment {
                let point = cubicBezier(from: segment.0, control1: segment.1,
                                        control2: segment.2, to: segment.3,
                                        t: CGFloat(sample) / CGFloat(samplesPerSegment))
                length += hypot(point.x - previous.x, point.y - previous.y)
                previous = point
            }
            return length
        }
        let total = max(0.001, lengths.reduce(0, +))
        var remaining = CGFloat(min(max(progress, 0), 1)) * total
        for (index, length) in lengths.enumerated() {
            if remaining <= length || index == segments.count - 1 {
                let t = length > 0 ? min(1, remaining / length) : 0
                let segment = segments[index]
                return cubicBezier(from: segment.0, control1: segment.1,
                                   control2: segment.2, to: segment.3, t: t)
            }
            remaining -= length
        }
        return segments.last?.3 ?? .zero
    }

    private func cubicBezier(from start: CGPoint, control1: CGPoint,
                             control2: CGPoint, to end: CGPoint,
                             t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        let a = inverse * inverse * inverse
        let b = 3 * inverse * inverse * t
        let c = 3 * inverse * t * t
        let d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                       y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }

    private func spawnCompletionStreamBubble() {
        let vents = ReefConfig.craterPositions(width: size.width, isPad: isPad)
        guard let x = vents.randomElement() else { return }
        celebrationBubbles.append(ReefCelebrationBubble(
            position: CGPoint(x: x + CGFloat.random(in: -8...8), y: spawnLine + 8),
            radius: CGFloat.random(in: isPad ? 5...15 : 4...11),
            speed: CGFloat.random(in: 90...190),
            phase: Double.random(in: 0..<(2 * .pi)),
            kind: .stream
        ))
    }

    private func moveCelebrationBubbles(_ dt: Double) {
        for index in celebrationBubbles.indices {
            celebrationBubbles[index].age += dt
            switch celebrationBubbles[index].kind {
            case .stream, .trail:
                celebrationBubbles[index].position.y -= celebrationBubbles[index].speed * CGFloat(dt)
                celebrationBubbles[index].position.x += CGFloat(sin(
                    celebrationBubbles[index].age * 3 + celebrationBubbles[index].phase
                )) * CGFloat(dt) * 9
            }
        }
        celebrationBubbles.removeAll {
            $0.position.y < -$0.radius * 2
        }
    }

    private func smoothstep(_ value: Double) -> CGFloat {
        let t = min(max(value, 0), 1)
        return CGFloat(t * t * (3 - 2 * t))
    }

    private func interpolate(_ from: CGPoint, _ to: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * amount,
                y: from.y + (to.y - from.y) * amount)
    }

    // MARK: Fish

    private func moveFishEntrance(_ dt: Double) {
        guard let elapsed = entranceElapsed else { return }
        let nextElapsed = min(ReefConfig.fishEntranceDuration, elapsed + dt)
        let progress = nextElapsed / ReefConfig.fishEntranceDuration
        let previous = fish.position
        let next = fishEntrancePosition(progress: progress)

        fish.position = next
        let dx = next.x - previous.x
        let dy = next.y - previous.y
        if abs(dx) + abs(dy) > 0.01 {
            // The scripted path already has smooth curvature; following its
            // tangent exactly prevents the artwork from visibly lagging behind
            // the tight inner part of the spiral.
            fish.heading = atan2(Double(dy), Double(dx))
        }

        if !entranceDidOpenRound,
           nextElapsed >= ReefConfig.fishEntranceDuration - ReefConfig.fishEntranceAnswerLead {
            entranceDidOpenRound = true
            let completion = entranceCompletion
            entranceCompletion = nil
            completion?()
        }

        if progress >= 1 {
            entranceElapsed = nil
            let speed = min(CGFloat(165), (dx * dx + dy * dy).squareRoot() / CGFloat(dt))
            let distance = max(0.001, (dx * dx + dy * dy).squareRoot())
            coastVelocity = CGPoint(x: dx / distance * speed,
                                    y: dy / distance * speed)
            fish.isSwimming = true
            // Normally delivered during the last arc, but keep a fallback so
            // an extreme timing or future tuning change can never stall play.
            if !entranceDidOpenRound {
                entranceDidOpenRound = true
                let completion = entranceCompletion
                entranceCompletion = nil
                completion?()
            }
        } else {
            entranceElapsed = nextElapsed
        }
    }

    /// One continuous inward spiral, matching the broad hand-drawn loop: it
    /// enters at the right, sweeps around the whole playfield, then curls into
    /// the middle without a join or sudden change in curvature.
    private func fishEntrancePosition(progress: Double) -> CGPoint {
        let t = CGFloat(min(max(progress, 0), 1))
        let centre = fishEntranceCentre
        let outsideX = size.width + fishLength * 0.9
        let outerRadius = outsideX - centre.x
        let innerRadius = fishLength * 0.36
        let radius = outerRadius + (innerRadius - outerRadius) * t
        // One and a quarter turns place the endpoint just below centre, with
        // its tangent pointing naturally forward and to the left.
        let angle = 2.5 * .pi * t
        return CGPoint(x: centre.x + radius * cos(angle),
                       y: centre.y + radius * sin(angle))
    }

    private var fishEntranceCentre: CGPoint {
        CGPoint(x: size.width / 2,
                y: topReserve + max(0, spawnLine - topReserve) * 0.48)
    }

    // MARK: Wake

    private func leaveWakeIfMoving(from previous: CGPoint, dt: Double) {
        wakeCountdown -= dt
        let dx = fish.position.x - previous.x
        let dy = fish.position.y - previous.y
        guard dx * dx + dy * dy > 0.7, wakeCountdown <= 0 else {
            leaveIdleBreathIfDue(dt)
            return
        }
        idleBreathCountdown = Double.random(in: ReefConfig.idleBreathGap)
        wakeCountdown = ReefConfig.wakeInterval

        let speed = (dx * dx + dy * dy).squareRoot() / max(CGFloat(dt), 0.001)
        let strength = min(max(speed / 360, 0.55), 1.15)
        // How hard the player is actually driving, 0 at a crawl and 1 at full
        // tilt. Everything below scales with it, so the water reacts to the
        // steering instead of ticking over at a constant rate.
        let effort = min(max((speed - 40) / 420, 0), 1)
        let tailDistance = fishLength * 0.43
        let cosHeading = CGFloat(cos(fish.heading))
        let sinHeading = CGFloat(sin(fish.heading))

        func tailPoint(side: CGFloat, spread: CGFloat) -> CGPoint {
            let perpendicular = fishLength * spread * side
            return CGPoint(
                x: fish.position.x - cosHeading * tailDistance - sinHeading * perpendicular,
                y: fish.position.y - sinHeading * tailDistance + cosHeading * perpendicular
            )
        }

        // Water is pushed mostly sideways by the tail, with only a small
        // backward component. The wisp then slows in place instead of
        // expanding like a ring on the surface.
        func shedWisp(side: CGFloat, spread: CGFloat, scale: CGFloat) {
            let lateralSpeed = CGFloat(24) * strength * side
            let backwardSpeed = CGFloat(8) * strength
            wakes.append(ReefWake(position: tailPoint(side: side, spread: spread),
                                  radius: fishLength * 0.10 * strength * scale,
                                  kind: .wisp,
                                  heading: fish.heading,
                                  side: side,
                                  velocity: CGPoint(
                                    x: -cosHeading * backwardSpeed - sinHeading * lateralSpeed,
                                    y: -sinHeading * backwardSpeed + cosHeading * lateralSpeed
                                  )))
        }

        let side = wakeSide
        // A little jitter on every streak. Without it a steady finger produces
        // a perfectly regular zig-zag, which is exactly what makes a trail
        // read as a drawn pattern rather than as disturbed water.
        shedWisp(side: side,
                 spread: CGFloat.random(in: 0.055...0.105),
                 scale: CGFloat.random(in: 0.85...1.2))
        // Hard steering throws a second, shorter streak off the other side of
        // the tail. At a drift only the single one appears, so the density of
        // the trail is itself a readout of how fast the player is going.
        if effort > 0.35, !ReefPerformanceBudget.isConstrained {
            shedWisp(side: -side,
                     spread: CGFloat.random(in: 0.16...0.24),
                     scale: (0.62 + 0.3 * effort) * CGFloat.random(in: 0.85...1.15))
        }

        // A sparse, uneven bubble trail reads as trapped air. Emitting one on
        // two out of every three tail beats avoids a foamy motorboat wake;
        // pushing hard adds an extra, larger pocket on the same beat.
        if wakeEmissionIndex % 3 != 2 {
            let sizeStep = CGFloat(wakeEmissionIndex % 3) * 0.006
            let bubbleSide = side * fishLength * 0.035
            let tail = tailPoint(side: side, spread: 0.075)
            wakes.append(ReefWake(
                position: CGPoint(x: tail.x - sinHeading * bubbleSide,
                                  y: tail.y + cosHeading * bubbleSide),
                radius: fishLength * (0.020 + sizeStep) * (0.85 + 0.5 * effort),
                kind: .bubble,
                heading: fish.heading,
                side: side,
                velocity: CGPoint(x: -cosHeading * 5 - sinHeading * side * 3,
                                  y: -sinHeading * 5 - 13)
            ))
        }
        if effort > 0.55,
           wakeEmissionIndex.isMultiple(of: 2),
           !ReefPerformanceBudget.isConstrained {
            let tail = tailPoint(side: -side, spread: 0.16)
            wakes.append(ReefWake(
                position: tail,
                radius: fishLength * 0.030 * (0.7 + 0.6 * effort),
                kind: .bubble,
                heading: fish.heading,
                side: -side,
                velocity: CGPoint(x: -cosHeading * 9 + sinHeading * side * 4,
                                  y: -sinHeading * 9 - 17)
            ))
        }
        wakeEmissionIndex += 1
        wakeSide *= -1
    }

    /// A single small bubble every second or so while the player is holding
    /// still. Just enough that a resting character is breathing rather than
    /// parked — and far too sparse to read as a permanent decoration.
    private func leaveIdleBreathIfDue(_ dt: Double) {
        idleBreathCountdown -= dt
        guard idleBreathCountdown <= 0, size.width > 0 else { return }
        idleBreathCountdown = Double.random(in: ReefConfig.idleBreathGap)

        let cosHeading = CGFloat(cos(fish.heading))
        let sinHeading = CGFloat(sin(fish.heading))
        // Out of the mouth, at the front of the body.
        let snout = CGPoint(
            x: fish.position.x + cosHeading * fishLength * 0.34,
            y: fish.position.y + sinHeading * fishLength * 0.34 - fishLength * 0.06
        )
        wakes.append(ReefWake(
            position: snout,
            radius: fishLength * CGFloat.random(in: 0.016...0.030),
            kind: .bubble,
            heading: fish.heading,
            side: 1,
            velocity: CGPoint(x: CGFloat.random(in: -4...4), y: -16)
        ))
    }

    private func moveWakes(_ dt: Double) {
        for index in wakes.indices {
            wakes[index].age += dt
            let step = CGFloat(dt)
            wakes[index].position.x += wakes[index].velocity.x * step
            wakes[index].position.y += wakes[index].velocity.y * step

            switch wakes[index].kind {
            case .bubble:
                // Buoyancy gradually wins over the small amount of momentum
                // inherited from the fish; a tiny sideways meander prevents a
                // mechanically straight dotted line.
                wakes[index].velocity.y -= 5 * step
                wakes[index].position.x += CGFloat(sin(wakes[index].age * 7
                                                       + Double(wakes[index].side))) * step * 2.2
            case .wisp:
                let damping = CGFloat(pow(0.09, dt))
                wakes[index].velocity.x *= damping
                wakes[index].velocity.y *= damping
            }
        }
        wakes.removeAll { $0.age >= $0.lifetime }
    }

    private func moveFish(_ dt: Double) {
        guard fish.isSwimming else { return }
        guard let target else {
            moveCoastingFish(dt)
            return
        }
        let dx = target.x - fish.position.x
        let dy = target.y - fish.position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > ReefConfig.fishDeadzone else {
            fish.isSwimming = false
            return
        }

        // Speed falls off as the fish arrives, which is what makes small
        // corrections precise without the whole motion feeling nervous.
        let speed = min(ReefConfig.fishMaximumSpeed, distance * ReefConfig.fishApproach)
        let step = min(distance, speed * CGFloat(dt))
        let moved = CGPoint(x: fish.position.x + dx / distance * step,
                            y: fish.position.y + dy / distance * step)
        fish.position = clampedFishPosition(moved)
        turn(toward: atan2(Double(dy), Double(dx)), dt: dt)
    }

    private func moveCoastingFish(_ dt: Double) {
        let speed = (coastVelocity.x * coastVelocity.x
                     + coastVelocity.y * coastVelocity.y).squareRoot()
        guard speed > 5 else {
            coastVelocity = .zero
            fish.isSwimming = false
            return
        }

        let proposed = CGPoint(x: fish.position.x + coastVelocity.x * CGFloat(dt),
                               y: fish.position.y + coastVelocity.y * CGFloat(dt))
        let moved = clampedFishPosition(proposed)
        if abs(moved.x - fish.position.x) + abs(moved.y - fish.position.y) < 0.01 {
            coastVelocity = .zero
            fish.isSwimming = false
            return
        }
        fish.position = moved
        fish.heading = atan2(Double(coastVelocity.y), Double(coastVelocity.x))
        let damping = CGFloat(pow(0.20, dt))
        coastVelocity.x *= damping
        coastVelocity.y *= damping
    }

    /// Swings the fish round the short way, so crossing from just under π to
    /// just over −π does not spin it all the way about.
    private func turn(toward angle: Double, dt: Double) {
        var delta = angle - fish.heading
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        fish.heading += delta * min(1, ReefConfig.fishTurnRate * dt)
    }

    /// The fish stays in open water: inside the sides, below the top edge and
    /// above the coral, so it can never cover the sum.
    private func clampedFishPosition(_ point: CGPoint) -> CGPoint {
        let radius = fishLength * 0.5
        let minX = radius * 0.6
        let maxX = max(minX, size.width - radius * 0.6)
        let minY = topReserve + radius * 0.6
        let maxY = max(minY, spawnLine - 4)
        return CGPoint(x: min(max(point.x, minX), maxX),
                       y: min(max(point.y, minY), maxY))
    }

    // MARK: Ambience

    /// The specks rise slowly and start again from the sea floor, so the water
    /// is never still.
    private func moveMotes(_ dt: Double) {
        guard size.height > 0 else { return }
        for index in motes.indices {
            motes[index].age += dt
            var mote = motes[index]
            mote.position.y -= mote.speed * CGFloat(dt)
            let sway = sin(mote.age * 2 * .pi / mote.period + mote.phase)
            mote.position.x = mote.baseX + mote.sway * CGFloat(sway)
            if mote.position.y < -mote.radius {
                mote.position.y = size.height + mote.radius
            }
            motes[index] = mote
        }
    }

    private func spawnAmbientBubbleIfDue(_ dt: Double) {
        ambientBubbleCountdown -= dt
        guard ambientBubbleCountdown <= 0 else { return }
        ambientBubbleCountdown = Double.random(in: ReefConfig.ambientBubbleGap)
        guard ambientBubbles.count < ReefConfig.maximumAmbientBubbles,
              size.width > 0, spawnLine > topReserve else { return }

        let inset = ReefConfig.sideInset(isPad: isPad) + ReefConfig.ambientBubbleRadius.upperBound
        let x = CGFloat.random(in: inset...max(inset, size.width - inset))
        ambientBubbles.append(ReefAmbientBubble(
            baseX: x,
            position: CGPoint(x: x, y: spawnLine + CGFloat.random(in: 2...18)),
            radius: CGFloat.random(in: ReefConfig.ambientBubbleRadius),
            speed: CGFloat.random(in: ReefConfig.ambientBubbleSpeed),
            phase: Double.random(in: 0..<(2 * .pi))
        ))
    }

    private func moveAmbientBubbles(_ dt: Double) {
        for index in ambientBubbles.indices {
            ambientBubbles[index].age += dt
            if ambientBubbles[index].popAge != nil {
                ambientBubbles[index].popAge! += dt
                continue
            }
            ambientBubbles[index].position.y -= ambientBubbles[index].speed * CGFloat(dt)
            ambientBubbles[index].position.x = ambientBubbles[index].baseX
                + CGFloat(sin(ambientBubbles[index].age * 2.4
                              + ambientBubbles[index].phase)) * 8
        }
        ambientBubbles.removeAll { bubble in
            if let popAge = bubble.popAge {
                return popAge >= ReefConfig.ambientBubblePopDuration
            }
            return bubble.position.y < -bubble.radius * 2
        }
    }

    private func popAmbientBubblesTouchedByFish() {
        let fishRadius = fishLength * ReefConfig.fishHitFactor
        for index in ambientBubbles.indices where ambientBubbles[index].popAge == nil {
            let bubble = ambientBubbles[index]
            guard bubble.age > 0.12 else { continue }
            let dx = bubble.position.x - fish.position.x
            let dy = bubble.position.y - fish.position.y
            let hitRadius = fishRadius + bubble.radius
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                ambientBubbles[index].popAge = 0
            }
        }
    }

    // MARK: Bubbles

    private func moveBubbles(_ dt: Double) {
        for index in bubbles.indices {
            bubbles[index].age += dt
            if bubbles[index].popAge != nil {
                bubbles[index].popAge! += dt
                continue
            }
            var bubble = bubbles[index]
            let slowdownStart = ReefConfig.launchHoldDuration
            let slowdownDuration = ReefConfig.launchSlowdownDuration
            let currentSpeed: CGFloat
            if bubble.age <= slowdownStart {
                currentSpeed = bubble.launchSpeed
            } else if bubble.age < slowdownStart + slowdownDuration {
                let raw = (bubble.age - slowdownStart) / slowdownDuration
                let t = CGFloat(raw * raw * (3 - 2 * raw))
                currentSpeed = bubble.launchSpeed
                    + (bubble.speed - bubble.launchSpeed) * t
            } else {
                currentSpeed = bubble.speed
            }
            bubble.position.y -= currentSpeed * CGFloat(dt)
            let sway = sin(bubble.age * 2 * .pi / bubble.driftPeriod + bubble.phase)
            // The sway must never carry an answer off the side of the screen:
            // a half-visible number is not a readable one.
            let radius = bubble.diameter / 2
            let limit = max(radius, size.width - radius)
            bubble.position.x = min(max(bubble.baseX + bubble.driftAmplitude * CGFloat(sway),
                                        radius), limit)
            bubbles[index] = bubble
        }
        // A wrong answer that was never touched leaves as soon as its complete
        // circle is above the screen. Keeping an already invisible bubble alive
        // would unnecessarily block a replacement from the next wave.
        bubbles.removeAll { bubble in
            if let popAge = bubble.popAge { return popAge >= ReefConfig.popDuration }
            return bubble.position.y < -bubble.diameter / 2
        }
    }

    private func moveCollectedBubbles(_ dt: Double) {
        for index in collectedBubbles.indices {
            collectedBubbles[index].age += dt
            let raw = min(1, collectedBubbles[index].age / ReefConfig.collectedBubbleDuration)
            // A smooth climb reads as buoyancy: it leaves the tail gently and
            // settles without snapping when it reaches the score bubble.
            let t = CGFloat(raw * raw * (3 - 2 * raw))
            let bubble = collectedBubbles[index]
            collectedBubbles[index].position = cubicPoint(from: bubble.start,
                                                            control1: bubble.firstControl,
                                                            control2: bubble.secondControl,
                                                            to: bubble.target,
                                                            t: t)
        }
        let arrivedCount = collectedBubbles.reduce(into: 0) { count, bubble in
            if bubble.age >= ReefConfig.collectedBubbleDuration { count += 1 }
        }
        collectedBubbles.removeAll { $0.age >= ReefConfig.collectedBubbleDuration }
        for _ in 0..<arrivedCount { onCollectedBubbleArrived?() }
    }

    private func cubicPoint(from start: CGPoint, control1: CGPoint,
                            control2: CGPoint, to end: CGPoint,
                            t: CGFloat) -> CGPoint {
        let remaining = 1 - t
        let a = remaining * remaining * remaining
        let b = 3 * remaining * remaining * t
        let c = 3 * remaining * t * t
        let d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                       y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }

    /// Retires an unanswered correct bubble at the exact point where the fish
    /// can no longer reach it. Its replacement is put first in the queue, so a
    /// miss costs a brief beat but never a long wait for four unrelated answers
    /// to clear. Popping the old one first preserves one visible correct answer.
    private func retireMissedCorrectIfNeeded() {
        guard isLive,
              let index = bubbles.firstIndex(where: {
                  !$0.isPopping && $0.isCorrect
                      && $0.position.y <= topReserve
                          - $0.diameter * ReefConfig.missedCorrectTopFactor
              })
        else { return }

        bubbles[index].popAge = 0
        if let correctAnswer = round?.options.first(where: \.isCorrect) {
            queue.removeAll { $0.id == correctAnswer.id }
            queue.insert(correctAnswer, at: 0)
        }
        timeToNextSpawn = Double.random(in: ReefConfig.missedCorrectRetryGap)
    }

    private func spawnIfDue(_ dt: Double) {
        guard round != nil, size.width > 0 else { return }
        timeToNextSpawn -= dt
        guard timeToNextSpawn <= 0 else { return }

        if queue.isEmpty { refillQueue() }
        guard !queue.isEmpty else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }

        let live = bubbles.filter { !$0.isPopping }
        guard live.count < ReefConfig.maximumLiveBubbles else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }
        // The same answer is never in the water twice: two identical bubbles
        // would read as two right answers.
        let liveIDs = Set(live.map(\.optionID))
        guard let index = queue.firstIndex(where: { !liveIDs.contains($0.id) }) else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }
        guard let x = freeVentX(avoiding: live) else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }

        let option = queue.remove(at: index)
        bubbles.append(makeBubble(for: option, at: x))
        lastVentX = x
        // The wave that just emptied gets a longer pause than the beats inside
        // it, so the set reads as a set.
        if queue.isEmpty {
            timeToNextSpawn = Double.random(in: ReefConfig.waveGap)
        } else if Double.random(in: 0..<1) < ReefConfig.closeGapChance {
            timeToNextSpawn = Double.random(in: ReefConfig.closeGap)
        } else {
            timeToNextSpawn = Double.random(in: ReefConfig.spawnGap)
        }
    }

    /// The coral keeps offering the same set of answers for as long as the sum
    /// stands, in a fresh order each time, so a missed right answer always
    /// comes back around.
    private func refillQueue() {
        guard let round else { return }
        if let wave = tutorialPlan.answers, tutorialPlan.isActive {
            queue = tutorialWave(wave, from: round)
            return
        }
        var wrongAnswers = round.options.filter { !$0.isCorrect }.shuffled()
        guard let correctAnswer = round.options.first(where: \.isCorrect) else {
            queue = wrongAnswers
            return
        }

        let positionCount = wrongAnswers.count + 1
        let weights = Array(ReefConfig.correctAnswerPositionWeights.prefix(positionCount))
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            queue = wrongAnswers
            queue.insert(correctAnswer, at: 0)
            return
        }

        var draw = Int.random(in: 0..<totalWeight)
        var correctPosition = 0
        for (position, weight) in weights.enumerated() {
            if draw < weight {
                correctPosition = position
                break
            }
            draw -= weight
        }

        wrongAnswers.insert(correctAnswer,
                            at: min(correctPosition, wrongAnswers.endIndex))
        queue = wrongAnswers
    }

    /// The exact set of answers a tutorial step wants released, in a fresh
    /// order each wave. A step can ask for fewer answers than a round holds —
    /// never for more, since the same number may not be in the water twice.
    private func tutorialWave(_ wave: ReefTutorialPlan.Wave,
                              from round: GameRound) -> [AnswerOption] {
        var picks: [AnswerOption] = []
        if wave.correct > 0, let correct = round.options.first(where: \.isCorrect) {
            picks.append(correct)
        }
        picks += round.options.filter { !$0.isCorrect }.shuffled().prefix(wave.wrong)
        return picks.shuffled()
    }

    private func makeBubble(for option: AnswerOption, at x: CGFloat) -> ReefBubble {
        ReefBubble(optionID: option.id,
                   text: option.text,
                   isCorrect: option.isCorrect,
                   diameter: diameter,
                   baseX: x,
                   position: CGPoint(x: x, y: spawnLine + diameter * 0.22),
                   launchSpeed: diameter * CGFloat.random(in: ReefConfig.launchSpeedFactor),
                   speed: CGFloat.random(in: ReefConfig.riseSpeed),
                   driftAmplitude: CGFloat.random(in: ReefConfig.driftAmplitude),
                   driftPeriod: Double.random(in: ReefConfig.driftPeriod),
                   phase: Double.random(in: 0..<(2 * .pi)))
    }

    /// Picks a crater with room above it. Bubbles still close to the coral are
    /// what matter: keeping clear of those is what stops them overlapping, and
    /// what keeps a route open to every answer.
    private func freeVentX(avoiding live: [ReefBubble]) -> CGFloat? {
        let craters = ReefConfig.craterPositions(width: size.width, isPad: isPad)
        guard !craters.isEmpty else { return nil }

        let separation = diameter * ReefConfig.separationFactor
        let band = spawnLine - diameter * ReefConfig.crowdBandFactor
        let blockers = live.filter { $0.position.y > band }.map(\.position.x)

        let clear = craters.filter { crater in
            blockers.allSatisfy { abs($0 - crater) >= separation }
        }
        guard !clear.isEmpty else { return nil }

        // Prefer a different crater from the last one; fall back if that is the
        // only room left rather than skipping the release altogether.
        if let lastVentX {
            let spread = diameter * ReefConfig.ventSpreadFactor
            let apart = clear.filter { abs($0 - lastVentX) >= spread }
            if let pick = apart.randomElement() { return pick }
        }
        return clear.randomElement()
    }

    // MARK: Collisions

    private func checkCollisions() {
        guard collisionCooldown == 0 else { return }
        let fishRadius = fishLength * ReefConfig.fishHitFactor

        if let bonusFish, bonusFish.isCarryingReward, !hasBonusAura {
            let dx = bonusFish.position.x - fish.position.x
            let dy = bonusFish.position.y - fish.position.y
            let hitRadius = fishRadius + bonusFish.length * 0.48
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                self.bonusFish?.isCarryingReward = false
                hasBonusAura = true
                collisionCooldown = ReefConfig.collisionCooldown
                onBonusFishCaught?()
                onTutorialEvent?(.caughtBonusFish)
                return
            }
        }

        if let heartFish, heartFish.isCarryingReward {
            let dx = heartFish.position.x - fish.position.x
            let dy = heartFish.position.y - fish.position.y
            let hitRadius = fishRadius + heartFish.length * 0.48
            if dx * dx + dy * dy <= hitRadius * hitRadius,
               onHeartFishCaught?() == true {
                self.heartFish?.isCarryingReward = false
                isHeartFishAvailable = false
                heartFishDelay = nil
                collisionCooldown = ReefConfig.collisionCooldown
                onTutorialEvent?(.caughtHeartFish)
                return
            }
        }

        guard isLive else { return }
        for bubble in bubbles where !bubble.isPopping {
            // A bubble must be full-size and visibly clear of the coral. The
            // launch gets it there quickly, but the player cannot camp on a
            // crater and collect an answer the instant it appears.
            guard bubble.emergence >= 1 else { continue }
            let releaseY = spawnLine + bubble.diameter * 0.22
            let risen = releaseY - bubble.position.y
            guard risen >= bubble.diameter * ReefConfig.minimumCatchRiseFactor else {
                continue
            }
            let radius = bubble.diameter * ReefConfig.bubbleHitFactor
            let dx = bubble.position.x - fish.position.x
            let dy = bubble.position.y - fish.position.y
            let hitRadius = radius + fishRadius
            guard dx * dx + dy * dy <= hitRadius * hitRadius else { continue }

            // The session has the final say. If it does not take the answer —
            // feedback still playing, round already resolved — nothing happens.
            guard onHit?(bubble.optionID) == true else { return }
            collisionCooldown = ReefConfig.collisionCooldown
            // A right answer clears the water; the sum is about to change.
            if bubble.isCorrect {
                collectCorrectBubble(bubble)
                popAllAnswerBubbles()
            } else if tutorialPlan.burstsWaveOnWrong {
                // The step that teaches what a wrong answer costs bursts the
                // whole set, so the price is unmistakable.
                popAllAnswerBubbles()
            } else {
                pop(bubbleID: bubble.id)
            }
            return
        }
    }

    // MARK: 2x fish

    private func spawnBonusFishIfDue(_ dt: Double) {
        // While the walkthrough is running, the only helper fish in the water
        // is the one the current step put there.
        guard !tutorialPlan.isActive,
              bonusFish == nil,
              heartFish == nil,
              !hasBonusAura,
              !pendingBonusFishDelays.isEmpty,
              size.width > 0 else { return }
        pendingBonusFishDelays[0] -= dt
        guard pendingBonusFishDelays[0] <= 0 else { return }

        let length = ReefConfig.bonusFishLength(isPad: isPad)
        let direction: CGFloat = Bool.random() ? 1 : -1
        let startX = direction > 0 ? -length : size.width + length
        let minY = topReserve + length
        let maxY = max(minY, spawnLine - length * 0.8)
        bonusFish = ReefBonusFish(position: CGPoint(x: startX,
                                                    y: CGFloat.random(in: minY...maxY)),
                                  direction: direction,
                                  speed: CGFloat.random(in: ReefConfig.bonusFishSpeed),
                                  length: length)
        pendingBonusFishDelays.removeFirst()
    }

    private func moveBonusFish(_ dt: Double) {
        guard var swimmer = bonusFish else { return }
        swimmer.position.x += swimmer.direction * swimmer.speed * CGFloat(dt)
        // The fish starts a full body-length outside the entry edge. Only the
        // opposite edge may remove it; checking both edges made every new fish
        // disappear again before its nose could enter the screen.
        let hasLeftScreen = swimmer.direction > 0
            ? swimmer.position.x > size.width + swimmer.length
            : swimmer.position.x < -swimmer.length
        if hasLeftScreen {
            bonusFish = nil
            // The step that is teaching this fish sends it round again rather
            // than letting a miss end the lesson.
            if swimmer.isCarryingReward, tutorialPlan.wantsBonusFish {
                tutorialFishDelay = ReefConfig.tutorialFishArrival
            }
        } else {
            bonusFish = swimmer
        }
    }

    // MARK: Heart fish

    private func spawnHeartFishIfDue(_ dt: Double) {
        guard !tutorialPlan.isActive,
              heartFish == nil,
              bonusFish == nil,
              isHeartFishAvailable,
              var delay = heartFishDelay,
              size.width > 0 else { return }
        delay -= dt
        heartFishDelay = delay
        guard delay <= 0 else { return }

        let length = ReefConfig.heartFishLength(isPad: isPad)
        let direction: CGFloat = Bool.random() ? 1 : -1
        let startX = direction > 0 ? -length : size.width + length
        let minY = topReserve + length
        let maxY = max(minY, spawnLine - length * 0.8)
        heartFish = ReefHeartFish(position: CGPoint(x: startX,
                                                    y: CGFloat.random(in: minY...maxY)),
                                  direction: direction,
                                  speed: CGFloat.random(in: ReefConfig.heartFishSpeed),
                                  length: length)
        heartFishDelay = nil
    }

    private func moveHeartFish(_ dt: Double) {
        guard var swimmer = heartFish else { return }
        swimmer.position.x += swimmer.direction * swimmer.speed * CGFloat(dt)
        let hasLeftScreen = swimmer.direction > 0
            ? swimmer.position.x > size.width + swimmer.length
            : swimmer.position.x < -swimmer.length
        if hasLeftScreen {
            heartFish = nil
            guard swimmer.isCarryingReward else { return }
            // In the walkthrough the fish simply comes back: its step is not
            // over until the player has actually caught one.
            if tutorialPlan.wantsHeartFish {
                tutorialFishDelay = ReefConfig.tutorialFishArrival
                return
            }
            isHeartFishAvailable = false
            heartFishDelay = nil
            onHeartFishMissed?()
        } else {
            heartFish = swimmer
        }
    }

    private func pop(bubbleID: UUID) {
        guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        bubbles[index].popAge = 0
    }

    private func collectCorrectBubble(_ bubble: ReefBubble) {
        let heading = CGFloat(fish.heading)
        let backward = CGVector(dx: -cos(heading), dy: -sin(heading))
        let side = CGVector(dx: -sin(heading), dy: cos(heading))
        // Exactly the HUD glyph's size at arrival; both use CurrencyIcon, so
        // the moving and stationary silhouettes become one clean overlay.
        let scoreDiameter: CGFloat = isPad ? 34 : 26
        let tailDistance = fishArtworkWidth * 0.52 + scoreDiameter * 0.18
        let start = CGPoint(x: fish.position.x + backward.dx * tailDistance,
                            y: fish.position.y + backward.dy * tailDistance)
        let target = scoreTarget ?? CGPoint(x: size.width / 2,
                                            y: max(scoreDiameter / 2, topReserve - 20))
        let firstControl = CGPoint(
            x: start.x + backward.dx * fishArtworkWidth * 0.32 + side.dx * scoreDiameter * 0.18,
            y: start.y + backward.dy * fishArtworkWidth * 0.32 + side.dy * scoreDiameter * 0.18
        )
        let secondControl = CGPoint(x: target.x + (start.x - target.x) * 0.24,
                                    y: start.y + (target.y - start.y) * 0.72)

        collectedBubbles.append(ReefCollectedBubble(diameter: scoreDiameter,
                                                     start: start,
                                                     firstControl: firstControl,
                                                     secondControl: secondControl,
                                                     target: target,
                                                     position: start))
        bubbles.removeAll { $0.id == bubble.id }
    }

    private func popAllAnswerBubbles() {
        for index in bubbles.indices where !bubbles[index].isPopping {
            bubbles[index].popAge = 0
        }
    }
}

// MARK: - Level completion bubbles

private struct CelebrationBubbleView: View {
    let bubble: ReefCelebrationBubble
    let palette: ReefPalette

    private var scale: CGFloat {
        switch bubble.kind {
        case .stream: return min(1, CGFloat(bubble.age / 0.18))
        case .trail:  return max(0.45, 1 - CGFloat(bubble.age / 2.8) * 0.42)
        }
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [
                    .white.opacity(0.42),
                    palette.waterTop.opacity(0.22),
                    .white.opacity(0.16)
                ], center: .topLeading, startRadius: 1, endRadius: bubble.radius * 1.4)
            )
            .overlay {
                Circle().stroke(.white.opacity(0.48),
                                lineWidth: max(1, bubble.radius * 0.09))
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.72))
                    .frame(width: bubble.radius * 0.34, height: bubble.radius * 0.34)
                    .padding(bubble.radius * 0.32)
            }
            .frame(width: bubble.radius * 2, height: bubble.radius * 2)
            .scaleEffect(scale)
            .opacity(bubble.kind == .trail
                     ? max(0, 1 - bubble.age / 3.0)
                     : 1)
            .allowsHitTesting(false)
    }
}

// MARK: - Playfield

/// The reef itself. Everything below the HUD and above the helper button.
/// The reef itself: water, fish, bubbles, the sea floor.
///
/// Deliberately never mirrored. Everything below is a simulation in screen
/// points — the fish carries a heading in radians, the sprite is flipped from
/// `cos(heading)`, and steering reads the raw touch location — so a
/// right-to-left environment turns the whole world into its own reflection: the
/// character swims backwards, a tap on the right steers left, and a turn that
/// looks correct going up comes out wrong coming down. Reading direction
/// belongs to text and to the HUD around this view, not to a physical space.
struct ReefPlayfield: View {
    let round: GameRound?
    let maximumRounds: Int
    let character: AnimalCharacter
    let isPad: Bool
    /// Whether an answer may be released and taken right now.
    let isLive: Bool
    /// Whether the simulation runs at all.
    let isRunning: Bool
    /// True between dismissing the level card and opening the first round.
    let playsFishEntrance: Bool
    let hasBonusFishPower: Bool
    let isHeartFishAvailable: Bool
    let heartFishRestoresWholeLife: Bool
    let isStreakBoostActive: Bool
    let playsLevelCompletion: Bool
    let reduceMotion: Bool
    /// What the walkthrough wants in the water, if one is running.
    var tutorialPlan = ReefTutorialPlan()
    /// Screen edges the reef works around: the HUD at the top, the home
    /// indicator at the bottom.
    let topReserve: CGFloat
    let bottomReserve: CGFloat
    /// Exact global centre of the currency icon in the overlaid HUD.
    let scoreTarget: CGPoint?
    /// Hands a touched answer to the session; the return value says whether it
    /// counted.
    let onHit: (UUID) -> Bool
    let onScoreBubbleArrived: () -> Void
    let onBonusFishCaught: () -> Void
    let onHeartFishCaught: () -> Bool
    let onHeartFishMissed: () -> Void
    let onFishEntranceComplete: () -> Void
    let onLevelCompletionFinished: () -> Void
    /// Everything the walkthrough waits on that only the reef can see.
    var onTutorialEvent: (ReefTutorialEvent) -> Void = { _ in }

    @StateObject private var engine = ReefEngine()

    private var bandHeight: CGFloat {
        ReefConfig.bandHeight(isPad: isPad, bottomReserve: bottomReserve)
    }
    private var sandHeight: CGFloat {
        ReefConfig.sandHeight(isPad: isPad, bottomReserve: bottomReserve)
    }
    private var palette: ReefPalette { ReefPalette(character: character) }

    private var coralBed: CoralBed {
        CoralBed(palette: palette,
                 isPad: isPad,
                 bandHeight: bandHeight,
                 sandHeight: sandHeight,
                 clock: engine.swayClock,
                 prompt: round?.question.prompt ?? "",
                 roundID: round?.id,
                 bottomReserve: bottomReserve)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let spawnLine = max(0, size.height - bandHeight)

            ZStack(alignment: .topLeading) {
                // The open water takes the touch; the fish only ever moves
                // while a finger is down on it.
                WaterColumn(palette: palette, clock: engine.driftClock)
                    .equatable()
                    .contentShape(Rectangle())

                // These effects used to be dozens of individual SwiftUI view
                // nodes. A single Canvas keeps the same layering while turning
                // the whole decorative field into one inexpensive draw pass.
                ReefEffectsCanvas(motes: engine.motes,
                                  wakes: engine.wakes,
                                  ambientBubbles: engine.ambientBubbles,
                                  character: character)
                    .allowsHitTesting(false)

                ForEach(engine.celebrationBubbles) { bubble in
                    CelebrationBubbleView(bubble: bubble, palette: palette)
                        .position(bubble.position)
                }

                // Under the answers and the swimmer: the marker is a place in
                // the water, not an object floating in front of the game.
                if let target = engine.tutorialTarget {
                    if tutorialPlan.showsSwipeHint {
                        TutorialSwipeHint(start: engine.fish.position,
                                          end: target,
                                          theme: character,
                                          clock: engine.clock,
                                          isPad: isPad)
                            .frame(width: size.width, height: size.height)
                            .transition(.opacity)
                    }
                    TutorialTargetView(theme: character,
                                       clock: engine.clock,
                                       isPad: isPad)
                        .position(target)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }

                ForEach(engine.bubbles) { bubble in
                    AnswerBubbleView(bubble: bubble, palette: palette, isPad: isPad)
                        .equatable()
                        .position(bubble.position)
                }

                // Drawn before the swimmer so its first beat genuinely comes
                // from behind the body, then remains free to rise to the HUD.
                ForEach(engine.collectedBubbles) { bubble in
                    CollectedAnswerBubbleView(bubble: bubble,
                                              palette: palette,
                                              isPad: isPad)
                        .position(bubble.position)
                        .allowsHitTesting(false)
                }

                if let bonusFish = engine.bonusFish {
                    BonusFishView(fish: bonusFish, palette: palette, isPad: isPad)
                        .equatable()
                        .position(bonusFish.position)
                        .allowsHitTesting(false)
                }

                if let heartFish = engine.heartFish {
                    HeartFishView(fish: heartFish,
                                  palette: palette,
                                  isPad: isPad,
                                  restoresWholeLife: heartFishRestoresWholeLife)
                        .equatable()
                        .position(heartFish.position)
                        .allowsHitTesting(false)
                }

                ZStack {
                    if isStreakBoostActive {
                        StreakAuraView(fish: engine.fish,
                                       character: character,
                                       clock: engine.clock,
                                       isPad: isPad)
                    }
                    if engine.hasBonusAura {
                        BonusAuraView(character: character, isPad: isPad)
                            .equatable()
                    }
                    FishView(fish: engine.fish,
                             character: character,
                             isPad: isPad,
                             clock: engine.clock)
                        .equatable()
                }
                .position(engine.fish.position)
                .allowsHitTesting(false)

                // Sea floor and coral last, so the sum is never covered by a
                // bubble or by the fish.
                coralBed
                    .equatable()
                    .frame(width: size.width, height: bandHeight)
                    .offset(y: spawnLine)
                    .allowsHitTesting(false)

            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { engine.steer(toward: $0.location) }
                    .onEnded { _ in engine.releaseTouch() }
            )
            .allowsHitTesting(!playsLevelCompletion)
            // See the note on the type: the reef is a simulated space, so it
            // keeps its own orientation whatever the language reads like.
            .environment(\.layoutDirection, .leftToRight)
            .onAppear {
#if canImport(UIKit)
                ReefArtworkCache.prewarm()
#endif
                engine.onHit = onHit
                engine.onCollectedBubbleArrived = onScoreBubbleArrived
                engine.onBonusFishCaught = onBonusFishCaught
                engine.onHeartFishCaught = onHeartFishCaught
                engine.onHeartFishMissed = onHeartFishMissed
                engine.onTutorialEvent = onTutorialEvent
                engine.layout(size: size, spawnLine: spawnLine,
                              topReserve: topReserve, isPad: isPad,
                              fishArtworkWidth: fishArtworkSize(for: character,
                                                               isPad: isPad).width)
                engine.configureBonusFish(maximumRounds: maximumRounds)
                engine.load(round: round)
                engine.setLive(isLive)
                engine.setBonusAura(hasBonusFishPower)
                engine.setHeartFishAvailable(isHeartFishAvailable)
                engine.setSpeedMultiplier(isStreakBoostActive
                                          ? GameConfig.streakSpeedMultiplier : 1)
                engine.setScoreTarget(scoreTarget)
                engine.applyTutorial(tutorialPlan)
                engine.setRunning(isRunning)
                if playsFishEntrance {
                    engine.beginFishEntrance(completion: onFishEntranceComplete)
                }
                if playsLevelCompletion {
                    engine.beginLevelCompletion(reduceMotion: reduceMotion,
                                                completion: onLevelCompletionFinished)
                }
            }
            .onChange(of: size) { _, newSize in
                engine.layout(size: newSize,
                              spawnLine: max(0, newSize.height - bandHeight),
                              topReserve: topReserve,
                              isPad: isPad,
                              fishArtworkWidth: fishArtworkSize(for: character,
                                                               isPad: isPad).width)
            }
        }
        // A new sum clears the water and starts a fresh set of answers. A wrong
        // answer keeps the same round, so this deliberately does not fire.
        .onChange(of: round?.id) { _, _ in
            engine.load(round: round)
        }
        .onChange(of: isLive) { _, live in
            engine.setLive(live)
        }
        .onChange(of: isRunning) { _, running in
            engine.setRunning(running)
        }
        .onChange(of: hasBonusFishPower) { _, active in
            engine.setBonusAura(active)
        }
        .onChange(of: isHeartFishAvailable) { _, available in
            engine.setHeartFishAvailable(available)
        }
        .onChange(of: isStreakBoostActive) { _, active in
            engine.setSpeedMultiplier(active ? GameConfig.streakSpeedMultiplier : 1)
        }
        .onChange(of: scoreTarget) { _, target in
            engine.setScoreTarget(target)
        }
        .onChange(of: tutorialPlan) { _, plan in
            withAnimation(.easeInOut(duration: 0.25)) {
                engine.applyTutorial(plan)
            }
        }
        .onChange(of: playsFishEntrance) { _, shouldPlay in
            if shouldPlay {
                engine.beginFishEntrance(completion: onFishEntranceComplete)
            }
        }
        .onChange(of: playsLevelCompletion) { _, shouldPlay in
            if shouldPlay {
                engine.beginLevelCompletion(reduceMotion: reduceMotion,
                                            completion: onLevelCompletionFinished)
            } else {
                engine.endLevelCompletion()
            }
        }
        .onDisappear {
            engine.stop()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Heart fish

private struct HeartFishView: View, Equatable {
    let fish: ReefHeartFish
    let palette: ReefPalette
    let isPad: Bool
    let restoresWholeLife: Bool

    private var artwork: Image {
#if canImport(UIKit)
        Image(uiImage: ReefArtworkCache.lifeFish)
#else
        Image("life_fish")
#endif
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fish.id == rhs.fish.id
            && lhs.fish.direction == rhs.fish.direction
            && lhs.fish.length == rhs.fish.length
            && lhs.fish.isCarryingReward == rhs.fish.isCarryingReward
            && lhs.palette.character == rhs.palette.character
            && lhs.isPad == rhs.isPad
            && lhs.restoresWholeLife == rhs.restoresWholeLife
    }

    var body: some View {
        ZStack {
            artwork
                .resizable()
                .scaledToFit()
                .frame(width: fish.length * 1.62, height: fish.length * 1.30)
                .scaleEffect(x: fish.direction < 0 ? -1 : 1, y: 1)

            if fish.isCarryingReward {
                carriedHeart
                    .offset(x: fish.length * 0.60 * fish.direction,
                            y: fish.length * 0.08)
            }
        }
        .frame(width: fish.length * 1.68, height: fish.length * 1.34)
        .shadow(color: .pink.opacity(0.30), radius: isPad ? 7 : 5, y: 2)
        .accessibilityHidden(true)
    }

    private var carriedHeart: some View {
        let size = fish.length * 0.31
        return ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(palette.coralDeep.opacity(0.22))
            Image(systemName: "heart.fill")
                .foregroundStyle(palette.coralDeep)
                .frame(width: size, height: size)
                .mask {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            Rectangle()
                                .frame(width: restoresWholeLife
                                       ? geometry.size.width
                                       : geometry.size.width / 2)
                            Spacer(minLength: 0)
                        }
                    }
                }
        }
        .font(.system(size: size, weight: .bold))
        .frame(width: size, height: size)
        .shadow(color: .white.opacity(0.85), radius: 2)
    }
}

// MARK: - 2x power-up fish

private struct BonusFishView: View, Equatable {
    let fish: ReefBonusFish
    let palette: ReefPalette
    let isPad: Bool

    private var artwork: Image {
#if canImport(UIKit)
        Image(uiImage: ReefArtworkCache.bonusFish)
#else
        Image("2x_coin_fish")
#endif
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fish.id == rhs.fish.id
            && lhs.fish.direction == rhs.fish.direction
            && lhs.fish.length == rhs.fish.length
            && lhs.fish.isCarryingReward == rhs.fish.isCarryingReward
            && lhs.palette.character == rhs.palette.character
            && lhs.isPad == rhs.isPad
    }

    var body: some View {
        ZStack {
            artwork
                .resizable()
                .scaledToFit()
                .frame(width: fish.length * 1.62, height: fish.length * 1.30)
                .scaleEffect(x: fish.direction < 0 ? -1 : 1, y: 1)

            if fish.isCarryingReward {
                Text(verbatim: "2×")
                    .font(.system(size: fish.length * 0.21,
                                  weight: .black,
                                  design: .rounded))
                    .foregroundStyle(palette.waterDeep)
                    .frame(width: fish.length * 0.42, height: fish.length * 0.42)
                    .background {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.white, .yellow.opacity(0.92)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            )
                            .overlay {
                                Circle().stroke(.orange, lineWidth: isPad ? 3 : 2)
                            }
                    }
                    .shadow(color: .orange.opacity(0.55), radius: 3, y: 2)
                    .offset(x: fish.length * 0.64 * fish.direction,
                            y: fish.length * -0.02)
            }
        }
        .frame(width: fish.length * 1.68, height: fish.length * 1.34)
        .shadow(color: .yellow.opacity(0.30), radius: isPad ? 7 : 5, y: 2)
        .accessibilityHidden(true)
    }
}

private struct StreakAuraView: View {
    let fish: ReefFish
    let character: AnimalCharacter
    let clock: Double
    let isPad: Bool

    private var artworkSize: CGSize { fishArtworkSize(for: character, isPad: isPad) }
    private var isFacingLeft: Bool { cos(fish.heading) < 0 }

    var body: some View {
        // Keep the effect attached to the playable character's silhouette.
        // The restrained pulse makes the streak feel alive without changing
        // the apparent hit area or turning the aura into a separate object.
        let pulse = CGFloat(sin(clock * 4.4)) * 0.010

        StreakAuraArtwork(character: character, artworkSize: artworkSize, isPad: isPad)
            .equatable()
            .scaleEffect(1 + pulse)
        .frame(width: artworkSize.width, height: artworkSize.height)
        .scaleEffect(x: 1, y: isFacingLeft ? -1 : 1)
        .rotationEffect(.radians(fish.heading))
        .accessibilityHidden(true)
    }
}

private struct StreakAuraArtwork: View, Equatable {
    let character: AnimalCharacter
    let artworkSize: CGSize
    let isPad: Bool

    var body: some View {
        ZStack {
            FishAuraSilhouette(character: character, size: artworkSize, color: .orange)
                .scaleEffect(1.25)
                .blur(radius: isPad ? 8 : 6)
                .opacity(0.52)

            FishAuraSilhouette(character: character, size: artworkSize, color: .yellow)
                .scaleEffect(1.15)
                .shadow(color: .white.opacity(0.95), radius: isPad ? 2.5 : 2)
                .shadow(color: .yellow.opacity(0.72), radius: isPad ? 7 : 5)
        }
    }
}

/// A solid copy of the character's own outline, taken from the alpha channel of
/// its swimming artwork. Enlarging this underneath `FishView` produces a true
/// contour — the bunny's ears, the octopus's arms — instead of a generic halo
/// that would fit none of the ten.
private struct FishAuraSilhouette: View {
    let character: AnimalCharacter
    let size: CGSize
    let color: Color

    var body: some View {
        character.sideArtwork
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size.width, height: size.height)
            .compositingGroup()
    }
}

private struct BonusAuraView: View, Equatable {
    let character: AnimalCharacter
    let isPad: Bool

    var body: some View {
        let size: CGFloat = isPad ? 126 : 94
        ZStack {
            Circle()
                .fill(character.tintColor.opacity(0.20))
            Circle()
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
            Text(verbatim: "2×")
                .font(.system(size: isPad ? 22 : 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(character.deepColor, in: Capsule())
                .offset(y: -size * 0.57)
        }
        .frame(width: size, height: size)
        .shadow(color: .white.opacity(0.55), radius: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Bubble

private struct CollectedAnswerBubbleView: View {
    let bubble: ReefCollectedBubble
    let palette: ReefPalette
    let isPad: Bool

    private var progress: Double {
        min(1, bubble.age / ReefConfig.collectedBubbleDuration)
    }

    private var scale: Double {
        0.52 + easeOut(min(1, progress / 0.28)) * 0.48
    }

    private func easeOut(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }

    var body: some View {
        CurrencyIcon(size: bubble.diameter)
            .foregroundStyle(palette.character.deepColor)
        .frame(width: bubble.diameter, height: bubble.diameter)
        .scaleEffect(scale)
        .shadow(color: .white.opacity(0.82), radius: isPad ? 8 : 6)
        .accessibilityHidden(true)
    }
}

private struct AnswerBubbleView: View, Equatable {
    let bubble: ReefBubble
    let palette: ReefPalette
    let isPad: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bubble.id == rhs.bubble.id
            && lhs.bubble.emergence == rhs.bubble.emergence
            && lhs.bubble.isPopping == rhs.bubble.isPopping
            && lhs.popProgress == rhs.popProgress
            && lhs.palette.character == rhs.palette.character
            && lhs.isPad == rhs.isPad
    }

    /// The shell vanishes immediately; the water it held keeps splashing for
    /// the rest of the beat.
    private var popProgress: Double {
        guard let popAge = bubble.popAge else { return 0 }
        return min(1, popAge / ReefConfig.popDuration)
    }

    private var emergenceScale: Double {
        let start = ReefConfig.emergeStartScale
        return start + (1 - start) * easeOut(bubble.emergence)
    }

    private var shellScale: Double {
        emergenceScale * (bubble.isPopping ? max(0.08, 1 - popProgress * 3.8) : 1)
    }

    private var shellOpacity: Double {
        min(1, bubble.emergence * 3)
            * (bubble.isPopping ? max(0, 1 - popProgress * 4.2) : 1)
    }

    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    var body: some View {
        ZStack {
            ZStack {
                // A pale, glassy shell: light enough for a dark answer to be read
                // straight through it, and clearly a bubble against the water.
                Circle()
                    .fill(
                        RadialGradient(colors: [.white.opacity(0.97), .white.opacity(0.62)],
                                       center: UnitPoint(x: 0.34, y: 0.30),
                                       startRadius: 2,
                                       endRadius: bubble.diameter * 0.74)
                    )
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: isPad ? 3 : 2.2)

                Circle()
                    .fill(.white)
                    .frame(width: bubble.diameter * 0.17, height: bubble.diameter * 0.17)
                    .offset(x: -bubble.diameter * 0.22, y: -bubble.diameter * 0.24)

                Text(verbatim: bubble.text)
                    .font(.system(size: isPad ? 34 : 26, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .foregroundStyle(palette.coralDeep)
                    .frame(width: bubble.diameter * 0.74)
            }
            .scaleEffect(shellScale)
            .opacity(shellOpacity)
            .shadow(color: palette.waterDeep.opacity(0.28), radius: 6, y: 3)

            if bubble.isPopping {
                BubbleSplashView(diameter: bubble.diameter,
                                 progress: popProgress)
            }
        }
        .frame(width: bubble.diameter, height: bubble.diameter)
        .accessibilityLabel(Text(verbatim: bubble.text))
        .accessibilityValue(Text(bubble.isCorrect ? "game.answer.correct" : "game.answer.wrong"))
    }
}

/// A collapsing shell throws an uneven crown and loose droplets into the
/// surrounding water. Gravity bends the drops down at the end, making this
/// read as a wet splash rather than a radial sparkle.
private struct BubbleSplashView: View {
    let diameter: CGFloat
    let progress: Double

    private let angles: [Double] = [
        -2.92, -2.58, -2.22, -1.88, -1.58, -1.31,
        -1.02, -0.69, -0.31, 0.18, 0.62, 2.78
    ]

    var body: some View {
        ZStack {
            // The short, wide crown at the impact point.
            Capsule()
                .fill(.white.opacity(max(0, 0.88 - progress * 1.25)))
                .frame(width: diameter * (0.18 + CGFloat(progress) * 0.88),
                       height: diameter * max(0.035, 0.18 - CGFloat(progress) * 0.13))
                .offset(y: diameter * CGFloat(progress) * 0.12)

            ForEach(Array(angles.enumerated()), id: \.offset) { index, angle in
                splashDrop(index: index, angle: angle)
            }
        }
        .allowsHitTesting(false)
    }

    private func splashDrop(index: Int, angle: Double) -> some View {
        let p = CGFloat(progress)
        let speed = CGFloat(0.58 + Double(index % 4) * 0.10)
        let distance = diameter * (0.10 + p * speed)
        let gravityFactor = CGFloat(0.22 + Double(index % 3) * 0.045)
        let gravity = diameter * p * p * gravityFactor
        let dropWidth = diameter * CGFloat(0.045 + Double(index % 3) * 0.012)
        let dropHeight = diameter * CGFloat(0.10 + Double(index % 2) * 0.045)
        let x = CGFloat(cos(angle)) * distance
        let y = CGFloat(sin(angle)) * distance + gravity
        let opacity = max(0, 1 - progress * 0.92)

        // A correct answer bursts all five bubbles at once, so this drop is on
        // screen sixty times over in the same instant. It deliberately carries
        // no shadow: a 1 pt cyan halo at a quarter opacity behind a white drop
        // is invisible against the water, while sixty offscreen blur passes
        // landing on the frame the player just scored in are not.
        return Ellipse()
            .fill(.white.opacity(opacity))
            .frame(width: dropWidth, height: dropHeight)
            .rotationEffect(.radians(angle + .pi / 2))
            .offset(x: x, y: y)
    }
}

// MARK: - Fish

/// The size the swimming artwork is drawn at.
///
/// Each character keeps the proportions of its own asset — a long octopus and a
/// stubby crab are not forced into one silhouette — while the *area* stays the
/// same for everyone. That keeps `fishHitFactor` a fair, single number: nobody
/// gets a larger target by being drawn wider.
private func fishArtworkSize(for character: AnimalCharacter, isPad: Bool) -> CGSize {
    let span = ReefConfig.fishLength(isPad: isPad) * ReefConfig.fishArtworkSpan
    let root = max(0.2, character.sideAspectRatio).squareRoot()
    return CGSize(width: span * root, height: span / root)
}

/// The playable character: its own artwork, swimming the way it is drawn.
private struct FishView: View, Equatable {
    let fish: ReefFish
    let character: AnimalCharacter
    let isPad: Bool
    let clock: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fish.heading == rhs.fish.heading
            && lhs.fish.isSwimming == rhs.fish.isSwimming
            && lhs.character == rhs.character
            && lhs.isPad == rhs.isPad
            && lhs.clock == rhs.clock
    }

    private var artworkSize: CGSize { fishArtworkSize(for: character, isPad: isPad) }

    /// The assets all face right, so facing left is a mirror rather than an
    /// upside-down turn: the character is never swimming on its back.
    private var isFacingLeft: Bool { cos(fish.heading) < 0 }
    /// Even at rest a swimmer balances itself in the current. The active beat is
    /// deliberately quicker and wider, so starting to swim is legible.
    private var swimBeat: Double {
        fish.isSwimming ? sin(clock * 12.5) * 0.045 : sin(clock * 2.2) * 0.018
    }
    /// A slow, continuous list to either side. It never fully stops, which is
    /// what keeps a resting character from reading as a pasted-on sticker.
    private var roll: Double {
        fish.isSwimming ? sin(clock * 6.2) * 0.026 : sin(clock * 1.35) * 0.038
    }
    private var lift: CGFloat {
        fish.isSwimming
            ? CGFloat(sin(clock * 6.2 + 1.1)) * 1.1
            : CGFloat(sin(clock * 1.55)) * 2.6
    }

    var body: some View {
        character.sideArtwork
            .resizable()
            .scaledToFit()
            // The stroke is what a tail beat reads as here: the body stretches
            // along the swim axis and narrows across it, which suits ten very
            // different shapes better than one hand-tuned fin animation.
            .frame(width: artworkSize.width * (1 + swimBeat),
                   height: artworkSize.height * (1 - swimBeat))
            .frame(width: artworkSize.width, height: artworkSize.height)
            .scaleEffect(x: 1, y: isFacingLeft ? -1 : 1)
            .rotationEffect(.radians(fish.heading + roll))
            .offset(y: lift)
            .shadow(color: character.deepColor.opacity(0.22), radius: 6, y: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Water

/// The water column: the whole screen, from the surface at the very top edge
/// down to the sea floor.
private struct WaterColumn: View, Equatable {
    let palette: ReefPalette
    let clock: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.palette.character == rhs.palette.character && lhs.clock == rhs.clock
    }

    var body: some View {
        LinearGradient(colors: [palette.waterTop, palette.waterDeep],
                       startPoint: .top, endPoint: .bottom)
            .overlay { SunShafts(clock: clock) }
    }
}

/// Two wide, very faint shafts of light leaning in from above. They drift
/// slowly, which is most of what makes the water feel like water.
private struct SunShafts: View {
    let clock: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                shaft(width: width * 0.30, lean: -13)
                    .offset(x: width * (0.24 + 0.03 * CGFloat(sin(clock * 0.18))))
                shaft(width: width * 0.20, lean: -9)
                    .offset(x: width * (0.70 + 0.04 * CGFloat(sin(clock * 0.13 + 1.7))))
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
        }
        .opacity(0.13)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Kept deliberately faint: the shafts are there to be felt, not looked at,
    /// and the answers have to stay the brightest thing in the water.
    private func shaft(width: CGFloat, lean: Double) -> some View {
        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                               .init(color: .white, location: 0.22),
                               .init(color: .white.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: width)
            .rotationEffect(.degrees(lean), anchor: .top)
            .blur(radius: 26)
    }
}

/// Plankton, wake wisps and ambient bubbles share one immediate-mode render
/// pass. None of them needs its own layout, accessibility or hit-testing node;
/// keeping them in a Canvas dramatically reduces SwiftUI diffing during fast
/// movement and when an extra boost aura is on screen.
private struct ReefEffectsCanvas: View {
    let motes: [ReefMote]
    let wakes: [ReefWake]
    let ambientBubbles: [ReefAmbientBubble]
    let character: AnimalCharacter

    var body: some View {
        // Draw synchronously with the current display frame. Asynchronous
        // Canvas rendering can trail the fish by a frame on older hardware.
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            for mote in motes {
                let rect = CGRect(x: mote.position.x - mote.radius,
                                  y: mote.position.y - mote.radius,
                                  width: mote.radius * 2,
                                  height: mote.radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.34)))
            }

            for wake in wakes {
                draw(wake: wake, in: &context)
            }

            for bubble in ambientBubbles {
                draw(ambientBubble: bubble, in: &context)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(wake: ReefWake, in context: inout GraphicsContext) {
        let progress = min(1, wake.age / wake.lifetime)
        switch wake.kind {
        case .bubble:
            let scale = 0.72 + CGFloat(progress) * 0.46
            let radius = wake.radius * scale
            let rect = CGRect(x: wake.position.x - radius,
                              y: wake.position.y - radius,
                              width: radius * 2,
                              height: radius * 2)
            let shell = Path(ellipseIn: rect)
            context.fill(shell, with: .color(
                character.tintColor.opacity(0.30 * (1 - progress))
            ))
            context.stroke(shell, with: .color(.white.opacity(0.72 * (1 - progress))),
                           lineWidth: 1.1)

            let highlightRadius = wake.radius * 0.25 * scale
            let highlightCenter = CGPoint(x: wake.position.x - radius * 0.42,
                                          y: wake.position.y - radius * 0.40)
            let highlight = CGRect(x: highlightCenter.x - highlightRadius,
                                   y: highlightCenter.y - highlightRadius,
                                   width: highlightRadius * 2,
                                   height: highlightRadius * 2)
            context.fill(Path(ellipseIn: highlight), with: .color(
                .white.opacity(0.85 * (1 - progress))
            ))

        case .wisp:
            let width = wake.radius * (3.4 + CGFloat(progress) * 4.6)
            let height = wake.radius * 1.65
            let start = rotatedPoint(x: width / 2, y: 0, around: wake.position,
                                     angle: wake.heading)
            let end = rotatedPoint(x: -width / 2, y: -wake.side * height * 0.12,
                                   around: wake.position, angle: wake.heading)
            let control1 = rotatedPoint(x: width * 0.20,
                                        y: wake.side * height * 0.44,
                                        around: wake.position, angle: wake.heading)
            let control2 = rotatedPoint(x: -width * 0.20,
                                        y: wake.side * height * 0.24,
                                        around: wake.position, angle: wake.heading)
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end, control1: control1, control2: control2)
            let fade = pow(1 - progress, 1.6)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [character.deepColor.opacity(0),
                                  character.color.opacity(0.78 * fade),
                                  .white.opacity(0.55 * fade)]),
                startPoint: end,
                endPoint: start
            )
            context.stroke(path, with: shading,
                           style: StrokeStyle(lineWidth: max(0.8, 2.6 * (1 - progress)),
                                              lineCap: .round))
        }
    }

    private func draw(ambientBubble bubble: ReefAmbientBubble,
                      in context: inout GraphicsContext) {
        let progress = bubble.popAge.map {
            min(1, CGFloat($0 / ReefConfig.ambientBubblePopDuration))
        } ?? 0
        let opacity = 1 - Double(progress)
        let scale = bubble.popAge == nil ? CGFloat(1) : 1 + progress * 1.15
        let radius = bubble.radius * scale
        let rect = CGRect(x: bubble.position.x - radius,
                          y: bubble.position.y - radius,
                          width: radius * 2,
                          height: radius * 2)
        let shell = Path(ellipseIn: rect)
        context.fill(shell, with: .color(.white.opacity(0.10 * opacity)))
        context.stroke(shell, with: .color(.white.opacity(0.48 * opacity)),
                       lineWidth: max(1, bubble.radius * 0.16))

        let highlightRadius = bubble.radius * 0.19 * scale
        let highlightCenter = CGPoint(x: bubble.position.x - radius * 0.43,
                                      y: bubble.position.y - radius * 0.43)
        let highlight = CGRect(x: highlightCenter.x - highlightRadius,
                               y: highlightCenter.y - highlightRadius,
                               width: highlightRadius * 2,
                               height: highlightRadius * 2)
        context.fill(Path(ellipseIn: highlight),
                     with: .color(.white.opacity(0.68 * opacity)))
    }

    private func rotatedPoint(x: CGFloat, y: CGFloat, around centre: CGPoint,
                              angle: Double) -> CGPoint {
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        return CGPoint(x: centre.x + x * cosine - y * sine,
                       y: centre.y + x * sine + y * cosine)
    }
}

// MARK: - Sea floor
/// The sea bed: a sand mound, coral swaying in the current, the craters the
/// bubbles come out of, and the sum set into a doorway in the reef. The sum is
/// drawn in front of everything, so neither a bubble nor the fish can cover it.
private struct CoralBed: View, Equatable {
    let palette: ReefPalette
    let isPad: Bool
    let bandHeight: CGFloat
    let sandHeight: CGFloat
    let clock: Double
    let prompt: String
    /// Changes when a new sum is installed; the door opens on it.
    let roundID: UUID?
    let bottomReserve: CGFloat

    private var doorHeight: CGFloat { ReefConfig.doorHeight(isPad: isPad) }
    private var rimHeight: CGFloat { ReefConfig.craterRimHeight(isPad: isPad) }
    private var floorInset: CGFloat { ReefConfig.floorInset(isPad: isPad) + bottomReserve }
    private var questionInset: CGFloat { isPad ? 126 : 48 }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.palette.character == rhs.palette.character
            && lhs.isPad == rhs.isPad
            && lhs.bandHeight == rhs.bandHeight
            && lhs.sandHeight == rhs.sandHeight
            && lhs.clock == rhs.clock
            && lhs.prompt == rhs.prompt
            && lhs.roundID == rhs.roundID
            && lhs.bottomReserve == rhs.bottomReserve
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SandBank(palette: palette)
                .frame(height: sandHeight)

            // Fronds sway either side of the block, out where the mound shows.
            CoralClump(palette: palette,
                       isPad: isPad,
                       clock: clock,
                       rootDepth: sandHeight * 0.46)
                .frame(height: bandHeight)

            // One low coral boulder, partly buried in the hill.
            ReefMass(palette: palette, isPad: isPad, clock: clock)
                .padding(.horizontal, ReefConfig.blockInset(isPad: isPad))
                .padding(.bottom, floorInset * 0.25)
                .frame(height: doorHeight + rimHeight + floorInset * 0.75,
                       alignment: .bottom)

            // The vents and sum share that same mass; neither draws a separate
            // rectangular backing of its own.
            CraterRim(palette: palette, isPad: isPad, clock: clock)
                .frame(height: rimHeight)
                .padding(.horizontal, ReefConfig.blockInset(isPad: isPad))
                .padding(.bottom, floorInset + doorHeight)

            CoralQuestion(prompt: prompt,
                          roundID: roundID,
                          palette: palette,
                          isPad: isPad)
                .frame(height: doorHeight)
                .padding(.horizontal, questionInset)
                .padding(.bottom, floorInset)

            SeaPlantField(palette: palette, isPad: isPad, clock: clock)
                .frame(height: bandHeight)

            // This is a full foreground bank, not a narrow strip: it hides the
            // complete foot of the coral and lets the plants emerge from sand.
            ForegroundSandLip(palette: palette)
                .frame(height: floorInset + (isPad ? 18 : 12))
                .allowsHitTesting(false)
        }
    }
}

private struct ForegroundSandLip: View {
    let palette: ReefPalette

    var body: some View {
        ForegroundSandShape()
            .fill(
                LinearGradient(colors: [palette.sand.opacity(0.96), palette.sandDeep],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                ForegroundSandShape()
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct ForegroundSandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
        path.addCurve(to: CGPoint(x: rect.width * 0.32, y: rect.height * 0.10),
                      control1: CGPoint(x: rect.width * 0.10, y: rect.height * 0.06),
                      control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.17))
        path.addCurve(to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.11),
                      control1: CGPoint(x: rect.width * 0.43, y: rect.height * 0.02),
                      control2: CGPoint(x: rect.width * 0.56, y: rect.height * 0.19))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.16),
                      control1: CGPoint(x: rect.width * 0.80, y: rect.height * 0.03),
                      control2: CGPoint(x: rect.width * 0.91, y: rect.height * 0.21))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The main piece of coral. Its scalloped crown and flared roots are a single
/// silhouette, which visually welds the question niche to the sandy hill.
private struct ReefMass: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    private let texture: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.54, 0.026), (0.14, 0.78, 0.018), (0.22, 0.34, 0.014),
        (0.78, 0.31, 0.016), (0.87, 0.66, 0.024), (0.92, 0.45, 0.013),
        (0.31, 0.88, 0.019), (0.68, 0.84, 0.015)
    ]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                ReefMassShape()
                    .fill(
                        LinearGradient(colors: [palette.coral.opacity(0.98), palette.coralDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay {
                        ReefMassShape()
                            .stroke(.white.opacity(0.17), lineWidth: isPad ? 2 : 1.3)
                    }
                    .shadow(color: palette.coralDeep.opacity(0.32), radius: 12, y: 8)

                // Quiet pits in the coral keep the large surface from reading
                // as a flat slab. They breathe by only a few percent.
                ForEach(Array(texture.enumerated()), id: \.offset) { index, spot in
                    let pulse = 1 + 0.07 * sin(clock * 0.55 + Double(index) * 1.7)
                    Circle()
                        .fill(palette.coralDeep.opacity(0.32))
                        .overlay {
                            Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                        .frame(width: max(4, w * spot.2), height: max(4, w * spot.2))
                        .scaleEffect(pulse)
                        .position(x: w * spot.0, y: h * spot.1)
                }

                CoralSurfaceLife(palette: palette, isPad: isPad, clock: clock)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Living details that grow from the boulder itself: small coral fans, flower-
/// like polyps and buds. Motion stays deliberately slow and asynchronous.
private struct CoralSurfaceLife: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    /// x, root y, scale, resting lean, animation phase.
    private let twigs: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
        // A dense low cluster on the left shoulder.
        (0.060, 0.68, 1.00, -14, 0.2), (0.105, 0.55, 0.72, 9, 1.5),
        (0.155, 0.66, 0.88, -5, 3.2), (0.215, 0.46, 0.60, 12, 4.7),
        (0.285, 0.58, 0.68, -8, 2.3),
        // The opposite side deliberately has a different rhythm and outline.
        (0.705, 0.48, 0.58, 9, 5.1), (0.770, 0.61, 0.76, -12, 3.8),
        (0.835, 0.45, 0.62, 7, 0.9), (0.885, 0.66, 0.90, -7, 4.1),
        (0.940, 0.70, 1.04, 14, 2.0)
    ]

    /// x, y, size, animation phase.
    private let polyps: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.10, 0.70, 1.00, 0.5), (0.18, 0.61, 0.78, 2.1),
        (0.27, 0.73, 0.70, 4.2), (0.36, 0.34, 0.62, 1.2),
        (0.43, 0.78, 0.72, 3.4), (0.57, 0.76, 0.64, 5.5),
        (0.64, 0.35, 0.66, 2.7), (0.73, 0.72, 0.76, 0.1),
        (0.82, 0.60, 0.82, 4.8), (0.90, 0.70, 0.96, 1.8)
    ]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let baseTwigHeight = h * (isPad ? 0.34 : 0.31)
            let basePolyp = isPad ? 14.0 : 10.0

            ZStack {
                ForEach(Array(twigs.enumerated()), id: \.offset) { index, twig in
                    let twigHeight = baseTwigHeight * twig.2
                    let wave = sin(clock * (0.56 + Double(index) * 0.022) + twig.4)
                    let ripple = sin(clock * 1.08 + twig.4 * 1.7)
                    let sway = 5.8 * wave + 1.4 * ripple

                    BranchingCoralShape(bend: CGFloat(wave) * 0.13
                                              + CGFloat(ripple) * 0.035)
                        .stroke(
                            LinearGradient(colors: [.white.opacity(0.48),
                                                    palette.coralDeep.opacity(0.88)],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: isPad ? 4.2 : 3,
                                               lineCap: .round,
                                               lineJoin: .round)
                        )
                        .frame(width: twigHeight * 0.82, height: twigHeight)
                        .rotationEffect(.degrees(twig.3 + sway), anchor: .bottom)
                        .position(x: w * twig.0,
                                  y: h * twig.1 - twigHeight / 2)
                }

                ForEach(Array(polyps.enumerated()), id: \.offset) { index, polyp in
                    CoralPolyp(palette: palette,
                               clock: clock,
                               phase: polyp.3)
                        .frame(width: basePolyp * polyp.2,
                               height: basePolyp * polyp.2)
                        .position(x: w * polyp.0, y: h * polyp.1)
                        .rotationEffect(.degrees(3 * sin(clock * 0.30 + Double(index))))
                }
            }
        }
    }
}

private struct CoralPolyp: View {
    let palette: ReefPalette
    let clock: Double
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let bloom = 0.90 + 0.10 * sin(clock * 0.58 + phase)

            ZStack {
                ForEach(0..<6, id: \.self) { petal in
                    Capsule()
                        .fill(.white.opacity(0.36))
                        .frame(width: size * 0.20, height: size * 0.52)
                        .offset(y: -size * 0.25)
                        .rotationEffect(.degrees(Double(petal) * 60))
                }
                Circle()
                    .fill(palette.coralDeep)
                    .frame(width: size * 0.31, height: size * 0.31)
            }
            .frame(width: size, height: size)
            .scaleEffect(bloom)
        }
    }
}

private struct ReefMassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.02, y: h))
        path.addCurve(to: CGPoint(x: w * 0.04, y: h * 0.23),
                      control1: CGPoint(x: w * 0.00, y: h * 0.72),
                      control2: CGPoint(x: w * 0.01, y: h * 0.37))
        path.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.08),
                      control1: CGPoint(x: w * 0.06, y: h * 0.14),
                      control2: CGPoint(x: w * 0.09, y: h * 0.08))
        path.addCurve(to: CGPoint(x: w * 0.31, y: h * 0.06),
                      control1: CGPoint(x: w * 0.20, y: h * 0.01),
                      control2: CGPoint(x: w * 0.26, y: h * 0.12))
        path.addCurve(to: CGPoint(x: w * 0.49, y: h * 0.07),
                      control1: CGPoint(x: w * 0.37, y: h * 0.01),
                      control2: CGPoint(x: w * 0.43, y: h * 0.03))
        path.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.05),
                      control1: CGPoint(x: w * 0.55, y: h * 0.12),
                      control2: CGPoint(x: w * 0.62, y: h * 0.10))
        path.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.08),
                      control1: CGPoint(x: w * 0.75, y: -h * 0.01),
                      control2: CGPoint(x: w * 0.81, y: h * 0.01))
        path.addCurve(to: CGPoint(x: w * 0.96, y: h * 0.23),
                      control1: CGPoint(x: w * 0.91, y: h * 0.08),
                      control2: CGPoint(x: w * 0.94, y: h * 0.14))
        path.addCurve(to: CGPoint(x: w * 0.98, y: h),
                      control1: CGPoint(x: w * 0.99, y: h * 0.48),
                      control2: CGPoint(x: w, y: h * 0.75))
        path.closeSubpath()
        return path
    }
}

// MARK: Sand

/// The floor: one soft mound rather than a straight edge, so the reef sits on a
/// little hill.
private struct SandBank: View {
    let palette: ReefPalette

    var body: some View {
        SandShape()
            .fill(
                LinearGradient(colors: [palette.sand, palette.sandDeep],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                SandShape()
                    .stroke(palette.sandDeep.opacity(0.40), lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }
}

private struct SandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // The crown of the hill sits well above the sides, which is what makes
        // it read as a mound instead of a band across the bottom.
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: h * 0.72))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.28),
                      control1: CGPoint(x: w * 0.14, y: h * 0.70),
                      control2: CGPoint(x: w * 0.28, y: h * 0.20))
        path.addCurve(to: CGPoint(x: rect.maxX, y: h * 0.66),
                      control1: CGPoint(x: w * 0.74, y: h * 0.22),
                      control2: CGPoint(x: w * 0.88, y: h * 0.66))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Craters

/// The crest of the reef block: knobbly coral with the craters sunk into it.
/// Every bubble is released from one of these, at exactly these positions, so
/// an answer really does grow out of the hole it appears above.
private struct CraterRim: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    /// Fixed differences make the little vents feel grown rather than stamped.
    private static let ventScale: [CGFloat] = [0.76, 1.12, 0.66, 0.96, 0.80]
    private static let ventRise: [CGFloat] = [0.04, -0.04, 0.10, -0.07, 0.03]

    var body: some View {
        GeometryReader { proxy in
            // Craters are placed in screen coordinates, so the crest undoes its
            // own inset to line them up with where bubbles actually appear.
            let inset = ReefConfig.blockInset(isPad: isPad)
            let screenWidth = proxy.size.width + inset * 2
            let height = proxy.size.height
            let craters = ReefConfig.craterPositions(width: screenWidth, isPad: isPad)
                .map { $0 - inset }

            ZStack {
                ForEach(Array(crownPositions(between: craters).enumerated()), id: \.offset) { index, x in
                    crownSprout(height: height, index: index)
                        .position(x: x, y: height * 0.56)
                }

                ForEach(Array(craters.enumerated()), id: \.offset) { index, x in
                    vent(height: height, index: index)
                        .position(x: x,
                                  y: height * (0.74 + Self.ventRise[index % Self.ventRise.count]))
                }
            }
            .frame(width: proxy.size.width, height: height)
        }
        .accessibilityHidden(true)
    }

    /// A small raised lip with a dark centre. The answer bubble appears from
    /// this exact x-coordinate, so the animation still reads as an eruption.
    private func vent(height: CGFloat, index: Int) -> some View {
        let scale = Self.ventScale[index % Self.ventScale.count]
        let diameter = height * 0.64 * scale
        let breath = 1 + 0.055 * sin(clock * 0.85 + Double(index) * 1.3)
        return ZStack {
            Capsule()
                .fill(
                    LinearGradient(colors: [palette.coral.opacity(0.94), palette.coralDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: diameter * 0.60, height: diameter * 0.88)
                .offset(y: diameter * 0.24)
            Ellipse()
                .fill(
                    LinearGradient(colors: [.white.opacity(0.38), palette.coralDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: diameter, height: diameter * 0.52)
            Ellipse()
                .fill(palette.coralDeep.opacity(0.95))
                .frame(width: diameter * 0.50, height: diameter * 0.20)
                .overlay {
                    Ellipse()
                        .stroke(.black.opacity(0.18), lineWidth: 1)
                }
        }
        .scaleEffect(breath)
    }

    private func crownPositions(between craters: [CGFloat]) -> [CGFloat] {
        guard craters.count > 1 else { return [] }
        return zip(craters, craters.dropFirst()).map { ($0 + $1) / 2 }
    }

    private func crownSprout(height: CGFloat, index: Int) -> some View {
        let scales: [CGFloat] = [0.74, 0.52, 0.82, 0.60]
        let sproutHeight = height * scales[index % scales.count]
        let wave = sin(clock * (0.54 + Double(index) * 0.04) + Double(index) * 1.6)
        return BranchingCoralShape(bend: CGFloat(wave) * 0.12)
            .stroke(
                LinearGradient(colors: [.white.opacity(0.46), palette.coralDeep.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: isPad ? 3.2 : 2.3,
                                   lineCap: .round,
                                   lineJoin: .round)
            )
            .frame(width: sproutHeight * 0.72, height: sproutHeight)
            .rotationEffect(.degrees(4.5 * wave), anchor: .bottom)
    }
}

// MARK: Coral

/// Branching coral gardens at both shoulders of the central boulder.
private struct CoralClump: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double
    /// How far above the bottom of the band the fronds are rooted, so they come
    /// out of the sand rather than off the edge of the screen.
    let rootDepth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let root = max(isPad ? 72 : 54, height - rootDepth)
            let clusterWidth = isPad ? 128.0 : 86.0
            let leftWave = sin(clock * 0.62 + 0.3)
            let rightWave = sin(clock * 0.57 + 2.7)

            ZStack {
                branchCluster(bend: CGFloat(leftWave) * 0.16)
                    .frame(width: clusterWidth, height: root)
                    .rotationEffect(.degrees(5.5 * leftWave), anchor: .bottom)
                    .position(x: width * 0.09, y: root / 2)

                branchCluster(bend: CGFloat(rightWave) * 0.16)
                    .frame(width: clusterWidth, height: root)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(5.2 * rightWave), anchor: .bottom)
                    .position(x: width * 0.91, y: root / 2)
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }

    private func branchCluster(bend: CGFloat) -> some View {
        BranchingCoralShape(bend: bend)
            .stroke(
                LinearGradient(colors: [palette.coral.opacity(0.92), palette.coralDeep],
                               startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: isPad ? 13 : 9,
                                   lineCap: .round,
                                   lineJoin: .round)
            )
            .shadow(color: palette.coralDeep.opacity(0.22), radius: 3, y: 3)
    }
}

private struct BranchingCoralShape: Shape {
    var bend: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        path.move(to: CGPoint(x: w * 0.52, y: h))
        path.addCurve(to: CGPoint(x: w * (0.43 + bend), y: h * 0.08),
                      control1: CGPoint(x: w * 0.54, y: h * 0.68),
                      control2: CGPoint(x: w * (0.39 + bend * 0.72), y: h * 0.36))

        path.move(to: CGPoint(x: w * 0.48, y: h * 0.66))
        path.addCurve(to: CGPoint(x: w * (0.16 + bend * 0.68), y: h * 0.29),
                      control1: CGPoint(x: w * 0.38, y: h * 0.52),
                      control2: CGPoint(x: w * (0.24 + bend * 0.45), y: h * 0.47))

        path.move(to: CGPoint(x: w * 0.46, y: h * 0.48))
        path.addCurve(to: CGPoint(x: w * (0.74 + bend * 1.12), y: h * 0.17),
                      control1: CGPoint(x: w * 0.57, y: h * 0.38),
                      control2: CGPoint(x: w * (0.68 + bend * 0.78), y: h * 0.31))

        path.move(to: CGPoint(x: w * 0.28, y: h * 0.43))
        path.addCurve(to: CGPoint(x: w * (0.10 + bend * 0.54), y: h * 0.10),
                      control1: CGPoint(x: w * 0.20, y: h * 0.34),
                      control2: CGPoint(x: w * (0.13 + bend * 0.40), y: h * 0.22))

        return path
    }
}

// MARK: Plants

/// Small grass-like plants distributed over the foreground. Their roots are
/// covered by the near sand bank and every blade gets a slightly different
/// current, avoiding the synchronized metronome look.
private struct SeaPlantField: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    private let plants: [(CGFloat, CGFloat, Double)] = [
        // Lower shoulder plants: still lively, but kept clear of the equation.
        (0.035, 0.58, 0.2), (0.105, 0.76, 1.4), (0.185, 0.52, 3.1),
        (0.270, 0.60, 4.6),
        // A short foreground garden directly beneath the equation.
        (0.365, 0.28, 2.5), (0.435, 0.34, 5.6), (0.500, 0.30, 0.8),
        (0.565, 0.36, 3.7), (0.635, 0.27, 1.9),
        // An intentionally different rhythm on the right shoulder.
        (0.730, 0.58, 2.2), (0.810, 0.50, 5.3),
        (0.895, 0.74, 3.8), (0.970, 0.56, 0.9)
    ]

    var body: some View {
        GeometryReader { proxy in
            let baseHeight = isPad ? 112.0 : 82.0
            let rootY = proxy.size.height - (isPad ? 31.0 : 24.0)

            ForEach(Array(plants.enumerated()), id: \.offset) { index, plant in
                SeaPlant(palette: palette,
                         clock: clock,
                         phase: plant.2,
                         isPad: isPad)
                    .frame(width: (isPad ? 88 : 62) * min(1, max(0.58, plant.1)),
                           height: baseHeight * plant.1)
                    .position(x: proxy.size.width * plant.0,
                              y: rootY - baseHeight * plant.1 / 2)
                    .opacity(plant.1 < 0.40 ? 0.84 : (index == 2 || index == 10 ? 0.82 : 1))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SeaPlant: View {
    let palette: ReefPalette
    let clock: Double
    let phase: Double
    let isPad: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .bottom) {
                ForEach(0..<4, id: \.self) { blade in
                    let bladePhase = phase + Double(blade) * 1.15
                    let sway = sin(clock * (0.60 + Double(blade) * 0.045) + bladePhase)
                    let ripple = sin(clock * 1.16 + bladePhase * 1.4)
                    let bladeHeight = height * (0.62 + CGFloat(blade) * 0.105)

                    PlantBladeShape(bend: CGFloat(sway) * 0.31
                                          + CGFloat(ripple) * 0.06
                                          + CGFloat(blade - 1) * 0.08)
                        .stroke(
                            LinearGradient(colors: [palette.plantLight, palette.plant],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: isPad ? 7 : 5,
                                               lineCap: .round)
                        )
                        .frame(width: width, height: bladeHeight)
                        .offset(x: CGFloat(blade - 1) * width * 0.09)
                }
            }
            .frame(width: width, height: height)
        }
    }
}

private struct PlantBladeShape: Shape {
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.midX + rect.width * bend, y: rect.minY),
                      control1: CGPoint(x: rect.midX, y: rect.height * 0.68),
                      control2: CGPoint(x: rect.midX + rect.width * bend * 1.4,
                                        y: rect.height * 0.30))
        return path
    }
}

// MARK: The sum

/// The equation is printed directly on the coral. It changes with a short
/// dissolve, but deliberately has no card, panel, cavity or own background.
private struct CoralQuestion: View {
    let prompt: String
    let roundID: UUID?
    let palette: ReefPalette
    let isPad: Bool

    @State private var shownPrompt = ""
    @State private var isVisible = true

    var body: some View {
        VStack(spacing: isPad ? 4 : 1) {
            Text(verbatim: shownPrompt)
                .font(.system(size: isPad ? 46 : 35,
                              weight: .black, design: .rounded))
                .minimumScaleFactor(0.32)
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: palette.coralDeep.opacity(0.95), radius: 1, y: 3)
        }
        .padding(.horizontal, isPad ? 12 : 8)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear {
            shownPrompt = prompt
        }
        .onChange(of: roundID) { _, _ in revealNewQuestion() }
        .accessibilityIdentifier("question-card")
        .accessibilityLabel(Text(L("game.question \(prompt)")))
    }

    private func revealNewQuestion() {
        guard !shownPrompt.isEmpty else {
            shownPrompt = prompt
            return
        }
        withAnimation(.easeOut(duration: 0.10)) { isVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            shownPrompt = prompt
            withAnimation(.easeOut(duration: 0.20)) { isVisible = true }
        }
    }
}
