import Foundation
import IntegrationSnapshot
import Testing
@testable import ClepsoApp

@MainActor @Suite("Integration sharing lifecycle", .serialized)
struct IntegrationSharingTests {
    @Test func nothingSharedBeforeConsentAndDemoNeverShared() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = box.model(clock: TestClock())
        await model.start(); defer { model.stop() }
        let file = SnapshotFile(dataDirectory: box.data)
        #expect((try? file.load()) == nil)
        await model.setMCPClient("test-client", allowed: true)
        #expect(file.allows("test-client"))
        #expect(try file.load().limits.isEmpty)
        await model.setDemo(true)
        #expect((try? file.load()) == nil)
        await model.setMCPClient("test-client", allowed: false)
        #expect(!file.allows("test-client"))
    }
    @Test func sharedReadingsUseProjectionAndConsentPersists() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), model = box.model(clock: clock)
        await model.start()
        await model.setMCPClient("test-client", allowed: true)
        #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: 83)))
        #expect(await eventually { model.snapshot.provider?.pools.count == 2 })
        let snapshot = try SnapshotFile(dataDirectory: box.data).load()
        #expect(snapshot.limits.first { $0.window == .fiveHour }?.usedPercent == 83)
        #expect(snapshot.limits.allSatisfy { $0.provider == .claudeCode && $0.source == .automatic })
        let text = String(decoding: try UsageSnapshot.encoder().encode(snapshot), as: UTF8.self)
        #expect(!text.contains("Opus"))
        #expect(!text.contains("session"))
        model.stop()
        let second = box.model(clock: clock); await second.start(); defer { second.stop() }
        #expect(second.mcpClients == ["test-client"])
        await second.setMCPClient("test-client", allowed: false)
        #expect((try? SnapshotFile(dataDirectory: box.data).load()) == nil)
    }
    @Test func widgetSharingIsIndependentAndClearedOnDeletion() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let container = box.root.appendingPathComponent("widget")
        let clock = TestClock()
        var environment = box.model(clock: clock).environment
        environment.widgetContainer = { container }
        let model = AppModel(environment: environment)
        await model.start(); defer { model.stop() }
        let shared = SnapshotFile(dataDirectory: container)
        #expect(!model.widgetsEnabled && model.mcpClients.isEmpty)
        #expect((try? shared.load()) == nil)
        await model.setWidgetsEnabled(true)
        #expect(model.widgetsEnabled)
        #expect(try shared.load().limits.isEmpty)
        await model.setMCPClient("test", allowed: true)
        await model.setWidgetsEnabled(false)
        #expect((try? shared.load()) == nil)
        #expect(SnapshotFile(dataDirectory: box.data).allows("test"))
        await model.setWidgetsEnabled(true)
        let report = await model.deleteAll(includeBackups: false, relaunch: false)
        #expect(report.failure == nil)
        #expect((try? shared.load()) == nil)
        #expect(!SnapshotFile(dataDirectory: box.data).allows("test"))
        #expect(model.mcpClients.isEmpty && !model.widgetsEnabled)
    }
    @Test func widgetUnavailableDoesNotPersistFalseSuccess() async {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = box.model(clock: TestClock()); await model.start(); defer { model.stop() }
        await model.setWidgetsEnabled(true)
        #expect(!model.widgetsEnabled)
        #expect(model.integrationMessage != nil)
    }
    @Test func interruptedWidgetOptOutIsClearedOnRestart() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let container = box.root.appendingPathComponent("widget")
        let clock = TestClock()
        var environment = box.model(clock: clock).environment
        environment.widgetContainer = { container }
        let first = AppModel(environment: environment)
        await first.start()
        await first.setWidgetsEnabled(true)
        let shared = SnapshotFile(dataDirectory: container)
        #expect((try? shared.load()) != nil)
        // Crash boundary: the off choice reached SQLite, but the old shared snapshot still exists.
        try await first.store?.setPreference(AppModel.Pref.widgets, false, now: clock.now())
        first.stop()
        let second = AppModel(environment: environment); await second.start(); defer { second.stop() }
        #expect(!second.widgetsEnabled)
        #expect((try? shared.load()) == nil)
    }
    @Test func concurrentRefreshCannotUndoWidgetOptOut() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let container = box.root.appendingPathComponent("widget")
        var environment = box.model(clock: TestClock()).environment
        environment.widgetContainer = { container }
        let model = AppModel(environment: environment); await model.start(); defer { model.stop() }
        for _ in 0..<20 {
            await model.setWidgetsEnabled(true)
            async let disabled = model.setWidgetsEnabled(false)
            async let refreshed: Void = model.refresh()
            let (off, _) = await (disabled, refreshed)
            #expect(off && !model.widgetsEnabled)
            #expect((try? SnapshotFile(dataDirectory: container).load()) == nil)
        }
    }
    @Test func updateSettingsUseInjectedControllerOnly() async {
        let box = Sandbox(); defer { box.cleanUp() }
        let updater = UnavailableUpdater()
        var environment = box.model(clock: TestClock()).environment
        environment.updater = updater
        let model = AppModel(environment: environment); await model.start(); defer { model.stop() }
        #expect(!model.updatesAvailable && !model.updateChecksEnabled)
        model.setUpdateChecks(true); model.setUpdateDownloads(true)
        #expect(updater.automaticChecks && updater.automaticDownloads)
        model.setUpdateChecks(false)
        #expect(!updater.automaticChecks && !updater.automaticDownloads)
        model.checkForUpdates()
        await model.handleOpenURL(URL(string: "clepso://dashboard")!)
        #expect(model.detailsSection == .limits)
        #expect(model.accountMessage == nil)
    }
}
