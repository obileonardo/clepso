import Foundation

/// Where Pulse accounts live (DECISIONS C9, ACCOUNTS_AND_SYNC S1–S3). The publishable key is meant to ship inside
/// apps: it identifies the project and grants nothing by itself; every table is protected by row-level security,
/// so a signed-in user's token reaches only that user's rows. The project's secret key is never in the app.
public struct SyncConfig: Sendable, Equatable {
    public let projectURL: URL
    public let publishableKey: String
    /// Where sign-in links and providers send the user back to the app (registered in Info.plist).
    public let redirectURL: URL

    public init(projectURL: URL, publishableKey: String, redirectURL: URL) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
        self.redirectURL = redirectURL
    }

    public static let urlScheme = "dev.tokone.pulse"

    public static let production = SyncConfig(
        projectURL: URL(string: "https://mllnddulchvrblpmezhh.supabase.co")!,
        publishableKey: "sb_publishable_nDRIuq-q1sY5YMDjaOMm5A_BMCjoHHg",
        redirectURL: URL(string: "\(urlScheme)://auth-callback")!)
}
