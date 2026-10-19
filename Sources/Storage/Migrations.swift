import GRDB

/// Forward-only migrations (DATA_MODEL §4). Migration names are never edited after release.
public enum Migrations {
    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: SchemaV1.sql)
        }
        // Increment 1.7: three more value kinds (count, duration, flag). SQLite cannot alter a CHECK, so the ledger
        // table is rebuilt with every row copied unchanged (DATA_MODEL §4 rule 3: rows are never reinterpreted).
        migrator.registerMigration("v2_value_kinds_count_duration_flag") { db in
            try db.execute(sql: SchemaV2.observationsRebuild)
        }
        // Increment 1.9: agents per task (two new tables; nothing existing changes).
        migrator.registerMigration("v3_agent_tasks") { db in
            try db.execute(sql: SchemaV3.agentTasks)
        }
        // Founder decision 19 Oct 2026: a run's type may be a custom agent name the user approved (rebuilt for the CHECK).
        migrator.registerMigration("v4_agent_type_approved_names") { db in
            try db.execute(sql: SchemaV4.agentRunsRebuild)
        }
        return migrator
    }

    /// WAL and foreign keys for the app's single writer (ARCHITECTURE §4). GRDB enables foreign keys by default.
    public static func openPool(at path: String) throws -> DatabasePool {
        let pool = try DatabasePool(path: path)
        try migrator().migrate(pool)
        return pool
    }
}
