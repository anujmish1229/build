import Foundation
import Testing
@testable import RoomScanKit

@Suite struct PlannerTests {
    let catalog = FurnitureCatalog.bundled
    let bedroom = SampleRooms.all[0].room
    let living = SampleRooms.all[1].room

    func result(_ room: CanonicalRoom, _ theme: String, _ c: FurnishConstraints = .init(), name: String? = nil, reader: FurniturePlanner.BriefReader? = nil) async -> FurniturePlanner.Result {
        await FurniturePlanner.design(room: room, theme: theme, constraints: c, roomName: name, catalog: catalog, reader: reader)
    }

    @Test func worksWithAppleIntelligenceOff() async {
        let r = await result(bedroom, "calm japandi bedroom")
        #expect(r.provider == FurniturePlanner.rulesProvider)
        #expect(r.layout.placed.contains { $0.category == "bed" })
        #expect(LayoutSolver.check(bedroom, r.layout, r.plan, catalog: catalog).isEmpty)
        #expect(r.plan.style?.words == ["japandi"])
    }

    @Test(arguments: ["bedroom", "living room", "home office", "dining room"])
    func everyRoomTypeGivesALegalLayout(_ theme: String) async {
        for sample in SampleRooms.all {
            let r = await result(sample.room, theme)
            #expect(!r.layout.placed.isEmpty, "\(sample.name) \(theme)")
            #expect(LayoutSolver.check(sample.room, r.layout, r.plan, catalog: catalog).isEmpty, "\(sample.name) \(theme)")
            for u in r.layout.unplaced { #expect(!u.reason.isEmpty) }
        }
    }

    @Test func roomTypeOrderFollowsTheRules() {
        func type(_ theme: String, must: [String] = [], name: String? = nil, area: Double = 20) -> String? {
            FurniturePlanner.rulesBrief(theme: theme, constraints: .init(mustHave: must), roomName: name, area: area).roomType
        }
        #expect(type("cosy bedroom", name: "My office") == "bedroom")
        #expect(type("japandi", must: ["desk"]) == "office")
        #expect(type("japandi", name: "Dining nook") == "dining")
        #expect(type("japandi", area: 10) == "bedroom")
        #expect(type("japandi", area: 20) == "living")
        #expect(type("home office", must: ["bed"]) == "bedroom")
    }

    @Test func mustHaveAddsOrPicksByName() async {
        let added = await result(bedroom, "bedroom", .init(mustHave: ["bench"]))
        #expect(added.plan.items.contains { $0.category == "bench" })
        let named = await result(bedroom, "bedroom", .init(mustHave: ["pine bed"]))
        #expect(named.plan.items.first { $0.category == "bed" }?.catalogID == "sample_bed_double_pine")
        let none = await result(bedroom, "bedroom", .init(mustHave: ["flying carpet"]))
        #expect(none.notes.contains("flying carpet"))
    }

    @Test func leaveOutRemovesPieceAndDependants() async {
        let r = await result(bedroom, "bedroom", .init(mustAvoid: ["bed"]))
        #expect(!r.plan.items.contains { $0.category == "bed" || $0.category == "nightstand" })
    }

    @Test func budgetSteersAndWarns() async {
        let free = await result(living, "living room")
        let tight = await result(living, "living room", .init(budget: "under $1,500"))
        func total(_ r: FurniturePlanner.Result) -> Double { r.plan.items.compactMap { catalog.entry($0.catalogID)?.price }.reduce(0, +) }
        #expect(total(tight) < total(free))
        let tiny = await result(living, "living room", .init(budget: "100"))
        #expect(tiny.notes.contains("over your budget"))
        #expect(!tiny.layout.placed.isEmpty)
        #expect(FurnishConstraints(budget: "about 2,500.50 CAD").budgetAmount == 2500.5)
    }

    @Test func smallerPieceIsTriedWhenOneDoesNotFit() async {
        let narrow = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(2.5, 0), Point2(2.5, 2.9), Point2(0, 2.9)])
        let big = catalog.entry("sample_bed_queen_oak")!
        let plan = FurniturePlan(theme: "", items: [FurnitureItem(itemID: "bed", catalogID: big.catalogID, name: big.name, category: "bed", size: big.size,
                                                                  placement: .againstWall(wallID: "w0", align: "center"), priority: 1)])
        let (fitted, layout, swaps) = FurniturePlanner.fitted(plan, room: narrow, catalog: catalog)
        #expect(layout.placed.count == 1)
        #expect(fitted.items[0].catalogID == "sample_bed_double_pine")
        #expect(swaps.count == 1)
    }

    @Test func unusableModelAnswerFallsBackToRules() async {
        let r = await result(bedroom, "japandi bedroom", reader: { _ in nil })
        #expect(r.provider == FurniturePlanner.rulesProvider)
    }

    @Test func modelOnlyChoosesWordsAndItsJunkIsDropped() async {
        let answer = DesignBrief(roomType: "spaceship", styleWords: ["Japandi"], wanted: ["bench", "x=1.2 z=3.4", "teleporter"],
                                 avoided: ["plant", "laser"], materials: ["oak", "kryptonite"], accents: ["sage", "plaid"], note: "  A calm room. ")
        let r = await result(bedroom, "calm bedroom", reader: { _ in answer })
        #expect(r.provider == FurniturePlanner.aiProvider)
        #expect(r.brief.roomType == "bedroom")
        #expect(r.brief.wanted == ["bench"])
        #expect(r.brief.avoided == ["plant"])
        #expect(r.brief.materials == ["oak"] && r.brief.accents == ["sage"])
        #expect(r.notes.hasPrefix("A calm room."))
        #expect(LayoutSolver.check(bedroom, r.layout, r.plan, catalog: catalog).isEmpty)
    }

    @Test func modelNeverHandlesCoordinates() async throws {
        // A brief has no field that could carry a position, in code or in JSON.
        let names = Mirror(reflecting: DesignBrief()).children.compactMap(\.label)
        for banned in ["x", "z", "rotation", "position", "coordinates", "placement", "offset"] { #expect(!names.contains(banned)) }
        // Whatever the model writes in a note, the placements still come from the rule vocabulary.
        let r = await result(bedroom, "bedroom", reader: { _ in DesignBrief(note: "Put the bed at x=99, z=99.") })
        let rules = await result(bedroom, "bedroom")
        #expect(r.layout.placed == rules.layout.placed)
        // And the prompt asks for no geometry: only the area of the room goes in.
        let prompt = FurniturePlanner.prompt(room: bedroom, theme: "bedroom", constraints: .init(), colours: nil)
        #expect(!prompt.contains("[") && !prompt.contains("wall"))
    }

    @Test func sameThemeGivesTheSameDesign() async {
        let a = await result(living, "warm boho lounge")
        let b = await result(living, "warm boho lounge")
        #expect(a.plan == b.plan && a.layout == b.layout)
    }

    @Test func rolesFindTheFacingWall() {
        let roles = WallRoles(CanonicalRoom.make(polygon: [Point2(0, 0), Point2(5, 0), Point2(5, 3), Point2(0, 3)]))
        #expect(roles.main == "w0" && roles.opposite == "w2")
        #expect(roles.sides == ["w1", "w3"])
        let turned = WallRoles(CanonicalRoom.make(polygon: [Point2(0, 0), Point2(5, 0), Point2(5, 3), Point2(0, 3)]), anchor: "w1")
        #expect(turned.main == "w1" && turned.opposite == "w3")
    }

    @Test(arguments: [("christmas living room", "christmas", "christmas_tree"), ("xmas lounge", "christmas", "christmas_tree"),
                      ("halloween living room", "halloween", "pumpkins"), ("spooky lounge", "halloween", "pumpkins")])
    func aHolidayThemeAddsDecorationsLegally(_ theme: String, _ word: String, _ piece: String) async {
        let room = SampleRooms.all[3].room
        let r = await result(room, theme)
        #expect(r.plan.style?.words.first == word)
        #expect(r.layout.placed.contains { $0.category == piece })
        #expect(r.layout.placed.contains { $0.category == "fireplace" })
        #expect(LayoutSolver.check(room, r.layout, r.plan, catalog: catalog).isEmpty)
        // Decorations aren't products: they have no catalogue entry and add nothing to the price.
        for item in r.plan.items where Season.isDecoration(item.category) { #expect(item.catalogID == nil, "\(item.name)") }
        #expect(r.layout.unplaced.isEmpty)
    }

    @Test func aHolidayIsReadWhateverTheModelSays() async {
        let r = await result(bedroom, "christmas bedroom", reader: { _ in DesignBrief(roomType: "bedroom", styleWords: ["cosy"]) })
        #expect(r.plan.style?.words.first == "christmas")
        #expect(r.layout.placed.contains { $0.category == "bed" })
        #expect(LayoutSolver.check(bedroom, r.layout, r.plan, catalog: catalog).isEmpty)
    }

    @Test func extrasThatDoNotFitAreLeftOutQuietly() async {
        let tiny = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(3, 0), Point2(3, 2.8), Point2(0, 2.8)])
        let r = await result(tiny, "bedroom")
        #expect(r.layout.unplaced.allSatisfy { id in r.plan.items.first { $0.itemID == id.itemID }.map { $0.priority < FurniturePlanner.extraPriority } ?? false })
        #expect(r.plan.items.allSatisfy { item in item.priority < FurniturePlanner.extraPriority || r.layout.placed.contains { $0.itemID == item.itemID } })
    }

    @Test func aHolidayThemeSuggestsItsPaint() {
        #expect(WallPaint.suggestions(for: "halloween lounge").first == Season.halloween.paint)
        #expect(WallPaint.suggestions(for: "cosy christmas room").first == Season.christmas.paint)
    }

    @Test func colourNamesArePlain() {
        #expect(RoomColours.name("#FFFFFF", surface: "") == "white")
        #expect(RoomColours.name("#F0E8D8", surface: "") == "warm off-white")
        #expect(RoomColours.name("#B58A5E", surface: "wood") == "honey wood")
        #expect(RoomColours.hex(r: 1, g: 0, b: 0.5) == "#FF0080")
        #expect(RoomColours.rgb("nope") == nil)
    }
}
