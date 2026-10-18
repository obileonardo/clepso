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

All four share one design: the site's dark palette (ink `#060907`, surface `#0D1410`, phosphor `#4DFF8F`), the
logo as a hosted PNG with alt text "Clepso", system monospace text, a square phosphor button, a facts table (expiry,
single use, same device), the plain link as a fallback, an "ignore this" line and a footer with the reason it was
sent. Every text colour is at least 8.6:1 against its background.

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

The logo is `site/assets/email/clepso-logo-email-244.png` (122 × 32 at 2×), made by `design/brand/pipeline`
(`logo.write_email_logo`) and copied by `scripts/build-site.py`. Emails link it at
`https://clepso-app.vercel.app/assets/email/clepso-logo-email-244.png`, so it must be deployed before the templates
go live, and the name must not change while old emails exist.

### On the local stack

`supabase start` (from `backend/`) loads the templates from `config.toml`; emails land in Mailpit at
http://127.0.0.1:54324. After editing, restart the stack or wait for Auth to reload them.

With Colima, Docker can only bind-mount paths the VM shares (by default not `~/Developer`). If the repo isn't
shared, Docker mounts empty directories instead and every email arrives as an nginx "Index of /email/…" page. Share
the repo's path with the VM (Colima `mounts`) or run Docker Desktop.

## The hosted project

What the accounts project has today: the Free plan, Supabase's built-in email service, the default templates and
subjects, `otp_expiry` 3600, email rate limit 2 per hour.

What that means:

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

### Sender domain

Every provider needs SPF and DKIM records (DMARC recommended) on a domain you control. `*.vercel.app` can't be used:
nobody can add DNS records under it. Options:

1. **Register a Clepso domain** (e.g. `clepso.dev` or `clepso.app`, roughly $12–15 a year at Cloudflare Registrar,
   which sells at cost; price not confirmed on the registry list) and send from a subdomain such as
   `mail.clepso.dev`. The same domain can later host the site. Note: Clepso is a working name with no trademark
   search yet (`TRADEMARKS.md`).
2. **Use a subdomain of a domain you already own**, e.g. `clepso.<your-domain>`. No purchase; the sender then shows
   that domain. Switching later is two settings and new DNS records.

### Providers

| | Resend | Postmark | Amazon SES |
|---|---|---|---|
| Free | 3,000 a month, 100 a day, 3 domains | 100 a month | none beyond AWS credits |
| Paid from | $20 a month (50,000) | $15 a month (10,000) | $0.10 per 1,000 |
| Setup | API key is the SMTP password; no approval step | manual account approval (usually < 24 h on weekdays) | IAM SMTP credentials; sandbox until production access (up to 96 h) |
| DNS | DKIM TXT, SPF TXT, MX on the bounce subdomain | DKIM TXT, Return-Path CNAME | 3 DKIM CNAMEs; MX + SPF TXT for a custom MAIL FROM |
| Tracking | off by default | off by default | not checked |

Sources: [Resend pricing](https://resend.com/pricing), [Resend with Supabase](https://resend.com/docs/send-with-supabase-smtp),
[Resend domains](https://resend.com/docs/add-a-domain), [Postmark pricing](https://postmarkapp.com/pricing),
[Postmark SMTP](https://postmarkapp.com/developer/user-guide/send-email-with-smtp),
[Postmark approval](https://postmarkapp.com/support/article/1084-how-does-the-account-approval-process-work),
[SES pricing](https://aws.amazon.com/ses/pricing/), [SES SMTP credentials](https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html),
[SES production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html).

**Recommendation: Resend.** Sign-in mail is a few emails a day; Resend's free tier covers it with room to spare, needs
no approval wait, has a Supabase guide, and leaves link tracking off (tracking rewrites links; Supabase advises turning it off with custom SMTP:
[production checklist](https://supabase.com/docs/guides/platform/going-into-prod)). Postmark is the fallback if deliverability ever becomes a problem.

### Applying (owner's go-ahead required: these change the live project)

1. Deploy the site so the logo URL above answers 200.
2. Pick the domain, verify it in Resend (add the DNS records it shows), add DMARC (`_dmarc` TXT,
   `v=DMARC1; p=none; rua=mailto:…` to start), and create an API key restricted to sending.
3. Set SMTP and the templates in one call with the Management API (a personal access token from
   https://supabase.com/dashboard/account/tokens; keep both secrets out of shell history and the repo):

   ```sh
   python3 -I scripts/build-email.py --api-payload > /tmp/clepso-email.json
   # add the SMTP fields to the same JSON, e.g. with python or jq:
   #   "smtp_host": "smtp.resend.com", "smtp_port": "465", "smtp_user": "resend", "smtp_pass": "<resend api key>",
   #   "smtp_admin_email": "signin@mail.<domain>", "smtp_sender_name": "Clepso", "rate_limit_email_sent": 30
   curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
     -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
     --data @/tmp/clepso-email.json
   rm /tmp/clepso-email.json
   ```

   Field names: [email templates guide](https://supabase.com/docs/guides/auth/auth-email-templates) (Management API
   example) and [SMTP guide](https://supabase.com/docs/guides/auth/auth-smtp).
4. Check: `GET` the same endpoint and compare the subjects; sign in on the web dashboard with an address outside the
   team; confirm sender, subject, logo and that the link signs you in; then the same from the Mac app.

The dashboard (Authentication › Emails) is an alternative to step 3: paste each template file and subject.

Avoid `supabase config push` for this. It pushes the whole local `config.toml` (rate limits, redirect list, OTP
settings…), not just the emails, and would reset anything set on the hosted side to what the file says (e.g.
`email_sent = 2`) ([CLI reference](https://supabase.com/docs/reference/cli/supabase-config-push)). Per the CLI 2.108.0
release notes it reads templates from `content_path` only from that version on.

### After it's live

- Link scanners (corporate mail gateways, some security tools) can open a link before the person does, using it up;
  the person then sees "That link has expired or was already used". If that's reported, Supabase's suggested fix is a
  page of ours that holds the link behind a button
  ([email templates guide](https://supabase.com/docs/guides/auth/auth-email-templates)).
- Not verified in real clients: the design is tested in WebKit (Apple Mail's engine) at 700 and 390 px in light and
  dark appearance. Gmail's iOS app may invert the dark design into a light one (readable, less on-brand), and classic
  Outlook for Windows ignores `max-width` and may fall back to a serif font. Check those once SMTP works.
