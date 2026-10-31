import Foundation

public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric, imperial
    public static var deviceDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}

/// Reading and showing lengths. Storage is always metres.
public enum Units {
    public static let metresPerInch = 0.0254
    public static let metresPerFoot = 0.3048

    /// Reads forms such as `3.45`, `345 cm`, `11 ft 4 in`, `11' 4"`. A bare number is metres
    /// in metric and feet in imperial. Returns nil for anything unreadable or not above zero.
    public static func parse(_ text: String, system: UnitSystem = .metric) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (from, to) in [("’", "'"), ("′", "'"), ("”", "\""), ("″", "\""), (",", "."),
                           ("''", "\"")] { s = s.replacingOccurrences(of: from, with: to) }
        guard !s.isEmpty else { return nil }
        if let bare = Double(s) {
            return valid(system == .metric ? bare : bare * metresPerFoot)
        }
        let pattern = #"(\d+(?:\.\d*)?|\.\d+)\s*(millimetres|millimeters|millimetre|millimeter|mm|centimetres|centimeters|centimetre|centimeter|cm|metres|meters|metre|meter|m|feet|foot|ft|'|inches|inch|in|")?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let whole = NSRange(s.startIndex..., in: s)
        var total = 0.0
        var cursor = s.startIndex
        var matched = 0
        var lastWasFeet = false
        for m in re.matches(in: s, range: whole) {
            guard let r = Range(m.range, in: s), let numR = Range(m.range(at: 1), in: s),
                  let value = Double(s[numR]) else { return nil }
            // Only spaces (or "and") may sit between parts.
            let gap = s[cursor..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            guard gap.isEmpty || gap == "and" else { return nil }
            let unit = Range(m.range(at: 2), in: s).map { String(s[$0]) } ?? ""
            switch unit {
            case "mm", "millimetre", "millimeter", "millimetres", "millimeters": total += value / 1000
            case "cm", "centimetre", "centimeter", "centimetres", "centimeters": total += value / 100
            case "m", "metre", "meter", "metres", "meters": total += value
            case "ft", "foot", "feet", "'": total += value * metresPerFoot
            case "in", "inch", "inches", "\"": total += value * metresPerInch
            case "":
                // "11 ft 4" means 4 inches. Any other number without a unit is unreadable.
                guard lastWasFeet else { return nil }
                total += value * metresPerInch
            default: return nil
            }
            lastWasFeet = ["ft", "foot", "feet", "'"].contains(unit)
            cursor = r.upperBound
            matched += 1
        }
        guard matched > 0, s[cursor...].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return valid(total)
    }

    private static func valid(_ v: Double) -> Double? { v.isFinite && v > 0 ? v : nil }

    public static func metric(_ metres: Double) -> String {
        if abs(metres) < 1 { return "\(Int((metres * 100).rounded())) cm" }
        return String(format: "%.2f m", metres)
    }

    public static func imperial(_ metres: Double) -> String {
        var totalInches = Int((abs(metres) / metresPerInch).rounded())
        let sign = metres < 0 && totalInches > 0 ? "-" : ""
        let feet = totalInches / 12
        totalInches %= 12
        if feet == 0 { return "\(sign)\(totalInches) in" }
        return totalInches == 0 ? "\(sign)\(feet) ft" : "\(sign)\(feet) ft \(totalInches) in"
    }

    public static func format(_ metres: Double, _ system: UnitSystem) -> String {
        system == .metric ? metric(metres) : imperial(metres)
    }

    public static func area(_ squareMetres: Double, _ system: UnitSystem) -> String {
        system == .metric ? String(format: "%.1f m²", squareMetres)
                          : String(format: "%.0f sq ft", squareMetres / (metresPerFoot * metresPerFoot))
    }

    /// How an entry was read, in both systems.
    public static func readBack(_ metres: Double) -> String { "\(metric(metres)) (\(imperial(metres)))" }
}
