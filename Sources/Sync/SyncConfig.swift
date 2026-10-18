import Foundation

/// Where Clepso accounts live. The publishable key is meant to ship inside apps: it identifies the project and grants
/// nothing by itself; every table is protected by row-level security, so a signed-in user's token reaches only that
/// user's rows. The project's secret key is never in the app.
///
/// No project is compiled in. Official builds get the host and key as Info.plist values (`ClepsoSyncHost`,
/// `ClepsoSyncPublishableKey`) from a local, uncommitted `Config/Sync.local.xcconfig`; see
/// `Config/Sync.local.xcconfig.example`. A build from source without that file has no `SyncConfig`, and Sync stays
/// off: it never signs in and never makes a request.
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

    public static let urlScheme = "clepso"
    public static let redirectURL = URL(string: "\(urlScheme)://auth-callback")!

    public static let hostKey = "ClepsoSyncHost"
    public static let publishableKeyKey = "ClepsoSyncPublishableKey"

    /// The configuration in an app's Info.plist, or nil when the build carries none (every build from source, unless
    /// its builder supplies their own project). Values that are empty, unexpanded (`$(…)`) or malformed count as none.
    public init?(infoDictionary: [String: Any]) {
        guard let host = (infoDictionary[Self.hostKey] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (infoDictionary[Self.publishableKeyKey] as? String)?.trimmingCharacters(in: .whitespaces),
              Self.isPlausibleHost(host), Self.isPlausibleKey(key),
              let url = URL(string: "https://\(host)") else { return nil }
        self.init(projectURL: url, publishableKey: key, redirectURL: Self.redirectURL)
    }

    /// A bare host name such as `abcd.supabase.co`: no scheme, path, port or unexpanded build setting.
    static func isPlausibleHost(_ host: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return !host.isEmpty && host.count <= 253 && host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
            && host.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// A publishable key: non-empty, no whitespace, no unexpanded build setting. Secret keys are refused outright.
    static func isPlausibleKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 512 && !key.contains("$(") && !key.hasPrefix("sb_secret_")
            && key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}
