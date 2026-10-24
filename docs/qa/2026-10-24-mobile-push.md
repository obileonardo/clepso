# Mobile background refresh validation

Issue [#27](https://github.com/obileonardo/clepso/issues/27), draft [PR #30](https://github.com/obileonardo/clepso/pull/30). The installed/public Mac remains alpha2/build244. This record distinguishes tested source, server configuration and actual delivery.

| Check | Result |
| --- | --- |
| Final strict Mac quality gates | All17 passed;580 tests/118 suites |
| Native iPhone lifecycle tests | All5 passed on a new disposable iOS simulator; account configuration empty, injected transport/APNs callbacks, simulator removed afterward |
| Native cases | Wrong-account cache discarded; sign-out clears before slow server removal; late registration/failure cannot undo off; unrelated links preserve consent; cached On cannot reacquire a revoked lease |
| Push handler tests | All10 Node tests passed: authenticated owner derivation, bounded requests, readiness, missing configuration, exact destinations, empty Apple payload, cooldown, cleanup and ES256 JWT verification/cache/clock rewind |
| Clean local migration | Baseline16 + relay35 + push23 pgTAP assertions passed; no local advisor issues |
| Local integration | Auth→RPC→REST ownership, revocation, concurrent writes and actual Deno Edge authentication checks passed with disposable synthetic accounts; no emails sent |
| Development signing | Phone archive strict signature, explicit bundle ID, development push entitlement/profile and Info environment agree |
| Owner credentials | Owner supplied both environment-specific P-256 keys; validated and stored directly in server secrets; private material and device IDs excluded from source/artifacts |
| Source secret scanner | Scans tracked plus publishable untracked files, including tracked files matching ignore rules; reports locations only. A synthetic untracked secret was detected without echoing its value. Ignored local runtime credentials are outside publishable source |

The first full gate run found an ignored local Supabase runtime secret in its overly broad scanner. The scanner previously echoed matching lines. Captured local output was redacted, the scanner corrected, and the full17 gates rerun successfully. No production secret was committed or published.

Production dry run selected exactly the two mobile migrations. Existing production advisor warnings concern the pre-existing profile trigger/account-deletion definers and password protection; they are not evidence of mobile delivery. Production migration/function rollout, Apple acceptance, opt-in physical phone/paired Watch behavior and public TestFlight distribution remain pending at this checkpoint. A configuration/readiness success alone must not be reported as a delivered notification.

Reproducible runners: `scripts/test-mobile.py`, `backend/tests/mobile_{relay_http,relay_concurrency,signal_http}.py`, the pgTAP files and `node --test backend/supabase/functions/mobile-signal/handler.test.ts`. Local API runners hard-check the synthetic project's localhost port. Hosted CI compiles phone/Watch and runs actual iPhone lifecycle tests without credentials.
