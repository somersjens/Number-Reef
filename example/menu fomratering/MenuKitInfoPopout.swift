//
//  MenuKitInfoPopout.swift
//  MenuKit — overgenomen uit Jumping Fox
//
//  De "tik nog eens"-pop-out: tik je een knop aan die al geselecteerd is, dan
//  verschijnt eronder een klein kaartje met een kopje en één regel uitleg.
//  (Voorheen deed die tweede tik niets.)
//
//  Werking in drie stappen:
//  1. Elke knop meldt via `reportAnchor(_:)` zijn frame in de gedeelde
//     coördinatenruimte `MenuKit.homeSpace`.
//  2. `InfoPopoutHost` verzamelt die frames en tekent de pop-out bovenop alles.
//  3. Een tik náást de pop-out sluit hem — en doet meteen ook waar die tik op
//     landde (een andere knop schakelt om, een levelkaart start).
//

import SwiftUI

// MARK: - Inhoud

/// De gegevens achter het kaartje. `anchor` is het frame van de aangetikte
/// knop in de gedeelde "home"-ruimte.
struct InfoPopup: Identifiable, Equatable {
    enum Kind: Equatable {
        case topic(MenuTopic)
        case mode(PracticeMode, MenuTopic?)
        case supermix(SupermixOption)
    }

    let kind: Kind
    let anchor: CGRect

    var id: String {
        switch kind {
        case .topic(let t):    return "topic.\(t.id)"
        case .mode(let m, _):  return "mode.\(m.rawValue)"
        case .supermix(let s): return "super.\(s.id)"
        }
    }

    /// Het kopje ("Soorten sommen" / "Volgorde" / "Delen" / "Soort").
    var header: String {
        switch kind {
        case .topic, .supermix:   return MKText("info.filter.header")
        case .mode(let m, let t): return m.infoHeader(for: t)
        }
    }

    /// De regel uitleg bij precies deze keuze.
    var body: String {
        switch kind {
        case .topic(let t):       return MKText(t.infoKey)
        case .mode(let m, let t): return m.infoBody(for: t)
        case .supermix(let s):    return MKText(s.infoKey)
        }
    }

    /// De eerste twee onderwerp-knoppen en de eerste volgorde-knop hebben ruimte
    /// zat aan hun rechterkant. Hun pop-out blijft daarom aan de linkerrand van
    /// de knop hangen, zodat een langere vertaling díé kant op groeit in plaats
    /// van naar de schermrand te duwen. De rest blijft gecentreerd, want die
    /// kaartjes gebruiken juist de ruimte aan hun linkerkant.
    var expandsRight: Bool {
        switch kind {
        case .topic(let t):
            return (MenuKitConfig.topics.firstIndex(of: t) ?? 99) < 2
        case .mode(let m, _):
            return m == .order
        case .supermix:
            return false
        }
    }
}

// MARK: - Positiemeting

/// Frames van de aantikbare knoppen, per sleutel ("topic.tables", "mode.mix",
/// "super.superAll").
struct ControlAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Meld het frame van deze knop (in "home"-ruimte), zodat de pop-out er
    /// precies onder kan hangen.
    func reportAnchor(_ key: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: ControlAnchorKey.self,
                                   value: [key: geo.frame(in: .named(MenuKit.homeSpace))])
        })
    }
}

// MARK: - Aansturing

final class InfoPopoutController: ObservableObject {
    @Published fileprivate(set) var popup: InfoPopup?
    @Published var anchors: [String: CGRect] = [:]

    func show(_ kind: InfoPopup.Kind, anchorKey: String) {
        guard let anchor = anchors[anchorKey] else { return }
        MenuKit.playPopoutHaptic()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            popup = InfoPopup(kind: kind, anchor: anchor)
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.16)) { popup = nil }
    }

    /// De knopsleutel onder een punt, of `nil`.
    func controlKey(at point: CGPoint) -> String? {
        anchors.first { $0.value.contains(point) }?.key
    }
}

// MARK: - Host

/// Wikkel je hele scherm hierin. Dit zet de gedeelde coördinatenruimte, vangt
/// de gemeten knopposities op en tekent de pop-out bovenop de inhoud.
///
///     InfoPopoutHost(controller: popout, selection: menu) {
///         ScrollView { … }
///     }
///
/// `onBackgroundTap` krijgt een tik náást de pop-out die niet op een knop
/// landde; geef `true` terug als je hem zelf hebt afgehandeld (bijvoorbeeld een
/// levelkaart die je meteen start).
struct InfoPopoutHost<Content: View>: View {
    @ObservedObject var controller: InfoPopoutController
    @ObservedObject var selection: MenuSelectionStore
    var onBackgroundTap: ((CGPoint) -> Bool)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()

            if let popup = controller.popup {
                overlay(popup)
                    .transition(.opacity)
            }
        }
        .coordinateSpace(name: MenuKit.homeSpace)
        .onPreferenceChange(ControlAnchorKey.self) { controller.anchors = $0 }
    }

    private func overlay(_ popup: InfoPopup) -> some View {
        GeometryReader { geo in
            // Reken het anker (in "home"-ruimte) om naar de lokale ruimte van
            // deze overlay, zodat het kaartje net onder de knop komt.
            let localOrigin = geo.frame(in: .named(MenuKit.homeSpace)).origin
            // Korte uitleg blijft compact; een lang label mag op één regel
            // blijven zolang de zijmarges van het menu dat toelaten.
            let cardWidth = InfoPopoutCard.preferredWidth(
                header: popup.header,
                message: popup.body,
                isPad: MenuKitLayout.isPad,
                maximum: geo.size.width - 24
            )
            let anchorMidX = popup.anchor.midX - localOrigin.x
            let leadingAnchorX = popup.anchor.minX - localOrigin.x
            let rawX = popup.expandsRight ? leadingAnchorX : anchorMidX - cardWidth / 2
            let x = min(max(12, rawX), max(12, geo.size.width - cardWidth - 12))
            let y = popup.anchor.maxY - localOrigin.y + 8

            ZStack(alignment: .topLeading) {
                // Vangnet dat de pop-out sluit bij een tik ernaast — en die tik
                // meteen doorgeeft aan wat eronder ligt.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture(coordinateSpace: .named(MenuKit.homeSpace))
                            .onEnded { value in handleBackgroundTap(at: value.location) }
                    )

                // Het pijltje wijst naar de knop; het wordt gemeten vanaf het
                // midden van het kaartje en blijft binnen de ronde hoeken.
                let caretLimit = cardWidth / 2 - 18
                let caret = min(max(anchorMidX - (x + cardWidth / 2), -caretLimit), caretLimit)
                InfoPopoutCard(header: popup.header,
                               message: popup.body,
                               caretOffset: caret)
                    .frame(width: cardWidth)
                    .offset(x: x, y: y)
                    .onTapGesture { controller.dismiss() }
            }
        }
    }

    /// Een tik achter de pop-out. Hij sluit altijd, en als de tik ook nog ergens
    /// op landt gebeurt dat in dezelfde beweging: een andere knop schakelt om,
    /// en wat de host herkent (een levelkaart) start meteen. Een tik op lege
    /// ruimte sluit alleen.
    private func handleBackgroundTap(at point: CGPoint) {
        if onBackgroundTap?(point) == true {
            controller.dismiss()
            return
        }
        if let key = controller.controlKey(at: point) {
            controller.dismiss()
            selection.apply(controlKey: key)
            return
        }
        controller.dismiss()
    }
}

// MARK: - Het kaartje

/// Klein kaartje met een pijltje erboven, in dezelfde stijl als de menupanelen:
/// wit vlak, haarlijntje in de themakleur en een zachte schaduw. `caretOffset`
/// zet het pijltje boven de knop waar het kaartje bij hoort.
struct InfoPopoutCard: View {
    let header: String
    let message: String
    let caretOffset: CGFloat
    @Environment(\.menuKitTheme) private var theme
    private var isPad: Bool { MenuKitLayout.isPad }

    /// De breedte die het kopje of de boodschap nodig heeft, inclusief de
    /// zijpadding van het kaartje. Langere teksten kiezen bewust de smalste
    /// breedte die nog op twee regels past, in plaats van schermbreed te worden.
    static func preferredWidth(header: String,
                               message: String,
                               isPad: Bool,
                               maximum: CGFloat) -> CGFloat {
#if canImport(UIKit)
        let headerFont = UIFont.systemFont(ofSize: isPad ? 14 : 11, weight: .heavy)
        let messageFont = UIFont.systemFont(ofSize: isPad ? 21 : 16, weight: .bold)
        // `Text(header)` zet hieronder 0,6 punt tussen elk letterpaar. Reken die
        // tracking hier mee, anders wordt een kopje als "Soorten sommen" iets te
        // smal gemeten en breekt het af terwijl het kaartje nog kon groeien.
        let uppercasedHeader = header.uppercased()
        let headerTracking = CGFloat(max(0, uppercasedHeader.count - 1)) * 0.6
        let headerWidth = (uppercasedHeader as NSString)
            .size(withAttributes: [.font: headerFont]).width + headerTracking
        let messageString = message as NSString
        let messageWidth = messageString
            .size(withAttributes: [.font: messageFont]).width
        let horizontalPadding: CGFloat = isPad ? 36 : 28
        let maximumContentWidth = max(1, maximum - horizontalPadding)

        // Korte uitleg blijft op één regel. Voor langere vertalingen: zoek de
        // kleinste breedte die niet meer dan twee regels nodig heeft, zodat de
        // tweede regel geen grote lege staart overhoudt.
        if max(headerWidth, messageWidth) <= maximumContentWidth {
            return ceil(max(headerWidth, messageWidth) + horizontalPadding)
        }

        var lowerBound = min(maximumContentWidth, max(headerWidth, isPad ? 220 : 170))
        var upperBound = maximumContentWidth
        let twoLineHeight = messageFont.lineHeight * 2.05

        for _ in 0..<9 {
            let candidate = (lowerBound + upperBound) / 2
            let measured = messageString.boundingRect(
                with: CGSize(width: candidate, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: messageFont],
                context: nil
            )
            if measured.height <= twoLineHeight {
                upperBound = candidate
            } else {
                lowerBound = candidate
            }
        }

        return ceil(upperBound + horizontalPadding)
#else
        return min(isPad ? 340 : 250, maximum)
#endif
    }

    var body: some View {
        VStack(spacing: 0) {
            InfoPopoutCaret()
                .fill(.white)
                .frame(width: 18, height: 9)
                .overlay(alignment: .bottom) {
                    // Verberg de naad waar het pijltje het kaartje raakt.
                    Rectangle().fill(.white).frame(height: 1).padding(.horizontal, 2)
                }
                .offset(x: caretOffset)

            VStack(alignment: .leading, spacing: isPad ? 5 : 3) {
                Text(header.uppercased())
                    .font(.system(size: isPad ? 14 : 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(theme.deep.opacity(0.55))
                Text(message)
                    .font(.system(size: isPad ? 21 : 16, weight: .bold))
                    .foregroundStyle(theme.deep)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isPad ? 18 : 14)
            .padding(.vertical, isPad ? 14 : 11)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.deep.opacity(0.18), lineWidth: 1))
        }
        .shadow(color: theme.deep.opacity(0.22), radius: 14, y: 6)
    }
}

/// Het driehoekje dat omhoog wijst.
private struct InfoPopoutCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
