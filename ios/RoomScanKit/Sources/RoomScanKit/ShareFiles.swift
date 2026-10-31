import Foundation

/// A design as it travels: in a shared file, on the Board, or in a feed. It carries its room, colours,
/// plan, layout and products, so it can be viewed, shopped and remixed anywhere (FR-H2).
public struct DesignPackage: Codable, Sendable, Equatable {
    public static let format = "roomscan.design"

    public var format: String
    public var version: Int
    public var id: String
    public var title: String
    public var theme: String
    public var notes: String
    public var roomType: String
    public var styles: [String]
    public var room: CanonicalRoom
    public var colours: RoomColours
    public var plan: FurniturePlan
    public var layout: FurnitureLayout
    public var products: [CatalogEntry]
    public var author: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, title: String, theme: String, notes: String, roomType: String, styles: [String],
                room: CanonicalRoom, colours: RoomColours, plan: FurniturePlan, layout: FurnitureLayout, products: [CatalogEntry],
                author: String? = nil, createdAt: Date = Date()) {
        format = Self.format; version = 1; self.id = id; self.title = title; self.theme = theme; self.notes = notes
        self.roomType = roomType; self.styles = styles; self.room = room; self.colours = colours; self.plan = plan
        self.layout = layout; self.products = products; self.author = author; self.createdAt = createdAt
    }

    public init(_ design: SavedDesign, room: SavedRoom, author: String? = nil) {
        var colours = room.colours
        if let paint = design.wallPaint { colours.wall = paint.hex }
        self.init(id: design.id.uuidString, title: design.name, theme: design.theme, notes: design.notes,
                  roomType: Self.roomType(of: design.plan), styles: Self.styles(of: design.plan, products: design.products),
                  room: room.room, colours: colours, plan: design.plan, layout: design.layout, products: design.products,
                  author: author, createdAt: design.createdAt)
    }

    public var placedProducts: [CatalogEntry] { layout.placed.compactMap { p in products.first { $0.catalogID == p.catalogID } } }

    public var stores: [String] {
        var seen: [String] = []
        for p in placedProducts { if let s = p.store, !seen.contains(s) { seen.append(s) } }
        return seen
    }

    public static func roomType(of plan: FurniturePlan) -> String {
        let categories = Set(plan.items.map(\.category))
        if categories.contains("bed") { return "bedroom" }
        if categories.contains("sofa") || categories.contains("tv_stand") { return "living" }
        if categories.contains("desk") { return "office" }
        if categories.contains("dining_table") { return "dining" }
        return "living"
    }

    /// The design's own style words, then the products' most common ones.
    public static func styles(of plan: FurniturePlan, products: [CatalogEntry]) -> [String] {
        var counts: [String: Int] = [:]
        for p in products { for s in p.styles { counts[s, default: 0] += 1 } }
        let common = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        var out: [String] = []
        for s in (plan.style?.words ?? []) + common where !out.contains(s) { out.append(s) }
        return Array(out.prefix(4))
    }
}

/// A room as it travels in a `.roomscan` file: never the raw scan or corrections (FR-H1).
public struct ScanPackage: Codable, Sendable, Equatable {
    public static let format = "roomscan.scan"

    public var format: String
    public var version: Int
    public var name: String
    public var room: CanonicalRoom
    public var colours: RoomColours
    public var createdAt: Date

    public init(_ room: SavedRoom) {
        format = Self.format; version = 1; name = room.name; self.room = room.room
        colours = room.colours; createdAt = room.createdAt
    }
}

/// The files people send each other.
public enum ShareFiles {
    public static let scanExtension = "roomscan"
    public static let designExtension = "roomdesign"
    public static let scanType = "com.anujmish1229.roomscan.scan"
    public static let designType = "com.anujmish1229.roomscan.design"

    public enum Shared: Sendable, Equatable {
        case scan(ScanPackage)
        case design(DesignPackage)
    }

    public static func data(_ scan: ScanPackage) throws -> Data { try LibraryStore.encoder.encode(scan) }
    public static func data(_ design: DesignPackage) throws -> Data { try LibraryStore.encoder.encode(design) }

    /// Reads a shared file, refusing one that is damaged, isn't ours, or came from a newer app (FR-H4).
    public static func read(_ data: Data) throws -> Shared {
        struct Header: Decodable {
            let format: String?
            let version: Int?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), let format = header.format else {
            throw CatalogError("That file isn't a room or a design from this app.")
        }
        guard Migrations.shareFileVersion(header.version) <= 1 else {
            throw CatalogError("That file was made by a newer version of the app. Update the app to open it.")
        }
        do {
            switch format {
            case ScanPackage.format: return .scan(try decodeFilling(ScanPackage.self, from: data))
            case DesignPackage.format: return .design(try decodeFilling(DesignPackage.self, from: data))
            default: throw CatalogError("That file isn't a room or a design from this app.")
            }
        } catch let error as CatalogError {
            throw error
        } catch {
            throw CatalogError("That file is damaged and couldn't be opened.")
        }
    }

    /// Fills in a missing version before decoding, so a file from before versions existed still opens.
    private static func decodeFilling<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if json["version"] == nil { json["version"] = 1 }
        return try LibraryStore.decoder.decode(type, from: JSONSerialization.data(withJSONObject: json))
    }

    /// A safe file name from a title: "Japandi calm.roomdesign".
    public static func fileName(_ title: String, ext: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleaned.isEmpty ? "Room" : String(cleaned.prefix(60))).\(ext)"
    }

    /// Writes a temporary file for the share sheet.
    public static func temporaryFile(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
