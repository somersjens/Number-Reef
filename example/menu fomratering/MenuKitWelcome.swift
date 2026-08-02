//
//  MenuKitWelcome.swift
//  MenuKit — overgenomen uit Jumping Fox
//
//  Welkomstscherm 2 en 3.
//
//  Scherm 2 kiest het ONDERWERP (dezelfde lijst als de cirkels in het menu).
//  Scherm 3 kiest het STARTNIVEAU, en dat is precies dezelfde keuze als de drie
//  knoppen Reeks · Hussel · Gemixt — alleen in kindertaal:
//
//      "Net begonnen"      → .order   (Reeks)
//      "Al wat geoefend"   → .random  (Hussel)
//      "Al aardig goed"    → .mixed   (Gemixt)
//
//  Koos het kind in scherm 2 de ster (die heeft geen volgorde-knoppen), dan
//  wordt dezelfde keuze afgebeeld op de eenvoudigste respectievelijk de meest
//  complete sterknop.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Scherm 2: onderwerp

struct WelcomeTopicStep: View {
    @ObservedObject var selection: MenuSelectionStore
    var onChosen: () -> Void
    @Environment(\.menuKitTheme) private var theme

    private var isPad: Bool { MenuKitLayout.isPad }

    var body: some View {
        VStack(spacing: 14) {
            WelcomeTitle(text: MKText("onboarding.subject.title"),
                         fontSize: isPad ? 42 : 32)

            Text(MKText("onboarding.subject.subtitle"))
                .font(isPad ? .title3 : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            VStack(spacing: 8) {
                ForEach(MenuKitConfig.topics) { topic in
                    Button {
                        selection.topicID = topic.id      // direct, geen sprong
                        onChosen()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: topic.icon)
                                .font(.system(size: isPad ? 28 : 21, weight: .bold))
                                .frame(width: isPad ? 44 : 30)
                            Text(MKText(topic.titleKey))
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, isPad ? 26 : 16)
                        .frame(maxWidth: .infinity, minHeight: isPad ? 72 : 54)
                        .background(.white.opacity(0.78),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(WelcomeOptionStyle())
                    .foregroundStyle(theme.accent)
                }
            }
        }
    }
}

// MARK: - Scherm 3: startniveau (= de drie volgorde-knoppen)

struct WelcomeLevelStep: View {
    @ObservedObject var selection: MenuSelectionStore
    /// De breedte die de inhoud werkelijk krijgt; nodig om alle drie de rijen op
    /// dezelfde schaal te kunnen zetten.
    var availableWidth: CGFloat
    var onFinished: () -> Void

    private var isPad: Bool { MenuKitLayout.isPad }

    /// De drie keuzes, in dezelfde volgorde als de knoppen in het menu.
    private static let choices: [(mode: PracticeMode, titleKey: String, subtitleKey: String, icon: String)] = [
        (.order,  "onboarding.level.beginner.title",     "onboarding.level.beginner.subtitle",     "leaf.fill"),
        (.random, "onboarding.level.intermediate.title", "onboarding.level.intermediate.subtitle", "shuffle"),
        (.mixed,  "onboarding.level.advanced.title",     "onboarding.level.advanced.subtitle",     "bolt.fill")
    ]

    var body: some View {
        let sizing = Self.sizing(availableWidth: availableWidth)
        let topicName = selection.topic.map { MKText($0.titleKey) }
            ?? MKText("onboarding.level.thisTopic")

        return VStack(spacing: 14) {
            WelcomeTitle(text: MKText("onboarding.level.title"),
                         fontSize: isPad ? 42 : 32)

            Text(String(format: MKText("onboarding.level.subtitle"), topicName))
                .font(isPad ? .title3 : .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ForEach(Self.choices, id: \.mode) { choice in
                Button {
                    finish(with: choice.mode)
                } label: {
                    WelcomeChoiceLabel(title: MKText(choice.titleKey),
                                       subtitle: MKText(choice.subtitleKey),
                                       icon: choice.icon,
                                       textScale: sizing.scale,
                                       allowsTwoLines: sizing.allowsTwoLines,
                                       rowHeight: sizing.rowHeight)
                }
                .buttonStyle(WelcomeOptionStyle())
            }
        }
    }

    private func finish(with mode: PracticeMode) {
        selection.modeRaw = mode.rawValue
        // De ster heeft geen eigen volgorde-knoppen — beeld de beginners-/
        // gevorderdenkeuze af op zijn eenvoudigste en zijn meest complete knop.
        if selection.showsSupermixGrid {
            let options = MenuKitConfig.supermixOptions
            let target = (mode == .mixed ? options.last : options.first)
            if let target { selection.supermixID = target.id }
        }
        onFinished()
    }

    /// Gebruikt één gedeelde schaal voor alle drie de keuzes, gebaseerd op de
    /// breedste titel of ondertitel in de actieve taal. Is een bescheiden
    /// verkleining niet genoeg, dan groeien alle drie de rijen even hard en
    /// mogen ze een tweede regel gebruiken.
    static func sizing(availableWidth: CGFloat)
        -> (scale: CGFloat, allowsTwoLines: Bool, rowHeight: CGFloat) {
        let isPad = MenuKitLayout.isPad
        let minimumComfortableScale: CGFloat = isPad ? 0.82 : 0.78

#if canImport(UIKit)
        let titles = choices.map { MKText($0.titleKey) }
        let subtitles = choices.map { MKText($0.subtitleKey) }

        let titleFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
        let subtitleFont = UIFont.systemFont(ofSize: isPad ? 17 : 16)

        let widestTitle = titles
            .map { ($0 as NSString).size(withAttributes: [.font: titleFont]).width }
            .max() ?? 0
        let widestSubtitle = subtitles
            .map { ($0 as NSString).size(withAttributes: [.font: subtitleFont]).width }
            .max() ?? 0
        let widestText = max(widestTitle, widestSubtitle)

        // Ruimte die de rijpadding, het icoon, de chevron en de tussenruimtes
        // innemen. De kleine veiligheidsmarge voorkomt afbreken door
        // fractionele glyphmetingen op verschillende schermschalen.
        let reservedWidth: CGFloat = isPad ? 168 : 128
        let textWidth = max(1, availableWidth - reservedWidth)
        let requiredScale = min(1, textWidth / max(1, widestText))
        let allowsTwoLines = requiredScale < minimumComfortableScale
        let scale = max(requiredScale, minimumComfortableScale)
#else
        let allowsTwoLines = false
        let scale: CGFloat = 1
#endif
        let rowHeight: CGFloat = isPad
            ? (allowsTwoLines ? 120 : 94)
            : (allowsTwoLines ? 96 : 70)
        return (scale, allowsTwoLines, rowHeight)
    }
}

// MARK: - Onderdelen

struct WelcomeChoiceLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let textScale: CGFloat
    let allowsTwoLines: Bool
    let rowHeight: CGFloat
    @Environment(\.menuKitTheme) private var theme
    private var isPad: Bool { MenuKitLayout.isPad }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(isPad ? .title2 : .title3)
                .frame(width: isPad ? 44 : 30)
                .foregroundStyle(theme.accent)
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
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, isPad ? 26 : 16)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(.white.opacity(0.78),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(theme.deep)
    }
}

struct WelcomeOptionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.52 : 0),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

/// Houdt vertaalde koppen compact zonder een los woord op de tweede regel. Een
/// korte kop mag op één regel blijven; anders wordt de meest gelijkmatige
/// woordafbreking gekozen.
struct WelcomeTitle: View {
    let text: String
    let fontSize: CGFloat

    private var normalizedText: String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // `fixedSize` laat deze kandidaat zijn échte breedte op één regel
            // rapporteren, zodat ViewThatFits hem alleen kiest als hij past.
            titleText(normalizedText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)

            titleText(Self.balancedTwoLineText(normalizedText, fontSize: fontSize))
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

    static func balancedTwoLineText(_ text: String, fontSize: CGFloat) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return text }
#if canImport(UIKit)
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
#else
        return text
#endif
    }
}
