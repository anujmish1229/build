import Foundation

// Placement rules turned into candidate positions, in fallback tiers.
// - against_wall, corner, under_window: the requested spot; slides along the same wall, nearest first;
//   each other wall, longest first; then turned side-on (never for wall units).
// - centered_in_room: the room centre at four rotations; then a grid around it, nearest first.
// - in_front_of: centred in front of the target, `gap` away, facing it; then slides across it.
// - beside: next to the target's own left (+x) or right side, backs flush; then a little further away.
//   For the second of two same-category items either side of a target, both form one tier (symmetry).

extension Solver {
    /// Wall units: turning them side-on to the wall isn't a meaningful fallback.
    static let noRotatedFallback: Set<String> = ["tv_stand", "wardrobe", "bookshelf", "dresser", "storage"]

    struct RuleError: Error { let reason: String }

    struct Candidate {
        let x: Double
        let z: Double
        let rotation: Double
        /// Where this tier ideally wants the item; closeness to it is scored.
        let anchor: Point2
    }

    struct Tier {
        let name: String
        let candidates: [Candidate]
    }

    struct SearchPlan {
        let tiers: [Tier]
        var requestedWall: SolverWall?
    }

    static func candidate(_ p: Point2, _ rotation: Double, _ anchor: Point2) -> Candidate {
        Candidate(x: rounded(p.x), z: rounded(p.z), rotation: normaliseRotation(rotation), anchor: anchor)
    }

    // MARK: Wall rules

    enum WallMode { case backToWall, frontToEnd, frontToStart }

    struct WallFit {
        let rotation: Double
        /// The item centre's distance from the wall line.
        let offset: Double
        let halfAlong: Double
        let clearStart: Double
        let clearEnd: Double
    }

    static func wallFit(_ wall: SolverWall, _ spec: ItemSpec, _ mode: WallMode, _ margin: Double) -> WallFit {
        let c = spec.clearance
        switch mode {
        case .backToWall:
            return WallFit(rotation: PlanMath.rotationFacing(wall.normal), offset: margin + c.back + spec.depth / 2,
                           halfAlong: spec.width / 2, clearStart: c.sides, clearEnd: c.sides)
        case .frontToEnd:
            return WallFit(rotation: PlanMath.rotationFacing(wall.direction), offset: margin + c.sides + spec.width / 2,
                           halfAlong: spec.depth / 2, clearStart: c.back, clearEnd: c.front)
        case .frontToStart:
            return WallFit(rotation: PlanMath.rotationFacing(wall.direction * -1), offset: margin + c.sides + spec.width / 2,
                           halfAlong: spec.depth / 2, clearStart: c.front, clearEnd: c.back)
        }
    }

    /// Centres that keep the item within the wall's span. One longer than the wall gets the centre only.
    static func tRange(_ wall: SolverWall, _ fit: WallFit) -> (Double, Double) {
        let lo = fit.halfAlong, hi = wall.length - fit.halfAlong
        return lo > hi ? (wall.length / 2, wall.length / 2) : (lo, hi)
    }

    static func alignT(_ wall: SolverWall, _ fit: WallFit, _ align: String, _ margin: Double) -> Double {
        let t: Double
        switch align {
        case "start": t = margin + fit.clearStart + fit.halfAlong
        case "end": t = wall.length - margin - fit.clearEnd - fit.halfAlong
        default: t = wall.length / 2
        }
        let (lo, hi) = tRange(wall, fit)
        return min(max(t, lo), hi)
    }

    /// Fallback spots along the wall: steps either side of t0, plus the exact end-aligned spots. Nearest first, t0 excluded.
    static func slideTs(_ wall: SolverWall, _ fit: WallFit, _ t0: Double, _ margin: Double, _ step: Double) -> [Double] {
        let (lo, hi) = tRange(wall, fit)
        var ts = [lo, hi, margin + fit.halfAlong, wall.length - margin - fit.halfAlong,
                  margin + fit.clearStart + fit.halfAlong, wall.length - margin - fit.clearEnd - fit.halfAlong]
        let kMax = Int(((hi - lo) / step).rounded(.up)) + 1
        if kMax >= 1 { for k in 1...kMax { ts += [t0 + Double(k) * step, t0 - Double(k) * step] } }
        var seen = Set<Double>()
        var order: [Double] = []
        for t in ts where t >= lo - 1e-9 && t <= hi + 1e-9 {
            let key = PlanMath.round6(t)
            if key != PlanMath.round6(t0), seen.insert(key).inserted { order.append(t) }
        }
        return order.sorted { (round9(abs($0 - t0)), $0) < (round9(abs($1 - t0)), $1) }
    }

    static func alongWall(_ wall: SolverWall, _ fit: WallFit, _ t0: Double, _ config: SolverConfig, includeT0: Bool,
                          includeSlides: Bool) -> [Candidate] {
        let anchor = wall.point(t0, fit.offset)
        let ts = (includeT0 ? [t0] : []) + (includeSlides ? slideTs(wall, fit, t0, config.safetyMargin, config.slideStep) : [])
        return ts.map { candidate(wall.point($0, fit.offset), fit.rotation, anchor) }
    }

    static func wallRuleTiers(_ spec: ItemSpec, _ geom: RoomGeom, _ wall: SolverWall, _ align: String, _ config: SolverConfig,
                              tRequested: Double? = nil) -> [Tier] {
        let margin = config.safetyMargin
        let fit = wallFit(wall, spec, .backToWall, margin)
        let t0 = tRequested ?? alignT(wall, fit, align, margin)
        var tiers = [
            Tier(name: "requested position", candidates: alongWall(wall, fit, t0, config, includeT0: true, includeSlides: false)),
            Tier(name: "slid along \(wall.id)", candidates: alongWall(wall, fit, t0, config, includeT0: false, includeSlides: true)),
        ]
        let others = geom.wallsLongestFirst.filter { $0.id != wall.id }
        for other in others {
            let ofit = wallFit(other, spec, .backToWall, margin)
            tiers.append(Tier(name: "against \(other.id)",
                              candidates: alongWall(other, ofit, alignT(other, ofit, align, margin), config, includeT0: true, includeSlides: true)))
        }
        if !noRotatedFallback.contains(spec.category) {
            for w in [wall] + others {
                var cands: [Candidate] = []
                for mode in [WallMode.frontToEnd, .frontToStart] {
                    let rfit = wallFit(w, spec, mode, margin)
                    let t: Double
                    if w.id == wall.id, let tRequested {
                        let (lo, hi) = tRange(w, rfit)
                        t = min(max(tRequested, lo), hi)
                    } else {
                        t = alignT(w, rfit, align, margin)
                    }
                    cands += alongWall(w, rfit, t, config, includeT0: true, includeSlides: true)
                }
                tiers.append(Tier(name: "turned sideways on \(w.id)", candidates: cands))
            }
        }
        return tiers
    }

    // MARK: Room-centred rule

    /// Four right-angle rotations, starting with the one facing away from the longest wall.
    static func roomRotations(_ geom: RoomGeom) -> [Double] {
        let base = geom.wallsLongestFirst.first.map { PlanMath.rotationFacing($0.normal) } ?? 0
        var out: [Double] = []
        for k in 0..<4 {
            let r = normaliseRotation(base + 90 * Double(k))
            if !out.contains(r) { out.append(r) }
        }
        return out
    }

    static func gridRanges(_ lo: Point2, _ hi: Point2, _ centre: Point2, _ g: Double) -> (ClosedRange<Int>?, ClosedRange<Int>?) {
        let i0 = Int(((lo.x - centre.x) / g - 1e-9).rounded(.up)), i1 = Int(((hi.x - centre.x) / g + 1e-9).rounded(.down))
        let j0 = Int(((lo.z - centre.z) / g - 1e-9).rounded(.up)), j1 = Int(((hi.z - centre.z) / g + 1e-9).rounded(.down))
        return (i0 <= i1 ? i0...i1 : nil, j0 <= j1 ? j0...j1 : nil)
    }

    /// The configured grid step, coarsened until the grid has at most `maxGridCells` points.
    static func gridStep(_ lo: Point2, _ hi: Point2, _ centre: Point2, _ config: SolverConfig) -> Double {
        var g = max(config.gridStep, (max((hi.x - lo.x) * (hi.z - lo.z), 0) / Double(config.maxGridCells)).squareRoot())
        while true {
            let (ri, rj) = gridRanges(lo, hi, centre, g)
            if (ri?.count ?? 0) * (rj?.count ?? 0) <= config.maxGridCells { return g }
            g *= 1.05
        }
    }

    static func centredTiers(_ geom: RoomGeom, _ config: SolverConfig) -> [Tier] {
        let c = geom.centre
        let rotations = roomRotations(geom)
        let first = rotations.map { candidate(c, $0, c) }
        let (lo, hi) = geom.inner.isEmpty ? (c, c) : Shape.bounds(geom.inner)
        let g = gridStep(lo, hi, c, config)
        let (ri, rj) = gridRanges(lo, hi, c, g)
        var cells: [(Int, Int)] = []
        if let ri, let rj {
            for i in ri { for j in rj where (i, j) != (0, 0) { cells.append((i, j)) } }
        }
        cells.sort { ($0.0 * $0.0 + $0.1 * $0.1, $0.0, $0.1) < ($1.0 * $1.0 + $1.1 * $1.1, $1.0, $1.1) }
        cells = cells.filter { Shape.strictlyContains(geom.inner, Point2(c.x + Double($0.0) * g, c.z + Double($0.1) * g)) }
        let grid = cells.flatMap { i, j in rotations.map { candidate(Point2(c.x + Double(i) * g, c.z + Double(j) * g), $0, c) } }
        return [Tier(name: "room centre", candidates: first), Tier(name: "near the room centre", candidates: grid)]
    }

    // MARK: Rules relative to another item

    static func inFrontTiers(_ spec: ItemSpec, _ target: Placement, gap: Double, _ config: SolverConfig) -> [Tier] {
        let f = PlanMath.front(degrees: target.rotation)
        let l = PlanMath.rotate(Point2(1, 0), degrees: target.rotation)
        let along = target.spec.depth / 2 + gap + spec.depth / 2
        let base = Point2(target.x, target.z) + f * along
        let rotation = target.rotation + 180
        var slides: [Candidate] = []
        let kMax = Int((target.spec.width / 2 / config.slideStep + 1e-9).rounded(.down))
        if kMax >= 1 {
            for k in 1...kMax {
                for sign in [1.0, -1.0] { slides.append(candidate(base + l * (sign * Double(k) * config.slideStep), rotation, base)) }
            }
        }
        return [Tier(name: "in front of target", candidates: [candidate(base, rotation, base)]),
                Tier(name: "slid across target", candidates: slides)]
    }

    /// Placed items of the same category beside the same target on its other side.
    static func mirrorPartners(_ spec: ItemSpec, _ placed: [String: Placement], order: [String]) -> [Placement] {
        guard case let .beside(target, side, _) = spec.item.placement else { return [] }
        return order.compactMap { placed[$0] }.filter {
            if case let .beside(otherTarget, otherSide, _) = $0.spec.item.placement {
                return otherTarget == target && otherSide != side && $0.spec.category == spec.category
            }
            return false
        }
    }

    static func besideTiers(_ spec: ItemSpec, _ target: Placement, side: String, gap: Double, _ config: SolverConfig,
                            mirrored: Bool) -> [Tier] {
        let l = PlanMath.rotate(Point2(side == "left" ? 1 : -1, 0), degrees: target.rotation)
        let f = PlanMath.front(degrees: target.rotation)
        let back = -target.spec.depth / 2 + spec.depth / 2
        func at(_ g: Double) -> Point2 {
            Point2(target.x, target.z) + l * (target.spec.width / 2 + g + spec.width / 2) + f * back
        }
        let anchor = at(gap)
        let exact = candidate(anchor, target.rotation, anchor)
        let extra = config.besideGapSteps < 1 ? []
            : (1...config.besideGapSteps).map { candidate(at(gap + Double($0) * config.slideStep), target.rotation, anchor) }
        if mirrored { return [Tier(name: "beside target, matching the item on its other side", candidates: [exact] + extra)] }
        return [Tier(name: "beside target", candidates: [exact]), Tier(name: "further from target", candidates: extra)]
    }

    /// All candidate tiers for one item, in fallback order. Throws when the rule names something
    /// that doesn't exist or a target that wasn't placed.
    static func generateTiers(_ spec: ItemSpec, _ geom: RoomGeom, _ placed: [String: Placement], placedOrder: [String],
                              _ config: SolverConfig, cache: inout [Tier]?) throws -> SearchPlan {
        switch spec.item.placement {
        case let .againstWall(wallID, align), let .corner(wallID, align):
            guard let wall = geom.walls[wallID] else { throw RuleError(reason: "unknown wall \(wallID)") }
            return SearchPlan(tiers: wallRuleTiers(spec, geom, wall, align, config), requestedWall: wall)
        case let .underWindow(openingID):
            guard let opening = geom.openings[openingID] else { throw RuleError(reason: "unknown window \(openingID)") }
            guard opening.type == .window else { throw RuleError(reason: "\(openingID) is a \(opening.type.plainName), not a window") }
            guard let wall = geom.walls[opening.wallID] else {
                throw RuleError(reason: "window \(openingID) is on unknown wall \(opening.wallID)")
            }
            let fit = wallFit(wall, spec, .backToWall, config.safetyMargin)
            let (lo, hi) = tRange(wall, fit)
            let t = min(max(opening.offset + opening.width / 2, lo), hi)
            return SearchPlan(tiers: wallRuleTiers(spec, geom, wall, "center", config, tRequested: t), requestedWall: wall)
        case .centeredInRoom:
            if cache == nil { cache = centredTiers(geom, config) }
            return SearchPlan(tiers: cache!)
        case let .inFrontOf(targetID, gap):
            guard let target = placed[targetID] else { throw RuleError(reason: "target \(targetID) could not be placed") }
            return SearchPlan(tiers: inFrontTiers(spec, target, gap: gap, config))
        case let .beside(targetID, side, gap):
            guard let target = placed[targetID] else { throw RuleError(reason: "target \(targetID) could not be placed") }
            let mirrored = !mirrorPartners(spec, placed, order: placedOrder).isEmpty
            return SearchPlan(tiers: besideTiers(spec, target, side: side, gap: gap, config, mirrored: mirrored))
        }
    }

    // MARK: Scoring

    struct PairPreference {
        let minGap: Double
        let maxGap: Double
        var facing = false
    }

    static func pairPreference(_ a: String, _ b: String) -> PairPreference? {
        let key = a <= b ? "\(a)|\(b)" : "\(b)|\(a)"
        switch key {
        case "bed|nightstand": return PairPreference(minGap: 0, maxGap: 0.3)
        case "sofa|tv_stand": return PairPreference(minGap: 1.5, maxGap: 3.5, facing: true)
        case "chair|desk": return PairPreference(minGap: 0, maxGap: 0.6)
        case "coffee_table|sofa": return PairPreference(minGap: 0.3, maxGap: 0.8)
        default: return nil
        }
    }

    /// A penalty sum in metres, higher is better: distance to the tier's anchor, a quarter of the distance
    /// to the requested wall, functional-pair gaps and facing, and symmetry across a target.
    static func score(_ spec: ItemSpec, _ c: Candidate, _ placed: [String: Placement], placedOrder: [String],
                      requestedWall: SolverWall?) -> Double {
        var score = -Point2(c.x - c.anchor.x, c.z - c.anchor.z).length
        let p = Point2(c.x, c.z)
        if let wall = requestedWall {
            let t = min(max((p - wall.start).dot(wall.direction), 0), wall.length)
            score -= 0.25 * p.distance(to: wall.start + wall.direction * t)
        }
        let partners = placedOrder.compactMap { placed[$0] }.compactMap { other in
            pairPreference(spec.category, other.spec.category).map { (other, $0) }
        }
        if !partners.isEmpty {
            let rect = localRect(c.x, c.z, c.rotation, (-spec.width / 2, spec.width / 2, -spec.depth / 2, spec.depth / 2))
            let f = PlanMath.front(degrees: c.rotation)
            for (partner, pref) in partners {
                let gap = Shape.distance(partner.footprint, rect)
                score -= 0.5 * (max(0, pref.minGap - gap) + max(0, gap - pref.maxGap))
                if pref.facing {
                    let v = Point2(partner.x - c.x, partner.z - c.z)
                    score -= 0.5 * (1 - f.dot(v) / max(v.length, 1e-9)) / 2
                }
            }
        }
        if case let .beside(targetID, _, _) = spec.item.placement, let target = placed[targetID] {
            for other in mirrorPartners(spec, placed, order: placedOrder) {
                let mirror = Point2(other.x - target.x, other.z - target.z).length
                score -= 2 * abs(Point2(c.x - target.x, c.z - target.z).length - mirror)
            }
        }
        return score
    }
}
