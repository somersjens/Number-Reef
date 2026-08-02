//
//  MenuKitCore.swift
//  MenuKit — overgenomen uit Jumping Fox
//
//  Configuratie, thema, teksten en het selectie-model.
//  Dit bestand heeft geen enkele afhankelijkheid buiten SwiftUI.
//

import SwiftUI

// MARK: - Globale haken

/// Alles wat MenuKit van de host-app nodig heeft, op één plek.
/// Zet deze in je `App.init()` of in `onAppear` van je hoofdscherm.
enum MenuKit {
    /// Naam van de gedeelde coördinatenruimte waarin de knopposities worden
    /// gemeten. Wordt door `InfoPopoutHost` gezet — zelf niets voor doen.
    static let homeSpace = "menukit.home"

    /// Vertaalfunctie. Standaard `NSLocalizedString`; heeft je app al een eigen
    /// `L(...)` (zoals Jumping Fox), zet die er dan hier in:
    ///     MenuKit.localize = { L($0) }
    static var localize: (String) -> String = { NSLocalizedString($0, comment: "") }

    /// Klikgeluid bij elke druk op een menuknop (in Jumping Fox
    /// `AppAudio.shared.playMenuTap()`). Standaard stil.
    static var playTapSound: () -> Void = {}

    /// Reactie op een échte wisseling van selectie. `big == true` bij een
    /// onderwerpwissel (grote sprong), `false` bij een volgorde-/supermixwissel
    /// (kwart sprong). In Jumping Fox laat dit het personage springen.
    static var onSelectionChanged: (_ big: Bool) -> Void = { _ in }

    /// Haptiek bij het openen van een pop-out.
    static var playPopoutHaptic: () -> Void = {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }
}

/// Korte hulpfunctie voor vertalingen binnen MenuKit.
func MKText(_ key: String) -> String { MenuKit.localize(key) }

// MARK: - Layout

enum MenuKitLayout {
    static var isPad: Bool {
#if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    /// Alle symbolen in de onderwerp-cirkels schalen mee met dit getal.
    static var symbolScale: CGFloat { isPad ? 1.64 : 1 }
    static var circleDiameter: CGFloat { isPad ? 82 : 44 }
    static var modeButtonHeight: CGFloat { isPad ? 72 : 42 }
    static var supermixButtonHeight: CGFloat { isPad ? 84 : 42 }
    static var gridSpacing: CGFloat { isPad ? 12 : 8 }
}

// MARK: - Thema

/// De paar kleuren die het menu gebruikt. In Jumping Fox komt `deep` uit het
/// gekozen dier; geef hier gewoon je eigen accentkleur mee.
struct MenuKitTheme {
    var deep: Color = Color(red: 0.43, green: 0.20, blue: 0.03)
    /// Ongeselecteerde vlakke knop (Reeks/Hussel/Gemixt en supermix).
    var idleFill: Color = .white.opacity(0.62)
    /// Ongeselecteerde cirkelknop (de onderwerpen).
    var idleCircleFill: Color = .white.opacity(0.70)
    /// Accent voor het welkomstscherm.
    var accent: Color = .orange

    static let `default` = MenuKitTheme()
}

private struct MenuKitThemeKey: EnvironmentKey {
    static let defaultValue = MenuKitTheme.default
}

extension EnvironmentValues {
    var menuKitTheme: MenuKitTheme {
        get { self[MenuKitThemeKey.self] }
        set { self[MenuKitThemeKey.self] = newValue }
    }
}

extension View {
    func menuKitTheme(_ theme: MenuKitTheme) -> some View {
        environment(\.menuKitTheme, theme)
    }
}

// MARK: - Onderwerpen (de rij cirkels, met de ster als laatste)

/// Eén onderwerp-cirkel. De ster is gewoon een onderwerp met
/// `usesSupermixGrid = true`: die vervangt de drie volgorde-knoppen door het
/// 2×2 rooster met operator-knoppen.
struct MenuTopic: Identifiable, Equatable {
    let id: String
    /// Vertaalsleutel van de naam (alleen gebruikt in het welkomstscherm).
    var titleKey: String
    /// SF Symbol op de cirkel — kaal glyph, de knop levert zelf de cirkel.
    var icon: String
    /// Puntgrootte vóór schaling. Per symbool apart, omdat glyphs optisch
    /// verschillend "groot" lezen: de gevulde ster leest breed, % leest hoog.
    var iconSize: CGFloat
    /// Vertaalsleutel van de pop-outtekst ("Alleen optellen", …).
    var infoKey: String
    /// Toont deze keuze het supermix-rooster in plaats van de volgorde-knoppen?
    var usesSupermixGrid: Bool = false
    /// Optionele afwijkende labels/pop-outs voor de drie volgorde-knoppen.
    var modeOverride: ModeLabelOverride? = nil

    static func == (lhs: MenuTopic, rhs: MenuTopic) -> Bool { lhs.id == rhs.id }
}

/// Breuken en Procenten sorteren hun drie sub-levels niet op *volgorde*, maar
/// veranderen *wat voor som* je krijgt. Die twee menu's krijgen dus eigen
/// knoplabels, een eigen kopje en eigen pop-outteksten; alle andere onderwerpen
/// houden Reeks · Hussel · Gemixt.
struct ModeLabelOverride {
    var orderTitleKey: String
    var randomTitleKey: String
    /// Gemixt houdt in Jumping Fox altijd zijn gedeelde label; laat `nil` om dat
    /// gedrag over te nemen.
    var mixedTitleKey: String? = nil

    var infoHeaderKey: String
    var orderInfoKey: String
    var randomInfoKey: String
    /// `nil` = gedeelde "Gemengd met lagere niveaus".
    var mixedInfoKey: String? = nil
}

// MARK: - De drie volgorde-knoppen

/// De drie manieren waarop elk onderwerp een level kan oefenen:
/// - `order`  (Reeks / Order):   de rustige oplopende reeks.
/// - `random` (Hussel / Random): alleen het eigen getal van dit level, door
///   elkaar geschud.
/// - `mixed`  (Gemixt / Mixed):  dit getal *of een lager*, allemaal door elkaar,
///   met de nadruk op de hogere (moeilijkere) kant.
///
/// De rawValues zijn bewust de opgeslagen waarden ("standard"/"random"/"mix"),
/// zodat bestaande spelers hun scores behouden. `idSuffix` hangt achter een
/// level-id zodat elke modus zijn eigen score bijhoudt.
enum PracticeMode: String, CaseIterable, Identifiable {
    case order = "standard"
    case random = "random"
    case mixed = "mix"

    var id: String { rawValue }

    /// Achtervoegsel achter een level-id, zodat elke modus zijn eigen score houdt.
    var idSuffix: String {
        switch self {
        case .order:  return ""
        case .random: return ".random"
        case .mixed:  return ".mix"
        }
    }

    /// Gedeeld knoplabel (Reeks · Hussel · Gemixt / Order · Random · Mixed).
    var title: String {
        switch self {
        case .order:  return MKText("mode.order")
        case .random: return MKText("mode.random")
        case .mixed:  return MKText("mode.mixed")
        }
    }

    /// Gedeelde pop-outtekst onder het kopje `info.mode.header` ("Volgorde").
    var infoBody: String {
        switch self {
        case .order:  return MKText("info.mode.order")
        case .random: return MKText("info.mode.random")
        case .mixed:  return MKText("info.mode.mixed")
        }
    }

    // MARK: Per-onderwerp varianten

    func title(for topic: MenuTopic?) -> String {
        guard let override = topic?.modeOverride else { return title }
        switch self {
        case .order:  return MKText(override.orderTitleKey)
        case .random: return MKText(override.randomTitleKey)
        case .mixed:  return override.mixedTitleKey.map(MKText) ?? title
        }
    }

    /// Kopje boven de pop-outtekst ("Volgorde" / "Delen" / "Soort").
    func infoHeader(for topic: MenuTopic?) -> String {
        MKText(topic?.modeOverride?.infoHeaderKey ?? "info.mode.header")
    }

    func infoBody(for topic: MenuTopic?) -> String {
        guard let override = topic?.modeOverride else { return infoBody }
        switch self {
        case .order:  return MKText(override.orderInfoKey)
        case .random: return MKText(override.randomInfoKey)
        case .mixed:  return override.mixedInfoKey.map(MKText) ?? infoBody
        }
    }
}

// MARK: - De vier knoppen van de ster (supermix)

/// Eén van de vier supermix-knoppen. Elke knop is een eigen categorie die
/// steeds méér bewerkingen combineert; de zwaardere bewerkingen wegen daarbij
/// zwaarder mee in de vraaggenerator.
struct SupermixOption: Identifiable, Equatable {
    let id: String
    /// De operatoren die deze knop toont, in vaste volgorde.
    var operators: [String]
    /// Vertaalsleutel van de pop-outtekst.
    var infoKey: String

    static func == (lhs: SupermixOption, rhs: SupermixOption) -> Bool { lhs.id == rhs.id }
}

// MARK: - Standaardconfiguratie (exact die van Jumping Fox)

/// Vervang deze lijsten door je eigen onderwerpen; de rest van MenuKit past
/// zich automatisch aan (ook het 2×2 rooster en de kolombreedtes).
enum MenuKitConfig {
    static let fractionsOverride = ModeLabelOverride(
        orderTitleKey: "mode.fractions.single",
        randomTitleKey: "mode.fractions.multiple",
        infoHeaderKey: "info.mode.fractions.header",
        orderInfoKey: "info.mode.fractions.single",
        randomInfoKey: "info.mode.fractions.multiple"
    )

    static let percentagesOverride = ModeLabelOverride(
        orderTitleKey: "mode.percentages.whole",
        randomTitleKey: "mode.percentages.decimal",
        infoHeaderKey: "info.mode.percentages.header",
        orderInfoKey: "info.mode.percentages.whole",
        randomInfoKey: "info.mode.percentages.decimal"
    )

    /// De zes onderwerpen, in schermvolgorde. De ster staat altijd achteraan.
    static var topics: [MenuTopic] = [
        MenuTopic(id: "addition", titleKey: "filter.addition",
                  icon: "plus", iconSize: 21, infoKey: "info.filter.addition"),
        MenuTopic(id: "subtraction", titleKey: "filter.subtraction",
                  icon: "minus", iconSize: 21, infoKey: "info.filter.subtraction"),
        MenuTopic(id: "tables", titleKey: "filter.tables",
                  icon: "multiply", iconSize: 21, infoKey: "info.filter.tables"),
        MenuTopic(id: "fractions", titleKey: "filter.fractions",
                  icon: "divide", iconSize: 21, infoKey: "info.filter.fractions",
                  modeOverride: fractionsOverride),
        MenuTopic(id: "percentages", titleKey: "filter.percentages",
                  icon: "percent", iconSize: 19, infoKey: "info.filter.percentages",
                  modeOverride: percentagesOverride),
        MenuTopic(id: "mixed", titleKey: "filter.mixed",
                  icon: "star.fill", iconSize: 17, infoKey: "info.filter.mixed",
                  usesSupermixGrid: true)
    ]

    /// De vier sterknoppen, in vaste volgorde. Ze vullen het 2×2 rooster van
    /// links naar rechts, dus: linksboven, rechtsboven, linksonder, rechtsonder.
    static var supermixOptions: [SupermixOption] = [
        SupermixOption(id: "superBasic",    operators: ["+", "−"],
                       infoKey: "info.super.basic"),
        SupermixOption(id: "superTimes",    operators: ["+", "−", "×"],
                       infoKey: "info.super.times"),
        SupermixOption(id: "superFraction", operators: ["+", "−", "×", "÷"],
                       infoKey: "info.super.fraction"),
        SupermixOption(id: "superAll",      operators: ["+", "−", "×", "÷", "%"],
                       infoKey: "info.super.all")
    ]

    /// Glyphs die op dezelfde puntgrootte optisch zwaarder lezen dan de rest,
    /// met hun eigen (kleinere) factor. Alleen "%" in Jumping Fox.
    static var heavyOperatorGlyphs: [String: CGFloat] = ["%": 0.8]

    static func topic(id: String) -> MenuTopic? { topics.first { $0.id == id } }
    static func supermix(id: String) -> SupermixOption? { supermixOptions.first { $0.id == id } }
}

// MARK: - Selectiemodel

/// Houdt de drie keuzes vast (onderwerp, volgorde, sterknop) en bewaart ze in
/// UserDefaults. Eén `@StateObject` in je hoofdscherm en je bent klaar.
final class MenuSelectionStore: ObservableObject {
    struct Keys {
        var topic = "ui.menuFilter"
        var mode = "ui.menuMode"
        var supermix = "ui.supermixCategory"
    }

    private let keys: Keys
    private let defaults: UserDefaults

    @Published var topicID: String { didSet { defaults.set(topicID, forKey: keys.topic) } }
    @Published var modeRaw: String { didSet { defaults.set(modeRaw, forKey: keys.mode) } }
    @Published var supermixID: String { didSet { defaults.set(supermixID, forKey: keys.supermix) } }

    init(keys: Keys = Keys(), defaults: UserDefaults = .standard) {
        self.keys = keys
        self.defaults = defaults
        self.topicID = defaults.string(forKey: keys.topic)
            ?? MenuKitConfig.topics.first?.id ?? ""
        self.modeRaw = defaults.string(forKey: keys.mode) ?? PracticeMode.order.rawValue
        self.supermixID = defaults.string(forKey: keys.supermix)
            ?? MenuKitConfig.supermixOptions.first?.id ?? ""
    }

    var topic: MenuTopic? { MenuKitConfig.topic(id: topicID) }
    var mode: PracticeMode { PracticeMode(rawValue: modeRaw) ?? .order }
    var supermix: SupermixOption? { MenuKitConfig.supermix(id: supermixID) }

    /// Toont dit onderwerp het sterrooster in plaats van de volgorde-knoppen?
    var showsSupermixGrid: Bool { topic?.usesSupermixGrid == true }

    /// Het achtervoegsel voor level-id's bij de huidige selectie
    /// ("" / ".random" / ".mix"); het sterrooster heeft geen volgorde.
    var levelIDSuffix: String { showsSupermixGrid ? "" : mode.idSuffix }

    // MARK: Wisselen

    /// Past de keuze toe die een besturingssleutel voorstelt ("topic.tables",
    /// "mode.standard", "super.superBasic"). Een tik op wat al geselecteerd is,
    /// is een lege wissel en doet dus niets.
    @discardableResult
    func apply(controlKey key: String) -> Bool {
        guard let dot = key.firstIndex(of: ".") else { return false }
        let prefix = String(key[..<dot])
        let value = String(key[key.index(after: dot)...])
        switch prefix {
        case "topic": return select(topicID: value)
        case "mode":  return select(modeRaw: value)
        case "super": return select(supermixID: value)
        default:      return false
        }
    }

    @discardableResult
    func select(topicID value: String) -> Bool {
        guard value != topicID else { return false }
        MenuKit.onSelectionChanged(true)   // grote sprong: ander onderwerp
        // Eén runloop later committen: de zware level-grid-wissel mag de net
        // gestarte animatie van de knop niet onderbreken.
        DispatchQueue.main.async { self.topicID = value }
        return true
    }

    @discardableResult
    func select(modeRaw value: String) -> Bool {
        guard value != modeRaw else { return false }
        MenuKit.onSelectionChanged(false)  // kwart sprong: andere volgorde
        DispatchQueue.main.async { self.modeRaw = value }
        return true
    }

    @discardableResult
    func select(supermixID value: String) -> Bool {
        guard value != supermixID else { return false }
        MenuKit.onSelectionChanged(false)
        DispatchQueue.main.async { self.supermixID = value }
        return true
    }
}
