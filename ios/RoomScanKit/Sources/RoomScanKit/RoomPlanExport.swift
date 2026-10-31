#if canImport(RoomPlan)
import Foundation
import RoomPlan

/// Converts RoomPlan's result to `RawRoom` straight away. `room.objects` is never read (FR-S4).
@available(iOS 16.0, *)
public enum RoomPlanExport {
    public static func rawRoom(from room: CapturedRoom, capturedAt: Date = Date()) -> RawRoom {
        RawRoom(capturedAt: ISO8601DateFormatter().string(from: capturedAt),
                device: DeviceInfo.current(),
                walls: room.walls.map(surface),
                doors: room.doors.map(surface),
                windows: room.windows.map(surface),
                openings: room.openings.map(surface))
    }

    static func surface(_ s: CapturedRoom.Surface) -> RawSurface {
        var parent: String?
        if #available(iOS 17.0, *) { parent = s.parentIdentifier?.uuidString }
        return RawSurface(id: s.identifier.uuidString,
                          category: category(s.category),
                          dimensions: [Double(s.dimensions.x), Double(s.dimensions.y), Double(s.dimensions.z)],
                          transform: MatrixFlattening.flatten(s.transform),
                          confidence: confidence(s.confidence),
                          parentID: parent)
    }

    static func category(_ c: CapturedRoom.Surface.Category) -> String {
        switch c {
        case .wall: return "wall"
        case .door: return "door"
        case .window: return "window"
        case .opening: return "opening"
        default: return "other"
        }
    }

    static func confidence(_ c: CapturedRoom.Confidence) -> Confidence {
        switch c {
        case .high: return .high
        case .medium: return .medium
        default: return .low
        }
    }
}
#endif
