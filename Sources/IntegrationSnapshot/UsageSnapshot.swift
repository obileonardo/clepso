import Foundation

/// The complete outbound contract. No arbitrary provider strings, paths, model/session IDs or account details.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public enum Provider: String, Codable, Sendable, CaseIterable {
        case claudeCode = "claude-code", codex, claudeChat = "claude-chat", chatgpt, gemini, grok, cursor, copilot, windsurf
    }
    public enum Window: String, Codable, Sendable { case fiveHour, weekly, daily }
    public enum Source: String, Codable, Sendable { case automatic, manual }
    public enum State: String, Codable, Sendable { case reported, missing, disconnected, invalid, resetExpected }
    public struct Limit: Codable, Equatable, Sendable {
        public let provider: Provider
        public let window: Window
        public let source: Source
        public let usedPercent: Double?
        public let observedAt: Date?
        public let resetsAt: Date?
        public let state: State
        public init(provider: Provider, window: Window, source: Source, usedPercent: Double?, observedAt: Date?, resetsAt: Date?, state: State) {
            self.provider = provider; self.window = window; self.source = source; self.usedPercent = usedPercent
            self.observedAt = observedAt; self.resetsAt = resetsAt; self.state = state
        }
        public func freshness(at now: Date) -> String {
            guard let observedAt else { return "never" }
            return now.timeIntervalSince(observedAt) >= 600 || observedAt > now.addingTimeInterval(60) ? "stale" : "fresh"
        }
        public func effectiveState(at now: Date) -> State {
            if let resetsAt, resetsAt <= now, state == .reported { return .resetExpected }
            return state
        }
    }
    public let schemaVersion: Int
    public let generatedAt: Date
    public let demo: Bool
    public let limits: [Limit]
    public init(generatedAt: Date, demo: Bool = false, limits: [Limit]) {
        schemaVersion = 1; self.generatedAt = generatedAt; self.demo = demo; self.limits = limits
    }
    public var valid: Bool {
        schemaVersion == 1 && limits.count <= 64 && generatedAt.timeIntervalSince1970.isFinite && limits.allSatisfy {
            ($0.usedPercent.map { $0.isFinite && $0 >= 0 && $0 <= 1_000_000 } ?? true) &&
            [$0.observedAt, $0.resetsAt].compactMap { $0 }.allSatisfy { $0.timeIntervalSince1970.isFinite }
        }
    }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}
