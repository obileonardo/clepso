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
        static let bodyNoExisting = "To read usage, \(product) sets Claude Code's status line to a small script that runs a signed \(product) helper. Each time Claude Code refreshes its status, the helper reads only these fields: Claude Code version, a hashed session ID, model name, context window size, percent used and token counts, 5-hour and 7-day usage and reset times, a gateway spend limit if your organisation sets one, prompt-cache status, effort and thinking settings, session time and the number of lines of code changed, and Claude Code's estimated session cost (an estimate at list price, not your bill; you can turn it off). It never reads your prompts, files, folder paths or transcript. It makes no AI calls and costs no tokens. Your settings file is backed up first, and Remove restores it."
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

    /// Increment 1.7e: the Details window.
    enum Details {
        static let open = "Details", openStats = "Stats"
        static let limits = "Limits", session = "Session", stats = "Stats", you = "You"
        static let now = "NOW"
        static func resets(_ time: String) -> String { "RESETS \(time.uppercased())" }
        static let noLimits = "No limits reported yet. They appear after your next Claude Code message."
        static func noHistory(_ scope: String) -> String { "\(scope) usage history: no readings yet" }
        static func historySummary(scope: String, from: Int, to: Int, readings: Int) -> String {
            "\(scope) usage history: from \(from) to \(to) percent over \(readings) readings"
        }
        static let unknownModel = "Unknown model"
        static let context = "CONTEXT"
        static func contextShort(_ pct: String) -> String { "Context \(pct)" }
        static let tokensIn = "Tokens in", tokensOut = "Tokens out", costEstimate = "Cost est.", cacheHits = "Cache hits"
        static let apiTime = "API time", wallTime = "Wall time", lines = "Lines +/−", cacheState = "Cache"
        static let warm = "Warm", cold = "Cold"
        static func cacheCounts(requests: Int64, misses: Int64) -> String { "Cache · \(requests) req · \(misses) miss" }
        static let costNote = "Cost is Claude Code's estimate at API list price for this session. It is not your bill and not your plan's usage."
        static let byModel = "BY MODEL · LAST 30 DAYS"
        static func groupLine(sessions: Int, cost: String, lines: String, api: String, share: Int) -> String {
            "\(sessions) session\(sessions == 1 ? "" : "s") · \(cost) est. · +\(lines) lines · \(api) API · \(share)% of cost"
        }
        static let usage = "Usage"
        static let limitsSubtitle = "Each limit over its own window, with readings, thresholds and a pace estimate"
        static let sessionSubtitle = "The current Claude Code session in full, and recent ones beside it"
        static let notWatching = "NOT WATCHING YET"
        static let recentSessions = "RECENT SESSIONS"
        static let byModelNote = "Grouped by each session's main model. Claude Code also uses smaller models in the background; those count under the main one. For exact per-model figures, see Stats."
    }

    /// Increment 1.7f: Stats from Claude Code's own statistics file.
    enum Stats {
        static let explainerTitle = "SHOW YOUR CLAUDE CODE STATS?"
        static let explainerBody = "Claude Code keeps a statistics file for /stats (~/.claude/stats-cache.json). \(product) can read it to show your activity, streaks and tokens per model. It reads only dates, counts and model names; never session ids, prompts or paths. Nothing from it is stored or exported. You can turn this off in Settings › Providers."
        static let enable = "Show my stats"
        static let missing = "Claude Code's statistics file wasn't found. It appears after Claude Code has computed /stats at least once."
        static let unreadable = "Claude Code's statistics file couldn't be read. Its format may have changed."
        static let overview = "Overview", models = "Models"
        static let allTime = "All time", last30 = "30 days", last7 = "7 days"
        static let favorite = "Favorite model", totalTokens = "Total tokens", sessions = "Sessions", longestSession = "Longest session"
        static let activeDays = "Active days", currentStreak = "Current streak", longestStreak = "Longest streak", mostActive = "Most active day"
        static let tokensPerDay = "TOKENS PER DAY"
        static func through(_ day: String) -> String {
            "From Claude Code's statistics file, which covers days up to \(day). Today's tokens appear tomorrow; today counts as active when \(product) has seen Claude Code today."
        }
        static func heatmapSummary(active: Int, of days: Int) -> String { "Activity: \(active) active days of \(days)" }
        static func chartSummary(days: Int, models: Int) -> String { "Tokens per day for \(models) models over \(days) days" }
        static func modelBreakdown(input: String, output: String, read: String, write: String) -> String {
            "In \(input) · Out \(output) · Cache \(read) read · \(write) write"
        }
        static let rangeLabel = "Range", viewLabel = "View", arena = "Arena", chart = "Chart"
        static let overviewSubtitle = "Your Claude Code activity, from its own statistics file"
        static let modelsSubtitle = "What each model did: tokens by kind, and by day"
        static func activityIn(_ days: Int, _ year: Int) -> String { "\(days) ACTIVE DAY\(days == 1 ? "" : "S") IN \(year)" }
        static let previousYear = "Previous year", nextYear = "Next year"
        static let last30Title = "LAST 30 DAYS", last7Title = "LAST 7 DAYS"
        static let pending = "Counted tomorrow"
        static func dayDetail(sessions: Int, tokens: String) -> String { "\(sessions) session\(sessions == 1 ? "" : "s")\n\(tokens) tokens" }
        static let messagesPerDay = "Bars: messages per day. Today's counts arrive once Claude Code folds today into its statistics file."
        static let tokenKinds = "TOKENS BY KIND · ALL TIME"
        static let input = "Input", output = "Output", cacheRead = "Cache read", cacheWrite = "Cache write"
        static let allTimeNote = "Most tokens are cache reads: Claude Code re-reads the conversation from the prompt cache on every turn."
        static let noData = "No data", less = "Less", more = "More"
        static func noDataDay(_ day: String) -> String { "\(day): no data" }
        static func dayTooltip(_ day: String, messages: Int, sessions: Int) -> String {
            "\(day): \(messages) message\(messages == 1 ? "" : "s"), \(sessions) session\(sessions == 1 ? "" : "s")"
        }
        static let hours = "SESSIONS BY HOUR OF DAY"
        static func hourTooltip(_ h: Int, _ n: Int) -> String { String(format: "%02d:00", h) + " · \(n) session\(n == 1 ? "" : "s") started" }
        static func hoursSummary(peak: Int) -> String { "Sessions started by hour of day; the busiest hour is " + String(format: "%02d:00", peak) }
        static let tokensPerWeek = "TOKENS PER WEEK"
        static func tokensTotal(_ n: String) -> String { "\(n) tokens" }
        static let hoverHint = "Point at a bar for its numbers"
        static let noTokens = "no tokens"
        static let noModels = "No model activity in this range yet."
        static func level(_ n: Int) -> String { "LV \(n)" }
        static let levelUnknown = "LV —"
        static func progressTo(_ n: Int) -> String { "PROGRESS TO LV \(n)" }
        static func outputOf(_ output: String, _ next: String, toGo: String) -> String { "\(output) of \(next) output · \(toGo) to go" }
        static let legendTitle = "HOW LEVELS WORK"
        static let ladderTitle = "OUTPUT TOKENS NEEDED FOR EACH LEVEL"
        static let ladderNote = "Targets follow 1, 2, 5 in every power of ten. A model is at the highest level whose target its all-time output has reached; the bar on its card is the way from that target to the next."
        static let kindsTitle = "WHAT THE TOKENS ARE"
        static let countsForLevel = "COUNTS FOR LEVEL", notForLevel = "NOT FOR LEVEL"
        /// (kind, what it is, whether it counts toward a level)
        static let kindDefinitions: [(String, String, Bool)] = [
            ("Output", "Text the model wrote: replies, code and tool calls. The model's own work.", true),
            ("Input", "New text sent to the model that wasn't already cached: your message, tool results, files it read.", false),
            ("Cache read", "Earlier conversation the model re-reads from the prompt cache on every turn. Usually most tokens; grows with conversation length.", false),
            ("Cache write", "Conversation stored in the prompt cache so later turns can re-read it cheaply.", false),
        ]
        static let rankRule = "Rank: by level, then by output, then by total tokens."
        static let specialtyRule = "Specialty: the kind of token a model uses most compared with all models together (its share of that kind ÷ everyone's share). Under 1.1× for every kind: All-rounder."
        static func levelLabel(_ level: Int, output: String, next: String) -> String {
            "Level \(level): \(output) output tokens written; level \(level + 1) at \(next)"
        }
        static func tokensLine(_ n: String, _ pct: Int, days: Int, allTime: Bool) -> String {
            "\(n) tokens · \(pct)% of all · active \(days) day\(days == 1 ? "" : "s")\(allTime ? "" : " in this range")"
        }
        static let doingRecall = "Reading from cache", doingStore = "Writing to cache", doingWrite = "Writing output", doingRead = "Reading input"
        static let activityUnknown = "Tokens by kind appear in All time"
        static func specialty(_ doing: String, times: Double) -> String {
            times < 1.1 ? "All-rounder" : "\(doing) · \(times < 10 ? String(format: "%.1f", times) : String(Int(times)))× the party"
        }
        static let specialtyHelp = "Its specialty: the token kind this model uses most compared with all models together. All-rounder: no kind stands out."
        static let arenaNote = "All figures are all time, from Claude Code's statistics file."
        static let arenaRangeNote = "Levels and ranks use all-time output. Tokens, share and active days are for this range; the bars show all-time tokens by kind, the only breakdown Claude Code records."
        static let toggle = "Read Claude Code's statistics file"
        static let toggleSublabel = "For the Stats tab: dates, counts and model names only"
    }

    /// Increment 1.10: Home, the player card, Goals, Account.
    enum Home {
        static let morning = "Good morning", afternoon = "Good afternoon", evening = "Good evening", late = "Working late"
        static let title = "Home"
        static let subtitle = "Your limits, your latest task and your goals, at a glance"
        static func runningTotal(_ tokens: String) -> String { "\(tokens) tokens and counting" }
        static func lastDay(_ tokens: String, _ day: String) -> String { "+\(tokens) on \(day)" }
        static func watched(_ sessions: Int) -> String { "\(sessions) Claude Code session\(sessions == 1 ? "" : "s") watched" }
        static let limits = "LIMITS", latestTask = "LATEST TASK", goals = "GOALS", level = "LEVEL", lastYear = "LAST 12 MONTHS"
        static let connectTitle = "CONNECT CLAUDE CODE", connectBody = "Pulse reads Claude Code's status line on this Mac to show your limits."
        static let agentsTitle = "COUNT AGENTS PER TASK", agentsBody = "See how many subagents each prompt starts, by type. Counts only."
        static let statsTitle = "SHOW YOUR CLAUDE CODE STATS", statsBody = "Your activity calendar, levels and the player card come from Claude Code's statistics file."
        static let turnOn = "Turn on", connect = "Connect…"
        static let seeAll = "See all"
    }

    enum Card {
        static let title = "Card", subtitle = "Your Claude Code player card, ready to share"
        static func toNext(_ n: String, _ level: Int) -> String { "\(n) output to LV \(level)" }
        static func levelBar(_ level: Int, _ name: String) -> String { "LV \(level): \(name.uppercased())" }
        static let outputTokens = "OUTPUT TOKENS"
        static let streak = "Streak", topModel = "Top model", sessions = "Sessions", longest = "Longest session"
        static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
        static let copy = "Copy image", save = "Save PNG…", share = "Share…"
        static let copied = "Copied to the clipboard", saved = "Saved"
        static let needsStats = "The card needs Claude Code's statistics file. Turn it on in Stats › Overview or Settings."
        static let since = "SINCE"
        static let note = "Built on this Mac from Claude Code's statistics file. Sharing is up to you: nothing is sent anywhere."
    }

    enum Goals {
        static let title = "Goals", subtitle = "Targets you set; checked on this Mac against what Claude Code reports"
        static let activeDays = "Active days a week", fiveHourPeak = "Keep the 5-hour limit under", weeklyFinish = "Finish the week under"
        static func activeDetail(_ n: Int, _ target: Int) -> String { "Active \(n) of the last 7 days; goal \(target)" }
        static func peakDetail(_ peak: Int, _ target: Int) -> String { "Today's 5-hour peak so far: \(peak)%; goal under \(target)%" }
        static func weeklyDetail(_ pct: Int, projected: Int, target: Int) -> String {
            "7-day limit at \(pct)%; estimate at the reset about \(projected)%; goal under \(target)%"
        }
        static let needsStats = "Needs Claude Code's statistics file (Stats › Overview)"
        static let noReadingsToday = "No readings yet today"
        static let met = "MET", onTrack = "ON TRACK", atRisk = "AT RISK", missed = "OVER", noData = "NO DATA"
        static func streak(_ n: Int) -> String { n == 1 ? "1 day in a row" : "\(n) days in a row" }
        static let off = "Off", target = "Target"
        static let note = "Goals stay on this Mac for now. When accounts arrive (ACCOUNTS_AND_SYNC), you'll be able to see them anywhere."
    }

    enum Account {
        static let title = "Account", subtitle = "Your profile, your plan and your year"
        static let name = "Name", namePlaceholder = "Your first name"
        static let plan = "PLAN", planNotSet = "PLAN NOT SET", change = "Change plan…"
        static let profile = "PROFILE"
        static let signInTitle = "SIGN IN TO SEE PULSE ANYWHERE"
        static let signInBody = "Coming next: sign in with Apple, Google or an email link to see your goals and usage on the web, and later on iPhone. Only daily counts would leave this Mac, never prompts, replies or file paths, and you could delete everything at any time."
        static let signIn = "Sign in (coming soon)"
        static let year = "YOUR YEAR"
    }

    enum SettingsPage {
        static let title = "Settings", subtitle = "How Pulse runs on this Mac"
        static let general = "GENERAL", claudeCode = "CLAUDE CODE", notifications = "NOTIFICATIONS", data = "DATA"
        static let loginSub = "Start Pulse when you log in"
        static let percentSub = "The highest limit's % next to the icon"
        static let notificationsTitle = "Notifications"
        static let allowed = "Allowed", notAllowed = "Not allowed yet", allow = "Allow…"
        static let connection = "Connection"
        static let diagnostics = "Diagnostics, export and delete-all", open = "Open…"
    }

    /// Increment 1.9: agents per task, from Claude Code hooks (counts only).
    enum Agents {
        static let general = "General", guide = "Guide", statusLine = "Status line", custom = "Custom", unknown = "Unknown"
        static let title = "AGENTS PER TASK"
        static let latest = "LATEST TASK", recent = "RECENT TASKS", month = "LAST 30 DAYS"
        static func count(_ n: Int) -> String { n == 1 ? "1 agent" : "\(n) agents" }
        static let none = "No subagents"
        static let running = "Running", taskLabel = "A task is one prompt: from sending it until Claude stops."
        static func finished(_ done: Int, of total: Int) -> String { "\(done) of \(total) finished" }
        static let tasks = "Tasks", withAgents = "Used agents", average = "Agents per task", most = "Most in one task"
        static let noTasks = "No tasks yet. Send Claude Code a prompt; it appears here when Claude starts working on it."
        static let missedPrompt = "Started before Pulse saw the prompt"
        static let offTitle = "COUNT AGENTS PER TASK?"
        static let offBody = "Pulse can count how many subagents Claude Code starts for each prompt, by type (Explore, Plan, General; your own agents as Custom). It adds four background hooks to Claude Code's settings, with a backup first. The hooks send only the event, hashed ids and the type, never your prompts, replies or file names. Turn it on in Settings › Providers."
        static let openSettings = "Open Settings…"
        static func strip(_ n: Int, _ types: String) -> String { n == 0 ? "Last task: no subagents" : "Last task: \(n == 1 ? "1 agent" : "\(n) agents") · \(types)" }
        static let toggle = "Count subagents per task"
        static let toggleSublabel = "Adds four background hooks to Claude Code's settings; counts and types only"
        static let needsConnection = "Connect Claude Code first"
        static let confirmTitle = "Add hooks to Claude Code?"
        static func confirmBody(_ file: String) -> String {
            "\(Product.name) adds one entry under UserPromptSubmit, SubagentStart, SubagentStop and Stop in \(file), after your own hooks, which stay as they are. A backup is made first, and turning this off takes the entries out again. Each entry is:"
        }
        static let add = "Add hooks", cancel = "Cancel"
        static let added = "Hooks added. New prompts are counted from now on."
        static let removedExact = "Hooks removed. Claude Code's settings are byte-for-byte as before."
        static let removedEntries = "Hooks removed. Your other changes to Claude Code's settings were kept."
        static let alreadyGone = "The hooks were already gone from Claude Code's settings."
        static func failed(_ reason: String) -> String { "Couldn't change Claude Code's settings: \(reason). Nothing was changed." }
    }

    /// Increment 1.7c: always says "Estimate", never a promise.
    enum Pace {
        static func reaches(_ time: String) -> String { "Estimate: at this pace, 100% around \(time)" }
        static func byReset(_ pct: String) -> String { "Estimate: about \(pct) used by the reset" }
        static let notRising = "Estimate: not rising right now"
        static let notEnough = "Estimate: needs a few more readings"
        static let atLimit = "At the limit"
    }

    enum Detail {
        static let openUsage = "Open usage in Claude"
        static let changePlan = "Change plan…"
        static func sessions(_ n: Int) -> String { n == 1 ? "1 Claude Code session" : "\(n) Claude Code sessions" }
        /// DECISIONS C7: say what the source covers, so "available" is never read as "every limit".
        static let otherLimits = "Claude Code's status line reports the 5-hour and 7-day limits only. Others, such as a weekly limit for one model, appear in /\u{2060}usage in Claude Code."          // word joiner: never break "/usage" across lines
        static func unreadLimits(_ n: Int) -> String {
            "Claude Code is sending \(n == 1 ? "1 more limit" : "\(n) more limits") that \(product) doesn't read yet. Check /\u{2060}usage in Claude Code."
        }
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
