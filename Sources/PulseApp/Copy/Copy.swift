import Domain
import Foundation

/// Every string the screens show, named after its UX_SPEC §2 key. Seat 7 owns the wording; change it here only.
enum Copy {
    static let product = Product.name

    enum Header {
        static let title = "AI Capacity"                                         // copy.header.title
        static func updated(_ age: String) -> String { "Updated \(age)" }        // copy.header.updated
    }

    enum Onboarding {
        static let welcomeTitle = "See your AI limits before they stop you"
        static let welcomeBody = "\(product) reads usage your tools already report. It makes no AI calls, uses no tokens, and nothing leaves this Mac."
        static let `continue` = "Continue"
        static let planTitle = "Which Claude plan are you on?"
        static let planBody = "Your plan is only a label next to your usage. \(product) never guesses it from how much you use."
        static let planNotSure = "Not sure"
        static let planConfirmToggle = "I checked this in my Claude account"
        static func providerDetected(_ version: String?) -> String { version.map { "Found Claude Code \($0)" } ?? "Found Claude Code" }
        static let providerNotDetected = "No supported tools found. You can still enter values yourself, or come back after installing Claude Code."
        static let providerManualOnly = "Continue without a connection"
        static let firstReadingWaiting = "Waiting for Claude Code… Send any message in Claude Code and this will update."
        static let firstReadingDemo = "Show demo data instead"
        static func firstReadingReceived(_ time: String) -> String { "First reading received · \(time)" }
        static let alertsTitle = "Warn you before you hit a limit?"
        static let alertsBody = "\(product) can notify you at 80%, 95% and 100% of a limit, and when a reported reset time arrives. You can change this any time."
        static let alertsEnable = "Enable notifications"
        static let alertsSkip = "Not now"
        static func doneConnected(_ time: String) -> String { "Connected · Claude Code · observed \(time)" }
        static let doneWaiting = "Installed · waiting for first reading"
        static let doneOpen = "Open menu bar"
    }

    enum Explainer {
        static let title = "Connect Claude Code"
        static let bodyNoExisting = "To read usage, \(product) sets Claude Code's status line to a small script that runs a signed \(product) helper. Each time Claude Code refreshes its status, the helper reads only these fields: Claude Code version, a hashed session ID, model name, context window size, percent used and token counts, 5-hour and 7-day usage and reset times, a gateway spend limit if your organisation sets one, prompt-cache status, effort and thinking settings, and Claude Code's estimated session cost (an estimate at list price, not your bill; you can turn it off). It never reads your prompts, files, folder paths or transcript. It makes no AI calls and costs no tokens. Your settings file is backed up first, and Remove restores it."
        static let bodyExisting = "You already have a status line in Claude Code. \(product) will run it first and show its output unchanged, then pass the same status data to \(product). If \(product) is slow or not running, your status line still works. Your settings file is backed up first, and Remove restores it."
        static func file(_ path: String) -> String { "File that will change: \(path)" }
        static func backup(_ path: String) -> String { "Backup: \(path)" }
        static func existingCommand(_ command: String) -> String { "Your current status line: \(command)" }
        static let ctaNoExisting = "Install"
        static let ctaExisting = "Install and keep mine"
        static let cancel = "Not now"
        static func installFailed(_ reason: String) -> String { "Couldn't update settings. Nothing was changed. \(reason)" }
        static let restoreExact = "Your settings file will be restored exactly as it was before \(product) installed."
        static let restoreSurgical = "Your settings changed after \(product) installed, so only the \(product) status line entry will be removed. Everything else stays as it is now."
    }

    enum Empty {
        static let noProviderTitle = "Nothing connected yet"
        static let noProviderBody = "Connect Claude Code to see usage here."
        static let noProviderCTA = "Connect…"
        static let noSessions = "No active Claude Code sessions. Start one and it appears here."
    }

    enum Problem {
        static let socket = "\(product) isn't receiving updates. Claude Code is unaffected."
        static let socketCTA = "Reconnect"
        static let storage = "\(product) couldn't open its data file."
        static let notificationsDenied = "Notifications are off in System Settings."
        static let openSystemSettings = "Open System Settings"
    }

    enum Inspector {
        static let title = "Where this number comes from"
        static let field = "Provider field"
        static let source = "Source"
        static let sourceStatusLine = "Claude Code status line"
        static func sourceDemo(_ fixture: String) -> String { "Demo fixture \(fixture)" }
        static let observedAt = "Measured at"
        static let receivedAt = "Received at"
        static let quality = "Quality"
        static let adapterVersion = "Adapter"
        static let providerVersion = "Claude Code version"
        static let ttl = "Considered stale after 10 minutes"
        static let recent = "Last 3 readings"
        static let copy = "Copy details"
        static let absent = "Not sent by provider"
        static func quality(_ q: Quality) -> String {
            switch q {
            case .reported: "Reported by provider"
            case .verified: "Verified by provider"
            case .estimated: "Estimated by provider"
            case .unknown: "Unknown"
            }
        }
    }

    enum Detail {
        static let openUsage = "Open usage in Claude"
        static let changePlan = "Change plan…"
        static func sessions(_ n: Int) -> String { n == 1 ? "1 Claude Code session" : "\(n) Claude Code sessions" }
    }

    enum Footer {
        static let notifications = "Notifications…"
        static let settings = "Settings…"
        static let quit = "Quit"
    }

    enum Settings {
        static let general = "General", notifications = "Notifications", providers = "Providers", plan = "Plan", diagnostics = "Diagnostics"
        static let launchAtLogin = "Open at login"
        static let showPercent = "Show highest usage in menu bar"
        static let test = "Send a test notification"
        static func providerConnected(_ time: String) -> String { "Connected · observed \(time)" }
        static let providerInstalled = "Installed · no readings yet"
        static let providerNotInstalled = "Not installed"
        static let remove = "Remove from Claude Code…"
        static let forwardCost = "Keep Claude Code's API cost estimate"
        static let forwardCostSublabel = "An estimate at list price, not your bill or your plan's usage"
        static let changePlan = "Change plan…"
        static func lastChecked(_ date: String) -> String { "Last checked \(date)" }
        static let notVerified = "Plan name not verified by the provider's page"
        static let save = "Save"
        static let demoToggle = "Show demo data"
    }

    enum DeleteAll {
        static let title = "Delete all \(product) data?"
        static let body = "This removes all stored readings and alerts, and restores your Claude Code settings from the backup."
        static let backups = "Also delete settings backups (~/.claude/pulse-backups)"
        static let confirm = "Delete All"
        static let cancel = "Cancel"
        static func restoreFailed(_ backups: String) -> String {
            "Couldn't restore your Claude Code settings automatically, so nothing was deleted. Your backups are in \(backups)."
        }
        static let done = "All \(product) data was deleted."
        static func leftovers(_ names: [String]) -> String { "Left in place because \(product) didn't create them: \(names.joined(separator: ", "))" }
    }

    enum Export {
        static let button = "Export my data…"
        static func done(_ rows: Int, _ scrubbed: Int) -> String {
            "Exported \(rows) rows. Contains no prompts, paths, keys or transcripts"
                + (scrubbed > 0 ? "; \(scrubbed) value(s) were removed by the privacy check." : ".")
        }
    }

    enum Diagnostics {
        static let log = "Recent events (paths and secrets removed)"
        static let clear = "Clear diagnostics"
        static let empty = "No events yet."
        static let receiving = "Updates from Claude Code"
        static func health(_ h: (accepted: Int, otherUser: Int, malformed: Int, oversize: Int, rateLimited: Int)) -> String {
            "\(h.accepted) received · \(h.malformed) malformed · \(h.oversize) too large · \(h.rateLimited) over the rate limit · \(h.otherUser) from another user"
        }
        static let deleteAll = "Delete all \(product) data…"
    }

    enum Demo {
        static let header = "Demo data · not your account"
        static let exit = "Stop showing demo data"
    }
}
