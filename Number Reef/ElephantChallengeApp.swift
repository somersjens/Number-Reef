//
//  ElephantChallengeApp.swift
//  Elephant Challenge: Math Memory
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// Keep the compact iPhone experience in portrait, while allowing iPad to use
/// the orientation of the device. iPad players commonly use a keyboard case or
/// Stage Manager, so forcing portrait there makes an otherwise adaptive
/// SwiftUI layout feel like an enlarged phone app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
    -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
}
#endif

@main
struct ElephantChallengeApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @AppStorage(GameSettings.onboardingReplayRequestedKey) private var onboardingReplayRequested = false
    /// The first game opened from the last welcome screen. Shown in this
    /// ZStack so it can crossfade with onboarding; a `fullScreenCover` from
    /// the menu would flash that menu in between.
    @State private var firstSession: GameSessionRequest?
    @StateObject private var language = LanguageManager.shared
    @StateObject private var promotedPurchase = PromotedPurchaseCoordinator.shared

#if TRAILER_EXPORT
    private var isExportingMenuTour: Bool {
        ProcessInfo.processInfo.arguments.contains("--export-menu-tour")
    }

    private var isExportingPremiumTour: Bool {
        ProcessInfo.processInfo.arguments.contains("--export-premium-tour")
    }
#endif

    init() {
        // Bring stored progress up to the current version before anything can
        // read it: data written by Jumping Fox must never reach the new game.
        Progress.store.migrateIfNeeded()
        // Decimal answers are printed with the separator of the language the
        // player is reading — a comma in Dutch, a point in English — rather
        // than the device's. The in-app language switch must win here too.
        DecimalAnswer.separatorProvider = {
            LanguageManager.shared.locale.decimalSeparator ?? "."
        }
#if TRAILER_EXPORT
        if ProcessInfo.processInfo.arguments.contains("--export-menu-tour")
            || ProcessInfo.processInfo.arguments.contains("--export-premium-tour") {
            GameSettings.gameSoundsEnabled = true
            GameSettings.spokenSumsEnabled = false
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: GameSettings.onboardingCompleteKey)
            defaults.set(false, forKey: GameSettings.tutorialPendingKey)
            GameSettings.characterID = CharacterCatalog.freeCharacterID
            defaults.set(MathTopic.addition.rawValue, forKey: GameSettings.topicKey)
            defaults.set(PracticeMode.order.rawValue, forKey: GameSettings.practiceModeKey)
            defaults.set(MixedVariant.basic.rawValue, forKey: GameSettings.mixedVariantKey)
            LanguageManager.shared.override = .english
            if ProcessInfo.processInfo.arguments.contains("--export-menu-tour") {
                GameSettings.playerName = "Number Reef"
                GameSettings.premiumUnlockedCache = true
                PremiumStore.shared.preparePromoUnlockedState()
            } else {
                // Simulator audio can stall while recordVideo captures a long
                // SwiftUI scroll. The master adds the bundled soundtrack, so
                // keep this native visual take silent and deterministic.
                GameSettings.gameSoundsEnabled = false
                GameSettings.playerName = "أخطبوط"
                GameSettings.premiumUnlockedCache = false
                PremiumStore.shared.preparePromoLockedState()
            }
            return
        }
#endif
        // Capture the first launch date independently of when the player first
        // finishes a game; later review phases use age since installation.
        _ = ReviewRequestCoordinator.shared
        PromotedPurchaseCoordinator.shared.startListening()
        // Bring iCloud sync online at launch, not just once the home screen
        // appears — on a fresh reinstall the app opens on onboarding, which
        // never touches ProgressSync, and the saved name would stay missing.
        _ = ProgressSync.shared
        // Install the notification delegate and rebuild the reminder schedule
        // for players who granted permission in an earlier session.
        NotificationManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
#if TRAILER_EXPORT
            if isExportingMenuTour {
                HomeView(promoMenuTrailer: true)
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.layoutDirection)
                    .preferredColorScheme(.light)
                    .persistentSystemOverlays(.hidden)
                    .statusBarHidden(true)
            } else if isExportingPremiumTour {
                PremiumPromoTourView()
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.layoutDirection)
                    .preferredColorScheme(.light)
                    .persistentSystemOverlays(.hidden)
                    .statusBarHidden(true)
            } else {
                standardLaunch
            }
#else
            standardLaunch
#endif
        }
    }

    @ViewBuilder
    private var standardLaunch: some View {
        if PromoTrailerRuntime.isActive {
            PromoTrailerBootstrapView()
        } else {
            productionRoot
        }
    }

    @ViewBuilder
    private var productionRoot: some View {
        let showsHome = onboardingComplete && !onboardingReplayRequested
        ZStack {
            if showsHome {
                HomeView(isCoveredByFirstSession: firstSession != nil)
                    // Hidden while the welcome flow's first game is covering
                    // it, so the menu never flashes through the crossfade.
                    .opacity(firstSession == nil ? 1 : 0)
                    .allowsHitTesting(firstSession == nil)
                    .accessibilityHidden(firstSession != nil)
            }

            if let session = firstSession {
                GameView(request: session, onExit: { firstSession = nil })
                    .gameEnvironment()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(1)
            } else if !showsHome {
                OnboardingView(onBeginFirstSession: { firstSession = $0 })
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                    .zIndex(1)
            }
        }
        // The overlay swap (welcome ↔ first game ↔ menu reveal) is what the
        // player sees. The menu itself is inserted behind that overlay without
        // its own fade, so it cannot flash through the crossfade.
        .animation(.easeInOut(duration: 0.42), value: firstSession != nil)
        .animation(firstSession == nil ? .easeInOut(duration: 0.42) : nil, value: showsHome)
        // Re-renders every `Text` (and formats numbers) when the language
        // changes; combined with the bundle redirection this makes the
        // switch instant, no restart required.
        .environment(\.locale, language.locale)
        // SwiftUI takes reading direction from the bundle's language, which
        // the in-app switch overrides, so Arabic and Hebrew must be told
        // explicitly to lay out right-to-left.
        .environment(\.layoutDirection, language.layoutDirection)
        // The reef, cards and copy are all painted for light surfaces.
        // Without this, Dark Mode turns system fills black and inverts
        // `.primary` / `.secondary` labels against those same light colours.
        .preferredColorScheme(.light)
        .sheet(isPresented: Binding(
            get: { promotedPurchase.isAwaitingParentApproval },
            set: { isPresented in
                if !isPresented { promotedPurchase.cancelDeferredPurchase() }
            }
        ),
               onDismiss: { promotedPurchase.cancelDeferredPurchase() }) {
            let character = CharacterCatalog.current(isPremium: PremiumStore.shared.isPremium)
            ParentApprovalGate(
                accent: character.color,
                deepColor: character.deepColor,
                onApproved: { promotedPurchase.approveDeferredPurchase() }
            )
            .gameEnvironment()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Shared layout helper, used to give iPad more breathing room without
/// changing the visual hierarchy.
enum AppLayout {
    static var isPad: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    /// Portrait iPad menus are laid out in a slightly smaller space and scaled
    /// back up, matching the Jumping Fox menu tour. Phone sizes stay put.
    static let padMenuZoom: CGFloat = 1.24
}

/// Portrait iPad lays the menu out smaller and scales it back up. Landscape
/// stays at full size so a fourth level column still fits.
struct PadMenuZoom: ViewModifier {
    var isPad: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPad {
            GeometryReader { geo in
                let zoom = geo.size.width < 1100 ? AppLayout.padMenuZoom : 1
                content
                    .frame(width: geo.size.width / zoom, height: geo.size.height / zoom)
                    .scaleEffect(zoom, anchor: .top)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        } else {
            content
        }
    }
}
