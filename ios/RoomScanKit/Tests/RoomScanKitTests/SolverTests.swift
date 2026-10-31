import Foundation
import Testing
@testable import RoomScanKit

/// A tiny repeatable generator, so a failing randomised case can be replayed from its seed.
private struct Dice {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    mutating func pick<T>(_ list: [T]) -> T { list[min(Int(next() * Double(list.count)), list.count - 1)] }
}

private func rectangle(_ w: Double, _ d: Double) -> [Point2] { [Point2(0, 0), Point2(w, 0), Point2(w, d), Point2(0, d)] }

private func randomRoom(_ dice: inout Dice) -> CanonicalRoom {
    let w = dice.range(2.6, 7), d = dice.range(2.6, 6)
    var polygon = rectangle(w, d)
    if dice.next() < 0.4 {
        let cx = dice.range(w * 0.45, w * 0.8), cz = dice.range(d * 0.45, d * 0.8)
        polygon = [Point2(0, 0), Point2(w, 0), Point2(w, cz), Point2(cx, cz), Point2(cx, d), Point2(0, d)]
    }
    var room = CanonicalRoom.make(polygon: polygon, ceiling: 2.5)
    let swings: [DoorSwing] = [.unknown, .inwardLeft, .inwardRight, .outwardLeft, .outwardRight]
    let walls = room.walls.filter { $0.length > 1.2 }
    let doorWall = dice.pick(walls)
    room.openings.append(Opening(id: "d0", type: .door, wallID: doorWall.id, offset: dice.range(0, doorWall.length - 0.85),
                                 width: 0.82, height: 2.03, sill: 0, swing: dice.pick(swings)))
    let windowWall = dice.pick(walls.filter { $0.id != doorWall.id })
    room.openings.append(Opening(id: "win0", type: .window, wallID: windowWall.id, offset: dice.range(0, windowWall.length - 1.05),
                                 width: 1.0, height: 1.2, sill: 0.9))
    return room
}

private func randomPlan(_ dice: inout Dice, room: CanonicalRoom, catalog: FurnitureCatalog) -> FurniturePlan {
    var items: [FurnitureItem] = []
    let count = Int(dice.range(3, 10))
    for i in 0..<count {
        let entry = dice.pick(catalog.entries)
        let wall = dice.pick(room.walls)
        var rule: PlacementRule
        switch Int(dice.range(0, 6)) {
        case 0: rule = .againstWall(wallID: wall.id, align: dice.pick(["start", "center", "end"]))
        case 1: rule = .corner(wallID: wall.id, corner: dice.pick(["start", "end"]))
        case 2: rule = .centeredInRoom
        case 3: rule = .underWindow(openingID: "win0")
        case 4 where !items.isEmpty: rule = .inFrontOf(targetItemID: items[0].itemID, gap: dice.range(0.1, 0.5))
        case 5 where !items.isEmpty: rule = .beside(targetItemID: items[0].itemID, side: dice.pick(["left", "right"]), gap: 0.05)
        default: rule = .againstWall(wallID: wall.id, align: "center")
        }
        if case .centeredInRoom = rule, i == 0 { rule = .againstWall(wallID: wall.id, align: "center") }
        items.append(FurnitureItem(itemID: "item\(i)", catalogID: entry.catalogID, name: entry.name, category: entry.category,
                                   size: entry.size, placement: rule, priority: Int(dice.range(1, 5))))
    }
    return FurniturePlan(theme: "random", items: items)
}

@Suite struct SolverTests {
    let catalog = FurnitureCatalog.bundled

    /// Checks that don't share the solver's geometry code, so a bug there can't hide itself.
    private func independentViolations(_ room: CanonicalRoom, _ layout: FurnitureLayout, _ plan: FurniturePlan) -> [String] {
        var out: [String] = []
        func hangs(_ p: FurnitureLayout.Placed) -> Bool { ["poster", "neon_sign", "string_lights", "led_strip"].contains(p.category ?? "") }
        let rects = layout.placed.map { OrientedRect(centre: Point2($0.x, $0.z), width: $0.footprint[0], depth: $0.footprint[1], rotation: $0.rotation) }
        for (p, rect) in zip(layout.placed, rects) {
            for corner in rect.corners {
                if !PlanMath.contains(room.floorPolygon, corner) { out.append("\(p.itemID) outside") }
                for w in room.walls where PlanMath.distance(corner, toSegment: w.start, w.end) < 0.02 - 1e-3 {
                    out.append("\(p.itemID) within the margin of \(w.id)")
                }
            }
            for corner in room.floorPolygon where rect.halfU > 0 && rect.contains(corner) {
                out.append("\(p.itemID) contains a room corner")
            }
            for (o, zone) in PlanGeometry.keepClearZones(room) where rect.overlaps(zone) { out.append("\(p.itemID) in door zone \(o.id)") }
            for o in room.openings where o.type == .window {
                guard let w = room.wall(o.wallID) else { continue }
                if (p.height ?? 0) > o.sill + 0.05 || hangs(p), rect.overlaps(PlanGeometry.windowZone(o, wall: w)) { out.append("\(p.itemID) tall at \(o.id)") }
            }
        }
        for i in rects.indices {
            // A piece on the floor and one hanging above it are at different heights.
            for j in rects.indices where j > i && hangs(layout.placed[i]) == hangs(layout.placed[j]) && rects[i].overlaps(rects[j], tolerance: 1e-4) {
                out.append("\(layout.placed[i].itemID) overlaps \(layout.placed[j].itemID)")
            }
        }
        return out
    }

    @Test(arguments: 0..<60)
    func randomisedPlansNeverBreakAHardConstraint(_ seed: Int) {
        var dice = Dice(state: UInt64(seed) &* 7919 &+ 17)
        let room = randomRoom(&dice)
        let plan = randomPlan(&dice, room: room, catalog: catalog)
        let layout = LayoutSolver.solve(room, plan, catalog: catalog)
        #expect(LayoutSolver.check(room, layout, plan, catalog: catalog).isEmpty, "seed \(seed)")
        #expect(independentViolations(room, layout, plan).isEmpty, "seed \(seed): \(independentViolations(room, layout, plan))")
        // Every item is accounted for, and every unplaced one says why.
        #expect(layout.placed.count + layout.unplaced.count == plan.items.count, "seed \(seed)")
        #expect(layout.unplaced.allSatisfy { !$0.reason.isEmpty })
    }

    @Test(arguments: 0..<10)
    func sameInputGivesTheSameLayout(_ seed: Int) throws {
        var dice = Dice(state: UInt64(seed) &* 104729 &+ 3)
        let room = randomRoom(&dice)
        let plan = randomPlan(&dice, room: room, catalog: catalog)
        let first = LayoutSolver.solve(room, plan, catalog: catalog, seed: UInt64(seed))
        let again = LayoutSolver.solve(room, plan, catalog: catalog, seed: UInt64(seed))
        #expect(first == again)
        #expect(try RoomJSON.encoder().encode(first) == RoomJSON.encoder().encode(again))
    }

    private func item(_ id: String, _ size: [Double], _ rule: PlacementRule, category: String = "side_table", priority: Int = 1) -> FurnitureItem {
        FurnitureItem(itemID: id, name: id, category: category, size: size, placement: rule, priority: priority)
    }

    @Test func wallRulePutsTheBackAgainstTheWall() throws {
        let room = CanonicalRoom.make(polygon: rectangle(5, 4))
        let plan = FurniturePlan(theme: "", items: [item("a", [1.6, 2.0, 0.5], .againstWall(wallID: "w0", align: "center"), category: "bed")])
        let p = try #require(LayoutSolver.solve(room, plan, catalog: catalog).placed.first)
        #expect(p.rotation == 0)
        #expect(abs(p.x - 2.5) < 1e-6)
        #expect(abs(p.z - 1.02) < 1e-6)
    }

    @Test func oppositeWallFacesTheRoom() throws {
        let room = CanonicalRoom.make(polygon: rectangle(5, 4))
        let plan = FurniturePlan(theme: "", items: [item("a", [1, 0.5, 0.5], .againstWall(wallID: "w2", align: "center"))])
        let p = try #require(LayoutSolver.solve(room, plan, catalog: catalog).placed.first)
        #expect(p.rotation == 180)
    }

    @Test func dependantsComeAfterTargetsWhateverThePriority() throws {
        let room = CanonicalRoom.make(polygon: rectangle(5, 4))
        let plan = FurniturePlan(theme: "", items: [
            item("chair", [0.5, 0.5, 0.8], .inFrontOf(targetItemID: "desk", gap: 0.1), category: "chair", priority: 1),
            item("desk", [1.2, 0.6, 0.75], .againstWall(wallID: "w0", align: "center"), category: "desk", priority: 3),
        ])
        let layout = LayoutSolver.solve(room, plan, catalog: catalog)
        #expect(layout.placed.count == 2)
        let chair = try #require(layout.placed.first { $0.itemID == "chair" })
        #expect(chair.z > 0.6)
        #expect(chair.rotation == 180)
    }

    @Test func tooBigIsReported() {
        let room = CanonicalRoom.make(polygon: rectangle(3, 3))
        let plan = FurniturePlan(theme: "", items: [item("huge", [4, 4, 1], .againstWall(wallID: "w0", align: "center"))])
        let layout = LayoutSolver.solve(room, plan, catalog: catalog)
        #expect(layout.placed.isEmpty)
        #expect(layout.unplaced.first?.reason == "does not fit inside the room")
    }

    @Test func aDependantOfAnUnplacedTargetIsDropped() {
        let room = CanonicalRoom.make(polygon: rectangle(3, 3))
        let plan = FurniturePlan(theme: "", items: [
            item("huge", [4, 4, 1], .againstWall(wallID: "w0", align: "center")),
            item("lamp", [0.3, 0.3, 1], .beside(targetItemID: "huge", side: "left", gap: 0.05)),
        ])
        #expect(LayoutSolver.solve(room, plan, catalog: catalog).unplaced.map(\.reason).last == "target huge could not be placed")
    }

    @Test func badReferencesAreReportedInPlainWords() {
        let room = CanonicalRoom.make(polygon: rectangle(4, 4))
        let plan = FurniturePlan(theme: "", items: [
            item("a", [1, 1, 1], .againstWall(wallID: "nope", align: "center")),
            item("b", [1, 1, 1], .underWindow(openingID: "nope")),
            item("c", [1, 1, 1], .inFrontOf(targetItemID: "ghost", gap: 0.2)),
        ])
        let reasons = LayoutSolver.solve(room, plan, catalog: catalog).unplaced.map(\.reason)
        #expect(reasons == ["unknown wall nope", "unknown window nope", "unknown target item ghost"])
    }

    @Test func aFullWalkwayBlockIsRefused() {
        // A corridor with a door at each end: a wide cabinet would cut it in two.
        let room = CanonicalRoom.make(polygon: rectangle(6, 1.5), openings: [
            Opening(id: "d0", type: .door, wallID: "w1", offset: 0.3, width: 0.8, height: 2, sill: 0, swing: .outwardLeft),
            Opening(id: "d1", type: .door, wallID: "w3", offset: 0.3, width: 0.8, height: 2, sill: 0, swing: .outwardLeft),
        ])
        let plan = FurniturePlan(theme: "", items: [item("block", [1, 1.2, 0.9], .centeredInRoom)])
        let layout = LayoutSolver.solve(room, plan, catalog: catalog)
        #expect(LayoutSolver.check(room, layout, plan, catalog: catalog).isEmpty)
        #expect(layout.placed.isEmpty)
    }

    @Test func tallPieceStaysOutOfAWindowZoneButALowOneMayStay() {
        let window = Opening(id: "win0", type: .window, wallID: "w0", offset: 0.5, width: 3, height: 1.2, sill: 0.9)
        let room = CanonicalRoom.make(polygon: rectangle(4, 4), openings: [window])
        let low = FurniturePlan(theme: "", items: [item("low", [1, 0.4, 0.8], .underWindow(openingID: "win0"))])
        #expect(abs(LayoutSolver.solve(room, low, catalog: catalog).placed[0].z - 0.22) < 1e-6)
        let tall = FurniturePlan(theme: "", items: [item("tall", [1, 0.4, 1.8], .underWindow(openingID: "win0"))])
        let p = LayoutSolver.solve(room, tall, catalog: catalog).placed[0]
        #expect(!OrientedRect(centre: Point2(p.x, p.z), width: 1, depth: 0.4, rotation: p.rotation)
            .overlaps(PlanGeometry.windowZone(window, wall: room.walls[0])))
    }

    @Test func invalidRoomPlacesNothing() {
        let room = CanonicalRoom.make(polygon: rectangle(4, 4).reversed())
        let plan = FurniturePlan(theme: "", items: [item("a", [1, 1, 1], .centeredInRoom)])
        #expect(LayoutSolver.solve(room, plan, catalog: catalog).unplaced.first?.reason == LayoutSolver.invalidRoomReason)
    }

    @Test func checkerCatchesATamperedLayout() {
        let room = CanonicalRoom.make(polygon: rectangle(5, 4))
        let plan = FurniturePlan(theme: "", items: [item("a", [1, 1, 1], .againstWall(wallID: "w0", align: "center"))])
        var layout = LayoutSolver.solve(room, plan, catalog: catalog)
        layout.placed[0].x = -2
        #expect(LayoutSolver.check(room, layout, plan, catalog: catalog).contains { $0.constraint == Solver.inside })
    }

    @Test func aLargePlanFinishesWithinItsWorkBudget() {
        let room = CanonicalRoom.make(polygon: rectangle(9, 8))
        let items = (0..<60).map { item("i\($0)", [0.5, 0.5, 0.5], .againstWall(wallID: "w\($0 % 4)", align: "center"), priority: $0 / 10 + 1) }
        let plan = FurniturePlan(theme: "", items: items)
        let layout = LayoutSolver.solve(room, plan, catalog: catalog)
        #expect(!layout.placed.isEmpty)
        #expect(layout.placed.count + layout.unplaced.count == 60)
        #expect(LayoutSolver.check(room, layout, plan, catalog: catalog).isEmpty)
    }

    @Test func svgDrawsThePlanAndEscapesNames() {
        let room = SampleRooms.all[0].room
        let plan = FurniturePlan(theme: "", items: [item("a&b", [1, 1, 0.5], .centeredInRoom)])
        let svg = RoomRenderer.svg(room, LayoutSolver.solve(room, plan, catalog: catalog))
        #expect(svg.hasPrefix("<svg") && svg.hasSuffix("</svg>"))
        #expect(svg.contains("a&amp;b"))
        #expect(!svg.contains("a&b"))
    }
}

@Suite struct CatalogTests {
    @Test func builtInCatalogueIsValidAndCoversEveryCategory() {
        let c = FurnitureCatalog.bundled
        #expect(c.entries.filter { !$0.isProp }.count == 27)
        #expect(c.props.count == 56)
        let categories = Set(c.entries.map(\.category))
        for needed in ["bed", "nightstand", "desk", "chair", "wardrobe", "dresser", "bookshelf", "storage", "sofa", "armchair",
                       "coffee_table", "tv_stand", "side_table", "lamp", "plant", "dining_table", "bench"] {
            #expect(categories.contains(needed), "\(needed)")
        }
    }

    @Test func builtInCatalogueNamesNoRetailer() throws {
        for e in FurnitureCatalog.bundled.entries where !e.isProp {
            #expect(e.catalogID.hasPrefix("sample_"))
            #expect(e.store == "Polter Samples")
            #expect(e.url == nil)
        }
        // Props have no store or link of their own. Some name shops that stock them.
        for e in FurnitureCatalog.bundled.props {
            #expect(e.store == nil && e.url == nil, "\(e.catalogID)")
        }
    }

    private func json(_ items: String) -> Data { Data("{\"catalog_version\":2,\"items\":[\(items)]}".utf8) }

    @Test func badFilesAreRefused() {
        #expect(throws: CatalogError.self) { try FurnitureCatalog(json: Data("nope".utf8)) }
        #expect(throws: CatalogError.self) { try FurnitureCatalog(json: json("")) }
        let one = #"{"catalog_id":"a","name":"A","category":"bed","size":[1,1,1]}"#
        #expect(throws: CatalogError.self) { try FurnitureCatalog(json: json(one + "," + one)) }
        #expect(throws: CatalogError.self) { try FurnitureCatalog(json: json(#"{"catalog_id":"a","name":"A","category":"bed","size":[1,1]}"#)) }
        #expect(throws: CatalogError.self) { try FurnitureCatalog(json: json(#"{"catalog_id":"a","name":"A","category":"bed","size":[1,1,25]}"#)) }
    }

    @Test func onlyWebLinksAreKept() throws {
        let c = try FurnitureCatalog(json: json(#"{"catalog_id":"a","name":"A","category":"bed","size":[1,1,1],"url":"javascript:alert(1)"},{"catalog_id":"b","name":"B","category":"bed","size":[1,1,1],"url":"https://example.com/b"}"#))
        #expect(c.entry("a")?.url == nil)
        #expect(c.entry("b")?.url?.host == "example.com")
    }

    @Test func planRoundTripsThroughTheDocumentedShape() throws {
        let text = #"{"theme":"t","items":[{"item_id":"bed","catalog_id":"x","name":"Bed","category":"bed","size":[1.65,2.23,1.0],"style":"","placement":{"rule":"against_wall","wall_id":"w0","align":"center"},"priority":1}]}"#
        let plan = try JSONDecoder().decode(FurniturePlan.self, from: Data(text.utf8))
        #expect(plan.items[0].placement == .againstWall(wallID: "w0", align: "center"))
        #expect(try JSONDecoder().decode(FurniturePlan.self, from: RoomJSON.encoder().encode(plan)) == plan)
    }

    @Test func unknownRuleIsRefused() {
        let text = #"{"rule":"at_coordinates","x":1,"z":2}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(PlacementRule.self, from: Data(text.utf8)) }
    }
}
