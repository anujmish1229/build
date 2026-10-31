import Foundation
import Testing
@testable import PoltarKit

enum Fixtures {
    static var root: URL { Bundle.module.resourceURL!.appendingPathComponent("Fixtures") }
    static func data(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(name)) }
    static func realScans() -> [URL] {
        let dir = root.appendingPathComponent("real")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }
}

@Suite struct CaptureTests {
    @Test func contractExampleRoundTrips() throws {
        let raw = try RawRoom.decode(Fixtures.data("raw_room.example.json"))
        #expect(raw.walls.count == 4)
        #expect(raw.summary == "4 walls, 1 door, 1 window")
        #expect(try RawRoom.decode(raw.encoded()) == raw)
    }

    @Test func detectedFurnitureIsDropped() throws {
        var json = try JSONSerialization.jsonObject(with: Fixtures.data("raw_room.example.json")) as! [String: Any]
        json["objects"] = [["id": "sofa", "category": "sofa"]]
        let raw = try RawRoom.decode(JSONSerialization.data(withJSONObject: json))
        let out = try JSONSerialization.jsonObject(with: raw.encoded()) as! [String: Any]
        #expect(out["objects"] == nil)
        #expect(!String(decoding: try raw.encoded(), as: UTF8.self).contains("sofa"))
    }

    @Test func realScansHaveNoFurniture() throws {
        for url in Fixtures.realScans() {
            let data = try Data(contentsOf: url)
            let raw = try RawRoom.decode(data)
            #expect(raw.hasEnoughWalls, "\(url.lastPathComponent)")
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            #expect(json["objects"] == nil, "\(url.lastPathComponent) holds detected furniture")
        }
    }

    @Test func newerVersionIsRefused() throws {
        var json = try JSONSerialization.jsonObject(with: Fixtures.data("raw_room.example.json")) as! [String: Any]
        json["schema_version"] = 99
        #expect(throws: (any Error).self) { try RawRoom.decode(JSONSerialization.data(withJSONObject: json)) }
    }

    @Test func malformedTransformIsRefused() throws {
        var json = try JSONSerialization.jsonObject(with: Fixtures.data("raw_room.example.json")) as! [String: Any]
        var walls = json["walls"] as! [[String: Any]]
        walls[0]["transform"] = [1.0, 2.0]
        json["walls"] = walls
        #expect(throws: (any Error).self) { try RawRoom.decode(JSONSerialization.data(withJSONObject: json)) }
    }

    @Test func tooFewWallsFlagged() {
        let raw = RawRoom(capturedAt: "x", device: .init(model: "m", osVersion: "o"), walls: [])
        #expect(!raw.hasEnoughWalls)
    }

    @Test func flatteningIsColumnMajor() {
        let t = MatrixFlattening.transform(yawRadians: 0, x: 1, y: 2, z: 3)
        let s = RawSurface(id: "a", category: "wall", dimensions: [1, 1, 0], transform: t)
        #expect(s.centre.x == 1 && s.centre.y == 2 && s.centre.z == 3)
        #expect(s.xAxis.x == 1 && s.xAxis.z == 0)
    }

    @Test func deviceInfoHasNoName() {
        let d = DeviceInfo.current()
        #expect(!d.model.isEmpty)
        #expect(!d.osVersion.isEmpty)
    }
}
