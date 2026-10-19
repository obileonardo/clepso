import Darwin
import Foundation
import Testing
@testable import ClaudeCodeAdapter

/// v0.3 (docs/specs/mod-bridge.md §9): the mod's two settings entries go in and come out without disturbing anything
/// else in settings.json, with the status line's and hooks' guarantees. Every test runs in a throwaway HOME with the
/// repository's mod as the "bundled" copy; the real ~/.claude is never read or written.
@Suite("Claude Code mod install and uninstall", .serialized)
struct ClaudeModInstallerTests {
    static let repoMod = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("mod/claude-code")

    func mod(_ box: Sandbox, bundled: URL = ClaudeModInstallerTests.repoMod, shim: String = Sandbox.shim,
             beforeWrite: (@Sendable () -> Void)? = nil) -> ClaudeModInstaller {
        ClaudeModInstaller(paths: .init(home: box.home), shimPath: shim, bundledMod: bundled, now: { Sandbox.fixedNow },
                           beforeSettingsWrite: beforeWrite)
    }

    /// Settings with plugin entries of the user's own, in both objects the mod adds to. Kept here rather than in the
    /// settings corpus, whose lint forbids "@" (every plugin id has one).
    static let withPlugins = """
    {
      "model": "opus",
      "enabledPlugins": {
        "commit-commands@claude-plugins-official": true,
        "experimental@personal": false
      },
      "extraKnownMarketplaces": {
        "team-tools": {
          "source": {
            "source": "github",
            "repo": "acme-corp/claude-plugins"
          }
        }
      },
      "statusLine": {
        "type": "command",
        "command": "echo hi"
      }
    }

    """

    func write(_ text: String, to box: Sandbox) throws {
        try Data(text.utf8).write(to: box.settings)
        chmod(box.settings.path, 0o640)
    }

    func text(_ box: Sandbox) -> String? { box.bytes(box.settings).map { String(decoding: $0, as: UTF8.self) } }

    /// Whether `old` survives in `new` byte for byte and in order (only insertions happened). Independent of the
    /// installer's scanner.
    static func isSubsequence(_ old: [UInt8], of new: [UInt8]) -> Bool {
        var i = 0
        for byte in new where i < old.count && byte == old[i] { i += 1 }
        return i == old.count
    }

    @Test("Across the settings corpus (and settings with plugins of their own): the two entries go in after the status line, only they are new, and removal is byte-exact",
          arguments: Sandbox.installable + ["(with plugins)"])
    func roundTrip(file: String) throws {
        let box = try Sandbox(settingsFixture: file == "(with plugins)" ? nil : file); defer { box.cleanUp() }
        if file == "(with plugins)" { try write(Self.withPlugins, to: box) }
        let original = try #require(box.bytes(box.settings))
        _ = try box.installer().install()
        let withStatusLine = try #require(box.bytes(box.settings))
        let installer = mod(box)
        try installer.install()

        let installed = try #require(box.bytes(box.settings))
        let object = try #require(jsonObject(installed), "\(file): not valid JSON after adding the mod")
        let before = try #require(jsonObject(withStatusLine))
        for (key, value) in before where key != "enabledPlugins" && key != "extraKnownMarketplaces" {
            #expect((value as AnyObject).isEqual(object[key]), "\(file): \(key) changed")
        }
        let marketplaces = try #require(object["extraKnownMarketplaces"] as? [String: Any])
        let plugins = try #require(object["enabledPlugins"] as? [String: Any])
        #expect(plugins["clepso-limits@clepso"] as? Bool == true)
        let source = try #require((marketplaces["clepso"] as? [String: Any])?["source"] as? [String: Any])
        #expect(source["source"] as? String == "directory")
        #expect(source["path"] as? String == box.claude.appendingPathComponent("clepso/claude-mod").path)
        for (key, value) in (before["extraKnownMarketplaces"] as? [String: Any] ?? [:]) { #expect((value as AnyObject).isEqual(marketplaces[key])) }
        for (key, value) in (before["enabledPlugins"] as? [String: Any] ?? [:]) { #expect((value as AnyObject).isEqual(plugins[key])) }
        // Bytes only added, never rewritten or removed: every original byte is still there, in order, and only
        // Clepso's two entries (and their separators and indentation) were inserted around them.
        #expect(Self.isSubsequence(withStatusLine, of: installed), "\(file): existing bytes were rewritten")
        #expect(installed.count - withStatusLine.count < 400, "\(file): more than the two entries were added")
        if String(decoding: withStatusLine, as: UTF8.self).contains("\r\n") {
            let t = String(decoding: installed, as: UTF8.self)
            #expect(t.components(separatedBy: "\n").count == t.components(separatedBy: "\r\n").count, "\(file): mixed line endings")
        }
        #expect(box.mode(box.settings) == 0o640)
        #expect(box.mode(box.claude.appendingPathComponent("clepso/mod-handoff.sh")) == 0o700)
        #expect(box.mode(box.claude.appendingPathComponent("clepso/claude-mod")) == 0o700)
        #expect(box.mode(box.claude.appendingPathComponent("clepso/claude-mod/plugins/clepso-limits/hooks/register.js")) == 0o600)

        #expect(try installer.uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == withStatusLine, "\(file): not byte-identical after removing the mod")
        #expect(!box.exists(box.claude.appendingPathComponent("clepso/claude-mod")))
        #expect(!box.exists(box.claude.appendingPathComponent("clepso/mod-handoff.sh")))
        #expect(!installer.isInstalled)
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original, "\(file): status line uninstall no longer exact")
    }

    @Test("The copied mod is byte-identical to the bundled one, and the hand-off script execs the helper with --mod")
    func files() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        let installer = mod(box)
        try installer.install()
        let bundled = try installer.bundledFiles()
        #expect(bundled.contains { $0.path == "plugins/clepso-limits/hooks/register.js" })
        for file in bundled {
            #expect(box.bytes(installer.marketplaceDir.appendingPathComponent(file.path)) == file.bytes, "\(file.path)")
        }
        let script = try #require(box.bytes(box.claude.appendingPathComponent("clepso/mod-handoff.sh")).map { String(decoding: $0, as: UTF8.self) })
        #expect(script.contains("CLEPSO_SHIM='\(Sandbox.shim)'\n") && script.contains("exec \"$CLEPSO_SHIM\" --mod"))
        #expect(!installer.needsRepair())
        // The app moved: only the script is rewritten; settings.json is not touched.
        let settings = box.bytes(box.settings)
        let moved = mod(box, shim: "/Users/someone/Applications/Clepso.app/Contents/Helpers/clepso-statusline")
        #expect(moved.needsRepair())
        try moved.repair()
        #expect(!moved.needsRepair() && box.bytes(box.settings) == settings)
        // A file of the installed copy changed (an update brought a new version): repair copies the bundle again.
        try Data("// edited\n".utf8).write(to: installer.marketplaceDir.appendingPathComponent("plugins/clepso-limits/hooks/register.js"))
        #expect(moved.needsRepair())
        try moved.repair()
        #expect(!moved.needsRepair() && box.bytes(box.settings) == settings)
    }

    @Test("Existing plugin entries stay, the user's later edit stays, and only Clepso's members come out")
    func surgical() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try write(Self.withPlugins, to: box)
        _ = try box.installer().install()
        let withStatusLine = try #require(text(box))
        let installer = mod(box)
        try installer.install()
        let installed = try #require(text(box))
        try write(installed.replacingOccurrences(of: "\"model\": \"opus\"", with: "\"model\": \"sonnet\""), to: box)
        #expect(try installer.uninstall() == .removedEntries(formattingChanged: false))
        #expect(text(box) == withStatusLine.replacingOccurrences(of: "\"model\": \"opus\"", with: "\"model\": \"sonnet\""))
    }

    @Test("Keys Clepso created go again once empty; a user's own entry added to them since is kept")
    func createdKeys() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try write("{\n  \"model\": \"opus\"\n}\n", to: box)
        _ = try box.installer().install()
        let withStatusLine = try #require(text(box))
        let installer = mod(box)
        try installer.install()
        // The user enables another plugin in the object Clepso created.
        let edited = try #require(text(box)).replacingOccurrences(of: "\"clepso-limits@clepso\": true", with: "\"clepso-limits@clepso\": true, \"other@market\": true")
        try write(edited, to: box)
        #expect(try installer.uninstall() == .removedEntries(formattingChanged: false))
        let after = try #require(box.bytes(box.settings))
        let object = try #require(jsonObject(after))
        #expect((object["enabledPlugins"] as? [String: Any])?.keys.sorted() == ["other@market"])
        #expect(object["extraKnownMarketplaces"] == nil, "the emptied marketplaces key Clepso created is gone")
        let before = try #require(jsonObject(Array(withStatusLine.utf8)))
        #expect(Set(object.keys) == Set(before.keys).union(["enabledPlugins"]))
    }

    @Test("Refused without touching anything: plugin entries of another shape, a conflicting entry, mods turned off", arguments: [
        #"{"enabledPlugins": []}"#,
        #"{"extraKnownMarketplaces": "x"}"#,
        #"{"enabledPlugins": {}, "enabledPlugins": {}}"#,
        #"{"enabledPlugins": {"clepso-limits@clepso": false}}"#,
        #"{"extraKnownMarketplaces": {"clepso": {"source": {"source": "github", "repo": "someone/clepso"}}}}"#,
        #"{"additionalMarketplaces": {"clepso": {"source": {"source": "directory", "path": "/tmp/x"}}}}"#,
        #"{"disableAllHooks": true}"#,
    ])
    func refusals(settings: String) throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try write("{}\n", to: box)
        _ = try box.installer().install()
        try write(settings, to: box)
        #expect(throws: ClaudeModInstaller.InstallError.self) { try mod(box).install() }
        #expect(text(box) == settings)
        #expect(!mod(box).isInstalled)
        #expect(!box.exists(box.claude.appendingPathComponent("clepso/claude-mod")))
        #expect(!box.exists(box.claude.appendingPathComponent("clepso/mod-handoff.sh")))
    }

    @Test("Needs the status line; a missing bundle and a concurrent edit stop it before settings.json changes")
    func preconditions() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        #expect(throws: ClaudeModInstaller.InstallError.connectionNotInstalled) { try mod(box).install() }
        _ = try box.installer().install()
        let before = try #require(box.bytes(box.settings))
        #expect(throws: ClaudeModInstaller.InstallError.bundleMissing) { try mod(box, bundled: box.home.appendingPathComponent("nowhere")).install() }
        #expect(box.bytes(box.settings) == before)
        let settings = box.settings
        let racing = mod(box) { try? Data("{\"edited\": true}\n".utf8).write(to: settings) }
        #expect(throws: ClaudeModInstaller.InstallError.settingsChangedDuringInstall) { try racing.install() }
        #expect(!racing.isInstalled && !box.exists(box.claude.appendingPathComponent("clepso/claude-mod")))
        #expect(throws: ClaudeModInstaller.InstallError.alreadyInstalled) { try { try mod(box).install(); try mod(box).install() }() }
    }

    @Test("Removal after the user took the entries out by hand changes nothing; a marketplace pointed elsewhere is left alone")
    func alreadyGone() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        try write(Self.withPlugins, to: box)
        _ = try box.installer().install()
        let withStatusLine = try #require(box.bytes(box.settings))
        let installer = mod(box)
        try installer.install()
        try Data(withStatusLine).write(to: box.settings)
        #expect(try installer.uninstall() == .entriesAlreadyGone)
        #expect(box.bytes(box.settings) == withStatusLine)
        #expect(!installer.isInstalled && !box.exists(installer.marketplaceDir))

        // The user re-pointed "clepso" at their own folder: Clepso removes its plugin entry only.
        try installer.install()
        let repointed = try #require(text(box)).replacingOccurrences(of: installer.marketplaceDir.path, with: "/Users/someone/own")
        try write(repointed, to: box)
        #expect(try installer.uninstall() == .removedEntries(formattingChanged: false))
        let after = try #require(box.bytes(box.settings))
        let object = try #require(jsonObject(after))
        #expect((object["extraKnownMarketplaces"] as? [String: Any])?["clepso"] != nil)
        #expect((object["enabledPlugins"] as? [String: Any])?["clepso-limits@clepso"] == nil)
    }

    @Test("The consent preview is exactly what is written")
    func preview() throws {
        let box = try Sandbox(settingsFixture: "plain.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        let installer = mod(box)
        try installer.install()
        let written = try #require(text(box))
        for line in installer.previewEntries.split(separator: "\n") {
            let inner = line.drop { $0 != "{" }.dropFirst().dropLast()           // the member inside the outer braces
            #expect(written.contains(String(inner)), "\(inner)")
        }
    }
}
