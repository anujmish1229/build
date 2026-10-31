import Foundation

/// The placement solver (FR-P1 to FR-P7): plan, room and catalogue to layout.
///
///     for item in items by priority (targets first):
///         for tier in rule tiers (requested spot, slides, other walls, turned):
///             candidates passing constraints 1 to 5, best soft score first:
///                 then the walkway; prefer one that also keeps the 0.9 m walkway
///             the first tier with a valid candidate wins
///         else: unplaced, with a plain-English reason
///
/// Deterministic: candidates come in a fixed order and score ties keep it (seed 0), or are broken by
/// a seeded generator. The work is bounded by a budget that counts work, not seconds.
public enum LayoutSolver {
    static let invalidRoomReason = "the room outline is not valid"
    static let budgetReason = "not tried: the plan has more furniture than can be checked in one go; "
        + "remove some lower-priority items and try again"

    final class Budget {
        let maxWalkwayChecks: Double
        let maxCandidates: Double
        var walkwayChecks = 0.0
        var candidates = 0.0

        init(_ config: SolverConfig) {
            maxWalkwayChecks = config.maxTotalWalkwayChecks
            maxCandidates = config.maxTotalCandidates
        }

        func chargeWalkway(_ placedCount: Int) { walkwayChecks += 1 + Double(placedCount) / 20 }
        var spent: Bool { walkwayChecks >= maxWalkwayChecks || candidates >= maxCandidates }
    }

    /// A seeded generator for tie-breaks (SplitMix64), so a non-zero seed still gives the same layout every time.
    struct SeededRandom {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }

    /// Everything a search depends on besides the room and what is placed: two items with the same
    /// key, searched with nothing placed in between, get the same outcome.
    private static func failureKey(_ spec: Solver.ItemSpec) -> String {
        let c = spec.clearance
        let rule = (try? JSONEncoder().encode(spec.item.placement)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return "\(spec.category)|\(spec.width)|\(spec.depth)|\(spec.height)|\(c.front)|\(c.sides)|\(c.back)|\(rule)"
    }

    /// Plan indices in solving order (priority, then plan order; a target always before its
    /// dependants), plus the items that can't be attempted at all, with reasons.
    static func processingOrder(_ specs: [Solver.ItemSpec]) -> ([Int], [Int: String]) {
        var first: [String: Int] = [:]
        var early: [Int: String] = [:]
        for (i, spec) in specs.enumerated() {
            if first[spec.id] != nil { early[i] = "duplicate item id \(spec.id)" } else { first[spec.id] = i }
        }
        var order: [Int] = []
        var state: [Int: Bool] = [:] // false is active, true is done.
        func visit(_ i: Int) {
            if state[i] != nil { return }
            state[i] = false
            if let target = specs[i].targetID, early[i] == nil {
                if target == specs[i].id {
                    early[i] = "\(target) is placed relative to itself"
                } else if let t = first[target] {
                    if state[t] == false {
                        early[i] = "circular placement: \(specs[i].id) and \(target) are placed relative to each other"
                    } else {
                        visit(t)
                    }
                } else {
                    early[i] = "unknown target item \(target)"
                }
            }
            state[i] = true
            order.append(i)
        }
        for i in specs.indices.sorted(by: { (specs[$0].item.priority, $0) < (specs[$1].item.priority, $1) }) { visit(i) }
        return (order, early)
    }

    /// The reason, from the constraint that actually stood in the way (7.4).
    static func unplacedReason(_ counts: [String: Int], fitsRoom: Bool, passedCheap: Bool, _ spec: Solver.ItemSpec) -> String {
        if passedCheap { return Solver.reasons[Solver.walkway]! }
        if !fitsRoom {
            switch spec.item.placement {
            case let .inFrontOf(target, _): return "no room in front of \(target)"
            case let .beside(target, side, _): return "no room on the \(side) of \(target)"
            default: return Solver.reasons[Solver.inside]!
            }
        }
        let others = Solver.cheapConstraints.filter { $0 != Solver.inside }
        var best = others[0]
        for c in others.dropFirst() where counts[c, default: 0] > counts[best, default: 0] { best = c }
        return Solver.reasons[best]!
    }

    private enum Outcome {
        case placed(Solver.Placement)
        case unplaced(String)
    }

    private static func search(_ spec: Solver.ItemSpec, _ plan: Solver.SearchPlan, _ geom: Solver.RoomGeom,
                               _ walkway: Solver.Walkway, _ placed: [String: Solver.Placement], _ placedOrder: [String],
                               _ config: SolverConfig, doors: [Solver.KeepClearZone], preferredDoors: [Solver.KeepClearZone],
                               rng: inout SeededRandom?, budget: Budget) -> Outcome {
        let others = placedOrder.compactMap { placed[$0] }
        let radius = config.walkwayRadius(), preferredRadius = config.walkwayRadius(config.walkwayPreferred)
        var counts: [String: Int] = [:]
        var fitsRoom = false, passedCheap = false
        var walkwayChecks = 0

        for tier in plan.tiers where !tier.candidates.isEmpty {
            if budget.spent { return .unplaced(budgetReason) }
            budget.candidates += Double(tier.candidates.count) * (1 + Double(others.count) / 40)
            var ok: [(candidate: Solver.Candidate, placement: Solver.Placement)] = []
            for c in tier.candidates {
                let placement = Solver.makePlacement(spec, c.x, c.z, c.rotation)
                let failed = Solver.failedConstraints(geom, placement, others, config)
                if failed.contains(Solver.inside) { continue }
                fitsRoom = true
                for constraint in failed { counts[constraint, default: 0] += 1 }
                if failed.isEmpty { ok.append((c, placement)) }
            }
            if ok.isEmpty { continue }
            passedCheap = true

            let scores = ok.map { Solver.round9(Solver.score(spec, $0.candidate, placed, placedOrder: placedOrder,
                                                             requestedWall: plan.requestedWall)) }
            let ties: [Double] = rng == nil ? ok.indices.map(Double.init) : ok.indices.map { _ in rng!.next() }
            let ranked = ok.indices.sorted { (-scores[$0], ties[$0]) < (-scores[$1], ties[$1]) }

            var valid: [Solver.Placement] = []
            var chosen: Solver.Placement?
            for k in ranked {
                if walkwayChecks >= config.maxWalkwayChecks || budget.walkwayChecks >= budget.maxWalkwayChecks { break }
                let placement = ok[k].placement
                walkwayChecks += 1
                budget.chargeWalkway(others.count)
                let trial = others + [placement]
                if !Solver.walkwayUnreached(geom, walkway, trial, doors, radius).isEmpty {
                    counts[Solver.walkway, default: 0] += 1
                    continue
                }
                valid.append(placement)
                budget.chargeWalkway(others.count)
                if Solver.walkwayUnreached(geom, walkway, trial, preferredDoors, preferredRadius, primaryOnly: true).isEmpty {
                    chosen = placement
                    break
                }
                if valid.count >= config.preferredWalkwayChecks { break }
            }
            if let best = chosen ?? valid.first { return .placed(best) }
            if walkwayChecks >= config.maxWalkwayChecks { break }
            if budget.spent { return .unplaced(budgetReason) }
        }
        return .unplaced(unplacedReason(counts, fitsRoom: fitsRoom, passedCheap: passedCheap, spec))
    }

    /// Places the plan's items in the room. Every placed item satisfies all hard constraints, and each
    /// item that can't be placed is listed with a plain-English reason. Lists follow plan order.
    public static func solve(_ room: CanonicalRoom, _ plan: FurniturePlan, catalog: FurnitureCatalog = .current,
                             config: SolverConfig = SolverConfig(), seed: UInt64 = 0) -> FurnitureLayout {
        let geom = Solver.roomGeometry(room, config)
        let specs = plan.items.enumerated().map { Solver.resolve($1, catalog, $0) }
        var placements: [Int: Solver.Placement] = [:]
        var reasons: [Int: String] = [:]

        if !geom.valid {
            for i in specs.indices { reasons[i] = invalidRoomReason }
        } else {
            let (order, early) = processingOrder(specs)
            let walkway = Solver.Walkway(geom, config)
            let doors = Solver.requiredDoorZones(geom, walkway, config.walkwayRadius())
            let preferredDoors = Solver.requiredDoorZones(geom, walkway, config.walkwayRadius(config.walkwayPreferred))
            var rng: SeededRandom? = seed == 0 ? nil : SeededRandom(state: seed)
            let budget = Budget(config)
            var placed: [String: Solver.Placement] = [:]
            var placedOrder: [String] = []
            var failed: [String: String] = [:]
            var centredCache: [Solver.Tier]?
            for i in order {
                let spec = specs[i]
                if let reason = early[i] {
                    reasons[i] = reason
                    continue
                }
                if let target = spec.targetID, placed[target] == nil {
                    reasons[i] = "target \(target) could not be placed"
                    continue
                }
                let key = failureKey(spec)
                if let reason = failed[key] {
                    reasons[i] = reason
                    continue
                }
                if budget.spent {
                    reasons[i] = budgetReason
                    continue
                }
                let searchPlan: Solver.SearchPlan
                do {
                    searchPlan = try Solver.generateTiers(spec, geom, placed, placedOrder: placedOrder, config, cache: &centredCache)
                } catch let error as Solver.RuleError {
                    reasons[i] = error.reason
                    failed[key] = error.reason
                    continue
                } catch {
                    reasons[i] = "this placement rule couldn't be used"
                    continue
                }
                switch search(spec, searchPlan, geom, walkway, placed, placedOrder, config, doors: doors,
                              preferredDoors: preferredDoors, rng: &rng, budget: budget) {
                case let .placed(p):
                    placed[spec.id] = p
                    placedOrder.append(spec.id)
                    placements[i] = p
                    failed.removeAll()
                case let .unplaced(reason):
                    reasons[i] = reason
                    if reason != budgetReason { failed[key] = reason }
                }
            }
        }
        let placedItems = placements.keys.sorted().map { i -> FurnitureLayout.Placed in
            let p = placements[i]!
            return FurnitureLayout.Placed(itemID: p.spec.id, x: p.x, z: p.z, rotation: p.rotation,
                                          footprint: [p.spec.width, p.spec.depth], name: p.spec.item.name,
                                          category: p.spec.category, catalogID: p.spec.item.catalogID, height: p.spec.height)
        }
        let unplaced = reasons.keys.sorted().map { FurnitureLayout.Unplaced(itemID: specs[$0].id, reason: reasons[$0]!) }
        return FurnitureLayout(placed: placedItems, unplaced: unplaced)
    }

    /// Re-checks every hard constraint on a finished layout. Empty means valid.
    public static func check(_ room: CanonicalRoom, _ layout: FurnitureLayout, _ plan: FurniturePlan,
                             catalog: FurnitureCatalog = .current, config: SolverConfig = SolverConfig()) -> [LayoutViolation] {
        Solver.checkLayout(room, layout, plan, catalog, config)
    }
}
