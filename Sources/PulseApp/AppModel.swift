import ClaudeCodeAdapter
import DesignSystem
import enum Domain.EvidenceKind
import enum Domain.Freshness
import enum Domain.Product
import struct Domain.Redacted
import Foundation
import Observation
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

    public private(set) var snapshot: OverviewSnapshot
    public private(set) var problem: Problem?
    public private(set) var plan: Store.PlanIdentity?
    public private(set) var preview: SettingsInstaller.Preview
    public private(set) var notificationStatus: NotificationAuthorization = .notDetermined
    /// On only when the user chose it here and the system confirms it. `SMAppService.mainApp.status` was seen
    /// reporting `.enabled` for a development build that never registered, so the system's word alone is not enough.
    public private(set) var loginItemEnabled = false
    public private(set) var onboardingComplete = false
    public private(set) var firstRealReadingAt: Date?
    public private(set) var demo = false
    public private(set) var showPercent = true
    public private(set) var forwardCost = true          // founder decision A5: on by default
    public private(set) var started = false
    public var settingsTab: SettingsTab = .general
    /// Navigation lives here so "Connect…" and similar can deep-link, and Escape always has one place to go back to.
    public var popoverRoute: PopoverRoute = .overview
    public var onboardingStep: OnboardingStep = .welcome
    /// The delete-all confirmation sheet; on the model so the verification probe can show it.
    public var confirmingDeleteAll = false
    public let catalog: PlanCatalog?
    /// The Diagnostics drawer's events (PRIVACY_AND_SECURITY §5).
    public let diagnostics: DiagnosticsLog
    /// Live counts from the listener for the Diagnostics tab.
    public private(set) var socketHealth = IngestSocket.Health()

    public let environment: AppEnvironment
    private var store: Store?
    private var socket: IngestSocket?
    private var ingestor: Ingestor?
    private var loggedHealth = IngestSocket.Health()
    private var loggedCounters = Ingestor.Counters()
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
            let chose = try await store.preference(Pref.loginItem, as: Bool.self) ?? false
            loginItemEnabled = chose && environment.loginItem.isEnabled
            plan = try await store.currentPlan()
        } catch {
            problem = .storage("\(error)")
            diagnostics.record(.storageFailed(sqliteCode: Store.sqliteCode(of: error)))
            return
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
            let ingestor = Ingestor(connectionID: store.connectionID, sink: StoreSink(store: store) { [weak self] in
                await self?.didIngest()
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
        _ = try? await store?.tick(now: environment.clock.now())
        await recordIngestHealth()
        await refresh()
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

    /// A real observation arrived: it ends demo mode (UX_SPEC §2.8) and is the first-reading moment of onboarding.
    private func didIngest() async {
        let now = environment.clock.now()
        if firstRealReadingAt == nil {
            firstRealReadingAt = now
            try? await store?.setPreference(Pref.firstReading, now, now: now)
        }
        if demo { await setDemo(false) } else { await refresh() }
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
                input = try await Self.read(store)
                input.installed = Self.installer(environment, forwardCost: forwardCost).isInstalled
                input.unreadLimitWindows = await ingestor?.counters.unknownRateLimitWindows ?? 0
            }
        } catch {
            problem = .storage("\(error)")
            return
        }
        input.showPercent = showPercent
        let snapshot = OverviewProjection.make(input, now: now, staleAfter: Freshness.localTelemetryTTL,
                                               zone: environment.timeZone, locale: environment.locale)
        guard mine == generation else { return }         // a newer refresh finished first
        self.snapshot = snapshot
        if case .storage = problem { problem = nil }
    }

    /// One read of everything the screens need, so opening the popover never touches storage.
    static func read(_ store: Store) async throws -> OverviewInput {
        var input = OverviewInput()
        input.pools = try await store.poolStates()
        input.sessions = try await store.sessionStates()
        input.sessionSummaries = try await store.sessionSummaries(limit: 20)
        for pool in input.pools {
            input.recent[pool.poolKey] = try await store.recentReadings(poolKey: pool.poolKey, kind: .quotaUsedPct, limit: 3)
        }
        input.plan = try await store.currentPlan()
        input.sourceVersion = try await store.latestSourceVersion()
        input.lastEventAt = try await store.lastEventAt()
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

    // MARK: - Plan (PLAN_CATALOG §4: chosen by the user, never inferred)

    /// nil entry is "Not sure": the current plan ends and the header reads `Plan not set`.
    public func choosePlan(_ entry: PlanCatalog.Entry?, confirmed: Bool) async {
        guard let store else { return }
        try? await store.setPlan(catalogID: entry?.id, displayName: entry?.displayName,
                                 evidence: confirmed ? .userConfirmed : .userSelectedUnverified, now: environment.clock.now())
        plan = try? await store.currentPlan()
        diagnostics.record(.planChanged(catalogID: entry?.id, confirmed: confirmed && entry != nil))
        await refresh()
    }

    // MARK: - Claude Code connection (UX_SPEC §2.2, §4 step 4)

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

    // MARK: - Login item and notifications (consent first; COMPLIANCE_GATES §4)

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
                "\(Product.name)'s status line in Claude Code: your settings are restored from the backup",
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
            _ = try installer.uninstall()
        } catch {
            listen()
            return DeleteReport(failure: Copy.DeleteAll.restoreFailed(paths.backupsDir.path))
        }
        if Self.isRealDirectory(paths.pulseDir) { try? fm.removeItem(at: paths.pulseDir) }

        // 4. Keychain, and the login item if the user had turned it on.
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
    }
}

/// Ingest → store (ARCHITECTURE §4): one transaction per frame, then a snapshot refresh.
struct StoreSink: IngestSink {
    let store: Store
    let didIngest: @Sendable () async -> Void

    func ingest(_ batch: IngestBatch) async {
        let meta = batch.sessionRef.map { Store.SessionMeta(sessionRef: $0, modelID: batch.modelID, modelDisplayName: batch.modelDisplayName) }
        guard let result = try? await store.ingest(batch.observations, session: meta), result.inserted > 0 else { return }
        await didIngest()
    }
}
