import Foundation
import IntegrationSnapshot

extension SyncClient {
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
