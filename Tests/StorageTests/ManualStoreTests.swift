import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

struct ManualStoreTests {
    @Test("Upgrading a v5 database backs it up and preserves its observations while adding manual storage")
    func upgrade() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clepso-v6-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("clepso.sqlite")
        do {
            let queue = try DatabaseQueue(path: file.path)
            try Migrations.migrator().migrate(queue, upTo: "v5_agent_background")
            try await queue.write { db in
                try SchemaV1Tests().seed(db)
                try SchemaV1Tests().insertObservation(db, id: "kept", dedupe: "kept", valueText: "83.25")
            }
        }
        let store = try Store.onDisk(at: file, now: t0)
        let export = try await store.exportRows()
        #expect(export.first { $0.table == "observations" }?.rows.first?["value_text"] == .text("83.25"))
        #expect(export.contains { $0.table == "manual_allowances" && $0.rows.isEmpty })
        let backup = root.appendingPathComponent("clepso.sqlite.pre-v6_manual_allowances.bak")
        var configuration = Configuration(); configuration.readonly = true
        let queue = try DatabaseQueue(path: backup.path, configuration: configuration)
        let value = try await queue.read { try String.fetchOne($0, sql: "SELECT value_text FROM observations WHERE id = 'kept'") }
        #expect(value == "83.25")
        let manualTables = try await queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'manual_allowances'") }
        #expect(manualTables == 0, "the backup is the pre-migration v5 database")
    }
    @Test("Manual history uses the latest measured reading, stays separate, exports and can be removed")
    func lifecycle() async throws {
        let store = try Store.inMemory(now: t0)
        let current = try ManualAllowance(providerID: "cursor", window: .weekly, usedPercent: 83,
                                          resetsAt: t0 + 7200, observedAt: t0, enteredAt: t0)
        let older = try ManualAllowance(providerID: "cursor", window: .weekly, usedPercent: 12,
                                        resetsAt: nil, observedAt: t0 - 60, enteredAt: t0 + 60)
        try await store.recordManualAllowance(current)
        try await store.recordManualAllowance(older)
        #expect(try await store.manualAllowances().first?.usedPercent == 83)
        #expect(try await store.poolStates().isEmpty)
        #expect(try await store.exportRows().first { $0.table == "manual_allowances" }?.rows.count == 2)
        try await store.removeManualAllowance(providerID: "cursor", window: .weekly)
        #expect(try await store.manualAllowances().isEmpty)
    }
}
