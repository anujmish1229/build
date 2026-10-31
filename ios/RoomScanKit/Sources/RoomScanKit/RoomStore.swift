import Foundation

/// Reads and writes protected, backup-excluded files (requirements 5.4).
public enum ProtectedFile {
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    /// Moves an unreadable file aside so it can never be overwritten by the next save.
    public static func setAside(_ url: URL) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingPathExtension().appendingPathExtension("damaged-\(stamp).json")
        try? FileManager.default.removeItem(at: target)
        return (try? FileManager.default.moveItem(at: url, to: target)) == nil ? nil : target
    }
}

/// One room with everything needed to rescan it. The single-room file format, read once for migration.
public struct StoredRoom: Codable, Equatable, Sendable {
    public var editable: EditableRoom
    public var rawScan: RawRoom?
    public var sourceIDs: [String: [String]]

    public init(editable: EditableRoom, rawScan: RawRoom? = nil, sourceIDs: [String: [String]] = [:]) {
        self.editable = editable; self.rawScan = rawScan; self.sourceIDs = sourceIDs
    }
}

public struct RoomStore: Sendable {
    public enum LoadError: Error, LocalizedError {
        case damaged
        public var errorDescription: String? { "Your saved room couldn't be read. It was kept, not overwritten." }
    }

    public let url: URL
    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RoomScan/room_store.json")
    }

    /// nil when nothing is saved. Throws, after moving the file aside, when it can't be read.
    public func load() throws -> StoredRoom? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(StoredRoom.self, from: Data(contentsOf: url))
        } catch {
            _ = ProtectedFile.setAside(url)
            throw LoadError.damaged
        }
    }

    public func save(_ stored: StoredRoom) throws {
        try ProtectedFile.write(RoomJSON.encoder().encode(stored), to: url)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
