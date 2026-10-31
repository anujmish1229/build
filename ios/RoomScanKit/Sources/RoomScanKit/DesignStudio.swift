import Foundation

/// One way to furnish a room.
public struct LayoutOption: Sendable, Equatable, Identifiable {
    public var id: Int
    public var plan: FurniturePlan
    public var layout: FurnitureLayout
    /// "Bed on the long wall, facing the window".
    public var summary: String
    public var notes: String
    public var provider: String
    /// A snapshot of the products, for saving and sharing.
    public var products: [CatalogEntry]

    public var placedProducts: [CatalogEntry] { layout.placed.compactMap { p in products.first { $0.catalogID == p.catalogID } } }

    public init(id: Int, plan: FurniturePlan, layout: FurnitureLayout, summary: String, notes: String, provider: String, products: [CatalogEntry]) {
        self.id = id; self.plan = plan; self.layout = layout; self.summary = summary
        self.notes = notes; self.provider = provider; self.products = products
    }
}

/// Layout options for a theme, and editing by swapping, removing or adding pieces. Everything is
/// re-fitted by the solver, so every result keeps doors and walkways clear.
public enum DesignStudio {
    /// Up to three layouts, the main piece on a different wall in each.
    public static func options(room: CanonicalRoom, theme: String, constraints: FurnishConstraints = .init(), roomName: String? = nil,
                               colours: RoomColours? = nil, catalog: FurnitureCatalog = .current, count: Int = 3,
                               reader: FurniturePlanner.BriefReader? = FurniturePlanner.systemReader) async -> [LayoutOption] {
        let (brief, provider) = await FurniturePlanner.readBrief(room: room, theme: theme, constraints: constraints, roomName: roomName,
                                                                 colours: colours, reader: reader)
        var candidates: [LayoutOption] = []
        for (n, wall) in anchorWalls(room).enumerated() {
            let chosen = FurniturePlanner.plan(brief: brief, room: room, theme: theme, constraints: constraints, catalog: catalog, anchorWall: wall)
            let (plan, layout, swaps) = FurniturePlanner.fitted(chosen.plan, room: room, catalog: catalog)
            let notes = FurniturePlanner.notes(brief: brief, base: chosen.notes + swaps, layout: layout, constraints: constraints, catalog: catalog)
            candidates.append(option(n, plan, layout, room: room, notes: notes, provider: provider, catalog: catalog))
        }
        return pick(candidates, count: count)
    }

    /// The design with one piece swapped for another product, re-fitted.
    public static func swap(_ option: LayoutOption, itemID: String, to entry: CatalogEntry, room: CanonicalRoom,
                            catalog: FurnitureCatalog = .current) -> LayoutOption {
        var plan = option.plan
        guard let i = plan.items.firstIndex(where: { $0.itemID == itemID }) else { return option }
        plan.items[i].catalogID = entry.catalogID
        plan.items[i].name = entry.name
        plan.items[i].category = entry.category
        plan.items[i].size = entry.size
        return refit(option, plan, room: room, catalog: FurnitureCatalog(entries: option.products + [entry]).merged(with: catalog))
    }

    /// The design without a piece and anything placed relative to it, re-fitted.
    public static func remove(_ option: LayoutOption, itemID: String, room: CanonicalRoom, catalog: FurnitureCatalog = .current) -> LayoutOption {
        var plan = option.plan
        var gone: Set<String> = [itemID]
        var changed = true
        while changed {
            changed = false
            for item in plan.items where !gone.contains(item.itemID) {
                if let target = item.placement.targetItemID, gone.contains(target) { gone.insert(item.itemID); changed = true }
            }
        }
        plan.items.removeAll { gone.contains($0.itemID) }
        return refit(option, plan, room: room, catalog: FurnitureCatalog(entries: option.products).merged(with: catalog))
    }

    /// The design with a new piece, or nil if it can't fit anywhere.
    public static func add(_ option: LayoutOption, entry: CatalogEntry, room: CanonicalRoom, catalog: FurnitureCatalog = .current) -> LayoutOption? {
        let merged = FurnitureCatalog(entries: option.products + [entry]).merged(with: catalog)
        let id = Library.free(entry.category, taken: Set(option.plan.items.map(\.itemID))).replacingOccurrences(of: " ", with: "_")
        var rules: [PlacementRule] = []
        let placedIDs = Set(option.layout.placed.map(\.itemID))
        // Wall decor is in neither set: it goes centred on the longest wall that takes it, the last resort below.
        let wallPieces: Set<String> = ["bed", "sofa", "wardrobe", "desk", "dresser", "bookshelf", "storage", "tv_stand", "coffin", "fence", "cobweb", "tree"]
        let companions: Set<String> = ["nightstand", "side_table", "lamp", "plant", "chair", "coffee_table", "armchair", "jack_o_lantern", "curio",
                                       "gore", "prop_light", "candelabra", "cauldron", "fog_machine", "spider", "projector"]
        if companions.contains(entry.category), let main = option.plan.items.first(where: { wallPieces.contains($0.category) && placedIDs.contains($0.itemID) }) {
            rules += [.beside(targetItemID: main.itemID, side: "left", gap: 0.05), .beside(targetItemID: main.itemID, side: "right", gap: 0.05)]
        }
        if entry.category == "dining_table" || entry.category == "coffee_table" { rules.append(.centeredInRoom) }
        rules += room.walls.sorted { $0.length > $1.length }.map { .againstWall(wallID: $0.id, align: "center") }
        for rule in rules {
            var plan = option.plan
            plan.items.append(FurnitureItem(itemID: id, catalogID: entry.catalogID, name: entry.name, category: entry.category,
                                            size: entry.size, placement: rule, priority: 5))
            let edited = refit(option, plan, room: room, catalog: merged)
            if edited.layout.placed.contains(where: { $0.itemID == id }), edited.layout.placed.count > option.layout.placed.count { return edited }
        }
        return nil
    }

    /// Products of the same kind, best fit first.
    public static func alternatives(for itemID: String, in option: LayoutOption, catalog: FurnitureCatalog = .current) -> [CatalogEntry] {
        guard let item = option.plan.items.first(where: { $0.itemID == itemID }) else { return [] }
        let styles = Set(option.products.first { $0.catalogID == item.catalogID }?.styles ?? [])
        let area = item.size.count >= 2 ? item.size[0] * item.size[1] : 1
        func key(_ e: CatalogEntry) -> (Int, Double) { (-Set(e.styles).intersection(styles).count, abs(e.size[0] * e.size[1] - area)) }
        return catalog.entries.filter { $0.category == item.category && $0.catalogID != item.catalogID }.sorted { key($0) < key($1) }
    }

    /// Up to five walls over 1.2 m, longest first.
    static func anchorWalls(_ room: CanonicalRoom) -> [String] {
        let walls = room.walls.filter { $0.length > 1.2 }.sorted { $0.length > $1.length }.map(\.id)
        return Array((walls.isEmpty ? room.walls.map(\.id) : walls).prefix(5))
    }

    /// Distinct options placing at least as many pieces as the best minus one. Those where every
    /// piece that matters fits come first, when there are any.
    static func pick(_ all: [LayoutOption], count: Int) -> [LayoutOption] {
        let complete = all.filter { $0.layout.unplaced.isEmpty && !$0.layout.placed.isEmpty }
        let candidates = complete.isEmpty ? all : complete
        let best = candidates.map(\.layout.placed.count).max() ?? 0
        func positions(_ o: LayoutOption) -> Set<String> {
            Set(o.layout.placed.map { "\($0.itemID)@\(Int($0.x * 10)),\(Int($0.z * 10)),\(Int($0.rotation))" })
        }
        var out: [LayoutOption] = []
        for c in candidates where c.layout.placed.count >= best - 1 && !c.layout.placed.isEmpty {
            if out.contains(where: { positions($0) == positions(c) }) { continue }
            out.append(c)
            if out.count == count { break }
        }
        if out.isEmpty, let first = candidates.first { out = [first] }
        return out.enumerated().map { var o = $1; o.id = $0; return o }
    }

    static func uniqued(_ list: [CatalogEntry]) -> [CatalogEntry] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.catalogID).inserted }
    }

    static func option(_ n: Int, _ plan: FurniturePlan, _ layout: FurnitureLayout, room: CanonicalRoom, notes: String,
                       provider: String, catalog: FurnitureCatalog) -> LayoutOption {
        LayoutOption(id: n, plan: plan, layout: layout, summary: summary(plan, layout, room: room), notes: notes, provider: provider,
                     products: uniqued(plan.items.compactMap { catalog.entry($0.catalogID) }))
    }

    static func refit(_ option: LayoutOption, _ plan: FurniturePlan, room: CanonicalRoom, catalog: FurnitureCatalog) -> LayoutOption {
        let layout = LayoutSolver.solve(room, plan, catalog: catalog)
        return DesignStudio.option(option.id, plan, layout, room: room, notes: option.notes, provider: option.provider, catalog: catalog)
    }

    /// "Bed on the long wall, facing the window".
    public static func summary(_ plan: FurniturePlan, _ layout: FurnitureLayout, room: CanonicalRoom, units: UnitSystem = .metric) -> String {
        let order = ["bed", "sofa", "desk", "dining_table", "wardrobe", "tv_stand"]
        guard let main = order.lazy.compactMap({ c in layout.placed.first { $0.category == c } }).first ?? layout.placed.first else {
            return "Nothing fits this room yet"
        }
        let centre = Point2(main.x, main.z)
        func distance(_ w: Wall) -> Double { PlanMath.distance(centre, toSegment: w.start, w.end) }
        let wall = room.walls.min { distance($0) < distance($1) }
        var text = (main.category ?? "piece").replacingOccurrences(of: "_", with: " ").capitalized
        if let wall {
            let longest = room.walls.map(\.length).max() ?? 0
            text += abs(wall.length - longest) < 0.05 ? " on the long wall" : " on the \(Units.format(wall.length, units)) wall"
        }
        let front = PlanMath.front(degrees: main.rotation)
        func middle(_ o: Opening) -> Point2? { room.wall(o.wallID)?.point(at: o.offset + o.width / 2) }
        func faces(_ p: Point2) -> Bool { (p - centre).dot(front) / max((p - centre).length, 1e-9) > 0.8 }
        var clauses: [String] = []
        if let wall, room.openings.contains(where: { $0.type == .window && $0.wallID == wall.id }) {
            clauses.append("under the window")
        } else if room.openings.filter({ $0.type == .window }).compactMap(middle).contains(where: faces) {
            clauses.append("facing the window")
        }
        if let door = room.openings.first(where: { $0.type == .door }).flatMap(middle) {
            if faces(door) {
                clauses.append("facing the door")
            } else {
                let b = room.derived.bounds
                clauses.append(door.distance(to: centre) < max(b.width, b.depth) * 0.45 ? "near the door" : "away from the door")
            }
        }
        return ([text] + clauses.prefix(2)).joined(separator: ", ")
    }
}
