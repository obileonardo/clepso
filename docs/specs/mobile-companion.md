# iPhone, Watch and expected-reset reminders

Task: [#27](https://github.com/obileonardo/clepso/issues/27). Implementation in progress; not a claim of physical installation or production availability.

The Mac requires a separate, default-off mobile-sharing choice. Existing hourly daily-count uploads do not authorize this relay. The consent explains that provider/window/source/percentage/state and observation/reset timestamps pass through the existing Clepso account. No conversation content, account identifiers, paths, model or session IDs are included in the snapshot. Demo data is excluded.

The server stores the latest typed snapshot only. An authenticated account enables a fresh generation lease; a new lease supersedes other publishers for that account. Publishing and disabling take the same account-row lock. Disabling rotates the lease and deletes the snapshot atomically, so a delayed old request cannot recreate it. There are no direct client table write grants or caller-supplied owner IDs. Owner-only RLS applies to reads, including a server expiry check. Payloads reject unknown fields, arbitrary strings, invalid timestamps, demo data and excessive counts/sizes. Snapshot freshness and retention must be verified before production deployment.

The iPhone signs in independently using existing email PKCE and reads its own relay. Credentials remain in its Keychain. A bounded typed cache is bound to a one-way account digest and loaded only after the signed-in account is known. It permits explicitly old offline readings; signing out clears that cache and sends a clear to the paired Watch. WatchConnectivity transfers only the aggregate envelope, never credentials. Watch refresh asks the phone to refresh; age labels do not manufacture new observations.

Expected-reset reminders are opt-in. Only a current automatic report with a future reported reset qualifies. Manual, missing, stale and reset-expected readings do not create reminders. Reset timing is not proof of renewed quota. Fresh snapshots replace pending requests. Serialized OS replacements ensure an older suspended add finishes before a later opt-out completes. Unchanged plans coalesce; failed writes remain retryable. Unrelated notification IDs are preserved. Offline devices can miss a cancellation; Watch notification mirroring follows system settings.

Background push is a best-effort refresh signal, not a reliable alarm guarantee. It requires separately configured Apple push credentials, provisioning and physical testing. Do not label polling or a simulator build as verified APNs delivery. Do not publish development provisioning profiles or private device identifiers.

Validation separates shared-contract/unit tests, isolated local database/RPC ownership tests, simulator compilation, actual native rendering, physical phone/Watch behavior, and public distribution. Social OAuth and domain purchase remain deferred. README visual work stays queued after the existing implementation tasks.
