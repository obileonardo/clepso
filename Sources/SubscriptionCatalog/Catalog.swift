import Foundation

/// The bundled plan catalog seed, decoded for the plan picker.
/// Increment 1.4 reads the bundled copy only; signed downloads and the entitlement graph arrive in 3.1.
public struct PlanCatalog: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: String
        public let publisher: String
        public let displayName: String
        public let shortLabel: String
        public let status: String                // open string: "active", "legacy", or a value this build has never seen
        public let checkedAt: String
        public let sourceURL: String
        public let verified: Bool
    }

    public static let supportedSchemaVersion = 1

    public let catalogVersion: String
    public let entries: [Entry]
    /// Entries skipped because a required field was missing (§3: skipped one by one, never the whole catalog).
    public let skipped: Int

    public enum LoadError: Error, Equatable { case unreadable, unsupportedSchema(Int) }

    public init(data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LoadError.unreadable }
        let schema = root["schemaVersion"] as? Int ?? 0
        guard schema == Self.supportedSchemaVersion else { throw LoadError.unsupportedSchema(schema) }
        var entries: [Entry] = [], skipped = 0
        for case let raw as [String: Any] in root["entries"] as? [Any] ?? [] {
            guard let id = raw["id"] as? String, let publisher = raw["publisher"] as? String,
                  let displayName = raw["displayName"] as? String, let checkedAt = raw["checkedAt"] as? String,
                  let sourceURL = raw["sourceURL"] as? String, let verified = raw["verified"] as? Bool else { skipped += 1; continue }
            entries.append(Entry(id: id, publisher: publisher, displayName: displayName,
                                 shortLabel: raw["shortLabel"] as? String ?? displayName, status: raw["status"] as? String ?? "unknown",
                                 checkedAt: checkedAt, sourceURL: sourceURL, verified: verified))
        }
        self.catalogVersion = root["catalogVersion"] as? String ?? "unknown"
        self.entries = entries
        self.skipped = skipped
    }

    /// The seed shipped inside the app.
    public static func bundled() throws -> PlanCatalog {
        guard let url = Bundle.module.url(forResource: "plan-catalog.v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { throw LoadError.unreadable }
        return try PlanCatalog(data: data)
    }

    /// Plans a Claude Code user can hold, in catalog order. API-organization entries are not subscriptions.
    public var claudePlans: [Entry] {
        entries.filter { $0.publisher == "anthropic" && !$0.id.hasPrefix("anthropic.api.") }
    }
}
