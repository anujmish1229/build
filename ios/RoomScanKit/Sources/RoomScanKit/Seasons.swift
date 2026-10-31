import Foundation

/// The holidays a design can be themed for. A holiday adds decorations placed by the solver like any other
/// piece, so doors and walkways stay clear. Halloween's are catalogue props with a price and somewhere to buy
/// them; Christmas's, and the fireplace, are drawn decorations with no price.
public enum Season: String, CaseIterable, Sendable {
    case christmas, halloween

    /// One decoration: its name, and [width, depth, height] in metres.
    public struct Prop: Sendable, Equatable {
        public let name: String
        public let size: [Double]
    }

    var themeWords: [String] {
        switch self {
        case .christmas: ["christmas", "xmas", "festive", "yuletide"]
        case .halloween: ["halloween", "hallowe", "haunted", "haunt", "haunting", "spooky", "spook", "scary", "creepy", "horror", "fright",
                          "frightening", "graveyard", "cemetery", "grave", "graves", "crypt", "tomb", "witch", "witches", "ghost", "ghosts",
                          "ghostly", "zombie", "zombies", "vampire", "monster", "monsters", "macabre", "eerie", "sinister", "pumpkin",
                          "pumpkins", "skeleton", "skeletons", "coffin", "samhain"]
        }
    }

    public static func of(_ words: Set<String>) -> Season? {
        allCases.first { !words.isDisjoint(with: $0.themeWords) }
    }

    public static func of(style: DesignStyle?) -> Season? {
        of(Set((style?.words ?? []).flatMap { FurniturePlanner.words($0) }))
    }

    /// True for a category that's a drawn decoration, with no product behind it.
    public static func isDecoration(_ category: String?) -> Bool {
        decorations.contains(category ?? "")
    }

    static let decorations: Set<String> = ["fireplace", "christmas_tree", "gift_pile", "nutcracker", "reindeer"]

    static func isProp(_ category: String) -> Bool { FurnitureCatalog.propCategories.contains(category) }

    /// Which props a haunt gets, in the order they're placed and so dropped: a graveyard, a witch's lair, a
    /// vampire's crypt, or the classic haunted house when the theme doesn't say which.
    public static func props(for words: Set<String>) -> [String] {
        func mentions(_ list: [String]) -> Bool { !words.isDisjoint(with: list) }
        if mentions(["graveyard", "cemetery", "grave", "graves", "tomb", "tombstone", "zombie", "zombies", "bones", "undead"]) {
            return ["tombstone", "skeleton", "poster", "groundbreaker", "string_lights", "tree", "projector",
                    "fence", "fog_machine", "prop_light", "curio"]
        }
        if mentions(["witch", "witches", "potion", "potions", "coven", "spell", "spells", "cauldron", "apothecary"]) {
            return ["cauldron", "candelabra", "neon_sign", "curio", "poster", "cobweb", "string_lights",
                    "spider", "jack_o_lantern", "prop_light", "gore"]
        }
        if mentions(["vampire", "crypt", "coffin", "dracula", "gothic"]) {
            return ["coffin", "candelabra", "neon_sign", "cobweb", "led_strip", "curio", "poster",
                    "spider", "prop_light", "fog_machine", "gore"]
        }
        return ["jack_o_lantern", "ghost", "poster", "cobweb", "neon_sign", "skeleton", "string_lights",
                "spider", "candelabra", "fog_machine", "prop_light"]
    }

    /// The wall colour that suits the holiday.
    public var paint: WallPaint.Paint {
        switch self {
        case .christmas: WallPaint.Paint("forest green", "#32503F")
        case .halloween: WallPaint.Paint("deep plum", "#2C1E36")
        }
    }

    /// Product finishes that suit the holiday, preferred when choosing between products.
    var preferredFinishes: Set<String> {
        switch self {
        case .christmas: ["walnut", "oak", "oat", "boucle", "leather"]
        case .halloween: ["charcoal", "black", "walnut", "leather"]
        }
    }

    /// The holiday's two main colours: Christmas red and green, Halloween orange and purple.
    var red: Finish {
        switch self {
        case .christmas: Finish(0.6, 0.06, 0.09, roughness: 0.55)
        case .halloween: Finish(0.93, 0.42, 0.05, roughness: 0.6)
        }
    }

    var green: Finish {
        switch self {
        case .christmas: Finish(0.07, 0.3, 0.17, roughness: 0.7)
        case .halloween: Finish(0.24, 0.1, 0.36, roughness: 0.65)
        }
    }

    /// The room type's slots with this holiday's pieces in. A living room turns to face a fireplace.
    func slots(_ base: [FurniturePlanner.Slot], type: String, roles r: WallRoles, area: Double, themeWords: Set<String> = []) -> [FurniturePlanner.Slot] {
        typealias Slot = FurniturePlanner.Slot
        let extra = FurniturePlanner.extraPriority
        let living = type == "living"
        var list = base
        let hearthWall = living ? r.main : r.secondSide
        if living {
            // The fireplace takes the main wall. The sofa moves to a side wall, with the armchairs facing it.
            list.removeAll { ["tv_stand", "armchair", "armchair_2", "bookshelf", "lamp", "side_table", "storage", "bench"].contains($0.id) }
            list = list.map { slot in
                switch slot.id {
                case "sofa": Slot(id: "sofa", category: "sofa", rule: .againstWall(wallID: r.secondSide, align: "center"), priority: 1)
                case "plant": Slot(id: "plant", category: "plant", rule: .corner(wallID: r.main, corner: "start"), priority: extra)
                default: slot
                }
            }
            list.append(Slot(id: "armchair", category: "armchair", rule: .inFrontOf(targetItemID: "sofa", gap: 1.55), priority: 3))
            list.append(Slot(id: "armchair_2", category: "armchair", rule: .beside(targetItemID: "armchair", side: "left", gap: 0.3), priority: extra))
            list.append(Slot(id: "lamp", category: "lamp", rule: .beside(targetItemID: "sofa", side: "left", gap: 0.05), priority: 3))
            list.append(Slot(id: "side_table", category: "side_table", rule: .beside(targetItemID: "sofa", side: "right", gap: 0.05), priority: extra))
            list.append(Slot(id: "storage", category: "storage", rule: .againstWall(wallID: r.opposite, align: "end"), priority: extra))
            list.append(Slot(id: "bench", category: "bench", rule: .againstWall(wallID: r.firstSide, align: "center"), priority: extra))
        }
        let hearth = Prop(name: self == .christmas ? "Christmas fireplace" : "Haunted fireplace", size: [1.6, 0.45, 1.25])
        list.append(Slot(id: "fireplace", category: "fireplace", rule: .againstWall(wallID: hearthWall, align: "center"), priority: living ? 1 : 3, prop: hearth))
        let small = area < 14
        switch self {
        case .christmas:
            let tree = small ? Prop(name: "Small Christmas tree", size: [0.9, 0.9, 1.75]) : Prop(name: "Christmas tree", size: [1.35, 1.35, 2.3])
            list.append(Slot(id: "christmas_tree", category: "christmas_tree", rule: .corner(wallID: r.main, corner: "end"), priority: 2, prop: tree))
            list.append(Slot(id: "gift_pile", category: "gift_pile", rule: .beside(targetItemID: "christmas_tree", side: "left", gap: 0.03), priority: extra, prop: Prop(name: "Wrapped gifts", size: [0.9, 0.6, 0.38])))
            list.append(Slot(id: "nutcracker_left", category: "nutcracker", rule: .beside(targetItemID: "fireplace", side: "left", gap: 0.06), priority: extra, prop: Prop(name: "Nutcracker", size: [0.3, 0.3, 1.1])))
            list.append(Slot(id: "nutcracker_right", category: "nutcracker", rule: .beside(targetItemID: "fireplace", side: "right", gap: 0.06), priority: extra, prop: Prop(name: "Nutcracker", size: [0.3, 0.3, 1.1])))
            list.append(Slot(id: "reindeer", category: "reindeer", rule: .corner(wallID: r.firstSide, corner: "end"), priority: extra, prop: Prop(name: "Golden reindeer", size: [0.75, 0.32, 1.0])))
        case .halloween:
            // Props in the corners and along the free walls; what hangs goes mid-wall at eye height, one wall
            // each, and beside the fireplace rather than behind it. All are extras, so a room loses a tombstone
            // before it loses the bed.
            list.removeAll { $0.id == "plant" }
            let floorSpots: [PlacementRule] = [
                .corner(wallID: r.main, corner: "end"), .corner(wallID: r.firstSide, corner: "end"), .corner(wallID: r.main, corner: "start"),
                .corner(wallID: r.opposite, corner: "start"), .corner(wallID: r.secondSide, corner: "end"), .againstWall(wallID: r.firstSide, align: "center"),
                .againstWall(wallID: r.opposite, align: "start"), .againstWall(wallID: r.firstSide, align: "end"),
            ]
            let wallOrder = living ? [r.secondSide, r.main, r.firstSide, r.opposite] : [r.main, r.opposite, r.firstSide, r.secondSide]
            var onFloor = 0, onWall = 0
            for category in Season.props(for: themeWords) where !list.contains(where: { $0.category == category }) {
                let rule: PlacementRule
                if FurnitureCatalog.wallMounted.contains(category) {
                    let wall = wallOrder[onWall % wallOrder.count]
                    rule = .againstWall(wallID: wall, align: wall == hearthWall ? "end" : "center")
                    onWall += 1
                } else {
                    rule = floorSpots[onFloor % floorSpots.count]
                    onFloor += 1
                }
                list.append(Slot(id: "prop_\(category)", category: category, rule: rule, priority: extra))
            }
        }
        return list
    }
}
