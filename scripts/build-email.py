"""Builds Clepso's account emails (Supabase Auth templates) from one layout.

    python3 -I scripts/build-email.py              write backend/supabase/templates/*.html
    python3 -I scripts/build-email.py --check      fail if those files are stale, malformed or too big for Gmail
    python3 -I scripts/build-email.py --preview D  also write D/<name>.html with sample values, for screenshots
    python3 -I scripts/build-email.py --api-payload  print the templates as a Management API JSON body (docs/EMAIL.md)

The templates are Go templates filled in by Supabase Auth: {{ .ConfirmationURL }}, {{ .Email }}, {{ .NewEmail }}.
Both apps sign in with PKCE, and {{ .ConfirmationURL }} (Auth's /verify link) is what returns `?code=…` to the
redirect each app asked for: /app on the web, dev.tokone.pulse://auth-callback on the Mac. Neither app takes a typed
code, so {{ .Token }} is never shown. See docs/EMAIL.md.

Email-client rules followed here: tables for layout, every style inline (a <style> block only adds dark-mode and
small-screen refinements that clients without it can skip), no web fonts, no scripts, no tracking, the logo as a hosted
PNG with alt text, and the whole message as real text. The design is dark in both colour schemes; the dark-mode rules
only pin the brand's colours for clients that would re-colour them. No HTML comments: Supabase Auth renders templates
with Go's html/template, which strips them (so Outlook conditional comments can't be used).
"""
import html
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
OUT = repo / "backend" / "supabase" / "templates"
CONFIG = repo / "backend" / "supabase" / "config.toml"
SITE = "https://clepso-app.vercel.app"
LOGO = f"{SITE}/assets/email/clepso-logo-email-244.png"   # site/assets/email/, built by design/brand/pipeline
LOGO_W, LOGO_H = 122, 32                                  # CSS px; the PNG is 2×, one brand p = 2 px
GMAIL_CLIP = 102 * 1024                                   # Gmail hides everything after ~102 KB of HTML

# Site tokens (scripts/site/shell.css). Contrast on SURFACE: TEXT 16.9:1, TEXT2 8.6:1, ACCENT 14.2:1; INK on ACCENT 14.5:1.
BG, SURFACE, LINE, TEXT, TEXT2, ACCENT, INK = "#060907", "#0D1410", "#2C4034", "#EAF7EE", "#93B9A0", "#4DFF8F", "#06130B"
MONO = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Consolas, 'Liberation Mono', 'Courier New', monospace"


def otp_expiry_words():
    """The link lifetime from config.toml ([auth.email] otp_expiry, seconds), in words, so text and config agree."""
    m = re.search(r"^\[auth\.email\]$.*?^otp_expiry\s*=\s*(\d+)", CONFIG.read_text(), re.S | re.M)
    seconds = int(m.group(1)) if m else 3600
    if seconds % 3600 == 0:
        h = seconds // 3600
        return "1 hour" if h == 1 else f"{h} hours"
    minutes = seconds // 60
    return "1 minute" if minutes == 1 else f"{minutes} minutes"


EXPIRES = otp_expiry_words()
ME = "{{ .Email }}"
NEW = "{{ .NewEmail }}"
LINK = "{{ .ConfirmationURL }}"


def strong(text):
    return f'<strong style="color:{TEXT};font-weight:700;">{text}</strong>'


SAME_DEVICE = "the Mac or browser that asked for it"

# One entry per Supabase template. `button` is (label, href) or None; `facts` are label/value rows; `fallback` says
# where to paste the plain link (False: no link to paste).
EMAILS = {
    "magic_link": dict(
        subject="Sign in to Clepso",
        tag="Sign-in link",
        preheader=f"Your one-time link to sign in to Clepso. It works once and expires in {EXPIRES}.",
        title="Sign in to Clepso",
        body=[f"Use the button below to sign in as {strong(ME)}."],
        button=("Sign in", LINK),
        facts=[("Expires", f"in {EXPIRES}"), ("Works", "once"), ("Open on", SAME_DEVICE)],
        fallback=SAME_DEVICE,
        ignore="Didn't ask to sign in? Ignore this email. Nothing happens, and nobody gets in with it.",
        reason=f"Sent because someone asked to sign in to Clepso as {ME}.",
    ),
    "confirmation": dict(
        subject="Confirm your email for Clepso",
        tag="New account",
        preheader=f"One step left: confirm your email to create your Clepso account. The link expires in {EXPIRES}.",
        title="Confirm your email",
        body=[f"Welcome to Clepso. Confirm {strong(ME)} to create your account. You'll be signed in straight away."],
        button=("Confirm and sign in", LINK),
        facts=[("Expires", f"in {EXPIRES}"), ("Works", "once"), ("Open on", SAME_DEVICE)],
        fallback=SAME_DEVICE,
        ignore="Didn't ask for this? Ignore this email. Without the link, the account is never confirmed.",
        reason=f"Sent because {ME} was used to sign in to Clepso for the first time.",
    ),
    "email_change": dict(
        subject="Confirm your new email for Clepso",
        tag="Email change",
        preheader=f"Confirm changing your Clepso account's email to {NEW}.",
        title="Confirm your new email",
        body=[f"Your Clepso account's email is changing from {strong(ME)} to {strong(NEW)}.",
              "Both addresses get this email. The change happens once the link in each one is opened."],
        button=("Confirm the change", LINK),
        facts=[("Expires", f"in {EXPIRES}"), ("Works", "once"), ("Needs", "a click from both addresses")],
        fallback="your browser",
        ignore=f"Didn't ask for this? Ignore this email. The account keeps {ME} unless both addresses confirm.",
        reason=f"Sent because an email change was requested for the Clepso account {ME}.",
    ),
    "recovery": dict(
        subject="Password reset requested for Clepso",
        tag="Account notice",
        preheader="Clepso accounts have no password. To sign in, ask for a one-time link.",
        title="There's no password to reset",
        body=[f"Someone asked to reset the password for the Clepso account {strong(ME)}. Clepso accounts don't have "
              "passwords: you sign in with a one-time link sent to your email.",
              "To sign in, open Clepso on your Mac (Clepso › Account), or enter your email on the web dashboard."],
        button=("Open the web dashboard", f"{SITE}/app/"),
        facts=[],
        fallback=False,
        ignore="Didn't ask for this? Ignore this email. Nothing on your account has changed.",
        reason=f"Sent because a password reset was requested for {ME}.",
    ),
}

HEAD = f"""<!DOCTYPE html>
<html lang="en" dir="ltr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="format-detection" content="telephone=no, date=no, address=no, email=no, url=no">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>[[subject]]</title>
<style>
  :root {{ color-scheme: light dark; supported-color-schemes: light dark; }}
  body {{ margin: 0 !important; padding: 0 !important; width: 100% !important; background-color: {BG} !important; }}
  a[x-apple-data-detectors] {{ color: inherit !important; text-decoration: none !important; }}
  .cl-text a {{ color: {ACCENT}; }}
  @media (prefers-color-scheme: dark) {{
    .cl-bg {{ background-color: {BG} !important; }}
    .cl-card {{ background-color: {SURFACE} !important; }}
    .cl-btn {{ background-color: {ACCENT} !important; }}
    .cl-btn a {{ color: {INK} !important; }}
  }}
  [data-ogsb] .cl-btn {{ background-color: {ACCENT} !important; }}
  [data-ogsc] .cl-btn a {{ color: {INK} !important; }}
  @media only screen and (max-width: 520px) {{
    .cl-pad {{ padding-left: 22px !important; padding-right: 22px !important; }}
    .cl-outer {{ padding-left: 12px !important; padding-right: 12px !important; padding-top: 20px !important; }}
    .cl-title {{ font-size: 23px !important; line-height: 30px !important; }}
    .cl-btn-table, .cl-btn-cell {{ width: 100% !important; }}
    .cl-btn a {{ display: block !important; text-align: center !important; }}
    .cl-fact-label {{ width: 74px !important; }}
  }}
</style>
</head>
"""

BODY = f"""<body class="cl-bg" style="margin:0;padding:0;width:100%;background-color:{BG};">
<div style="display:none;max-height:0;max-width:0;overflow:hidden;opacity:0;mso-hide:all;font-size:1px;line-height:1px;color:{BG};">[[preheader]]&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;</div>
<table role="presentation" class="cl-bg" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="{BG}" style="width:100%;background-color:{BG};border-collapse:collapse;">
<tr><td class="cl-outer" align="center" style="padding:40px 16px 48px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;border-collapse:collapse;">
<tr><td style="padding:0 2px 20px 2px;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;"><tr>
    <td valign="middle" style="padding:0;"><a href="{SITE}/" style="text-decoration:none;"><img src="{LOGO}" width="{LOGO_W}" height="{LOGO_H}" alt="Clepso" style="display:block;width:{LOGO_W}px;height:{LOGO_H}px;border:0;outline:none;text-decoration:none;color:{ACCENT};font-family:{MONO};font-size:20px;font-weight:700;line-height:{LOGO_H}px;background-color:{BG};"></a></td>
    <td valign="middle" align="right" style="padding:0;font-family:{MONO};font-size:11px;line-height:16px;letter-spacing:1.6px;text-transform:uppercase;color:{TEXT2};">[[tag]]</td>
  </tr></table>
</td></tr>
<tr><td class="cl-card cl-pad" bgcolor="{SURFACE}" style="background-color:{SURFACE};border:1px solid {LINE};border-top:2px solid {ACCENT};padding:36px 40px 32px 40px;">
  <h1 class="cl-title" style="margin:0 0 16px 0;font-family:{MONO};font-size:26px;line-height:34px;font-weight:700;letter-spacing:-0.2px;color:{TEXT};">[[title]]</h1>
[[body]]
[[button]]
[[facts]]
[[fallback]]
  <p style="margin:28px 0 0 0;padding-top:20px;border-top:1px solid {LINE};font-family:{MONO};font-size:13px;line-height:21px;color:{TEXT2};">[[ignore]]</p>
</td></tr>
<tr><td style="padding:24px 2px 0 2px;font-family:{MONO};font-size:12px;line-height:19px;color:{TEXT2};">
  <p style="margin:0 0 8px 0;color:{TEXT2};"><strong style="color:{TEXT};font-weight:700;letter-spacing:1.6px;">CLEPSO</strong> &middot; how much of your AI coding agent's limits you have left, in your Mac's menu bar.</p>
  <p style="margin:0 0 8px 0;color:{TEXT2};">[[reason]] Clepso only emails you about your account.</p>
  <p style="margin:0;"><a href="{SITE}/" style="color:{ACCENT};text-decoration:underline;">clepso-app.vercel.app</a> <span style="color:{LINE};">&nbsp;/&nbsp;</span> <a href="{SITE}/privacy/" style="color:{ACCENT};text-decoration:underline;">Privacy</a></p>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>
"""


def para(text, first):
    top = "0" if first else "14px"
    return (f'  <p class="cl-text" style="margin:{top} 0 0 0;font-family:{MONO};font-size:15px;line-height:24px;'
            f'color:{TEXT2};">{text}</p>')


def button(label, href):
    return f"""  <table role="presentation" class="cl-btn-table" cellspacing="0" cellpadding="0" border="0" style="margin:28px 0 0 0;border-collapse:collapse;"><tr>
    <td class="cl-btn cl-btn-cell" bgcolor="{ACCENT}" style="background-color:{ACCENT};border-radius:0;mso-padding-alt:15px 26px;">
      <a href="{href}" target="_blank" style="display:inline-block;padding:15px 26px;font-family:{MONO};font-size:14px;line-height:18px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:{INK};text-decoration:none;">{html.escape(label)}&nbsp;&rarr;</a>
    </td></tr></table>"""


def facts(rows):
    if not rows:
        return ""
    cells = []
    for i, (label, value) in enumerate(rows):
        rule = f"border-top:1px solid {LINE};" if i else ""
        cells.append(
            f'    <tr><td class="cl-fact-label" width="96" valign="top" style="width:96px;padding:9px 12px 9px 0;{rule}'
            f'font-family:{MONO};font-size:11px;line-height:18px;letter-spacing:1.4px;text-transform:uppercase;color:{TEXT2};">'
            f'{html.escape(label)}</td>'
            f'<td valign="top" style="padding:9px 0;{rule}font-family:{MONO};font-size:13px;line-height:18px;color:{TEXT};">'
            f'{html.escape(value)}</td></tr>')
    return (f'  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:28px 0 0 0;'
            f'border-collapse:collapse;border-top:1px solid {LINE};border-bottom:1px solid {LINE};">\n'
            + "\n".join(cells) + "\n  </table>")


def fallback(where):
    return (f'  <p style="margin:24px 0 8px 0;font-family:{MONO};font-size:13px;line-height:20px;color:{TEXT2};">'
            f'Button not working? Paste this address into {where}:</p>\n'
            f'  <p style="margin:0;padding:10px 12px;background-color:{BG};border:1px solid {LINE};font-family:{MONO};'
            f'font-size:12px;line-height:18px;word-break:break-all;overflow-wrap:anywhere;">'
            f'<a href="{LINK}" target="_blank" style="color:{ACCENT};text-decoration:underline;word-break:break-all;">{LINK}</a></p>')


def render(e):
    out = (HEAD + BODY)
    parts = {
        "subject": html.escape(e["subject"]),
        "preheader": e["preheader"],
        "tag": html.escape(e["tag"]),
        "title": html.escape(e["title"]),
        "body": "\n".join(para(t, i == 0) for i, t in enumerate(e["body"])),
        "button": button(*e["button"]) if e["button"] else "",
        "facts": facts(e["facts"]),
        "fallback": fallback(e["fallback"]) if e["fallback"] else "",
        "ignore": e["ignore"],
        "reason": e["reason"],
    }
    for k, v in parts.items():
        out = out.replace(f"[[{k}]]", v)
    out = re.sub(r"\n(\s*\n)+", "\n", out)       # drop the blank lines left by empty parts
    assert "[[" not in out
    return out


class Checker(HTMLParser):
    """Well-formedness for the elements we write: every opened tag closed, in order."""
    VOID = {"meta", "img", "br", "hr", "link", "input"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack, self.errors = [], []

    def handle_starttag(self, tag, attrs):
        if tag not in self.VOID:
            self.stack.append((tag, self.getpos()))

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1][0] != tag:
            self.errors.append(f"</{tag}> at {self.getpos()} closes {self.stack[-1] if self.stack else 'nothing'}")
            return
        self.stack.pop()


def problems(name, text, subject):
    errs = []
    c = Checker()
    c.feed(text)
    c.close()
    errs += [f"{name}: {m}" for m in c.errors]
    errs += [f"{name}: <{t}> at {p} never closed" for t, p in c.stack]
    if len(text.encode()) > GMAIL_CLIP:
        errs.append(f"{name}: {len(text.encode())} bytes, Gmail clips above {GMAIL_CLIP}")
    for var in re.findall(r"{{\s*([^}]*?)\s*}}", text):
        if var not in (".ConfirmationURL", ".Email", ".NewEmail"):
            errs.append(f"{name}: unexpected template variable {var}")
    for img in re.findall(r"<img\b[^>]*>", text):
        if 'alt="' not in img:
            errs.append(f"{name}: image without alt text")
    for table in re.findall(r"<table\b[^>]*>", text):
        if 'role="presentation"' not in table:
            errs.append(f"{name}: layout table without role=presentation")
    if "<!--" in text or "/*" in text:
        errs.append(f"{name}: comments (Go's html/template strips them before sending)")
    if re.search(r"<script|@import|<link\b|@font-face", text, re.I):
        errs.append(f"{name}: scripts, external CSS or web fonts")
    if f"<title>{html.escape(subject)}</title>" not in text:
        errs.append(f"{name}: <title> does not match the subject")
    return errs


def subjects_in_config():
    text = CONFIG.read_text()
    found = {}
    for name in EMAILS:
        m = re.search(rf'^\[auth\.email\.template\.{name}\]\nsubject = "([^"]*)"\ncontent_path = "([^"]*)"', text, re.M)
        found[name] = m.groups() if m else None
    return found


def api_payload():
    """The committed templates as a Management API body (PATCH /v1/projects/{ref}/config/auth), written to stdout."""
    body = {}
    for name, e in EMAILS.items():
        body[f"mailer_subjects_{name}"] = e["subject"]
        body[f"mailer_templates_{name}_content"] = (OUT / f"{name}.html").read_text()
    json.dump(body, sys.stdout, indent=1)
    return 0


def main(argv):
    if "--api-payload" in argv:
        return api_payload()
    check = "--check" in argv
    preview = Path(argv[argv.index("--preview") + 1]) if "--preview" in argv else None
    errs = []
    configured = subjects_in_config()
    for name, e in EMAILS.items():
        text = render(e)
        path = OUT / f"{name}.html"
        errs += problems(name, text, e["subject"])
        want = (e["subject"], f"./supabase/templates/{name}.html")
        if configured[name] != want:
            errs.append(f"{name}: config.toml needs [auth.email.template.{name}] subject = \"{want[0]}\", "
                        f"content_path = \"{want[1]}\"")
        if check:
            if not path.exists() or path.read_text() != text:
                errs.append(f"{name}: {path.relative_to(repo)} is stale; run python3 -I scripts/build-email.py")
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        if preview:
            preview.mkdir(parents=True, exist_ok=True)
            sample = (text.replace(LINK, "http://127.0.0.1:54321/auth/v1/verify?token=pkce_3f9c1d8e7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f&amp;type=magiclink&amp;redirect_to=http://127.0.0.1:3000/app")
                      .replace(ME, "ada@example.com").replace(NEW, "ada.lovelace@example.org")
                      .replace(LOGO, (repo / "site/assets/email/clepso-logo-email-244.png").as_uri()))
            (preview / f"{name}.html").write_text(sample)
        print(f"{name}: {len(text.encode())} bytes, subject \"{e['subject']}\"")
    for m in errs:
        print("ERROR", m)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
