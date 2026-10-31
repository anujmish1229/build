import Foundation

public struct Wall: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var start: Point2
    public var end: Point2
    public var height: Double
    public var confidence: Confidence

    public init(id: String, start: Point2, end: Point2, height: Double, confidence: Confidence = .high) {
        self.id = id; self.start = start; self.end = end; self.height = height; self.confidence = confidence
    }
    public var length: Double { start.distance(to: end) }
    public var direction: Point2 { (end - start).normalized }
    public var inwardNormal: Point2 { direction.leftNormal }
    public func point(at offset: Double) -> Point2 { start + direction * offset }
}

public enum OpeningType: String, Codable, Sendable, CaseIterable {
    case door, window, opening
    public var idPrefix: String {
        switch self { case .door: "d"; case .window: "win"; case .opening: "op" }
    }
    public var plainName: String {
        switch self { case .door: "door"; case .window: "window"; case .opening: "gap" }
    }
}

public enum DoorSwing: String, Codable, Sendable, CaseIterable {
    case inwardLeft = "inward_left", inwardRight = "inward_right"
    case outwardLeft = "outward_left", outwardRight = "outward_right"
    case unknown
    public var isInward: Bool { self == .inwardLeft || self == .inwardRight }
    public var isOutward: Bool { self == .outwardLeft || self == .outwardRight }
}

public struct Opening: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: OpeningType
    public var wallID: String
    public var offset: Double
    public var width: Double
    public var height: Double
    public var sill: Double
    public var swing: DoorSwing?

    enum CodingKeys: String, CodingKey {
        case id, type, offset, width, height, sill, swing
        case wallID = "wall_id"
    }

    public init(id: String, type: OpeningType, wallID: String, offset: Double, width: Double,
                height: Double, sill: Double, swing: DoorSwing? = nil) {
        self.id = id; self.type = type; self.wallID = wallID; self.offset = offset
        self.width = width; self.height = height; self.sill = sill
        self.swing = type == .door ? (swing ?? .unknown) : nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(OpeningType.self, forKey: .type)
        wallID = try c.decode(String.self, forKey: .wallID)
        offset = try c.decode(Double.self, forKey: .offset)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        sill = try c.decodeIfPresent(Double.self, forKey: .sill) ?? 0
        let s = try c.decodeIfPresent(DoorSwing.self, forKey: .swing)
        swing = type == .door ? (s ?? .unknown) : nil
    }
}

/// Values computed from a room. Recalculated on every load and never written.
public struct RoomDerived: Equatable, Sendable {
    public let area: Double
    public let bounds: Bounds
    public let perimeter: Double
    public let wallLengths: [String: Double]
}

/// `room.json`. The source of truth for everything else.
public struct CanonicalRoom: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var units: String
    public var source: String
    public var ceilingHeight: Double
    public var floorPolygon: [Point2]
    public var walls: [Wall]
    public var openings: [Opening]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case units, source, walls, openings
        case ceilingHeight = "ceiling_height"
        case floorPolygon = "floor_polygon"
    }

    public init(source: String, ceilingHeight: Double, floorPolygon: [Point2], walls: [Wall], openings: [Opening]) {
        schemaVersion = Self.currentSchemaVersion
        units = "m"; self.source = source; self.ceilingHeight = ceilingHeight
        self.floorPolygon = floorPolygon; self.walls = walls; self.openings = openings
    }

    /// Builds a room whose walls follow the polygon. For sample rooms and tests.
    public static func make(polygon: [Point2], ceiling: Double = 2.5, openings: [Opening] = [], source: String = "manual") -> CanonicalRoom {
        var walls: [Wall] = []
        for i in polygon.indices {
            walls.append(Wall(id: "w\(i)", start: polygon[i], end: polygon[(i + 1) % polygon.count], height: ceiling))
        }
        return CanonicalRoom(source: source, ceilingHeight: ceiling, floorPolygon: polygon, walls: walls, openings: openings)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c,
                debugDescription: "Unsupported room version \(schemaVersion)")
        }
        units = try c.decodeIfPresent(String.self, forKey: .units) ?? "m"
        guard units == "m" else {
            throw DecodingError.dataCorruptedError(forKey: .units, in: c, debugDescription: "Rooms are stored in metres")
        }
        source = try c.decode(String.self, forKey: .source)
        ceilingHeight = try c.decode(Double.self, forKey: .ceilingHeight)
        floorPolygon = try c.decode([Point2].self, forKey: .floorPolygon)
        walls = try c.decode([Wall].self, forKey: .walls)
        openings = try c.decodeIfPresent([Opening].self, forKey: .openings) ?? []
    }

    public static func decode(_ data: Data) throws -> CanonicalRoom { try JSONDecoder().decode(CanonicalRoom.self, from: data) }
    public func encoded() throws -> Data { try RoomJSON.encoder().encode(self) }

    public var derived: RoomDerived {
        RoomDerived(area: abs(PlanMath.signedArea(floorPolygon)),
                    bounds: PlanMath.bounds(floorPolygon),
                    perimeter: PlanMath.perimeter(floorPolygon),
                    wallLengths: Dictionary(walls.map { ($0.id, $0.length) }, uniquingKeysWith: { a, _ in a }))
    }

    public func wall(_ id: String) -> Wall? { walls.first { $0.id == id } }
    public func opening(_ id: String) -> Opening? { openings.first { $0.id == id } }
    public func openings(onWall id: String) -> [Opening] { openings.filter { $0.wallID == id } }
}
