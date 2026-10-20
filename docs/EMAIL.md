# Account emails

Clepso accounts sign in with a one-time email link (Supabase Auth, PKCE). This page covers the branded emails: what
exists, how they're built and previewed, and what the hosted project needs before it can send them.

## The emails

| Supabase template | When it's sent | Subject | Link |
|---|---|---|---|
| `magic_link` | Signing in with an address that already has an account | Sign in to Clepso | `{{ .ConfirmationURL }}` |
| `confirmation` | Signing in with a new address (it creates the account) | Confirm your email for Clepso | `{{ .ConfirmationURL }}` |
| `email_change` | `PUT /auth/v1/user` with a new email; sent to both addresses | Confirm your new email for Clepso | `{{ .ConfirmationURL }}` |
| `recovery` | `POST /auth/v1/recover`; no app calls it, but the endpoint is public | Password reset requested for Clepso | none: says Clepso has no passwords, links to `/app/` |

Not customised: `invite` (only an admin with the service key can invite) and `reauthentication` (only for password
changes; neither app asks for it). The opt-in security notifications (`password_changed` and others) are off.

All four share a compact layout using Phosphor's warm-paper light palette and an optional dark palette.
A text wordmark remains visible when images are blocked; headings and paragraphs use email-safe system sans-serif,
with monospace reserved for the brand and small label. One button leads the message. Expiry, same-device guidance,
a short fallback link and the security note follow it. Authentication tokens never appear as visible body text.
There are no remote images, full-URL blocks or facts tables. Text and action contrast meet 4.5:1, including hover.

### Why `{{ .ConfirmationURL }}`

Both apps start sign-in with `POST /auth/v1/otp` carrying a PKCE `code_challenge` and a `redirect_to`:
`<site>/app` on the web (`scripts/site/app.js`), `clepso://auth-callback` on the Mac
(`Sources/Sync/SyncClient.swift`). `{{ .ConfirmationURL }}` is Auth's `/auth/v1/verify` link; opening it redirects to
that `redirect_to` with `?code=…`, which the app that asked exchanges with its stored verifier
(`/token?grant_type=pkce`). A `{{ .TokenHash }}` link would need a page that calls `verifyOtp`, and neither app takes a
typed code, so `{{ .Token }}` is not shown. Because the verifier stays where the request was made, each email says to
open the link on the Mac or browser that asked for it.

## Editing and previewing

The HTML in `backend/supabase/templates/` is generated; edit `scripts/build-email.py`, not the files.

```sh
python3 -I scripts/build-email.py                 # regenerate the templates
python3 -I scripts/build-email.py --preview /tmp/clepso-email   # plus copies with sample values, open in a browser
python3 -I scripts/build-email.py --check         # what CI runs (make ci, "email templates")
```

The check fails when a template is stale, a subject in `config.toml` doesn't match, the HTML is malformed, has an
HTML comment, a script, a web font or an image without alt text, or is over Gmail's 102 KB clipping size. The expiry
text comes from `otp_expiry` in `config.toml`; if you change it there (or on the hosted project), regenerate.

Rules the generator keeps, because mail clients need them: table layout, inline styles (the `<style>` block only adds
phone and dark-mode refinements), no external CSS or fonts, no scripts, no tracking pixels. **No HTML comments**:
Supabase renders templates with Go's `html/template`, which strips them, so Outlook conditional comments never arrive.

The redesigned email needs no image downloads to display the brand. Keep the previous logo URL
`https://clepso-app.vercel.app/assets/email/clepso-logo-email-244.png` available for emails already sent;
`scripts/build-site.py` still publishes it. No website deployment is needed to update the new templates.

### On the local stack

`supabase start` (from `backend/`) loads the templates from `config.toml`; emails land in Mailpit at
http://127.0.0.1:54324. After editing, restart the stack or wait for Auth to reload them.

With Colima, Docker can only bind-mount paths the VM shares (by default not `~/Developer`). If the repo isn't
shared, Docker mounts empty directories instead and every email arrives as an nginx "Index of /email/…" page. Share
the repo's path with the VM (Colima `mounts`) or run Docker Desktop.

## The hosted project

**Updated 20 October 2026:** the hosted accounts project now uses an existing mailbox's custom SMTP service,
sender name **Clepso**, and all four branded subjects/templates above. The templates were read back byte-for-byte
after deployment; unrelated authentication settings were unchanged. The link expiry remains 3600 seconds and the
hosted email limit is 30 per hour. Links use the existing `clepso-app.vercel.app` site. No new domain
purchase or website migration was needed. Local development still uses Mailpit.

The previous built-in service had these restrictions, which explain why changing HTML alone was insufficient:

- **Custom templates need custom SMTP.** Since 3 June 2026, new Free-plan projects that send through Supabase's
  default provider can't change their auth templates; projects with their own SMTP can
  ([changelog](https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier)). This
  project was created after that date.
- **The sender and footer can't be changed without it either.** The sender address and name are SMTP settings
  (`smtp_admin_email`, `smtp_sender_name`) ([SMTP guide](https://supabase.com/docs/guides/auth/auth-smtp)); the
  built-in service sends as "Supabase Auth <noreply@mail.app.supabase.io>" with a "powered by Supabase" footer, and no
  setting for either was found without SMTP.
- **The built-in service only mails the project's team.** "Supabase Auth will refuse to deliver messages to addresses
  that are not part of the project's team", at 2 messages per hour
  ([SMTP guide](https://supabase.com/docs/guides/auth/auth-smtp),
  [rate limits](https://supabase.com/docs/guides/auth/rate-limits)). So nobody outside the team can sign in until
  custom SMTP is set, branding aside. With custom SMTP the limit starts at 30 per hour and can be raised.

### Brand the email without buying a domain

The email's logo, colours, wording, subject and sender display name are separate from buying a Clepso domain.
An existing mailbox can send through its own provider's authenticated SMTP service. The recipient sees
`Clepso <your-existing-address>`; the actual sender address remains honest. Keep the current website, logo URL
and sign-in redirects. There is no need to invent an address on a domain you do not own.

For example, [Namecheap Private Email](https://www.namecheap.com/support/knowledgebase/article.aspx/1179/2175/general-private-email-configuration-for-mail-clients-and-mobile-devices/)
uses `mail.privateemail.com`, port 465 with TLS or 587 with STARTTLS, and the full mailbox address as the username.
Enter its password directly in Supabase's SMTP settings; do not put it in a template, source file or chat.
Set the default sender to that mailbox and the sender name to `Clepso`.

If a new delivery provider is introduced later, follow its sender/domain verification requirements. An existing
owned domain or subdomain can be verified without a new purchase. `*.vercel.app` is only the website host here;
it is not a sender domain whose DNS Clepso controls.

### Providers

The current setup reuses an existing mailbox. A new transactional service is optional, not a prerequisite for
branded email. If sending volume or delivery requirements change, alternatives include
[Resend](https://resend.com/docs/send-with-supabase-smtp),
[Postmark](https://postmarkapp.com/developer/user-guide/send-email-with-smtp) and
[Amazon SES](https://docs.aws.amazon.com/ses/latest/dg/send-email-smtp.html).
Check their current limits and sender verification requirements at that time. Keep link tracking disabled so
the authentication link is not rewritten.

### Applying to the hosted project

1. Generate and validate the templates. Preview at desktop and phone widths, light and dark, including a client
   that ignores embedded styles and blocks remote images.
2. Configure an existing mailbox's SMTP service and sender name, or verify an owned domain with the chosen
   delivery provider. No new domain purchase is required. Keep mail credentials out of source and chat.
3. Apply the four templates and subjects with a narrow Management API update (a scoped personal access token from
   https://supabase.com/dashboard/account/tokens; keep both secrets out of shell history and the repo):

   ```sh
   python3 -I scripts/build-email.py --api-payload > /tmp/clepso-email.json
   # If SMTP is already configured, apply this eight-field payload unchanged.
   # For a new SMTP setup only, add its fields privately, e.g. with python or jq:
   #   "smtp_host": "smtp.resend.com", "smtp_port": "465", "smtp_user": "resend", "smtp_pass": "<resend api key>",
   #   "smtp_admin_email": "signin@mail.<domain>", "smtp_sender_name": "Clepso", "rate_limit_email_sent": 30
   curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
     -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
     --data @/tmp/clepso-email.json
   rm /tmp/clepso-email.json
   ```

   Field names: [email templates guide](https://supabase.com/docs/guides/auth/auth-email-templates) (Management API
   example) and [SMTP guide](https://supabase.com/docs/guides/auth/auth-smtp).
4. Check: `GET` the same endpoint and compare all four subjects and HTML bodies. Confirm unrelated auth settings
   did not change; Supabase may also update its derived template-content maps. Send one authorized test email,
   confirm sender, subject and layout in the inbox, then verify the link in the browser that requested it.
   A successful Auth API response establishes that the send request was accepted, not that the message reached
   the inbox. Mac account sign-in remains a separate test, unavailable in the public Stage A build.

The dashboard (Authentication › Emails) is an alternative to step 3: paste each template file and subject.

Do not push the development `config.toml` to deploy emails: its declared rate limits, redirect list and other
settings may differ from production. CLI 2.119.0's narrow `config diff` showed the subject changes but did not
establish the HTML-body changes. The eight-field Management API payload was used instead, with readback of
both subjects and HTML. Never print a complete hosted auth response; it can contain unrelated secrets.

### After it's live

- Link scanners (corporate mail gateways, some security tools) can open a link before the person does, using it up;
  the person then sees "That link has expired or was already used". If that's reported, Supabase's suggested fix is a
  page of ours that holds the link behind a button
  ([email templates guide](https://supabase.com/docs/guides/auth/auth-email-templates)).
- Browser verification covers Chromium and WebKit: four templates at 700, 390 and 320 px, light/dark appearance,
  stripped embedded CSS, long email addresses, button sizes, visible fallback links and contrast including hover.
  The first live email reached the founder but its inbox recoloured the dark-only layout and blocked the logo;
  the redesign removes that image dependency and excess content. Browser checks are not certification for Gmail,
  Outlook or Apple Mail. Verify the redesigned message in real clients before claiming those results.
