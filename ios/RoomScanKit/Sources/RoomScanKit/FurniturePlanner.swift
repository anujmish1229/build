import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What the user typed alongside the theme (FR-L1).
public struct FurnishConstraints: Codable, Sendable, Equatable {
    public var mustHave: [String]
    public var mustAvoid: [String]
    public var budget: String?

    public init(mustHave: [String] = [], mustAvoid: [String] = [], budget: String? = nil) {
        self.mustHave = mustHave; self.mustAvoid = mustAvoid; self.budget = budget
    }

    /// The first number in the text (FR-L8).
    public var budgetAmount: Double? {
        guard let digits = budget?.replacingOccurrences(of: ",", with: ""),
              let range = digits.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(digits[range])
    }
}

/// A reading of the theme: words only. It has no field that could hold a position, so whatever
/// reads the theme can't place furniture (FR-L4).
public struct DesignBrief: Codable, Sendable, Equatable {
    public var roomType: String?
    public var styleWords: [String]
    public var wanted: [String]
    public var avoided: [String]
    public var materials: [String]
    public var accents: [String]
    public var note: String

    public init(roomType: String? = nil, styleWords: [String] = [], wanted: [String] = [], avoided: [String] = [],
                materials: [String] = [], accents: [String] = [], note: String = "") {
        self.roomType = roomType; self.styleWords = styleWords; self.wanted = wanted; self.avoided = avoided
        self.materials = materials; self.accents = accents; self.note = note
    }
}

/// The main wall, the wall facing it, and the others longest first (7.5).
public struct WallRoles: Sendable, Equatable {
    public let main: String
    public let opposite: String
    public let sides: [String]
    public let windows: [String]

    public init(_ room: CanonicalRoom, anchor: String? = nil) {
        var walls = room.walls.filter { $0.length > 0.3 }.sorted { $0.length > $1.length }
        if let anchor, let i = walls.firstIndex(where: { $0.id == anchor }) { walls.insert(walls.remove(at: i), at: 0) }
        windows = room.openings.filter { $0.type == .window }.map(\.id)
        guard let first = walls.first else {
            main = room.walls.first?.id ?? "w0"; opposite = main; sides = []
            return
        }
        let n = first.inwardNormal
        let facing = walls.dropFirst().min { $0.inwardNormal.dot(n) < $1.inwardNormal.dot(n) } ?? first
        main = first.id
        opposite = facing.id
        sides = walls.map(\.id).filter { $0 != first.id && $0 != facing.id }
    }

    public var firstSide: String { sides.first ?? opposite }
    public var secondSide: String { sides.dropFirst().first ?? firstSide }
}

/// Chooses furniture for a theme (4.4). The rules work alone; Apple Intelligence, where available, only
/// reads the theme into a brief. Either way the rules choose catalogue pieces and the solver places them.
public enum FurniturePlanner {
    public static let aiProvider = "Apple Intelligence (on this phone)"
    public static let rulesProvider = "Built-in rules"
    public static let roomTypes = ["bedroom", "living", "office", "dining"]
    public static let styles = ["christmas", "halloween", "japandi", "scandinavian", "mid-century", "modern", "boho", "minimalist", "warm", "dark"]
    public static let furnitureCategories = ["bed", "nightstand", "desk", "chair", "wardrobe", "dresser", "bookshelf", "storage", "sofa",
                                             "armchair", "coffee_table", "tv_stand", "side_table", "lamp", "plant", "dining_table", "bench"]
    /// The Halloween props it can decorate with.
    public static let propCategories = ["jack_o_lantern", "tombstone", "skeleton", "ghost", "reaper", "groundbreaker", "cauldron",
                                        "candelabra", "cobweb", "spider", "coffin", "tree", "fence", "fog_machine", "prop_light",
                                        "poster", "neon_sign", "string_lights", "led_strip", "projector", "curio", "gore"]
    /// Everything it can place.
    public static let categories = furnitureCategories + propCategories
    public static let materialNames = ["oak", "walnut", "pine", "ash", "brass", "steel", "leather", "linen", "velvet", "rattan", "marble", "concrete", "wool"]
    public static let accentNames = ["sage", "terracotta", "navy", "mustard", "blush", "charcoal", "cream", "emerald", "burgundy", "teal", "black", "white"]

    public struct Result: Sendable {
        public let plan: FurniturePlan
        public let layout: FurnitureLayout
        public let notes: String
        public let provider: String
        public let brief: DesignBrief
    }

    /// Anything that can read a theme into a brief, returning nil when it can't.
    public typealias BriefReader = @Sendable (_ prompt: String) async -> DesignBrief?

    // MARK: Words

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && $0 != "-" }.map(String.init))
    }

    static let kindWords: [String: [String]] = [
        "bed": ["bed", "beds"], "nightstand": ["nightstand", "nightstands", "bedside"], "desk": ["desk"], "chair": ["chair", "chairs"],
        "wardrobe": ["wardrobe", "closet"], "dresser": ["dresser", "drawers"], "bookshelf": ["bookshelf", "bookcase", "shelf", "shelves"],
        "storage": ["storage", "cabinet", "sideboard"], "sofa": ["sofa", "couch"], "armchair": ["armchair"],
        "coffee_table": ["coffee"], "tv_stand": ["tv", "television", "media"], "side_table": ["side"], "lamp": ["lamp", "light"],
        "plant": ["plant", "plants"], "dining_table": ["dining"], "bench": ["bench"],
        "fireplace": ["fireplace"],
        // Halloween props and wall decor. "light" and "lamp" stay with lamp, so these claim only their own words.
        "skeleton": ["skeleton", "skeletons", "bones", "skelly"], "reaper": ["reaper", "witch", "scarecrow", "grim", "figure"],
        "ghost": ["ghost", "ghosts", "spirit", "phantom", "wraith"], "groundbreaker": ["zombie", "zombies", "groundbreaker", "corpse"],
        "tombstone": ["tombstone", "tombstones", "headstone", "gravestone", "grave", "graves"], "cauldron": ["cauldron", "cauldrons"],
        "jack_o_lantern": ["pumpkin", "pumpkins", "lantern", "jack"], "fog_machine": ["fog", "fogger", "smoke", "mist"],
        "prop_light": ["floodlight", "spotlight", "uplight", "flame", "strobe"], "gore": ["gore", "blood", "bloody", "severed", "limb"],
        "spider": ["spider", "spiders", "tarantula"], "cobweb": ["cobweb", "cobwebs", "web", "webs", "bat", "bats"],
        "coffin": ["coffin", "coffins", "casket", "sarcophagus"], "candelabra": ["candelabra", "candle", "candles", "chandelier"],
        "curio": ["skull", "skulls", "raven", "crow", "potion", "potions"], "fence": ["fence", "fencing", "railing"],
        "tree": ["tree", "trees", "branches"], "poster": ["poster", "posters", "print", "prints", "artwork", "picture", "pictures"],
        "neon_sign": ["neon", "sign", "signs", "signage"], "string_lights": ["string", "strings", "fairy", "twinkle", "garland", "lights"],
        "led_strip": ["led", "leds", "strip", "strips", "rgb"], "projector": ["projector", "projectors", "projection", "projected"],
    ]

    /// The kind of piece some words name. Specific kinds first: "bedside table" is a nightstand, not a table.
    public static func kind(of words: Set<String>) -> String? {
        let order = ["nightstand", "coffee_table", "side_table", "dining_table", "tv_stand", "armchair", "bookshelf",
                     "neon_sign", "led_strip", "string_lights"] + kindWords.keys.sorted()
        return order.first { !words.isDisjoint(with: kindWords[$0] ?? []) }
    }

    static func roomKind(of words: Set<String>) -> String? {
        func mentions(_ list: [String]) -> Bool { !words.isDisjoint(with: list) }
        if mentions(["bed", "bedroom", "sleep", "sleeping", "guest", "nursery"]) { return "bedroom" }
        if mentions(["office", "study", "desk", "work", "workspace"]) { return "office" }
        if mentions(["dining", "dinner", "eat", "kitchen"]) { return "dining" }
        if mentions(["living", "lounge", "sofa", "tv", "family"]) { return "living" }
        return nil
    }

    // MARK: Reading the theme

    /// The rules' reading of a theme. The room type comes from the theme, else the must-haves,
    /// else the room's name, else its area; a wanted bed always makes it a bedroom (FR-L5).
    public static func rulesBrief(theme: String, constraints: FurnishConstraints = .init(), roomName: String? = nil, area: Double) -> DesignBrief {
        let themeWords = words(theme)
        let mustWords = words(constraints.mustHave.joined(separator: " "))
        var type = roomKind(of: themeWords) ?? roomKind(of: mustWords) ?? roomKind(of: words(roomName ?? ""))
        if type == nil { type = area < 12 ? "bedroom" : "living" }
        if constraints.mustHave.contains(where: { kind(of: words($0)) == "bed" }) { type = "bedroom" }
        let aliases: [String: String] = ["midcentury": "mid-century", "scandi": "scandinavian", "nordic": "scandinavian", "cozy": "warm",
                                         "cosy": "warm", "minimal": "minimalist", "contemporary": "modern", "moody": "dark", "bohemian": "boho",
                                         "xmas": "christmas", "festive": "christmas", "spooky": "halloween", "haunted": "halloween"]
        var style = styles.filter { themeWords.contains($0) }
        for (alias, word) in aliases.sorted(by: { $0.key < $1.key }) where themeWords.contains(alias) && !style.contains(word) {
            style.append(word)
        }
        return DesignBrief(roomType: type, styleWords: style,
                           materials: materialNames.filter { themeWords.contains($0) }.prefix(3).map { $0 },
                           accents: accentNames.filter { themeWords.contains($0) }.prefix(3).map { $0 })
    }

    /// What the model is told. It holds no coordinates of any kind, and asks for none.
    public static func prompt(room: CanonicalRoom, theme: String, constraints: FurnishConstraints, colours: RoomColours?) -> String {
        var out = "Theme: \(theme.isEmpty ? "comfortable and practical" : theme)\nThe room is \(String(format: "%.1f", room.derived.area)) m²."
        if let colours { out += "\nThe walls are \(colours.wallName) and the floor is \(colours.floorName). Choose words that suit them." }
        if !constraints.mustHave.isEmpty { out += "\nMust include: \(constraints.mustHave.joined(separator: ", "))" }
        if !constraints.mustAvoid.isEmpty { out += "\nLeave out: \(constraints.mustAvoid.joined(separator: ", "))" }
        if let budget = constraints.budget, !budget.isEmpty { out += "\nBudget: \(budget)" }
        return out
    }

    /// Only what the app knows survives from a model's answer: unknown kinds, rooms and materials are dropped.
    public static func sanitised(_ brief: DesignBrief) -> DesignBrief {
        let known = Set(categories), wanted = brief.wanted.filter(known.contains).prefix(4).map { $0 }
        return DesignBrief(roomType: brief.roomType.flatMap { roomTypes.contains($0) ? $0 : nil },
                           styleWords: brief.styleWords.map { $0.lowercased() },
                           wanted: wanted,
                           avoided: brief.avoided.filter { known.contains($0) && !wanted.contains($0) }.prefix(4).map { $0 },
                           materials: brief.materials.filter(materialNames.contains).prefix(3).map { $0 },
                           accents: brief.accents.filter(accentNames.contains).prefix(3).map { $0 },
                           note: brief.note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Reads the theme, using the reader when it gives an answer and the rules otherwise (FR-L3).
    public static func readBrief(room: CanonicalRoom, theme: String, constraints: FurnishConstraints = .init(), roomName: String? = nil,
                                 colours: RoomColours? = nil, reader: BriefReader? = systemReader) async -> (brief: DesignBrief, provider: String) {
        let rules = rulesBrief(theme: theme, constraints: constraints, roomName: roomName, area: room.derived.area)
        guard let reader, let answer = await reader(prompt(room: room, theme: theme, constraints: constraints, colours: colours)) else {
            return (rules, rulesProvider)
        }
        var brief = sanitised(answer)
        if brief.roomType == nil { brief.roomType = rules.roomType }
        // The user's own words always win over the model's reading.
        if constraints.mustHave.contains(where: { kind(of: words($0)) == "bed" }) { brief.roomType = "bedroom" }
        return (brief, aiProvider)
    }

    /// The on-device model when it can be used right now; nil means rules only.
    public static var systemReader: BriefReader? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), SystemLanguageModel.default.availability == .available {
            return { prompt in await AIBriefReader.read(prompt) }
        }
        #endif
        return nil
    }

    // MARK: Choosing pieces

    /// Scores a product by style words in common, materials named, and budget (FR-L6, FR-L8).
    static func bestEntry(_ category: String, brief: DesignBrief, catalog: FurnitureCatalog, budget: Double?, nameWords: Set<String> = [], headroom: Double = .infinity) -> CatalogEntry? {
        let wanted = Set(brief.styleWords)
        func score(_ e: CatalogEntry) -> Double {
            var s = Double(Set(e.styles.map { $0.lowercased() }).intersection(wanted).count)
            let name = words(e.name)
            s += 0.5 * Double(name.intersection(Set(brief.materials + brief.accents)).count)
            s += 3 * Double(name.intersection(nameWords).count)
            if let budget, let price = e.budgetPrice { s -= 2 * price / max(budget, 1) }
            return s
        }
        // Ties keep catalogue order, so the same input always gives the same plan.
        var best: (CatalogEntry, Double)?
        for e in catalog.entries where e.category == category && (e.size.count > 2 ? e.size[2] : 0) <= headroom {
            let value = score(e)
            if best == nil || value > best!.1 + 1e-9 { best = (e, value) }
        }
        return best?.0
    }

    struct Slot {
        let id: String
        let category: String
        let rule: PlacementRule
        let priority: Int
        /// Set for a decoration that isn't a catalogue product, so it never counts towards the price.
        var prop: Season.Prop? = nil
    }

    /// Priority of a piece that only dresses the room: left out quietly if there's no space for it.
    static let extraPriority = 5

    /// The pieces for a room type (7.5). A bigger room gets a second seating or storage area as extras.
    static func slots(_ type: String, roles r: WallRoles, area: Double, askedForDesk: Bool) -> [Slot] {
        switch type {
        case "bedroom":
            var list = [
                Slot(id: "bed", category: "bed", rule: .againstWall(wallID: r.main, align: "center"), priority: 1),
                Slot(id: "nightstand_left", category: "nightstand", rule: .beside(targetItemID: "bed", side: "left", gap: 0.05), priority: 2),
                Slot(id: "nightstand_right", category: "nightstand", rule: .beside(targetItemID: "bed", side: "right", gap: 0.05), priority: 2),
                Slot(id: "wardrobe", category: "wardrobe", rule: .againstWall(wallID: r.opposite, align: "center"), priority: 2),
                Slot(id: "dresser", category: "dresser", rule: .againstWall(wallID: r.firstSide, align: "center"), priority: 3),
            ]
            if askedForDesk || area > 12 {
                list.append(Slot(id: "desk", category: "desk", rule: .corner(wallID: r.secondSide, corner: "start"), priority: 3))
                list.append(Slot(id: "chair", category: "chair", rule: .inFrontOf(targetItemID: "desk", gap: 0.1), priority: extraPriority))
            }
            list.append(Slot(id: "plant", category: "plant", rule: .corner(wallID: r.main, corner: "end"), priority: 4))
            list.append(Slot(id: "bench", category: "bench", rule: .inFrontOf(targetItemID: "bed", gap: 0.03), priority: extraPriority))
            list.append(Slot(id: "lamp", category: "lamp", rule: .corner(wallID: r.main, corner: "start"), priority: extraPriority))
            return list
        case "office":
            let lounge = area > 24 ? [
                Slot(id: "work_table", category: "dining_table", rule: .centeredInRoom, priority: extraPriority),
                Slot(id: "coffee_table", category: "coffee_table", rule: .inFrontOf(targetItemID: "armchair", gap: 0.3), priority: extraPriority),
            ] : []
            return lounge + [
                Slot(id: "desk", category: "desk", rule: .againstWall(wallID: r.main, align: "center"), priority: 1),
                Slot(id: "chair", category: "chair", rule: .inFrontOf(targetItemID: "desk", gap: 0.1), priority: 1),
                Slot(id: "bookshelf", category: "bookshelf", rule: .againstWall(wallID: r.opposite, align: "center"), priority: 2),
                Slot(id: "storage", category: "storage", rule: .againstWall(wallID: r.firstSide, align: "center"), priority: 2),
                Slot(id: "armchair", category: "armchair", rule: .corner(wallID: r.secondSide, corner: "start"), priority: 3),
                Slot(id: "lamp", category: "lamp", rule: .beside(targetItemID: "desk", side: "left", gap: 0.05), priority: 3),
                Slot(id: "plant", category: "plant", rule: .corner(wallID: r.main, corner: "end"), priority: 4),
                Slot(id: "side_table", category: "side_table", rule: .beside(targetItemID: "armchair", side: "right", gap: 0.05), priority: extraPriority),
                Slot(id: "bookshelf_2", category: "bookshelf", rule: .beside(targetItemID: "bookshelf", side: "left", gap: 0.02), priority: extraPriority),
                Slot(id: "bookshelf_3", category: "bookshelf", rule: .beside(targetItemID: "bookshelf", side: "right", gap: 0.02), priority: extraPriority),
                Slot(id: "bench", category: "bench", rule: .againstWall(wallID: r.opposite, align: "start"), priority: extraPriority),
            ]
        case "dining":
            let lounge = area > 24 ? [
                Slot(id: "coffee_table", category: "coffee_table", rule: .inFrontOf(targetItemID: "armchair", gap: 0.3), priority: extraPriority),
                Slot(id: "dresser", category: "dresser", rule: .againstWall(wallID: r.secondSide, align: "center"), priority: extraPriority),
            ] : []
            return lounge + [
                Slot(id: "dining_table", category: "dining_table", rule: .centeredInRoom, priority: 1),
                Slot(id: "storage", category: "storage", rule: .againstWall(wallID: r.main, align: "center"), priority: 2),
                Slot(id: "bench", category: "bench", rule: .againstWall(wallID: r.firstSide, align: "center"), priority: 3),
                Slot(id: "plant", category: "plant", rule: .corner(wallID: r.main, corner: "end"), priority: 4),
                Slot(id: "bookshelf", category: "bookshelf", rule: .againstWall(wallID: r.opposite, align: "center"), priority: extraPriority),
                Slot(id: "armchair", category: "armchair", rule: .corner(wallID: r.secondSide, corner: "start"), priority: extraPriority),
                Slot(id: "side_table", category: "side_table", rule: .beside(targetItemID: "armchair", side: "right", gap: 0.05), priority: extraPriority),
                Slot(id: "lamp", category: "lamp", rule: .beside(targetItemID: "armchair", side: "left", gap: 0.05), priority: extraPriority),
            ]
        default:
            return [
                Slot(id: "sofa", category: "sofa", rule: .againstWall(wallID: r.main, align: "center"), priority: 1),
                Slot(id: "tv_stand", category: "tv_stand", rule: .againstWall(wallID: r.opposite, align: "center"), priority: 1),
                Slot(id: "coffee_table", category: "coffee_table", rule: .inFrontOf(targetItemID: "sofa", gap: 0.4), priority: 2),
                Slot(id: "armchair", category: "armchair", rule: .corner(wallID: r.firstSide, corner: "start"), priority: 2),
                Slot(id: "side_table", category: "side_table", rule: .beside(targetItemID: "sofa", side: "left", gap: 0.05), priority: 3),
                Slot(id: "lamp", category: "lamp", rule: .beside(targetItemID: "sofa", side: "right", gap: 0.05), priority: 3),
                Slot(id: "bookshelf", category: "bookshelf", rule: .againstWall(wallID: r.firstSide, align: "end"), priority: 3),
                Slot(id: "plant", category: "plant", rule: .corner(wallID: r.main, corner: "end"), priority: 4),
                Slot(id: "armchair_2", category: "armchair", rule: .corner(wallID: r.firstSide, corner: "end"), priority: extraPriority),
                Slot(id: "storage", category: "storage", rule: .againstWall(wallID: r.secondSide, align: "center"), priority: extraPriority),
                Slot(id: "bench", category: "bench", rule: .againstWall(wallID: r.opposite, align: "start"), priority: extraPriority),
            ]
        }
    }

    /// The plan for a brief, with the main piece on `anchorWall` (nil is the longest wall).
    public static func plan(brief: DesignBrief, room: CanonicalRoom, theme: String, constraints: FurnishConstraints = .init(),
                            catalog: FurnitureCatalog = .current, anchorWall: String? = nil) -> (plan: FurniturePlan, notes: [String]) {
        let roles = WallRoles(room, anchor: anchorWall)
        let type = brief.roomType ?? "living"
        let budget = constraints.budgetAmount
        var notes: [String] = []
        let musts = constraints.mustHave.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let mustKinds = musts.map { (text: $0, words: words($0), kind: kind(of: words($0))) }
        let askedForDesk = mustKinds.contains { $0.kind == "desk" } || brief.wanted.contains("desk")
        var list = slots(type, roles: roles, area: room.derived.area, askedForDesk: askedForDesk)
        // A holiday theme, however the brief was read, changes what goes in the room and sets its look.
        var brief = brief
        let season = Season.of(words(theme).union(words(brief.styleWords.joined(separator: " "))))
        if let season {
            list = season.slots(list, type: type, roles: roles, area: room.derived.area, themeWords: words(theme))
            brief.styleWords.removeAll { $0 == season.rawValue }
            brief.styleWords.insert(season.rawValue, at: 0)
        }

        // Must-haves replace the plan's piece of that kind, or add one (FR-L7).
        var nameWordsByKind: [String: Set<String>] = [:]
        for must in mustKinds {
            guard let kind = must.kind else {
                notes.append("We don't have anything matching “\(must.text)”.")
                continue
            }
            nameWordsByKind[kind, default: []].formUnion(must.words.subtracting(kindWords[kind] ?? []))
        }
        let extras = mustKinds.compactMap(\.kind) + brief.wanted
        for kind in extras where !list.contains(where: { $0.category == kind }) {
            let rule: PlacementRule
            if ["lamp", "side_table", "nightstand"].contains(kind), let main = list.first {
                rule = .beside(targetItemID: main.id, side: "left", gap: 0.05)
            } else {
                rule = .againstWall(wallID: roles.secondSide, align: "center")
            }
            list.append(Slot(id: kind, category: kind, rule: rule, priority: 2))
        }

        // Leave-outs remove the piece and anything placed relative to it, unless it's also a must-have.
        var removed = Set<String>()
        for text in constraints.mustAvoid + brief.avoided {
            let found = categories.contains(text) ? text : kind(of: words(text))
            guard let found, !mustKinds.contains(where: { $0.kind == found }) else { continue }
            removed.formUnion(list.filter { $0.category == found }.map(\.id))
        }
        var changed = true
        while changed {
            changed = false
            for slot in list where !removed.contains(slot.id) {
                if let target = slot.rule.targetItemID, removed.contains(target) {
                    removed.insert(slot.id)
                    changed = true
                }
            }
        }
        list.removeAll { removed.contains($0.id) }

        var items: [FurnitureItem] = []
        var missing = Set<String>()
        for slot in list {
            if let prop = slot.prop {
                items.append(FurnitureItem(itemID: slot.id, name: prop.name, category: slot.category, size: prop.size,
                                           style: brief.styleWords.joined(separator: " "), placement: slot.rule, priority: slot.priority))
                continue
            }
            let wanted = nameWordsByKind[slot.category] ?? []
            // Nothing taller than the room, so the 12-ft lawn skeleton only turns up where there's headroom for it.
            // A prop's styles name the kind of haunt it suits, so the theme's own words can pick it.
            var reading = brief
            if Season.isProp(slot.category) { reading.styleWords += words(theme) }
            let headroom = room.ceilingHeight > 1.8 ? room.ceilingHeight - 0.05 : Double.infinity
            guard let entry = bestEntry(slot.category, brief: reading, catalog: catalog, budget: budget, nameWords: wanted.union(season?.preferredFinishes ?? []), headroom: headroom) else {
                // A decoration the catalogue doesn't have is simply left out.
                if Season.isProp(slot.category) && slot.priority >= extraPriority { continue }
                if missing.insert(slot.category).inserted { notes.append("The catalogue has no \(slot.category.replacingOccurrences(of: "_", with: " ")).") }
                continue
            }
            if !wanted.isEmpty, words(entry.name).isDisjoint(with: wanted) {
                notes.append("Nothing called “\(wanted.sorted().joined(separator: " "))” is in the catalogue, so \(entry.name) is used.")
            }
            // Something the user asked for is never just an extra.
            let priority = mustKinds.contains { $0.kind == slot.category } ? min(slot.priority, 3) : slot.priority
            items.append(FurnitureItem(itemID: slot.id, catalogID: entry.catalogID, name: entry.name, category: entry.category,
                                       size: entry.size, style: brief.styleWords.joined(separator: " "), placement: slot.rule, priority: priority))
        }
        // A piece whose target wasn't in the catalogue can't be placed either.
        let ids = Set(items.map(\.itemID))
        items.removeAll { $0.placement.targetItemID.map { !ids.contains($0) } ?? false }
        let style = DesignStyle(words: brief.styleWords, materials: brief.materials, accents: brief.accents)
        return (FurniturePlan(theme: theme, items: items, style: style), notes)
    }

    /// Places the plan; for each misfit, tries the closest piece of the same kind in a similar style at
    /// least 15% smaller by footprint. The retry is kept only if more pieces fit (FR-L10).
    public static func fitted(_ plan: FurniturePlan, room: CanonicalRoom, catalog: FurnitureCatalog = .current)
        -> (plan: FurniturePlan, layout: FurnitureLayout, swaps: [String]) {
        let result = fittedWithExtras(plan, room: room, catalog: catalog)
        // Extras are a bonus: one that doesn't fit is simply not in the design, and isn't reported as a problem.
        let extras = Set(result.plan.items.filter { $0.priority >= extraPriority }.map(\.itemID))
        let dropped = Set(result.layout.unplaced.map(\.itemID)).intersection(extras)
        guard !dropped.isEmpty else { return result }
        var kept = result.plan, layout = result.layout
        kept.items.removeAll { dropped.contains($0.itemID) }
        layout.unplaced.removeAll { dropped.contains($0.itemID) }
        return (kept, layout, result.swaps)
    }

    private static func fittedWithExtras(_ plan: FurniturePlan, room: CanonicalRoom, catalog: FurnitureCatalog)
        -> (plan: FurniturePlan, layout: FurnitureLayout, swaps: [String]) {
        let layout = LayoutSolver.solve(room, plan, catalog: catalog)
        let extras = Set(plan.items.filter { $0.priority >= extraPriority }.map(\.itemID))
        let misfits = Set(layout.unplaced.filter { !$0.reason.hasPrefix("target ") && !extras.contains($0.itemID) }.map(\.itemID))
        guard !misfits.isEmpty else { return (plan, layout, []) }
        var retry = plan
        var swaps: [String] = []
        for i in retry.items.indices where misfits.contains(retry.items[i].itemID) {
            let item = retry.items[i]
            let current = catalog.entry(item.catalogID)
            let size = current?.size ?? item.size
            let area = size[0] * size[1]
            let styles = Set(current?.styles ?? [])
            let smaller = catalog.entries.filter { $0.category == item.category && $0.size[0] * $0.size[1] < area * 0.85 }
            guard let swap = smaller.max(by: { a, b in
                (Set(a.styles).intersection(styles).count, a.size[0] * a.size[1]) < (Set(b.styles).intersection(styles).count, b.size[0] * b.size[1])
            }) else { continue }
            retry.items[i].catalogID = swap.catalogID
            retry.items[i].name = swap.name
            retry.items[i].size = swap.size
            swaps.append("\(item.name) didn't fit, so the smaller \(swap.name) is used instead.")
        }
        guard !swaps.isEmpty else { return (plan, layout, []) }
        let second = LayoutSolver.solve(room, retry, catalog: catalog)
        // Pieces that matter count first: a wardrobe that now fits is worth a bench that no longer does.
        func core(_ l: FurnitureLayout) -> Int { l.placed.filter { !extras.contains($0.itemID) }.count }
        let better = (core(second), second.placed.count) > (core(layout), layout.placed.count)
        return better ? (retry, second, swaps) : (plan, layout, [])
    }

    /// Theme to furnished layout: read, choose, place, and explain.
    public static func design(room: CanonicalRoom, theme: String, constraints: FurnishConstraints = .init(), roomName: String? = nil,
                              colours: RoomColours? = nil, catalog: FurnitureCatalog = .current, anchorWall: String? = nil,
                              reader: BriefReader? = systemReader) async -> Result {
        let (brief, provider) = await readBrief(room: room, theme: theme, constraints: constraints, roomName: roomName, colours: colours, reader: reader)
        let chosen = plan(brief: brief, room: room, theme: theme, constraints: constraints, catalog: catalog, anchorWall: anchorWall)
        let (plan, layout, swaps) = fitted(chosen.plan, room: room, catalog: catalog)
        return Result(plan: plan, layout: layout, notes: notes(brief: brief, base: chosen.notes + swaps, layout: layout, constraints: constraints, catalog: catalog),
                      provider: provider, brief: brief)
    }

    static func notes(brief: DesignBrief, base: [String], layout: FurnitureLayout, constraints: FurnishConstraints, catalog: FurnitureCatalog) -> String {
        var lines = (brief.note.isEmpty ? [] : [brief.note]) + base
        if let budget = constraints.budgetAmount {
            let total = layout.placed.compactMap { catalog.entry($0.catalogID)?.budgetPrice }.reduce(0, +)
            if total > budget { lines.append("This comes to \(Int(total.rounded())), over your budget of \(Int(budget)).") }
        }
        return lines.joined(separator: " ")
    }
}

#if canImport(FoundationModels)
/// Apple Intelligence reads the theme. The answer has only words in it; the time limit is 30 seconds (5.3).
@available(iOS 26.0, macOS 26.0, *)
enum AIBriefReader {
    @Generable
    struct Answer {
        @Guide(description: "The kind of room the theme describes", .anyOf(FurniturePlanner.roomTypes))
        var roomType: String
        @Guide(description: "Up to six lowercase style words for the furniture", .maximumCount(6))
        var styleWords: [String]
        @Guide(description: "Kinds of furniture or Halloween prop the theme asks for, if any", .element(.anyOf(FurniturePlanner.categories)), .maximumCount(4))
        var wanted: [String]
        @Guide(description: "Kinds of furniture or prop the theme says to leave out, if any", .element(.anyOf(FurniturePlanner.categories)), .maximumCount(4))
        var avoided: [String]
        @Guide(description: "Up to three materials that give the theme its look", .element(.anyOf(FurniturePlanner.materialNames)), .maximumCount(3))
        var materials: [String]
        @Guide(description: "Up to three accent colours that suit the theme and the room", .element(.anyOf(FurniturePlanner.accentNames)), .maximumCount(3))
        var accents: [String]
        @Guide(description: "One or two friendly sentences describing the design idea")
        var note: String
    }

    static let instructions = """
        You are an interior designer. Read the user's theme for one room and describe what it asks for: the kind \
        of room, the style, materials and accent colours, any pieces or Halloween props it specifically wants or doesn't want, and \
        the design idea in one or two friendly sentences. Don't list furniture or props the theme doesn't mention.
        """

    static func read(_ prompt: String) async -> DesignBrief? {
        await withTaskGroup(of: DesignBrief?.self) { group in
            group.addTask {
                guard let answer = try? await LanguageModelSession(instructions: instructions).respond(to: prompt, generating: Answer.self).content else {
                    return nil
                }
                return DesignBrief(roomType: answer.roomType, styleWords: answer.styleWords, wanted: answer.wanted, avoided: answer.avoided,
                                   materials: answer.materials, accents: answer.accents, note: answer.note)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
#endif
