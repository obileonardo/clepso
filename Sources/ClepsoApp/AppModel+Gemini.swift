import Foundation
import ProviderTelemetry

extension AppModel {
    public var geminiInstalled: Bool { GeminiReader.isPresent(home: environment.home) }

    @discardableResult public func setGeminiEnabled(_ enabled: Bool) async -> Bool {
        guard !geminiChanging, let store else { return false }
        geminiChanging = true
        defer { geminiChanging = false }
        do {
            try await store.setPreference(Pref.readGemini, enabled, now: environment.clock.now())
            geminiGeneration += 1
            geminiEnabled = enabled
            geminiUsage = nil
            geminiReader = GeminiReader()
            geminiMessage = nil
            if enabled { await pollGemini() }
            return true
        } catch {
            geminiMessage = "Could not save Gemini reading permission. Try again."
            return false
        }
    }

    func pollGemini() async {
        guard geminiEnabled, !demo, !geminiScanning else { return }
        geminiScanning = true
        defer { geminiScanning = false }
        let home = environment.home, now = environment.clock.now(), generation = geminiGeneration, reader = geminiReader
        let (scanned, usage) = await Task.detached(priority: .utility) {
            var copy = reader
            let usage = copy.scan(home: home, now: now)
            return (copy, usage)
        }.value
        guard geminiEnabled, !demo, generation == geminiGeneration else { return }
        geminiReader = scanned
        geminiUsage = usage
    }
}
