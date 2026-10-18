import Domain
import Foundation

/// Every string the screens show, named after its key. Seat 7 owns the wording; change it here only.
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
        static let planSkip = "Skip for now"
        static func step(_ n: Int, of total: Int) -> String { "Step \(n) of \(total)" }
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
        static let open = "Details", openStats = "Stats", dashboard = "Dashboard"
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
        static let connectTitle = "CONNECT CLAUDE CODE", connectBody = "\(product) reads Claude Code's status line on this Mac to show your limits."
        static let agentsTitle = "COUNT AGENTS PER TASK", agentsBody = "See how many subagents each prompt starts, by type. Counts only."
        static let statsTitle = "SHOW YOUR CLAUDE CODE STATS", statsBody = "Your activity calendar, levels and the player card come from Claude Code's statistics file."
        static let turnOn = "Turn on", connect = "Connect…"
        static let seeAll = "See all"
    }

    enum Limits {
        static func resets(_ time: String) -> String { "Resets \(time)" }
    }

    /// Account page (1.12, after the founder's Twenty, Rive and GitBook picks).
    enum AccountPage {
        static let profile = "Profile", profileSub = "The name Home greets you with and the card shows."
        static let plan = "Plan", planSub = "The plan you chose. \(product) never guesses it from usage."
        static let signIn = "Sign in", signInSub = "Optional. Sign in to see goals and usage on the web."
        static let sync = "Upload"
        static let year = "Your year", yearSub = "Every day you used Claude Code this year."
        static let emailLink = "Email link", emailSub = "A one-time link, no password"
        static let connected = "CONNECTED", soon = "Soon", soonSub = "Being set up"
        static let danger = "DANGER ZONE", signOutSub = "Stops uploads from this Mac. What's on the server stays."
        static let deleteTitle = "Delete account"
        static let dangerSignedOut = "Nothing to delete: you aren't signed in. To remove \(product)'s data from this Mac, use Settings › Delete all."
    }

    /// Card page milestones (1.12, after the founder's Tripadvisor pick).
    enum CardPage {
        static let yourCard = "Your card"
        static let milestones = "MILESTONES", milestonesSub = "Each category has its own rungs. Lit squares are the ones you've reached."
        static func name(_ kind: Ladder.Kind) -> String {
            switch kind {
            case .output: "Output written"
            case .streak: "Longest streak"
            case .sessions: "Sessions"
            case .activeDays: "Active days"
            }
        }
        static func tier(_ kind: Ladder.Kind, _ reached: Int) -> String {
            let names: [String] = switch kind {
            case .output: ["Starter", "Writer", "Author", "Publisher", "Press", "Library", "Archive"]
            case .streak: ["Starter", "Warm-up", "Week run", "Fortnight", "Month run", "Two months", "Centurion", "Year run"]
            case .sessions: ["Starter", "Regular", "Frequent", "Centurion", "Veteran", "Expert", "Master", "Legend"]
            case .activeDays: ["Starter", "Week one", "Month one", "Hundred", "Two hundred", "Year", "Two years"]
            }
            return names[min(reached, names.count - 1)]
        }
        static func toGo(_ kind: Ladder.Kind, _ n: String) -> String {
            switch kind {
            case .output: "\(n) more output tokens to the next rung"
            case .streak: "\(n) more days in a row to the next rung"
            case .sessions: "\(n) more sessions to the next rung"
            case .activeDays: "\(n) more active days to the next rung"
            }
        }
        static let top = "Top rung reached"
    }

    /// Models page (1.12, after the founder's Krea pick).
    enum ModelsPage {
        static let distribution = "USAGE DISTRIBUTION", tokens = "TOKENS"
        static let distributionTitle = "Distribution", distributionSub = "Each model's share of all tokens in this range."
        static let chartTitle = "Tokens over time"
        static let chartSub = "Stacked by model; every day on the axis, quiet ones included."
        static func ofTotal(_ pct: String) -> String { "\(pct)% of all tokens" }
    }

    /// Overview page (1.12, after the founder's Steep and Mixpanel picks).
    enum OverviewPage {
        static let clear = "Clear", messages = "Messages", toolCalls = "Tool calls", byModel = "TOKENS BY MODEL"
        static let activity = "Activity", activityYear = "One year at a time. Choose a day to see it in full."
        static let glance = "At a glance", hoursTitle = "When you work", hoursSub = "Sessions started, by hour of the day."
        static let kindsTitle = "Tokens by kind", tokensTitle = "Tokens per day", tokensSub = "All models together."
        static func summary(_ range: String) -> String { range.uppercased() + " AT A GLANCE" }
        static let pickDay = "Choose a day in the calendar to see it here."
        /// A secondary fact as a card's context line: "Longest session: 4h 12m".
        static func fact(_ label: String, _ value: String) -> String { "\(label): \(value)" }
        static let codexTitle = "Codex", codexSub = "Tokens from Codex's own session files on this Mac, by model."
        static let codexOutput = "Output tokens", codexTop = "Top model"
        static func codexShare(_ pct: Int) -> String { "\(pct)% of Codex tokens" }
        static let codexReading = "Reading Codex's session files…"
        static let codexOutputDetail = "Reasoning included"
    }

    /// Session page (1.12, after the founder's Adaline and Gumloop picks).
    enum SessionPage {
        static let details = "DETAILS", model = "Model", window = "Context window", requests = "Cache requests"
        static let current = "Session", detailsTitle = "Details", detailsSub = "Everything Claude Code's status line reports about it."
        static let recentTitle = "Recent sessions", recentSub = "Choose one to see it above."
        static let byModelTitle = "By model"
        /// 1.15: the by-model table's column heads.
        static let colModel = "Model", colSessions = "Sessions", colCost = "Cost est.", colLines = "Lines +", colAPI = "API time", colShare = "Share of cost"
        static let timeSplit = "TIME WAITING ON THE MODEL"
        static func apiShare(_ pct: Int) -> String { "\(pct)% of the session's wall time" }
    }

    /// Limits page (1.12, after the founder's Remote, StackAI and Sprig picks).
    enum LimitsPage {
        static let allLimits = "ALL LIMITS", plan = "Plan", left = "LEFT", used = "used"
        static let planSub = "What you're on, and where these numbers come from."
        static let planName = "Plan", source = "Source", lastReading = "Last reading", sessions = "Sessions seen"
        static func usage(_ scope: String) -> String { "\(scope) usage" }
        static func window(_ scope: String) -> String { "\(scope.uppercased()) WINDOW" }
        static let notReported = "Not reported"
    }

    /// 1.14: section names and lines for every page in Account's structure.
    enum HomePage {
        static let today = "Today", todaySub = "What needs you now, most urgent first."
        static let limitsSub = "How much of each limit you've used, and when it resets."
        static let monthSub = "Claude Code activity, day by day."
        static let levelSub = "Grows with what your models write. See Card for the full ladder."
        static let openCard = "Open card"
    }

    /// Home's "For you today" (after the founder's Deel pick).
    enum ForYou {
        static let title = "FOR YOU TODAY"
        static func limit(_ scope: String, _ pct: Int) -> String { "\(scope) limit at \(pct)%" }
        static let limitApproaching = "Approaching the limit. Pace yourself or plan around the reset."
        static let limitCritical = "Nearly used up. New work may be refused until the reset."
        static func goal(_ name: String, _ over: Bool) -> String { (over ? "Goal missed: " : "Goal at risk: ") + name.lowercased() }
        static func running(_ agents: Int) -> String { agents == 0 ? "A task is running" : "A task is running with \(agents) agent\(agents == 1 ? "" : "s")" }
        static let signInTitle = "See \(product) anywhere", signInBody = "Sign in to check your goals and usage on the web.", signIn = "Sign in"
        static let allClear = "ALL CLEAR", allClearBody = "Nothing needs you right now."
        static let view = "View"
        static let connectTitle = "Connect Claude Code", statsTitle = "Show your Claude Code stats", agentsTitle = "Count agents per task"
        static let metric = "Metric"
        static let tokens = "Tokens", messages = "Messages", sessions = "Sessions"
        static let last30 = "LAST 30 DAYS"
        static func total(_ n: String, _ metric: String) -> String { "\(n) \(metric.lowercased())" }
        static let level = "LEVEL", thisMonth = "THIS MONTH"
        static let activeDays = "Active days", sessionsMonth = "Sessions", streak = "Current streak", agentsPerTask = "Agents per task"
    }

    enum Card {
        static let title = "Card", subtitle = "Your Claude Code player card, ready to share"
        static func toNext(_ n: String, _ level: Int) -> String { "\(n) output to LV \(level)" }
        static func levelBar(_ level: Int, _ name: String) -> String { "LV \(level): \(name.uppercased())" }
        static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
        static let copy = "Copy image", save = "Save PNG…", share = "Share…"
        static func copied(_ back: Bool) -> String { back ? "Copied the back of the card" : "Copied the front of the card" }
        static let saved = "Saved"
        static let needsStats = "The card needs Claude Code's statistics file. Turn it on in Stats › Overview or Settings."
        static let since = "SINCE"
        static let note = "Built on this Mac from Claude Code's statistics file and Clepso's own readings. Sharing is up to you: "
            + "nothing is sent anywhere. Click the card to flip it; Save and Copy use the side that's showing."

        // The hero and the grid (founder review: one hero figure, the rest in a tidy grid, every label unambiguous).
        static let totalTokens = "TOTAL TOKENS", totalCaption = "Input, output and cache · all models · all time"
        static let output = "Output tokens", outputCaption = "Written by the models"
        static let lines = "Lines added"
        static func linesCaption(removed: String, since: String?) -> String { "−\(removed) removed · " + (since.map { "since \($0)" } ?? "last 30 days") }
        static let linesNone = "No session has reported lines yet"
        static let currentStreak = "Current streak", bestStreak = "Best streak", bestCaption = "Longest run of active days"
        static func currentCaption(includesToday: Bool) -> String { includesToday ? "Including today" : "Through yesterday" }
        static let sessions = "Sessions", sessionsCaption = "All time"
        static let longest = "Longest session", longestCaption = "First to last message"
        static let activeDays = "Active days"
        static func activeCaption(_ days: Int) -> String { "of \(days) days since the first" }
        static let topModel = "Top model"
        static func topCaption(_ pct: Int) -> String { "\(pct)% of tokens" }
        static func updated(_ when: String) -> String { "UPDATED \(when)" }
        static func through(_ day: String) -> String { "TOKENS THROUGH \(day)" }

        // The back and the flip (after Aqua Voice's card).
        static let flip = "Flip card", showBack = "Show back", showFront = "Show front"
        static let front = "Front", back = "Back"
        static let website = "clepso-app.vercel.app"
        static let backTag = "PLAYER CARD"
        static let backLine = "Claude Code usage and limits, tracked on this Mac."
        static func activityTitle(_ weeks: Int) -> String { "ACTIVITY LOG · LAST \(weeks) WEEKS" }
        static func activitySummary(_ active: Int, _ days: Int) -> String { "\(active) of \(days) days active" }
        static let less = "LESS", more = "MORE", pending = "Seen by Clepso, not yet in the file"
        static func dayBeforeFirst(_ date: String) -> String { "\(date): before your first session" }
        static func dayHelp(_ date: String, active: Bool, pending: Bool) -> String {
            pending ? "Active on \(date) (seen by Clepso; Claude Code's file adds it later)" : (active ? "Active on \(date)" : "No activity on \(date)")
        }

        /// What VoiceOver reads for each face (the card is one button, "Flip card", whose value is the face showing).
        static func frontSummary(_ c: PlayerCard, figures: [(String, String)]) -> String {
            (["Front", c.name, c.plan ?? "", levelBar(c.level.level, c.levelName)] + figures.map { "\($0.0): \($0.1)" })
                .filter { !$0.isEmpty }.joined(separator: ". ")
        }
        static func backSummary(_ c: PlayerCard, weeks: Int) -> String {
            ["Back", Copy.product, backLine, "\(activityTitle(weeks).capitalized): \(activitySummary(c.activity.activeDays, c.activity.days))", website]
                .joined(separator: ". ")
        }
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
        static let off = "Off", target = "Target", details = "DETAILS", status = "Status", streakLabel = "Streak"
        static let lastSeven = "LAST 7 DAYS", aboutTitle = "About goals"
        static func dayValue(_ kind: GoalStatus.Kind, _ value: Double?, _ met: Bool?) -> String {
            guard let value else { return "no data" }
            switch kind {
            case .activeDays: return met == true ? "active" : "not active"
            case .fiveHourPeak: return "peak \(Int(value.rounded()))%"
            case .weeklyFinish: return "\(Int(value.rounded()))% at day end"
            }
        }
        static let note = "Goals stay on this Mac for now. When accounts arrive, you'll be able to see them anywhere."
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

    /// Pulse accounts.
    enum Sync {
        static let title = "PULSE ACCOUNT"
        static let explainer = "Sign in to see your goals and usage on the web (and later on iPhone). Once an hour \(product) uploads daily counts only: messages, sessions and tokens per model per day (when Claude Code stats are on), each day's limit peaks, agents per task (when counting is on), your goals and your name and plan. Never prompts, replies, file paths, project names or session ids. Delete the account at any time and everything on the server goes with it."
        static let emailPlaceholder = "you@example.com"
        static let emailMe = "Email me a link"
        static func linkSent(_ email: String) -> String { "Check \(email): open the link on this Mac to sign in. It works once and expires within the hour." }
        static let differentEmail = "Use a different email"
        static let providersSoon = "Apple, Google and GitHub sign-in: being set up"
        static func signedInAs(_ email: String?) -> String { "Signed in" + (email.map { " as \($0)" } ?? "") }
        static func lastSynced(_ when: String) -> String { "Last uploaded \(when)" }
        static let neverSynced = "Not uploaded yet"
        static let syncNow = "Upload now", signOut = "Sign out", deleteAccount = "Delete account…"
        static let deleteTitle = "Delete your \(product) account?"
        static let deleteBody = "This deletes the account and every count stored with it on the server. Nothing on this Mac changes. It can't be undone."
        static let deleteConfirm = "Delete account"
        static let signedIn = "Signed in. Your counts are uploading."
        static let signedOut = "Signed out. Nothing more is uploaded; what's on the server stays until you delete the account."
        static let deleted = "Account deleted, and everything stored with it."
        static let invalidEmail = "That doesn't look like an email address."
        static let notSignedIn = "You're signed out. Sign in again to keep uploading."
        static let noPending = "That link was sent from a different sign-in attempt. Ask for a new one."
        static let linkFailed = "The sign-in link didn't work. Ask for a new one."
        static let unavailable = "Accounts aren't available in this build. Builds made from source don't connect to \(product)'s accounts service, so nothing leaves this Mac."
        static func serverError(_ status: Int, _ code: String?) -> String { "The server said no (\(status)\(code.map { ", \($0)" } ?? "")). Try again later." }
        static let badResponse = "The server's answer didn't make sense. Try again later."
        static let offline = "Couldn't reach the server. \(product) will try again within the hour."
        static let demoNote = "Uploads are paused while demo data is showing."
    }

    /// 2.1–2.3: limit alerts. `agent` is "Claude Code" or "Codex"; `scope` is "5-hour" or "7-day".
    enum Alerts {
        static func approaching(_ agent: String, _ scope: String, _ level: Int) -> String { "\(agent) · \(scope) limit at \(level)%" }
        static func exhausted(_ agent: String, _ scope: String) -> String { "\(agent) · \(scope) limit reached" }
        static func resetExpected(_ agent: String, _ scope: String) -> String { "\(agent) · \(scope) reset time has arrived" }
        static func readyAgain(_ agent: String, _ scope: String) -> String { "\(agent) · \(scope) limit available again" }
        static func resets(_ time: String) -> String { "Resets \(time)." }
        static let noReset = "Reset time not reported."
        static func notRechecked(_ agent: String) -> String { "Not rechecked yet: it updates with your next \(agent) message." }
        static func verified(_ pct: Int) -> String { "Verified just now: \(pct)% used." }
        static let toggle = "Limit alerts", toggleSub = "At 80%, 95% and 100% of a limit, and when a limit you hit is ready again"
        static func snoozed(_ time: String) -> String { "Snoozed until \(time)" }
        static let snooze = "Snooze 1 h", unsnooze = "Resume"
    }

    /// 2.5 One-tap Calendar: a weekly reset as a one-shot event the user adds (NOTIFICATIONS §3.1).
    enum CalendarAction {
        static let add = "Add reset to Calendar"
        static let addSub = "Opens Calendar, which asks before adding it. Weekly limits only."
        static func summary(_ agent: String, _ scope: String) -> String { "\(agent) \(scope) limit resets" }
        static func notes(_ agent: String) -> String {
            "The reset time \(agent) reported. \(Product.name) can't change this event: if the time moves, add it again from Limits."
        }
        static func fileName(_ summary: String) -> String { summary + ".ics" }
    }

    /// Increment 3.4: Codex's limits beside Claude Code's.
    enum Codex {
        static let name = "Codex"
        static let toggle = "Read Codex's session files"
        static let toggleSublabel = "Its 5-hour and weekly limits, plan and tokens per day; prompts and replies are skipped unread"
        static let unknownModel = "Model not reported"
        static let notFound = "Codex hasn't written a session on this Mac"
        static let waiting = "On. Waiting for Codex's next session to report its limits"
        static let source = "Codex session files"
        static let model = "Model", plan = "Plan", lastReading = "Last reading"
        static let factsTitle = "CODEX", factsSub = "Where Codex's numbers come from"
        static func scope(_ scope: String) -> String { "Codex \(scope)" }
    }

    enum SettingsPage {
        static let alertsNeedPermission = "Allow notifications above to get alerts at 80%, 95% and 100%"
        static let title = "Settings", subtitle = "How \(product) runs on this Mac"
        static let general = "GENERAL", claudeCode = "CLAUDE CODE", codex = "CODEX", notifications = "NOTIFICATIONS", data = "YOUR DATA", diagnostics = "DIAGNOSTICS"
        static let exportSub = "Everything \(product) stores on this Mac, as one JSON file", exportAction = "Export…"
        static let demoSub = "Sample numbers, clearly marked DEMO; uploads pause"
        static let deleteSub = "Removes all of \(product)'s data and restores Claude Code's settings", deleteAction = "Delete…"
        static let showLog = "Show log", hideLog = "Hide log"
        static func groupLine(_ title: String) -> String {
            switch title {
            case general: "How \(product) looks and starts."
            case notifications: "Alerts when a limit gets close."
            case claudeCode: "What \(product) reads from Claude Code, and what it keeps."
            case codex: "Codex's own limits, read from its session files on this Mac."
            case data: "Everything \(product) stores is on this Mac."
            case diagnostics: "What \(product) received, for troubleshooting."
            default: ""
            }
        }
        static let appearance = "Appearance", appearanceSub = "Light, dark, or follow macOS"
        /// 1.15: colour themes. Names and one-line intents; every theme has a light and a dark palette.
        static let theme = "Theme", themeSub = "The colours of the menu bar panel and this window"
        static func themeName(_ id: String) -> String {
            switch id {
            case "amber": "Amber"
            case "cobalt": "Cobalt"
            case "orchid": "Orchid"
            case "graphite": "Graphite"
            default: "Phosphor"
            }
        }
        static func themeIntent(_ id: String) -> String {
            switch id {
            case "amber": "Warm amber CRT"
            case "cobalt": "Cool ice blue"
            case "orchid": "Violet and orchid"
            case "graphite": "Monochrome ink"
            default: "The original green"
            }
        }
        static let selected = "Selected"
        static let system = "System", light = "Light", dark = "Dark"
        static let loginSub = "Start \(product) when you log in"
        static let percentSub = "The highest limit's % next to the icon"
        static let notificationsTitle = "Notifications"
        static let allowed = "Allowed", notAllowed = "Not allowed yet", allow = "Allow…"
        static let connection = "Connection"
        static let open = "Open…"
    }

    /// Increment 1.9: agents per task, from Claude Code hooks (counts only).
    enum Agents {
        static let lastTaskShort = "Agents, last task"
        static let statShort = "Agents"
        static let general = "General", guide = "Guide", statusLine = "Status line", custom = "Custom"
        static let title = "AGENTS PER TASK", titleShort = "Agents per task", claudeTitle = "Claude Code agents per task"
        static let latest = "LATEST TASK", recent = "RECENT TASKS", month = "LAST 30 DAYS"
        static func count(_ n: Int) -> String { n == 1 ? "1 agent" : "\(n) agents" }
        static let none = "No subagents"
        static let running = "Running", taskLabel = "A task is one prompt: from sending it until Claude stops."
        static func finished(_ done: Int, of total: Int) -> String { "\(done) of \(total) finished" }
        static let tasks = "Tasks", withAgents = "Used agents", average = "Agents per task", most = "Most in one task"
        /// The 30-day cards' context lines and the recent-tasks table (founder review, 18 Oct 2026).
        static let last30 = "Last 30 days", oneTask = "In a single prompt"
        static func ofTasks(_ n: Int, _ total: Int) -> String { "\(n) of \(total) tasks" }
        static func inAll(_ n: Int) -> String { n == 1 ? "1 agent in all" : "\(n) agents in all" }
        static func started(_ time: String) -> String { "Started \(time)" }
        static let colStarted = "Started", colAgents = "Agents", colTypes = "Types", colDuration = "Duration", done = "Done"
        static let noTasks = "No tasks yet. Send Claude Code a prompt; it appears here when Claude starts working on it."
        static let missedPrompt = "Started before \(product) saw the prompt"
        static let offTitle = "COUNT AGENTS PER TASK?"
        static let offBody = "\(product) can count how many subagents Claude Code starts for each prompt, by type (Explore, Plan, General; your own agents as Custom). It adds four background hooks to Claude Code's settings, with a backup first. The hooks send only the event, hashed ids and the type, never your prompts, replies or file names. Turn it on in Settings › Providers."
        static let openSettings = "Open Settings…"
        /// Item 4: Codex's agents per task, from its own session files.
        static let codexTitle = "Codex agents per task"
        static let codexTaskLabel = "A task is one prompt to Codex: from sending it until Codex finishes the turn. Its agents are the sub-agents Codex spawns for it."
        static let codexNoTasks = "No Codex tasks yet. Send Codex a prompt; it appears here once Codex has written it to its session files."
        static let codexReading = "Reading Codex's session files…"
        static let codexDefault = "Default", codexExplorer = "Explorer", codexWorker = "Worker", codexAwaiter = "Awaiter"
        static func reviews(_ n: Int) -> String { n == 1 ? "1 auto-review" : "\(n) auto-reviews" }
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
        /// 1.15: the same estimates in a card's one-line form; still always marked as an estimate.
        static func reachesShort(_ time: String) -> String { "Est. 100% by \(time)" }
        static func byResetShort(_ pct: String) -> String { "Est. \(pct) at reset" }
        static let notRisingShort = "Est. not rising"
        static let atLimit = "At the limit"
    }

    enum Detail {
        static let openUsage = "Open usage in Claude"
        static let changePlan = "Change plan…"
        static func sessions(_ n: Int) -> String { n == 1 ? "1 Claude Code session" : "\(n) Claude Code sessions" }
        /// 1.15: the detail page's compact status strip and action bar.
        static func sessionsShort(_ n: Int) -> String { n == 1 ? "1 session" : "\(n) sessions" }
        static let openUsageShort = "Usage"
        static let coverage = "5-hour & 7-day only"
        static func unreadShort(_ n: Int) -> String { n == 1 ? "1 limit not read" : "\(n) limits not read" }
        static let moreInfo = "More about which limits \(product) reads"
        /// Say what the source covers, so "available" is never read as "every limit".
        static let otherLimits = "Claude Code's status line reports the 5-hour and 7-day limits only. Others, such as a weekly limit for one model, appear in /\u{2060}usage in Claude Code."          // word joiner: never break "/usage" across lines
        static func unreadLimits(_ n: Int) -> String {
            "Claude Code is sending \(n == 1 ? "1 more limit" : "\(n) more limits") that \(product) doesn't read yet. Check /\u{2060}usage in Claude Code."
        }
    }

    enum Footer {
        static let notifications = "Notifications…"
        static let settings = "Settings…"
        static let quit = "Quit"
        static let quitHelp = "Quit \(product). Limits are not tracked until it opens again."
        static let refresh = "Refresh"
        static let refreshHelp = "Check again now. Claude Code sends its limits each time it runs; Codex and stats are re-read."
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
        /// 1.15: the same counts as figures.
        static let received = "Received", malformed = "Malformed", tooLarge = "Too large", rateLimited = "Rate-limited", otherUser = "Other user"
    }

    enum Demo {
        static let header = "Demo data · not your account"
        static let exit = "Stop showing demo data"
        static let strip = "Sample data · not your account", exitShort = "Exit demo"
    }
}
