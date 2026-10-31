import Foundation

/// A board feed file: `format` is `roomscan.board`.
public struct FeedFile: Codable, Sendable, Equatable {
    public static let format = "roomscan.board"
    public var format: String
    public var version: Int
    public var title: String
    public var designs: [DesignPackage]

    public init(title: String, designs: [DesignPackage]) {
        format = Self.format; version = 1; self.title = title; self.designs = designs
    }

    /// Reads a feed, refusing one that is invalid or from a newer format.
    public static func read(_ data: Data) throws -> FeedFile {
        struct Header: Decodable {
            let format: String?
            let version: Int?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == format else {
            throw CatalogError("That address isn't a board feed.")
        }
        guard (header.version ?? 1) <= 1 else { throw CatalogError("That feed was made by a newer version of the app.") }
        guard let feed = try? LibraryStore.decoder.decode(FeedFile.self, from: data) else { throw CatalogError("That feed is damaged.") }
        return feed
    }

    public func encoded() throws -> Data { try LibraryStore.encoder.encode(self) }
}

/// The only place the app uses the network, and only for an address the user entered.
public struct FeedStore: Sendable {
    public let file: URL

    public init(directory: URL) { file = directory.appendingPathComponent("feed.json") }

    public func load() -> FeedFile? { (try? Data(contentsOf: file)).flatMap { try? FeedFile.read($0) } }

    public func delete() { try? FileManager.default.removeItem(at: file) }

    /// https only; plain http only to the device itself.
    public static func checkedURL(_ address: String) throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            throw CatalogError("That doesn't look like a web address.")
        }
        guard scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw CatalogError("Feeds must use a secure (https) address.")
        }
        return url
    }

    public func refresh(from address: String, session: URLSession = URLSession(configuration: .ephemeral)) async throws -> FeedFile {
        let url = try Self.checkedURL(address)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw CatalogError("The feed couldn't be downloaded. Check the address and your connection.")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError("The feed couldn't be downloaded (error \(http.statusCode)).")
        }
        let feed = try FeedFile.read(data)
        try ProtectedFile.write(data, to: file)
        return feed
    }
}

/// What the Board shows, and its filters.
public enum BoardContents {
    public struct Filter: Equatable, Sendable {
        public var source: BoardPin.Source?
        public var roomType: String?
        public var style: String?
        public init(source: BoardPin.Source? = nil, roomType: String? = nil, style: String? = nil) {
            self.source = source; self.roomType = roomType; self.style = style
        }
    }

    public static func minePins(_ library: Library) -> [BoardPin] {
        library.designs.filter { $0.exampleOf == nil }.compactMap { design in
            library.room(design.roomID).map { BoardPin(id: design.id.uuidString, source: .mine, design: DesignPackage(design, room: $0)) }
        }
    }

    /// Yours, then shared, then the feed, then the starter inspiration. Each design appears once.
    public static func pins(library: Library, feed: FeedFile?, starter: [DesignPackage]) -> [BoardPin] {
        let shared = library.pins.filter { $0.source == .shared }
        let fromFeed = (feed?.designs ?? []).map { BoardPin(id: $0.id, source: .feed, design: $0) }
        let fromStarter = starter.map { BoardPin(id: $0.id, source: .starter, design: $0) }
        var seen = Set<String>()
        return (minePins(library) + shared + fromFeed + fromStarter).filter { seen.insert($0.id).inserted }
    }

    public static func filtered(_ pins: [BoardPin], _ filter: Filter) -> [BoardPin] {
        pins.filter { pin in
            (filter.source == nil || pin.source == filter.source)
                && (filter.roomType == nil || pin.design.roomType == filter.roomType)
                && (filter.style == nil || pin.design.styles.contains(filter.style!))
        }
    }

    /// Every design as a feed file, to host elsewhere.
    public static func exportFeed(_ library: Library, title: String = "My designs") -> FeedFile {
        FeedFile(title: title, designs: minePins(library).map(\.design))
    }

    /// Masonry columns: each card goes to the shorter column.
    public static func columns<T>(_ items: [T], count: Int = 2, height: (T) -> Double) -> [[T]] {
        var out = Array(repeating: [T](), count: max(count, 1))
        var heights = Array(repeating: 0.0, count: max(count, 1))
        for item in items {
            let i = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            out[i].append(item)
            heights[i] += height(item)
        }
        return out
    }
}

/// The ready-made designs that are on the Board from the first launch. They load from a
/// file with no solving, however large the catalogue is.
public enum StarterBoard {
    struct Recipe {
        let id: String
        let title: String
        let theme: String
        let room: Int
        let wall: String
        let floor: String
        let floorType: FloorType
    }

    /// The holiday room comes first; both designs share its floor, and each paints the walls its own colour.
    static let recipes = [
        Recipe(id: "starter-halloween", title: "Haunted Halloween lounge", theme: "halloween living room", room: 3, wall: Season.halloween.paint.hex, floor: "#6B4A32", floorType: .wood),
        Recipe(id: "starter-christmas", title: "Cosy Christmas living room", theme: "christmas living room", room: 3, wall: Season.christmas.paint.hex, floor: "#6B4A32", floorType: .wood),
        Recipe(id: "starter-1", title: "Calm japandi retreat", theme: "calm japandi bedroom in oak", room: 0, wall: "#EFEAE1", floor: "#C2A27C", floorType: .wood),
        Recipe(id: "starter-2", title: "After-dark bedroom", theme: "dark modern bedroom", room: 0, wall: "#2E3033", floor: "#5B4636", floorType: .wood),
        Recipe(id: "starter-3", title: "Warm boho lounge", theme: "warm boho living room", room: 1, wall: "#E3CBA8", floor: "#B58A5E", floorType: .wood),
        Recipe(id: "starter-4", title: "Mid-century living", theme: "mid-century living room in walnut", room: 1, wall: "#F3EEE4", floor: "#8F6A48", floorType: .wood),
        Recipe(id: "starter-5", title: "Quiet scandinavian lounge", theme: "scandinavian living room", room: 1, wall: "#F4F4F1", floor: "#D9C4A5", floorType: .wood),
        Recipe(id: "starter-6", title: "Minimal home office", theme: "minimalist home office", room: 2, wall: "#F5F5F2", floor: "#B8B5AF", floorType: .concrete),
        Recipe(id: "starter-7", title: "Modern study", theme: "modern office with a warm feel", room: 2, wall: "#DADAD7", floor: "#8F6A48", floorType: .wood),
        Recipe(id: "starter-8", title: "Scandinavian dining", theme: "scandinavian dining room", room: 2, wall: "#DCDCD8", floor: "#D9C4A5", floorType: .wood),
    ]

    /// The file that ships with the app. Empty only if the file is missing, which a test guards against.
    public static func load() -> [DesignPackage] {
        // Ready-made designs for a catalogue built into this copy of the app come first.
        if let url = Bundle.main.url(forResource: "ikea-starter", withExtension: "json"),
           let data = try? Data(contentsOf: url), let feed = try? FeedFile.read(data) {
            return feed.designs
        }
        guard let url = Bundle.module.url(forResource: "starter_board", withExtension: "json"),
              let data = try? Data(contentsOf: url), let feed = try? FeedFile.read(data) else { return [] }
        return feed.designs
    }

    /// The ready-made designs for a sample room, kept with the room so it isn't empty.
    static func designs(for sample: SampleRooms.Sample, in shipped: [DesignPackage]) -> [DesignPackage] {
        shipped.filter { $0.room == sample.room }
    }

    /// Makes the designs from the sample rooms and catalogue, with the rules only, so the result never varies.
    public static func generate(catalog: FurnitureCatalog = .bundled) async -> FeedFile {
        var designs: [DesignPackage] = []
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        for recipe in recipes {
            let sample = SampleRooms.all[recipe.room]
            let colours = RoomColours(wall: recipe.wall, floor: recipe.floor, floorType: recipe.floorType)
            let options = await DesignStudio.options(room: sample.room, theme: recipe.theme, colours: colours, catalog: catalog, count: 1, reader: nil)
            guard let option = options.first else { continue }
            designs.append(DesignPackage(id: recipe.id, title: recipe.title, theme: recipe.theme, notes: option.summary,
                                         roomType: DesignPackage.roomType(of: option.plan), styles: DesignPackage.styles(of: option.plan, products: option.products),
                                         room: sample.room, colours: colours, plan: option.plan, layout: option.layout, products: option.products,
                                         author: "Poltar", createdAt: date))
        }
        return FeedFile(title: "Inspiration", designs: designs)
    }
}

extension DesignStudio {
    /// A design refitted to another room, its pieces kept where they fit.
    public static func remix(_ design: DesignPackage, into room: CanonicalRoom, catalog: FurnitureCatalog = .current, count: Int = 3) -> [LayoutOption] {
        // Their products count even if this catalogue doesn't have them.
        let merged = FurnitureCatalog(entries: design.products).merged(with: catalog)
        let theirs = WallRoles(design.room)
        let placed = Set(design.layout.placed.map(\.itemID))
        var candidates: [LayoutOption] = []
        for (n, anchor) in anchorWalls(room).enumerated() {
            let mine = WallRoles(room, anchor: anchor)
            let items = design.plan.items.filter { placed.contains($0.itemID) }.map { item -> FurnitureItem in
                var item = item
                item.placement = mapped(item.placement, from: theirs, theirRoom: design.room, to: mine)
                return item
            }
            let plan = FurniturePlan(theme: design.theme, items: items, style: design.plan.style)
            let (fitted, layout, swaps) = FurniturePlanner.fitted(plan, room: room, catalog: merged)
            var notes = "Remixed from “\(design.title)”: \(layout.placed.count) of its \(design.layout.placed.count) pieces fit your room."
            if !swaps.isEmpty { notes += " " + swaps.joined(separator: " ") }
            candidates.append(option(n, fitted, layout, room: room, notes: notes, provider: "Remix", catalog: merged))
        }
        return pick(candidates, count: count)
    }

    /// A wall's role in their room as the same role in yours, and your window for theirs.
    static func mapped(_ rule: PlacementRule, from theirs: WallRoles, theirRoom: CanonicalRoom, to mine: WallRoles) -> PlacementRule {
        func wall(_ id: String) -> String {
            if id == theirs.main { return mine.main }
            if id == theirs.opposite { return mine.opposite }
            guard let i = theirs.sides.firstIndex(of: id), !mine.sides.isEmpty else { return mine.firstSide }
            return mine.sides[min(i, mine.sides.count - 1)]
        }
        switch rule {
        case let .againstWall(id, align): return .againstWall(wallID: wall(id), align: align)
        case let .corner(id, corner): return .corner(wallID: wall(id), corner: corner)
        case let .underWindow(opening):
            if let window = mine.windows.first { return .underWindow(openingID: window) }
            let fallback = theirRoom.opening(opening).map { wall($0.wallID) } ?? mine.firstSide
            return .againstWall(wallID: fallback, align: "center")
        default:
            return rule
        }
    }
}
