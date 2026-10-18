import ClaudeCodeAdapter
import ClepsoApp
import Foundation
import Testing

/// The rename from Pulse to Clepso, end to end with the real helper: an install made before the rename (settings.json
/// running `~/.claude/pulse/statusline.sh` and the hooks), the app launches, and the command Claude Code now finds in
/// settings.json runs the renamed helper, whose frame reaches the app through the socket in the new data folder.
@MainActor
@Suite("Old layout → launch → the renamed helper reaches the app", .serialized)
struct LegacyLayoutEndToEndTests {
    static let original = Data("""
    {
      "theme": "dark",
      "statusLine": {"type": "command", "command": "printf 'mine'"}
    }

    """.utf8)

    @Test("Claude Code's status-line command, as settings.json names it after the move, reaches the app; Remove restores the original")
    func helperReachesAppAfterMove() async throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        let claude = h.home.appendingPathComponent(".claude")
        try FileManager.default.removeItem(at: claude.appendingPathComponent("clepso"))     // the harness's own config
        // Short data folders: a socket path must fit in 104 bytes.
        let data = URL(fileURLWithPath: "/tmp").appendingPathComponent("ce-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: data) }
        let legacyData = data.appendingPathComponent("Pulse"), currentData = data.appendingPathComponent("Clepso")
        try FileManager.default.createDirectory(at: legacyData, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: legacyData.appendingPathComponent("diagnostics.jsonl"))

        // The install as the app made it before the rename.
        try Self.original.write(to: claude.appendingPathComponent("settings.json"))
        let paths = SettingsInstaller.Paths.legacy(home: h.home)
        let oldShim = "/Applications/Clepso.app/Contents/Helpers/pulse-statusline"
        _ = try SettingsInstaller(paths: paths, shimPath: oldShim, socketPath: legacyData.appendingPathComponent("run/agent.sock").path,
                                  now: { Date(timeIntervalSince1970: 1_792_159_200) }).install()
        try HooksInstaller(paths: paths, shimPath: oldShim, now: { Date(timeIntervalSince1970: 1_792_159_200) }).install()

        let model = AppModel(environment: AppEnvironment(
            dataDirectory: currentData, home: h.home, shimPath: ShimHarness.shimURL.path,
            loginItem: NoLoginItem(), notifications: NoNotifications(), keychain: NoKeychain(), appVersion: "0.1.0-test",
            legacyDataDirectory: legacyData))
        await model.start(); defer { model.stop() }
        #expect(model.problem == nil)
        #expect(!FileManager.default.fileExists(atPath: legacyData.path) && !FileManager.default.fileExists(atPath: claude.appendingPathComponent("pulse").path))

        // What Claude Code runs: the command in settings.json, through /bin/sh, with the user's HOME.
        let settings = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: claude.appendingPathComponent("settings.json"))) as? [String: Any])
        let command = try #require((settings["statusLine"] as? [String: Any])?["command"] as? String)
        #expect(command == "~/.claude/clepso/statusline.sh")
        let result = try h.run(stdin: CanaryLeakTests.payload(nowSeconds: ShimHarness.fixtureNowMs / 1000),
                               executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command])
        #expect(result.status == 0)
        #expect(result.text == "mine", "the user's own status line still prints, unchanged")
        let deadline = Date().addingTimeInterval(5)
        while model.snapshot.provider?.pools.first?.model.used.value != 41, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.snapshot.provider?.pools.first?.model.used.value == 41, "the renamed helper's frame reached the app")

        // A hook event through the hook command also exits 0 (it never blocks Claude Code).
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let stop = try #require(((hooks["Stop"] as? [Any])?.first as? [String: Any])?["hooks"] as? [[String: Any]])
        let hookCommand = try #require(stop.first?["command"] as? String)
        #expect(hookCommand.contains("~/.claude/clepso/hook.sh"))
        let hook = try h.run(stdin: Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8),
                             executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", hookCommand])
        #expect(hook.status == 0 && hook.stdout.isEmpty)

        #expect(await model.uninstall() == .restoredExactly)
        #expect(try Data(contentsOf: claude.appendingPathComponent("settings.json")) == Self.original)
    }
}
