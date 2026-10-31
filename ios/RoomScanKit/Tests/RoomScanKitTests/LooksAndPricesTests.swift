#if canImport(SceneKit)
import CoreGraphics
import Foundation
import Metal
import SceneKit
import Testing
@testable import RoomScanKit

@Suite struct ShapeTests {
    /// The world bounds of every part of a piece.
    func bounds(_ node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
        var lo = SCNVector3(1e6, 1e6, 1e6), hi = SCNVector3(-1e6, -1e6, -1e6)
        node.enumerateHierarchy { part, _ in
            guard part.geometry != nil else { return }
            let (a, b) = part.boundingBox
            for p in [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z)] {
                let w = part.convertPosition(p, to: node)
                lo = SCNVector3(min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))
                hi = SCNVector3(max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z))
            }
        }
        return (lo, hi)
    }

    static let styles = ["", "japandi", "scandinavian", "mid-century", "modern", "boho", "minimalist", "warm", "dark", "steampunk", "gothic", "deco", "industrial", "cyberpunk"]

    @Test(arguments: styles)
    func everyProductInEveryStyleStaysInsideItsSize(_ style: String) {
        let design = DesignStyle(words: style.isEmpty ? [] : [style])
        for entry in FurnitureCatalog.bundled.entries {
            let placed = FurnitureLayout.Placed(itemID: "x", x: 0, z: 0, rotation: 0, footprint: [entry.size[0], entry.size[1]], category: entry.category, height: entry.size[2])
            let node = RoomScene.furniture(placed, entry: entry, style: design)
            let (lo, hi) = bounds(node)
            let tol = 0.012
            #expect(Double(lo.y) > -tol, "\(entry.name) goes below the floor")
            #expect(Double(hi.y) < entry.size[2] + tol, "\(entry.name) is too tall: \(hi.y) over \(entry.size[2])")
            #expect(Double(hi.x - lo.x) < entry.size[0] + tol, "\(entry.name) is too wide")
            #expect(Double(hi.z - lo.z) < entry.size[1] + tol, "\(entry.name) is too deep")
            // Each is really a shape, not just a box.
            #expect(node.childNodes.count >= 2, "\(entry.name)")
        }
    }

    @Test(arguments: ["christmas", "halloween"])
    func decorationsStayInsideTheirSize(_ season: String) async throws {
        let style = DesignStyle(words: [season])
        let room = SampleRooms.all[3].room
        let plan = FurniturePlanner.plan(brief: DesignBrief(roomType: "living"), room: room, theme: season).plan
        for item in plan.items where Season.isDecoration(item.category) {
            let placed = FurnitureLayout.Placed(itemID: "x", x: 0, z: 0, rotation: 0, footprint: [item.size[0], item.size[1]], category: item.category, height: item.size[2])
            let node = RoomScene.furniture(placed, style: style)
            let (lo, hi) = bounds(node)
            let tol = 0.03
            #expect(Double(lo.y) > -tol, "\(item.name) goes below the floor: \(lo.y)")
            #expect(Double(hi.y) < item.size[2] + tol, "\(item.name) is too tall: \(hi.y) over \(item.size[2])")
            #expect(Double(hi.x - lo.x) < item.size[0] + tol, "\(item.name) is too wide: \(hi.x - lo.x) over \(item.size[0])")
            #expect(Double(hi.z - lo.z) < item.size[1] + tol, "\(item.name) is too deep: \(hi.z - lo.z) over \(item.size[1])")
        }
    }

    /// A picture is made, and isn't blank.
    func distinctColours(_ image: CGImage) -> Int {
        let width = 48, height = 60
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var seen = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4) {
            seen.insert(UInt32(pixels[i] / 16) << 8 | UInt32(pixels[i + 1] / 16) << 4 | UInt32(pixels[i + 2] / 16))
        }
        return seen.count
    }

    @Test(arguments: ["japandi", "dark", "steampunk", "boho", "minimalist"])
    func eachStyleRenders(_ style: String) throws {
        let design = StarterBoard.load()[2]
        let scene = RoomScene.snapshot(design.room, design.layout, colours: design.colours, products: design.products, style: DesignStyle(words: [style]), size: CGSize(width: 240, height: 300))
        // A machine with no graphics device, such as some hosted CI runners, can't render.
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let image = try #require(scene)
        #expect(distinctColours(image) > 8, "\(style) came out blank")
    }

    @Test func differentStylesLookDifferent() {
        let entry = FurnitureCatalog.bundled.entry("sample_side_table_brass")
        let sofa = FurnitureCatalog.bundled.entry("sample_sofa_two_charcoal")
        let japandi = ResolvedLook(entry: nil, name: "Plain sofa", category: "sofa", style: DesignStyle(words: ["japandi"]))
        let gothic = ResolvedLook(entry: nil, name: "Plain sofa", category: "sofa", style: DesignStyle(words: ["gothic"]))
        #expect(japandi.upholstery != gothic.upholstery)
        #expect(japandi.bedding != gothic.bedding || japandi.accent != gothic.accent)
        // The product's own name beats the look.
        #expect(ResolvedLook(entry: sofa, name: "", category: "sofa", style: DesignStyle(words: ["japandi"])).upholstery == Finishes.table["charcoal"])
        #expect(ResolvedLook(entry: entry, name: "", category: "side_table", style: nil).body == Finishes.table["brass"])
    }

    @Test func productDataBeatsTheName() throws {
        let data = #"{"catalog_id":"a","name":"White thing","category":"desk","size":[1,1,1],"look":{"body":"walnut","form":"round"}}"#
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: Data(data.utf8))
        let look = ResolvedLook(entry: entry, name: "", category: "desk", style: nil)
        #expect(look.body == Finishes.table["walnut"] && look.rounded)
    }

    @Test func themeWordsBecomeAStyle() {
        let style = DesignStyle(theme: "steampunk study in brass and burgundy")
        #expect(style.words == ["steampunk"])
        #expect(style.materials == ["brass"])
        #expect(style.accents == ["burgundy"])
    }
}

@Suite(.serialized) struct PriceTests {
    @Test func thereAre34Currencies() {
        #expect(Prices.currencies.count == 34)
    }

    @Test func conversionGoesThroughTheDollar() throws {
        #expect(Prices.convert(100, from: "CAD", to: "CAD") == 100)
        let usd = try #require(Prices.convert(139.69, from: "CAD", to: "USD"))
        #expect(abs(usd - 100) < 1e-9)
        #expect(Prices.convert(1, from: "CAD", to: "XXX") == nil)
    }

    @Test func currenciesUseTheirOwnDecimals() {
        #expect(!Prices.format(1000, currency: "JPY").contains("."))
        #expect(Prices.format(1000, currency: "CAD").contains(".00"))
    }

    @Test func aConvertedPriceIsMarked() {
        let same = Prices.shown(100, currency: "CAD", display: "CAD")
        #expect(!same.converted && !same.text.contains("≈"))
        let other = Prices.shown(100, currency: "CAD", display: "EUR")
        #expect(other.converted && other.text.hasPrefix("≈"))
        #expect(!Prices.shown(100, currency: "CAD", display: nil).converted)
    }

    @Test func mixedCurrenciesAddUpInTheShownOne() {
        func item(_ price: Double, _ currency: String) -> CatalogEntry {
            CatalogEntry(catalogID: UUID().uuidString, name: "", category: "bed", size: [1, 1, 1], price: price, currency: currency)
        }
        let total = Prices.totalText([item(100, "CAD"), item(100, "USD")], display: "USD", home: nil)
        #expect(total?.hasPrefix("≈") == true && total?.contains("171.59") == true)
        #expect(Prices.totalText([item(100, "CAD"), item(50, "CAD")], display: nil) == Prices.format(150, currency: "CAD"))
        #expect(Prices.totalText([]) == nil)
    }
}

@Suite struct RegionTests {
    let file = #"""
    {"catalog_version":3,"updated":"2026-10-30",
     "regions":{"CA":{"currency":"CAD","store":"Shop CA"},"US":{"currency":"USD","store":"Shop US"},"JP":{"currency":"JPY","store":"Shop JP"}},
     "items":[
      {"catalog_id":"a","name":"A","category":"bed","size":[1,2,1],"offers":{"CA":[300,"https://example.com/ca"],"US":[100,"https://example.com/us"]}},
      {"catalog_id":"b","name":"B","category":"sofa","size":[2,1,1],"offers":{"JP":[10000,"javascript:bad"]}}]}
    """#

    @Test func aMultiRegionFileBecomesOneEntryPerRegion() throws {
        let c = try FurnitureCatalog(json: Data(file.utf8))
        #expect(c.entries.count == 3)
        #expect(c.regions == ["CA", "JP", "US"])
        let ca = try #require(c.inRegions(["CA"]).entry("a"))
        #expect(ca.price == 300 && ca.currency == "CAD" && ca.store == "Shop CA")
        #expect(c.inRegions(["JP"]).entry("b")?.url == nil)
    }

    @Test func aPieceSoldInSeveralIsShownAtItsCheapest() throws {
        let c = try FurnitureCatalog(json: Data(file.utf8))
        #expect(c.inRegions(["CA", "US"]).entry("a")?.currency == "USD")
        #expect(c.inRegions(nil).entries.count == 2)
    }

    @Test func regionsWithNothingFallBackToTheUS() throws {
        let c = try FurnitureCatalog(json: Data(file.utf8))
        #expect(c.inRegions(["FR"]).entries.allSatisfy { $0.region == "US" })
    }

    @Test func duplicatesWithinARegionAreRefused() {
        let dup = #"{"regions":{"CA":{"currency":"CAD"}},"items":[{"catalog_id":"a","name":"A","category":"bed","size":[1,1,1],"offers":{"CA":[1,"https://x.com"]}},{"catalog_id":"a","name":"A","category":"bed","size":[1,1,1],"offers":{"CA":[2,"https://x.com"]}}]}"#
        #expect(throws: CatalogError.self) { try FurnitureCatalog(json: Data(dup.utf8)) }
    }

    @Test(.serialized) func importingKeepsTheFileAndABadOneChangesNothing() throws {
        let store = CatalogStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { store.reset() }
        try store.importData(Data(file.utf8))
        #expect(FurnitureCatalog.all.regions == ["CA", "JP", "US"])
        #expect(throws: CatalogError.self) { try store.importData(Data("nope".utf8)) }
        #expect(FurnitureCatalog.all.regions == ["CA", "JP", "US"])
        #expect(store.load() != nil)
        store.reset()
        #expect(FurnitureCatalog.all.entries.first?.catalogID.hasPrefix("sample_") == true)
    }
}
#endif
