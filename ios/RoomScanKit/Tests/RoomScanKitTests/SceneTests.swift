#if canImport(SceneKit)
import Foundation
import SceneKit
import Testing
@testable import RoomScanKit

@Suite struct SceneTests {
    let sample = SampleRooms.all[1]

    func layout() async -> FurnitureLayout {
        await FurniturePlanner.design(room: sample.room, theme: "living room", catalog: .bundled, reader: nil).layout
    }

    func nodes(_ scene: SCNScene, prefix: String) -> [SCNNode] {
        scene.rootNode.childNodes { node, _ in node.name?.hasPrefix(prefix) == true }
    }

    @Test func wallsMatchRoomJSONAndStandOutsideTheOutline() throws {
        let scene = RoomScene.make(sample.room, nil)
        for wall in sample.room.walls {
            let node = try #require(scene.rootNode.childNode(withName: "wall:\(wall.id)", recursively: true))
            let box = try #require(node.geometry as? SCNBox)
            #expect(abs(Double(box.width) - wall.length) < 1e-5)
            #expect(abs(Double(box.height) - wall.height) < 1e-5)
            // The inner face lies on the wall line, so the interior is exact.
            let centre = Point2(Double(node.position.x), Double(node.position.z))
            let offset = (wall.point(at: wall.length / 2) - centre).dot(wall.inwardNormal)
            #expect(abs(offset - RoomScene.wallThickness / 2) < 1e-5)
        }
    }

    @Test func furnitureIsWhereTheLayoutSays() async throws {
        let layout = await layout()
        #expect(!layout.placed.isEmpty)
        let scene = RoomScene.make(sample.room, layout, catalog: .bundled)
        for p in layout.placed {
            let holder = try #require(scene.rootNode.childNode(withName: RoomScene.itemPrefix + p.itemID, recursively: true))
            #expect(abs(Double(holder.position.x) - p.x) < 1e-5 && abs(Double(holder.position.z) - p.z) < 1e-5)
            #expect(abs(Double(holder.eulerAngles.y) - p.rotation * .pi / 180) < 1e-5)
        }
    }

    @Test func rotationSendsTheFrontTheRightWay() {
        var p = FurnitureLayout.Placed(itemID: "a", x: 1, z: 1, rotation: 90, footprint: [1, 1], height: 1)
        let node = RoomScene.furniture(p)
        let front = node.convertPosition(SCNVector3(0, 0, 1), to: nil)
        #expect(abs(Double(front.x) - 2) < 1e-4 && abs(Double(front.z) - 1) < 1e-4)
        p.rotation = 0
        #expect(abs(Double(RoomScene.furniture(p).convertPosition(SCNVector3(0, 0, 1), to: nil).z) - 2) < 1e-4)
    }

    @Test func cutawayLowersTheWalls() throws {
        let scene = RoomScene.make(sample.room, nil, cutaway: 1.1)
        for node in nodes(scene, prefix: "wall:") {
            #expect(abs(Double((node.geometry as? SCNBox)?.height ?? 0) - 1.1) < 1e-5)
        }
    }

    @Test func floorCoversTheWholeOutline() {
        let tris = RoomScene.triangulate(sample.room.floorPolygon)
        var area = 0.0
        for t in stride(from: 0, to: tris.count, by: 3) {
            area += abs(PlanMath.signedArea([sample.room.floorPolygon[tris[t]], sample.room.floorPolygon[tris[t + 1]], sample.room.floorPolygon[tris[t + 2]]]))
        }
        #expect(abs(area - sample.room.derived.area) < 1e-9)
    }

    @Test func tappedNodeLeadsBackToItsPiece() {
        let holder = RoomScene.furniture(.init(itemID: "bed", x: 0, z: 0, rotation: 0, footprint: [1, 1], height: 1))
        #expect(RoomScene.itemID(of: holder.childNodes.first) == "bed")
        #expect(RoomScene.itemID(of: SCNNode()) == nil)
    }

    @Test func usdzFileKeepsTheRoomsTrueSize() async throws {
        let layout = await layout()
        let url = try #require(RoomScene.writeUSDZ(sample.room, layout, products: FurnitureCatalog.bundled.entries))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: url).count > 1000)
        let loaded = try SCNScene(url: url, options: nil)
        let (lo, hi) = loaded.rootNode.boundingBox
        let b = sample.room.derived.bounds, t = RoomScene.wallThickness
        // Measured in the file itself: the room plus a wall's thickness on each side, within a millimetre.
        #expect(abs(Double(hi.x - lo.x) - (b.width + 2 * t)) < 0.001)
        #expect(abs(Double(hi.z - lo.z) - (b.depth + 2 * t)) < 0.001)
        #expect(abs(Double(hi.y - lo.y) - sample.room.ceilingHeight) < 0.001)
    }
}
#endif
