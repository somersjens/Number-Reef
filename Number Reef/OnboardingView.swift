//
//  OnboardingView.swift
//  Elephant Challenge: Math Memory
//
//  Welcome flow: name → topic → how many answer cards a round shows. The third
//  step doubles as the difficulty choice (2 cards easy, 3 medium, 4 hard).
//

import SwiftUI
import UIKit

struct OnboardingView: View {
    @AppStorage(GameSettings.playerNameKey) private var playerName = ""
    @AppStorage(GameSettings.onboardingCompleteKey) private var isComplete = false
    @AppStorage(GameSettings.topicKey) private var topicRaw = MathTopic.allCases[0].rawValue
    @AppStorage(GameSettings.cardCountKey) private var cardCountRaw = CardCount.allCases[0].rawValue
    @ObservedObject private var language = LanguageManager.shared
    @State private var step = 0
    @FocusState private var isNameFieldFocused: Bool

    private var isPad: Bool { AppLayout.isPad }
    private var contentWidth: CGFloat { isPad ? 640 : 500 }

    var body: some View {
        ZStack {
            onboardingBackground

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Image("no_background")
                            .resizable()
                            .scaledToFit()
                            .frame(width: isPad ? (step == 1 ? 160 : 210) : (step == 1 ? 112 : 150),
                                   height: isPad ? (step == 1 ? 160 : 210) : (step == 1 ? 112 : 150))
                            .padding(.bottom, isPad ? (step == 1 ? 20 : 30) : (step == 1 ? 14 : 22))
                            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: step)

                        Group {
                            switch step {
                            case 0: nameStep
                            case 1: subjectStep
                            default:
                                cardCountStep(
                                    availableWidth: min(
                                        contentWidth,
                                        max(0, proxy.size.width - (isPad ? 72 : 48))
                                    )
                                )
                            }
                        }
                        .id(step)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .frame(maxWidth: contentWidth)
                        .padding(.horizontal, isPad ? 36 : 24)
                    }
                    .padding(.vertical, isPad ? 40 : 28)
                    // On normal-height screens this fills the viewport and
                    // centres the welcome content. On smaller screens the
                    // content simply grows taller and remains scrollable.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(Color(red: 0.43, green: 0.20, blue: 0.03))
        .overlay(alignment: .topLeading) {
            // Steps 2 and 3 can step back to correct a wrong choice. Mirrors
            // the language flag: same glass style, same top inset, left corner.
            if step > 0 {
                backButton
                    .padding(.top, isPad ? 20 : 8)
                    .padding(.leading, isPad ? 28 : 16)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            LanguagePicker(tint: Color(red: 0.43, green: 0.20, blue: 0.03).opacity(0.6),
                           scale: isPad ? 1.25 : 1)
                .padding(.top, isPad ? 20 : 8)
                .padding(.trailing, isPad ? 28 : 16)
        }
    }

    private var backButton: some View {
        Button {
            advance(to: step - 1)
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: isPad ? 26 : 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.43, green: 0.20, blue: 0.03).opacity(0.6))
                .padding(.horizontal, isPad ? 16 : 13)
                .padding(.vertical, isPad ? 11 : 8)
                .liquidGlassCapsule()
                .contentShape(Capsule())
        }
        .accessibilityLabel(Text("common.back"))
    }

    private var onboardingBackground: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.24), Color.yellow.opacity(0.13)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var nameStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                OnboardingTitle(
                    text: L("onboarding.name.title"),
                    fontSize: isPad ? 44 : 35
                )

                Text("onboarding.name.subtitle")
                    .font(isPad ? .title2.weight(.medium) : .title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            TextField(String(), text: $playerName, prompt: Text("name.placeholder"))
                .font(.system(size: isPad ? 34 : 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($isNameFieldFocused)
                .textContentType(.name)
                .submitLabel(.next)
                .onSubmit { goToSubjects() }
                .padding(.horizontal, isPad ? 22 : 16)
                .padding(.vertical, isPad ? 18 : 14)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isNameFieldFocused ? Color.orange : .brown.opacity(0.18),
                                lineWidth: isNameFieldFocused ? 2 : 1)
                )
                .frame(maxWidth: isPad ? 400 : 300)
                .animation(.snappy(duration: 0.2), value: isNameFieldFocused)

            Button("common.continue") { goToSubjects() }
                .buttonStyle(OnboardingButtonStyle(isPad: isPad))
                .frame(maxWidth: isPad ? 360 : .infinity)
        }
    }

    private var subjectStep: some View {
        VStack(spacing: 14) {
            OnboardingTitle(
                text: L("onboarding.subject.title"),
                fontSize: isPad ? 42 : 32
            )

            Text("onboarding.subject.subtitle")
                .font(isPad ? .title3 : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            VStack(spacing: 8) {
                ForEach(MathTopic.allCases) { option in
                    Button {
                        topicRaw = option.rawValue
                        advance(to: 2)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.symbolName)
                                .font(.system(size: isPad ? 28 : 21, weight: .bold))
                                .frame(width: isPad ? 44 : 30)
                            Text(verbatim: L(key: option.titleKey))
                                .font(isPad ? .title3.weight(.semibold) : .title3.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, isPad ? 26 : 16)
                        .frame(maxWidth: .infinity, minHeight: isPad ? 72 : 54)
                        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(OnboardingOptionStyle())
                    .accessibilityIdentifier("onboarding-topic-\(option.rawValue)")
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    /// The third step: how many answer cards a round lays out. Fewer cards
    /// means fewer possible answers, so this is also the difficulty choice.
    private func cardCountStep(availableWidth: CGFloat) -> some View {
        let choiceSizing = cardChoiceSizing(availableWidth: availableWidth)

        return VStack(spacing: 14) {
            OnboardingTitle(
                text: L("onboarding.cards.title"),
                fontSize: isPad ? 42 : 32
            )

            Text("onboarding.cards.subtitle")
                .font(isPad ? .title3 : .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ForEach(CardCount.allCases) { option in
                Button { select(option) } label: {
                    OnboardingChoiceLabel(
                        title: L(key: "onboarding.cards.\(option.answerCards)"),
                        subtitle: L(key: option.difficultyDetailKey),
                        icon: option.symbolName,
                        textScale: choiceSizing.scale,
                        allowsTwoLines: choiceSizing.allowsTwoLines,
                        rowHeight: choiceSizing.rowHeight,
                        isSelected: option.rawValue == cardCountRaw
                    )
                }
                .buttonStyle(OnboardingOptionStyle())
                .accessibilityIdentifier("onboarding-cards-\(option.answerCards)")
            }
        }
    }

    /// Uses one shared scale for every card choice, based on the widest title
    /// or subtitle in the active language. If a modest scale-down is not
    /// enough, all three rows grow equally and may use a second line.
    private func cardChoiceSizing(
        availableWidth: CGFloat
    ) -> (scale: CGFloat, allowsTwoLines: Bool, rowHeight: CGFloat) {
        let titles = CardCount.allCases.map { L(key: "onboarding.cards.\($0.answerCards)") }
        let subtitles = CardCount.allCases.map { L(key: $0.difficultyDetailKey) }

        let titleSize: CGFloat = isPad ? 20 : 20
        let subtitleSize: CGFloat = isPad ? 17 : 16
        let titleFont = UIFont.systemFont(ofSize: titleSize, weight: .semibold)
        let subtitleFont = UIFont.systemFont(ofSize: subtitleSize)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: subtitleFont]

        let widestTitle = titles.map {
            ($0 as NSString).size(withAttributes: titleAttributes).width
        }.max() ?? 0
        let widestSubtitle = subtitles.map {
            ($0 as NSString).size(withAttributes: subtitleAttributes).width
        }.max() ?? 0
        let widestText = max(widestTitle, widestSubtitle)

        // Space occupied by the row padding, icon, chevron and HStack gaps.
        // A small safety inset avoids wrapping caused by fractional glyph
        // measurements at different display scales.
        let reservedWidth: CGFloat = isPad ? 168 : 128
        let textWidth = max(1, availableWidth - reservedWidth)
        let requiredScale = min(1, textWidth / max(1, widestText))
        let minimumComfortableScale: CGFloat = isPad ? 0.82 : 0.78
        let allowsTwoLines = requiredScale < minimumComfortableScale
        let scale = max(requiredScale, minimumComfortableScale)
        let rowHeight: CGFloat = isPad
            ? (allowsTwoLines ? 120 : 94)
            : (allowsTwoLines ? 96 : 70)

        return (scale, allowsTwoLines, rowHeight)
    }

    private func goToSubjects() {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        playerName = trimmedName.isEmpty ? L("home.defaultName") : trimmedName
        isNameFieldFocused = false
        advance(to: 1)
    }

    private func advance(to newStep: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            step = newStep
        }
    }

    /// Stores the chosen card count and hands over to the home screen. The
    /// selection is written first so the tick is visible for the moment the
    /// welcome flow fades out.
    private func select(_ option: CardCount) {
        // The selection lands first so the tick is visible while the flow
        // hands over, rather than the screen swapping out from under the tap.
        withAnimation(.snappy(duration: 0.18)) {
            cardCountRaw = option.rawValue
        }
        AppAudio.shared.playMenuTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isComplete = true
        }
    }
}

/// Keeps translated onboarding headings compact without leaving an orphaned
/// word on the second line. A short heading is allowed to remain on one line;
/// otherwise the fallback inserts the most visually even word-boundary break.
private struct OnboardingTitle: View {
    let text: String
    let fontSize: CGFloat

    private var normalizedText: String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var balancedText: String {
        Self.balancedTwoLineText(normalizedText, fontSize: fontSize)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // `fixedSize` makes this candidate report its true one-line width,
            // so ViewThatFits only chooses it when it genuinely fits.
            titleText(normalizedText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)

            titleText(balancedText)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(verbatim: normalizedText))
    }

    private func titleText(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
    }

    private static func balancedTwoLineText(_ text: String, fontSize: CGFloat) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return text }

        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let font = baseFont.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: fontSize) } ?? baseFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        var bestIndex = 1
        var smallestDifference = CGFloat.greatestFiniteMagnitude

        for index in 1..<words.count {
            let firstLine = words[..<index].joined(separator: " ")
            let secondLine = words[index...].joined(separator: " ")
            let firstWidth = (firstLine as NSString).size(withAttributes: attributes).width
            let secondWidth = (secondLine as NSString).size(withAttributes: attributes).width
            let difference = abs(firstWidth - secondWidth)

            if difference < smallestDifference {
                smallestDifference = difference
                bestIndex = index
            }
        }

        return words[..<bestIndex].joined(separator: " ")
            + "\n"
            + words[bestIndex...].joined(separator: " ")
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    let isPad: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isPad ? .title3.weight(.bold) : .headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, isPad ? 22 : 15)
            .background(.orange, in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct OnboardingOptionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.52 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct OnboardingChoiceLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let textScale: CGFloat
    let allowsTwoLines: Bool
    let rowHeight: CGFloat
    /// The topic step has no persisted choice yet, so it opts out.
    var isSelected = false
    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
            .font(isPad ? .title2 : .title3)
            .frame(width: isPad ? 44 : 30)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20 * textScale, weight: .semibold))
                    .lineLimit(allowsTwoLines ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: (isPad ? 17 : 16) * textScale))
                    .lineLimit(allowsTwoLines ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // A tick on the active choice, a chevron on the rest, so the
            // selected option is unmistakable.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.forward")
                .font(isSelected ? .title3.weight(.bold) : .footnote.weight(.bold))
                .foregroundStyle(isSelected ? .orange : .secondary)
        }
        .padding(.horizontal, isPad ? 26 : 16)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(isSelected ? AnyShapeStyle(Color.orange.opacity(0.16))
                               : AnyShapeStyle(.white.opacity(0.78)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(isSelected ? 0.9 : 0), lineWidth: 2.5)
        )
        .foregroundStyle(Color(red: 0.43, green: 0.20, blue: 0.03))
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
