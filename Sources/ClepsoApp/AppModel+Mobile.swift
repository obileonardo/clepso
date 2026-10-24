import Foundation
import IntegrationSnapshot

struct MobileSharingState: Codable, Equatable, Sendable {
    var enabled = false
    var accountID: String?
    var lease: UUID?
    var pendingRevocation = false
}

extension AppModel {
    public var mobileSharingEnabled: Bool { mobileSharing.enabled }

    /// Called only after the mobile disclosure. This is independent of daily-summary uploads and local integrations.
    @discardableResult public func setMobileSharing(_ enabled: Bool) async -> Bool {
        guard !mobileSharingBusy else { return false }
        guard let store else { mobileSharingMessage = "Clepso is still opening its data. Try again shortly."; return false }
        mobileSharingBusy = true
        defer { mobileSharingBusy = false }
        do {
            if enabled {
                guard !demo, let session = await environment.sync.session else {
                    mobileSharingMessage = "Sign in to Clepso and leave demo mode before sharing with your iPhone."; return false
                }
                let lease = try await environment.sync.setMobileRelayEnabled(true)
                guard await environment.sync.session?.userID == session.userID else {
                    mobileSharingMessage = "Your account changed. Review sharing again."; return false
                }
                let choice = MobileSharingState(enabled: true, accountID: session.userID, lease: lease)
                do { try await store.setPreference(Pref.mobileSharing, choice, now: environment.clock.now()) }
                catch { try? await environment.sync.revokeMobileRelay(); throw error }
                mobileSharing = choice
                lastMobileAttempt = nil
                mobileSharingMessage = "Sharing enabled. Sign in with the same account on your iPhone."
            } else {
                // Persist off before suspension. Even a crash or an older publisher cannot restore local consent.
                var choice = mobileSharing
                choice.enabled = false
                choice.pendingRevocation = choice.accountID != nil
                try await store.setPreference(Pref.mobileSharing, choice, now: environment.clock.now())
                mobileSharing = choice
                await finishMobileRevocation()
            }
            mobileSharingBusy = false
            if enabled { publishMobileIfDue() }
            return true
        } catch {
            mobileSharingMessage = "Mobile sharing could not be changed. Check your connection and retry."
            return false
        }
    }

    func finishMobileRevocation() async {
        guard mobileSharing.pendingRevocation, !mobileSharing.enabled else { return }
        guard let session = await environment.sync.session, session.userID == mobileSharing.accountID else {
            mobileSharingMessage = "Sharing is off on this Mac. The previous server reading expires within 15 minutes; sign in to the same account to remove it sooner."
            return
        }
        let choice = mobileSharing
        do {
            try await environment.sync.revokeMobileRelay()
            guard choice == mobileSharing else { return }
            var cleared = choice
            cleared.pendingRevocation = false; cleared.lease = nil
            try await store?.setPreference(Pref.mobileSharing, cleared, now: environment.clock.now())
            mobileSharing = cleared
            mobileSharingMessage = "Mobile sharing is off and the server snapshot was removed. Offline phones may retain an old reading or pending reminder."
        } catch {
            mobileSharingMessage = "Sharing is off on this Mac. Server removal is pending; the previous server reading expires within 15 minutes."
        }
    }

    func publishMobileIfDue() {
        guard mobileSharing.enabled, !mobileSharingBusy, !demo, mobilePublishTask == nil,
              let lease = mobileSharing.lease, mobileSharing.accountID != nil else { return }
        let now = environment.clock.now()
        guard lastMobileAttempt.map({ now.timeIntervalSince($0) >= 60 || now < $0 }) ?? true else { return }
        let choice = mobileSharing, snapshot = integrationSnapshot()
        guard snapshot.valid, !snapshot.demo else { return }
        lastMobileAttempt = now
        mobilePublishTask = Task { [weak self] in
            guard let self else { return }
            defer { self.mobilePublishTask = nil }
            guard await self.environment.sync.session?.userID == choice.accountID, self.mobileSharing == choice, !self.demo else { return }
            do {
                try await self.environment.sync.publishMobileRelay(snapshot, generation: lease)
                guard self.mobileSharing == choice, !Task.isCancelled else { return }
                let at = self.environment.clock.now()
                if self.lastMobileSignalAttempt.map({ at.timeIntervalSince($0) >= 21 * 60 || at < $0 }) ?? true {
                    self.lastMobileSignalAttempt = at
                    // A missing push setup or delayed Apple response must not invalidate a successful relay write.
                    try? await self.environment.sync.signalMobileRefresh()
                }
                guard self.mobileSharing == choice, !Task.isCancelled else { return }
                self.mobileSharingMessage = "Last mobile reading shared just now."
            } catch {
                guard self.mobileSharing == choice, !Task.isCancelled else { return }
                self.mobileSharingMessage = "Could not share the latest reading. Your phone may show an old reading. Retry by refreshing."
            }
        }
    }
}
