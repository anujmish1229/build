import Foundation

/// Prices in the store's currency or any of 34 others, converted at rates bundled with the app (FR-Z4, FR-Z5).
public enum Prices {
    /// The date of the bundled rates, from the European Central Bank's reference rates.
    public static let ratesDate = "2026-10-30"
    public static let displayCurrencyKey = "displayCurrency"

    /// Units of each currency per US dollar. AED, SAR, QAR and BHD are fixed to the dollar.
    static let perDollar: [String: Double] = [
        "USD": 1, "AUD": 1.4236, "BRL": 5.4325, "CAD": 1.3969, "CHF": 0.82295, "CNY": 6.6529, "CZK": 21.798, "DKK": 6.6895,
        "EUR": 0.89509, "GBP": 0.74633, "HKD": 7.8457, "HUF": 327.9, "IDR": 18148, "ILS": 3.1284, "INR": 94.95, "ISK": 121.73,
        "JPY": 157.25, "KRW": 1335.27, "MXN": 18.908, "MYR": 4.057, "NOK": 9.2302, "NZD": 1.7743, "PHP": 63.68, "PLN": 3.9418,
        "RON": 4.784, "SEK": 9.8264, "SGD": 1.2784, "THB": 33.73, "TRY": 49.948, "ZAR": 16.6895,
        "AED": 3.6725, "SAR": 3.75, "QAR": 3.64, "BHD": 0.376,
    ]

    /// The home region's usual currency, for adding up mixed currencies when none is chosen.
    public static var homeCurrency: String? {
        Locale(identifier: "en_" + CatalogRegion.home).currency?.identifier
    }

    public static var currencies: [String] { perDollar.keys.sorted() }

    /// The currency to show prices in; nil means each store's own.
    public static var displayCurrency: String? {
        get { UserDefaults.standard.string(forKey: displayCurrencyKey).flatMap { $0.isEmpty ? nil : $0 } }
        set { UserDefaults.standard.set(newValue ?? "", forKey: displayCurrencyKey) }
    }

    /// Nil when either currency has no bundled rate.
    public static func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        guard let a = perDollar[from], let b = perDollar[to] else { return nil }
        return amount / a * b
    }

    /// Uses the currency's own decimals and symbol.
    public static func format(_ amount: Double, currency: String?) -> String {
        guard let currency else { return String(format: "%.0f", amount) }
        return amount.formatted(.currency(code: currency).locale(Locale(identifier: "en_CA")))
    }

    /// The amount as it should be shown, and whether it was converted.
    public static func shown(_ amount: Double, currency: String?, display: String? = displayCurrency) -> (text: String, converted: Bool) {
        if let display, let currency, display != currency, let value = convert(amount, from: currency, to: display) {
            return ("≈ " + format(value, currency: display), true)
        }
        return (format(amount, currency: currency), false)
    }

    /// A total in the shown currency, else the home one. Mixed currencies with no way to add up give nil.
    public static func totalText(_ entries: [CatalogEntry], display: String? = displayCurrency, home: String? = nil) -> String? {
        let priced = entries.compactMap { e in e.price.map { (amount: $0, currency: e.currency) } }
        guard !priced.isEmpty else { return nil }
        let codes = Set(priced.compactMap(\.currency))
        let target = display ?? (codes.count == 1 ? codes.first : home ?? "USD")
        guard let target else { return format(priced.map(\.amount).reduce(0, +), currency: nil) }
        var total = 0.0
        for p in priced {
            guard let value = p.currency.map({ convert(p.amount, from: $0, to: target) }) ?? p.amount else { return nil }
            total += value
        }
        let converted = codes != [target]
        return (converted ? "≈ " : "") + format(total, currency: target)
    }
}

extension CatalogEntry {
    /// The price as shown, marked ≈ when converted.
    public var priceText: String? { price.map { Prices.shown($0, currency: currency).text } }

    /// The store's own price, for under a converted one.
    public var originalPriceText: String? {
        guard let price, Prices.shown(price, currency: currency).converted else { return nil }
        return Prices.format(price, currency: currency)
    }

    /// The price in the currency a budget is typed in.
    public var budgetPrice: Double? {
        guard let price else { return nil }
        guard let from = currency, let to = Prices.displayCurrency else { return price }
        return Prices.convert(price, from: from, to: to) ?? price
    }

    /// The price in US dollars, to compare offers in different currencies.
    var dollars: Double? {
        guard let price else { return nil }
        guard let currency else { return price }
        return Prices.convert(price, from: currency, to: "USD")
    }
}

/// Where the user is, and which regions furniture is shown from (FR-Z1 to FR-Z3).
public enum CatalogRegion {
    public static let key = "catalogRegion"
    public static let shoppingKey = "shoppingRegions"
    public static let every = "*"

    public static var home: String {
        get { UserDefaults.standard.string(forKey: key) ?? Locale.current.region?.identifier ?? "US" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The regions shown; nil is every region. Just home until others are picked.
    public static var shopping: Set<String>? {
        get {
            let raw = UserDefaults.standard.string(forKey: shoppingKey) ?? ""
            if raw == every { return nil }
            let codes = Set(raw.split(separator: ",").map(String.init))
            return codes.isEmpty ? [home] : codes
        }
        set {
            // Just home is stored as nothing, so it follows home when that changes.
            let raw = newValue.map { $0 == [home] ? "" : $0.sorted().joined(separator: ",") } ?? every
            UserDefaults.standard.set(raw, forKey: shoppingKey)
        }
    }

    public static func name(_ code: String) -> String { Locale.current.localizedString(forRegionCode: code) ?? code }

    /// Forgets the user's choices.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: shoppingKey)
    }
}

/// Keeps an imported catalogue, used from then on instead of the built-in one (FR-C2).
public struct CatalogStore: Sendable {
    public let file: URL

    public init(directory: URL) { file = directory.appendingPathComponent("furniture_catalog.json") }

    @discardableResult
    public func load() -> FurnitureCatalog? {
        let catalog = (try? Data(contentsOf: file)).flatMap { try? FurnitureCatalog(json: $0) }
        FurnitureCatalog.use(catalog)
        return catalog
    }

    /// Checks a file before keeping it, so a bad one never replaces the current catalogue (FR-C3).
    @discardableResult
    public func importData(_ data: Data) throws -> FurnitureCatalog {
        let catalog = try FurnitureCatalog(json: data)
        try ProtectedFile.write(data, to: file)
        FurnitureCatalog.use(catalog)
        return catalog
    }

    /// Goes back to the built-in catalogue.
    public func reset() {
        try? FileManager.default.removeItem(at: file)
        FurnitureCatalog.use(nil)
    }
}
