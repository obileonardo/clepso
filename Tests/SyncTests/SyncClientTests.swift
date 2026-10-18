import Foundation
import Testing
@testable import Sync

/// A server stand-in: records each request and answers from a queue (default: 200 with an empty body).
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, String)] = []
    private(set) var requests: [URLRequest] = []
    func respond(_ status: Int, _ body: String) { lock.withLock { queue.append((status, body)) } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in
            requests.append(request)
            return queue.isEmpty ? (200, "") : queue.removeFirst()
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    var all: [URLRequest] { lock.withLock { requests } }
}

let config = SyncConfig(projectURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test",
                        redirectURL: URL(string: "clepso://auth-callback")!)
let t0 = Date(timeIntervalSince1970: 1_792_159_200)
func sessionJSON(_ access: String = "access-1", refresh: String = "refresh-1", expiresIn: Int = 3600) -> String {
    #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":\#(expiresIn),"user":{"id":"u-1","email":"e@example.test"}}"#
}
func body(_ r: URLRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any] ?? [:] }
func query(_ r: URLRequest, _ name: String) -> String? { URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value }

@Suite("Accounts configuration")
struct SyncConfigTests {
    @Test("Read from Info.plist values: host and publishable key; https and the app's redirect")
    func fromInfoPlist() throws {
        let c = try #require(SyncConfig(infoDictionary: ["PulseSyncHost": "abcd.supabase.co", "PulseSyncPublishableKey": "sb_publishable_x"]))
        #expect(c.projectURL.absoluteString == "https://abcd.supabase.co")
        #expect(c.publishableKey == "sb_publishable_x" && c.redirectURL.absoluteString == "clepso://auth-callback")
    }

    @Test("Missing, empty, unexpanded or malformed values mean no configuration (Sync off)",
          arguments: [
            [:],
            ["PulseSyncHost": "abcd.supabase.co"],
            ["PulseSyncPublishableKey": "sb_publishable_x"],
            ["PulseSyncHost": "", "PulseSyncPublishableKey": ""],
            ["PulseSyncHost": "$(PULSE_SYNC_HOST)", "PulseSyncPublishableKey": "$(PULSE_SYNC_PUBLISHABLE_KEY)"],
            ["PulseSyncHost": "https://abcd.supabase.co", "PulseSyncPublishableKey": "sb_publishable_x"],
            ["PulseSyncHost": "abcd.supabase.co/path", "PulseSyncPublishableKey": "sb_publishable_x"],
            ["PulseSyncHost": "localhost", "PulseSyncPublishableKey": "sb_publishable_x"],
            ["PulseSyncHost": "abcd.supabase.co", "PulseSyncPublishableKey": "sb_secret_x"],
            ["PulseSyncHost": "abcd.supabase.co", "PulseSyncPublishableKey": "two words"],
          ] as [[String: String]])
    func refused(_ values: [String: String]) {
        #expect(SyncConfig(infoDictionary: values) == nil)
    }

    @Test("No configuration: every call fails as unavailable before a request; no session is reported; sign-out stays local")
    func unconfiguredSendsNothing() async throws {
        let transport = StubTransport(), store = MemoryAuthStore()
        store.save(StoredAuth(session: AuthSession(accessToken: "a", refreshToken: "r", expiresAt: t0.addingTimeInterval(3600),
                                                   userID: "u-1", email: "e@example.test"), pendingVerifier: "v", pendingEmail: "e@example.test"))
        let client = SyncClient(config: nil, transport: transport, store: store, now: { t0 })
        #expect(!client.isAvailable)
        let session = await client.session, pending = await client.pendingEmail
        #expect(session == nil && pending == nil)
        await #expect(throws: SyncError.unavailable) { try await client.requestEmailLink("e@example.test") }
        await #expect(throws: SyncError.unavailable) { try await client.handleCallback(URL(string: "clepso://auth-callback?code=abc")!) }
        await #expect(throws: SyncError.unavailable) { try await client.validSession() }
        await #expect(throws: SyncError.unavailable) { try await client.upload(SyncPayload()) }
        await #expect(throws: SyncError.unavailable) { try await client.deleteAccount() }
        let providerURL = await client.providerURL(.github)
        #expect(providerURL == nil)
        await client.signOut()
        #expect(transport.all.isEmpty, "not one request without a configuration")
        #expect(store.load() == StoredAuth(), "signing out still clears this Mac")
    }
}

@Suite("Accounts client")
struct SyncClientTests {
    @Test("PKCE matches the RFC 7636 example, and fresh verifiers are long and URL-safe")
    func pkce() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let v = PKCE.make().verifier
        #expect(v.count >= 43 && v.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(PKCE.make() != PKCE.make())
    }

    @Test("Email link: one POST to Auth with the redirect and a PKCE challenge; the verifier stays on this Mac")
    func emailLink() async throws {
        let transport = StubTransport(), store = MemoryAuthStore()
        let client = SyncClient(config: config, transport: transport, store: store, now: { t0 })
        try await client.requestEmailLink("e@example.test")
        let request = try #require(transport.all.first)
        #expect(request.httpMethod == "POST" && request.url?.path == "/auth/v1/otp")
        #expect(query(request, "redirect_to") == "clepso://auth-callback")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        let sent = body(request)
        let verifier = try #require(store.load().pendingVerifier)
        #expect(sent["email"] as? String == "e@example.test" && sent["code_challenge"] as? String == PKCE.challenge(for: verifier))
        #expect(!(String(decoding: request.httpBody ?? Data(), as: UTF8.self)).contains(verifier), "the verifier never leaves before the exchange")
    }

    @Test("Callback: wrong links and provider errors are refused; a code is exchanged with the stored verifier")
    func callback() async throws {
        let transport = StubTransport(), store = MemoryAuthStore()
        let client = SyncClient(config: config, transport: transport, store: store, now: { t0 })
        await #expect(throws: SyncError.invalidCallback("not a sign-in link")) { try await client.handleCallback(URL(string: "https://evil.test/?code=x")!) }
        await #expect(throws: SyncError.noPendingSignIn) { try await client.handleCallback(URL(string: "clepso://auth-callback?code=abc")!) }
        try await client.requestEmailLink("e@example.test")
        await #expect(throws: SyncError.invalidCallback("Email link is invalid or has expired")) {
            try await client.handleCallback(URL(string: "clepso://auth-callback#error=access_denied&error_description=Email+link+is+invalid+or+has+expired")!)
        }
        let verifier = try #require(store.load().pendingVerifier)
        transport.respond(200, sessionJSON())
        let session = try await client.handleCallback(URL(string: "clepso://auth-callback?code=abc")!)
        let exchange = try #require(transport.all.last)
        #expect(exchange.url?.path == "/auth/v1/token" && query(exchange, "grant_type") == "pkce")
        #expect(body(exchange)["auth_code"] as? String == "abc" && body(exchange)["code_verifier"] as? String == verifier)
        #expect(session.userID == "u-1" && session.email == "e@example.test" && session.expiresAt == t0 + 3600)
        #expect(store.load() == StoredAuth(session: session), "pending sign-in cleared")
    }

    @Test("A session near expiry is refreshed; a refused refresh signs out")
    func refresh() async throws {
        let transport = StubTransport(), store = MemoryAuthStore()
        store.save(StoredAuth(session: AuthSession(accessToken: "old", refreshToken: "r-old", expiresAt: t0 + 30, userID: "u-1", email: nil)))
        let client = SyncClient(config: config, transport: transport, store: store, now: { t0 })
        transport.respond(200, sessionJSON("access-2", refresh: "r-2"))
        #expect(try await client.validSession().accessToken == "access-2")
        #expect(body(try #require(transport.all.last))["refresh_token"] as? String == "r-old")
        store.save(StoredAuth(session: AuthSession(accessToken: "x", refreshToken: "revoked", expiresAt: t0, userID: "u-1", email: nil)))
        transport.respond(400, #"{"error_code":"refresh_token_not_found"}"#)
        await #expect(throws: SyncError.notSignedIn) { try await client.validSession() }
        #expect(store.load() == StoredAuth())
    }

    @Test("Upload: the user's token, one upsert per table with its conflict key, snake_case fields, never a user id")
    func upload() async throws {
        let transport = StubTransport(), store = MemoryAuthStore()
        store.save(StoredAuth(session: AuthSession(accessToken: "tok", refreshToken: "r", expiresAt: t0 + 3600, userID: "u-1", email: nil)))
        let client = SyncClient(config: config, transport: transport, store: store, now: { t0 })
        var payload = SyncPayload()
        payload.profile = .init(displayName: "Elvis", planLabel: "Max 5×")
        payload.activity = [.init(day: "2026-10-16", messages: 120, sessions: 3, active: true)]
        payload.modelTotals = [.init(model: "claude-opus-5-5", input: 1, output: 18_200_000, cacheRead: 3, cacheWrite: 4)]
        payload.goals = [.init(kind: "fiveHourPeak", target: 80), .init(kind: "weeklyFinish", target: nil)]
        try await client.upload(payload)
        let requests = transport.all
        #expect(requests.map { $0.url!.path } == ["/rest/v1/profiles", "/rest/v1/daily_activity", "/rest/v1/model_totals", "/rest/v1/goals"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok" })
        #expect(requests[0].httpMethod == "PATCH" && query(requests[0], "user_id") == "eq.u-1")
        #expect(query(requests[1], "on_conflict") == "user_id,day" && query(requests[3], "on_conflict") == "user_id,kind")
        #expect(requests[1].value(forHTTPHeaderField: "Prefer")?.contains("resolution=merge-duplicates") == true)
        let totals = String(decoding: requests[2].httpBody ?? Data(), as: UTF8.self)
        #expect(totals.contains("\"cache_read\":3") && !totals.contains("user_id"))
        #expect(String(decoding: requests[3].httpBody ?? Data(), as: UTF8.self).contains("\"target\":null"), "a goal turned off is sent as null")
    }

    @Test("Errors carry the status and Supabase's code, never a body or a token; delete-account signs out")
    func errorsAndDelete() async throws {
        let transport = StubTransport(), store = MemoryAuthStore()
        store.save(StoredAuth(session: AuthSession(accessToken: "tok-secret", refreshToken: "r", expiresAt: t0 + 3600, userID: "u-1", email: nil)))
        let client = SyncClient(config: config, transport: transport, store: store, now: { t0 })
        transport.respond(403, #"{"code":"42501","message":"tok-secret leaked?"}"#)
        await #expect(throws: SyncError.http(status: 403, code: "42501")) { try await client.upload({ var p = SyncPayload(); p.activity = [.init(day: "2026-10-16", messages: 1, sessions: 1, active: true)]; return p }()) }
        try await client.deleteAccount()
        #expect(transport.all.last?.url?.path == "/rest/v1/rpc/delete_account")
        #expect(store.load() == StoredAuth())
        await #expect(throws: SyncError.notSignedIn) { try await client.upload(SyncPayload()) }
    }
}
