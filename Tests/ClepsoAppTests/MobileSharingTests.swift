import Foundation
import Testing
@testable import ClepsoApp
@testable import Sync

private actor MobileServer: HTTPTransport {
    var paths: [String] = []
    var active = false
    var lease = UUID()
    var publishes = 0
    var blockPublish = false
    var failRevoke = false
    var continuation: CheckedContinuation<Void, Never>?
    func suspendPublication() { blockPublish = true }
    func failRevocation(_ fail: Bool) { failRevoke = fail }
    func releasePublication() { continuation?.resume(); continuation = nil; blockPublish = false }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        paths.append(path)
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        var status = 200, response = ""
        if path.hasSuffix("rpc/set_mobile_relay") {
            let enabled = body["p_enabled"] as? Bool == true
            if !enabled, failRevoke { throw URLError(.notConnectedToInternet) }
            active = enabled; lease = UUID(); response = "\"\(lease.uuidString)\""
        } else if path.hasSuffix("rpc/publish_mobile_relay") {
            publishes += 1
            if blockPublish { await withCheckedContinuation { continuation = $0 } }
            if !active || body["p_generation"] as? String != lease.uuidString { status = 403; response = "{\"code\":\"42501\"}" }
        }
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor @Suite("Mac mobile-sharing consent lifecycle", .serialized) struct MobileSharingTests {
    private func model(_ box: Sandbox, _ clock: TestClock, _ server: MobileServer) -> AppModel {
        let auth = MemoryAuthStore()
        auth.save(StoredAuth(session: AuthSession(accessToken: "synthetic", refreshToken: "synthetic", expiresAt: clock.now().addingTimeInterval(3600), userID: "synthetic-owner", email: nil)))
        var environment = box.model(clock: clock).environment
        environment.sync = SyncClient(config: testSyncConfig, transport: server, store: auth, now: { clock.now() })
        return AppModel(environment: environment)
    }
    private func publicationStarted(_ server: MobileServer) async -> Bool {
        for _ in 0..<200 {
            if await server.publishes > 0 { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
    @Test func dailyUploadsDoNotAuthorizeRelayAndDemoCannotEnableIt() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let server = MobileServer(), model = model(box,TestClock(),server)
        await model.start(); defer { model.stop() }
        await model.refresh()
        #expect(!model.mobileSharingEnabled)
        #expect(await server.paths.allSatisfy { !$0.contains("mobile_relay") })
        await model.setDemo(true)
        #expect(!(await model.setMobileSharing(true)))
        #expect(await server.paths.allSatisfy { !$0.contains("mobile_relay") })
    }
    @Test func optOutFencesSuspendedPublicationAndPersistsAcrossRestart() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let server = MobileServer(), clock = TestClock(), model = model(box,clock,server)
        await model.start()
        await server.suspendPublication()
        #expect(await model.setMobileSharing(true))
        #expect(await publicationStarted(server))
        #expect(await model.setMobileSharing(false))
        let offMessage = model.mobileSharingMessage
        await server.releasePublication()
        await model.mobilePublishTask?.value
        #expect(!model.mobileSharingEnabled && model.mobileSharingMessage == offMessage)
        #expect(!(await server.active))
        model.stop()
        let next = AppModel(environment: model.environment)
        await next.start(); defer { next.stop() }
        #expect(!next.mobileSharingEnabled)
        #expect(await server.publishes == 1)
    }
    @Test func offlineOffPersistsAndRetriesRevocationOnRestart() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let server = MobileServer(), model = model(box,TestClock(),server)
        await model.start()
        #expect(await model.setMobileSharing(true))
        await model.mobilePublishTask?.value
        await server.failRevocation(true)
        #expect(await model.setMobileSharing(false))
        #expect(!model.mobileSharingEnabled && model.mobileSharing.pendingRevocation)
        model.stop()
        await server.failRevocation(false)
        let next = AppModel(environment: model.environment)
        await next.start(); defer { next.stop() }
        #expect(!next.mobileSharingEnabled && !next.mobileSharing.pendingRevocation)
        #expect(!(await server.active))
    }
}
