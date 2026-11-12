# Mobile core — tested source, not a public mobile release

Issue [#27](https://github.com/obileonardo/clepso/issues/27). Current public/installed Mac app remains alpha2/build244. This branch adds iPhone/watchOS targets, separate Mac mobile consent, latest-only owner relay, generation-fenced revocation, account-bound phone cache, aggregate-only Watch handoff and opt-in expected-reset reminders. It does not claim live APNs, production migration, physical installation or TestFlight distribution.

| Check | Observed result |
| --- | --- |
| Strict Mac gates on d167892 | All17 passed;578tests across118suites |
| Relay/reminder/cache/client lifecycle | Synthetic plans, coalescing/retry, suspended writes vs opt-out, account cache binding, demo exclusion and offline revocation/restart passed |
| Local clean migration | Baseline16 and relay35 pgTAP assertions passed after reset of the isolated synthetic project |
| Concurrent database requests | Two connections proved revocation serializes after the older publisher and fences replay |
| Local Auth→RPC→REST | Two synthetic users: own read, other-account isolation, anonymous denial, exact-field validation and off/replay rejection passed; no email sent; fixtures removed |
| Advisors | No security/performance issues on isolated schema |
| Native targets | iPhone+embedded Watch simulator build passed; Apple Development device archive built and both code signatures verified with access to normal trust services |
| CI reproducibility | scripts/build-mobile.sh builds both simulator targets without credentials or a simulator boot; workflow step added |
| Visual states | Actual shared SwiftUI source rendered offscreen at phone/Watch widths, reader-error and old states; account form has a visible email label and compact meters adapt vertically |

[Phone](2026-10-24-mobile-images/phone-dark.png), [Watch width](2026-10-24-mobile-images/watch-dark.png), [reader error](2026-10-24-mobile-images/phone-error.png), [old snapshot](2026-10-24-mobile-images/phone-old.png). Renders use synthetic data and the Mac ImageRenderer. A requested accessibility-size environment in that renderer is not proof of physical iOS/Watch Dynamic Type behavior. Real focus/VoiceOver/device notification behavior remains to be tested.

Backend tests are in backend/supabase/tests/database/mobile-relay.test.sql and backend/tests/mobile_relay_{http,concurrency}.py. They target only the isolated clepso_mobile_test project at localhost55321; API test credentials stay in memory. Development profiles and device IDs are private and are not release artifacts.

Background push, production rollout, physical phone/Watch checks and distribution continue before this mobile task can be marked complete. Reset reminders describe a provider-reported expected time, never confirmed renewed quota; offline phones may miss a cancellation. Social OAuth/domain remain deferred. README visual work remains queued last.
