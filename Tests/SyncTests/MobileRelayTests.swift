import Foundation
import IntegrationSnapshot
import Testing
@testable import Sync

@Suite("Mobile relay transport contract") struct MobileRelayTests {
    func client(_ transport: StubTransport) -> SyncClient {
        let store = MemoryAuthStore()
        store.save(StoredAuth(session: AuthSession(accessToken: "synthetic-access", refreshToken: "synthetic-refresh",
            expiresAt: t0.addingTimeInterval(3600), userID: "synthetic-owner", email: nil)))
        return SyncClient(config: config, transport: transport, store: store, now: { t0 })
    }
    @Test func consentPublishAndRevokeUseFencedRPCs() async throws {
        let transport = StubTransport(), lease = UUID(), client = client(transport)
        transport.respond(200,"\"\(lease.uuidString)\"")
        #expect(try await client.setMobileRelayEnabled(true) == lease)
        try await client.publishMobileRelay(UsageSnapshot(generatedAt: t0, limits: []), generation: lease)
        transport.respond(200,"\"\(UUID().uuidString)\"")
        try await client.revokeMobileRelay()
        let requests = transport.all
        #expect(requests.map { $0.url!.path } == ["/rest/v1/rpc/set_mobile_relay","/rest/v1/rpc/publish_mobile_relay","/rest/v1/rpc/set_mobile_relay"])
        #expect(body(requests[0])["p_enabled"] as? Bool == true)
        #expect(body(requests[1])["p_generation"] as? String == lease.uuidString)
        #expect(body(requests[1])["user_id"] == nil)
        #expect(body(requests[2])["p_enabled"] as? Bool == false)
        #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access" })
    }
    @Test func readIsOwnerScopedAndRejectsInvalidEnvelope() async throws {
        let transport = StubTransport(), client = client(transport)
        transport.respond(200,"[]")
        #expect(try await client.mobileRelay() == nil)
        let request = try #require(transport.all.last)
        #expect(request.httpMethod == nil || request.httpMethod == "GET")
        #expect(query(request,"user_id") == "eq.synthetic-owner")
        #expect(query(request,"select") == "snapshot,received_at,expires_at")
        transport.respond(200,"[{}]")
        do { _ = try await client.mobileRelay(); Issue.record("Invalid envelope accepted") } catch {}
        let count = transport.all.count
        await #expect(throws: SyncError.badResponse) {
            try await client.publishMobileRelay(UsageSnapshot(generatedAt: t0, demo: true, limits: []), generation: UUID())
        }
        #expect(transport.all.count == count)
    }
    @Test func pushConsentAndSignalHaveNoCallerChosenOwnerOrDestination() async throws {
        let transport = StubTransport(), client = client(transport), device = UUID(), lease = UUID()
        transport.respond(200,"\"\(lease.uuidString)\"")
        #expect(try await client.setMobileDevice(device, enabled: true) == lease)
        transport.respond(204, "")
        try await client.registerMobileDevice(device, generation: lease, token: String(repeating: "ab", count: 32), environment: .development)
        transport.respond(200, "{\"configured\":true}")
        try await client.checkMobilePush(.production)
        transport.respond(202, "{\"accepted\":1}")
        try await client.signalMobileRefresh()
        let requests = transport.all
        #expect(requests.map { $0.url!.path } == ["/rest/v1/rpc/set_mobile_device", "/rest/v1/rpc/register_mobile_device", "/functions/v1/mobile-signal", "/functions/v1/mobile-signal"])
        #expect(body(requests[0])["p_device"] as? String == device.uuidString)
        #expect(body(requests[1])["p_generation"] as? String == lease.uuidString)
        #expect(body(requests[1])["p_environment"] as? String == "development")
        #expect(Set(body(requests[2]).keys) == ["check", "environment"])
        #expect(body(requests[2])["environment"] as? String == "production")
        #expect(body(requests[3]).isEmpty)
        #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access" })
    }
    @Test func invalidPushTokenNeverLeavesClientAndReadinessMustBeExplicit() async throws {
        let transport = StubTransport(), client = client(transport)
        for token in ["", "abc", "AB", "https://example.test", String(repeating: "a", count: 1026)] {
            await #expect(throws: SyncError.badResponse) {
                try await client.registerMobileDevice(UUID(), generation: UUID(), token: token, environment: .production)
            }
        }
        #expect(transport.all.isEmpty)
        transport.respond(200, "{\"configured\":false}")
        await #expect(throws: SyncError.badResponse) { try await client.checkMobilePush(.development) }
    }
}
