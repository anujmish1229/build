import Foundation

public enum CalibrationMode: String, Codable, Sendable, CaseIterable {
    /// Scale the whole plan by one factor.
    case uniform
    /// Change length along this wall only.
    case stretch
}

public struct CalibrationPreview: Equatable, Sendable {
    public struct Change: Equatable, Sendable {
        public let wallID: String
        public let before: Double
        public let after: Double
    }
    public let factor: Double
    public let room: CanonicalRoom
    public let changes: [Change]
}

public enum CalibrationError: Error, Equatable, LocalizedError {
    case unknownWall
    case invalidLength
    case factorOutOfRange(Double)

    public var errorDescription: String? {
        switch self {
        case .unknownWall: "That wall isn't in this room."
        case .invalidLength: "Enter a length above zero."
        case .factorOutOfRange(let f):
            "That would change the wall by \(String(format: "%.2f", f)) times. Only changes between 0.5 and 2 times are allowed, so please check the measurement and the wall you selected."
        }
    }
}

/// Fits the room to one tape-measured wall (FR-R2).
public enum RoomCalibration {
    public static let factorRange = 0.5...2.0

    public static func preview(_ room: CanonicalRoom, wallID: String, measured: Double, mode: CalibrationMode) throws -> CalibrationPreview {
        guard let wall = room.wall(wallID), wall.length > 0 else { throw CalibrationError.unknownWall }
        guard measured > 0, measured.isFinite else { throw CalibrationError.invalidLength }
        let factor = measured / wall.length
        guard factorRange.contains(factor) else { throw CalibrationError.factorOutOfRange(factor) }
        let after = mode == .uniform ? uniform(room, factor: factor) : stretch(room, wall: wall, measured: measured)
        let changes = zip(room.walls, after.walls).compactMap { old, new -> CalibrationPreview.Change? in
            abs(old.length - new.length) < 0.0005 ? nil : .init(wallID: old.id, before: old.length, after: new.length)
        }
        return CalibrationPreview(factor: factor, room: after, changes: changes)
    }

    static func uniform(_ room: CanonicalRoom, factor f: Double) -> CanonicalRoom {
        var r = room
        r.floorPolygon = room.floorPolygon.map { $0 * f }
        for i in r.walls.indices {
            r.walls[i].start = room.walls[i].start * f
            r.walls[i].end = room.walls[i].end * f
        }
        for i in r.openings.indices {
            r.openings[i].offset *= f
            r.openings[i].width *= f
        }
        return r
    }

    /// Corners on the far half of the wall's axis move along it. Walls crossing the wall stay as they are.
    static func stretch(_ room: CanonicalRoom, wall: Wall, measured: Double) -> CanonicalRoom {
        let dir = wall.direction
        let delta = measured - wall.length
        let cut = wall.start.dot(dir) + wall.length / 2
        func moved(_ p: Point2) -> Bool { p.dot(dir) >= cut }
        func move(_ p: Point2) -> Point2 { moved(p) ? p + dir * delta : p }
        var r = room
        r.floorPolygon = room.floorPolygon.map(move)
        for i in r.walls.indices {
            r.walls[i].start = move(room.walls[i].start)
            r.walls[i].end = move(room.walls[i].end)
        }
        for i in r.openings.indices {
            guard let old = room.wall(r.openings[i].wallID), let new = r.wall(r.openings[i].wallID) else { continue }
            // When only a wall's start moved, keep the opening's distance from its fixed end.
            if moved(old.start) != moved(old.end), moved(old.start) {
                r.openings[i].offset += new.length - old.length
            }
        }
        return r
    }
}
