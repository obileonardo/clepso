import GRDB

/// Forward-only migrations (DATA_MODEL §4). Migration names are never edited after release.
public enum Migrations {
    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: SchemaV1.sql)
        }
        return migrator
    }

    /// WAL and foreign keys for the app's single writer (ADR-005). GRDB enables foreign keys by default.
    public static func openPool(at path: String) throws -> DatabasePool {
        let pool = try DatabasePool(path: path)
        try migrator().migrate(pool)
        return pool
    }
}
