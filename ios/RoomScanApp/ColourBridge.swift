import RoomScanKit
import SwiftUI
import UIKit

/// Between stored "#RRGGBB" text and SwiftUI colours.
enum ColourBridge {
    static func color(_ hex: String) -> Color {
        let c = RoomColours.rgb(hex) ?? (0.8, 0.8, 0.8)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
    }

    static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RoomColours.hex(r: Double(r), g: Double(g), b: Double(b))
    }
}

/// A colour picker for the room's walls or floor, with its plain name.
struct ColourEditor: View {
    @Binding var colours: RoomColours

    var body: some View {
        ColorPicker(selection: Binding(get: { ColourBridge.color(colours.wall) }, set: { colours.wall = ColourBridge.hex($0); colours.detected = false }), supportsOpacity: false) {
            LabeledContent("Walls", value: colours.wallName)
        }
        ColorPicker(selection: Binding(get: { ColourBridge.color(colours.floor) }, set: { colours.floor = ColourBridge.hex($0); colours.detected = false }), supportsOpacity: false) {
            LabeledContent("Floor", value: colours.floorName)
        }
        Picker("Floor type", selection: $colours.floorType) {
            ForEach(FloorType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
    }
}

struct ColourSwatches: View {
    let colours: RoomColours
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(ColourBridge.color(colours.wall)).frame(width: 14, height: 14).overlay(Circle().stroke(.secondary.opacity(0.4)))
            Circle().fill(ColourBridge.color(colours.floor)).frame(width: 14, height: 14).overlay(Circle().stroke(.secondary.opacity(0.4)))
        }
        .accessibilityLabel("Walls \(colours.wallName), floor \(colours.floorName)")
    }
}
