import Foundation

/// Wall paints that suit a theme's look (FR-L13, 7.8). A paint belongs to one design; the room keeps its real colour.
public enum WallPaint {
    public struct Paint: Codable, Sendable, Equatable, Hashable {
        public var name: String
        public var hex: String

        public init(_ name: String, _ hex: String) {
            self.name = name; self.hex = hex
        }
    }

    /// Sixteen groups of looks and their paints, best first. The more distinctive looks come first.
    static let looks: [(words: [String], paints: [Paint])] = [
        (["cyberpunk", "neon", "synthwave", "futuristic", "gaming", "sci-fi", "scifi"],
         [Paint("midnight navy", "#1B2236"), Paint("blue-black", "#12141C"), Paint("deep purple", "#2E1F47")]),
        (["gothic"], [Paint("deep plum", "#3A1E2C"), Paint("charcoal", "#2B2B30"), Paint("oxblood", "#4A1518")]),
        (["steampunk"], [Paint("oxblood", "#5A1F1A"), Paint("forest green", "#2F3E2E"), Paint("tobacco brown", "#5B4636")]),
        (["deco", "glam", "hollywood"], [Paint("emerald", "#1F4D3A"), Paint("navy", "#1F2A44"), Paint("champagne", "#E8DCC4")]),
        (["victorian", "traditional", "classic"], [Paint("cream", "#F1E8D6"), Paint("sage", "#A3AE96"), Paint("burgundy", "#6A2632")]),
        (["industrial"], [Paint("concrete grey", "#8D8E8A"), Paint("charcoal", "#3A3B3D"), Paint("off-white", "#F2F1EC")]),
        (["boho", "bohemian", "tropical"], [Paint("warm sand", "#E3CBA8"), Paint("terracotta", "#C4704F"), Paint("sage", "#A9B59A")]),
        (["coastal", "nautical", "beach"], [Paint("sea-salt white", "#F1F2EE"), Paint("pale blue", "#C9DCE4"), Paint("navy", "#23395B")]),
        (["mid-century", "retro"], [Paint("warm white", "#F3EEE4"), Paint("teal", "#2F6F73"), Paint("mustard", "#D3A33B")]),
        (["farmhouse", "rustic", "cottage", "cottagecore"], [Paint("warm white", "#F4EFE4"), Paint("greige", "#CFC6B8"), Paint("sage", "#B2BBA0")]),
        (["japandi", "zen"], [Paint("warm white", "#EFEAE1"), Paint("greige", "#CFC6B8"), Paint("clay", "#C9B49C")]),
        (["scandinavian", "nordic"], [Paint("white", "#F4F4F1"), Paint("pale grey", "#DCDCD8"), Paint("soft greige", "#D9D2C6")]),
        (["moody", "dark"], [Paint("charcoal", "#2E3033"), Paint("ink blue", "#1E2838"), Paint("deep green", "#26372F")]),
        (["minimalist", "modern", "contemporary"], [Paint("white", "#F5F5F2"), Paint("light grey", "#DADAD7"), Paint("charcoal", "#3A3B3D")]),
        (["cozy", "cosy", "warm"], [Paint("warm white", "#F1E9DC"), Paint("clay", "#C9A98C"), Paint("terracotta", "#B86F52")]),
        (["bright", "light", "airy"], [Paint("white", "#F5F5F2"), Paint("butter yellow", "#F3E3B0"), Paint("pale blue", "#D5E4EC")]),
    ]

    /// Colours a typed change can name, longest names first so "pale blue" wins over "blue".
    public static let named: [Paint] = {
        var seen = Set<String>()
        var out: [Paint] = []
        let extra = [Paint("mustard", "#D3A33B"), Paint("blush", "#E7C4BC"), Paint("black", "#17171A"), Paint("blue", "#3B5B8C"),
                     Paint("green", "#4B6F52"), Paint("grey", "#8D8E8A"), Paint("pink", "#E3A6B4"), Paint("yellow", "#EBCF6B")]
        for paint in looks.flatMap(\.paints) + extra where seen.insert(paint.name).inserted { out.append(paint) }
        return out.sorted { $0.name.count > $1.name.count }
    }()

    public static func paint(named text: String) -> Paint? {
        let wanted = " " + text.lowercased() + " "
        return named.first { wanted.contains(" \($0.name) ") }
    }

    /// The paints that suit a theme, best first; empty when it names no look.
    public static func suggestions(for theme: String) -> [Paint] {
        let words = FurniturePlanner.words(theme)
        return looks.first { !words.isDisjoint(with: $0.words) }?.paints ?? []
    }

    /// True when the walls are far from every paint that suits the theme. A theme with no look never asks.
    public static func clashes(_ wall: String, theme: String) -> Bool {
        let paints = suggestions(for: theme)
        guard !paints.isEmpty, let w = RoomColours.rgb(wall) else { return false }
        return paints.allSatisfy { paint in
            guard let p = RoomColours.rgb(paint.hex) else { return true }
            // A weighted distance: green counts most, red least.
            let d = (2 * pow(w.r - p.r, 2) + 4 * pow(w.g - p.g, 2) + 3 * pow(w.b - p.b, 2)).squareRoot() / 3
            return d > 0.25
        }
    }
}
