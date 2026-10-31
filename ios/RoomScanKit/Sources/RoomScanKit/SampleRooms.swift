import Foundation

/// Three rooms for trying the app without LiDAR.
public enum SampleRooms {
    public struct Sample: Sendable {
        public let name: String
        public let room: CanonicalRoom
    }

    public static var all: [Sample] {
        [
            Sample(name: "Sample bedroom", room: .make(
                polygon: [Point2(0, 0), Point2(4.2, 0), Point2(4.2, 3.6), Point2(0, 3.6)], ceiling: 2.5,
                openings: [
                    Opening(id: "d0", type: .door, wallID: "w3", offset: 0.3, width: 0.82, height: 2.03, sill: 0, swing: .inwardRight),
                    Opening(id: "win0", type: .window, wallID: "w2", offset: 1.5, width: 1.2, height: 1.2, sill: 0.9),
                ])),
            Sample(name: "Sample living room", room: .make(
                polygon: [Point2(0, 0), Point2(6, 0), Point2(6, 4.4), Point2(4.2, 4.4), Point2(4.2, 5.2), Point2(2.6, 5.2), Point2(2.6, 4.4), Point2(0, 4.4)], ceiling: 2.7,
                openings: [
                    Opening(id: "d0", type: .door, wallID: "w7", offset: 2.8, width: 0.9, height: 2.03, sill: 0, swing: .inwardLeft),
                    Opening(id: "win0", type: .window, wallID: "w1", offset: 1.2, width: 2.0, height: 1.4, sill: 0.7),
                    Opening(id: "win1", type: .window, wallID: "w4", offset: 0.3, width: 1.0, height: 1.2, sill: 0.9),
                ])),
            Sample(name: "Sample studio", room: .make(
                polygon: [Point2(0, 0), Point2(6.5, 0), Point2(6.5, 3.5), Point2(3.5, 3.5), Point2(3.5, 6), Point2(0, 6)], ceiling: 2.6,
                openings: [
                    Opening(id: "d0", type: .door, wallID: "w5", offset: 0.4, width: 0.9, height: 2.03, sill: 0, swing: .unknown),
                    Opening(id: "win0", type: .window, wallID: "w1", offset: 1.1, width: 1.4, height: 1.3, sill: 0.8),
                    Opening(id: "win1", type: .window, wallID: "w4", offset: 1.0, width: 1.5, height: 1.3, sill: 0.8),
                ])),
        ]
    }
}
