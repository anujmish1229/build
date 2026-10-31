import RoomScanKit
import SwiftUI
import UniformTypeIdentifiers

/// Units, region and prices, catalogue, board feed and data deletion (FR-T1).
struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("unitSystem") private var units = UnitSystem.deviceDefault.rawValue
    @AppStorage(Prices.displayCurrencyKey) private var currency = ""
    @AppStorage("feedAddress") private var feedAddress = ""
    @State private var home = CatalogRegion.home
    @State private var everyRegion = CatalogRegion.shopping == nil
    @State private var regions = CatalogRegion.shopping ?? []
    @State private var confirmDelete = false
    @State private var importing = false

    private var catalogRegions: [String] {
        Array(Set(FurnitureCatalog.all.regions + [home])).sorted { CatalogRegion.name($0) < CatalogRegion.name($1) }
    }

    var body: some View {
        CardForm {
            Section("Units") {
                Picker("Units", selection: $units) {
                    Text("Metric").tag(UnitSystem.metric.rawValue)
                    Text("Imperial").tag(UnitSystem.imperial.rawValue)
                }
                .pickerStyle(.segmented)
            }
            Section("Region") {
                Picker("You are in", selection: $home) {
                    ForEach(catalogRegions, id: \.self) { Text(CatalogRegion.name($0)).tag($0) }
                }
                .onChange(of: home) { value in
                    CatalogRegion.home = value
                    regions.insert(value)
                    saveRegions()
                }
                Toggle("Show furniture from every region", isOn: $everyRegion)
                    .onChange(of: everyRegion) { _ in saveRegions() }
                if !everyRegion, FurnitureCatalog.all.regions.count > 1 {
                    ForEach(catalogRegions, id: \.self) { code in
                        Toggle(CatalogRegion.name(code), isOn: Binding(get: { regions.contains(code) }, set: { on in
                            if on { regions.insert(code) } else { regions.remove(code) }
                            saveRegions()
                        }))
                    }
                }
                if let note = fallbackNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Picker("Show prices in", selection: $currency) {
                    Text("Each store's currency").tag("")
                    ForEach(Prices.currencies, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Prices")
            } footer: {
                Text("Conversions are approximate, using rates from \(Prices.ratesDate). A converted price is marked ≈.")
            }
            Section {
                LabeledContent("Pieces", value: "\(FurnitureCatalog.all.entries.count)")
                Button("Open a catalogue file") { importing = true }
                if app.hasImportedCatalogue {
                    Button("Stop using the opened catalogue") { app.resetCatalogue() }
                }
            } header: {
                Text("Catalogue")
            } footer: {
                Text(FurnitureCatalog.all.isSamples
                    ? "The built-in pieces are invented samples with typical sizes and prices, not real products. Open a catalogue file to use real ones."
                    : "From a catalogue snapshot, for personal use. Prices and sizes may have changed, so the store's page is the source of truth.")
            }
            Section {
                TextField("https://example.com/board-feed.json", text: $feedAddress)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Refresh the feed") { Task { await app.refreshFeed(feedAddress) } }
                    .disabled(feedAddress.isEmpty)
                if let url = app.feedExportFile() {
                    ShareLink("Export my designs as a feed", item: url)
                }
            } header: {
                Text("Board feed")
            } footer: {
                Text("A feed is the only thing this app downloads. Publishing a feed shares your rooms' floor plans.")
            }
            Section {
                Button("Delete everything", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("deleteEverything")
            } footer: {
                Text("Removes all rooms, designs, boards and scans, the imported catalogue, the downloaded feed and these settings.")
            }
        }
        .nightBackground()
        .navigationTitle("Settings")
        .confirmationDialog("Delete everything on this device?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                app.deleteEverything()
                units = UnitSystem.deviceDefault.rawValue
                currency = ""
                feedAddress = ""
                home = CatalogRegion.home
                everyRegion = false
                regions = []
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { app.open(url) }
        }
    }

    private var fallbackNote: String? {
        let all = FurnitureCatalog.all
        guard !everyRegion, !all.regions.isEmpty else { return nil }
        let chosen = regions.isEmpty ? [home] : regions
        guard chosen.isDisjoint(with: all.regions) else { return nil }
        let used = all.regions.contains("US") ? "US" : all.regions[0]
        return "There's no furniture for your regions yet, so \(CatalogRegion.name(used))'s is shown."
    }

    private func saveRegions() {
        CatalogRegion.shopping = everyRegion ? nil : (regions.isEmpty ? [home] : regions)
        app.objectWillChange.send()
    }
}
