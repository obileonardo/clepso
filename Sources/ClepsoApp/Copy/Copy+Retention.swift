extension Copy {
    enum Retention {
        static let title = "Keep my history"
        static let subtitle = "Choose how long readings, session details, notification receipts and diagnostics stay on this Mac"
        static let readings = "Limit history"
        static let sessions = "Sessions and agents"
        static let receipts = "Notification receipts"
        static let logs = "Diagnostics"
        static let warning = "Shorter periods remove older records immediately. Increasing a period cannot recover deleted records. Model statistics remain in the agent's own files."
        static func days(_ value: Int) -> String { "\(value) DAYS" }
    }
}
