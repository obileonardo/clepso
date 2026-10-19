import ClaudeCodeAdapter
import Domain
import Foundation

/// v0.3 "Claude, everywhere" (docs/specs/mod-bridge.md): Settings › Claude Code › "Desktop app and VS Code panel",
/// after its consent sheet. Behind `ReleaseFeatures.claudeMod`.
extension AppModel {
    public enum ClaudeModOutcome: Equatable, Sendable { case added, removedExactly, removedEntries, alreadyGone, failed(reason: String) }

    public func setClaudeMod(_ on: Bool) async -> ClaudeModOutcome {
        let mod = Self.claudeMod(environment)
        defer {
            claudeModOn = mod.isInstalled
            Task { await refresh() }
        }
        do {
            if on {
                try mod.install()
                diagnostics.record(.claudeMod(outcome: "added"))
                return .added
            }
            let outcome = try mod.uninstall()
            diagnostics.record(.claudeMod(outcome: Self.caseName(outcome)))
            return switch outcome {
            case .restoredExactly: .removedExactly
            case .removedEntries: .removedEntries
            case .notInstalled, .entriesAlreadyGone: .alreadyGone
            }
        } catch {
            diagnostics.record(.claudeMod(outcome: "refused " + Self.caseName(error)))
            return .failed(reason: Self.claudeModReason(error))
        }
    }

    /// What the consent sheet shows before anything is written: the file, the two entries, and where the mod's source goes.
    public var claudeModPreview: (file: String, entries: String, folder: String) {
        let mod = Self.claudeMod(environment)
        return (mod.paths.settings.path, mod.previewEntries,
                "~" + mod.marketplaceDir.path.dropFirst(environment.home.path.count))
    }

    /// The Settings line: on and reporting, on and waiting for a first reading, or the plain explanation.
    func refreshClaudeModStatus() async {
        claudeModOn = Self.claudeMod(environment).isInstalled
        claudeModLastReading = claudeModOn ? (try? await store?.lastReading(channel: .mod)) ?? nil : nil
    }

    static func claudeMod(_ environment: AppEnvironment) -> ClaudeModInstaller {
        let bundled = environment.claudeModDirectory ?? URL(fileURLWithPath: environment.shimPath)
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/claude-code")
        return ClaudeModInstaller(paths: .init(home: environment.home), shimPath: environment.shimPath, bundledMod: bundled,
                                  now: { [clock = environment.clock] in clock.now() })
    }

    static func claudeModReason(_ error: Error) -> String {
        switch error as? ClaudeModInstaller.InstallError {
        case .connectionNotInstalled: Copy.ClaudeMod.needsConnection
        case .modsTurnedOff: Copy.ClaudeMod.modsTurnedOff
        case .conflictingEntry: Copy.ClaudeMod.conflicting
        case .unsupportedExistingEntries: "its plugin settings have a shape \(Product.name) can't edit safely"
        case .settingsInvalidJSON: "settings.json isn't valid JSON"
        case .settingsChangedDuringInstall: "settings.json changed while \(Product.name) was writing; try again"
        case .alreadyInstalled: "the mod is already there"
        case .bundleMissing: "this copy of \(Product.name) is missing its mod; reinstall \(Product.name)"
        case .verificationFailed: "the result didn't check out, so it was put back"
        default: "\(error)"
        }
    }
}
