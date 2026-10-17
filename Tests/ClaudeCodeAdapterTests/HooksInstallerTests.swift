import Darwin
import Foundation
import Testing
@testable import ClaudeCodeAdapter

/// Increment 1.9: the agents-per-task hooks go in and come out without disturbing anything else in settings.json.
/// Every test runs in a throwaway HOME; the real ~/.claude is never read or written.
@Suite("Hooks install and uninstall", .serialized)
struct HooksInstallerTests {
    func hooks(_ box: Sandbox, beforeWrite: (@Sendable () -> Void)? = nil) -> HooksInstaller {
        HooksInstaller(paths: .init(home: box.home), shimPath: Sandbox.shim, now: { Sandbox.fixedNow }, beforeSettingsWrite: beforeWrite)
    }

    func write(_ text: String, to box: Sandbox) throws {
        try Data(text.utf8).write(to: box.settings)
        chmod(box.settings.path, 0o640)
    }

    func entries(_ object: [String: Any], _ event: String, command: String) -> Int {
        ((object["hooks"] as? [String: Any])?[event] as? [Any] ?? []).filter { element in
            ((element as? [String: Any])?["hooks"] as? [Any])?.contains { ($0 as? [String: Any])?["command"] as? String == command } ?? false
        }.count
    }

    @Test("Across the settings corpus: hooks added after the status line come out leaving the file byte-identical", arguments: Sandbox.installable)
    func roundTrip(file: String) throws {
        let box = try Sandbox(settingsFixture: file); defer { box.cleanUp() }
        let original = try #require(box.bytes(box.settings))
        _ = try box.installer().install()
        let withStatusLine = try #require(box.bytes(box.settings))
        let installer = hooks(box)
        try installer.install()

        let installed = try #require(box.bytes(box.settings))
        let object = try #require(jsonObject(installed), "\(file): not valid JSON after adding hooks")
        let before = try #require(jsonObject(withStatusLine))
        for (key, value) in before {
            #expect((value as AnyObject).isEqual(object[key]), "\(file): \(key) changed")
        }
        for event in HooksInstaller.events {
            #expect(entries(object, event, command: installer.commandValue) == 1, "\(file): \(event) entry missing")
        }
        let entry = try #require(((object["hooks"] as? [String: Any])?["Stop"] as? [Any])?.first as? [String: Any])
        let handler = try #require((entry["hooks"] as? [Any])?.first as? [String: Any])
        #expect(handler["async"] as? Bool == true && handler["type"] as? String == "command" && entry["matcher"] == nil)
        let region = changedRegion(withStatusLine, installed)
        #expect(region.old.isEmpty || region.old == ",", "\(file): existing bytes were rewritten: \(region.old.debugDescription)")
        if String(decoding: withStatusLine, as: UTF8.self).contains("\r\n") {
            let text = String(decoding: installed, as: UTF8.self)
            #expect(text.components(separatedBy: "\n").count == text.components(separatedBy: "\r\n").count, "\(file): mixed line endings")
        }
        #expect(box.mode(box.settings) == 0o640)
        #expect(box.mode(box.claude.appendingPathComponent("pulse/hook.sh")) == 0o700)

        #expect(try installer.uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == withStatusLine, "\(file): not byte-identical after removing the hooks")
        #expect(!box.exists(box.claude.appendingPathComponent("pulse/hook.sh")))
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original, "\(file): status line uninstall no longer exact")
    }

    static let withUserHooks = """
    {
      "theme": "dark",
      "hooks": {
        "Stop": [
          {
            "hooks": [{"type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff"}]
          }
        ],
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo checked"}]}]
      }
    }

    """

    @Test("The user's own hooks stay, Pulse's entry is appended after them, and only Pulse's comes out")
    func coexists() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try write(Self.withUserHooks, to: box)
        _ = try box.installer().install()
        let withStatusLine = try #require(box.bytes(box.settings))
        let installer = hooks(box)
        try installer.install()

        let installedBytes = try #require(box.bytes(box.settings))
        let object = try #require(jsonObject(installedBytes))
        let hooks = try #require(object["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as? [Any])?.first as? [String: Any])?["command"] as? String == "afplay /System/Library/Sounds/Glass.aiff")
        #expect(entries(object, "Stop", command: installer.commandValue) == 1)
        #expect((hooks["PreToolUse"] as? [Any])?.count == 1, "an event Pulse doesn't use was changed")

        // The user edits another setting afterwards: only Pulse's entries come out, the edit stays, bytes elsewhere unchanged.
        let installed = String(decoding: installedBytes, as: UTF8.self)
        try write(installed.replacingOccurrences(of: "\"theme\": \"dark\"", with: "\"theme\": \"light\""), to: box)
        #expect(try installer.uninstall() == .removedEntries(formattingChanged: false))
        let expected = String(decoding: withStatusLine, as: UTF8.self).replacingOccurrences(of: "\"theme\": \"dark\"", with: "\"theme\": \"light\"")
        #expect(box.bytes(box.settings).map { String(decoding: $0, as: UTF8.self) } == expected)
    }

    @Test("Removal after the user deleted Pulse's entries by hand changes nothing")
    func alreadyGone() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try write(Self.withUserHooks, to: box)
        _ = try box.installer().install()
        let withStatusLine = try #require(box.bytes(box.settings))
        let installer = hooks(box)
        try installer.install()
        try Data(withStatusLine).write(to: box.settings)
        #expect(try installer.uninstall() == .entriesAlreadyGone)
        #expect(box.bytes(box.settings) == withStatusLine)
        #expect(!installer.isInstalled)
    }

    @Test("Shapes the editor can't change safely are refused and the file is untouched", arguments: [
        #"{"hooks": []}"#,
        #"{"hooks": {"Stop": {"hooks": []}}}"#,
        #"{"hooks": {"Stop": []}, "hooks": {}}"#,
    ])
    func refusals(text: String) throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try write("{}\n", to: box)
        _ = try box.installer().install()
        try write(text, to: box)
        #expect(throws: HooksInstaller.InstallError.self) { try hooks(box).install() }
        #expect(box.bytes(box.settings).map { String(decoding: $0, as: UTF8.self) } == text)
        #expect(!hooks(box).isInstalled)
    }

    @Test("Hooks need the status-line connection, and a concurrent edit stops the write")
    func preconditions() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        #expect(throws: HooksInstaller.InstallError.connectionNotInstalled) { try hooks(box).install() }
        _ = try box.installer().install()
        let before = try #require(box.bytes(box.settings))
        let settings = box.settings
        let racing = hooks(box) { try? Data("{\"edited\": true}\n".utf8).write(to: settings) }
        #expect(throws: HooksInstaller.InstallError.settingsChangedDuringInstall) { try racing.install() }
        #expect(box.bytes(box.settings) != before && !racing.isInstalled)
    }

    @Test("The hook command exits 0 silently whether or not the app is there")
    func commandNeverFails() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        let installer = hooks(box)
        // Run the command as Claude Code would, with HOME pointing at the sandbox: script missing, then present
        // but pointing at a helper that doesn't exist (the app was deleted).
        func run() throws -> (Int32, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", installer.commandValue]
            process.environment = ["HOME": box.home.path, "PATH": "/usr/bin:/bin"]
            let out = Pipe(), input = Pipe()
            process.standardOutput = out
            process.standardError = out
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(#"{"hook_event_name": "Stop", "session_id": "s", "prompt": "secret"}"#.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        #expect(try run() == (0, ""))
        try installer.install()
        #expect(try run() == (0, ""))
    }
}
