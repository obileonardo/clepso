import Foundation

extension AppModel {
    public func setDataRetention(_ value: DataRetention) async {
        dataRetention = value.validated
        try? await store?.setPreference(Pref.dataRetention, dataRetention, now: environment.clock.now())
        // A shorter choice applies immediately; increasing it cannot recover already purged rows.
        lastPurge = nil
        await purgeIfDue()
        await refresh()
    }
}
