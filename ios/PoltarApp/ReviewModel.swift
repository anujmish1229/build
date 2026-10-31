import SwiftUI
import PoltarKit

/// Holds a room being reviewed: undo, validation and saving as edits are made.
@MainActor
final class ReviewModel: ObservableObject {
    @Published private(set) var editable: EditableRoom
    @Published private(set) var issues: [RoomIssue] = []
    @Published var units: UnitSystem { didSet { revalidate() } }
    @Published var message: String?
    private var undoStack: [EditableRoom] = []
    private let onSave: (EditableRoom) throws -> Void

    init(editable: EditableRoom, units: UnitSystem = .deviceDefault, onSave: @escaping (EditableRoom) throws -> Void) {
        self.editable = editable
        self.units = units
        self.onSave = onSave
        revalidate()
    }

    var room: CanonicalRoom { editable.room }
    var canUndo: Bool { !undoStack.isEmpty }
    var hasErrors: Bool { RoomValidation.hasErrors(issues) }
    func issues(wall id: String) -> [RoomIssue] { issues.filter { $0.wallID == id && $0.openingID == nil } }
    func issues(opening id: String) -> [RoomIssue] { issues.filter { $0.openingID == id } }
    var generalIssues: [RoomIssue] { issues.filter { $0.wallID == nil && $0.openingID == nil } }

    private func revalidate() { issues = RoomValidation.validate(editable.room, units: units) }

    private func commit() {
        revalidate()
        do { try onSave(editable) } catch { message = "Couldn't save your change: \(error.localizedDescription)" }
    }

    /// Runs one edit as one undo step.
    func perform(_ edit: (inout EditableRoom) throws -> Void) {
        var copy = editable
        do {
            try edit(&copy)
            guard copy != editable else { return }
            undoStack.append(editable)
            editable = copy
            commit()
        } catch {
            message = error.localizedDescription
        }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        editable = last
        commit()
    }

    // A corner drag is one undo step: begin, many updates, end.
    func beginDrag() { undoStack.append(editable) }
    func drag(corner: Int, to p: Point2) {
        editable.moveCorner(corner, to: p)
        revalidate()
    }
    func endDrag() {
        editable.normalise()
        commit()
    }
}
