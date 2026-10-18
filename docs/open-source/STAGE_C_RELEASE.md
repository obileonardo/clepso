# Stage C: release validation and go-public record

Date: 18 Oct 2026. Decision: **go**, by the maintainer's explicit instruction. The repository was made public the same day.

## Checks run before the visibility change

| Check | Result |
|---|---|
| Secret scan of the full history (`gitleaks git`, 114 commits on `main`; plus a pattern scan of every added line on all refs) | 2 findings, both accepted: a Supabase **publishable** key in an early `SyncConfig.swift` (commit 8bb4720, removed in c8826ff) and a fake AWS key used as a redaction canary in `FrameBuilderTests.swift` |
| Publishable key | Public by design (Supabase anon/publishable role, guarded by row-level security); the same key is already served to every visitor of the web dashboard. No `sb_secret_` key, service-role key or JWT anywhere in history |
| Other secrets: private keys, GitHub/AWS/OpenAI/Anthropic/Resend/Vercel tokens, passwords | None (the only `secret =` line reads an environment variable) |
| Personal data: home-folder paths, personal email addresses | None. The real-capture fixture (C01) is scrubbed: no session ids, no real paths |
| Tracked files that must stay local (`.env*`, `*.local.xcconfig`, `.vercel/`, Supabase `.temp/`, signing material) | None tracked |
| Remote refs | `main` only; no tags |
| Licence and policies | MIT `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `TRADEMARKS.md`, `THIRD_PARTY_NOTICES.md` present |

## Settings applied

- About: description, homepage (https://clepso-app.vercel.app) and topics.
- Dependabot alerts and security updates on.
- After going public: secret scanning and push protection on; private vulnerability reporting on.
- Ruleset "Protect main": no force-pushes, no deletion of the default branch. Direct pushes and merges are unchanged.

## Afterwards

GitHub's own secret scanning reported 0 alerts after the switch. Collaborators: the maintainer (admin) and ChimeXXD (write).
