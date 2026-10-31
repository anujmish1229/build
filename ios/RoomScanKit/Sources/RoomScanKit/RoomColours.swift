import Foundation

public enum FloorType: String, Codable, Sendable, CaseIterable {
    case wood, laminate, tile, carpet, concrete
}

/// A room's colours. Only averages are ever kept, never a picture (FR-S10).
public struct RoomColours: Codable, Sendable, Equatable {
    public var wall: String
    public var floor: String
    public var floorType: FloorType
    public var detected: Bool

    public init(wall: String = "#EFEBE3", floor: String = "#B58A5E", floorType: FloorType = .wood, detected: Bool = false) {
        self.wall = wall; self.floor = floor; self.floorType = floorType; self.detected = detected
    }

    public var wallName: String { Self.name(wall, surface: "") }
    public var floorName: String { Self.name(floor, surface: floorType.rawValue) }

    /// Red, green and blue from 0 to 1, or nil for a bad value.
    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count == 6, let v = Int(text, radix: 16) else { return nil }
        return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    public static func hex(r: Double, g: Double, b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// Colours from camera samples: the median of each set, which ignores the odd lamp or chair, and a floor
    /// type guessed from its colour (7.7). Nil without at least two samples of each.
    public static func estimate(walls: [(Double, Double, Double)], floors: [(Double, Double, Double)]) -> RoomColours? {
        guard walls.count >= 2, floors.count >= 2 else { return nil }
        func median(_ samples: [(Double, Double, Double)]) -> (Double, Double, Double) {
            func m(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
            return (m(samples.map(\.0)), m(samples.map(\.1)), m(samples.map(\.2)))
        }
        let w = median(walls), f = median(floors)
        let top = max(f.0, f.1, f.2), low = min(f.0, f.1, f.2), saturation = top - low, light = (top + low) / 2
        let warm = f.0 > f.1 && f.1 > f.2
        let type: FloorType = warm && saturation > 0.1 ? .wood : (saturation < 0.08 ? (light > 0.55 ? .tile : .concrete) : .carpet)
        return RoomColours(wall: hex(r: w.0, g: w.1, b: w.2), floor: hex(r: f.0, g: f.1, b: f.2), floorType: type, detected: true)
    }

    /// A plain name, such as "warm off-white" or "honey oak wood" (FR-M5).
    public static func name(_ hex: String, surface: String) -> String {
        guard let c = rgb(hex) else { return surface.isEmpty ? "unknown" : surface }
        let top = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b)
        let light = (top + low) / 2, chroma = top - low
        var base: String
        if chroma < 0.08 {
            base = light > 0.88 ? "white" : light > 0.65 ? "light grey" : light > 0.35 ? "grey" : light > 0.15 ? "charcoal" : "black"
        } else {
            let hue: String
            if c.r == top { hue = c.g > c.b + 0.2 * chroma ? (c.g > c.r * 0.8 ? "yellow" : "orange") : "red" }
            else if c.g == top { hue = "green" }
            else { hue = c.r > c.g ? "purple" : "blue" }
            base = hue
            if surface == "wood" || surface == "laminate" {
                base = light > 0.6 ? "pale" : light > 0.4 ? "honey" : light > 0.22 ? "walnut" : "espresso"
                return "\(base) \(surface)"
            }
            if hue == "orange" || hue == "yellow", chroma < 0.25, light > 0.75 { base = "warm off-white" }
            else if light > 0.75 { base = "pale \(hue)" }
            else if light < 0.3 { base = "deep \(hue)" }
        }
        return surface.isEmpty ? base : "\(base) \(surface)"
    }
}
