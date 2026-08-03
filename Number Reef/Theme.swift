//
//  Theme.swift
//  Elephant Challenge: Math Memory
//
//  Character catalog: 10 animals, each with a clearly different colour and a
//  matching visual theme for the whole app. Characters are earned by collecting
//  cards; the requirements live in `GameConfig.characterUnlockRequirements`.
//

import SwiftUI

/// The game's currency. A player collects bubbles: in the reef, on the menu
/// totals, on the level cards and in the shop. One glyph, used everywhere, so
/// the same thing is never drawn two ways.
enum Currency {
    static let icon = "bubble"
}

/// The artwork used anywhere a bubble count is shown. The source PNG is
/// rendered as a template so it keeps following each character's theme color.
struct CurrencyIcon: View {
    let size: CGFloat

    var body: some View {
        Image(Currency.icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct AnimalCharacter: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    /// Position in the catalog, 1-based. It is also the suffix of both artwork
    /// assets, so a character can never be paired with someone else's picture.
    let slot: Int

    // Colour components (0–1).
    let primaryRGB: (Double, Double, Double)
    let deepRGB: (Double, Double, Double)
    let skyRGB: (Double, Double, Double)
    let tintRGB: (Double, Double, Double)

    /// Width ÷ height of the swimming artwork, measured from the asset itself.
    /// The reef draws every character at its own proportions rather than
    /// squeezing them all into one silhouette.
    let sideAspectRatio: CGFloat

    static func == (lhs: AnimalCharacter, rhs: AnimalCharacter) -> Bool {
        lhs.id == rhs.id
    }

    var color: Color { Color(red: primaryRGB.0, green: primaryRGB.1, blue: primaryRGB.2) }
    var deepColor: Color { Color(red: deepRGB.0, green: deepRGB.1, blue: deepRGB.2) }
    var skyColor: Color { Color(red: skyRGB.0, green: skyRGB.1, blue: skyRGB.2) }
    var tintColor: Color { Color(red: tintRGB.0, green: tintRGB.1, blue: tintRGB.2) }

    /// Facing the player: menus, cards, the shop and every portrait slot.
    /// All ten assets are square and optically equalised, so one square frame
    /// renders any character at the same apparent size.
    var imageName: String { "front_\(slot)" }
    var artwork: Image { Image(imageName) }

    /// Facing the way it swims, used while playing.
    var sideImageName: String { "side_\(slot)" }
    var sideArtwork: Image { Image(sideImageName) }

    /// Localized display name, resolved per language from the string catalog
    /// ("character.fox", "character.frog", …).
    var localizedName: String {
        L(key: "character.\(id)")
    }
}

enum CharacterCatalog {
    /// The character available from the very first card.
    static let freeCharacterID = CharacterUnlocks.starterCharacterID

    /// The localized fallback used when the player leaves their name empty.
    /// Resolve it through the character catalog so it can never drift from the
    /// name shown for the starter character in the active language.
    static var defaultPlayerName: String {
        character(id: freeCharacterID).localizedName
    }

    /// Order must match `CharacterUnlocks.orderedCharacterIDs`; a test asserts it.
    ///
    /// Every palette is sampled from that character's own artwork, so the reef,
    /// the menu and the motion trail behind a portrait all carry the colours
    /// the player is actually looking at.
    static let all: [AnimalCharacter] = [
        AnimalCharacter(id: "octopus", name: "Octopus", emoji: "🐙", slot: 1,
                        primaryRGB: (0.62, 0.40, 0.87), deepRGB: (0.35, 0.18, 0.60),
                        skyRGB: (0.93, 0.88, 0.99), tintRGB: (0.88, 0.79, 0.98),
                        sideAspectRatio: 1.599),
        AnimalCharacter(id: "crab", name: "Crab", emoji: "🦀", slot: 2,
                        primaryRGB: (0.90, 0.27, 0.10), deepRGB: (0.62, 0.13, 0.03),
                        skyRGB: (1.00, 0.90, 0.87), tintRGB: (1.00, 0.82, 0.77),
                        sideAspectRatio: 1.071),
        AnimalCharacter(id: "elephant", name: "Elephant", emoji: "🐘", slot: 3,
                        primaryRGB: (0.36, 0.58, 0.78), deepRGB: (0.19, 0.38, 0.58),
                        skyRGB: (0.90, 0.94, 0.97), tintRGB: (0.81, 0.89, 0.96),
                        sideAspectRatio: 1.606),
        AnimalCharacter(id: "bear", name: "Bear", emoji: "🐻", slot: 4,
                        primaryRGB: (0.72, 0.44, 0.16), deepRGB: (0.42, 0.20, 0.06),
                        skyRGB: (0.99, 0.94, 0.88), tintRGB: (0.98, 0.89, 0.79),
                        sideAspectRatio: 1.411),
        AnimalCharacter(id: "fox", name: "Fox", emoji: "🦊", slot: 5,
                        primaryRGB: (0.94, 0.60, 0.26), deepRGB: (0.68, 0.30, 0.07),
                        skyRGB: (1.00, 0.94, 0.87), tintRGB: (1.00, 0.89, 0.77),
                        sideAspectRatio: 1.266),
        AnimalCharacter(id: "frog", name: "Frog", emoji: "🐸", slot: 6,
                        primaryRGB: (0.45, 0.76, 0.18), deepRGB: (0.12, 0.47, 0.15),
                        skyRGB: (0.93, 0.99, 0.88), tintRGB: (0.88, 0.97, 0.80),
                        sideAspectRatio: 1.810),
        AnimalCharacter(id: "penguin", name: "Penguin", emoji: "🐧", slot: 7,
                        primaryRGB: (0.22, 0.36, 0.68), deepRGB: (0.08, 0.16, 0.38),
                        skyRGB: (0.89, 0.92, 0.98), tintRGB: (0.81, 0.86, 0.96),
                        sideAspectRatio: 1.356),
        AnimalCharacter(id: "bunny", name: "Bunny", emoji: "🐰", slot: 8,
                        primaryRGB: (0.94, 0.56, 0.60), deepRGB: (0.72, 0.29, 0.37),
                        skyRGB: (1.00, 0.87, 0.89), tintRGB: (0.99, 0.78, 0.80),
                        sideAspectRatio: 1.352),
        AnimalCharacter(id: "dog", name: "Dog", emoji: "🐶", slot: 9,
                        primaryRGB: (0.20, 0.66, 0.69), deepRGB: (0.06, 0.42, 0.46),
                        skyRGB: (0.89, 0.97, 0.98), tintRGB: (0.81, 0.95, 0.96),
                        sideAspectRatio: 1.544),
        AnimalCharacter(id: "lion", name: "Lion", emoji: "🦁", slot: 10,
                        primaryRGB: (0.95, 0.74, 0.20), deepRGB: (0.68, 0.45, 0.08),
                        skyRGB: (1.00, 0.96, 0.87), tintRGB: (1.00, 0.94, 0.77),
                        sideAspectRatio: 1.384)
    ]

    static func character(id: String) -> AnimalCharacter {
        all.first { $0.id == id } ?? all[0]
    }

    /// The first half of the catalog: earned purely by collecting cards.
    static var cardCharacters: [AnimalCharacter] {
        all.filter { !CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The second half: still earnable with cards, but Premium grants them at once.
    static var premiumCharacters: [AnimalCharacter] {
        all.filter { CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The selected character, falling back to the starter when the selected
    /// one is not available (yet).
    static func current(isPremium: Bool) -> AnimalCharacter {
        let selected = character(id: GameSettings.characterID)
        if !CharacterUnlockStore.canUse(characterID: selected.id, isPremium: isPremium) {
            return character(id: freeCharacterID)
        }
        return selected
    }
}

/// Character access, derived from the player's card total so an unlock can
/// never be lost through a missed animation. Only the one-time celebration
/// receipt is stored separately.
enum CharacterUnlockStore {
    static var totalCards: Int {
        get { Progress.store.totalCards }
        set { Progress.store.totalCards = newValue }
    }

    /// Cards required for a character, or nil when it is not card-unlockable.
    static func requirement(for characterID: String) -> Int? {
        CharacterUnlocks.cardsRequired(for: characterID)
    }

    static func canUse(characterID: String, isPremium: Bool) -> Bool {
        CharacterUnlocks.isUnlocked(characterID: characterID,
                                    totalCards: totalCards,
                                    isPremium: isPremium)
    }

    /// The next animal still to be earned, for the home screen and reminders.
    static func nextMilestone() -> (character: AnimalCharacter, remaining: Int)? {
        guard let next = CharacterUnlocks.nextMilestone(totalCards: totalCards) else { return nil }
        return (CharacterCatalog.character(id: next.characterID), next.remaining)
    }

    /// Characters that crossed their requirement but have not been celebrated.
    static func unannouncedUnlocks(at total: Int) -> [AnimalCharacter] {
        let announced = Progress.store.announcedUnlocks
        return CharacterUnlocks.unlockedCharacterIDs(totalCards: total)
            .filter { $0 != CharacterCatalog.freeCharacterID && !announced.contains($0) }
            .map { CharacterCatalog.character(id: $0) }
    }

    static func markAnnounced(_ characterID: String) {
        var announced = Progress.store.announcedUnlocks
        announced.insert(characterID)
        Progress.store.announcedUnlocks = announced
    }
}
