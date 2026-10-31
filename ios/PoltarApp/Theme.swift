import SwiftUI
import UIKit

/// One dark "Haunted Edition" look regardless of the device's appearance setting: deep night navy, white
/// text, Denk One titles and moon-orange accents.
enum Editorial {
    static let paper = Color(red: 0.043, green: 0.071, blue: 0.110)
    static let card = Color(red: 0.118, green: 0.161, blue: 0.208)
    static let tonal = Color(red: 0.039, green: 0.169, blue: 0.298)
    static let ink = Color.white
    static let accent = Color(red: 1, green: 0.769, blue: 0.498)
    static let pumpkin = Color(red: 0.91, green: 0.522, blue: 0.176)

    private static let displayFont = "DenkOne-Regular"
    static func title(_ size: CGFloat = 34) -> Font { .custom(displayFont, size: size) }

    /// Navigation bars that let the night sky show through, with Denk One titles, everywhere in the app.
    static func applyAppearance() {
        func display(_ size: CGFloat) -> UIFont { UIFont(name: displayFont, size: size) ?? .systemFont(ofSize: size, weight: .semibold) }
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        bar.titleTextAttributes = [.foregroundColor: UIColor.white, .font: display(20)]
        bar.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: display(34)]
        let scrolled = bar.copy()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundColor = UIColor(paper).withAlphaComponent(0.85)
        scrolled.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        let segments = UISegmentedControl.appearance()
        segments.selectedSegmentTintColor = UIColor(accent)
        segments.backgroundColor = UIColor(card)
        segments.setTitleTextAttributes([.foregroundColor: UIColor(paper)], for: .selected)
        segments.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
    }
}

extension View {
    /// A whole screen on the night sky, with lists and forms showing it instead of the system grey.
    func nightBackground() -> some View {
        scrollContentBackground(.hidden).background(NightSky().ignoresSafeArea())
    }
}

/// The night behind every screen: the moonlit sky from the design, fading out into deep navy.
struct NightSky: View {
    var body: some View {
        Editorial.paper
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: 340)
                    .overlay(alignment: .top) { Image("HauntedMoon").resizable().scaledToFill() }
                    .clipped()
                    .opacity(0.38)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .accessibilityHidden(true)
    }
}

/// A List with its rows on night cards. A row's background can only be set from inside the List.
struct CardList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        List { content().listRowBackground(Editorial.card) }
    }
}

/// A Form with its rows on night cards.
struct CardForm<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form { content().listRowBackground(Editorial.card) }
    }
}

/// A quiet secondary button: a navy capsule with a hairline edge and moon-orange text.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .small ? .footnote.weight(.medium) : .subheadline.weight(.semibold))
            .foregroundStyle(Editorial.accent.opacity(enabled ? 1 : 0.4))
            .padding(.horizontal, size == .small ? 12 : 16)
            .padding(.vertical, size == .small ? 6 : (size == .large ? 13 : 9))
            .background(Editorial.tonal.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.75))
    }
}

/// The main action on a screen: a moon-orange capsule with dark text.
struct PumpkinButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Editorial.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, size == .large ? 13 : 9)
            .background(Editorial.accent.opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35), in: Capsule())
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
}

extension ButtonStyle where Self == PumpkinButtonStyle {
    static var pumpkin: PumpkinButtonStyle { PumpkinButtonStyle() }
}

/// A rounded filter chip.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? Editorial.paper : Editorial.ink)
                .background(selected ? Editorial.accent : Editorial.card, in: Capsule())
                .overlay(Capsule().stroke(Editorial.ink.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
