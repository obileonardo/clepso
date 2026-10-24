import Foundation
import IntegrationSnapshot

extension SyncClient {
    public enum PushEnvironment: String, Sendable { case development, production }

    public func setMobileDevice(_ device: UUID, enabled: Bool) async throws -> UUID {
        let session = try await validSession()
        var request = try restRequest("rpc/set_mobile_device", session: session)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_device": device.uuidString, "p_enabled": enabled])
        return try JSONDecoder().decode(UUID.self, from: await send(request))
    }
    public func registerMobileDevice(_ device: UUID, generation: UUID, token: String, environment: PushEnvironment) async throws {
        guard token.utf8.count >= 2, token.utf8.count <= 1024, token.utf8.count % 2 == 0,
              token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw SyncError.badResponse }
        let session = try await validSession()
        var request = try restRequest("rpc/register_mobile_device", session: session)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_device": device.uuidString,
            "p_generation": generation.uuidString, "p_token": token, "p_environment": environment.rawValue])
        _ = try await send(request)
    }
    public func checkMobilePush(_ environment: PushEnvironment) async throws {
        let data = try await mobileSignal(["check": true, "environment": environment.rawValue])
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["configured"] as? Bool == true else { throw SyncError.badResponse }
    }
    public func signalMobileRefresh() async throws { _ = try await mobileSignal([:]) }
    private func mobileSignal(_ body: [String: Any]) async throws -> Data {
        let session = try await validSession(), config = try requireConfig()
        var request = URLRequest(url: config.projectURL.appendingPathComponent("functions/v1/mobile-signal"))
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }
    /// Separate consent is enforced by the Mac composition root; this never piggybacks on hourly counts uploads.
    public func setMobileRelayEnabled(_ enabled: Bool) async throws -> UUID {
        let session = try await validSession()
        var request = try restRequest("rpc/set_mobile_relay", session: session)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_enabled": enabled])
        let data = try await send(request)
        return try JSONDecoder().decode(UUID.self, from: data)
    }
    public func publishMobileRelay(_ snapshot: UsageSnapshot, generation: UUID) async throws {
        guard snapshot.valid, !snapshot.demo else { throw SyncError.badResponse }
        let session = try await validSession()
        var request = try restRequest("rpc/publish_mobile_relay", session: session)
        request.httpMethod = "POST"
        let data = try UsageSnapshot.encoder().encode(snapshot)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_snapshot": JSONSerialization.jsonObject(with: data),
                                                                 "p_generation": generation.uuidString])
        _ = try await send(request)
    }
    public func mobileRelay() async throws -> RelayEnvelope? {
        let session = try await validSession()
        let request = try restRequest("mobile_relay", session: session, query: [
            URLQueryItem(name: "user_id", value: "eq.\(session.userID)"),
            URLQueryItem(name: "select", value: "snapshot,received_at,expires_at"), URLQueryItem(name: "limit", value: "1")])
        let data = try await send(request)
        guard data.count <= 256 * 1024 else { throw SyncError.badResponse }
        let values = try RelayEnvelope.decoder().decode([RelayEnvelope].self, from: data)
        guard values.count <= 1, values.allSatisfy(\.valid) else { throw SyncError.badResponse }
        return values.first
    }
    public func revokeMobileRelay() async throws {
        _ = try await setMobileRelayEnabled(false)
    }
}
