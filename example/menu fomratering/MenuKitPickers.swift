//
//  MenuKitPickers.swift
//  MenuKit — overgenomen uit Jumping Fox
//
//  De drie besturingsrijen van het menu:
//  1. `MenuTopicPicker`     — de rij ronde onderwerp-knoppen (+ − × ÷ % ★)
//  2. `MenuModePicker`      — Reeks · Hussel · Gemixt
//  3. `MenuSupermixPicker`  — de vier knoppen van de ster (2×2)
//
//  Alle drie werken hetzelfde:
//  · tik op een andere knop  → selecteren (met geluid en sprong)
//  · tik op de knop die al geselecteerd is → info-pop-out eronder
//

import SwiftUI

// MARK: - Alles in één

/// De complete besturing: de onderwerp-cirkels, met daaronder óf de drie
/// volgorde-knoppen, óf — bij het ster-onderwerp — het 2×2 sterrooster.
struct MenuControlStack: View {
    @ObservedObject var selection: MenuSelectionStore
    @ObservedObject var popout: InfoPopoutController
    var spacing: CGFloat = MenuKitLayout.isPad ? 22 : 11

    var body: some View {
        VStack(spacing: spacing) {
            MenuTopicPicker(selection: selection, popout: popout)

            if selection.showsSupermixGrid {
                MenuSupermixPicker(selection: selection, popout: popout)
            } else {
                MenuModePicker(selection: selection, popout: popout)
            }
        }
    }
}

// MARK: - 1. De onderwerp-cirkels

/// Lijnt de buitenste knoppen uit met de knoppen eronder over de volle breedte:
/// de cirkels houden hun vaste aanraakmaat, de tussenruimtes slikken de rest op
/// (op zowel iPhone als iPad).
struct MenuTopicPicker: View {
    @ObservedObject var selection: MenuSelectionStore
    @ObservedObject var popout: InfoPopoutController
    @Environment(\.menuKitTheme) private var theme

    private var diameter: CGFloat { MenuKitLayout.circleDiameter }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(MenuKitConfig.topics.enumerated()), id: \.element.id) { index, topic in
                button(topic)
                    .frame(width: diameter, height: diameter)

                if index < MenuKitConfig.topics.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(_ topic: MenuTopic) -> some View {
        let isSelected = topic.id == selection.topicID
        return Button {
            MenuKit.playTapSound()
            // Een tik op het al geselecteerde onderwerp opent zijn info-pop-out
            // in plaats van het opnieuw te selecteren (wat eerder niets deed).
            if isSelected {
                popout.show(.topic(topic), anchorKey: "topic.\(topic.id)")
            } else {
                selection.select(topicID: topic.id)
            }
        } label: {
            icon(topic, isSelected: isSelected)
                .frame(maxWidth: .infinity)
                .frame(height: diameter)
                .background(isSelected ? theme.deep : theme.idleCircleFill, in: Circle())
                .overlay(Circle().stroke(theme.deep.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
                .reportAnchor("topic.\(topic.id)")
                .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: MKText("menu.accessibility.chooseMode"),
                                   MKText(topic.titleKey)))
    }

    /// Elk onderwerp tekent hetzelfde: een kaal glyph, wit op de geselecteerde
    /// (gevulde) knop en in de themakleur op de omlijnde. De puntgroottes per
    /// symbool vlakken de verschillende optische hoogtes af (de gevulde ster
    /// leest groot, het procentteken hoog) en een gedeelde hoogtebox houdt ze
    /// allemaal op dezelfde lijn.
    private func icon(_ topic: MenuTopic, isSelected: Bool) -> some View {
        let scale = MenuKitLayout.symbolScale
        return Image(systemName: topic.icon)
            .font(.system(size: topic.iconSize * scale, weight: .bold))
            .frame(height: 24 * scale)
            .foregroundStyle(isSelected ? .white : theme.deep)
    }
}

// MARK: - 2. Reeks · Hussel · Gemixt

/// Drie even brede knoppen. Het label blijft op één regel en krimpt om te
/// passen, zodat een langer woord in een andere taal nog steeds met z'n drieën
/// naast elkaar past zonder de basisgrootte van de kortere labels te wijzigen.
struct MenuModePicker: View {
    @ObservedObject var selection: MenuSelectionStore
    @ObservedObject var popout: InfoPopoutController
    @Environment(\.menuKitTheme) private var theme

    private var isPad: Bool { MenuKitLayout.isPad }

    var body: some View {
        HStack(spacing: isPad ? 12 : 8) {
            ForEach(PracticeMode.allCases) { mode in
                button(mode)
            }
        }
    }

    private func button(_ mode: PracticeMode) -> some View {
        let topic = selection.topic
        let isSelected = selection.mode == mode
        return Button {
            MenuKit.playTapSound()
            if isSelected {
                popout.show(.mode(mode, topic), anchorKey: "mode.\(mode.rawValue)")
            } else {
                selection.select(modeRaw: mode.rawValue)
            }
        } label: {
            Text(mode.title(for: topic))
                .font(.system(size: isPad ? 22 : 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isSelected ? .white : theme.deep)
                .frame(maxWidth: .infinity)
                .frame(height: MenuKitLayout.modeButtonHeight)
                .padding(.horizontal, isPad ? 8 : 2)
                .background(isSelected ? theme.deep : theme.idleFill,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.deep.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                .reportAnchor("mode.\(mode.rawValue)")
                .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: MKText("menu.accessibility.chooseMode"),
                                   mode.title(for: topic)))
    }
}

// MARK: - 3. De vier knoppen van de ster

/// De vier supermix-knoppen in een 2×2 rooster; elk is een zelfstandige reeks
/// levels die steeds méér bewerkingen combineert.
struct MenuSupermixPicker: View {
    @ObservedObject var selection: MenuSelectionStore
    @ObservedObject var popout: InfoPopoutController
    @Environment(\.menuKitTheme) private var theme

    private var isPad: Bool { MenuKitLayout.isPad }
    private var spacing: CGFloat { MenuKitLayout.gridSpacing }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: spacing),
                            GridItem(.flexible(), spacing: spacing)],
                  spacing: spacing) {
            ForEach(MenuKitConfig.supermixOptions) { option in
                button(option)
            }
        }
    }

    private func button(_ option: SupermixOption) -> some View {
        let isSelected = option.id == selection.supermixID
        return Button {
            MenuKit.playTapSound()
            if isSelected {
                popout.show(.supermix(option), anchorKey: "super.\(option.id)")
            } else {
                selection.select(supermixID: option.id)
            }
        } label: {
            label(option)
                .foregroundStyle(isSelected ? .white : theme.deep)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: MenuKitLayout.supermixButtonHeight)
                .background(isSelected ? theme.deep : theme.idleFill,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.deep.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                .reportAnchor("super.\(option.id)")
                .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: MKText("menu.accessibility.chooseMode"),
                                   option.operators.joined(separator: " ")))
    }

    /// Elke kolom reserveert een vast aantal vakjes (zie `slotCount`); een knop
    /// met minder operatoren centreert zich daarbinnen ("+ −" staat in vakje 2–3
    /// van 4), terwijl de langste knop van die kolom alle vakjes vult. Zo staan
    /// gedeelde operatoren van de twee knoppen boven elkaar netjes uitgelijnd.
    /// Het "%"-glyph leest bij dezelfde puntgrootte optisch zwaarder dan de rest
    /// en krijgt daarom zijn eigen, kleinere maat.
    private func label(_ option: SupermixOption) -> some View {
        // jens: aan deze twee getallen (iPad, iPhone) draai je de tekengrootte.
        let font = Font.system(size: isPad ? 26 : 19, weight: .bold)
        let heavyFont = Font.system(size: isPad ? 21 : 15, weight: .bold)
        let slotWidth: CGFloat = isPad ? 30 : 20
        let activeCount = option.operators.count
        let totalSlots = slotCount(for: option)
        let offset = (totalSlots - activeCount) / 2

        return HStack(spacing: 2) {
            ForEach(0..<totalSlots, id: \.self) { slot in
                let index = slot - offset
                let symbol = (index >= 0 && index < activeCount) ? option.operators[index] : ""
                let heavy = MenuKitConfig.heavyOperatorGlyphs[symbol]
                Text(symbol)
                    .font(heavy == nil ? font : heavyFont)
                    .frame(width: slotWidth * (heavy ?? 1))
            }
        }
    }

    /// Het aantal vakjes dat de kolom van deze knop reserveert: zoveel als de
    /// langste knop in diezelfde kolom nodig heeft. In het 2×2 rooster van
    /// Jumping Fox is dat 4 links (+ − / + − × ÷) en 5 rechts (+ − × / + − × ÷ %).
    private func slotCount(for option: SupermixOption) -> Int {
        let all = MenuKitConfig.supermixOptions
        guard let index = all.firstIndex(where: { $0.id == option.id }) else {
            return option.operators.count
        }
        let column = index % 2
        return all.enumerated()
            .filter { $0.offset % 2 == column }
            .map { $0.element.operators.count }
            .max() ?? option.operators.count
    }
}
