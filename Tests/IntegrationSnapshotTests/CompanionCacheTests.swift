import Foundation
import Testing
@testable import IntegrationSnapshot

@Suite("Account-bound phone cache") struct CompanionCacheTests {
    @Test func onlyMatchingSignedInAccountReceivesCachedReading() throws {
        let now = Date(timeIntervalSince1970: 1_792_665_600)
        let envelope = RelayEnvelope(snapshot: UsageSnapshot(generatedAt: now, limits: []),receivedAt:now,expiresAt:now.addingTimeInterval(900))
        let bytes = try UsageSnapshot.encoder().encode(CompanionCache(accountID:"synthetic-account-a",envelope:envelope))
        #expect(!String(decoding:bytes,as:UTF8.self).contains("synthetic-account-a"))
        let cache = try RelayEnvelope.decoder().decode(CompanionCache.self,from:bytes)
        #expect(cache.reading(for:"synthetic-account-a") == envelope)
        #expect(cache.reading(for:"synthetic-account-b") == nil)
        #expect(cache.reading(for:"") == nil)
    }
    @Test func invalidDemoEnvelopeNeverReappearsFromCache() {
        let now = Date(timeIntervalSince1970: 1_792_665_600)
        let value = RelayEnvelope(snapshot:UsageSnapshot(generatedAt:now,demo:true,limits:[]),receivedAt:now,expiresAt:now.addingTimeInterval(900))
        #expect(CompanionCache(accountID:"synthetic",envelope:value).reading(for:"synthetic") == nil)
    }
}
