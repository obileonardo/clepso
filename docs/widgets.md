# Desktop widgets

The Mac app embeds a real WidgetKit extension with small and medium layouts. In Settings → Integrations,
enable Desktop widgets, then add **Clepso limits** from macOS's widget gallery. Sharing is off initially.
No account is required. Clicking the widget opens the app's Limits page.

The app publishes only the allowlisted `IntegrationSnapshot.UsageSnapshot` into a shared app-group container.
The widget has no networking entitlement, database access, credentials, transcripts or session identifiers.
It shows up to two/four windows, automatic sources first, and labels manual readings. Missing data remains a dash.
After ten minutes a reading is old; a passed reset is expected and awaits a fresh reading. It never claims a
reset proves availability. macOS controls actual widget refresh frequency; this is not a live menu-bar replacement.

The timeline contains freshness/reset boundaries and requests another refresh after fifteen minutes. Publication
requests are coalesced when readings have not changed. Turning sharing off, entering demo mode or deleting local
data removes the widget snapshot. Widgets do not share MCP permissions.

For Developer ID distribution, both app and extension use the Mac-only app group
`<team identifier>.com.elvisobi.clepso.widgets`. Apple's documented team-prefixed format does not need a provisioning
profile or registration. The extension is sandboxed; the host remains unsandboxed to support the existing reversible
Claude settings integration. No broad temporary file-access or networking exceptions are added.
Source builds signed ad hoc cannot establish this production team identity and report sharing as unavailable.

See [Apple's app-group guidance](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).
Build/signature validation and rendered previews are separate from physical widget-gallery testing; consult the
current handoff for which observations have actually been completed.
