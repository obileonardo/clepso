import Foundation
import ShimProtocol
import Testing
@testable import ClepsoApp

/// v0.3 (docs/specs/mod-bridge.md): the Claude Code mod through the app, in a throwaway home with the repository's mod
/// as the bundled copy. The real ~/.claude is never read or written.
@MainActor
@Suite("Claude Code mod", .serialized)
struct ClaudeModTests {
    static let original = Data("{\n  \"model\": \"opus\",\n  \"enabledPlugins\": {\"commit-commands@claude-plugins-official\": true}\n}\n".utf8)
    static let repoMod = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("mod/claude-code")

    func model(_ box: Sandbox, clock: TestClock) -> AppModel {
        var environment = box.model(clock: clock).environment
        environment.claudeModDirectory = Self.repoMod
        return AppModel(environment: environment)
    }

    /// A frame as the helper sends it in mod mode: the status-line frame plus `via` and `surface`.
    func modFrame(at: Date, fiveHour: Double) throws -> Data {
        var frame = try FrameCodec.decode(try frameBytes(at: at, fiveHour: fiveHour, session: "fedcba9876543210"))
        guard case .object(var members) = frame else { throw FrameCodec.DecodeError.notObject }
        members["via"] = .string("mod")
        members["surface"] = .string("desktop")
        members["model"] = nil
        frame = .object(members)
        return try FrameCodec.encode(frame)
    }

    @Test("Needs the connection; add, report, remove: settings come back byte for byte, and Delete all takes the mod too")
    func endToEnd() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try Self.original.write(to: box.settings)
        let clock = TestClock()
        let model = model(box, clock: clock)
        await model.start(); defer { model.stop() }
        #expect(await model.setClaudeMod(true) == .failed(reason: Copy.ClaudeMod.needsConnection))
        #expect(try Data(contentsOf: box.settings) == Self.original)

        guard case .installed = await model.install() else { Issue.record("install failed"); return }
        let connected = try Data(contentsOf: box.settings)
        let preview = model.claudeModPreview
        #expect(preview.file == box.settings.path && preview.folder == "~/.claude/clepso/claude-mod")
        #expect(await model.setClaudeMod(true) == .added)
        #expect(model.claudeModOn)
        let text = String(decoding: try Data(contentsOf: box.settings), as: UTF8.self)
        #expect(text.contains("\"clepso-limits@clepso\": true") && text.contains("commit-commands@claude-plugins-official"))

        // Before the first reading: on, waiting. A desktop reading arrives on the mod channel and is shown.
        await model.refreshClaudeModStatus()
        #expect(model.claudeModOn && model.claudeModLastReading == nil)
        #expect(send(model.environment.socketPath, try modFrame(at: clock.now(), fiveHour: 27)))
        #expect(await eventually { model.snapshot.provider?.pools.contains { $0.model.used.value == 27 } == true })
        await model.refreshClaudeModStatus()
        #expect(model.claudeModLastReading != nil)

        #expect(await model.setClaudeMod(false) == .removedExactly)
        #expect(try Data(contentsOf: box.settings) == connected)
        #expect(!model.claudeModOn)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/clepso/claude-mod").path))

        #expect(await model.setClaudeMod(true) == .added)
        let report = await model.deleteAll(includeBackups: false, relaunch: false)
        #expect(report.failure == nil)
        #expect(try Data(contentsOf: box.settings) == Self.original, "Delete all restores settings.json exactly, mod included")
    }

    @Test("disableAllHooks on: refused in plain words, nothing written")
    func modsTurnedOff() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try Data("{\n  \"disableAllHooks\": false\n}\n".utf8).write(to: box.settings)
        let model = model(box, clock: TestClock())
        await model.start(); defer { model.stop() }
        guard case .installed = await model.install() else { Issue.record("install failed"); return }
        let connected = String(decoding: try Data(contentsOf: box.settings), as: UTF8.self)
        let off = connected.replacingOccurrences(of: "\"disableAllHooks\": false", with: "\"disableAllHooks\": true")
        try Data(off.utf8).write(to: box.settings)
        #expect(await model.setClaudeMod(true) == .failed(reason: Copy.ClaudeMod.modsTurnedOff))
        #expect(String(decoding: try Data(contentsOf: box.settings), as: UTF8.self) == off)
        #expect(!model.claudeModOn)
    }

    @Test("Held back in the release until the live test passes; shown in debug builds")
    func releaseFlag() {
        #expect(!ReleaseFeatures.shipping.claudeMod)
        #expect(ReleaseFeatures.all.claudeMod)
    }
}
