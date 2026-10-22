import Domain
import Foundation
import IntegrationSnapshot

extension AppModel {
    public var updatesAvailable: Bool { environment.updater?.available ?? false }
    public func setUpdateChecks(_ enabled: Bool) {
        if !enabled {
            environment.updater?.automaticDownloads = false
            updateDownloadsEnabled = false
        }
        environment.updater?.automaticChecks = enabled
        updateChecksEnabled = environment.updater?.automaticChecks ?? false
    }
    public func setUpdateDownloads(_ enabled: Bool) {
        environment.updater?.automaticDownloads = enabled
        updateDownloadsEnabled = environment.updater?.automaticDownloads ?? false
    }
    public func checkForUpdates() { environment.updater?.check() }

    public func setMCPClient(_ name: String, allowed: Bool) async {
        guard SnapshotFile.validClient(name) else { integrationMessage = "Use 1–48 lowercase letters, numbers or hyphens."; return }
        var names = Set(mcpClients)
        if allowed { names.insert(name) } else { names.remove(name) }
        guard names.count <= 16 else { integrationMessage = "Remove a client before adding another."; return }
        do {
            // Revoke on disk first, so an already-running client loses access immediately.
            try SnapshotFile(dataDirectory: environment.dataDirectory).setClients(Array(names))
            mcpClients = Array(names).sorted(); integrationMessage = nil
            publishIntegrations()
        } catch { integrationMessage = "Could not save integration permission. Try again." }
    }

    func publishIntegrations() {
        publishWidget()
        let file = SnapshotFile(dataDirectory: environment.dataDirectory)
        do {
            try file.setClients(mcpClients)
            if mcpClients.isEmpty || demo { try? file.removeSnapshot(); return }
            try file.publish(integrationSnapshot())
        } catch { integrationMessage = "The integration snapshot could not be written. Clients cannot read current usage." }
    }

    @discardableResult public func setWidgetsEnabled(_ enabled: Bool) async -> Bool {
        guard !widgetSharingBusy else { return false }
        guard let store else { integrationMessage = "Clepso is still opening its data. Try again shortly."; return false }
        if enabled, environment.widgetContainer() == nil {
            integrationMessage = "Widget sharing is unavailable in this app signature. Install the signed Clepso release."; return false
        }
        widgetSharingBusy = true
        defer { widgetSharingBusy = false }
        do {
            // Persist first, block publishers across the await, then clear. A crash between the two operations
            // is reconciled on launch from the explicit false preference.
            try await store.setPreference(Pref.widgets, enabled, now: environment.clock.now())
            if !enabled, let container = environment.widgetContainer() { try SnapshotFile(dataDirectory: container).removeSnapshot() }
            widgetsEnabled = enabled
            lastWidgetSnapshot = nil
            widgetSharingBusy = false
            integrationMessage = nil
            if enabled { publishWidget() }
            environment.reloadWidgets()
            return true
        } catch { integrationMessage = "Could not finish changing widget sharing. The previous snapshot may remain; try again."; return false }
    }

    private func publishWidget() {
        guard widgetsEnabled, !widgetSharingBusy, let container = environment.widgetContainer() else { return }
        do {
            let file = SnapshotFile(dataDirectory: container)
            let value = integrationSnapshot()
            if let last = lastWidgetSnapshot, last.limits == value.limits, last.demo == value.demo,
               value.generatedAt.timeIntervalSince(last.generatedAt) < 300 { return }
            if demo { try file.removeSnapshot() } else { try file.publish(value) }
            lastWidgetSnapshot = value
            environment.reloadWidgets()
        } catch { integrationMessage = "The widget snapshot could not be written. The widget will show its last reading as old." }
    }

    func integrationSnapshot() -> UsageSnapshot {
        func rows(_ rows: [PoolRow], provider: UsageSnapshot.Provider) -> [UsageSnapshot.Limit] {
            rows.compactMap { row in
                let window: UsageSnapshot.Window
                if row.poolKey.hasSuffix("five_hour") { window = .fiveHour }
                else if row.poolKey.hasSuffix("seven_day") { window = .weekly }
                else { return nil }
                let model = row.model
                let state: UsageSnapshot.State
                switch model.valueState(now: snapshot.now, staleAfter: Freshness.localTelemetryTTL) {
                case .notConnected: state = .disconnected
                case .providerError: state = .invalid
                default: state = model.card == .resetExpected ? .resetExpected : model.used.value == nil ? .missing : .reported
                }
                return .init(provider: provider, window: window, source: .automatic,
                             usedPercent: model.used.value.map { NSDecimalNumber(decimal: $0).doubleValue },
                             observedAt: model.used.observedAt, resetsAt: model.resetsAt.value, state: state)
            }
        }
        var limits = rows(snapshot.provider?.pools ?? [], provider: .claudeCode) + rows(snapshot.codex?.pools ?? [], provider: .codex)
        for manual in manualAllowances {
            guard let provider = UsageSnapshot.Provider(rawValue: manual.providerID),
                  let window = UsageSnapshot.Window(rawValue: manual.window.rawValue) else { continue }
            limits.append(.init(provider: provider, window: window, source: .manual,
                                usedPercent: manual.usedPercent.map { NSDecimalNumber(decimal: $0).doubleValue },
                                observedAt: manual.observedAt, resetsAt: manual.resetsAt,
                                state: manual.resetPassed(at: snapshot.now) ? .resetExpected : .reported))
        }
        return UsageSnapshot(generatedAt: snapshot.now, demo: snapshot.isDemo, limits: Array(limits.prefix(64)))
    }

    func mcpConfiguration(client: String) -> String {
        let command = URL(fileURLWithPath: environment.shimPath).deletingLastPathComponent().appendingPathComponent("clepso").path
        let object = ["mcpServers": ["clepso": ["command": command, "args": ["mcp", "--client", client]]]] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
