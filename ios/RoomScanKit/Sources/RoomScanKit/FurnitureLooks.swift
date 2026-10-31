import Foundation

/// What a product's data says about its appearance.
public struct ProductLook: Codable, Sendable, Equatable {
    public var body: String?
    public var frame: String?
    public var upholstery: String?
    public var hardware: String?
    public var form: String?
    public var details: [String]?

    public init(body: String? = nil, frame: String? = nil, upholstery: String? = nil, hardware: String? = nil, form: String? = nil, details: [String]? = nil) {
        self.body = body; self.frame = frame; self.upholstery = upholstery; self.hardware = hardware; self.form = form; self.details = details
    }
}

/// A surface: colour, and how shiny and metallic it is.
public struct Finish: Sendable, Equatable {
    public var r, g, b: Double
    public var roughness: Double
    public var metal: Double

    public init(_ r: Double, _ g: Double, _ b: Double, roughness: Double = 0.75, metal: Double = 0) {
        self.r = r; self.g = g; self.b = b; self.roughness = roughness; self.metal = metal
    }

    public func scaled(_ s: Double) -> Finish {
        var f = self
        f.r = min(r * s, 1); f.g = min(g * s, 1); f.b = min(b * s, 1)
        return f
    }
}

/// Words people use for materials and colours, longest first when matched.
enum Finishes {
    static let table: [String: Finish] = [
        "oak": Finish(0.76, 0.6, 0.42), "walnut": Finish(0.4, 0.27, 0.18), "pine": Finish(0.83, 0.69, 0.48), "ash": Finish(0.82, 0.72, 0.56),
        "birch": Finish(0.86, 0.75, 0.58), "teak": Finish(0.55, 0.38, 0.22), "acacia": Finish(0.56, 0.37, 0.22), "mahogany": Finish(0.36, 0.17, 0.12),
        "dark brown": Finish(0.3, 0.2, 0.13),
        "brass": Finish(0.72, 0.58, 0.32, roughness: 0.32, metal: 0.9), "gold": Finish(0.82, 0.66, 0.3, roughness: 0.3, metal: 0.95),
        "copper": Finish(0.72, 0.42, 0.28, roughness: 0.35, metal: 0.9), "steel": Finish(0.62, 0.63, 0.65, roughness: 0.35, metal: 0.9),
        "iron": Finish(0.2, 0.2, 0.21, roughness: 0.5, metal: 0.8), "chrome": Finish(0.8, 0.8, 0.82, roughness: 0.12, metal: 1),
        "leather": Finish(0.46, 0.29, 0.18, roughness: 0.45), "tan": Finish(0.62, 0.42, 0.26, roughness: 0.5),
        "linen": Finish(0.84, 0.79, 0.7, roughness: 0.92), "velvet": Finish(0.35, 0.42, 0.38, roughness: 0.6), "boucle": Finish(0.93, 0.9, 0.84, roughness: 0.98),
        "wool": Finish(0.78, 0.74, 0.68, roughness: 0.95), "oatmeal": Finish(0.86, 0.8, 0.7, roughness: 0.92),
        "rattan": Finish(0.78, 0.63, 0.42, roughness: 0.85), "marble": Finish(0.92, 0.91, 0.89, roughness: 0.2), "concrete": Finish(0.6, 0.6, 0.58, roughness: 0.9),
        "white": Finish(0.94, 0.94, 0.92, roughness: 0.55), "black": Finish(0.14, 0.14, 0.15, roughness: 0.5), "grey": Finish(0.5, 0.5, 0.52, roughness: 0.8),
        "gray": Finish(0.5, 0.5, 0.52, roughness: 0.8), "charcoal": Finish(0.24, 0.24, 0.26, roughness: 0.85), "cream": Finish(0.93, 0.89, 0.8, roughness: 0.85),
        "beige": Finish(0.84, 0.76, 0.64, roughness: 0.85), "sage": Finish(0.64, 0.68, 0.59, roughness: 0.85), "terracotta": Finish(0.74, 0.42, 0.3, roughness: 0.85),
        "navy": Finish(0.14, 0.2, 0.34, roughness: 0.8), "mustard": Finish(0.82, 0.63, 0.22, roughness: 0.85), "blush": Finish(0.9, 0.76, 0.73, roughness: 0.85),
        "emerald": Finish(0.1, 0.36, 0.26, roughness: 0.65), "burgundy": Finish(0.42, 0.12, 0.18, roughness: 0.7), "teal": Finish(0.18, 0.43, 0.45, roughness: 0.8),
    ]

    static func find(_ text: String?) -> Finish? {
        guard let text else { return nil }
        let wanted = " " + text.lowercased().map { $0.isLetter ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        let names = table.keys.sorted { ($0.count, $0) > ($1.count, $1) }
        return names.first { wanted.contains(" \($0) ") }.flatMap { table[$0] }
    }
}

/// What a named look sets: woods, fabrics, metals and accents.
public struct Vibe: Sendable, Equatable {
    public let wood: Finish
    public let fabric: Finish
    public let metal: Finish
    public let accent: Finish

    static let neutral = Vibe(wood: Finishes.table["oak"]!, fabric: Finish(0.74, 0.72, 0.68, roughness: 0.9), metal: Finishes.table["iron"]!, accent: Finishes.table["sage"]!)

    /// The looks the app knows, with the most distinctive first; the first one mentioned wins.
    static let all: [(word: String, vibe: Vibe)] = [
        ("steampunk", Vibe(wood: Finishes.table["mahogany"]!, fabric: Finishes.table["leather"]!, metal: Finishes.table["brass"]!, accent: Finishes.table["copper"]!)),
        ("gothic", Vibe(wood: Finish(0.14, 0.1, 0.1), fabric: Finishes.table["velvet"]!.scaled(0.5), metal: Finishes.table["iron"]!, accent: Finishes.table["burgundy"]!)),
        ("cyberpunk", Vibe(wood: Finishes.table["black"]!, fabric: Finishes.table["charcoal"]!, metal: Finishes.table["chrome"]!, accent: Finish(0.85, 0.15, 0.6, roughness: 0.4))),
        ("deco", Vibe(wood: Finish(0.2, 0.13, 0.1, roughness: 0.25), fabric: Finishes.table["emerald"]!, metal: Finishes.table["gold"]!, accent: Finishes.table["gold"]!)),
        ("industrial", Vibe(wood: Finish(0.45, 0.32, 0.22, roughness: 0.9), fabric: Finishes.table["charcoal"]!, metal: Finishes.table["iron"]!, accent: Finishes.table["tan"]!)),
        ("boho", Vibe(wood: Finishes.table["rattan"]!, fabric: Finishes.table["cream"]!, metal: Finishes.table["brass"]!, accent: Finishes.table["terracotta"]!)),
        ("japandi", Vibe(wood: Finishes.table["oak"]!, fabric: Finishes.table["linen"]!, metal: Finishes.table["black"]!, accent: Finishes.table["sage"]!)),
        ("scandinavian", Vibe(wood: Finishes.table["birch"]!, fabric: Finishes.table["wool"]!, metal: Finishes.table["white"]!, accent: Finish(0.62, 0.72, 0.78, roughness: 0.85))),
        ("mid-century", Vibe(wood: Finishes.table["walnut"]!, fabric: Finishes.table["teal"]!, metal: Finishes.table["brass"]!, accent: Finishes.table["mustard"]!)),
        ("minimalist", Vibe(wood: Finishes.table["white"]!, fabric: Finish(0.86, 0.86, 0.84, roughness: 0.9), metal: Finishes.table["steel"]!, accent: Finishes.table["grey"]!)),
        ("modern", Vibe(wood: Finishes.table["walnut"]!, fabric: Finishes.table["grey"]!, metal: Finishes.table["black"]!, accent: Finishes.table["navy"]!)),
        ("dark", Vibe(wood: Finishes.table["dark brown"]!, fabric: Finishes.table["charcoal"]!, metal: Finishes.table["black"]!, accent: Finishes.table["burgundy"]!)),
        ("warm", Vibe(wood: Finishes.table["teak"]!, fabric: Finishes.table["beige"]!, metal: Finishes.table["brass"]!, accent: Finishes.table["terracotta"]!)),
    ]
    public static var words: [String] { all.map(\.word) }

    static func of(_ style: DesignStyle?) -> Vibe {
        let words = Set((style?.words ?? []).flatMap { FurniturePlanner.words($0) } + (style?.words ?? []))
        return all.first { words.contains($0.word) }?.vibe ?? neutral
    }
}

extension DesignStyle {
    /// What a theme's words say: looks, materials and colours the app knows.
    public init(theme: String) {
        let words = FurniturePlanner.words(theme)
        self.init(words: Vibe.words.filter(words.contains),
                  materials: FurniturePlanner.materialNames.filter(words.contains),
                  accents: FurniturePlanner.accentNames.filter(words.contains))
    }
}

/// The finishes one piece is drawn in. The product's data comes first, then its name, then the design's look.
public struct ResolvedLook: Sendable, Equatable {
    public let body: Finish
    public let frame: Finish
    public let upholstery: Finish
    public let hardware: Finish
    public let accent: Finish
    public let bedding: Finish
    public let rounded: Bool

    static let upholstered: Set<String> = ["sofa", "armchair", "bed", "bench"]

    public init(entry: CatalogEntry?, name: String, category: String, style: DesignStyle?) {
        let vibe = Vibe.of(style)
        let look = entry?.look
        let named = Finishes.find(entry?.name ?? name)
        let material = (style?.materials ?? []).lazy.compactMap { Finishes.find($0) }.first
        let accentWord = (style?.accents ?? []).lazy.compactMap { Finishes.find($0) }.first
        let isSoft = Self.upholstered.contains(category) && category != "bed"
        body = Finishes.find(look?.body) ?? (isSoft ? nil : named) ?? material ?? vibe.wood
        frame = Finishes.find(look?.frame) ?? (named?.metal ?? 0 > 0.5 ? named : nil) ?? vibe.metal
        upholstery = Finishes.find(look?.upholstery) ?? (isSoft ? named : nil) ?? vibe.fabric
        hardware = Finishes.find(look?.hardware) ?? vibe.metal
        accent = accentWord ?? vibe.accent
        bedding = vibe.fabric.r + vibe.fabric.g + vibe.fabric.b < 0.9 ? vibe.fabric.scaled(1.3) : Finish(0.95, 0.94, 0.91, roughness: 0.92)
        rounded = look?.form == "round" || (entry?.name ?? name).lowercased().contains("round")
    }
}
