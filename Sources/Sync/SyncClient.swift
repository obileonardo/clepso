import CryptoKit
import Foundation
import Security

/// Clepso accounts: signing in and uploading daily counts to Supabase. Optional, and off in any build without a
/// `SyncConfig` (see SyncConfig.swift): then every call below fails with `SyncError.unavailable` before a request is made.
///
/// The only module allowed to make network calls (`make ci`, "networking only in Sync"). It talks to two Supabase
/// endpoints: Auth (sign-in, refresh, sign-out) and the REST API (upserting the signed-in user's own rows). Every
/// request carries the publishable key and, once signed in, the user's token; row-level security on the server does
/// the rest. Nothing here logs request or response bodies, and errors never include tokens.

// MARK: - Transport

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession without cookies or a cache: nothing about the account is written to disk except by the session store.
public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.badResponse }
        return (data, http)
    }
}

/// For tests and previews: every call fails as if offline, so nothing can reach the network by accident.
public struct OfflineTransport: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
}

// MARK: - Session

public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String
    public var email: String?
}

/// What survives a relaunch: the session, and the PKCE verifier between "email me a link" and the click.
public struct StoredAuth: Codable, Sendable, Equatable {
    public var session: AuthSession?
    public var pendingVerifier: String?
    public var pendingEmail: String?
    public init(session: AuthSession? = nil, pendingVerifier: String? = nil, pendingEmail: String? = nil) {
        self.session = session
        self.pendingVerifier = pendingVerifier
        self.pendingEmail = pendingEmail
    }
}

public protocol AuthStore: Sendable {
    func load() -> StoredAuth
    func save(_ auth: StoredAuth)
}

/// The Keychain, one generic-password item holding JSON, this device only.
public struct KeychainAuthStore: AuthStore {
    let service: String
    /// Kept from before the rename to Clepso: the Keychain item already saved under it is the signed-in session, and
    /// a new name would sign everyone out.
    let account = "pulse-account"
    public init(service: String = "com.elvisobi.clepso.account") { self.service = service }

    public func load() -> StoredAuth {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let auth = try? JSONDecoder().decode(StoredAuth.self, from: data) else { return StoredAuth() }
        return auth
    }

    public func save(_ auth: StoredAuth) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard auth != StoredAuth(), let data = try? JSONEncoder().encode(auth) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

public final class MemoryAuthStore: AuthStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value = StoredAuth()
    public init() {}
    public func load() -> StoredAuth { lock.withLock { value } }
    public func save(_ auth: StoredAuth) { lock.withLock { value = auth } }
}

public enum SyncError: Error, Equatable, Sendable {
    case unavailable                      // this build has no accounts project configured: Sync is off
    case notSignedIn
    case noPendingSignIn
    case invalidCallback(String)          // the provider's own error description, or what was missing
    case http(status: Int, code: String?) // Supabase's error code (e.g. "otp_expired"), never a body
    case badResponse
}

// MARK: - PKCE (RFC 7636)

public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public var challenge: String { Self.challenge(for: verifier) }

    public static func make() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PKCE(verifier: base64url(Data(bytes)))
    }

    public static func challenge(for verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Client

public actor SyncClient {
    public enum Provider: String, Sendable, CaseIterable, Hashable { case apple, google, github }

    let configuration: SyncConfig?
    let transport: any HTTPTransport
    let store: any AuthStore
    let now: @Sendable () -> Date

    /// Whether this build can use accounts at all. False for builds from source without a configured project.
    public nonisolated let isAvailable: Bool
    public nonisolated let enabledProviders: Set<Provider>

    /// `config` nil: Sync is off. No request is ever sent and no session is reported.
    public init(config: SyncConfig?, transport: any HTTPTransport = URLSessionTransport(), store: any AuthStore = KeychainAuthStore(),
                now: @escaping @Sendable () -> Date) {
        self.configuration = config
        self.isAvailable = config != nil
        self.enabledProviders = config?.enabledProviders ?? []
        self.transport = transport
        self.store = store
        self.now = now
    }

    public var session: AuthSession? { isAvailable ? store.load().session : nil }
    public var pendingEmail: String? { isAvailable ? store.load().pendingEmail : nil }
    public var hasPendingSignIn: Bool { isAvailable && store.load().pendingVerifier != nil }

    /// The configuration, or `unavailable` before anything touches the network.
    func requireConfig() throws -> SyncConfig {
        guard let configuration else { throw SyncError.unavailable }
        return configuration
    }

    // Sign-in

    /// Emails a one-time sign-in link that opens Clepso (`redirectURL`). PKCE: the link is useless without the verifier
    /// kept in this Mac's Keychain.
    public func requestEmailLink(_ email: String) async throws {
        let config = try requireConfig()
        let pkce = PKCE.make()
        var request = try authRequest("otp", query: [URLQueryItem(name: "redirect_to", value: config.redirectURL.absoluteString)])
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "create_user": true,
                                                                      "code_challenge": pkce.challenge, "code_challenge_method": "s256"])
        _ = try await send(request)
        var stored = store.load()
        stored.pendingVerifier = pkce.verifier
        stored.pendingEmail = email
        store.save(stored)
    }

    /// The browser page for Apple, Google or GitHub; it returns to `redirectURL` with a code. Nil when Sync is off.
    public func providerURL(_ provider: Provider) -> URL? {
        guard let config = configuration else { return nil }
        let pkce = PKCE.make()
        var stored = store.load()
        stored.pendingVerifier = pkce.verifier
        stored.pendingEmail = nil
        store.save(stored)
        var components = URLComponents(url: config.projectURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "provider", value: provider.rawValue),
                                 URLQueryItem(name: "redirect_to", value: config.redirectURL.absoluteString),
                                 URLQueryItem(name: "code_challenge", value: pkce.challenge),
                                 URLQueryItem(name: "code_challenge_method", value: "s256")]
        return components.url!
    }

    /// `clepso://auth-callback?code=…` (or `…#error=…&error_description=…`): exchanges the code for a session.
    @discardableResult
    public func handleCallback(_ url: URL) async throws -> AuthSession {
        let config = try requireConfig()
        guard url.scheme == config.redirectURL.scheme, url.host == config.redirectURL.host else { throw SyncError.invalidCallback("not a sign-in link") }
        let items = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            + (URLComponents(string: "?" + (url.fragment ?? ""))?.queryItems ?? [])
        // Form-encoded, as Supabase writes them: "+" is a space.
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value?.replacingOccurrences(of: "+", with: " ") }
        if let error = value("error_description") ?? value("error") { throw SyncError.invalidCallback(error) }
        guard let code = value("code") else { throw SyncError.invalidCallback("no code in the link") }
        guard let verifier = store.load().pendingVerifier else { throw SyncError.noPendingSignIn }
        var request = try authRequest("token", query: [URLQueryItem(name: "grant_type", value: "pkce")])
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": verifier])
        let session = try decodeSession(try await send(request))
        store.save(StoredAuth(session: session))
        return session
    }

    /// A session valid for at least another minute, refreshed if needed.
    public func validSession() async throws -> AuthSession {
        _ = try requireConfig()
        guard let session = store.load().session else { throw SyncError.notSignedIn }
        if session.expiresAt.timeIntervalSince(now()) > 60 { return session }
        var request = try authRequest("token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        do {
            let fresh = try decodeSession(try await send(request))
            store.save(StoredAuth(session: fresh))
            return fresh
        } catch SyncError.http(let status, _) where status == 400 || status == 401 {
            store.save(StoredAuth())                       // refresh token revoked or expired: signed out
            throw SyncError.notSignedIn
        }
    }

    /// Signs out here and revokes the session on the server (best effort: offline, it still signs out here).
    public func signOut() async {
        if configuration != nil, let session = store.load().session, var request = try? authRequest("logout", query: [URLQueryItem(name: "scope", value: "local")]) {
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await send(request)
        }
        store.save(StoredAuth())
    }

    /// Deletes the account and every row with it (server function `delete_account`), then signs out here.
    public func deleteAccount() async throws {
        let session = try await validSession()
        var request = try restRequest("rpc/delete_account", session: session)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        _ = try await send(request)
        store.save(StoredAuth())
    }

    // Upload

    /// Upserts every row of the payload as the signed-in user. Idempotent: re-sending a day replaces it.
    public func upload(_ payload: SyncPayload) async throws {
        let session = try await validSession()
        if let profile = payload.profile {
            var request = try restRequest("profiles", session: session, query: [URLQueryItem(name: "user_id", value: "eq.\(session.userID)")])
            request.httpMethod = "PATCH"
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try SyncPayload.encoder.encode(profile)
            _ = try await send(request)
        }
        try await upsert("daily_activity", payload.activity, conflict: "user_id,day", session: session)
        try await upsert("daily_model_tokens", payload.modelTokens, conflict: "user_id,day,model", session: session)
        try await upsert("model_totals", payload.modelTotals, conflict: "user_id,model", session: session)
        try await upsert("daily_limits", payload.limits, conflict: "user_id,day", session: session)
        try await upsert("daily_agents", payload.agents, conflict: "user_id,day", session: session)
        try await upsert("goals", payload.goals, conflict: "user_id,kind", session: session)
        try await upsert("goal_days", payload.goalDays, conflict: "user_id,day,kind", session: session)
    }

    func upsert<Row: Encodable>(_ table: String, _ rows: [Row], conflict: String, session: AuthSession) async throws {
        guard !rows.isEmpty else { return }
        var request = try restRequest(table, session: session, query: [URLQueryItem(name: "on_conflict", value: conflict)])
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try SyncPayload.encoder.encode(rows)
        _ = try await send(request)
    }

    // Plumbing

    func authRequest(_ path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        let config = try requireConfig()
        var components = URLComponents(url: config.projectURL.appendingPathComponent("auth/v1/\(path)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func restRequest(_ path: String, session: AuthSession, query: [URLQueryItem] = []) throws -> URLRequest {
        let config = try requireConfig()
        var components = URLComponents(url: config.projectURL.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        _ = try requireConfig()                                   // belt and braces: never send without a project
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = (object?["error_code"] ?? object?["code"] ?? object?["error"]).map { "\($0)" }
            throw SyncError.http(status: response.statusCode, code: code.map { String($0.prefix(40)) })
        }
        return data
    }

    func decodeSession(_ data: Data) throws -> AuthSession {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = object["access_token"] as? String, let refresh = object["refresh_token"] as? String,
              let user = object["user"] as? [String: Any], let id = user["id"] as? String else { throw SyncError.badResponse }
        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: now().addingTimeInterval(expiresIn),
                           userID: id, email: user["email"] as? String)
    }
}
