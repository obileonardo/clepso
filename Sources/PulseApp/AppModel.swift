import ClaudeCodeAdapter
import struct CodexAdapter.CodexReading
import DesignSystem
import enum Domain.EvidenceKind
import enum Domain.Freshness
import enum Domain.Product
import struct Domain.Redacted
import Foundation
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
    public internal(set) var dashboardRequests = 0
    /// On only when the user chose it here and the system confirms it. `SMAppService.mainApp.status` was seen
    /// reporting `.enabled` for a development build that never registered, so the system's word alone is not enough.
    public private(set) var loginItemEnabled = false
    public private(set) var onboardingComplete = false
    public private(set) var firstRealReadingAt: Date?
    public private(set) var demo = false
    public private(set) var showPercent = true
    public private(set) var forwardCost = true          // On by default
    /// Increment 1.7d: reading Claude Code's own statistics file is a second source, so it is off until the user agrees.
    public private(set) var statsEnabled = false
    /// Increment 3.4: read Codex's session files (opt-in) and the latest reading's plan and model.
    public internal(set) var codexEnabled = false
    var codexLatest: CodexReading?
    var codexConnection: UUID?
    /// The Pulse account on this Mac.
    public enum AccountState: Equatable, Sendable {
        case signedOut
        case linkSent(email: String)
        case signedIn(email: String?)
    }
    public private(set) var account: AccountState = .signedOut
    public private(set) var lastSync: Date?
    public private(set) var accountMessage: String?
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
    /// Agents per task: the hooks are in Claude Code's settings (read from Pulse's install record).
    public private(set) var agentsCounting = false
    public private(set) var stats: Result<ClaudeCodeStats, StatsReader.Problem>?
    public private(set) var started = false
    public var settingsTab: SettingsTab = .general
    /// Navigation lives here so "Connect…" and similar can deep-link, and Escape always has one place to go back to.
    public var popoverRoute: PopoverRoute = .overview
    public var onboardingStep: OnboardingStep = .welcome
    public var detailsSection: DetailsSection = .home
    public var statsRange: StatsSummary.Range = .allTime
    /// The year the all-time calendar shows; nil means the current year.
    public var statsYear: Int?
    public var modelsView: ModelsView = .arena
    /// The delete-all confirmation sheet; on the model so the verification probe can show it.
    public var confirmingDeleteAll = false
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
    private var lastPurge: Date?
    private var tasks: [Task<Void, Never>] = []
    private var generation = 0

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.catalog = try? PlanCatalog.bundled()
        self.diagnostics = DiagnosticsLog(url: environment.diagnosticsURL, clock: environment.clock)
        self.preview = Self.installer(environment, forwardCost: true).preview()
        self.snapshot = OverviewProjection.make(OverviewInput(), now: environment.clock.now(), staleAfter: Freshness.localTelemetryTTL,
                                                zone: environment.timeZone, locale: environment.locale)
    }

    // MARK: - Lifecycle

    public func start() async {
        guard !started else { return }
        started = true
        PixelFonts.ensureRegistered()                    // before the first popover open, not during it
        let now = environment.clock.now()
        diagnostics.record(.appStarted(version: environment.appVersion))
        do {
            let store = try Store.onDisk(at: environment.databaseURL, now: now)
            self.store = store
            onboardingComplete = try await store.preference(Pref.onboardingComplete, as: Bool.self) ?? false
            demo = try await store.preference(Pref.demo, as: Bool.self) ?? false
            showPercent = try await store.preference(Pref.showPercent, as: Bool.self) ?? true
            forwardCost = try await store.preference(Pref.forwardCost, as: Bool.self) ?? true
            firstRealReadingAt = try await store.preference(Pref.firstReading, as: Date.self)
            statsEnabled = try await store.preference(Pref.readStats, as: Bool.self) ?? false
            codexEnabled = try await store.preference(Pref.readCodex, as: Bool.self) ?? false
            alertsEnabled = try await store.preference(Pref.alertsEnabled, as: Bool.self) ?? true
            alertsSnoozedUntil = try await store.preference(Pref.alertsSnoozedUntil, as: Date.self)
            profileName = try await store.preference(Pref.profileName, as: String.self) ?? Greeting.defaultName(fullUserName: environment.fullUserName)
            goals = try await store.preference(Pref.goals, as: Goals.self) ?? Goals()
            agentsCounting = Self.hooks(environment).isInstalled
            lastSync = try await store.preference(Pref.lastSync, as: Date.self)
            appearance = try await store.preference(Pref.appearance, as: Appearance.self) ?? .dark
            themeName = Theme.named(try await store.preference(Pref.theme, as: String.self) ?? Theme.phosphor.name).name
            let chose = try await store.preference(Pref.loginItem, as: Bool.self) ?? false
            loginItemEnabled = chose && environment.loginItem.isEnabled
            plan = try await store.currentPlan()
        } catch {
            problem = .storage("\(error)")
            diagnostics.record(.storageFailed(sqliteCode: Store.sqliteCode(of: error)))
            return
        }
        await refreshAccount()
        await purgeIfDue()
        if Self.hooks(environment).needsRepair() { try? Self.hooks(environment).repair() }
        // The status line's wrapper names the helper by its full path; after the app moves or is renamed (Pulse.app →
        // Clepso.app) it points at nothing and Claude Code quietly falls back. Re-point it, like the hooks above.
        let statusLine = Self.installer(environment, forwardCost: forwardCost)
        if statusLine.needsRepair() { try? statusLine.repair() }
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
    }

    public func stop() {
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
            let ingestor = Ingestor(connectionID: store.connectionID, sink: StoreSink(store: store) { [weak self] events in
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
        await refresh()
        await handleEngineEvents(codexEvents + tickEvents)
    }

    /// Retention (PRIVACY_AND_SECURITY §6): at launch, then at most once a day.
    func purgeIfDue() async {
        let now = environment.clock.now()
        if let lastPurge, now.timeIntervalSince(lastPurge) < 86_400 { return }
        lastPurge = now
        if let report = try? await store?.purge(now: now), !report.isEmpty {
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
        let snapshot = OverviewProjection.make(input, now: now, staleAfter: Freshness.localTelemetryTTL,
                                               zone: environment.timeZone, locale: environment.locale)
        guard mine == generation else { return }         // a newer refresh finished first
        self.snapshot = snapshot
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

    /// `settings.providers.forwardCost`. When installed, the helper's config is regenerated so the change applies.
    public func setForwardCost(_ on: Bool) async {
        forwardCost = on
        try? await store?.setPreference(Pref.forwardCost, on, now: environment.clock.now())
        let installer = Self.installer(environment, forwardCost: on)
        if installer.isInstalled { try? installer.repair() }
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
        let installer = Self.installer(environment, forwardCost: forwardCost)
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
            // The hooks call the helper through Pulse's folder, so they come out before it goes.
            if Self.hooks(environment).isInstalled { _ = try Self.hooks(environment).uninstall() }
            let outcome = try Self.installer(environment, forwardCost: forwardCost).uninstall()
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
        return PlayerCard.make(file: file, summary: summary, name: profileName ?? "", plan: plan?.displayName)
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

    /// "Email me a link": a one-time sign-in link to `email`, which opens Pulse on this Mac.
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

    /// The sign-in link's return to the app (`dev.tokone.pulse://auth-callback?code=…`).
    public func handleOpenURL(_ url: URL) async {
        guard url.scheme == SyncConfig.urlScheme else { return }
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
        await environment.sync.signOut()
        account = .signedOut
        accountMessage = nil
    }

    public func signOut() async {
        await environment.sync.signOut()
        account = .signedOut
        accountMessage = Copy.Sync.signedOut
        diagnostics.record(.account(event: "signed out"))
    }

    /// Deletes the account and everything stored with it on the server; nothing on this Mac changes.
    public func deleteAccount() async {
        accountBusy = true
        defer { accountBusy = false }
        do {
            try await environment.sync.deleteAccount()
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
        case .unsupportedExistingHooks: "its hooks section has a shape Pulse can't edit safely"
        case .settingsInvalidJSON: "settings.json isn't valid JSON"
        case .settingsChangedDuringInstall: "settings.json changed while Pulse was writing; try again"
        case .alreadyInstalled: "the hooks are already there"
        case .verificationFailed: "the result didn't check out, so it was put back"
        default: "\(error)"
        }
    }

    static func installer(_ environment: AppEnvironment, forwardCost: Bool) -> SettingsInstaller {
        SettingsInstaller(paths: .init(home: environment.home), shimPath: environment.shimPath,
                          socketPath: environment.socketPath, forwardCost: forwardCost, now: { [clock = environment.clock] in clock.now() })
    }

    /// `copy.explainer.installFailed` {{reason}}: plain words, never an enum name.
    static func reason(_ error: SettingsInstaller.InstallError) -> String {
        switch error {
        case .claudeNotDetected: "Claude Code's settings folder (~/.claude) wasn't found."
        case .settingsInvalidJSON: "Claude Code's settings file isn't valid JSON, so it was left alone."
        case .unsupportedExistingStatusLine: "Your current status line uses a form Pulse can't wrap safely."
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
        guard statsEnabled else { stats = nil; return }
        stats = StatsReader.read(home: environment.home)
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
                                                        appVersion: environment.appVersion)
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
        /// Files in the data folder Pulse did not create, left in place and named here (file names only).
        public var leftovers: [String] = []
        public var backupsRemoved = false
    }

    /// The items the confirmation dialog names (§8 step 1).
    public var deleteAllItems: [String] {
        let paths = SettingsInstaller.Paths(home: environment.home)
        return ["All stored readings, sessions, plan and preferences (\(environment.databaseURL.lastPathComponent))",
                "The diagnostics log",
                "Pending and delivered \(Product.name) notifications",
                "\(Product.name)'s status line and hooks in Claude Code: your settings are restored from the backup",
                "\(paths.pulseDir.path): the helper's settings and session key",
                "\(Product.name) Keychain items"]
    }

    /// "Delete all Pulse data…" after its confirmation, in the order of §8.
    /// `relaunch` false leaves the app stopped, so a test can inspect the empty folders.
    public func deleteAll(includeBackups: Bool, relaunch: Bool = true) async -> DeleteReport {
        var report = DeleteReport()
        let installer = Self.installer(environment, forwardCost: forwardCost)
        let paths = installer.paths
        let fm = FileManager.default

        // 2. Stop listening; nothing scheduled or shown survives.
        stop()
        await environment.notifications.removeAll()

        // 3. Restore Claude Code's settings first. If that cannot be done safely, stop here with everything intact:
        //    the backup and the sidecar are what make the restore possible.
        if case .needsUserDecision = installer.recover() {
            listen()
            return DeleteReport(failure: Copy.DeleteAll.restoreFailed(paths.backupsDir.path))
        }
        do {
            if Self.hooks(environment).isInstalled { _ = try Self.hooks(environment).uninstall() }
            _ = try installer.uninstall()
        } catch {
            listen()
            return DeleteReport(failure: Copy.DeleteAll.restoreFailed(paths.backupsDir.path))
        }
        if Self.isRealDirectory(paths.pulseDir) { try? fm.removeItem(at: paths.pulseDir) }

        // 4. Keychain (the account session too), and the login item if the user had turned it on.
        await environment.sync.signOut()
        account = .signedOut
        environment.keychain.deleteAll()
        if (try? await store?.preference(Pref.loginItem, as: Bool.self)) == true { try? environment.loginItem.setEnabled(false) }

        // 5. The database, the diagnostics file and the socket.
        try? await store?.close()
        store = nil
        ingestor = nil
        diagnostics.clear()
        let data = environment.dataDirectory
        let migrationBackups = ((try? fm.contentsOfDirectory(atPath: data.path)) ?? []).filter { $0.hasPrefix("pulse.sqlite.pre-") && $0.hasSuffix(".bak") }
        for name in ["pulse.sqlite", "pulse.sqlite-wal", "pulse.sqlite-shm", "pulse.sqlite-journal", "diagnostics.jsonl", "run/agent.sock"] + migrationBackups {
            try? fm.removeItem(at: data.appendingPathComponent(name))
        }
        for folder in [data.appendingPathComponent("run"), data] where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fm.removeItem(at: folder)
        }
        report.leftovers = ((try? fm.contentsOfDirectory(atPath: data.path)) ?? []).sorted()

        // 6. Settings backups only when the user ticked the box (default off).
        if includeBackups, Self.isRealDirectory(paths.backupsDir) {
            report.backupsRemoved = (try? fm.removeItem(at: paths.backupsDir)) != nil
        }

        // 7. First-run state.
        reset()
        refreshPreview()
        if relaunch { await start() }
        return report
    }

    /// Every in-memory value back to what a fresh install has.
    private func reset() {
        started = false
        problem = nil
        plan = nil
        loginItemEnabled = false
        onboardingComplete = false
        firstRealReadingAt = nil
        demo = false
        showPercent = true
        forwardCost = true
        statsEnabled = false
        stats = nil
        codexEnabled = false
        codexLatest = nil
        alertsEnabled = true
        alertsSnoozedUntil = nil
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
        static let demo = "demo.enabled"
        static let showPercent = "menubar.showPercent"
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
        static let theme = "general.theme"
    }
}

/// Ingest → store (ARCHITECTURE §4): one transaction per frame, then a snapshot refresh.
struct StoreSink: IngestSink {
    let store: Store
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
        guard (try? await store.record(.init(kind: kind, sessionRef: hook.sessionRef, agentRef: hook.agentRef, agentType: hook.agentType, at: at))) != nil
        else { return }
        await didIngest([])
    }
}
