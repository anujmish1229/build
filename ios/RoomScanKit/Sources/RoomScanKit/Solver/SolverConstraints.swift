import Foundation

// Hard constraints (FR-P3) and the layout checker.
//
// 1. inside: the footprint lies inside the floor shrunk by the safety margin.
// 2. overlap: it doesn't overlap another footprint.
// 3. blocks_clearance / clearance: it doesn't stand in another item's clearance zones, and its own zones
//    stay inside the room and off other footprints. A pair placed relative to each other is exempt.
// 4. door: it stays off every door keep-clear zone.
// 5. window: an item taller than the sill plus tolerance stays off the window zone.
// 6. walkway: the free floor, where a walker disc of radius walkwayMin / 2 + safetyMargin fits, has one
//    connected piece that reaches every door zone and every item's access space.
//
// Shapes are compared by their cores, so touching never counts as overlapping. The walkway is
// tested on a grid of walker positions; everything else is exact.

extension Solver {
    static let inside = "inside"
    static let overlap = "overlap"
    static let door = "door"
    static let window = "window"
    static let blocksClearance = "blocks_clearance"
    static let clearance = "clearance"
    static let walkway = "walkway"

    /// The cheap constraints, in the order used to break ties when choosing an unplaced reason.
    static let cheapConstraints = [inside, door, window, overlap, blocksClearance, clearance]

    static let reasons: [String: String] = [
        inside: "does not fit inside the room",
        overlap: "overlaps other furniture",
        door: "blocks a door",
        window: "blocks a window",
        blocksClearance: "would block the space needed to use other furniture",
        clearance: "not enough clear space around it to use it",
        walkway: "no position satisfies walkway clearance",
    ]

    static func isTall(_ height: Double, _ zone: KeepClearZone, _ config: SolverConfig) -> Bool {
        height > zone.sill + config.windowHeightTolerance
    }

    /// Which cheap constraints placement `p` breaks against the room and `others`.
    static func failedConstraints(_ geom: RoomGeom, _ p: Placement, _ others: [Placement], _ config: SolverConfig) -> Set<String> {
        var out = Set<String>()
        if !Shape.covers(geom.inner, p.core) { out.insert(inside) }
        if geom.doorZones.contains(where: { Shape.intersects(p.core, $0.polygon) }) { out.insert(door) }
        if geom.windowZones.contains(where: { isTall(p.spec.height, $0, config) && Shape.intersects(p.core, $0.polygon) }) {
            out.insert(window)
        }
        if p.zoneCores.contains(where: { !Shape.covers(geom.inner, $0) }) { out.insert(clearance) }
        for other in others {
            if !out.contains(overlap), Shape.intersects(p.core, other.core) { out.insert(overlap) }
            if related(p.spec, other.spec) { continue }
            if !out.contains(blocksClearance), other.zoneCores.contains(where: { Shape.intersects(p.core, $0) }) {
                out.insert(blocksClearance)
            }
            if !out.contains(clearance), p.zoneCores.contains(where: { Shape.intersects($0, other.core) }) { out.insert(clearance) }
        }
        return out
    }

    /// Every constraint and message that `p` breaks, for the checker.
    static func itemFailures(_ geom: RoomGeom, _ p: Placement, _ others: [Placement], _ config: SolverConfig) -> [(String, String)] {
        let name = p.spec.item.name.isEmpty ? p.spec.id : p.spec.item.name
        var out: [(String, String)] = []
        if !Shape.covers(geom.inner, p.core) {
            out.append((inside, "\(name) sticks out of the room or comes closer to a wall than the safety margin"))
        }
        for zone in geom.doorZones where Shape.intersects(p.core, zone.polygon) {
            out.append((door, "\(name) stands in the space that must stay clear at \(zone.openingID)"))
        }
        for zone in geom.windowZones where isTall(p.spec.height, zone, config) && Shape.intersects(p.core, zone.polygon) {
            out.append((window, "\(name) is \(String(format: "%.2f", p.spec.height)) m tall and stands in front of window \(zone.openingID)"))
        }
        if p.zoneCores.contains(where: { !Shape.covers(geom.inner, $0) }) {
            out.append((clearance, "the space needed to use \(name) runs into a wall"))
        }
        for other in others {
            let otherName = other.spec.item.name.isEmpty ? other.spec.id : other.spec.item.name
            if Shape.intersects(p.core, other.core) { out.append((overlap, "\(name) overlaps \(otherName)")) }
            if related(p.spec, other.spec) { continue }
            if other.zoneCores.contains(where: { Shape.intersects(p.core, $0) }) {
                out.append((blocksClearance, "\(name) stands in the space needed to use \(otherName)"))
            }
            if p.zoneCores.contains(where: { Shape.intersects($0, other.core) }) {
                out.append((clearance, "\(otherName) stands in the space needed to use \(name)"))
            }
        }
        return out
    }

    // MARK: Walkway

    /// Something a person must be able to walk to: a door zone or an item's access space.
    struct WalkwayTarget {
        let itemID: String?
        let openingID: String?
        let shapes: [[Point2]]
    }

    /// Walker positions on a grid over the room. A cell is free when a walker disc fits somewhere in it,
    /// so a passage just wide enough isn't missed because its free strip is thinner than a cell.
    final class Walkway {
        let origin: Point2
        let cell: Double
        let nx: Int
        let nz: Int
        private let wallDistance: [Double]
        private var baseMasks: [Double: [Bool]] = [:]

        init(_ geom: RoomGeom, _ config: SolverConfig) {
            let (lo, hi) = Shape.bounds(geom.polygon)
            let width = hi.x - lo.x, depth = hi.z - lo.z
            cell = max(config.walkwayCell, (width * depth / Double(config.maxWalkwayCells)).squareRoot())
            origin = lo
            nx = max(1, Int((width / cell).rounded(.up)))
            nz = max(1, Int((depth / cell).rounded(.up)))
            var distances = Array(repeating: -1.0, count: nx * nz)
            for j in 0..<nz {
                for i in 0..<nx {
                    let c = Point2(lo.x + (Double(i) + 0.5) * cell, lo.z + (Double(j) + 0.5) * cell)
                    if Shape.contains(geom.polygon, c) { distances[j * nx + i] = Shape.edgeDistance(c, geom.polygon) }
                }
            }
            wallDistance = distances
        }

        func centre(_ i: Int, _ j: Int) -> Point2 {
            Point2(origin.x + (Double(i) + 0.5) * cell, origin.z + (Double(j) + 0.5) * cell)
        }

        /// Cells whose walker disc fits in the empty room.
        func baseMask(_ radius: Double) -> [Bool] {
            if let mask = baseMasks[radius] { return mask }
            let mask = wallDistance.map { $0 >= radius - cell / 2 }
            baseMasks[radius] = mask
            return mask
        }

        /// Index ranges of cells within `reach` of a shape's bounding box.
        func range(around shape: [Point2], reach: Double) -> (ClosedRange<Int>, ClosedRange<Int>)? {
            let (lo, hi) = Shape.bounds(shape)
            let i0 = max(0, Int(((lo.x - reach - origin.x) / cell).rounded(.down)))
            let i1 = min(nx - 1, Int(((hi.x + reach - origin.x) / cell).rounded(.down)))
            let j0 = max(0, Int(((lo.z - reach - origin.z) / cell).rounded(.down)))
            let j1 = min(nz - 1, Int(((hi.z + reach - origin.z) / cell).rounded(.down)))
            guard i0 <= i1, j0 <= j1 else { return nil }
            return (i0...i1, j0...j1)
        }

        /// Connected free pieces once `blockers` stand in the room: a label per cell (-1 is not free) and each piece's size.
        func components(blockers: [[Point2]], radius: Double) -> (labels: [Int32], sizes: [Int]) {
            var free = baseMask(radius)
            for shape in blockers {
                guard let (ri, rj) = range(around: shape, reach: radius) else { continue }
                for j in rj {
                    for i in ri where free[j * nx + i] {
                        if Shape.distance(centre(i, j), toConvex: shape) < radius - cell / 2 { free[j * nx + i] = false }
                    }
                }
            }
            var labels = Array(repeating: Int32(-1), count: nx * nz)
            var sizes: [Int] = []
            var stack: [Int] = []
            for start in free.indices where free[start] && labels[start] < 0 {
                let label = Int32(sizes.count)
                var size = 0
                labels[start] = label
                stack.append(start)
                while let k = stack.popLast() {
                    size += 1
                    let i = k % nx, j = k / nx
                    for dj in -1...1 {
                        for di in -1...1 where di != 0 || dj != 0 {
                            let ii = i + di, jj = j + dj
                            guard ii >= 0, ii < nx, jj >= 0, jj < nz else { continue }
                            let n = jj * nx + ii
                            if free[n] && labels[n] < 0 {
                                labels[n] = label
                                stack.append(n)
                            }
                        }
                    }
                }
                sizes.append(size)
            }
            return (labels, sizes)
        }

        /// The pieces from which a walker's disc overlaps `shapes`.
        func piecesReaching(_ shapes: [[Point2]], labels: [Int32], radius: Double) -> Set<Int32> {
            let reach = radius - Solver.geomEps + cell / 2
            var out = Set<Int32>()
            for shape in shapes {
                guard let (ri, rj) = range(around: shape, reach: reach) else { continue }
                for j in rj {
                    for i in ri {
                        let label = labels[j * nx + i]
                        if label >= 0, !out.contains(label), Shape.distance(centre(i, j), toConvex: shape) < reach { out.insert(label) }
                    }
                }
            }
            return out
        }
    }

    /// The door zones the walkway must serve: those reachable in the empty room through its
    /// best-connected piece. Normally every door.
    static func requiredDoorZones(_ geom: RoomGeom, _ walkway: Walkway, _ radius: Double) -> [KeepClearZone] {
        let (labels, sizes) = walkway.components(blockers: [], radius: radius)
        let reached = geom.doorZones.map { walkway.piecesReaching([$0.polygon], labels: labels, radius: radius) }
        var best: [KeepClearZone] = []
        var bestKey = (-1, -1)
        for label in sizes.indices {
            let doors = geom.doorZones.indices.filter { reached[$0].contains(Int32(label)) }.map { geom.doorZones[$0] }
            if doors.count > bestKey.0 || (doors.count == bestKey.0 && sizes[label] > bestKey.1) {
                best = doors
                bestKey = (doors.count, sizes[label])
            }
        }
        return best
    }

    /// Targets the best single walkway piece fails to reach. With `primaryOnly`, only doors and items
    /// placed by their own rule are targets.
    static func walkwayUnreached(_ geom: RoomGeom, _ walkway: Walkway, _ placements: [Placement], _ doors: [KeepClearZone],
                                 _ radius: Double, primaryOnly: Bool = false) -> [WalkwayTarget] {
        let ordered = placements.sorted { $0.spec.id < $1.spec.id }
        var targets = doors.map { WalkwayTarget(itemID: nil, openingID: $0.openingID, shapes: [$0.polygon]) }
        targets += ordered.filter { !$0.access.isEmpty && !(primaryOnly && $0.spec.targetID != nil) }
            .map { WalkwayTarget(itemID: $0.spec.id, openingID: nil, shapes: $0.access) }
        guard !targets.isEmpty else { return [] }
        let (labels, sizes) = walkway.components(blockers: ordered.map(\.footprint), radius: radius)
        let reached = targets.map { walkway.piecesReaching($0.shapes, labels: labels, radius: radius) }
        var best = targets
        for label in sizes.indices {
            let missing = targets.indices.filter { !reached[$0].contains(Int32(label)) }
            if missing.count < best.count { best = missing.map { targets[$0] } }
            if best.isEmpty { break }
        }
        return best
    }

    // MARK: Checker

    /// Re-checks every hard constraint on a finished layout. Empty means valid.
    static func checkLayout(_ room: CanonicalRoom, _ layout: FurnitureLayout, _ plan: FurniturePlan,
                            _ catalog: FurnitureCatalog, _ config: SolverConfig = SolverConfig()) -> [LayoutViolation] {
        let geom = roomGeometry(room, config)
        guard geom.valid else {
            return layout.placed.isEmpty ? [] : [LayoutViolation(itemID: nil, constraint: "room",
                                                                 message: "the room outline is not valid, so nothing can be placed")]
        }
        var specs: [String: ItemSpec] = [:]
        for (index, item) in plan.items.enumerated() where specs[item.itemID] == nil {
            specs[item.itemID] = resolve(item, catalog, index)
        }
        var violations: [LayoutViolation] = []
        var placements: [Placement] = []
        var seen = Set<String>()
        for placed in layout.placed {
            guard seen.insert(placed.itemID).inserted else {
                violations.append(LayoutViolation(itemID: placed.itemID, constraint: "duplicate",
                                                  message: "\(placed.itemID) is placed more than once"))
                continue
            }
            guard let spec = specs[placed.itemID] else {
                violations.append(LayoutViolation(itemID: placed.itemID, constraint: "unknown_item",
                                                  message: "\(placed.itemID) is not in the furniture plan"))
                continue
            }
            let width = placed.footprint.first ?? 0, depth = placed.footprint.count > 1 ? placed.footprint[1] : 0
            if abs(width - spec.width) > 1e-6 || abs(depth - spec.depth) > 1e-6 {
                violations.append(LayoutViolation(
                    itemID: spec.id, constraint: "size",
                    message: "\(spec.id) is laid out as \(String(format: "%.2f", width)) x \(String(format: "%.2f", depth)) m "
                        + "but measures \(String(format: "%.2f", spec.width)) x \(String(format: "%.2f", spec.depth)) m"))
            }
            placements.append(makePlacement(spec, placed.x, placed.z, placed.rotation))
        }
        for (i, p) in placements.enumerated() {
            for (constraint, message) in itemFailures(geom, p, Array(placements[..<i]), config) {
                violations.append(LayoutViolation(itemID: p.spec.id, constraint: constraint, message: message))
            }
        }
        let grid = Walkway(geom, config)
        let radius = config.walkwayRadius()
        let doors = requiredDoorZones(geom, grid, radius)
        let width = String(format: "%.2f", config.walkwayMin)
        for target in walkwayUnreached(geom, grid, placements, doors, radius) {
            let message = target.itemID == nil
                ? "no walkway at least \(width) m wide reaches \(target.openingID ?? "")"
                : "no walkway at least \(width) m wide reaches the space in front of or around \(target.itemID ?? "")"
            violations.append(LayoutViolation(itemID: target.itemID, constraint: walkway, message: message))
        }
        return violations
    }
}
