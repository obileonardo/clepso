import CryptoKit
import Darwin
import Foundation
import Testing
import TestFixtures
@testable import ClaudeCodeAdapter

/// Every test runs in a throwaway HOME. The real ~/.claude is never read or written.
struct Sandbox {
    let home: URL
    var claude: URL { home.appendingPathComponent(".claude") }
    var settings: URL { claude.appendingPathComponent("settings.json") }
    static let shim = "/Applications/Clepso.app/Contents/Helpers/clepso-statusline"
    static let fixedNow = Date(timeIntervalSince1970: 1_792_159_200)

    init(settingsFixture: String? = nil, mode: mode_t = 0o640) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("tk-inst-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        if let settingsFixture {
            try Data(contentsOf: Sandbox.corpus(settingsFixture)).write(to: settings)
            chmod(settings.path, mode)
        }
    }

    static func corpus(_ name: String) -> URL {
        Fixtures.claudeCodeRoot.appendingPathComponent("settings/\(name)")
    }

    static var installable: [String] { corpusFiles.filter { !$0.hasPrefix("refused-") } }
    static var refused: [String] { corpusFiles.filter { $0.hasPrefix("refused-") } }
    static var corpusFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: Fixtures.claudeCodeRoot.appendingPathComponent("settings").path)) ?? []).sorted()
    }

    func installer(shim: String = Sandbox.shim, beforeWrite: (@Sendable () -> Void)? = nil) -> SettingsInstaller {
        SettingsInstaller(paths: .init(home: home), shimPath: shim, socketPath: home.appendingPathComponent("a.sock").path,
                          forwardCost: true, now: { Sandbox.fixedNow }, beforeSettingsWrite: beforeWrite)
    }

    func bytes(_ url: URL) -> [UInt8]? { (try? Data(contentsOf: url)).map(Array.init) }
    func mode(_ url: URL) -> mode_t { var s = stat(); lstat(url.path, &s); return s.st_mode & 0o7777 }
    func exists(_ url: URL) -> Bool { var s = stat(); return lstat(url.path, &s) == 0 }
    func cleanUp() { try? FileManager.default.removeItem(at: home) }
}

func sha(_ bytes: [UInt8]) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

/// The bytes that differ between two files, found by trimming the common prefix and suffix. Independent
/// of the installer's own scanner, so it checks the claim "only one value changed" from the outside.
func changedRegion(_ old: [UInt8], _ new: [UInt8]) -> (old: String, new: String) {
    var prefix = 0
    while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < old.count - prefix, suffix < new.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
    return (String(decoding: old[prefix..<(old.count - suffix)], as: UTF8.self),
            String(decoding: new[prefix..<(new.count - suffix)], as: UTF8.self))
}

/// A string as a JSON literal with unescaped slashes, the way settings files write paths.
func literal(_ string: String) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return String(decoding: try encoder.encode(string), as: UTF8.self)
}

func jsonObject(_ bytes: [UInt8]) -> [String: Any]? {
    let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
    return (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any]
}

@Suite("Settings install and uninstall (F13 corpus)", .serialized)
struct SettingsInstallerTests {
    @Test("Install changes only the command value; uninstall restores the original bytes exactly", arguments: Sandbox.installable)
    func roundTrip(file: String) throws {
        let box = try Sandbox(settingsFixture: file); defer { box.cleanUp() }
        let original = try #require(box.bytes(box.settings))
        let report = try box.installer().install()
        let installed = try #require(box.bytes(box.settings))
        let installedObject = try #require(jsonObject(installed), "\(file): installed file is not valid JSON")

        // Only statusLine.command (or one appended member) changed; every other key is identical.
        let before = try #require(jsonObject(original))
        #expect(Set(installedObject.keys) == Set(before.keys).union(["statusLine"]))
        for (key, value) in before where key != "statusLine" {
            #expect((value as AnyObject).isEqual(installedObject[key]), "\(file): \(key) changed")
        }
        let statusLine = try #require(installedObject["statusLine"] as? [String: Any])
        #expect(statusLine["command"] as? String == "~/.claude/clepso/statusline.sh")
        let region = changedRegion(original, installed)
        if let previous = before["statusLine"] as? [String: Any] {
            #expect(report.hadExistingStatusLine)
            // The installed file must equal the original with exactly the old command literal swapped.
            let oldLiteral = try literal(try #require(previous["command"] as? String))
            let originalText = String(decoding: original, as: UTF8.self)
            #expect(originalText.components(separatedBy: oldLiteral).count == 2, "\(file): old command literal not unique")
            let expected = originalText.replacingOccurrences(of: oldLiteral, with: try literal("~/.claude/clepso/statusline.sh"))
            #expect(String(decoding: installed, as: UTF8.self) == expected, "\(file): more than the command value changed: \(region)")
            for (key, value) in previous where key != "command" {
                #expect((value as AnyObject).isEqual(statusLine[key]), "\(file): statusLine.\(key) changed")
            }
        } else {
            #expect(region.old.isEmpty || region.old == ",", "\(file): existing bytes were rewritten: \(region.old.debugDescription)")
        }
        // Inserted text follows the file's own line endings: no bare LF appears in a CRLF file.
        let crlf = String(decoding: original, as: UTF8.self).contains("\r\n")
        if crlf {
            let text = String(decoding: installed, as: UTF8.self)
            #expect(text.components(separatedBy: "\n").count == text.components(separatedBy: "\r\n").count, "\(file): mixed line endings")
        }
        #expect(box.mode(box.settings) == 0o640, "\(file): file mode not preserved")

        // Backup: exact copy, private.
        let backup = try #require(report.backupPath)
        #expect(box.bytes(URL(fileURLWithPath: backup)) == original)
        #expect(box.mode(URL(fileURLWithPath: backup)) == 0o600)

        #expect(try box.installer().uninstall() == .restoredExactly)
        let restored = try #require(box.bytes(box.settings))
        #expect(restored == original, "\(file): not byte-identical after uninstall")
        #expect(sha(restored) == sha(original))
        #expect(box.mode(box.settings) == 0o640)
        #expect(!box.exists(box.claude.appendingPathComponent("clepso")), "Clepso's files must be removed")
        #expect(box.exists(URL(fileURLWithPath: backup)), "backups are kept for 30 days")
    }

    @Test("Refused files are left untouched and nothing is created", arguments: Sandbox.refused)
    func refusals(file: String) throws {
        let box = try Sandbox(settingsFixture: file); defer { box.cleanUp() }
        let original = box.bytes(box.settings)
        #expect(throws: SettingsInstaller.InstallError.self) { try box.installer().install() }
        #expect(box.bytes(box.settings) == original)
        #expect(!box.exists(box.claude.appendingPathComponent("clepso")))
        #expect(!box.exists(box.claude.appendingPathComponent("clepso-backups")))
    }

    @Test("Without settings.json, install creates it and uninstall deletes it again")
    func createdFile() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        let report = try box.installer().install()
        #expect(report.createdSettingsFile && report.backupPath == nil)
        #expect((jsonObject(try #require(box.bytes(box.settings)))?["statusLine"] as? [String: Any])?["type"] as? String == "command")
        #expect(try box.installer().uninstall() == .deletedCreatedFile)
        #expect(!box.exists(box.settings))
    }

    @Test("No ~/.claude folder means Claude Code is not detected")
    func noClaude() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try FileManager.default.removeItem(at: box.claude)
        #expect(throws: SettingsInstaller.InstallError.claudeNotDetected) { try box.installer().install() }
    }

    @Test("A user edit after install gets a surgical restore that keeps the edit")
    func surgicalRestore() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        let original = try #require(box.bytes(box.settings))
        _ = try box.installer().install()
        var text = String(decoding: try #require(box.bytes(box.settings)), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"theme\": \"dark\"", with: "\"theme\": \"light\"")
        try Data(text.utf8).write(to: box.settings)

        guard case .restoredStatusLineOnly(_, let reformatted) = try box.installer().uninstall() else {
            Issue.record("expected a surgical restore"); return
        }
        #expect(!reformatted)
        let restored = try #require(box.bytes(box.settings))
        let object = try #require(jsonObject(restored))
        #expect(object["theme"] as? String == "light", "the user's edit must survive")
        #expect((object["statusLine"] as? NSDictionary)?.isEqual(to: jsonObject(original)?["statusLine"] as? [String: Any] ?? [:]) == true)
        let expected = String(decoding: original, as: UTF8.self).replacingOccurrences(of: "\"dark\"", with: "\"light\"")
        #expect(String(decoding: restored, as: UTF8.self) == expected, "every byte except the user's edit is the original")
    }

    @Test("Surgical restore without an original status line removes ours and leaves valid JSON")
    func surgicalRemove() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        let original = try #require(box.bytes(box.settings))
        _ = try box.installer().install()
        var text = String(decoding: try #require(box.bytes(box.settings)), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"EDITOR\": \"vim\"", with: "\"EDITOR\": \"nano\"")
        try Data(text.utf8).write(to: box.settings)
        guard case .restoredStatusLineOnly = try box.installer().uninstall() else { Issue.record("expected surgical"); return }
        let restored = String(decoding: try #require(box.bytes(box.settings)), as: UTF8.self)
        #expect(restored == String(decoding: original, as: UTF8.self).replacingOccurrences(of: "vim", with: "nano"))
    }

    @Test("If the user already replaced the command, uninstall leaves settings alone")
    func userReplaced() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        let text = String(decoding: try #require(box.bytes(box.settings)), as: UTF8.self)
            .replacingOccurrences(of: "~/.claude/clepso/statusline.sh", with: "echo mine")
        try Data(text.utf8).write(to: box.settings)
        guard case .leftUnchanged = try box.installer().uninstall() else { Issue.record("expected leftUnchanged"); return }
        #expect(String(decoding: try #require(box.bytes(box.settings)), as: UTF8.self) == text)
        #expect(!box.exists(box.claude.appendingPathComponent("clepso")))
    }

    @Test("A settings change during install aborts without overwriting it")
    func compareAndSwap() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        let settingsPath = box.settings.path
        let installer = box.installer(beforeWrite: {
            let handle = FileHandle(forWritingAtPath: settingsPath)
            handle?.seekToEndOfFile()
            handle?.write(Data(" ".utf8))
            try? handle?.close()
        })
        #expect(throws: SettingsInstaller.InstallError.settingsChangedDuringInstall) { try installer.install() }
        let after = String(decoding: try #require(box.bytes(box.settings)), as: UTF8.self)
        #expect(after.hasSuffix("}\n "), "the concurrent edit must be preserved")
        #expect(!after.contains("statusLine"))
        #expect(!box.exists(box.claude.appendingPathComponent("clepso")))
    }

    @Test("Symlinked settings or backup folder are refused")
    func symlinks() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        let target = box.home.appendingPathComponent("elsewhere.json")
        try Data("{}\n".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: box.settings, withDestinationURL: target)
        #expect(throws: SettingsInstaller.InstallError.self) { try box.installer().install() }
        #expect(box.bytes(target) == Array("{}\n".utf8))

        let box2 = try Sandbox(settingsFixture: "plain.json"); defer { box2.cleanUp() }
        try FileManager.default.createSymbolicLink(at: box2.claude.appendingPathComponent("clepso-backups"),
                                                   withDestinationURL: box2.home)
        #expect(throws: SettingsInstaller.InstallError.symlinkRefused(path: box2.claude.appendingPathComponent("clepso-backups").path)) {
            try box2.installer().install()
        }
    }

    @Test("Disconnect and connect again within one second: each install backs up, and every uninstall is byte-exact")
    func offOnOffSameSecond() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        let original = try #require(box.bytes(box.settings))

        let first = try #require(try box.installer().install().backupPath)    // one fixed clock: the same second throughout
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original)

        // Same second, same bytes, so the same backup name: before the fix this threw `io("create …: errno 17")`.
        #expect(try box.installer().install().backupPath == first, "the identical backup is reused, not duplicated")
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original, "not byte-identical after the second uninstall")

        // A file of that name with other bytes is never overwritten or trusted: the next free name is used instead.
        try Data("not the backup\n".utf8).write(to: URL(fileURLWithPath: first))
        let third = try #require(try box.installer().install().backupPath)
        #expect(third != first && third.hasSuffix(".1.bak"))
        #expect(box.bytes(URL(fileURLWithPath: third)) == original && box.mode(URL(fileURLWithPath: third)) == 0o600)
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original)
    }

    @Test("A second install is refused while one is recorded")
    func alreadyInstalled() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        #expect(throws: SettingsInstaller.InstallError.alreadyInstalled(state: "verified")) { try box.installer().install() }
    }

    @Test("Generated files: modes, config contents, a 32-byte key")
    func generatedFiles() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        let clepso = box.claude.appendingPathComponent("clepso")
        #expect(box.mode(clepso) == 0o700)
        #expect(box.mode(box.claude.appendingPathComponent("clepso-backups")) == 0o700)
        #expect(box.mode(clepso.appendingPathComponent("statusline.sh")) == 0o700)
        for name in ["config.json", "session.key", "original-statusline.json", "install-state.json"] {
            #expect(box.mode(clepso.appendingPathComponent(name)) == 0o600, "\(name) mode")
        }
        #expect(box.bytes(clepso.appendingPathComponent("session.key"))?.count == 32)
        let configBytes = try #require(box.bytes(clepso.appendingPathComponent("config.json")))
        let config = try #require(jsonObject(configBytes))
        #expect(config["v"] as? Int == 1)
        #expect(config["original_command"] as? String == "~/bin/my-status.sh --color 'auto'")
        #expect(config["forward_cost"] as? Bool == true)
        let sidecar = String(decoding: try #require(box.bytes(clepso.appendingPathComponent("original-statusline.json"))), as: UTF8.self)
        #expect(sidecar.hasPrefix("{\n    \"type\": \"command\""), "sidecar keeps the original bytes verbatim")
    }
}

@Suite("Recovery and repair", .serialized)
struct RecoveryTests {
    func rewriteRecord(_ box: Sandbox, _ change: (inout [String: Any]) -> Void) throws {
        let url = box.claude.appendingPathComponent("clepso/install-state.json")
        let raw = try #require(box.bytes(url))
        var record = try #require(jsonObject(raw))
        change(&record)
        try JSONSerialization.data(withJSONObject: record).write(to: url)
    }

    @Test("Interrupted before settings were written, with settings unchanged: clean up")
    func cleanUpPartial() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        let original = box.bytes(box.settings)
        _ = try box.installer().install()
        _ = try box.installer().uninstall()                       // back to the original bytes
        try FileManager.default.createDirectory(at: box.claude.appendingPathComponent("clepso"), withIntermediateDirectories: true)
        let record: [String: Any] = ["state": "files_written", "h0": sha(original ?? []), "createdByPulse": false, "formattingChanged": false]
        try JSONSerialization.data(withJSONObject: record).write(to: box.claude.appendingPathComponent("clepso/install-state.json"))
        #expect(box.installer().recover() == .cleanedUp)
        #expect(box.bytes(box.settings) == original)
        #expect(!box.exists(box.claude.appendingPathComponent("clepso")))
    }

    @Test("Interrupted after settings were written: verify and complete")
    func completeAfterWrite() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        try rewriteRecord(box) { $0["state"] = "settings_written" }
        #expect(box.installer().recover() == .completed)
        #expect(box.installer().recover() == .nothingToRecover)
        #expect(try box.installer().uninstall() == .restoredExactly)
    }

    @Test("Settings changed in an unknown way during an interrupted install: ask, never guess")
    func needsDecision() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        try rewriteRecord(box) { $0["state"] = "files_written"; $0["h0"] = "not-the-current-hash" }
        guard case .needsUserDecision(let backup) = box.installer().recover() else { Issue.record("expected a decision"); return }
        #expect(backup != nil)
    }

    @Test("Repair rewrites only the wrapper and config when the app moved")
    func repairAfterMove() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        let settingsBefore = box.bytes(box.settings)
        let moved = box.installer(shim: "/Users/Shared/Clepso.app/Contents/Helpers/clepso-statusline")
        #expect(moved.needsRepair())
        try moved.repair()
        #expect(!moved.needsRepair())
        #expect(box.bytes(box.settings) == settingsBefore, "repair must not touch settings.json")
        let wrapper = String(decoding: try #require(box.bytes(box.claude.appendingPathComponent("clepso/statusline.sh"))), as: UTF8.self)
        #expect(wrapper.contains("CLEPSO_SHIM='/Users/Shared/Clepso.app/Contents/Helpers/clepso-statusline'"))
    }

    @Test("Approved agent names: written cleaned (agent-name shapes only, once each, sorted), kept by callers that don't pass them, repaired when they differ")
    func approvedAgentNamesInConfig() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        func installer(_ names: [String]?) -> SettingsInstaller {
            SettingsInstaller(paths: .init(home: box.home), shimPath: Sandbox.shim, socketPath: box.home.appendingPathComponent("a.sock").path,
                              forwardCost: true, approvedAgentTypes: names, now: { Sandbox.fixedNow }, beforeSettingsWrite: nil)
        }
        func written() throws -> [String]? {
            let bytes = try #require(box.bytes(box.claude.appendingPathComponent("clepso/config.json")))
            let config = try #require(jsonObject(bytes))
            return config["approved_agent_types"] as? [String]
        }
        _ = try installer(["db-helper", "code-reviewer", "two words", "/Users/x", "Explore", "custom", "code-reviewer"]).install()
        #expect(try written() == ["code-reviewer", "db-helper"])

        #expect(!installer(nil).needsRepair(), "nil means: leave the list alone")
        try installer(nil).repair()
        #expect(try written() == ["code-reviewer", "db-helper"], "a repair that isn't about names keeps them")

        let changed = installer(["code-reviewer"])
        #expect(changed.needsRepair())
        try changed.repair()
        #expect(try written() == ["code-reviewer"] && !changed.needsRepair())
        try installer([]).repair()
        #expect(try written() == [])
        #expect(SettingsInstaller.cleanAgentNames((0..<80).map { "agent-\($0)" }).count == 50, "at most 50")
    }
}

@Suite("Wrapper script behaviour", .serialized)
struct WrapperScriptTests {
    func run(_ script: URL, stdin: String) throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    @Test("Shim present: the wrapper execs it")
    func execsShim() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        let fakeShim = box.home.appendingPathComponent("fake-shim")
        try Data("#!/bin/sh\nprintf SHIM\n".utf8).write(to: fakeShim)
        chmod(fakeShim.path, 0o755)
        _ = try box.installer(shim: fakeShim.path).install()
        #expect(try run(box.claude.appendingPathComponent("clepso/statusline.sh"), stdin: "{}") == ("SHIM", 0))
    }

    @Test("Shim missing: the wrapper runs the user's original command with the same stdin")
    func fallsBackToOriginal() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try Data(#"{"statusLine": {"type": "command", "command": "printf '%s: ' \"it's\"; cat"}}"#.utf8).write(to: box.settings)
        _ = try box.installer(shim: box.home.appendingPathComponent("missing").path).install()
        #expect(try run(box.claude.appendingPathComponent("clepso/statusline.sh"), stdin: "{\"x\":1}") == ("it's: {\"x\":1}", 0))
    }

    @Test("Shim missing and no original command: prints nothing, exits 0")
    func silentFallback() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer(shim: box.home.appendingPathComponent("missing").path).install()
        #expect(try run(box.claude.appendingPathComponent("clepso/statusline.sh"), stdin: "{}") == ("", 0))
    }
}
