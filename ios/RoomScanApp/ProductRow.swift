import RoomScanKit
import SwiftUI

/// A piece as a row: name, price, store and note. Tapping opens its product page when it has one.
struct ProductRow: View {
    let piece: FurnitureLayout.Placed
    let entry: CatalogEntry?
    @AppStorage(Prices.displayCurrencyKey) private var displayCurrency = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry?.name ?? piece.name ?? piece.itemID)
                if entry?.url != nil {
                    Spacer()
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary).accessibilityLabel("Opens the store")
                }
            }
            HStack {
                if let price = entry?.priceText { Text(price) }
                if let store = entry?.store { Text(store) }
            }
            .font(.footnote).foregroundStyle(.secondary)
            if Season.isDecoration(piece.category) { Text("Decoration").font(.footnote).foregroundStyle(.secondary) }
            if let original = entry?.originalPriceText { Text("Store price: \(original)").font(.caption).foregroundStyle(.secondary) }
            if let note = entry?.note { Text(note).font(.caption).foregroundStyle(.orange) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let url = entry?.url { openURL(url) } }
    }
}
