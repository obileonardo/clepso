/// Sparkle stays in the signed Xcode host. Tests and isolated runs receive no updater and make no requests.
public protocol AppUpdating: AnyObject, Sendable {
    @MainActor var available: Bool { get }
    @MainActor var automaticChecks: Bool { get set }
    @MainActor var automaticDownloads: Bool { get set }
    @MainActor func check()
}

@MainActor public final class UnavailableUpdater: AppUpdating {
    public init() {}
    public let available = false
    public var automaticChecks = false
    public var automaticDownloads = false
    public func check() {}
}
