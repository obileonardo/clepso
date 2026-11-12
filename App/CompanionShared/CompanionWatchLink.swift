import Foundation
import IntegrationSnapshot
import WatchConnectivity

/// Only the typed aggregate crosses to the paired Watch. No account/session credentials or model IDs.
@MainActor final class CompanionWatchLink: NSObject, WCSessionDelegate {
    var onSnapshot: ((RelayEnvelope?) -> Void)?
    var onRefresh: (() -> Void)?
    private var latest: Data?
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func send(_ envelope: RelayEnvelope?) {
        latest = envelope.flatMap { try? UsageSnapshot.encoder().encode($0) }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["version": 1, "snapshot": latest ?? Data()])
    }
    func requestRefresh() {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["refresh": true], replyHandler: nil)
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let received = session.receivedApplicationContext["snapshot"] as? Data
        Task { @MainActor [weak self] in
            guard let self else { return }
            #if os(iOS)
            self.send(self.latest.flatMap { try? RelayEnvelope.decoder().decode(RelayEnvelope.self, from: $0) })
            #else
            self.receive(received)
            #endif
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        Task { @MainActor [weak self] in self?.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let refresh = message["refresh"] as? Bool == true
        Task { @MainActor [weak self] in if refresh { self?.onRefresh?() } }
    }
    private func receive(_ data: Data?) {
        guard let data, data.count <= 128 * 1024 else { return }
        if data.isEmpty { onSnapshot?(nil); return }
        guard let value = try? RelayEnvelope.decoder().decode(RelayEnvelope.self, from: data), value.valid else { return }
        onSnapshot?(value)
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
