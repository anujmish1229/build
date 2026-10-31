import Foundation

/// Tunable solver numbers, in metres. The limits bound how hard it searches and never loosen a hard constraint.
public struct SolverConfig: Sendable {
    /// Kept between furniture and walls, and added around door and window zones (5.1).
    public var safetyMargin = 0.02
    /// The walkway a person needs (hard) and the one preferred when it can be kept (soft).
    public var walkwayMin = 0.6
    public var walkwayPreferred = 0.9
    /// An item taller than `sill + this` may not stand in a window's zone.
    public var windowHeightTolerance = 0.05
    public var windowZoneDepth = PlanGeometry.windowZoneDepth
    /// How far each fallback slide moves an item along a wall (FR-P5).
    public var slideStep = 0.1
    public var approachZoneDepth = PlanGeometry.outwardZoneDepth
    public var gridStep = 0.2
    public var besideGapSteps = 3
    public var maxWalkwayChecks = 300
    public var preferredWalkwayChecks = 8
    public var maxGridCells = 4000
    public var maxTotalWalkwayChecks = 20_000.0
    public var maxTotalCandidates = 2_000_000.0
    /// Cell size of the walkway grid.
    public var walkwayCell = 0.01
    /// The most walkway cells; a bigger room gets coarser cells.
    public var maxWalkwayCells = 1_000_000

    public init() {}

    /// Radius of the walker disc: half the walkway plus the safety margin on each side.
    func walkwayRadius(_ width: Double? = nil) -> Double { (width ?? walkwayMin) / 2 + safetyMargin }
}

enum Solver {
    /// How far a shape is shrunk to get its core, so touching items never "overlap".
    static let geomEps = 1e-5

    static func rounded(_ v: Double) -> Double { PlanMath.round6(v) }
    static func round9(_ v: Double) -> Double { (v * 1e9).rounded(.toNearestOrEven) / 1e9 }

    static func normaliseRotation(_ degrees: Double) -> Double {
        var r = degrees.truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        r = PlanMath.round6(r)
        return r >= 360 || r == 0 ? 0 : r
    }

    // MARK: Room

    struct SolverWall {
        let id: String
        let index: Int
        let start: Point2
        let end: Point2
        let length: Double
        let direction: Point2
        let normal: Point2

        /// `t` metres along the wall from its start and `offset` metres into the room.
        func point(_ t: Double, _ offset: Double = 0) -> Point2 { start + direction * t + normal * offset }
    }

    struct KeepClearZone {
        let openingID: String
        let polygon: [Point2]
        let sill: Double
    }

    struct RoomGeom {
        let valid: Bool
        let polygon: [Point2]
        /// The floor shrunk by the safety margin.
        let inner: [Point2]
        var walls: [String: SolverWall] = [:]
        var wallOrder: [String] = []
        var openings: [String: Opening] = [:]
        var doorZones: [KeepClearZone] = []
        var windowZones: [KeepClearZone] = []
        var centre = Point2(0, 0)

        /// Longest first; equal lengths keep room order.
        var wallsLongestFirst: [SolverWall] {
            wallOrder.compactMap { walls[$0] }.sorted {
                (-round9($0.length), $0.index) < (-round9($1.length), $1.index)
            }
        }
    }

    static func strip(_ wall: SolverWall, _ t0: Double, _ t1: Double, _ depth: Double) -> [Point2] {
        [wall.point(t0), wall.point(t1), wall.point(t1, depth), wall.point(t0, depth)]
    }

    static func doorZoneDepth(_ opening: Opening, _ config: SolverConfig) -> Double {
        if opening.type == .opening || (opening.swing?.isOutward ?? false) { return config.approachZoneDepth }
        return opening.width
    }

    static func roomGeometry(_ room: CanonicalRoom, _ config: SolverConfig) -> RoomGeom {
        let polygon = room.floorPolygon
        guard polygon.count >= 3, !PlanMath.isSelfIntersecting(polygon), PlanMath.signedArea(polygon) > 0 else {
            return RoomGeom(valid: false, polygon: polygon, inner: [])
        }
        var geom = RoomGeom(valid: true, polygon: polygon, inner: Shape.inset(polygon, by: config.safetyMargin))
        for (index, wall) in room.walls.enumerated() {
            let length = wall.length
            guard length >= 1e-9, geom.walls[wall.id] == nil else { continue }
            geom.walls[wall.id] = SolverWall(id: wall.id, index: index, start: wall.start, end: wall.end, length: length,
                                             direction: wall.direction, normal: wall.inwardNormal)
            geom.wallOrder.append(wall.id)
        }
        let margin = config.safetyMargin
        for opening in room.openings {
            if geom.openings[opening.id] == nil { geom.openings[opening.id] = opening }
            guard let wall = geom.walls[opening.wallID] else { continue }
            let t0 = opening.offset - margin, t1 = opening.offset + opening.width + margin
            if opening.type == .window {
                geom.windowZones.append(KeepClearZone(openingID: opening.id, polygon: strip(wall, t0, t1, config.windowZoneDepth + margin),
                                                      sill: opening.sill))
            } else {
                geom.doorZones.append(KeepClearZone(openingID: opening.id,
                                                    polygon: strip(wall, t0, t1, doorZoneDepth(opening, config) + margin),
                                                    sill: opening.sill))
            }
        }
        let c = Shape.centroid(polygon)
        geom.centre = Shape.strictlyContains(polygon, c) ? c : Shape.representativePoint(polygon)
        return geom
    }

    // MARK: Items

    /// A plan item with the dimensions the solver trusts: the catalogue's when its id is known, else its own.
    struct ItemSpec {
        let item: FurnitureItem
        let index: Int
        let width: Double
        let depth: Double
        let height: Double
        let clearance: Clearance

        var id: String { item.itemID }
        var category: String { item.category }
        var targetID: String? { item.placement.targetItemID }
    }

    static func resolve(_ item: FurnitureItem, _ catalog: FurnitureCatalog, _ index: Int) -> ItemSpec {
        let size = catalog.entry(item.catalogID)?.size ?? item.size
        func at(_ i: Int) -> Double { size.indices.contains(i) ? size[i] : 0 }
        return ItemSpec(item: item, index: index, width: at(0), depth: at(1), height: at(2), clearance: catalog.clearance(for: item))
    }

    /// One item placed relative to the other: such a pair may share clearance space.
    static func related(_ a: ItemSpec, _ b: ItemSpec) -> Bool { a.targetID == b.id || b.targetID == a.id }

    /// The rectangle [x0, x1] by [z0, z1] in an item's local frame, placed at (x, z) and `rotation`.
    static func localRect(_ x: Double, _ z: Double, _ rotation: Double, _ b: (Double, Double, Double, Double)) -> [Point2] {
        let t = rotation * .pi / 180, c = cos(t), s = sin(t)
        return [(b.0, b.2), (b.1, b.2), (b.1, b.3), (b.0, b.3)].map { lx, lz in
            Point2(x + lx * c + lz * s, z - lx * s + lz * c)
        }
    }

    /// Local bounds of each clearance zone: front (+z), back, left (+x) and right. Empty zones are left out.
    static func zoneBounds(_ width: Double, _ depth: Double, _ c: Clearance, shrink s: Double = 0)
        -> [(String, (Double, Double, Double, Double))] {
        let hw = width / 2, hd = depth / 2
        var out: [(String, (Double, Double, Double, Double))] = []
        if c.front > 2 * s { out.append(("front", (-hw + s, hw - s, hd + s, hd + c.front - s))) }
        if c.back > 2 * s { out.append(("back", (-hw + s, hw - s, -hd - c.back + s, -hd - s))) }
        if c.sides > 2 * s {
            out.append(("left", (hw + s, hw + c.sides - s, -hd + s, hd - s)))
            out.append(("right", (-hw - c.sides + s, -hw - s, -hd + s, hd - s)))
        }
        return out
    }

    /// An item at a concrete position, with every shape the constraints need.
    struct Placement {
        let spec: ItemSpec
        let x: Double
        let z: Double
        let rotation: Double
        let footprint: [Point2]
        /// The footprint shrunk by `geomEps`.
        let core: [Point2]
        let zoneCores: [[Point2]]
        /// Where a person stands to use it: all its full clearance zones.
        let access: [[Point2]]
    }

    static func makePlacement(_ spec: ItemSpec, _ x: Double, _ z: Double, _ rotation: Double) -> Placement {
        let w = spec.width, d = spec.depth, e = geomEps
        return Placement(
            spec: spec, x: x, z: z, rotation: rotation,
            footprint: localRect(x, z, rotation, (-w / 2, w / 2, -d / 2, d / 2)),
            core: localRect(x, z, rotation, (-w / 2 + e, w / 2 - e, -d / 2 + e, d / 2 - e)),
            zoneCores: zoneBounds(w, d, spec.clearance, shrink: e).map { localRect(x, z, rotation, $0.1) },
            access: zoneBounds(w, d, spec.clearance).map { localRect(x, z, rotation, $0.1) })
    }
}
