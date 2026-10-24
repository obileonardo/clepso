# Apple push setup for Clepso

The phone app and server use a content-free background refresh signal. No quota values, account IDs, prompts or session IDs go to Apple. Delivery is best effort, with a server limit of three signals per account per hour. Expected-reset reminders run locally on the phone. [Apple background update guidance](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).

The signed phone app uses team **DD8UY75RZT** and topic/bundle ID **com.elvisobi.clepso.mobile**. Development archives use Sandbox; TestFlight/App Store exports use Production. The exported app's aps-environment entitlement and ClepsoPushEnvironment Info value must agree before distribution. A successful archive does not prove delivery.

## Owner input required

Apple requires an **Account Holder or Admin** to create a private key. Private keys can only be downloaded once. Confirm configuration through the authenticated readiness check; never list private values in a report. [Apple key creation instructions](https://developer.apple.com/help/account/keys/create-a-private-key/).

1. Open Apple Developer → Certificates, Identifiers & Profiles → Keys.
2. Create **Clepso Sandbox**. Enable Apple Push Notification service; configure **Sandbox**, **Topic Specific**, topic **com.elvisobi.clepso.mobile**.
3. Create **Clepso Production** with **Production**, **Topic Specific**, the same topic.
4. Download both .p8 files and keep them securely. Keep the original filename containing the key ID; the helper accepts AuthKey_<KeyID>.p8, Apple Auth Key <KeyID>.p8 and Auth Key <KeyID>.p8.
5. Give the maintainer only their **local file paths**, never their contents or an Apple password. The reviewed setup helper validates the keys locally and sends them directly to this project's Supabase server secrets after an explicit apply step. They are never app configuration, GitHub assets or client-side keys.

If the topic is absent, confirm that the explicit iOS identifier has Push Notifications enabled. The project requests that capability through Xcode automatic provisioning. Existing legacy keys can have different environment scope; do not assume one new key covers both environments. [Apple APNs key scope](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns).

## Server values

| Secret name | Value |
| --- | --- |
| APNS_TEAM_ID | DD8UY75RZT |
| APNS_SANDBOX_KEY_ID | Sandbox key's 10-character ID |
| APNS_SANDBOX_KEY_P8 | Sandbox private key, server only |
| APNS_PRODUCTION_KEY_ID | Production key's 10-character ID |
| APNS_PRODUCTION_KEY_P8 | Production private key, server only |

Default setup is a dry run:

~~~sh
python3 scripts/configure-mobile-push.py --project-ref YOUR_PROJECT_REF \
  --team-id DD8UY75RZT --sandbox-key /private/path/AuthKey_ABCDEFGHIJ.p8 \
  --production-key /private/path/AuthKey_KLMNOPQRST.p8
~~~

Add --apply only for the reviewed target. Temporary secret input is owner-readable and removed afterward. The helper never prints keys, tokens or secret CLI output. Redeploy mobile-signal after updating secrets to load the new environment and recreate its HTTP/2 connection pools.

User-facing function JWT verification stays **on**. The handler independently checks the caller with Auth and derives the owner; service RPCs never accept an owner from the client. [Supabase function authentication](https://supabase.com/docs/guides/functions/auth).

## Remaining verification

After configuration: verify both environment readiness checks, user-controlled phone sign-in/sharing, actual Apple acceptance, foreground/background refresh, local expected-reset reminders, offline opt-out, account deletion and paired Watch behavior. Do not equate HTTP acceptance with device delivery. Public mobile distribution/TestFlight still needs a reviewed export and App Store Connect setup.

## Production package

Run `python3 scripts/export-mobile.py --build NEXT_BUILD --team-id YOUR_TEAM_ID` after preparing signing/account configuration. It archives with the Production Info setting, exports with App Store Connect automatic signing, verifies the exported Production entitlement, strict signatures and both privacy manifests, and records a SHA-256 receipt. It never uploads or accepts agreements. Do not install the intermediate development-signed archive: its Info setting intentionally anticipates the final export. Build a separate Development archive for direct device installation. An exported IPA is not a public installation link; TestFlight still requires an App Store Connect record, upload/processing and any required review.
