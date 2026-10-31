import Foundation

/// Brings older files up to the current formats. Each step works on plain JSON, so an old file
/// never has to decode as today's types before it is upgraded.
public enum Migrations {
    public enum Failure: Error, Equatable { case damaged, newer }

    /// Reads a library file of any version up to the current one.
    public static func library(from data: Data) throws -> Library {
        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.damaged }
        let version = json["version"] as? Int ?? 0
        guard version <= Library.currentVersion else { throw Failure.newer }
        if version < 1 { json = libraryV0toV1(json) }
        do {
            let upgraded = try JSONSerialization.data(withJSONObject: json)
            return try LibraryStore.decoder.decode(Library.self, from: upgraded)
        } catch {
            throw Failure.damaged
        }
    }

    /// Version 0 had no version field, one source id per wall, and its own shape of corrections.
    static func libraryV0toV1(_ old: [String: Any]) -> [String: Any] {
        var json = old
        json["version"] = 1
        if var rooms = json["rooms"] as? [[String: Any]] {
            for i in rooms.indices { rooms[i] = roomRecordV0toV1(rooms[i]) }
            json["rooms"] = rooms
        }
        return json
    }

    static func roomRecordV0toV1(_ old: [String: Any]) -> [String: Any] {
        var record = old
        if let single = record["sourceIDs"] as? [String: String] {
            record["sourceIDs"] = single.mapValues { [$0] }
        } else if record["sourceIDs"] == nil {
            record["sourceIDs"] = [String: [String]]()
        }
        // Corrections in a shape this version can't read can't be replayed. The geometry already holds their
        // effect, so only a future rescan loses them.
        let corrections = (record["corrections"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        if corrections.flatMap({ try? JSONDecoder().decode(RoomCorrections.self, from: $0) }) == nil {
            record["corrections"] = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(RoomCorrections()))) ?? [String: Any]()
        }
        if var room = record["room"] as? [String: Any], room["schema_version"] == nil {
            room["schema_version"] = 1
            record["room"] = room
        }
        return record
    }

    /// A share file without a version is the first version.
    static func shareFileVersion(_ value: Int?) -> Int { value ?? 1 }

    /// Moves a room from the earlier one-room app into the library once, as "My room".
    @discardableResult
    public static func importLegacyRoom(from legacy: RoomStore, into store: LibraryStore) throws -> Bool {
        guard let stored = try legacy.load() else { return false }
        try store.addRoom(SavedRoom(name: "My room", room: stored.editable.room, rawScan: stored.rawScan,
                                    sourceIDs: stored.sourceIDs, corrections: stored.editable.corrections))
        try legacy.delete()
        return true
    }
}
