import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Changing a design in plain words. Apple Intelligence, where available, answers with up to eight
/// changes; each is checked against the design, and the solver still places every piece.
public enum DesignEditor {
    public enum Spot: Sendable, Equatable {
        case wall(String), window, centre
    }

    public enum Step: Sendable, Equatable {
        case remove(itemID: String)
        case swap(itemID: String, words: Set<String>)
        case add(category: String, words: Set<String>)
        case move(itemID: String, to: Spot)
        case paint(WallPaint.Paint)
    }

    public struct Result: Sendable {
        public var option: LayoutOption
        public var wallPaint: WallPaint.Paint?
        /// What was done, or why not, a sentence each.
        public var report: [String]
        public var provider: String
        public var changed: Bool
    }

    public typealias StepReader = @Sendable (_ prompt: String, _ option: LayoutOption, _ room: CanonicalRoom) async -> [Step]?

    public static let examples = "I couldn't tell what to change. Try “remove the plant”, “swap the sofa for a smaller one”, “add a lamp”, “move the desk under the window” or “paint the walls sage”."

    public static func edit(_ option: LayoutOption, request: String, room: CanonicalRoom, colours: RoomColours,
                            wallPaint: WallPaint.Paint? = nil, catalog: FurnitureCatalog = .current,
                            reader: StepReader? = systemReader) async -> Result {
        var steps: [Step] = []
        var provider = FurniturePlanner.rulesProvider
        if let reader, let answer = await reader(prompt(option, request: request, room: room, colours: colours), option, room), !answer.isEmpty {
            steps = Array(answer.prefix(8))
            provider = FurniturePlanner.aiProvider
        }
        if steps.isEmpty { steps = ruleSteps(request, option: option, room: room) }
        var result = apply(steps, to: option, room: room, wallPaint: wallPaint, catalog: catalog)
        result.provider = provider
        if steps.isEmpty { result.report = [examples] }
        return result
    }

    public static var systemReader: StepReader? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), FurniturePlanner.systemReader != nil {
            return { prompt, option, room in await AIEditor.steps(prompt, option: option, room: room) }
        }
        #endif
        return nil
    }

    /// The steps in order. A step that can't be done is skipped and said so, leaving the piece as it was.
    public static func apply(_ steps: [Step], to option: LayoutOption, room: CanonicalRoom, wallPaint: WallPaint.Paint? = nil,
                             catalog: FurnitureCatalog = .current) -> Result {
        var current = option, paint = wallPaint, report: [String] = [], changed = false
        func name(_ itemID: String) -> String {
            let item = current.plan.items.first { $0.itemID == itemID }
            return item.map { item in current.products.first { $0.catalogID == item.catalogID }?.name ?? item.name } ?? itemID
        }
        func isPlaced(_ o: LayoutOption, _ id: String) -> Bool { o.layout.placed.contains { $0.itemID == id } }
        for step in steps {
            switch step {
            case let .remove(itemID):
                guard current.plan.items.contains(where: { $0.itemID == itemID }) else { continue }
                let label = name(itemID)
                current = DesignStudio.remove(current, itemID: itemID, room: room, catalog: catalog)
                report.append("Removed \(label).")
                changed = true
            case let .swap(itemID, words):
                guard let item = current.plan.items.first(where: { $0.itemID == itemID }) else { continue }
                let now = current.products.first { $0.catalogID == item.catalogID }
                guard let entry = product(item.category, words: words, replacing: now, size: item.size, catalog: catalog) else {
                    report.append("There's no other \(item.category.replacingOccurrences(of: "_", with: " ")) like that to swap \(name(itemID)) for.")
                    continue
                }
                let label = name(itemID)
                let swapped = DesignStudio.swap(current, itemID: itemID, to: entry, room: room, catalog: catalog)
                if isPlaced(swapped, itemID) || !isPlaced(current, itemID) {
                    current = swapped
                    report.append("Swapped \(label) for \(entry.name)" + (entry.priceText.map { " (\($0))." } ?? "."))
                    changed = true
                } else {
                    report.append("\(entry.name) doesn't fit where \(label) was, so it stays.")
                }
            case let .add(category, words):
                guard let entry = product(category, words: words, replacing: nil, size: nil, catalog: catalog) else {
                    report.append("There's no \(category.replacingOccurrences(of: "_", with: " ")) like that in the catalogue.")
                    continue
                }
                if let added = DesignStudio.add(current, entry: entry, room: room, catalog: catalog) {
                    current = added
                    report.append("Added \(entry.name)" + (entry.priceText.map { " (\($0))." } ?? "."))
                    changed = true
                } else {
                    report.append("There's no room for \(entry.name).")
                }
            case let .move(itemID, spot):
                guard let i = current.plan.items.firstIndex(where: { $0.itemID == itemID }) else { continue }
                guard let rule = rule(spot, room: room, plan: current.plan) else {
                    report.append("This room has no window to move \(name(itemID)) under.")
                    continue
                }
                var plan = current.plan
                plan.items[i].placement = rule
                let merged = FurnitureCatalog(entries: current.products).merged(with: catalog)
                let moved = DesignStudio.refit(current, plan, room: room, catalog: merged)
                if isPlaced(moved, itemID) {
                    current = moved
                    report.append("Moved \(name(itemID)) \(describe(spot, room: room)).")
                    changed = true
                } else {
                    report.append("\(name(itemID)) doesn't fit \(describe(spot, room: room)), so it stays where it was.")
                }
            case let .paint(colour):
                paint = colour
                report.append("Painted the walls \(colour.name).")
                changed = true
            }
        }
        return Result(option: current, wallPaint: paint, report: report, provider: FurniturePlanner.rulesProvider, changed: changed)
    }

    /// The product of a kind that best matches the words. "cheaper", "smaller" and "bigger" keep only those that are.
    static func product(_ category: String, words: Set<String>, replacing current: CatalogEntry?, size: [Double]?, catalog: FurnitureCatalog) -> CatalogEntry? {
        func area(_ s: [Double]?) -> Double { (s?.count ?? 0) >= 2 ? s![0] * s![1] : 0 }
        let currentArea = area(current?.size ?? size), currentPrice = current?.price
        var options = catalog.entries.filter { $0.category == category && $0.catalogID != current?.catalogID }
        let wantsCheap = !words.isDisjoint(with: ["cheaper", "cheap", "cheapest", "budget", "affordable"])
        if wantsCheap { options = options.filter { ($0.price ?? .infinity) < (currentPrice ?? .infinity) } }
        if !words.isDisjoint(with: ["smaller", "small", "compact", "narrower"]), currentArea > 0 { options = options.filter { area($0.size) < currentArea } }
        if !words.isDisjoint(with: ["bigger", "larger", "big", "large", "wider"]), currentArea > 0 { options = options.filter { area($0.size) > currentArea } }
        func score(_ e: CatalogEntry) -> Double {
            var s = Double(Set(e.styles).intersection(words).count) + Double(FurniturePlanner.words(e.name).intersection(words).count) * 1.5
            if currentArea > 0 { s -= abs(area(e.size) - currentArea) * 0.3 }
            if wantsCheap { s -= (e.price ?? 0) / 1000 }
            return s
        }
        var best: (CatalogEntry, Double)?
        for e in options where best == nil || score(e) > best!.1 + 1e-9 { best = (e, score(e)) }
        return best?.0
    }

    static func rule(_ spot: Spot, room: CanonicalRoom, plan: FurniturePlan) -> PlacementRule? {
        switch spot {
        case let .wall(id): return room.wall(id) == nil ? nil : .againstWall(wallID: id, align: "center")
        case .centre: return .centeredInRoom
        case .window:
            // A window nothing is under yet, else the first.
            let windows = room.openings.filter { $0.type == .window }.map(\.id)
            let used = Set(plan.items.compactMap { item -> String? in
                if case let .underWindow(id) = item.placement { return id }
                return nil
            })
            return (windows.first { !used.contains($0) } ?? windows.first).map { .underWindow(openingID: $0) }
        }
    }

    static func describe(_ spot: Spot, room: CanonicalRoom) -> String {
        switch spot {
        case let .wall(id): "to the \(Units.metric(room.wall(id)?.length ?? 0)) wall"
        case .window: "under the window"
        case .centre: "to the middle of the room"
        }
    }

    /// The room and design as compact JSON: lengths and sizes, never positions.
    public static func prompt(_ option: LayoutOption, request: String, room: CanonicalRoom, colours: RoomColours) -> String {
        func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        let walls: [[String: Any]] = room.walls.map { w in
            ["id": w.id, "length_m": round2(w.length),
             "openings": room.openings(onWall: w.id).map { "\($0.type.plainName) \($0.id)" }]
        }
        let pieces: [[String: Any]] = option.plan.items.map { item in
            ["item_id": item.itemID, "name": item.name, "category": item.category, "size_m": item.size.map(round2),
             "placed": option.layout.placed.contains { $0.itemID == item.itemID },
             "price": option.products.first { $0.catalogID == item.catalogID }?.priceText ?? ""]
        }
        let value: [String: Any] = ["area_m2": round2(room.derived.area), "walls": walls, "wall_colour": colours.wallName,
                                    "floor": colours.floorName, "furniture": pieces]
        let json = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "Room and furniture:\n\(json)\n\nChange: \(request)"
    }

    static let stopWords: Set<String> = ["the", "a", "an", "for", "with", "to", "it", "one", "of", "in", "my", "me", "please", "swap", "replace",
                                         "change", "add", "some", "make", "want", "need", "include", "different", "another", "instead", "this",
                                         "that", "room", "piece", "more", "i", "and", "is", "be", "can", "you"]

    /// Simple requests read without a model: clauses split at commas, "and" and full stops.
    static func ruleSteps(_ request: String, option: LayoutOption, room: CanonicalRoom) -> [Step] {
        let clauses = request.lowercased().replacingOccurrences(of: " and ", with: ",")
            .split { ",.;\n".contains($0) }.map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var steps: [Step] = []
        for clause in clauses {
            let words = FurniturePlanner.words(clause)
            let kind = FurniturePlanner.kind(of: words)
            let item = kind.flatMap { k in
                option.plan.items.first { item in item.category == k && option.layout.placed.contains { $0.itemID == item.itemID } }
                    ?? option.plan.items.first { $0.category == k }
            }
            let extra = words.subtracting(FurniturePlanner.kindWords[kind ?? ""] ?? []).subtracting(stopWords)
            if words.contains("paint") || words.contains("walls") {
                if let paint = WallPaint.paint(named: clause) { steps.append(.paint(paint)) }
            } else if !words.isDisjoint(with: ["remove", "delete", "without", "rid", "drop"]) {
                if let item { steps.append(.remove(itemID: item.itemID)) }
            } else if !words.isDisjoint(with: ["move", "put", "place"]), let item {
                let wall = room.walls.first { words.contains($0.id.lowercased()) }
                if words.contains("window") { steps.append(.move(itemID: item.itemID, to: .window)) }
                else if !words.isDisjoint(with: ["middle", "centre", "center"]) { steps.append(.move(itemID: item.itemID, to: .centre)) }
                else if let wall { steps.append(.move(itemID: item.itemID, to: .wall(wall.id))) }
            } else if !words.isDisjoint(with: ["add", "want", "need", "include"]), let kind {
                steps.append(.add(category: kind, words: extra))
            } else if !words.isDisjoint(with: ["swap", "replace", "change", "different", "another", "cheaper", "cheap", "budget", "smaller", "bigger", "larger"]) {
                if let item {
                    steps.append(.swap(itemID: item.itemID, words: extra))
                } else if !words.isDisjoint(with: ["cheaper", "cheap", "budget"]) {
                    // "Make it cheaper" with no named piece: every placed piece.
                    steps += option.layout.placed.map { .swap(itemID: $0.itemID, words: ["cheaper"]) }
                }
            }
        }
        return steps
    }
}

#if canImport(FoundationModels)
/// The model's answer as words and ids, each checked before it is applied. There is no field for a position.
@available(iOS 26.0, macOS 26.0, *)
enum AIEditor {
    @Generable
    struct Change {
        @Guide(description: "What to do", .anyOf(["remove", "swap", "add", "move", "paint"]))
        var action: String
        @Guide(description: "For remove, swap and move: the item_id of the piece from the JSON; otherwise empty")
        var itemID: String
        @Guide(description: "For add: the kind of piece to add; otherwise empty", .anyOf(FurniturePlanner.categories + [""]))
        var category: String
        @Guide(description: "For swap and add: a few lowercase words for the product wanted; otherwise empty")
        var words: String
        @Guide(description: "For move: a wall id from the JSON, or window, or center; otherwise empty")
        var target: String
        @Guide(description: "For paint: the new wall colour; otherwise empty")
        var colour: String
    }

    @Generable
    struct Reply {
        @Guide(description: "The changes that do what the user asks, in order; as few as needed", .maximumCount(8))
        var changes: [Change]
    }

    static let instructions = """
        You edit a furnished room design. You are given the room and its furniture as JSON, and what the user wants \
        changed. Answer with the changes that do it: remove a piece, swap a piece for another product of the same kind, \
        add a kind of piece, move a piece to a wall, under a window or to the center, or paint the walls a colour. Use \
        item_id and wall id values exactly as they appear in the JSON. Only change what the user asks for.
        """

    static func steps(_ prompt: String, option: LayoutOption, room: CanonicalRoom) async -> [DesignEditor.Step]? {
        guard let reply = try? await LanguageModelSession(instructions: instructions).respond(to: prompt, generating: Reply.self).content else { return nil }
        return reply.changes.compactMap { step(action: $0.action, itemID: $0.itemID, category: $0.category, words: $0.words, target: $0.target, colour: $0.colour, option: option, room: room) }
    }

    /// One change checked against the design and the known kinds and colours.
    static func step(action: String, itemID: String, category: String, words: String, target: String, colour: String,
                     option: LayoutOption, room: CanonicalRoom) -> DesignEditor.Step? {
        let items = option.plan.items
        let id = items.first { $0.itemID == itemID }?.itemID ?? items.first { $0.category == itemID || $0.category == category }?.itemID
        let wordSet = FurniturePlanner.words(words)
        switch action {
        case "remove": return id.map { .remove(itemID: $0) }
        case "swap": return id.map { .swap(itemID: $0, words: wordSet) }
        case "add": return FurniturePlanner.categories.contains(category) ? .add(category: category, words: wordSet) : nil
        case "move":
            guard let id else { return nil }
            let place = target.lowercased()
            if place.contains("window") { return .move(itemID: id, to: .window) }
            if place.contains("cent") || place.contains("middle") { return .move(itemID: id, to: .centre) }
            return room.wall(target) == nil ? nil : .move(itemID: id, to: .wall(target))
        case "paint": return WallPaint.paint(named: colour).map { .paint($0) }
        default: return nil
        }
    }
}
#endif
