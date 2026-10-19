import Domain
import Foundation

/// v0.3: limits from the Claude desktop app and the VS Code panel (docs/specs/mod-bridge.md §8, §10).
extension Copy {
    enum ClaudeMod {
        static let toggle = "Desktop app and VS Code panel"
        static let toggleSublabel = "Limits from the Claude desktop app's Code tab and the VS Code panel, through a small Claude Code mod"
        static let needsConnection = "Connect Claude Code first"
        static func lastReading(_ age: String) -> String { "On · last reading from the desktop app or VS Code \(age)" }
        static let waiting = "On · nothing from the desktop app or VS Code yet. It starts with your next Claude session there. If your organisation turns Claude Code mods off, \(Product.name) still counts tasks there, but not limits."
        static let confirmTitle = "Read limits from the desktop app?"
        static func confirmBody(_ file: String) -> String {
            "\(Product.name) adds its own small Claude Code mod, clepso-limits, and turns it on in \(file). After each reply in the Claude desktop app's Code tab or the VS Code panel, it hands \(Product.name) your plan-limit percentages, when they reset, and how full the context window is. Nothing else: no prompts, replies, file paths, transcripts or passwords, and nothing leaves your Mac. Terminal sessions keep using the status line. The two entries it adds:"
        }
        static func scopeBody(_ folder: String) -> String {
            "A mod runs inside Claude Code with your permissions, so this one is kept to one hook and four calls: session.surfaces, session.id, session.version and process.run (to start \(Product.name)'s helper). Its source is in \(folder)."
        }
        static let offBody = "It starts with your next Claude session. Turning it off takes both entries out again; if nothing else changed, settings.json is restored byte for byte. If your organisation turns Claude Code mods off, \(Product.name) still counts tasks there, but not limits."
        static let add = "Add the mod", cancel = "Cancel"
        static let added = "Mod added. Limits from the desktop app and VS Code arrive from your next Claude session there."
        static let removedExact = "Mod removed. Claude Code's settings are byte-for-byte as before."
        static let removedEntries = "Mod removed. Your other changes to Claude Code's settings were kept."
        static let alreadyGone = "The mod was already gone from Claude Code's settings."
        static func failed(_ reason: String) -> String { "Couldn't change Claude Code's settings: \(reason). Nothing was changed." }
        static let modsTurnedOff = "disableAllHooks is on in settings.json, so Claude Code would run no mod (and no status line)"
        static let conflicting = "settings.json already names a clepso marketplace or the clepso-limits plugin; remove it first"
    }
}
