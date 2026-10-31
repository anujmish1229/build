import Foundation

public struct MergeReport: Equatable, Sendable {
    public var kept: [String] = []
    public var notKept: [String] = []
}

/// Replays corrections on a fresh scan of the same room (FR-S6, UC11).
public enum RoomMerge {
    public static let cornersNotice = "Corners you dragged by hand aren't carried over to a new scan."
    static let matchDistance = 0.6

    public static func merge(previous: EditableRoom, rescan: CanonicalRoom) -> (result: EditableRoom, report: MergeReport) {
        let wallMap = mapWalls(from: previous.room, to: rescan, openings: previous.corrections)
        var report = MergeReport()
        var out = EditableRoom(room: rescan)
        out.corrections.retiredOpeningIDs = previous.corrections.retiredOpeningIDs
        let prior = previous.corrections

        // Measurements first: edited openings below are positions in the corrected plan.
        for m in prior.measuredWalls {
            guard let wallID = wallMap[m.wallID] else {
                report.notKept.append("The measurement of \(Units.metric(m.length)): that wall wasn't found in the new scan.")
                continue
            }
            do {
                try out.applyMeasurement(wallID: wallID, measured: m.length, mode: m.mode)
                report.kept.append("Measured wall of \(Units.metric(m.length))")
            } catch {
                report.notKept.append("The measurement of \(Units.metric(m.length)): it's too far from the new scan.")
            }
        }

        // Deleted openings stay deleted. Each new opening is matched at most once.
        var claimed = Set<String>()
        for old in prior.deletedOpenings {
            guard let wallID = wallMap[old.wallID] else { continue }
            if let match = nearest(old, wallID: wallID, in: out.room, previous: previous.room, excluding: claimed) {
                claimed.insert(match.id)
                out.room.openings.removeAll { $0.id == match.id }
                var kept = old; kept.id = match.id; kept.wallID = wallID
                out.corrections.deletedOpenings.append(kept)
                if !out.corrections.retiredOpeningIDs.contains(match.id) { out.corrections.retiredOpeningIDs.append(match.id) }
                report.kept.append("Deleted \(old.type.plainName)")
            }
        }

        // Edited openings overwrite the fresh value, keeping the new id.
        for old in prior.editedOpenings {
            guard let wallID = wallMap[old.wallID] else {
                report.notKept.append("Your changes to \(old.type.plainName) \(old.id): its wall wasn't found in the new scan.")
                continue
            }
            guard let match = nearest(old, wallID: wallID, in: out.room, previous: previous.room, excluding: claimed) else {
                report.notKept.append("Your changes to \(old.type.plainName) \(old.id): it wasn't found in the new scan.")
                continue
            }
            claimed.insert(match.id)
            var updated = old
            updated.id = match.id
            updated.wallID = wallID
            if let i = out.room.openings.firstIndex(where: { $0.id == match.id }) { out.room.openings[i] = updated }
            out.corrections.editedOpenings.append(updated)
            report.kept.append(old.swing != nil && old.swing != .unknown ? "Door swing and changes to \(match.id)" : "Changes to \(old.type.plainName) \(match.id)")
        }

        // A fresh id can collide with one retired earlier; give those new ids.
        for i in out.room.openings.indices where prior.retiredOpeningIDs.contains(out.room.openings[i].id) {
            let newID = out.nextOpeningID(out.room.openings[i].type)
            let oldID = out.room.openings[i].id
            out.room.openings[i].id = newID
            if let e = out.corrections.editedOpenings.firstIndex(where: { $0.id == oldID }) { out.corrections.editedOpenings[e].id = newID }
        }

        // Added openings return on the same wall, at the same distance along it.
        for old in prior.addedOpenings {
            guard let wallID = wallMap[old.wallID], let wall = out.room.wall(wallID), wall.length >= old.width else {
                report.notKept.append("The \(old.type.plainName) you added (\(old.id)): its wall wasn't found in the new scan.")
                continue
            }
            var added = old
            added.wallID = wallID
            added.offset = min(max(0, old.offset), wall.length - old.width)
            if out.room.openings.contains(where: { $0.id == added.id }) || out.corrections.retiredOpeningIDs.contains(added.id) {
                added.id = out.nextOpeningID(old.type)
            }
            out.room.openings.append(added)
            out.corrections.addedOpenings.append(added)
            report.kept.append("Added \(old.type.plainName)")
        }

        if prior.cornersMoved { report.notKept.append(cornersNotice) }
        return (out, report)
    }

    /// Finds the same type of opening on the wall, nearest along it.
    static func nearest(_ old: Opening, wallID: String, in room: CanonicalRoom, previous: CanonicalRoom, excluding: Set<String>) -> Opening? {
        let oldCentre = old.offset + old.width / 2
        let candidates = room.openings(onWall: wallID).filter { $0.type == old.type && !excluding.contains($0.id) }
        let best = candidates.min { abs($0.offset + $0.width / 2 - oldCentre) < abs($1.offset + $1.width / 2 - oldCentre) }
        guard let best, abs(best.offset + best.width / 2 - oldCentre) <= matchDistance else { return nil }
        return best
    }

    /// Old wall id to new wall id. With the same wall count, picks the best rotation of the loop;
    /// otherwise matches each wall by its middle and length.
    static func mapWalls(from old: CanonicalRoom, to new: CanonicalRoom, openings: RoomCorrections) -> [String: String] {
        let n = old.walls.count
        guard n > 0, !new.walls.isEmpty else { return [:] }
        var map: [String: String] = [:]
        if new.walls.count == n {
            var bestK = 0
            var bestCost = Double.infinity
            for k in 0..<n {
                var cost = 0.0
                for i in 0..<n {
                    let a = old.walls[i], b = new.walls[(i + k) % n]
                    cost += abs(a.length - b.length)
                    // Opposite walls of a rectangle tie on length, so openings decide.
                    for o in old.openings(onWall: a.id) {
                        let centre = o.offset + o.width / 2
                        let found = new.openings(onWall: b.id).contains {
                            $0.type == o.type && abs($0.offset + $0.width / 2 - centre) <= matchDistance
                        }
                        if !found { cost += 0.25 }
                    }
                }
                if cost < bestCost - 1e-9 { bestCost = cost; bestK = k }
            }
            for i in 0..<n { map[old.walls[i].id] = new.walls[(i + bestK) % n].id }
            return map
        }
        var taken = Set<String>()
        for a in old.walls {
            let mid = (a.start + a.end) * 0.5
            let ranked = new.walls.filter { !taken.contains($0.id) }.map { b -> (Wall, Double) in
                let m = (b.start + b.end) * 0.5
                return (b, m.distance(to: mid) + abs(a.length - b.length))
            }
            if let best = ranked.min(by: { $0.1 < $1.1 }), best.1 <= 0.75 {
                map[a.id] = best.0.id
                taken.insert(best.0.id)
            }
        }
        return map
    }
}
