import Foundation
import Testing
@testable import PoltarKit

/// Builds a raw scan from a floor outline, in any pose, the way RoomPlan reports walls.
enum RawBuilder {
    struct OpeningSpec { var wall: Int; var along: Double; var width: Double; var height: Double; var sill: Double; var parent = true }

    static func raw(outline: [Point2], ceiling: Double = 2.5, yaw: Double = 0.4, shift: Point2 = Point2(3, -2),
                    floorY: Double = -1.2, gap: Double = 0, doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                    lowWalls: Set<Int> = []) -> RawRoom {
        func place(_ p: Point2) -> Point2 { p.rotated(by: yaw) + shift }
        var walls: [RawSurface] = []
        for i in outline.indices {
            let a = place(outline[i]), b = place(outline[(i + 1) % outline.count])
            let c = (a + b) * 0.5, d = (b - a).normalized
            // RoomPlan's local x: Y rotation by alpha gives x axis (cos, -sin).
            let alpha = atan2(-d.z, d.x)
            walls.append(RawSurface(id: "W\(i)", category: "wall", dimensions: [a.distance(to: b) - gap, ceiling, 0],
                                    transform: MatrixFlattening.transform(yawRadians: alpha, x: c.x, y: floorY + ceiling / 2, z: c.z),
                                    confidence: lowWalls.contains(i) ? .low : .high))
        }
        func surface(_ spec: OpeningSpec, _ category: String, _ n: Int) -> RawSurface {
            let a = place(outline[spec.wall]), b = place(outline[(spec.wall + 1) % outline.count])
            let d = (b - a).normalized
            let c = a + d * (spec.along + spec.width / 2)
            let alpha = atan2(-d.z, d.x)
            return RawSurface(id: "\(category)\(n)", category: category, dimensions: [spec.width, spec.height, 0],
                              transform: MatrixFlattening.transform(yawRadians: alpha, x: c.x, y: floorY + spec.sill + spec.height / 2, z: c.z),
                              parentID: spec.parent ? "W\(spec.wall)" : nil)
        }
        return RawRoom(capturedAt: "2026-10-31T00:00:00Z", device: .init(model: "test", osVersion: "1"), walls: walls,
                       doors: doors.enumerated().map { surface($1, "door", $0) },
                       windows: windows.enumerated().map { surface($1, "window", $0) })
    }

    static let rectangle = [Point2(0, 0), Point2(4.2, 0), Point2(4.2, 3.4), Point2(0, 3.4)]
    static let lShape = [Point2(0, 0), Point2(5, 0), Point2(5, 3), Point2(2.5, 3), Point2(2.5, 5), Point2(0, 5)]
    static let alcove = [Point2(0, 0), Point2(6, 0), Point2(6, 4), Point2(4, 4), Point2(4, 4.8), Point2(2.5, 4.8), Point2(2.5, 4), Point2(0, 4)]
}

@Suite struct RoomImportTests {
    private func lengths(_ p: [Point2]) -> [Double] {
        p.indices.map { p[$0].distance(to: p[($0 + 1) % p.count]) }.sorted()
    }

    @Test(arguments: [("rectangle", RawBuilder.rectangle), ("l", RawBuilder.lShape), ("alcove", RawBuilder.alcove)])
    func threeRoomShapesImportClean(_ name: String, _ outline: [Point2]) throws {
        let raw = RawBuilder.raw(outline: outline, doors: [.init(wall: 0, along: 0.5, width: 0.9, height: 2.03, sill: 0)],
                                 windows: [.init(wall: 1, along: 0.5, width: 1.0, height: 1.2, sill: 0.9)])
        let result = try RoomImport.importRoom(raw)
        #expect(!RoomValidation.hasErrors(result.issues), "\(name): \(result.issues)")
        #expect(result.room.walls.count == outline.count)
        #expect(abs(result.room.derived.area - PlanMath.signedArea(outline)) < 0.001)
        #expect(result.room.derived.bounds.minX.magnitude < 1e-6)
        #expect(result.room.derived.bounds.minZ.magnitude < 1e-6)
        #expect(PlanMath.signedArea(result.room.floorPolygon) > 0)
        for (a, b) in zip(lengths(result.room.floorPolygon), lengths(outline)) { #expect(abs(a - b) < 0.001) }
        let door = try #require(result.room.openings.first { $0.type == .door })
        #expect(door.sill == 0 && door.swing == .unknown)
        #expect(abs(door.offset - 0.5) < 0.001 || abs((result.room.wall(door.wallID)!.length - door.offset - door.width) - 0.5) < 0.001)
        let win = try #require(result.room.openings.first { $0.type == .window })
        #expect(abs(win.sill - 0.9) < 0.001)
    }

    @Test func poseDoesNotChangeTheResult() throws {
        let a = try RoomImport.importRoom(RawBuilder.raw(outline: RawBuilder.lShape, yaw: 0.2)).room
        let b = try RoomImport.importRoom(RawBuilder.raw(outline: RawBuilder.lShape, yaw: 2.1, shift: Point2(-7, 11))).room
        #expect(a.walls.count == b.walls.count)
        for (p, q) in zip(a.floorPolygon, b.floorPolygon) { #expect(p.distance(to: q) < 0.001) }
    }

    @Test func clockwiseInputIsFixed() throws {
        let room = try RoomImport.importRoom(RawBuilder.raw(outline: RawBuilder.rectangle.reversed())).room
        #expect(PlanMath.signedArea(room.floorPolygon) > 0)
        #expect(abs(room.walls[0].length - 4.2) < 0.001)
        #expect(room.walls[0].inwardNormal.z > 0.99)
    }

    @Test func cornerGapsCloseAtLineIntersections() throws {
        let room = try RoomImport.importRoom(RawBuilder.raw(outline: RawBuilder.rectangle, gap: 0.2)).room
        #expect(abs(room.derived.area - 4.2 * 3.4) < 0.001)
    }

    @Test func collinearPiecesMerge() throws {
        let outline = [Point2(0, 0), Point2(2, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3)]
        let result = try RoomImport.importRoom(RawBuilder.raw(outline: outline))
        #expect(result.room.walls.count == 4)
        let merged = try #require(result.sourceIDs.values.first { $0.count == 2 })
        #expect(Set(merged) == ["W0", "W1"])
    }

    @Test func nearPerpendicularIsNotForcedSquare() throws {
        let outline = [Point2(0, 0), Point2(4, 0), Point2(4.1, 3), Point2(0, 3)]
        let room = try RoomImport.importRoom(RawBuilder.raw(outline: outline)).room
        #expect(abs(room.derived.area - PlanMath.signedArea(outline)) < 0.001)
    }

    @Test func tooFewWallsRefused() {
        let raw = RawBuilder.raw(outline: [Point2(0, 0), Point2(4, 0)])
        #expect(throws: RoomImportError.self) { try RoomImport.importRoom(raw) }
    }

    @Test func openLoopRefused() {
        var raw = RawBuilder.raw(outline: RawBuilder.rectangle)
        raw.walls.removeLast()
        #expect(throws: RoomImportError.notClosed) { try RoomImport.importRoom(raw) }
    }

    @Test func strayWallIsLeftOutWithAWarning() throws {
        var raw = RawBuilder.raw(outline: RawBuilder.rectangle, yaw: 0, shift: Point2(0, 0))
        raw.walls.append(RawSurface(id: "stray", category: "wall", dimensions: [0.6, 2.5, 0],
                                    transform: MatrixFlattening.transform(yawRadians: 0, x: 2, y: 0, z: 1.7)))
        let result = try RoomImport.importRoom(raw)
        #expect(result.room.walls.count == 4)
        #expect(result.issues.contains { $0.code == "extra_walls" })
    }

    @Test func openingSlidesInsideSilentlyThenWithWarning() throws {
        let small = try RoomImport.importRoom(RawBuilder.raw(outline: RawBuilder.rectangle, yaw: 0, shift: Point2(0, 0),
            doors: [.init(wall: 0, along: 3.33, width: 0.9, height: 2, sill: 0)]))
        #expect(!small.issues.contains { $0.code == "opening_moved" })
        #expect(abs(small.room.openings[0].offset - 3.3) < 0.001)
        let big = try RoomImport.importRoom(RawBuilder.raw(outline: RawBuilder.rectangle, yaw: 0, shift: Point2(0, 0),
            doors: [.init(wall: 0, along: 3.5, width: 0.9, height: 2, sill: 0)]))
        #expect(big.issues.contains { $0.code == "opening_moved" })
        #expect(abs(big.room.openings[0].offset - 3.3) < 0.001)
    }

    @Test func nearestWallUsedWithoutParent() throws {
        let room = try RoomImport.importRoom(RawBuilder.raw(outline: RawBuilder.rectangle,
            windows: [.init(wall: 2, along: 1, width: 1, height: 1, sill: 1, parent: false)])).room
        let wall = try #require(room.wall(room.openings[0].wallID))
        #expect(abs(wall.length - 4.2) < 0.001)
        #expect(wall.start.z > 3)
    }

    @Test func worstConfidenceKeptOnMerge() {
        #expect(Confidence.high.worst(.low) == .low)
        #expect(Confidence.medium.worst(.high) == .medium)
    }

    @Test func contractScanImports() throws {
        let raw = try RawRoom.decode(Fixtures.data("raw_room.example.json"))
        let result = try RoomImport.importRoom(raw)
        #expect(!RoomValidation.hasErrors(result.issues), "\(result.issues)")
        #expect(abs(result.room.derived.area - 4.12 * 3.2) < 0.001)
        #expect(result.issues.contains { $0.code == "low_confidence" })
        #expect(result.issues.contains { $0.code == "unknown_swing" })
    }

    @Test func realScansImport() throws {
        for url in Fixtures.realScans() {
            let result = try RoomImport.importRoom(RawRoom.decode(Data(contentsOf: url)))
            #expect(!RoomValidation.hasErrors(result.issues), "\(url.lastPathComponent): \(result.issues)")
        }
    }
}

@Suite struct RoomSchemaTests {
    let specExample = #"""
    {"schema_version":1,"units":"m","source":"roomplan","ceiling_height":2.46,
     "floor_polygon":[[0,0],[4.12,0],[4.12,2.9],[2.1,2.9],[2.1,3.8],[0,3.8]],
     "walls":[
      {"id":"w0","start":[0,0],"end":[4.12,0],"height":2.46,"confidence":"high"},
      {"id":"w1","start":[4.12,0],"end":[4.12,2.9],"height":2.46,"confidence":"high"},
      {"id":"w2","start":[4.12,2.9],"end":[2.1,2.9],"height":2.46,"confidence":"high"},
      {"id":"w3","start":[2.1,2.9],"end":[2.1,3.8],"height":2.46,"confidence":"high"},
      {"id":"w4","start":[2.1,3.8],"end":[0,3.8],"height":2.46,"confidence":"high"},
      {"id":"w5","start":[0,3.8],"end":[0,0],"height":2.46,"confidence":"high"}],
     "openings":[
      {"id":"d0","type":"door","wall_id":"w0","offset":0.35,"width":0.9,"height":2.03,"sill":0.0,"swing":"inward_left"},
      {"id":"win0","type":"window","wall_id":"w1","offset":0.8,"width":1.4,"height":1.2,"sill":0.9}]}
    """#

    @Test func specExampleDecodesAndValidates() throws {
        let room = try CanonicalRoom.decode(Data(specExample.utf8))
        #expect(room.walls.count == 6)
        #expect(RoomValidation.validate(room).isEmpty)
        #expect(room.opening("d0")?.swing == .inwardLeft)
        #expect(room.opening("win0")?.swing == nil)
        let expected = 4.12 * 2.9 + 2.1 * 0.9
        #expect(abs(room.derived.area - expected) < 1e-9)
    }

    @Test func derivedIsNotWrittenAndIsIgnoredOnRead() throws {
        let text = String(decoding: try CanonicalRoom.decode(Data(specExample.utf8)).encoded(), as: UTF8.self)
        #expect(!text.contains("derived"))
        let tampered = specExample.replacingOccurrences(of: "\"units\":\"m\"", with: "\"units\":\"m\",\"derived\":{\"area\":999}")
        #expect(try CanonicalRoom.decode(Data(tampered.utf8)).derived.area < 20)
    }

    @Test func roundTrip() throws {
        let room = try CanonicalRoom.decode(Data(specExample.utf8))
        #expect(try CanonicalRoom.decode(room.encoded()) == room)
    }

    @Test func newerVersionRefused() {
        let text = specExample.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":2")
        #expect(throws: (any Error).self) { try CanonicalRoom.decode(Data(text.utf8)) }
    }
}

@Suite struct ValidationTests {
    let base = CanonicalRoom.make(polygon: RawBuilder.rectangle, ceiling: 2.5)
    func codes(_ r: CanonicalRoom) -> Set<String> { Set(RoomValidation.validate(r).map(\.code)) }

    @Test func cleanRoomHasNoIssues() { #expect(RoomValidation.validate(base).isEmpty) }

    @Test func duplicateIds() {
        var r = base; r.walls[1].id = "w0"
        #expect(codes(r).contains("duplicate_id"))
    }

    @Test func crossingOutline() {
        let r = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(4, 3), Point2(4, 0), Point2(0, 3)])
        #expect(codes(r).contains("self_crossing"))
    }

    @Test func wrongOrientation() {
        let r = CanonicalRoom.make(polygon: RawBuilder.rectangle.reversed())
        #expect(codes(r).contains("bad_orientation"))
    }

    @Test func wallOffOutline() {
        var r = base; r.walls[0].end = Point2(4.3, 0)
        #expect(codes(r).contains("wall_off_outline"))
    }

    @Test func sizeLimits() {
        let tiny = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(0.4, 0), Point2(0.4, 3), Point2(0, 3)])
        #expect(codes(tiny).contains("room_too_small"))
        let huge = CanonicalRoom.make(polygon: [Point2(0, 0), Point2(60, 0), Point2(60, 3), Point2(0, 3)])
        #expect(codes(huge).contains("room_too_large"))
    }

    @Test func ceilingLevels() {
        var r = base; r.ceilingHeight = 0.9
        #expect(RoomValidation.hasErrors(RoomValidation.validate(r)))
        r.ceilingHeight = 21
        #expect(RoomValidation.hasErrors(RoomValidation.validate(r)))
        r.ceilingHeight = 1.5
        let issues = RoomValidation.validate(r)
        #expect(!RoomValidation.hasErrors(issues) && issues.contains { $0.code == "ceiling_unusual" })
        r.ceilingHeight = 7
        #expect(codes(r).contains("ceiling_unusual"))
    }

    @Test func openingChecks() {
        var r = base
        r.openings = [Opening(id: "d0", type: .door, wallID: "nope", offset: 0, width: 1, height: 2, sill: 0)]
        #expect(codes(r).contains("unknown_wall"))
        r.openings = [Opening(id: "d0", type: .door, wallID: "w0", offset: 3.9, width: 0.9, height: 2, sill: 0)]
        #expect(codes(r).contains("opening_outside_wall"))
        r.openings = [Opening(id: "win0", type: .window, wallID: "w0", offset: 0, width: 1, height: 2, sill: 1)]
        #expect(codes(r).contains("opening_above_wall"))
    }

    @Test func overlapsExceptDifferentHeights() {
        var r = base
        r.openings = [Opening(id: "d0", type: .door, wallID: "w0", offset: 1, width: 1, height: 2, sill: 0, swing: .inwardLeft),
                      Opening(id: "win0", type: .window, wallID: "w0", offset: 1.5, width: 1, height: 1, sill: 1)]
        #expect(codes(r).contains("openings_overlap"))
        r.openings[1].sill = 2.05; r.openings[1].height = 0.3
        #expect(!codes(r).contains("openings_overlap"))
    }

    @Test func levelsAndAttachment() {
        var r = base
        r.walls[2].confidence = .low
        r.openings = [Opening(id: "d0", type: .door, wallID: "w0", offset: 1, width: 1, height: 2, sill: 0)]
        let issues = RoomValidation.validate(r)
        #expect(issues.first { $0.code == "low_confidence" }?.level == .warning)
        #expect(issues.first { $0.code == "low_confidence" }?.wallID == "w2")
        #expect(issues.first { $0.code == "unknown_swing" }?.level == .info)
        #expect(issues.first { $0.code == "unknown_swing" }?.openingID == "d0")
    }

    @Test func messagesUseTheUsersUnits() {
        var r = base; r.ceilingHeight = 7
        let imperial = RoomValidation.validate(r, units: .imperial).first { $0.code == "ceiling_unusual" }
        #expect(imperial?.message.contains("ft") == true)
    }
}

@Suite struct UnitsTests {
    @Test(arguments: [
        ("3.45", 3.45), ("345 cm", 3.45), ("345cm", 3.45), ("3450 mm", 3.45), ("3.45 m", 3.45), ("3,45", 3.45),
        ("11 ft 4 in", 3.4544), ("11' 4\"", 3.4544), ("11'4\"", 3.4544), ("11 ft", 3.3528), ("4 in", 0.1016),
        ("11’ 4”", 3.4544), ("11 ft 4", 3.4544), ("3 m 45 cm", 3.45),
    ])
    func parses(_ text: String, _ metres: Double) {
        let v = Units.parse(text)
        #expect(v != nil && abs(v! - metres) < 1e-6, "\(text)")
    }

    @Test(arguments: ["", "abc", "-3", "0", "3.4.5", "12 parsecs", "3 4", "m"])
    func refuses(_ text: String) { #expect(Units.parse(text) == nil, "\(text)") }

    @Test func bareNumberFollowsUnitSystem() {
        #expect(abs(Units.parse("10", system: .imperial)! - 3.048) < 1e-9)
        #expect(Units.parse("10", system: .metric) == 10)
    }

    @Test func formats() {
        #expect(Units.format(3.45, .metric) == "3.45 m")
        #expect(Units.format(0.82, .metric) == "82 cm")
        #expect(Units.format(3.4544, .imperial) == "11 ft 4 in")
        #expect(Units.format(0.1016, .imperial) == "4 in")
        #expect(Units.format(3.6576, .imperial) == "12 ft")
        #expect(Units.readBack(3.4544) == "3.45 m (11 ft 4 in)")
    }
}
