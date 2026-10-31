import Foundation

public enum RoomImportError: Error, Equatable, LocalizedError {
    case tooFewWalls(Int)
    case notClosed

    public var errorDescription: String? {
        switch self {
        case .tooFewWalls(let n): "That scan found only \(n) wall\(n == 1 ? "" : "s"). A room needs at least three."
        case .notClosed: "The walls in that scan don't join up into a closed room. Please scan again, including every corner."
        }
    }
}

public struct ImportResult: Equatable, Sendable {
    public var room: CanonicalRoom
    /// Canonical wall id to the scanner's surface ids it was built from.
    public var sourceIDs: [String: [String]]
    public var issues: [RoomIssue]
}

/// Raw scan to canonical room (requirements 7.1 to 7.3).
public enum RoomImport {
    /// The biggest corner gap that is still treated as the same corner.
    static let linkTolerance = 0.45

    struct Segment {
        var a: Point2
        var b: Point2
        var top: Double
        var confidence: Confidence
        var ids: [String]
    }

    public static func importRoom(_ raw: RawRoom) throws -> ImportResult {
        guard raw.hasEnoughWalls else { throw RoomImportError.tooFewWalls(raw.walls.count) }

        // 7.1: endpoints, floor level, heights.
        let floorY = raw.walls.map { $0.centre.y - $0.height / 2 }.min() ?? 0
        let segments: [Segment] = raw.walls.map { s in
            let c = s.centre, d = s.xAxis, h = s.width / 2
            // Project the wall's axis to the plan and renormalise, in case the wall leans slightly.
            let dir = Point2(d.x, d.z).normalized
            return Segment(a: Point2(c.x, c.z) - dir * h, b: Point2(c.x, c.z) + dir * h,
                           top: c.y + s.height / 2 - floorY, confidence: s.confidence, ids: [s.id])
        }
        let ceiling = segments.map(\.top).max() ?? 0

        // 7.2: snap, chain, merge, intersect.
        let snapped = snap(segments)
        let (chain, leftovers) = try traceLoop(snapped)
        var merged = mergeCollinear(chain)
        guard merged.count >= 3 else { throw RoomImportError.notClosed }
        var corners = trueCorners(merged)
        if PlanMath.signedArea(corners) < 0 {
            merged = merged.reversed().map { var s = $0; swap(&s.a, &s.b); return s }
            corners = trueCorners(merged)
        }

        // 7.2 step 4: canonical pose.
        let pose = CanonicalPose(corners: corners)
        var outline = corners.map(pose.apply)
        let shift = outline.indices.min { lessCorner(outline[$0], outline[$1]) } ?? 0
        outline = Array(outline[shift...] + outline[..<shift]).map { Point2(PlanMath.tidy($0.x), PlanMath.tidy($0.z)) }
        let order = merged.indices.map { merged[($0 + shift) % merged.count] }

        var walls: [Wall] = []
        var sourceIDs: [String: [String]] = [:]
        for i in outline.indices {
            let id = "w\(i)"
            walls.append(Wall(id: id, start: outline[i], end: outline[(i + 1) % outline.count],
                              height: PlanMath.tidy(order[i].top), confidence: order[i].confidence))
            sourceIDs[id] = order[i].ids
        }

        // 7.3: openings.
        var issues: [RoomIssue] = []
        var openings: [Opening] = []
        let lookup = Dictionary(zip(walls.indices, order).flatMap { i, s in s.ids.map { ($0, walls[i].id) } }, uniquingKeysWith: { a, _ in a })
        for (surfaces, type) in [(raw.doors, OpeningType.door), (raw.windows, .window), (raw.openings, .opening)] {
            for (n, s) in surfaces.enumerated() {
                let c = pose.apply(Point2(s.centre.x, s.centre.z))
                let wall = assign(centre: c, parent: s.parentID, walls: walls, lookup: lookup)
                guard let wall else {
                    issues.append(.init(.warning, "opening_dropped", "A \(type.plainName) from the scan wasn't near any wall, so it was left out."))
                    continue
                }
                var offset = (c - wall.start).dot(wall.direction) - s.width / 2
                var width = s.width
                if width > wall.length { width = wall.length }
                let id = "\(type.idPrefix)\(n)"
                let slide = max(0, -offset, offset + width - wall.length)
                offset = min(max(0, offset), wall.length - width)
                if slide > PlanMath.snapTolerance {
                    issues.append(.init(.warning, "opening_moved", "\(type.plainName.capitalized) \(id) ran past the end of its wall by \(Units.metric(slide)), so it was moved inside. Please check it.", wallID: wall.id, openingID: id))
                }
                var sill = max(0, s.centre.y - s.height / 2 - floorY)
                if type != .window, sill < PlanMath.snapTolerance { sill = 0 }
                var height = s.height
                if sill + height > wall.height { height = max(0.01, wall.height - sill) }
                openings.append(Opening(id: id, type: type, wallID: wall.id, offset: PlanMath.tidy(offset), width: PlanMath.tidy(width),
                                        height: PlanMath.tidy(height), sill: PlanMath.tidy(sill)))
            }
        }

        if !leftovers.isEmpty {
            issues.append(.init(.warning, "extra_walls", "\(leftovers.count) wall piece\(leftovers.count == 1 ? " wasn't" : "s weren't") part of the room's outline and \(leftovers.count == 1 ? "was" : "were") left out."))
        }

        let room = CanonicalRoom(source: raw.source, ceilingHeight: PlanMath.tidy(ceiling), floorPolygon: outline, walls: walls, openings: openings)
        return ImportResult(room: room, sourceIDs: sourceIDs, issues: issues + RoomValidation.validate(room))
    }

    static func lessCorner(_ a: Point2, _ b: Point2) -> Bool {
        abs(a.z - b.z) > 1e-6 ? a.z < b.z : a.x < b.x
    }

    /// Endpoints within 5 cm move to their shared average.
    static func snap(_ segments: [Segment]) -> [Segment] {
        var points = segments.flatMap { [$0.a, $0.b] }
        var used = [Bool](repeating: false, count: points.count)
        for i in points.indices where !used[i] {
            var group = [i]
            for j in points.indices where j > i && !used[j] && points[i].distance(to: points[j]) <= PlanMath.snapTolerance {
                group.append(j); used[j] = true
            }
            guard group.count > 1 else { continue }
            let mean = group.reduce(Point2(0, 0)) { $0 + points[$1] } * (1 / Double(group.count))
            for g in group { points[g] = mean }
        }
        var out = segments
        for i in out.indices { out[i].a = points[i * 2]; out[i].b = points[i * 2 + 1] }
        return out
    }

    /// Follows wall ends from the longest wall until the loop closes. Pieces off the loop are left over.
    static func traceLoop(_ segments: [Segment]) throws -> (chain: [Segment], leftovers: [Segment]) {
        guard let first = segments.indices.max(by: { segments[$0].a.distance(to: segments[$0].b) < segments[$1].a.distance(to: segments[$1].b) }) else {
            throw RoomImportError.notClosed
        }
        var remaining = Array(segments.indices.filter { $0 != first })
        var chain = [segments[first]]
        while true {
            let head = chain.last!.b
            let closeGap = head.distance(to: chain[0].a)
            var best: (index: Int, flip: Bool, gap: Double)?
            for r in remaining {
                let s = segments[r]
                for (flip, end) in [(false, s.a), (true, s.b)] {
                    let gap = head.distance(to: end)
                    if gap <= linkTolerance, best == nil || gap < best!.gap { best = (r, flip, gap) }
                }
            }
            // Closing wins once there are enough walls and no nearer piece continues the chain.
            if chain.count >= 3, closeGap <= linkTolerance, best == nil || closeGap <= best!.gap { break }
            guard let next = best else { throw RoomImportError.notClosed }
            var s = segments[next.index]
            if next.flip { swap(&s.a, &s.b) }
            chain.append(s)
            remaining.removeAll { $0 == next.index }
        }
        return (chain, remaining.map { segments[$0] })
    }

    /// Joins consecutive pieces of the same straight wall.
    static func mergeCollinear(_ chain: [Segment]) -> [Segment] {
        func collinear(_ s: Segment, _ t: Segment) -> Bool {
            let u = (s.b - s.a).normalized, v = (t.b - t.a).normalized
            guard u.dot(v) > 0.998 else { return false }  // About 3.5 degrees.
            // A step between two parallel walls is a real corner, not one wall.
            return abs((t.a - s.b).cross(u)) < PlanMath.snapTolerance
        }
        func join(_ s: Segment, _ t: Segment) -> Segment {
            Segment(a: s.a, b: t.b, top: max(s.top, t.top), confidence: s.confidence.worst(t.confidence), ids: s.ids + t.ids)
        }
        var out: [Segment] = []
        for s in chain {
            if let last = out.last, collinear(last, s) { out[out.count - 1] = join(last, s) } else { out.append(s) }
        }
        while out.count > 3, let f = out.first, let l = out.last, collinear(l, f) {
            out[0] = join(l, f)
            out.removeLast()
        }
        return out
    }

    /// Each corner is where adjacent wall lines meet, or the midpoint if they are nearly parallel.
    static func trueCorners(_ walls: [Segment]) -> [Point2] {
        walls.indices.map { i in
            let prev = walls[(i + walls.count - 1) % walls.count], cur = walls[i]
            let mid = (prev.b + cur.a) * 0.5
            if let hit = PlanMath.lineIntersection(prev.a, prev.b, cur.a, cur.b), hit.distance(to: mid) <= linkTolerance * 2 {
                return hit
            }
            return mid
        }
    }

    static func assign(centre c: Point2, parent: String?, walls: [Wall], lookup: [String: String]) -> Wall? {
        if let parent, let id = lookup[parent], let wall = walls.first(where: { $0.id == id }) { return wall }
        var best: (wall: Wall, distance: Double)?
        for w in walls {
            let d = PlanMath.distance(c, toSegment: w.start, w.end)
            if best == nil || d < best!.distance - 1e-9 { best = (w, d) }
        }
        guard let best, best.distance <= 0.5 else { return nil }
        return best.wall
    }
}

/// Rotates the longest wall onto +x with the room on +z, then moves the minimum corner to the origin.
struct CanonicalPose {
    let angle: Double
    let shift: Point2

    init(corners: [Point2]) {
        let lengths = corners.indices.map { corners[$0].distance(to: corners[($0 + 1) % corners.count]) }
        let longest = lengths.max() ?? 0
        // Walls tied for longest would make the result depend on scan order, so
        // each one is tried and the outline that sorts first wins.
        var best: (angle: Double, shift: Point2, key: [Double])?
        for i in corners.indices where lengths[i] >= longest - 2 * PlanMath.wallAgreementTolerance {
            let d = corners[(i + 1) % corners.count] - corners[i]
            let a = -atan2(d.z, d.x)
            let turned = corners.map { $0.rotated(by: a) }
            let b = PlanMath.bounds(turned)
            let moved = turned.map { Point2($0.x - b.minX, $0.z - b.minZ) }
            let start = moved.indices.min { RoomImport.lessCorner(moved[$0], moved[$1]) } ?? 0
            let key = moved.indices.flatMap { n -> [Double] in
                let p = moved[(start + n) % moved.count]
                return [(p.z * 100).rounded(), (p.x * 100).rounded()]
            }
            if best == nil || key.lexicographicallyPrecedes(best!.key) { best = (a, Point2(-b.minX, -b.minZ), key) }
        }
        angle = best?.angle ?? 0
        shift = best?.shift ?? Point2(0, 0)
    }

    func apply(_ p: Point2) -> Point2 { p.rotated(by: angle) + shift }
}
