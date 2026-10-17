## What and why

<!-- What does this change, and why? Link the issue it resolves, e.g. "Closes #12". -->

## How it was verified

<!-- Paste the `make ci` summary. If you could not run a gate (for example "app bundle" without the signing identity),
say which and why. Describe any manual checks, using a throwaway -PulseHome / -PulseDataDirectory. -->

```
make ci summary here
```

- [ ] Tests added or updated for every behaviour change (bug fixes include a test that fails without the fix)
- [ ] No test reads or writes the real `~/.claude`, `~/.codex`, Keychain or network

## Privacy and security

- [ ] This change does **not** widen the helper's field allowlist, read a new file or source, or change what leaves the Mac
- [ ] If it does, it was discussed in an issue first, and the canary tests cover the new field or source
- [ ] No secrets, personal data, real captures or unscrubbed fixtures are included
- [ ] Changes to `~/.claude/settings.json` handling keep backup, compare-and-swap and exact restore

## User-facing changes

- [ ] Screenshots attached for visual changes (light and dark, using demo data)
- [ ] Text lives in `Copy.swift` and says only what the source reports
- [ ] README or other docs updated where behaviour, commands or requirements changed

## Breaking changes

<!-- Database migrations, settings format, frame protocol version, CLI flags. Write "None" if there are none. -->
