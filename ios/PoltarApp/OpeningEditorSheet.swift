import SwiftUI
import PoltarKit

/// Edit a door, window or gap's position and size, set swing, or delete it.
struct OpeningEditorSheet: View {
    @ObservedObject var model: ReviewModel
    let openingID: String
    @Environment(\.dismiss) private var dismiss
    @State private var position = ""
    @State private var width = ""
    @State private var height = ""
    @State private var sill = ""
    @State private var swing: DoorSwing = .unknown
    @State private var confirmDelete = false

    private var opening: Opening? { model.room.opening(openingID) }

    var body: some View {
        NavigationStack {
            CardForm {
                if let opening {
                    Section("Position from the left corner, facing the wall") {
                        field("Position", $position)
                    }
                    Section("Size") {
                        field("Width", $width)
                        field("Height", $height)
                        if opening.type != .door { field("Sill above floor", $sill) }
                    }
                    if opening.type == .door {
                        Section("Which way does it open?") {
                            Picker("Swing", selection: $swing) {
                                Text("Into the room, hinged left").tag(DoorSwing.inwardLeft)
                                Text("Into the room, hinged right").tag(DoorSwing.inwardRight)
                                Text("Out of the room, hinged left").tag(DoorSwing.outwardLeft)
                                Text("Out of the room, hinged right").tag(DoorSwing.outwardRight)
                                Text("Not sure").tag(DoorSwing.unknown)
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                    Section {
                        ForEach(model.issues(opening: openingID)) { IssueRow(issue: $0) }
                        Button("Delete this \(opening.type.plainName)", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .nightBackground()
            .navigationTitle(opening?.type.plainName.capitalized ?? "Opening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isReadable) }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this \(opening?.type.plainName ?? "opening")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.perform { try $0.deleteOpening(openingID) }
                    dismiss()
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("opening\(label)")
        }
    }

    private func load() {
        guard let o = opening else { return }
        let f: (Double) -> String = { Units.format($0, model.units) }
        position = f(o.offset); width = f(o.width); height = f(o.height); sill = f(o.sill)
        swing = o.swing ?? .unknown
    }

    private func read(_ s: String) -> Double? {
        // A zero isn't accepted by the length reader, but is a real position or sill.
        let t = s.trimmingCharacters(in: .whitespaces)
        if ["0", "0 cm", "0 m", "0 in", "0 ft"].contains(t) { return 0 }
        return Units.parse(s, system: model.units)
    }

    private var isReadable: Bool {
        read(position) != nil && read(width) != nil && read(height) != nil && (opening?.type == .door || read(sill) != nil)
    }

    private func save() {
        guard var o = opening, let p = read(position), let w = read(width), let h = read(height) else { return }
        o.offset = p; o.width = w; o.height = h
        if o.type != .door, let s = read(sill) { o.sill = s }
        if o.type == .door { o.swing = swing }
        let updated = o
        // Editing can make an opening invalid; validation shows why, and it can be fixed or undone.
        model.perform { try $0.updateOpening(updated) }
        dismiss()
    }
}

struct IssueRow: View {
    let issue: RoomIssue
    var body: some View {
        Label {
            Text(issue.message).font(.footnote)
        } icon: {
            switch issue.level {
            case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
    }
}
