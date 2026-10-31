import Foundation

public struct MeasuredWall: Codable, Equatable, Sendable {
    public var wallID: String
    public var length: Double
    public var mode: CalibrationMode
}

/// What the user changed, kept apart from the geometry so it can be replayed on a rescan.
public struct RoomCorrections: Codable, Equatable, Sendable {
    public var measuredWalls: [MeasuredWall] = []
    /// Scanned openings as the user left them.
    public var editedOpenings: [Opening] = []
    public var addedOpenings: [Opening] = []
    /// Copies of scanned openings the user deleted, so a rescan can recognise them.
    public var deletedOpenings: [Opening] = []
    /// Ids that must never be given to a new opening in this room.
    public var retiredOpeningIDs: [String] = []
    public var cornersMoved = false
    public init() {}
    public var isEmpty: Bool { self == RoomCorrections() }
}

/// A room plus its corrections. Every edit keeps the two in step.
public struct EditableRoom: Codable, Equatable, Sendable {
    public var room: CanonicalRoom
    public var corrections: RoomCorrections

    public init(room: CanonicalRoom, corrections: RoomCorrections = .init()) {
        self.room = room; self.corrections = corrections
    }
}

public enum RoomEditError: Error, Equatable, LocalizedError {
    case unknownOpening, unknownWall, wallTooShort

    public var errorDescription: String? {
        switch self {
        case .unknownOpening: "That door or window isn't in this room."
        case .unknownWall: "That wall isn't in this room."
        case .wallTooShort: "That wall is too short to hold it."
        }
    }
}

public enum OpeningDefaults {
    public static func size(_ t: OpeningType) -> (width: Double, height: Double, sill: Double) {
        switch t {
        case .door: (0.82, 2.03, 0)
        case .window: (1.0, 1.2, 0.9)
        case .opening: (0.9, 2.03, 0)
        }
    }
}

extension EditableRoom {
    // MARK: Corners

    /// Moves a corner, snapping to the neighbouring corners' x and z within 5 cm. Keeps openings where they are on the wall.
    public mutating func moveCorner(_ index: Int, to target: Point2) {
        guard room.floorPolygon.indices.contains(index), room.walls.count == room.floorPolygon.count else { return }
        let n = room.floorPolygon.count
        let prev = room.floorPolygon[(index + n - 1) % n], next = room.floorPolygon[(index + 1) % n]
        var p = target
        for neighbour in [prev, next] {
            if abs(p.x - neighbour.x) <= PlanMath.snapTolerance { p.x = neighbour.x }
            if abs(p.z - neighbour.z) <= PlanMath.snapTolerance { p.z = neighbour.z }
        }
        let inID = room.walls[(index + n - 1) % n].id, outID = room.walls[index].id
        let oldOutLength = room.walls[index].length
        room.floorPolygon[index] = p
        room.walls[(index + n - 1) % n].end = p
        room.walls[index].start = p
        // The wall leaving this corner starts here, so its openings keep their distance from its far end.
        let delta = room.walls[index].length - oldOutLength
        for i in room.openings.indices where room.openings[i].wallID == outID {
            room.openings[i].offset += delta
        }
        corrections.cornersMoved = true
        corrections.measuredWalls.removeAll { $0.wallID == inID || $0.wallID == outID }
    }

    /// Restores the origin at the minimum corner after dragging (FR-D4).
    public mutating func normalise() {
        let b = PlanMath.bounds(room.floorPolygon)
        let shift = Point2(-b.minX, -b.minZ)
        guard shift.length > 0 else { return }
        room.floorPolygon = room.floorPolygon.map { $0 + shift }
        for i in room.walls.indices {
            room.walls[i].start = room.walls[i].start + shift
            room.walls[i].end = room.walls[i].end + shift
        }
    }

    // MARK: Measured walls

    /// Applies a calibration from a preview that the user accepted.
    public mutating func applyMeasurement(wallID: String, measured: Double, mode: CalibrationMode) throws {
        let preview = try RoomCalibration.preview(room, wallID: wallID, measured: measured, mode: mode)
        room = preview.room
        if let i = room.walls.firstIndex(where: { $0.id == wallID }) { room.walls[i].confidence = .high }
        corrections.measuredWalls.removeAll { $0.wallID == wallID }
        corrections.measuredWalls.append(MeasuredWall(wallID: wallID, length: measured, mode: mode))
    }

    // MARK: Openings

    public mutating func updateOpening(_ updated: Opening) throws {
        guard let i = room.openings.firstIndex(where: { $0.id == updated.id }) else { throw RoomEditError.unknownOpening }
        guard room.wall(updated.wallID) != nil else { throw RoomEditError.unknownWall }
        room.openings[i] = updated
        if let a = corrections.addedOpenings.firstIndex(where: { $0.id == updated.id }) {
            corrections.addedOpenings[a] = updated
        } else if let e = corrections.editedOpenings.firstIndex(where: { $0.id == updated.id }) {
            corrections.editedOpenings[e] = updated
        } else {
            corrections.editedOpenings.append(updated)
        }
    }

    public mutating func setSwing(_ id: String, _ swing: DoorSwing) throws {
        guard var o = room.opening(id) else { throw RoomEditError.unknownOpening }
        o.swing = swing
        try updateOpening(o)
    }

    /// Adds an opening centred on a wall, at the default size (FR-R3a).
    @discardableResult
    public mutating func addOpening(type: OpeningType, wallID: String) throws -> Opening {
        guard let wall = room.wall(wallID) else { throw RoomEditError.unknownWall }
        let size = OpeningDefaults.size(type)
        guard wall.length >= size.width else { throw RoomEditError.wallTooShort }
        let height = min(size.height, max(wall.height - size.sill, 0.1))
        let o = Opening(id: nextOpeningID(type), type: type, wallID: wallID, offset: (wall.length - size.width) / 2,
                        width: size.width, height: height, sill: size.sill)
        room.openings.append(o)
        corrections.addedOpenings.append(o)
        return o
    }

    public mutating func deleteOpening(_ id: String) throws {
        guard let o = room.opening(id) else { throw RoomEditError.unknownOpening }
        room.openings.removeAll { $0.id == id }
        corrections.retiredOpeningIDs.append(id)
        if corrections.addedOpenings.contains(where: { $0.id == id }) {
            corrections.addedOpenings.removeAll { $0.id == id }
        } else {
            let original = corrections.editedOpenings.first { $0.id == id } ?? o
            corrections.editedOpenings.removeAll { $0.id == id }
            corrections.deletedOpenings.append(original)
        }
    }

    /// The next id for a type, never reusing one deleted in this room (requirements 6.1).
    public func nextOpeningID(_ type: OpeningType) -> String {
        let used = room.openings.map(\.id) + corrections.retiredOpeningIDs
        let numbers = used.compactMap { id -> Int? in
            guard id.hasPrefix(type.idPrefix) else { return nil }
            return Int(id.dropFirst(type.idPrefix.count))
        }
        return "\(type.idPrefix)\((numbers.max() ?? -1) + 1)"
    }
}
