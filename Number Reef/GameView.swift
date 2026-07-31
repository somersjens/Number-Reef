//
//  GameView.swift
//  Math Memory
//
//  The playing surface. A round runs answers-first: the cards lie face up long
//  enough to be memorised, a tap turns them over and brings the question up,
//  and from then on the player is working from memory.
//
//  All rules live in `MemoryGame`; this file only renders its state and drives
//  the timed transitions. Every tap is handed straight to the engine, which is
//  the single place that decides whether it counts.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Everything a session needs to start: which level to draw questions from and
/// how many answer cards each round lays out.
struct GameSessionRequest: Identifiable {
    let level: MathLevel
    let cardCount: CardCount
    /// Only meaningful for Supermix levels; every other topic has one operation.
    var mixedVariant: MixedVariant = .all
    var id: String { "\(level.id).\(cardCount.rawValue).\(mixedVariant.rawValue)" }

    /// The scoreboard this session plays on.
    var board: LevelBoard {
        LevelBoard(level: level, cardCount: cardCount, mixedVariant: mixedVariant)
    }
}

struct GameView: View {
    let request: GameSessionRequest

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var language = LanguageManager.shared
    @StateObject private var model: GameViewModel

    /// The level's start card, shown before the first round and dismissed by
    /// the player. The session only begins once it is gone.
    @State private var showsIntro = true

    init(request: GameSessionRequest) {
        self.request = request
        _model = StateObject(wrappedValue: GameViewModel(request: request))
    }

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        ZStack {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // The level's own wallpaper, exactly as the original game had it.
            LevelWallpaper(level: request.level, tint: character.color)
                .ignoresSafeArea()

            if model.isGameOver {
                ResultView(result: model.result,
                           board: request.board,
                           character: character,
                           onPlayAgain: { model.restart() },
                           onExit: { dismiss() })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                playfield
                    .transition(.opacity)
            }

            if showsIntro {
                LevelIntroCard(board: request.board,
                               theme: character,
                               onStart: startSession,
                               onExit: { dismiss() })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.isGameOver)
        .animation(.easeInOut(duration: 0.25), value: showsIntro)
        .onDisappear { model.end() }
    }

    private func startSession() {
        showsIntro = false
        model.begin()
    }

    // MARK: - Playfield

    private var playfield: some View {
        VStack(spacing: 0) {
            hud
                .padding(.horizontal, isPad ? 28 : 16)
                .padding(.top, isPad ? 12 : 6)

            Spacer(minLength: 8)

            questionArea
                .padding(.horizontal, isPad ? 40 : 20)

            Spacer(minLength: 12)

            answerArea
                .padding(.horizontal, isPad ? 40 : 16)

            Spacer(minLength: 8)

            flamethrowerButton
                .padding(.bottom, isPad ? 28 : 18)
        }
    }

    // MARK: - HUD

    private var hud: some View {
        ZStack {
            progressCounter

            HStack(spacing: 10) {
                pauseButton
                Spacer(minLength: 0)
                LivesView(lives: model.livesRemaining,
                          character: character,
                          isPad: isPad,
                          glyphSize: hudGlyphSize)
            }
        }
    }

    /// Leaving pauses the level: the cards earned so far are banked and the
    /// session is stored, so the level continues from here next time.
    private var pauseButton: some View {
        Button {
            AppAudio.shared.playMenuTap()
            model.quit()
            dismiss()
        } label: {
            // Inverted against the rest of the HUD: the disc carries the theme
            // colour and the bars are punched clean out of it, so the playing
            // field shows through where the glyph used to be.
            Circle()
                .fill(character.deepColor)
                .frame(width: isPad ? 44 : 34, height: isPad ? 44 : 34)
                .overlay {
                    Image(systemName: "pause.fill")
                        .font(.system(size: hudGlyphSize, weight: .bold))
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pause")
        .accessibilityLabel(Text("game.pause"))
    }

    /// Every glyph in the HUD — the pause bars, the card icon and the hearts —
    /// is struck at this one size, so the row reads as a single set.
    private var hudGlyphSize: CGFloat { isPad ? 22 : 16 }

    /// One combined counter: the cards banked this session over what this
    /// board holds, so the HUD and the result card quote the same target.
    private var boardMaximum: Int { request.board.maximum }

    private var progressCounter: some View {
        HStack(spacing: 5) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: hudGlyphSize, weight: .bold))
                Text(verbatim: "\(model.cards)/\(boardMaximum)")
                    .font(.system(size: isPad ? 26 : 19, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.cards)))
            }
        .foregroundStyle(character.deepColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.cards)
        .accessibilityIdentifier("progress")
        .accessibilityLabel(Text(L("game.progress \(model.cards) \(boardMaximum)")))
    }

    // MARK: - Question

    private var questionArea: some View {
        QuestionCard(prompt: model.round?.question.prompt ?? "",
                     isVisible: model.showsQuestion,
                     isDoubleCard: model.round?.isDoubleCard ?? false,
                     character: character,
                     isPad: isPad,
                     // Turning the cards over is deliberately a tap on the
                     // question area, never on an answer: a stray tap on a card
                     // must not cost the memorising beat.
                     onTurnOver: model.state == .memorising ? { model.turnCardsOver() } : nil)
        .id(model.round?.id ?? UUID())
    }

    // MARK: - Answers

    @ViewBuilder
    private var answerArea: some View {
        if let round = model.round, model.showsAnswers {
            AnswerCardGrid(round: round,
                           cardCount: request.cardCount,
                           character: character,
                           isPad: isPad,
                           showsValues: model.showsAnswerValues,
                           selectedID: model.selectedOptionID,
                           burnedIDs: model.burnedOptionIDs,
                           revealsCorrect: model.revealsCorrectAnswer,
                           isInteractive: model.acceptsInput,
                           onSelect: { model.select(optionID: $0) })
        } else {
            // Reserve the space so nothing jumps when the round starts.
            Color.clear.frame(height: isPad ? 300 : 210)
        }
    }

    // MARK: - Flamethrower

    private var flamethrowerButton: some View {
        Button {
            model.useFlamethrower()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: isPad ? 26 : 20, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("game.flamethrower")
                        .font(.system(size: isPad ? 19 : 15, weight: .heavy, design: .rounded))
                    Text("game.flamethrowerCost")
                        .font(.system(size: isPad ? 15 : 11, weight: .semibold, design: .rounded))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isPad ? 30 : 22)
            .padding(.vertical, isPad ? 16 : 12)
            .background(
                LinearGradient(colors: [Color(red: 1.0, green: 0.52, blue: 0.13),
                                        Color(red: 0.88, green: 0.20, blue: 0.10)],
                               startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .shadow(color: .black.opacity(model.canUseFlamethrower ? 0.22 : 0), radius: 8, y: 4)
            .opacity(model.canUseFlamethrower ? 1 : 0.35)
            .scaleEffect(model.isFiring ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!model.canUseFlamethrower)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: model.isFiring)
        .animation(.easeInOut(duration: 0.15), value: model.canUseFlamethrower)
        .accessibilityIdentifier("flamethrower")
        .accessibilityLabel(Text("game.flamethrower"))
        .accessibilityHint(Text("game.flamethrowerCost"))
    }
}

// MARK: - Level wallpaper

/// The level's own quiet wallpaper: a staggered grid of the level's number and
/// sign ("3×", "−4", "25%") or a stacked fraction, in a faint wash of the
/// theme colour. Carried over from the original game.
struct LevelWallpaper: View {
    let level: MathLevel
    let tint: Color

    /// The glyph that fills the wallpaper, built from the level's own card
    /// number so it reads like the level itself. Fractions draw a stacked
    /// fraction instead and return nil here.
    private var glyph: String? {
        let n = level.cardNumber
        switch level.topic {
        case .addition:    return "\(n)+"
        case .subtraction: return "−\(n)"
        case .tables:      return "\(n)×"
        case .percentages: return "\(n)%"
        case .mixed:       return "\(n)★"
        case .fractions:   return nil
        }
    }

    private var isPad: Bool { AppLayout.isPad }
    private var fontSize: CGFloat { isPad ? 30 : 22 }
    private var spacingX: CGFloat { isPad ? 118 : 86 }
    private var spacingY: CGFloat { isPad ? 104 : 76 }

    var body: some View {
        GeometryReader { proxy in
            let columns = Int(ceil(proxy.size.width / spacingX)) + 1
            let rows = Int(ceil(proxy.size.height / spacingY)) + 1

            ZStack {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        tile
                            .position(
                                // Every other row is offset by half a step, so
                                // the pattern staggers instead of gridding.
                                x: CGFloat(column) * spacingX
                                    + (row.isMultiple(of: 2) ? 0 : spacingX / 2),
                                y: CGFloat(row) * spacingY
                            )
                    }
                }
            }
        }
        .foregroundStyle(tint.opacity(0.10))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tile: some View {
        if let glyph {
            Text(verbatim: glyph)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
        } else {
            // The fraction levels have one denominator each, so the wallpaper
            // mirrors it: 1/3 on the thirds level, and so on.
            VStack(spacing: 1) {
                Text(verbatim: "1")
                Rectangle().frame(height: 2)
                Text(verbatim: level.cardNumber)
            }
            .font(.system(size: fontSize * 0.62, weight: .heavy, design: .rounded))
            .fixedSize()
        }
    }
}

// MARK: - Lives

struct LivesView: View {
    let lives: Double
    let character: AnimalCharacter
    let isPad: Bool
    /// Matches the other HUD glyphs exactly.
    var glyphSize: CGFloat = 16

    private var wholeHearts: Int { Int(lives.rounded(.down)) }
    private var hasHalf: Bool { lives - Double(wholeHearts) >= 0.5 }
    private var capacity: Int { Int(GameConfig.startingLives.rounded(.up)) }

    /// Hearts wear the character's own deep colour — the same one the counter
    /// and the close button use — rather than a generic red.
    private var heartColor: Color { character.deepColor }

    var body: some View {
        HStack(spacing: isPad ? 5 : 3) {
            ForEach(0..<capacity, id: \.self) { index in
                heart(at: index)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: lives)
        .accessibilityElement()
        .accessibilityIdentifier("lives")
        .accessibilityLabel(Text(L("game.livesRemaining \(livesText)")))
        .accessibilityValue(Text(verbatim: livesText))
    }

    private var livesText: String {
        // Halves read as "2.5"; whole lives never show a decimal tail.
        lives == lives.rounded() ? "\(Int(lives))" : String(format: "%.1f", lives)
    }

    /// A full, half or empty heart. The half heart is the full glyph masked to
    /// its leading half over the empty one, so the two always align exactly.
    private func heart(at index: Int) -> some View {
        let size = glyphSize
        return ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(heartColor.opacity(0.22))
            if index < wholeHearts {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
            } else if index == wholeHearts && hasHalf {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size / 2)
                    }
            }
        }
        .font(.system(size: size, weight: .bold))
        .frame(width: size, height: size)
    }
}

// MARK: - Question card

/// The question, which is only readable once the answer cards are face down.
private struct QuestionCard: View {
    let prompt: String
    let isVisible: Bool
    let isDoubleCard: Bool
    let character: AnimalCharacter
    let isPad: Bool
    /// Non-nil only during the memorising beat, when tapping here turns the
    /// answer cards over.
    let onTurnOver: (() -> Void)?

    var body: some View {
        Button(action: { onTurnOver?() }) {
            ZStack {
                if isVisible {
                    content
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else {
                    placeholder
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: isPad ? 190 : 138)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onTurnOver == nil)
        .animation(.easeInOut(duration: GameConfig.cardFlipDuration), value: isVisible)
        .accessibilityIdentifier("question-card")
        .accessibilityLabel(Text(isVisible ? L("game.question \(prompt)") : L("game.memorise")))
    }

    private var content: some View {
        VStack(spacing: isPad ? 10 : 6) {
            if isDoubleCard {
                Label("game.doubleCard", systemImage: "sparkles")
                    .font(.system(size: isPad ? 17 : 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.02))
            }
            Text(verbatim: prompt)
                .font(.system(size: isPad ? 62 : 44, weight: .black, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(character.deepColor)
        }
        .padding(.horizontal, isPad ? 30 : 20)
        .frame(maxWidth: .infinity)
        .frame(height: isPad ? 190 : 138)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(isDoubleCard ? Color(red: 0.96, green: 0.72, blue: 0.13)
                                     : character.color.opacity(0.35),
                        lineWidth: isDoubleCard ? 3.5 : 1.5)
        )
        .shadow(color: character.deepColor.opacity(0.14), radius: 10, y: 5)
    }

    /// While the answers are being memorised there is no question yet — just
    /// the instruction to remember them.
    private var placeholder: some View {
        VStack(spacing: isPad ? 10 : 6) {
            Image(systemName: "eye.fill")
                .font(.system(size: isPad ? 34 : 25, weight: .bold))
            Text("game.memorise")
                .font(.system(size: isPad ? 22 : 16, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(character.deepColor.opacity(0.75))
        .padding(.horizontal, isPad ? 30 : 20)
        .frame(maxWidth: .infinity)
        .frame(height: isPad ? 190 : 138)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(character.color.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        )
    }
}

// MARK: - Answer cards

private struct AnswerCardGrid: View {
    let round: GameRound
    let cardCount: CardCount
    let character: AnimalCharacter
    let isPad: Bool
    let showsValues: Bool
    let selectedID: UUID?
    let burnedIDs: Set<UUID>
    let revealsCorrect: Bool
    let isInteractive: Bool
    let onSelect: (UUID) -> Void

    private var spacing: CGFloat { isPad ? 16 : 11 }

    /// How the cards are stacked. Options arrive in ascending order, so index 0
    /// is always the lowest number:
    ///   2 → one row of two
    ///   3 → the lowest on its own on top, the other two beneath
    ///   4 → a 2×2 block
    private var rows: [[AnswerOption]] {
        let options = round.options
        switch options.count {
        case 3:  return [[options[0]], Array(options[1...])]
        case 4:  return [Array(options[0..<2]), Array(options[2...])]
        default: return [options]
        }
    }

    /// Cards come out as close to square as the space allows: a single row gets
    /// the full height, two rows split it.
    private var cardHeight: CGFloat {
        let available: CGFloat = isPad ? 320 : 232
        return (available - spacing * CGFloat(rows.count - 1)) / CGFloat(rows.count)
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowOptions in
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(rowOptions) { option in
                        AnswerCard(option: option,
                                   character: character,
                                   isPad: isPad,
                                   showsValue: showsValues,
                                   isSelected: selectedID == option.id,
                                   isBurned: burnedIDs.contains(option.id),
                                   revealsCorrect: revealsCorrect,
                                   isInteractive: isInteractive,
                                   isDouble: round.isDoubleCard,
                                   height: cardHeight,
                                   onTap: { onSelect(option.id) })
                    }
                    // The lone top card keeps the width of one card in the row
                    // below rather than stretching across both. The filler is
                    // pinned to the card height — `Color` is greedy in both
                    // directions, and left unbounded it forces the rows apart.
                    if rowOptions.count == 1 && round.options.count == 3 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: cardHeight)
                    }
                }
            }
        }
    }
}

private struct AnswerCard: View {
    let option: AnswerOption
    let character: AnimalCharacter
    let isPad: Bool
    /// Face up (the value is readable) or face down (the back pattern).
    let showsValue: Bool
    let isSelected: Bool
    let isBurned: Bool
    let revealsCorrect: Bool
    let isInteractive: Bool
    let isDouble: Bool
    let height: CGFloat
    let onTap: () -> Void

    @State private var isPressed = false

    private var correctGreen: Color { Color(red: 0.19, green: 0.68, blue: 0.35) }
    private var wrongRed: Color { Color(red: 0.85, green: 0.22, blue: 0.22) }

    private var showsAsCorrect: Bool { revealsCorrect && option.isCorrect }
    private var showsAsWrong: Bool { isSelected && !option.isCorrect }

    var body: some View {
        Button(action: tapped) {
            ZStack {
                if showsValue {
                    face
                } else {
                    back
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // The flip is a half-turn of the card with the *content*
            // counter-rotated, so neither face is ever mirrored.
            .rotation3DEffect(.degrees(showsValue ? 0 : 180),
                              axis: (x: 0, y: 1, z: 0),
                              perspective: 0.35)
            .opacity(isBurned ? 0.18 : 1)
            .rotationEffect(.degrees(isBurned ? -4 : 0))
            .scaleEffect(isPressed ? 0.96 : (isSelected ? 1.03 : 1))
            .animation(.easeInOut(duration: GameConfig.cardFlipDuration), value: showsValue)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .animation(.easeOut(duration: 0.22), value: isBurned)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive || isBurned)
        .accessibilityIdentifier("answer-card")
        .accessibilityLabel(Text(verbatim: option.text))
        .accessibilityValue(Text(verbatim: option.isCorrect ? "correct" : "wrong"))
        .accessibilityAddTraits(.isButton)
    }

    /// The readable side of the card.
    private var face: some View {
        Text(verbatim: option.text)
            .font(.system(size: isPad ? 40 : 30, weight: .black, design: .rounded))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor, lineWidth: isDouble ? 3.5 : 2)
            )
            .overlay { if isBurned { burnOverlay } }
            .shadow(color: character.deepColor.opacity(0.12), radius: 6, y: 3)
    }

    /// The face-down side: the card's back, with nothing to read.
    private var back: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [character.color, character.deepColor],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: isDouble ? 3.5 : 2)
            )
            .overlay {
                Image(systemName: "questionmark")
                    .font(.system(size: isPad ? 32 : 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    // Undo the parent's half-turn so the glyph is not mirrored.
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(height: height)
            .shadow(color: character.deepColor.opacity(0.18), radius: 6, y: 3)
    }

    private var fill: Color {
        if showsAsWrong { return wrongRed.opacity(0.16) }
        if showsAsCorrect { return correctGreen.opacity(0.18) }
        return .white.opacity(0.92)
    }

    private var textColor: Color {
        if showsAsWrong { return wrongRed }
        if showsAsCorrect { return correctGreen }
        return character.deepColor
    }

    private var borderColor: Color {
        if showsAsWrong { return wrongRed }
        if showsAsCorrect { return correctGreen }
        if isDouble { return Color(red: 0.96, green: 0.72, blue: 0.13) }
        return character.color.opacity(0.4)
    }

    private var burnOverlay: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.black.opacity(0.22))
            .overlay {
                Image(systemName: "flame.fill")
                    .font(.system(size: isPad ? 30 : 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.12))
            }
    }

    /// Presses feel immediate: the scale-down happens on the spot, and the
    /// engine decides whether the tap counts.
    private func tapped() {
        guard isInteractive, !isBurned else { return }
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { isPressed = false }
        onTap()
    }
}
