# Diagnosing release-host access

From the implementation checkout, run:

```sh
make doctor
```

This checks Xcode selection, free internal space, GitHub/Apple DNS, Git remote read, GitHub API authentication,
local socket binding, release logging, DiskManagement, visible Developer ID identities, the `clepso-notary`
Keychain profile and temporary DMG creation. It never pushes, signs, publishes, changes permissions, exports
credentials or mounts a disk image. Temporary probe files are removed. A nonzero exit means at least one check
failed; this is separate from the full build/test/release gates.

## CLI and IDE permissions

Sandbox access and command approval are separate. An approved `git push` prefix does not enable network access
for a sandboxed command. In a granular approval policy, `sandbox_approval = false` automatically rejects requests
to run outside the sandbox; the agent cannot turn this into an interactive prompt.

Use `/permissions` in Codex CLI or the permission control beneath the IDE composer. **Ask for approval** permits
requests to cross the sandbox boundary. **Full access** removes the local filesystem/network sandbox for the
trusted release session. Change this through the client; an agent must not launch another process to evade the
current restrictions. Managed policy may limit available choices.

For a new CLI session using workspace boundaries with network access and interactive elevation requests:

```sh
codex --cd "/Volumes/Elvis Obi - Mac Extended/Projects/Clepso/app" \
  --sandbox workspace-write --ask-for-approval on-request \
  -c 'sandbox_workspace_write.network_access=true'
```

Network access alone does not establish Keychain or DiskManagement access. Approve the required native host
commands through the client, then rerun `make doctor`. No passwords or private keys need to be pasted into chat.

References: [Sandbox and permission controls](https://learn.chatgpt.com/docs/sandboxing),
[configuration keys](https://learn.chatgpt.com/docs/config-file/config-reference).

## Interpreting the checks

On 20 October 2026 the restricted session resolved neither GitHub nor Apple, denied local socket binding with
EPERM, denied `/dev/fd` logging redirection, could not use DiskManagement, showed no visible signing identity and
failed `notarytool` while accessing the Keychain. These results are consistent with the known restricted execution
policy. They do **not** prove that the Mac has no certificate or that its system services are broken.

The user config had no explicit sandbox/approval/network override; no requirements file was present at the checked
system/user paths. The exact source of the effective client/runtime policy was not established. Do not infer who
disabled it or edit unrelated system security settings.

After the client grants access, compare the results:

- Git read succeeds but API authentication fails: check GitHub CLI authentication using its normal login flow.
- No Developer ID remains visible: check the login Keychain is unlocked and the Developer ID Application
  certificate has its matching private key. Do not regenerate or export it based only on a sandbox result.
- Keychain access works but the notary profile is missing or Apple rejects it: use `docs/RELEASE.md` and the normal
  credential setup flow. A successful history check validates access without submitting a release.
- DiskManagement/DMG creation still fail: investigate the native host services using the exact errors; don't alter
  app entitlements to solve restrictions imposed on the build process.
- Xcode package products still fail: diagnose local package resolution separately. `project.yml` now generates a
  shared `ClepsoMac` scheme with Release archive configuration. This alone does not prove package resolution works.

Then fetch/reconcile remote main and pass the full CI and signed/notarized release gates in `docs/RELEASE.md`.
