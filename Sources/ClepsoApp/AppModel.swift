import ClaudeCodeAdapter
import struct CodexAdapter.CodexAgents
import struct CodexAdapter.CodexReading
import struct CodexAdapter.CodexUsage
import DesignSystem
import enum Domain.EvidenceKind
import enum Domain.Freshness
import enum Domain.Product
import struct Domain.Redacted
import struct Domain.ManualAllowance
import Foundation
import IntegrationSnapshot
import enum SwiftUI.ColorScheme
import Observation
import enum ShimProtocol.HookFrame
import Sync
import Storage
import SubscriptionCatalog
import UsageEngine

/// The composition root (ARCHITECTURE §1): owns the store, the socket listener and the clock tick, and
/// publishes one `OverviewSnapshot` for every screen. All user-visible state changes go through here.
@MainActor @Observable
public final class AppModel {
    public enum Problem: Equatable, Sendable { case socket(String), storage(String) }
    public enum SettingsTab: String, Hashable, Sendable { case general, notifications, providers, plan, diagnostics }
    public enum PopoverRoute: Hashable, Sendable { case overview, detail, inspector(poolKey: String, fromDetail: Bool) }
    public enum OnboardingStep: Int, CaseIterable, Sendable { case welcome, plan, provider, consent, firstReading, alerts, done }
    /// Increment 1.8c: one sidebar, one level of sections.
    public enum DetailsSection: String, Hashable, Sendable, CaseIterable { case home, limits, session, overview, models, card, goals, account, settings }
    public enum ModelsView: String, Hashable, Sendable { case chart, arena }

    public private(set) var snapshot: OverviewSnapshot
    public internal(set) var problem: Problem?
    public private(set) var plan: Store.PlanIdentity?
    public private(set) var preview: SettingsInstaller.Preview
    public private(set) var notificationStatus: NotificationAuthorization = .notDetermined
    /// 2.1: limit alerts (on by default once notifications are allowed), a snooze, and a request to open the Dashboard.
    public internal(set) var alertsEnabled = true
    public internal(set) var alertsSnoozedUntil: Date?
    /// §1.6 quiet hours (off by default) and §2 reset reminders' lead in minutes (nil: off, the default).
    public internal(set) var quietHours = QuietHours()
    public internal(set) var reminderLead: Int?
    public internal(set) var dataRetention = DataRetention()
    public internal(set) var manualAllowances: [ManualAllowance] = []
    public internal(set) var mcpClients: [String] = []
    public internal(set) var widgetsEnabled = false
    public internal(set) var widgetSharingBusy = false
    var lastWidgetSnapshot: UsageSnapshot?
    var mobileSharing = MobileSharingState()
    public internal(set) var mobileSharingBusy = false
    public internal(set) var mobileSharingMessage: String?
    var mobilePublishTask: Task<Void, Never>?
    var lastMobileAttempt: Date?
    public internal(set) var integrationMessage: String?
    public internal(set) var updateChecksEnabled = false
    public internal(set) var updateDownloadsEnabled = false
    public internal(set) var dashboardRequests = 0
    /// On only when the user chose it here and the system confirms it. `SMAppService.mainApp.status` was seen
    /// reporting `.enabled` for a development build that never registered, so the system's word alone is not enough.
    public private(set) var loginItemEnabled = false
    public private(set) var onboardingComplete = false
    public private(set) var firstRealReadingAt: Date?
    public private(set) var demo = false
    public private(set) var showPercent = true
    public private(set) var menuBarDisplay: MenuBarDisplay = .rotating
    public private(set) var forwardCost = true          // On by default
    /// Increment 1.7d: reading Claude Code's own statistics file is a second source, so it is off until the user agrees.
    public private(set) var statsEnabled = false
    /// Increment 3.4: read Codex's session files (opt-in) and the latest reading's plan and model.
    public internal(set) var codexEnabled = false
    var codexLatest: CodexReading?
    var codexConnection: UUID?
    /// Codex's tokens per day and model (Stats), in memory only; nil until the first background read finishes.
    public internal(set) var codexDays: [CodexUsage.Day]?
    /// Codex's agents per task (item 4), in memory only, from the same read.
    var codexAgentTasks: [CodexAgents.Task]?
    var codexUsage: CodexUsage?
    var codexScanning = false
    /// The Clepso account on this Mac.
    public enum AccountState: Equatable, Sendable {
        case signedOut
        case linkSent(email: String)
        case signedIn(email: String?)
    }
    public private(set) var account: AccountState = .signedOut
    public private(set) var lastSync: Date?
    public internal(set) var accountMessage: String?
    public private(set) var accountBusy = false
    private var lastSyncAttempt: Date?
    /// Increment 1.13: Dark (the original Phosphor look), Light, or follow the system.
    public enum Appearance: String, Codable, Sendable, CaseIterable {
        case system, light, dark
        public var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }
    public private(set) var appearance: Appearance = .dark
    /// Increment 1.15: the colour theme, by `Theme.name` (Phosphor unless the user picks another).
    public private(set) var themeName = Theme.phosphor.name
    public var theme: Theme { Theme.named(themeName) }
    /// Increment 1.10: the name Home greets, and the user's goals (both kept in preferences).
    public private(set) var profileName: String?
    public private(set) var goals = Goals()
    /// Agents per task: the hooks are in Claude Code's settings (read from Clepso's install record).
    public private(set) var agentsCounting = false
    /// v0.3: Clepso's Claude Code mod is in Claude Code's settings (`AppModel+ClaudeMod`), and when it last delivered.
    public internal(set) var claudeModOn = false
    public internal(set) var claudeModLastReading: Date?
    /// Custom agent names the user approved to be shown by name (`AppModel+AgentNames`).
    public internal(set) var approvedAgentNames: [String] = []
    let agentNameAllowlist = AgentNameAllowlist()
    public private(set) var stats: Result<ClaudeCodeStats, StatsReader.Problem>?
    /// When the statistics file was last checked for changes (each tick re-reads it only when Claude Code rewrote it).
    public private(set) var statsCheckedAt: Date?
    private var statsModifiedAt: Date?
    /// Which face of the player card is showing; on the model so the export and the verification probe agree with it.
    public var cardShowsBack = false
    /// Home's "What's new" card for this version (`WhatsNew`), or nil. Set once at launch; cleared by Dismiss.
    var whatsNew: WhatsNew?
    /// Debug probe only: a fixed pointer position for the card's tilt, so a screenshot can show it (nil: follow the pointer).
    public var cardTiltPreview: CGSize?
    public private(set) var started = false
    public var settingsTab: SettingsTab = .general
    /// Navigation lives here so "Connect…" and similar can deep-link, and Escape always has one place to go back to.
    public var popoverRoute: PopoverRoute = .overview
    public var onboardingStep: OnboardingStep = .welcome
    /// A section this build holds back (`ReleaseFeatures`) is never shown: every link into it lands on Home instead.
    public var detailsSection: DetailsSection = .home {
        didSet { if !features.allows(detailsSection) { detailsSection = .home } }
    }
    /// What this build shows (`ReleaseFeatures`).
    public var features: ReleaseFeatures { environment.features }
    public var statsRange: StatsSummary.Range = .allTime
    /// The year the all-time calendar shows; nil means the current year.
    public var statsYear: Int?
    public var modelsView: ModelsView = .arena
    /// The delete-all confirmation sheet; on the model so the verification probe can show it.
    public var confirmingDeleteAll = false
    /// The Claude Code mod's consent sheet (Settings); on the model so the probe can capture it.
    public var confirmingClaudeMod = false
    public let catalog: PlanCatalog?
    /// The Diagnostics drawer's events (PRIVACY_AND_SECURITY §5).
    public let diagnostics: DiagnosticsLog
    /// Live counts from the listener for the Diagnostics tab.
    public private(set) var socketHealth = IngestSocket.Health()

    public let environment: AppEnvironment
    private(set) var store: Store?
    private var socket: IngestSocket?
    private var ingestor: Ingestor?
    private var loggedHealth = IngestSocket.Health()
    private var loggedCounters = Ingestor.Counters()
    var lastPurge: Date?
    private var tasks: [Task<Void, Never>] = []
    private var generation = 0
    /// The move from the layout before the rename to Clepso, done in `init` before any file in the data folder or
    /// `~/.claude/clepso` is read, and reported in Diagnostics once by `start()`.
    @ObservationIgnored private let dataMigration: LegacyDataMigration.Outcome
    @ObservationIgnored private var unreportedMigrations: [(step: String, outcome: String)] = []

    public init(environment: AppEnvironment) {
        self.environment = environment
        let data = LegacyDataMigration(legacy: environment.legacyDataDirectory, current: environment.dataDirectory).run()
        // While the data folder is in use by another copy or half moved, ~/.claude stays as it is too: the next launch
        // moves both.
        let claude = data.blocksStore ? .nothingToDo : Self.legacyLayout(environment).run()
        self.dataMigration = data
        self.unreportedMigrations = [("data", data.rawValue), ("claudeCode", claude.rawValue)].filter { $0.1 != "nothingToDo" }
        self.catalog = try? PlanCatalog.bundled()
        // While the data folder can't be used, this launch's diagnostics go to a temporary file: writing them into the
        // data folder would create it, and the next launch would then find both folders and leave the old one alone.
        let diagnosticsURL = data.blocksStore
            ? FileManager.default.temporaryDirectory.appendingPathComponent("\(Product.name)-diagnostics-\(UUID().uuidString).jsonl")
            : environment.diagnosticsURL
        self.diagnostics = DiagnosticsLog(url: diagnosticsURL, clock: environment.clock)
        self.preview = Self.installer(environment, forwardCost: true).preview()
        self.snapshot = OverviewProjection.make(OverviewInput(), now: environment.clock.now(), staleAfter: Freshness.localTelemetryTTL,
                                                zone: environment.timeZone, locale: environment.locale)
    }

    // MARK: - Lifecycle

    public func start() async {
        guard !started else { return }
        started = true
        updateChecksEnabled = environment.updater?.automaticChecks ?? false
        updateDownloadsEnabled = environment.updater?.automaticDownloads ?? false
        PixelFonts.ensureRegistered()                    // before the first popover open, not during it
        let now = environment.clock.now()
        diagnostics.record(.appStarted(version: environment.appVersion))
        for (step, outcome) in unreportedMigrations { diagnostics.record(.legacyLayout(step: step, outcome: outcome)) }
        unreportedMigrations = []
        guard !dataMigration.blocksStore else {
            problem = .storage(dataMigration.rawValue)
            return
        }
        do {
            let store = try Store.onDisk(at: environment.databaseURL, now: now)
            self.store = store
            onboardingComplete = try await store.preference(Pref.onboardingComplete, as: Bool.self) ?? false
            demo = try await store.preference(Pref.demo, as: Bool.self) ?? false
            showPercent = try await store.preference(Pref.showPercent, as: Bool.self) ?? true
            menuBarDisplay = (try await store.preference(Pref.menuBarDisplay, as: String.self)).flatMap(MenuBarDisplay.init(rawValue:)) ?? .rotating
            forwardCost = try await store.preference(Pref.forwardCost, as: Bool.self) ?? true
            firstRealReadingAt = try await store.preference(Pref.firstReading, as: Date.self)
            statsEnabled = try await store.preference(Pref.readStats, as: Bool.self) ?? false
            codexEnabled = try await store.preference(Pref.readCodex, as: Bool.self) ?? false
            alertsEnabled = try await store.preference(Pref.alertsEnabled, as: Bool.self) ?? true
            alertsSnoozedUntil = try await store.preference(Pref.alertsSnoozedUntil, as: Date.self)
            quietHours = try await store.preference(Pref.quietHours, as: QuietHours.self) ?? QuietHours()
            reminderLead = try await store.preference(Pref.reminderLead, as: Int.self).flatMap { $0 > 0 ? $0 : nil }
            dataRetention = (try await store.preference(Pref.dataRetention, as: DataRetention.self) ?? DataRetention()).validated
            manualAllowances = try await store.manualAllowances()
            mcpClients = SnapshotFile(dataDirectory: environment.dataDirectory).clients()
            let widgetChoice = try await store.preference(Pref.widgets, as: Bool.self)
            widgetsEnabled = widgetChoice ?? false
            mobileSharing = try await store.preference(Pref.mobileSharing, as: MobileSharingState.self) ?? MobileSharingState()
            // Finish an off transition interrupted after its preference was committed. Never resolve a group
            // container for a user who has not configured widget sharing.
            if widgetChoice == false, let container = environment.widgetContainer() {
                do { try SnapshotFile(dataDirectory: container).removeSnapshot(); environment.reloadWidgets() }
                catch { integrationMessage = "Widget sharing is off, but its previous snapshot could not be cleared. Try turning sharing off again." }
            }
            diagnostics.setRetention(days: dataRetention.logs)
            profileName = try await store.preference(Pref.profileName, as: String.self) ?? Greeting.defaultName(fullUserName: environment.fullUserName)
            goals = try await store.preference(Pref.goals, as: Goals.self) ?? Goals()
            agentsCounting = Self.hooks(environment).isInstalled
            claudeModOn = Self.claudeMod(environment).isInstalled
            approvedAgentNames = (try await store.preference(Pref.approvedAgentNames, as: [String].self) ?? []).filter(HookFrame.isApprovableAgentName)
            agentNameAllowlist.set(approvedAgentNames)
            lastSync = try await store.preference(Pref.lastSync, as: Date.self)
            appearance = try await store.preference(Pref.appearance, as: Appearance.self) ?? .dark
            themeName = Theme.named(try await store.preference(Pref.theme, as: String.self) ?? Theme.phosphor.name).name
            let chose = try await store.preference(Pref.loginItem, as: Bool.self) ?? false
            loginItemEnabled = chose && environment.loginItem.isEnabled
            plan = try await store.currentPlan()
            try await loadWhatsNew(store)
        } catch {
            problem = .storage("\(error)")
            diagnostics.record(.storageFailed(sqliteCode: Store.sqliteCode(of: error)))
            return
        }
        await refreshAccount()
        await finishMobileRevocation()
        await purgeIfDue()
        if environment.rewritesHome {
            _ = try? BackupRetention(paths: .init(home: environment.home)).purgeExpired(at: now)
            if Self.hooks(environment).needsRepair() { try? Self.hooks(environment).repair() }
            if Self.claudeMod(environment).needsRepair() { try? Self.claudeMod(environment).repair() }
            // The status line's wrapper names the helper by its full path; after the app moves or is renamed (Clepso.app →
            // Clepso.app) it points at nothing and Claude Code quietly falls back. Re-point it, like the hooks above.
            let statusLine = Self.installer(environment, forwardCost: forwardCost, approvedAgentTypes: approvedAgentNames)
            if statusLine.needsRepair() { try? statusLine.repair() }
        }
        listen()
        let interval = environment.tickInterval
        tasks.append(Task { [weak self] in
            // A cancelled sleep throws; stop then, rather than running one more tick after `stop()`.
            while (try? await Task.sleep(for: interval)) != nil {
                await self?.tick()
            }
        })
        notificationStatus = await environment.notifications.status()
        environment.notifications.onAction { [weak self] action in
            Task { @MainActor in await self?.handleAlertAction(action) }
        }
        await refresh()
        await alertHousekeeping()                    // launch reconciliation: reminders, and a digest due while quit
    }

    public func stop() {
        mobilePublishTask?.cancel()
        tasks.forEach { $0.cancel() }
        tasks = []
        socket?.stop()
        socket = nil
    }

    /// `copy.error.socket` → `Reconnect`.
    public func reconnect() {
        socket?.stop()
        socket = nil
        listen()
    }

    private func listen() {
        guard let store else { return }
        do {
            let socket = try IngestSocket(path: environment.socketPath, wallClock: { [clock = environment.clock] in clock.now() })
            socket.start()
            let ingestor = Ingestor(connectionID: store.connectionID, sink: StoreSink(store: store, agentNames: agentNameAllowlist) { [weak self] events in
                await self?.didIngest(events: events)
            })
            tasks.append(Task { await ingestor.consume(socket.frames) })
            self.socket = socket
            self.ingestor = ingestor
            loggedHealth = IngestSocket.Health()
            loggedCounters = Ingestor.Counters()
            if case .socket = problem { problem = nil }
            diagnostics.record(.listening)
        } catch {
            problem = .socket("\(error)")
            if case .bind(let code) = error as? IngestSocket.SocketError { diagnostics.record(.socketFailed(errno: code)) }
            else { diagnostics.record(.socketFailed(errno: nil)) }
        }
    }

    private func tick() async {
        let codexEvents = await pollCodex()
        let tickEvents = (try? await store?.tick(now: environment.clock.now())) ?? []
        await purgeIfDue()
        await syncIfDue()
        await recordIngestHealth()
        reloadStatsIfChanged()
        await refresh()
        await handleEngineEvents(codexEvents + tickEvents)
        await alertHousekeeping()
    }

    /// The footer's refresh: everything a tick does, now.
    public func refreshNow() async { await tick() }

    /// Retention (PRIVACY_AND_SECURITY §6): at launch, then at most once a day.
    func purgeIfDue() async {
        let now = environment.clock.now()
        if let lastPurge, now.timeIntervalSince(lastPurge) < 86_400 { return }
        lastPurge = now
        diagnostics.setRetention(days: dataRetention.logs)
        if let report = try? await store?.purge(now: now, retention: dataRetention.storePolicy), !report.isEmpty {
            diagnostics.record(.purged(readings: report.readings, sessions: report.sessions))
        }
    }

    /// The Diagnostics tab calls this on open so the counts are current, not up to a tick old.
    public func refreshIngestHealth() async { await recordIngestHealth() }

    /// Logs rejected updates once per tick, as counts since the last entry: never the frames themselves.
    func recordIngestHealth() async {
        guard let socket, let ingestor else { return }
        let health = socket.currentHealth
        let counters = await ingestor.counters
        socketHealth = health
        let rejected = (health.rejectedPeer - loggedHealth.rejectedPeer, health.rejectedFrame - loggedHealth.rejectedFrame,
                        health.oversize - loggedHealth.oversize, health.rateLimited - loggedHealth.rateLimited,
                        counters.unmappable - loggedCounters.unmappable)
        if rejected != (0, 0, 0, 0, 0) {
            diagnostics.record(.ingestRejected(otherUser: rejected.0, malformed: rejected.1, oversize: rejected.2,
                                               rateLimited: rejected.3, unmappable: rejected.4))
        }
        if counters.unknownRateLimitWindows != loggedCounters.unknownRateLimitWindows {
            diagnostics.record(.unreadLimitWindows(count: counters.unknownRateLimitWindows))
        }
        if counters.skewFlagged > loggedCounters.skewFlagged {
            diagnostics.record(.clockSkew(frames: counters.skewFlagged - loggedCounters.skewFlagged))
        }
        loggedHealth = health
        loggedCounters = counters
    }

    /// A real observation arrived: it ends demo mode and is the first-reading moment of onboarding.
    private func didIngest(events: [EngineEvent] = []) async {
        let now = environment.clock.now()
        if firstRealReadingAt == nil {
            firstRealReadingAt = now
            try? await store?.setPreference(Pref.firstReading, now, now: now)
        }
        if demo { await setDemo(false) } else { await refresh() }
        await handleEngineEvents(events)           // after refresh: the alert text reads the current snapshot
    }

    // MARK: - Snapshot

    public func refresh() async {
        guard let store else { return }
        if let saved = try? await store.manualAllowances() { manualAllowances = saved }
        generation += 1
        let mine = generation
        let now = environment.clock.now()
        var input: OverviewInput
        do {
            if demo {
                input = try await DemoData.input(now: now)
            } else {
                input = try await Self.read(store, now: now)
                input.installed = Self.installer(environment, forwardCost: forwardCost).isInstalled
                input.agentsTracking = Self.hooks(environment).isInstalled
                agentsCounting = input.agentsTracking
                claudeModOn = Self.claudeMod(environment).isInstalled
                input.unreadLimitWindows = await ingestor?.counters.unknownRateLimitWindows ?? 0
            }
        } catch {
            problem = .storage("\(error)")
            return
        }
        input.showPercent = showPercent
        input.codexEnabled = codexEnabled
        input.codexPlan = codexLatest?.plan
        input.codexModel = codexLatest?.model
        input.codexVersion = codexLatest?.version
        input.codexAgentTasks = codexAgentTasks
        let snapshot = OverviewProjection.make(input, now: now, staleAfter: Freshness.localTelemetryTTL,
                                               zone: environment.timeZone, locale: environment.locale)
        guard mine == generation else { return }         // a newer refresh finished first
        self.snapshot = snapshot
        publishIntegrations()
        if case .storage = problem { problem = nil }
    }

    /// One read of everything the screens need, so opening the popover never touches storage.
    static func read(_ store: Store, now: Date) async throws -> OverviewInput {
        var input = OverviewInput()
        input.pools = try await store.poolStates()
        for pool in input.pools {
            input.history[pool.poolKey] = try await store.usageHistory(poolKey: pool.poolKey, since: now.addingTimeInterval(-7 * 86_400))
        }
        input.sessions = try await store.sessionStates()
        input.sessionSummaries = try await store.sessionSummaries(limit: 20)
        input.firstSessionSeen = try await store.firstSessionSeenAt()
        for pool in input.pools {
            input.recent[pool.poolKey] = try await store.recentReadings(poolKey: pool.poolKey, kind: .quotaUsedPct, limit: 3)
        }
        input.plan = try await store.currentPlan()
        input.sourceVersion = try await store.latestSourceVersion()
        input.lastEventAt = try await store.lastEventAt()
        input.agentTasks = try await store.agentTasks(limit: 500)
        input.openAgentRuns = try await store.openAgentRuns(since: now.addingTimeInterval(-OverviewProjection.agentRunCap))
        input.backgroundSnapshots = try await store.backgroundSnapshots(since: now.addingTimeInterval(-OverviewProjection.agentRunCap))
        // Increment 3.4: other agents' pools never mix into Claude Code's section.
        input.codexPools = input.pools.filter { $0.poolKey.hasPrefix("codex.") }
        input.pools = input.pools.filter { !$0.poolKey.hasPrefix("codex.") }
        return input
    }

    // MARK: - Preferences

    public func setDemo(_ on: Bool) async {
        if demo != on { diagnostics.record(.demo(on: on)) }
        demo = on
        try? await store?.setPreference(Pref.demo, on, now: environment.clock.now())
        await refresh()
    }

    public func setShowPercent(_ on: Bool) async {
        showPercent = on
        try? await store?.setPreference(Pref.showPercent, on, now: environment.clock.now())
        await refresh()
    }

    public func setMenuBarDisplay(_ display: MenuBarDisplay) async {
        menuBarDisplay = display
        try? await store?.setPreference(Pref.menuBarDisplay, display.rawValue, now: environment.clock.now())
    }

    /// `settings.providers.forwardCost`. When installed, the helper's config is regenerated so the change applies.
    public func setForwardCost(_ on: Bool) async {
        forwardCost = on
        try? await store?.setPreference(Pref.forwardCost, on, now: environment.clock.now())
        let installer = Self.installer(environment, forwardCost: on, approvedAgentTypes: approvedAgentNames)
        if environment.rewritesHome, installer.isInstalled { try? installer.repair() }
    }

    /// RELEASE_ROADMAP §6: after the version changes, the newest entry the user hasn't seen. A fresh install (onboarding
    /// not finished) only records the version: onboarding introduces everything, so nothing is "new" yet.
    private func loadWhatsNew(_ store: Store) async throws {
        let current = environment.appVersion
        let lastSeen = try await store.preference(Pref.whatsNewSeen, as: String.self)
        guard lastSeen != current else { return }
        whatsNew = onboardingComplete ? WhatsNew.entry(lastSeen: lastSeen, current: current) : nil
        if whatsNew == nil { try await store.setPreference(Pref.whatsNewSeen, current, now: environment.clock.now()) }
    }

    /// Home has shown the card: it won't show again after a relaunch. It stays on screen until dismissed.
    func whatsNewShown() async {
        guard whatsNew != nil else { return }
        try? await store?.setPreference(Pref.whatsNewSeen, environment.appVersion, now: environment.clock.now())
    }

    func dismissWhatsNew() async {
        guard whatsNew != nil else { return }
        whatsNew = nil
        try? await store?.setPreference(Pref.whatsNewSeen, environment.appVersion, now: environment.clock.now())
    }

    /// The card's changelog link: the only way it reaches the web, and only by the user's click (their browser opens it).
    func openChangelog() {
        environment.openLink(WhatsNew.changelogURL)
    }

    public func completeOnboarding() async {
        onboardingComplete = true
        try? await store?.setPreference(Pref.onboardingComplete, true, now: environment.clock.now())
    }

    // MARK: - Plan (chosen by the user, never inferred)

    /// nil entry is "Not sure": the current plan ends and the header reads `Plan not set`.
    public func choosePlan(_ entry: PlanCatalog.Entry?, confirmed: Bool) async {
        guard let store else { return }
        try? await store.setPlan(catalogID: entry?.id, displayName: entry?.displayName,
                                 evidence: confirmed ? .userConfirmed : .userSelectedUnverified, now: environment.clock.now())
        plan = try? await store.currentPlan()
        diagnostics.record(.planChanged(catalogID: entry?.id, confirmed: confirmed && entry != nil))
        await refresh()
    }

    // MARK: - Claude Code connection

    public enum InstallOutcome: Equatable, Sendable {
        case installed(backupPath: String?, keptExisting: Bool)
        case failed(reason: String)
    }

    public func refreshPreview() {
        preview = Self.installer(environment, forwardCost: forwardCost).preview()
    }

    /// The only path that writes Claude Code's settings, and only from the consent screen's `Install`.
    public func install() async -> InstallOutcome {
        let installer = Self.installer(environment, forwardCost: forwardCost, approvedAgentTypes: approvedAgentNames)
        defer { refreshPreview() }
        do {
            let report = try installer.install()
            diagnostics.record(.installed(keptExisting: report.hadExistingStatusLine,
                                          backupFingerprint: report.backupPath.map { Redacted($0, label: "backup_path").fingerprint }))
            await refresh()
            return .installed(backupPath: report.backupPath, keptExisting: report.hadExistingStatusLine)
        } catch let error as SettingsInstaller.InstallError {
            diagnostics.record(.installRefused(reason: Self.caseName(error)))
            return .failed(reason: Self.reason(error))
        } catch {
            return .failed(reason: "\(error)")
        }
    }

    public enum RemoveOutcome: Equatable, Sendable { case restoredExactly, removedOurEntryOnly, nothingToRemove, failed(reason: String) }

    /// `settings.providers.remove`, after its confirmation sheet.
    public func uninstall() async -> RemoveOutcome {
        defer { refreshPreview() }
        do {
            let outcome = try removeFromClaudeCode()
            diagnostics.record(.removed(outcome: Self.caseName(outcome)))
            await refresh()
            switch outcome {
            case .restoredExactly, .deletedCreatedFile: return .restoredExactly
            case .restoredStatusLineOnly: return .removedOurEntryOnly
            case .notInstalled, .leftUnchanged: return .nothingToRemove
            }
        } catch {
            diagnostics.record(.removed(outcome: "failed"))
            return .failed(reason: "\(error)")
        }
    }

    /// An enum value's case name without its payload, which can hold a path.
    static func caseName(_ value: Any) -> String {
        Mirror(reflecting: value).children.first?.label ?? String(describing: value)
    }

    // MARK: - Home, card, goals, account (increment 1.10)

    public func setAppearance(_ value: Appearance) async {
        appearance = value
        try? await store?.setPreference(Pref.appearance, value, now: environment.clock.now())
    }

    public func setTheme(_ name: String) async {
        themeName = Theme.named(name).name
        try? await store?.setPreference(Pref.theme, themeName, now: environment.clock.now())
    }

    public func setProfileName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profileName = trimmed.isEmpty ? nil : String(trimmed.prefix(40))
        try? await store?.setPreference(Pref.profileName, profileName ?? "", now: environment.clock.now())
    }

    public func setGoals(_ goals: Goals) async {
        self.goals = goals
        try? await store?.setPreference(Pref.goals, goals, now: environment.clock.now())
    }

    var greeting: String { Greeting.make(environment.clock.now(), zone: environment.timeZone, name: profileName) }

    var statsFile: ClaudeCodeStats? { if case .success(let file)? = stats { file } else { nil } }

    var playerCard: PlayerCard? {
        guard let file = statsFile, let summary = statsSummary(.allTime) else { return nil }
        return PlayerCard.make(file: file, summary: summary, name: profileName ?? "", plan: plan?.displayName,
                               lines: snapshot.provider?.lines, updatedAt: [statsCheckedAt, snapshot.updatedAt].compactMap { $0 }.max())
    }

    var runningTotal: RunningTotal? { statsFile.map(RunningTotal.make) }

    var goalStatuses: [GoalStatus] {
        let pools = snapshot.provider?.pools ?? []
        let five = pools.first { $0.poolKey.hasSuffix("five_hour") }, seven = pools.first { $0.poolKey.hasSuffix("seven_day") }
        let sevenPct = seven?.model.used.value.map { NSDecimalNumber(decimal: $0).doubleValue }
        return GoalEvaluator.evaluate(goals, last7: statsSummary(.last7), fiveHourHistory: five?.history ?? [], sevenDayPct: sevenPct,
                                      sevenDayPace: seven?.pace, now: environment.clock.now(), zone: environment.timeZone)
    }

    // MARK: - Account and sync

    /// Whether this build can sign in at all. Builds from source carry no accounts project, so Sync stays off.
    public var accountsAvailable: Bool { environment.sync.isAvailable }

    public func refreshAccount() async {
        if let session = await environment.sync.session { account = .signedIn(email: session.email) }
        else if let email = await environment.sync.pendingEmail { account = .linkSent(email: email) }
        else { account = .signedOut }
    }

    /// "Email me a link": a one-time sign-in link to `email`, which opens Clepso on this Mac.
    public func emailSignInLink(_ email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accountsAvailable else { accountMessage = Copy.Sync.unavailable; return }
        guard trimmed.contains("@"), trimmed.count <= 254 else { accountMessage = Copy.Sync.invalidEmail; return }
        accountBusy = true
        defer { accountBusy = false }
        do {
            try await environment.sync.requestEmailLink(trimmed)
            account = .linkSent(email: trimmed)
            accountMessage = Copy.Sync.linkSent(trimmed)
        } catch {
            accountMessage = Self.syncReason(error)
        }
    }

    /// The sign-in link's return to the app (`clepso://auth-callback?code=…`).
    public func handleOpenURL(_ url: URL) async {
        guard url.scheme == SyncConfig.urlScheme else { return }
        if url.host == "dashboard", url.query == nil, url.fragment == nil {
            detailsSection = .limits; return
        }
        // An isolated debug run shares the installed app's URL scheme: a link for a sign-in it did not start is not its own.
        if environment.isolated, !(await environment.sync.hasPendingSignIn) { return }
        detailsSection = .account
        accountBusy = true
        defer { accountBusy = false }
        do {
            let session = try await environment.sync.handleCallback(url)
            account = .signedIn(email: session.email)
            accountMessage = Copy.Sync.signedIn
            diagnostics.record(.account(event: "signed in"))
            await syncNow()
        } catch {
            accountMessage = Self.syncReason(error)
            await refreshAccount()
        }
    }

    public func cancelSignIn() async {
        guard !mobileSharingBusy else { return }
        if mobileSharing.enabled || mobileSharing.pendingRevocation {
            guard await setMobileSharing(false) else { return }
        }
        await environment.sync.signOut()
        account = .signedOut
        accountMessage = nil
    }

    public func signOut() async {
        guard !mobileSharingBusy else { accountMessage = "Wait for the mobile sharing change to finish, then sign out."; return }
        if mobileSharing.enabled || mobileSharing.pendingRevocation {
            guard await setMobileSharing(false) else { accountMessage = "Could not save mobile sharing off. Retry before signing out."; return }
        }
        await environment.sync.signOut()
        account = .signedOut
        accountMessage = Copy.Sync.signedOut
        diagnostics.record(.account(event: "signed out"))
    }

    /// Deletes the account and everything stored with it on the server; nothing on this Mac changes.
    public func deleteAccount() async {
        guard !mobileSharingBusy else { accountMessage = "Wait for the sharing change to finish before deleting your account."; return }
        accountBusy = true
        defer { accountBusy = false }
        do {
            try await environment.sync.deleteAccount()
            mobileSharing = MobileSharingState()
            try? await store?.setPreference(Pref.mobileSharing, mobileSharing, now: environment.clock.now())
            account = .signedOut
            lastSync = nil
            try? await store?.setPreference(Pref.lastSync, Date?.none, now: environment.clock.now())
            accountMessage = Copy.Sync.deleted
            diagnostics.record(.account(event: "account deleted"))
        } catch {
            accountMessage = Self.syncReason(error)
        }
    }

    /// Uploads the last 14 days of counts now. Never while demo data is showing.
    public func syncNow() async {
        guard case .signedIn = account, !snapshot.isDemo, let store else { return }
        let now = environment.clock.now()
        lastSyncAttempt = now
        do {
            let pools = snapshot.provider?.pools ?? []
            func history(_ suffix: String) async throws -> [UsagePoint] {
                guard let key = pools.first(where: { $0.poolKey.hasSuffix(suffix) })?.poolKey else { return [] }
                return try await store.usageHistory(poolKey: key, since: now.addingTimeInterval(-14 * 86_400))
            }
            loadStats()
            let input = SyncPayloadBuilder.Input(profileName: profileName, planLabel: plan?.displayName, stats: statsEnabled ? statsFile : nil,
                                                 fiveHour: try await history("five_hour"), sevenDay: try await history("seven_day"),
                                                 agentTasks: agentsCounting ? try await store.agentTasks(limit: 2000) : nil,
                                                 goals: goals, goalStatuses: goalStatuses, now: now, zone: environment.timeZone)
            try await environment.sync.upload(SyncPayloadBuilder.make(input))
            lastSync = now
            accountMessage = nil
            try? await store.setPreference(Pref.lastSync, now, now: now)
        } catch {
            accountMessage = Self.syncReason(error)
            if case SyncError.notSignedIn? = error as? SyncError { account = .signedOut }
        }
    }

    /// Upload on quit: the counts since the last hourly upload are sent before Clepso quits. True when signed in,
    /// real data shows, and the last upload is more than a minute old.
    public var uploadsOnQuit: Bool {
        guard case .signedIn = account, !snapshot.isDemo else { return false }
        guard let lastSync else { return true }
        return environment.clock.now().timeIntervalSince(lastSync) >= 60
    }

    /// One last upload, given at most `limit`: quitting never waits longer, offline or not. True if it finished in time.
    public func uploadBeforeQuit(limit: Duration = .seconds(3)) async -> Bool {
        guard uploadsOnQuit else { return true }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.syncNow(); return true }
            group.addTask { try? await Task.sleep(for: limit); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Once an hour while signed in.
    func syncIfDue() async {
        guard case .signedIn = account else { return }
        let now = environment.clock.now()
        if let last = lastSyncAttempt, now.timeIntervalSince(last) < 3600 { return }
        await syncNow()
    }

    static func syncReason(_ error: Error) -> String {
        switch error as? SyncError {
        case .unavailable?: Copy.Sync.unavailable
        case .notSignedIn?: Copy.Sync.notSignedIn
        case .noPendingSignIn?: Copy.Sync.noPending
        case .invalidCallback?: Copy.Sync.linkFailed      // the link's own text is never shown: any app can open the URL
        case .http(let status, let code)?: Copy.Sync.serverError(status, code)
        case .badResponse?: Copy.Sync.badResponse
        case nil: Copy.Sync.offline
        }
    }

    // MARK: - Agents per task (increment 1.9)

    public enum AgentsOutcome: Equatable, Sendable { case added, removedExactly, removedEntries, alreadyGone, failed(reason: String) }


    /// Settings › Providers › "Count subagents per task", after its confirmation for turning on.
    public func setAgentsCounting(_ on: Bool) async -> AgentsOutcome {
        let hooks = Self.hooks(environment)
        defer {
            agentsCounting = hooks.isInstalled
            Task { await refresh() }
        }
        do {
            if on {
                try hooks.install()
                diagnostics.record(.agentsCounting(outcome: "added"))
                return .added
            }
            let outcome = try hooks.uninstall()
            diagnostics.record(.agentsCounting(outcome: Self.caseName(outcome)))
            return switch outcome {
            case .restoredExactly: .removedExactly
            case .removedEntries: .removedEntries
            case .notInstalled, .entriesAlreadyGone: .alreadyGone
            }
        } catch {
            diagnostics.record(.agentsCounting(outcome: "refused " + Self.caseName(error)))
            return .failed(reason: Self.hooksReason(error))
        }
    }

    public var agentsPreview: (file: String, entry: String) {
        let hooks = Self.hooks(environment)
        return (hooks.paths.settings.path, hooks.previewEntry)
    }

    static func hooks(_ environment: AppEnvironment) -> HooksInstaller {
        HooksInstaller(paths: .init(home: environment.home), shimPath: environment.shimPath, now: { [clock = environment.clock] in clock.now() })
    }

    static func hooksReason(_ error: Error) -> String {
        switch error as? HooksInstaller.InstallError {
        case .connectionNotInstalled: Copy.Agents.needsConnection
        case .unsupportedExistingHooks: "its hooks section has a shape Clepso can't edit safely"
        case .settingsInvalidJSON: "settings.json isn't valid JSON"
        case .settingsChangedDuringInstall: "settings.json changed while Clepso was writing; try again"
        case .alreadyInstalled: "the hooks are already there"
        case .verificationFailed: "the result didn't check out, so it was put back"
        default: "\(error)"
        }
    }

    /// `approvedAgentTypes` nil keeps the names the helper's config already lists (callers that only read or remove).
    static func installer(_ environment: AppEnvironment, forwardCost: Bool, approvedAgentTypes: [String]? = nil) -> SettingsInstaller {
        SettingsInstaller(paths: .init(home: environment.home), shimPath: environment.shimPath,
                          socketPath: environment.socketPath, forwardCost: forwardCost, approvedAgentTypes: approvedAgentTypes,
                          now: { [clock = environment.clock] in clock.now() })
    }

    // MARK: - The layout from before the rename to Clepso

    static func legacyLayout(_ environment: AppEnvironment) -> LegacyLayoutMigration {
        LegacyLayoutMigration(home: environment.home, now: { [clock = environment.clock] in clock.now() })
    }

    /// An install still in `~/.claude/pulse`, when the move couldn't happen (`keptBoth`, `settingsUnreadable`).
    static func legacyInstaller(_ environment: AppEnvironment, forwardCost: Bool) -> SettingsInstaller {
        SettingsInstaller(paths: .legacy(home: environment.home), shimPath: environment.shimPath,
                          socketPath: environment.socketPath, forwardCost: forwardCost, now: { [clock = environment.clock] in clock.now() })
    }

    static func legacyHooks(_ environment: AppEnvironment) -> HooksInstaller {
        HooksInstaller(paths: .legacy(home: environment.home), shimPath: environment.shimPath, now: { [clock = environment.clock] in clock.now() })
    }

    /// Takes Clepso out of Claude Code's settings: the mod and the hooks first (they call the helper through Clepso's folder), then
    /// the status line. One more try at moving an old layout first; whatever of it is still there (both folders existed,
    /// or settings.json couldn't be edited) is removed by its own install records, the same way, so Remove and Delete
    /// work from either layout. Each installer touches settings.json only where its own record or command matches.
    func removeFromClaudeCode() throws -> SettingsInstaller.UninstallOutcome {
        _ = Self.legacyLayout(environment).run()
        if Self.claudeMod(environment).isInstalled { _ = try Self.claudeMod(environment).uninstall() }
        if Self.hooks(environment).isInstalled { _ = try Self.hooks(environment).uninstall() }
        var outcome = try Self.installer(environment, forwardCost: forwardCost).uninstall()
        let legacy = Self.legacyInstaller(environment, forwardCost: forwardCost)
        if Self.isRealDirectory(legacy.paths.clepsoDir) {
            if Self.legacyHooks(environment).isInstalled { _ = try Self.legacyHooks(environment).uninstall() }
            let legacyOutcome = try legacy.uninstall()
            if outcome == .notInstalled { outcome = legacyOutcome }
        }
        return outcome
    }

    /// `copy.explainer.installFailed` {{reason}}: plain words, never an enum name.
    static func reason(_ error: SettingsInstaller.InstallError) -> String {
        switch error {
        case .claudeNotDetected: "Claude Code's settings folder (~/.claude) wasn't found."
        case .settingsInvalidJSON: "Claude Code's settings file isn't valid JSON, so it was left alone."
        case .unsupportedExistingStatusLine: "Your current status line uses a form Clepso can't wrap safely."
        case .alreadyInstalled: "A previous install didn't finish. Open Settings › Providers to recover."
        case .settingsChangedDuringInstall: "The settings file changed while installing. Try again."
        case .symlinkRefused: "The settings file is a link to another file, so it was left alone."
        case .verificationFailed: "The change couldn't be verified, so it was undone."
        case .io(let detail): "A file couldn't be written (\(detail))."
        }
    }

    // MARK: - Login item and notifications (consent first)

    /// Called only from the user's own toggle: onboarding's done step or Settings › General.
    public func setLoginItem(_ enabled: Bool) async {
        let applied = (try? environment.loginItem.setEnabled(enabled)) != nil
        let chose = enabled && applied
        loginItemEnabled = chose && environment.loginItem.isEnabled
        diagnostics.record(.loginItem(on: chose))
        try? await store?.setPreference(Pref.loginItem, chose, now: environment.clock.now())
    }

    /// Onboarding offers this only after a real observation; Settings offers it any time on request.
    public func requestNotifications() async {
        notificationStatus = await environment.notifications.request()
        diagnostics.record(.notifications(status: notificationStatus.rawValue))
    }

    public func refreshNotificationStatus() async {
        notificationStatus = await environment.notifications.status()
    }

    public func sendTestNotification() async {
        await environment.notifications.sendTest(title: "\(Product.name) test", body: "Notifications are working.")
    }

    // MARK: - Claude Code statistics (increment 1.7d; PRIVACY_AND_SECURITY §4.1)

    /// The user's choice from the Stats view's explainer or Settings › Providers.
    public func setStatsEnabled(_ on: Bool) async {
        statsEnabled = on
        try? await store?.setPreference(Pref.readStats, on, now: environment.clock.now())
        diagnostics.record(.statsReading(on: on))
        if on { loadStats() } else { stats = nil }
    }

    /// Reads the file now (it is small). Nothing from it is stored.
    public func loadStats() {
        guard statsEnabled else { stats = nil; statsCheckedAt = nil; return }
        statsModifiedAt = Self.modificationDate(StatsReader.url(home: environment.home))
        stats = StatsReader.read(home: environment.home)
        statsCheckedAt = environment.clock.now()
    }

    /// Each tick: re-reads the file when Claude Code has rewritten it (it does so as it folds in finished days), so the
    /// card, Stats and Goals follow it without reopening; otherwise only notes the check.
    func reloadStatsIfChanged() {
        guard statsEnabled else { return }
        let modified = Self.modificationDate(StatsReader.url(home: environment.home))
        if stats == nil || modified != statsModifiedAt { loadStats() } else { statsCheckedAt = environment.clock.now() }
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// The summary for a range, counting the days after the statistics file's last day on which Clepso itself received
    /// Claude Code readings (see `seenDays`).
    public func statsSummary(_ range: StatsSummary.Range) -> StatsSummary? {
        guard case .success(let file)? = stats else { return nil }
        let today = Self.dayLabel(environment.clock.now(), zone: environment.timeZone)
        return StatsSummary.make(file, range: range, today: today, seenDays: snapshot.isDemo ? [] : Self.seenDays(snapshot, zone: environment.timeZone))
    }

    /// Local days with Claude Code readings in Clepso's own store: the newest reading, the limit readings of the last
    /// seven days, and when each kept session was last seen. Claude Code's pools only; demo data is never evidence.
    static func seenDays(_ snapshot: OverviewSnapshot, zone: TimeZone) -> Set<String> {
        guard let provider = snapshot.provider else { return [] }
        let instants = [snapshot.updatedAt] + provider.pools.flatMap { $0.history.map(\.at) } + provider.sessions.map(\.lastSeen)
        return Set(instants.compactMap { $0 }.map { dayLabel($0, zone: zone) })
    }

    /// Claude Code labels days by the local calendar.
    static func dayLabel(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Export and delete-all (PRIVACY_AND_SECURITY §8)

    /// "Export my data…" to a location the user chose in the save panel.
    public func export(to url: URL) async -> Result<Exporter.Summary, ExportFailure> {
        guard let store else { return .failure(ExportFailure(reason: Copy.Problem.storage)) }
        do {
            let (data, summary) = try Exporter.document(try await store.exportRows(), exportedAt: environment.clock.now(),
                                                        appVersion: environment.appVersion, retention: dataRetention)
            try Exporter.write(data, to: url)
            diagnostics.record(.exported(rows: summary.rows, scrubbed: summary.scrubbed))
            return .success(summary)
        } catch {
            return .failure(ExportFailure(reason: error.localizedDescription))
        }
    }

    public struct ExportFailure: Error, Equatable, Sendable { public let reason: String }

    public struct DeleteReport: Equatable, Sendable {
        /// nil when every step ran. When restoring settings fails, nothing at all is deleted.
        public var failure: String?
        /// Files in the data folder Clepso did not create, left in place and named here (file names only).
        public var leftovers: [String] = []
        public var backupsRemoved = false
    }

    /// The items the confirmation dialog names (§8 step 1).
    /// What "Delete Clepso data…" can remove, each its own checkbox (founder review, 18 Oct 2026). Claude Code's status
    /// line and hooks go with the helper folder they call: removing one without the other would leave Claude Code
    /// running a helper that isn't there, or a helper nothing calls.
    public enum DeleteItem: String, CaseIterable, Sendable, Hashable {
        case data, diagnostics, notifications, claudeCode, account
    }

    /// Each item with the line the checkbox shows, in the order they're deleted.
    public var deleteItems: [(item: DeleteItem, label: String)] {
        let paths = SettingsInstaller.Paths(home: environment.home)
        return [(.data, Copy.DeleteAll.itemData(environment.databaseURL.lastPathComponent)),
                (.diagnostics, Copy.DeleteAll.itemDiagnostics),
                (.notifications, Copy.DeleteAll.itemNotifications),
                (.claudeCode, Copy.DeleteAll.itemClaudeCode("~" + paths.clepsoDir.path.dropFirst(environment.home.path.count))),
                (.account, Copy.DeleteAll.itemAccount)]
    }

    /// "Delete all Clepso data…" with everything ticked: a fresh install (§8).
    /// `relaunch` false leaves the app stopped, so a test can inspect the empty folders.
    public func deleteAll(includeBackups: Bool, relaunch: Bool = true) async -> DeleteReport {
        await delete(Set(DeleteItem.allCases), includeBackups: includeBackups, relaunch: relaunch)
    }

    /// Deletes what was ticked, in the order of §8. Claude Code's settings are restored first: if that can't be done
    /// safely, nothing at all is deleted. Turning off the login item is part of the full delete only.
    public func delete(_ items: Set<DeleteItem>, includeBackups: Bool, relaunch: Bool = true) async -> DeleteReport {
        guard !mobileSharingBusy else { return DeleteReport(failure: "Wait for the mobile sharing change to finish, then retry deletion.") }
        var report = DeleteReport()
        let installer = Self.installer(environment, forwardCost: forwardCost)
        let paths = installer.paths
        let fm = FileManager.default
        let everything = items == Set(DeleteItem.allCases)

        // Claude Code's settings first. If they can't be restored safely, stop with everything intact: the backup and
        // the sidecar are what make the restore possible.
        if items.contains(.claudeCode) {
            let legacy = Self.legacyInstaller(environment, forwardCost: forwardCost)
            if case .needsUserDecision = installer.recover() {
                return DeleteReport(failure: Copy.DeleteAll.restoreFailed(paths.backupsDir.path))
            }
            if Self.isRealDirectory(legacy.paths.clepsoDir), case .needsUserDecision = legacy.recover() {
                return DeleteReport(failure: Copy.DeleteAll.restoreFailed(legacy.paths.backupsDir.path))
            }
            do {
                _ = try removeFromClaudeCode()
            } catch {
                return DeleteReport(failure: Copy.DeleteAll.restoreFailed(paths.backupsDir.path))
            }
            for folder in [paths.clepsoDir, legacy.paths.clepsoDir] where Self.isRealDirectory(folder) { try? fm.removeItem(at: folder) }
        }
        if items.contains(.notifications) { await environment.notifications.removeAll() }
        if items.contains(.account) || items.contains(.data), mobileSharing.enabled || mobileSharing.pendingRevocation {
            guard await setMobileSharing(false) else { return DeleteReport(failure: "Could not save mobile sharing off. Retry before deleting local data.") }
        }
        if items.contains(.account) {
            await environment.sync.signOut()
            account = .signedOut
            lastSync = nil
            environment.keychain.deleteAll()
        }
        if everything, (try? await store?.preference(Pref.loginItem, as: Bool.self)) == true { try? environment.loginItem.setEnabled(false) }
        if items.contains(.diagnostics) { diagnostics.clear() }

        // The database (and with it every preference) and the socket: the app starts over as a fresh install.
        if items.contains(.data) {
            do { try SnapshotFile(dataDirectory: environment.dataDirectory).revokeAndRemove() }
            catch { return DeleteReport(failure: "Could not revoke integration access. No usage data was deleted.") }
            guard !widgetSharingBusy else { return DeleteReport(failure: "A sharing change is still being saved. Try deleting data again shortly.") }
            // Deletion must also work when storage failed to open. Clear the external snapshot synchronously
            // before closing/removing SQLite; no publisher can interleave this main-actor transition.
            do {
                if let container = environment.widgetContainer() { try SnapshotFile(dataDirectory: container).removeSnapshot() }
            } catch { return DeleteReport(failure: "Could not clear widget sharing. No usage data was deleted.") }
            widgetsEnabled = false
            lastWidgetSnapshot = nil
            environment.reloadWidgets()
            stop()
            try? await store?.close()
            store = nil
            ingestor = nil
            // The data folder, and the one from before the rename to Clepso if it is still there (it was in use, or both
            // existed): the same files under either database name, and nothing the app didn't create.
            var leftovers: [String] = []
            for data in [environment.dataDirectory, environment.legacyDataDirectory].compactMap({ $0 }) where Self.isRealDirectory(data) {
                let databases = [LegacyDataMigration.databaseName, LegacyDataMigration.legacyDatabaseName]
                let contents = (try? fm.contentsOfDirectory(atPath: data.path)) ?? []
                let migrationBackups = contents.filter { name in databases.contains { name.hasPrefix("\($0).pre-") } && name.hasSuffix(".bak") }
                var names = databases.flatMap { db in [db] + LegacyDataMigration.companions.map { db + $0 } } + ["run/agent.sock", "integrations/mcp-clients.json"] + migrationBackups
                if items.contains(.diagnostics) { names.append("diagnostics.jsonl") }
                for name in names { try? fm.removeItem(at: data.appendingPathComponent(name)) }
                for folder in [data.appendingPathComponent("run"), data.appendingPathComponent("integrations"), data] where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                    try? fm.removeItem(at: folder)
                }
                leftovers += ((try? fm.contentsOfDirectory(atPath: data.path)) ?? []).filter { $0 != "diagnostics.jsonl" }
            }
            report.leftovers = leftovers.sorted()
            reset()
            refreshPreview()
            if relaunch { await start() }
        } else {
            await refresh()                                // e.g. "not connected" once Claude Code's settings are restored
        }

        // Settings backups only when that box was ticked (default off); the old layout's folder too if it is still there.
        if includeBackups {
            let folders = [paths.backupsDir, SettingsInstaller.Paths.legacy(home: environment.home).backupsDir].filter(Self.isRealDirectory)
            report.backupsRemoved = !folders.isEmpty && folders.allSatisfy { (try? fm.removeItem(at: $0)) != nil }
        }
        return report
    }

    /// Every in-memory value back to what a fresh install has.
    private func reset() {
        started = false
        problem = nil
        plan = nil
        loginItemEnabled = false
        onboardingComplete = false
        whatsNew = nil
        firstRealReadingAt = nil
        demo = false
        showPercent = true
        menuBarDisplay = .rotating
        forwardCost = true
        approvedAgentNames = []
        agentNameAllowlist.set([])
        statsEnabled = false
        stats = nil
        codexEnabled = false
        codexLatest = nil
        alertsEnabled = true
        alertsSnoozedUntil = nil
        quietHours = QuietHours()
        reminderLead = nil
        dataRetention = DataRetention()
        manualAllowances = []
        mcpClients = []
        widgetsEnabled = false
        mobileSharing = MobileSharingState()
        lastMobileAttempt = nil
        integrationMessage = nil
        codexConnection = nil
        lastSync = nil
        accountMessage = nil
        appearance = .dark
        themeName = Theme.phosphor.name
        socketHealth = IngestSocket.Health()
        popoverRoute = .overview
        onboardingStep = .welcome
        settingsTab = .general
        snapshot = OverviewProjection.make(OverviewInput(), now: environment.clock.now(), staleAfter: Freshness.localTelemetryTTL,
                                           zone: environment.timeZone, locale: environment.locale)
    }

    static func isRealDirectory(_ url: URL) -> Bool {
        guard let type = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else { return false }
        return type == .typeDirectory                     // attributesOfItem does not follow a final symlink
    }

    enum Pref {
        static let onboardingComplete = "onboarding.completed"
        static let widgets = "integrations.widgets.v1"
        static let mobileSharing = "integrations.mobileSharing.v1"
        static let demo = "demo.enabled"
        static let showPercent = "menubar.showPercent"
        static let menuBarDisplay = "menubar.display"
        static let forwardCost = "claudeCode.forwardCost"
        static let firstReading = "onboarding.firstReadingAt"
        static let loginItem = "general.openAtLogin"
        static let readStats = "claudeCode.readStatsFile"
        static let profileName = "profile.name"
        static let goals = "goals.v1"
        static let lastSync = "account.lastSync"
        static let appearance = "general.appearance"
        static let readCodex = "codex.readSessionFiles"
        static let alertsEnabled = "alerts.enabled"
        static let alertsSnoozedUntil = "alerts.snoozedUntil"
        static let quietHours = "alerts.quietHours"
        static let reminderLead = "alerts.resetReminderLeadMinutes"
        static let dataRetention = "data.retention.v1"
        static let theme = "general.theme"
        static let approvedAgentNames = "claudeCode.approvedAgentNames"
        static let whatsNewSeen = "whatsNew.lastSeenVersion"
    }
}

/// Ingest → store (ARCHITECTURE §4): one transaction per frame, then a snapshot refresh.
struct StoreSink: IngestSink {
    let store: Store
    var agentNames = AgentNameAllowlist()
    let didIngest: @Sendable ([EngineEvent]) async -> Void

    func ingest(_ batch: IngestBatch) async {
        let meta = batch.sessionRef.map { Store.SessionMeta(sessionRef: $0, modelID: batch.modelID, modelDisplayName: batch.modelDisplayName) }
        // Refresh even when nothing new was stored: the frame itself proves the connection is live.
        guard let result = try? await store.ingest(batch.observations, session: meta) else { return }
        await didIngest(result.events)
    }

    func ingest(hook: HookFrame.Decoded, at: Date) async {
        let kind: Store.AgentEvent.Kind = switch hook.event {
        case .promptSubmitted: .promptSubmitted
        case .subagentStarted: .subagentStarted
        case .subagentStopped: .subagentStopped
        case .stopped: .stopped
        }
        let type = hook.agentType.map(agentNames.filter)
        guard (try? await store.record(.init(kind: kind, sessionRef: hook.sessionRef, agentRef: hook.agentRef, agentType: type, at: at,
                                             background: hook.background.map(Self.counts(agentNames))))) != nil
        else { return }
        await didIngest([])
    }

    /// A frame's background counts as the store keeps them, each agent type re-checked against the current list.
    static func counts(_ names: AgentNameAllowlist) -> (HookFrame.Background) -> Store.BackgroundCounts {
        { background in
            var agents: [String: [String: Int]] = [:]
            for (type, statuses) in background.agents {
                for (status, n) in statuses { agents[names.filter(type), default: [:]][status.rawValue, default: 0] += n }
            }
            return Store.BackgroundCounts(tasks: Dictionary(uniqueKeysWithValues: background.tasks.map { type, statuses in
                (type.rawValue, Dictionary(uniqueKeysWithValues: statuses.map { ($0.key.rawValue, $0.value) }))
            }), agents: agents)
        }
    }
}
