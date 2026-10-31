import Foundation
import Testing
@testable import PoltarKit

private func door(_ id: String = "d0", wall: String = "w0", offset: Double = 1) -> Opening {
    Opening(id: id, type: .door, wallID: wall, offset: offset, width: 0.9, height: 2.03, sill: 0)
}
private func rect(w: Double = 4, d: Double = 3, _ openings: [Opening] = []) -> CanonicalRoom {
    .make(polygon: [Point2(0, 0), Point2(w, 0), Point2(w, d), Point2(0, d)], openings: openings)
}

@Suite struct CalibrationTests {
    @Test func uniformMatchesExactlyAndScalesOthers() throws {
        let room = rect([door()])
        let p = try RoomCalibration.preview(room, wallID: "w0", measured: 4.4, mode: .uniform)
        #expect(abs(p.room.wall("w0")!.length - 4.4) < 1e-9)
        #expect(abs(p.room.wall("w1")!.length - 3.3) < 1e-9)
        #expect(abs(p.room.opening("d0")!.offset - 1.1) < 1e-9)
        #expect(p.changes.count == 4)
        #expect(RoomValidation.validate(p.room).filter { $0.level == .error }.isEmpty)
    }

    @Test func stretchChangesOnlyThatDirection() throws {
        let p = try RoomCalibration.preview(rect([door("d0", wall: "w2", offset: 0.5)]), wallID: "w0", measured: 4.5, mode: .stretch)
        #expect(abs(p.room.wall("w0")!.length - 4.5) < 1e-9)
        #expect(abs(p.room.wall("w2")!.length - 4.5) < 1e-9)
        #expect(abs(p.room.wall("w1")!.length - 3) < 1e-9)
        // The door on the opposite wall stays where it was on the fixed side.
        #expect(abs(p.room.opening("d0")!.offset - 1.0) < 1e-9)
        #expect(!RoomValidation.hasErrors(RoomValidation.validate(p.room)))
    }

    @Test func stretchOfASlantedWallIsExact() throws {
        let room = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(4, 0), Point2(4.5, 3), Point2(0, 3)])
        let p = try RoomCalibration.preview(room, wallID: "w1", measured: 3.3, mode: .stretch)
        #expect(abs(p.room.wall("w1")!.length - 3.3) < 1e-9)
    }

    @Test func extremeFactorsRefused() {
        #expect(throws: CalibrationError.self) { try RoomCalibration.preview(rect(), wallID: "w0", measured: 1.9, mode: .uniform) }
        #expect(throws: CalibrationError.self) { try RoomCalibration.preview(rect(), wallID: "w0", measured: 8.1, mode: .stretch) }
        #expect(throws: CalibrationError.self) { try RoomCalibration.preview(rect(), wallID: "nope", measured: 4, mode: .stretch) }
        #expect(throws: CalibrationError.self) { try RoomCalibration.preview(rect(), wallID: "w0", measured: 0, mode: .stretch) }
    }

    @Test func boundaryFactorsAllowed() throws {
        _ = try RoomCalibration.preview(rect(), wallID: "w0", measured: 2, mode: .uniform)
        _ = try RoomCalibration.preview(rect(), wallID: "w0", measured: 8, mode: .uniform)
    }
}

@Suite struct EditingTests {
    @Test func cornerSnapsToNeighbours() {
        var e = EditableRoom(room: rect())
        e.moveCorner(2, to: Point2(4.03, 3.5))
        #expect(e.room.floorPolygon[2] == Point2(4, 3.5))
        #expect(e.room.walls[1].end == Point2(4, 3.5))
        #expect(e.room.walls[2].start == Point2(4, 3.5))
        #expect(e.corrections.cornersMoved)
        #expect(!RoomValidation.hasErrors(RoomValidation.validate(e.room)))
    }

    @Test func movingACornerKeepsOpeningsInPlace() {
        var e = EditableRoom(room: rect([door("d0", wall: "w1", offset: 1)]))
        // Corner 1 starts wall w1; the door keeps its place relative to the far end.
        e.moveCorner(1, to: Point2(4, -0.5))
        #expect(abs(e.room.opening("d0")!.offset - 1.5) < 1e-9)
    }

    @Test func movedCornerDropsThatWallsMeasurement() throws {
        var e = EditableRoom(room: rect())
        try e.applyMeasurement(wallID: "w0", measured: 4.1, mode: .stretch)
        e.moveCorner(1, to: Point2(4.5, 0))
        #expect(e.corrections.measuredWalls.isEmpty)
    }

    @Test func normaliseRestoresOrigin() {
        var e = EditableRoom(room: rect())
        e.moveCorner(0, to: Point2(-1, -1))
        e.normalise()
        let b = PlanMath.bounds(e.room.floorPolygon)
        #expect(b.minX == 0 && b.minZ == 0)
        #expect(e.room.walls[0].start == e.room.floorPolygon[0])
    }

    @Test func addUsesDefaultsCentred() throws {
        var e = EditableRoom(room: rect())
        let d = try e.addOpening(type: .door, wallID: "w0")
        #expect(d.width == 0.82 && d.height == 2.03 && d.sill == 0 && d.swing == .unknown)
        #expect(abs(d.offset - (4 - 0.82) / 2) < 1e-9)
        let w = try e.addOpening(type: .window, wallID: "w1")
        #expect(w.width == 1 && w.height == 1.2 && w.sill == 0.9 && w.swing == nil)
        let g = try e.addOpening(type: .opening, wallID: "w2")
        #expect(g.width == 0.9 && g.id == "op0")
    }

    @Test func tooShortWallRefused() {
        var e = EditableRoom(room: .make(polygon: [Point2(0, 0), Point2(0.6, 0), Point2(0.6, 3), Point2(0, 3)]))
        #expect(throws: RoomEditError.wallTooShort) { try e.addOpening(type: .door, wallID: "w0") }
    }

    @Test func deletedIdsAreNeverReused() throws {
        var e = EditableRoom(room: rect([door()]))
        try e.deleteOpening("d0")
        let next = try e.addOpening(type: .door, wallID: "w0")
        #expect(next.id == "d1")
        try e.deleteOpening("d1")
        #expect(e.nextOpeningID(.door) == "d2")
        #expect(e.corrections.addedOpenings.isEmpty)
    }

    @Test func unknownOpeningThrows() {
        var e = EditableRoom(room: rect())
        #expect(throws: RoomEditError.unknownOpening) { try e.deleteOpening("zz") }
        #expect(throws: RoomEditError.unknownOpening) { try e.setSwing("zz", .inwardLeft) }
    }
}

@Suite struct MergeTests {
    func scan(_ openings: [Opening]) -> CanonicalRoom { rect(openings) }
    func scan(_ w: Double, _ d: Double, _ openings: [Opening]) -> CanonicalRoom { rect(w: w, d: d, openings) }

    @Test func correctionsSurviveARescan() throws {
        let window = Opening(id: "win0", type: .window, wallID: "w1", offset: 1, width: 1, height: 1.2, sill: 0.9)
        var e = EditableRoom(room: scan([door(), window]))
        try e.applyMeasurement(wallID: "w0", measured: 4.05, mode: .uniform)
        try e.setSwing("d0", .inwardLeft)
        let added = try e.addOpening(type: .opening, wallID: "w2")
        try e.deleteOpening("win0")

        // A new scan with small differences.
        let fresh = scan(4.02, 3.01, [door(offset: 1.03), Opening(id: "win0", type: .window, wallID: "w1", offset: 1.02, width: 1, height: 1.2, sill: 0.9)])
        let (out, report) = RoomMerge.merge(previous: e, rescan: fresh)

        #expect(abs(out.room.wall("w0")!.length - 4.05) < 1e-9)
        #expect(out.room.opening("d0")?.swing == .inwardLeft)
        #expect(out.room.opening("win0") == nil)
        #expect(out.room.opening(added.id)?.type == .opening)
        #expect(report.kept.count == 4)
        #expect(report.notKept.isEmpty)

        // And a second rescan keeps them too.
        let (again, _) = RoomMerge.merge(previous: out, rescan: fresh)
        #expect(abs(again.room.wall("w0")!.length - 4.05) < 1e-9)
        #expect(again.room.opening("d0")?.swing == .inwardLeft)
        #expect(again.room.opening("win0") == nil)
        #expect(again.room.opening(added.id) != nil)
        #expect(again.nextOpeningID(.window) == "win1")
    }

    @Test func draggedCornersAreNotCarriedAndTheAppSaysSo() {
        var e = EditableRoom(room: scan([]))
        e.moveCorner(2, to: Point2(5, 3))
        let (out, report) = RoomMerge.merge(previous: e, rescan: scan([]))
        #expect(out.room.floorPolygon[2] == Point2(4, 3))
        #expect(report.notKept == [RoomMerge.cornersNotice])
        #expect(!out.corrections.cornersMoved)
    }

    @Test func rescanInAnotherLoopOrderStillMaps() throws {
        var e = EditableRoom(room: scan(4, 3, [door("d0", wall: "w0", offset: 1)]))
        try e.setSwing("d0", .outwardRight)
        // The same room, loop rotated by two walls: the door is now on w2.
        let fresh = scan(4, 3, [door("d7", wall: "w2", offset: 1)])
        let (out, _) = RoomMerge.merge(previous: e, rescan: fresh)
        #expect(out.room.opening("d7")?.swing == .outwardRight)
    }

    @Test func missingOpeningIsReported() throws {
        var e = EditableRoom(room: scan([door()]))
        try e.setSwing("d0", .inwardLeft)
        let (_, report) = RoomMerge.merge(previous: e, rescan: scan([]))
        #expect(report.notKept.count == 1)
    }

    @Test func farAwayMeasurementIsNotApplied() throws {
        var e = EditableRoom(room: scan([]))
        try e.applyMeasurement(wallID: "w0", measured: 4.2, mode: .stretch)
        let (out, report) = RoomMerge.merge(previous: e, rescan: scan(9, 8, []))
        #expect(abs(out.room.wall("w0")!.length - 9) < 1e-9)
        #expect(report.notKept.count == 1)
    }
}

@Suite struct GeometryTests {
    let wall = Wall(id: "w0", start: Point2(0, 0), end: Point2(4, 0), height: 2.5)

    @Test func keepClearDepthFollowsSwing() {
        func depth(_ s: DoorSwing) -> Double {
            PlanGeometry.keepClearZone(Opening(id: "d", type: .door, wallID: "w0", offset: 1, width: 0.9, height: 2, sill: 0, swing: s), wall: wall).halfV * 2
        }
        #expect(depth(.unknown) == 0.9)
        #expect(depth(.inwardLeft) == 0.9)
        #expect(depth(.outwardRight) == 0.6)
        let gap = Opening(id: "o", type: .opening, wallID: "w0", offset: 1, width: 1.2, height: 2, sill: 0)
        #expect(PlanGeometry.keepClearZone(gap, wall: wall).halfV * 2 == 0.6)
    }

    @Test func zoneExtendsIntoTheRoom() {
        let z = PlanGeometry.keepClearZone(Opening(id: "d", type: .door, wallID: "w0", offset: 1, width: 1, height: 2, sill: 0), wall: wall)
        #expect(z.contains(Point2(1.5, 0.5)))
        #expect(!z.contains(Point2(1.5, -0.5)))
    }

    @Test func doorLeaf() {
        let o = Opening(id: "d", type: .door, wallID: "w0", offset: 1, width: 1, height: 2, sill: 0, swing: .inwardLeft)
        let leaf = PlanGeometry.doorLeaf(o, wall: wall)!
        #expect(leaf.hinge == Point2(1, 0) && leaf.openEnd == Point2(1, 1) && leaf.closedEnd == Point2(2, 0))
        var out = o; out.swing = .outwardRight
        let leaf2 = PlanGeometry.doorLeaf(out, wall: wall)!
        #expect(leaf2.hinge == Point2(2, 0) && leaf2.openEnd == Point2(2, -1))
        var unknown = o; unknown.swing = .unknown
        #expect(PlanGeometry.doorLeaf(unknown, wall: wall) == nil)
    }

    @Test func overlapsIgnoresTouchingEdges() {
        let a = OrientedRect(centre: Point2(0, 0), width: 2, depth: 2, rotation: 0)
        #expect(!a.overlaps(OrientedRect(centre: Point2(2, 0), width: 2, depth: 2, rotation: 0)))
        #expect(a.overlaps(OrientedRect(centre: Point2(1.9, 0), width: 2, depth: 2, rotation: 0)))
        #expect(a.overlaps(OrientedRect(centre: Point2(2.2, 0), width: 2, depth: 2, rotation: 45)))
        #expect(!a.overlaps(OrientedRect(centre: Point2(3, 0), width: 2, depth: 2, rotation: 45)))
    }

    @Test func rotationConvention() {
        let r = OrientedRect(centre: Point2(0, 0), width: 2, depth: 1, rotation: 90)
        // At 90 degrees the front (local +z) faces +x.
        #expect(abs(r.v.x - 1) < 1e-9 && abs(r.v.z) < 1e-9)
    }

    @Test func fitRoundTrips() {
        let fit = PlanFit(bounds: Bounds(minX: 0, minZ: 0, maxX: 4, maxZ: 3), width: 400, height: 300)
        let s = fit.screen(Point2(1, 2))
        let p = fit.plan(x: s.x, y: s.y)
        #expect(p.distance(to: Point2(1, 2)) < 1e-9)
    }
}

@Suite struct StoreTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("room.json")
    }

    @Test func saveAndLoad() throws {
        let store = RoomStore(url: tempURL())
        #expect(try store.load() == nil)
        var e = EditableRoom(room: rect([door()]))
        try e.setSwing("d0", .inwardRight)
        try store.save(StoredRoom(editable: e))
        #expect(try store.load()?.editable == e)
        let values = try store.url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func damagedFileIsKept() throws {
        let store = RoomStore(url: tempURL())
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        #expect(throws: RoomStore.LoadError.self) { try store.load() }
        let files = try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path)
        #expect(files.contains { $0.contains("damaged") })
    }

    @Test func samplesAreValid() {
        for s in SampleRooms.all {
            #expect(!RoomValidation.hasErrors(RoomValidation.validate(s.room)), "\(s.name): \(RoomValidation.validate(s.room))")
        }
    }

    @Test func scanReviewFlagsLowConfidence() throws {
        let raw = try RawRoom.decode(Fixtures.data("raw_room.example.json"))
        let review = ScanReview(raw: raw)
        #expect(review.summary == "4 walls, 1 door, 1 window")
        #expect(review.flags.map(\.id) == ["W-D"])
        #expect(review.flags[0].message == "Wall 4 wasn't seen clearly.")
    }
}
