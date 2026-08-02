//
//  MenuKitDemo.swift
//  MenuKit — overgenomen uit Jumping Fox
//
//  Een werkend voorbeeldscherm dat alles aan elkaar knoopt. Zet dit als
//  rootview van een leeg project en je ziet meteen het hele gedrag:
//  onderwerp-cirkels, de drie volgorde-knoppen, het sterrooster, de pop-outs
//  en de welkomstschermen. Gebruik het als kopieersjabloon en gooi het daarna
//  gerust weg.
//

import SwiftUI

struct MenuKitDemoView: View {
    @StateObject private var selection = MenuSelectionStore()
    @StateObject private var popout = InfoPopoutController()
    @State private var showsWelcome = false
    @State private var welcomeStep = 1
    /// Frames van de nepkaarten, zodat een tik achter de pop-out er meteen
    /// eentje kan starten (zoals de levelkaarten in Jumping Fox).
    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var startedCard: Int?

    private let theme = MenuKitTheme(deep: Color(red: 0.43, green: 0.20, blue: 0.03),
                                     accent: .orange)

    var body: some View {
        InfoPopoutHost(controller: popout,
                       selection: selection,
                       onBackgroundTap: startCard(at:)) {
            ZStack {
                LinearGradient(colors: [Color.orange.opacity(0.26), Color.yellow.opacity(0.12)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        menuCard
                        cardGrid
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .menuKitTheme(theme)
        .overlay {
            if showsWelcome { welcomeFlow }
        }
    }

    // MARK: Menupaneel

    private var menuCard: some View {
        VStack(spacing: 14) {
            MenuControlStack(selection: selection, popout: popout)

            Text(statusLine)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.deep.opacity(0.6))

            Button("Welkomstscherm opnieuw") {
                welcomeStep = 1
                withAnimation { showsWelcome = true }
            }
            .font(.footnote.weight(.bold))
            .tint(theme.accent)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.76))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                }
        }
        .shadow(color: theme.deep.opacity(0.12), radius: 14, y: 7)
    }

    /// Laat zien welke level-id de huidige keuze oplevert.
    private var statusLine: String {
        let base = selection.showsSupermixGrid
            ? selection.supermixID
            : selection.topicID
        return "\(base).1\(selection.levelIDSuffix)"
    }

    // MARK: Nepkaarten (staan hier alleen om de doortik te tonen)

    private var cardGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                  spacing: 10) {
            ForEach(1...6, id: \.self) { index in
                Text("\(index)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(startedCard == index ? .white : theme.deep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(startedCard == index ? theme.deep : .white.opacity(0.7),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: DemoCardFrameKey.self,
                                               value: [index: geo.frame(in: .named(MenuKit.homeSpace))])
                    })
                    .onTapGesture { startedCard = index }
            }
        }
        .onPreferenceChange(DemoCardFrameKey.self) { cardFrames = $0 }
    }

    /// Een tik achter de pop-out die op een kaart landt: sluit de pop-out én
    /// start die kaart in dezelfde beweging.
    private func startCard(at point: CGPoint) -> Bool {
        guard let hit = cardFrames.first(where: { $0.value.contains(point) }) else { return false }
        startedCard = hit.key
        return true
    }

    // MARK: Welkomstschermen 2 en 3

    private var welcomeFlow: some View {
        ZStack {
            LinearGradient(colors: [Color.orange.opacity(0.24), Color.yellow.opacity(0.13)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Image(systemName: "hare.fill")
                            .font(.system(size: welcomeStep == 1 ? 70 : 90))
                            .foregroundStyle(theme.accent)
                            .padding(.bottom, welcomeStep == 1 ? 14 : 22)
                            .animation(.spring(response: 0.42, dampingFraction: 0.82),
                                       value: welcomeStep)

                        Group {
                            if welcomeStep == 1 {
                                WelcomeTopicStep(selection: selection) {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                        welcomeStep = 2
                                    }
                                }
                            } else {
                                WelcomeLevelStep(
                                    selection: selection,
                                    availableWidth: min(500, max(0, proxy.size.width - 48))
                                ) {
                                    withAnimation(.easeInOut(duration: 0.45)) {
                                        showsWelcome = false
                                    }
                                }
                            }
                        }
                        .id(welcomeStep)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(theme.deep)
        .menuKitTheme(theme)
        .transition(.opacity)
    }
}

private struct DemoCardFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

#Preview {
    MenuKitDemoView()
}
