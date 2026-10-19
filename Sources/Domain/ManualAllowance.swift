import Foundation

/// A dated value the user copied from a provider. It never replaces automatic telemetry or claims a provider
/// connection. No credentials, pasted account pages or arbitrary notes are accepted.
public struct ManualAllowance: Codable, Identifiable, Sendable, Equatable {
    public enum Window: String, Codable, Sendable, CaseIterable { case fiveHour, weekly, daily }
    public let id: UUID
    public let providerID: String
    public let window: Window
    public let usedPercent: Decimal?
    public let resetsAt: Date?
    public let observedAt: Date
    public let enteredAt: Date
    public let planCatalogID: String?
    public let paidOverage: Bool

    public enum Invalid: Error, Equatable { case provider, percent, observedAt, reset, empty }

    public init(id: UUID = UUID(), providerID: String, window: Window, usedPercent: Decimal?, resetsAt: Date?,
                observedAt: Date, enteredAt: Date, planCatalogID: String? = nil, paidOverage: Bool = false) throws {
        guard ManualProvider.supported.contains(where: { $0.id == providerID }) else { throw Invalid.provider }
        if let usedPercent, usedPercent.isNaN || usedPercent < 0 || usedPercent > 100 { throw Invalid.percent }
        guard observedAt <= enteredAt, observedAt >= enteredAt.addingTimeInterval(-90 * 86_400) else { throw Invalid.observedAt }
        if let resetsAt, resetsAt <= observedAt || resetsAt > observedAt.addingTimeInterval(90 * 86_400) { throw Invalid.reset }
        guard usedPercent != nil || resetsAt != nil else { throw Invalid.empty }
        self.id = id; self.providerID = providerID; self.window = window; self.usedPercent = usedPercent
        self.resetsAt = resetsAt; self.observedAt = observedAt; self.enteredAt = enteredAt
        self.planCatalogID = planCatalogID; self.paidOverage = paidOverage
    }

    public var evidence: EvidenceKind { .userConfirmed }
    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(observedAt) >= Freshness.localTelemetryTTL }
    public func resetPassed(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }

    /// Decimal(string:) accepts a numeric prefix of arbitrary text. Forms require the entire input to be a
    /// percentage, using the user's decimal separator, without exponents or pasted page content.
    public static func parsePercent(_ input: String, locale: Locale) -> Decimal? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let allowed = CharacterSet(charactersIn: "0123456789" + separator)
        guard text.contains(where: { $0.isASCII && $0.isNumber }), text.utf8.count <= 16, text.unicodeScalars.allSatisfy(allowed.contains),
              text.components(separatedBy: separator).count <= 2,
              let value = Decimal(string: text, locale: locale), !value.isNaN, value >= 0, value <= 100 else { return nil }
        return value
    }
}

public struct ManualProvider: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let publisher: String
    public let usageURL: String
    public static let supported: [Self] = [
        Self(id: "claude-chat", name: "Claude Chat", publisher: "anthropic", usageURL: "https://claude.ai/settings/usage"),
        Self(id: "chatgpt", name: "ChatGPT", publisher: "openai", usageURL: "https://chatgpt.com/"),
        Self(id: "gemini", name: "Gemini / Gemini CLI", publisher: "google", usageURL: "https://gemini.google.com/"),
        Self(id: "grok", name: "Grok", publisher: "xai", usageURL: "https://grok.com/"),
        Self(id: "cursor", name: "Cursor", publisher: "cursor", usageURL: "https://cursor.com/dashboard"),
        Self(id: "copilot", name: "GitHub Copilot", publisher: "github", usageURL: "https://github.com/settings/copilot"),
        Self(id: "windsurf", name: "Windsurf", publisher: "windsurf", usageURL: "https://windsurf.com/"),
    ]
}
