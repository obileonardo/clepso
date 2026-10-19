import Foundation
import Testing
@testable import ClaudeCodeAdapter

struct BackupRetentionTests {
    @Test("Only unchanged recorded backups expire after disconnect; active connections, edits and other files survive")
    func cleanup() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("clepso-backup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SettingsInstaller.Paths(home: home), now = Date(timeIntervalSince1970: 1_792_159_200)
        try FileManager.default.createDirectory(at: paths.backupsDir, withIntermediateDirectories: true)
        let backup = paths.backupsDir.appendingPathComponent("settings.json.20261019T120000Z.123456abcdef.bak")
        let edited = paths.backupsDir.appendingPathComponent("settings.json.20261019T120001Z.123456abcdef.bak")
        let other = paths.backupsDir.appendingPathComponent("my-notes.txt")
        try Data("original".utf8).write(to: backup)
        try Data("before".utf8).write(to: edited)
        try Data("keep".utf8).write(to: other)
        let retention = BackupRetention(paths: paths)
        try retention.markDisconnected(at: now)
        try Data("user edit".utf8).write(to: edited)
        #expect(try retention.purgeExpired(at: now + 29 * 86_400) == 0)
        try FileManager.default.createDirectory(at: paths.clepsoDir, withIntermediateDirectories: true)
        #expect(try retention.purgeExpired(at: now + 31 * 86_400) == 0)
        try FileManager.default.removeItem(at: paths.clepsoDir)
        #expect(try retention.purgeExpired(at: now + 31 * 86_400) == 1)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(try String(contentsOf: edited, encoding: .utf8) == "user edit")
        #expect(try String(contentsOf: other, encoding: .utf8) == "keep")
    }
}
