# Signed in-app updates

Official Mac builds embed **Sparkle 2.10.0**, pinned in `project.yml`. Settings → Updates exposes a manual check,
daily automatic checks and automatic download/installation. Both automatic options start off. A user can opt in
without an account. The alpha feed includes alpha previews; the UI says so explicitly.

The fixed feed is `https://clepso-app.vercel.app/updates/appcast.xml`. Its URL is returned by the updater delegate,
so a stale Sparkle user-default feed override cannot redirect normal checks. No system profile is sent.
The Ed25519 public key is pinned in the app. The private key remains in the login Keychain, account
`com.elvisobi.clepso.updates`. Never export or commit it.

`SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are mandatory. The release pipeline checks Developer ID,
hardened runtime, timestamps and exact executable/entitlement allowlists for the app, widget, helpers and framework.
App and DMG must still be notarized and stapled. Sparkle's normal installation/relaunch/error UI handles updates;
Clepso does not run an arbitrary downloaded shell script or weaken library validation.

After `scripts/release.sh <tag> --with-accounts`, run:

```sh
python3 scripts/prepare-update-feed.py <tag>
```

This checks the DMG checksum/ticket, downloads official tool bytes using a pinned SHA-256, checks the Keychain's
public key against the release, and generates archive/feed signatures using the official tool. It never creates a
new signing key or publishes. Copy the exact generated `update-feed/appcast.xml` (and `.sig` if present) to
`site/updates/` **after** the GitHub release asset is live, then deploy from `site/`. Do not edit signed feed bytes.
Feed publication and a fresh client fetch are separate checks from generating it.

For Homebrew installations, the tap declares `auto_updates true`, the standard cask mechanism for an app with its
own updater. `brew upgrade --cask --greedy obileonardo/clepso/clepso` remains available to users who prefer Homebrew.
Do not rewrite a user's Homebrew receipt to pretend that an in-app upgrade was a cask upgrade.

References: [Sparkle setup and signing](https://sparkle-project.org/documentation/),
[programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
[Homebrew cask semantics](https://docs.brew.sh/Cask-Cookbook#stanza-auto_updates).

The first updater-enabled release cannot automatically upgrade an earlier app that had no updater. Install that
release by DMG/Homebrew once. A real old-to-new installation test requires two correctly signed builds and is
recorded separately from feed/signature validation. Test only on an isolated app/data location before claiming it.
