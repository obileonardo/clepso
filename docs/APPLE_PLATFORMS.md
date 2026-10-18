# iPhone, Apple Watch and widgets: feasibility

Roadmap increment 4.2 ("shared Domain/UsageEngine; snapshot file for widgets; honest stale-age timelines"). This note
records what was checked on 18 Oct 2026, what it means for the design, and what needs a decision. Nothing for these
platforms is built yet.

## Checked (compiled, 18 Oct 2026, Xcode with the iOS 27.1 and watchOS 27.0 SDKs)

| Module | iOS Simulator | watchOS Simulator |
|---|---|---|
| `Domain`, `UsageEngine`, `Storage` (with GRDB) | builds | builds |
| `DesignSystem` | builds | **fails**: `onHover(perform:)` is unavailable on watchOS (`Pixel/PixelKit.swift`); later errors may be hidden behind this one |
| `PulseApp` | not attempted: AppKit, the status item, the Unix socket and the settings installer are Mac-only by design | — |

Command: `xcodebuild -scheme <Storage|DesignSystem> -destination 'generic/platform=iOS Simulator' build` (and the
watchOS one). `Package.swift` already declares `.iOS(.v17), .watchOS(.v10)`.

So the engine (reducers, alert planner, reset and window logic, `.ics` builder) and the store are shared as they are.
The pixel design system needs a few `#if os(watchOS)` guards before a Watch target can use it.

## The real constraint: the data is on the Mac

Clepso's readings come from Claude Code's status line on the Mac (and Codex's session files there). An iPhone has no
such source, so every phone, watch or phone-widget value is a copy of the Mac's, and its age has to be shown.

| Route to the phone | What it needs | Freshness | Notes |
|---|---|---|---|
| Accounts sync (ACCOUNTS_AND_SYNC, steps 1–2 done) | The user signed in on both; an iOS client for the existing API | As old as the last upload (hourly today) | Already built on the Mac side. A shorter upload interval or an upload on each limit crossing would make phone alerts useful |
| Push (NOTIFICATIONS §3.5) | APNs key, `aps-environment` entitlement on iOS, the backend sending pushes | Seconds | The spec's freshness caps already exist in `AlertKind.maxAge` and apply unchanged |
| CloudKit | iCloud entitlement on both apps | Minutes, best effort | A second sync system next to the accounts backend; not recommended |

**Recommendation:** iOS reads through the accounts backend (no second sync path), with pushes for limit alerts
when Stage B allows network traffic.

## Widgets

- **Mac widgets first (inference: lowest risk).** A WidgetKit extension in the Mac app, reading a small snapshot file
  the app writes on every refresh (scope, used %, reset instant, reading time, never prompt text). WidgetKit
  extensions run sandboxed, so the file goes in an App Group container both can read. The host app stays
  unsandboxed. Needs an App Group entitlement on both targets: a signing change (docs/RELEASE.md section 5).
- **Honest stale-age timelines.** Every entry carries the reading's time; the widget shows "as of 14:05" and the
  relative age (`Text(date, style: .relative)`), and switches to "reset expected · awaiting update" at the reset
  instant through a timeline entry dated then, never a guessed 0%. The same rules as the app: stale after 10 minutes,
  a passed reset is not proof of availability (DATA_MODEL §6, G6).
- **iPhone widgets and Watch complications** use the same snapshot shape, filled by the iOS app from the backend.

## What's needed before work starts

1. A7 bundle prefix, and App Group identifier(s) under it.
2. The Watch build fix in `DesignSystem` (guards around hover and other macOS-only modifiers).
3. Decide the upload interval (hourly vs on change) and whether alpha includes Sync (docs/RELEASE.md section 5).
4. iOS and watchOS targets in `project.yml`; the version numbers already follow the shared scheme (RELEASE.md section 1).
