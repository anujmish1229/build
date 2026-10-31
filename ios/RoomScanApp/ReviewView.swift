import SwiftUI
import RoomScanKit

/// Check the plan and fix errors. Optional unless an error stops a layout.
struct ReviewView: View {
    @StateObject private var model: ReviewModel
    @State private var selection: PlanSelection?
    @State private var sheet: PlanSelection?
    @State private var addType: OpeningType?

    init(model: @autoclosure @escaping () -> ReviewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        VStack(spacing: 0) {
            FloorPlanView(model: model, selection: $selection)
                .frame(height: 320)
            List {
                summary
                if !model.generalIssues.isEmpty {
                    Section("Check these") { ForEach(model.generalIssues) { IssueRow(issue: $0) } }
                }
                wallsSection
                openingsSection
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Floor plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("undoEdit")
            }
        }
        .onChange(of: selection) { value in
            if value != nil { sheet = value }
        }
        .sheet(item: $sheet, onDismiss: { selection = nil }) { item in
            switch item {
            case .wall(let id): WallLengthSheet(model: model, wallID: id)
            case .opening(let id): OpeningEditorSheet(model: model, openingID: id)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.message ?? "") }
        .confirmationDialog("Which wall?", isPresented: Binding(get: { addType != nil }, set: { if !$0 { addType = nil } }), titleVisibility: .visible) {
            ForEach(Array(model.room.walls.enumerated()), id: \.element.id) { i, wall in
                Button("Wall \(i + 1) (\(Units.format(wall.length, model.units)))") {
                    if let type = addType {
                        model.perform { try $0.addOpening(type: type, wallID: wall.id) }
                    }
                }
            }
        }
    }

    private var summary: some View {
        Section {
            LabeledContent("Floor area", value: Units.area(model.room.derived.area, model.units))
            LabeledContent("Ceiling height", value: Units.format(model.room.ceilingHeight, model.units))
            Picker("Units", selection: $model.units) {
                Text("Metric").tag(UnitSystem.metric)
                Text("Imperial").tag(UnitSystem.imperial)
            }
            .pickerStyle(.segmented)
        }
    }

    private var wallsSection: some View {
        Section("Walls: tap to measure") {
            ForEach(Array(model.room.walls.enumerated()), id: \.element.id) { i, wall in
                Button { sheet = .wall(wall.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Wall \(i + 1)", value: Units.format(wall.length, model.units))
                        ForEach(model.issues(wall: wall.id)) { IssueRow(issue: $0) }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("wallRow\(i + 1)")
            }
        }
    }

    private var openingsSection: some View {
        Section {
            ForEach(model.room.openings) { o in
                Button { sheet = .opening(o.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(o.type.plainName.capitalized + " " + o.id, value: Units.format(o.width, model.units))
                        ForEach(model.issues(opening: o.id)) { IssueRow(issue: $0) }
                    }
                }
                .foregroundStyle(.primary)
            }
            Menu {
                Button("Add a door") { addType = .door }
                Button("Add a window") { addType = .window }
                Button("Add a gap") { addType = .opening }
            } label: { Label("Add", systemImage: "plus") }
        } header: { Text("Doors and windows") }
    }
}
