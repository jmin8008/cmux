import Foundation

/// A user-owned list. Invalid or future documents are never repaired by a write.
public struct QuickLaunchRegistry: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var entries: [QuickLaunchEntry] = []

    public init(entries: [QuickLaunchEntry] = []) { self.entries = entries }

    public static func decode(_ raw: Any?) throws -> Self {
        guard let raw else { return Self() }
        guard let object = raw as? [String: Any],
              let version = object["version"] as? Int, version == 1 else {
            throw QuickLaunchError.unsupportedDocument
        }
        // Preserve fields from a newer writer instead of silently dropping them.
        guard Set(object.keys).isSubset(of: ["version", "entries"]) else {
            throw QuickLaunchError.unsupportedDocument
        }
        let data = try JSONSerialization.data(withJSONObject: raw)
        let registry = try JSONDecoder().decode(Self.self, from: data)
        guard Set(registry.entries.map(\.id)).count == registry.entries.count else {
            throw QuickLaunchError.invalidEntry
        }
        for entry in registry.entries { try entry.validate() }
        // Codable ignores unknown nested fields. Refuse a lossy round trip.
        let encoded = try registry.jsonObject()
        guard NSDictionary(dictionary: object).isEqual(to: encoded) else {
            throw QuickLaunchError.unsupportedDocument
        }
        return registry
    }

    public func jsonObject() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as! [String: Any]
    }

    public mutating func apply(_ mutation: QuickLaunchMutation) throws {
        switch mutation {
        case let .save(entry, replacing):
            try entry.validate()
            if let replacing {
                guard replacing.id == entry.id,
                      let index = entries.firstIndex(where: { $0.id == entry.id }),
                      entries[index] == replacing else { throw QuickLaunchError.conflict }
                entries[index] = entry
            } else {
                guard !entries.contains(where: { $0.id == entry.id }) else { throw QuickLaunchError.conflict }
                entries.append(entry)
            }
        case let .remove(entry):
            guard let index = entries.firstIndex(where: { $0.id == entry.id }),
                  entries[index] == entry else { throw QuickLaunchError.conflict }
            entries.remove(at: index)
        case let .move(id, before):
            guard let index = entries.firstIndex(where: { $0.id == id }) else { throw QuickLaunchError.conflict }
            if before == id { return }
            if let before, !entries.contains(where: { $0.id == before }) { throw QuickLaunchError.conflict }
            let entry = entries.remove(at: index)
            let destination = before.flatMap { target in entries.firstIndex(where: { $0.id == target }) } ?? entries.endIndex
            entries.insert(entry, at: destination)
        }
    }
}

public struct QuickLaunchEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case web, app }
    public enum OpenMode: String, Codable, Sendable {
        case inApp = "in-app"
        case systemBrowser = "system-browser"
        case native
    }
    public struct Target: Codable, Equatable, Sendable {
        public var kind: Kind
        public var url: String
        public var bundleIdentifier: String?
        public var bookmark: Data?
        public init(kind: Kind, url: String, bundleIdentifier: String? = nil, bookmark: Data? = nil) {
            self.kind = kind
            self.url = url
            self.bundleIdentifier = bundleIdentifier
            self.bookmark = bookmark
        }
    }
    public var id: UUID
    public var name: String
    public var target: Target
    public var openMode: OpenMode
    public var reusePolicy = "focus-or-open"
    public var symbol: String

    public init(id: UUID = UUID(), name: String, target: Target, openMode: OpenMode, symbol: String = "globe") {
        self.id = id
        self.name = name
        self.target = target
        self.openMode = openMode
        self.symbol = symbol
    }

    public static let symbols = ["globe", "star", "bolt", "terminal", "hammer", "book", "app"]

    public static func webURL(_ text: String) -> URL? {
        guard text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: text),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.symbols.contains(symbol), reusePolicy == "focus-or-open" else {
            throw QuickLaunchError.invalidEntry
        }
        switch target.kind {
        case .web:
            guard Self.webURL(target.url) != nil, openMode != .native,
                  target.bundleIdentifier == nil, target.bookmark == nil else { throw QuickLaunchError.invalidEntry }
        case .app:
            guard let url = URL(string: target.url), url.isFileURL, url.pathExtension == "app",
                  let bundleID = target.bundleIdentifier, !bundleID.isEmpty,
                  openMode == .native else { throw QuickLaunchError.invalidEntry }
        }
    }
}

public enum QuickLaunchMutation: Sendable {
    case save(QuickLaunchEntry, replacing: QuickLaunchEntry?)
    case remove(QuickLaunchEntry)
    case move(UUID, before: UUID?)
}

public enum QuickLaunchError: Error, Equatable, Sendable {
    case unsupportedDocument, invalidEntry, conflict
}

public enum QuickLaunchState: Equatable, Sendable {
    case ready(QuickLaunchRegistry)
    case unreadable
}
