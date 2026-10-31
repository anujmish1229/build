import PoltarKit
import SwiftUI

/// A piece as a row: name, price, store and note. Tapping opens its product page, or a Google Shopping search
/// when there's no one page to open, so anything in a design can be found.
struct ProductRow: View {
    let piece: FurnitureLayout.Placed
    let entry: CatalogEntry?
    @AppStorage(Prices.displayCurrencyKey) private var displayCurrency = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry?.name ?? piece.name ?? piece.itemID)
                if let shopURL {
                    Spacer()
                    Image(systemName: shopURL == entry?.url ? "arrow.up.right.square" : "magnifyingglass.circle").foregroundStyle(.secondary)
                        .accessibilityLabel(shopURL == entry?.url ? "Opens the store" : "Searches Google Shopping")
                }
            }
            HStack {
                if let price = entry?.priceText { Text(price) }
                if let store = entry?.shopLabel ?? (shopURL == nil ? nil : "Google Shopping") { Text(store) }
            }
            .font(.footnote).foregroundStyle(.secondary)
            if entry == nil && Season.isDecoration(piece.category) { Text("Decoration").font(.footnote).foregroundStyle(.secondary) }
            if let power = entry?.propText { Text(power).font(.caption).foregroundStyle(.secondary) }
            if entry?.searchesForBuyers == true, let retailers = entry?.retailersText { Text(retailers).font(.caption).foregroundStyle(.secondary) }
            if let original = entry?.originalPriceText { Text("Store price: \(original)").font(.caption).foregroundStyle(.secondary) }
            if let note = entry?.note { Text(note).font(.caption).foregroundStyle(.orange) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let shopURL { openURL(shopURL) } }
    }

    private var shopURL: URL? {
        entry?.shopURL ?? (entry == nil && Season.isDecoration(piece.category) ? CatalogEntry.shoppingSearch(piece.name ?? piece.itemID) : nil)
    }
}
