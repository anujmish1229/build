import Foundation

/// JSON formats shared by every file the engine reads and writes.
public enum RoomJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

public enum Confidence: String, Codable, Sendable, CaseIterable {
    case high, medium, low

    /// The lower of two confidences; a merged wall is only as sure as its weakest piece.
    public func worst(_ other: Confidence) -> Confidence {
        let order: [Confidence] = [.low, .medium, .high]
        return order.first { $0 == self || $0 == other } ?? self
    }
}

/// One surface exactly as the scanner reported it.
public struct RawSurface: Codable, Equatable, Sendable {
    public var id: String
    public var category: String
    /// [width, height, depth] in metres.
    public var dimensions: [Double]
    /// 16 numbers, column-major.
    public var transform: [Double]
    public var confidence: Confidence
    public var parentID: String?

    enum CodingKeys: String, CodingKey {
        case id, category, dimensions, transform, confidence
        case parentID = "parent_id"
    }

    public init(id: String, category: String, dimensions: [Double], transform: [Double],
                confidence: Confidence = .high, parentID: String? = nil) {
        self.id = id; self.category = category; self.dimensions = dimensions
        self.transform = transform; self.confidence = confidence; self.parentID = parentID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(String.self, forKey: .category)
        dimensions = try c.decode([Double].self, forKey: .dimensions)
        transform = try c.decode([Double].self, forKey: .transform)
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .medium
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        guard dimensions.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: .dimensions, in: c, debugDescription: "dimensions must have 3 values")
        }
        guard transform.count == 16 else {
            throw DecodingError.dataCorruptedError(forKey: .transform, in: c, debugDescription: "transform must have 16 values")
        }
    }

    public var width: Double { dimensions[0] }
    public var height: Double { dimensions[1] }
    public var centre: (x: Double, y: Double, z: Double) { (transform[12], transform[13], transform[14]) }
    /// The surface's local x axis, along its width.
    public var xAxis: (x: Double, y: Double, z: Double) { (transform[0], transform[1], transform[2]) }
}

public struct RawDevice: Codable, Equatable, Sendable {
    public var model: String
    public var osVersion: String
    enum CodingKeys: String, CodingKey { case model; case osVersion = "os_version" }
    public init(model: String, osVersion: String) { self.model = model; self.osVersion = osVersion }
}

/// The scan with structure only. It has no field for detected furniture, so
/// `objects` in any input is dropped by construction.
public struct RawRoom: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var source: String
    public var capturedAt: String
    public var device: RawDevice
    public var walls: [RawSurface]
    public var doors: [RawSurface]
    public var windows: [RawSurface]
    public var openings: [RawSurface]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source, device, walls, doors, windows, openings
        case capturedAt = "captured_at"
    }

    public init(source: String = "roomplan", capturedAt: String, device: RawDevice,
                walls: [RawSurface], doors: [RawSurface] = [], windows: [RawSurface] = [], openings: [RawSurface] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.source = source; self.capturedAt = capturedAt; self.device = device
        self.walls = walls; self.doors = doors; self.windows = windows; self.openings = openings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c,
                debugDescription: "Unsupported raw scan version \(schemaVersion)")
        }
        source = try c.decode(String.self, forKey: .source)
        capturedAt = try c.decode(String.self, forKey: .capturedAt)
        device = try c.decode(RawDevice.self, forKey: .device)
        walls = try c.decode([RawSurface].self, forKey: .walls)
        doors = try c.decodeIfPresent([RawSurface].self, forKey: .doors) ?? []
        windows = try c.decodeIfPresent([RawSurface].self, forKey: .windows) ?? []
        openings = try c.decodeIfPresent([RawSurface].self, forKey: .openings) ?? []
    }

    public static func decode(_ data: Data) throws -> RawRoom {
        try JSONDecoder().decode(RawRoom.self, from: data)
    }

    public func encoded() throws -> Data { try RoomJSON.encoder().encode(self) }

    /// A plain summary of what was found, such as "4 walls, 1 door, 2 windows".
    public var summary: String {
        func part(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        var parts = [part(walls.count, "wall", "walls"), part(doors.count, "door", "doors"), part(windows.count, "window", "windows")]
        if !openings.isEmpty { parts.append(part(openings.count, "gap", "gaps")) }
        return parts.joined(separator: ", ")
    }

    /// Fewer than three walls can't enclose a room.
    public var hasEnoughWalls: Bool { walls.count >= 3 }
}
