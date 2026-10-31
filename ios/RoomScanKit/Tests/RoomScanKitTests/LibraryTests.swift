import Foundation
import Testing
@testable import RoomScanKit

private func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

private func sampleOption(_ theme: String = "bedroom", room: CanonicalRoom = SampleRooms.all[0].room) async -> LayoutOption {
    await DesignStudio.options(room: room, theme: theme, catalog: .bundled, reader: nil)[0]
}

@Suite struct LibraryStoreTests {
    @Test func savesAndReloads() throws {
        let dir = tempDir()
        let store = LibraryStore(directory: dir)
        let room = try store.addRoom(SavedRoom(name: "Bedroom", room: SampleRooms.all[0].room))
        let again = LibraryStore(directory: dir)
        #expect(again.problem == nil)
        #expect(again.current.rooms.map(\.id) == [room.id])
        #expect(again.current.version == Library.currentVersion)
        let values = try store.file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func namesAreMadeUnique() throws {
        let store = LibraryStore(directory: tempDir())
        try store.addRoom(SavedRoom(name: "Bedroom", room: SampleRooms.all[0].room))
        #expect(try store.addRoom(SavedRoom(name: "Bedroom", room: SampleRooms.all[0].room)).name == "Bedroom 2")
    }

    @Test func aDamagedLibraryIsKeptAndNotOverwritten() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("library.json")
        let damaged = Data("{ not json".utf8)
        try damaged.write(to: file)
        let store = LibraryStore(directory: dir)
        #expect(store.problem?.contains("kept") == true)
        #expect(store.current.rooms.isEmpty)
        try store.addRoom(SavedRoom(name: "New", room: SampleRooms.all[0].room))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let aside = try #require(names.first { $0.contains("damaged") })
        #expect(try Data(contentsOf: dir.appendingPathComponent(aside)) == damaged)
    }

    @Test func aNewerLibraryIsNotOverwritten() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let newer = Data(#"{"version":99,"rooms":[]}"#.utf8)
        try newer.write(to: dir.appendingPathComponent("library.json"))
        let store = LibraryStore(directory: dir)
        #expect(store.problem?.contains("newer") == true)
        try store.addSamples()
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.contains("damaged") })
    }

    @Test func sampleRoomsComeFurnished() throws {
        let store = LibraryStore(directory: tempDir())
        try store.addSamples()
        let library = store.current
        for room in library.rooms { #expect(!library.designs(for: room.id).isEmpty, "\(room.name) is empty") }
        for design in library.designs {
            let room = try #require(library.room(design.roomID))
            #expect(LayoutSolver.check(room.room, design.layout, design.plan, catalog: FurnitureCatalog(entries: design.products)).isEmpty, "\(design.name)")
        }
    }

    @Test func theHolidayRoomHasBothHolidaysInItsOwnColours() throws {
        let store = LibraryStore(directory: tempDir())
        try store.addSamples()
        let room = try #require(store.current.rooms.first { $0.name == SampleRooms.holidayRoomName })
        let designs = store.current.designs(for: room.id)
        #expect(Set(designs.compactMap { Season.of(style: $0.plan.style) }) == [.christmas, .halloween])
        #expect(Set(designs.compactMap(\.wallPaint?.hex)) == [Season.christmas.paint.hex, Season.halloween.paint.hex])
    }

    @Test func anEarlierLibraryGetsItsExamplesOnceAndKeepsItsOwnWork() async throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A library from before the sample rooms came furnished: one sample untouched, one with the user's design.
        var old = Library()
        old.samplesAdded = true
        let bare = SavedRoom(name: "Sample bedroom", room: SampleRooms.all[0].room)
        let used = SavedRoom(name: "Sample living room", room: SampleRooms.all[1].room)
        old.rooms = [bare, used]
        let option = await sampleOption("living room", room: used.room)
        old.designs = [SavedDesign(option: option, roomID: used.id, name: "Mine", theme: "t")]
        try LibraryStore.encoder.encode(old).write(to: dir.appendingPathComponent("library.json"))

        let store = LibraryStore(directory: dir)
        try store.addSamplesIfNeeded()
        #expect(!store.current.designs(for: bare.id).isEmpty)
        #expect(store.current.designs(for: used.id).map(\.name) == ["Mine"])
        #expect(store.current.rooms.contains { $0.name == SampleRooms.holidayRoomName })

        // It happens once, even after the user deletes the room.
        let holiday = try #require(store.current.rooms.first { $0.name == SampleRooms.holidayRoomName })
        try store.deleteRoom(holiday.id)
        let reopened = LibraryStore(directory: dir)
        try reopened.addSamplesIfNeeded()
        #expect(!reopened.current.rooms.contains { $0.name == SampleRooms.holidayRoomName })
    }

    @Test func deletingARoomRemovesItsDesigns() async throws {
        let store = LibraryStore(directory: tempDir())
        let room = try store.addRoom(SavedRoom(name: "R", room: SampleRooms.all[0].room))
        let option = await sampleOption()
        try store.addDesign(SavedDesign(option: option, roomID: room.id, name: "D", theme: "t"))
        try store.deleteRoom(room.id)
        #expect(store.current.designs.isEmpty)
    }

    @Test func samplesAreAddedOnceAndStayGoneAfterDeleteEverything() throws {
        let dir = tempDir()
        let store = LibraryStore(directory: dir)
        try store.addSamplesIfNeeded()
        #expect(store.current.rooms.count == SampleRooms.all.count)
        try store.addSamplesIfNeeded()
        #expect(store.current.rooms.count == SampleRooms.all.count)
        try store.deleteAll()
        let reopened = LibraryStore(directory: dir)
        try reopened.addSamplesIfNeeded()
        #expect(reopened.current.rooms.isEmpty)
        try reopened.addSamples()
        #expect(reopened.current.rooms.count == SampleRooms.all.count)
    }

    @Test func boardsKeepACopyOfThePin() async throws {
        let store = LibraryStore(directory: tempDir())
        let board = try store.addBoard("Ideas")
        #expect(try store.addBoard("Ideas").name == "Ideas 2")
        let option = await sampleOption()
        let room = SavedRoom(name: "R", room: SampleRooms.all[0].room)
        let pin = BoardPin(id: "p", source: .feed, design: DesignPackage(SavedDesign(option: option, roomID: room.id, name: "D", theme: "t"), room: room))
        try store.save(pin, to: board.id)
        #expect(store.current.pins.count == 1)
        #expect(store.current.boards[0].pinIDs == ["p"])
        try store.remove(pinID: "p", from: board.id)
        #expect(store.current.boards[0].pinIDs.isEmpty)
        try store.deletePin("p")
        #expect(store.current.pins.isEmpty)
    }
}

@Suite struct MigrationTests {
    func roomJSON(version: Bool = true) throws -> Any {
        var json = try JSONSerialization.jsonObject(with: SampleRooms.all[0].room.encoded()) as! [String: Any]
        if !version { json["schema_version"] = nil }
        return json
    }

    @Test func aVersionZeroLibraryStillLoads() throws {
        let id = UUID().uuidString
        let old: [String: Any] = ["rooms": [[
            "id": id, "name": "Old room", "createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z",
            "room": try roomJSON(version: false),
            "sourceIDs": ["w0": "SURFACE-1"],
            "corrections": ["measured": ["w0": 4.2]],
            "colours": ["wall": "#EEEAE3", "floor": "#B48A5E", "floorType": "wood", "detected": false],
        ]], "designs": [], "boards": [], "pins": []]
        let library = try Migrations.library(from: JSONSerialization.data(withJSONObject: old))
        #expect(library.version == 1)
        #expect(library.rooms[0].name == "Old room")
        #expect(library.rooms[0].sourceIDs == ["w0": ["SURFACE-1"]])
        #expect(library.rooms[0].corrections == RoomCorrections())
        #expect(library.samplesAdded)
    }

    @Test func aRoomFromTheOneRoomAppMovesInOnce() throws {
        let legacy = RoomStore(url: tempDir().appendingPathComponent("room.json"))
        let store = LibraryStore(directory: tempDir())
        #expect(try Migrations.importLegacyRoom(from: legacy, into: store) == false)
        try legacy.save(StoredRoom(editable: EditableRoom(room: SampleRooms.all[0].room)))
        #expect(try Migrations.importLegacyRoom(from: legacy, into: store))
        #expect(store.current.rooms.map(\.name) == ["My room"])
        #expect(try Migrations.importLegacyRoom(from: legacy, into: store) == false)
        #expect(store.current.rooms.count == 1)
    }
}

@Suite struct ShareFileTests {
    func package() async -> (DesignPackage, SavedRoom) {
        let option = await sampleOption()
        var room = SavedRoom(name: "Room", room: SampleRooms.all[0].room, rawScan: RawRoom(capturedAt: "x", device: .init(model: "SECRET-MODEL", osVersion: "o"), walls: []))
        room.corrections.retiredOpeningIDs = ["SECRET-ID"]
        return (DesignPackage(SavedDesign(option: option, roomID: room.id, name: "Design", theme: "t"), room: room), room)
    }

    @Test func designRoundTripsWithProducts() async throws {
        let (design, _) = await package()
        guard case let .design(read) = try ShareFiles.read(ShareFiles.data(design)) else { Issue.record("wrong kind"); return }
        #expect(read.layout == design.layout)
        #expect(read.products == design.products)
        #expect(!read.products.isEmpty)
    }

    @Test func roomFileLeavesOutTheRawScanAndCorrections() async throws {
        let (_, room) = await package()
        let data = try ShareFiles.data(ScanPackage(room))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("SECRET"))
        guard case let .scan(read) = try ShareFiles.read(data) else { Issue.record("wrong kind"); return }
        #expect(read.room == room.room)
    }

    @Test func badFilesAreRefusedInPlainWords() {
        func message(_ text: String) -> String? {
            do { _ = try ShareFiles.read(Data(text.utf8)); return nil }
            catch { return error.localizedDescription }
        }
        #expect(message("nope")?.contains("isn't a room") == true)
        #expect(message(#"{"format":"other"}"#)?.contains("isn't a room") == true)
        #expect(message(#"{"format":"roomscan.scan","version":2}"#)?.contains("newer") == true)
        #expect(message(#"{"format":"roomscan.scan","version":1}"#)?.contains("damaged") == true)
    }

    @Test func aFileWithNoVersionStillOpens() throws {
        var json = try JSONSerialization.jsonObject(with: ShareFiles.data(ScanPackage(SavedRoom(name: "Old", room: SampleRooms.all[0].room)))) as! [String: Any]
        json["version"] = nil
        guard case let .scan(read) = try ShareFiles.read(JSONSerialization.data(withJSONObject: json)) else { Issue.record("wrong kind"); return }
        #expect(read.name == "Old" && read.version == 1)
    }

    @Test func fileNamesAreSafe() {
        #expect(ShareFiles.fileName("a/b:c", ext: "roomscan") == "a-b-c.roomscan")
        #expect(ShareFiles.fileName("  ", ext: "roomdesign") == "Room.roomdesign")
    }
}

@Suite struct StudioTests {
    let catalog = FurnitureCatalog.bundled
    let room = SampleRooms.all[1].room

    func legal(_ o: LayoutOption, _ r: CanonicalRoom? = nil) -> Bool {
        LayoutSolver.check(r ?? room, o.layout, o.plan, catalog: FurnitureCatalog(entries: o.products).merged(with: catalog)).isEmpty
    }

    @Test func upToThreeDistinctLegalLayouts() async {
        let options = await DesignStudio.options(room: room, theme: "living room", catalog: catalog, reader: nil)
        #expect((1...3).contains(options.count))
        #expect(Set(options.map { $0.layout.placed.map(\.x) }).count == options.count)
        let best = options.map(\.layout.placed.count).max()!
        for o in options {
            #expect(legal(o))
            #expect(o.layout.placed.count >= best - 1)
            #expect(!o.summary.isEmpty)
        }
    }

    @Test func swapRemoveAndAddStayLegal() async throws {
        let option = await sampleOption("living room", room: room)
        let sofa = try #require(option.plan.items.first { $0.category == "sofa" })
        let alternative = try #require(DesignStudio.alternatives(for: sofa.itemID, in: option, catalog: catalog).first)
        let swapped = DesignStudio.swap(option, itemID: sofa.itemID, to: alternative, room: room, catalog: catalog)
        #expect(swapped.plan.items.first { $0.itemID == sofa.itemID }?.catalogID == alternative.catalogID)
        #expect(legal(swapped))
        let removed = DesignStudio.remove(option, itemID: sofa.itemID, room: room, catalog: catalog)
        #expect(!removed.plan.items.contains { $0.placement.targetItemID == sofa.itemID })
        #expect(legal(removed))
        let bench = try #require(catalog.entries.first { $0.category == "bench" })
        let added = try #require(DesignStudio.add(removed, entry: bench, room: room, catalog: catalog))
        #expect(added.layout.placed.contains { $0.category == "bench" })
        #expect(legal(added))
    }

    @Test func aPieceThatCannotFitIsRefused() async throws {
        let tiny = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(1, 0), Point2(1, 1), Point2(0, 1)])
        let option = LayoutOption(id: 0, plan: FurniturePlan(theme: "", items: []), layout: FurnitureLayout(placed: []), summary: "", notes: "", provider: "", products: [])
        #expect(DesignStudio.add(option, entry: try #require(catalog.entry("sample_sofa_three_oat")), room: tiny, catalog: catalog) == nil)
    }

    func editing(_ request: String, _ theme: String = "living room") async -> (DesignEditor.Result, LayoutOption) {
        let option = await sampleOption(theme, room: room)
        return (await DesignEditor.edit(option, request: request, room: room, colours: RoomColours(), catalog: catalog, reader: nil), option)
    }

    @Test func typedRemoveAndAdd() async {
        let (r, before) = await editing("remove the plant and add a bench")
        #expect(!r.option.plan.items.contains { $0.category == "plant" })
        #expect(r.option.plan.items.contains { $0.category == "bench" })
        #expect(r.report.count == 2)
        #expect(r.changed)
        #expect(before.plan.items.contains { $0.category == "plant" })
        #expect(legal(r.option))
    }

    @Test func makeItCheaperAppliesToEveryPlacedPiece() async {
        let (r, before) = await editing("Make it cheaper")
        func total(_ o: LayoutOption) -> Double { o.placedProducts.compactMap(\.price).reduce(0, +) }
        #expect(total(r.option) <= total(before))
        #expect(r.report.count == before.layout.placed.count)
        #expect(legal(r.option))
    }

    @Test func smallerMeansSmaller() async throws {
        let (r, before) = await editing("swap the sofa for a smaller one")
        func area(_ o: LayoutOption) throws -> Double {
            let e = try #require(o.products.first { p in p.catalogID == o.plan.items.first { $0.category == "sofa" }?.catalogID })
            return e.size[0] * e.size[1]
        }
        #expect(try area(r.option) < area(before))
    }

    @Test func paintChangesTheDesignNotTheRoom() async {
        let (r, _) = await editing("paint the walls sage")
        #expect(r.wallPaint?.name == "sage")
        #expect(r.report == ["Painted the walls sage."])
    }

    @Test func aMoveThatCannotWorkIsReportedAndChangesNothing() async {
        let bare = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(0, 4)])
        let option = await sampleOption("living room", room: bare)
        let r = await DesignEditor.edit(option, request: "move the sofa under the window", room: bare, colours: RoomColours(), catalog: catalog, reader: nil)
        #expect(!r.changed)
        #expect(r.report.first?.contains("no window") == true)
    }

    @Test func nonsenseGetsExamples() async {
        let (r, before) = await editing("sing me a song")
        #expect(r.report == [DesignEditor.examples])
        #expect(r.option.plan == before.plan)
    }

    @Test func aModelAnswerIsUsedAndFallsBackWhenEmpty() async {
        let option = await sampleOption("living room", room: room)
        let used = await DesignEditor.edit(option, request: "whatever", room: room, colours: RoomColours(), catalog: catalog,
                                           reader: { _, _, _ in [.paint(WallPaint.Paint("sage", "#A3AE96"))] })
        #expect(used.provider == FurniturePlanner.aiProvider && used.wallPaint?.name == "sage")
        let empty = await DesignEditor.edit(option, request: "remove the plant", room: room, colours: RoomColours(), catalog: catalog,
                                            reader: { _, _, _ in [] })
        #expect(empty.provider == FurniturePlanner.rulesProvider)
        #expect(!empty.option.plan.items.contains { $0.category == "plant" })
    }

    @Test func thePromptHoldsNoPositions() async {
        let option = await sampleOption("living room", room: room)
        let prompt = DesignEditor.prompt(option, request: "x", room: room, colours: RoomColours())
        #expect(prompt.contains("length_m"))
        #expect(!prompt.contains("rotation") && !prompt.contains("\"x\""))
    }
}

@Suite struct PaintTests {
    @Test func looksAndClashes() {
        #expect(WallPaint.looks.count == 18)
        #expect(WallPaint.suggestions(for: "cyberpunk den").map(\.name) == ["midnight navy", "blue-black", "deep purple"])
        #expect(WallPaint.suggestions(for: "somewhere to sit").isEmpty)
        #expect(WallPaint.clashes("#FF4FA8", theme: "cyberpunk den"))
        #expect(!WallPaint.clashes("#1B2236", theme: "cyberpunk den"))
        #expect(!WallPaint.clashes("#FF4FA8", theme: "somewhere to sit"))
    }

    @Test func namedPaintPrefersTheLongestName() {
        #expect(WallPaint.paint(named: "paint the walls pale blue")?.name == "pale blue")
        #expect(WallPaint.paint(named: "walls in plaid") == nil)
    }

    @Test func coloursComeFromTheMedianOfSamples() {
        let wall = (0.9, 0.9, 0.88), wood = (0.7, 0.5, 0.3)
        let c = RoomColours.estimate(walls: [wall, wall, (0.1, 0.1, 0.1)], floors: [wood, wood, wood])
        #expect(c?.wall == RoomColours.hex(r: 0.9, g: 0.9, b: 0.88))
        #expect(c?.floorType == .wood && c?.detected == true)
        #expect(RoomColours.estimate(walls: [wall], floors: [wood, wood]) == nil)
        #expect(RoomColours.estimate(walls: [wall, wall], floors: [(0.8, 0.8, 0.8), (0.8, 0.8, 0.8)])?.floorType == .tile)
        #expect(RoomColours.estimate(walls: [wall, wall], floors: [(0.3, 0.3, 0.3), (0.3, 0.3, 0.3)])?.floorType == .concrete)
    }
}
