# Clepso site on Cloudflare

Vercel blocked the owner's team for an unpaid invoice on 19 Nov 2026, so clepso-app.vercel.app answers 402. The site in `site/` is static files only, so it now runs on Cloudflare Workers static assets on the free plan (every request a static file: free and unlimited), at https://clepso.ledger-trigger.workers.dev.

- `site/wrangler.jsonc`: Worker `clepso`, assets from this folder, `force-trailing-slash` (vercel.json had `trailingSlash: true`), the site's own `404.html` for missing paths, no per-upload preview addresses.
- `site/_headers`: the one header vercel.json set (the email font may load cross-origin).
- `site/.assetsignore`: deploy and repo files are never served.
- Deploy: `cd site && npx wrangler deploy`. Going back: `vercel.json` and `.vercelignore` are kept.

Differences from Vercel: trailing-slash redirects are 307 (Vercel 308); the address.
