import Foundation
import Testing
@testable import RoomScanKit

/// Checks a personal catalogue outside the repository and lays out its starter Board. Skipped unless
/// LOCAL_CATALOG names a file, so CI and other people's machines never need that file.
@Suite(.serialized) struct LocalCatalogTests {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    @Test(.enabled(if: env["LOCAL_CATALOG"] != nil))
    func aLargeCatalogueWorksThroughTheWholeChain() async throws {
        let path = try #require(Self.env["LOCAL_CATALOG"])
        let region = Self.env["LOCAL_REGION"] ?? "CA"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        let clock = ContinuousClock()
        var all: FurnitureCatalog?
        let parse = try clock.measure { all = try FurnitureCatalog(json: data) }
        let catalog = try #require(all).inRegions([region])
        print("local catalogue: \(try #require(all).entries.count) offers, \(catalog.entries.count) pieces in \(region), parsed in \(parse)")
        #expect(!catalog.entries.isEmpty)
        #expect(catalog.entries.allSatisfy { $0.region == region })

        // Every room type in every sample room gives a legal layout using these products.
        for sample in SampleRooms.all {
            for theme in ["japandi bedroom", "modern living room", "minimalist office", "scandinavian dining room"] {
                var result: FurniturePlanner.Result?
                let took = await clock.measure {
                    result = await FurniturePlanner.design(room: sample.room, theme: theme, catalog: catalog, reader: nil)
                }
                let design = try #require(result)
                #expect(!design.layout.placed.isEmpty, "\(sample.name) \(theme)")
                #expect(LayoutSolver.check(sample.room, design.layout, design.plan, catalog: catalog).isEmpty, "\(sample.name) \(theme)")
                #expect(design.plan.items.allSatisfy { $0.catalogID?.hasPrefix("ikea_") == true }, "\(theme)")
                print("local catalogue: \(sample.name), \(theme): \(design.layout.placed.count) placed in \(took)")
            }
        }

        let starter = await StarterBoard.generate(catalog: catalog)
        #expect(starter.designs.count == StarterBoard.recipes.count)
        for d in starter.designs {
            #expect(LayoutSolver.check(d.room, d.layout, d.plan, catalog: FurnitureCatalog(entries: d.products)).isEmpty, "\(d.title)")
        }
        if let out = Self.env["LOCAL_STARTER_OUT"] {
            try starter.encoded().write(to: URL(fileURLWithPath: out))
        }
    }
}
