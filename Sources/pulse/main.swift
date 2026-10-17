import ClaudeCodeAdapter
import Darwin
import Foundation

// Headless CLI (ARCHITECTURE.md §2). For now: the reversible status-line install, used for the first
// real capture before the app exists. `install` and `uninstall` only preview unless --confirm is given.

let usage = """
usage: pulse install   --shim <helper path> [--socket <path>] [--confirm]
       pulse uninstall [--confirm]
       pulse status
       pulse recover

Without --confirm, install and uninstall print what they would change and touch nothing.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}
let confirmed = arguments.contains("--confirm")
let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
let paths = SettingsInstaller.Paths(home: home)
let defaultSocket = home.appendingPathComponent("Library/Application Support/Pulse/run/agent.sock").path

func installer(shim: String = "", socket: String = defaultSocket) -> SettingsInstaller {
    SettingsInstaller(paths: paths, shimPath: shim, socketPath: socket)
}

func describe(_ url: URL) -> String {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return "absent" }
    return "\(info.st_size) bytes, mode \(String(info.st_mode & 0o777, radix: 8))"
}

switch arguments.first {
case "install":
    guard let shim = option("--shim") else { print(usage); exit(2) }
    let socket = option("--socket") ?? defaultSocket
    print("Settings file:   \(paths.settings.path) (\(describe(paths.settings)))")
    print("Backup folder:   \(paths.backupsDir.path)")
    print("Change:          statusLine.command = \"\(paths.commandValue)\" (only this key)")
    print("Wrapper runs:    \(shim)")
    print("Readings go to:  \(socket)")
    guard confirmed else { print("\nPreview only. Nothing was changed. Re-run with --confirm to install."); exit(0) }
    do {
        let report = try installer(shim: shim, socket: socket).install()
        print("\nInstalled. Backup: \(report.backupPath ?? "none (settings.json was created)")")
        print(report.hadExistingStatusLine ? "Your existing status line still runs first." : "No previous status line; the helper prints its own line.")
    } catch {
        print("\nNot installed: \(error). Nothing was changed."); exit(1)
    }

case "uninstall":
    let record = paths.record
    print("Install record:  \(record.path) (\(describe(record)))")
    guard confirmed else { print("\nPreview only. Re-run with --confirm to restore your settings."); exit(0) }
    do {
        let outcome = try installer().uninstall()
        print("\nUninstall: \(outcome)")
    } catch {
        print("\nUninstall failed: \(error). Backups are in \(paths.backupsDir.path)"); exit(1)
    }

case "status":
    print("settings.json:   \(describe(paths.settings))")
    print("install record:  \(describe(paths.record))")
    if let data = FileManager.default.contents(atPath: paths.record.path) { print(String(decoding: data, as: UTF8.self)) }

case "recover":
    print("Recovery: \(installer().recover())")

default:
    print(usage)
    exit(arguments.isEmpty ? 0 : 2)
}
