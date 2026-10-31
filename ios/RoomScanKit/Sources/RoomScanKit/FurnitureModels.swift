import Foundation

// The furniture plan, layout and catalogue.

/// Free space an item needs around it to be usable, in metres.
public struct Clearance: Codable, Sendable, Equatable, Hashable {
    public var front: Double
    public var sides: Double
    public var back: Double

    public init(front: Double = 0, sides: Double = 0, back: Double = 0) {
        self.front = front; self.sides = sides; self.back = back
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        front = try c.decodeIfPresent(Double.self, forKey: .front) ?? 0
        sides = try c.decodeIfPresent(Double.self, forKey: .sides) ?? 0
        back = try c.decodeIfPresent(Double.self, forKey: .back) ?? 0
    }
}

/// One catalogue product. Only `catalog_id`, `name`, `category` and `size` are required.
public struct CatalogEntry: Codable, Sendable, Equatable, Identifiable {
    public var catalogID: String
    public var name: String
    public var category: String
    /// [width, depth, height] in metres.
    public var size: [Double]
    public var styles: [String]
    public var clearance: Clearance
    public var store: String?
    public var url: URL?
    public var price: Double?
    public var currency: String?
    public var note: String?

    public var id: String { catalogID }

    enum CodingKeys: String, CodingKey {
        case catalogID = "catalog_id"
        case name, category, size, styles, clearance, store, url, price, currency, note
    }

    public init(catalogID: String, name: String, category: String, size: [Double], styles: [String] = [],
                clearance: Clearance = Clearance(), store: String? = nil, url: URL? = nil, price: Double? = nil,
                currency: String? = nil, note: String? = nil) {
        self.catalogID = catalogID; self.name = name; self.category = category; self.size = size
        self.styles = styles; self.clearance = clearance; self.store = store; self.url = url
        self.price = price; self.currency = currency; self.note = note
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        catalogID = try c.decode(String.self, forKey: .catalogID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        size = try c.decode([Double].self, forKey: .size)
        styles = try c.decodeIfPresent([String].self, forKey: .styles) ?? []
        clearance = try c.decodeIfPresent(Clearance.self, forKey: .clearance) ?? Clearance()
        store = try c.decodeIfPresent(String.self, forKey: .store)
        // Only web links: a product page must never open anything else.
        url = try c.decodeIfPresent(String.self, forKey: .url).flatMap(Self.webURL)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    /// "$899 CAD", or nil without a price.
    public var priceText: String? {
        price.map { "$\(Int($0.rounded()))" + (currency.map { " \($0)" } ?? "") }
    }

    static func webURL(_ text: String) -> URL? {
        URL(string: text).flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
    }
}

public struct CatalogError: Error, Equatable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct FurnitureCatalog: Sendable {
    public let entries: [CatalogEntry]
    /// When the catalogue was last checked, from the file.
    public let updated: String?
    private let byID: [String: CatalogEntry]

    /// Clearance for items with no catalogue entry, by category. Anything else gets 0.3 m in front.
    static let defaultClearance: [String: Clearance] = [
        "bed": Clearance(front: 0.6, sides: 0.4),
        "desk": Clearance(front: 0.7),
        "wardrobe": Clearance(front: 0.7),
        "dresser": Clearance(front: 0.6),
        "sofa": Clearance(front: 0.5),
        "tv_stand": Clearance(front: 0.9),
        "bookshelf": Clearance(front: 0.5),
    ]
    static let fallbackClearance = Clearance(front: 0.3)

    public init(entries: [CatalogEntry], updated: String? = nil) {
        self.entries = entries
        self.updated = updated
        byID = Dictionary(entries.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Reads a catalogue file. Refuses one that is unreadable or empty, has duplicate ids or an impossible size.
    public init(json: Data) throws {
        struct File: Decodable {
            let items: [CatalogEntry]
            let updated: String?
        }
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: json)
        } catch {
            throw CatalogError("That file isn't a furniture catalogue.")
        }
        guard !file.items.isEmpty else { throw CatalogError("The catalogue has no furniture in it.") }
        guard Set(file.items.map(\.catalogID)).count == file.items.count else {
            throw CatalogError("Two pieces in the catalogue share an id.")
        }
        for item in file.items where item.size.count != 3 || item.size.contains(where: { !($0 > 0 && $0 < 20) }) {
            throw CatalogError("\(item.name) has an impossible size.")
        }
        self.init(entries: file.items, updated: file.updated)
    }

    /// The catalogue built into the app (Resources/catalog.json).
    public static let bundled: FurnitureCatalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? FurnitureCatalog(json: data)
        else { return FurnitureCatalog(entries: []) }
        return catalog
    }()

    public static var current: FurnitureCatalog { bundled }

    public func entry(_ id: String?) -> CatalogEntry? { id.flatMap { byID[$0] } }

    /// This catalogue's pieces, then those of `other` that it doesn't have.
    public func merged(with other: FurnitureCatalog) -> FurnitureCatalog {
        let ids = Set(entries.map(\.catalogID))
        return FurnitureCatalog(entries: entries + other.entries.filter { !ids.contains($0.catalogID) }, updated: updated ?? other.updated)
    }

    public func clearance(for item: FurnitureItem) -> Clearance {
        entry(item.catalogID)?.clearance ?? Self.defaultClearance[item.category] ?? Self.fallbackClearance
    }
}

/// Where an item should go, in the rule vocabulary. Never coordinates.
public enum PlacementRule: Codable, Sendable, Equatable, Hashable {
    case againstWall(wallID: String, align: String)
    case corner(wallID: String, corner: String)
    case centeredInRoom
    case inFrontOf(targetItemID: String, gap: Double)
    case beside(targetItemID: String, side: String, gap: Double)
    case underWindow(openingID: String)

    enum CodingKeys: String, CodingKey {
        case rule
        case wallID = "wall_id"
        case align, corner
        case targetItemID = "target_item_id"
        case gap, side
        case openingID = "opening_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .rule) {
        case "against_wall":
            self = .againstWall(wallID: try c.decode(String.self, forKey: .wallID),
                                align: try c.decodeIfPresent(String.self, forKey: .align) ?? "center")
        case "corner":
            self = .corner(wallID: try c.decode(String.self, forKey: .wallID), corner: try c.decode(String.self, forKey: .corner))
        case "centered_in_room":
            self = .centeredInRoom
        case "in_front_of":
            self = .inFrontOf(targetItemID: try c.decode(String.self, forKey: .targetItemID),
                              gap: try c.decodeIfPresent(Double.self, forKey: .gap) ?? 0.4)
        case "beside":
            self = .beside(targetItemID: try c.decode(String.self, forKey: .targetItemID),
                           side: try c.decode(String.self, forKey: .side),
                           gap: try c.decodeIfPresent(Double.self, forKey: .gap) ?? 0.05)
        case "under_window":
            self = .underWindow(openingID: try c.decode(String.self, forKey: .openingID))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .rule, in: c, debugDescription: "unknown placement rule \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .againstWall(wall, align):
            try c.encode("against_wall", forKey: .rule)
            try c.encode(wall, forKey: .wallID)
            try c.encode(align, forKey: .align)
        case let .corner(wall, corner):
            try c.encode("corner", forKey: .rule)
            try c.encode(wall, forKey: .wallID)
            try c.encode(corner, forKey: .corner)
        case .centeredInRoom:
            try c.encode("centered_in_room", forKey: .rule)
        case let .inFrontOf(target, gap):
            try c.encode("in_front_of", forKey: .rule)
            try c.encode(target, forKey: .targetItemID)
            try c.encode(gap, forKey: .gap)
        case let .beside(target, side, gap):
            try c.encode("beside", forKey: .rule)
            try c.encode(target, forKey: .targetItemID)
            try c.encode(side, forKey: .side)
            try c.encode(gap, forKey: .gap)
        case let .underWindow(opening):
            try c.encode("under_window", forKey: .rule)
            try c.encode(opening, forKey: .openingID)
        }
    }

    /// The item this one is placed relative to, if any.
    public var targetItemID: String? {
        switch self {
        case let .inFrontOf(target, _), let .beside(target, _, _): target
        default: nil
        }
    }
}

/// One piece in a plan.
public struct FurnitureItem: Codable, Sendable, Equatable, Identifiable {
    public var itemID: String
    public var catalogID: String?
    public var name: String
    public var category: String
    /// [width, depth, height] in metres.
    public var size: [Double]
    public var style: String
    public var placement: PlacementRule
    /// 1 is most important: placed first, dropped last.
    public var priority: Int

    public var id: String { itemID }

    public init(itemID: String, catalogID: String? = nil, name: String, category: String, size: [Double], style: String = "",
                placement: PlacementRule, priority: Int) {
        self.itemID = itemID; self.catalogID = catalogID; self.name = name; self.category = category
        self.size = size; self.style = style; self.placement = placement; self.priority = priority
    }

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case catalogID = "catalog_id"
        case name, category, size, style, placement, priority
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try c.decode(String.self, forKey: .itemID)
        catalogID = try c.decodeIfPresent(String.self, forKey: .catalogID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        size = try c.decode([Double].self, forKey: .size)
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        placement = try c.decode(PlacementRule.self, forKey: .placement)
        priority = try c.decode(Int.self, forKey: .priority)
    }
}

/// A design's look: style words, materials and accent colours.
public struct DesignStyle: Codable, Sendable, Equatable {
    public var words: [String]
    public var materials: [String]
    public var accents: [String]

    public init(words: [String] = [], materials: [String] = [], accents: [String] = []) {
        self.words = words; self.materials = materials; self.accents = accents
    }

    public var isEmpty: Bool { words.isEmpty && materials.isEmpty && accents.isEmpty }
}

public struct FurniturePlan: Codable, Sendable, Equatable {
    public var theme: String
    public var items: [FurnitureItem]
    public var style: DesignStyle?

    public init(theme: String, items: [FurnitureItem], style: DesignStyle? = nil) {
        self.theme = theme; self.items = items; self.style = style
    }
}

/// Where each item went, and why the rest didn't fit.
public struct FurnitureLayout: Codable, Sendable, Equatable {
    public struct Placed: Codable, Sendable, Equatable, Identifiable {
        public var itemID: String
        /// Footprint centre.
        public var x: Double
        public var z: Double
        /// Degrees about +Y; at 0 the item's front faces +z.
        public var rotation: Double
        /// [width, depth].
        public var footprint: [Double]
        public var name: String?
        public var category: String?
        public var catalogID: String?
        public var height: Double?

        public var id: String { itemID }

        public init(itemID: String, x: Double, z: Double, rotation: Double, footprint: [Double], name: String? = nil,
                    category: String? = nil, catalogID: String? = nil, height: Double? = nil) {
            self.itemID = itemID; self.x = x; self.z = z; self.rotation = rotation; self.footprint = footprint
            self.name = name; self.category = category; self.catalogID = catalogID; self.height = height
        }

        enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
            case x, z, rotation, footprint, name, category
            case catalogID = "catalog_id"
            case height
        }
    }

    public struct Unplaced: Codable, Sendable, Equatable, Identifiable {
        public var itemID: String
        public var reason: String
        public var id: String { itemID }

        public init(itemID: String, reason: String) {
            self.itemID = itemID; self.reason = reason
        }

        enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
            case reason
        }
    }

    public var placed: [Placed]
    public var unplaced: [Unplaced]

    public init(placed: [Placed], unplaced: [Unplaced] = []) {
        self.placed = placed; self.unplaced = unplaced
    }

    enum CodingKeys: String, CodingKey { case placed, unplaced }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        placed = try c.decode([Placed].self, forKey: .placed)
        unplaced = try c.decodeIfPresent([Unplaced].self, forKey: .unplaced) ?? []
    }
}

/// One broken hard constraint in a finished layout.
public struct LayoutViolation: Codable, Sendable, Equatable, Hashable {
    public var itemID: String?
    public var constraint: String
    public var message: String

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case constraint, message
    }
}
