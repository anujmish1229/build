import SwiftUI
import UIKit

/// One light, editorial look regardless of the device's appearance setting (FR-U2).
enum Editorial {
    static let paper = Color(red: 0.965, green: 0.95, blue: 0.925)
    static let card = Color.white
    static let ink = Color(red: 0.13, green: 0.12, blue: 0.11)
    static let accent = Color(red: 0.62, green: 0.3, blue: 0.2)

    static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .semibold, design: .serif) }
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
                .foregroundStyle(selected ? Color.white : Editorial.ink)
                .background(selected ? Editorial.ink : Editorial.card, in: Capsule())
                .overlay(Capsule().stroke(Editorial.ink.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
