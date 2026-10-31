import Foundation

// The user's library: named rooms, their designs, the user's boards and kept pins (6.7).

public struct SavedRoom: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var room: CanonicalRoom
    /// The scan it came from, so a rescan can be compared; nil for a shared or sample room.
    public var rawScan: RawRoom?
    public var sourceIDs: [String: [String]]
    public var corrections: RoomCorrections
    public var colours: RoomColours

    public init(id: UUID = UUID(), name: String, room: CanonicalRoom, rawScan: RawRoom? = nil, sourceIDs: [String: [String]] = [:],
                corrections: RoomCorrections = RoomCorrections(), colours: RoomColours = RoomColours(), createdAt: Date = Date()) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.updatedAt = createdAt; self.room = room
        self.rawScan = rawScan; self.sourceIDs = sourceIDs; self.corrections = corrections; self.colours = colours
    }

    public var editable: EditableRoom { EditableRoom(room: room, corrections: corrections) }
}

/// A furnished design for one room. Products are a snapshot, so names, prices and links survive catalogue changes (FR-G1).
public struct SavedDesign: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var roomID: UUID
    public var name: String
    public var createdAt: Date
    public var theme: String
    public var plan: FurniturePlan
    public var layout: FurnitureLayout
    public var notes: String
    public var provider: String
    public var summary: String
    public var products: [CatalogEntry]
    public var remixedFrom: String?
    public var wallPaint: WallPaint.Paint?
    /// The ready-made design this still is, unchanged. It's already on the Board as inspiration, so it isn't shown again as the user's.
    public var exampleOf: String?

    public init(id: UUID = UUID(), roomID: UUID, name: String, theme: String, plan: FurniturePlan, layout: FurnitureLayout,
                notes: String = "", provider: String = "", summary: String = "", products: [CatalogEntry] = [],
                remixedFrom: String? = nil, wallPaint: WallPaint.Paint? = nil, exampleOf: String? = nil, createdAt: Date = Date()) {
        self.exampleOf = exampleOf
        self.id = id; self.roomID = roomID; self.name = name; self.createdAt = createdAt; self.theme = theme
        self.plan = plan; self.layout = layout; self.notes = notes; self.provider = provider; self.summary = summary
        self.products = products; self.remixedFrom = remixedFrom; self.wallPaint = wallPaint
    }

    public init(option: LayoutOption, roomID: UUID, name: String, theme: String, remixedFrom: String? = nil, wallPaint: WallPaint.Paint? = nil) {
        self.init(roomID: roomID, name: name, theme: theme, plan: option.plan, layout: option.layout, notes: option.notes,
                  provider: option.provider, summary: option.summary, products: option.products, remixedFrom: remixedFrom, wallPaint: wallPaint)
    }

    public var option: LayoutOption {
        LayoutOption(id: 0, plan: plan, layout: layout, summary: summary, notes: notes, provider: provider, products: products)
    }

    public var placedProducts: [CatalogEntry] { layout.placed.compactMap { p in products.first { $0.catalogID == p.catalogID } } }
}

/// A design on the Board.
public struct BoardPin: Codable, Sendable, Equatable, Identifiable {
    public enum Source: String, Codable, Sendable, CaseIterable {
        case starter, feed, shared, mine
        public var label: String {
            switch self {
            case .starter: "Inspiration"
            case .feed: "From the feed"
            case .shared: "Shared with you"
            case .mine: "Yours"
            }
        }
    }

    public var id: String
    public var source: Source
    public var design: DesignPackage

    public init(id: String, source: Source, design: DesignPackage) {
        self.id = id; self.source = source; self.design = design
    }
}

public struct Board: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var pinIDs: [String]

    public init(id: UUID = UUID(), name: String, pinIDs: [String] = []) {
        self.id = id; self.name = name; self.pinIDs = pinIDs
    }
}

public struct Library: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version = Library.currentVersion
    public var rooms: [SavedRoom] = []
    public var designs: [SavedDesign] = []
    public var boards: [Board] = []
    public var pins: [BoardPin] = []
    /// Samples are only added once, so they don't come back after the user deletes everything.
    public var samplesAdded = false
    /// Whether a library from before the sample rooms came furnished has been given its examples.
    public var examplesAdded = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        rooms = try c.decodeIfPresent([SavedRoom].self, forKey: .rooms) ?? []
        designs = try c.decodeIfPresent([SavedDesign].self, forKey: .designs) ?? []
        boards = try c.decodeIfPresent([Board].self, forKey: .boards) ?? []
        pins = try c.decodeIfPresent([BoardPin].self, forKey: .pins) ?? []
        samplesAdded = try c.decodeIfPresent(Bool.self, forKey: .samplesAdded) ?? !rooms.isEmpty
        examplesAdded = try c.decodeIfPresent(Bool.self, forKey: .examplesAdded) ?? false
    }

    public func designs(for roomID: UUID) -> [SavedDesign] {
        designs.filter { $0.roomID == roomID }.sorted { $0.createdAt > $1.createdAt }
    }

    public func room(_ id: UUID) -> SavedRoom? { rooms.first { $0.id == id } }

    /// "Bedroom 2" when "Bedroom" is taken (FR-M1).
    public func freeRoomName(_ base: String) -> String { Self.free(base, taken: Set(rooms.map(\.name))) }

    public func freeDesignName(_ base: String, in roomID: UUID) -> String {
        Self.free(base, taken: Set(designs.filter { $0.roomID == roomID }.map(\.name)))
    }

    public static func free(_ base: String, taken: Set<String>) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : base.trimmingCharacters(in: .whitespaces)
        if !taken.contains(trimmed) { return trimmed }
        var n = 2
        while taken.contains("\(trimmed) \(n)") { n += 1 }
        return "\(trimmed) \(n)"
    }
}

/// Keeps the library in one protected JSON file. A file that can't be read is moved aside and never
/// overwritten, and `problem` says so (requirements 12.4).
public final class LibraryStore: @unchecked Sendable {
    public let file: URL
    /// Why the saved library couldn't be opened, when it couldn't.
    public private(set) var problem: String?
    private let lock = NSLock()
    private var library = Library()

    public init(directory: URL) {
        file = directory.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let data = try Data(contentsOf: file)
            library = try Migrations.library(from: data)
        } catch {
            let isNewer = (error as? Migrations.Failure) == .newer
            let aside = ProtectedFile.setAside(file)
            problem = (isNewer ? "Your library was saved by a newer version of the app." : "Your library couldn't be read.")
                + (aside == nil ? "" : " The file was kept, not overwritten, and you're starting with an empty library.")
        }
    }

    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RoomScanLibrary", isDirectory: true)
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public var current: Library {
        lock.lock()
        defer { lock.unlock() }
        return library
    }

    /// Changes the library and saves it. If the save fails nothing changes, in memory or on disk.
    @discardableResult
    public func update<T>(_ change: (inout Library) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        var copy = library
        let result = try change(&copy)
        try ProtectedFile.write(Self.encoder.encode(copy), to: file)
        library = copy
        return result
    }

    @discardableResult
    public func addRoom(_ room: SavedRoom) throws -> SavedRoom {
        try update { lib in
            var r = room
            r.name = lib.freeRoomName(room.name)
            lib.rooms.insert(r, at: 0)
            return r
        }
    }

    public func updateRoom(_ id: UUID, _ change: (inout SavedRoom) -> Void) throws {
        try update { lib in
            guard let i = lib.rooms.firstIndex(where: { $0.id == id }) else { return }
            change(&lib.rooms[i])
            lib.rooms[i].updatedAt = Date()
        }
    }

    public func renameRoom(_ id: UUID, to name: String) throws {
        try update { lib in
            guard let i = lib.rooms.firstIndex(where: { $0.id == id }) else { return }
            lib.rooms[i].name = Library.free(name, taken: Set(lib.rooms.filter { $0.id != id }.map(\.name)))
        }
    }

    /// Deletes a room and every design made for it.
    public func deleteRoom(_ id: UUID) throws {
        try update { lib in
            lib.rooms.removeAll { $0.id == id }
            lib.designs.removeAll { $0.roomID == id }
        }
    }

    @discardableResult
    public func addDesign(_ design: SavedDesign) throws -> SavedDesign {
        try update { lib in
            var d = design
            d.name = lib.freeDesignName(design.name, in: design.roomID)
            lib.designs.insert(d, at: 0)
            return d
        }
    }

    public func updateDesign(_ id: UUID, _ change: (inout SavedDesign) -> Void) throws {
        try update { lib in
            guard let i = lib.designs.firstIndex(where: { $0.id == id }) else { return }
            change(&lib.designs[i])
        }
    }

    public func deleteDesign(_ id: UUID) throws {
        try update { lib in lib.designs.removeAll { $0.id == id } }
    }

    @discardableResult
    public func addBoard(_ name: String) throws -> Board {
        try update { lib in
            let board = Board(name: Library.free(name, taken: Set(lib.boards.map(\.name))))
            lib.boards.append(board)
            return board
        }
    }

    public func renameBoard(_ id: UUID, to name: String) throws {
        try update { lib in
            guard let i = lib.boards.firstIndex(where: { $0.id == id }) else { return }
            lib.boards[i].name = Library.free(name, taken: Set(lib.boards.filter { $0.id != id }.map(\.name)))
        }
    }

    public func deleteBoard(_ id: UUID) throws {
        try update { lib in lib.boards.removeAll { $0.id == id } }
    }

    /// Saves a pin to a board, keeping a copy so it stays even if a feed drops it (FR-B6).
    public func save(_ pin: BoardPin, to boardID: UUID) throws {
        try update { lib in
            if !lib.pins.contains(where: { $0.id == pin.id }) { lib.pins.append(pin) }
            guard let i = lib.boards.firstIndex(where: { $0.id == boardID }) else { return }
            if !lib.boards[i].pinIDs.contains(pin.id) { lib.boards[i].pinIDs.insert(pin.id, at: 0) }
        }
    }

    public func remove(pinID: String, from boardID: UUID) throws {
        try update { lib in
            guard let i = lib.boards.firstIndex(where: { $0.id == boardID }) else { return }
            lib.boards[i].pinIDs.removeAll { $0 == pinID }
        }
    }

    public func addPin(_ pin: BoardPin) throws {
        try update { lib in
            lib.pins.removeAll { $0.id == pin.id }
            lib.pins.insert(pin, at: 0)
        }
    }

    public func deletePin(_ id: String) throws {
        try update { lib in
            lib.pins.removeAll { $0.id == id }
            for i in lib.boards.indices { lib.boards[i].pinIDs.removeAll { $0 == id } }
        }
    }

    /// Adds the sample rooms once (FR-M6).
    public func addSamplesIfNeeded(starter: [DesignPackage] = StarterBoard.load()) throws {
        if !current.samplesAdded { return try addSamples(starter: starter) }
        guard !current.examplesAdded else { return }
        // A library from an earlier version: furnish its untouched sample rooms and add the holiday room, once.
        try update { lib in
            lib.examplesAdded = true
            for sample in SampleRooms.all {
                if sample.name == SampleRooms.holidayRoomName {
                    Self.add(sample, starter: starter, to: &lib)
                } else if let i = lib.rooms.firstIndex(where: { $0.room == sample.room }), lib.designs(for: lib.rooms[i].id).isEmpty {
                    var room = lib.rooms[i]
                    Self.furnish(&room, from: sample, starter: starter, in: &lib)
                    lib.rooms[i] = room
                }
            }
        }
    }

    /// Adds every sample room, each with its ready-made designs (FR-M6).
    public func addSamples(starter: [DesignPackage] = StarterBoard.load()) throws {
        try update { lib in
            lib.samplesAdded = true
            lib.examplesAdded = true
            for sample in SampleRooms.all.reversed() { Self.add(sample, starter: starter, to: &lib) }
        }
    }

    private static func add(_ sample: SampleRooms.Sample, starter: [DesignPackage], to lib: inout Library) {
        var room = SavedRoom(name: lib.freeRoomName(sample.name), room: sample.room)
        furnish(&room, from: sample, starter: starter, in: &lib)
        lib.rooms.insert(room, at: 0)
    }

    /// Gives a room the first design's colours, and the designs. Any other wall colour is that design's paint.
    private static func furnish(_ room: inout SavedRoom, from sample: SampleRooms.Sample, starter: [DesignPackage], in lib: inout Library) {
        let designs = StarterBoard.designs(for: sample, in: starter)
        guard let first = designs.first else { return }
        room.colours = first.colours
        // The holiday room has neutral walls of its own, since each of its designs paints them.
        if sample.name == SampleRooms.holidayRoomName { room.colours.wall = "#EFE8DC" }
        for (n, design) in designs.enumerated() {
            let wall = design.colours.wall
            let paint = wall == room.colours.wall ? nil : WallPaint.Paint(design.colours.wallName, wall)
            lib.designs.insert(SavedDesign(roomID: room.id, name: lib.freeDesignName(design.title, in: room.id), theme: design.theme, plan: design.plan,
                                           layout: design.layout, notes: "", provider: "Ready-made example", summary: design.notes,
                                           products: design.products, wallPaint: paint, exampleOf: design.id, createdAt: Date().addingTimeInterval(-Double(n))), at: 0)
        }
    }

    /// Removes all rooms, designs, boards and pins (FR-T2). Samples stay gone.
    public func deleteAll() throws {
        try update { lib in
            lib = Library()
            lib.samplesAdded = true
            lib.examplesAdded = true
        }
    }
}
