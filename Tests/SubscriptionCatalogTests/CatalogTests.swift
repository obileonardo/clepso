import Foundation
import Testing
@testable import SubscriptionCatalog

struct CatalogTests {
    @Test func bundledSeedDecodes() throws {
        let catalog = try PlanCatalog.bundled()
        #expect(catalog.catalogVersion == "1.0.0")
        #expect(catalog.entries.count == 31)
        #expect(catalog.skipped == 0)
        // Max 5× and Max 20× are separately selectable.
        let ids = catalog.claudePlans.map(\.id)
        #expect(ids.contains("anthropic.max.5x") && ids.contains("anthropic.max.20x"))
        #expect(!ids.contains("anthropic.api.payg"))
        #expect(catalog.claudePlans.allSatisfy { !$0.displayName.isEmpty && !$0.sourceURL.isEmpty })
    }

    /// §3: an entry missing a required field is skipped on its own; an unknown tier or status still decodes.
    @Test func skipsBadEntriesAndKeepsUnknownValues() throws {
        let json = """
        {"schemaVersion": 1, "catalogVersion": "9.9.9", "entries": [
          {"id": "anthropic.future", "publisher": "anthropic", "displayName": "Claude Future", "tier": "zz_future",
           "status": "zz_status", "checkedAt": "2026-10-16", "sourceURL": "https://example.invalid", "verified": false, "newField": 1},
          {"id": "anthropic.broken", "publisher": "anthropic", "checkedAt": "2026-10-16"}
        ]}
        """
        let catalog = try PlanCatalog(data: Data(json.utf8))
        #expect(catalog.entries.map(\.id) == ["anthropic.future"])
        #expect(catalog.entries[0].status == "zz_status")
        #expect(catalog.entries[0].shortLabel == "Claude Future")
        #expect(catalog.skipped == 1)
    }

    @Test func refusesNewerSchema() {
        #expect(throws: PlanCatalog.LoadError.unsupportedSchema(2)) {
            try PlanCatalog(data: Data(#"{"schemaVersion": 2, "entries": []}"#.utf8))
        }
    }
}
