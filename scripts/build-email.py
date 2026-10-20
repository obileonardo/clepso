"""Builds Clepso's account emails (Supabase Auth templates) from one layout.

    python3 -I scripts/build-email.py              write backend/supabase/templates/*.html
    python3 -I scripts/build-email.py --check      fail if those files are stale, malformed or too big for Gmail
    python3 -I scripts/build-email.py --preview D  also write D/<name>.html with sample values, for screenshots
    python3 -I scripts/build-email.py --api-payload  print the templates as a Management API JSON body (docs/EMAIL.md)

The templates are Go templates filled in by Supabase Auth: {{ .ConfirmationURL }}, {{ .Email }}, {{ .NewEmail }}.
Both apps sign in with PKCE, and {{ .ConfirmationURL }} (Auth's /verify link) is what returns `?code=…` to the
redirect each app asked for: /app on the web, clepso://auth-callback on the Mac. Neither app takes a typed
code, so {{ .Token }} is never shown. See docs/EMAIL.md.

Email-client rules: table layout and inline styles; dark Protocol palette; one flattened hero image with the
Clepso logo already composited over the artwork. The optional hosted display font has a monospace fallback;
all instructions, actions and fallback links remain real text when images/fonts are blocked. No scripts,
tracking or HTML comments (Supabase's Go html/template strips comments, including Outlook conditionals).
"""
import html
import json
import re
import sys
import struct
import shutil
from html.parser import HTMLParser
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
OUT = repo / "backend" / "supabase" / "templates"
CONFIG = repo / "backend" / "supabase" / "config.toml"
SITE = "https://clepso-app.vercel.app"
GMAIL_CLIP = 102 * 1024                                   # Gmail hides everything after ~102 KB of HTML

# Founder-selected Protocol: same layout and palette as the approved preview.
BG, SURFACE, LINE, TEXT, TEXT2, ACCENT, INK = "#252525", "#131313", "#373D38", "#FFFFFF", "#B9C1BB", "#4DFF8F", "#0C1710"
MONO = "'Clepso Pixel', 'Courier New', monospace"
SANS = "Arial, Helvetica, sans-serif"
HERO_FILE = "clepso-protocol-hero-v1.png"
HERO = f"{SITE}/assets/email/{HERO_FILE}"
FONT = f"{SITE}/assets/email/ClepsoPixel-Regular.woff2"
FONT_FACE = f"@font-face {{ font-family: 'Clepso Pixel'; src: url('{FONT}') format('woff2'); font-weight: 400; font-style: normal; font-display: swap; }}"


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
    return f'<strong style="color:{TEXT};font-weight:600;overflow-wrap:anywhere;word-break:break-word;">{text}</strong>'


SAME_DEVICE = "the Mac or browser that asked for it"

# One entry per Supabase template. `button` is (label, href) or None; `facts` are label/value rows; `fallback` says
# where to paste the plain link (False: no link to paste).
EMAILS = {
    "magic_link": dict(
        subject="Sign in to Clepso",
        tag="Sign-in link",
        preheader=f"Your one-time link to sign in to Clepso. It works once and expires in {EXPIRES}.",
        title="Sign in to Clepso",
        body=["Use this one-time link to sign in to your account."],
        button=("Sign in to Clepso", LINK),
        facts=[("Expires", f"in {EXPIRES}"), ("Works", "once"), ("Open on", SAME_DEVICE)],
        fallback=SAME_DEVICE,
        ignore="Didn't request this? You can safely ignore this email.",
        reason=f"Sent because someone asked to sign in to Clepso as {ME}.",
    ),
    "confirmation": dict(
        subject="Confirm your email for Clepso",
        tag="New account",
        preheader=f"One step left: confirm your email to create your Clepso account. The link expires in {EXPIRES}.",
        title="Confirm your email",
        body=["Welcome to Clepso. Confirm your email to create your account and sign in."],
        button=("Confirm and sign in", LINK),
        facts=[("Expires", f"in {EXPIRES}"), ("Works", "once"), ("Open on", SAME_DEVICE)],
        fallback=SAME_DEVICE,
        ignore="Didn't request this? You can safely ignore this email.",
        reason=f"Sent because {ME} was used to sign in to Clepso for the first time.",
    ),
    "email_change": dict(
        subject="Confirm your new email for Clepso",
        tag="Email change",
        preheader=f"Confirm changing your Clepso account's email to {NEW}.",
        title="Confirm your new email",
        body=[f"Confirm changing your account's email from {strong(ME)} to {strong(NEW)}.",
              "Open the confirmation link sent to each address to finish the change."],
        button=("Confirm the change", LINK),
        facts=[("Expires", f"in {EXPIRES}"), ("Works", "once")],
        fallback="your browser",
        ignore=f"Didn't ask for this? Ignore this email. The account keeps {ME} unless both addresses confirm.",
        reason=f"Sent because an email change was requested for the Clepso account {ME}.",
    ),
    "recovery": dict(
        subject="Password reset requested for Clepso",
        tag="Account notice",
        preheader="Clepso accounts have no password. To sign in, ask for a one-time link.",
        title="There's no password to reset",
        body=["Clepso uses one-time email links instead of passwords. To sign in, open the dashboard and request a new link."],
        button=("Open the web dashboard", f"{SITE}/app/"),
        facts=[],
        fallback=False,
        ignore="Didn't request this? You can safely ignore this email. Your account is unchanged.",
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
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>[[subject]]</title>
<style>
  {FONT_FACE}
  :root {{ color-scheme: dark; supported-color-schemes: dark; }}
  body {{ margin: 0 !important; padding: 0 !important; width: 100% !important; }}
  a[x-apple-data-detectors] {{ color: inherit !important; text-decoration: none !important; }}
  .cl-text a[x-apple-data-detectors], .cl-text a[href^="mailto:"], .cl-muted a[x-apple-data-detectors] {{ color: inherit !important; text-decoration: none !important; }}
  .cl-button:hover {{ background-color: #8DE9A7 !important; }}
  a:focus-visible {{ outline: 2px solid {ACCENT}; outline-offset: 4px; }}
  @media (prefers-color-scheme: dark) {{
    .cl-bg {{ background-color: {BG} !important; }}
    .cl-card {{ background-color: {SURFACE} !important; border-color: {LINE} !important; }}
    .cl-title, .cl-text strong, .cl-link {{ color: {TEXT} !important; }}
    .cl-text, .cl-muted {{ color: {TEXT2} !important; }}
    .cl-button {{ background-color: {ACCENT} !important; }}
    .cl-button a {{ color: {INK} !important; }}
    .cl-button:hover {{ background-color: #8DE9A7 !important; }}
  }}
  @media only screen and (max-width: 520px) {{
    .cl-pad {{ padding-left: 28px !important; padding-right: 28px !important; }}
    .cl-outer {{ padding: 20px 12px !important; }}
    .cl-title {{ font-size: 32px !important; line-height: 40px !important; }}
    .cl-button-table {{ width: 100% !important; }}
    .cl-button a {{ display: block !important; text-align: center !important; padding-left: 12px !important; padding-right: 12px !important; }}
  }}
</style>
</head>
"""

BODY = f"""<body class="cl-bg" style="margin:0;padding:0;width:100%;background-color:{BG};">
<div style="display:none;max-height:0;max-width:0;overflow:hidden;opacity:0;mso-hide:all;font-size:1px;line-height:1px;color:{BG};">[[preheader]]&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;</div>
<table role="presentation" class="cl-bg" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="{BG}" style="width:100%;background-color:{BG};border-collapse:collapse;">
<tr><td class="cl-outer" align="center" style="padding:32px 24px;">
<table role="presentation" class="cl-card" width="600" cellspacing="0" cellpadding="0" border="0" bgcolor="{SURFACE}" style="width:100%;max-width:600px;background-color:{SURFACE};border:1px solid {LINE};border-collapse:separate;border-spacing:0;">
<tr><td style="padding:24px 24px 0;">
  <img class="cl-hero" src="{HERO}" width="552" alt="Clepso" style="display:block;width:100%;max-width:552px;height:auto;border:0;color:{ACCENT};font-family:'Courier New',monospace;font-size:24px;line-height:32px;">
</td></tr>
<tr><td class="cl-pad" style="padding:32px 40px;">
  <h1 class="cl-title" style="margin:0 0 24px;font-family:{MONO};font-size:40px;line-height:50px;font-weight:400;letter-spacing:0;color:{TEXT};">[[title]]</h1>
[[body]]
[[button]]
[[facts]]
[[fallback]]
  <p class="cl-muted" style="margin:32px 0 0;font-family:{SANS};font-size:13px;line-height:21px;color:{TEXT2};">[[ignore]]</p>
</td></tr>
<tr><td class="cl-pad" style="padding:24px 40px 28px;border-top:1px solid {LINE};">
  <p style="margin:0 0 14px;font-family:{SANS};font-size:13px;line-height:21px;color:{TEXT};">Your limits. A clearer signal.</p>
  <p style="margin:0;font-family:{SANS};font-size:12px;line-height:20px;color:{TEXT2};"><a href="{SITE}/" style="color:inherit;text-decoration:underline;">Clepso</a> &nbsp;/&nbsp; <a href="{SITE}/privacy/" style="color:inherit;text-decoration:underline;">Privacy</a></p>
</td></tr>
</table></td></tr></table>
</body>
</html>
"""


def para(text, first):
    top = "0" if first else "14px"
    return (f'  <p class="cl-text" style="margin:{top} 0 0 0;font-family:{SANS};font-size:16px;line-height:26px;'
            f'color:{TEXT2};">{text}</p>')


def button(label, href):
    return f"""  <table role="presentation" class="cl-button-table" cellspacing="0" cellpadding="0" border="0" style="margin:28px 0 0;border-collapse:separate;"><tr>
    <td class="cl-button" align="center" bgcolor="{ACCENT}" style="background-color:{ACCENT};border:1px solid {ACCENT};border-radius:2px;mso-padding-alt:15px 24px;">
      <a href="{href}" target="_blank" style="display:inline-block;padding:16px 24px;font-family:{SANS};font-size:15px;line-height:22px;font-weight:600;color:{INK};text-decoration:none;">{html.escape(label)}</a>
    </td></tr></table>"""


def facts(rows):
    if not rows:
        return ""
    device = any(label == "Open on" for label, _ in rows)
    note = f"Valid for {EXPIRES}. One use only."
    if device:
        note += "<br>Open on the Mac or browser that requested it."
    return (f'  <p class="cl-muted" style="margin:16px 0 0;font-family:{SANS};font-size:13px;line-height:21px;color:{TEXT2};">{note}</p>')


def fallback(where):
    return (f'  <p class="cl-muted" style="margin:18px 0 0;font-family:{SANS};font-size:13px;line-height:21px;color:{TEXT2};">'
            f'Button not working? <a class="cl-link" href="{LINK}" target="_blank" style="color:{ACCENT};text-decoration:underline;">Open the link directly</a>.</p>')


def render(e):
    out = (HEAD + BODY)
    parts = {
        "subject": html.escape(e["subject"]),
        "preheader": e["preheader"],
        "tag": html.escape(e["tag"]),
        "title": html.escape(e["title"].upper()),
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
    # Exactly one optional display font is allowed; all content must have a local fallback.
    if text.count(FONT_FACE) != 1 or re.search(r"<script|@import|<link\b|@font-face", text.replace(FONT_FACE, ""), re.I):
        errs.append(f"{name}: scripts, external CSS or an unexpected web font")
    if 'Courier New' not in text or 'alt="Clepso"' not in text:
        errs.append(f"{name}: missing font/image fallback")
    if f'src="{HERO}"' not in text:
        errs.append(f"{name}: unexpected hero image")
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
    asset = repo / "design/email" / HERO_FILE
    if not asset.exists() or len(asset.read_bytes()) > 500_000:
        errs.append("Protocol hero missing or larger than the 500 KB asset budget")
    elif asset.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", asset.read_bytes()[16:24]) != (1200, 474):
        errs.append("Protocol hero dimensions must be 1200 x 474")
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
            (preview / "assets").mkdir(exist_ok=True)
            shutil.copyfile(repo / "design/email" / HERO_FILE, preview / "assets" / HERO_FILE)
            shutil.copyfile(repo / "design/brand/fonts/ClepsoPixel-Regular.woff2", preview / "assets/ClepsoPixel-Regular.woff2")
            sample = (text.replace(LINK, "http://127.0.0.1:54321/auth/v1/verify?token=pkce_3f9c1d8e7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f&amp;type=magiclink&amp;redirect_to=http://127.0.0.1:3000/app")
                      .replace(ME, "ada@example.com").replace(NEW, "ada.lovelace@example.org")
                      .replace(HERO, "assets/" + HERO_FILE)
                      .replace(FONT, "assets/ClepsoPixel-Regular.woff2"))
            (preview / f"{name}.html").write_text(sample)
        print(f"{name}: {len(text.encode())} bytes, subject \"{e['subject']}\"")
    for m in errs:
        print("ERROR", m)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
