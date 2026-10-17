// swift-tools-version: 6.0
// Package layout: docs/ARCHITECTURE.md §2 in the Tokone docs folder. Targets are added at the
// milestone that needs them; this is the Milestone 0 foundation.
import PackageDescription

let package = Package(
    name: "Tokone",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "ShimProtocol", targets: ["ShimProtocol"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        // Linked by the Xcode project (project.yml): the app target imports PulseApp, the embedded helper StatusLineShim.
        .library(name: "PulseApp", targets: ["PulseApp"]),
        .library(name: "StatusLineShim", targets: ["StatusLineShim"]),
        .executable(name: "pulse-statusline", targets: ["pulse-statusline"]),
        .executable(name: "pulse", targets: ["pulse"]),
        .executable(name: "pulse-fixture", targets: ["pulse-fixture"]),
    ],
    dependencies: [
        // ADR-005: GRDB 7.x, exact revision pinned in Package.resolved.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Value types, provenance, ids. No I/O, no clock reads.
        .target(name: "Domain"),
        // Socket frame v1 and the approved field allowlist (statusline-shim.md §6). Foundation only.
        .target(name: "ShimProtocol"),
        // The helper's run loop: stdin, child spawn, frame, socket send (statusline-shim.md §2, §4, §5).
        .target(name: "StatusLineShim", dependencies: ["ShimProtocol"]),
        // What Claude Code runs on every status refresh. One-line main; all logic is in StatusLineShim.
        .executableTarget(name: "pulse-statusline", dependencies: ["StatusLineShim"]),
        // GRDB over SQLite: schema v1 and migrations (DATA_MODEL.md §3, §4).
        // Pure limit, reset and session state machines (DATA_MODEL §6–§7). No I/O, clock injected.
        .target(name: "UsageEngine", dependencies: ["Domain"]),
        // SwiftUI tokens, status styles and components (DESIGN_SYSTEM.md). The founder restyles Theme/ and component bodies.
        .target(name: "DesignSystem", dependencies: ["Domain"], resources: [.copy("Resources/Fonts")]),
        .target(name: "Storage", dependencies: ["Domain", "UsageEngine", .product(name: "GRDB", package: "GRDB.swift")]),
        // Claude Code adapter: reversible settings install (statusline-shim.md §3); listener and ingest arrive in 1.1.
        .target(name: "ClaudeCodeAdapter", dependencies: ["Domain", "ShimProtocol"]),
        // Headless CLI: reversible install/uninstall now; replay, status and export later (ARCHITECTURE §2).
        .executableTarget(name: "pulse", dependencies: ["ClaudeCodeAdapter"]),
        // The bundled plan catalog seed (PLAN_CATALOG.md); signed downloads arrive in 3.1.
        .target(name: "SubscriptionCatalog", resources: [.copy("Resources/plan-catalog.v1.json")]),
        // Composition root, view models and screens (ARCHITECTURE §2). The Xcode app target is a thin @main over this.
        .target(name: "PulseApp", dependencies: ["DesignSystem", "Domain", "Storage", "UsageEngine", "ClaudeCodeAdapter",
                                                 "SubscriptionCatalog", "ShimProtocol", "Sync"]),
        // Pulse accounts (ROADMAP 2.0): the only module allowed to make network calls.
        .target(name: "Sync"),
        // Developer-only fixture tooling: capture listener, capture shim, scrubber. Never shipped.
        .target(name: "FixtureTools", dependencies: ["ShimProtocol"]),
        .executableTarget(name: "pulse-fixture", dependencies: ["FixtureTools"]),
        // Developer-only: renders the real components to PNG and exports the theme for the design-system page.
        .executableTarget(name: "pulse-design-render", dependencies: ["DesignSystem", "Domain"]),
        // Fixture corpus F01–F19 (docs/fixtures/README.md format) shipped as test resources.
        .target(name: "TestFixtures", resources: [.copy("Resources")]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "ShimProtocolTests", dependencies: ["ShimProtocol"]),
        .testTarget(name: "UsageEngineTests", dependencies: ["UsageEngine", "Domain"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "Domain"]),
        .testTarget(name: "StorageTests", dependencies: ["Storage", "Domain", "UsageEngine"]),
        .testTarget(name: "ClaudeCodeAdapterTests", dependencies: ["ClaudeCodeAdapter", "Domain", "ShimProtocol", "TestFixtures"]),
        .testTarget(name: "FixtureToolsTests", dependencies: ["FixtureTools"]),
        .testTarget(name: "SubscriptionCatalogTests", dependencies: ["SubscriptionCatalog"]),
        .testTarget(name: "SyncTests", dependencies: ["Sync"]),
        .testTarget(name: "PulseAppTests", dependencies: ["PulseApp", "DesignSystem", "Domain", "Storage", "UsageEngine",
                                                          "ClaudeCodeAdapter", "ShimProtocol", "SubscriptionCatalog", "Sync"]),
        // Runs the built pulse-statusline binary as a child process against a temporary HOME.
        .testTarget(name: "ShimIntegrationTests", dependencies: ["pulse-statusline", "pulse", "Domain", "ShimProtocol", "TestFixtures", "ClaudeCodeAdapter", "FixtureTools",
                                                             "UsageEngine", "Storage", "PulseApp"]),
    ]
)
