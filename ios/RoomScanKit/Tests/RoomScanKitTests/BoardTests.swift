import Foundation
import Testing
@testable import RoomScanKit

@Suite struct BoardTests {
    let catalog = FurnitureCatalog.bundled

    @Test func starterBoardShipsAndStaysInStepWithThePlanner() async throws {
        let generated = await StarterBoard.generate(catalog: catalog)
        // To refresh the file after changing the planner: REGENERATE_STARTER=<path to the resource> swift test
        if let path = ProcessInfo.processInfo.environment["REGENERATE_STARTER"] {
            try generated.encoded().write(to: URL(fileURLWithPath: path))
        }
        let shipped = StarterBoard.load()
        #expect(shipped.count == StarterBoard.recipes.count)
        #expect(shipped == generated.designs)
    }

    @Test func loadingTheStarterBoardNeedsNoSolving() {
        // Reading a file is the whole of the work, so a large catalogue can't slow the first Board down.
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = StarterBoard.load() }
        #expect(elapsed < .milliseconds(500))
    }

    @Test func everyStarterDesignIsLegal() {
        for d in StarterBoard.load() {
            #expect(!d.layout.placed.isEmpty, "\(d.title)")
            #expect(LayoutSolver.check(d.room, d.layout, d.plan, catalog: FurnitureCatalog(entries: d.products)).isEmpty, "\(d.title)")
        }
    }

    @Test func starterBoardCoversTheFilters() {
        let designs = StarterBoard.load()
        #expect(Set(designs.map(\.roomType)) == ["bedroom", "living", "office", "dining"])
        #expect(!designs.flatMap(\.styles).isEmpty)
    }

    func package(_ id: String = UUID().uuidString, title: String = "T") -> DesignPackage {
        var d = StarterBoard.load()[0]
        d.id = id
        d.title = title
        return d
    }

    @Test func orderIsYoursThenSharedThenFeedThenStarter() throws {
        var library = Library()
        let room = SavedRoom(name: "R", room: SampleRooms.all[0].room)
        library.rooms = [room]
        let d = package()
        library.designs = [SavedDesign(roomID: room.id, name: "Mine", theme: "", plan: d.plan, layout: d.layout, products: d.products)]
        library.pins = [BoardPin(id: "s", source: .shared, design: package("s")), BoardPin(id: "f2", source: .feed, design: package("f2"))]
        let pins = BoardContents.pins(library: library, feed: FeedFile(title: "", designs: [package("f"), package("starter-1")]), starter: [package("starter-1"), package("x")])
        #expect(pins.map(\.source) == [.mine, .shared, .feed, .feed, .starter])
        #expect(pins.map(\.id).filter { $0 == "starter-1" }.count == 1)
    }

    @Test func readyMadeDesignsInSampleRoomsAppearOnceUntilChanged() throws {
        let store = LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try store.addSamples()
        let starter = StarterBoard.load()
        let pins = BoardContents.pins(library: store.current, feed: nil, starter: starter)
        #expect(pins.count == starter.count)
        #expect(pins.allSatisfy { $0.source == .starter })
        #expect(BoardContents.exportFeed(store.current).designs.isEmpty)
        // Once it's been changed, it's the user's own.
        let first = try #require(store.current.designs.first)
        try store.updateDesign(first.id) { $0.exampleOf = nil }
        #expect(BoardContents.minePins(store.current).map(\.id) == [first.id.uuidString])
    }

    @Test func filtersCombine() {
        let pins = StarterBoard.load().map { BoardPin(id: $0.id, source: .starter, design: $0) }
        #expect(BoardContents.filtered(pins, .init()).count == StarterBoard.recipes.count)
        #expect(BoardContents.filtered(pins, .init(source: .shared)).isEmpty)
        let bedrooms = BoardContents.filtered(pins, .init(roomType: "bedroom"))
        #expect(!bedrooms.isEmpty && bedrooms.allSatisfy { $0.design.roomType == "bedroom" })
        let style = pins[0].design.styles[0]
        #expect(BoardContents.filtered(pins, .init(style: style)).allSatisfy { $0.design.styles.contains(style) })
    }

    @Test func masonryGoesToTheShorterColumn() {
        let columns = BoardContents.columns([3.0, 1.0, 1.0, 1.0], height: { $0 })
        #expect(columns[0] == [3.0])
        #expect(columns[1] == [1.0, 1.0, 1.0])
    }

    @Test(arguments: 0..<StarterBoard.recipes.count)
    func aRemixFitsTheTargetRoom(_ index: Int) {
        let design = StarterBoard.load()[index]
        for sample in SampleRooms.all {
            let options = DesignStudio.remix(design, into: sample.room, catalog: catalog)
            #expect((1...3).contains(options.count))
            for o in options {
                let merged = FurnitureCatalog(entries: o.products).merged(with: catalog)
                #expect(LayoutSolver.check(sample.room, o.layout, o.plan, catalog: merged).isEmpty, "\(design.title) into \(sample.name)")
                #expect(!o.layout.placed.isEmpty)
                #expect(o.notes.contains("Remixed from"))
            }
        }
    }

    @Test func aRemixKeepsProductsThisCatalogueDoesNotHave() throws {
        var design = try #require(StarterBoard.load().first { $0.roomType == "bedroom" })
        let bed = try #require(design.plan.items.firstIndex { $0.category == "bed" })
        let foreign = CatalogEntry(catalogID: "foreign_bed", name: "Foreign bed", category: "bed", size: [1.4, 2.0, 0.9], store: "Elsewhere", price: 500, currency: "EUR")
        design.plan.items[bed].catalogID = foreign.catalogID
        design.products.append(foreign)
        if let p = design.layout.placed.firstIndex(where: { $0.category == "bed" }) { design.layout.placed[p].catalogID = foreign.catalogID }
        let option = DesignStudio.remix(design, into: SampleRooms.all[1].room, catalog: catalog)[0]
        #expect(option.products.contains { $0.catalogID == "foreign_bed" })
    }

    @Test func aRoomWithNoWindowGetsAWallInstead() {
        let bare = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(0, 4)])
        let theirs = SampleRooms.all[0].room
        let rule = DesignStudio.mapped(.underWindow(openingID: "win0"), from: WallRoles(theirs), theirRoom: theirs, to: WallRoles(bare))
        if case .againstWall = rule {} else { Issue.record("expected a wall rule, got \(rule)") }
    }

    @Test func feedAddressesMustBeSecure() throws {
        #expect(try FeedStore.checkedURL("https://example.com/feed.json").host == "example.com")
        #expect(try FeedStore.checkedURL("http://localhost:8000/feed.json").host == "localhost")
        #expect(throws: CatalogError.self) { try FeedStore.checkedURL("http://example.com/feed.json") }
        #expect(throws: CatalogError.self) { try FeedStore.checkedURL("ftp://example.com/feed.json") }
        #expect(throws: CatalogError.self) { try FeedStore.checkedURL("not an address") }
    }

    @Test func badFeedsAreRefused() throws {
        #expect(throws: CatalogError.self) { try FeedFile.read(Data("nope".utf8)) }
        #expect(throws: CatalogError.self) { try FeedFile.read(Data(#"{"format":"roomscan.design","version":1}"#.utf8)) }
        #expect(throws: CatalogError.self) { try FeedFile.read(Data(#"{"format":"roomscan.board","version":2,"title":"","designs":[]}"#.utf8)) }
        #expect(throws: CatalogError.self) { try FeedFile.read(Data(#"{"format":"roomscan.board","version":1}"#.utf8)) }
    }

    @Test func exportedFeedReadsBack() throws {
        var library = Library()
        let room = SavedRoom(name: "R", room: SampleRooms.all[0].room)
        library.rooms = [room]
        let d = package()
        library.designs = [SavedDesign(roomID: room.id, name: "Mine", theme: "", plan: d.plan, layout: d.layout, products: d.products)]
        let feed = BoardContents.exportFeed(library)
        #expect(try FeedFile.read(feed.encoded()).designs.map(\.title) == ["Mine"])
    }
}
