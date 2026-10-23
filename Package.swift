// swift-tools-version: 6.0
// Package layout: ARCHITECTURE §2. Targets are added at the
// milestone that needs them; this is the Milestone 0 foundation.
import PackageDescription

let package = Package(
    name: "Clepso",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "IntegrationSnapshot", targets: ["IntegrationSnapshot"]),
        .library(name: "ClepsoMCP", targets: ["ClepsoMCP"]),
        .library(name: "ClaudeCodeAdapter", targets: ["ClaudeCodeAdapter"]),
        .library(name: "ShimProtocol", targets: ["ShimProtocol"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        // Linked by the Xcode project (project.yml): the app target imports ClepsoApp, the embedded helper StatusLineShim.
        .library(name: "ClepsoApp", targets: ["ClepsoApp"]),
        .library(name: "StatusLineShim", targets: ["StatusLineShim"]),
        .executable(name: "clepso-statusline", targets: ["clepso-statusline"]),
        .executable(name: "clepso", targets: ["clepso"]),
        .executable(name: "clepso-fixture", targets: ["clepso-fixture"]),
    ],
    dependencies: [
        // ARCHITECTURE §4: GRDB 7.x, exact revision pinned in Package.resolved.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Value types, provenance, ids. No I/O, no clock reads.
        .target(name: "Domain"),
        .target(name: "IntegrationSnapshot"),
        .target(name: "ProviderTelemetry"),
        .target(name: "ClepsoMCP", dependencies: ["IntegrationSnapshot"]),
        // Socket frame v1 and the approved field allowlist (PRIVACY_AND_SECURITY §4). Foundation only.
        .target(name: "ShimProtocol"),
        // The helper's run loop: stdin, child spawn, frame, socket send (ARCHITECTURE §3).
        .target(name: "StatusLineShim", dependencies: ["ShimProtocol"]),
        // What Claude Code runs on every status refresh. One-line main; all logic is in StatusLineShim.
        .executableTarget(name: "clepso-statusline", dependencies: ["StatusLineShim"]),
        // GRDB over SQLite: schema v1 and migrations (DATA_MODEL §3, §4).
        // Pure limit, reset and session state machines (DATA_MODEL §6–§7). No I/O, clock injected.
        .target(name: "UsageEngine", dependencies: ["Domain"]),
        // SwiftUI tokens, status styles and components. The founder restyles Theme/ and component bodies.
        .target(name: "DesignSystem", dependencies: ["Domain"], resources: [.copy("Resources/Fonts")]),
        .target(name: "Storage", dependencies: ["Domain", "UsageEngine", .product(name: "GRDB", package: "GRDB.swift")]),
        // Claude Code adapter: reversible settings install (PRIVACY_AND_SECURITY §7); listener and ingest arrive in 1.1.
        .target(name: "ClaudeCodeAdapter", dependencies: ["Domain", "ShimProtocol"]),
        // Increment 3.4: Codex limits from its own session files.
        .target(name: "CodexAdapter", dependencies: ["Domain"]),
        // Headless CLI: reversible install/uninstall now; replay, status and export later (ARCHITECTURE §2).
        .executableTarget(name: "clepso", dependencies: ["ClaudeCodeAdapter", "ClepsoMCP"]),
        // The bundled plan catalog seed; signed downloads arrive in 3.1.
        .target(name: "SubscriptionCatalog", resources: [.copy("Resources/plan-catalog.v1.json")]),
        // Composition root, view models and screens (ARCHITECTURE §2). The Xcode app target is a thin @main over this.
        .target(name: "ClepsoApp", dependencies: ["DesignSystem", "Domain", "Storage", "UsageEngine", "ClaudeCodeAdapter", "CodexAdapter",
                                                 "SubscriptionCatalog", "ShimProtocol", "Sync", "IntegrationSnapshot", "ProviderTelemetry"]),
        // Clepso accounts: the only module allowed to make network calls.
        .target(name: "Sync"),
        // Developer-only fixture tooling: capture listener, capture shim, scrubber. Never shipped.
        .target(name: "FixtureTools", dependencies: ["ShimProtocol"]),
        .executableTarget(name: "clepso-fixture", dependencies: ["FixtureTools"]),
        // Developer-only: renders the real components to PNG and exports the theme for the design-system page.
        .executableTarget(name: "clepso-design-render", dependencies: ["DesignSystem", "Domain"]),
        // Fixture corpus F01–F19 (FIXTURES format) shipped as test resources.
        .target(name: "TestFixtures", resources: [.copy("Resources")]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "ProviderTelemetryTests", dependencies: ["ProviderTelemetry"]),
        .testTarget(name: "IntegrationSnapshotTests", dependencies: ["IntegrationSnapshot", "ClepsoMCP"]),
        .testTarget(name: "ShimProtocolTests", dependencies: ["ShimProtocol"]),
        .testTarget(name: "UsageEngineTests", dependencies: ["UsageEngine", "Domain"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "Domain"]),
        .testTarget(name: "StorageTests", dependencies: ["Storage", "Domain", "UsageEngine"]),
        .testTarget(name: "CodexAdapterTests", dependencies: ["CodexAdapter", "Domain"]),
        .testTarget(name: "ClaudeCodeAdapterTests", dependencies: ["ClaudeCodeAdapter", "Domain", "ShimProtocol", "TestFixtures"]),
        .testTarget(name: "FixtureToolsTests", dependencies: ["FixtureTools"]),
        .testTarget(name: "SubscriptionCatalogTests", dependencies: ["SubscriptionCatalog"]),
        .testTarget(name: "SyncTests", dependencies: ["Sync"]),
        .testTarget(name: "ClepsoAppTests", dependencies: ["ClepsoApp", "DesignSystem", "Domain", "Storage", "UsageEngine",
                                                          "ClaudeCodeAdapter", "ShimProtocol", "SubscriptionCatalog", "Sync", "IntegrationSnapshot", "ProviderTelemetry"]),
        // Runs the built clepso-statusline binary as a child process against a temporary HOME.
        .testTarget(name: "ShimIntegrationTests", dependencies: ["clepso-statusline", "clepso", "Domain", "ShimProtocol", "TestFixtures", "ClaudeCodeAdapter", "FixtureTools",
                                                             "UsageEngine", "Storage", "ClepsoApp"]),
    ]
)
