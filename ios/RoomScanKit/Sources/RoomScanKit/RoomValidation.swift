import Foundation

public enum IssueLevel: String, Codable, Sendable, Comparable {
    case error, warning, info
    private var rank: Int { switch self { case .error: 0; case .warning: 1; case .info: 2 } }
    public static func < (a: IssueLevel, b: IssueLevel) -> Bool { a.rank < b.rank }
}

/// A plain-English problem, tied to the wall or opening it names (FR-R6).
public struct RoomIssue: Codable, Equatable, Identifiable, Sendable {
    public var level: IssueLevel
    public var code: String
    public var message: String
    public var wallID: String?
    public var openingID: String?
    public var id: String { [code, wallID ?? "", openingID ?? ""].joined(separator: "|") }

    public init(_ level: IssueLevel, _ code: String, _ message: String, wallID: String? = nil, openingID: String? = nil) {
        self.level = level; self.code = code; self.message = message; self.wallID = wallID; self.openingID = openingID
    }
}

public enum RoomValidation {
    public static let minSide = 0.5, maxSide = 50.0
    public static let minCeiling = 1.0, maxCeiling = 20.0
    public static let usualCeiling = 1.8...6.0

    public static func validate(_ room: CanonicalRoom, units: UnitSystem = .metric) -> [RoomIssue] {
        var issues: [RoomIssue] = []
        func len(_ v: Double) -> String { Units.format(v, units) }
        let polygon = room.floorPolygon

        // Ids.
        var seen = Set<String>()
        for id in room.walls.map(\.id) + room.openings.map(\.id) where !seen.insert(id).inserted {
            issues.append(.init(.error, "duplicate_id", "Two parts of this room share the name \(id)."))
        }

        // Polygon.
        if polygon.count < 3 {
            issues.append(.init(.error, "too_few_corners", "A room needs at least three corners."))
            return issues
        }
        if !polygon.allSatisfy({ $0.x.isFinite && $0.z.isFinite }) {
            issues.append(.init(.error, "bad_number", "Some corner positions aren't valid numbers."))
            return issues
        }
        for i in polygon.indices where polygon[i].distance(to: polygon[(i + 1) % polygon.count]) < 0.01 {
            issues.append(.init(.error, "repeated_corner", "Two corners are in the same place."))
            break
        }
        if PlanMath.isSelfIntersecting(polygon) {
            issues.append(.init(.error, "self_crossing", "The walls cross each other. Check the corners."))
        }
        let area = PlanMath.signedArea(polygon)
        if area <= 0 {
            issues.append(.init(.error, "bad_orientation", area == 0
                ? "The floor outline has no area."
                : "The floor outline runs the wrong way round."))
        }

        // Size.
        let b = PlanMath.bounds(polygon)
        for side in [b.width, b.depth] {
            if side < minSide {
                issues.append(.init(.error, "room_too_small", "This room is only \(len(side)) across. It needs to be at least \(len(minSide))."))
                break
            }
            if side > maxSide {
                issues.append(.init(.error, "room_too_large", "This room is \(len(side)) across. The limit is \(len(maxSide))."))
                break
            }
        }
        if room.ceilingHeight < minCeiling || room.ceilingHeight > maxCeiling {
            issues.append(.init(.error, "ceiling_out_of_range", "A ceiling height of \(len(room.ceilingHeight)) isn't possible here. It must be between \(len(minCeiling)) and \(len(maxCeiling))."))
        } else if !usualCeiling.contains(room.ceilingHeight) {
            issues.append(.init(.warning, "ceiling_unusual", "The ceiling height of \(len(room.ceilingHeight)) is unusual. Please check it."))
        }

        // Walls agree with the outline, in order.
        if room.walls.count != polygon.count {
            issues.append(.init(.error, "walls_mismatch", "The walls don't match the floor outline."))
        } else {
            let tol = PlanMath.wallAgreementTolerance
            for (i, w) in room.walls.enumerated() {
                let a = polygon[i], z = polygon[(i + 1) % polygon.count]
                if w.start.distance(to: a) > tol || w.end.distance(to: z) > tol {
                    issues.append(.init(.error, "wall_off_outline", "Wall \(i + 1) doesn't follow the floor outline.", wallID: w.id))
                }
            }
        }

        // Confidence.
        for (i, w) in room.walls.enumerated() where w.confidence == .low {
            issues.append(.init(.warning, "low_confidence", "Wall \(i + 1) wasn't seen clearly. It's worth measuring it.", wallID: w.id))
        }

        // Openings.
        let wallNumber = Dictionary(room.walls.enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { a, _ in a })
        for o in room.openings {
            let name = o.type.plainName.capitalized
            guard let wall = room.wall(o.wallID) else {
                issues.append(.init(.error, "unknown_wall", "\(name) \(o.id) is on a wall that doesn't exist.", openingID: o.id))
                continue
            }
            let n = wallNumber[o.wallID] ?? 0
            if o.width <= 0 || o.height <= 0 {
                issues.append(.init(.error, "bad_opening_size", "\(name) \(o.id) needs a width and height above zero.", wallID: wall.id, openingID: o.id))
                continue
            }
            if o.offset < -0.001 || o.offset + o.width > wall.length + 0.001 {
                issues.append(.init(.error, "opening_outside_wall", "\(name) \(o.id) runs past the end of wall \(n), which is \(len(wall.length)) long.", wallID: wall.id, openingID: o.id))
            }
            if o.sill < 0 {
                issues.append(.init(.error, "negative_sill", "\(name) \(o.id) starts below the floor.", wallID: wall.id, openingID: o.id))
            }
            if o.sill + o.height > wall.height + 0.001 {
                issues.append(.init(.error, "opening_above_wall", "\(name) \(o.id) is taller than wall \(n), which is \(len(wall.height)) high.", wallID: wall.id, openingID: o.id))
            }
            if o.type == .door, o.swing == .unknown {
                issues.append(.init(.info, "unknown_swing", "We don't know which way door \(o.id) swings, so the space in front of it is kept clear.", wallID: wall.id, openingID: o.id))
            }
        }
        for w in room.walls {
            let list = room.openings(onWall: w.id).sorted { $0.offset < $1.offset }
            for i in list.indices {
                for j in list.indices where j > i {
                    let a = list[i], c = list[j]
                    let alongOverlap = a.offset + a.width > c.offset + 0.001 && c.offset + c.width > a.offset + 0.001
                    let heightOverlap = a.sill + a.height > c.sill + 0.001 && c.sill + c.height > a.sill + 0.001
                    if alongOverlap && heightOverlap {
                        issues.append(.init(.error, "openings_overlap", "\(a.type.plainName.capitalized) \(a.id) overlaps \(c.type.plainName) \(c.id).", wallID: w.id, openingID: a.id))
                    }
                }
            }
        }
        return issues.sorted { $0.level < $1.level }
    }

    public static func hasErrors(_ issues: [RoomIssue]) -> Bool { issues.contains { $0.level == .error } }
}
