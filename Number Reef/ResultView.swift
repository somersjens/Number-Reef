//
//  ResultView.swift
//  Math Memory
//
//  The end-of-session card, restored to the original layout: the character, a
//  title, a word of encouragement, the score out of what the level holds, and
//  the two ways onward. Only the unit has changed — cards instead of trophies.
//

import SwiftUI

struct ResultView: View {
    let result: SessionResult
    /// Which scoreboard was played: it sets what a full score is worth here.
    let board: LevelBoard
    let character: AnimalCharacter
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    @State private var isPresented = false
    @State private var badgeLanded = false
    @State private var shineSweep = false
    @State private var showsConfetti = false

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }
    private var textScale: CGFloat { isPad ? 1.296 : 1 }

    private var maximum: Int { board.maximum }
    /// The level's score tops out at its maximum, exactly as the menu stores
    /// it; cards beyond that still count toward the player's grand total.
    private var levelScore: Int { min(result.cardsEarned, maximum) }
    private var showsNewBest: Bool { result.isNewPersonalBest && result.cardsEarned > 0 }

    /// Ten graded messages, keyed `game.encouragement.0 … .9`, scaled to what
    /// this level actually holds.
    private var encouragement: String {
        let step = max(1, maximum / 10)
        let index = min(max(result.cardsEarned, 0) / step, 9)
        return L(key: "game.encouragement.\(index)")
    }

    private var titleKey: LocalizedStringKey {
        switch result.reason {
        case .outOfLives:      return "game.end.gameOverTitle"
        case .roundsCompleted: return "result.complete"
        case .quit:            return "result.stopped"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    card
                        .padding(26 * scale)
                        .frame(maxWidth: 400 * scale)
                        .background(
                            LinearGradient(colors: [character.skyColor, .white, character.tintColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.82), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : 0.93)
            .offset(y: isPresented ? 0 : 18)

            // Layered above the card, so the burst rains over the result rather
            // than behind it. It starts once the card entrance is underway.
            if showsConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                isPresented = true
            }
            // Only a score this level has never seen before rains confetti;
            // matching or falling short of the old best ends quietly.
            guard showsNewBest else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                showsConfetti = true
            }
            // The badge drops in after the card has settled, then glints once.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.52)) {
                    badgeLanded = true
                }
                withAnimation(.easeInOut(duration: 0.7).delay(0.22)) {
                    shineSweep = true
                }
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            character.artwork
                .resizable()
                .scaledToFit()
                .frame(width: 130 * scale, height: 104 * scale)
                .accessibilityHidden(true)
                .padding(.bottom, 18 * scale)

            Text(titleKey)
                .font(.system(size: 32 * textScale, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(verbatim: encouragement)
                .font(.system(size: 20 * textScale, weight: .semibold))
                .foregroundStyle(character.deepColor.opacity(0.64))
                .multilineTextAlignment(.center)
                .padding(.top, 10 * scale)
                .frame(minHeight: 30 * scale)

            scoreCapsule
                .padding(.top, 22 * scale)

            if !result.unlockedCharacterIDs.isEmpty {
                unlockedRow
                    .padding(.top, 20 * scale)
            }

            buttons
                .padding(.top, 24 * scale)
        }
    }

    private var scoreCapsule: some View {
        Text(verbatim: "\(levelScore) / \(maximum)")
            // Keep "x / y" from flipping around.
            .environment(\.layoutDirection, .leftToRight)
            .font(.system(size: 30 * textScale, weight: .heavy, design: .rounded))
            .foregroundStyle(character.color)
            .padding(.horizontal, 27 * scale)
            .padding(.vertical, 10 * scale)
            .background(character.tintColor, in: Capsule())
            .overlay { Capsule().stroke(character.color.opacity(0.12), lineWidth: 1) }
            // The smaller capsule deliberately sits just beyond the score's
            // top-right corner, leaving the tally itself unobscured.
            .overlay(alignment: .topTrailing) {
                if showsNewBest {
                    newBestBadge
                        .offset(x: 30, y: -16)
                        .scaleEffect(badgeLanded ? 1 : 0.4)
                        .rotationEffect(.degrees(badgeLanded ? 0 : -18))
                        .opacity(badgeLanded ? 1 : 0)
                }
            }
            .accessibilityIdentifier("score")
            .accessibilityLabel(Text(L("game.accessibility.scoreOutOf \(levelScore) \(maximum)")))
    }

    private var newBestBadge: some View {
        HStack(spacing: 4) {
            Text("game.highScore")
                .lineLimit(1)
            Image(systemName: "rectangle.stack.fill")
        }
        // The badge is an overlay pinned to the score capsule's width, so a long
        // translation would wrap; fixedSize lets it grow on one line instead.
        .fixedSize()
        .font(.system(size: 13 * textScale, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10 * textScale)
        .padding(.vertical, 6 * textScale)
        .background(character.color, in: Capsule())
        // A soft diagonal highlight sweeps across once as the badge lands.
        // Clipped to the capsule and starting off-badge, it is invisible before
        // and after that single pass — no fade bookkeeping needed.
        .overlay {
            Capsule()
                .fill(
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 26)
                .rotationEffect(.degrees(18))
                .offset(x: shineSweep ? 90 : -90)
                .allowsHitTesting(false)
        }
        .clipShape(Capsule())
        .accessibilityIdentifier("new-best")
    }

    private var unlockedRow: some View {
        VStack(spacing: 8) {
            Text("result.unlocked")
                .font(.system(size: 15 * textScale, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)
            HStack(spacing: 14) {
                ForEach(result.unlockedCharacterIDs, id: \.self) { id in
                    let animal = CharacterCatalog.character(id: id)
                    VStack(spacing: 4) {
                        animal.artwork
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50 * scale, height: 50 * scale)
                        Text(verbatim: animal.localizedName)
                            .font(.system(size: 11 * textScale, weight: .bold, design: .rounded))
                            .foregroundStyle(character.deepColor)
                    }
                }
            }
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var buttons: some View {
        VStack(spacing: 12 * scale) {
            Button(action: onPlayAgain) {
                Label("game.end.playAgain", systemImage: "arrow.counterclockwise")
                    .font(isPad ? .title3.weight(.bold) : .headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * scale)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("play-again")

            Button(action: onExit) {
                Label("game.end.mainMenu", systemImage: "house.fill")
                    .font(isPad ? .title3.weight(.semibold) : .headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * scale)
                    .foregroundStyle(character.deepColor)
                    .background(character.skyColor, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(character.color.opacity(0.24), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("back-to-menu")
        }
    }
}

/// Lightweight falling-confetti burst for a new personal best.
private struct ConfettiView: View {
    @State private var pieces: [ConfettiPiece]
    @State private var fallen = false

    init() {
        _pieces = State(initialValue: (0..<44).map { _ in ConfettiPiece() })
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    Rectangle()
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size * 0.5)
                        .rotationEffect(.degrees(fallen ? piece.spin : 0))
                        .position(x: piece.x * proxy.size.width,
                                  y: fallen ? proxy.size.height + 40 : -40)
                        .opacity(fallen ? 0 : 1)
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay),
                                   value: fallen)
                }
            }
        }
        // A short real-time gap guarantees the initial above-screen positions
        // have been presented before the fall begins. The pieces live in State,
        // so their identities and random paths stay stable across body updates.
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { fallen = true }
        }
        .accessibilityHidden(true)
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x = CGFloat.random(in: 0...1)
    let size = CGFloat.random(in: 7...13)
    let spin = Double.random(in: 180...900)
    let duration = Double.random(in: 1.4...2.6)
    let delay = Double.random(in: 0...0.5)
    let color: Color = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
        .randomElement()!
}
