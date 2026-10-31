import SwiftUI
import RoomScanKit

/// Enter a tape-measured length, see how it was read and what it changes, then apply or cancel (FR-R2).
struct WallLengthSheet: View {
    @ObservedObject var model: ReviewModel
    let wallID: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mode: CalibrationMode = .uniform

    private var wall: Wall? { model.room.wall(wallID) }
    private var measured: Double? { Units.parse(text, system: model.units) }
    private var preview: Result<CalibrationPreview, Error>? {
        guard let measured else { return nil }
        return Result { try RoomCalibration.preview(model.room, wallID: wallID, measured: measured, mode: mode) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("For example 3.45, 345 cm or 11 ft 4 in", text: $text)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("wallLengthField")
                    if let measured {
                        Text("Read as \(Units.readBack(measured))").font(.footnote).foregroundStyle(.secondary)
                    } else if !text.isEmpty {
                        Text("That doesn't look like a length.").font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    if let wall { Text("Measured length (now \(Units.format(wall.length, model.units)))") }
                }
                Section("How should it change?") {
                    Picker("Method", selection: $mode) {
                        Text("Scale whole plan").tag(CalibrationMode.uniform)
                        Text("Stretch this wall").tag(CalibrationMode.stretch)
                    }
                    .pickerStyle(.segmented)
                }
                previewSection
            }
            .navigationTitle("Measure this wall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let measured else { return }
                        model.perform { try $0.applyMeasurement(wallID: wallID, measured: measured, mode: mode) }
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
        }
    }

    private var canApply: Bool {
        if case .success = preview { return true }
        return false
    }

    @ViewBuilder private var previewSection: some View {
        switch preview {
        case .success(let p):
            Section("Preview") {
                if p.changes.isEmpty { Text("No walls change.").foregroundStyle(.secondary) }
                ForEach(p.changes, id: \.wallID) { change in
                    let index = (model.room.walls.firstIndex { $0.id == change.wallID } ?? 0) + 1
                    HStack {
                        Text("Wall \(index)")
                        Spacer()
                        Text("\(Units.format(change.before, model.units)) → \(Units.format(change.after, model.units))")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        case .failure(let error):
            Section { Text(error.localizedDescription).foregroundStyle(.red) }
        case nil:
            EmptyView()
        }
    }
}
