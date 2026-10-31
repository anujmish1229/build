import Foundation

/// What to show straight after a scan.
public struct ScanReview: Equatable, Sendable {
    public struct Line: Equatable, Identifiable, Sendable {
        public let id: String
        public let kind: String
        public let a: Point2
        public let b: Point2
        public let flagged: Bool
        public let message: String?
    }

    public let summary: String
    public let lines: [Line]
    public let flags: [Line]

    public init(raw: RawRoom) {
        summary = raw.summary
        func line(_ s: RawSurface, kind: String, number: Int) -> Line {
            let c = Point2(s.centre.x, s.centre.z), d = Point2(s.xAxis.x, s.xAxis.z).normalized
            let flagged = s.confidence == .low
            return Line(id: s.id, kind: kind, a: c - d * (s.width / 2), b: c + d * (s.width / 2), flagged: flagged,
                        message: flagged ? "\(kind.capitalized) \(number) wasn't seen clearly." : nil)
        }
        lines = raw.walls.enumerated().map { line($1, kind: "wall", number: $0 + 1) }
            + raw.doors.enumerated().map { line($1, kind: "door", number: $0 + 1) }
            + raw.windows.enumerated().map { line($1, kind: "window", number: $0 + 1) }
            + raw.openings.enumerated().map { line($1, kind: "gap", number: $0 + 1) }
        flags = lines.filter(\.flagged)
    }
}
