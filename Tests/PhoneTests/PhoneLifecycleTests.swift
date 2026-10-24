import Foundation
import IntegrationSnapshot
import Sync
import Testing
@testable import ClepsoPhone

private final class Auth: AuthStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredAuth
    init(_ owner: String) throws {
        let json = #"{"accessToken":"synthetic","refreshToken":"synthetic","expiresAt":2000000000,"userID":"OWNER"}"#.replacingOccurrences(of:"OWNER",with:owner)
        value = StoredAuth(session: try JSONDecoder().decode(AuthSession.self,from:Data(json.utf8)))
    }
    func load() -> StoredAuth { lock.withLock { value } }
    func save(_ auth: StoredAuth) { lock.withLock { value = auth } }
}
private actor Server: HTTPTransport {
    var paths: [String] = []
    var offline = false
    var stallReading = false
    var stallOff = false
    var stallRegistration = false
    var readStarted = false
    var offStarted = false
    var registrationStarted = false
    var active = false
    var lease = UUID()
    var token: String?
    var readGate: CheckedContinuation<Void,Never>?
    var offGate: CheckedContinuation<Void,Never>?
    var registrationGate: CheckedContinuation<Void,Never>?
    let envelope: RelayEnvelope
    init(_ envelope: RelayEnvelope) { self.envelope = envelope }
    func configure(read: Bool = false, off: Bool = false, registration: Bool = false, offline: Bool = false) {
        stallReading = read; stallOff = off; stallRegistration = registration; self.offline = offline
    }
    func releaseRead() { readGate?.resume();readGate=nil;stallReading=false }
    func releaseOff() { offGate?.resume();offGate=nil;stallOff=false }
    func releaseRegistration() { registrationGate?.resume();registrationGate=nil;stallRegistration=false }
    func send(_ request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        let path = request.url!.path
        paths.append(path)
        let body = (try? JSONSerialization.jsonObject(with:request.httpBody ?? Data())) as? [String:Any] ?? [:]
        let enabled = body["p_enabled"] as? Bool == true
        let requestedGeneration = body["p_generation"] as? String
        let requestedToken = body["p_token"] as? String
        var status = 200, data = Data()
        if path.hasSuffix("/mobile_relay") {
            readStarted = true
            if stallReading { await withCheckedContinuation { readGate = $0 } }
            if offline { throw URLError(.notConnectedToInternet) }
            data = try UsageSnapshot.encoder().encode([envelope])
        } else if path.hasSuffix("/mobile-signal") { data = Data(#"{"configured":true}"#.utf8) }
        else if path.hasSuffix("/set_mobile_device") {
            if !enabled {
                offStarted = true
                if stallOff { await withCheckedContinuation { offGate = $0 } }
            }
            active = enabled; lease = UUID(); token = nil
            data = Data("\"\(lease.uuidString)\"".utf8)
        } else if path.hasSuffix("/register_mobile_device") {
            registrationStarted = true
            if stallRegistration { await withCheckedContinuation { registrationGate = $0 } }
            if active && requestedGeneration == lease.uuidString { token = requestedToken }
            else { status = 403; data = Data(#"{"code":"42501"}"#.utf8) }
        }
        return (data,HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
    }
}

@MainActor @Suite("Native iPhone privacy transitions",.serialized) struct PhoneLifecycleTests {
    let now = Date(timeIntervalSince1970:1_792_665_600)
    let owner = "11111111-1111-1111-1111-111111111111"
    var envelope: RelayEnvelope {
        .init(snapshot:UsageSnapshot(generatedAt:now,limits:[
            .init(provider:.codex,window:.fiveHour,source:.automatic,usedPercent:80,observedAt:now,resetsAt:now.addingTimeInterval(3600),state:.reported)
        ]),receivedAt:now,expiresAt:now.addingTimeInterval(900))
    }
    private func client(_ server: Server, owner: String) throws -> SyncClient {
        SyncClient(config:SyncConfig(projectURL:URL(string:"https://example.supabase.co")!,publishableKey:"synthetic",
            redirectURL:SyncConfig.redirectURL),transport:server,store:try Auth(owner),now:{ Date(timeIntervalSince1970:1_792_665_600) })
    }
    func wait(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<600 { if await condition() { return true };try? await Task.sleep(for:.milliseconds(5)) }
        return false
    }
    func defaults() -> (String,UserDefaults) {
        let name = "Clepso.PhoneTests." + UUID().uuidString
        return (name,UserDefaults(suiteName:name)!)
    }
    @Test func cacheLoadsOnlyForMatchingAuthenticatedAccount() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let cache = folder.appendingPathComponent("cache.json")
        try UsageSnapshot.encoder().encode(CompanionCache(accountID:owner,envelope:envelope)).write(to:cache)
        let server = Server(envelope);await server.configure(offline:true)
        let client = try client(server,owner:"22222222-2222-2222-2222-222222222222")
        let (name,prefs) = defaults();defer { prefs.removePersistentDomain(forName:name) }
        let push = PhonePushController(client:client,defaults:prefs,register:{},unregister:{})
        let model = PhoneModel(client:client,cache:cache,clock:{Date(timeIntervalSince1970:1_792_665_600)},push:push)
        #expect(model.envelope == nil)
        await model.start()
        #expect(model.signedIn && model.envelope == nil)
        #expect(!FileManager.default.fileExists(atPath:cache.path))
    }
    @Test func slowPushRemovalCannotDelayLocalSignOutOrAllowOldReads() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let server = Server(envelope), client = try client(server,owner:owner)
        let (name,prefs) = defaults();defer { prefs.removePersistentDomain(forName:name) }
        let push = PhonePushController(client:client,defaults:prefs,register:{},unregister:{})
        let model = PhoneModel(client:client,cache:folder.appendingPathComponent("cache.json"),clock:{Date(timeIntervalSince1970:1_792_665_600)},push:push)
        await push.setEnabled(true)
        await server.configure(read:true,off:true)
        let started = Task { await model.start() }
        #expect(await wait { await server.readStarted })
        let signingOut = Task { await model.signOut() }
        #expect(await wait { await server.offStarted })
        #expect(!model.signedIn && model.envelope == nil)
        await server.releaseRead()
        await started.value
        let before = await server.paths.count
        await model.refresh()
        model.email = "synthetic@example.test"
        await model.requestLink()
        #expect(await server.paths.count == before)
        #expect(model.envelope == nil)
        await server.releaseOff()
        await signingOut.value
        #expect(await client.session == nil)
        #expect(!FileManager.default.fileExists(atPath:folder.appendingPathComponent("cache.json").path))
    }
    @Test func lateRegistrationCannotUndoOffOrItsStatus() async throws {
        let server = Server(envelope), client = try client(server,owner:owner)
        let (name,prefs) = defaults();defer { prefs.removePersistentDomain(forName:name) }
        let push = PhonePushController(client:client,defaults:prefs,register:{},unregister:{})
        await push.setEnabled(true)
        await server.configure(registration:true)
        let registering = Task { await push.register(Data(repeating:10,count:32)) }
        #expect(await wait { await server.registrationStarted })
        await push.setEnabled(false)
        let offMessage = push.message
        await server.releaseRegistration()
        await registering.value
        push.failedRegistration()
        #expect(!push.enabled && push.message == offMessage)
        #expect(await server.token == nil)
    }
    @Test func unrelatedDeepLinksAndUnrequestedCallbacksPreserveConsent() async throws {
        let server = Server(envelope),client = try client(server,owner:owner)
        let (name,prefs) = defaults();defer { prefs.removePersistentDomain(forName:name) }
        let push = PhonePushController(client:client,defaults:prefs,register:{},unregister:{})
        let model = PhoneModel(client:client,cache:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),clock:{Date(timeIntervalSince1970:1_792_665_600)},push:push)
        await push.setEnabled(true)
        let before = await server.paths.count
        await model.callback(URL(string:"clepso://dashboard")!)
        await model.callback(URL(string:"clepso://auth-callback?code=unrequested")!)
        #expect(push.enabled)
        #expect(await server.paths.count == before)
    }
    @Test func cachedOnCannotReenableRevokedServerConsentAfterRestart() async throws {
        let server = Server(envelope),client = try client(server,owner:owner)
        let (name,prefs) = defaults();defer { prefs.removePersistentDomain(forName:name) }
        let push = PhonePushController(client:client,defaults:prefs,register:{},unregister:{})
        await push.setEnabled(true)
        let previousOn = try #require(prefs.data(forKey:"companion.push.choice"))
        await push.setEnabled(false)
        // The server has durably revoked the lease; simulate an older local preferences backup.
        prefs.set(previousOn,forKey:"companion.push.choice")
        let restarted = PhonePushController(client:client,defaults:prefs,register:{},unregister:{})
        await restarted.start()
        await restarted.register(Data(repeating:10,count:32))
        #expect(!restarted.enabled)
        let active = await server.active, token = await server.token
        #expect(!active && token == nil)
    }
}
