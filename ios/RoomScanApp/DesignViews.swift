import SwiftUI
import RoomScanKit

/// Enter a theme and constraints (FR-L1).
struct NewDesignForm: View {
    @Binding var theme: String
    @Binding var mustHave: String
    @Binding var leaveOut: String
    @Binding var budget: String

    static let suggestions = ["Calm japandi bedroom", "Warm boho living room", "Minimalist home office", "Scandinavian dining room", "Dark moody lounge"]

    var body: some View {
        Section("Theme") {
            TextField("For example, calm japandi bedroom", text: $theme, axis: .vertical)
                .accessibilityIdentifier("themeField")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Self.suggestions, id: \.self) { s in
                        Button(s) { theme = s }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        Section("Optional") {
            TextField("Must have, such as desk, pine bed", text: $mustHave)
            TextField("Leave out, such as wardrobe", text: $leaveOut)
            TextField("Budget, such as 2500", text: $budget)
        }
    }

    var constraints: FurnishConstraints {
        func list(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return FurnishConstraints(mustHave: list(mustHave), mustAvoid: list(leaveOut), budget: budget.isEmpty ? nil : budget)
    }
}

/// Type a theme and get a furnished plan, or reasons why pieces don't fit.
struct ThemeDesignView: View {
    let room: CanonicalRoom
    let roomName: String
    var colours: RoomColours?

    @State private var theme = ""
    @State private var mustHave = ""
    @State private var leaveOut = ""
    @State private var budget = ""
    @State private var result: FurniturePlanner.Result?
    @State private var working = false

    var body: some View {
        Form {
            NewDesignForm(theme: $theme, mustHave: $mustHave, leaveOut: $leaveOut, budget: $budget)
            Section {
                Button(action: run) {
                    HStack {
                        Text(working ? "Designing…" : "Design this room")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working)
                .accessibilityIdentifier("designButton")
            }
            if let result { DesignResultSections(room: room, plan: result.plan, layout: result.layout, notes: result.notes, provider: result.provider) }
        }
        .navigationTitle(roomName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        working = true
        let form = NewDesignForm(theme: $theme, mustHave: $mustHave, leaveOut: $leaveOut, budget: $budget)
        let (room, roomName, theme, colours, constraints) = (room, roomName, theme, colours, form.constraints)
        Task {
            let value = await Task.detached {
                await FurniturePlanner.design(room: room, theme: theme, constraints: constraints, roomName: roomName, colours: colours)
            }.value
            result = value
            working = false
        }
    }
}

struct DesignResultSections: View {
    let room: CanonicalRoom
    let plan: FurniturePlan
    let layout: FurnitureLayout
    let notes: String
    let provider: String

    var body: some View {
        Section("Your design") {
            FurnishedPlanView(room: room, layout: layout).frame(height: 280)
            if !notes.isEmpty { Text(notes).font(.footnote) }
            Text("Furniture chosen by: \(provider)").font(.caption).foregroundStyle(.secondary)
        }
        Section("Pieces (\(layout.placed.count))") {
            ForEach(layout.placed) { Text($0.name ?? $0.itemID) }
        }
        if !layout.unplaced.isEmpty {
            Section("Didn't fit") {
                ForEach(layout.unplaced) { u in
                    VStack(alignment: .leading) {
                        Text(plan.items.first { $0.itemID == u.itemID }?.name ?? u.itemID)
                        Text(u.reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
