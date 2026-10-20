# Optional accounts: current implementation

Public alpha builds carry no accounts project, make no account requests and cannot sign in. This remains the
release default. Local source builds also have no project unless their builder supplies `Config/Sync.local.xcconfig`.

Configured builds support email links with PKCE, Keychain sessions, refresh, sign-out, deletion, hourly aggregate
uploads and a bounded final upload on quit. The callback is `clepso://auth-callback`. No prompts, replies, paths,
transcripts, raw session identifiers or per-session cost are uploaded. Daily activity, model totals, allowance
aggregates, agent counts, goals and the selected profile fields are defined by `Sources/Sync/SyncPayload.swift`.
Manual allowance snapshots stay local.

The Mac and web client now wire Apple, Google and GitHub OAuth into the same PKCE callback/exchange flow. They expose
only providers explicitly enabled in deployment configuration **after** their console setup has been verified:

```text
CLEPSO_SYNC_PROVIDERS = apple,google,github
```

This adds `ClepsoSyncProviders` to the Mac Info.plist and `providers` to the website's generated public config.
`CLEPSO_ACCOUNTS_PROVIDERS` is the equivalent website-build environment variable. Empty is the default; unknown
provider names are ignored. The client opens sign-in only after a click. Constructing the OAuth URL itself makes no
network request; the provider's single-use callback is bound to this device/browser's verifier. A source build
without an accounts project stays fully offline.

Third-party OAuth apps and branded email are still deployment prerequisites. Wiring the buttons does not create
those credentials or establish that external users can sign in. Supabase migrations and access policies were not
changed in this continuation. The existing web dashboard remains based on the same account and row-level security.
